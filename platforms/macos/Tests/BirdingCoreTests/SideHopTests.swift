import XCTest
@testable import BirdingCore

final class SideHopTests:XCTestCase {
    private let display=CGRect(x:-1200,y:-400,width:2400,height:1400)
    private let host=Surface(id:151,pid:23,rect:CGRect(x:-900,y:500,width:1800,height:300))

    private func fixture(host custom:Surface?=nil,scale:CGFloat=1,fraction:CGFloat=0.5) -> BehaviorEngine {
        var settings=BirdSettings();settings.pointerVisits=false;settings.flockPasses=false
        settings.ambientLeafPlayEnabled=false;settings.sideHopEnabled=true
        let e=BehaviorEngine(seed:731,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let surface=custom ?? host
        let frames=SideHopPlan.requiredFrames.union(["blink","breathe","idle0","idle1","idle2"])
            .union((0...7).map{"fly\($0)"})
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[surface],scale:scale,
            pointer:CGPoint(x:-1100,y:-300),availableFrames:[.treeSparrow:frames]))
        let bird=Bird(position:.zero,fraction:fraction,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:surface,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
        e.installFixtureBirds([bird]);advance(e,seconds:0.5)
        return e
    }
    private func advance(_ e:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    private func pointer(_ p:CGPoint,in e:BehaviorEngine) {
        var world=e.world;world.pointer=p;e.updateWorld(world)
    }
    private func nearPointer(in e:BehaviorEngine,right:Bool=false) {
        let bird=e.birds[0],scale=e.spriteScale(for:bird)
        pointer(CGPoint(x:bird.position.x+(right ? 20:-20)*scale,y:bird.position.y-8*scale),in:e)
    }
    private func started(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let run)=result else {
            XCTFail("Expected side hop start, got \(result)",file:file,line:line)
            throw NSError(domain:"SideHopTests",code:1)
        }
        return run
    }
    private func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    private func terminal(_ e:BehaviorEngine,_ run:BehaviorRunID,_ type:BehaviorEventType,
                          _ reason:BehaviorReason?=nil,file:StaticString=#filePath,line:UInt=#line) {
        let events=terminals(e,run)
        XCTAssertEqual(events.count,1,file:file,line:line)
        XCTAssertEqual(events.first?.type,type,file:file,line:line)
        XCTAssertEqual(events.first?.reason,reason,file:file,line:line)
        XCTAssertNil(e.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(run),file:file,line:line)
    }
    private func fraction(at x:CGFloat,on surface:Surface) -> CGFloat {
        (x-Geometry.perchX(0,rect:surface.rect))/(Geometry.perchX(1,rect:surface.rect)-Geometry.perchX(0,rect:surface.rect))
    }

    func testLifecycleMovesActualAnchorAndFractionThroughOneLowContinuousArch() throws {
        for scale:CGFloat in [0.75,1,2] {
            let e=fixture(scale:scale),bird=e.birds[0],origin=bird.position,oldFraction=bird.fraction
            let size=e.spriteScale(for:bird),id=try XCTUnwrap(e.id(of:bird))
            nearPointer(in:e)
            let run=try started(e.handle(.sideHop(.preview)))
            XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.fraction,oldFraction)
            XCTAssertEqual(e.behavior(of:bird),.sideHop)
            XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
            XCTAssertEqual(e.reservedLandingCount,1);XCTAssertFalse(e.ambientBusy)
            XCTAssertEqual(e.runtime.owners[id],run)
            XCTAssertEqual(e.requestSideHop(source:.preview,target:id),.rejected(.busy))
            let slot=try XCTUnwrap(e.runtime.landingReservations.first)
            let target=try XCTUnwrap(slot.point(in:e))
            XCTAssertGreaterThanOrEqual(target.x-origin.x,60*size-0.001)
            XCTAssertLessThanOrEqual(target.x-origin.x,110*size+0.001)
            var last=origin,minY=origin.y,frames=Set<String>(),airborneSteps=0
            for _ in 0..<120 {
                if e.runtime.runs[run] != nil {
                    let pose=try XCTUnwrap(e.renderSnapshot().first)
                    frames.insert(pose.frameName)
                    XCTAssertEqual(pose.position,bird.position);XCTAssertEqual(pose.hopOffset,0)
                    XCTAssertFalse(pose.frameName.hasPrefix("fly"));XCTAssertFalse(bird.isGliding)
                    XCTAssertEqual(e.bounds(of:bird),pose.rect.insetBy(dx:-2,dy:-2))
                    if bird.state == .flying {
                        airborneSteps+=1
                        XCTAssertGreaterThanOrEqual(bird.fraction,oldFraction)
                        XCTAssertLessThanOrEqual(bird.fraction,slot.fraction+0.000001)
                    }
                }
                e.advance(BehaviorEngine.step)
                XCTAssertGreaterThanOrEqual(bird.position.x,last.x-0.000001)
                XCTAssertLessThan(Geometry.distance(bird.position,last),20*size)
                minY=min(minY,bird.position.y);last=bird.position
            }
            XCTAssertGreaterThan(airborneSteps,10);XCTAssertLessThan(airborneSteps,30)
            XCTAssertLessThan(minY,origin.y-8*size);XCTAssertGreaterThanOrEqual(minY,origin.y-12*size-0.001)
            XCTAssertEqual(bird.position,target);XCTAssertEqual(bird.fraction,slot.fraction)
            XCTAssertNotEqual(bird.fraction,oldFraction);XCTAssertEqual(bird.hostID,host.id)
            XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.landedCount,1)
            XCTAssertTrue(Set(["stand","land0","land1","land2"]).isSubset(of:frames))
            terminal(e,run,.completed)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertGreaterThan(e.ecology(of:bird)?.cooldowns[.sideHop] ?? 0,20)
            advance(e,seconds:2);terminal(e,run,.completed)
        }
    }

    func testOnlyBirdTickAdvancesHopAndMetadataOrExecutionNeverIntegrateIt() throws {
        let e=fixture(),bird=e.birds[0],origin=bird.position
        let run=try started(e.requestSideHop(source:.preview))
        let execution=try XCTUnwrap(e.runtime.runs[run]?.execution)
        for _ in 0..<20 {
            _=execution.validate(in:e);_=execution.advance(0.1,in:e)
            e.updateWorld(e.world,sampleDT:0.1);_=e.renderSnapshot()
            XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.stateTime,0)
        }
        bird.tick(BehaviorEngine.step)
        XCTAssertGreaterThan(bird.position.x,origin.x);XCTAssertLessThan(bird.position.y,origin.y)
        XCTAssertEqual(e.runtime.runs[run]?.age,0)
    }

    func testAutomaticDirectionNearPointerCooldownAndPreviewDistanceException() throws {
        for right in [false,true] {
            let e=fixture(),bird=e.birds[0],origin=bird.position
            XCTAssertEqual(e.requestSideHop(source:.automatic),.rejected(.pointerMoved))
            nearPointer(in:e,right:right)
            let initialPointer=e.world.pointer,id=try XCTUnwrap(e.id(of:bird))
            XCTAssertTrue(e.sideHopCandidate(id))
            let run=try started(e.requestSideHop(source:.automatic,target:id))
            advance(e,seconds:0.2)
            XCTAssertTrue(terminals(e,run).isEmpty,"A stationary near pointer must not cancel a hop")
            advance(e,seconds:1.3);terminal(e,run,.completed)
            XCTAssertEqual(bird.position.x>origin.x,!right)
            XCTAssertGreaterThan(Geometry.distance(bird.position,initialPointer),Geometry.distance(origin,initialPointer))
            nearPointer(in:e,right:right)
            XCTAssertEqual(e.requestSideHop(source:.automatic,target:id),.rejected(.unavailableBird))
            pointer(CGPoint(x:-1100,y:-300),in:e)
            let preview=try started(e.requestSideHop(source:.preview,target:id))
            advance(e,seconds:1.5);terminal(e,preview,.completed)
        }
        let disturbed=fixture(),id=try XCTUnwrap(disturbed.id(of:disturbed.birds[0]))
        nearPointer(in:disturbed);disturbed.perchPlanner.rhythms[id]?.disturbance=0.6
        XCTAssertEqual(disturbed.requestSideHop(source:.automatic,target:id),.rejected(.unavailableBird))
        disturbed.perchPlanner.rhythms[id]?.disturbance=0.59
        XCTAssertTrue(disturbed.sideHopCandidate(id))
    }

    func testPointerMovingAheadCancelsOnceWithoutChasingOrReversing() throws {
        let e=fixture(),bird=e.birds[0],origin=bird.position
        nearPointer(in:e)
        let run=try started(e.requestSideHop(source:.automatic))
        advance(e,seconds:0.1)
        let actual=bird.position,target=try XCTUnwrap(e.runtime.landingReservations.first?.point(in:e))
        // Subthreshold movement on the original side is harmless.
        pointer(CGPoint(x:e.world.pointer.x+5,y:e.world.pointer.y),in:e)
        XCTAssertTrue(terminals(e,run).isEmpty)
        pointer(CGPoint(x:target.x+40,y:target.y),in:e)
        terminal(e,run,.cancelled,.pointerMoved)
        XCTAssertEqual(bird.position,actual);XCTAssertNotEqual(actual,origin)
        XCTAssertTrue(bird.needsDestination);XCTAssertFalse(bird.isSideHopping)
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        advance(e,seconds:1);XCTAssertEqual(bird.position,actual)
        XCTAssertTrue(e.route(bird,avoiding:actual));XCTAssertEqual(bird.position,actual)
        advance(e,seconds:0.1);XCTAssertNotEqual(bird.position,actual)
        terminal(e,run,.cancelled,.pointerMoved)
    }

    func testNarrowEdgeRejectsAndBoundedShorterCandidateFitsWithoutReversing() throws {
        let narrow=Surface(id:host.id,pid:host.pid,rect:CGRect(x:-60,y:500,width:90,height:200))
        let e=fixture(host:narrow),bird=e.birds[0],origin=bird.position
        XCTAssertEqual(e.requestSideHop(source:.preview),.rejected(.noSpace))
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        XCTAssertEqual(bird.position,origin)
        let size=e.spriteScale(for:bird)
        let shorter=Surface(id:host.id,pid:host.pid,rect:CGRect(x:-200,y:500,width:84+160*size,height:200))
        let fits=fixture(host:shorter),start=fits.birds[0].position
        let run=try started(fits.requestSideHop(source:.preview))
        let end=try XCTUnwrap(fits.runtime.landingReservations.first?.point(in:fits))
        XCTAssertEqual(end.x-start.x,60*size,accuracy:0.001)
        advance(fits,seconds:1.5);terminal(fits,run,.completed)
    }

    func testWholeArcRejectsThinOverheadBlockerEvenWithVisibleEndpoints() throws {
        for targetOnly in [false,true] {
            let e=fixture(),bird=e.birds[0],start=bird.position,size=e.spriteScale(for:bird)
            let clear=try XCTUnwrap(SideHopPlan.make(id:try XCTUnwrap(e.id(of:bird)),in:e))
            var world=e.world
            let rect=targetOnly ? CGRect(x:start.x+55*size,y:start.y-30*size,width:100*size,height:40*size):
                CGRect(x:start.x+30*size,y:start.y-49*size,width:size,height:2*size)
            world.surfaces.insert(Surface(id:152,rect:rect),at:0);e.updateWorld(world)
            XCTAssertTrue(Geometry.isLandingVisible(on:host.id,at:start,surfaces:world.surfaces,scale:size))
            if !targetOnly {XCTAssertTrue(clear.destination.isValid(in:e),"Only the low arc, not the landing slot, is occluded")}
            XCTAssertEqual(e.requestSideHop(source:.preview),.rejected(.noSpace))
            XCTAssertEqual(bird.position,start);XCTAssertEqual(e.leasedBirdCount,0)
        }
    }

    func testLatePathOcclusionAndOtherBirdIntrusionReleaseAtActualPosition() throws {
        for intruder in [false,true] {
            let e=fixture(),bird=e.birds[0],size=e.spriteScale(for:bird)
            let run=try started(e.requestSideHop(source:.preview));advance(e,seconds:0.1)
            let actual=bird.position
            if intruder {
                let other=Bird(position:actual,fraction:0.9,profile:bird.profile,random:{0.5})
                e.register(other);e.updateWorld(e.world)
            } else {
                var world=e.world
                world.surfaces.insert(Surface(id:152,rect:CGRect(x:actual.x+5*size,y:host.rect.minY-49*size,width:size,height:2*size)),at:0)
                e.updateWorld(world)
            }
            terminal(e,run,.failed,.targetInvalid)
            XCTAssertEqual(bird.position,actual);XCTAssertTrue(bird.needsDestination)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
    }

    private final class SlotExecution:BehaviorExecution {
        let kind:BehaviorKind = .relocate
        let occupiesEncounter=false,runsWhilePaused=false,timeout=10.0
        let landingReservations:[LandingReservation]
        var participants:[BirdID] {landingReservations.map(\.bird)}
        init(_ slot:LandingReservation) {landingReservations=[slot]}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }
    private func distantBird(in e:BehaviorEngine) -> Bird {
        let other=Bird(position:CGPoint(x:-1000,y:-200),fraction:0.95,profile:e.birds[0].profile,random:{0.5})
        e.register(other);return other
    }
    func testForeignReservationsProtectWholeCorridorAndReleaseWithTheirRun() throws {
        let e=fixture(),bird=e.birds[0],other=distantBird(in:e),size=e.spriteScale(for:bird)
        let slot=LandingReservation(bird:try XCTUnwrap(e.id(of:other)),host:host,
            fraction:fraction(at:bird.position.x+50*size,on:host))
        let foreign=try started(e.runtime.start(SlotExecution(slot),source:.preview,in:e))
        // Target the hopping bird; the slot owner is independently busy and
        // should not determine the reason for this geometry-specific request.
        XCTAssertEqual(e.requestSideHop(source:.preview,target:e.id(of:bird)),.rejected(.noSpace))
        XCTAssertEqual(e.leasedBirdCount,1);XCTAssertEqual(e.reservedLandingCount,1)
        e.runtime.cancel(foreign,reason:.removed,in:e)
        let run=try started(e.requestSideHop(source:.preview))
        advance(e,seconds:0.1)
        let actual=bird.position
        // This slot misses the hop destination, so the runtime can accept it;
        // the hop's whole-corridor check must still catch it before another tick.
        let behind=LandingReservation(bird:try XCTUnwrap(e.id(of:other)),host:host,
            fraction:fraction(at:-30*size,on:host))
        let late=try started(e.runtime.start(SlotExecution(behind),source:.preview,in:e))
        e.updateWorld(e.world)
        terminal(e,run,.failed,.targetInvalid);XCTAssertEqual(bird.position,actual)
        XCTAssertEqual(e.reservedLandingCount,1)
        e.runtime.cancel(late,reason:.removed,in:e);XCTAssertEqual(e.reservedLandingCount,0)
    }

    func testOrdinaryArrivalFarAwayStillReservesItsPlannedLandingCorridor() throws {
        let e=fixture(),bird=e.birds[0],origin=bird.position,other=distantBird(in:e)
        let size=e.spriteScale(for:bird)
        other.fraction=fraction(at:origin.x+50*size,on:host)
        other.fly(to:Geometry.foot(on:host,fraction:other.fraction,edge:.top,scale:size),
            host:host,duration:8,allowsOrbit:false,random:{0.5})
        XCTAssertGreaterThan(Geometry.distance(other.position,origin),500)
        XCTAssertEqual(e.reservedLandingCount,0)
        XCTAssertEqual(e.requestSideHop(source:.preview),.rejected(.noSpace))
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(e.leasedBirdCount,0)
        other.fraction=0.95
        other.fly(to:Geometry.foot(on:host,fraction:other.fraction,edge:.top,scale:size),
            host:host,duration:8,allowsOrbit:false,random:{0.5})
        XCTAssertTrue(e.requestSideHop(source:.preview).accepted)
    }

    func testPauseFreezesMotionAndGentleMetadataUsesActualSamplingInterval() throws {
        for sampleDT in [0.1,1.0] {
            let e=fixture(),bird=e.birds[0]
            let run=try started(e.requestSideHop(source:.preview));advance(e,seconds:0.1)
            e.handle(.pause(true))
            let actual=bird.position,stateTime=bird.stateTime,age=e.runtime.runs[run]?.age
            var world=e.world;world.surfaces[0].rect.origin.x+=20;world.surfaces[0].rect.origin.y+=3
            e.updateWorld(world,sampleDT:sampleDT)
            advance(e,seconds:3)
            XCTAssertEqual(bird.position,actual);XCTAssertEqual(bird.stateTime,stateTime)
            XCTAssertEqual(e.runtime.runs[run]?.age,age);XCTAssertTrue(terminals(e,run).isEmpty)
            XCTAssertEqual(e.requestSideHop(source:.preview),.rejected(.paused))
            e.handle(.pause(false));e.advance(BehaviorEngine.step)
            XCTAssertLessThan(Geometry.distance(bird.position,actual),20)
            advance(e,seconds:1.5);terminal(e,run,.completed)
            let moved=world.surfaces[0]
            XCTAssertEqual(bird.position,Geometry.foot(on:moved,fraction:bird.fraction,edge:.top,scale:e.spriteScale(for:bird)))
        }
    }

    func testInvalidHostScaleDisplayAndFramesFailWhilePausedWithoutTeleporting() throws {
        for scenario in ["removed","pid","resize","scale","display","workArea","fast","frames"] {
            let e=fixture(),bird=e.birds[0]
            let run=try started(e.requestSideHop(source:.preview));advance(e,seconds:0.1)
            e.handle(.pause(true));let actual=bird.position
            var world=e.world
            switch scenario {
            case "removed":world.surfaces=[]
            case "pid":world.surfaces=[Surface(id:host.id,pid:host.pid+1,rect:host.rect)]
            case "resize":world.surfaces[0].rect.size.width-=10
            case "scale":world.scale*=1.1
            case "display":world.displays[0].origin.x+=1
            case "workArea":world.screens[0].size.height-=1
            case "fast":world.surfaces[0].rect.origin.x+=30
            default:world.availableFrames[bird.profile.id]?.remove("land1")
            }
            e.updateWorld(world,sampleDT:BehaviorEngine.step)
            terminal(e,run,.failed,scenario == "frames" ? .missingFrames:.targetInvalid)
            XCTAssertEqual(bird.position,actual);XCTAssertTrue(bird.needsDestination)
            XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            advance(e,seconds:2);XCTAssertEqual(bird.position,actual)
        }
    }

    func testClickCancelAndRelocateStartAtCurrentAnchorWithOneTerminal() throws {
        for sampled in [false,true] {
            let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:e.birds[0]))
            let run=try started(e.requestSideHop(source:.preview));advance(e,seconds:0.1)
            let actual=bird.position
            if sampled {
                e.handle(.pause(true));var world=e.world;world.buttonsDown=true;e.updateWorld(world)
            } else {e.handle(.pointerClick)}
            terminal(e,run,.cancelled,.userInput)
            XCTAssertEqual(bird.position,actual);XCTAssertTrue(bird.needsDestination)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            let relocated=try started(e.handle(.relocate(id)))
            XCTAssertEqual(bird.position,actual);XCTAssertEqual(e.runtime.owners[id],relocated)
            XCTAssertFalse(bird.isSideHopping)
            advance(e,seconds:10);terminal(e,relocated,.completed)
            terminal(e,run,.cancelled,.userInput)
            XCTAssertGreaterThan(Geometry.distance(bird.position,actual),100)
        }
    }

    func testMissingFramesSettingsAndUnsettledOrBusyBirdCannotStart() throws {
        for missing in SideHopPlan.requiredFrames {
            let e=fixture(),bird=e.birds[0],actual=bird.position
            var world=e.world;world.availableFrames[bird.profile.id]?.remove(missing);e.updateWorld(world)
            XCTAssertEqual(e.requestSideHop(source:.preview),.rejected(.missingFrames))
            XCTAssertEqual(bird.position,actual);XCTAssertEqual(e.leasedBirdCount,0)
        }
        for master in [false,true] {
            let e=fixture(),bird=e.birds[0]
            let run=try started(e.requestSideHop(source:.preview));advance(e,seconds:0.1)
            let actual=bird.position;var settings=e.settings
            if master {settings.perchActions=false} else {settings.sideHopEnabled=false}
            e.applySettings(settings);terminal(e,run,.cancelled,.settingsChanged)
            XCTAssertEqual(bird.position,actual);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertEqual(e.requestSideHop(source:.preview),.rejected(.disabled))
        }
        let e=fixture(),bird=e.birds[0]
        bird.perch(on:host)
        XCTAssertEqual(e.requestSideHop(source:.preview),.rejected(.unavailableBird))
        advance(e,seconds:0.5)
        let slot=LandingReservation(bird:try XCTUnwrap(e.id(of:bird)),host:host,fraction:0.1)
        _=try started(e.runtime.start(SlotExecution(slot),source:.preview,in:e))
        XCTAssertEqual(e.requestSideHop(source:.automatic),.rejected(.busy))
    }

    func testNegativeCoordinateGroundUsesRealFootAnchorAndIgnoresNormalWindows() throws {
        let ground=Geometry.ground(id:999,display:display,workArea:display)
        let e=fixture(host:ground,scale:2,fraction:0.3),bird=e.birds[0],scale=e.spriteScale(for:bird)
        let origin=bird.position
        XCTAssertLessThan(origin.x,0);XCTAssertEqual(origin.y,display.maxY-9*scale)
        var world=e.world
        world.surfaces.insert(Surface(id:61,rect:display),at:0);e.updateWorld(world)
        let run=try started(e.requestSideHop(source:.preview))
        let target=try XCTUnwrap(e.runtime.landingReservations.first?.point(in:e))
        advance(e,seconds:1.5);terminal(e,run,.completed)
        XCTAssertEqual(bird.position,target);XCTAssertEqual(target.y,origin.y)
        XCTAssertEqual(bird.position,Geometry.foot(on:ground,fraction:bird.fraction,edge:.top,scale:scale))
        XCTAssertTrue(display.contains(Geometry.landingFootprint(at:bird.position,scale:scale)))
    }

    func testReplayMatchesAt30And60And120HzAcrossPauseCancellationAndRecovery() throws {
        struct Trace:Equatable {
            let position:CGPoint,fraction:CGFloat,frame:String
            let counts:[Int],events:[String]
        }
        func replay(_ hz:Int) throws -> [Trace] {
            let e=fixture(),bird=e.birds[0]
            var trace:[Trace]=[]
            nearPointer(in:e)
            _=try started(e.requestSideHop(source:.preview))
            for part in 0..<20 {
                if part==1 {e.handle(.pause(true))}
                if part==4 {e.handle(.pause(false))}
                if part==5 {
                    e.handle(.pointerClick)
                    _=try started(e.handle(.relocate(try XCTUnwrap(e.id(of:bird)))))
                }
                advance(e,seconds:0.1,hz:hz)
                trace.append(Trace(position:bird.position,fraction:bird.fraction,frame:e.renderSnapshot().first!.frameName,
                    counts:[e.activeRunCount,e.leasedBirdCount,e.reservedLandingCount],
                    events:e.events.map{"\($0.time):\($0.type):\($0.kind?.rawValue ?? ""):\($0.reason?.rawValue ?? "")"}))
            }
            return trace
        }
        let reference=try replay(60)
        XCTAssertEqual(try replay(30),reference);XCTAssertEqual(try replay(120),reference)
    }
}
