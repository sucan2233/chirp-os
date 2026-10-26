import XCTest
@testable import BirdingCore

final class FlycatcherInsectCatchRecordingTests:XCTestCase {
    private typealias F=FlycatcherInsectCatchTestSupport
    private typealias Common=InsectCatchTestSupport

    func testSharedEighteenthFixturePreservesRealReturnPausedCancellationAndIndependentInsectAtEveryBoundary() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let log=try BehaviorInputLog.load(from:root.appendingPathComponent("shared/behavior-fixtures/v1/flycatcher-insect-catch.json"))
        XCTAssertEqual(log.simulationVersion,22)
        func prefix(_ count:Int,_ hz:Int=60)throws->BehaviorReplayReport {
            var input=log;input.inputs=Array(log.inputs.prefix(count));return try input.replay(callbackHz:hz)
        }
        for count in 1...log.inputs.count {
            let report=try prefix(count)
            XCTAssertEqual(try prefix(count,30),report,"boundary \(count)")
            XCTAssertEqual(try prefix(count,120),report,"boundary \(count)")
            XCTAssertEqual(report.residents,1);XCTAssertEqual(report.birds.map(\.id),["1"])
            XCTAssertLessThanOrEqual(report.runs,1);XCTAssertLessThanOrEqual(report.leases,1)
            XCTAssertLessThanOrEqual(report.props.count,1);XCTAssertNil(report.sceneFocusID)
            XCTAssertFalse(report.events.contains{$0.type=="failed" || $0.type=="rejected"},"boundary \(count)")
        }
        for (beforeCount,afterCount) in [(4,5),(10,11)] {
            let before=try prefix(beforeCount),after=try prefix(afterCount)
            XCTAssertTrue(after.paused);XCTAssertEqual(after.birds,before.birds)
            XCTAssertEqual(after.insect,before.insect);XCTAssertEqual(after.props,before.props)
            XCTAssertEqual(after.lastInsectContact,before.lastInsectContact)
            XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
            XCTAssertEqual(after.insectCooldownRemaining,before.insectCooldownRemaining)
        }
        let first=try prefix(2),returned=try prefix(7)
        let target=try XCTUnwrap(first.insect),contact=try XCTUnwrap(returned.lastInsectContact)
        XCTAssertEqual(target.age,0);XCTAssertEqual(target.remainingLifetime,12)
        XCTAssertEqual(first.runs,1);XCTAssertEqual(first.leases,1);XCTAssertEqual(first.reservations,1)
        XCTAssertEqual(returned.birds.first?.state,"perched")
        XCTAssertEqual(try XCTUnwrap(returned.birds.first).position.x,529.4,accuracy:1e-8)
        XCTAssertEqual(returned.birds.first?.position.y,1650)
        XCTAssertEqual(returned.runs,0);XCTAssertEqual(returned.leases,0);XCTAssertEqual(returned.reservations,0)
        let completion=try XCTUnwrap(returned.events.first{$0.kind=="insectCatch" && $0.type=="completed"})
        XCTAssertEqual(contact.insectID,target.id);XCTAssertEqual(contact.runID,completion.run)
        XCTAssertLessThanOrEqual(contact.insectAge,3)
        XCTAssertGreaterThanOrEqual(completion.time-contact.time,0.48-1e-8)
        XCTAssertLessThanOrEqual(hypot(contact.beakPosition.x-contact.insectPosition.x,contact.beakPosition.y-contact.insectPosition.y),3+1e-8)
        let next=try XCTUnwrap(try prefix(8).insect),cancelled=try prefix(12)
        XCTAssertNotEqual(next.id,target.id);XCTAssertEqual(next.age,0)
        XCTAssertTrue(cancelled.paused);XCTAssertEqual(cancelled.insect?.id,next.id)
        XCTAssertEqual(try XCTUnwrap(cancelled.insect).age,0.05,accuracy:1e-9)
        XCTAssertEqual(cancelled.insect?.waypoints,next.waypoints)
        XCTAssertEqual(cancelled.runs,0);XCTAssertEqual(cancelled.leases,0);XCTAssertEqual(cancelled.reservations,0)
        let final=try prefix(log.inputs.count)
        XCTAssertEqual(try XCTUnwrap(log.expected),final)
        XCTAssertEqual(final.events.filter{$0.kind=="insectCatch" && $0.type=="started"}.count,2)
        XCTAssertEqual(final.events.filter{$0.kind=="insectCatch" && $0.type=="completed"}.count,1)
        XCTAssertEqual(final.events.filter{$0.kind=="insectCatch" && $0.type=="cancelled"}.map(\.reason),["userInput"])
        XCTAssertEqual(final.lastInsectContact,contact);XCTAssertEqual(final.insectMissedTargetCount,0)
        XCTAssertEqual(final.birds.first?.state,"perched");XCTAssertEqual(final.birds.first?.species,F.species.rawValue)
        XCTAssertEqual(final.runs,0);XCTAssertEqual(final.leases,0);XCTAssertEqual(final.reservations,0)
        XCTAssertEqual(final.habitatReservations,0);XCTAssertNil(final.insect);XCTAssertTrue(final.props.isEmpty)
        XCTAssertEqual(final.hasInsectCatchPreview,false);XCTAssertNil(final.sceneFocusID)
    }

    func testSuccessMissAndClickCancellationKeepIdenticalFullReportsAtThirtySixtyAndOneHundredTwentyHz() throws {
        func replay(_ hz:Int,_ scenario:String)throws->[BehaviorReplayReport] {
            let e=try F.engine(),bird=try XCTUnwrap(e.birds.first),foot=bird.position
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            let run:BehaviorRunID
            if scenario == "miss" {
                guard case .started(let value)=e.startInsectCatchFixture(species:F.species,trajectory:try F.missTrajectory(e)) else {
                    XCTFail("Real miss must admit normally");throw NSError(domain:"FlycatcherInsectCatchRecordingTests",code:1)
                }
                run=value
            } else {run=try F.start(e).0}
            var reports:[BehaviorReplayReport]=[]
            for sample in 0..<270 {
                if sample==1 {e.handle(.pause(true))}
                if sample==4 {e.handle(.pause(false))}
                if scenario == "cancel",sample==5 {e.handle(.pointerClick)}
                F.advance(e,0.1,hz:hz)
                reports.append(BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init)))
            }
            F.released(e,run)
            let terminal:BehaviorEventType=scenario == "hit" ? .completed:scenario == "miss" ? .failed:.cancelled
            XCTAssertEqual(Common.terminals(e,run).map(\.type),[terminal])
            XCTAssertEqual(observations.count,scenario == "hit" ? 1:0)
            XCTAssertEqual(e.insectMissedTargetCount,scenario == "miss" ? 1:0)
            if scenario != "cancel" {XCTAssertEqual(bird.position,foot);XCTAssertEqual(bird.state,.perched)}
            XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
            return reports
        }
        for scenario in ["hit","miss","cancel"] {
            let reference=try replay(60,scenario)
            XCTAssertEqual(try replay(30,scenario),reference,scenario)
            XCTAssertEqual(try replay(120,scenario),reference,scenario)
        }
    }

    func testProductionCurrentVersionRecordingCompletesWithoutInjectionAndRejectsTheActualVersionFourteenEnvelope() throws {
        var settings=Common.settings()
        let index=try XCTUnwrap(settings.probabilities.entries.firstIndex{$0.id==F.species})
        settings.probabilities.adjust(at:index,to:10000)
        let e=BehaviorEngine(seed:2101,settings:settings,recordInputs:true)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(.init(screens:[F.display],displays:[F.display],surfaces:[F.host()],
            pointer:CGPoint(x:20,y:20),availableFrames:[F.species:F.frames]))
        XCTAssertEqual(e.handle(.insectCatch(species:F.species,source:.preview)),.rejected(.noSpecies))
        e.bringInBird()
        for _ in 0..<60*60 {
            if e.birds.first?.state == .perched {break}
            e.advance(BehaviorEngine.step)
        }
        let bird=try XCTUnwrap(e.birds.first),foot=bird.position
        XCTAssertEqual(bird.profile.id,F.species);XCTAssertEqual(bird.state,.perched)
        let (run,_)=try F.start(e);F.finish(e,run);F.released(e,run)
        XCTAssertEqual(Common.terminals(e,run).map(\.type),[.completed])
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,foot)
        let log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        XCTAssertEqual(log.simulationVersion,22);XCTAssertNotNil(log.expected);XCTAssertNil(log.failure)
        XCTAssertEqual(log.inputs.filter{$0.command?.name=="insectCatch"}.map{$0.command?.species},[F.species.rawValue,F.species.rawValue])
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
        // This is a complete real recording, including its real expected report;
        // old semantics are rejected, never promoted or regenerated to pass.
        var old=log;old.simulationVersion=14
        let bytes=try BehaviorInputLog.encoder().encode(old)
        XCTAssertEqual(old.expected,log.expected)
        XCTAssertThrowsError(try BehaviorInputLog.decode(bytes))
        let decoded=try JSONDecoder().decode(BehaviorInputLog.self,from:bytes)
        for hz in [30,60,120] {XCTAssertThrowsError(try decoded.replay(callbackHz:hz))}
        _=e.startInsectCatchFixture(species:F.species,trajectory:try F.missTrajectory(e))
        XCTAssertThrowsError(try e.recordedInputs(),"The physical miss seam cannot be recorded as a command")
    }
}
