import XCTest
@testable import BirdingCore

final class SocialGreetingTests:XCTestCase {
    private let screen=CGRect(x:-1200,y:-400,width:3000,height:1800)
    private let host=Surface(id:71,pid:42,rect:CGRect(x:-900,y:800,width:2300,height:400))
    private let greetingFrames:Set<String> = ["stand","blink","idle0","idle1","idle2"]

    private func fixture(scale:CGFloat=1,species:[SpeciesID]=[.treeSparrow,.redWhiskeredBulbul]) -> BehaviorEngine {
        var settings=BirdSettings()
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=true
        let engine=BehaviorEngine(seed:73,settings:settings)
        engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
        let frames=greetingFrames.union(["breathe","preen0","preen1","land0","land1","land2"])
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],scale:scale,
            pointer:CGPoint(x:1200,y:0),availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)})))
        engine.installFixtureBirds(species.enumerated().map { index,id in
            let x:CGFloat = -500+CGFloat(index)*200*scale
            let start=Geometry.perchX(0,rect:host.rect),end=Geometry.perchX(1,rect:host.rect)
            let bird=Bird(position:.zero,fraction:(x-start)/(end-start),profile:settings.catalog.profile(id),random:{0.5})
            bird.perch(on:host,spriteScale:scale*bird.profile.relativeScale);bird.perchDuration=600
            bird.facingRight=index != 0
            return bird
        })
        return engine
    }

    private func advance(_ engine:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {engine.advance(1/Double(hz))}
    }

    private func started(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let run)=result else {
            XCTFail("Expected social greeting to start, got \(result)",file:file,line:line)
            throw NSError(domain:"SocialGreetingTests",code:1)
        }
        return run
    }

    private func terminal(_ engine:BehaviorEngine,_ run:BehaviorRunID,type:BehaviorEventType,
                          reason:BehaviorReason?=nil,file:StaticString=#filePath,line:UInt=#line) {
        let events=engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
        XCTAssertEqual(events.count,1,file:file,line:line)
        XCTAssertEqual(events.first?.type,type,file:file,line:line)
        XCTAssertEqual(events.first?.reason,reason,file:file,line:line)
    }

    private func released(_ engine:BehaviorEngine,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(engine.activeRunCount,0,file:file,line:line)
        XCTAssertEqual(engine.leasedBirdCount,0,file:file,line:line)
        XCTAssertFalse(engine.ambientBusy,file:file,line:line)
        for bird in engine.birds {XCTAssertNil(engine.behavior(of:bird),file:file,line:line)}
    }

    func testActorsUseStaggeredSpeciesFramesAndCompleteExactlyOnce() throws {
        let engine=fixture(),birds=engine.birds
        let anchors=birds.map(\.position),revisions=birds.map(\.motionRevision)
        let run=try started(engine.handle(.socialGreeting(.preview)))
        let event=try XCTUnwrap(engine.events.first{$0.runID==run && $0.type == .started})
        XCTAssertEqual(event.kind,.socialGreeting);XCTAssertEqual(event.source,.preview)
        XCTAssertEqual(Set(event.participants),Set(birds.compactMap{engine.id(of:$0)}))
        XCTAssertEqual(event.participants.count,2)
        XCTAssertEqual(engine.activeRunCount,1);XCTAssertEqual(engine.leasedBirdCount,2);XCTAssertTrue(engine.ambientBusy)
        var observed:[BirdID:Set<String>]=[:]
        for _ in 0..<276 {
            let age=engine.time-event.time
            let states=engine.renderSnapshot()
            XCTAssertEqual(states.count,2)
            XCTAssertLessThanOrEqual(states.filter{$0.frameName.hasPrefix("idle")}.count,1)
            for state in states {
                observed[state.id,default:[]].insert(state.frameName)
                XCTAssertTrue(greetingFrames.contains(state.frameName))
                XCTAssertEqual(state.species,engine.bird(state.id)?.profile.id)
                if state.frameName.hasPrefix("idle") {
                    let isInitiator=state.id==event.participants[0]
                    XCTAssertGreaterThanOrEqual(age,(isInitiator ? 0.4:1.9)-1e-8)
                    XCTAssertLessThan(age,(isInitiator ? 1.5:3.0)+1e-8)
                }
            }
            engine.advance(BehaviorEngine.step)
        }
        for id in event.participants {XCTAssertEqual(observed[id],greetingFrames)}
        terminal(engine,run,type:.completed);released(engine)
        let completion=try XCTUnwrap(engine.events.first{$0.runID==run && $0.type == .completed})
        XCTAssertEqual(completion.time-event.time,4.6,accuracy:BehaviorEngine.step/2)
        XCTAssertEqual(completion.participants,event.participants)
        XCTAssertEqual(birds.map(\.position),anchors);XCTAssertEqual(birds.map(\.motionRevision),revisions)
        advance(engine,seconds:2);terminal(engine,run,type:.completed)
    }

    func testFacingOverridePreservesFeetAndBlendsExistingHops() throws {
        let engine=fixture(species:[.treeSparrow,.treeSparrow]),birds=engine.birds
        advance(engine,seconds:1.25)
        let before=engine.renderSnapshot(),anchors=birds.map(\.position)
        let revisions=birds.map(\.motionRevision),directions=birds.map(\.facingRight)
        XCTAssertTrue(before.allSatisfy{$0.hopOffset < -2})
        let run=try started(engine.handle(.socialGreeting(.preview)))
        XCTAssertEqual(engine.renderSnapshot().map(\.hopOffset),before.map(\.hopOffset))
        var previousHops=before.map(\.hopOffset)
        for step in 0..<276 {
            for (index,state) in engine.renderSnapshot().enumerated() {
                XCTAssertEqual(state.position,anchors[index]);XCTAssertEqual(state.facingRight,index==0)
                XCTAssertEqual(state.rect.minX+(state.facingRight ? 29:19)*state.scale,anchors[index].x,accuracy:1e-8)
                XCTAssertEqual(state.rect.minY+(39-state.hopOffset)*state.scale,anchors[index].y,accuracy:1e-8)
                XCTAssertEqual(engine.bounds(of:birds[index]),state.rect.insetBy(dx:-2,dy:-2))
                if step>0 && step<=21 {
                    XCTAssertGreaterThanOrEqual(state.hopOffset,previousHops[index])
                    XCTAssertLessThanOrEqual(state.hopOffset,0)
                    XCTAssertLessThan(state.hopOffset-previousHops[index],0.3)
                }
                if step==24 {XCTAssertEqual(state.hopOffset,0,accuracy:1e-8)}
                previousHops[index]=state.hopOffset
            }
            XCTAssertEqual(birds.map(\.facingRight),directions)
            engine.advance(BehaviorEngine.step)
        }
        terminal(engine,run,type:.completed)
        XCTAssertEqual(birds.map(\.motionRevision),revisions);XCTAssertEqual(birds.map(\.position),anchors)
        XCTAssertEqual(engine.renderSnapshot().map(\.facingRight),directions)
        advance(engine,seconds:0.25)
        XCTAssertEqual(engine.renderSnapshot().map(\.hopOffset),birds.map(\.hopOffset))
    }

    func testPointerNearEitherActorAndBothClickInputsCancelTogether() throws {
        for index in 0..<2 {
            for input in ["pointer","buttons","click"] {
                let engine=fixture(),birds=engine.birds
                let run=try started(engine.handle(.socialGreeting(.preview)))
                advance(engine,seconds:0.75)
                let positions=birds.map(\.position),revisions=birds.map(\.motionRevision)
                var world=engine.world
                if input=="pointer" {world.pointer=birds[index].position;engine.updateWorld(world)}
                else if input=="buttons" {world.buttonsDown=true;engine.updateWorld(world)}
                else {engine.handle(.pointerClick)}
                engine.advance(BehaviorEngine.step)
                let reason:BehaviorReason=input=="pointer" ? .pointerNearby:.userInput
                terminal(engine,run,type:.cancelled,reason:reason);released(engine)
                XCTAssertEqual(birds.map(\.position),positions);XCTAssertEqual(birds.map(\.motionRevision),revisions)
                advance(engine,seconds:6);terminal(engine,run,type:.cancelled,reason:reason)
            }
        }
    }

    func testRemovingEitherCompanionReleasesSurvivor() throws {
        for index in 0..<2 {
            let engine=fixture(),bird=engine.birds[index],survivor=engine.birds[1-index]
            let id=try XCTUnwrap(engine.id(of:bird)),anchor=survivor.position
            let run=try started(engine.handle(.socialGreeting(.preview)))
            advance(engine,seconds:0.6);engine.handle(.remove(id))
            terminal(engine,run,type:.cancelled,reason:.removed);released(engine)
            XCTAssertNil(engine.bird(id));XCTAssertEqual(engine.renderSnapshot().count,1)
            XCTAssertEqual(survivor.position,anchor)
            advance(engine,seconds:6);terminal(engine,run,type:.cancelled,reason:.removed)
        }
    }

    func testRelocatingEitherActorReleasesPartnerWithoutRestoringOldMotion() throws {
        for index in 0..<2 {
            let engine=fixture(),birds=engine.birds,bird=birds[index],partner=birds[1-index]
            let id=try XCTUnwrap(engine.id(of:bird)),anchor=bird.position
            let run=try started(engine.handle(.socialGreeting(.preview)))
            advance(engine,seconds:0.6)
            let move=try started(engine.handle(.relocate(id))),revision=bird.motionRevision
            terminal(engine,run,type:.cancelled,reason:.replaced)
            XCTAssertEqual(bird.position,anchor);XCTAssertEqual(bird.state,.flying)
            XCTAssertEqual(engine.behavior(of:bird),.relocate);XCTAssertNil(engine.behavior(of:partner))
            XCTAssertEqual(engine.activeRunCount,1);XCTAssertEqual(engine.leasedBirdCount,1);XCTAssertFalse(engine.ambientBusy)
            for _ in 0..<12 {
                let state=try XCTUnwrap(engine.renderSnapshot().first{$0.id==id})
                XCTAssertEqual(state.hopOffset,0);XCTAssertEqual(bird.motionRevision,revision)
                engine.advance(BehaviorEngine.step)
            }
            advance(engine,seconds:15)
            terminal(engine,run,type:.cancelled,reason:.replaced);terminal(engine,move,type:.completed)
        }
    }

    func testPauseFreezesBothPosesAndResumesRemainingDuration() throws {
        let engine=fixture()
        let run=try started(engine.handle(.socialGreeting(.preview)))
        advance(engine,seconds:0.75);engine.handle(.pause(true))
        let before=engine.renderSnapshot(),ages=engine.birds.map(\.stateTime)
        advance(engine,seconds:8)
        let after=engine.renderSnapshot()
        XCTAssertEqual(after.map(\.position),before.map(\.position));XCTAssertEqual(after.map(\.rect),before.map(\.rect))
        XCTAssertEqual(after.map(\.frameName),before.map(\.frameName));XCTAssertEqual(after.map(\.facingRight),before.map(\.facingRight))
        XCTAssertEqual(after.map(\.hopOffset),before.map(\.hopOffset));XCTAssertEqual(engine.birds.map(\.stateTime),ages)
        XCTAssertEqual(engine.activeRunCount,1);XCTAssertEqual(engine.leasedBirdCount,2);XCTAssertTrue(engine.ambientBusy)
        engine.handle(.pause(false));advance(engine,seconds:3.8)
        XCTAssertEqual(engine.activeRunCount,1)
        advance(engine,seconds:0.1);terminal(engine,run,type:.completed);released(engine)
    }

    func testBothActorsInvalidateImmediatelyEvenWhilePaused() throws {
        for paused in [false,true] {
            for index in 0..<2 {
                for invalidation in ["host","pid","occluded","frames","revision","expired","side","height","distance","display"] {
                    let engine=fixture(),bird=engine.birds[index]
                    let run=try started(engine.handle(.socialGreeting(.preview)))
                    advance(engine,seconds:0.6)
                    if paused {engine.handle(.pause(true))}
                    let clock=engine.time
                    var world=engine.world
                    switch invalidation {
                    case "host":world.surfaces=[]
                    case "pid":world.surfaces=[Surface(id:host.id,pid:host.pid+1,rect:host.rect)]
                    case "occluded":
                        world.surfaces.insert(Surface(id:99,rect:CGRect(x:bird.position.x-4,y:bird.position.y-30,width:8,height:10)),at:0)
                    case "frames":world.availableFrames[bird.profile.id]?.remove("idle2")
                    case "revision":bird.perch(on:host,spriteScale:engine.spriteScale(for:bird))
                    case "expired":bird.perchDuration=bird.stateTime
                    case "side":bird.edge = .left
                    case "height":bird.position.y+=1
                    case "distance":bird.position.x += index==0 ? -600:600
                    default:world.displays=[]
                    }
                    engine.updateWorld(world)
                    let reason:BehaviorReason=invalidation=="frames" ? .missingFrames:.targetInvalid
                    terminal(engine,run,type:.failed,reason:reason);released(engine)
                    XCTAssertEqual(engine.time,clock);XCTAssertEqual(engine.paused,paused)
                    XCTAssertEqual(engine.renderSnapshot().count,2)
                    engine.updateWorld(world);advance(engine,seconds:6)
                    terminal(engine,run,type:.failed,reason:reason)
                }
            }
        }
    }

    func testReplacementFlightAndDepartureAreNeverOverwritten() throws {
        for index in 0..<2 {
            for departing in [false,true] {
                let engine=fixture(),bird=engine.birds[index]
                let run=try started(engine.handle(.socialGreeting(.preview)))
                advance(engine,seconds:0.8)
                let destination=CGPoint(x:bird.position.x+500,y:bird.position.y-200)
                if departing {bird.depart(to:destination,duration:3)}
                else {bird.fly(to:destination,host:nil,duration:3,urgent:true,random:{0.5})}
                let revision=bird.motionRevision,position=bird.position
                engine.updateWorld(engine.world)
                terminal(engine,run,type:.failed,reason:.targetInvalid);released(engine)
                XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.motionRevision,revision)
                XCTAssertEqual(bird.state,.flying);XCTAssertEqual(bird.isDeparting,departing)
                advance(engine,seconds:0.2)
                XCTAssertEqual(bird.motionRevision,revision);XCTAssertNotEqual(bird.position,position)
            }
        }
    }

    func testMissingAssetsOnEitherSpeciesRejectBeforeLeasing() {
        for index in 0..<2 {
            for frame in greetingFrames.sorted() {
                let engine=fixture(),bird=engine.birds[index]
                var world=engine.world;world.availableFrames[bird.profile.id]?.remove(frame);engine.updateWorld(world)
                for source:BehaviorSource in [.preview,.automatic] {
                    XCTAssertEqual(engine.handle(.socialGreeting(source)),.rejected(.missingFrames))
                    XCTAssertEqual(engine.events.last?.source,source);released(engine)
                    for state in engine.renderSnapshot() {XCTAssertTrue(world.availableFrames[state.species]!.contains(state.frameName))}
                }
            }
        }
        let engine=fixture();var world=engine.world;world.availableFrames=[:];engine.updateWorld(world)
        XCTAssertEqual(engine.handle(.socialGreeting(.preview)),.rejected(.missingFrames));released(engine)
    }

    func testBusyMissingCompanionPausedAndDisabledGates() throws {
        for species:[SpeciesID] in [[],[.treeSparrow]] {
            let engine=fixture(species:species)
            XCTAssertEqual(engine.handle(.socialGreeting(.preview)),.rejected(.noCompanion));released(engine)
        }
        let engine=fixture()
        let run=try started(engine.handle(.socialGreeting(.preview)))
        XCTAssertEqual(engine.handle(.socialGreeting(.preview)),.rejected(.busy))
        XCTAssertEqual(engine.activeRunCount,1);XCTAssertEqual(engine.leasedBirdCount,2)
        var settings=engine.settings;settings.socialInteractions=false;engine.applySettings(settings)
        terminal(engine,run,type:.cancelled,reason:.settingsChanged);released(engine)
        XCTAssertEqual(engine.handle(.socialGreeting(.preview)),.rejected(.disabled))
        settings.socialInteractions=true;engine.applySettings(settings);engine.handle(.pause(true))
        XCTAssertEqual(engine.handle(.socialGreeting(.preview)),.rejected(.paused));released(engine)
        engine.handle(.pause(false))
        _=try started(engine.handle(.perchAction(.rest,.preview)))
        XCTAssertEqual(engine.handle(.socialGreeting(.preview)),.rejected(.busy))
        XCTAssertEqual(engine.activeRunCount,1);XCTAssertEqual(engine.leasedBirdCount,1)
    }

    func testNegativeCoordinatesScaleAndFullSpriteClearance() throws {
        for scale:CGFloat in [0.5,1,2,3] {
            let engine=fixture(scale:scale),a=engine.birds[0],b=engine.birds[1]
            XCTAssertLessThan(a.position.x,0)
            XCTAssertTrue(SocialGreetingPlan.eligiblePair(a,b,in:engine))
            XCTAssertTrue(SocialGreetingPlan.eligiblePair(b,a,in:engine))
            let run=try started(engine.handle(.socialGreeting(.preview)))
            let poses=engine.renderSnapshot()
            XCTAssertGreaterThanOrEqual(poses[1].rect.minX-poses[0].rect.maxX,12)
            XCTAssertTrue(poses.allSatisfy{screen.contains($0.rect)})
            advance(engine,seconds:4.7);terminal(engine,run,type:.completed)
            let minimum=19*engine.spriteScale(for:a)+19*engine.spriteScale(for:b)+12
            b.position.x=a.position.x+minimum+0.001
            XCTAssertTrue(SocialGreetingPlan.eligiblePair(a,b,in:engine))
            b.position.x-=0.002
            XCTAssertFalse(SocialGreetingPlan.eligiblePair(a,b,in:engine))
            b.position.x=a.position.x+420*scale
            XCTAssertTrue(SocialGreetingPlan.eligiblePair(a,b,in:engine))
            b.position.x+=0.01
            XCTAssertFalse(SocialGreetingPlan.eligiblePair(a,b,in:engine))
        }
    }

    func testGeometryRejectsDifferentHostsHeightsDisplaysAndTurningOffscreenWithoutMutation() {
        for invalidation in ["sameBird","host","height","side","display","turn","blocker"] {
            let engine=fixture(),a=engine.birds[0],b=engine.birds[1]
            var world=engine.world
            switch invalidation {
            case "host":
                let other=Surface(id:72,pid:host.pid,rect:host.rect)
                world.surfaces.append(other);b.perch(on:other,spriteScale:engine.spriteScale(for:b))
            case "height":b.position.y+=1
            case "side":b.edge = .left
            case "display":
                let split=(a.position.x+b.position.x)/2
                world.displays=[CGRect(x:screen.minX,y:screen.minY,width:split-screen.minX,height:screen.height),
                    CGRect(x:split,y:screen.minY,width:screen.maxX-split,height:screen.height)]
            case "turn":
                // Its original left-facing sprite fits; turning left bird right
                // adds ten pixels on the left and must not move the anchor.
                let boundary=a.position.x-24*engine.spriteScale(for:a)
                world.displays=[CGRect(x:boundary,y:screen.minY,width:screen.maxX-boundary,height:screen.height)]
            case "blocker":
                world.surfaces.insert(Surface(id:99,rect:CGRect(x:b.position.x-10,y:b.position.y-20,width:20,height:10)),at:0)
            default:break
            }
            engine.updateWorld(world)
            let positions=engine.birds.map(\.position),directions=engine.birds.map(\.facingRight),revisions=engine.birds.map(\.motionRevision)
            XCTAssertFalse(SocialGreetingPlan.eligiblePair(a,invalidation=="sameBird" ? a:b,in:engine),invalidation)
            XCTAssertEqual(engine.birds.map(\.position),positions);XCTAssertEqual(engine.birds.map(\.facingRight),directions)
            XCTAssertEqual(engine.birds.map(\.motionRevision),revisions);released(engine)
        }
    }

    func testGroundGreetingAllowsTailsOutsideWorkAreaInsideSameDisplay() throws {
        for scale:CGFloat in [0.5,1,2] {
            let engine=fixture(scale:scale,species:[.treeSparrow,.treeSparrow])
            let workArea=CGRect(x:screen.minX,y:screen.minY,width:screen.width,height:screen.height-40)
            let ground=Geometry.ground(id:88,display:screen,workArea:workArea)
            var world=engine.world;world.screens=[workArea];world.surfaces=[ground];engine.updateWorld(world)
            for (index,bird) in engine.birds.enumerated() {
                let x:CGFloat = -500+CGFloat(index)*200*scale
                bird.fraction=(x-Geometry.perchX(0,rect:ground.rect))/(Geometry.perchX(1,rect:ground.rect)-Geometry.perchX(0,rect:ground.rect))
                bird.perch(on:ground,spriteScale:engine.spriteScale(for:bird))
            }
            XCTAssertTrue(SocialGreetingPlan.eligiblePair(engine.birds[0],engine.birds[1],in:engine))
            let anchors=engine.birds.map(\.position)
            let run=try started(engine.handle(.socialGreeting(.preview)))
            for state in engine.renderSnapshot() {
                XCTAssertGreaterThan(state.rect.maxY,workArea.maxY)
                XCTAssertTrue(screen.contains(state.rect));XCTAssertFalse(workArea.contains(state.rect))
            }
            advance(engine,seconds:4.7);terminal(engine,run,type:.completed);released(engine)
            XCTAssertEqual(engine.birds.map(\.position),anchors)
        }
    }

    func testDifferentSizedGroundBirdsKeepTheirOwnLegalFootHeights() throws {
        let engine=fixture(),ground=Geometry.ground(id:88,display:screen,workArea:screen)
        var world=engine.world;world.surfaces=[ground];engine.updateWorld(world)
        for (index,bird) in engine.birds.enumerated() {
            let x:CGFloat = -500+CGFloat(index)*200
            bird.fraction=(x-Geometry.perchX(0,rect:ground.rect))/(Geometry.perchX(1,rect:ground.rect)-Geometry.perchX(0,rect:ground.rect))
            bird.perch(on:ground,spriteScale:engine.spriteScale(for:bird))
        }
        let anchors=engine.birds.map(\.position)
        XCTAssertNotEqual(anchors[0].y,anchors[1].y)
        let run=try started(engine.handle(.socialGreeting(.preview)))
        advance(engine,seconds:4.7);terminal(engine,run,type:.completed);released(engine)
        XCTAssertEqual(engine.birds.map(\.position),anchors)
    }

    func testHiddenBaseHopDoesNotInvalidateTheVisibleGreetingPose() throws {
        let engine=fixture(species:[.treeSparrow,.treeSparrow]),bird=engine.birds[0]
        let top=bird.position.y-39*engine.spriteScale(for:bird)-1
        var world=engine.world
        world.displays=[CGRect(x:screen.minX,y:top,width:screen.width,height:screen.maxY-top)]
        world.screens=world.displays;engine.updateWorld(world)
        let run=try started(engine.handle(.socialGreeting(.preview)))
        advance(engine,seconds:1.25)
        XCTAssertLessThan(bird.hopOffset,-2)
        XCTAssertEqual(engine.activeRunCount,1)
        XCTAssertTrue(engine.renderSnapshot().allSatisfy{$0.hopOffset==0 && world.displays[0].contains($0.rect)})
        advance(engine,seconds:3.5);terminal(engine,run,type:.completed);released(engine)
    }

    func testReplayMatchesAt30And60And120Hz() throws {
        struct Trace:Equatable {
            let positions:[CGPoint],rects:[CGRect],frames:[String],directions:[Bool],hops:[CGFloat],events:[String],counts:[Int]
        }
        func replay(_ hz:Int) throws -> [Trace] {
            let engine=fixture()
            var traces:[Trace]=[]
            for second in 0..<14 {
                switch second {
                case 0,10:_=try started(engine.handle(.socialGreeting(.preview)))
                case 1:engine.handle(.pause(true))
                case 3:engine.handle(.pause(false))
                case 11:engine.handle(.pointerClick)
                default:break
                }
                advance(engine,seconds:1,hz:hz)
                let states=engine.renderSnapshot()
                traces.append(Trace(positions:states.map(\.position),rects:states.map(\.rect),frames:states.map(\.frameName),
                    directions:states.map(\.facingRight),hops:states.map(\.hopOffset),
                    events:engine.events.map{"\($0.sequence):\($0.time):\($0.runID?.rawValue ?? 0):\($0.kind?.rawValue ?? ""):\($0.type):\($0.reason?.rawValue ?? ""):\($0.participants.map(\.rawValue))"},
                    counts:[engine.activeRunCount,engine.leasedBirdCount,engine.residentCount]))
            }
            XCTAssertEqual(engine.events.filter{$0.kind == .socialGreeting && $0.type == .completed}.count,1)
            XCTAssertEqual(engine.events.filter{$0.kind == .socialGreeting && $0.type == .cancelled}.count,1)
            return traces
        }
        let reference=try replay(60)
        XCTAssertEqual(try replay(30),reference);XCTAssertEqual(try replay(120),reference)
    }
}
