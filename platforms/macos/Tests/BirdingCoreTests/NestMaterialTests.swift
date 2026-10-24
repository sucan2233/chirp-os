import XCTest
@testable import BirdingCore

final class NestMaterialTests:XCTestCase {
    private typealias F=NestTestSupport

    func testRealPickupAndDeliveryCommitsAreIdempotentAndBoundToOneMaterialRunAndBird() throws {
        let e=try F.prepared(),run=try F.start(e)
        let execution=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestMaterialCarryExecution)
        let plan=execution.plan,object=plan.objectID,material=plan.materialID,bird=plan.id
        let wrongRun=BehaviorRunID(rawValue:run.rawValue+1000),wrongBird=BirdID(bird.rawValue+1000)
        let other=try XCTUnwrap(try F.nest(e).materials.first{$0.id != material}).id
        let reserved=e.nestSnapshot().map(RecordedNestState.init)
        XCTAssertTrue(e.habitatObjects.reserveNestMaterial(object,materialID:material,runID:run,birdID:bird,purpose:.carry))
        XCTAssertFalse(e.habitatObjects.reserveNestMaterial(object,materialID:other,runID:run,birdID:bird,purpose:.carry))
        XCTAssertFalse(e.habitatObjects.reserveNestMaterial(object,materialID:material,runID:wrongRun,birdID:bird,purpose:.carry))
        XCTAssertFalse(e.habitatObjects.releaseNestMaterial(object,materialID:material,runID:run,birdID:wrongBird))
        XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),reserved)

        try F.until(e,run) {execution.pickedUp}
        let contact=try XCTUnwrap(F.tokens(e).first{$0.id==material})
        let picked=e.nestSnapshot().map(RecordedNestState.init)
        for _ in 0..<3 {
            XCTAssertTrue(e.habitatObjects.pickupNestMaterial(object,materialID:material,runID:run,birdID:bird,contact:contact))
        }
        XCTAssertFalse(e.habitatObjects.pickupNestMaterial(object,materialID:material,runID:wrongRun,birdID:bird,contact:contact))
        XCTAssertFalse(e.habitatObjects.pickupNestMaterial(object,materialID:material,runID:run,birdID:wrongBird,contact:contact))
        XCTAssertFalse(e.habitatObjects.pickupNestMaterial(object,materialID:other,runID:run,birdID:bird,contact:contact))
        XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),picked)
        XCTAssertEqual(try F.nest(e).available,2);XCTAssertEqual(try F.nest(e).attached,1)

        try F.until(e,run) {execution.delivered}
        let model=try XCTUnwrap(e.bird(bird)),direction:CGFloat=plan.facingRight ? 1:-1
        let bill=CGPoint(x:model.position.x+direction*11*e.spriteScale(for:model),y:model.position.y)
        let release=NestGeometry.render(id:material,position:bill,worldScale:e.world.scale,facingRight:plan.facingRight)
        let delivered=e.nestSnapshot().map(RecordedNestState.init)
        for _ in 0..<3 {
            XCTAssertTrue(e.habitatObjects.deliverNestMaterial(object,materialID:material,runID:run,birdID:bird,contact:release))
            XCTAssertTrue(e.habitatObjects.pickupNestMaterial(object,materialID:material,runID:run,birdID:bird,contact:contact))
        }
        XCTAssertFalse(e.habitatObjects.deliverNestMaterial(object,materialID:material,runID:wrongRun,birdID:bird,contact:release))
        XCTAssertFalse(e.habitatObjects.deliverNestMaterial(object,materialID:material,runID:run,birdID:wrongBird,contact:release))
        XCTAssertFalse(e.habitatObjects.reserveNestMaterial(object,materialID:material,runID:run,birdID:bird,purpose:.build))
        XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),delivered)
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
    }

    func testRealArrangementCommitReplaysExactlyOnceAndCannotUseTheTransportRunOrAnotherBird() throws {
        let e=try F.prepared(),carry=try F.deliver(e),run=try F.start(e,build:true)
        let execution=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestBuildExecution),plan=execution.plan
        let object=plan.objectID,material=plan.materialID,bird=plan.id
        let before=e.nestSnapshot().map(RecordedNestState.init)
        XCTAssertFalse(e.habitatObjects.arrangeNestMaterial(object,materialID:material,runID:carry,birdID:bird))
        XCTAssertFalse(e.habitatObjects.arrangeNestMaterial(object,materialID:material,runID:run,birdID:BirdID(bird.rawValue+1)))
        XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),before)
        try F.until(e,run) {execution.arranged}
        let arranged=e.nestSnapshot().map(RecordedNestState.init)
        for _ in 0..<4 {
            XCTAssertTrue(e.habitatObjects.arrangeNestMaterial(object,materialID:material,runID:run,birdID:bird))
        }
        XCTAssertFalse(e.habitatObjects.arrangeNestMaterial(object,materialID:material,runID:carry,birdID:bird))
        XCTAssertFalse(e.habitatObjects.arrangeNestMaterial(object,materialID:material,runID:run,birdID:BirdID(bird.rawValue+1)))
        XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),arranged)
        XCTAssertEqual(try F.nest(e).progress,1);XCTAssertEqual(try F.nest(e).available,2)
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        XCTAssertFalse(e.habitatObjects.reserveNestMaterial(object,materialID:material,runID:run,birdID:bird,purpose:.build))
        F.clear(e)
    }
}
