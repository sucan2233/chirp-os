import XCTest
@testable import BirdingCore

/// Bounded core lifecycle loads; the legacy performance workload stays separate.
final class InsectCatchStressTests:XCTestCase {
    private typealias F=InsectCatchTestSupport
    func testTwentyFourResidentsActuallyCatchCancelPauseAndReleaseTheTarget() throws {try exercise(residents:24)}
    func testSixtyFourResidentsActuallyCatchCancelPauseAndReleaseTheTarget() throws {try exercise(residents:64)}

    private func exercise(residents:Int)throws {
        var completed=0,cancelled=0,observed=0
        for scenario in ["success","cancel","successAfterPause"] {
            let e=try F.engine(right:scenario != "successAfterPause",residents:residents)
            let identities=e.birds.map(ObjectIdentifier.init),background=Array(e.birds.dropFirst())
            let positions=background.map(\.position),hosts=background.map(\.hostID)
            XCTAssertEqual(e.birds.count,residents)
            XCTAssertEqual(e.birds.filter{$0.profile.id == .barnSwallow}.count,1)
            for bird in e.birds {XCTAssertTrue(F.display.contains(e.bounds(of:bird)))}
            for a in e.birds.indices {
                for b in e.birds.indices where b>a {XCTAssertFalse(e.bounds(of:e.birds[a]).intersects(e.bounds(of:e.birds[b])))}
            }
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            let (run,x)=try F.start(e),id=try XCTUnwrap(e.insectSnapshot()).id
            var peakRuns=0,peakLeases=0,peakInsects=0,samples=0
            func sample() {
                samples+=1
                XCTAssertEqual(e.residentCount,residents);XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
                XCTAssertEqual(background.map(\.position),positions);XCTAssertEqual(background.map(\.hostID),hosts)
                XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                XCTAssertEqual(e.passingCount,0);XCTAssertEqual(e.pendingCount,0)
                XCTAssertLessThanOrEqual(e.activeRunCount,1);XCTAssertLessThanOrEqual(e.leasedBirdCount,1)
                XCTAssertLessThanOrEqual(e.reservedLandingCount,1);XCTAssertEqual(e.habitatReservationCount,0)
                XCTAssertNil(e.sceneFocus);XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
                XCTAssertLessThanOrEqual(e.propSnapshot().count,1)
                peakRuns=max(peakRuns,e.activeRunCount);peakLeases=max(peakLeases,e.leasedBirdCount)
                peakInsects=max(peakInsects,e.insectSnapshot()==nil ? 0:1)
                if let insect=e.insectSnapshot() {
                    XCTAssertEqual(insect.id,id);XCTAssertEqual(insect.trajectory,x.plan.trajectory)
                    XCTAssertEqual(e.propSnapshot().map(\.id),[id])
                    XCTAssertEqual(e.propSnapshot().map(\.kind),[.insect])
                }
            }
            sample();F.advance(e,0.05);sample()
            e.handle(.pause(true))
            let before=BehaviorReplayReport(engine:e,events:[]),age=e.runtime.runs[run]?.age
            F.advance(e,2);sample()
            let frozen=BehaviorReplayReport(engine:e,events:[])
            XCTAssertEqual(frozen.birds,before.birds);XCTAssertEqual(frozen.insect,before.insect)
            XCTAssertEqual(frozen.props,before.props);XCTAssertEqual(e.runtime.runs[run]?.age,age)
            XCTAssertEqual(frozen.insectCooldownRemaining,before.insectCooldownRemaining)
            e.handle(.pause(false))
            if scenario == "cancel" {
                let insect=try XCTUnwrap(e.insectSnapshot())
                e.handle(.pointerClick);F.released(e,run)
                XCTAssertEqual(F.terminals(e,run).map(\.type),[.cancelled]);cancelled+=1
                XCTAssertEqual(e.insectSnapshot()?.id,id);XCTAssertEqual(e.insectSnapshot()?.age,insect.age)
                XCTAssertEqual(e.insectSnapshot()?.trajectory,insect.trajectory)
                for _ in 0..<13*60 {e.advance(BehaviorEngine.step);sample()}
                XCTAssertTrue(observations.isEmpty);XCTAssertNil(e.lastInsectContact)
            } else {
                for _ in 0..<35*60+2 {
                    guard e.runtime.runs[run] != nil else {break}
                    e.advance(BehaviorEngine.step);sample()
                }
                F.released(e,run)
                XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed]);completed+=1
                XCTAssertEqual(e.lastInsectContact?.insectID,id);XCTAssertNil(e.insectSnapshot())
                XCTAssertEqual(observations.count,1);observed+=observations.count
                XCTAssertFalse(e.birds[0].isCoordinatedFlying);XCTAssertFalse(e.birds[0].needsDestination)
                F.advance(e,30);sample()
                XCTAssertEqual(e.birds[0].state,.perched)
            }
            XCTAssertEqual([peakRuns,peakLeases,peakInsects],[1,1,1]);XCTAssertGreaterThan(samples,0)
            XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertTrue(e.runtime.propIDs.isEmpty);XCTAssertNil(e.sceneFocus);XCTAssertFalse(e.ambientBusy)
            XCTAssertEqual(e.insectMissedTargetCount,0);XCTAssertFalse(e.hasInsectCatchPreview)
            XCTAssertEqual(e.events.filter{$0.kind == .insectCatch && $0.type == .started}.count,1)
            XCTAssertFalse(e.events.contains{$0.type == .failed || $0.type == .rejected})
            XCTAssertEqual(F.terminals(e,run).count,1)
            e.handle(.cancelAmbient(.sleep));sample()
            for bird in e.birds {if let id=e.id(of:bird) {e.handle(.remove(id))}}
            XCTAssertTrue(e.birds.isEmpty);XCTAssertEqual(e.residentCount,0)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
            XCTAssertNil(e.sceneFocus);XCTAssertTrue(e.perchPlanner.rhythms.isEmpty)
        }
        XCTAssertEqual(completed,2);XCTAssertEqual(cancelled,1);XCTAssertEqual(observed,2)
    }
}
