import XCTest
@testable import BirdingCore

/// Bounded real resident loads, independent of the existing performance baseline.
final class FlycatcherInsectCatchStressTests:XCTestCase {
    private typealias F=FlycatcherInsectCatchTestSupport
    private typealias Common=InsectCatchTestSupport
    func testTwentyFourResidentsActuallyCompleteTwoHitsAndOneCancellation() throws {try exercise(24)}
    func testSixtyFourResidentsActuallyCompleteTwoHitsAndOneCancellation() throws {try exercise(64)}

    private func exercise(_ count:Int)throws {
        var hits=0,cancels=0,observed=0
        for scenario in ["hit","cancel","pausedHit"] {
            let e=try F.engine(right:scenario != "pausedHit",residents:count)
            let carrier=try XCTUnwrap(e.birds.first),originalFoot=carrier.position
            let identities=e.birds.map(ObjectIdentifier.init),background=Array(e.birds.dropFirst())
            let feet=background.map(\.position),hosts=background.map(\.hostID)
            XCTAssertEqual(e.residentCount,count);XCTAssertEqual(e.birds.filter{$0.profile.id==F.species}.count,1)
            for bird in e.birds {XCTAssertTrue(F.display.contains(e.bounds(of:bird)))}
            for a in e.birds.indices {for b in e.birds.indices where b>a {
                XCTAssertFalse(e.bounds(of:e.birds[a]).intersects(e.bounds(of:e.birds[b])))
            }}
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            let (run,x)=try F.start(e),entity=try XCTUnwrap(e.insectSnapshot())
            var sawRun=false,sawInsect=false,samples=0
            func sample() {
                samples+=1
                XCTAssertEqual(e.residentCount,count);XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
                XCTAssertEqual(background.map(\.position),feet);XCTAssertEqual(background.map(\.hostID),hosts)
                XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                XCTAssertEqual(e.pendingCount,0);XCTAssertEqual(e.passingCount,0)
                XCTAssertLessThanOrEqual(e.activeRunCount,1);XCTAssertLessThanOrEqual(e.leasedBirdCount,1)
                XCTAssertLessThanOrEqual(e.reservedLandingCount,1);XCTAssertEqual(e.habitatReservationCount,0)
                XCTAssertLessThanOrEqual(e.propSnapshot().count,1);XCTAssertNil(e.sceneFocus)
                sawRun = sawRun || e.activeRunCount==1;sawInsect = sawInsect || e.insectSnapshot() != nil
                if let insect=e.insectSnapshot() {
                    XCTAssertEqual(insect.id,entity.id);XCTAssertEqual(insect.trajectory,entity.trajectory)
                    XCTAssertEqual(insect.position,entity.trajectory.position(at:insect.age))
                    XCTAssertEqual(e.propSnapshot().map(\.id),[entity.id])
                }
            }
            sample();F.advance(e,0.05);sample()
            e.handle(.pause(true));let before=BehaviorReplayReport(engine:e,events:[]),age=e.runtime.runs[run]?.age
            F.advance(e,2);sample()
            let after=BehaviorReplayReport(engine:e,events:[])
            XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(after.insect,before.insect)
            XCTAssertEqual(after.props,before.props);XCTAssertEqual(after.insectCooldownRemaining,before.insectCooldownRemaining)
            XCTAssertEqual(e.runtime.runs[run]?.age,age);e.handle(.pause(false))
            if scenario == "cancel" {
                let target=try XCTUnwrap(e.insectSnapshot())
                e.handle(.pointerClick);F.released(e,run)
                XCTAssertEqual(Common.terminals(e,run).map(\.type),[.cancelled]);cancels+=1
                XCTAssertEqual(e.insectSnapshot()?.id,target.id);XCTAssertEqual(e.insectSnapshot()?.age,target.age)
                for _ in 0..<13*60 {e.advance(BehaviorEngine.step);sample()}
                XCTAssertTrue(observations.isEmpty);XCTAssertFalse(x.captured);XCTAssertNil(e.lastInsectContact)
            } else {
                for _ in 0..<25*60+2 {
                    if e.runtime.runs[run]==nil {break}
                    e.advance(BehaviorEngine.step);sample()
                }
                F.released(e,run);XCTAssertEqual(Common.terminals(e,run).map(\.type),[.completed]);hits+=1
                XCTAssertTrue(x.captured);XCTAssertEqual(e.lastInsectContact?.insectID,entity.id)
                XCTAssertEqual(carrier.state,.perched);XCTAssertEqual(carrier.position,originalFoot)
                XCTAssertEqual(observations.count,1);observed+=observations.count
                XCTAssertEqual(observations.first?.species,[F.species])
            }
            XCTAssertTrue(sawRun);XCTAssertTrue(sawInsect);XCTAssertGreaterThan(samples,0)
            XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertTrue(e.runtime.propIDs.isEmpty);XCTAssertNil(e.sceneFocus);XCTAssertFalse(e.ambientBusy)
            XCTAssertEqual(e.insectMissedTargetCount,0);XCTAssertFalse(e.hasInsectCatchPreview)
            XCTAssertEqual(e.events.filter{$0.kind == .insectCatch && $0.type == .started}.count,1)
            XCTAssertFalse(e.events.contains{$0.type == .failed || $0.type == .rejected})
            e.handle(.cancelAmbient(.sleep));sample()
            for bird in e.birds {e.handle(.remove(try XCTUnwrap(e.id(of:bird))))}
            XCTAssertTrue(e.birds.isEmpty);XCTAssertEqual(e.residentCount,0)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty);XCTAssertTrue(e.perchPlanner.rhythms.isEmpty)
        }
        XCTAssertEqual(hits,2);XCTAssertEqual(cancels,1);XCTAssertEqual(observed,2)
    }
}
