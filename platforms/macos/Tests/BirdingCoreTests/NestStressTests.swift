import XCTest
@testable import BirdingCore

/// Resident simulation workloads with real transactions; not renderer or soak evidence.
final class NestStressTests:XCTestCase {
    private typealias F=NestTestSupport
    func testTwentyFourResidentsFinishTwoDeliveriesTwoBuildsAndCancelAnAttachedTwigWithoutResidualResources() throws {try workload(24)}
    func testSixtyFourResidentsFinishTwoDeliveriesTwoBuildsAndCancelAnAttachedTwigWithoutResidualResources() throws {try workload(64)}
    private func workload(_ count:Int)throws {
        let e=try F.prepared(residents:count),identities=e.birds.map(ObjectIdentifier.init)
        let background=e.birds.dropFirst().map(\.position),ids=Set(try F.nest(e).materials.map(\.id))
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        var runs:[BehaviorRunID]=[],peak=0
        func invariant()throws {
            XCTAssertEqual(e.residentCount,count);XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
            XCTAssertEqual(e.birds.dropFirst().map(\.position),background)
            XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0);XCTAssertEqual(e.pendingCount,0)
            XCTAssertLessThanOrEqual(e.activeRunCount,1);XCTAssertLessThanOrEqual(e.leasedBirdCount,1)
            XCTAssertLessThanOrEqual(e.habitatReservationCount,1);XCTAssertLessThanOrEqual(F.tokens(e).count,3)
            XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertNil(e.insectSnapshot());XCTAssertNil(e.giftAuthorizationRequest)
            peak=max(peak,e.leasedBirdCount);try F.conserved(e,ids:ids)
        }
        for index in 0..<3 {
            let carry=try F.start(e);runs.append(carry)
            let active=try XCTUnwrap(e.runtime.runs[carry]?.execution as? NestMaterialCarryExecution)
            try F.until(e,carry) {active.pickedUp && !active.delivered}
            try invariant();e.handle(.pause(true))
            let before=try F.nest(e),age=active.age,birds=e.renderSnapshot().map{RecordedBirdState($0,engine:e)}
            F.advance(e,2);XCTAssertEqual(try F.nest(e),before);XCTAssertEqual(active.age,age)
            XCTAssertEqual(e.renderSnapshot().map{RecordedBirdState($0,engine:e)},birds)
            if index==1 {e.handle(.pointerClick)}
            e.handle(.pause(false))
            if index==1 {
                F.advance(e,12);F.released(e,carry)
                XCTAssertEqual(F.terminals(e,carry).map(\.type),[.cancelled]);XCTAssertEqual(try F.nest(e).spent,1)
                XCTAssertFalse(F.tokens(e).contains{$0.id==active.plan.materialID})
            } else {
                for _ in 0..<35*60 {if e.runtime.runs[carry]==nil {break};try invariant();e.advance(BehaviorEngine.step)}
                F.released(e,carry);XCTAssertEqual(F.terminals(e,carry).map(\.type),[.completed])
                F.advance(e,1.1)
                let build=try F.start(e,build:true);runs.append(build)
                for _ in 0..<30*60 {if e.runtime.runs[build]==nil {break};try invariant();e.advance(BehaviorEngine.step)}
                F.released(e,build);XCTAssertEqual(F.terminals(e,build).map(\.type),[.completed])
                F.advance(e,1.1)
            }
            try invariant()
        }
        let final=try F.nest(e)
        XCTAssertEqual(final.progress,2);XCTAssertEqual(final.spent,1);XCTAssertEqual(final.available,0)
        XCTAssertEqual(final.delivered,0);XCTAssertEqual(final.attached,0);XCTAssertFalse(final.canContinue)
        XCTAssertNil(e.sceneFocus);XCTAssertEqual(peak,1)
        XCTAssertEqual(observations.filter{$0.kind == .nestMaterialCarry}.count,2)
        XCTAssertEqual(observations.filter{$0.kind == .nestBuild}.count,2)
        XCTAssertEqual(observations.count,4);XCTAssertEqual(Set(observations.map(\.runID)).count,4)
        XCTAssertEqual(runs.flatMap{F.terminals(e,$0)}.filter{$0.type == .cancelled}.count,1)
        F.clear(e);XCTAssertEqual(e.residentCount,count)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        XCTAssertEqual(e.habitatReservationCount,0);XCTAssertTrue(e.propSnapshot().isEmpty);XCTAssertTrue(e.runtime.propIDs.isEmpty)
        XCTAssertNil(e.sceneFocus);XCTAssertFalse(e.hasNestPlacement)
    }
}
