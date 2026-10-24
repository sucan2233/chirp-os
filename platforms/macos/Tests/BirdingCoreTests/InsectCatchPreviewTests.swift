import XCTest
@testable import BirdingCore

final class InsectCatchPreviewTests:XCTestCase {
    private typealias F=InsectCatchTestSupport

    func testTenSecondWaitDoesNotLeaseSpawnOrForceFlightAndPauseFreezesRemaining() throws {
        let e=try F.engine(airborne:false),bird=try XCTUnwrap(e.birds.first)
        let identity=ObjectIdentifier(bird),foot=bird.position,revision=bird.motionRevision
        XCTAssertEqual(e.handle(.insectCatch(species:.barnSwallow,source:.preview)),.scheduled)
        XCTAssertTrue(e.hasInsectCatchPreview);XCTAssertEqual(e.insectPreviewRemaining,10)
        XCTAssertEqual(e.handle(.insectCatch(species:.barnSwallow,source:.preview)),.rejected(.busy))
        F.advance(e,3);e.handle(.pause(true))
        let remaining=try XCTUnwrap(e.insectPreviewRemaining)
        XCTAssertEqual(remaining,7,accuracy:1e-9)
        F.advance(e,20)
        XCTAssertEqual(e.insectPreviewRemaining,remaining);XCTAssertTrue(e.hasInsectCatchPreview)
        XCTAssertEqual(bird.position,foot);XCTAssertEqual(bird.state,.perched)
        XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(ObjectIdentifier(bird),identity)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
        e.handle(.pause(false));F.advance(e,6.9)
        XCTAssertTrue(e.hasInsectCatchPreview);XCTAssertNil(e.insectSnapshot())
        F.advance(e,0.2)
        XCTAssertFalse(e.hasInsectCatchPreview);XCTAssertNil(e.insectPreviewRemaining)
        XCTAssertEqual(e.events.filter{$0.type == .previewResult}.map(\.reason),[.timedOut])
        XCTAssertFalse(e.events.contains{$0.type == .started || $0.type == .completed})
        XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.pendingCount,0)
        XCTAssertEqual(bird.position,foot);XCTAssertEqual(bird.state,.perched)
    }

    func testPendingPreviewLetsTheExistingDepartureClockProduceARealOrdinaryFlight() throws {
        func fixture()throws->BehaviorEngine {
            var settings=F.settings();settings.perchActions=true;settings.takeoffPreparationEnabled=true
            let e=BehaviorEngine(seed:1901,settings:settings)
            e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=true
            // The small initial window is a legal perch. Only the broad left
            // window qualifies as the next ordinary DestinationPlanner host.
            let initial=Surface(id:1901,pid:42,rect:CGRect(x:2000,y:1650,width:100,height:180))
            let next=Surface(id:1902,pid:42,rect:CGRect(x:120,y:1650,width:800,height:180))
            e.updateWorld(.init(screens:[F.display],displays:[F.display],surfaces:[initial,next],
                pointer:CGPoint(x:20,y:20),availableFrames:[.barnSwallow:F.frames]))
            var bird=F.fixtureBird(airborne:false);bird.perchDuration=1
            e.installFixtureBirds([try bird.make(in:e)]);return e
        }
        let e=try fixture(),control=try fixture(),bird=try XCTUnwrap(e.birds.first),foot=bird.position
        XCTAssertEqual(e.handle(.insectCatch(species:.barnSwallow,source:.preview)),.scheduled)
        var departure:Double?,started:BehaviorRunID?,preparation:BehaviorRunID?
        for _ in 0..<10*60 {
            e.advance(BehaviorEngine.step);control.advance(BehaviorEngine.step)
            if e.activeRunCount==0 {
                XCTAssertEqual(bird.position,control.birds[0].position)
                XCTAssertEqual(bird.state,control.birds[0].state)
                XCTAssertNil(e.insectSnapshot());XCTAssertEqual(e.leasedBirdCount,0)
            }
            if bird.state == .flying,departure==nil {departure=e.time}
            if let run=e.runtime.owners[e.id(of:bird)!],let value=e.runtime.runs[run] {
                if value.execution.kind == .takeoffPreparation {
                    if let preparation {XCTAssertEqual(run,preparation)} else {preparation=run}
                    XCTAssertEqual(value.source,.automatic);XCTAssertTrue(e.hasInsectCatchPreview)
                    XCTAssertEqual(e.leasedBirdCount,1);XCTAssertNil(e.insectSnapshot())
                    XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,foot)
                    XCTAssertFalse(e.events.contains{$0.kind == .insectCatch && $0.type == .started})
                } else if value.execution.kind == .insectCatch {started=run;break}
            }
            if e.time<1-1e-9 {XCTAssertEqual(bird.position,foot);XCTAssertEqual(bird.state,.perched)}
        }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(departure),1-1e-9)
        let run=try XCTUnwrap(started),x=try XCTUnwrap(e.runtime.runs[run]?.execution as? InsectCatchExecution)
        let prep=try XCTUnwrap(preparation,"The pending preview must survive an actual automatic preparation lease")
        XCTAssertEqual(F.terminals(e,prep).map(\.type),[.completed])
        XCTAssertFalse(e.events.contains{$0.type == .previewResult && $0.reason != nil})
        XCTAssertLessThan(e.time,10);XCTAssertFalse(e.hasInsectCatchPreview)
        XCTAssertLessThan(Geometry.distance(bird.position,x.plan.route.position(at:try XCTUnwrap(bird.coordinatedFlightAge))),0.01)
        XCTAssertGreaterThan(Geometry.distance(.zero,x.plan.initialFlight.velocity),60)
        XCTAssertNotNil(e.insectSnapshot());XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0)
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        XCTAssertEqual(e.events.filter{$0.type == .previewResult}.count,1)
    }

    func testPendingInvalidationsAreImmediateEvenWhilePausedAndLastResidentRemovalMatters() throws {
        for mutation in ["cancel","click","disabled","art","frame","remove","sleep","clear"] {
            let e=try F.engine(airborne:false),id=try XCTUnwrap(e.id(of:e.birds[0]))
            XCTAssertEqual(e.handle(.insectCatch(species:.barnSwallow,source:.preview)),.scheduled)
            F.advance(e,1);e.handle(.pause(true));XCTAssertTrue(e.hasInsectCatchPreview)
            switch mutation {
            case "cancel":e.handle(.cancelInsectCatchPreview)
            case "click":e.handle(.pointerClick)
            case "disabled":var settings=e.settings;settings.insectCatchEnabled=false;e.applySettings(settings)
            case "art":var world=e.world;world.insectArtAvailable=false;e.updateWorld(world)
            case "frame":var world=e.world;world.availableFrames[.barnSwallow]?.remove("catchRecover");e.updateWorld(world)
            case "remove":e.handle(.remove(id))
            case "sleep":e.handle(.cancelAmbient(.sleep))
            default:e.handle(.clearInsect)
            }
            XCTAssertFalse(e.hasInsectCatchPreview,mutation);XCTAssertNil(e.insectPreviewRemaining,mutation)
            XCTAssertNil(e.insectSnapshot());XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(e.events.filter{$0.type == .previewResult}.count,1,mutation)
            e.handle(.pause(false));F.advance(e,11)
            XCTAssertFalse(e.events.contains{$0.type == .started},mutation)
            XCTAssertEqual(e.events.filter{$0.type == .previewResult}.count,1,mutation)
        }
        let e=try F.engine(airborne:false),host=F.host()
        let other=Bird(position:.zero,fraction:0.1,profile:e.settings.catalog.profile(.barnSwallow),random:{0.5})
        other.perch(on:host,spriteScale:e.spriteScale(for:other));other.perchDuration=600
        let second=e.register(other),first=try XCTUnwrap(e.id(of:e.birds[0]))
        XCTAssertEqual(e.handle(.insectCatch(species:.barnSwallow,source:.preview)),.scheduled)
        e.handle(.pause(true));e.handle(.remove(first))
        XCTAssertTrue(e.hasInsectCatchPreview,"A remaining qualified resident can still take its natural departure")
        e.handle(.remove(second));XCTAssertFalse(e.hasInsectCatchPreview)
        XCTAssertEqual(e.events.filter{$0.type == .previewResult}.count,1)
    }
}
