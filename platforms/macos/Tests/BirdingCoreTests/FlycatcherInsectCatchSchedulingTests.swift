import XCTest
@testable import BirdingCore

final class FlycatcherInsectCatchSchedulingTests:XCTestCase {
    private typealias F=FlycatcherInsectCatchTestSupport
    private typealias Common=InsectCatchTestSupport

    private func opportunitySeed()throws->UInt64 {
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
        XCTFail("A real scheduler seed must exercise the shared 8% opportunity")
        throw NSError(domain:"FlycatcherInsectCatchSchedulingTests",code:1)
    }

    private func automaticEngine(_ seed:UInt64)throws->BehaviorEngine {
        let e=try F.engine(seed:seed)
        var s=e.settings;s.ambientFrequency = .high
        s.pointerVisits=true;s.flockPasses=true;s.socialInteractions=true
        e.applySettings(s);e.ambientEnabled=true
        XCTAssertEqual(e.scheduler.remaining,45)
        return e
    }

    func testSameEightPercentOpportunityStartsThePerchedFlycatcherWithNoExtraClockAcrossRatesAndRandomStreams() throws {
        let seed=try opportunitySeed()
        var referenceByDraws:[Int:[BehaviorReplayReport]]=[:]
        for hz in [30,60,120] {
          for draws in [0,29] {
            let e=try automaticEngine(seed),bird=try XCTUnwrap(e.birds.first),foot=bird.position
            for _ in 0..<draws {_=e.random.unit();_=e.ecologyRandom.unit()}
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            F.advance(e,44,hz:hz)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertNil(e.insectSnapshot())
            var reports:[BehaviorReplayReport]=[]
            for _ in 0..<110 {
                F.advance(e,0.1,hz:hz)
                reports.append(BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init)))
            }
            let started=try XCTUnwrap(e.events.first{$0.kind == .insectCatch && $0.type == .started})
            let run=try XCTUnwrap(started.runID)
            XCTAssertEqual(started.source,.automatic);XCTAssertEqual(started.participants,[BirdID(1)])
            F.released(e,run);XCTAssertEqual(Common.terminals(e,run).map(\.type),[.completed])
            XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,foot)
            XCTAssertEqual(observations.count,1);XCTAssertEqual(observations.first?.source,.automatic)
            XCTAssertGreaterThan(e.scheduler.insectCooldownRemaining,0);XCTAssertFalse(e.scheduler.canAttemptInsectCatch)
            XCTAssertGreaterThan(e.ecology(of:bird)?.cooldowns[.insectCatch] ?? 0,0)
            XCTAssertFalse(e.events.contains{$0.type == .failed || $0.type == .rejected})
            XCTAssertEqual(e.events.filter{$0.type == .started}.count,1)
            if let reference=referenceByDraws[draws] {
                // Identical external draws retain the entire report at every Hz.
                XCTAssertEqual(reports,reference,"draws=\(draws), Hz=\(hz)")
            } else {referenceByDraws[draws]=reports}
          }
        }
        // The next daily interval deliberately consumes the legacy random
        // stream. Only that field differs after unrelated draws; keep every
        // other report field, including idle poses, under strict comparison.
        func excludingLegacyInterval(_ reports:[BehaviorReplayReport])->[BehaviorReplayReport] {
            reports.map {report in
                var value=report;value.schedulerRemaining=nil;return value
            }
        }
        let zeroDraws=try XCTUnwrap(referenceByDraws[0])
        let extraDraws=try XCTUnwrap(referenceByDraws[29])
        XCTAssertEqual(excludingLegacyInterval(extraDraws),excludingLegacyInterval(zeroDraws))
    }

    func testBothSpeciesEligibleShareOneOpportunityOneRunAndOneInsectWithoutPrescribingTheWinner() throws {
        let seed=try opportunitySeed()
        for hz in [30,60,120] {
            let e=try automaticEngine(seed),flycatcher=try XCTUnwrap(e.birds.first)
            F.advance(e,44,hz:hz)
            var world=e.world
            world.surfaces.append(Surface(id:1901,pid:44,rect:CGRect(x:2000,y:1350,width:280,height:180)))
            world.availableFrames[.barnSwallow]=Common.frames;e.updateWorld(world)
            var input=Common.fixtureBird();input.flightOrigin=RecordedPoint(CGPoint(x:220,y:1350))
            let swallow=try input.make(in:e);e.installFixtureBirds([flycatcher,swallow])
            F.advance(e,0.8,hz:hz)
            XCTAssertFalse(FlycatcherInsectCatchPlan.candidates(in:e,species:F.species,source:.automatic).isEmpty)
            XCTAssertFalse(InsectCatchPlan.candidates(in:e,species:.barnSwallow,source:.automatic).isEmpty)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            var sawRun=false,sawInsect=false
            for _ in 0..<100 {
                F.advance(e,0.1,hz:hz)
                XCTAssertLessThanOrEqual(e.activeRunCount,1);XCTAssertLessThanOrEqual(e.leasedBirdCount,1)
                XCTAssertLessThanOrEqual(e.propSnapshot().filter{$0.kind == .insect}.count,1)
                sawRun = sawRun || e.activeRunCount==1;sawInsect = sawInsect || e.insectSnapshot() != nil
            }
            let starts=e.events.filter{$0.kind == .insectCatch && $0.type == .started}
            XCTAssertEqual(starts.count,1);XCTAssertTrue(sawRun);XCTAssertTrue(sawInsect)
            let run=try XCTUnwrap(starts.first?.runID)
            XCTAssertEqual(starts.first?.source,.automatic);XCTAssertEqual(starts.first?.participants.count,1)
            F.released(e,run);XCTAssertEqual(Common.terminals(e,run).map(\.type),[.completed])
            XCTAssertEqual(observations.count,1);XCTAssertEqual(observations.first?.species.count,1)
            XCTAssertEqual(e.residentCount,2);XCTAssertEqual(e.arrivalCount,0);XCTAssertNil(e.insectSnapshot())
            XCTAssertFalse(e.events.contains{$0.type == .rejected || $0.type == .failed})
        }
    }

    func testIneligibleFlycatcherOpportunityStaysEmptyInsteadOfTransferringToLegacyBehaviors() throws {
        let seed=try opportunitySeed()
        for condition in ["speciesDisabled","missingFrames","fixedPerch"] {
            let e=try automaticEngine(seed),bird=try XCTUnwrap(e.birds.first)
            if condition == "speciesDisabled" {
                var s=e.settings;let index=try XCTUnwrap(s.probabilities.entries.firstIndex{$0.id==F.species})
                s.probabilities.setManualWeight(at:index,to:0);e.applySettings(s)
            } else {
                var world=e.world
                if condition == "missingFrames" {world.availableFrames[F.species]?.remove("catchOpen")}
                else {
                    let fixed=Surface(id:2102,pid:42,rect:F.host().rect,isFixedPerch:true)
                    world.surfaces=[fixed];e.updateWorld(world);bird.perch(on:fixed,spriteScale:e.spriteScale(for:bird))
                }
                e.updateWorld(world)
            }
            let identity=ObjectIdentifier(bird)
            F.advance(e,45.1)
            XCTAssertTrue(e.events.isEmpty,condition)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertNil(e.insectSnapshot());XCTAssertFalse(e.hasInsectCatchPreview)
            XCTAssertEqual(e.residentCount,1);XCTAssertEqual(ObjectIdentifier(bird),identity)
            XCTAssertGreaterThan(e.scheduler.remaining,0);XCTAssertNil(e.sceneFocus)
        }
    }
}
