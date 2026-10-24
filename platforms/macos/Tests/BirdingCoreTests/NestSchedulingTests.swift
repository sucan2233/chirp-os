import XCTest
@testable import BirdingCore

final class NestSchedulingTests:XCTestCase {
    private typealias F=NestTestSupport
    private func opportunity(_ scheduler:inout AmbientScheduler,busy:Bool=false)->AmbientEvent? {
        for _ in 0..<Int(ceil(scheduler.remaining*60))+2 {
            let before=scheduler.remaining
            let event=scheduler.tick(BehaviorEngine.step,pointer:.zero,buttonsDown:false,pointerEnabled:false,
                flockEnabled:true,socialEnabled:true,insectEnabled:true,giftEnabled:true,courtshipEnabled:true,
                frequency:.high,busy:busy,random:{0})
            if scheduler.remaining>before {return event}
            XCTAssertNil(event)
        }
        XCTFail("The sole scene opportunity did not expire");return nil
    }

    func testNestUsesTheSameSeventyPercentOpportunityAndCannotTransferClosedOrBusyChances() {
        let focus=SceneFocus(nestID:HabitatObjectID(7));var visits=0,legacy=0
        XCTAssertEqual(focus.nestID,HabitatObjectID(7));XCTAssertEqual(focus.objectID,HabitatObjectID(7))
        XCTAssertNotEqual(focus,SceneFocus(objectID:HabitatObjectID(7)))
        XCTAssertNotEqual(focus,SceneFocus(leafID:ScenePropID(7)))
        for seed:UInt64 in 0..<256 {
            var scheduler=AmbientScheduler(seed:seed);scheduler.reset(.high)
            XCTAssertTrue(scheduler.acquireFocus(focus,frequency:.high));XCTAssertEqual(scheduler.remaining,10)
            let event=opportunity(&scheduler)
            if event == .nestVisit(HabitatObjectID(7)) {visits+=1} else {XCTAssertEqual(event,.flockPass);legacy+=1}
            XCTAssertTrue((15.0...25.0).contains(scheduler.remaining))
            var busy=AmbientScheduler(seed:seed);busy.reset(.high);_=busy.acquireFocus(focus,frequency:.high)
            XCTAssertNil(opportunity(&busy,busy:true));XCTAssertGreaterThanOrEqual(busy.remaining,15)
            var cooling=AmbientScheduler(seed:seed);cooling.reset(.high);_=cooling.acquireFocus(focus,frequency:.high)
            cooling.didFinishNest();XCTAssertEqual(cooling.nestCooldownRemaining,15)
            if event == .nestVisit(HabitatObjectID(7)) {XCTAssertNil(opportunity(&cooling))}
            else {_=opportunity(&cooling)}
        }
        XCTAssertEqual(visits+legacy,256);XCTAssertEqual(Double(visits)/256,0.7,accuracy:0.07)
    }

    func testRealAutomaticVisitsPreferDeliveredMaterialAndOnlyStartOneRunPerOpportunity() throws {
        for seed:UInt64 in 0..<8 {
            let e=try F.prepared(seed:seed);_=try F.deliver(e)
            let previous=e.events.filter{$0.type == .started}.count
            XCTAssertEqual(try F.nest(e).available,2);XCTAssertEqual(try F.nest(e).delivered,1)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            e.ambientEnabled=true
            for _ in 0..<120*60 {
                if e.events.filter({$0.type == .started}).count>previous {break}
                e.advance(BehaviorEngine.step)
            }
            let starts=e.events.filter{$0.type == .started}.dropFirst(previous)
            XCTAssertEqual(starts.count,1);XCTAssertEqual(starts.first?.kind,.nestBuild);XCTAssertEqual(starts.first?.source,.automatic)
            let run=try XCTUnwrap(starts.first?.runID)
            XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
            e.ambientEnabled=false;F.finish(e,run);F.released(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed]);XCTAssertEqual(try F.nest(e).progress,1)
            XCTAssertEqual(try F.nest(e).available,2);XCTAssertEqual(observations.map(\.kind),[.nestBuild])
            XCTAssertEqual(observations.map(\.source),[.automatic])
        }
        let e=try F.prepared(seed:3);e.ambientEnabled=true
        for _ in 0..<120*60 {if e.activeRunCount>0 {break};e.advance(BehaviorEngine.step)}
        let run=try XCTUnwrap(e.runtime.runs.values.first{$0.execution.kind == .nestMaterialCarry}?.id)
        e.ambientEnabled=false;F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed]);XCTAssertEqual(try F.nest(e).delivered,1)
        XCTAssertEqual(try F.nest(e).progress,0)
    }

    func testSharedTwentySecondBirdAndFifteenSecondGlobalCooldownFreezeWithoutCatchup() throws {
        let e=try F.prepared(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
        let carried=try F.start(e);F.finish(e,carried);F.released(e,carried)
        let rhythm=try XCTUnwrap(e.perchPlanner.ecology(id))
        let carry=try XCTUnwrap(rhythm.cooldowns[.nestMaterialCarry]),build=try XCTUnwrap(rhythm.cooldowns[.nestBuild])
        XCTAssertEqual(carry,build);XCTAssertEqual(carry,20,accuracy:BehaviorEngine.step*1.1)
        XCTAssertEqual(e.scheduler.nestCooldownRemaining,15,accuracy:BehaviorEngine.step*1.1)
        XCTAssertEqual(e.perchPlanner.automaticWeight(id,kind:.nestMaterialCarry),0)
        XCTAssertEqual(e.perchPlanner.automaticWeight(id,kind:.nestBuild),0)
        e.handle(.pause(true));let nest=try F.nest(e),wait=e.scheduler.remaining,global=e.scheduler.nestCooldownRemaining
        F.advance(e,60)
        XCTAssertEqual(try F.nest(e),nest);XCTAssertEqual(e.scheduler.nestCooldownRemaining,global)
        XCTAssertEqual(rhythm.cooldowns[.nestMaterialCarry],carry);XCTAssertEqual(rhythm.cooldowns[.nestBuild],build)
        XCTAssertEqual(e.scheduler.remaining,wait);e.handle(.pause(false))
        F.advance(e,14.9);XCTAssertFalse(e.scheduler.canAttemptNest)
        F.advance(e,0.2);XCTAssertTrue(e.scheduler.canAttemptNest)
        XCTAssertEqual(e.perchPlanner.automaticWeight(id,kind:.nestMaterialCarry),0)
        XCTAssertEqual(e.perchPlanner.automaticWeight(id,kind:.nestBuild),0)
        F.advance(e,5.1)
        XCTAssertGreaterThan(e.perchPlanner.automaticWeight(id,kind:.nestMaterialCarry),0)
        XCTAssertGreaterThan(e.perchPlanner.automaticWeight(id,kind:.nestBuild),0)
        XCTAssertEqual(e.activeRunCount,0,"An elapsed cooldown must not queue a visit while automatic scenes are off")
        let run=try F.start(e,build:true);F.finish(e,run);F.released(e,run)
        XCTAssertEqual(rhythm.cooldowns[.nestMaterialCarry],rhythm.cooldowns[.nestBuild])
        XCTAssertEqual(try XCTUnwrap(rhythm.cooldowns[.nestBuild]),20,accuracy:BehaviorEngine.step*1.1)
    }

    func testQuietAndIneligibleSceneOpportunitiesAreSilentAndUserInputStillSuppressesForSixtySeconds() throws {
        for mode in ["quiet","noSpecies","frames"] {
            let e=F.engine(residents:mode=="noSpecies" ? 0:1,species:mode=="noSpecies" ? nil:.spottedDove)
            XCTAssertEqual(e.handle(.placeNest(at:F.point(e))),.accepted)
            if mode=="quiet" {var s=e.settings;s.activityRhythm = .quiet;e.applySettings(s)}
            if mode=="frames" {var w=e.world;w.availableFrames[.spottedDove]?.remove("carryGrip");e.updateWorld(w)}
            e.ambientEnabled=true;let count=e.events.count
            F.advance(e,80)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.events.count,count)
            XCTAssertEqual(try F.nest(e).available,3);XCTAssertEqual(e.arrivalCount,0)
        }
        let e=try F.prepared();e.ambientEnabled=true;e.handle(.pointerClick)
        let events=e.events.count;F.advance(e,59)
        XCTAssertEqual(e.events.count,events);XCTAssertEqual(e.activeRunCount,0)
        XCTAssertGreaterThan(e.scheduler.userInputRemaining,0)
        XCTAssertEqual(try F.nest(e).available,3)
    }

    func testMaterialChoiceHasAnIndependentStreamAndFullReportsMatchAcrossCallbackRates() throws {
        var independent:[BehaviorReplayReport]?
        for draws in [0,29] {
            var reference:[BehaviorReplayReport]?
            for hz in [30,60,120] {
                let e=try F.prepared(seed:3701)
                for _ in 0..<draws {_=e.random.unit();_=e.ecologyRandom.unit()}
                var reports:[BehaviorReplayReport]=[]
                for build in [false,true] {
                    let run=try F.start(e,build:build)
                    for sample in 0..<350 {
                        if sample==2 {e.handle(.pause(true))};if sample==5 {e.handle(.pause(false))}
                        F.advance(e,0.1,hz:hz)
                        reports.append(BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init)))
                        if e.runtime.runs[run]==nil {break}
                    }
                    F.released(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
                    F.advance(e,1.1,hz:hz)
                }
                XCTAssertEqual(try F.nest(e).progress,1)
                if let reference {XCTAssertEqual(reports,reference)} else {reference=reports}
            }
            let reports=try XCTUnwrap(reference)
            // Ambient is off and focus was acquired before the unrelated draws;
            // no daily next-wait is sampled here. Compare every field, including
            // trajectory, material IDs, commits, clocks, events and final pose.
            if let independent {XCTAssertEqual(reports,independent)} else {independent=reports}
        }
    }
}
