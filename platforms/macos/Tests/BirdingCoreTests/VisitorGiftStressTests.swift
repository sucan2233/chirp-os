import XCTest
@testable import BirdingCore

/// Bounded core workloads with real residents, authorization and motion. This
/// does not claim renderer performance or a long-running desktop benchmark.
final class VisitorGiftStressTests:XCTestCase {
    private typealias F=VisitorGiftTestSupport
    func testTwentyFourResidentsCompleteTwoGiftsAndOneAttachedCancellation() throws {try exercise(24)}
    func testSixtyFourResidentsCompleteTwoGiftsAndOneAttachedCancellation() throws {try exercise(64)}

    private func exercise(_ residents:Int) throws {
        let e=try F.engine(residents:residents),carrier=e.birds[0],carrierID=try XCTUnwrap(e.id(of:carrier))
        let identities=e.birds.map(ObjectIdentifier.init),background=Array(e.birds.dropFirst())
        let feet=background.map(\.position),hosts=background.map(\.hostID)
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        var allocated=Set<ScenePropID>(),attached=Set<ScenePropID>(),delivered=Set<ScenePropID>()
        var runs:[BehaviorRunID]=[],expectedID:ScenePropID?,peakRuns=0,peakObjects=0
        for bird in e.birds {
            XCTAssertTrue(F.display().contains(e.renderSnapshot().first{$0.id==e.id(of:bird)}!.rect))
            XCTAssertTrue(Geometry.isLandingVisible(on:try XCTUnwrap(bird.hostID),at:bird.position,
                surfaces:e.world.surfaces,scale:e.spriteScale(for:bird)))
        }
        for a in e.birds.indices {
            for b in e.birds.indices where b>a {XCTAssertFalse(e.bounds(of:e.birds[a]).intersects(e.bounds(of:e.birds[b])))}
        }
        func sample() {
            XCTAssertEqual(e.residentCount,residents);XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
            XCTAssertEqual(background.map(\.position),feet);XCTAssertEqual(background.map(\.hostID),hosts)
            XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
            XCTAssertEqual(e.passingCount,0);XCTAssertEqual(e.pendingCount,0)
            XCTAssertEqual(e.perchPlanner.rhythms.count,residents)
            XCTAssertLessThanOrEqual(e.activeRunCount,1);XCTAssertLessThanOrEqual(e.leasedBirdCount,1)
            XCTAssertLessThanOrEqual(e.reservedLandingCount,2);XCTAssertLessThanOrEqual(e.activeGiftAuthorizationCount,1)
            XCTAssertLessThanOrEqual(e.runtime.giftReceiverReservations.count,1)
            XCTAssertEqual(e.habitatReservationCount,0)
            let objects=e.carriedObjectSnapshot(),tokens=e.propSnapshot().filter{$0.kind == .leafToken}
            XCTAssertLessThanOrEqual(objects.count,1);XCTAssertEqual(tokens.map(\.id),objects.map(\.id))
            XCTAssertEqual(e.scenePropCount,objects.count)
            peakRuns=max(peakRuns,e.activeRunCount);peakObjects=max(peakObjects,objects.count)
            if let object=objects.first {
                XCTAssertEqual(object.id,expectedID)
                if object.state == .attached {
                    attached.insert(object.id);XCTAssertEqual(object.owner,carrierID)
                    XCTAssertEqual(object.remainingLifetime,0);XCTAssertEqual(object.reservedByRun,e.runtime.owners[carrierID])
                }
                if object.giftDelivery?.arrived==true {delivered.insert(object.id)}
            }
        }
        func advance(_ seconds:Double) {
            for tick in 0..<Int((seconds*60).rounded()) {e.advance(BehaviorEngine.step);if tick%6==0 {sample()}}
            sample()
        }
        func clean() {
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.habitatReservationCount,0)
            XCTAssertEqual(e.activeGiftAuthorizationCount,0);XCTAssertNil(e.giftAuthorizationRequest)
            XCTAssertTrue(e.runtime.propIDs.isEmpty);XCTAssertTrue(e.runtime.giftReceiverReservations.isEmpty)
            XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertTrue(e.propSnapshot().isEmpty)
            XCTAssertTrue(e.giftObstacleRects().isEmpty);XCTAssertNil(e.sceneFocus);XCTAssertFalse(e.ambientBusy)
            sample();expectedID=nil
        }
        for iteration in 0..<3 {
            for _ in 0..<30*60 {
                if carrier.state == .perched,carrier.stateTime>=1,e.runtime.owners[carrierID]==nil,
                   abs(e.baseHop(for:carrierID,bird:carrier))<0.001 {break}
                e.advance(BehaviorEngine.step)
            }
            XCTAssertEqual(carrier.state,.perched)
            XCTAssertTrue(e.handle(.placeCarryLeaf(at:CGPoint(x:iteration==1 ? 1400:1000,y:1700))).accepted)
            let object=try XCTUnwrap(e.carriedObjectSnapshot().first);expectedID=object.id
            XCTAssertTrue(allocated.insert(object.id).inserted)
            let (run,_)=try F.authorize(e,tokenID:UUID(uuidString:"00000000-0000-4000-8000-00000000007\(iteration)")!)
            runs.append(run)
            for _ in 0..<35*60 {
                if e.carriedObjectSnapshot().first?.state == .attached {break}
                guard e.runtime.runs[run] != nil else {break}
                e.advance(BehaviorEngine.step);sample()
            }
            XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.attached);sample()
            e.handle(.pause(true))
            let before=BehaviorReplayReport(engine:e,events:[]),age=e.runtime.runs[run]?.age
            advance(2)
            let after=BehaviorReplayReport(engine:e,events:[])
            XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(after.props,before.props)
            XCTAssertEqual(after.carriedObjects,before.carriedObjects);XCTAssertEqual(e.runtime.runs[run]?.age,age)
            e.handle(.pause(false))
            if iteration==1 {
                e.handle(.pointerClick)
                XCTAssertEqual(F.terminals(e,run).map(\.type),[.cancelled])
                advance(0.3);F.released(e,run);clean()
                XCTAssertEqual(observations.count,1)
            } else {
                for _ in 0..<35*60 {if e.runtime.runs[run]==nil {break};e.advance(BehaviorEngine.step);sample()}
                F.released(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
                let gift=try XCTUnwrap(e.carriedObjectSnapshot().first)
                XCTAssertEqual(gift.id,object.id);XCTAssertTrue(try XCTUnwrap(gift.giftDelivery).arrived)
                XCTAssertNil(gift.owner);XCTAssertNil(gift.reservedByRun)
                if iteration==0 {advance(gift.remainingLifetime+0.3)}
                else {e.handle(.clearVisitorGift)}
                clean()
            }
        }
        XCTAssertEqual(allocated.count,3);XCTAssertEqual(attached,allocated);XCTAssertEqual(delivered.count,2)
        XCTAssertEqual(observations.map(\.kind),[.visitorGift,.visitorGift])
        XCTAssertEqual(observations.map(\.source),[.preview,.preview])
        XCTAssertEqual(runs.flatMap{F.terminals(e,$0)}.filter{$0.type == .completed}.count,2)
        XCTAssertEqual(runs.flatMap{F.terminals(e,$0)}.filter{$0.type == .cancelled}.count,1)
        XCTAssertEqual([peakRuns,peakObjects],[1,1])
        XCTAssertFalse(e.events.contains{$0.type == .failed || $0.type == .rejected})
        e.handle(.cancelAmbient(.sleep));clean()
        for id in e.birds.compactMap({e.id(of:$0)}) {e.handle(.remove(id))}
        XCTAssertEqual(e.residentCount,0);XCTAssertTrue(e.birds.isEmpty)
        XCTAssertEqual(e.activeVisitorCount,0);XCTAssertTrue(e.perchPlanner.rhythms.isEmpty)
        XCTAssertEqual(e.scenePropCount,0);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
    }
}
