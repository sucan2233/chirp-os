import XCTest
@testable import BirdingCore

final class AirborneFlightTests:XCTestCase {
    private let host=Surface(id:31,pid:17,rect:CGRect(x:900,y:600,width:800,height:180))
    private func flying() -> Bird {
        let bird=Bird(position:CGPoint(x:100,y:600),fraction:0.6,
            profile:SpeciesCatalog.standard.profile(.spottedDove),random:{0.5})
        bird.fly(to:Geometry.foot(on:host,fraction:bird.fraction,edge:.top),host:host,arc:0,allowsOrbit:false,random:{0.5})
        for _ in 0..<60 {bird.tick(1.0/60)}
        return bird
    }
    private func route(_ bird:Bird,speedOffset:Double=0,reverse:Bool=false,tilt:Bool=false) throws -> CoordinatedFlightRoute {
        let snapshot=try XCTUnwrap(bird.airborneFlight)
        let initial=Double(Geometry.distance(.zero,snapshot.velocity))+speedOffset
        let bend=reverse ? -100.0:100.0
        let path=FlightPath(snapshot.position,CGPoint(x:snapshot.position.x+bend,y:snapshot.position.y+(tilt ? 9:0)),
            CGPoint(x:snapshot.destination.x-100,y:snapshot.destination.y),snapshot.destination)
        let timing=try XCTUnwrap(FlightTiming(distance:path.length,cruiseSpeed:180,initialSpeed:initial,finalSpeed:0,rampIn:0.6,rampOut:0.8))
        return try XCTUnwrap(CoordinatedFlightRoute(legs:[CoordinatedFlightLeg(path:path,timing:timing)]))
    }
    func testMovingEnvelopePreservesEndpointsAndIntegratedDistance() throws {
        for (initial,cruise,final) in [(340.0,180.0,0.0),(100,280,160),(180,180,180)] {
            let timing=try XCTUnwrap(FlightTiming(distance:1000,cruiseSpeed:cruise,initialSpeed:initial,finalSpeed:final,rampIn:0.7,rampOut:0.8))
            XCTAssertEqual(timing.speed(at:0),initial,accuracy:0.000001)
            XCTAssertEqual(timing.speed(at:timing.duration),final,accuracy:0.000001)
            var distance=0.0,last=0.0
            let dt=timing.duration/10000
            for i in 0..<10000 {
                distance+=timing.speed(at:(Double(i)+0.5)*dt)*dt
                let progress=timing.progress(at:Double(i)*dt)
                XCTAssertGreaterThanOrEqual(progress,last);last=progress
                XCTAssertLessThanOrEqual(timing.speed(at:Double(i)*dt),timing.peakSpeed+0.000001)
            }
            XCTAssertEqual(distance,1000,accuracy:0.001)
            XCTAssertEqual(timing.progress(at:timing.duration),1)
        }
    }
    func testExtremeFiniteRampsDoNotOverflowTheTrigonometricArguments() throws {
        let timing=try XCTUnwrap(FlightTiming(distance:1,cruiseSpeed:1e-308,initialSpeed:1e-308,finalSpeed:1e-308,rampIn:1e308,rampOut:0))
        XCTAssertTrue(timing.speed(at:6e307).isFinite)
        XCTAssertEqual(timing.progress(at:6e307),0.6,accuracy:1e-10)
        for index in 0..<6 {
            for invalid in [Double.nan,Double.infinity,-Double.infinity] {
                var values=[1000.0,200,300,0,0.6,0.8];values[index]=invalid
                XCTAssertNil(FlightTiming(distance:values[0],cruiseSpeed:values[1],initialSpeed:values[2],finalSpeed:values[3],rampIn:values[4],rampOut:values[5]))
            }
        }
    }
    func testImpossibleMovingEnvelopesAreRejectedRatherThanResettingSpeed() {
        for (length,start,ramp) in [(10.0,400.0,1.0),(1000,-1,1),(1000,400,0),(Double.nan,400,1)] {
            XCTAssertNil(FlightTiming(distance:length,cruiseSpeed:200,initialSpeed:start,finalSpeed:0,rampIn:ramp,rampOut:0.5))
        }
    }
    func testAirborneHandoffPreservesFeetVelocityAndWingPhase() throws {
        let bird=flying(),snapshot=try XCTUnwrap(bird.airborneFlight),route=try route(bird)
        let frame=bird.frameName,revision=bird.motionRevision
        XCTAssertTrue(bird.beginCoordinatedFlight(route,on:host,fraction:bird.fraction,spriteScale:1,airborne:true))
        XCTAssertEqual(bird.position,snapshot.position);XCTAssertEqual(bird.frameName,frame)
        XCTAssertEqual(bird.flightSpeed,Double(Geometry.distance(.zero,snapshot.velocity)),accuracy:0.000001)
        XCTAssertEqual(bird.motionRevision,revision+1);XCTAssertNil(bird.airborneFlight)
        bird.tick(1.0/60)
        let actual=CGPoint(x:(bird.position.x-snapshot.position.x)*60,y:(bird.position.y-snapshot.position.y)*60)
        XCTAssertLessThan(Geometry.distance(actual,snapshot.velocity),1)
        XCTAssertGreaterThan(bird.flightSpeed,100)
        for _ in 0..<Int(ceil((route.duration+1)*60)) {bird.tick(1.0/60)}
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,snapshot.destination)
        XCTAssertEqual(bird.landedCount,1)
    }
    func testInvalidHandoffCannotChangeAnIndependentFlight() throws {
        for failure in ["speed","direction","tilt","delay","destination","owner"] {
            let bird=flying(),snapshot=try XCTUnwrap(bird.airborneFlight)
            let route=try route(bird,speedOffset:failure=="speed" ? 10:0,reverse:failure=="direction",tilt:failure=="tilt")
            let other=Surface(id:host.id,pid:99,rect:host.rect)
            let accepted=bird.beginCoordinatedFlight(route,on:failure=="owner" ? other:host,
                fraction:failure=="destination" ? 0.5:bird.fraction,spriteScale:1,
                delay:failure=="delay" ? 0.5:0,airborne:true)
            XCTAssertFalse(accepted,failure);XCTAssertEqual(bird.position,snapshot.position)
            XCTAssertEqual(bird.motionRevision,snapshot.revision);XCTAssertNotNil(bird.airborneFlight)
            bird.tick(1.0/60);XCTAssertNotEqual(bird.position,snapshot.position)
        }
    }
    func testOnlyStableIndependentFlightsOfferVelocitySnapshots() throws {
        let bird=flying();XCTAssertNotNil(bird.airborneFlight)
        bird.perch(on:host);XCTAssertNil(bird.airborneFlight)
        bird.fly(to:CGPoint(x:100,y:600),host:host,urgent:true);bird.tick(0.5);XCTAssertNil(bird.airborneFlight)
        bird.depart(to:CGPoint(x:3000,y:600),duration:4);bird.tick(0.5);XCTAssertNil(bird.airborneFlight)
        let fresh=flying(),route=try route(fresh)
        XCTAssertTrue(fresh.beginCoordinatedFlight(route,on:host,fraction:fresh.fraction,spriteScale:1,airborne:true))
        fresh.tick(0.3);XCTAssertNil(fresh.airborneFlight)
        let actual=fresh.position
        fresh.updateHost(surfaces:[],sampleDT:0.1)
        XCTAssertTrue(fresh.needsDestination);XCTAssertNil(fresh.airborneFlight)
        fresh.tick(0.5);XCTAssertEqual(fresh.position,actual)
    }
}
