import XCTest
@testable import BirdingCore

final class VisitorGiftSchedulingTests:XCTestCase {
    /// Search observable opportunities, without duplicating the scheduler RNG.
    static func giftOpportunitySeed() throws -> UInt64 {
        for seed:UInt64 in 0..<512 {
            var scheduler=AmbientScheduler(seed:seed);scheduler.reset(.high)
            for _ in 0..<45*60+2 {
                let before=scheduler.remaining
                let event=scheduler.tick(BehaviorEngine.step,pointer:.zero,buttonsDown:false,
                    pointerEnabled:true,flockEnabled:true,socialEnabled:true,leafEnabled:true,
                    insectEnabled:true,giftEnabled:true,frequency:.high,busy:false,random:{0})
                if scheduler.remaining>before {
                    if event == .visitorGift {return seed}
                    break
                }
            }
        }
        XCTFail("The finite seed range must contain an actual daily gift opportunity")
        throw NSError(domain:"VisitorGiftSchedulingTests",code:1)
    }

    func testGiftOnePercentOpportunityDefaultsOffAndDoesNotTransferToOtherEnabledActions() throws {
        let seed=try Self.giftOpportunitySeed()
        var remaining:Double?,drawCount:Int?
        for enabled in [true,false] {
            var scheduler=AmbientScheduler(seed:seed);scheduler.reset(.high)
            var draws=0,outcome:AmbientEvent?
            for _ in 0..<45*60+2 {
                let before=scheduler.remaining
                let random:()->Double={draws+=1;return 0}
                let event:AmbientEvent?
                if enabled {
                    event=scheduler.tick(BehaviorEngine.step,pointer:.zero,buttonsDown:false,
                        pointerEnabled:true,flockEnabled:true,socialEnabled:true,leafEnabled:true,
                        insectEnabled:true,giftEnabled:true,frequency:.high,busy:false,random:random)
                } else {
                    // Deliberately omit giftEnabled: old callers keep the empty interval.
                    event=scheduler.tick(BehaviorEngine.step,pointer:.zero,buttonsDown:false,
                        pointerEnabled:true,flockEnabled:true,socialEnabled:true,leafEnabled:true,
                        insectEnabled:true,frequency:.high,busy:false,random:random)
                }
                if scheduler.remaining>before {outcome=event;break}
            }
            if enabled {
                XCTAssertEqual(outcome,.visitorGift);remaining=scheduler.remaining;drawCount=draws
            } else {
                XCTAssertNil(outcome);XCTAssertEqual(scheduler.remaining,remaining);XCTAssertEqual(draws,drawCount)
            }
            XCTAssertEqual(draws,1,"The closed or open gift interval spends only the existing interval draw")
        }
    }

    func testSceneFocusNeverDrawsDailyGiftAndTurningGiftOnCannotChangeSceneOutcomes() {
        for seed:UInt64 in 0..<16 {
            var outcomes:[[AmbientEvent?]]=[],clocks:[[Double]]=[]
            for enabled in [false,true] {
                var scheduler=AmbientScheduler(seed:seed);scheduler.reset(.high)
                XCTAssertTrue(scheduler.acquireFocus(SceneFocus(leafID:ScenePropID(1)),frequency:.high))
                var events:[AmbientEvent?]=[],remaining:[Double]=[]
                for _ in 0..<120*10 {
                    let before=scheduler.remaining
                    let event=scheduler.tick(0.1,pointer:.zero,buttonsDown:false,
                        pointerEnabled:true,flockEnabled:true,socialEnabled:true,leafEnabled:true,
                        insectEnabled:true,giftEnabled:enabled,frequency:.high,busy:false,random:{0.5})
                    XCTAssertNotEqual(event,.visitorGift)
                    if scheduler.remaining>before {events.append(event);remaining.append(scheduler.remaining)}
                }
                XCTAssertFalse(events.isEmpty);outcomes.append(events);clocks.append(remaining)
            }
            XCTAssertEqual(outcomes[0],outcomes[1]);XCTAssertEqual(clocks[0],clocks[1])
        }
    }

    func testActualAutomaticGiftConsumesOneSharedOpportunityAndItsOwnRandomStreamAcrossCallbackRates() throws {
        typealias F=VisitorGiftTestSupport
        let seed=try Self.giftOpportunitySeed()
        var independent:[BehaviorReplayReport]?
        for draws in [0,29] {
            var reference:[BehaviorReplayReport]?
            for hz in [30,60,120] {
                let e=try F.prepared(seed:seed,ordinaryCarryFirst:true)
                var settings=e.settings;settings.ambientFrequency = .high;e.applySettings(settings)
                let carry=try LeafCarryTestSupport.start(e.handle(.leafCarry(.preview)))
                for _ in 0..<25*60 {if e.runtime.runs[carry]==nil {break};e.advance(BehaviorEngine.step)}
                XCTAssertEqual(F.terminals(e,carry).map(\.type),[.completed])
                XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.placed)
                e.handle(.remove(try XCTUnwrap(e.id(of:e.birds[1]))))
                // Align an ordinary idle-hop-free opportunity using real time;
                // do not overwrite the resident, its owner or its motion phase.
                let bird=e.birds[0]
                for _ in 0..<8*60 {
                    if [45-BehaviorEngine.step,45,45+BehaviorEngine.step,46].allSatisfy({
                        abs(SpeciesBehavior.hop(F.species,age:bird.stateTime+$0))<0.001
                    }) {break}
                    e.advance(BehaviorEngine.step)
                }
                e.scheduler.reset(.high);e.ambientEnabled=true
                for _ in 0..<draws {_=e.random.unit();_=e.ecologyRandom.unit()}
                var requests:[GiftAuthorizationRequest]=[],observations:[BehaviorObservation]=[]
                e.giftAuthorizationObserver={requests.append($0)};e.observationObserver={observations.append($0)}
                var reports:[BehaviorReplayReport]=[]
                // Feed the external result at the same simulation boundary,
                // independent of the callback that first sees the request.
                F.advance(e,46,hz:hz)
                let request=try XCTUnwrap(e.giftAuthorizationRequest,"Actual daily opportunity must pass geometric preflight: \(e.events.map(RecordedEvent.init))")
                XCTAssertEqual(requests,[request]);XCTAssertEqual(request.binding.source,.automatic)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                e.receiveGiftAuthorization(.init(granted:.init(id:F.tokenID,binding:request.binding)))
                let run=try XCTUnwrap(e.runtime.runs.values.first{$0.execution.kind == .visitorGift})
                for sample in 0..<360 {
                    if sample==2 {e.handle(.pause(true))}
                    if sample==5 {e.handle(.pause(false))}
                    F.advance(e,0.1,hz:hz)
                    reports.append(BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init)))
                }
                F.released(e,run.id);XCTAssertEqual(F.terminals(e,run.id).map(\.type),[.completed])
                XCTAssertEqual(requests.count,1);XCTAssertEqual(observations.count,1)
                XCTAssertEqual(observations.first?.source,.automatic)
                XCTAssertEqual(e.events.filter{$0.kind == .visitorGift && $0.type == .started}.count,1)
                if let reference {XCTAssertEqual(reports,reference,"Same draws retain every report field across Hz")}
                else {reference=reports}
            }
            // Daily next-wait selection predates the independent scene RNG and
            // consumes e.random. Normalize exactly that clock across draw counts;
            // all other fields, including token, route, object and events remain.
            var normalized=try XCTUnwrap(reference)
            for index in normalized.indices {normalized[index].schedulerRemaining=nil}
            if let independent {XCTAssertEqual(normalized,independent)} else {independent=normalized}
        }
    }
}
