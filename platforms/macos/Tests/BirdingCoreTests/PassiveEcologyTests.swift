import XCTest
@testable import BirdingCore

final class PassiveEcologyTests:XCTestCase {
    let screen=CGRect(x:0,y:0,width:1600,height:1200)
    let host=Surface(id:91,pid:42,rect:CGRect(x:100,y:900,width:1400,height:250))
    func fixture(seed:UInt64=81,automatic:Bool=false) -> BehaviorEngine {
        var settings=BirdSettings();settings.pointerVisits=false;settings.flockPasses=false
        settings.socialInteractions=false;settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.autonomousRouting=false;e.ambientEnabled=automatic
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:20,y:20),
            availableFrames:[.treeSparrow:Set(["stand","blink","preen0","preen1","land0","land1","land2"]+(0...7).map{"fly\($0)"})]))
        let bird=Bird(position:.zero,fraction:0.5,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host);bird.perchDuration=600;e.installFixtureBirds([bird]);return e
    }
    func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    func point(_ e:BehaviorEngine,_ point:CGPoint,buttons:Bool=false) {
        var world=e.world;world.pointer=point;world.buttonsDown=buttons;e.updateWorld(world)
    }
    func testClickCommandAndButtonSnapshotAreOneStimulusAndPauseFreezesMemory() throws {
        let e=fixture(),bird=e.birds[0]
        point(e,bird.position,buttons:true);e.handle(.pointerClick)
        let hit=try XCTUnwrap(e.ecology(of:bird))
        XCTAssertEqual(hit.disturbance,0.8*(1-hit.temperament.boldness),accuracy:1e-9)
        advance(e,0.5)
        let state=try XCTUnwrap(e.ecology(of:bird))
        XCTAssertEqual(state.disturbance,hit.disturbance*pow(0.5,0.5/6),accuracy:1e-9)
        e.handle(.pause(true));advance(e,12)
        XCTAssertEqual(e.ecology(of:bird),state)
        point(e,CGPoint(x:20,y:20));e.handle(.pause(false));advance(e,6)
        XCTAssertEqual(try XCTUnwrap(e.ecology(of:bird)).disturbance,state.disturbance/2,accuracy:1e-9)
    }
    func testSampledDownBeforeNativeCommandDoesNotDoubleCount() throws {
        let e=fixture(),bird=e.birds[0]
        point(e,bird.position,buttons:true);advance(e,0.1)
        let before=try XCTUnwrap(e.ecology(of:bird)).disturbance
        e.handle(.pointerClick)
        XCTAssertEqual(try XCTUnwrap(e.ecology(of:bird)).disturbance,before)
        e.handle(.pause(true));point(e,bird.position);point(e,bird.position,buttons:true);e.handle(.pointerClick)
        XCTAssertGreaterThan(try XCTUnwrap(e.ecology(of:bird)).disturbance,before)
    }
    func testRelocationAndPointerClickDoNotDoubleCountDisturbance() throws {
        let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:e.birds[0]))
        point(e,bird.position,buttons:true)
        XCTAssertTrue(e.handle(.relocate(id)).accepted);e.handle(.pointerClick)
        let ecology=try XCTUnwrap(e.ecology(of:bird))
        XCTAssertEqual(ecology.disturbance,0.8*(1-ecology.temperament.boldness),accuracy:1e-9)
    }
    func testAutomaticAlertPreemptsAutomaticRestButPreservesExplicitPreview() throws {
        for source:BehaviorSource in [.automatic,.preview] {
            let e=fixture(automatic:true),bird=e.birds[0]
            XCTAssertTrue(e.handle(.perchAction(.rest,source)).accepted)
            // Establish a stationary baseline, then cross the bird at 900pt/s.
            let origin=bird.position
            point(e,CGPoint(x:origin.x-300,y:origin.y-20));advance(e,0.2)
            for i in 1...40 {
                point(e,CGPoint(x:origin.x-300+CGFloat(i)*15,y:origin.y-20));e.advance(BehaviorEngine.step)
            }
            let alerts=e.events.filter{$0.type == .started && $0.kind == .alert}
            // Perch rest itself cancels on close approach. A preview must never
            // be replaced by the higher-priority automatic reaction beforehand.
            XCTAssertLessThanOrEqual(alerts.count,1)
            if source == .automatic {XCTAssertEqual(alerts.count,1)}
            let restEnd=e.events.first{$0.kind == .rest && $0.type == .cancelled}
            if source == .preview {XCTAssertNotEqual(restEnd?.reason,.replaced)}
            XCTAssertGreaterThan(try XCTUnwrap(e.ecology(of:bird)).disturbance,0)
        }
    }
    func testAttentionCooldownIsAppliedOnceOnEveryTerminalPathAndPreviewBypassesIt() throws {
        for completion in [true,false] {
            let e=fixture(),bird=e.birds[0]
            XCTAssertTrue(e.handle(.attention(.watch,.preview)).accepted)
            if completion {advance(e,3)} else {e.handle(.pointerClick)}
            let state=try XCTUnwrap(e.ecology(of:bird))
            XCTAssertGreaterThan(state.cooldowns[.watch] ?? 0,6)
            let terminals=e.events.filter{$0.kind == .watch && [.completed,.cancelled,.failed].contains($0.type)}
            XCTAssertEqual(terminals.count,1)
            XCTAssertTrue(e.handle(.attention(.watch,.preview)).accepted)
        }
    }
    func testPointerPerceptionRejectsFirstSampleWarpAndCrossDisplayJump() {
        var p=PointerPerception()
        p.sample(CGPoint(x:500,y:500),screens:[screen],dt:1.0/60);XCTAssertFalse(p.fast)
        for i in 1...12 {p.sample(CGPoint(x:500+i*15,y:500),screens:[screen],dt:1.0/60)}
        XCTAssertTrue(p.fast)
        p.sample(CGPoint(x:1500,y:500),screens:[screen],dt:1.0/60);XCTAssertFalse(p.fast)
        p.sample(CGPoint(x:1700,y:500),screens:[screen,screen.offsetBy(dx:1600,dy:0)],dt:1.0/60)
        XCTAssertFalse(p.fast)
    }
    func testSampleRatesProduceOneFastPassAndComparableMemory() throws {
        func replay(_ hz:Int,speed:CGFloat) throws -> (Int,Double) {
            let e=fixture(automatic:true),origin=e.birds[0].position
            point(e,CGPoint(x:origin.x-400,y:origin.y-20));advance(e,0.5,hz:hz)
            for i in 1...hz {
                point(e,CGPoint(x:origin.x-400+CGFloat(i)*speed/CGFloat(hz),y:origin.y-20))
                e.advance(1/Double(hz))
            }
            return (e.events.filter{$0.kind == .alert && $0.type == .started}.count,try XCTUnwrap(e.ecology(of:e.birds[0])).disturbance)
        }
        for speed:CGFloat in [610,650,800] {
            let reference=try replay(60,speed:speed)
            XCTAssertEqual(reference.0,1)
            for hz in [30,120] {
                let result=try replay(hz,speed:speed)
                XCTAssertEqual(result.0,reference.0);XCTAssertEqual(result.1,reference.1,accuracy:0.005)
            }
        }
    }
    func testSeparateClicksDuringPauseCountButHeldClickDoesNotRepeatOnResume() throws {
        let e=fixture(),bird=e.birds[0]
        point(e,bird.position,buttons:true);e.handle(.pointerClick)
        let first=try XCTUnwrap(e.ecology(of:bird)).disturbance
        e.handle(.pause(true));e.handle(.pause(false));advance(e,0.1)
        XCTAssertEqual(try XCTUnwrap(e.ecology(of:bird)).disturbance,first*pow(0.5,0.1/6),accuracy:1e-9)
        e.handle(.pause(true));point(e,bird.position);point(e,bird.position,buttons:true);e.handle(.pointerClick)
        let second=try XCTUnwrap(e.ecology(of:bird)).disturbance
        XCTAssertEqual(second,min(1,first*pow(0.5,0.1/6)+first),accuracy:1e-9)
        point(e,bird.position);point(e,bird.position,buttons:true);e.handle(.pointerClick)
        XCTAssertEqual(try XCTUnwrap(e.ecology(of:bird)).disturbance,min(1,second+first),accuracy:1e-9)
    }
    func testClickInOuterAttentionRangeClearsWatchCandidateAndSetsCooldown() throws {
        let e=fixture(automatic:true),bird=e.birds[0],id=try XCTUnwrap(e.id(of:e.birds[0]))
        point(e,CGPoint(x:bird.position.x+150,y:bird.position.y))
        e.handle(.pointerClick);advance(e,0.2)
        XCTAssertGreaterThan(try XCTUnwrap(e.ecology(of:bird)).cooldowns[.watch] ?? 0,3)
        XCTAssertNil(e.perchPlanner.attentionCandidate(id))
        XCTAssertFalse(e.events.contains{$0.kind == .watch && $0.type == .started})
    }
    func testLeafRejectsPerchThatWillExpireDuringObservation() {
        let e=fixture(automatic:true),bird=e.birds[0]
        var settings=e.settings;settings.ambientLeafPlayEnabled=true;e.applySettings(settings)
        bird.perchDuration=0.3
        e.requestAutomaticLeaf()
        XCTAssertEqual(e.activeRunCount,0)
        XCTAssertNil(e.ecology(of:bird)?.cooldowns[.leafPlay])
        XCTAssertFalse(e.handle(.leafPlay(at:CGPoint(x:800,y:500),source:.preview)).accepted)
    }
    func testRenderAndValidationReadsDoNotAdvanceEcologyOrConsumeFlightRandom() throws {
        let e=fixture(),control=fixture(),bird=e.birds[0]
        XCTAssertTrue(e.handle(.attention(.watch,.preview)).accepted)
        let state=e.ecology(of:bird)
        for _ in 0..<100 {e.updateWorld(e.world);_=e.renderSnapshot();_=e.propSnapshot()}
        XCTAssertEqual(e.ecology(of:bird),state)
        advance(e,4);advance(control,4)
        for _ in 0..<16 {XCTAssertEqual(e.random.unit(),control.random.unit())}
    }
    func testAutomaticLeafUsesCalmResidentAndCancelsWhenItsAutomaticSwitchIsDisabled() throws {
        let e=fixture(automatic:true),bird=e.birds[0]
        var settings=e.settings;settings.ambientLeafPlayEnabled=true;e.applySettings(settings)
        e.requestAutomaticLeaf()
        XCTAssertEqual(e.behavior(of:bird),.leafPlay)
        XCTAssertEqual(e.scenePropCount,1);XCTAssertEqual(e.residentCount,1)
        let prop=try XCTUnwrap(e.propSnapshot().first)
        XCTAssertGreaterThan(Geometry.distance(prop.position,e.world.pointer),100)
        settings.ambientLeafPlayEnabled=false;e.applySettings(settings)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.scenePropCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        // Manual previews retain their own master gate and ignore the automatic switch.
        bird.perch(on:host);bird.perchDuration=600
        XCTAssertTrue(e.handle(.leafPlay(at:CGPoint(x:800,y:500),source:.preview)).accepted)
    }
    func testRareLeafSharesExistingOpportunitiesAndDoesNotQueueWhenBusy() {
        for ticket in [0.05,0.5] {
            var scheduler=AmbientScheduler();scheduler.reset(.high)
            var events:[AmbientEvent]=[]
            for _ in 0..<46*60 {
                if let event=scheduler.tick(1.0/60,pointer:.zero,buttonsDown:false,pointerEnabled:false,flockEnabled:false,
                    leafEnabled:true,frequency:.high,busy:false,leafRandom:{ticket},random:{0}) {events.append(event)}
            }
            XCTAssertEqual(events,ticket<0.1 ? [.leafPlay]:[])
        }
        var scheduler=AmbientScheduler();scheduler.reset(.high)
        for _ in 0..<46*60 {
            XCTAssertNil(scheduler.tick(1.0/60,pointer:.zero,buttonsDown:false,pointerEnabled:false,flockEnabled:false,
                leafEnabled:true,frequency:.high,busy:true,leafRandom:{0},random:{0}))
        }
        XCTAssertNil(scheduler.tick(1.0/60,pointer:.zero,buttonsDown:false,pointerEnabled:false,flockEnabled:false,
            leafEnabled:true,frequency:.high,busy:false,leafRandom:{0},random:{0}))
    }
    func testDisturbedBirdDoesNotStartAutomaticLeafAndNoOpportunityIsQueued() throws {
        let e=fixture(automatic:true),bird=e.birds[0]
        var settings=e.settings;settings.ambientLeafPlayEnabled=true;e.applySettings(settings)
        point(e,bird.position);e.handle(.pointerClick);point(e,CGPoint(x:20,y:20))
        e.requestAutomaticLeaf();XCTAssertEqual(e.scenePropCount,0)
        advance(e,8);XCTAssertEqual(e.scenePropCount,0)
    }
}
