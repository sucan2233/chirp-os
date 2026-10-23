import XCTest
@testable import BirdingCore

final class CoordinatedFlightTests:XCTestCase {
    private let host=Surface(id:41,pid:23,rect:CGRect(x:100,y:900,width:1200,height:200))
    private func line(_ a:CGPoint,_ b:CGPoint,speed:Double=180,acceleration:Double=0,deceleration:Double=0) -> CoordinatedFlightLeg {
        let path=FlightPath(points:[a,b])
        return CoordinatedFlightLeg(path:path,timing:FlightTiming(distance:path.length,speed:speed,
            acceleration:acceleration,deceleration:deceleration))
    }
    private func fixture() throws -> (Bird,CoordinatedFlightRoute) {
        let bird=Bird(position:.zero,fraction:0.2,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host);bird.perchDuration=600
        let a=bird.position,b=Geometry.foot(on:host,fraction:0.75,edge:.top)
        let p=CGPoint(x:a.x+150,y:a.y),q=CGPoint(x:b.x-150,y:b.y)
        let route=try XCTUnwrap(CoordinatedFlightRoute(legs:[line(a,p,acceleration:0.5),line(p,q),line(q,b,deceleration:0.6)]))
        return (bird,route)
    }
    func testRoutePreservesContinuousPositionAndSpeedAcrossJoins() throws {
        let (_,route)=try fixture()
        var age=0.0
        for leg in route.legs.dropLast() {
            age+=leg.timing.duration
            XCTAssertLessThan(Geometry.distance(route.position(at:age-0.00001),route.position(at:age+0.00001)),0.01)
            XCTAssertEqual(route.speed(at:age-0.00001),route.speed(at:age+0.00001),accuracy:0.001)
        }
        XCTAssertEqual(route.speed(at:0),0)
        XCTAssertEqual(route.speed(at:route.duration),0)
        XCTAssertEqual(route.position(at:-1),route.position(at:0))
        XCTAssertEqual(route.position(at:route.duration+1),route.legs.last!.path.point(1))
    }
    func testInvalidRoutesAreRejectedBeforeInstallingMovement() {
        let a=CGPoint(x:0,y:0),b=CGPoint(x:200,y:0),c=CGPoint(x:400,y:0)
        XCTAssertNil(CoordinatedFlightRoute(legs:[]))
        XCTAssertNil(CoordinatedFlightRoute(legs:[line(a,b),line(CGPoint(x:201,y:0),c)]))
        XCTAssertNil(CoordinatedFlightRoute(legs:[line(a,b,speed:180),line(b,c,speed:200)]))
        XCTAssertNil(CoordinatedFlightRoute(legs:[line(a,b,speed:1)]))
        XCTAssertNil(CoordinatedFlightRoute(legs:[line(a,a)]))
        XCTAssertNil(CoordinatedFlightRoute(legs:[line(a,CGPoint(x:CGFloat.nan,y:0))]))
        let path=FlightPath(points:[a,b])
        XCTAssertNil(CoordinatedFlightRoute(legs:[CoordinatedFlightLeg(path:path,timing:FlightTiming(distance:201,speed:180))]))
    }
    func testInstallAndMetadataNeverMoveFeetOnlyTickSamplesRoute() throws {
        let (bird,route)=try fixture(),origin=bird.position,revision=bird.motionRevision
        XCTAssertTrue(bird.beginCoordinatedFlight(route,on:host,fraction:0.75,spriteScale:1))
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision+1)
        XCTAssertEqual(bird.state,.flying);XCTAssertTrue(bird.isCoordinatedFlying)
        for _ in 0..<10 {bird.updateHost(surfaces:[host],sampleDT:0.1)}
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.coordinatedFlightAge,0)
        for tick in 1...60 {
            bird.tick(1.0/60)
            XCTAssertLessThan(Geometry.distance(bird.position,route.position(at:Double(tick)/60)),0.000001)
            XCTAssertTrue(bird.frameName.hasPrefix("fly"));XCTAssertFalse(bird.isGliding)
        }
    }
    func testLandingFinishesOnceWithoutExtraTimeOrHostSnap() throws {
        let (bird,route)=try fixture()
        XCTAssertTrue(bird.beginCoordinatedFlight(route,on:host,fraction:0.75,spriteScale:1))
        let revision=bird.motionRevision
        for _ in 0..<Int(ceil((route.duration+1)*60)) {bird.tick(1.0/60)}
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.landedCount,1)
        XCTAssertEqual(bird.position,route.position(at:route.duration))
        XCTAssertFalse(bird.needsDestination);XCTAssertTrue(bird.isCoordinatedFlying)
        bird.finishCoordinatedFlight()
        XCTAssertFalse(bird.isCoordinatedFlying);XCTAssertEqual(bird.motionRevision,revision)
        bird.tick(0.1);XCTAssertEqual(bird.landedCount,1)
    }
    func testDelayedStartProtectsWaitingFeetAndUsesTheSameTickClock() throws {
        let (bird,route)=try fixture(),origin=bird.position
        XCTAssertTrue(bird.beginCoordinatedFlight(route,on:host,fraction:0.75,spriteScale:1,delay:0.5))
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.depthID,host.id)
        bird.tick(0.25);bird.updateHost(surfaces:[host],sampleDT:0.1)
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.coordinatedFlightAge,0)
        bird.tick(0.25);XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.state,.perched)
        bird.tick(0.1)
        XCTAssertEqual(bird.state,.flying);XCTAssertNil(bird.depthID)
        XCTAssertLessThan(Geometry.distance(bird.position,route.position(at:0.1)),0.000001)
        let (waiting,other)=try fixture(),actual=waiting.position
        XCTAssertTrue(waiting.beginCoordinatedFlight(other,on:host,fraction:0.75,spriteScale:1,delay:0.5))
        var moved=host;moved.rect.origin.x+=20
        waiting.updateHost(surfaces:[moved],sampleDT:0.1)
        XCTAssertEqual(waiting.position,actual);XCTAssertTrue(waiting.needsDestination)
        waiting.tick(1);XCTAssertEqual(waiting.position,actual)
    }
    func testInvalidHostScaleOrOwnerCancelsAtActualFeetEvenAfterLanding() throws {
        for settled in [false,true] {
            for mutation in ["removed","moved","pid","scale","size"] {
                let (bird,route)=try fixture()
                XCTAssertTrue(bird.beginCoordinatedFlight(route,on:host,fraction:0.75,spriteScale:1))
                for _ in 0..<(settled ? Int(ceil((route.duration+1)*60)):30) {bird.tick(1.0/60)}
                let actual=bird.position
                var changed=host,scale:CGFloat=1
                switch mutation {
                case "moved":changed.rect.origin.x+=1
                case "pid":changed=Surface(id:host.id,pid:99,rect:host.rect)
                case "scale":scale=1.1
                case "size":changed.rect.size.width+=1
                default:break
                }
                bird.updateHost(surfaces:mutation == "removed" ? []:[changed],sampleDT:0.1,spriteScale:scale)
                XCTAssertEqual(bird.position,actual);XCTAssertFalse(bird.isCoordinatedFlying)
                XCTAssertTrue(bird.needsDestination);XCTAssertNil(bird.hostID)
                bird.tick(1);bird.updateHost(surfaces:[changed],sampleDT:0.1)
                XCTAssertEqual(bird.position,actual)
            }
        }
    }
    func testRejectedInstallAndExternalFlightReplacementPreserveActualAnchor() throws {
        let (bird,route)=try fixture(),origin=bird.position,revision=bird.motionRevision
        XCTAssertFalse(bird.beginCoordinatedFlight(route,on:host,fraction:0.7,spriteScale:1))
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
        XCTAssertTrue(bird.beginCoordinatedFlight(route,on:host,fraction:0.75,spriteScale:1))
        bird.tick(0.2);let actual=bird.position
        XCTAssertFalse(bird.beginCoordinatedFlight(route,on:host,fraction:0.75,spriteScale:1))
        bird.fly(to:CGPoint(x:700,y:700),host:nil,allowsOrbit:false,random:{0.5})
        let replacement=bird.motionRevision
        bird.cancelCoordinatedFlight()
        XCTAssertEqual(bird.position,actual);XCTAssertEqual(bird.motionRevision,replacement)
        XCTAssertFalse(bird.isCoordinatedFlying);bird.tick(0.1);XCTAssertNotEqual(bird.position,actual)
    }
    func testPeerFlightEnvelopeContainsHostCorrectionAndWaveBeforeNextTick() throws {
        for species:SpeciesID in [.spottedDove,.treeSparrow,.commonKestrel] {
            let bird=Bird(position:CGPoint(x:1000,y:400),fraction:0.6,
                profile:SpeciesCatalog.standard.profile(species),random:{0.5})
            bird.fly(to:Geometry.foot(on:host,fraction:bird.fraction,edge:.top),host:host,
                allowsOrbit:species == .commonKestrel,random:{0.5})
            for _ in 0..<90 {bird.tick(1.0/60)}
            var moved=host;moved.rect.origin.x-=1800;moved.rect.origin.y-=80
            let actual=bird.position
            bird.updateHost(surfaces:[moved],sampleDT:0.1)
            XCTAssertEqual(bird.position,actual)
            let envelope=try XCTUnwrap(bird.plannedFlightFootprint(scale:1))
            for _ in 0..<Int(ceil(bird.flightDuration*60)) {
                bird.tick(1.0/60)
                let footprint=Geometry.landingFootprint(at:bird.position,scale:1)
                XCTAssertTrue(envelope.insetBy(dx:-0.000001,dy:-0.000001).contains(footprint),"\(species)")
            }
        }
    }
}
