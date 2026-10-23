import XCTest
@testable import BirdingCore

final class LandingReservationTests:XCTestCase {
    private let host=Surface(id:88,pid:12,rect:CGRect(x:-600,y:600,width:1200,height:200))
    private func fixture() -> BehaviorEngine {
        let e=BehaviorEngine(seed:44);e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let screen=CGRect(x:-800,y:-200,width:1600,height:1200)
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host]))
        e.installFixtureBirds([0.15,0.85].map {fraction in
            let bird=Bird(position:.zero,fraction:fraction,random:{0.5})
            bird.perch(on:host);bird.perchDuration=600;return bird
        })
        return e
    }
    private final class ReservationExecution:BehaviorExecution {
        let kind:BehaviorKind = .relocate
        let occupiesEncounter=false,runsWhilePaused=false,timeout=1.0
        let landingReservations:[LandingReservation]
        var participants:[BirdID] {landingReservations.map(\.bird)}
        init(_ slots:[LandingReservation]) {landingReservations=slots}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }
    func testReservationsAreAtomicAndReleaseWithOwner() throws {
        let e=fixture(),a=e.id(of:e.birds[0])!,b=e.id(of:e.birds[1])!
        let first=ReservationExecution([LandingReservation(bird:a,host:host,fraction:0.5)])
        guard case .started(let run)=e.runtime.start(first,source:.preview,in:e) else {return XCTFail("start")}
        XCTAssertEqual(e.reservedLandingCount,1)
        XCTAssertEqual(e.runtime.start(ReservationExecution([LandingReservation(bird:b,host:host,fraction:0.51)]),source:.preview,in:e),.rejected(.noSpace))
        XCTAssertEqual(e.leasedBirdCount,1)
        e.runtime.cancel(run,reason:.removed,in:e)
        XCTAssertEqual(e.reservedLandingCount,0)
        XCTAssertTrue(e.runtime.start(ReservationExecution([LandingReservation(bird:b,host:host,fraction:0.5)]),source:.preview,in:e).accepted)
        for _ in 0..<70 {e.advance(BehaviorEngine.step)}
        XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
    }
    func testInternalConflictsAndForeignOwnershipRejectWithoutLeaking() {
        let e=fixture(),a=e.id(of:e.birds[0])!,b=e.id(of:e.birds[1])!
        let slots=[LandingReservation(bird:a,host:host,fraction:0.5),LandingReservation(bird:b,host:host,fraction:0.51)]
        XCTAssertEqual(e.runtime.start(ReservationExecution(slots),source:.preview,in:e),.rejected(.noSpace))
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
    }
    func testReservationFollowsHostAndRejectsIdentityReuseAndOcclusion() throws {
        let e=fixture(),a=e.id(of:e.birds[0])!,slot=LandingReservation(bird:e.id(of:e.birds[0])!,host:host,fraction:0.5)
        let old=try XCTUnwrap(slot.point(in:e));var w=e.world
        w.surfaces[0].rect.origin.x+=30;e.updateWorld(w)
        XCTAssertEqual(try XCTUnwrap(slot.point(in:e)).x,old.x+30)
        XCTAssertTrue(slot.isValid(in:e))
        w.surfaces.insert(Surface(id:89,rect:CGRect(x:old.x,y:old.y-40,width:100,height:60)),at:0);e.updateWorld(w)
        XCTAssertFalse(slot.isValid(in:e))
        w.surfaces=[Surface(id:host.id,pid:99,rect:host.rect)];e.updateWorld(w)
        XCTAssertNil(slot.point(in:e))
        XCTAssertEqual(e.runtime.start(ReservationExecution([LandingReservation(bird:a,host:host,fraction:0.5)]),source:.preview,in:e),.rejected(.noSpace))
    }
    func testNormalDestinationPlanningRespectsPendingReservation() throws {
        let e=fixture(),a=e.id(of:e.birds[0])!,other=e.birds[1]
        let slot=LandingReservation(bird:a,host:host,fraction:0.5)
        XCTAssertTrue(e.runtime.start(ReservationExecution([slot]),source:.preview,in:e).accepted)
        let blocked=try XCTUnwrap(slot.footprint(in:e))
        for _ in 0..<100 {
            let plan=try XCTUnwrap(e.plan(for:other))
            XCTAssertNotNil(plan.host)
            let footprint=Geometry.landingFootprint(at:plan.point,scale:e.spriteScale(for:other))
            XCTAssertTrue(footprint.intersection(blocked).isEmpty)
        }
    }
    func testInvalidReservationEndsEvenWhilePaused() {
        let e=fixture(),a=e.id(of:e.birds[0])!
        XCTAssertTrue(e.runtime.start(ReservationExecution([LandingReservation(bird:a,host:host,fraction:0.5)]),source:.preview,in:e).accepted)
        e.handle(.pause(true));var world=e.world;world.surfaces=[];e.updateWorld(world)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
        XCTAssertEqual(e.events.last?.reason,.targetInvalid);XCTAssertEqual(e.events.last?.type,.failed)
    }
    func testShrinkingHostReleasesConflictingReservations() {
        let e=fixture(),a=e.id(of:e.birds[0])!,b=e.id(of:e.birds[1])!
        let slots=[LandingReservation(bird:a,host:host,fraction:0.3),LandingReservation(bird:b,host:host,fraction:0.7)]
        XCTAssertTrue(e.runtime.start(ReservationExecution(slots),source:.preview,in:e).accepted)
        e.handle(.pause(true));var world=e.world;world.surfaces[0].rect.size.width=180;e.updateWorld(world)
        XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
        XCTAssertEqual(e.events.last?.reason,.targetInvalid)
    }
}
