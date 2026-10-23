import XCTest
@testable import BirdingCore

final class AttentionActivityTests:XCTestCase {
    private let screen=CGRect(x:-1200,y:-400,width:3000,height:1800)
    private let host=Surface(id:71,pid:31,rect:CGRect(x:-900,y:800,width:2300,height:400))
    private var frames:Set<String> {Set(["stand","blink"]+(0...7).map{"fly\($0)"})}

    private func fixture(scale:CGFloat=1) -> BehaviorEngine {
        var settings=BirdSettings()
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        let engine=BehaviorEngine(seed:73,settings:settings)
        engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],scale:scale,
            pointer:CGPoint(x:0,y:0),availableFrames:Dictionary(uniqueKeysWithValues:
                SpeciesID.allCases.map{($0,frames)})))
        let bird=Bird(position:.zero,fraction:0.5,
            profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host);bird.perchDuration=600
        engine.installFixtureBirds([bird])
        return engine
    }

    private func advance(_ engine:BehaviorEngine,seconds:Double) {
        for _ in 0..<Int((seconds*60).rounded()) {engine.advance(BehaviorEngine.step)}
    }

    private func started(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let id)=result else {
            XCTFail("Expected attention to start, got \(result)",file:file,line:line)
            throw NSError(domain:"AttentionActivityTests",code:1)
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

    private func pointer(_ point:CGPoint,in engine:BehaviorEngine) {
        var world=engine.world;world.pointer=point;engine.updateWorld(world)
    }

    private func direct(_ kind:AttentionKind,in engine:BehaviorEngine,duration:Double=2,
                        requiresNearbyPointer:Bool=true) throws -> BehaviorRunID {
        let id=try XCTUnwrap(engine.id(of:engine.birds[0]))
        return try started(engine.runtime.start(AttentionExecution(id:id,kind:kind,duration:duration,
            requiresNearbyPointer:requiresNearbyPointer),source:.preview,in:engine))
    }

    func testKindsCapabilitiesAndDefaultSetting() {
        XCTAssertEqual(AttentionKind.allCases,[.watch,.alert])
        XCTAssertEqual(AttentionKind.watch.behavior,.watch);XCTAssertEqual(AttentionKind.alert.behavior,.alert)
        XCTAssertEqual(AttentionKind.watch.requiredFrames,["stand","blink"])
        XCTAssertEqual(AttentionKind.alert.requiredFrames,["stand"])
        XCTAssertTrue(BirdSettings().passiveAttentionEnabled)
        XCTAssertEqual(PerchActionKind.allCases,[.rest,.preen])
    }

    func testPreviewsStartFarFromPointerUseRealFramesAndFinishExactlyOnce() throws {
        for kind in AttentionKind.allCases {
            let e=fixture(),bird=e.birds[0],origin=bird.position,revision=bird.motionRevision
            let direction=bird.facingRight,id=try XCTUnwrap(e.id(of:bird))
            XCTAssertGreaterThan(Geometry.distance(e.world.pointer,origin),400)
            let run=try started(e.handle(.attention(kind,.preview)))
            XCTAssertEqual(e.behavior(of:bird),kind.behavior)
            XCTAssertEqual(e.events.last?.participants,[id]);XCTAssertEqual(e.events.last?.source,.preview)
            XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
            XCTAssertFalse(e.ambientBusy);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertEqual(e.scenePropCount,0)
            XCTAssertEqual(e.handle(.attention(kind,.preview)),.rejected(.busy))
            var seen=Set<String>(),blinkSteps=0,totalSteps=0
            for _ in 0..<4*60 {
                if let execution=e.runtime.runs[run]?.execution {
                    XCTAssertFalse(execution.occupiesEncounter);XCTAssertFalse(execution.runsWhilePaused)
                    let pose=try XCTUnwrap(e.renderSnapshot().first)
                    seen.insert(pose.frameName);totalSteps+=1
                    if pose.frameName == "blink" {blinkSteps+=1}
                    XCTAssertTrue(frames.contains(pose.frameName));XCTAssertTrue(pose.hoverable)
                    XCTAssertEqual(pose.position,origin);XCTAssertEqual(bird.position,origin)
                    XCTAssertEqual(bird.facingRight,direction);XCTAssertEqual(bird.motionRevision,revision)
                    XCTAssertEqual(pose.rect.minY+(39-pose.hopOffset)*pose.scale,origin.y,accuracy:0.000001)
                    XCTAssertEqual(e.bounds(of:bird),pose.rect.insetBy(dx:-2,dy:-2))
                    XCTAssertFalse(bird.isGliding)
                }
                e.advance(BehaviorEngine.step)
            }
            XCTAssertTrue(seen.contains("stand"));XCTAssertTrue(seen.contains("blink"))
            XCTAssertLessThanOrEqual(blinkSteps,11);XCTAssertLessThan(blinkSteps,totalSteps/2)
            assertTerminal(e,run,type:.completed)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.facingRight,direction)
            XCTAssertEqual(bird.motionRevision,revision)
            advance(e,seconds:2);assertTerminal(e,run,type:.completed)
            XCTAssertEqual(e.renderSnapshot().count,1)
            XCTAssertTrue(frames.contains(try XCTUnwrap(e.renderSnapshot().first).frameName))
        }
    }

    func testFacingUsesScaledHysteresisAndChangesOnlyDuringAdvance() throws {
        for scale:CGFloat in [1,2] {
            let e=fixture(scale:scale),bird=e.birds[0],origin=bird.position
            let size=e.spriteScale(for:bird),direction=bird.facingRight
            pointer(CGPoint(x:origin.x-100*size,y:origin.y),in:e)
            let run=try started(e.handle(.attention(.watch,.preview)))
            XCTAssertEqual(e.renderSnapshot().first?.facingRight,direction)
            e.advance(BehaviorEngine.step)
            XCTAssertEqual(e.renderSnapshot().first?.facingRight,false)
            for offset:CGFloat in [-23,-1,0,1,23] {
                pointer(CGPoint(x:origin.x+offset*size,y:origin.y),in:e)
                for _ in 0..<3 {
                    XCTAssertEqual(e.renderSnapshot().first?.facingRight,false)
                    _=e.bounds(of:bird)
                }
                e.advance(BehaviorEngine.step)
                XCTAssertEqual(e.renderSnapshot().first?.facingRight,false)
            }
            pointer(CGPoint(x:origin.x+25*size,y:origin.y),in:e)
            XCTAssertEqual(e.renderSnapshot().first?.facingRight,false)
            e.advance(BehaviorEngine.step)
            XCTAssertEqual(e.renderSnapshot().first?.facingRight,true)
            pointer(CGPoint(x:origin.x-23*size,y:origin.y),in:e)
            e.advance(BehaviorEngine.step)
            XCTAssertEqual(e.renderSnapshot().first?.facingRight,true)
            pointer(CGPoint(x:origin.x-25*size,y:origin.y),in:e)
            e.advance(BehaviorEngine.step)
            XCTAssertEqual(e.renderSnapshot().first?.facingRight,false)
            XCTAssertEqual(bird.facingRight,direction);XCTAssertEqual(bird.position,origin)
            advance(e,seconds:4);assertTerminal(e,run,type:.completed)
            XCTAssertEqual(e.renderSnapshot().first?.facingRight,direction)
        }
    }

    func testAutomaticWatchRejectsDistantPointerButPreviewAllowsItAndNearPointerDoesNotFlee() throws {
        let e=fixture(),bird=e.birds[0],revision=bird.motionRevision
        if case .rejected=e.handle(.attention(.watch,.automatic)) {} else {
            XCTFail("Automatic watch needs a nearby pointer")
        }
        XCTAssertEqual(e.activeRunCount,0)
        pointer(bird.position,in:e)
        let run=try started(e.handle(.attention(.watch,.automatic)))
        advance(e,seconds:0.5)
        XCTAssertTrue(terminals(e,run).isEmpty)
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.startledCount,0)
        XCTAssertEqual(bird.motionRevision,revision)
        advance(e,seconds:4);assertTerminal(e,run,type:.completed)
        pointer(CGPoint(x:0,y:0),in:e)
        let preview=try started(e.handle(.attention(.watch,.preview)))
        advance(e,seconds:4);assertTerminal(e,preview,type:.completed)
    }

    func testWatchExitRadiusHasHysteresisAndAlertIgnoresPointerDistance() throws {
        for scale:CGFloat in [1,2] {
            let e=fixture(scale:scale),bird=e.birds[0],origin=bird.position
            let radius=max(200,144*e.spriteScale(for:bird))
            pointer(origin,in:e)
            let run=try direct(.watch,in:e)
            pointer(CGPoint(x:origin.x+radius*1.1,y:origin.y),in:e)
            advance(e,seconds:0.1)
            XCTAssertTrue(terminals(e,run).isEmpty,"Entry radius must have an exit dead band")
            pointer(CGPoint(x:origin.x+radius*1.21,y:origin.y),in:e)
            e.advance(BehaviorEngine.step)
            assertTerminal(e,run,type:.cancelled,reason:.pointerMoved)
            advance(e,seconds:3);assertTerminal(e,run,type:.cancelled,reason:.pointerMoved)
        }
        for kind in AttentionKind.allCases {
            let e=fixture(),origin=e.birds[0].position
            pointer(origin,in:e)
            let run=try direct(kind,in:e,duration:1,requiresNearbyPointer:kind == .alert)
            pointer(CGPoint(x:100000,y:100000),in:e)
            advance(e,seconds:1.5)
            assertTerminal(e,run,type:.completed)
        }
    }

    func testNearbyWatchStaysOnItsOriginalScreen() throws {
        let e=fixture(),bird=e.birds[0],origin=bird.position
        let left=CGRect(x:screen.minX,y:screen.minY,width:origin.x+100-screen.minX,height:screen.height)
        let right=CGRect(x:left.maxX,y:left.minY,width:screen.maxX-left.maxX,height:screen.height)
        var world=e.world;world.displays=[left,right];world.screens=[left,right];world.pointer=origin
        e.updateWorld(world)
        let run=try direct(.watch,in:e)
        pointer(CGPoint(x:origin.x+110,y:origin.y),in:e)
        e.advance(BehaviorEngine.step)
        assertTerminal(e,run,type:.cancelled,reason:.pointerMoved)
    }

    func testPauseFreezesAgeFacingAndPoseThenResumesWithRemainingDuration() throws {
        for kind in AttentionKind.allCases {
            let e=fixture(),control=fixture(),bird=e.birds[0]
            let run=try started(e.handle(.attention(kind,.preview)))
            let baseline=try started(control.handle(.attention(kind,.preview)))
            advance(e,seconds:0.4);advance(control,seconds:0.4)
            let pose=try XCTUnwrap(e.renderSnapshot().first),age=e.runtime.runs[run]?.age,stateTime=bird.stateTime
            e.handle(.pause(true))
            let otherSide=CGPoint(x:bird.position.x+100,y:bird.position.y)
            pointer(otherSide,in:e);pointer(otherSide,in:control)
            advance(e,seconds:8)
            XCTAssertEqual(e.runtime.runs[run]?.age,age);XCTAssertEqual(bird.stateTime,stateTime)
            for _ in 0..<3 {
                let frozen=try XCTUnwrap(e.renderSnapshot().first)
                XCTAssertEqual(frozen.position,pose.position);XCTAssertEqual(frozen.hopOffset,pose.hopOffset)
                XCTAssertEqual(frozen.frameName,pose.frameName);XCTAssertEqual(frozen.facingRight,pose.facingRight)
            }
            XCTAssertTrue(terminals(e,run).isEmpty)
            XCTAssertEqual(e.handle(.attention(kind,.preview)),.rejected(.paused))
            e.handle(.pause(false))
            for _ in 0..<4*60 {
                e.advance(BehaviorEngine.step);control.advance(BehaviorEngine.step)
                XCTAssertEqual(e.renderSnapshot().first?.frameName,control.renderSnapshot().first?.frameName)
                XCTAssertEqual(e.renderSnapshot().first?.hopOffset,control.renderSnapshot().first?.hopOffset)
                XCTAssertEqual(e.renderSnapshot().first?.facingRight,control.renderSnapshot().first?.facingRight)
                XCTAssertEqual(terminals(e,run).isEmpty,terminals(control,baseline).isEmpty)
                if !terminals(e,run).isEmpty {break}
            }
            assertTerminal(e,run,type:.completed);assertTerminal(control,baseline,type:.completed)
            let finish=try XCTUnwrap(terminals(e,run).first),other=try XCTUnwrap(terminals(control,baseline).first)
            XCTAssertEqual(finish.time-other.time,8,accuracy:0.000001)
        }
    }

    func testPausedWorldValidationReleasesInvalidHostScaleScreenAndFramesImmediately() throws {
        for kind in AttentionKind.allCases {
            for invalidation in ["hostRemoved","hostPID","hostChanged","occluded","scale","displayBounds","displayRemoved","hostMoved","revision","frames"] {
                let e=fixture(),bird=e.birds[0],origin=bird.position
                let run=try started(e.handle(.attention(kind,.preview)))
                advance(e,seconds:0.4);e.handle(.pause(true))
                let clock=e.time
                var world=e.world
                switch invalidation {
                case "hostRemoved":world.surfaces=[]
                case "hostPID":world.surfaces=[Surface(id:host.id,pid:host.pid+1,rect:host.rect)]
                case "hostChanged":
                    let replacement=Surface(id:host.id+1,pid:host.pid,rect:host.rect)
                    bird.hostID=replacement.id;world.surfaces=[replacement]
                case "occluded":world.surfaces=[Surface(id:72,rect:Geometry.landingFootprint(at:origin,scale:2)),host]
                case "scale":world.scale*=1.1
                case "displayBounds":
                    // Actual display must contain both possible facing sprites,
                    // even when a broad work-area snapshot still contains them.
                    let size=e.spriteScale(for:bird)
                    world.displays=[CGRect(x:origin.x-20*size,y:screen.minY,width:1000,height:screen.height)]
                case "displayRemoved":world.displays=[]
                case "hostMoved":world.surfaces=[Surface(id:host.id,pid:host.pid,rect:host.rect.offsetBy(dx:20,dy:0))]
                case "revision":bird.perch(on:host)
                default:world.availableFrames[bird.profile.id]?.remove(kind == .watch ? "blink":"stand")
                }
                e.updateWorld(world)
                XCTAssertTrue(e.paused);XCTAssertEqual(e.time,clock)
                let reason:BehaviorReason=invalidation == "frames" ? .missingFrames:.targetInvalid
                assertTerminal(e,run,type:.failed,reason:reason)
                XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.renderSnapshot().count,1)
                e.updateWorld(world);advance(e,seconds:3)
                assertTerminal(e,run,type:.failed,reason:reason)
            }
        }
    }

    func testBothClickInputsCancelAndRelocatePreemptsWithoutStalePose() throws {
        for kind in AttentionKind.allCases {
            for input in ["click","buttons","pausedButtons","relocate"] {
                let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:e.birds[0]))
                let run=try started(e.handle(.attention(kind,.preview)))
                advance(e,seconds:0.4)
                let origin=bird.position,revision=bird.motionRevision
                var relocation:BehaviorRunID?
                switch input {
                case "click":e.handle(.pointerClick)
                case "buttons","pausedButtons":
                    if input == "pausedButtons" {e.handle(.pause(true))}
                    var world=e.world;world.buttonsDown=true;e.updateWorld(world)
                    e.advance(BehaviorEngine.step)
                default:relocation=try started(e.handle(.relocate(id)))
                }
                assertTerminal(e,run,type:.cancelled,reason:input == "relocate" ? .replaced:.userInput)
                XCTAssertEqual(bird.position,origin)
                if let relocation {
                    XCTAssertEqual(e.runtime.owners[id],relocation);XCTAssertEqual(e.activeRunCount,1)
                    XCTAssertEqual(bird.state,.flying);XCTAssertGreaterThan(bird.motionRevision,revision)
                    XCTAssertEqual(e.renderSnapshot().first?.hopOffset,0)
                    XCTAssertEqual(e.renderSnapshot().first?.frameName,bird.frameName)
                    advance(e,seconds:10);assertTerminal(e,relocation,type:.completed)
                } else {
                    XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(e.leasedBirdCount,0)
                }
                e.handle(.pointerClick);advance(e,seconds:4)
                assertTerminal(e,run,type:.cancelled,reason:input == "relocate" ? .replaced:.userInput)
            }
        }
    }

    func testRequiredFramesRejectAndAlertTreatsLateBlinkAsOptional() throws {
        for kind in AttentionKind.allCases {
            for missing in kind.requiredFrames {
                let e=fixture(),bird=e.birds[0]
                var world=e.world;world.availableFrames[bird.profile.id]?.remove(missing);e.updateWorld(world)
                XCTAssertEqual(e.handle(.attention(kind,.preview)),.rejected(.missingFrames))
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                XCTAssertTrue(world.availableFrames[bird.profile.id]!.contains(try XCTUnwrap(e.renderSnapshot().first).frameName))
            }
        }
        for loseBlink in [false,true] {
            let e=fixture(),bird=e.birds[0]
            var world=e.world
            if !loseBlink {world.availableFrames[bird.profile.id]=["stand"];e.updateWorld(world)}
            let run=try started(e.handle(.attention(.alert,.preview)))
            if loseBlink {
                advance(e,seconds:0.3)
                world.availableFrames[bird.profile.id]?.remove("blink");e.updateWorld(world)
            }
            for _ in 0..<2*60 {
                if e.runtime.runs[run] != nil {XCTAssertEqual(e.renderSnapshot().first?.frameName,"stand")}
                e.advance(BehaviorEngine.step)
            }
            assertTerminal(e,run,type:.completed);XCTAssertEqual(e.renderSnapshot().count,1)
        }
        let e=fixture(),bird=e.birds[0]
        let run=try direct(.alert,in:e,duration:1,requiresNearbyPointer:false)
        advance(e,seconds:0.8)
        XCTAssertEqual(e.renderSnapshot().first?.frameName,"blink")
        var world=e.world;world.availableFrames[bird.profile.id]?.remove("blink");e.updateWorld(world)
        XCTAssertTrue(terminals(e,run).isEmpty);XCTAssertEqual(e.renderSnapshot().first?.frameName,"stand")
        advance(e,seconds:0.3);assertTerminal(e,run,type:.completed)
    }

    func testMasterAndPassiveSettingDisableAttentionAndRejectNewCommands() throws {
        for kind in AttentionKind.allCases {
            for master in [false,true] {
                let e=fixture()
                let run=try started(e.handle(.attention(kind,.preview)))
                advance(e,seconds:0.4)
                var settings=e.settings
                if master {settings.perchActions=false} else {settings.passiveAttentionEnabled=false}
                e.applySettings(settings)
                assertTerminal(e,run,type:.cancelled,reason:.settingsChanged)
                for source:BehaviorSource in [.preview,.automatic] {
                    XCTAssertEqual(e.handle(.attention(kind,source)),.rejected(.disabled))
                }
                e.ambientEnabled=true;advance(e,seconds:4)
                XCTAssertFalse(e.events.contains{$0.type == .started && ($0.kind == .watch || $0.kind == .alert) && $0.source == .automatic})
                XCTAssertEqual(e.leasedBirdCount,0)
                assertTerminal(e,run,type:.cancelled,reason:.settingsChanged)
            }
        }
    }

    func testHopBlendsAtEntryAndSharedMixerRecoversWithoutMovingFeet() throws {
        for kind in AttentionKind.allCases {
            let e=fixture(),bird=e.birds[0]
            advance(e,seconds:1.25)
            let original=try XCTUnwrap(e.renderSnapshot().first),origin=bird.position
            XCTAssertLessThan(original.hopOffset,-2)
            let run=try started(e.handle(.attention(kind,.preview)))
            XCTAssertEqual(e.renderSnapshot().first?.hopOffset,original.hopOffset)
            advance(e,seconds:0.1)
            let blending=try XCTUnwrap(e.renderSnapshot().first)
            XCTAssertGreaterThan(blending.hopOffset,original.hopOffset);XCTAssertLessThan(blending.hopOffset,0)
            XCTAssertEqual(blending.position,origin)
            advance(e,seconds:0.3)
            XCTAssertEqual(try XCTUnwrap(e.renderSnapshot().first).hopOffset,0,accuracy:0.000001)
            XCTAssertEqual(bird.position,origin)
            advance(e,seconds:4);assertTerminal(e,run,type:.completed)

            // A fixed direct duration makes both kinds release in the middle
            // of the live idle hop, so an immediate snap cannot pass this test.
            let recovery=fixture(),model=recovery.birds[0]
            let active=try direct(kind,in:recovery,duration:2,requiresNearbyPointer:false)
            advance(recovery,seconds:1.25)
            let before=try XCTUnwrap(recovery.renderSnapshot().first)
            XCTAssertLessThan(model.hopOffset,-2);XCTAssertEqual(before.hopOffset,0)
            recovery.handle(.pointerClick)
            assertTerminal(recovery,active,type:.cancelled,reason:.userInput)
            XCTAssertEqual(recovery.renderSnapshot().first?.hopOffset,before.hopOffset)
            advance(recovery,seconds:0.1)
            let middle=try XCTUnwrap(recovery.renderSnapshot().first)
            XCTAssertLessThan(middle.hopOffset,0);XCTAssertGreaterThan(middle.hopOffset,model.hopOffset)
            XCTAssertEqual(middle.position,before.position)
            advance(recovery,seconds:7.0/60)
            XCTAssertLessThan(model.hopOffset,-0.5)
            XCTAssertEqual(try XCTUnwrap(recovery.renderSnapshot().first).hopOffset,model.hopOffset,accuracy:0.000001)
            XCTAssertEqual(model.position,before.position)
        }
    }

    func testDirectExecutionCannotBypassDisabledSettingsEvenWhilePaused() throws {
        for kind in AttentionKind.allCases {
            for master in [false,true] {
                let e=fixture(),bird=e.birds[0],origin=bird.position,revision=bird.motionRevision
                var settings=e.settings
                if master {settings.perchActions=false} else {settings.passiveAttentionEnabled=false}
                e.applySettings(settings);e.handle(.pause(true))
                let run=try direct(kind,in:e,requiresNearbyPointer:false)
                // Force runtime validation without advancing its paused clock.
                e.updateWorld(e.world)
                assertTerminal(e,run,type:.cancelled,reason:.settingsChanged)
                XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.time,0)
                XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
                e.updateWorld(e.world)
                assertTerminal(e,run,type:.cancelled,reason:.settingsChanged)
            }
        }
    }

    func testRemovalAndGlobalCancellationHaveOneTerminalAndNoGhostLease() throws {
        for kind in AttentionKind.allCases {
            for reason:BehaviorReason in [.removed,.sleep,.screensChanged,.spaceChanged,.shutdown] {
                let e=fixture(),id=try XCTUnwrap(e.id(of:e.birds[0]))
                let run=try started(e.handle(.attention(kind,.preview)))
                for _ in 0..<2 {
                    if reason == .removed {e.handle(.remove(id))}
                    else {e.handle(.cancelAmbient(reason))}
                }
                advance(e,seconds:4)
                assertTerminal(e,run,type:.cancelled,reason:reason)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                XCTAssertEqual(e.renderSnapshot().count,reason == .removed ? 0:1)
            }
        }
    }
}
