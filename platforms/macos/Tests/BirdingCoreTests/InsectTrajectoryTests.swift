import XCTest
@testable import BirdingCore

final class InsectTrajectoryTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:100,height:100)
    private func trajectory(scale:CGFloat=1,duration:Double=14)->InsectTrajectory? {
        InsectTrajectory(waypoints:[.init(time:0,position:CGPoint(x:-20,y:50)),
            .init(time:duration,position:CGPoint(x:120,y:50))],display:display,worldScale:scale)
    }

    func testFullSpriteEntryExitAndTwelveSecondLifetimeHaveOneFrozenClock() throws {
        let path=try XCTUnwrap(trajectory())
        XCTAssertEqual(InsectTrajectory.lifetime,12);XCTAssertEqual(InsectTrajectory.logicalSize,16)
        XCTAssertEqual(path.visibleFrom,1.2,accuracy:1e-12)
        XCTAssertEqual(path.visibleUntil,12.8,accuracy:1e-12);XCTAssertEqual(path.terminalAge,12)
        XCTAssertEqual(path.position(at:-1),CGPoint(x:-20,y:50))
        XCTAssertEqual(path.position(at:7),CGPoint(x:50,y:50))
        XCTAssertEqual(path.position(at:20),CGPoint(x:120,y:50))
        XCTAssertFalse(path.isVisible(at:path.visibleFrom));XCTAssertTrue(path.isVisible(at:2))
        XCTAssertTrue(path.isVisible(at:11.9));XCTAssertFalse(path.isVisible(at:12))
        for scale:CGFloat in [0.5,1,2] {
            let scaled=try XCTUnwrap(trajectory(scale:scale))
            XCTAssertEqual(scaled.collisionRadius,3*scale)
            let half=8*scale
            XCTAssertLessThanOrEqual(scaled.position(at:0).x+half,display.minX)
            XCTAssertGreaterThanOrEqual(scaled.position(at:scaled.duration).x-half,display.maxX)
        }
        let quick=try XCTUnwrap(trajectory(duration:7))
        XCTAssertEqual(quick.terminalAge,6.4,accuracy:1e-12,"Leaving the screen retires the entity before its age cap")
    }

    func testInvalidTrajectoriesCannotStartInsideReenterOrCarryNonfiniteGeometry() {
        func make(_ points:[InsectWaypoint],scale:CGFloat=1,area:CGRect?=nil)->InsectTrajectory? {
            InsectTrajectory(waypoints:points,display:area ?? display,worldScale:scale)
        }
        let start=InsectWaypoint(time:0,position:CGPoint(x:-20,y:50))
        let end=InsectWaypoint(time:14,position:CGPoint(x:120,y:50))
        XCTAssertNil(make([start]));XCTAssertNil(make([end,start]))
        XCTAssertNil(make([.init(time:0,position:CGPoint(x:0,y:50)),end]))
        XCTAssertNil(make([start,.init(time:14,position:CGPoint(x:100,y:50))]))
        XCTAssertNil(make([start,.init(time:1,position:CGPoint(x:120,y:50)),
            .init(time:2,position:CGPoint(x:-20,y:50)),.init(time:3,position:CGPoint(x:120,y:50))]))
        XCTAssertNil(make([start,.init(time:14,position:CGPoint(x:120,y:150))],scale:0))
        XCTAssertNil(make([start,end],scale:.infinity));XCTAssertNil(make([start,end],area:.zero))
        XCTAssertNil(make([start,.init(time:.nan,position:CGPoint(x:120,y:50))]))
        XCTAssertNil(make([start,.init(time:14,position:CGPoint(x:CGFloat.infinity,y:50))]))
        XCTAssertNil(make([start,.init(time:0,position:CGPoint(x:120,y:50))]))
        XCTAssertNil(make([start,.init(time:61,position:CGPoint(x:120,y:50))]))
        // No visible interval, despite finite points outside both ends.
        XCTAssertNil(make([.init(time:0,position:CGPoint(x:-20,y:-20)),
            .init(time:5,position:CGPoint(x:120,y:-20))]))
    }

    func testStoreHasOneIdentityAndPureStepsCommitExactlyOnceEvenAcrossExpiry() throws {
        let store=InsectStore(),path=try XCTUnwrap(trajectory())
        XCTAssertFalse(store.install(id:ScenePropID(0),trajectory:path))
        XCTAssertTrue(store.install(id:ScenePropID(9),trajectory:path))
        XCTAssertFalse(store.install(id:ScenePropID(10),trajectory:path))
        for dt in [0.0,-1,.nan,.infinity] {XCTAssertNil(store.makeStep(dt))}
        let step=try XCTUnwrap(store.makeStep(2)),again=try XCTUnwrap(store.makeStep(2))
        XCTAssertEqual(store.current?.age,0);XCTAssertEqual(step.startAge,again.startAge)
        XCTAssertEqual(step.endAge,again.endAge);XCTAssertNil(store.lastContact)
        XCTAssertTrue(store.commit(step,capture:nil));XCTAssertFalse(store.commit(again,capture:nil))
        XCTAssertEqual(store.current?.id,ScenePropID(9));XCTAssertEqual(store.current?.age,2)
        let expiry=try XCTUnwrap(store.makeStep(11))
        XCTAssertNotNil(store.current,"Post-motion contact must resolve before expiry is committed")
        XCTAssertTrue(store.commit(expiry,capture:nil));XCTAssertNil(store.current)
        XCTAssertTrue(store.install(id:ScenePropID(10),trajectory:path))
        XCTAssertFalse(store.commit(expiry,capture:nil),"A stale step cannot retire the replacement entity")
        XCTAssertEqual(store.current?.id,ScenePropID(10));XCTAssertEqual(store.current?.age,0)
    }

    func testWorldInvalidationClearsTheIndependentEntityEvenWhilePaused() throws {
        for mutation in ["disabled","art","scale","display","screen","displayID"] {
            let e=BehaviorEngine(seed:9);e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
            e.updateWorld(.init(screens:[display],displays:[display],displayIDs:["A"]))
            let path=try XCTUnwrap(InsectTrajectory(waypoints:try XCTUnwrap(trajectory()).waypoints,
                display:display,worldScale:1,screens:[display],displays:[display],displayIDs:["A"]))
            XCTAssertTrue(e.insects.install(id:ScenePropID(9),trajectory:path))
            e.handle(.pause(true))
            let age=e.insectSnapshot()?.age
            for _ in 0..<60 {e.advance(BehaviorEngine.step)}
            XCTAssertEqual(e.insectSnapshot()?.age,age)
            if mutation == "disabled" {
                var settings=e.settings;settings.insectCatchEnabled=false;e.applySettings(settings)
            } else {
                var world=e.world
                switch mutation {
                case "art":world.insectArtAvailable=false
                case "scale":world.scale=2
                case "display":world.displays=[]
                case "screen":world.screens=[display.offsetBy(dx:10,dy:0)]
                default:world.displayIDs=["B"]
                }
                e.updateWorld(world)
            }
            XCTAssertNil(e.insectSnapshot(),mutation);XCTAssertTrue(e.propSnapshot().isEmpty,mutation)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
        }
    }
}
