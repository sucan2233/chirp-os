import XCTest
@testable import BirdingCore

final class ChaseSchedulingTests:XCTestCase {
    private func fixture(seed:UInt64=81) -> BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false
        settings.pointerVisits=false;settings.flockPasses=false;settings.ambientLeafPlayEnabled=false
        settings.ambientFrequency = .high
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.autonomousRouting=false;e.ambientEnabled=false
        let screen=CGRect(x:0,y:0,width:1600,height:1200)
        let host=Surface(id:61,pid:42,rect:CGRect(x:100,y:900,width:1400,height:200))
        let frames:Set<String>=Set(["stand","blink","idle0","idle1","idle2","land0","land1","land2"])
            .union((0...7).map{"fly\($0)"})
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],
            pointer:CGPoint(x:40,y:40),availableFrames:[.treeSparrow:frames]))
        let birds=[CGFloat(0.35),0.55].map {fraction -> Bird in
            let bird=Bird(position:.zero,fraction:fraction,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=3600;return bird
        }
        e.installFixtureBirds(birds);advance(e,6)
        return e
    }
    private func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    func testAutomaticChaseSharesSocialBudgetAndRecoveryPeriod() throws {
        let e=fixture()
        XCTAssertTrue(e.handle(.chase(.automatic)).accepted)
        XCTAssertTrue(e.ambientBusy);XCTAssertEqual(e.leasedBirdCount,2);XCTAssertEqual(e.reservedLandingCount,2)
        XCTAssertEqual(e.handle(.socialGreeting(.preview)),.rejected(.busy))
        XCTAssertEqual(e.handle(.chase(.preview)),.rejected(.busy))
        advance(e,24)
        XCTAssertEqual(e.events.filter{$0.kind == .chase && $0.type == .completed}.count,1)
        XCTAssertFalse(e.ambientBusy);XCTAssertEqual(e.reservedLandingCount,0)
        for bird in e.birds {
            let id=try XCTUnwrap(e.id(of:bird))
            for kind:BehaviorKind in [.chase,.socialGreeting,.sideBySide,.giveWay,.pairedTakeoff] {
                XCTAssertEqual(e.perchPlanner.automaticWeight(id,kind:kind),0)
            }
        }
        XCTAssertFalse(e.handle(.chase(.automatic)).accepted)
        XCTAssertTrue(e.handle(.chase(.preview)).accepted,"Explicit preview may bypass recovery cooldown")
    }
    func testQuietModeStopsNewAutomaticChasesButLetsCurrentSceneFinish() {
        let e=fixture()
        XCTAssertTrue(e.handle(.chase(.automatic)).accepted);advance(e,1)
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings)
        e.updateWorld(e.world)
        XCTAssertTrue(e.ambientBusy)
        advance(e,22)
        XCTAssertEqual(e.events.filter{$0.kind == .chase && $0.type == .completed}.count,1)
        XCTAssertFalse(e.events.contains{$0.kind == .chase && [.failed,.cancelled].contains($0.type)})
        XCTAssertEqual(e.handle(.chase(.automatic)),.rejected(.disabled))
        XCTAssertTrue(e.handle(.chase(.preview)).accepted)
    }
    func testSchedulerStartsRealChaseWithoutAdditionalTimerOrPopulation() {
        let e=fixture();e.ambientEnabled=true
        advance(e,900);e.ambientEnabled=false;advance(e,24)
        XCTAssertTrue(e.events.contains{$0.kind == .chase && $0.source == .automatic && $0.type == .completed})
        XCTAssertEqual(e.birds.count,2)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
    }
    func testDisabledChildAndQuietDoNotAccumulateAutomaticChases() {
        for quiet in [false,true] {
            let e=fixture();var settings=e.settings
            if quiet {settings.activityRhythm = .quiet} else {settings.chaseEnabled=false}
            e.applySettings(settings);e.ambientEnabled=true;advance(e,300)
            XCTAssertFalse(e.events.contains{$0.kind == .chase && $0.type == .started})
            settings.activityRhythm = .steady;settings.chaseEnabled=true;e.applySettings(settings)
            advance(e,1)
            XCTAssertFalse(e.events.contains{$0.kind == .chase && $0.type == .started})
        }
    }
    func testAutomaticChaseSequenceMatchesAcrossCallbackRates() {
        let reports=[30,60,120].map {hz -> BehaviorReplayReport in
            let e=fixture();e.ambientEnabled=true;advance(e,300,hz:hz)
            e.ambientEnabled=false;advance(e,24,hz:hz)
            return BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
        }
        XCTAssertEqual(reports[0],reports[1]);XCTAssertEqual(reports[1],reports[2])
    }
    func testPublicRejectedChaseCommandIsRecordedAndReplays() throws {
        let e=BehaviorEngine(seed:1,recordInputs:true)
        XCTAssertEqual(e.handle(.chase(.preview)),.rejected(.noCompanion))
        let log=try e.recordedInputs()
        XCTAssertEqual(log.expected?.events.count,1)
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
    }
}
