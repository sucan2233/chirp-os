import XCTest
@testable import BirdingCore

final class SceneSchedulingTests:XCTestCase {
    private func tick(_ scheduler:inout AmbientScheduler,frequency:AmbientFrequency = .high,
                      hz:Int=60,busy:Bool=false,buttons:Bool=false,legacy:Double=0,insect:Bool=false)->AmbientEvent? {
        scheduler.tick(1/Double(hz),pointer:.zero,buttonsDown:buttons,pointerEnabled:false,
            flockEnabled:true,insectEnabled:insect,frequency:frequency,busy:busy,random:{legacy})
    }
    private func nextOpportunity(_ scheduler:inout AmbientScheduler,frequency:AmbientFrequency = .high,
                                 hz:Int=60,busy:Bool=false,legacy:Double=0,insect:Bool=false)->AmbientEvent? {
        let count=Int(ceil(scheduler.remaining*Double(hz)))+2
        for _ in 0..<count {
            let before=scheduler.remaining
            let event=tick(&scheduler,frequency:frequency,hz:hz,busy:busy,legacy:legacy,insect:insect)
            if scheduler.remaining>before {return event}
            XCTAssertNil(event)
        }
        XCTFail("The finite opportunity clock did not expire");return nil
    }

    func testOneClockAcquiresOnlyOneFocusAndUsesExactFrequencyWindows() {
        for (frequency,daily,scene):(AmbientFrequency,ClosedRange<Double>,ClosedRange<Double>) in [
            (.low,180...360,30...45),(.medium,90...180,20...35),(.high,45...90,15...25)] {
            XCTAssertEqual(frequency.interval,daily);XCTAssertEqual(frequency.sceneInterval,scene)
            var scheduler=AmbientScheduler(seed:14);scheduler.reset(frequency)
            let first=SceneFocus(objectID:HabitatObjectID(1)),second=SceneFocus(objectID:HabitatObjectID(2))
            XCTAssertTrue(scheduler.acquireFocus(first,frequency:frequency))
            XCTAssertEqual(scheduler.remaining,10);XCTAssertEqual(scheduler.sceneFocus,first)
            XCTAssertFalse(scheduler.acquireFocus(second,frequency:frequency))
            XCTAssertEqual(scheduler.remaining,10);XCTAssertEqual(scheduler.sceneFocus,first)
            for _ in 0..<6 {
                _=nextOpportunity(&scheduler,frequency:frequency)
                XCTAssertTrue(scene.contains(scheduler.remaining))
                scheduler.suppress()
                XCTAssertLessThanOrEqual(scheduler.remaining,scene.upperBound)
            }
            scheduler.endFocus(frequency:frequency)
            XCTAssertNil(scheduler.sceneFocus);XCTAssertEqual(scheduler.remaining,daily.lowerBound)
            XCTAssertNil(tick(&scheduler,frequency:frequency))
        }
        var soon=AmbientScheduler();soon.reset(.high)
        for _ in 0..<42*60 {_=tick(&soon)}
        let remaining=soon.remaining
        XCTAssertTrue(soon.acquireFocus(.init(objectID:HabitatObjectID(9)),frequency:.high))
        XCTAssertEqual(soon.remaining,remaining,"Placement cannot postpone an already closer opportunity")
    }

    func testSceneSeventyPercentAndDailyInsectEightPercentKeepTheOtherFivePercentEmpty() {
        var sceneHits=0,dailyEmpty=0,dailyInsect=0,dailyLegacy=0
        let count=512,id=HabitatObjectID(7)
        for seed in 0..<count {
            var scene=AmbientScheduler(seed:UInt64(seed));scene.reset(.high)
            XCTAssertTrue(scene.acquireFocus(.init(objectID:id),frequency:.high))
            let event=nextOpportunity(&scene)
            if event == .bathVisit(id) {sceneHits+=1}
            else {XCTAssertEqual(event,.flockPass,"The other 30% uses exactly the existing selector")}
            var daily=AmbientScheduler(seed:UInt64(seed));daily.reset(.high)
            let ordinary=nextOpportunity(&daily,insect:true)
            if ordinary == nil {dailyEmpty+=1}
            else if ordinary == .insectCatch {dailyInsect+=1}
            else {XCTAssertEqual(ordinary,.flockPass);dailyLegacy+=1}
            XCTAssertEqual(daily.remaining,45,accuracy:1e-7)
        }
        XCTAssertEqual(Double(sceneHits)/Double(count),0.70,accuracy:0.06)
        // An ineligible insect opportunity is silently spent by the engine;
        // it must not be transferred to the old selector.
        XCTAssertEqual(Double(dailyInsect)/Double(count),0.08,accuracy:0.04)
        XCTAssertEqual(Double(dailyEmpty)/Double(count),0.05,accuracy:0.03)
        XCTAssertEqual(Double(dailyLegacy)/Double(count),0.87,accuracy:0.04)
        XCTAssertEqual(dailyEmpty+dailyInsect+dailyLegacy,count)
    }

    func testBusyAndCoolingSceneOpportunitiesAreDiscardedWithoutImmediateRetry() {
        for busy in [false,true] {
            var scheduler=AmbientScheduler(seed:88);scheduler.reset(.high)
            let id=HabitatObjectID(3)
            XCTAssertTrue(scheduler.acquireFocus(.init(objectID:id),frequency:.high))
            if !busy {scheduler.didFinishScene();XCTAssertFalse(scheduler.canAttemptScene(id))}
            let event=nextOpportunity(&scheduler,busy:busy)
            if busy {XCTAssertNil(event)}
            else {XCTAssertNotEqual(event,.bathVisit(id))}
            XCTAssertGreaterThanOrEqual(scheduler.remaining,15)
            for _ in 0..<14*60 {XCTAssertNil(tick(&scheduler))}
            XCTAssertGreaterThan(scheduler.remaining,0)
        }
    }

    func testUserInputSixtySecondsSurvivesPlacementAndOrdinarySuppressionUsesSceneFloor() {
        for frequency:AmbientFrequency in [.low,.medium,.high] {
            var scheduler=AmbientScheduler(seed:17);scheduler.reset(frequency)
            scheduler.suppress(reason:.userInput)
            XCTAssertTrue(scheduler.acquireFocus(.init(objectID:HabitatObjectID(1)),frequency:frequency))
            XCTAssertEqual(scheduler.remaining,60);XCTAssertEqual(scheduler.userInputRemaining,60)
            for _ in 0..<59*60 {XCTAssertNil(tick(&scheduler,frequency:frequency))}
            XCTAssertFalse(scheduler.canAttemptScene(HabitatObjectID(1)))
            scheduler.suppress()
            XCTAssertEqual(scheduler.remaining,frequency.sceneInterval.lowerBound)
            scheduler.suppress(reason:.userInput)
            XCTAssertEqual(scheduler.remaining,60);XCTAssertEqual(scheduler.userInputRemaining,60)
            for _ in 0..<120 {XCTAssertNil(tick(&scheduler,frequency:frequency,buttons:true))}
            XCTAssertGreaterThan(scheduler.userInputRemaining,59.9)
            scheduler.endFocus(frequency:frequency)
            XCTAssertGreaterThanOrEqual(scheduler.remaining,60)
        }
    }

    func testLegacyRandomConsumptionCannotChangeFocusSelectionOrItsSingleClock() {
        struct Trace:Equatable {let time:Int,event:AmbientEvent?,remaining:Double}
        func sample(_ legacy:Double)->[Trace] {
            var scheduler=AmbientScheduler(seed:731);scheduler.reset(.high)
            _=scheduler.acquireFocus(.init(objectID:HabitatObjectID(1)),frequency:.high)
            var trace:[Trace]=[]
            for second in 0..<180 {
                var event:AmbientEvent?
                for _ in 0..<60 {if let next=tick(&scheduler,legacy:legacy) {event=next}}
                trace.append(.init(time:second,event:event,remaining:(scheduler.remaining*1e7).rounded()/1e7))
            }
            return trace
        }
        let reference=sample(0)
        XCTAssertEqual(sample(0.999),reference,"A single legacy choice must not consume the scene stream")
        XCTAssertEqual(SceneRandomSalt.scheduler,0x5343454E45464F43)
        XCTAssertEqual(SceneRandomSalt.bath,0x4241544856495349)
        XCTAssertNotEqual(SceneRandomSalt.scheduler,SceneRandomSalt.bath)
    }

    func testTypedLeafFocusSharesTheBathClockAndAnOldTerminalCannotClearItsReplacement() {
        let leaf=SceneFocus(leafID:ScenePropID(7)),bath=SceneFocus(objectID:HabitatObjectID(7))
        XCTAssertEqual(leaf.leafID,ScenePropID(7));XCTAssertNil(leaf.objectID)
        XCTAssertEqual(bath.objectID,HabitatObjectID(7));XCTAssertNil(bath.leafID)
        XCTAssertNotEqual(leaf,bath,"Numeric IDs from different stores do not identify the same scene")
        var hits=0
        for seed in 0..<512 {
            var scheduler=AmbientScheduler(seed:UInt64(seed));scheduler.reset(.high)
            XCTAssertTrue(scheduler.acquireFocus(leaf,frequency:.high))
            XCTAssertEqual(scheduler.remaining,10)
            XCTAssertFalse(scheduler.acquireFocus(bath,frequency:.high))
            XCTAssertFalse(scheduler.canAttemptScene(bath));XCTAssertTrue(scheduler.canAttemptScene(leaf))
            let event=nextOpportunity(&scheduler)
            if event == .leafCarry(ScenePropID(7)) {hits+=1} else {XCTAssertEqual(event,.flockPass)}
            XCTAssertTrue((15.0...25.0).contains(scheduler.remaining))
            XCTAssertFalse(scheduler.endFocus(matching:bath,frequency:.high))
            XCTAssertEqual(scheduler.sceneFocus,leaf)
            XCTAssertTrue(scheduler.endFocus(matching:leaf,frequency:.high))
            XCTAssertNil(scheduler.sceneFocus);XCTAssertEqual(scheduler.remaining,45)
            XCTAssertTrue(scheduler.acquireFocus(bath,frequency:.high))
            XCTAssertFalse(scheduler.endFocus(matching:leaf,frequency:.high))
            XCTAssertEqual(scheduler.sceneFocus,bath)
        }
        XCTAssertEqual(Double(hits)/512,0.7,accuracy:0.06)
        XCTAssertEqual(SceneRandomSalt.leafCarry,0x4C45414643415252)
        XCTAssertNotEqual(SceneRandomSalt.leafCarry,SceneRandomSalt.scheduler)
        XCTAssertNotEqual(SceneRandomSalt.leafCarry,SceneRandomSalt.bath)
    }
}
