import XCTest
@testable import BirdingCore

final class PerchActivityTests: XCTestCase {
    private let screen=CGRect(x:-1200,y:-400,width:3000,height:1800)
    private let host=Surface(id:71,rect:CGRect(x:-900,y:800,width:2300,height:400))

    private func fixture(seed:UInt64=73,count:Int=1,automatic:Bool=false,enabled:Bool=true) -> BehaviorEngine {
        var settings=BirdSettings()
        settings.pointerVisits=false;settings.flockPasses=false;settings.perchActions=enabled
        let engine=BehaviorEngine(seed:seed,settings:settings)
        engine.populationEnabled=false;engine.ambientEnabled=automatic
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],
            pointer:CGPoint(x:0,y:0),availableFrames:Dictionary(uniqueKeysWithValues:
                SpeciesID.allCases.map{($0,Set(["stand","breathe","blink","preen0","preen1",
                    "land0","land1","land2","idle0","idle1","idle2","stretch","shake","poop0","poop1",
                    "cling0","cling1","peck0","peck1","glide0","glide1","glide2","bank0","bank1","bank2","bound"]
                    + (0...7).map{"fly\($0)"}))})))
        engine.installFixtureBirds((0..<count).map { index in
            let bird=Bird(position:.zero,fraction:CGFloat(index+1)/CGFloat(count+1),
                profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
            bird.perch(on:host);bird.perchDuration=600
            return bird
        })
        return engine
    }

    private func advance(_ engine:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {engine.advance(1/Double(hz))}
    }

    private func started(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let id)=result else {
            XCTFail("Expected a started perch activity, got \(result)",file:file,line:line)
            throw NSError(domain:"PerchActivityTests",code:1)
        }
        return id
    }

    private func terminals(_ engine:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }

    private func assertTerminal(_ engine:BehaviorEngine,_ run:BehaviorRunID,type:BehaviorEventType,
                                reason:BehaviorReason?=nil,file:StaticString=#filePath,line:UInt=#line) {
        let events=terminals(engine,run)
        XCTAssertEqual(events.count,1,file:file,line:line)
        XCTAssertEqual(events.first?.type,type,file:file,line:line)
        XCTAssertEqual(events.first?.reason,reason,file:file,line:line)
        XCTAssertNil(engine.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(engine.runtime.owners.values.contains(run),file:file,line:line)
    }

    func testBothPreviewsRenderTheirFramesAndCompleteOnce() throws {
        for action in PerchActionKind.allCases {
            let e=fixture(),bird=e.birds[0],origin=e.birds[0].position
            let revision=bird.motionRevision,id=try XCTUnwrap(e.id(of:bird))
            let run=try started(e.handle(.perchAction(action,.preview)))
            XCTAssertEqual(e.behavior(of:bird),action == .rest ? .rest:.preen)
            XCTAssertEqual(e.events.last?.participants,[id]);XCTAssertEqual(e.events.last?.source,.preview)
            XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
            XCTAssertFalse(e.ambientBusy)
            XCTAssertEqual(e.handle(.perchAction(action,.preview)),.rejected(.busy))
            var frames=Set<String>()
            for _ in 0..<6*60 {
                if e.runtime.runs[run] != nil {
                    let state=try XCTUnwrap(e.renderSnapshot().first)
                    frames.insert(state.frameName)
                    XCTAssertEqual(state.position,origin);XCTAssertTrue(state.hoverable)
                    XCTAssertTrue(e.world.availableFrames[bird.profile.id]!.contains(state.frameName))
                }
                e.advance(BehaviorEngine.step)
            }
            let expected:Set<String> = action == .rest ? ["stand","blink"]:["stand","preen0","preen1"]
            XCTAssertEqual(frames,expected)
            assertTerminal(e,run,type:.completed)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
            advance(e,seconds:2);assertTerminal(e,run,type:.completed)
        }
    }

    func testPointerApproachAndBothClickInputsCancelExactlyOnce() throws {
        for action in PerchActionKind.allCases {
            for input in ["approach","buttonState","clickCommand"] {
                let e=fixture(),bird=e.birds[0]
                let run=try started(e.handle(.perchAction(action,.preview)))
                advance(e,seconds:0.5)
                // Moving elsewhere on the desktop must not interrupt a perched bird.
                var world=e.world;world.pointer.x+=300;e.updateWorld(world)
                e.advance(BehaviorEngine.step)
                XCTAssertTrue(terminals(e,run).isEmpty)
                let origin=bird.position,revision=bird.motionRevision
                switch input {
                case "approach":world.pointer=CGPoint(x:origin.x+50,y:origin.y);e.updateWorld(world)
                case "buttonState":world.buttonsDown=true;e.updateWorld(world)
                default:e.handle(.pointerClick)
                }
                e.advance(BehaviorEngine.step)
                let reason:BehaviorReason=input == "approach" ? .pointerNearby:.userInput
                assertTerminal(e,run,type:.cancelled,reason:reason)
                XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
                XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
                e.handle(.pointerClick);advance(e,seconds:6)
                assertTerminal(e,run,type:.cancelled,reason:reason)
                XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.renderSnapshot().count,1)
            }
        }
    }

    func testDisablingActivitiesCancelsImmediatelyAndUsesSharedPreviewAutomaticGate() throws {
        for action in PerchActionKind.allCases {
            let e=fixture(),bird=e.birds[0]
            let run=try started(e.handle(.perchAction(action,.preview)))
            advance(e,seconds:0.6)
            var settings=e.settings;settings.perchActions=false;e.applySettings(settings)
            assertTerminal(e,run,type:.cancelled,reason:.settingsChanged)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
            for source:BehaviorSource in [.preview,.automatic] {
                XCTAssertEqual(e.handle(.perchAction(action,source)),.rejected(.disabled))
                XCTAssertEqual(e.events.last?.reason,.disabled);XCTAssertEqual(e.events.last?.source,source)
            }
            e.ambientEnabled=true;advance(e,seconds:40)
            XCTAssertEqual(e.events.filter{$0.type == .started}.count,1)
            e.ambientEnabled=false;settings.perchActions=true;e.applySettings(settings)
            advance(e,seconds:2)
            assertTerminal(e,run,type:.cancelled,reason:.settingsChanged)
            XCTAssertEqual(e.activeRunCount,0)
            _=try started(e.handle(.perchAction(action,.preview)))
        }
    }

    func testLostOrOccludedHostReleasesPoseWithoutGhostsOrDuplicateTerminal() throws {
        for action in PerchActionKind.allCases {
            for removeHost in [true,false] {
                let e=fixture(),bird=e.birds[0]
                let run=try started(e.handle(.perchAction(action,.preview)))
                advance(e,seconds:0.6)
                let origin=bird.position
                var world=e.world
                world.surfaces=removeHost ? []:[Surface(id:72,rect:Geometry.landingFootprint(at:origin,scale:2)),host]
                e.updateWorld(world,sampleDT:1.0/30)
                XCTAssertEqual(bird.position,origin)
                e.advance(BehaviorEngine.step)
                assertTerminal(e,run,type:.failed,reason:.targetInvalid)
                XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.renderSnapshot().count,1)
                XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
                if removeHost {XCTAssertEqual(bird.state,.flying)}
                e.handle(.pointerClick);advance(e,seconds:6)
                assertTerminal(e,run,type:.failed,reason:.targetInvalid)
            }
        }
    }

    func testScreenSleepAndRemovalCleanupAreIdempotent() throws {
        for action in PerchActionKind.allCases {
            for reason:BehaviorReason in [.screensChanged,.sleep,.spaceChanged,.shutdown,.removed] {
                let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:e.birds[0]))
                let run=try started(e.handle(.perchAction(action,.preview)))
                advance(e,seconds:0.6)
                for _ in 0..<2 {
                    if reason == .removed {e.handle(.remove(id))}
                    else {e.handle(.cancelAmbient(reason))}
                }
                advance(e,seconds:6)
                assertTerminal(e,run,type:.cancelled,reason:reason)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                if reason == .removed {
                    XCTAssertNil(e.bird(id));XCTAssertNil(e.perchPlanner.rhythms[id])
                    XCTAssertTrue(e.renderSnapshot().isEmpty)
                    XCTAssertEqual(e.events.filter{$0.type == .birdRemoved && $0.participants == [id]}.count,1)
                } else {
                    XCTAssertTrue(e.bird(id) === bird);XCTAssertEqual(e.renderSnapshot().count,1)
                    XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
                }
            }
        }
    }

    func testPauseFreezesPoseAndRemainingDurationThenResumesAtSameStep() throws {
        for action in PerchActionKind.allCases {
            let paused=fixture(),control=fixture(),bird=paused.birds[0]
            let run=try started(paused.handle(.perchAction(action,.preview)))
            let other=try started(control.handle(.perchAction(action,.preview)))
            advance(paused,seconds:0.6);advance(control,seconds:0.6)
            let pose=try XCTUnwrap(paused.renderSnapshot().first)
            let age=try XCTUnwrap(paused.runtime.runs[run]).age,stateTime=bird.stateTime
            paused.handle(.pause(true));advance(paused,seconds:12)
            XCTAssertEqual(paused.runtime.runs[run]?.age,age)
            XCTAssertEqual(bird.stateTime,stateTime);XCTAssertEqual(bird.position,pose.position)
            XCTAssertEqual(paused.renderSnapshot().first?.frameName,pose.frameName)
            XCTAssertEqual(paused.renderSnapshot().first?.hopOffset,pose.hopOffset)
            XCTAssertTrue(terminals(paused,run).isEmpty)
            XCTAssertEqual(paused.handle(.perchAction(action,.preview)),.rejected(.paused))
            paused.handle(.pause(false))
            var finishStep:Int?
            for step in 0..<6*60 {
                paused.advance(BehaviorEngine.step);control.advance(BehaviorEngine.step)
                XCTAssertEqual(paused.renderSnapshot().first?.frameName,control.renderSnapshot().first?.frameName)
                XCTAssertEqual(paused.renderSnapshot().first?.hopOffset,control.renderSnapshot().first?.hopOffset)
                XCTAssertEqual(terminals(paused,run).isEmpty,terminals(control,other).isEmpty)
                if !terminals(paused,run).isEmpty {finishStep=step;break}
            }
            XCTAssertNotNil(finishStep)
            assertTerminal(paused,run,type:.completed);assertTerminal(control,other,type:.completed)
            let finish=try XCTUnwrap(terminals(paused,run).first),baseline=try XCTUnwrap(terminals(control,other).first)
            XCTAssertEqual(finish.time-baseline.time,12,accuracy:0.000001)
        }
    }

    func testPausedWorldInvalidationImmediatelyReleasesActivityWithoutResume() throws {
        for action in PerchActionKind.allCases {
            for missingHost in [true,false] {
                for sampleHost in [false,true] {
                    let e=fixture(),bird=e.birds[0]
                    let run=try started(e.handle(.perchAction(action,.preview)))
                    advance(e,seconds:0.6)
                    e.handle(.pause(true))
                    let clock=e.time,originalWorld=e.world
                    var invalidWorld=originalWorld
                    if missingHost {invalidWorld.surfaces=[]}
                    else {invalidWorld.availableFrames[bird.profile.id]?.remove(action == .rest ? "blink":"preen1")}
                    let reason:BehaviorReason=missingHost ? .targetInvalid:.missingFrames
                    e.updateWorld(invalidWorld,sampleDT:sampleHost ? 1.0/30:nil)
                    // No advance, resume, or render call may be required to release ownership.
                    XCTAssertTrue(e.paused);XCTAssertEqual(e.time,clock)
                    assertTerminal(e,run,type:.failed,reason:reason)
                    XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                    XCTAssertNil(e.behavior(of:bird));XCTAssertEqual(e.renderSnapshot().count,1)
                    e.updateWorld(invalidWorld)
                    advance(e,seconds:3)
                    assertTerminal(e,run,type:.failed,reason:reason)
                    e.updateWorld(originalWorld)
                    e.handle(.pause(false));advance(e,seconds:6)
                    assertTerminal(e,run,type:.failed,reason:reason)
                    XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                }
            }
        }
    }

    func testCancellingRestPreservesInstantHopThenBlendsUnlessFlightTakesOver() throws {
        for disable in [false,true] {
            for relocateDuringRecovery in [false,true] {
                let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:e.birds[0]))
                let run=try started(e.handle(.perchAction(.rest,.preview)))
                advance(e,seconds:1.25)
                let before=try XCTUnwrap(e.renderSnapshot().first),clock=e.time
                XCTAssertEqual(bird.stateTime,1.25,accuracy:0.000001)
                XCTAssertEqual(bird.hopOffset,-3,accuracy:0.000001)
                XCTAssertEqual(before.hopOffset,0,accuracy:0.000001)
                if disable {var settings=e.settings;settings.perchActions=false;e.applySettings(settings)}
                else {e.handle(.pointerClick)} // Click elsewhere: do not relocate the bird yet.
                let reason:BehaviorReason=disable ? .settingsChanged:.userInput
                assertTerminal(e,run,type:.cancelled,reason:reason)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                XCTAssertEqual(e.time,clock)
                let immediate=try XCTUnwrap(e.renderSnapshot().first)
                XCTAssertEqual(immediate.hopOffset,before.hopOffset,accuracy:0.000001)
                XCTAssertEqual(immediate.position,before.position);XCTAssertEqual(immediate.rect,before.rect)
                XCTAssertEqual(e.bounds(of:bird),immediate.rect.insetBy(dx:-2,dy:-2))

                // Inspect the middle of the recovery, where the live idle hop is
                // still nonzero. A delayed snap and an immediate snap both fail.
                var previousHop=immediate.hopOffset,previousBlend:CGFloat=0
                for _ in 0..<6 {
                    e.advance(BehaviorEngine.step)
                    let snapshot=try XCTUnwrap(e.renderSnapshot().first)
                    XCTAssertEqual(snapshot.position,before.position)
                    XCTAssertLessThan(abs(snapshot.hopOffset-previousHop),1)
                    XCTAssertGreaterThan(snapshot.hopOffset,bird.hopOffset)
                    XCTAssertLessThan(snapshot.hopOffset,0)
                    let blend=snapshot.hopOffset/bird.hopOffset
                    XCTAssertGreaterThan(blend,previousBlend);XCTAssertLessThan(blend,1)
                    XCTAssertEqual(e.bounds(of:bird),snapshot.rect.insetBy(dx:-2,dy:-2))
                    previousHop=snapshot.hopOffset;previousBlend=blend
                }

                if relocateDuringRecovery {
                    let move=try started(e.handle(.relocate(id)))
                    XCTAssertEqual(bird.position,before.position);XCTAssertEqual(bird.state,.flying)
                    XCTAssertEqual(e.behavior(of:bird),.relocate)
                    XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
                    XCTAssertEqual(e.renderSnapshot().first?.hopOffset,0)
                    XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
                    for _ in 0..<12 {
                        e.advance(BehaviorEngine.step)
                        XCTAssertEqual(bird.state,.flying)
                        XCTAssertEqual(e.renderSnapshot().first?.hopOffset,0)
                        XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
                    }
                    advance(e,seconds:10)
                    assertTerminal(e,move,type:.completed)
                } else {
                    // Thirteen total steps are just beyond 0.2 seconds, before
                    // the underlying hop reaches zero at stateTime 1.5 seconds.
                    for _ in 0..<7 {e.advance(BehaviorEngine.step)}
                    let settled=try XCTUnwrap(e.renderSnapshot().first)
                    XCTAssertLessThan(bird.hopOffset,-0.5)
                    XCTAssertEqual(settled.hopOffset,bird.hopOffset,accuracy:0.000001)
                    XCTAssertEqual(settled.position,before.position)
                    advance(e,seconds:0.1)
                }
                let finalPose=try XCTUnwrap(e.renderSnapshot().first)
                XCTAssertEqual(finalPose.hopOffset,bird.hopOffset,accuracy:0.000001)
                assertTerminal(e,run,type:.cancelled,reason:reason)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            }
        }
    }

    func testMissingFramesRejectTypedAndRuntimeFrameLossKeepsBirdVisible() throws {
        for action in PerchActionKind.allCases {
            let missing=action == .rest ? "blink":"preen1"
            let e=fixture(),bird=e.birds[0]
            // Do not advance to a convenient idle frame: at age zero the old
            // idle pose is blink, which itself may be the missing asset. A typed
            // rejection must still leave a drawable fallback such as stand.
            let origin=bird.position
            var world=e.world;world.availableFrames[bird.profile.id]?.remove(missing);e.updateWorld(world)
            for source:BehaviorSource in [.preview,.automatic] {
                XCTAssertEqual(e.handle(.perchAction(action,source)),.rejected(.missingFrames))
                XCTAssertEqual(e.events.last?.reason,.missingFrames)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                let visible=try XCTUnwrap(e.renderSnapshot().first)
                XCTAssertEqual(visible.position,origin)
                XCTAssertTrue(world.availableFrames[bird.profile.id]!.contains(visible.frameName))
            }
            world.availableFrames[bird.profile.id]?.insert(missing);e.updateWorld(world)
            let run=try started(e.handle(.perchAction(action,.preview)))
            advance(e,seconds:0.4)
            world.availableFrames[bird.profile.id]?.remove(missing);e.updateWorld(world)
            let fallback=try XCTUnwrap(e.renderSnapshot().first)
            XCTAssertEqual(fallback.frameName,bird.frameName)
            XCTAssertTrue(world.availableFrames[bird.profile.id]!.contains(fallback.frameName))
            e.advance(BehaviorEngine.step)
            assertTerminal(e,run,type:.failed,reason:.missingFrames)
            XCTAssertEqual(e.renderSnapshot().count,1);XCTAssertEqual(e.leasedBirdCount,0)
            e.handle(.pointerClick);advance(e,seconds:6)
            assertTerminal(e,run,type:.failed,reason:.missingFrames)
        }
        let empty=fixture();var world=empty.world;world.availableFrames=[:];empty.updateWorld(world)
        for action in PerchActionKind.allCases {
            XCTAssertEqual(empty.handle(.perchAction(action,.preview)),.rejected(.missingFrames))
        }
        XCTAssertEqual(empty.renderSnapshot().count,1)
        world.availableFrames[empty.birds[0].profile.id] = ["preen1","preen0"]
        empty.updateWorld(world)
        XCTAssertEqual(empty.renderSnapshot().first?.frameName,"preen0",
            "A partial manifest without stand still has a deterministic drawable fallback")
    }

    func testReplayIsIdenticalAt30And60And120Hz() throws {
        struct Trace:Equatable {
            let positions:[CGPoint],hops:[CGFloat],frames:[String],events:[String],counts:[Int]
        }
        func replay(_ hz:Int) throws -> [Trace] {
            let e=fixture(count:3,automatic:true)
            var trace:[Trace]=[]
            for second in 0..<60 {
                switch second {
                case 0:_=try started(e.handle(.perchAction(.rest,.preview)))
                case 1:_=try started(e.handle(.perchAction(.preen,.preview)))
                case 2:e.handle(.pause(true))
                case 4:e.handle(.pause(false))
                case 6:e.handle(.pointerClick)
                default:break
                }
                advance(e,seconds:1,hz:hz)
                let states=e.renderSnapshot()
                trace.append(Trace(positions:states.map(\.position),hops:states.map(\.hopOffset),frames:states.map(\.frameName),
                    events:e.events.map{"\($0.sequence):\($0.time):\($0.runID?.rawValue ?? 0):\($0.type):\($0.kind?.rawValue ?? ""):\($0.source):\($0.reason?.rawValue ?? ""):\($0.participants.map(\.rawValue))"},
                    counts:[e.activeRunCount,e.leasedBirdCount,e.residentCount]))
            }
            XCTAssertTrue(e.events.contains{$0.type == .started && $0.kind == .rest && $0.source == .automatic})
            return trace
        }
        let reference=try replay(60)
        XCTAssertEqual(try replay(30),reference);XCTAssertEqual(try replay(120),reference)
    }

    func testAutomaticSchedulingIsOptInAndIndividualRhythmsAreStaggered() throws {
        let e=fixture(count:4)
        advance(e,seconds:40)
        XCTAssertFalse(e.events.contains{$0.type == .started})
        e.ambientEnabled=true
        advance(e,seconds:40)
        let starts=e.events.filter{$0.type == .started && $0.kind == .rest && $0.source == .automatic}
        var firstTimes:[Double]=[],durations:[Double]=[]
        for bird in e.birds {
            let id=try XCTUnwrap(e.id(of:bird))
            let first=try XCTUnwrap(starts.first{$0.participants == [id]})
            let run=try XCTUnwrap(first.runID)
            let end=try XCTUnwrap(terminals(e,run).first)
            firstTimes.append(first.time);durations.append(end.time-first.time)
            assertTerminal(e,run,type:.completed)
        }
        XCTAssertGreaterThan(Set(firstTimes).count,1,"Birds must not all start on one shared timer")
        XCTAssertGreaterThan(Set(durations).count,1,"Activity durations should vary between individuals")
        XCTAssertTrue(e.events.filter{$0.type == .started}.allSatisfy{$0.kind == .rest})
    }

    func testNaturalLandingCanPreenOnlyOnceAndDirectPerchDoesNotFakeLanding() throws {
        let stationary=fixture(automatic:true)
        advance(stationary,seconds:40)
        XCTAssertEqual(stationary.birds[0].landedCount,0)
        XCTAssertFalse(stationary.events.contains{$0.type == .started && $0.kind == .preen})
        var totalPreens=0
        // Fixed seeds exercise both probabilistic outcomes without searching for a passing seed.
        for seed:UInt64 in 1...8 {
            let e=fixture(seed:seed,automatic:true),bird=e.birds[0]
            bird.fraction=0.75
            let destination=Geometry.foot(on:host,fraction:bird.fraction,edge:.top)
            bird.fly(to:destination,host:host,duration:1.2,urgent:true,random:{0.5})
            var firstPerchedAt:Double?
            for _ in 0..<8*60 {
                e.advance(BehaviorEngine.step)
                if firstPerchedAt == nil && bird.state == .perched {firstPerchedAt=e.time}
            }
            XCTAssertEqual(bird.landedCount,1);XCTAssertEqual(bird.position,destination)
            let perchedAt=try XCTUnwrap(firstPerchedAt)
            let preens=e.events.filter{$0.type == .started && $0.kind == .preen && $0.source == .automatic}
            XCTAssertLessThanOrEqual(preens.count,1)
            for event in preens {
                XCTAssertGreaterThan(event.time,perchedAt)
                assertTerminal(e,try XCTUnwrap(event.runID),type:.completed)
            }
            totalPreens+=preens.count
            advance(e,seconds:30)
            XCTAssertEqual(bird.landedCount,1)
            XCTAssertEqual(e.events.filter{$0.type == .started && $0.kind == .preen}.count,preens.count,
                "A settled bird must not replay the same landing's preen opportunity")
        }
        XCTAssertGreaterThan(totalPreens,0,"The fixed seed sample must exercise actual natural-landing preening")
    }

    func testPerchActivitiesDoNotConsumeOriginalFlightRandomStream() throws {
        for automatic in [false,true] {
            let active=fixture(automatic:automatic),control=fixture(automatic:automatic,enabled:false)
            if automatic {
                // Both engines cross the old ambient scheduler's 180-second boundary.
                advance(active,seconds:210);advance(control,seconds:210)
                XCTAssertTrue(active.events.contains{$0.type == .started && $0.source == .automatic})
            } else {
                for action in PerchActionKind.allCases {
                    _=try started(active.handle(.perchAction(action,.preview)))
                    advance(active,seconds:6);advance(control,seconds:6)
                }
            }
            XCTAssertFalse(control.events.contains{$0.type == .started})
            for _ in 0..<16 {XCTAssertEqual(active.random.unit(),control.random.unit())}
            active.ambientEnabled=false;control.ambientEnabled=false
            _=try started(active.handle(.relocate(try XCTUnwrap(active.id(of:active.birds[0])))))
            _=try started(control.handle(.relocate(try XCTUnwrap(control.id(of:control.birds[0])))))
            XCTAssertEqual(active.birds[0].flightDuration,control.birds[0].flightDuration)
            for _ in 0..<10*60 {
                active.advance(BehaviorEngine.step);control.advance(BehaviorEngine.step)
                XCTAssertEqual(active.birds[0].position,control.birds[0].position)
                XCTAssertEqual(active.birds[0].state,control.birds[0].state)
                XCTAssertEqual(active.renderSnapshot().first?.frameName,control.renderSnapshot().first?.frameName)
            }
        }
    }

    func testPoseBlendsHopWithoutMovingFootAndSnapshotsRemainValues() throws {
        for action in PerchActionKind.allCases {
            let e=fixture(),bird=e.birds[0]
            advance(e,seconds:1.25)
            let original=try XCTUnwrap(e.renderSnapshot().first),anchor=bird.position
            XCTAssertLessThan(original.hopOffset,-2)
            let run=try started(e.handle(.perchAction(action,.preview)))
            XCTAssertEqual(e.renderSnapshot().first?.hopOffset,original.hopOffset)
            advance(e,seconds:0.4)
            let pose=try XCTUnwrap(e.renderSnapshot().first)
            XCTAssertEqual(pose.hopOffset,0,accuracy:0.000001)
            XCTAssertLessThan(bird.hopOffset,-1,"Fixture must retain underlying idle hop while the overlay plants the feet")
            XCTAssertEqual(pose.position,anchor);XCTAssertEqual(pose.facingRight,original.facingRight)
            XCTAssertEqual(pose.rect.minY+(39-pose.hopOffset)*pose.scale,anchor.y,accuracy:0.000001)
            for _ in 0..<6*60 {
                let snapshot=try XCTUnwrap(e.renderSnapshot().first)
                XCTAssertEqual(snapshot.position,anchor)
                XCTAssertEqual(e.bounds(of:bird),snapshot.rect.insetBy(dx:-2,dy:-2))
                e.advance(BehaviorEngine.step)
            }
            assertTerminal(e,run,type:.completed)
            e.handle(.remove(original.id))
            XCTAssertTrue(e.renderSnapshot().isEmpty)
            XCTAssertEqual(original.position,anchor);XCTAssertLessThan(original.hopOffset,-2)
            XCTAssertEqual(pose.position,anchor);XCTAssertEqual(pose.hopOffset,0)
            XCTAssertEqual(pose.frameName,action == .rest ? "blink":"preen0")
        }
    }

    func testRelocatePreemptsPerchPoseAtCurrentPositionAndOwnsOnlyOneLease() throws {
        for action in PerchActionKind.allCases {
            let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:e.birds[0]))
            let perch=try started(e.handle(.perchAction(action,.preview)))
            advance(e,seconds:0.6)
            let position=bird.position
            let relocation=try started(e.handle(.relocate(id)))
            assertTerminal(e,perch,type:.cancelled,reason:.replaced)
            XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.state,.flying)
            XCTAssertEqual(e.behavior(of:bird),.relocate)
            XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
            XCTAssertEqual(e.runtime.owners[id],relocation)
            XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
            XCTAssertEqual(e.renderSnapshot().first?.hopOffset,0)
            e.handle(.pointerClick)
            XCTAssertEqual(e.behavior(of:bird),.relocate)
            advance(e,seconds:10)
            assertTerminal(e,perch,type:.cancelled,reason:.replaced)
            assertTerminal(e,relocation,type:.completed)
            XCTAssertGreaterThan(Geometry.distance(position,bird.position),100)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
        }
    }

    func testShortPerchSidePerchDeparturesAndUnsafeWorldCannotStartActivities() {
        for scenario in ["short","side","departing","transient","pointer","buttons","offscreen"] {
            for action in PerchActionKind.allCases {
                let e=fixture(),bird=e.birds[0]
                var world=e.world
                let reason:BehaviorReason
                switch scenario {
                case "short":bird.perchDuration=7;reason = .unavailableBird
                case "side":bird.edge = .left;bird.perch(on:host);reason = .unavailableBird
                case "departing":bird.depart(to:CGPoint(x:screen.maxX+200,y:400),duration:3);reason = .unavailableBird
                case "transient":
                    e.installFixtureBirds([]);e.register(bird,role:.transient);reason = .unavailableBird
                case "pointer":world.pointer=bird.position;reason = .pointerNearby
                case "buttons":world.buttonsDown=true;reason = .userInput
                default:world.displays=[];reason = .noSpace
                }
                e.updateWorld(world)
                for source:BehaviorSource in [.preview,.automatic] {
                    XCTAssertEqual(e.handle(.perchAction(action,source)),.rejected(reason),"\(scenario), \(action), \(source)")
                    XCTAssertEqual(e.events.last?.source,source)
                    XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                    XCTAssertEqual(e.renderSnapshot().count,1)
                }
            }
        }
    }
}
