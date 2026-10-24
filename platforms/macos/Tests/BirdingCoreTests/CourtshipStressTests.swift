import XCTest
@testable import BirdingCore

/// Bounded simulation workloads, not renderer benchmarks or long-run evidence.
final class CourtshipStressTests:XCTestCase {
    private typealias F=CourtshipTestSupport
    func testTwentyFourResidentsCompleteTwoDisplaysAndCancelOneWithoutResidualLeases() throws {try exercise(24)}
    func testSixtyFourResidentsCompleteTwoDisplaysAndCancelOneWithoutResidualLeases() throws {try exercise(64)}

    private func exercise(_ count:Int)throws {
        let e=F.engine(residents:count),identities=e.birds.map(ObjectIdentifier.init)
        let feet=e.birds.map(\.position),hosts=e.birds.map(\.hostID)
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        var runs:[BehaviorRunID]=[],peakLeases=0,peakReservations=0
        func invariant() {
            XCTAssertEqual(e.residentCount,count);XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
            XCTAssertEqual(e.birds.map(\.position),feet);XCTAssertEqual(e.birds.map(\.hostID),hosts)
            XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0);XCTAssertEqual(e.pendingCount,0)
            XCTAssertEqual(e.perchPlanner.rhythms.count,count);XCTAssertLessThanOrEqual(e.activeRunCount,1)
            XCTAssertLessThanOrEqual(e.leasedBirdCount,2);XCTAssertLessThanOrEqual(e.reservedLandingCount,1)
            XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertTrue(e.propSnapshot().isEmpty)
            XCTAssertTrue(e.habitatSnapshot().isEmpty);XCTAssertNil(e.insectSnapshot());XCTAssertNil(e.sceneFocus)
            XCTAssertEqual(e.activeGiftAuthorizationCount,0);XCTAssertNil(e.giftAuthorizationRequest)
            peakLeases=max(peakLeases,e.leasedBirdCount);peakReservations=max(peakReservations,e.reservedLandingCount)
        }
        for a in e.birds.indices {for b in e.birds.indices where b>a {
            XCTAssertFalse(e.bounds(of:e.birds[a]).intersects(e.bounds(of:e.birds[b])))
        }}
        for index in 0..<3 {
            if index>0 {F.advance(e,10.1)}
            let run=try F.start(e);runs.append(run);invariant()
            F.advance(e,1.4);invariant();e.handle(.pause(true))
            let before=BehaviorReplayReport(engine:e,events:[]),age=e.runtime.runs[run]?.age
            F.advance(e,2);invariant()
            let after=BehaviorReplayReport(engine:e,events:[])
            XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(e.runtime.runs[run]?.age,age)
            if index==1 {e.handle(.cancelAmbient(.sleep))}
            e.handle(.pause(false));F.advance(e,3);invariant();F.clean(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[index==1 ? .cancelled:.completed])
            XCTAssertEqual(observations.count,index==0 ? 1:index==1 ? 1:2)
        }
        XCTAssertEqual(peakLeases,2);XCTAssertEqual(peakReservations,1)
        XCTAssertEqual(runs.flatMap{F.terminals(e,$0)}.filter{$0.type == .completed}.count,2)
        XCTAssertEqual(runs.flatMap{F.terminals(e,$0)}.filter{$0.type == .cancelled}.count,1)
        XCTAssertEqual(observations.map(\.kind),[.courtshipDisplay,.courtshipDisplay])
        XCTAssertEqual(observations.map(\.source),[.preview,.preview])
        XCTAssertFalse(e.events.contains{$0.type == .rejected || $0.type == .failed})
        e.handle(.cancelAmbient(.shutdown));invariant()
        for id in e.birds.compactMap({e.id(of:$0)}) {e.handle(.remove(id))}
        XCTAssertEqual(e.residentCount,0);XCTAssertTrue(e.birds.isEmpty);XCTAssertEqual(e.activeVisitorCount,0)
        XCTAssertTrue(e.perchPlanner.rhythms.isEmpty);XCTAssertEqual(e.leasedBirdCount,0)
        XCTAssertEqual(e.reservedLandingCount,0);XCTAssertTrue(e.runtime.owners.isEmpty)
        XCTAssertTrue(e.runtime.runs.isEmpty);XCTAssertTrue(e.runtime.propIDs.isEmpty)
        XCTAssertTrue(e.runtime.giftReceiverReservations.isEmpty);XCTAssertEqual(e.habitatReservationCount,0)
    }
}
