import XCTest
@testable import BirdingCore

final class EdgePeekSchedulingTests:XCTestCase {
    private let screen=CGRect(x:0,y:0,width:1600,height:1200)
    private let host=Surface(id:61,pid:42,rect:CGRect(x:100,y:900,width:800,height:200))
    private func fixture(fraction:CGFloat=0.1,species:SpeciesID = .treeSparrow,
                         normalizedDistance:CGFloat?=nil,missing:String?=nil) -> BehaviorEngine {
        var settings=BirdSettings()
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        settings.ambientLeafPlayEnabled=false;settings.passiveAttentionEnabled=false;settings.sideHopEnabled=false
        let e=BehaviorEngine(seed:81,settings:settings)
        e.populationEnabled=false;e.autonomousRouting=false;e.ambientEnabled=true
        var frames:Set<String>=["stand","blink","preen0","preen1","idle0","idle1","idle2","land0","land1","land2"]
        if [.lightVentedBulbul,.magpieRobin].contains(species) {frames.formUnion(["peekLower","peekLook","peekRecover"])}
        if let missing {frames.remove(missing)}
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:1500,y:100),availableFrames:[species:frames]))
        let bird=Bird(position:.zero,fraction:fraction,profile:settings.catalog.profile(species),random:{0.5})
        if let normalizedDistance {
            bird.fraction=normalizedDistance*e.spriteScale(for:bird)/(Geometry.perchX(1,rect:host.rect)-Geometry.perchX(0,rect:host.rect))
        }
        bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
        e.installFixtureBirds([bird]);return e
    }
    private func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int(seconds*Double(hz)) {e.advance(1/Double(hz))}
    }
    func testAutomaticEdgePeekUsesExistingBirdAndReturnsWithoutPopulationChange() throws {
        let e=fixture(),bird=try XCTUnwrap(e.birds.first),origin=bird.position
        advance(e,120)
        let starts=e.events.filter{$0.kind == .edgePeek && $0.type == .started}
        XCTAssertFalse(starts.isEmpty,"Natural calm time should eventually offer an edge peek")
        XCTAssertLessThanOrEqual(starts.count,3,"Cooldown prevents frequent repetition")
        XCTAssertTrue(starts.allSatisfy{$0.source == .automatic && $0.participants==[e.id(of:bird)!]})
        XCTAssertTrue(e.events.contains{$0.kind == .edgePeek && $0.type == .completed})
        XCTAssertEqual(e.birds.count,1);XCTAssertTrue(e.birds.first === bird)
        // Stop new opportunities and drain a possible final return.
        e.ambientEnabled=false;advance(e,8)
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.fraction,0.1,accuracy:1e-9)
        XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
    }
    func testIneligibleMiddleOfWindowConsumesOpportunityWithoutRejectedEventSpam() throws {
        let e=fixture(fraction:0.5),bird=try XCTUnwrap(e.birds.first)
        advance(e,90)
        XCTAssertFalse(e.events.contains{$0.kind == .edgePeek})
        XCTAssertEqual(bird.fraction,0.5)
        XCTAssertEqual(e.reservedLandingCount,0)
        let rhythm=try XCTUnwrap(e.perchPlanner.rhythms[e.id(of:bird)!])
        XCTAssertLessThan(rhythm.peekQuiet,rhythm.nextPeek)
    }

    func testNewPeekSpeciesNaturallyCompleteOnlyWithAllDedicatedFramesWithoutRejectedEventSpam() throws {
        let losses:[String?]=[nil,"peekLower","peekLook","peekRecover"]
        for species:SpeciesID in [.lightVentedBulbul,.magpieRobin] {
            for missing in losses {
                let e=fixture(species:species,normalizedDistance:95,missing:missing),bird=e.birds[0]
                let origin=bird.position,identity=ObjectIdentifier(bird),id=try XCTUnwrap(e.id(of:bird))
                advance(e,120);e.ambientEnabled=false;advance(e,8)
                let starts=e.events.filter{$0.kind == .edgePeek && $0.type == .started}
                let completions=e.events.filter{$0.kind == .edgePeek && $0.type == .completed}
                if missing == nil {
                    XCTAssertFalse(starts.isEmpty,species.rawValue)
                    XCTAssertLessThanOrEqual(starts.count,3)
                    XCTAssertEqual(completions.count,starts.count)
                    XCTAssertTrue(starts.allSatisfy{$0.source == .automatic && $0.participants == [id]})
                } else {XCTAssertTrue(starts.isEmpty);XCTAssertTrue(completions.isEmpty)}
                XCTAssertFalse(e.events.contains{$0.kind == .edgePeek && $0.type == .rejected})
                XCTAssertEqual(e.birds.map(ObjectIdentifier.init),[identity]);XCTAssertEqual(bird.position,origin)
                XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0)
                XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            }
        }
    }
    func testDisabledMasterAndChildNeverQueueAndPauseFreezesOpportunityClock() throws {
        for masterOff in [true,false] {
            let e=fixture(),bird=try XCTUnwrap(e.birds.first)
            var settings=e.settings
            if masterOff {settings.perchActions=false} else {settings.edgePeekEnabled=false}
            e.applySettings(settings);advance(e,90)
            XCTAssertFalse(e.events.contains{$0.kind == .edgePeek})
            let rhythm=try XCTUnwrap(e.perchPlanner.rhythms[e.id(of:bird)!])
            XCTAssertEqual(rhythm.peekQuiet,0)
            settings.perchActions=true;settings.edgePeekEnabled=true;e.applySettings(settings)
            advance(e,1);XCTAssertFalse(e.events.contains{$0.kind == .edgePeek})
            e.handle(.pause(true));let before=rhythm.peekQuiet;advance(e,60)
            XCTAssertEqual(rhythm.peekQuiet,before)
            e.handle(.pause(false));advance(e,1)
            XCTAssertLessThanOrEqual(rhythm.peekQuiet,before+1.001)
        }
    }
    func testPointerProximityDiscardsCalmProgressInsteadOfTriggeringOnExit() throws {
        let e=fixture(),bird=try XCTUnwrap(e.birds.first)
        advance(e,5)
        let rhythm=try XCTUnwrap(e.perchPlanner.rhythms[e.id(of:bird)!])
        XCTAssertGreaterThan(rhythm.peekQuiet,0)
        var world=e.world;world.pointer=bird.position;e.updateWorld(world);advance(e,2)
        XCTAssertEqual(rhythm.peekQuiet,0)
        world.pointer=CGPoint(x:1500,y:100);e.updateWorld(world);advance(e,1)
        XCTAssertFalse(e.events.contains{$0.kind == .edgePeek})
    }
    func testAutonomousOpportunityAndEventsMatchAtDifferentCallbackRates() {
        let runs=[30,60,120].map {hz -> BehaviorReplayReport in
            let e=fixture();advance(e,75,hz:hz);e.ambientEnabled=false;advance(e,8,hz:hz)
            return BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
        }
        XCTAssertEqual(runs[0],runs[1]);XCTAssertEqual(runs[1],runs[2])
        XCTAssertTrue(runs[0].events.contains{$0.kind=="edgePeek" && $0.type=="completed"})
    }
    func testMultiplePeeksReserveTwoPlacesPerBirdWithinAuditedBudget() throws {
        let e=fixture();e.installFixtureBirds([])
        let display=CGRect(x:0,y:0,width:1600,height:2400)
        // Leave room for the whole bird and hop arc above each window; a
        // preceding foreground window must not occlude the next landing.
        let hosts=(0..<8).map{Surface(id:UInt32(100+$0),pid:42,rect:CGRect(x:100,y:300+$0*230,width:800,height:80))}
        var world=e.world;world.screens=[display];world.displays=[display];world.surfaces=hosts;e.updateWorld(world)
        let birds=hosts.map {host -> Bird in
            let bird=Bird(position:.zero,fraction:0.1,profile:e.settings.catalog.profile(.treeSparrow),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600;bird.tick(0.5);return bird
        }
        e.installFixtureBirds(birds)
        let auditor=BehaviorStress.Auditor();e.eventObserver=auditor.observe
        for bird in birds {XCTAssertTrue(e.requestEdgePeek(source:.preview,target:e.id(of:bird)).accepted)}
        XCTAssertEqual(e.activeRunCount,8);XCTAssertEqual(e.reservedLandingCount,16)
        auditor.sample(e,birds:e.renderSnapshot(),props:e.propSnapshot(),birdLimit:8)
        XCTAssertEqual(auditor.report.checks["boundedResources"],true)
        XCTAssertEqual(auditor.report.checks["reservations"],true)
        e.ambientEnabled=false;advance(e,8)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
    }

}
