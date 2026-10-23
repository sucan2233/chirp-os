import XCTest
@testable import BirdingCore

final class TakeoffPreparationTests:XCTestCase {
    private let screen=CGRect(x:-1000,y:-400,width:2800,height:1800)
    private let sourceHost=Surface(id:181,pid:31,rect:CGRect(x:-800,y:700,width:850,height:400))
    private let targetHost=Surface(id:182,pid:32,rect:CGRect(x:400,y:500,width:1000,height:500))
    private var frames:Set<String> {Set(["stand"]+(0...7).map{"fly\($0)"})}

    private func fixture(ground:Bool=false,due:Bool=true) -> BehaviorEngine {
        let e=BehaviorEngine(seed:615)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let work=screen.insetBy(dx:0,dy:60)
        let surfaces=ground ? [Geometry.ground(id:183,display:screen,workArea:work)]:[sourceHost,targetHost]
        e.updateWorld(BehaviorWorld(screens:[work],displays:[screen],surfaces:surfaces,
            pointer:CGPoint(x:-950,y:-300),availableFrames:Dictionary(uniqueKeysWithValues:
                SpeciesID.allCases.map{($0,frames)})))
        let bird=Bird(position:.zero,fraction:0.35,
            profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
        bird.perch(on:surfaces[0],spriteScale:e.spriteScale(for:bird))
        bird.perchDuration=due ? 0:600
        e.installFixtureBirds([bird]);return e
    }

    private func destination(_ e:BehaviorEngine,host:Surface?=nil,fraction:CGFloat=0.65) -> DestinationPlan {
        let host=host ?? e.world.surfaces.last!,bird=e.birds[0]
        return DestinationPlan(point:Geometry.foot(on:host,fraction:fraction,edge:.top,scale:e.spriteScale(for:bird)),
            host:host,fraction:fraction,edge:.top,duration:3.2,arc:70,
            airspace:e.world.screens[0].insetBy(dx:60,dy:60),urgent:false)
    }

    private func started(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let run)=result else {
            XCTFail("Expected preparation, got \(result)",file:file,line:line)
            throw NSError(domain:"TakeoffPreparationTests",code:1)
        }
        return run
    }

    private func start(_ e:BehaviorEngine,plan:DestinationPlan?=nil,source:BehaviorSource = .automatic) throws -> BehaviorRunID {
        try started(e.prepareTakeoff(id:e.id(of:e.birds[0])!,plan:plan ?? destination(e),source:source))
    }

    private func advance(_ e:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }

    private func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }

    private func released(_ e:BehaviorEngine,_ run:BehaviorRunID,type:BehaviorEventType,
                          reason:BehaviorReason?=nil,file:StaticString=#filePath,line:UInt=#line) {
        let terminal=terminals(e,run)
        XCTAssertEqual(terminal.count,1,file:file,line:line)
        XCTAssertEqual(terminal.first?.type,type,file:file,line:line)
        XCTAssertEqual(terminal.first?.reason,reason,file:file,line:line)
        XCTAssertNil(e.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
    }

    func testDefinitionUsesExistingStandingAndFlightFramesWithoutEncounterSlot() {
        let definition=BehaviorDefinitions.definition(for:.takeoffPreparation)
        XCTAssertEqual(definition.requiredCapabilities,[.standing,.flight])
        XCTAssertEqual(definition.requiredFrames,frames)
        XCTAssertFalse(definition.occupiesEncounter);XCTAssertFalse(definition.runsWhilePaused)
        XCTAssertEqual(definition.priority,30);XCTAssertEqual(definition.cooldown,4)
        XCTAssertTrue(BirdSettings().takeoffPreparationEnabled)
    }

    func testExpiredDwellReallyWaitsThenOpensWingsAndLaunchesAtExactlyFortyFiveHundredths() throws {
        let e=fixture(),bird=e.birds[0],origin=bird.position,revision=bird.motionRevision
        bird.facingRight=false
        XCTAssertTrue(bird.needsDestination)
        let run=try start(e)
        XCTAssertEqual(e.behavior(of:bird),.takeoffPreparation)
        XCTAssertEqual(e.leasedBirdCount,1);XCTAssertEqual(e.reservedLandingCount,1)
        XCTAssertFalse(e.ambientBusy);XCTAssertEqual(e.scenePropCount,0)
        XCTAssertTrue(try XCTUnwrap(e.renderSnapshot().first).facingRight)
        XCTAssertFalse(bird.facingRight,"Orientation is a pose until normal flight takes over")
        for step in 0..<27 {
            let pose=try XCTUnwrap(e.renderSnapshot().first)
            XCTAssertEqual(pose.frameName,step<18 ? "stand":"fly0")
            XCTAssertEqual(pose.hopOffset,0);XCTAssertEqual(pose.position,origin)
            XCTAssertEqual(pose.rect.minY+39*pose.scale,origin.y,accuracy:0.000001)
            XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertEqual(bird.state,.perched);XCTAssertTrue(bird.needsDestination)
            XCTAssertTrue(terminals(e,run).isEmpty)
            e.advance(BehaviorEngine.step)
        }
        released(e,run,type:.completed)
        XCTAssertEqual(try XCTUnwrap(terminals(e,run).first).time,0.45,accuracy:0.000001)
        XCTAssertEqual(bird.state,.flying);XCTAssertEqual(bird.hostID,targetHost.id)
        XCTAssertEqual(bird.motionRevision,revision+1)
        XCTAssertEqual(bird.stateTime,BehaviorEngine.step,accuracy:0.000001,"Only the engine ticks the new flight")
        XCTAssertNil(e.behavior(of:bird));XCTAssertNotEqual(bird.position,origin)
        advance(e,seconds:30)
        released(e,run,type:.completed)
        XCTAssertEqual(bird.state,.perched)
        XCTAssertEqual(bird.position,destination(e).point)
    }

    func testAcceptedPlanConsumesNoExtraFlightRandomnessAndUsesNormalSingleTick() throws {
        let e=fixture(),control=fixture(),plan=destination(e)
        _=try start(e,plan:plan)
        for _ in 0..<26 {e.advance(BehaviorEngine.step)}
        plan.apply(to:control.birds[0],random:control.random)
        control.birds[0].tick(BehaviorEngine.step)
        e.advance(BehaviorEngine.step)
        let actual=e.birds[0],expected=control.birds[0]
        XCTAssertEqual(actual.position,expected.position)
        XCTAssertEqual(actual.stateTime,expected.stateTime)
        XCTAssertEqual(actual.flightDuration,expected.flightDuration)
        XCTAssertEqual(actual.frameName,expected.frameName)
        XCTAssertEqual(e.random.unit(),control.random.unit(),"No destination redraw or duplicate apply")
    }

    func testNaturalRouterWaitsButMissingFramesFallsThroughWithoutRejectedEvent() throws {
        let e=fixture(),bird=e.birds[0],origin=bird.position
        e.autonomousRouting=true;e.advance(BehaviorEngine.step)
        XCTAssertEqual(e.behavior(of:bird),.takeoffPreparation)
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.state,.perched)
        let run=try XCTUnwrap(e.events.first{$0.kind == .takeoffPreparation && $0.type == .started}?.runID)
        advance(e,seconds:26.0/60)
        XCTAssertEqual(bird.state,.perched)
        e.advance(BehaviorEngine.step);XCTAssertEqual(bird.state,.flying)
        released(e,run,type:.completed)

        let fallback=fixture(),model=fallback.birds[0],before=model.motionRevision
        var world=fallback.world;world.availableFrames=[:];fallback.updateWorld(world)
        fallback.autonomousRouting=true;fallback.advance(BehaviorEngine.step)
        XCTAssertEqual(model.state,.flying);XCTAssertEqual(model.motionRevision,before+1)
        XCTAssertEqual(fallback.activeRunCount,0);XCTAssertEqual(fallback.reservedLandingCount,0)
        XCTAssertFalse(fallback.events.contains{$0.kind == .takeoffPreparation})
    }

    func testExplicitRequestAndCommandStartAndRejectWithUsefulReasons() throws {
        for command in [false,true] {
            let e=fixture(),id=e.id(of:e.birds[0])!
            let result=command ? e.handle(.prepareTakeoff(.preview)):e.requestTakeoffPreparation(source:.preview,target:id)
            let run=try started(result)
            XCTAssertEqual(e.events.first{$0.runID==run}?.source,.preview)
            XCTAssertEqual(e.requestTakeoffPreparation(source:.preview,target:id),.rejected(.busy))
            advance(e,seconds:0.45);released(e,run,type:.completed)
        }
        let e=fixture()
        XCTAssertEqual(e.requestTakeoffPreparation(source:.preview,target:BirdID(999)),.rejected(.missingBird))
        XCTAssertEqual(e.events.last?.type,.rejected);XCTAssertEqual(e.events.last?.reason,.missingBird)
    }

    func testWorldSyncAndRenderingCannotAdvancePreparationOrLaunch() throws {
        let e=fixture(),bird=e.birds[0],revision=bird.motionRevision,origin=bird.position
        let run=try start(e)
        for _ in 0..<50 {e.updateWorld(e.world);_=e.renderSnapshot();_=e.bounds(of:bird)}
        XCTAssertEqual(e.time,0);XCTAssertEqual(bird.position,origin)
        XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(bird.stateTime,0)
        XCTAssertEqual(e.runtime.runs[run]?.age,0)
        XCTAssertEqual(e.renderSnapshot().first?.frameName,"stand")
        advance(e,seconds:0.30)
        for _ in 0..<50 {e.updateWorld(e.world);_=e.renderSnapshot()}
        XCTAssertEqual(e.renderSnapshot().first?.frameName,"fly0")
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,origin)
        XCTAssertTrue(terminals(e,run).isEmpty)
    }

    func testGentleHostMovementKeepsLiveFeetAndRefreshesDestinationBeforeApply() throws {
        let e=fixture(),bird=e.birds[0],control=fixture(),original=destination(e)
        let run=try start(e,plan:original),revision=bird.motionRevision
        advance(e,seconds:0.2)
        var world=e.world
        world.surfaces[0].rect=sourceHost.rect.offsetBy(dx:12,dy:4)
        world.surfaces[1].rect=targetHost.rect.offsetBy(dx:36,dy:-12)
        e.updateWorld(world,sampleDT:0.1)
        let liveSource=Geometry.foot(on:world.surfaces[0],fraction:bird.fraction,edge:.top,scale:e.spriteScale(for:bird))
        let liveTarget=Geometry.foot(on:world.surfaces[1],fraction:original.fraction,edge:.top,scale:e.spriteScale(for:bird))
        XCTAssertEqual(bird.position,liveSource);XCTAssertEqual(bird.motionRevision,revision)
        XCTAssertNotEqual(liveTarget,original.point)
        XCTAssertEqual(e.renderSnapshot().first?.position,liveSource)
        XCTAssertEqual(e.runtime.landingReservations.first?.point(in:e),liveTarget)
        advance(e,seconds:14.0/60)
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,liveSource)
        control.birds[0].position=liveSource
        let refreshed=DestinationPlan(point:liveTarget,host:world.surfaces[1],fraction:original.fraction,edge:.top,
            duration:original.duration,arc:original.arc,airspace:original.airspace,urgent:false)
        refreshed.apply(to:control.birds[0],random:control.random);control.birds[0].tick(BehaviorEngine.step)
        e.advance(BehaviorEngine.step)
        released(e,run,type:.completed)
        XCTAssertEqual(bird.position,control.birds[0].position,"Flight must begin at the moved source, exactly one tick old")
        advance(e,seconds:30)
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,liveTarget)
    }

    func testPauseFreezesRemainingPreparationAndResumesAtTheSameStep() throws {
        let e=fixture(),bird=e.birds[0],run=try start(e)
        advance(e,seconds:0.2)
        let age=e.runtime.runs[run]?.age,stateTime=bird.stateTime,pose=try XCTUnwrap(e.renderSnapshot().first)
        e.handle(.pause(true));advance(e,seconds:4)
        XCTAssertEqual(e.runtime.runs[run]?.age,age);XCTAssertEqual(bird.stateTime,stateTime)
        XCTAssertEqual(e.renderSnapshot().first?.frameName,pose.frameName)
        XCTAssertEqual(e.renderSnapshot().first?.facingRight,pose.facingRight)
        XCTAssertEqual(e.renderSnapshot().first?.hopOffset,pose.hopOffset)
        XCTAssertEqual(e.renderSnapshot().first?.position,pose.position)
        XCTAssertEqual(e.requestTakeoffPreparation(source:.preview),.rejected(.paused))
        e.handle(.pause(false));advance(e,seconds:14.0/60)
        XCTAssertEqual(bird.state,.perched);e.advance(BehaviorEngine.step)
        released(e,run,type:.completed)
        XCTAssertEqual(try XCTUnwrap(terminals(e,run).first).time,4.45,accuracy:0.000001)
    }

    func testSourceAndTargetInvalidationReleaseImmediatelyEvenWhilePaused() throws {
        for change in ["sourceRemoved","sourcePID","targetRemoved","targetPID","sourceLayer","targetLayer",
                       "sourceCovered","targetCovered","scale","display","workArea","fraction","position","revision","frames"] {
            let e=fixture(),bird=e.birds[0],run=try start(e)
            advance(e,seconds:0.2);e.handle(.pause(true))
            let time=e.time
            var world=e.world
            switch change {
            case "sourceRemoved":world.surfaces.removeFirst()
            case "sourcePID":world.surfaces[0]=Surface(id:sourceHost.id,pid:99,rect:sourceHost.rect)
            case "targetRemoved":world.surfaces.removeLast()
            case "targetPID":world.surfaces[1]=Surface(id:targetHost.id,pid:99,rect:targetHost.rect)
            case "sourceLayer":world.surfaces[0]=Surface(id:sourceHost.id,pid:sourceHost.pid,rect:sourceHost.rect,layer:1)
            case "targetLayer":world.surfaces[1]=Surface(id:targetHost.id,pid:targetHost.pid,rect:targetHost.rect,layer:1)
            case "sourceCovered","targetCovered":
                let point=change == "sourceCovered" ? bird.position:destination(e).point
                world.surfaces.insert(Surface(id:184,rect:Geometry.landingFootprint(at:point,scale:2)),at:0)
            case "scale":world.scale*=1.1
            case "display":world.displays=[screen.offsetBy(dx:1,dy:0)]
            case "workArea":world.screens[0]=world.screens[0].insetBy(dx:0,dy:10)
            case "fraction":bird.fraction+=0.05
            case "position":bird.position.x+=20
            case "revision":bird.perch(on:sourceHost,spriteScale:e.spriteScale(for:bird))
            default:world.availableFrames[bird.profile.id]?.remove("fly0")
            }
            let position=bird.position,revision=bird.motionRevision
            e.updateWorld(world)
            released(e,run,type:.failed,reason:change == "frames" ? .missingFrames:.targetInvalid)
            XCTAssertEqual(e.time,time);XCTAssertEqual(bird.position,position)
            XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(bird.state,.perched)
            e.updateWorld(world);advance(e,seconds:1)
            XCTAssertEqual(terminals(e,run).count,1)
        }
    }

    func testClicksRelocationScatterAndHostStartlePreemptWithoutWaitingOrRestoring() throws {
        for input in ["click","buttons","pausedButtons","relocate","route","scatter","startle"] {
            let e=fixture(),bird=e.birds[0],id=e.id(of:e.birds[0])!,run=try start(e)
            advance(e,seconds:0.2)
            var world=e.world;world.surfaces[0].rect.origin.x+=10
            e.updateWorld(world,sampleDT:0.1)
            let position=bird.position,revision=bird.motionRevision
            switch input {
            case "click":e.handle(.pointerClick)
            case "buttons","pausedButtons":
                if input == "pausedButtons" {e.handle(.pause(true))}
                world.buttonsDown=true;e.updateWorld(world)
            case "relocate":_=try started(e.handle(.relocate(id)))
            case "route":XCTAssertTrue(e.route(bird,avoiding:bird.position))
            case "scatter":e.handle(.scatter)
            default:
                world.surfaces[0].rect.origin.x+=100
                e.updateWorld(world,sampleDT:0.05)
            }
            let reason:BehaviorReason=["click","buttons","pausedButtons"].contains(input) ? .userInput:
                (input == "startle" ? .targetInvalid:.replaced)
            released(e,run,type:input == "startle" ? .failed:.cancelled,reason:reason)
            XCTAssertEqual(bird.position,position,"Cancellation must not rewind a gently moved host")
            if ["click","buttons","pausedButtons"].contains(input) {
                XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(bird.state,.perched)
            } else {
                XCTAssertEqual(bird.state,.flying);XCTAssertGreaterThan(bird.motionRevision,revision)
                XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
            }
        }
    }

    func testSettingsCancelImmediatelyAndRejectBothEntriesWithoutLeaking() throws {
        for master in [false,true] {
            let e=fixture(),bird=e.birds[0],run=try start(e)
            advance(e,seconds:0.2);e.handle(.pause(true))
            var settings=e.settings
            if master {settings.perchActions=false} else {settings.takeoffPreparationEnabled=false}
            e.applySettings(settings)
            released(e,run,type:.cancelled,reason:.settingsChanged)
            e.handle(.pause(false))
            let count=e.events.count,revision=bird.motionRevision,position=bird.position
            XCTAssertEqual(e.prepareTakeoff(id:e.id(of:bird)!,plan:destination(e),source:.automatic),.rejected(.disabled))
            XCTAssertEqual(e.events.count,count)
            XCTAssertEqual(e.requestTakeoffPreparation(source:.preview),.rejected(.disabled))
            XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.motionRevision,revision)
        }
    }

    func testEveryRequiredFrameRejectsAtomicallyAndCallerCanApplyOriginalPlanImmediately() throws {
        for missing in frames.sorted() {
            let e=fixture(),control=fixture(),bird=e.birds[0],plan=destination(e)
            var world=e.world;world.availableFrames[bird.profile.id]?.remove(missing);e.updateWorld(world)
            let position=bird.position,revision=bird.motionRevision,count=e.events.count
            XCTAssertEqual(e.prepareTakeoff(id:e.id(of:bird)!,plan:plan,source:.automatic),.rejected(.missingFrames))
            XCTAssertEqual(e.events.count,count);XCTAssertEqual(bird.position,position)
            XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(e.reservedLandingCount,0)
            plan.apply(to:bird,random:e.random);plan.apply(to:control.birds[0],random:control.random)
            XCTAssertEqual(bird.state,.flying);XCTAssertEqual(bird.stateTime,0)
            XCTAssertEqual(e.random.unit(),control.random.unit())
        }
    }

    func testUnsupportedOrUnsafePlansRejectWithoutClaimingResourcesOrConsumingRandomness() throws {
        for change in ["hostless","side","urgent","targetPID","covered","occupied","sourceSide","flying","transient"] {
            let e=fixture(),control=fixture(),bird=e.birds[0],initial=destination(e)
            var host=initial.host,edge=initial.edge,urgent=false
            switch change {
            case "hostless":host=nil
            case "side":edge = .left
            case "urgent":urgent=true
            case "targetPID":host=Surface(id:targetHost.id,pid:90,rect:targetHost.rect)
            case "covered":
                var world=e.world
                world.surfaces.insert(Surface(id:185,rect:Geometry.landingFootprint(at:initial.point,scale:2)),at:0)
                e.updateWorld(world)
            case "occupied":
                let other=Bird(position:.zero,fraction:initial.fraction,profile:bird.profile,random:{0.5})
                other.perch(on:targetHost,spriteScale:e.spriteScale(for:other));e.register(other)
            case "sourceSide":bird.edge = .left
            case "flying":bird.fly(to:initial.point,host:targetHost,urgent:true)
            default:
                e.installFixtureBirds([]);e.register(bird,role:.transient)
            }
            let plan=DestinationPlan(point:initial.point,host:host,fraction:initial.fraction,edge:edge,
                duration:initial.duration,arc:initial.arc,airspace:initial.airspace,urgent:urgent)
            let revision=bird.motionRevision,position=bird.position,count=e.events.count
            let result=e.prepareTakeoff(id:e.id(of:bird)!,plan:plan,source:.automatic)
            if case .rejected=result {} else {XCTFail("Must reject \(change)")}
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertEqual(e.events.count,count);XCTAssertEqual(e.random.unit(),control.random.unit())
        }
    }

    func testLeaseAndReservationBlockCompetitorsButAllowIndependentEncounterPreview() throws {
        let e=fixture(),bird=e.birds[0],run=try start(e)
        XCTAssertEqual(e.prepareTakeoff(id:e.id(of:bird)!,plan:destination(e),source:.automatic),.rejected(.busy))
        XCTAssertEqual(e.handle(.previewPointerAfter(3)),.scheduled,"Preparation has no encounter budget")
        let other=Bird(position:.zero,fraction:0.8,profile:bird.profile,random:{0.5})
        other.perch(on:sourceHost,spriteScale:e.spriteScale(for:other));e.register(other)
        let plan=destination(e)
        if case .rejected=e.prepareTakeoff(id:e.id(of:other)!,plan:plan,source:.automatic) {} else {
            XCTFail("An existing landing reservation must block the same destination")
        }
        XCTAssertEqual(e.leasedBirdCount,1);XCTAssertEqual(e.reservedLandingCount,1)
        e.handle(.pointerClick);released(e,run,type:.cancelled,reason:.userInput)
    }

    func testInitialIdleHopBlendsOutOverFifteenHundredthsWithoutChangingFootAnchor() throws {
        let e=fixture(due:false),bird=e.birds[0]
        advance(e,seconds:1.25)
        let initial=try XCTUnwrap(e.renderSnapshot().first),position=bird.position
        XCTAssertLessThan(initial.hopOffset,-2)
        let run=try start(e)
        XCTAssertEqual(e.renderSnapshot().first?.hopOffset,initial.hopOffset)
        advance(e,seconds:0.05)
        let middle=try XCTUnwrap(e.renderSnapshot().first)
        XCTAssertGreaterThan(middle.hopOffset,initial.hopOffset);XCTAssertLessThan(middle.hopOffset,0)
        XCTAssertEqual(middle.position,position);XCTAssertEqual(middle.frameName,"stand")
        advance(e,seconds:0.1)
        XCTAssertEqual(try XCTUnwrap(e.renderSnapshot().first).hopOffset,0,accuracy:0.000001)
        XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.state,.perched)
        advance(e,seconds:0.30);released(e,run,type:.completed)
    }

    func testInitialHopEnvelopeMustFitDisplayAndAvoidOccluders() throws {
        for obstruction in [false,true] {
            let e=fixture(due:false),bird=e.birds[0]
            advance(e,seconds:1.25)
            let hop=e.baseHop(for:e.id(of:bird)!,bird:bird),scale=e.spriteScale(for:bird)
            XCTAssertLessThan(hop,-2)
            let planted=Geometry.landingFootprint(at:bird.position,scale:scale)
            var world=e.world
            if obstruction {
                // A blocker above the planted sprite intersects only the hop.
                world.surfaces.insert(Surface(id:186,rect:CGRect(x:planted.minX,y:planted.minY+hop*scale,
                    width:planted.width,height:-hop*scale/2)),at:0)
            } else {
                world.displays=[CGRect(x:screen.minX,y:planted.minY-0.1,
                    width:screen.width,height:screen.maxY-planted.minY+0.1)]
            }
            e.updateWorld(world)
            XCTAssertTrue(e.hasUsablePerch(bird),"Planted-only validation would miss this unsafe initial pose")
            if case .rejected=e.prepareTakeoff(id:e.id(of:bird)!,plan:destination(e,host:sourceHost,fraction:0.8),source:.automatic) {} else {
                XCTFail("Initial hop envelope must be checked")
            }
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
    }

    func testGroundToGroundAndWindowGroundTransitionsUseRealAnchors() throws {
        for mode in ["ground","toGround","fromGround"] {
            let e=fixture(ground:mode == "ground"),bird=e.birds[0]
            var world=e.world
            let ground=Geometry.ground(id:183,display:screen,workArea:world.screens[0])
            if mode != "ground" {world.surfaces.append(ground);e.updateWorld(world)}
            if mode == "fromGround" {bird.perch(on:ground,spriteScale:e.spriteScale(for:bird));bird.perchDuration=0}
            let host=mode == "fromGround" ? targetHost:ground
            let plan=destination(e,host:host,fraction:0.8),position=bird.position
            let run=try start(e,plan:plan)
            advance(e,seconds:26.0/60)
            XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.state,.perched)
            e.advance(BehaviorEngine.step);released(e,run,type:.completed)
            XCTAssertEqual(bird.state,.flying);XCTAssertEqual(bird.hostID,host.id)
            advance(e,seconds:30)
            XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,plan.point)
        }
        let natural=fixture(ground:true);natural.autonomousRouting=true
        natural.advance(BehaviorEngine.step)
        XCTAssertEqual(natural.behavior(of:natural.birds[0]),.takeoffPreparation)
    }

    func testFixedStepPreparationAndFlightAgreeAtThirtySixtyAndOneHundredTwentyHz() throws {
        struct Trace:Equatable {
            let position:CGPoint,state:String,frame:String,facing:Bool,hop:CGFloat,revision:UInt64
            let counts:[Int],events:[String]
        }
        func replay(_ hz:Int) throws -> [Trace] {
            let e=fixture(),bird=e.birds[0],run=try start(e)
            var trace:[Trace]=[]
            for sample in 0..<75 {
                if sample==1 {e.handle(.pause(true))}
                if sample==4 {e.handle(.pause(false))}
                advance(e,seconds:0.2,hz:hz)
                let pose=try XCTUnwrap(e.renderSnapshot().first)
                trace.append(Trace(position:bird.position,state:bird.state.rawValue,frame:pose.frameName,
                    facing:pose.facingRight,hop:pose.hopOffset,revision:bird.motionRevision,
                    counts:[e.activeRunCount,e.leasedBirdCount,e.reservedLandingCount],
                    events:e.events.map{"\($0.sequence):\($0.time):\($0.type):\($0.kind?.rawValue ?? ""):\($0.reason?.rawValue ?? "")"}))
            }
            released(e,run,type:.completed);return trace
        }
        let reference=try replay(60)
        XCTAssertEqual(try replay(30),reference);XCTAssertEqual(try replay(120),reference)
    }

    func testOffscreenArrivalStartsFlyingImmediatelyWithoutPreparation() throws {
        let e=fixture();e.installFixtureBirds([]);e.autonomousRouting=true
        e.bringInBird()
        let bird=try XCTUnwrap(e.birds.first),position=bird.position
        XCTAssertEqual(e.arrivalCount,1);XCTAssertEqual(bird.state,.flying)
        XCTAssertEqual(bird.motionRevision,1);XCTAssertEqual(bird.stateTime,0)
        XCTAssertFalse(e.world.displays.contains{$0.contains(position)})
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        advance(e,seconds:0.1)
        XCTAssertNotEqual(bird.position,position)
        XCTAssertFalse(e.events.contains{$0.kind == .takeoffPreparation})
    }

    func testRemovalAndGlobalCancellationReleaseExactlyOnceWithoutStartingFlight() throws {
        for reason:BehaviorReason in [.removed,.sleep,.screensChanged,.spaceChanged,.shutdown] {
            let e=fixture(),bird=e.birds[0],id=e.id(of:bird)!,run=try start(e)
            advance(e,seconds:0.2)
            let position=bird.position,revision=bird.motionRevision
            for _ in 0..<2 {
                if reason == .removed {e.handle(.remove(id))}
                else {e.handle(.cancelAmbient(reason))}
            }
            released(e,run,type:.cancelled,reason:reason)
            XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertEqual(bird.state,.perched);XCTAssertEqual(e.birds.count,reason == .removed ? 0:1)
            advance(e,seconds:1)
            XCTAssertEqual(terminals(e,run).count,1)
        }
    }
}
