import XCTest
@testable import BirdingCore

final class PerchSpanReservationTests:XCTestCase {
    private let host=Surface(id:21,pid:42,rect:CGRect(x:100,y:500,width:1000,height:200))
    private func fixture() -> (BehaviorEngine,[BirdID]) {
        let e=BehaviorEngine(seed:53)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let screen=CGRect(x:0,y:0,width:1400,height:1000)
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:1300,y:50)))
        for fraction:CGFloat in [0.2,0.8,0.95] {
            let bird=Bird(position:.zero,fraction:fraction,profile:e.settings.catalog.profile(.barnSwallow),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
            _=e.register(bird)
        }
        return (e,e.birds.compactMap{e.id(of:$0)})
    }
    private final class ReservationOnly:BehaviorExecution {
        let kind:BehaviorKind = .sideHop
        let participants:[BirdID]
        let landingReservations:[LandingReservation]
        let timeout=10.0
        init(_ ids:[BirdID],_ slots:[LandingReservation]) {participants=ids;landingReservations=slots}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }
    func testSpanRejectsCrossingSlotsAndNormalRoutesWithoutWeakeningOtherReservations() throws {
        let (e,ids)=fixture()
        let span=LandingReservation(bird:ids[0],host:host,fraction:0.2,span:0.2...0.6,headroom:16)
        XCTAssertTrue(e.runtime.start(ReservationOnly([ids[0]],[span]),source:.preview,in:e).accepted)
        let middle=LandingReservation(bird:ids[1],host:host,fraction:0.4)
        XCTAssertEqual(e.runtime.start(ReservationOnly([ids[1]],[middle]),source:.preview,in:e),.rejected(.noSpace))
        XCTAssertEqual(e.leasedBirdCount,1)
        let route=try XCTUnwrap(e.plan(for:e.birds[2]))
        let candidate=Geometry.landingFootprint(at:route.point,scale:e.spriteScale(for:e.birds[2]))
        XCTAssertTrue(candidate.intersection(try XCTUnwrap(span.footprint(in:e))).isNull)
        let outside=LandingReservation(bird:ids[1],host:host,fraction:0.8)
        XCTAssertTrue(e.runtime.start(ReservationOnly([ids[1]],[outside]),source:.preview,in:e).accepted)
        XCTAssertEqual(e.reservedLandingCount,2)
    }
    func testBlockerInsideSpanInvalidatesTheWholeRunEvenWhenEndpointsRemainVisible() {
        let (e,ids)=fixture()
        let span=LandingReservation(bird:ids[0],host:host,fraction:0.2,span:0.2...0.6,headroom:16)
        XCTAssertTrue(e.runtime.start(ReservationOnly([ids[0]],[span]),source:.preview,in:e).accepted)
        var world=e.world
        let center=Geometry.perchX(0.4,rect:host.rect)
        world.surfaces.insert(Surface(id:99,pid:43,rect:CGRect(x:center-5,y:480,width:10,height:30),layer:1),at:0)
        e.updateWorld(world)
        XCTAssertFalse(span.isValid(in:e))
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        XCTAssertEqual(e.events.last?.reason,.targetInvalid)
        e.updateWorld(world)
        XCTAssertEqual(e.events.filter{$0.type == .failed}.count,1)
    }
    func testHeadroomIsProtectedAndInvalidSpansCannotAcquireLeases() throws {
        let (e,ids)=fixture()
        let plain=LandingReservation(bird:ids[0],host:host,fraction:0.2)
        let span=LandingReservation(bird:ids[0],host:host,fraction:0.2,span:0.2...0.6,headroom:16)
        let a=try XCTUnwrap(plain.footprint(in:e)),b=try XCTUnwrap(span.footprint(in:e))
        XCTAssertEqual(b.minY,a.minY-16,accuracy:0.001)
        XCTAssertGreaterThan(b.maxX,a.maxX+300)
        for invalid in [
            LandingReservation(bird:ids[0],host:host,fraction:0.2,span:0.3...0.6),
            LandingReservation(bird:ids[0],host:host,fraction:0.2,span:(-0.1)...0.6),
            LandingReservation(bird:ids[0],host:host,fraction:0.2,span:0.2...1.1),
            LandingReservation(bird:ids[0],host:host,fraction:0.2,headroom:.infinity),
            LandingReservation(bird:ids[0],host:host,fraction:0.2,headroom:-1)
        ] {
            XCTAssertFalse(invalid.isValid(in:e))
            XCTAssertEqual(e.runtime.start(ReservationOnly([ids[0]],[invalid]),source:.preview,in:e),.rejected(.noSpace))
        }
        XCTAssertEqual(e.leasedBirdCount,0)
    }
}
