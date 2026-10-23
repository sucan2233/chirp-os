import XCTest
@testable import BirdingCore

final class BehaviorStressTests: XCTestCase {
    func testConfigurationRejectsNonfiniteAndOutOfBoundsBeforeRunning() throws {
        for seconds in [Double.nan, .infinity, -.infinity, -1, 0, 0.999, 3600.001, .greatestFiniteMagnitude] {
            XCTAssertThrowsError(try BehaviorStress.run(configuration:.init(seconds:seconds))) {
                XCTAssertEqual($0 as? BehaviorStress.ConfigurationError,.seconds)
            }
        }
        for birds in [Int.min,0,65,Int.max] {
            XCTAssertThrowsError(try BehaviorStress.run(configuration:.init(seconds:1,birds:birds))) {
                XCTAssertEqual($0 as? BehaviorStress.ConfigurationError,.birds)
            }
        }
        for displays in [Int.min,0,5,Int.max] {
            XCTAssertThrowsError(try BehaviorStress.run(configuration:.init(seconds:1,displays:displays))) {
                XCTAssertEqual($0 as? BehaviorStress.ConfigurationError,.displays)
            }
        }
        try BehaviorStress.Configuration(seconds:1,birds:1,displays:1,seed:0).validate()
        try BehaviorStress.Configuration(seconds:3600,birds:64,displays:4,seed:UInt64.max).validate()
        XCTAssertEqual(BehaviorStress.Configuration(),.init(seconds:600,birds:24,displays:2,seed:73))
    }

    func testShortestFractionalWorkloadHasRealCompletionsAndRemovesEcology() throws {
        let report=try BehaviorStress.run(configuration:.init(seconds:1.025,birds:1,displays:1,seed:73))
        assertPassed(report)
        XCTAssertEqual(report.workload.activeSteps,62)
        XCTAssertGreaterThan(report.metrics.startedRuns,0)
        XCTAssertGreaterThan(report.metrics.completedRuns,0)
        XCTAssertGreaterThan(report.metrics.completedByKind["preen",default:0],0)
        XCTAssertGreaterThan(report.metrics.startedByKind["leafPlay",default:0],0)
        XCTAssertGreaterThan(report.metrics.drainCompletions,0)
        XCTAssertGreaterThan(report.metrics.successfulPreviews,0)
        XCTAssertEqual(report.cleanup.residentsBeforeRemoval,1)
        XCTAssertEqual(report.cleanup.explicitlyRemovedBirds,1)
        XCTAssertEqual(report.cleanup.ecologyMemories,0)
        XCTAssertEqual(report.metrics.repeatedRemovalChecks,1)
        XCTAssertEqual(report.metrics.startedRuns,report.metrics.completedRuns+report.metrics.cancelledRuns+report.metrics.failedRuns)
        XCTAssertEqual(report.metrics.explicitCleanupCancellations,report.cleanup.explicitlyCancelledRuns)
        XCTAssertEqual(report.cleanup.naturallyCompletedDuringDrain,report.metrics.drainCompletions)
    }

    func testSeedReplayMatchesAllDeterministicMetricsAcrossRepeatedHostAndBirdRemovals() throws {
        let config=BehaviorStress.Configuration(seconds:220,birds:8,displays:2,seed:73)
        let a=try BehaviorStress.run(configuration:config), b=try BehaviorStress.run(configuration:config)
        assertPassed(a); assertPassed(b)
        XCTAssertEqual(a.configuration,b.configuration)
        XCTAssertEqual(a.workload,b.workload)
        XCTAssertEqual(a.metrics,b.metrics)
        XCTAssertEqual(a.failures,b.failures)
        XCTAssertEqual(a.peaks,b.peaks)
        XCTAssertEqual(a.integrity,b.integrity)
        XCTAssertEqual(a.cleanup,b.cleanup)
        XCTAssertEqual(a.metrics.hostRemovalTransitions,2)
        XCTAssertEqual(a.metrics.residentRemovals,2)
        XCTAssertEqual(a.metrics.replacementBirds,2)
        XCTAssertEqual(a.metrics.repeatedRemovalChecks,2+a.cleanup.explicitlyRemovedBirds)
        XCTAssertGreaterThan(a.metrics.pointerSweepSamples,0)
        XCTAssertGreaterThanOrEqual(a.metrics.pauseTransitions,4)
        XCTAssertGreaterThanOrEqual(a.metrics.settingsChanges,4)
        XCTAssertGreaterThanOrEqual(a.metrics.lifecycleCancellations,8)
        XCTAssertGreaterThan(a.metrics.startedByKind["socialGreeting",default:0],0)
        XCTAssertGreaterThan(a.metrics.startedByKind["sideBySide",default:0],0)
        XCTAssertGreaterThan(a.metrics.startedByKind["sideHop",default:0],0)
        XCTAssertGreaterThan(a.metrics.startedByKind["flockPass",default:0],0)
        XCTAssertGreaterThan(a.metrics.events,a.metrics.startedRuns)
        XCTAssertEqual(a.peaks.events,min(256,a.metrics.events))
        XCTAssertGreaterThan(a.peaks.props,0)
        XCTAssertGreaterThan(a.peaks.reservations,0)
        XCTAssertEqual(a.timings.active["advance"]?.calls,a.workload.activeSteps)
        XCTAssertEqual(a.timings.active["advance"]?.sampledCalls,a.workload.timingSampleLimit)
        // All wall-clock values are deliberately excluded from replay equality.
        assertTimings(a); assertTimings(b)
    }

    func testMaximumBirdAndDisplayConfigurationStaysBoundedAndCodable() throws {
        let report=try BehaviorStress.run(configuration:.init(seconds:1,birds:64,displays:4,seed:UInt64.max))
        assertPassed(report)
        XCTAssertEqual(report.cleanup.explicitlyRemovedBirds,64)
        XCTAssertEqual(report.cleanup.ecologyMemories,0)
        XCTAssertEqual(report.peaks.ecologyMemories,64)
        XCTAssertLessThanOrEqual(report.peaks.birds,69)
        let data=try JSONEncoder().encode(report)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(object["passed"] as? Bool,true)
        let decoded=try JSONDecoder().decode(BehaviorStress.Report.self,from:data)
        XCTAssertTrue(decoded.passed)
        XCTAssertEqual(decoded.metrics,report.metrics)
        XCTAssertEqual(decoded.failures,report.failures)
        XCTAssertEqual(decoded.cleanup,report.cleanup)
        var legacy=object;legacy.removeValue(forKey:"failures")
        let legacyReport=try JSONDecoder().decode(BehaviorStress.Report.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertTrue(legacyReport.failures.samples.isEmpty)
        XCTAssertEqual(legacyReport.metrics,report.metrics)
        assertTimings(report)
    }

    func testSustainedAutonomyChoosesAndCompletesActionsAcrossInterruptions() throws {
        let configuration=BehaviorStress.Configuration(seconds:240,birds:12,displays:2,seed:73,autonomous:true)
        let report=try BehaviorStress.run(configuration:configuration)
        assertPassed(report)
        XCTAssertGreaterThan(report.metrics.automaticStartedRuns,0)
        XCTAssertGreaterThan(report.metrics.automaticCompletedRuns,0)
        XCTAssertEqual(report.metrics.residentRemovals,2)
        XCTAssertEqual(report.metrics.hostRemovalTransitions,2)
        XCTAssertEqual(report.integrity.checks["autonomousCoverage"],true)
        let empty=BehaviorStress.Auditor()
        empty.finish(requireAutonomy:true)
        XCTAssertEqual(empty.report.checks["autonomousCoverage"],false)
    }

    func testFailureAttributionSurvivesRingEvictionWithBoundedSamples() throws {
        let auditor=BehaviorStress.Auditor()
        for index in 1...300 {
            let id=BehaviorRunID(rawValue:UInt64(index)),kind:BehaviorKind=index%2==0 ? .edgePeek:.foodTrayVisit
            auditor.observe(BehaviorEvent(sequence:UInt64(index*2-1),time:Double(index),runID:id,
                kind:kind,source:.automatic,type:.started,participants:[BirdID(7)],reason:nil))
            auditor.observe(BehaviorEvent(sequence:UInt64(index*2),time:Double(index)+0.5,runID:id,
                kind:kind,source:.automatic,type:.failed,participants:[BirdID(7)],reason:.targetInvalid))
        }
        XCTAssertEqual(auditor.failures.byBehavior,["edgePeek":150,"foodTrayVisit":150])
        XCTAssertEqual(auditor.failures.samples.count,32)
        XCTAssertEqual(auditor.failures.omittedSamples,268)
        let first=try XCTUnwrap(auditor.failures.samples.first)
        XCTAssertEqual(first.runID,1);XCTAssertEqual(first.simulationTime,1.5)
        XCTAssertEqual(first.behavior,"foodTrayVisit");XCTAssertEqual(first.participants,[7])
        XCTAssertEqual(first.reason,"targetInvalid");XCTAssertEqual(first.source,"automatic")
        let data=try JSONEncoder().encode(auditor.failures)
        XCTAssertEqual(try JSONDecoder().decode(BehaviorStress.FailureDiagnostics.self,from:data),auditor.failures)
    }

    func testDifferentSeedsChangeDeterministicTrace() throws {
        let a=try BehaviorStress.run(configuration:.init(seconds:1,birds:2,displays:1,seed:73))
        let b=try BehaviorStress.run(configuration:.init(seconds:1,birds:2,displays:1,seed:74))
        assertPassed(a); assertPassed(b)
        XCTAssertNotEqual(a.metrics.stateDigest,b.metrics.stateDigest)
    }

    func testAuditorDetectsDuplicateOrOrphanTerminalAndSequenceGap() {
        let auditor=BehaviorStress.Auditor()
        let id=BehaviorRunID(rawValue:1)
        func event(_ sequence:UInt64,_ type:BehaviorEventType) -> BehaviorEvent {
            BehaviorEvent(sequence:sequence,time:0,runID:id,kind:.rest,source:.preview,type:type,participants:[BirdID(1)],reason:nil)
        }
        auditor.observe(event(1,.started)); auditor.observe(event(2,.completed))
        auditor.observe(event(4,.completed)); auditor.finish()
        XCTAssertFalse(auditor.report.passed)
        XCTAssertEqual(auditor.report.violations["runLifecycle"],1)
        XCTAssertEqual(auditor.report.violations["eventSequence"],1)
        XCTAssertEqual(auditor.report.checks["finalRunBalance"],false)
    }

    func testAuditorDetectsNonfiniteFramesAndLeakedEcologyMemory() {
        let engine=fixture(), auditor=BehaviorStress.Auditor(), bird=engine.birds[0]
        let id=engine.id(of:bird)!
        engine.perchPlanner.remove(id)
        bird.position=CGPoint(x:Double.nan,y:400)
        auditor.sample(engine,birds:engine.renderSnapshot(),props:[],birdLimit:1)
        XCTAssertEqual(auditor.report.checks["finitePresentation"],false)
        XCTAssertEqual(auditor.report.checks["ecologyMemory"],false)
        XCTAssertFalse(auditor.report.passed)
    }

    func testAuditorDetectsBypassedRemovalLeavingOwnedMissingBird() {
        let engine=fixture(), auditor=BehaviorStress.Auditor()
        engine.eventObserver={auditor.observe($0)}
        let bird=engine.birds[0], id=engine.id(of:engine.birds[0])!
        guard case .started = engine.handle(.perchAction(.preen,.preview)) else {return XCTFail("Expected actual production preen")}
        engine.removeRecord(id) // Deliberately bypass the public cancellation contract.
        auditor.sample(engine,birds:engine.renderSnapshot(),props:[],birdLimit:1)
        XCTAssertEqual(auditor.report.checks["leaseOwnership"],false)
        XCTAssertNil(engine.ecology(of:bird))
        engine.handle(.cancelAmbient(.shutdown))
    }

    func testAuditorDetectsOrphanPropsAndVacuousWorkload() {
        let engine=fixture(), auditor=BehaviorStress.Auditor()
        let prop=ScenePropRenderState(id:ScenePropID(99),kind:.leaf,position:.zero,size:36,rotation:0,opacity:2,blockers:[])
        auditor.sample(engine,birds:engine.renderSnapshot(),props:[prop,prop],birdLimit:1)
        auditor.finish()
        XCTAssertEqual(auditor.report.checks["propOwnership"],false)
        XCTAssertEqual(auditor.report.checks["finitePresentation"],false)
        XCTAssertEqual(auditor.report.checks["successfulWork"],false)
    }

    func testTimeoutAndMissingActionCoverageFailEvenAfterBalancedTerminal() {
        let auditor=BehaviorStress.Auditor(), id=BehaviorRunID(rawValue:1)
        auditor.observe(BehaviorEvent(sequence:1,time:0,runID:id,kind:.leafPlay,source:.preview,type:.started,participants:[BirdID(1)],reason:nil))
        auditor.observe(BehaviorEvent(sequence:2,time:30,runID:id,kind:.leafPlay,source:.preview,type:.failed,participants:[BirdID(1)],reason:.timedOut))
        auditor.finish(requiredCompletedKinds:["leafPlay"])
        XCTAssertEqual(auditor.metrics.failureReasons["timedOut"],1)
        XCTAssertEqual(auditor.report.checks["finalRunBalance"],true)
        XCTAssertEqual(auditor.report.checks["noTimeouts"],false)
        XCTAssertEqual(auditor.report.checks["actionCoverage"],false)
        XCTAssertFalse(auditor.report.passed)
    }

    func testEventAccountingOutlivesEngineRingBufferWithoutRetainingHistory() {
        let engine=fixture(), auditor=BehaviorStress.Auditor()
        engine.eventObserver={auditor.observe($0)}
        for _ in 0..<300 {engine.handle(.relocate(BirdID(999)))}
        XCTAssertEqual(engine.events.count,256)
        XCTAssertEqual(auditor.metrics.events,300)
        XCTAssertEqual(auditor.report.checks["eventSequence"],true)
    }

    private func fixture() -> BehaviorEngine {
        let engine=BehaviorEngine(seed:73)
        engine.ambientEnabled=false; engine.populationEnabled=false; engine.autonomousRouting=false
        let screen=CGRect(x:0,y:0,width:1600,height:1200)
        let host=Surface(id:1,rect:CGRect(x:100,y:900,width:1400,height:100))
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:800,y:400),
            availableFrames:[.treeSparrow:["stand","blink","preen0","preen1"]]))
        let bird=Bird(position:.zero,fraction:0.5,profile:engine.settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:engine.spriteScale(for:bird)); bird.perchDuration=600
        engine.installFixtureBirds([bird]); return engine
    }
    private func assertPassed(_ report:BehaviorStress.Report,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertTrue(report.passed,"\(report.integrity.violations), cleanup: \(report.cleanup)",file:file,line:line)
        XCTAssertTrue(report.cleanup.drainReachedIdle,file:file,line:line)
        XCTAssertTrue(report.cleanup.passed,file:file,line:line)
        XCTAssertEqual(report.cleanup.activeRuns,0,file:file,line:line)
        XCTAssertEqual(report.cleanup.leases,0,file:file,line:line)
        XCTAssertEqual(report.cleanup.reservations,0,file:file,line:line)
        XCTAssertEqual(report.cleanup.props,0,file:file,line:line)
        XCTAssertEqual(report.cleanup.birds,0,file:file,line:line)
        XCTAssertEqual(report.cleanup.pendingBirds,0,file:file,line:line)
        XCTAssertEqual(report.cleanup.pendingPreviews,0,file:file,line:line)
        XCTAssertEqual(report.cleanup.ecologyMemories,0,file:file,line:line)
    }
    private func assertTimings(_ report:BehaviorStress.Report,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertGreaterThan(report.timings.warmup["advance"]?.calls ?? 0,0,file:file,line:line)
        XCTAssertGreaterThan(report.timings.active["worldSampling"]?.calls ?? 0,0,file:file,line:line)
        XCTAssertGreaterThan(report.timings.active["worldUpdate"]?.calls ?? 0,0,file:file,line:line)
        for timings in [report.timings.warmup,report.timings.active,report.timings.drain,report.timings.cleanup] {
            for value in timings.values {
                XCTAssertGreaterThan(value.calls,0,file:file,line:line)
                XCTAssertLessThanOrEqual(value.sampledCalls,report.workload.timingSampleLimit,file:file,line:line)
                XCTAssertLessThanOrEqual(value.sampledCalls,value.calls,file:file,line:line)
                let quantiles=[value.p50Milliseconds,value.p95Milliseconds,value.p99Milliseconds,value.maxMilliseconds]
                XCTAssertTrue(quantiles.allSatisfy{$0.isFinite && $0>=0},file:file,line:line)
                XCTAssertEqual(quantiles,quantiles.sorted(),file:file,line:line)
            }
        }
    }
}
