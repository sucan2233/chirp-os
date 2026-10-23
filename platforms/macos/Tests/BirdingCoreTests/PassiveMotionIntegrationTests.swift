import XCTest
@testable import BirdingCore

final class PassiveMotionIntegrationTests:XCTestCase {
    func fixture(seed:UInt64) -> BehaviorEngine {
        var settings=BirdSettings()
        settings.passiveAttentionEnabled=false;settings.pointerVisits=false;settings.flockPasses=false
        settings.socialInteractions=false;settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.autonomousRouting=false
        let display=CGRect(x:0,y:0,width:1600,height:1200)
        let host=Surface(id:61,pid:42,rect:CGRect(x:100,y:900,width:1400,height:250))
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[host],pointer:CGPoint(x:20,y:20),
            availableFrames:[.treeSparrow:Set(["stand","blink","land0","land1","land2"]+(0...7).map{"fly\($0)"})]))
        let bird=Bird(position:.zero,fraction:0.5,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600;bird.tick(2)
        e.installFixtureBirds([bird]);return e
    }
    func near(_ e:BehaviorEngine) {
        var world=e.world
        world.pointer=CGPoint(x:e.birds[0].position.x-40,y:e.birds[0].position.y-10)
        e.updateWorld(world)
    }
    func starts(_ e:BehaviorEngine) -> Int {e.events.filter{$0.kind == .sideHop && $0.type == .started}.count}
    func testApproachHasOneChanceAndHeldPointerCannotRetryAfterCooldown() {
        var accepted=0
        for seed:UInt64 in 1...16 {
            let e=fixture(seed:seed)
            e.advance(BehaviorEngine.step);near(e);e.advance(BehaviorEngine.step)
            let initial=starts(e);accepted+=initial
            // Follow close enough to remain near, including after cooldown ends.
            for _ in 0..<32*60 {near(e);e.advance(BehaviorEngine.step)}
            XCTAssertEqual(starts(e),initial,"held approach must not become periodic hopping")
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
        XCTAssertGreaterThan(accepted,0)
        XCTAssertLessThan(accepted,16,"not every bird responds to every approach")
    }
    func testResumeAndFirstSampleDoNotInventAnApproach() {
        for seed:UInt64 in 1...16 {
            let e=fixture(seed:seed);near(e)
            for _ in 0..<60 {e.advance(BehaviorEngine.step)}
            XCTAssertEqual(starts(e),0)
            e.handle(.pause(true));e.handle(.pause(false))
            for _ in 0..<60 {near(e);e.advance(BehaviorEngine.step)}
            XCTAssertEqual(starts(e),0)
        }
    }
    func testFailedApproachIsConsumedWithoutRetryWhenRoomAppears() {
        for seed:UInt64 in 1...16 {
            let e=fixture(seed:seed),bird=e.birds[0]
            var world=e.world
            let tiny=Surface(id:61,pid:42,rect:CGRect(x:760,y:900,width:80,height:250))
            world.surfaces=[tiny];bird.perch(on:tiny,spriteScale:e.spriteScale(for:bird));bird.tick(2);e.updateWorld(world)
            e.advance(BehaviorEngine.step);near(e);e.advance(BehaviorEngine.step)
            XCTAssertEqual(starts(e),0)
            world=e.world;world.surfaces=[Surface(id:61,pid:42,rect:CGRect(x:100,y:900,width:1400,height:250))]
            e.updateWorld(world,sampleDT:1)
            for _ in 0..<60 {near(e);e.advance(BehaviorEngine.step)}
            XCTAssertEqual(starts(e),0,"new room must not retry an already consumed approach")
        }
    }
    func testAutomaticHopGatesDoNotAffectPreviewOrCauseDelayedApproach() {
        for ambient in [false,true] {
            let e=fixture(seed:81);e.ambientEnabled=ambient
            if ambient {var settings=e.settings;settings.sideHopEnabled=false;e.applySettings(settings)}
            near(e)
            for _ in 0..<60 {e.advance(BehaviorEngine.step)}
            XCTAssertEqual(starts(e),0)
            e.ambientEnabled=true
            var settings=e.settings;settings.sideHopEnabled=true;e.applySettings(settings)
            for _ in 0..<60 {near(e);e.advance(BehaviorEngine.step)}
            XCTAssertEqual(starts(e),0)
            XCTAssertTrue(e.handle(.sideHop(.preview)).accepted)
        }
    }
    func testNewPreferencesMigrateIndependentlyAndRoundTripWithoutLosingExistingValues() throws {
        var settings=BirdSettings();settings.hoverDelay=0.2;settings.pointerFollowEnabled=true
        settings.sideHopEnabled=false;settings.takeoffPreparationEnabled=false
        var data=try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as! [String:Any]
        data.removeValue(forKey:"sideHopEnabled");data.removeValue(forKey:"takeoffPreparationEnabled")
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:data))
        XCTAssertTrue(migrated.sideHopEnabled);XCTAssertTrue(migrated.takeoffPreparationEnabled)
        XCTAssertEqual(migrated.hoverDelay,0.2);XCTAssertTrue(migrated.pointerFollowEnabled)
        let loaded=try BirdSettings.decode(JSONEncoder().encode(settings))
        XCTAssertFalse(loaded.sideHopEnabled);XCTAssertFalse(loaded.takeoffPreparationEnabled)
        XCTAssertEqual(loaded.probabilities,settings.probabilities)
    }
    func testOlderSimulationVersionFailsBeforeDecodingNestedContent() throws {
        let object:[String:Any]=["version":1,"simulationVersion":1,"settings":"old content"]
        XCTAssertThrowsError(try BehaviorInputLog.decode(JSONSerialization.data(withJSONObject:object)))
    }
}
