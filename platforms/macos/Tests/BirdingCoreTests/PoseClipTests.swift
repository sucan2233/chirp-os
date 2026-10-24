import XCTest
@testable import BirdingCore

final class PoseClipTests:XCTestCase {
    private let species:[SpeciesID] = [.treeSparrow,.spottedDove,.barnSwallow,.nightHeron,
        .lightVentedBulbul,.redWhiskeredBulbul,.chineseBlackbird,.magpieRobin,
        .swinhoesWhiteEye,.azureWingedMagpie,.redBilledLeiothrix,.littleOwl]
    private let kinds:[BehaviorKind] = [.watch,.alert,.rest,.takeoffPreparation]
    private let poseFrames:Set<String> = ["lookNear","lookFar","alertRise","alertHold","alertRelax",
        "restLower","restTuck","restWake","takeoffCrouch","takeoffPush"]
    private let screen=CGRect(x:-1200,y:-500,width:4000,height:2400)
    private let host=Surface(id:201,pid:31,rect:CGRect(x:-900,y:700,width:1400,height:500))
    private let target=Surface(id:202,pid:32,rect:CGRect(x:900,y:500,width:1200,height:700))
    private var legacyFrames:Set<String> {
        Set(["stand","breathe","blink","preen0","preen1","idle0","idle1","idle2",
            "stretch","shake","land0","land1","land2","glide0","glide1","glide2",
            "bank0","bank1","bank2","bound","cling0","cling1","peck0","peck1","poop0","poop1"]
            + (0...7).map{"fly\($0)"})
    }

    private func fixture(_ species:SpeciesID = .treeSparrow,enhanced:Bool=true,
                         scale:CGFloat=1,seed:UInt64=73,topOnly:Bool=false) -> BehaviorEngine {
        var settings=BirdSettings()
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        settings.ambientLeafPlayEnabled=false;settings.edgePeekEnabled=false;settings.sideHopEnabled=false
        let engine=BehaviorEngine(seed:seed,settings:settings)
        engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
        var surfaces=[host,target]
        if topOnly {
            // Wide 120-point windows support top landings without entering the
            // woodpecker planner's side-route branch (window height >= 180).
            for index in surfaces.indices {surfaces[index].rect.size.height=120}
        }
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:surfaces,scale:scale,
            pointer:CGPoint(x:screen.minX+20,y:screen.minY+20),
            availableFrames:[species:enhanced ? legacyFrames.union(poseFrames):legacyFrames]))
        let bird=Bird(position:.zero,fraction:0.35,profile:SpeciesCatalog.standard.profile(species),random:{0.5})
        bird.perch(on:surfaces[0],spriteScale:engine.spriteScale(for:bird));bird.perchDuration=600
        engine.installFixtureBirds([bird]);return engine
    }

    private func advance(_ engine:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {engine.advance(1/Double(hz))}
    }

    private func command(_ kind:BehaviorKind,_ source:BehaviorSource) -> EngineCommand {
        switch kind {
        case .watch:return .attention(.watch,source)
        case .alert:return .attention(.alert,source)
        case .rest:return .perchAction(.rest,source)
        case .takeoffPreparation:return .prepareTakeoff(source)
        default:preconditionFailure("Only the four M6b enhancement owners belong in this fixture")
        }
    }

    private func started(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let id)=result else {
            XCTFail("Expected a real engine entry to start, got \(result)",file:file,line:line)
            throw NSError(domain:"PoseClipTests",code:1)
        }
        return id
    }

    private func start(_ kind:BehaviorKind,in engine:BehaviorEngine,source:BehaviorSource = .preview) throws -> BehaviorRunID {
        let bird=engine.birds[0],id=try XCTUnwrap(engine.id(of:bird))
        if kind == .watch {
            var world=engine.world
            world.pointer=CGPoint(x:bird.position.x+120*engine.spriteScale(for:bird),y:bird.position.y)
            engine.updateWorld(world)
        } else {
            var world=engine.world
            world.pointer=CGPoint(x:screen.minX+20,y:screen.minY+20)
            engine.updateWorld(world)
        }
        if kind == .alert,source == .automatic {
            // An automatic alert needs existing disturbance. This fixture sets
            // eligibility, then uses the command gate, selection and runtime.
            engine.perchPlanner.rhythms[id]?.disturbance=0.5
        }
        return try started(engine.handle(command(kind,source)))
    }

    private func duration(_ engine:BehaviorEngine,_ run:BehaviorRunID) throws -> Double {
        let execution=try XCTUnwrap(engine.runtime.runs[run]?.execution)
        if let attention=execution as? AttentionExecution {return attention.plan.duration}
        if let perch=execution as? PerchActivityExecution {return perch.plan.duration}
        XCTAssertTrue(execution is TakeoffPreparationExecution)
        return 0.45
    }

    // Probe each product phase, independently of PoseClip.sample's algorithm.
    private func phases(_ kind:BehaviorKind,duration:Double) -> [(Double,String)] {
        switch kind {
        case .watch:return [(0.05,"lookNear"),(0.20,"lookFar"),(duration-0.05,"lookNear")]
        case .alert:return [(0.05,"alertRise"),(0.20,"alertHold"),(duration-0.10,"alertRelax")]
        case .rest:return [(0.10,"restLower"),(0.40,"restTuck"),(duration-0.10,"restWake")]
        case .takeoffPreparation:return [(0.10,"takeoffCrouch"),(0.30,"takeoffPush")]
        default:preconditionFailure("Unexpected pose owner")
        }
    }

    private func terminals(_ engine:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }

    private func released(_ engine:BehaviorEngine,_ run:BehaviorRunID,type:BehaviorEventType,
                          reason:BehaviorReason?=nil,file:StaticString=#filePath,line:UInt=#line) {
        let events=terminals(engine,run)
        XCTAssertEqual(events.count,1,file:file,line:line)
        XCTAssertEqual(events.first?.type,type,file:file,line:line)
        XCTAssertEqual(events.first?.reason,reason,file:file,line:line)
        XCTAssertNil(engine.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(engine.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(engine.reservedLandingCount,0,file:file,line:line)
        XCTAssertEqual(engine.scenePropCount,0,file:file,line:line)
        XCTAssertEqual(engine.habitatReservationCount,0,file:file,line:line)
    }

    private func events(_ engine:BehaviorEngine) -> [String] {
        engine.events.map {"\($0.sequence):\($0.time):\($0.runID?.rawValue ?? 0):\($0.kind?.rawValue ?? ""):\($0.type):\($0.source):\($0.reason?.rawValue ?? ""):\($0.participants.map(\.rawValue))"}
    }

    func testClipTimingUsesOriginalDeadlineAndCompressesOnlyTransitions() throws {
        let fixtures:[(BehaviorKind,Double,[String],[Double])] = [
            (.watch,2,["lookNear","lookFar","lookNear"],[0.15,1.70,0.15]),
            (.alert,2,["alertRise","alertHold","alertRelax"],[0.12,1.63,0.25]),
            (.rest,2,["restLower","restTuck","restWake"],[0.25,1.50,0.25]),
            (.takeoffPreparation,0.45,["takeoffCrouch","takeoffPush"],[0.25,0.20]),
            (.watch,0.10,["lookNear","lookFar","lookNear"],[0.05,0,0.05]),
            (.alert,0.074,["alertRise","alertHold","alertRelax"],[0.024,0,0.050]),
            (.rest,0.10,["restLower","restTuck","restWake"],[0.05,0,0.05]),
            (.takeoffPreparation,0.09,["takeoffCrouch","takeoffPush"],[0.05,0.04])
        ]
        for bird in species {
            for (kind,deadline,names,times) in fixtures {
                let clip=try XCTUnwrap(SpeciesBehaviorProfile.profile(for:bird)
                    .poseClip(for:kind,duration:deadline,lookingFar:true))
                XCTAssertEqual(clip.frames.map(\.name),names)
                XCTAssertEqual(clip.frames.count,times.count)
                XCTAssertEqual(clip.requiredFrames,Set(names))
                for (frame,expected) in zip(clip.frames,times) {XCTAssertEqual(frame.duration,expected,accuracy:1e-9)}
                XCTAssertEqual(clip.duration,deadline,accuracy:1e-9)
                XCTAssertEqual(clip.maximumLoops,1)
                XCTAssertEqual(clip.foot,PoseClip.Anchor(29,39))
                XCTAssertEqual(clip.recovery,.currentEngineState)
                XCTAssertNil(clip.sample(at:clip.duration))
                XCTAssertNil(clip.sample(at:clip.duration+1))
                XCTAssertEqual(try JSONDecoder().decode(PoseClip.self,from:JSONEncoder().encode(clip)),clip)
            }
            let near=try XCTUnwrap(SpeciesBehaviorProfile.profile(for:bird).poseClip(for:.watch,duration:2))
            let far=try XCTUnwrap(SpeciesBehaviorProfile.profile(for:bird).poseClip(for:.watch,duration:2,lookingFar:true))
            XCTAssertEqual(near.id,"\(bird.rawValue).watch")
            XCTAssertEqual(far.id,"\(bird.rawValue).watch.far")
            XCTAssertEqual(near.requiredFrames,["lookNear","lookFar"])
            XCTAssertEqual(far.requiredFrames,["lookNear","lookFar"])
            XCTAssertEqual(near.sample(at:1)?.name,"lookNear")
            XCTAssertEqual(far.sample(at:1)?.name,"lookFar")
            for kind in kinds {
                for invalid in [0.0,-0.1,Double.nan,Double.infinity] {
                    XCTAssertNil(SpeciesBehaviorProfile.profile(for:bird).poseClip(for:kind,duration:invalid))
                }
            }
        }
    }

    func testInitializerAndDecoderRejectInvalidClipsAndUnboundedTotalDuration() throws {
        let frame=PoseClip.Frame(name:"stand",duration:Double.greatestFiniteMagnitude,beak:.init(42,22))
        XCTAssertNil(PoseClip(id:"sumOverflow",frames:[frame,frame]))
        XCTAssertNil(PoseClip(id:"loopOverflow",frames:[frame],maximumLoops:2))
        let valid:[String:Any] = ["id":"decode","maximumLoops":1,"foot":["x":29,"y":39],
            "recovery":"currentEngineState","frames":[["name":"stand","duration":1,"beak":["x":42,"y":22]]]]
        let changes:[(String,Any)] = [
            ("id",""),("frames",[]),("maximumLoops",0),("maximumLoops",-1),
            ("foot",["x":28,"y":39]),("recovery","restoreStalePose"),
            ("frames",[["name":"","duration":1,"beak":["x":42,"y":22]]]),
            ("frames",[["name":"stand","duration":-1,"beak":["x":42,"y":22]]]),
            ("frames",[["name":"stand","duration":0,"beak":["x":42,"y":22]]]),
            ("frames",[["name":"stand","duration":1,"beak":["x":49,"y":22]]]),
            ("frames",[["name":"stand","duration":1,"beak":["x":42,"y":-1]]])
        ]
        XCTAssertNoThrow(try JSONDecoder().decode(PoseClip.self,from:JSONSerialization.data(withJSONObject:valid)))
        for (key,value) in changes {
            var invalid=valid;invalid[key]=value
            let data=try JSONSerialization.data(withJSONObject:invalid)
            XCTAssertThrowsError(try JSONDecoder().decode(PoseClip.self,from:data),key)
        }
    }

    func testDedicatedPeekClipHasOnePointSixSecondClockAndExactFrameBoundaries() throws {
        let supported:[SpeciesID] = [.lightVentedBulbul,.magpieRobin]
        for species in SpeciesID.allCases {
            guard supported.contains(species) else {
                XCTAssertNil(PoseClip.edgePeek(species:species));continue
            }
            let clip=try XCTUnwrap(PoseClip.edgePeek(species:species))
            XCTAssertEqual(clip.frames.map(\.name),["peekLower","peekLook","peekRecover"])
            for (frame,time) in zip(clip.frames,[0.32,0.96,0.32]) {XCTAssertEqual(frame.duration,time,accuracy:1e-9)}
            XCTAssertEqual(clip.duration,1.6,accuracy:1e-9)
            XCTAssertEqual(clip.maximumLoops,1);XCTAssertEqual(clip.foot,.init(29,39))
            XCTAssertEqual(clip.requiredFrames,["peekLower","peekLook","peekRecover"])
            for (age,name) in [(0.0,"peekLower"),(0.319999,"peekLower"),(0.32,"peekLook"),
                               (1.279999,"peekLook"),(1.28,"peekRecover"),(1.599999,"peekRecover")] {
                XCTAssertEqual(clip.sample(at:age)?.name,name,"\(species), \(age)")
            }
            XCTAssertNil(clip.sample(at:1.6));XCTAssertNil(clip.sample(at:3.2))
            XCTAssertEqual(try JSONDecoder().decode(PoseClip.self,from:JSONEncoder().encode(clip)),clip)
        }
    }

    func testSamplingSkipsZeroDurationFramesAndStopsAtLoopLimit() throws {
        let beak=PoseClip.Anchor(42,22)
        let clip=try XCTUnwrap(PoseClip(id:"boundary",frames:[
            .init(name:"unused",duration:0,beak:beak),
            .init(name:"first",duration:0.25,beak:beak),
            .init(name:"second",duration:0.50,beak:beak)],maximumLoops:2))
        for (age,name) in [(0.0,"first"),(0.249,"first"),(0.25,"second"),
                           (0.749,"second"),(0.75,"first"),(1.0,"second"),(1.499,"second")] {
            XCTAssertEqual(clip.sample(at:age)?.name,name)
        }
        for age in [-1.0,1.5,2,Double.nan,Double.infinity] {XCTAssertNil(clip.sample(at:age))}
        XCTAssertEqual(clip.requiredFrames,["unused","first","second"])
        XCTAssertNil(PoseClip(id:"empty",frames:[]))
        XCTAssertNil(PoseClip(id:"",frames:clip.frames))
        XCTAssertNil(PoseClip(id:"loops",frames:clip.frames,maximumLoops:0))
        XCTAssertNil(PoseClip(id:"feet",frames:clip.frames,foot:.init(28,39)))
        for invalid in [-1.0,Double.nan,Double.infinity] {
            XCTAssertNil(PoseClip(id:"duration",frames:[.init(name:"stand",duration:invalid,beak:beak)]))
        }
        XCTAssertNil(PoseClip(id:"zero",frames:[.init(name:"stand",duration:0,beak:beak)]))
        for invalid in [PoseClip.Anchor(-1,22),.init(49,22),.init(42,49),.init(.nan,22)] {
            XCTAssertNil(PoseClip(id:"beak",frames:[.init(name:"stand",duration:1,beak:invalid)]))
        }
    }

    func testAnchorsMatchRenderTransformInBothDirectionsAndAtAllScales() throws {
        let foot=CGPoint(x:-640,y:-120)
        for bird in species {
            for kind in kinds {
                let clip=try XCTUnwrap(SpeciesBehaviorProfile.profile(for:bird).poseClip(for:kind,duration:2,lookingFar:true))
                for scale:CGFloat in [0.5,1,2] {
                    for frame in clip.frames {
                        var points:[CGPoint]=[]
                        for facing in [true,false] {
                            let state=BirdRenderState(id:BirdID(1),species:bird,position:foot,facingRight:facing,
                                scale:scale,hopOffset:0,frameName:frame.name,blockers:[],hoverable:true)
                            let beak=frame.beak.mirrored(facingRight:facing)
                            let point=frame.beak.world(foot:foot,scale:scale,facingRight:facing)
                            XCTAssertEqual(point.x,state.rect.minX+CGFloat(beak.x)*scale,accuracy:1e-9)
                            XCTAssertEqual(point.y,state.rect.minY+CGFloat(beak.y)*scale,accuracy:1e-9)
                            XCTAssertEqual(clip.foot.world(foot:foot,scale:scale,facingRight:facing),foot)
                            XCTAssertTrue(state.rect.contains(point))
                            let restored=beak.mirrored(facingRight:facing)
                            XCTAssertEqual(restored.x,frame.beak.x,accuracy:1e-9)
                            XCTAssertEqual(restored.y,frame.beak.y,accuracy:1e-9)
                            points.append(point)
                        }
                        XCTAssertEqual(points[0].x-foot.x,foot.x-points[1].x,accuracy:1e-9)
                        XCTAssertEqual(points[0].y,points[1].y)
                    }
                }
            }
        }
    }

    func testRealPreviewAndAutomaticEntriesRenderEveryPhaseAndRecoverWithoutExtraRuns() throws {
        for bird in species {
            for kind in kinds {
                for source:BehaviorSource in [.preview,.automatic] {
                    let engine=fixture(bird),model=engine.birds[0],origin=model.position,revision=model.motionRevision
                    let probabilities=engine.settings.probabilities
                    let run=try start(kind,in:engine,source:source),deadline=try duration(engine,run)
                    let probes=phases(kind,duration:deadline)
                    var step=0
                    for (age,expected) in probes {
                        let next=Int((age*60).rounded())
                        advance(engine,seconds:Double(next-step)/60);step=next
                        let pose=try XCTUnwrap(engine.renderSnapshot().first)
                        XCTAssertEqual(pose.frameName,expected,"\(bird): \(kind): \(source), age \(age)")
                        XCTAssertEqual(pose.position,origin)
                        XCTAssertEqual(model.motionRevision,revision)
                        XCTAssertEqual(pose.rect.minY+(39-pose.hopOffset)*pose.scale,origin.y,accuracy:1e-8)
                        XCTAssertEqual(engine.activeRunCount,1);XCTAssertEqual(engine.leasedBirdCount,1)
                        XCTAssertFalse(engine.ambientBusy)
                    }
                    advance(engine,seconds:6)
                    released(engine,run,type:.completed)
                    XCTAssertEqual(engine.events.filter{$0.type == .started}.count,1)
                    XCTAssertEqual(engine.events.first?.source,source)
                    let end=try XCTUnwrap(terminals(engine,run).first)
                    XCTAssertGreaterThanOrEqual(end.time+1e-9,deadline)
                    XCTAssertLessThanOrEqual(end.time,deadline+BehaviorEngine.step+1e-9)
                    XCTAssertEqual(engine.renderSnapshot().first?.frameName,model.frameName)
                    XCTAssertEqual(engine.residentCount,1);XCTAssertEqual(engine.birds.count,1)
                    XCTAssertEqual(engine.arrivalCount,0);XCTAssertEqual(engine.departureCount,0)
                    XCTAssertEqual(engine.settings.probabilities,probabilities)
                    XCTAssertEqual(engine.activeRunCount,0);XCTAssertEqual(engine.leasedBirdCount,0)
                    if kind != .takeoffPreparation {
                        XCTAssertEqual(model.position,origin);XCTAssertEqual(model.motionRevision,revision)
                    }
                }
            }
        }
    }

    func testEachMissingOptionalFrameFallsBackToLegacyWithoutChangingEventsOrRandomness() throws {
        for bird in species {
            for kind in kinds {
                let missingByKind:[BehaviorKind:[String]] = [
                    .watch:["lookNear","lookFar"],.alert:["alertRise","alertHold","alertRelax"],
                    .rest:["restLower","restTuck","restWake"],.takeoffPreparation:["takeoffCrouch","takeoffPush"]]
                for missing in try XCTUnwrap(missingByKind[kind]) {
                    let engine=fixture(bird),control=fixture(bird,enhanced:false)
                    var world=engine.world;world.availableFrames[bird]?.remove(missing);engine.updateWorld(world)
                    let run=try start(kind,in:engine),baseline=try start(kind,in:control)
                    for _ in 0..<6*60 {
                        XCTAssertEqual(engine.renderSnapshot().first?.frameName,control.renderSnapshot().first?.frameName,
                            "\(bird): \(kind), missing \(missing)")
                        XCTAssertEqual(engine.birds[0].position,control.birds[0].position)
                        engine.advance(BehaviorEngine.step);control.advance(BehaviorEngine.step)
                    }
                    released(engine,run,type:.completed);released(control,baseline,type:.completed)
                    XCTAssertEqual(events(engine),events(control))
                    for _ in 0..<4 {XCTAssertEqual(engine.random.unit(),control.random.unit())}
                }
            }
        }
    }

    func testNearWatchStillNeedsTheFarFrameAndCanFallbackWithoutMovingFeet() throws {
        for bird in species {
            for complete in [false,true] {
                let engine=fixture(bird),model=engine.birds[0],origin=model.position
                var world=engine.world
                world.pointer=CGPoint(x:origin.x+40*engine.spriteScale(for:model),y:origin.y)
                if !complete {world.availableFrames[bird]?.remove("lookFar")}
                engine.updateWorld(world)
                let run=try started(engine.handle(.attention(.watch,.preview)))
                advance(engine,seconds:0.3)
                XCTAssertEqual(engine.renderSnapshot().first?.frameName,complete ? "lookNear":"stand")
                XCTAssertEqual(model.position,origin)
                advance(engine,seconds:3)
                released(engine,run,type:.completed)
            }
        }
    }

    func testLateOptionalFrameLossFallsBackWhilePausedWithoutFailingOrRestarting() throws {
        for kind in kinds {
            let engine=fixture(),control=fixture(enhanced:false)
            let run=try start(kind,in:engine),baseline=try start(kind,in:control)
            advance(engine,seconds:0.2);advance(control,seconds:0.2)
            engine.handle(.pause(true));control.handle(.pause(true))
            let age=engine.runtime.runs[run]?.age,revision=engine.birds[0].motionRevision
            var world=engine.world;world.availableFrames[.treeSparrow]=legacyFrames;engine.updateWorld(world)
            XCTAssertTrue(terminals(engine,run).isEmpty)
            XCTAssertEqual(engine.runtime.runs[run]?.age,age)
            XCTAssertEqual(engine.birds[0].motionRevision,revision)
            XCTAssertEqual(engine.renderSnapshot().first?.frameName,control.renderSnapshot().first?.frameName)
            engine.handle(.pause(false));control.handle(.pause(false))
            advance(engine,seconds:6);advance(control,seconds:6)
            released(engine,run,type:.completed);released(control,baseline,type:.completed)
            XCTAssertEqual(events(engine),events(control))
        }
    }

    func testNormalRestCompletionAtIdleHopPeakStartsRecoveryFromPlantedFeet() throws {
        let reference=fixture(),referenceRun=try start(.rest,in:reference)
        let deadline=try duration(reference,referenceRun)
        let steps=Int(ceil(deadline/BehaviorEngine.step))
        for scale:CGFloat in [0.5,1,2] {
            for facing in [false,true] {
                let engine=fixture(scale:scale),model=engine.birds[0]
                // The sparrow's next idle hop peaks at age 10.25. Only fixture
                // setup advances Bird directly; the entire run and release use
                // the real command and fixed-step engine lifecycle.
                model.tick(10.25-Double(steps)*BehaviorEngine.step)
                model.facingRight=facing
                let origin=model.position,revision=model.motionRevision
                var observations:[BehaviorObservation]=[]
                engine.observationObserver={observations.append($0)}
                let run=try start(.rest,in:engine)
                XCTAssertEqual(try duration(engine,run),deadline)
                advance(engine,seconds:Double(steps-1)*BehaviorEngine.step)
                XCTAssertTrue(terminals(engine,run).isEmpty)
                XCTAssertEqual(engine.renderSnapshot().first?.frameName,"restWake")
                XCTAssertLessThan(model.hopOffset,-2.9,"The deadline must overlap a real periodic hop")
                XCTAssertEqual(try XCTUnwrap(engine.renderSnapshot().first).hopOffset,0,accuracy:1e-9)

                engine.advance(BehaviorEngine.step)
                released(engine,run,type:.completed)
                let completed=try XCTUnwrap(engine.renderSnapshot().first)
                XCTAssertEqual(model.stateTime,10.25,accuracy:1e-8)
                XCTAssertLessThan(model.hopOffset,-2.9)
                XCTAssertEqual(completed.hopOffset,0,accuracy:1e-9,
                    "Normal completion must give PoseMixer the planted final pose, even after clip.sample expires")
                XCTAssertEqual(completed.frameName,model.frameName)
                XCTAssertEqual(completed.position,origin);XCTAssertEqual(completed.facingRight,facing)
                XCTAssertEqual(model.motionRevision,revision)
                XCTAssertEqual(completed.rect.minY+39*completed.scale,origin.y,accuracy:1e-8)
                XCTAssertEqual(observations.count,1)

                engine.handle(.pause(true));advance(engine,seconds:2)
                XCTAssertEqual(engine.renderSnapshot().first?.hopOffset,0)
                engine.handle(.pause(false));advance(engine,seconds:0.1)
                let middle=try XCTUnwrap(engine.renderSnapshot().first)
                XCTAssertLessThan(middle.hopOffset,0)
                XCTAssertGreaterThan(middle.hopOffset,model.hopOffset,"Recovery must blend toward the live idle hop")
                XCTAssertEqual(middle.position,origin)
                advance(engine,seconds:7.0/60)
                XCTAssertEqual(try XCTUnwrap(engine.renderSnapshot().first).hopOffset,model.hopOffset,accuracy:1e-9)
                XCTAssertEqual(model.position,origin);XCTAssertEqual(observations.count,1)
                released(engine,run,type:.completed)
            }
        }
    }

    func testLateRestFrameLossAndPausedRestorationKeepFeetPlantedThroughCompletion() throws {
        let reference=fixture(),referenceRun=try start(.rest,in:reference)
        let deadline=try duration(reference,referenceRun)
        let steps=Int(ceil(deadline/BehaviorEngine.step)),lateSteps=steps-6
        for scale:CGFloat in [0.5,1,2] {
            for facing in [false,true] {
                for missing in ["restLower","restTuck","restWake"] {
                    let context="scale=\(scale), facing=\(facing), missing=\(missing)"
                    let engine=fixture(scale:scale),model=engine.birds[0]
                    // Align the last 0.1 seconds of rest with the live idle hop
                    // peak, where switching motion ownership would be visible.
                    model.tick(10.25-Double(lateSteps)*BehaviorEngine.step)
                    model.facingRight=facing
                    let origin=model.position,revision=model.motionRevision
                    var observations:[BehaviorObservation]=[]
                    engine.observationObserver={observations.append($0)}
                    let run=try start(.rest,in:engine)
                    XCTAssertEqual(try duration(engine,run),deadline,context)
                    advance(engine,seconds:Double(lateSteps)*BehaviorEngine.step)
                    let planted=try XCTUnwrap(engine.renderSnapshot().first)
                    XCTAssertEqual(planted.frameName,"restWake",context)
                    XCTAssertEqual(planted.hopOffset,0,accuracy:1e-9,context)
                    XCTAssertEqual(model.stateTime,10.25,accuracy:1e-8,context)
                    XCTAssertLessThan(model.hopOffset,-2.9,context)

                    var world=engine.world
                    world.availableFrames[.treeSparrow]?.remove(missing);engine.updateWorld(world)
                    let fallback=try XCTUnwrap(engine.renderSnapshot().first)
                    XCTAssertEqual(fallback.frameName,"stand",context)
                    XCTAssertEqual(fallback.hopOffset,planted.hopOffset,accuracy:1e-9,context)
                    XCTAssertEqual(fallback.rect,planted.rect,context)
                    engine.advance(BehaviorEngine.step)
                    XCTAssertEqual(try XCTUnwrap(engine.renderSnapshot().first).hopOffset,0,accuracy:1e-9,context)
                    world.availableFrames[.treeSparrow]?.insert(missing);engine.updateWorld(world)
                    XCTAssertEqual(engine.renderSnapshot().first?.frameName,"restWake",context)
                    XCTAssertEqual(engine.renderSnapshot().first?.rect,planted.rect,context)

                    engine.handle(.pause(true))
                    let age=try XCTUnwrap(engine.runtime.runs[run]?.age),stateTime=model.stateTime
                    // Finish with artwork absent, so runtime release must also
                    // receive the planted pose from the legacy-frame fallback.
                    for available in [false,true,false] {
                        if available {world.availableFrames[.treeSparrow]?.insert(missing)}
                        else {world.availableFrames[.treeSparrow]?.remove(missing)}
                        engine.updateWorld(world)
                        for sample in 0..<2 {
                            if sample>0 {advance(engine,seconds:0.5)}
                            let frozen=try XCTUnwrap(engine.renderSnapshot().first)
                            XCTAssertEqual(frozen.frameName,available ? "restWake":"stand",context)
                            XCTAssertEqual(frozen.hopOffset,0,accuracy:1e-9,context)
                            XCTAssertEqual(frozen.rect,planted.rect,context)
                            XCTAssertEqual(frozen.position,origin,context)
                            XCTAssertEqual(frozen.facingRight,facing,context)
                            XCTAssertEqual(engine.runtime.runs[run]?.age,age,context)
                            XCTAssertEqual(model.stateTime,stateTime,context)
                            XCTAssertTrue(terminals(engine,run).isEmpty,context)
                            XCTAssertTrue(observations.isEmpty,context)
                        }
                    }
                    let resumeTime=engine.time
                    engine.handle(.pause(false))
                    for _ in 0..<steps-lateSteps-1 {
                        engine.advance(BehaviorEngine.step)
                        XCTAssertEqual(try XCTUnwrap(engine.renderSnapshot().first).hopOffset,0,accuracy:1e-9,context)
                    }
                    released(engine,run,type:.completed)
                    let end=try XCTUnwrap(terminals(engine,run).first)
                    XCTAssertEqual(end.time-resumeTime,Double(steps-lateSteps-1)*BehaviorEngine.step,accuracy:1e-8,context)
                    let completed=try XCTUnwrap(engine.renderSnapshot().first)
                    XCTAssertLessThan(model.hopOffset,-2,context)
                    XCTAssertEqual(completed.rect,planted.rect,context)
                    XCTAssertEqual(completed.frameName,model.frameName,context)
                    XCTAssertEqual(model.motionRevision,revision,context)
                    XCTAssertEqual(observations.count,1,context)
                    XCTAssertEqual(engine.events.filter{$0.type == .started}.count,1,context)
                    XCTAssertEqual(engine.residentCount,1,context);XCTAssertEqual(engine.arrivalCount,0,context)

                    world.availableFrames[.treeSparrow]?.insert(missing);engine.updateWorld(world)
                    XCTAssertEqual(engine.renderSnapshot().first?.rect,completed.rect,context)
                    advance(engine,seconds:0.1)
                    let recovering=try XCTUnwrap(engine.renderSnapshot().first)
                    XCTAssertLessThan(recovering.hopOffset,0,context)
                    XCTAssertGreaterThan(recovering.hopOffset,model.hopOffset,context)
                    advance(engine,seconds:7.0/60)
                    XCTAssertEqual(try XCTUnwrap(engine.renderSnapshot().first).hopOffset,model.hopOffset,accuracy:1e-9,context)
                    XCTAssertEqual(model.position,origin,context);XCTAssertEqual(observations.count,1,context)
                    released(engine,run,type:.completed)
                }
            }
        }
    }

    func testRestMissingArtAtStartKeepsLegacyHopWhenArtReturnsWhilePaused() throws {
        let reference=fixture(),referenceRun=try start(.rest,in:reference)
        let deadline=try duration(reference,referenceRun)
        let steps=Int(ceil(deadline/BehaviorEngine.step)),lateSteps=steps-6
        for scale:CGFloat in [0.5,1,2] {
            for facing in [false,true] {
                for missing in ["restLower","restTuck","restWake"] {
                    let context="scale=\(scale), facing=\(facing), initially missing=\(missing)"
                    let engine=fixture(scale:scale),control=fixture(enhanced:false,scale:scale)
                    let model=engine.birds[0],legacy=control.birds[0]
                    for bird in [model,legacy] {
                        bird.tick(10.25-Double(lateSteps)*BehaviorEngine.step)
                        bird.facingRight=facing
                    }
                    var world=engine.world
                    world.availableFrames[.treeSparrow]?.remove(missing);engine.updateWorld(world)
                    let run=try start(.rest,in:engine),baseline=try start(.rest,in:control)
                    XCTAssertEqual(try duration(engine,run),deadline,context)
                    XCTAssertEqual(try duration(control,baseline),deadline,context)
                    advance(engine,seconds:Double(lateSteps)*BehaviorEngine.step)
                    advance(control,seconds:Double(lateSteps)*BehaviorEngine.step)
                    let pose=try XCTUnwrap(engine.renderSnapshot().first)
                    XCTAssertEqual(pose.frameName,control.renderSnapshot().first?.frameName,context)
                    XCTAssertEqual(pose.rect,control.renderSnapshot().first?.rect,context)
                    XCTAssertLessThan(model.hopOffset,-2.9,context)
                    XCTAssertLessThan(pose.hopOffset,-1,context)
                    XCTAssertEqual(pose.hopOffset,try XCTUnwrap(control.renderSnapshot().first).hopOffset,accuracy:1e-9,context)

                    engine.handle(.pause(true));control.handle(.pause(true))
                    let age=try XCTUnwrap(engine.runtime.runs[run]?.age),stateTime=model.stateTime
                    for available in [true,false,true] {
                        if available {world.availableFrames[.treeSparrow]?.insert(missing)}
                        else {world.availableFrames[.treeSparrow]?.remove(missing)}
                        engine.updateWorld(world)
                        for sample in 0..<2 {
                            if sample>0 {advance(engine,seconds:0.5);advance(control,seconds:0.5)}
                            let frozen=try XCTUnwrap(engine.renderSnapshot().first)
                            // Initial absence selects the legacy presentation
                            // for this run; restored art applies next time.
                            XCTAssertEqual(frozen.frameName,control.renderSnapshot().first?.frameName,context)
                            XCTAssertEqual(frozen.hopOffset,pose.hopOffset,accuracy:1e-9,context)
                            XCTAssertEqual(frozen.rect,pose.rect,context)
                            XCTAssertEqual(frozen.rect,control.renderSnapshot().first?.rect,context)
                            XCTAssertEqual(frozen.facingRight,facing,context)
                            XCTAssertEqual(engine.runtime.runs[run]?.age,age,context)
                            XCTAssertEqual(model.stateTime,stateTime,context)
                            XCTAssertTrue(terminals(engine,run).isEmpty,context)
                        }
                    }
                    let resumeTime=engine.time
                    engine.handle(.pause(false));control.handle(.pause(false))
                    for _ in 0..<steps-lateSteps+15 {
                        engine.advance(BehaviorEngine.step);control.advance(BehaviorEngine.step)
                        let current=try XCTUnwrap(engine.renderSnapshot().first)
                        XCTAssertEqual(current.hopOffset,try XCTUnwrap(control.renderSnapshot().first).hopOffset,accuracy:1e-9,context)
                        XCTAssertEqual(current.rect,control.renderSnapshot().first?.rect,context)
                    }
                    released(engine,run,type:.completed);released(control,baseline,type:.completed)
                    let end=try XCTUnwrap(terminals(engine,run).first)
                    XCTAssertEqual(end.time-resumeTime,Double(steps-lateSteps)*BehaviorEngine.step,accuracy:1e-8,context)
                    XCTAssertEqual(events(engine),events(control),context)
                    XCTAssertEqual(engine.residentCount,1,context);XCTAssertEqual(engine.arrivalCount,0,context)
                }
            }
        }
    }

    func testRelocationImmediatelyPreemptsEveryPosePhaseIncludingWhilePaused() throws {
        for bird in species {
            for kind in kinds {
                let reference=fixture(bird),referenceRun=try start(kind,in:reference)
                for (age,frame) in phases(kind,duration:try duration(reference,referenceRun)) {
                    for paused in [false,true] {
                        let engine=fixture(bird),model=engine.birds[0],id=try XCTUnwrap(engine.id(of:model))
                        let run=try start(kind,in:engine)
                        advance(engine,seconds:age)
                        XCTAssertEqual(engine.renderSnapshot().first?.frameName,frame)
                        if paused {engine.handle(.pause(true))}
                        let position=model.position,revision=model.motionRevision,clock=engine.time
                        let relocation=try started(engine.handle(.relocate(id)))
                        released(engine,run,type:.cancelled,reason:.replaced)
                        XCTAssertEqual(engine.time,clock,"Input cannot wait for the clip to finish")
                        XCTAssertEqual(model.position,position);XCTAssertEqual(model.state,.flying)
                        XCTAssertGreaterThan(model.motionRevision,revision)
                        XCTAssertEqual(engine.runtime.owners[id],relocation)
                        XCTAssertEqual(engine.leasedBirdCount,1)
                        XCTAssertEqual(engine.renderSnapshot().first?.frameName,model.frameName)
                        XCTAssertEqual(engine.renderSnapshot().first?.hopOffset,0)
                        advance(engine,seconds:0.1)
                        XCTAssertNotEqual(model.position,position,"Existing manual relocation remains actionable while paused")
                        XCTAssertEqual(engine.renderSnapshot().first?.frameName,model.frameName)
                        engine.handle(.cancelAmbient(.sleep))
                        released(engine,run,type:.cancelled,reason:.replaced)
                        XCTAssertEqual(engine.activeRunCount,0);XCTAssertEqual(engine.leasedBirdCount,0)
                    }
                }
            }
        }
    }

    func testPauseFreezesEachEnhancedPhaseAndResumesAtTheSameRemainingDeadline() throws {
        for kind in kinds {
            let reference=fixture(),referenceRun=try start(kind,in:reference)
            for (age,_) in phases(kind,duration:try duration(reference,referenceRun)) {
                let engine=fixture(),control=fixture(),model=engine.birds[0]
                let run=try start(kind,in:engine),baseline=try start(kind,in:control)
                advance(engine,seconds:age);advance(control,seconds:age)
                let pose=try XCTUnwrap(engine.renderSnapshot().first),runAge=engine.runtime.runs[run]?.age
                let stateTime=model.stateTime,ecology=engine.ecology(of:model)?.cooldowns
                engine.handle(.pause(true));advance(engine,seconds:2)
                for _ in 0..<5 {engine.updateWorld(engine.world);_=engine.bounds(of:model)}
                let frozen=try XCTUnwrap(engine.renderSnapshot().first)
                XCTAssertEqual(frozen.frameName,pose.frameName);XCTAssertEqual(frozen.position,pose.position)
                XCTAssertEqual(frozen.facingRight,pose.facingRight);XCTAssertEqual(frozen.hopOffset,pose.hopOffset)
                XCTAssertEqual(engine.runtime.runs[run]?.age,runAge);XCTAssertEqual(model.stateTime,stateTime)
                XCTAssertEqual(engine.ecology(of:model)?.cooldowns,ecology)
                XCTAssertEqual(engine.handle(command(kind,.preview)),.rejected(.paused))
                XCTAssertEqual(engine.handle(command(kind,.automatic)),.rejected(.paused))
                engine.handle(.pause(false))
                for _ in 0..<6*60 {
                    engine.advance(BehaviorEngine.step);control.advance(BehaviorEngine.step)
                    XCTAssertEqual(engine.renderSnapshot().first?.frameName,control.renderSnapshot().first?.frameName)
                    XCTAssertEqual(engine.renderSnapshot().first?.position,control.renderSnapshot().first?.position)
                    if !terminals(engine,run).isEmpty {break}
                }
                released(engine,run,type:.completed);released(control,baseline,type:.completed)
                let end=try XCTUnwrap(terminals(engine,run).first)
                let normal=try XCTUnwrap(terminals(control,baseline).first)
                XCTAssertEqual(end.time-normal.time,2,accuracy:1e-8)
            }
        }
    }

    func testEveryPhaseReleasesOnDisableHostLossRemovalAndSleepEvenWhilePaused() throws {
        for bird in species {
            for kind in kinds {
                let reference=fixture(bird),referenceRun=try start(kind,in:reference)
                for (age,_) in phases(kind,duration:try duration(reference,referenceRun)) {
                    for action in ["disable","hostLoss","remove","sleep"] {
                        let engine=fixture(bird),model=engine.birds[0],id=try XCTUnwrap(engine.id(of:model))
                        var observations:[BehaviorObservation]=[]
                        engine.observationObserver={observations.append($0)}
                        let run=try start(kind,in:engine)
                        advance(engine,seconds:age);engine.handle(.pause(true))
                        let clock=engine.time
                        switch action {
                        case "disable":
                            var settings=engine.settings;settings.perchActions=false;engine.applySettings(settings)
                        case "hostLoss":
                            var world=engine.world;world.surfaces.removeAll{$0.id==host.id};engine.updateWorld(world)
                        case "remove":engine.handle(.remove(id))
                        default:engine.handle(.cancelAmbient(.sleep))
                        }
                        let reason:BehaviorReason=action == "disable" ? .settingsChanged:
                            (action == "hostLoss" ? .targetInvalid:(action == "remove" ? .removed:.sleep))
                        released(engine,run,type:action == "hostLoss" ? .failed:.cancelled,reason:reason)
                        XCTAssertEqual(engine.time,clock);XCTAssertTrue(observations.isEmpty)
                        XCTAssertEqual(engine.activeRunCount,0);XCTAssertEqual(engine.leasedBirdCount,0)
                        XCTAssertEqual(engine.birds.count,action == "remove" ? 0:1)
                        XCTAssertEqual(engine.renderSnapshot().count,action == "remove" ? 0:1)
                        engine.updateWorld(engine.world);engine.handle(.cancelAmbient(.sleep));advance(engine,seconds:1)
                        released(engine,run,type:action == "hostLoss" ? .failed:.cancelled,reason:reason)
                        XCTAssertTrue(observations.isEmpty)
                    }
                }
            }
        }
    }

    func testEnhancedAndLegacyRunsKeepEventsObservationCountsAndFlightRandomStreamIdentical() throws {
        for bird in species {
            for source:BehaviorSource in [.preview,.automatic] {
                let engine=fixture(bird),control=fixture(bird,enhanced:false)
                let journal=ObservationJournal(),baseline=ObservationJournal()
                var observations:[BehaviorObservation]=[],oldObservations:[BehaviorObservation]=[]
                engine.observationObserver={
                    observations.append($0);journal.observe($0,at:Date(timeIntervalSince1970:1_700_000_000+$0.simulationTime))
                }
                control.observationObserver={
                    oldObservations.append($0);baseline.observe($0,at:Date(timeIntervalSince1970:1_700_000_000+$0.simulationTime))
                }
                for kind in kinds {
                    let run=try start(kind,in:engine,source:source),other=try start(kind,in:control,source:source)
                    advance(engine,seconds:8);advance(control,seconds:8)
                    released(engine,run,type:.completed);released(control,other,type:.completed)
                    XCTAssertEqual(events(engine),events(control))
                    XCTAssertEqual(engine.birds[0].position,control.birds[0].position)
                    XCTAssertEqual(engine.birds[0].motionRevision,control.birds[0].motionRevision)
                    XCTAssertEqual(engine.ecology(of:engine.birds[0])?.cooldowns,
                        control.ecology(of:control.birds[0])?.cooldowns)
                }
                XCTAssertEqual(observations,oldObservations);XCTAssertEqual(observations.count,4)
                XCTAssertEqual(journal.archive,baseline.archive)
                XCTAssertEqual(journal.archive.entries.count,4)
                XCTAssertEqual(journal.archive.entries.reduce(0){$0+$1.totalCount},4)
                XCTAssertTrue(journal.archive.entries.allSatisfy{
                    $0.totalCount==1 && $0.previewCount==(source == .preview ? 1:0)
                        && $0.automaticCount==(source == .automatic ? 1:0) && $0.userCount==0
                })
                XCTAssertEqual(engine.residentCount,1);XCTAssertEqual(engine.arrivalCount,0)
                for _ in 0..<8 {XCTAssertEqual(engine.random.unit(),control.random.unit())}
            }
        }
    }

    func testOptionalArtCannotReplaceRequiredLegacyFramesOrBypassFeatureSettings() throws {
        let requirements:[(BehaviorKind,String)] = [(.watch,"blink"),(.alert,"stand"),
            (.rest,"blink"),(.takeoffPreparation,"fly0")]
        for bird in species {
            for (kind,missing) in requirements {
                let engine=fixture(bird),run=try start(kind,in:engine)
                advance(engine,seconds:0.2);engine.handle(.pause(true))
                var world=engine.world;world.availableFrames[bird]?.remove(missing)
                engine.updateWorld(world)
                released(engine,run,type:.failed,reason:.missingFrames)
                XCTAssertEqual(engine.leasedBirdCount,0)
                engine.handle(.pause(false))
                XCTAssertEqual(engine.handle(command(kind,.preview)),.rejected(.missingFrames))
                XCTAssertEqual(engine.activeRunCount,0)
            }
            for kind:BehaviorKind in [.watch,.alert,.takeoffPreparation] {
                let engine=fixture(bird),run=try start(kind,in:engine)
                advance(engine,seconds:0.2);engine.handle(.pause(true))
                var settings=engine.settings
                if kind == .takeoffPreparation {settings.takeoffPreparationEnabled=false}
                else {settings.passiveAttentionEnabled=false}
                engine.applySettings(settings)
                released(engine,run,type:.cancelled,reason:.settingsChanged)
                engine.handle(.pause(false))
                for source:BehaviorSource in [.preview,.automatic] {
                    XCTAssertEqual(engine.handle(command(kind,source)),.rejected(.disabled))
                }
            }
        }
    }

    func testEmptyPopulationRejectsInsteadOfCreatingPreviewResidents() {
        for kind in kinds {
            for source:BehaviorSource in [.preview,.automatic] {
                let engine=fixture(),probabilities=engine.settings.probabilities
                engine.installFixtureBirds([])
                XCTAssertEqual(engine.handle(command(kind,source)),.rejected(.unavailableBird))
                XCTAssertEqual(engine.events.last?.type,.rejected)
                XCTAssertNil(engine.events.last?.runID)
                XCTAssertTrue(engine.birds.isEmpty);XCTAssertTrue(engine.renderSnapshot().isEmpty)
                XCTAssertEqual(engine.activeRunCount,0);XCTAssertEqual(engine.leasedBirdCount,0)
                XCTAssertEqual(engine.arrivalCount,0);XCTAssertEqual(engine.settings.probabilities,probabilities)
            }
        }
    }

    func testUnlistedSpeciesKeepOldPresentationEvenWithInjectedEnhancementFrames() throws {
        XCTAssertEqual(species.count,12)
        XCTAssertEqual(SpeciesID.allCases.filter{!species.contains($0)}.count,34)
        for bird in SpeciesID.allCases where !species.contains(bird) {
            for kind in kinds {
                // Takeoff preparation requires a top-edge destination for every
                // species, including the woodpecker. Keep the public preview
                // command and real planner; constrain only this fixture's hosts.
                let engine=fixture(bird,topOnly:true),control=fixture(bird,enhanced:false,topOnly:true)
                let run=try start(kind,in:engine),other=try start(kind,in:control)
                for _ in 0..<6*60 {
                    XCTAssertEqual(engine.renderSnapshot().first?.frameName,control.renderSnapshot().first?.frameName)
                    XCTAssertFalse(poseFrames.contains(try XCTUnwrap(engine.renderSnapshot().first).frameName))
                    engine.advance(BehaviorEngine.step);control.advance(BehaviorEngine.step)
                }
                released(engine,run,type:.completed);released(control,other,type:.completed)
                XCTAssertEqual(events(engine),events(control))
            }
        }
    }

    func testNaturalRestAndExpiredDwellUseEnhancementWithoutPreviewOrExtraResidents() throws {
        for bird in species {
            let resting=fixture(bird),model=resting.birds[0]
            resting.ambientEnabled=true
            var sawRest=false
            for _ in 0..<40*60 {
                resting.advance(BehaviorEngine.step)
                if resting.behavior(of:model) == .rest {
                    sawRest=true
                    XCTAssertTrue(["restLower","restTuck","restWake"].contains(try XCTUnwrap(resting.renderSnapshot().first).frameName))
                }
            }
            XCTAssertTrue(sawRest,bird.rawValue)
            XCTAssertTrue(resting.events.contains{$0.type == .completed && $0.kind == .rest && $0.source == .automatic})
            XCTAssertEqual(resting.residentCount,1);XCTAssertEqual(resting.arrivalCount,0)

            let departing=fixture(bird),resident=departing.birds[0]
            resident.perchDuration=0;departing.autonomousRouting=true
            departing.advance(BehaviorEngine.step)
            XCTAssertEqual(departing.behavior(of:resident),.takeoffPreparation)
            XCTAssertEqual(departing.renderSnapshot().first?.frameName,"takeoffCrouch")
            XCTAssertEqual(departing.events.last?.source,.automatic)
            departing.autonomousRouting=false
            advance(departing,seconds:0.3)
            XCTAssertEqual(departing.renderSnapshot().first?.frameName,"takeoffPush")
            advance(departing,seconds:0.15)
            XCTAssertEqual(resident.state,.flying)
            XCTAssertEqual(departing.events.filter{$0.kind == .takeoffPreparation && $0.type == .completed}.count,1)
            XCTAssertEqual(departing.residentCount,1);XCTAssertEqual(departing.arrivalCount,0)
        }
    }

    func testNaturalPointerPerceptionStartsEnhancedWatchAndAlert() throws {
        for bird in species {
            var watches=0
            // Fixed sample, not a search for a passing seed. Every sampled run
            // must stay on the existing resident and complete on its own clock.
            for seed:UInt64 in 1...8 {
                let engine=fixture(bird,seed:seed),model=engine.birds[0]
                engine.ambientEnabled=true
                var world=engine.world
                let radius=max(100,72*engine.spriteScale(for:model))
                world.pointer=CGPoint(x:model.position.x+radius*1.5,y:model.position.y)
                engine.updateWorld(world)
                engine.advance(BehaviorEngine.step)
                let starts=engine.events.filter{$0.type == .started && $0.kind == .watch}
                watches+=starts.count
                if let start=starts.first {
                    XCTAssertEqual(start.source,.automatic)
                    XCTAssertEqual(engine.renderSnapshot().first?.frameName,"lookNear")
                    advance(engine,seconds:0.3)
                    XCTAssertEqual(engine.renderSnapshot().first?.frameName,"lookFar")
                    advance(engine,seconds:3)
                    released(engine,try XCTUnwrap(start.runID),type:.completed)
                }
                XCTAssertEqual(engine.residentCount,1);XCTAssertEqual(engine.arrivalCount,0)
            }
            XCTAssertGreaterThan(watches,0,bird.rawValue)

            let engine=fixture(bird,seed:81),origin=engine.birds[0].position
            engine.ambientEnabled=true
            var world=engine.world
            world.pointer=CGPoint(x:origin.x-400,y:origin.y-20);engine.updateWorld(world)
            advance(engine,seconds:0.5)
            var seen=Set<String>()
            for index in 1...60 {
                world.pointer=CGPoint(x:origin.x-400+CGFloat(index)*800/60,y:origin.y-20)
                engine.updateWorld(world);engine.advance(BehaviorEngine.step)
                if engine.behavior(of:engine.birds[0]) == .alert {
                    seen.insert(try XCTUnwrap(engine.renderSnapshot().first).frameName)
                }
            }
            for _ in 0..<3*60 {
                if engine.behavior(of:engine.birds[0]) == .alert {
                    seen.insert(try XCTUnwrap(engine.renderSnapshot().first).frameName)
                }
                engine.advance(BehaviorEngine.step)
            }
            let alert=try XCTUnwrap(engine.events.first{$0.kind == .alert && $0.type == .started})
            XCTAssertEqual(alert.source,.automatic)
            XCTAssertEqual(seen,["alertRise","alertHold","alertRelax"])
            released(engine,try XCTUnwrap(alert.runID),type:.completed)
            XCTAssertEqual(engine.residentCount,1);XCTAssertEqual(engine.arrivalCount,0)
        }
    }

    func testThirtySixtyAndOneHundredTwentyHzPreserveEnhancedPosesAndSemanticEvents() throws {
        struct Trace:Equatable {
            let frame:String,position:CGPoint,facing:Bool,hop:CGFloat
            let events:[String],counts:[Int]
        }
        func replay(_ bird:SpeciesID,_ kind:BehaviorKind,_ hz:Int) throws -> [Trace] {
            let engine=fixture(bird),run=try start(kind,in:engine,source:.automatic)
            var trace:[Trace]=[]
            for sample in 0..<40 {
                if sample==1 {engine.handle(.pause(true))}
                if sample==4 {engine.handle(.pause(false))}
                advance(engine,seconds:0.2,hz:hz)
                let pose=try XCTUnwrap(engine.renderSnapshot().first)
                trace.append(Trace(frame:pose.frameName,position:pose.position,facing:pose.facingRight,hop:pose.hopOffset,
                    events:events(engine),counts:[engine.activeRunCount,engine.leasedBirdCount,
                        engine.reservedLandingCount,engine.residentCount,engine.arrivalCount,engine.scenePropCount]))
            }
            released(engine,run,type:.completed);return trace
        }
        for bird in species {
            for kind in kinds {
                let baseline=try replay(bird,kind,60)
                XCTAssertEqual(try replay(bird,kind,30),baseline,"\(bird): \(kind)")
                XCTAssertEqual(try replay(bird,kind,120),baseline,"\(bird): \(kind)")
            }
        }
    }
}
