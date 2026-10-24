import XCTest
@testable import BirdingCore

final class NestRuntimeBoundaryTests:XCTestCase {
    private typealias F=NestTestSupport
    /// A Runtime unit probe, deliberately not a simulated real visit. The real
    /// visits test their physical routes, commits and terminal recovery elsewhere.
    private final class Probe:BehaviorExecution {
        let kind:BehaviorKind
        let participants:[BirdID]
        let timeout:Double
        var steps:[Double]=[]
        init(_ id:BirdID,build:Bool) {participants=[id];kind=build ? .nestBuild:.nestMaterialCarry;timeout=build ? 30:35}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine)->BehaviorCompletion? {steps.append(dt);return nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }

    func testRuntimeClipsBothLastMotionStepsAndLeavesAfterMotionDecisionToTheCaller() throws {
        for build in [false,true] {
            let e=F.engine(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird)),probe=Probe(id,build:build),feet=bird.position
            guard case .started(let run)=e.runtime.start(probe,source:.preview,in:e) else {return XCTFail("Probe must acquire the real Runtime lease")}
            e.runtime.advance(probe.timeout-0.01,in:e);e.runtime.advance(BehaviorEngine.step,in:e)
            let state=try XCTUnwrap(e.runtime.runs[run])
            XCTAssertEqual(state.age,probe.timeout,accuracy:1e-12)
            XCTAssertEqual(try XCTUnwrap(state.motionDT),0.01,accuracy:1e-12)
            XCTAssertEqual(try XCTUnwrap(probe.steps.last),0.01,accuracy:1e-12)
            XCTAssertTrue(F.terminals(e,run).isEmpty,"Only the caller may decide the terminal result after clipped physical motion")
            e.runtime.advance(BehaviorEngine.step,in:e)
            XCTAssertEqual(try XCTUnwrap(e.runtime.runs[run]).motionDT,0)
            XCTAssertEqual(probe.steps.reduce(0,+),probe.timeout,accuracy:1e-12);XCTAssertEqual(bird.position,feet)
            e.runtime.cancel(run,reason:.removed,in:e);F.released(e,run)
        }
    }

    func testInsufficientActualRemainingLifetimeRejectsBeforeLeasingOrConsumingEitherMaterial() throws {
        for build in [false,true] {
            let e=try F.prepared();if build {_=try F.deliver(e)}
            let remaining=try F.nest(e).remainingLifetime
            F.advance(e,remaining-0.5)
            let before=try F.nest(e),feet=e.birds[0].position
            XCTAssertEqual(before.remainingLifetime,0.5,accuracy:0.01)
            XCTAssertEqual(e.handle(build ? .nestBuild(.preview):.nestMaterialCarry(.preview)),.rejected(.noSpace))
            XCTAssertEqual(try F.nest(e),before);XCTAssertEqual(e.birds[0].position,feet)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertNil(before.reservation)
            F.clear(e)
        }
    }
}
