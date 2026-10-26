import XCTest
@testable import BirdingCore

final class FlycatcherInsectCatchLifecycleTests:XCTestCase {
    private typealias F=FlycatcherInsectCatchTestSupport
    private typealias Common=InsectCatchTestSupport

    private func reach(_ phase:String,_ e:BehaviorEngine,_ run:BehaviorRunID,_ x:FlycatcherInsectCatchExecution)throws {
        switch phase {
        case "entry":F.advance(e,0.05)
        case "open":F.advance(e,x.plan.interceptionWindow.lowerBound+0.02)
        case "recovery":try F.reachContact(e,run)
        case "return":F.advance(e,x.plan.route.legs[0].timing.duration+0.1)
        default:
            for _ in 0..<25*60 {
                if e.bird(x.plan.id)?.state == .landing {break}
                if e.runtime.runs[run]==nil {break}
                e.advance(BehaviorEngine.step)
            }
            XCTAssertEqual(e.bird(x.plan.id)?.state,.landing)
        }
        XCTAssertNotNil(e.runtime.runs[run],phase)
    }

    func testPauseFreezesEntryOpenRecoveryReturnAndLandingThenCompletesOnlyOnce() throws {
        for phase in ["entry","open","recovery","return","landing"] {
            let e=try F.engine(),(run,x)=try F.start(e)
            try reach(phase,e,run,x);e.handle(.pause(true))
            let before=BehaviorReplayReport(engine:e,events:[]),age=e.runtime.runs[run]?.age
            let flight=e.bird(x.plan.id)?.coordinatedFlightAge
            F.advance(e,2)
            let after=BehaviorReplayReport(engine:e,events:[])
            XCTAssertTrue(after.paused);XCTAssertEqual(after.birds,before.birds,phase)
            XCTAssertEqual(after.insect,before.insect);XCTAssertEqual(after.props,before.props)
            XCTAssertEqual(after.lastInsectContact,before.lastInsectContact)
            XCTAssertEqual(after.insectCooldownRemaining,before.insectCooldownRemaining)
            XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
            XCTAssertEqual(e.runtime.runs[run]?.age,age);XCTAssertEqual(e.bird(x.plan.id)?.coordinatedFlightAge,flight)
            XCTAssertTrue(Common.terminals(e,run).isEmpty)
            e.handle(.pause(false));F.finish(e,run);F.released(e,run)
            XCTAssertEqual(Common.terminals(e,run).map(\.type),[.completed])
            XCTAssertEqual(e.bird(x.plan.id)?.state,.perched);XCTAssertEqual(e.bird(x.plan.id)?.position,x.plan.originalFoot)
        }
    }

    func testClickCancelsEveryPhaseWithoutMovingFeetAndLeavesTheIndependentUncaughtInsect() throws {
        for phase in ["entry","open","recovery","return","landing"] {
            let e=try F.engine(),(run,x)=try F.start(e)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            try reach(phase,e,run,x)
            let foot=try XCTUnwrap(e.bird(x.plan.id)).position,insect=e.insectSnapshot()
            e.handle(.pointerClick);F.released(e,run)
            XCTAssertEqual(Common.terminals(e,run).map(\.type),[.cancelled])
            XCTAssertEqual(Common.terminals(e,run).first?.reason,.userInput)
            XCTAssertEqual(e.bird(x.plan.id)?.position,foot);XCTAssertTrue(observations.isEmpty)
            if let insect {
                let continued=try XCTUnwrap(e.insectSnapshot())
                XCTAssertEqual(continued.id,insect.id);XCTAssertEqual(continued.age,insect.age)
                XCTAssertEqual(continued.trajectory,insect.trajectory)
                F.advance(e,0.1)
                let moved=try XCTUnwrap(e.insectSnapshot())
                XCTAssertEqual(moved.id,insect.id);XCTAssertEqual(moved.age,insect.age+0.1,accuracy:1e-9)
                XCTAssertEqual(moved.position,insect.trajectory.position(at:moved.age))
            } else {XCTAssertTrue(x.captured);XCTAssertNil(e.insectSnapshot())}
            F.advance(e,13);XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
            XCTAssertEqual(e.insectMissedTargetCount,0);XCTAssertTrue(observations.isEmpty)
            XCTAssertEqual(Common.terminals(e,run).count,1)
        }
    }

    func testDisabledRemovedFramesAndSceneCleanupDuringPauseReleaseOwnershipWithoutSuccess() throws {
        for phase in ["entry","recovery","landing"] {
          for cause in ["disabled","speciesDisabled","art","frames","clear","scene","sleep","removed"] {
            let e=try F.engine(),(run,x)=try F.start(e)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            try reach(phase,e,run,x);e.handle(.pause(true))
            let foot=try XCTUnwrap(e.bird(x.plan.id)).position
            switch cause {
            case "disabled":var s=e.settings;s.insectCatchEnabled=false;e.applySettings(s)
            case "speciesDisabled":
                var s=e.settings;let index=try XCTUnwrap(s.probabilities.entries.firstIndex{$0.id==F.species})
                s.probabilities.setManualWeight(at:index,to:0);e.applySettings(s)
            case "art":var w=e.world;w.insectArtAvailable=false;e.updateWorld(w)
            case "frames":var w=e.world;w.availableFrames[F.species]?.remove("catchRecover");e.updateWorld(w)
            case "clear":e.handle(.clearInsect)
            case "scene":e.handle(.clearCurrentScene)
            case "sleep":e.handle(.cancelAmbient(.sleep))
            default:e.handle(.remove(x.plan.id))
            }
            F.released(e,run);XCTAssertFalse(Common.terminals(e,run).contains{$0.type == .completed},cause)
            if let bird=e.bird(x.plan.id) {XCTAssertEqual(bird.position,foot,cause)}
            if ["disabled","art","clear","scene","sleep"].contains(cause) {XCTAssertNil(e.insectSnapshot(),cause)}
            XCTAssertTrue(observations.isEmpty);XCTAssertEqual(e.insectMissedTargetCount,0)
            e.handle(.pause(false));F.advance(e,13)
            XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
            XCTAssertEqual(Common.terminals(e,run).count,1);XCTAssertTrue(observations.isEmpty)
          }
        }
    }

    func testHostLossPIDReuseAndSecondaryObstructionReplanFromActualFeetToARealSafePerch() throws {
        for cause in ["removed","pidReuse","occluded"] {
            let e=try F.engine(),(run,x)=try F.start(e),bird=try XCTUnwrap(e.bird(x.plan.id))
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            try F.reachContact(e,run)
            let foot=bird.position,revision=bird.motionRevision
            let safe=Surface(id:2104,pid:77,rect:CGRect(x:300,y:1300,width:1000,height:180))
            var world=e.world
            switch cause {
            case "removed":world.surfaces=[safe]
            case "pidReuse":world.surfaces=[safe,Surface(id:2101,pid:99,rect:F.host().rect)]
            default:
                let panel=Surface(id:2105,pid:88,
                    rect:Geometry.landingFootprint(at:x.plan.originalFoot,scale:x.plan.spriteScale).insetBy(dx:-4,dy:-4),layer:1)
                world.surfaces=[panel,safe,F.host()]
            }
            e.handle(.pause(true));let age=e.runtime.runs[run]?.age
            e.updateWorld(world,sampleDT:1.0/30)
            XCTAssertEqual(bird.position,foot,"Reconciliation installs a route; it cannot translate the bird")
            XCTAssertNotNil(e.runtime.runs[run],cause);XCTAssertGreaterThan(bird.motionRevision,revision)
            XCTAssertEqual(e.runtime.owners[x.plan.id],run);XCTAssertEqual(e.runtime.runs[run]?.age,age)
            if cause == "removed" {
                let firstReturn=try XCTUnwrap(e.runtime.landingReservations.first?.point(in:e))
                let blocked=Surface(id:2106,pid:88,
                    rect:Geometry.landingFootprint(at:firstReturn,scale:x.plan.spriteScale).insetBy(dx:-4,dy:-4),layer:1)
                var second=e.world;second.surfaces.insert(blocked,at:0)
                second.surfaces.append(Surface(id:2107,pid:77,rect:CGRect(x:1100,y:1450,width:900,height:180)))
                let firstRevision=bird.motionRevision
                e.updateWorld(second,sampleDT:1.0/30)
                XCTAssertEqual(bird.position,foot,"A second obstruction must not teleport to a replacement landing")
                XCTAssertNotNil(e.runtime.runs[run]);XCTAssertGreaterThan(bird.motionRevision,firstRevision)
                XCTAssertTrue(Common.terminals(e,run).isEmpty)
            }
            F.advance(e,1);XCTAssertEqual(bird.position,foot);XCTAssertTrue(observations.isEmpty)
            e.handle(.pause(false));F.finish(e,run);F.released(e,run)
            XCTAssertEqual(Common.terminals(e,run).map(\.type),[.completed],cause)
            XCTAssertEqual(bird.state,.perched);XCTAssertFalse(bird.needsDestination);XCTAssertFalse(bird.isCoordinatedFlying)
            let host=try XCTUnwrap(e.world.surfaces.first{$0.id==bird.hostID && $0.pid==bird.hostPID})
            XCTAssertFalse(host.isHabitat);XCTAssertTrue(host.isGround || host.layer==0)
            XCTAssertTrue(Geometry.isLandingVisible(on:host.id,at:bird.position,surfaces:e.world.surfaces,scale:e.spriteScale(for:bird)))
            XCTAssertTrue(F.display.contains(e.bounds(of:bird)))
            if cause == "pidReuse" {XCTAssertNotEqual(bird.hostPID,42,"A reused window ID cannot restore the stale original host")}
            XCTAssertEqual(observations.count,1);XCTAssertNil(e.insectSnapshot());XCTAssertEqual(e.insectMissedTargetCount,0)
        }
    }

    func testExternalReplacementAndPausedClickRelocationKeepTheirNewMotionOwner() throws {
        for external in [false,true] {
            let e=try F.engine(),(run,x)=try F.start(e),bird=try XCTUnwrap(e.bird(x.plan.id))
            F.advance(e,0.1);e.handle(.pause(true));let foot=bird.position
            var newOwner:BehaviorRunID?
            if external {
                bird.fly(to:CGPoint(x:1400,y:1300),host:nil,arc:0,allowsOrbit:false,random:{0.5})
                e.updateWorld(e.world)
            } else {
                guard case .started(let replacement)=e.handle(.relocate(x.plan.id)) else {return XCTFail("Paused click must accept a replacement route")}
                newOwner=replacement
            }
            XCTAssertEqual(bird.position,foot);XCTAssertFalse(e.runtime.owners.values.contains(run))
            XCTAssertEqual(Common.terminals(e,run).map(\.type),[external ? .failed:.cancelled])
            XCTAssertEqual(Common.terminals(e,run).first?.reason,external ? .targetInvalid:.replaced)
            if let newOwner {XCTAssertEqual(e.runtime.owners[x.plan.id],newOwner)}
            let revision=bird.motionRevision
            e.handle(.pause(false));F.advance(e,0.2)
            XCTAssertEqual(bird.motionRevision,revision);XCTAssertNotEqual(bird.position,foot)
            if let newOwner {XCTAssertEqual(e.runtime.owners[x.plan.id],newOwner)}
            XCTAssertEqual(Common.terminals(e,run).count,1);XCTAssertEqual(e.insectMissedTargetCount,0)
            e.handle(.cancelAmbient(.sleep));XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
        }
    }
}
