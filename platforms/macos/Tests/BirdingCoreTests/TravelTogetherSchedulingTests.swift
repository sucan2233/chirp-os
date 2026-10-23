import XCTest
@testable import BirdingCore

final class TravelTogetherSchedulingTests:XCTestCase {
    private let screen=CGRect(x:0,y:0,width:1920,height:1100)
    private let hosts=[Surface(id:71,pid:42,rect:CGRect(x:1640,y:400,width:240,height:160)),
                       Surface(id:72,pid:42,rect:CGRect(x:1640,y:640,width:240,height:160))]
    private func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    private func fixture(seed:UInt64=81,automatic:Bool=false,hz:Int=60) -> BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false
        settings.pointerVisits=false;settings.flockPasses=false;settings.ambientLeafPlayEnabled=false
        settings.ambientFrequency = .high
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.autonomousRouting=false;e.ambientEnabled=automatic
        let frames=Set(["stand","blink","land0","land1","land2"]+(0...7).map{"fly\($0)"})
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:hosts,
            pointer:CGPoint(x:40,y:40),availableFrames:[.treeSparrow:frames]))
        // The production opportunity is due at 45 s; no direct scheduler or
        // command injection makes these two ordinary flights meet that clock.
        if automatic {advance(e,44,hz:hz)}
        let birds=[CGFloat(0.5),0.5].enumerated().map {index,fraction -> Bird in
            let host=hosts[index]
            let bird=Bird(position:CGPoint(x:100+CGFloat(index)*20,y:host.rect.minY),fraction:fraction,
                profile:settings.catalog.profile(.treeSparrow),random:{0.5})
            bird.perchDuration=600
            bird.fly(to:Geometry.foot(on:host,fraction:fraction,edge:.top,scale:e.spriteScale(for:bird)),
                host:host,arc:0,allowsOrbit:false,random:{0.5})
            return bird
        }
        e.installFixtureBirds(birds)
        advance(e,0.8,hz:hz)
        return e
    }
    func testAutomaticEntryUsesOneSocialBudgetAndSharedCooldown() throws {
        let e=fixture()
        XCTAssertTrue(e.handle(.travelTogether(.automatic)).accepted)
        XCTAssertTrue(e.ambientBusy);XCTAssertEqual(e.leasedBirdCount,2);XCTAssertEqual(e.reservedLandingCount,2)
        XCTAssertEqual(e.handle(.chase(.preview)),.rejected(.busy))
        advance(e,24)
        XCTAssertEqual(e.events.filter{$0.kind == .travelTogether && $0.type == .completed}.count,1)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        for bird in e.birds {
            let id=try XCTUnwrap(e.id(of:bird))
            for kind:BehaviorKind in [.travelTogether,.chase,.socialGreeting,.pairedTakeoff] {
                XCTAssertEqual(e.perchPlanner.automaticWeight(id,kind:kind),0)
            }
        }
    }
    func testExistingAutomaticPairCompletesAfterSwitchToQuiet() {
        let e=fixture();XCTAssertTrue(e.handle(.travelTogether(.automatic)).accepted)
        advance(e,0.5)
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings)
        e.updateWorld(e.world);XCTAssertTrue(e.ambientBusy)
        advance(e,24)
        XCTAssertEqual(e.events.filter{$0.kind == .travelTogether && $0.type == .completed}.count,1)
        XCTAssertEqual(e.handle(.travelTogether(.automatic)),.rejected(.disabled))
    }
    func testProductionSchedulerCanJoinExistingFlightsWithoutACommandOrExtraBirds() {
        var completed=0
        for seed:UInt64 in 1...16 {
            let e=fixture(seed:seed,automatic:true)
            advance(e,1);e.ambientEnabled=false;advance(e,24)
            completed+=e.events.filter{$0.kind == .travelTogether && $0.source == .automatic && $0.type == .completed}.count
            XCTAssertEqual(e.birds.count,2);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertFalse(e.events.contains{$0.kind == .travelTogether && $0.source != .automatic})
        }
        XCTAssertGreaterThan(completed,0)
    }
    func testScheduledSceneAndEndpointStateMatchAcrossCallbackRates() {
        let reports=[30,60,120].map {hz -> BehaviorReplayReport in
            let e=fixture(automatic:true,hz:hz)
            advance(e,1,hz:hz);e.ambientEnabled=false;advance(e,24,hz:hz)
            return BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
        }
        XCTAssertEqual(reports[0],reports[1]);XCTAssertEqual(reports[1],reports[2])
    }
    func testDisabledChildAndQuietSkipTheOpportunityWithoutDeferredPairing() {
        for quiet in [false,true] {
            let e=fixture(automatic:true);var settings=e.settings
            if quiet {settings.activityRhythm = .quiet} else {settings.travelTogetherEnabled=false}
            e.applySettings(settings);advance(e,2)
            XCTAssertFalse(e.events.contains{$0.kind == .travelTogether && $0.type == .started})
            settings.activityRhythm = .steady;settings.travelTogetherEnabled=true;e.applySettings(settings)
            advance(e,0.5)
            XCTAssertFalse(e.events.contains{$0.kind == .travelTogether && $0.type == .started})
        }
    }
    func testPublicRejectedCommandIsRecordedAndReplayed() throws {
        let e=BehaviorEngine(seed:1,recordInputs:true)
        XCTAssertEqual(e.handle(.travelTogether(.preview)),.rejected(.noCompanion))
        let log=try e.recordedInputs()
        XCTAssertEqual(log.inputs.last?.command?.name,"travelTogether")
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
    }
}
