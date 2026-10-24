import XCTest
@testable import BirdingCore

final class InsectCatchRuntimeBoundaryTests:XCTestCase {
    /// Runtime-only evidence. Engine dispatches its after-motion resolver by
    /// concrete execution type, so this probe deliberately never advances Engine
    /// and does not claim to reproduce a real catch reaching its35s timeout.
    private final class AfterMotionProbe:BehaviorExecution {
        let kind:BehaviorKind = .insectCatch
        let participants:[BirdID]
        let timeout=35.0
        var steps:[Double]=[]
        init(_ bird:BirdID) {participants=[bird]}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine)->BehaviorCompletion? {steps.append(dt);return nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }

    func testRuntimeClipsOnlyTheFinalAfterMotionStepAndDefersTerminalDecisionToItsCaller() throws {
        let e=try InsectCatchTestSupport.engine(),bird=try XCTUnwrap(e.birds.first)
        let id=try XCTUnwrap(e.id(of:bird)),probe=AfterMotionProbe(id),foot=bird.position
        guard case .started(let run)=e.runtime.start(probe,source:.preview,in:e) else {return XCTFail("The unit probe must acquire its ordinary runtime lease")}
        e.runtime.advance(35-0.01,in:e)
        XCTAssertEqual(try XCTUnwrap(e.runtime.runs[run]).age,34.99,accuracy:1e-12)
        e.runtime.advance(BehaviorEngine.step,in:e)
        XCTAssertEqual(try XCTUnwrap(e.runtime.runs[run]).age,35,accuracy:1e-12)
        XCTAssertEqual(try XCTUnwrap(try XCTUnwrap(e.runtime.runs[run]).motionDT),0.01,accuracy:1e-12)
        XCTAssertEqual(try XCTUnwrap(probe.steps.last),0.01,accuracy:1e-12)
        XCTAssertTrue(InsectCatchTestSupport.terminals(e,run).isEmpty,
            "Contact before this deadline must be resolved after the caller integrates the clipped motion")
        e.runtime.advance(BehaviorEngine.step,in:e)
        XCTAssertEqual(try XCTUnwrap(e.runtime.runs[run]).motionDT,0)
        XCTAssertEqual(probe.steps.reduce(0,+),35,accuracy:1e-12)
        XCTAssertEqual(bird.position,foot,"This unit test never integrates physical catch motion")
        XCTAssertNil(e.insectSnapshot());XCTAssertNil(e.lastInsectContact)
        e.runtime.cancel(run,reason:.removed,in:e)
        InsectCatchTestSupport.released(e,run)
        XCTAssertEqual(InsectCatchTestSupport.terminals(e,run).map(\.type),[.cancelled])
    }
}
