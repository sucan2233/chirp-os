import XCTest
@testable import BirdingCore

final class LeafPlayTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:1600,height:1200)
    private let host=Surface(id:81,pid:42,rect:CGRect(x:100,y:900,width:1400,height:250))
    private let center=CGPoint(x:800,y:500)
    // Independent of LeafPlayPlan.requiredFrames: losing a required asset must
    // not silently change the fixture along with the implementation.
    private let frames:Set<String> = ["stand","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","land0","land1","land2"]

    private func fixture(seed:UInt64=81,offset:CGPoint = .zero) -> BehaviorEngine {
        var settings=BirdSettings();settings.leafPlayEnabled=true;settings.perchActions=false
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let area=display.offsetBy(dx:offset.x,dy:offset.y)
        let perch=Surface(id:host.id,pid:host.pid,rect:host.rect.offsetBy(dx:offset.x,dy:offset.y))
        e.updateWorld(BehaviorWorld(screens:[area],displays:[area],surfaces:[perch],
            pointer:CGPoint(x:center.x+offset.x,y:center.y+offset.y),availableFrames:[.treeSparrow:frames]))
        e.installFixtureBirds([makeBird(on:perch,in:e)])
        return e
    }

    private func makeBird(on perch:Surface,in e:BehaviorEngine) -> Bird {
        let bird=Bird(position:.zero,fraction:0.5,profile:e.settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:perch,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
        return bird
    }

    private func runID(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let id)=result else {
            XCTFail("Expected a leaf scene to start, got \(result)",file:file,line:line)
            throw NSError(domain:"LeafPlayTests",code:1)
        }
        return id
    }

    private func start(_ e:BehaviorEngine,at point:CGPoint?=nil,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        try runID(e.handle(.leafPlay(at:point ?? e.world.pointer,source:.preview)),file:file,line:line)
    }

    private func terminals(_ e:BehaviorEngine,_ id:BehaviorRunID) -> [BehaviorEvent] {
        e.events.filter{$0.runID==id && [.completed,.cancelled,.failed].contains($0.type)}
    }

    private func advance(_ e:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }

    private func finish(_ e:BehaviorEngine,_ id:BehaviorRunID) {
        for _ in 0..<35*60 {
            if !terminals(e,id).isEmpty {return}
            e.advance(BehaviorEngine.step)
        }
    }

    private func released(_ e:BehaviorEngine,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(e.activeRunCount,0,file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line)
        XCTAssertEqual(e.scenePropCount,0,file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertTrue(e.propSnapshot().isEmpty,file:file,line:line)
        XCTAssertFalse(e.ambientBusy,file:file,line:line)
    }

    private struct BirdSample:Equatable {
        let id:BirdID
        let position:CGPoint
        let facing:Bool
        let scale:CGFloat
        let hop:CGFloat
        let frame:String
        let blockers:[CGRect]
        let hoverable:Bool
        init(_ value:BirdRenderState) {
            id=value.id;position=value.position;facing=value.facingRight;scale=value.scale
            hop=value.hopOffset;frame=value.frameName;blockers=value.blockers;hoverable=value.hoverable
        }
        var visibleFoot:CGPoint {CGPoint(x:position.x,y:position.y+hop*scale)}
    }
    private struct PropSample:Equatable {
        let id:ScenePropID
        let kind:ScenePropKind
        let position:CGPoint
        let size:CGFloat
        let rotation:CGFloat
        let opacity:Double
        let blockers:[CGRect]
        init(_ value:ScenePropRenderState) {
            id=value.id;kind=value.kind;position=value.position;size=value.size
            rotation=value.rotation;opacity=value.opacity;blockers=value.blockers
        }
    }

    func testSceneCompletesExactlyOnceReturnsHomeAndReleasesEveryLease() throws {
        let e=fixture(),bird=e.birds[0],origin=e.birds[0].position
        let id=try start(e)
        XCTAssertEqual(e.events.filter{$0.runID==id && $0.type == .started}.count,1)
        XCTAssertEqual(e.events.first{$0.runID==id}?.participants,[try XCTUnwrap(e.id(of:bird))])
        XCTAssertEqual(e.behavior(of:bird),.leafPlay)
        XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
        XCTAssertEqual(e.scenePropCount,1);XCTAssertEqual(e.reservedLandingCount,1)
        XCTAssertEqual(e.propSnapshot().first?.kind,.leaf)
        finish(e,id)
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.hostID,host.id)
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.landedCount,1)
        XCTAssertEqual(e.residentCount,1);released(e)
        advance(e,seconds:3)
        XCTAssertEqual(terminals(e,id).count,1);XCTAssertEqual(bird.position,origin)
    }

    func testBirdAndLeafSnapshotsStayContinuousThroughCircleFadeAndCompletion() throws {
        let e=fixture(),bird=e.birds[0],id=try start(e)
        var previousBird=try XCTUnwrap(e.renderSnapshot().first).position
        var previousFoot=BirdSample(try XCTUnwrap(e.renderSnapshot().first)).visibleFoot
        var previousLeaf=try XCTUnwrap(e.propSnapshot().first)
        var circled=false,faded=false,landed=false,disappeared=false
        var minimumOpacity=1.0,maximumLeafTravel:CGFloat=0
        for _ in 0..<35*60 {
            e.advance(BehaviorEngine.step)
            let pose=try XCTUnwrap(e.renderSnapshot().first)
            let foot=BirdSample(pose).visibleFoot
            XCTAssertLessThan(Geometry.distance(previousBird,pose.position),15)
            XCTAssertLessThan(Geometry.distance(previousFoot,foot),15)
            XCTAssertTrue(frames.contains(pose.frameName))
            if bird.state == .flying {XCTAssertTrue(pose.frameName.hasPrefix("fly"))}
            previousBird=pose.position;previousFoot=foot
            circled = circled || bird.isCircling;landed = landed || bird.state == .landing
            if let leaf=e.propSnapshot().first {
                XCTAssertFalse(disappeared,"A faded prop must never reappear")
                XCTAssertEqual(leaf.id,previousLeaf.id)
                XCTAssertLessThan(Geometry.distance(previousLeaf.position,leaf.position),15)
                XCTAssertGreaterThanOrEqual(leaf.opacity,0);XCTAssertLessThanOrEqual(leaf.opacity,1)
                XCTAssertTrue(leaf.rotation.isFinite);XCTAssertTrue(display.contains(leaf.rect))
                XCTAssertLessThanOrEqual(leaf.opacity,previousLeaf.opacity+1e-12)
                maximumLeafTravel=max(maximumLeafTravel,Geometry.distance(leaf.position,center))
                minimumOpacity=min(minimumOpacity,leaf.opacity);faded = faded || leaf.opacity<0.99
                previousLeaf=leaf
            } else {
                disappeared=true
                XCTAssertLessThan(previousLeaf.opacity,0.01,"Removal should follow the fade")
            }
            if !terminals(e,id).isEmpty {break}
        }
        XCTAssertTrue(circled);XCTAssertTrue(landed);XCTAssertTrue(faded);XCTAssertTrue(disappeared)
        XCTAssertLessThan(minimumOpacity,0.01);XCTAssertGreaterThan(maximumLeafTravel,100)
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed]);released(e)
    }

    func testRepeatedSnapshotsArePureAndPauseFreezesObservationCircleAndFade() throws {
        for phase in ["observe","circle","fade"] {
            let e=fixture(),bird=e.birds[0],id=try start(e)
            if phase != "observe" {
                for _ in 0..<30*60 {
                    if phase == "circle" && bird.isCircling {break}
                    if phase == "fade",let leaf=e.propSnapshot().first,leaf.opacity<0.9 {break}
                    e.advance(BehaviorEngine.step)
                }
                if phase == "circle" {XCTAssertTrue(bird.isCircling)}
                else {XCTAssertLessThan(try XCTUnwrap(e.propSnapshot().first).opacity,0.9)}
            }
            let birds=e.renderSnapshot().map(BirdSample.init),props=e.propSnapshot().map(PropSample.init)
            let time=e.time,stateTime=bird.stateTime,revision=bird.motionRevision,eventCount=e.events.count
            for _ in 0..<100 {
                XCTAssertEqual(e.renderSnapshot().map(BirdSample.init),birds)
                XCTAssertEqual(e.propSnapshot().map(PropSample.init),props)
            }
            XCTAssertEqual(e.time,time);XCTAssertEqual(bird.stateTime,stateTime)
            XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(e.events.count,eventCount)
            e.handle(.pause(true));advance(e,seconds:2)
            XCTAssertEqual(e.renderSnapshot().map(BirdSample.init),birds)
            XCTAssertEqual(e.propSnapshot().map(PropSample.init),props)
            XCTAssertEqual(bird.stateTime,stateTime);XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertTrue(terminals(e,id).isEmpty);XCTAssertEqual(e.scenePropCount,1)
            e.handle(.pause(false));finish(e,id)
            XCTAssertEqual(terminals(e,id).map(\.type),[.completed]);released(e)
        }
    }

    func testNegativeOriginReplayMatchesAt30And60And120Hz() throws {
        struct Trace:Equatable {
            let birds:[BirdSample],props:[PropSample]
            let events:[String]
            let active:Int,leased:Int,landings:Int,propCount:Int
        }
        func replay(hz:Int) throws -> [Trace] {
            let e=fixture(offset:CGPoint(x:-1900,y:-700)),origin=e.birds[0].position,id=try start(e)
            var trace:[Trace]=[]
            for _ in 0..<35 {
                advance(e,seconds:1,hz:hz)
                trace.append(Trace(birds:e.renderSnapshot().map(BirdSample.init),props:e.propSnapshot().map(PropSample.init),
                    events:e.events.map{"\($0.sequence):\($0.time):\($0.type):\($0.reason?.rawValue ?? "")"},
                    active:e.activeRunCount,leased:e.leasedBirdCount,landings:e.reservedLandingCount,propCount:e.scenePropCount))
            }
            XCTAssertEqual(terminals(e,id).map(\.type),[.completed]);XCTAssertEqual(e.birds[0].position,origin)
            released(e);return trace
        }
        let reference=try replay(hz:60)
        XCTAssertEqual(try replay(hz:30),reference);XCTAssertEqual(try replay(hz:120),reference)
    }

    func testClearPropsCancelsObservationAndFlightOnceWithoutTeleporting() throws {
        for delay in [0.2,2.0] {
            let e=fixture(),bird=e.birds[0],id=try start(e)
            advance(e,seconds:delay)
            let position=bird.position
            XCTAssertEqual(e.handle(.clearProps),.accepted);XCTAssertEqual(bird.position,position)
            XCTAssertEqual(terminals(e,id).map(\.type),[.cancelled])
            XCTAssertEqual(terminals(e,id).map(\.reason),[.userInput]);released(e)
            e.handle(.clearProps);advance(e,seconds:2)
            XCTAssertEqual(terminals(e,id).count,1);released(e)
        }
    }

    func testRemovePropReleasesItsRunAndOldIDCannotCancelANewScene() throws {
        let e=fixture(),bird=e.birds[0],first=try start(e)
        let oldProp=try XCTUnwrap(e.propSnapshot().first).id
        advance(e,seconds:2)
        let position=bird.position
        XCTAssertEqual(e.handle(.removeProp(oldProp)),.accepted)
        XCTAssertEqual(bird.position,position)
        XCTAssertEqual(terminals(e,first).map(\.reason),[.removed]);released(e)
        // Removing a leaf allows the intact return route to finish naturally.
        advance(e,seconds:30)
        XCTAssertEqual(bird.state,.perched)
        let second=try start(e),newProp=try XCTUnwrap(e.propSnapshot().first).id
        XCTAssertGreaterThan(newProp,oldProp)
        e.handle(.removeProp(oldProp))
        XCTAssertTrue(terminals(e,second).isEmpty);XCTAssertEqual(e.scenePropCount,1)
        finish(e,second)
        XCTAssertEqual(terminals(e,first).map(\.type),[.cancelled])
        XCTAssertEqual(terminals(e,second).map(\.type),[.completed]);released(e)
    }

    func testRelocatePreemptsLeafAndKeepsOnlyTheRelocationLease() throws {
        let e=fixture(),bird=e.birds[0],id=try start(e)
        advance(e,seconds:2)
        let position=bird.position,birdID=try XCTUnwrap(e.id(of:bird))
        let relocation=try runID(e.handle(.relocate(birdID)))
        XCTAssertEqual(bird.position,position)
        XCTAssertEqual(terminals(e,id).map(\.type),[.cancelled])
        XCTAssertEqual(terminals(e,id).map(\.reason),[.replaced])
        XCTAssertEqual(e.behavior(of:bird),.relocate);XCTAssertEqual(e.leasedBirdCount,1)
        XCTAssertEqual(e.scenePropCount,0);XCTAssertTrue(e.propSnapshot().isEmpty)
        finish(e,relocation)
        XCTAssertEqual(terminals(e,relocation).map(\.type),[.completed]);released(e)
    }

    func testDisablingLeafSettingCancelsPendingAndActiveWithoutRevival() throws {
        for pending in [false,true] {
            let e=fixture()
            let id:BehaviorRunID?
            if pending {XCTAssertEqual(e.handle(.releaseLeafAfter(0.5)),.scheduled);id=nil}
            else {id=try start(e);advance(e,seconds:2)}
            let position=e.birds[0].position
            var settings=e.settings;settings.leafPlayEnabled=false;e.applySettings(settings)
            XCTAssertEqual(e.birds[0].position,position);XCTAssertFalse(e.hasLeafPreview);released(e)
            if let id {XCTAssertEqual(terminals(e,id).map(\.reason),[.settingsChanged])}
            else {
                XCTAssertEqual(e.events.filter{$0.type == .previewResult && $0.kind == .leafPlay}.map(\.reason),[.settingsChanged])
            }
            XCTAssertEqual(e.handle(.releaseLeafAfter(0)),.rejected(.disabled))
            XCTAssertEqual(e.handle(.leafPlay(at:center,source:.preview)),.rejected(.disabled))
            settings.leafPlayEnabled=true;e.applySettings(settings);advance(e,seconds:12)
            XCTAssertEqual(e.events.filter{$0.kind == .leafPlay && $0.type == .started}.count,pending ? 0:1)
            released(e)
        }
    }

    func testPointerAndLeafPreviewsShareOneQueueAndRejectDuplicateEncounters() throws {
        for leafFirst in [false,true] {
            let e=fixture()
            XCTAssertEqual(e.handle(leafFirst ? .releaseLeafAfter(0.5):.previewPointerAfter(0.5)),.scheduled)
            XCTAssertEqual(e.hasLeafPreview,leafFirst);XCTAssertEqual(e.hasPointerPreview,!leafFirst)
            XCTAssertEqual(e.handle(.releaseLeafAfter(0.1)),.rejected(.busy))
            XCTAssertEqual(e.handle(.previewPointerAfter(0.1)),.rejected(.busy))
            XCTAssertEqual(e.handle(.leafPlay(at:center,source:.preview)),.rejected(.busy))
            XCTAssertEqual(e.handle(.pointerVisit(.preview)),.rejected(.busy))
            advance(e,seconds:0.6)
            XCTAssertFalse(e.hasLeafPreview);XCTAssertFalse(e.hasPointerPreview)
            XCTAssertEqual(e.activeRunCount,1)
            XCTAssertEqual(e.handle(.releaseLeafAfter(0)),.rejected(.busy))
            XCTAssertEqual(e.handle(.previewPointerAfter(0)),.rejected(.busy))
            XCTAssertEqual(e.handle(.leafPlay(at:center,source:.preview)),.rejected(.busy))
            XCTAssertEqual(e.handle(.pointerVisit(.preview)),.rejected(.busy))
            e.handle(.cancelAmbient(.shutdown));released(e)
        }
    }

    func testDelayedReleaseUsesPointerAtDeadlineRatherThanSchedulingTime() throws {
        let e=fixture()
        var world=e.world;world.pointer=CGPoint(x:5,y:5);e.updateWorld(world)
        XCTAssertEqual(e.handle(.releaseLeafAfter(0.5)),.scheduled)
        advance(e,seconds:0.25);XCTAssertTrue(e.propSnapshot().isEmpty)
        world.pointer=CGPoint(x:1050,y:500);e.updateWorld(world)
        let birdID=try XCTUnwrap(e.id(of:e.birds[0]))
        let plan=try XCTUnwrap(LeafPlayPlan.make(id:birdID,center:world.pointer,in:e))
        advance(e,seconds:0.25)
        XCTAssertEqual(try XCTUnwrap(e.propSnapshot().first).position,plan.leafPosition(progress:0))
        XCTAssertFalse(e.hasLeafPreview)
        let previews=e.events.filter{$0.kind == .leafPlay && $0.type == .previewResult}
        XCTAssertEqual(previews.count,1);XCTAssertNil(previews.first?.reason)
        let id=try XCTUnwrap(e.events.first{$0.kind == .leafPlay && $0.type == .started}?.runID)
        finish(e,id);XCTAssertEqual(terminals(e,id).map(\.type),[.completed]);released(e)
    }

    func testClearingDelayedLeafCannotReviveItAndPreservesQueuedPointerPreview() {
        let e=fixture()
        XCTAssertEqual(e.handle(.releaseLeafAfter(0.5)),.scheduled)
        advance(e,seconds:0.2);e.handle(.clearProps);e.handle(.clearProps)
        XCTAssertFalse(e.hasLeafPreview);advance(e,seconds:12);released(e)
        XCTAssertFalse(e.events.contains{$0.kind == .leafPlay && $0.type == .started})
        XCTAssertEqual(e.events.filter{$0.kind == .leafPlay && $0.type == .previewResult}.map(\.reason),[.userInput])
        XCTAssertEqual(e.handle(.previewPointerAfter(0.5)),.scheduled)
        e.handle(.clearProps);XCTAssertTrue(e.hasPointerPreview)
        advance(e,seconds:0.6);XCTAssertEqual(e.activeRunCount,1)
        e.handle(.cancelAmbient(.shutdown));released(e)
    }

    func testPointerSettingsAndPointerMovementDoNotCancelLeafPlay() throws {
        let e=fixture(),id=try start(e)
        advance(e,seconds:2)
        var settings=e.settings;settings.pointerVisits=false;settings.pointerFollowEnabled=true;e.applySettings(settings)
        var world=e.world;world.pointer=CGPoint(x:-4000,y:-4000);e.updateWorld(world)
        XCTAssertTrue(terminals(e,id).isEmpty);XCTAssertEqual(e.scenePropCount,1)
        settings.pointerFollowEnabled=false;e.applySettings(settings)
        finish(e,id)
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed]);released(e)
        // Leaf previews also work when pointer encounters are disabled.
        world.pointer=center;e.updateWorld(world)
        XCTAssertEqual(e.handle(.releaseLeafAfter(0)),.scheduled)
        advance(e,seconds:0.1);XCTAssertEqual(e.scenePropCount,1)
        e.handle(.clearProps);released(e)
    }

    func testGroundReturnFitsHiddenDockAndFooterAtPhysicalDisplayBoundary() throws {
        let layouts=[display,CGRect(x:0,y:0,width:1600,height:1140),CGRect(x:80,y:0,width:1520,height:1200)]
        for work in layouts {
            let e=fixture(),ground=Geometry.ground(id:90,display:display,workArea:work)
            var world=e.world;world.screens=[work];world.surfaces=[ground];e.updateWorld(world)
            e.installFixtureBirds([makeBird(on:ground,in:e)])
            let bird=e.birds[0],origin=e.birds[0].position,scale=e.spriteScale(for:e.birds[0])
            XCTAssertEqual(origin.y,min(work.maxY,display.maxY-9*scale))
            XCTAssertTrue(display.contains(Geometry.landingFootprint(at:origin,scale:scale)))
            let id=try start(e)
            finish(e,id)
            XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
            XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.hostID,ground.id);released(e)
        }
    }

    func testHostScaleScreensFramesAndPanelsInvalidateEvenWhilePaused() throws {
        for paused in [false,true] {
            for change in ["hostPID","hostMoved","hostMissing","scale","screen","display","frames","panel"] {
                let e=fixture(),bird=e.birds[0],id=try start(e)
                advance(e,seconds:2)
                if paused {e.handle(.pause(true))}
                let position=bird.position
                var world=e.world
                switch change {
                case "hostPID":world.surfaces=[Surface(id:host.id,pid:host.pid+1,rect:host.rect)]
                case "hostMoved":world.surfaces=[Surface(id:host.id,pid:host.pid,rect:host.rect.offsetBy(dx:20,dy:0))]
                case "hostMissing":world.surfaces=[]
                case "scale":world.scale=1.1
                case "screen":world.screens=[display.insetBy(dx:1,dy:1)]
                case "display":world.displays=[display.insetBy(dx:1,dy:1)]
                case "frames":world.availableFrames[.treeSparrow]?.remove("fly7")
                default:
                    let leaf=try XCTUnwrap(e.propSnapshot().first)
                    world.surfaces.insert(Surface(id:99,rect:leaf.rect.insetBy(dx:-5,dy:-5),layer:3),at:0)
                }
                e.updateWorld(world)
                XCTAssertEqual(bird.position,position,"\(change), paused=\(paused)")
                XCTAssertEqual(terminals(e,id).map(\.type),[.failed],change)
                XCTAssertEqual(terminals(e,id).map(\.reason),[change == "frames" ? .missingFrames:.targetInvalid],change)
                released(e);advance(e,seconds:1)
                XCTAssertEqual(terminals(e,id).count,1)
            }
        }
    }

    func testEachRequiredFrameAndInvalidRequestRejectWithoutLeakingResources() {
        for missing in frames.sorted() {
            let e=fixture();var world=e.world
            world.availableFrames[.treeSparrow]?.remove(missing);e.updateWorld(world)
            XCTAssertEqual(e.handle(.leafPlay(at:center,source:.preview)),.rejected(.missingFrames),missing)
            released(e)
        }
        for point in [CGPoint(x:CGFloat.nan,y:500),CGPoint(x:800,y:CGFloat.infinity),CGPoint(x:5,y:5),CGPoint(x:800,y:900)] {
            let e=fixture()
            XCTAssertEqual(e.handle(.leafPlay(at:point,source:.preview)),.rejected(.noSpace));released(e)
        }
        let e=fixture();e.handle(.pause(true))
        XCTAssertEqual(e.handle(.leafPlay(at:center,source:.preview)),.rejected(.paused))
        XCTAssertEqual(e.handle(.releaseLeafAfter(0)),.rejected(.paused));released(e)
        e.handle(.pause(false));var world=e.world;world.buttonsDown=true;e.updateWorld(world)
        XCTAssertEqual(e.handle(.leafPlay(at:center,source:.preview)),.rejected(.userInput));released(e)
    }

    func testPanelIntersectingLeafRouteRejectsButDistantPanelAndNormalWindowsDoNot() throws {
        for obstacle in ["routePanel","distantPanel","normalWindow"] {
            let e=fixture(),birdID=try XCTUnwrap(e.id(of:e.birds[0]))
            let plan=try XCTUnwrap(LeafPlayPlan.make(id:birdID,center:center,in:e))
            let point=plan.leafPosition(progress:0.5)
            let rect=obstacle == "distantPanel" ? CGRect(x:10,y:10,width:40,height:40):CGRect(x:point.x-20,y:point.y-20,width:40,height:40)
            var world=e.world
            world.surfaces.insert(Surface(id:98,rect:rect,layer:obstacle == "normalWindow" ? 0:3),at:0)
            e.updateWorld(world)
            if obstacle == "routePanel" {
                XCTAssertEqual(e.handle(.leafPlay(at:center,source:.preview)),.rejected(.noSpace));released(e)
            } else {
                let id=try start(e)
                XCTAssertEqual(e.propSnapshot().first?.blockers,obstacle == "distantPanel" ? [rect]:[])
                finish(e,id);XCTAssertEqual(terminals(e,id).map(\.type),[.completed]);released(e)
            }
        }
    }

    func testPreflightAndSuccessfulSceneDoNotConsumeEngineRandomStream() throws {
        let e=fixture(seed:9123),reference=fixture(seed:9123)
        let birdID=try XCTUnwrap(e.id(of:e.birds[0]))
        for _ in 0..<4 {
            XCTAssertNotNil(LeafPlayPlan.make(id:birdID,center:center,in:e))
            XCTAssertNil(LeafPlayPlan.make(id:birdID,center:e.birds[0].position,in:e))
        }
        for _ in 0..<8 {XCTAssertEqual(e.random.unit(),reference.random.unit())}
        let id=try start(e)
        finish(e,id)
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed]);released(e)
        for _ in 0..<16 {XCTAssertEqual(e.random.unit(),reference.random.unit())}
    }

    func testEightTooNearBirdsCannotExhaustBudgetBeforeNinthEligibleBird() throws {
        let e=fixture(),eligible=e.birds[0]
        var perches:[Surface]=[],nearby:[Bird]=[]
        for y:CGFloat in [420,500,580] {
            for x:CGFloat in [720,800,880] where x != 800 || y != 500 {
                let perch=Surface(id:UInt32(100+perches.count),pid:43,rect:CGRect(x:x-34,y:y,width:68,height:20))
                perches.append(perch);nearby.append(makeBird(on:perch,in:e))
            }
        }
        var world=e.world;world.surfaces=perches+[host];e.updateWorld(world)
        e.installFixtureBirds(nearby+[eligible])
        XCTAssertEqual(nearby.count,8)
        for bird in nearby {
            XCTAssertLessThan(Geometry.distance(bird.position,center),Geometry.distance(eligible.position,center))
            XCTAssertNil(PointerOrbit(center:center,origin:bird.position,area:display,spriteScale:e.spriteScale(for:bird)))
        }
        let footprints=e.birds.map{Geometry.landingFootprint(at:$0.position,scale:e.spriteScale(for:$0)).insetBy(dx:-8,dy:-8)}
        for (index,footprint) in footprints.enumerated() {
            for other in footprints.dropFirst(index+1) {
                let cut=footprint.intersection(other)
                XCTAssertTrue(cut.isNull || cut.isEmpty,"Fixture return slots must not collide")
            }
        }
        let id=try start(e),eligibleID=try XCTUnwrap(e.id(of:eligible))
        XCTAssertEqual(e.events.first{$0.runID==id && $0.type == .started}?.participants,[eligibleID])
        finish(e,id)
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed]);released(e)
    }
}
