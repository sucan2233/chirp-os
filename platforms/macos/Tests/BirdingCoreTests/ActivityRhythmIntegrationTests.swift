import XCTest
@testable import BirdingCore

final class ActivityRhythmIntegrationTests:XCTestCase {
    let screen=CGRect(x:0,y:0,width:1600,height:1200)
    let host=Surface(id:61,pid:42,rect:CGRect(x:100,y:900,width:1400,height:250))
    func fixture(_ mode:ActivityRhythmMode,minute:Int?=nil,record:Bool=false) -> BehaviorEngine {
        var settings=BirdSettings();settings.activityRhythm=mode;settings.ambientFrequency = .high
        let e=BehaviorEngine(seed:81,settings:settings,recordInputs:record)
        e.populationEnabled=false;e.autonomousRouting=false
        let frames=Set(["stand","blink","preen0","preen1","idle0","idle1","idle2","land0","land1","land2"]+(0...7).map{"fly\($0)"})
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:30,y:30),
            availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)}),localMinuteOfDay:minute))
        return e
    }
    func advance(_ e:BehaviorEngine,_ seconds:Double) {for _ in 0..<Int(seconds*60) {e.advance(BehaviorEngine.step)}}
    func perch(_ e:BehaviorEngine) -> Bird {
        let bird=Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host);bird.perchDuration=3600;bird.tick(1);e.installFixtureBirds([bird]);return bird
    }
    func testQuietRejectsOnlyNewAutomaticEncountersAndAllowsPreviewAndClick() throws {
        let e=fixture(.quiet),bird=perch(e)
        let commands:[EngineCommand]=[.pointerVisit(.automatic),.flockPass(.automatic),.socialGreeting(.automatic),
            .socialMotion(.sideBySide,.automatic),.socialMotion(.giveWay,.automatic),.socialMotion(.pairedTakeoff,.automatic),
            .leafPlay(at:CGPoint(x:500,y:500),source:.automatic),.fixedPerchVisit(.automatic),.foodTrayVisit(.automatic),.bathVisit(.automatic),.leafCarry(.automatic),.insectCatch(species:.barnSwallow,source:.automatic)]
        for command in commands {XCTAssertEqual(e.handle(command),.rejected(.disabled))}
        for definition in BehaviorDefinitions.all where !definition.occupiesEncounter && definition.kind != .fixedPerchVisit && definition.kind != .foodTrayVisit {
            XCTAssertTrue(definition.isEnabled(settings:e.settings,source:.automatic),definition.kind.rawValue)
        }
        XCTAssertTrue(e.handle(.flockPass(.preview)).accepted)
        advance(e,30)
        XCTAssertTrue(e.events.contains{$0.kind == .flockPass && $0.type == .completed && $0.source == .preview})
        XCTAssertTrue(e.handle(.relocate(try XCTUnwrap(e.id(of:bird)))).accepted)
        XCTAssertEqual(e.behavior(of:bird),.relocate)
    }
    func testQuietHasNoAutomaticEncountersAndResumesWithoutAccumulatedOpportunities() {
        let e=fixture(.quiet);_=perch(e)
        advance(e,120)
        XCTAssertFalse(e.events.contains{$0.type == .started && $0.kind.map{BehaviorDefinitions.definition(for:$0).occupiesEncounter} == true})
        XCTAssertTrue(e.events.contains{$0.type == .completed && $0.kind == .rest})
        XCTAssertEqual(e.scheduler.remaining,45)
        var settings=e.settings;settings.activityRhythm = .steady;e.applySettings(settings)
        XCTAssertEqual(e.scheduler.remaining,45)
        advance(e,1)
        XCTAssertGreaterThan(e.scheduler.remaining,43.9)
        XCTAssertFalse(e.ambientBusy)
    }
    func testClockChangesDoNotAdvanceSimulationOrProduceCatchupAndPauseFreezesCadence() {
        let e=fixture(.localDayNight,minute:720)
        advance(e,10)
        XCTAssertEqual(e.scheduler.remaining,35,accuracy:1e-8)
        var world=e.world;world.localMinuteOfDay=0;e.updateWorld(world)
        XCTAssertEqual(e.scheduler.remaining,35,accuracy:1e-8)
        advance(e,10)
        XCTAssertEqual(e.scheduler.remaining,31.5,accuracy:1e-8)
        e.handle(.pause(true));let before=e.scheduler.remaining
        world.localMinuteOfDay=720;e.updateWorld(world);advance(e,300)
        XCTAssertEqual(e.scheduler.remaining,before)
        e.handle(.pause(false));advance(e,1)
        XCTAssertEqual(e.scheduler.remaining,before-1,accuracy:1e-8)
    }
    func testChangingToQuietLetsExistingAutomaticFlightFinish() {
        let e=fixture(.steady)
        XCTAssertTrue(e.handle(.flockPass(.automatic)).accepted)
        advance(e,1)
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings)
        XCTAssertTrue(e.ambientBusy)
        advance(e,30)
        XCTAssertTrue(e.events.contains{$0.kind == .flockPass && $0.type == .completed})
        XCTAssertFalse(e.events.contains{$0.kind == .flockPass && $0.type == .cancelled})
        XCTAssertEqual(e.pendingCount,0);XCTAssertEqual(e.passingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
    }
    func testCadenceScalingDoesNotChangePointerDwellTimeOrCreateEventsAtZeroRate() {
        var scheduler=AmbientScheduler();scheduler.reset(.high)
        for _ in 0..<241 {
            XCTAssertNil(scheduler.tick(1.0/60,pointer:.zero,buttonsDown:false,pointerEnabled:true,flockEnabled:false,
                frequency:.high,busy:false,cadenceRate:0.35,random:{0.5}))
        }
        XCTAssertEqual(scheduler.stationaryTime,4,accuracy:1e-8)
        let remaining=scheduler.remaining
        for _ in 0..<1000 {
            XCTAssertNil(scheduler.tick(0.1,pointer:.zero,buttonsDown:false,pointerEnabled:true,flockEnabled:true,
                frequency:.high,busy:false,cadenceRate:0,random:{0.5}))
        }
        XCTAssertEqual(scheduler.remaining,remaining)
    }
    func testLocalTimeAndModeChangesReplayAtAllRates() throws {
        let e=fixture(.localDayNight,minute:1380,record:true)
        e.bringInBird();advance(e,20)
        for minute in [0,360,420,720,1080,1200,1439] {
            var world=e.world;world.localMinuteOfDay=minute;e.updateWorld(world);advance(e,3)
        }
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings)
        XCTAssertTrue(e.handle(.flockPass(.preview)).accepted);advance(e,30)
        let log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
        XCTAssertTrue(log.inputs.contains{$0.world?.localMinuteOfDay==1439})
        XCTAssertTrue(log.expected?.events.contains{$0.kind=="flockPass" && $0.type=="completed"} ?? false)
    }
    func testMissingRecordedClockClearsRatherThanInheritingAndInvalidClockIsRejected() throws {
        let e=fixture(.localDayNight,minute:720)
        var recorded=RecordedWorld(e.world);recorded.localMinuteOfDay=nil
        XCTAssertNil(try recorded.validated(inheriting:e.world).localMinuteOfDay)
        for invalid in [-1,1440,Int.max] {
            recorded.localMinuteOfDay=invalid
            XCTAssertThrowsError(try recorded.validated(inheriting:e.world))
        }
        XCTAssertNil(BehaviorWorld(localMinuteOfDay:-1).localMinuteOfDay)
        XCTAssertNil(BehaviorWorld(localMinuteOfDay:1440).localMinuteOfDay)
    }
    func testPriorSimulationVersionsAreRejectedBeforeNestedDecode() throws {
        let e=fixture(.steady,record:true)
        let data=try BehaviorInputLog.encoder().encode(e.recordedInputs())
        for version in Array(1...13)+[15] {
            var object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
            object["simulationVersion"]=version;object["settings"]="incompatible"
            XCTAssertThrowsError(try BehaviorInputLog.decode(JSONSerialization.data(withJSONObject:object)))
        }
    }
}
