import XCTest
@testable import BirdingCore

final class CourtshipSchedulingTests:XCTestCase {
    private typealias F=CourtshipTestSupport
    private func first(_ scheduler:inout AmbientScheduler,enabled:Bool?=true,social:Bool=true,busy:Bool=false)->AmbientEvent? {
        for _ in 0..<45*60+2 {
            let before=scheduler.remaining,event:AmbientEvent?
            if let enabled {
                event=scheduler.tick(BehaviorEngine.step,pointer:.zero,buttonsDown:false,
                    pointerEnabled:true,flockEnabled:true,socialEnabled:social,insectEnabled:true,giftEnabled:true,
                    courtshipEnabled:enabled,frequency:.high,busy:busy,random:{0})
            } else {
                event=scheduler.tick(BehaviorEngine.step,pointer:.zero,buttonsDown:false,
                    pointerEnabled:true,flockEnabled:true,socialEnabled:social,insectEnabled:true,giftEnabled:true,
                    frequency:.high,busy:busy,random:{0})
            }
            if scheduler.remaining>before {return event}
            XCTAssertNil(event)
        }
        XCTFail("The first finite daily opportunity must expire");return nil
    }
    private func seed()throws->UInt64 {
        // Find an observable production opportunity; do not reproduce its RNG.
        for seed:UInt64 in 0..<512 {
            var s=AmbientScheduler(seed:seed);s.reset(.high)
            if first(&s) == .courtshipDisplay {return seed}
        }
        XCTFail("The finite seed range must include courtship")
        throw NSError(domain:"CourtshipSchedulingTests",code:1)
    }

    func testFourPercentDailyIntervalDefaultsClosedAndCannotTransferToAnotherAction() throws {
        var count=0
        for seed:UInt64 in 0..<512 {
            var s=AmbientScheduler(seed:seed);s.reset(.high)
            if first(&s) == .courtshipDisplay {count+=1}
        }
        XCTAssertEqual(Double(count)/512,0.04,accuracy:0.025)
        let chosen=try seed()
        for enabled:Bool? in [nil,false,true] {
            var s=AmbientScheduler(seed:chosen);s.reset(.high)
            XCTAssertEqual(first(&s,enabled:enabled),enabled==true ? .courtshipDisplay:nil)
            XCTAssertEqual(s.remaining,45,accuracy:1e-8)
        }
        var master=AmbientScheduler(seed:chosen);master.reset(.high)
        XCTAssertNil(first(&master,social:false))
        var busy=AmbientScheduler(seed:chosen);busy.reset(.high)
        XCTAssertNil(first(&busy,busy:true))
        for _ in 0..<60 {
            XCTAssertNil(busy.tick(BehaviorEngine.step,pointer:.zero,buttonsDown:false,
                pointerEnabled:true,flockEnabled:true,socialEnabled:true,courtshipEnabled:true,
                frequency:.high,busy:false,random:{0}))
        }
    }

    func testActualAutomaticOpportunityStartsOnePairAndCompletesWithOneNaturalObservation() throws {
        let e=F.engine(seed:try seed()),ids=e.birds.compactMap{e.id(of:$0)}
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        e.scheduler.reset(.high);e.ambientEnabled=true
        F.advance(e,45.1)
        let starts=e.events.filter{$0.kind == .courtshipDisplay && $0.type == .started}
        XCTAssertEqual(starts.count,1);XCTAssertEqual(starts.first?.source,.automatic)
        XCTAssertEqual(Set(try XCTUnwrap(starts.first).participants),Set(ids))
        XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,2)
        XCTAssertEqual(e.events.filter{$0.type == .started}.count,1,"The daily draw starts at most one behavior")
        e.ambientEnabled=false;F.advance(e,4.1)
        let run=try XCTUnwrap(starts.first?.runID);F.clean(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        XCTAssertEqual(observations.map(\.kind),[.courtshipDisplay]);XCTAssertEqual(observations.map(\.source),[.automatic])
        XCTAssertEqual(e.birds.compactMap{e.id(of:$0)},ids);XCTAssertEqual(e.arrivalCount,0)
    }

    func testIneligibleAutomaticIntervalIsSilentlySpentWithoutFallbackNewBirdOrImmediateRetry() throws {
        for cause in ["single","frames","disabled","probability","quiet"] {
            let e=F.engine(seed:try seed())
            switch cause {
            case "single":e.handle(.remove(try XCTUnwrap(e.id(of:e.birds[1]))))
            case "frames":var w=e.world;w.availableFrames[F.species]?.remove("courtBow1");e.updateWorld(w)
            case "disabled":var s=e.settings;s.courtshipEnabled=false;e.applySettings(s)
            case "probability":
                var s=e.settings;let index=try XCTUnwrap(s.probabilities.entries.firstIndex{$0.id==F.species})
                s.probabilities.setManualWeight(at:index,to:0);e.applySettings(s)
            default:break
            }
            let identities=e.birds.map(ObjectIdentifier.init),events=e.events.count
            e.scheduler.reset(.high);e.ambientEnabled=true
            if cause=="quiet" {
                F.advance(e,44.9)
                // A real disturbance resets the residents' quiet clocks just
                // before the existing opportunity, without adding another timer.
                for id in e.birds.compactMap({e.id(of:$0)}) {e.perchPlanner.noteClick(id)}
                F.advance(e,0.2)
            } else {F.advance(e,45.1)}
            XCTAssertEqual(e.events.count,events,cause)
            XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities);XCTAssertEqual(e.activeRunCount,0)
            XCTAssertNil(e.sceneFocus);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.pendingCount,0)
            if cause=="disabled" {var s=e.settings;s.courtshipEnabled=true;e.applySettings(s)}
            F.advance(e,0.5)
            XCTAssertFalse(e.events.contains{$0.kind == .courtshipDisplay && $0.type == .started})
        }
    }

    func testSixHundredSecondParticipantAndThreeHundredSecondGlobalCooldownsFreezeWithoutCatchup() throws {
        let e=F.engine(),run=try F.start(e);F.advance(e,4);F.clean(e,run)
        let ids=e.birds.compactMap{e.id(of:$0)}
        for id in ids {XCTAssertEqual(try XCTUnwrap(e.perchPlanner.ecology(id)?.cooldowns[.courtshipDisplay]),600,accuracy:BehaviorEngine.step+1e-8)}
        XCTAssertEqual(e.scheduler.courtshipCooldownRemaining,300,accuracy:BehaviorEngine.step+1e-8)
        e.handle(.pause(true));let before=BehaviorReplayReport(engine:e,events:[])
        F.advance(e,650);let after=BehaviorReplayReport(engine:e,events:[])
        XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(after.courtshipCooldownRemaining,before.courtshipCooldownRemaining)
        e.handle(.pause(false));F.advance(e,300.1)
        XCTAssertTrue(e.scheduler.canAttemptCourtship)
        for id in ids {XCTAssertEqual(e.perchPlanner.automaticWeight(id,kind:.courtshipDisplay),0)}
        e.ambientEnabled=true
        XCTAssertTrue(CourtshipDisplayPlan.candidates(in:e,source:.automatic).isEmpty)
        e.ambientEnabled=false;F.advance(e,300.1);e.ambientEnabled=true
        let next=try F.start(e,source:.automatic);e.ambientEnabled=false;F.advance(e,4.1);F.clean(e,next)
        XCTAssertEqual(F.terminals(e,next).map(\.type),[.completed])
        XCTAssertEqual(e.events.filter{$0.kind == .courtshipDisplay && $0.type == .started}.count,2)
    }

    func testPairSamplingHasAnIndependentStreamAndFullReportsMatchAcrossCallbackRates() throws {
        var independent:[BehaviorReplayReport]?
        for draws in [0,29] {
            var reference:[BehaviorReplayReport]?
            for hz in [30,60,120] {
                let e=F.engine(seed:try seed(),hz:hz)
                for _ in 0..<draws {_=e.random.unit();_=e.ecologyRandom.unit()}
                e.scheduler.reset(.high);e.ambientEnabled=true;F.advance(e,45.1,hz:hz)
                let run=try XCTUnwrap(e.runtime.runs.values.first{$0.execution.kind == .courtshipDisplay})
                e.ambientEnabled=false
                var reports:[BehaviorReplayReport]=[]
                for sample in 0..<50 {
                    if sample==2 {e.handle(.pause(true))};if sample==5 {e.handle(.pause(false))}
                    F.advance(e,0.1,hz:hz);reports.append(BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init)))
                }
                F.clean(e,run.id);XCTAssertEqual(F.terminals(e,run.id).map(\.type),[.completed])
                if let reference {XCTAssertEqual(reports,reference)} else {reference=reports}
            }
            var normalized=try XCTUnwrap(reference)
            // The existing daily next-wait uses e.random. Only that known
            // clock differs across unrelated draw counts; every other field stays strict.
            for index in normalized.indices {normalized[index].schedulerRemaining=nil}
            if let independent {XCTAssertEqual(normalized,independent)} else {independent=normalized}
        }
    }

    func testQuietModeLetsAcceptedAutomaticDisplayFinishButOnlyPreviewCanStartTheNextDisplay() throws {
        let e=F.engine();e.ambientEnabled=true
        let run=try F.start(e,source:.automatic);F.advance(e,1)
        var s=e.settings;s.activityRhythm = .quiet;e.applySettings(s)
        F.advance(e,3.1);F.clean(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        XCTAssertEqual(e.handle(.courtshipDisplay(.automatic)),.rejected(.disabled))
        F.advance(e,10.1)
        let preview=try F.start(e);F.advance(e,4.1);F.clean(e,preview)
        XCTAssertEqual(F.terminals(e,preview).map(\.type),[.completed])
    }

    func testGlobalCooldownBlocksAFreshQuietPairBeforeItsOwnParticipantCooldownExists() throws {
        let e=F.engine(),first=try F.start(e);F.advance(e,4);F.clean(e,first)
        let host=Surface(id:2795,pid:42,rect:CGRect(x:200,y:1300,width:2000,height:180))
        var world=e.world;world.surfaces.append(host);e.updateWorld(world)
        var fresh:[BirdID]=[]
        for fraction:CGFloat in [0.3,0.5] {
            let bird=Bird(position:.zero,fraction:fraction,profile:e.settings.catalog.profile(F.species),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=3600
            e.register(bird);fresh.append(try XCTUnwrap(e.id(of:bird)))
        }
        F.advance(e,10.1)
        for id in fresh {XCTAssertGreaterThan(e.perchPlanner.automaticWeight(id,kind:.courtshipDisplay),0)}
        e.ambientEnabled=true
        XCTAssertFalse(e.handle(.courtshipDisplay(.automatic)).accepted)
        XCTAssertEqual(e.activeRunCount,0);e.ambientEnabled=false
        F.advance(e,290);e.ambientEnabled=true
        let next=try F.start(e,source:.automatic)
        XCTAssertEqual(Set(try XCTUnwrap(e.runtime.runs[next]).execution.participants),Set(fresh))
        e.ambientEnabled=false;F.advance(e,4.1);F.clean(e,next)
        XCTAssertEqual(F.terminals(e,next).map(\.type),[.completed])
    }
}
