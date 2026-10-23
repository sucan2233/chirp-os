import XCTest
@testable import BirdingCore

final class AllopreeningSchedulingTests:XCTestCase {
    private func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    private func fixture(seed:UInt64=81,automatic:Bool=false,hz:Int=60) -> BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false
        settings.pointerVisits=false;settings.flockPasses=false;settings.ambientLeafPlayEnabled=false
        settings.ambientFrequency = .high
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.autonomousRouting=false;e.ambientEnabled=automatic
        let screen=CGRect(x:0,y:0,width:1600,height:1000)
        let host=Surface(id:91,pid:42,rect:CGRect(x:300,y:450,width:800,height:180))
        let frames=Set(["stand","land0","land1","land2"]+(0...2).flatMap{["allopreenGive\($0)","allopreenReceive\($0)"]})
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],
            pointer:CGPoint(x:1400,y:50),availableFrames:[.barnSwallow:frames]))
        for x:CGFloat in [500,620] {
            let fraction=(x-Geometry.perchX(0,rect:host.rect))/(host.rect.width-84)
            let bird=Bird(position:.zero,fraction:fraction,profile:settings.catalog.profile(.barnSwallow),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
            _=e.register(bird)
        }
        // Stable residents accrue real quiet time. No request injects the
        // automatic scene: the production social opportunity remains at 45 s.
        advance(e,automatic ? 44:10,hz:hz)
        return e
    }
    func testAutomaticProductionOpportunityCanCompleteWithoutAddingBirds() {
        var completed=0
        for seed:UInt64 in 1...16 {
            let e=fixture(seed:seed,automatic:true),before=e.birds.map(\.position)
            advance(e,2);e.ambientEnabled=false;advance(e,16)
            completed+=e.events.filter{$0.kind == .allopreening && $0.source == .automatic && $0.type == .completed}.count
            XCTAssertEqual(e.birds.count,2)
            XCTAssertEqual(e.birds.map(\.position),before)
            XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertFalse(e.events.contains{$0.kind == .allopreening && $0.source != .automatic})
        }
        XCTAssertGreaterThan(completed,0)
    }
    func testSharedEncounterBudgetAndCooldownApplyToBothParticipants() throws {
        let e=fixture()
        XCTAssertTrue(e.handle(.allopreening(.automatic)).accepted)
        XCTAssertEqual(e.leasedBirdCount,2);XCTAssertEqual(e.reservedLandingCount,1)
        XCTAssertEqual(e.handle(.travelTogether(.preview)),.rejected(.busy))
        advance(e,12)
        XCTAssertEqual(e.events.filter{$0.kind == .allopreening && $0.type == .completed}.count,1)
        for bird in e.birds {
            let id=try XCTUnwrap(e.id(of:bird))
            for kind:BehaviorKind in [.allopreening,.travelTogether,.chase,.socialGreeting,.pairedTakeoff] {
                XCTAssertEqual(e.perchPlanner.automaticWeight(id,kind:kind),0)
            }
        }
    }
    func testQuietAndDisabledChildDiscardOpportunityWithoutQueuedRetry() {
        for quiet in [false,true] {
            let e=fixture(automatic:true);var settings=e.settings
            if quiet {settings.activityRhythm = .quiet} else {settings.allopreeningEnabled=false}
            e.applySettings(settings);advance(e,2)
            XCTAssertFalse(e.events.contains{$0.kind == .allopreening && $0.type == .started})
            settings.activityRhythm = .steady;settings.allopreeningEnabled=true;e.applySettings(settings)
            advance(e,0.5)
            XCTAssertFalse(e.events.contains{$0.kind == .allopreening && $0.type == .started})
        }
    }
    func testActiveAutomaticSceneFinishesWhenQuietIsEnabled() {
        let e=fixture();XCTAssertTrue(e.handle(.allopreening(.automatic)).accepted)
        advance(e,1.5)
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings)
        advance(e,12)
        XCTAssertEqual(e.events.filter{$0.kind == .allopreening && $0.type == .completed}.count,1)
        XCTAssertEqual(e.handle(.allopreening(.automatic)),.rejected(.disabled))
        XCTAssertTrue(e.handle(.allopreening(.preview)).accepted)
    }
    func testProductionOpportunityIsIdenticalAtThirtySixtyAndOneTwentyHz() {
        let reports=[30,60,120].map {hz -> BehaviorReplayReport in
            let e=fixture(automatic:true,hz:hz)
            advance(e,2,hz:hz);e.ambientEnabled=false;advance(e,16,hz:hz)
            return BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
        }
        XCTAssertEqual(reports[0],reports[1]);XCTAssertEqual(reports[1],reports[2])
    }
    func testRejectedPublicCommandIsRecordedAndReplayed() throws {
        let e=BehaviorEngine(seed:1,recordInputs:true)
        XCTAssertEqual(e.handle(.allopreening(.preview)),.rejected(.noCompanion))
        let log=try e.recordedInputs()
        XCTAssertEqual(log.inputs.last?.command?.name,"allopreening")
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
    }
}
