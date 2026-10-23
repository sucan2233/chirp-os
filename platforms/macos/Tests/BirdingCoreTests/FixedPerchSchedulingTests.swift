import XCTest
@testable import BirdingCore

final class FixedPerchSchedulingTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:1600,height:1200)
    private let host=Surface(id:61,pid:42,rect:CGRect(x:300,y:900,width:1000,height:150))
    private func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    private func fixture(seed:UInt64=18,hz:Int=60) -> BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        settings.ambientLeafPlayEnabled=false
        settings.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"main",displayFrame:display,x:0.6875,y:0.375)]
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.autonomousRouting=false;e.ambientEnabled=true
        let frames:Set<String>=["stand","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","land0","land1","land2"]
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[host],
            pointer:CGPoint(x:40,y:40),availableFrames:[.treeSparrow:frames],displayIDs:["main"]))
        let bird=Bird(position:.zero,fraction:0.5,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=20
        e.installFixtureBirds([bird]);advance(e,19,hz:hz)
        return e
    }
    func testRealDepartureOpportunityCanVisitWithoutSpawningOrManualCommands() {
        var starts=0,completed=0
        for seed:UInt64 in 1...64 {
            let e=fixture(seed:seed),bird=e.birds[0],identity=ObjectIdentifier(bird)
            XCTAssertFalse(bird.needsDestination)
            XCTAssertFalse(e.events.contains{$0.kind == .fixedPerchVisit})
            e.autonomousRouting=true;advance(e,2);e.autonomousRouting=false;advance(e,20)
            starts+=e.events.filter{$0.kind == .fixedPerchVisit && $0.type == .started}.count
            completed+=e.events.filter{$0.kind == .fixedPerchVisit && $0.type == .completed}.count
            XCTAssertEqual(e.birds.count,1);XCTAssertEqual(ObjectIdentifier(e.birds[0]),identity)
            XCTAssertFalse(e.events.contains{$0.kind == .fixedPerchVisit && $0.source != .automatic})
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
        XCTAssertGreaterThan(starts,0);XCTAssertLessThan(starts,64);XCTAssertEqual(completed,starts)
    }
    func testQuietDisabledAbsentArtAndEmptyAnchorsNeverStartAutomatically() {
        for mode in 0..<4 {
            for seed:UInt64 in 1...16 {
                let e=fixture(seed:seed);var settings=e.settings
                switch mode {
                case 0:settings.activityRhythm = .quiet
                case 1:settings.fixedPerchesEnabled=false
                case 2:var world=e.world;world.fixedPerchArtAvailable=false;e.updateWorld(world)
                default:settings.fixedPerches=[]
                }
                e.applySettings(settings);e.autonomousRouting=true;advance(e,10)
                XCTAssertFalse(e.events.contains{$0.kind == .fixedPerchVisit && $0.type == .started})
                if mode != 0 {XCTAssertTrue(e.fixedPerchSnapshot().isEmpty)}
                XCTAssertEqual(e.birds.count,1)
            }
        }
    }
    func testBlockedDepartureDoesNotRerollEveryFrameWhileOrdinaryRoutingHasNoSpace() {
        var rejected=0
        for seed:UInt64 in 1...32 {
            let e=fixture(seed:seed)
            var world=e.world;world.surfaces=[];world.screens=[];e.updateWorld(world)
            let perch=e.fixedPerchSnapshot()[0],bird=e.birds[0]
            bird.fraction=0.5;bird.perch(on:perch.surface,spriteScale:e.spriteScale(for:bird));bird.perchDuration=1
            advance(e,9);e.autonomousRouting=true;advance(e,10)
            let attempts=e.events.filter{$0.kind == .fixedPerchVisit && $0.type == .rejected}
            XCTAssertLessThanOrEqual(attempts.count,1);rejected+=attempts.count
            XCTAssertTrue(bird.needsDestination);XCTAssertEqual(bird.position,perch.foot)
        }
        XCTAssertGreaterThan(rejected,0)
    }
    func testQuietLetsActiveVisitFinishAndKeepsManualPreviewAvailable() {
        let e=fixture();XCTAssertTrue(e.handle(.fixedPerchVisit(.automatic)).accepted)
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings)
        advance(e,20)
        XCTAssertEqual(e.events.filter{$0.kind == .fixedPerchVisit && $0.type == .completed}.count,1)
        let preview=fixture();settings=preview.settings;settings.activityRhythm = .quiet;preview.applySettings(settings)
        XCTAssertTrue(preview.handle(.fixedPerchVisit(.preview)).accepted)
    }
    func testPreviewPrefersAnAvailableWindowResidentOverMovingAnExistingPerchOccupant() {
        let e=fixture();XCTAssertTrue(e.handle(.fixedPerchVisit(.preview)).accepted);advance(e,20)
        let first=e.birds[0],firstFoot=first.position
        var settings=e.settings
        settings.fixedPerches.append(FixedPerchAnchor(slot:2,displayID:"main",displayFrame:display,x:0.25,y:0.375))
        e.applySettings(settings)
        let newcomer=Bird(position:.zero,fraction:0.5,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
        newcomer.perch(on:host,spriteScale:e.spriteScale(for:newcomer));newcomer.perchDuration=600
        let id=e.register(newcomer);advance(e,0.6)
        XCTAssertTrue(e.handle(.fixedPerchVisit(.preview)).accepted)
        XCTAssertEqual(e.events.last(where:{$0.kind == .fixedPerchVisit && $0.type == .started})?.participants,[id])
        advance(e,20);XCTAssertEqual(first.position,firstFoot)
        XCTAssertEqual(Set(e.birds.compactMap(\.hostID)).count,2)
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
    }
    func testMissingArtDuringFlightOrAfterSettlingRecoversFromActualFoot() {
        for seconds in [0.5,20.0] {
            let e=fixture();XCTAssertTrue(e.handle(.fixedPerchVisit(.preview)).accepted);advance(e,seconds)
            let bird=e.birds[0],point=bird.position
            var world=e.world;world.fixedPerchArtAvailable=false;e.updateWorld(world,sampleDT:0.1)
            XCTAssertEqual(bird.position,point);XCTAssertTrue(bird.needsDestination)
            XCTAssertTrue(e.fixedPerchSnapshot().isEmpty);XCTAssertEqual(e.activeRunCount,0)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            world.fixedPerchArtAvailable=true;e.updateWorld(world)
            XCTAssertEqual(e.fixedPerchSnapshot().count,1);XCTAssertEqual(bird.position,point)
        }
    }
    func testNaturalOpportunityAndHabitatSnapshotsAreCallbackRateIndependent() {
        for seed:UInt64 in 1...16 {
            let reports=[30,60,120].map {hz -> BehaviorReplayReport in
                let e=fixture(seed:seed,hz:hz);e.autonomousRouting=true;advance(e,2,hz:hz)
                e.autonomousRouting=false;advance(e,20,hz:hz)
                return BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            }
            XCTAssertEqual(reports[0],reports[1]);XCTAssertEqual(reports[1],reports[2])
        }
    }
    func testCapabilityAndAnchorChangesRecordAndReplayAtAllCallbackRates() throws {
        let source=fixture()
        let e=BehaviorEngine(seed:18,settings:source.settings,recordInputs:true)
        e.populationEnabled=false;e.autonomousRouting=false;e.ambientEnabled=false
        e.updateWorld(source.world)
        XCTAssertEqual(e.handle(.fixedPerchVisit(.preview)),.rejected(.noSpecies));advance(e,0.5)
        var world=e.world;world.fixedPerchArtAvailable=false;e.updateWorld(world)
        advance(e,1)
        world.fixedPerchArtAvailable=true;e.updateWorld(world)
        var settings=e.settings;settings.fixedPerches=[];e.applySettings(settings)
        advance(e,1)
        let log=try e.recordedInputs()
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
    }
}
