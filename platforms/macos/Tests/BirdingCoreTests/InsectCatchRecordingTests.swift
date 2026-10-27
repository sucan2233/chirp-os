import XCTest
@testable import BirdingCore

final class InsectCatchRecordingTests:XCTestCase {
    private typealias F=InsectCatchTestSupport
    private func sharedFixture()throws->BehaviorInputLog {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try BehaviorInputLog.load(from:root.appendingPathComponent("shared/behavior-fixtures/v1/insect-catch.json"))
    }

    func testHandwrittenFixturePreservesActualCancellationPauseContactAndRestorationAtAllCallbackRates() throws {
        let log=try sharedFixture();XCTAssertEqual(log.simulationVersion,24)
        func prefix(_ count:Int,_ hz:Int=60)throws->BehaviorReplayReport {
            var input=log;input.inputs=Array(log.inputs.prefix(count));return try input.replay(callbackHz:hz)
        }
        for count in 1...log.inputs.count {
            let reference=try prefix(count)
            XCTAssertEqual(try prefix(count,30),reference,"input \(count)")
            XCTAssertEqual(try prefix(count,120),reference,"input \(count)")
            XCTAssertEqual(reference.residents,1);XCTAssertEqual(reference.birds.map(\.id),["1"])
            XCTAssertLessThanOrEqual(reference.runs,1);XCTAssertLessThanOrEqual(reference.leases,1)
            XCTAssertLessThanOrEqual(reference.props.count,1);XCTAssertNil(reference.sceneFocusID)
            XCTAssertFalse(reference.events.contains{$0.type=="failed" || $0.type=="rejected"})
            if let insect=reference.insect {XCTAssertEqual(reference.props.map(\.id),[insect.id])}
        }
        for (beforeCount,afterCount) in [(4,5),(13,14)] {
            let before=try prefix(beforeCount),after=try prefix(afterCount)
            XCTAssertTrue(after.paused);XCTAssertEqual(after.birds,before.birds)
            XCTAssertEqual(after.props,before.props);XCTAssertEqual(after.insect,before.insect)
            XCTAssertEqual(after.lastInsectContact,before.lastInsectContact)
            XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
            XCTAssertEqual(after.insectCooldownRemaining,before.insectCooldownRemaining)
        }
        let first=try prefix(2),cancelled=try prefix(7),continued=try prefix(8)
        let insect=try XCTUnwrap(first.insect)
        XCTAssertEqual(insect.age,0);XCTAssertEqual(insect.remainingLifetime,12)
        XCTAssertEqual(first.runs,1);XCTAssertEqual(first.leases,1);XCTAssertNil(first.lastInsectContact)
        XCTAssertEqual(cancelled.insect?.id,insect.id)
        XCTAssertEqual(try XCTUnwrap(cancelled.insect).age,0.05,accuracy:1e-9)
        XCTAssertEqual(cancelled.runs,0);XCTAssertEqual(cancelled.leases,0);XCTAssertEqual(cancelled.reservations,0)
        XCTAssertEqual(cancelled.events.filter{$0.kind=="insectCatch" && $0.type=="cancelled"}.map(\.reason),["userInput"])
        let moving=try XCTUnwrap(continued.insect)
        XCTAssertEqual(moving.id,insect.id);XCTAssertEqual(moving.waypoints,insect.waypoints)
        XCTAssertEqual(moving.age,0.15,accuracy:1e-9);XCTAssertNotEqual(moving.position,insect.position)
        XCTAssertEqual(moving.remainingLifetime,11.85,accuracy:1e-9)
        XCTAssertNil(try prefix(9).insect)
        let second=try XCTUnwrap(try prefix(11).insect)
        XCTAssertNotEqual(second.id,insect.id);XCTAssertEqual(second.age,0)
        let final=try prefix(log.inputs.count),contact=try XCTUnwrap(final.lastInsectContact)
        XCTAssertEqual(try XCTUnwrap(log.expected),final)
        XCTAssertEqual(final.events.filter{$0.kind=="insectCatch" && $0.type=="started"}.count,2)
        XCTAssertEqual(final.events.filter{$0.kind=="insectCatch" && $0.type=="cancelled"}.count,1)
        let completed=try XCTUnwrap(final.events.first{$0.kind=="insectCatch" && $0.type=="completed"})
        XCTAssertEqual(final.events.filter{$0.kind=="insectCatch" && $0.type=="completed"}.count,1)
        XCTAssertEqual(contact.insectID,second.id);XCTAssertEqual(contact.birdID,"1")
        XCTAssertEqual(contact.runID,completed.run)
        XCTAssertGreaterThanOrEqual(completed.time-contact.time,0.48-1e-8)
        XCTAssertLessThanOrEqual(hypot(contact.beakPosition.x-contact.insectPosition.x,contact.beakPosition.y-contact.insectPosition.y),3)
        XCTAssertNil(final.insect);XCTAssertEqual(final.insectMissedTargetCount,0)
        XCTAssertEqual(final.hasInsectCatchPreview,false);XCTAssertEqual(final.runs,0)
        XCTAssertEqual(final.leases,0);XCTAssertEqual(final.reservations,0);XCTAssertTrue(final.props.isEmpty)
        XCTAssertEqual(final.birds.first?.state,"perched")
        XCTAssertEqual(final.birds.first?.position.x,2140);XCTAssertEqual(final.birds.first?.position.y,1650)
    }

    func testSegmentedRealSuccessAndMissHaveIdenticalEventsContactsAndCleanupAtThirtySixtyAndOneHundredTwentyHz() throws {
        func replay(_ hz:Int,miss:Bool)throws->[BehaviorReplayReport] {
            let e=try F.engine();var events:[RecordedEvent]=[],observations:[BehaviorObservation]=[]
            e.eventObserver={events.append(RecordedEvent($0))};e.observationObserver={observations.append($0)}
            let run:BehaviorRunID
            if miss {
                guard case .started(let value)=e.startInsectCatchFixture(species:.barnSwallow,trajectory:try F.missTrajectory(in:e)) else {
                    XCTFail("A legal miss must be admitted");throw NSError(domain:"InsectCatchRecordingTests",code:1)
                }
                run=value
            } else {run=try F.start(e).0}
            var reports:[BehaviorReplayReport]=[]
            for sample in 0..<360 {
                if sample==1 {e.handle(.pause(true))}
                if sample==4 {e.handle(.pause(false))}
                F.advance(e,0.1,hz:hz);reports.append(BehaviorReplayReport(engine:e,events:events))
            }
            F.released(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[miss ? .failed:.completed])
            XCTAssertEqual(e.insectMissedTargetCount,miss ? 1:0)
            XCTAssertEqual(observations.count,miss ? 0:1);XCTAssertNil(e.insectSnapshot())
            XCTAssertTrue(e.propSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
            return reports
        }
        for miss in [false,true] {
            let reference=try replay(60,miss:miss)
            XCTAssertEqual(try replay(30,miss:miss),reference)
            XCTAssertEqual(try replay(120,miss:miss),reference)
        }
    }

    func testActualRecordingKeepsPendingSpeciesAndDeadlineAndRejectsFixtureMutation() throws {
        var settings=F.settings()
        let index=try XCTUnwrap(settings.probabilities.entries.firstIndex{$0.id == .barnSwallow})
        for entry in settings.probabilities.entries { settings.probabilities.setWeight(0, for: entry.id) }; settings.probabilities.setManualWeight(at:index,to:1)
        let e=BehaviorEngine(seed:1901,settings:settings,recordInputs:true)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(.init(screens:[F.display],displays:[F.display],surfaces:[F.host()],
            pointer:CGPoint(x:20,y:20),availableFrames:[.barnSwallow:F.frames]))
        // Start with a real rejection, then let a normally spawned resident
        // land. No fixture injection is allowed in a production recording.
        XCTAssertEqual(e.handle(.insectCatch(species:.barnSwallow,source:.preview)),.rejected(.noSpecies))
        e.bringInBird();F.advance(e,20)
        XCTAssertEqual(e.birds.map{$0.profile.id},[.barnSwallow]);XCTAssertEqual(e.birds.first?.state,.perched)
        XCTAssertEqual(e.handle(.insectCatch(species:.barnSwallow,source:.preview)),.scheduled)
        F.advance(e,2);e.handle(.pause(true));F.advance(e,1)
        let pending=try e.recordedInputs(),report=try XCTUnwrap(pending.expected)
        XCTAssertEqual(report.hasInsectCatchPreview,true);XCTAssertEqual(report.insectPreviewSpecies,"barnSwallow")
        XCTAssertEqual(try XCTUnwrap(report.insectPreviewRemaining),8,accuracy:1e-9)
        XCTAssertNil(report.insect);XCTAssertEqual(report.runs,0);XCTAssertEqual(report.leases,0)
        for hz in [30,60,120] {XCTAssertEqual(try pending.replay(callbackHz:hz),report)}
        e.handle(.cancelInsectCatchPreview);e.handle(.pause(false));e.handle(.clearInsect)
        let log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        XCTAssertEqual(log.simulationVersion,24);XCTAssertNotNil(log.expected)
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
        XCTAssertEqual(log.expected?.events.filter{$0.kind=="insectCatch" && $0.type=="rejected"}.map(\.reason),["noSpecies"])
        _=e.startInsectCatchFixture(species:.barnSwallow,trajectory:try F.missTrajectory(in:e))
        XCTAssertThrowsError(try e.recordedInputs(),"A native physical-trajectory seam cannot masquerade as a recorded command")
    }
}
