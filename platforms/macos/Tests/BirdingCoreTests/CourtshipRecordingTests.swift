import XCTest
@testable import BirdingCore

final class CourtshipRecordingTests:XCTestCase {
    private typealias F=CourtshipTestSupport
    func testTwentiethHandwrittenFixtureKeepsFeetPauseCompletionAndGroupRemovalAtEveryBoundary() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let log=try BehaviorInputLog.load(from:root.appendingPathComponent("shared/behavior-fixtures/v1/courtship-display.json"))
        XCTAssertEqual(log.simulationVersion,24)
        func prefix(_ count:Int,_ hz:Int=60)throws->BehaviorReplayReport {
            var partial=log;partial.inputs=Array(log.inputs.prefix(count));return try partial.replay(callbackHz:hz)
        }
        let first=try prefix(1),feet=first.birds.map(\.position)
        XCTAssertEqual(first.residents,2);XCTAssertEqual(first.birds.map(\.id),["1","2"])
        XCTAssertEqual(feet.map(\.x),[800,1000]);XCTAssertEqual(feet.map(\.y),[1700,1700])
        for count in 1...log.inputs.count {
            let report=try prefix(count)
            XCTAssertEqual(try prefix(count,30),report,"boundary \(count)")
            XCTAssertEqual(try prefix(count,120),report,"boundary \(count)")
            XCTAssertLessThanOrEqual(report.runs,1);XCTAssertLessThanOrEqual(report.leases,2)
            XCTAssertLessThanOrEqual(report.reservations,1);XCTAssertEqual(report.habitatReservations,0)
            XCTAssertTrue(report.props.isEmpty);XCTAssertTrue(report.habitats.isEmpty)
            XCTAssertTrue(report.carriedObjects?.isEmpty ?? true);XCTAssertNil(report.sceneFocusID)
            XCTAssertFalse(report.events.contains{$0.type=="rejected" || $0.type=="failed"})
            for bird in report.birds {
                XCTAssertEqual(bird.position,feet[bird.id=="1" ? 0:1]);XCTAssertEqual(bird.state,"perched")
                XCTAssertEqual(bird.familiarity,first.birds.first{$0.id==bird.id}?.familiarity)
            }
        }
        for (before,after) in [(4,5),(11,12)] {
            let a=try prefix(before),b=try prefix(after)
            XCTAssertTrue(b.paused);XCTAssertEqual(a.birds,b.birds)
            XCTAssertEqual(a.events,b.events);XCTAssertEqual(a.schedulerRemaining,b.schedulerRemaining)
            XCTAssertEqual(a.courtshipCooldownRemaining,b.courtshipCooldownRemaining)
        }
        let completed=try prefix(7)
        XCTAssertEqual(completed.events.filter{$0.kind=="courtshipDisplay" && $0.type=="completed"}.count,1)
        XCTAssertEqual(completed.birds.map(\.position),feet)
        XCTAssertEqual(completed.runs,0);XCTAssertEqual(completed.leases,0);XCTAssertEqual(completed.reservations,0)
        let final=try prefix(log.inputs.count)
        XCTAssertEqual(try XCTUnwrap(log.expected),final)
        XCTAssertEqual(final.events.filter{$0.kind=="courtshipDisplay" && $0.type=="started"}.count,2)
        XCTAssertEqual(final.events.filter{$0.kind=="courtshipDisplay" && $0.type=="completed"}.count,1)
        XCTAssertEqual(final.events.filter{$0.kind=="courtshipDisplay" && $0.type=="cancelled"}.map(\.reason),["removed"])
        XCTAssertEqual(final.events.filter{$0.kind=="courtshipDisplay" && $0.type=="completed"}.map(\.source),["preview"])
        XCTAssertEqual(final.birds.map(\.id),["2"]);XCTAssertEqual(final.residents,1)
        XCTAssertEqual(final.runs,0);XCTAssertEqual(final.leases,0);XCTAssertEqual(final.reservations,0)
    }

    func testRealProductionRecordingPreservesSourceSuccessCancellationAndRejectsVersionSixteenEnvelope() throws {
        var settings=F.settings()
        let index=try XCTUnwrap(settings.probabilities.entries.firstIndex{$0.id==F.species})
        for entry in settings.probabilities.entries { settings.probabilities.setWeight(0, for: entry.id) }; settings.probabilities.setManualWeight(at:index,to:1)
        let profileIndex=try XCTUnwrap(settings.catalog.species.firstIndex{$0.id==F.species})
        settings.catalog.species[profileIndex].perchMin=120;settings.catalog.species[profileIndex].perchMax=180
        let e=BehaviorEngine(seed:2701,settings:settings,recordInputs:true)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let display=CGRect(x:0,y:0,width:2400,height:2200)
        let host=Surface(id:2701,pid:42,rect:CGRect(x:200,y:1700,width:2000,height:180))
        e.updateWorld(.init(screens:[display],displays:[display],surfaces:[host],pointer:CGPoint(x:20,y:20),availableFrames:[F.species:F.frames]))
        XCTAssertEqual(e.handle(.courtshipDisplay(.preview)),.rejected(.noCompanion))
        e.bringInBird();F.advance(e,12);e.bringInBird();F.advance(e,22)
        XCTAssertEqual(e.birds.map{$0.profile.id},[.spottedDove,.spottedDove])
        let run=try F.start(e,source:.user);F.advance(e,1.4)
        e.handle(.pause(true));F.advance(e,2);e.handle(.pause(false));F.advance(e,3)
        F.clean(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        F.advance(e,10.1);let cancelled=try F.start(e)
        e.handle(.pause(true));e.handle(.remove(try XCTUnwrap(e.id(of:e.birds[0]))))
        F.clean(e,cancelled);e.handle(.pause(false));F.advance(e,0.2)
        let log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        XCTAssertEqual(BehaviorInputLog.engineVersion,24);XCTAssertEqual(log.simulationVersion,24)
        let expected=try XCTUnwrap(log.expected);XCTAssertNil(log.failure);XCTAssertNil(log.fixtureBirds)
        XCTAssertEqual(expected.events.filter{$0.kind=="courtshipDisplay" && $0.type=="completed"}.map(\.source),["user"])
        XCTAssertEqual(expected.events.filter{$0.kind=="courtshipDisplay" && $0.type=="cancelled"}.map(\.source),["preview"])
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),expected)}
        // Reject a well-formed production envelope with its real inputs and
        // expected report intact. Never promote old input or synthesize expected.
        var old=log;old.simulationVersion=16
        XCTAssertEqual(old.expected,expected);XCTAssertEqual(old.inputs.count,log.inputs.count)
        let bytes=try BehaviorInputLog.encoder().encode(old)
        XCTAssertThrowsError(try BehaviorInputLog.decode(bytes))
        let unchecked=try JSONDecoder().decode(BehaviorInputLog.self,from:bytes)
        for hz in [30,60,120] {XCTAssertThrowsError(try unchecked.replay(callbackHz:hz))}
    }

    func testAllCommandSourcesRoundTripAndAbsentOrUnknownSourceRejects() throws {
        for source:BehaviorSource in [.user,.preview,.automatic] {
            let command=RecordedCommand(.courtshipDisplay(source))
            XCTAssertEqual(command.name,"courtshipDisplay");XCTAssertEqual(command.source,source.rawValue)
            let bytes=try JSONEncoder().encode(command),decoded=try JSONDecoder().decode(RecordedCommand.self,from:bytes)
            XCTAssertEqual(try BehaviorInputLog.encoder().encode(RecordedCommand(decoded.validated())),
                try BehaviorInputLog.encoder().encode(command))
        }
        var missing=RecordedCommand(.courtshipDisplay(.preview));missing.source=nil
        XCTAssertThrowsError(try missing.validated());missing.source="future";XCTAssertThrowsError(try missing.validated())
    }
}
