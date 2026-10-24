import XCTest
@testable import BirdingCore

final class VisitorGiftRecordingTests:XCTestCase {
    private typealias F=VisitorGiftTestSupport

    func testNineteenthHandwrittenFixtureRestoresMemoryBeforeResidentsAndPreservesFullResultsAtEveryBoundary() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let log=try BehaviorInputLog.load(from:root.appendingPathComponent("shared/behavior-fixtures/v1/visitor-gift.json"))
        XCTAssertEqual(log.simulationVersion,17);XCTAssertNil(log.expected)
        XCTAssertEqual(log.initialVisitorMemory?.seed,"73")
        XCTAssertEqual(log.initialVisitorMemory?.profiles.first?.visits,2)
        func prefix(_ count:Int,_ hz:Int=60)throws->BehaviorReplayReport {
            var partial=log;partial.inputs=Array(log.inputs.prefix(count));return try partial.replay(callbackHz:hz)
        }
        for count in 1...log.inputs.count {
            let report=try prefix(count)
            XCTAssertEqual(try prefix(count,30),report,"boundary \(count)")
            XCTAssertEqual(try prefix(count,120),report,"boundary \(count)")
            XCTAssertEqual(report.residents,1);XCTAssertEqual(report.birds.map(\.id),["1"])
            XCTAssertEqual(report.birds.first?.visitorID,"99")
            XCTAssertEqual(report.visitorMemory.profiles.first{$0.id=="99"}?.visits,3)
            XCTAssertLessThanOrEqual(report.carriedObjects?.count ?? 0,1)
            XCTAssertEqual(report.props.map(\.id),report.carriedObjects?.map(\.id) ?? [])
            XCTAssertLessThanOrEqual(report.runs,1);XCTAssertLessThanOrEqual(report.leases,1)
            XCTAssertFalse(report.events.contains{$0.type=="failed" || $0.type=="rejected"},"boundary \(count)")
        }
        let pending=try prefix(3),binding=try XCTUnwrap(pending.giftAuthorizationRequest).binding
        XCTAssertEqual(pending.runs,0);XCTAssertEqual(pending.leases,0);XCTAssertEqual(pending.reservations,0)
        XCTAssertEqual(pending.activeGiftAuthorizationCount,0)
        XCTAssertEqual(binding.requestID,"1");XCTAssertEqual(binding.visitorArchiveSeed,"73")
        XCTAssertEqual(binding.visitorID,"99");XCTAssertEqual(binding.birdID,BirdID(1))
        XCTAssertEqual(binding.species,F.species);XCTAssertEqual(binding.source,.preview)
        XCTAssertEqual(binding.leafID,ScenePropID(1));XCTAssertEqual(binding.receiverSlot,1)
        XCTAssertEqual(binding.receiverRevision,1)
        let granted=try prefix(4)
        XCTAssertNil(granted.giftAuthorizationRequest);XCTAssertEqual(granted.activeGiftAuthorizationCount,1)
        XCTAssertEqual(granted.carriedObjects?.first?.id,"1")
        XCTAssertEqual(granted.carriedObjects?.first?.isVisitorGift,true)
        XCTAssertEqual(granted.giftReceiverReservations?.count,1)
        for (a,b) in [(6,7),(14,15)] {
            let before=try prefix(a),after=try prefix(b)
            XCTAssertTrue(after.paused);XCTAssertEqual(after.birds,before.birds)
            XCTAssertEqual(after.props,before.props);XCTAssertEqual(after.carriedObjects,before.carriedObjects)
            XCTAssertEqual(after.giftAuthorizationToken,before.giftAuthorizationToken)
            XCTAssertEqual(after.giftAuthorizationConsumed,before.giftAuthorizationConsumed)
            XCTAssertEqual(after.giftReceiverReservations,before.giftReceiverReservations)
            XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
        }
        let complete=try prefix(9),gift=try XCTUnwrap(complete.carriedObjects?.first)
        XCTAssertEqual(complete.events.filter{$0.kind=="visitorGift" && $0.type=="completed"}.count,1)
        XCTAssertEqual(gift.id,"1");XCTAssertEqual(gift.isVisitorGift,true);XCTAssertEqual(gift.state,"placed")
        XCTAssertEqual(gift.giftReceiverSlot,1);XCTAssertEqual(gift.giftReceiverRevision,1)
        XCTAssertEqual(gift.giftFallAge,gift.giftFallDuration);XCTAssertGreaterThan(gift.remainingLifetime,0)
        XCTAssertEqual(complete.birds.first?.state,"perched")
        XCTAssertEqual(complete.runs,0);XCTAssertEqual(complete.leases,0);XCTAssertEqual(complete.reservations,0)
        XCTAssertEqual(complete.activeGiftAuthorizationCount,0)
        XCTAssertEqual(complete.giftReceiverReservations,[]);XCTAssertNil(complete.sceneFocusID)
        let cleared=try prefix(16)
        XCTAssertTrue(cleared.paused);XCTAssertEqual(cleared.carriedObjects,[]);XCTAssertTrue(cleared.props.isEmpty)
        XCTAssertEqual(cleared.runs,0);XCTAssertEqual(cleared.activeGiftAuthorizationCount,0)
        let final=try prefix(log.inputs.count)
        XCTAssertEqual(final.events.filter{$0.kind=="visitorGift" && $0.type=="started"}.count,2)
        XCTAssertEqual(final.events.filter{$0.kind=="visitorGift" && $0.type=="completed"}.count,1)
        XCTAssertEqual(final.events.filter{$0.kind=="visitorGift" && $0.type=="cancelled"}.map(\.reason),["removed"])
        XCTAssertEqual(final.carriedObjects,[]);XCTAssertTrue(final.props.isEmpty)
        XCTAssertEqual(final.runs,0);XCTAssertEqual(final.leases,0);XCTAssertEqual(final.reservations,0)
        XCTAssertEqual(final.activeGiftAuthorizationCount,0);XCTAssertEqual(final.giftReceiverReservations,[])
        XCTAssertNil(final.giftAuthorizationRequest);XCTAssertNil(final.sceneFocusID)
        XCTAssertEqual(final.hasCarryLeafPlacement,false)
    }

    func testProductionRecordingReplaysPlatformDenialGrantAndLateResultsAndRejectsRealVersionFifteen() throws {
        var settings=F.settings()
        let index=try XCTUnwrap(settings.probabilities.entries.firstIndex{$0.id==F.species})
        settings.probabilities.adjust(at:index,to:10000)
        let e=BehaviorEngine(seed:1971,settings:settings,recordInputs:true)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        try e.restoreVisitorMemory(F.memory())
        e.updateWorld(.init(screens:[F.display()],displays:[F.display()],surfaces:[F.host()],
            pointer:CGPoint(x:20,y:20),availableFrames:[F.species:F.frames],displayIDs:["gift-display"]))
        e.bringInBird()
        for _ in 0..<60*60 {
            if let bird=e.birds.first,bird.state == .perched,bird.stateTime>=1 {break}
            e.advance(BehaviorEngine.step)
        }
        let bird=try XCTUnwrap(e.birds.first)
        XCTAssertEqual(bird.profile.id,F.species);XCTAssertEqual(e.visitor(of:bird)?.id,"99")
        XCTAssertEqual(e.visitor(of:bird)?.visits,3)
        XCTAssertEqual(e.handle(.visitorGift(.preview)),.rejected(.noSpace))
        let x=try XCTUnwrap([CGFloat(1000),800,1200].first{abs($0-bird.position.x)>150})
        XCTAssertTrue(e.handle(.placeCarryLeaf(at:CGPoint(x:x,y:1700))).accepted)
        XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled)
        let first=try XCTUnwrap(e.giftAuthorizationRequest)
        e.receiveGiftAuthorization(.init(denied:first.binding,reason:.timedOut))
        let (run,_)=try F.authorize(e)
        let granted=try XCTUnwrap(try e.recordedInputs().expected?.giftAuthorizationToken)
        e.receiveGiftAuthorization(.init(granted:granted))
        F.advance(e,0.25);e.handle(.pause(true));F.advance(e,2);e.handle(.pause(false))
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        e.handle(.pause(true));e.handle(.clearVisitorGift)
        e.receiveGiftAuthorization(.init(granted:granted))
        var disabled=e.settings;disabled.visitorGiftsEnabled=false;e.applySettings(disabled)
        XCTAssertEqual(e.activeGiftAuthorizationCount,0);XCTAssertNil(e.giftAuthorizationRequest)
        XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertTrue(e.runtime.giftReceiverReservations.isEmpty)
        let log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        XCTAssertEqual(log.simulationVersion,17);XCTAssertNotNil(log.expected);XCTAssertNil(log.failure)
        XCTAssertNil(log.initialVisitorMemory,"Production bootstrapping is an actual visitorMemory input")
        XCTAssertEqual(log.inputs.filter{$0.kind=="visitorMemory"}.count,1)
        XCTAssertEqual(log.inputs.filter{$0.kind=="giftAuthorization"}.count,4)
        XCTAssertEqual(log.inputs.compactMap(\.giftAuthorization).first?.denial,.timedOut)
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
        var old=log;old.simulationVersion=15
        XCTAssertEqual(old.expected,log.expected);XCTAssertEqual(old.inputs.count,log.inputs.count)
        let bytes=try BehaviorInputLog.encoder().encode(old)
        XCTAssertThrowsError(try BehaviorInputLog.decode(bytes))
        let unvalidated=try JSONDecoder().decode(BehaviorInputLog.self,from:bytes)
        for hz in [30,60,120] {XCTAssertThrowsError(try unvalidated.replay(callbackHz:hz))}
    }

    func testGiftCommandsRoundTripAndIncompleteAuthorizationInputsCannotSilentlyReplay() throws {
        for command:EngineCommand in [.visitorGift(.automatic),.visitorGift(.preview),.visitorGift(.user),
                                      .cancelVisitorGiftRequest,.clearVisitorGift] {
            let bytes=try JSONEncoder().encode(RecordedCommand(command))
            let value=try JSONDecoder().decode(RecordedCommand.self,from:bytes)
            XCTAssertEqual(try BehaviorInputLog.encoder().encode(RecordedCommand(value.validated())),
                try BehaviorInputLog.encoder().encode(RecordedCommand(command)))
        }
        var command=RecordedCommand(.visitorGift(.preview));command.source=nil
        XCTAssertThrowsError(try command.validated())
        var log=BehaviorInputLog(seed:1971,settings:F.settings())
        log.inputs=[RecordedInput(kind:"giftAuthorization")]
        XCTAssertThrowsError(try log.replay())
    }
}
