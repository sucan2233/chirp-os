import XCTest
@testable import BirdingCore

final class InsectCatchSchedulingTests:XCTestCase {
    private func insectOpportunitySeed()throws->UInt64 {
        // Select a real scheduler outcome, rather than reproducing its RNG or
        // relying on the old selector's draw to control the new 8% interval.
        for seed:UInt64 in 0..<64 {
            var scheduler=AmbientScheduler(seed:seed);scheduler.reset(.high)
            for _ in 0..<45*60+2 {
                let before=scheduler.remaining
                let event=scheduler.tick(BehaviorEngine.step,pointer:CGPoint(x:20,y:20),buttonsDown:false,
                    pointerEnabled:true,flockEnabled:true,insectEnabled:true,frequency:.high,busy:false,random:{0})
                if scheduler.remaining>before {
                    if event == .insectCatch {return seed}
                    break
                }
            }
        }
        XCTFail("The fixed seed range must contain an actual insect opportunity")
        throw NSError(domain:"InsectCatchSchedulingTests",code:1)
    }

    func testDefaultOffAndCoolingInsectIntervalsKeepTheSameOpportunityAndLegacyRandomStream() throws {
        let seed=try insectOpportunitySeed()
        var referenceRemaining:Double?,referenceDraws:Int?
        for condition in ["enabled","defaultOff","cooling"] {
            var scheduler=AmbientScheduler(seed:seed);scheduler.reset(.high)
            if condition == "cooling" {scheduler.didFinishInsectCatch();XCTAssertFalse(scheduler.canAttemptInsectCatch)}
            var draws=0,outcome:AmbientEvent?
            for _ in 0..<45*60+2 {
                let before=scheduler.remaining
                let random:()->Double={draws+=1;return 0}
                // Omit the new argument deliberately for the compatibility path.
                let event:AmbientEvent?
                if condition == "defaultOff" {
                    event=scheduler.tick(BehaviorEngine.step,pointer:.zero,buttonsDown:false,
                        pointerEnabled:true,flockEnabled:true,socialEnabled:true,leafEnabled:true,
                        frequency:.high,busy:false,random:random)
                } else {
                    event=scheduler.tick(BehaviorEngine.step,pointer:.zero,buttonsDown:false,
                        pointerEnabled:true,flockEnabled:true,socialEnabled:true,leafEnabled:true,
                        insectEnabled:true,frequency:.high,busy:false,random:random)
                }
                if scheduler.remaining>before {outcome=event;break}
            }
            if condition == "enabled" {
                XCTAssertEqual(outcome,.insectCatch);referenceRemaining=scheduler.remaining;referenceDraws=draws
            } else {
                XCTAssertNil(outcome,"A closed insect interval cannot transfer to any enabled legacy action")
                XCTAssertEqual(scheduler.remaining,referenceRemaining);XCTAssertEqual(draws,referenceDraws)
            }
            if condition == "cooling" {
                XCTAssertEqual(scheduler.insectCooldownRemaining,45,accuracy:BehaviorEngine.step+1e-9)
                XCTAssertFalse(scheduler.canAttemptInsectCatch)
            }
        }
    }

    func testAutomaticIneligibleInsectIntervalIsSilentAndDoesNotTransferToEnabledLegacyActions() throws {
        let seed=try insectOpportunitySeed()
        let display=CGRect(x:0,y:0,width:2400,height:1500)
        let host=Surface(id:1801,pid:42,rect:CGRect(x:200,y:1100,width:2000,height:180))
        for condition in ["noResidents","otherSpecies","perchedSwallow","disabled","missingArt","missingFrames","zeroProbability"] {
          for hz in [30,60,120] {
            var settings=BirdSettings();settings.ambientFrequency = .high
            settings.perchActions=false;settings.passiveAttentionEnabled=false
            settings.pointerVisits=true;settings.flockPasses=true;settings.socialInteractions=true
            settings.ambientLeafPlayEnabled=false;settings.insectCatchEnabled = condition != "disabled"
            if condition == "zeroProbability",let index=settings.probabilities.entries.firstIndex(where:{$0.id == .barnSwallow}) {
                settings.probabilities.setManualWeight(at:index,to:0)
            }
            let e=BehaviorEngine(seed:seed,settings:settings)
            e.populationEnabled=false;e.ambientEnabled=true;e.autonomousRouting=false
            var world=BehaviorWorld(screens:[display],displays:[display],surfaces:[host],pointer:CGPoint(x:20,y:20))
            world.insectArtAvailable = condition != "missingArt"
            // Complete content keeps the perched/no-candidate check independent
            // from the separate missing-frame guard.
            world.availableFrames[.barnSwallow]=SpeciesBehaviorProfile.profile(for:.barnSwallow).requiredFrames(for:.insectCatch)
            if condition == "missingFrames" {world.availableFrames[.barnSwallow]?.remove("catchOpen")}
            e.updateWorld(world)
            if condition != "noResidents" {
                let species:SpeciesID=condition == "otherSpecies" ? .treeSparrow:.barnSwallow
                let bird=Bird(position:.zero,fraction:0.5,profile:settings.catalog.profile(species),random:{0.5})
                bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
                e.installFixtureBirds([bird])
            }
            let residents=e.residentCount,identities=e.birds.map(ObjectIdentifier.init)
            XCTAssertEqual(e.scheduler.remaining,45)
            for _ in 0..<45*hz+2 {e.advance(1/Double(hz))}
            XCTAssertTrue(e.events.isEmpty,"\(condition): ineligible automatic opportunities are discarded without rejection or substitution")
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertTrue(e.propSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
            XCTAssertEqual(e.residentCount,residents);XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
            XCTAssertEqual(e.pendingCount,0);XCTAssertEqual(e.passingCount,0);XCTAssertEqual(e.arrivalCount,0)
            XCTAssertGreaterThan(e.scheduler.remaining,0,"The opportunity is spent, with no immediate retry")
            XCTAssertNil(e.insectSnapshot());XCTAssertFalse(e.hasInsectCatchPreview)
            // The explicit command must still explain the same ineligibility.
            let reason:BehaviorReason
            switch condition {
            case "disabled":reason = .disabled
            case "missingArt","missingFrames":reason = .missingFrames
            case "perchedSwallow":reason = .unavailableBird
            default:reason = .noSpecies
            }
            XCTAssertEqual(e.handle(.insectCatch(species:.barnSwallow,source:.user)),.rejected(reason))
            XCTAssertEqual(e.events.filter{$0.type == .rejected}.map(\.reason),[reason])
          }
        }
    }

    func testActualEightPercentOpportunityStartsAndCompletesOnAnOrdinaryResidentAcrossRatesAndLegacyDraws() throws {
        typealias F=InsectCatchTestSupport
        let seed=try insectOpportunitySeed()
        var referenceContact:RecordedInsectContact?,referenceEvents:[RecordedEvent]?
        for hz in [30,60,120] {
            for unrelatedDraws in [0,29] {
                var settings=F.settings();settings.ambientFrequency = .high
                let e=BehaviorEngine(seed:seed,settings:settings)
                e.populationEnabled=false;e.ambientEnabled=true;e.autonomousRouting=false
                e.updateWorld(.init(screens:[F.display],displays:[F.display],surfaces:[F.host()],
                    pointer:CGPoint(x:20,y:20),availableFrames:[.barnSwallow:F.frames]))
                F.advance(e,44,hz:hz)
                // Fixture setup establishes an ordinary flight before the real
                // opportunity. No manual catch or scheduler reset starts it.
                e.installFixtureBirds([try F.fixtureBird().make(in:e)])
                for _ in 0..<unrelatedDraws {_=e.random.unit();_=e.ecologyRandom.unit()}
                var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
                F.advance(e,10,hz:hz)
                let started=try XCTUnwrap(e.events.first{$0.kind == .insectCatch && $0.type == .started})
                let run=try XCTUnwrap(started.runID)
                XCTAssertEqual(started.source,.automatic);XCTAssertGreaterThanOrEqual(started.time,45)
                XCTAssertEqual(started.participants,[BirdID(1)])
                F.released(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
                let contact=RecordedInsectContact(try XCTUnwrap(e.lastInsectContact))
                let events=e.events.map(RecordedEvent.init)
                if let referenceContact,let referenceEvents {
                    XCTAssertEqual(contact,referenceContact);XCTAssertEqual(events,referenceEvents)
                } else {referenceContact=contact;referenceEvents=events}
                XCTAssertEqual(observations.count,1);XCTAssertEqual(observations.first?.source,.automatic)
                XCTAssertGreaterThan(e.scheduler.insectCooldownRemaining,0)
                XCTAssertFalse(e.scheduler.canAttemptInsectCatch)
                let bird=try XCTUnwrap(e.birds.first)
                XCTAssertGreaterThan(e.ecology(of:bird)?.cooldowns[.insectCatch] ?? 0,0)
                XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
                XCTAssertFalse(e.hasInsectCatchPreview);XCTAssertNil(e.sceneFocus)
                XCTAssertFalse(e.events.contains{$0.type == .failed || $0.type == .rejected})
            }
        }
    }
}
