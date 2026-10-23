import XCTest
@testable import BirdingCore

final class PointerFollowTests:XCTestCase {
    private let screen=CGRect(x:-700,y:-200,width:1400,height:1000)
    private let host=Surface(id:41,pid:17,rect:CGRect(x:-640,y:680,width:1280,height:100))
    private let center=CGPoint(x:0,y:300)

    private func fixture(follow:Bool=true) -> BehaviorEngine {
        var settings=BirdSettings();settings.pointerFollowEnabled=follow;settings.perchActions=false
        let engine=BehaviorEngine(seed:73,settings:settings)
        engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:center))
        let bird=Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host);bird.perchDuration=600
        engine.installFixtureBirds([bird])
        return engine
    }
    private func runID(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let id)=result else {
            XCTFail("Expected started, got \(result)",file:file,line:line)
            throw NSError(domain:"PointerFollowTests",code:1)
        }
        return id
    }
    private func terminals(_ engine:BehaviorEngine,_ id:BehaviorRunID) -> [BehaviorEvent] {
        engine.events.filter{$0.runID==id && [.completed,.cancelled,.failed].contains($0.type)}
    }
    private func advance(_ engine:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded(.up)) {engine.advance(1/Double(hz))}
    }
    private func motionBird() throws -> (Bird,PointerOrbit) {
        let bird=Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host)
        let orbit=try XCTUnwrap(PointerOrbit(center:center,origin:bird.position,area:screen,spriteScale:1))
        bird.fly(to:bird.position,host:host,airspace:screen,pointerOrbit:orbit,random:{0.5})
        return (bird,orbit)
    }

    func testCenterHasBoundedSpeedAndContinuousEntryOrbitAndExitWithoutRestarting() throws {
        let (bird,_)=try motionBird(),(reference,_)=try motionBird()
        XCTAssertTrue(bird.enablePointerFollow(in:screen,spriteScale:1))
        let revision=bird.motionRevision,origin=bird.position,dt=1.0/120
        let originalDuration=bird.flightDuration
        var previous=bird.position,previousCenter=center,previousVelocity=CGPoint.zero
        var circled=false,exited=false,entryJoins=0,exitJoins=0
        var exitCenter:CGPoint?,exitDuration:Double?
        for tick in 0..<120*25 {
            let wasCircling=bird.isCircling
            let pointer=tick%240<120 ? CGPoint(x:650,y:400):CGPoint(x:-650,y:50)
            let before=bird.position
            XCTAssertTrue(bird.updatePointerFollowTarget(pointer))
            XCTAssertEqual(bird.position,before)
            bird.tick(dt);reference.tick(dt)
            let currentCenter=try XCTUnwrap(bird.pointerFollowCenter)
            XCTAssertLessThanOrEqual(Geometry.distance(previousCenter,currentCenter),Bird.pointerFollowSpeed*dt+0.00001)
            XCTAssertLessThanOrEqual(Geometry.distance(previous,bird.position),330*dt+0.05)
            XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertEqual(bird.isCircling,reference.isCircling)
            let velocity=CGPoint(x:(bird.position.x-previous.x)/dt,y:(bird.position.y-previous.y)/dt)
            if bird.isCircling && !wasCircling {
                entryJoins+=1
                XCTAssertLessThan(Geometry.distance(previousVelocity,velocity),20)
            }
            if wasCircling && !bird.isCircling {
                exitJoins+=1;exited=true;exitCenter=currentCenter;exitDuration=bird.flightDuration
                XCTAssertLessThan(Geometry.distance(previousVelocity,velocity),20)
                XCTAssertGreaterThan(Geometry.distance(center,currentCenter),10)
            }
            if !circled && !bird.isCircling {XCTAssertEqual(currentCenter,center)}
            if exited {
                XCTAssertEqual(currentCenter,exitCenter)
                XCTAssertEqual(bird.flightDuration,exitDuration)
            } else {XCTAssertEqual(bird.flightDuration,originalDuration)}
            circled = circled || bird.isCircling
            previous=bird.position;previousCenter=currentCenter;previousVelocity=velocity
            if bird.state != .flying {break}
        }
        XCTAssertTrue(circled);XCTAssertTrue(exited)
        XCTAssertEqual(entryJoins,1);XCTAssertEqual(exitJoins,1)
        XCTAssertEqual(bird.state,.landing);XCTAssertEqual(bird.position,origin)
        XCTAssertEqual(bird.hostID,host.id);XCTAssertEqual(bird.landedCount,1)
    }

    func testEveryScreenCornerClampsCenterAndKeepsOrbitSpriteInside() throws {
        for x in [screen.minX+0.01,screen.maxX-0.01] {
            for y in [screen.minY+0.01,screen.maxY-0.01] {
                let (bird,orbit)=try motionBird()
                XCTAssertTrue(bird.enablePointerFollow(in:screen,spriteScale:1))
                let centers=screen.insetBy(dx:orbit.radius+45,dy:orbit.radius+45)
                var circled=false
                for _ in 0..<60*25 {
                    XCTAssertTrue(bird.updatePointerFollowTarget(CGPoint(x:x,y:y)))
                    bird.tick(1.0/60)
                    if bird.isCircling {
                        circled=true
                        let c=try XCTUnwrap(bird.pointerFollowCenter)
                        XCTAssertGreaterThanOrEqual(c.x,centers.minX);XCTAssertLessThanOrEqual(c.x,centers.maxX)
                        XCTAssertGreaterThanOrEqual(c.y,centers.minY);XCTAssertLessThanOrEqual(c.y,centers.maxY)
                        XCTAssertTrue(screen.contains(Geometry.landingFootprint(at:bird.position,scale:1)))
                    }
                    if bird.state != .flying {break}
                }
                XCTAssertTrue(circled);XCTAssertEqual(bird.state,.landing)
                XCTAssertGreaterThan(Geometry.distance(center,try XCTUnwrap(bird.pointerFollowCenter)),50)
            }
        }
    }

    func testInvalidInputDoesNotMutateMotionAndNewFlightClearsFollowState() throws {
        let (bird,_)=try motionBird()
        XCTAssertFalse(bird.enablePointerFollow(in:CGRect(x:0,y:0,width:50,height:50),spriteScale:1))
        XCTAssertTrue(bird.enablePointerFollow(in:screen,spriteScale:1))
        let origin=bird.position,revision=bird.motionRevision
        for point in [CGPoint(x:screen.maxX+1,y:300),CGPoint(x:CGFloat.nan,y:0),CGPoint(x:0,y:CGFloat.infinity)] {
            XCTAssertFalse(bird.updatePointerFollowTarget(point))
            XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
        }
        bird.fly(to:CGPoint(x:100,y:100),host:nil,urgent:true)
        XCTAssertEqual(bird.position,origin);XCTAssertNil(bird.pointerFollowCenter)
        XCTAssertFalse(bird.updatePointerFollowTarget(center))
    }

    func testMovingPointerFinishesOnceAndReturnsToOriginalHost() throws {
        let e=fixture(),bird=e.birds[0],origin=e.birds[0].position
        let id=try runID(e.handle(.pointerVisit(.preview))),revision=bird.motionRevision
        for tick in 0..<60*25 {
            var world=e.world
            world.pointer=CGPoint(x:500*sin(Double(tick)/45),y:300+200*cos(Double(tick)/60))
            e.updateWorld(world);e.advance(BehaviorEngine.step)
            if !terminals(e,id).isEmpty {break}
            XCTAssertEqual(bird.motionRevision,revision)
        }
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.hostID,host.id)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
        advance(e,seconds:2)
        XCTAssertEqual(terminals(e,id).count,1);XCTAssertEqual(bird.state,.perched)
    }

    func testDefaultDisabledStillCancelsPointerMovement() throws {
        XCTAssertFalse(BirdSettings().pointerFollowEnabled)
        let e=fixture(follow:false),bird=e.birds[0]
        let id=try runID(e.handle(.pointerVisit(.preview)))
        advance(e,seconds:0.5)
        let position=bird.position,revision=bird.motionRevision
        var world=e.world;world.pointer.x+=30;e.updateWorld(world)
        _=e.renderSnapshot()
        XCTAssertEqual(bird.position,position)
        XCTAssertEqual(bird.motionRevision,revision)
        XCTAssertTrue(terminals(e,id).isEmpty)
        XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
        XCTAssertEqual(e.handle(.flockPass(.preview)),.rejected(.busy))
        e.advance(BehaviorEngine.step)
        XCTAssertEqual(terminals(e,id).map(\.reason),[.pointerMoved])
        XCTAssertLessThan(Geometry.distance(position,bird.position),10)
        XCTAssertEqual(e.leasedBirdCount,0)
    }

    func testExplicitClickOverridesSampledPointerMovementBeforeNextStep() throws {
        for follow in [false,true] {
            let e=fixture(follow:follow),bird=e.birds[0]
            let id=try runID(e.handle(.pointerVisit(.preview)))
            advance(e,seconds:0.5)
            let position=bird.position,revision=bird.motionRevision
            var world=e.world;world.pointer=CGPoint(x:screen.maxX+100,y:center.y)
            e.updateWorld(world);_=e.renderSnapshot()
            XCTAssertTrue(terminals(e,id).isEmpty)
            XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertEqual(e.handle(.flockPass(.preview)),.rejected(.busy))
            // A second sync, as performed by command adapters, must not consume
            // movement before the explicit click reaches the active execution.
            e.updateWorld(world);e.handle(.pointerClick)
            XCTAssertEqual(bird.position,position)
            XCTAssertEqual(terminals(e,id).map(\.type),[.cancelled])
            XCTAssertEqual(terminals(e,id).map(\.reason),[.userInput])
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            e.advance(BehaviorEngine.step)
            XCTAssertEqual(terminals(e,id).count,1)
        }
    }

    func testClickPauseAndMasterSwitchStillCancelFollow() throws {
        for input in ["click","buttons","pause","disabled"] {
            let e=fixture(),bird=e.birds[0]
            let id=try runID(e.handle(.pointerVisit(.preview)))
            advance(e,seconds:2)
            let position=bird.position
            switch input {
            case "click":e.handle(.pointerClick)
            case "buttons":var world=e.world;world.buttonsDown=true;e.updateWorld(world)
            case "pause":e.handle(.pause(true))
            default:var settings=e.settings;settings.pointerVisits=false;e.applySettings(settings)
            }
            XCTAssertEqual(bird.position,position)
            if input == "buttons" {
                XCTAssertTrue(terminals(e,id).isEmpty)
                XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
                XCTAssertEqual(e.handle(.flockPass(.preview)),.rejected(.busy))
            }
            advance(e,seconds:1)
            let reason:BehaviorReason=input == "pause" ? .paused:input == "disabled" ? .settingsChanged:.userInput
            XCTAssertEqual(terminals(e,id).map(\.reason),[reason])
            XCTAssertEqual(terminals(e,id).map(\.type),[.cancelled])
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertNil(bird.pointerFollowCenter)
        }
    }

    func testFollowSettingChangeCancelsOldRunInBothDirectionsButUnchangedValueDoesNot() throws {
        for oldValue in [false,true] {
            let e=fixture(follow:oldValue),bird=e.birds[0]
            let id=try runID(e.handle(.pointerVisit(.preview)))
            advance(e,seconds:0.5)
            e.applySettings(e.settings)
            XCTAssertTrue(terminals(e,id).isEmpty);XCTAssertEqual(e.activeRunCount,1)
            let position=bird.position
            var settings=e.settings;settings.pointerFollowEnabled = !oldValue;e.applySettings(settings)
            XCTAssertEqual(e.settings.pointerFollowEnabled,!oldValue)
            XCTAssertEqual(bird.position,position)
            XCTAssertEqual(terminals(e,id).map(\.type),[.cancelled])
            XCTAssertEqual(terminals(e,id).map(\.reason),[.settingsChanged])
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertNil(bird.pointerFollowCenter)
            e.applySettings(settings);advance(e,seconds:0.5)
            XCTAssertEqual(terminals(e,id).count,1)
            bird.perch(on:host)
            let next=try runID(e.handle(.pointerVisit(.preview)))
            var world=e.world;world.pointer.x+=30;e.updateWorld(world);e.advance(BehaviorEngine.step)
            if oldValue {XCTAssertEqual(terminals(e,next).map(\.reason),[.pointerMoved])}
            else {XCTAssertTrue(terminals(e,next).isEmpty);XCTAssertNotNil(bird.pointerFollowCenter)}
        }
    }

    func testCrossScreenAndMissingAreaCancelWithoutTeleporting() throws {
        for change in ["crossScreen","missing","resized","nonfinite"] {
            let e=fixture(),bird=e.birds[0]
            let id=try runID(e.handle(.pointerVisit(.preview)))
            advance(e,seconds:2)
            let position=bird.position
            var world=e.world
            switch change {
            case "crossScreen":
                let other=CGRect(x:700,y:-200,width:1400,height:1000)
                world.screens.append(other);world.displays.append(other);world.pointer=CGPoint(x:900,y:300)
            case "resized":world.screens=[CGRect(x:-700,y:-200,width:300,height:200)]
            case "nonfinite":world.pointer=CGPoint(x:CGFloat.nan,y:300)
            default:world.screens=[];world.displays=[];world.surfaces=[]
            }
            e.updateWorld(world)
            XCTAssertEqual(bird.position,position)
            if change == "crossScreen" || change == "nonfinite" {
                XCTAssertTrue(terminals(e,id).isEmpty)
                XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
            } else {
                XCTAssertEqual(terminals(e,id).map(\.reason),[.noSpace])
            }
            advance(e,seconds:0.5)
            XCTAssertEqual(terminals(e,id).map(\.type),[.cancelled])
            XCTAssertEqual(terminals(e,id).map(\.reason),[.noSpace])
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertNil(bird.pointerFollowCenter)
            if change == "missing" {XCTAssertEqual(bird.position,position)}
        }
    }

    func testLostOccludedOrReusedHostInvalidatesReturn() throws {
        for change in ["missing","occluded","reused"] {
            let e=fixture(),bird=e.birds[0]
            let id=try runID(e.handle(.pointerVisit(.preview)))
            advance(e,seconds:2)
            let position=bird.position
            var world=e.world
            switch change {
            case "reused":world.surfaces=[Surface(id:host.id,pid:host.pid+1,rect:host.rect)]
            case "occluded":world.surfaces.insert(Surface(id:90,rect:screen),at:0)
            default:world.surfaces=[]
            }
            e.updateWorld(world)
            XCTAssertEqual(bird.position,position)
            advance(e,seconds:0.5)
            XCTAssertEqual(terminals(e,id).map(\.type),[.failed])
            XCTAssertEqual(terminals(e,id).map(\.reason),[.targetInvalid])
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertNil(bird.pointerFollowCenter)
        }
    }

    func testGroundTailMayExtendPastWorkAreaIntoMatchingDisplay() throws {
        let e=fixture(),bird=e.birds[0]
        let work=CGRect(x:-700,y:-200,width:1400,height:940)
        let other=CGRect(x:700,y:-200,width:1400,height:1000)
        let ground=Geometry.ground(id:99,display:screen,workArea:work)
        let scale=e.spriteScale(for:bird)
        bird.perch(on:ground,spriteScale:scale)
        let origin=bird.position,footprint=Geometry.landingFootprint(at:origin,scale:scale)
        XCTAssertFalse(work.contains(footprint));XCTAssertTrue(screen.contains(footprint))
        e.updateWorld(BehaviorWorld(screens:[other,work],displays:[other,screen],surfaces:[ground],pointer:center))
        let id=try runID(e.handle(.pointerVisit(.preview)))
        for tick in 0..<60*25 {
            var world=e.world;world.pointer.x=300*sin(Double(tick)/60);e.updateWorld(world)
            e.advance(BehaviorEngine.step)
            if !terminals(e,id).isEmpty {break}
        }
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.hostID,ground.id)
        XCTAssertEqual(e.leasedBirdCount,0)
    }

    func testLandingHostSampleRejectsReusedIDBeforeMovingButFollowsSameOwner() throws {
        for follow in [false,true] {
            for reused in [false,true] {
                let e=fixture(follow:follow),bird=e.birds[0]
                let id=try runID(e.handle(.pointerVisit(.preview)))
                // Stop on the tick that lands, before the next runtime advance
                // can complete the pointer execution.
                for _ in 0..<60*25 {
                    e.advance(BehaviorEngine.step)
                    if bird.state == .landing {break}
                }
                XCTAssertEqual(bird.state,.landing)
                XCTAssertTrue(terminals(e,id).isEmpty);XCTAssertEqual(e.activeRunCount,1)
                let position=bird.position,revision=bird.motionRevision,startles=bird.startledCount
                let sampled=Surface(id:host.id,pid:reused ? host.pid+1:host.pid,
                                    rect:host.rect.offsetBy(dx:240,dy:-100))
                var world=e.world;world.surfaces=[sampled]
                // A long metadata gap deliberately bypasses the fast-window
                // movement heuristic; identity must still be checked first.
                e.updateWorld(world,sampleDT:0.25)
                if reused {
                    XCTAssertEqual(bird.position,position)
                    XCTAssertEqual(bird.state,.flying);XCTAssertNil(bird.hostID);XCTAssertNil(bird.depthID)
                    XCTAssertEqual(bird.startledCount,startles+1)
                    XCTAssertEqual(bird.motionRevision,revision+1)
                    XCTAssertNil(bird.pointerFollowCenter)
                    XCTAssertEqual(terminals(e,id).map(\.type),[.failed])
                    XCTAssertEqual(terminals(e,id).map(\.reason),[.targetInvalid])
                    XCTAssertEqual(e.leasedBirdCount,0)
                    e.advance(BehaviorEngine.step)
                    XCTAssertLessThan(Geometry.distance(position,bird.position),10)
                    XCTAssertEqual(terminals(e,id).count,1)
                } else {
                    let expected=Geometry.foot(on:sampled,fraction:bird.fraction,edge:bird.edge,scale:e.spriteScale(for:bird))
                    XCTAssertEqual(bird.position,expected);XCTAssertEqual(bird.state,.landing)
                    XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(bird.startledCount,startles)
                    XCTAssertTrue(terminals(e,id).isEmpty)
                    e.advance(BehaviorEngine.step)
                    XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
                    XCTAssertEqual(bird.position,expected);XCTAssertEqual(e.leasedBirdCount,0)
                }
            }
        }
    }

    func testFlyAndPerchBothCaptureHostOwnerBeforeSampling() {
        for perched in [false,true] {
            let bird=Bird(position:CGPoint(x:0,y:300),fraction:0.5,random:{0.5})
            if perched {bird.perch(on:host)}
            else {bird.fly(to:Geometry.foot(on:host,fraction:0.5,edge:.top),host:host,urgent:true)}
            let position=bird.position,revision=bird.motionRevision
            let replacement=Surface(id:host.id,pid:host.pid+1,rect:host.rect.offsetBy(dx:240,dy:-100))
            bird.updateHost(surfaces:[replacement],sampleDT:0.25)
            XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.state,.flying)
            XCTAssertEqual(bird.startledCount,1);XCTAssertEqual(bird.motionRevision,revision+1)
            XCTAssertNil(bird.hostID);XCTAssertNil(bird.depthID)
            // Explicitly adopting a new host must replace the remembered owner.
            bird.perch(on:replacement)
            let adopted=bird.position,adoptedRevision=bird.motionRevision
            bird.updateHost(surfaces:[replacement],sampleDT:0.25)
            XCTAssertEqual(bird.position,adopted);XCTAssertEqual(bird.state,.perched)
            XCTAssertEqual(bird.motionRevision,adoptedRevision);XCTAssertEqual(bird.startledCount,1)
        }
    }

    func testMovingOriginalHostIsUsedForExitWithoutReplanningOrbit() throws {
        let e=fixture(),bird=e.birds[0]
        let id=try runID(e.handle(.pointerVisit(.preview))),revision=bird.motionRevision
        for _ in 0..<60*5 {
            if bird.isCircling {break}
            e.advance(BehaviorEngine.step)
        }
        XCTAssertTrue(bird.isCircling)
        var moved=host;moved.rect.origin.x+=60;moved.rect.origin.y+=20
        let expected=Geometry.foot(on:moved,fraction:bird.fraction,edge:.top,scale:e.spriteScale(for:bird))
        var world=e.world;world.surfaces=[moved];world.pointer.x+=200;e.updateWorld(world)
        advance(e,seconds:20)
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
        XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(bird.position,expected)
        XCTAssertEqual(bird.hostID,host.id)
    }

    func testFollowingReplaysIdenticallyAt30And60And120Hz() throws {
        struct Trace:Equatable {
            let position:CGPoint,center:CGPoint?
            let frame:String,revision:UInt64
            let events:[String],active:Int,leased:Int
        }
        func replay(hz:Int) throws -> [Trace] {
            let e=fixture(),bird=e.birds[0]
            _=try runID(e.handle(.pointerVisit(.preview)))
            var trace:[Trace]=[]
            for second in 0..<25 {
                var world=e.world
                world.pointer=CGPoint(x:second%2 == 0 ? 650:-650,y:second%3 == 0 ? 700:0)
                e.updateWorld(world);advance(e,seconds:1,hz:hz)
                trace.append(Trace(position:bird.position,center:bird.pointerFollowCenter,frame:bird.frameName,
                    revision:bird.motionRevision,events:e.events.map{"\($0.sequence):\($0.time):\($0.type):\($0.reason?.rawValue ?? "")"},
                    active:e.activeRunCount,leased:e.leasedBirdCount))
            }
            XCTAssertTrue(e.events.contains{$0.type == .completed && $0.kind == .pointerVisit})
            return trace
        }
        let reference=try replay(hz:60)
        XCTAssertEqual(try replay(hz:30),reference);XCTAssertEqual(try replay(hz:120),reference)
    }
}
