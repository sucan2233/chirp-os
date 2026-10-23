import XCTest
@testable import BirdingCore

final class AmbientTests: XCTestCase {
    func testSettingsMigrationAndRoundTrip() throws {
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as! [String:Any]
        for key in ["pointerVisits","flockPasses","ambientFrequency"] {object.removeValue(forKey:key)}
        let old=try BirdSettings.decode(JSONSerialization.data(withJSONObject:object))
        XCTAssertTrue(old.pointerVisits);XCTAssertTrue(old.flockPasses);XCTAssertEqual(old.ambientFrequency,.low)
        var settings=old;settings.pointerVisits=false;settings.flockPasses=false;settings.ambientFrequency = .high
        let saved=try BirdSettings.decode(JSONEncoder().encode(settings))
        XCTAssertFalse(saved.pointerVisits);XCTAssertFalse(saved.flockPasses);XCTAssertEqual(saved.ambientFrequency,.high)
        XCTAssertEqual(saved.probabilities,old.probabilities)
        object["ambientFrequency"]="unknown"
        XCTAssertThrowsError(try BirdSettings.decode(JSONSerialization.data(withJSONObject:object)))
    }

    private func tick(_ scheduler:inout AmbientScheduler, seconds:Double, step:Double=0.05,
                      point:CGPoint = .zero, buttons:Bool=false, pointer:Bool=true,
                      flock:Bool=true, busy:Bool=false) -> [AmbientEvent] {
        var events:[AmbientEvent]=[]
        for _ in 0..<Int((seconds/step).rounded()) {
            if let event=scheduler.tick(step,pointer:point,buttonsDown:buttons,pointerEnabled:pointer,
                                        flockEnabled:flock,frequency:.high,busy:busy,random:{0}) {events.append(event)}
        }
        return events
    }
    func testScheduleIsIndependentOfFrameRateAndEventsAreExclusive() {
        for step in [1.0/30,1.0/60,1.0/120] {
            var scheduler=AmbientScheduler();scheduler.reset(.high)
            let events=tick(&scheduler,seconds:136,step:step)
            XCTAssertEqual(events.count,3)
            XCTAssertTrue(events.allSatisfy{$0 == .pointerVisit})
        }
    }
    func testMovingPointerFallsBackToFlockAndDisabledModesStayOff() {
        var scheduler=AmbientScheduler();scheduler.reset(.high)
        _=tick(&scheduler,seconds:44,pointer:false,flock:false)
        let events=tick(&scheduler,seconds:2,point:CGPoint(x:100,y:100))
        XCTAssertEqual(events,[.flockPass])
        XCTAssertTrue(tick(&scheduler,seconds:100,pointer:false,flock:false).isEmpty)
    }
    func testBusyAndClicksDiscardOpportunitiesAndDoNotQueue() {
        var scheduler=AmbientScheduler();scheduler.reset(.high)
        XCTAssertTrue(tick(&scheduler,seconds:46,busy:true).isEmpty)
        XCTAssertTrue(tick(&scheduler,seconds:10).isEmpty)
        XCTAssertTrue(tick(&scheduler,seconds:40,buttons:true).isEmpty)
        scheduler.suppress()
        XCTAssertGreaterThanOrEqual(scheduler.remaining,60)
        XCTAssertEqual(scheduler.stationaryTime,0)
        XCTAssertTrue(tick(&scheduler,seconds:59).isEmpty)
    }
    func testLongClockGapCannotCauseBurst() {
        var scheduler=AmbientScheduler();scheduler.reset(.high)
        XCTAssertNil(scheduler.tick(3600,pointer:.zero,buttonsDown:false,pointerEnabled:true,
                                    flockEnabled:true,frequency:.high,busy:false,random:{0}))
        XCTAssertEqual(scheduler.remaining,44.9,accuracy:0.0001)
    }
    func testPointerOrbitRejectsUnsafeEdgesAndCloseOrigins() {
        let area=CGRect(x:-1500,y:-400,width:1400,height:1000)
        let center=CGPoint(x:area.midX,y:area.midY)
        XCTAssertNil(PointerOrbit(center:CGPoint(x:area.minX+20,y:area.midY),origin:.zero,area:area,spriteScale:1))
        XCTAssertNil(PointerOrbit(center:center,origin:center,area:area,spriteScale:1))
        XCTAssertNil(PointerOrbit(center:.zero,origin:CGPoint(x:500,y:500),area:CGRect(x:0,y:0,width:100,height:100),spriteScale:1))
    }
    func testPointerFlightStaysOutsideRingAndReturnsWithoutTeleporting() throws {
        let area=CGRect(x:-1600,y:-500,width:1500,height:1200)
        let center=CGPoint(x:area.midX,y:area.midY)
        for angle in stride(from:0.0,to:Double.pi*2,by:Double.pi/4) {
            let start=CGPoint(x:center.x+390*cos(angle),y:center.y+390*sin(angle))
            let host=Surface(id:10,rect:CGRect(x:start.x-100,y:start.y,width:200,height:100))
            let bird=Bird(position:start,fraction:0.5,profile:SpeciesCatalog.standard.profile(.treeSparrow))
            bird.perch(on:host)
            let orbit=try XCTUnwrap(PointerOrbit(center:center,origin:bird.position,area:area,spriteScale:1))
            bird.fly(to:start,host:host,airspace:area,pointerOrbit:orbit)
            XCTAssertEqual(bird.state,.flying)
            var previous=start,wasCircling=false
            for _ in 0..<Int(ceil(bird.flightDuration*120))+1 {
                bird.tick(1.0/120)
                XCTAssertLessThan(Geometry.distance(previous,bird.position),5)
                XCTAssertGreaterThanOrEqual(Geometry.distance(center,bird.position),orbit.radius-0.1)
                XCTAssertTrue(area.contains(bird.position))
                wasCircling = wasCircling || bird.isCircling
                previous=bird.position
            }
            XCTAssertTrue(wasCircling)
            XCTAssertEqual(bird.state,.landing)
            XCTAssertEqual(bird.position.x,start.x,accuracy:0.001)
            XCTAssertEqual(bird.position.y,start.y,accuracy:0.001)
            XCTAssertFalse(bird.isDeparting)
        }
    }
    func testNewFlightInterruptsPointerVisitAtCurrentPosition() throws {
        let area=CGRect(x:0,y:0,width:1400,height:1000),center=CGPoint(x:700,y:500)
        let start=CGPoint(x:1100,y:500)
        let orbit=try XCTUnwrap(PointerOrbit(center:center,origin:start,area:area,spriteScale:1))
        let bird=Bird(position:start,fraction:0.5)
        bird.fly(to:start,host:nil,airspace:area,pointerOrbit:orbit);bird.tick(2)
        let position=bird.position
        bird.fly(to:CGPoint(x:100,y:100),host:nil,urgent:true)
        XCTAssertFalse(bird.isCircling);XCTAssertEqual(bird.position,position)
        bird.tick(1.0/60)
        XCTAssertLessThan(Geometry.distance(position,bird.position),10)
    }
    func testFlockIsBoundedStaggeredAndCruisesOutOfBothEdges() {
        let screen=CGRect(x:-1600,y:-300,width:3000,height:1000)
        for rightward in [true,false] {
            let plans=AmbientFlock.plan(screen:screen,rightward:rightward,count:100,spriteScale:1.5,speed:300,random:{0.4})
            XCTAssertEqual(plans.count,5)
            XCTAssertEqual(Set(plans.map(\.delay)).count,5)
            for plan in plans {
                let start=plan.path.point(0),end=plan.path.point(1)
                XCTAssertFalse(screen.contains(start));XCTAssertFalse(screen.contains(end))
                XCTAssertEqual(end.x>start.x,rightward)
                let bird=Bird(position:start,fraction:0.5)
                bird.passThrough(plan)
                XCTAssertEqual(bird.state,.flying);XCTAssertTrue(bird.isDeparting)
                XCTAssertFalse(bird.needsDestination)
                bird.tick(bird.flightDuration/2)
                let last=bird.position;bird.tick(0.01)
                XCTAssertEqual(Double(Geometry.distance(last,bird.position))/0.01,plan.speed,accuracy:5)
                bird.tick(bird.flightDuration)
                XCTAssertTrue(bird.departureFinished);XCTAssertFalse(bird.needsDestination)
                XCTAssertEqual(bird.position,end)
            }
        }
    }
}
