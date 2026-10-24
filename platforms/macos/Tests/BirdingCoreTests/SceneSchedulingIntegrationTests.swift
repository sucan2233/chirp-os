import XCTest
@testable import BirdingCore

final class SceneSchedulingIntegrationTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:2000,height:1400)
    private let point=CGPoint(x:1200,y:700)
    private func fixture(seed:UInt64=931,frequency:AmbientFrequency = .high)->BehaviorEngine {
        var settings=BirdSettings();settings.ambientFrequency=frequency
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        settings.perchActions=false;settings.passiveAttentionEnabled=false;settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=true;e.autonomousRouting=false
        e.updateWorld(.init(screens:[display],displays:[display],pointer:CGPoint(x:20,y:20)))
        return e
    }
    private func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }

    func testBathPlacementOnlyShortensTheExistingClockAndPauseQuietAndDisabledAmbientCannotLaunch() throws {
        let e=fixture();advance(e,2)
        XCTAssertEqual(e.scheduler.remaining,43,accuracy:1e-8)
        XCTAssertTrue(e.handle(.placeBath(at:point)).accepted)
        XCTAssertEqual(e.scheduler.remaining,10);XCTAssertNotNil(e.sceneFocus)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertFalse(e.events.contains{$0.type == .started})
        advance(e,5);let remaining=e.scheduler.remaining
        e.handle(.pause(true));let lifetime=e.habitatSnapshot().first?.remainingLifetime
        advance(e,120);e.updateWorld(e.world)
        XCTAssertEqual(e.scheduler.remaining,remaining)
        XCTAssertEqual(e.habitatSnapshot().first?.remainingLifetime,lifetime)
        e.handle(.pause(false))
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings)
        let quietRemaining=e.scheduler.remaining
        advance(e,30);XCTAssertEqual(e.scheduler.remaining,quietRemaining)
        XCTAssertFalse(e.events.contains{$0.type == .started})
        settings.activityRhythm = .steady;e.applySettings(settings);e.ambientEnabled=false
        let disabledRemaining=e.scheduler.remaining
        advance(e,30);XCTAssertEqual(e.scheduler.remaining,disabledRemaining)
        XCTAssertFalse(e.events.contains{$0.kind == .bathVisit && $0.type == .started})
    }

    func testClickAndDragQuietPeriodTakePrecedenceOverPlacementTenSecondOpportunity() {
        for drag in [false,true] {
            let e=fixture();advance(e,2)
            if drag {
                var world=e.world;world.buttonsDown=true;e.updateWorld(world);advance(e,1)
                world.buttonsDown=false;e.updateWorld(world)
            } else {e.handle(.pointerClick)}
            XCTAssertTrue(e.handle(.placeBath(at:point)).accepted)
            XCTAssertGreaterThanOrEqual(e.scheduler.remaining,59.9)
            let events=e.events.count
            advance(e,59)
            XCTAssertEqual(e.events.count,events,"Neither scene nor daily opportunities may bypass user-input silence")
            XCTAssertFalse(e.scheduler.canAttemptScene(e.sceneFocus!))
            XCTAssertEqual(e.activeRunCount,0)
        }
    }

    func testClearSleepDisplayLossAndExpiryEndFocusAndResetOneDailyClockWithoutCatchup() {
        for cause in ["clear","sleep","display","expire"] {
            let e=fixture();XCTAssertTrue(e.handle(.placeBath(at:point)).accepted)
            advance(e,3)
            switch cause {
            case "clear":e.handle(.clearCurrentScene)
            case "sleep":e.handle(.cancelAmbient(.sleep))
            case "display":var world=e.world;world.displays=[];world.screens=[];e.updateWorld(world)
            default:e.habitatObjects.advance(301);e.updateWorld(e.world)
            }
            XCTAssertNil(e.sceneFocus);XCTAssertTrue(e.habitatSnapshot().isEmpty)
            XCTAssertGreaterThanOrEqual(e.scheduler.remaining,45)
            let before=e.events.count
            advance(e,1)
            XCTAssertEqual(e.events.count,before);XCTAssertEqual(e.activeRunCount,0)
        }
    }

    func testSceneDecisionsUseIndependentRandomStreamAndMatchFixedStepEngineAtEveryRenderRate() {
        struct Trace:Equatable {
            let events:[RecordedEvent],object:[RecordedHabitatObjectState],remaining:Double,focus:SceneFocus?
        }
        func simulate(_ hz:Int,perturb:Bool)->[Trace] {
            let e=fixture();XCTAssertTrue(e.handle(.placeBath(at:point)).accepted)
            var result:[Trace]=[]
            for second in 0..<120 {
                if perturb {for _ in 0..<17 {_=e.random.unit();_=e.ecologyRandom.unit()}}
                if second==25 {e.handle(.pause(true))}
                if second==28 {e.handle(.pause(false))}
                advance(e,1,hz:hz)
                result.append(Trace(events:e.events.map(RecordedEvent.init),
                    object:e.habitatSnapshot().map(RecordedHabitatObjectState.init),remaining:e.scheduler.remaining,focus:e.sceneFocus))
            }
            XCTAssertNotNil(e.sceneFocus);XCTAssertEqual(e.activeRunCount,0)
            XCTAssertEqual(e.residentCount,0);XCTAssertEqual(e.arrivalCount,0)
            return result
        }
        let reference=simulate(60,perturb:false)
        XCTAssertEqual(simulate(30,perturb:false),reference)
        XCTAssertEqual(simulate(120,perturb:false),reference)
        XCTAssertEqual(simulate(60,perturb:true),reference)
    }
}
