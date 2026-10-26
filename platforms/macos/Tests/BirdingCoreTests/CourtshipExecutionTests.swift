import XCTest
@testable import BirdingCore

final class CourtshipExecutionTests:XCTestCase {
    private typealias F=CourtshipTestSupport

    func testRealCommandKeepsBothFeetAndFullTurningBodiesOnPositiveAndFullyNegativeDisplaysAtThreeScales() throws {
        for negative in [false,true] {for scale:CGFloat in [0.5,1,2] {for right in [false,true] {
            let e=F.engine(scale:scale,negative:negative,right:right),feet=e.birds.map(\.position)
            let memory=e.visitorMemoryArchive,identities=e.birds.map(ObjectIdentifier.init)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            let run=try F.start(e),active=try XCTUnwrap(e.runtime.runs[run])
            let startedAt=e.time
            let execution=try XCTUnwrap(active.execution as? CourtshipDisplayExecution)
            XCTAssertEqual(execution.timeout,6);XCTAssertEqual(execution.plan.duration,4)
            XCTAssertEqual(Set(execution.participants),Set(e.birds.compactMap{e.id(of:$0)}))
            XCTAssertEqual(e.leasedBirdCount,2);XCTAssertEqual(e.reservedLandingCount,1)
            XCTAssertEqual(execution.plan.role(for:execution.participants[0]),.initiator)
            XCTAssertEqual(execution.plan.role(for:execution.participants[1]),.observer)
            var seen=Set<String>()
            for _ in 0..<239 {
                e.advance(BehaviorEngine.step)
                XCTAssertNotNil(e.runtime.runs[run],"No early success before the complete 4-second sequence")
                XCTAssertEqual(e.birds.map(\.position),feet);XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
                for render in e.renderSnapshot() {
                    seen.insert(render.frameName)
                    XCTAssertEqual(render.hopOffset,0)
                    let turn=CGRect(x:render.position.x-29*render.scale,y:render.position.y-39*render.scale,
                        width:58*render.scale,height:48*render.scale)
                    XCTAssertTrue(e.world.displays[0].contains(turn))
                    XCTAssertTrue(e.world.displays[0].contains(render.rect))
                    XCTAssertEqual(render.facingRight,render.position.x<feet.map(\.x).max()!)
                }
                let sorted=e.birds.sorted{$0.position.x<$1.position.x}
                let size=e.spriteScale(for:sorted[0])
                XCTAssertGreaterThanOrEqual((sorted[1].position.x-29*size)-(sorted[0].position.x+29*size),12)
            }
            e.advance(BehaviorEngine.step);F.clean(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            XCTAssertEqual(try XCTUnwrap(F.terminals(e,run).first).time-startedAt,4,accuracy:1e-8)
            XCTAssertEqual(seen,F.dedicated.union(["stand"]))
            XCTAssertEqual(e.birds.map(\.position),feet);XCTAssertEqual(e.birds.map(\.state),[.perched,.perched])
            XCTAssertEqual(e.visitorMemoryArchive,memory,"Courtship adds no familiarity, visit or pair resource")
            XCTAssertEqual(observations.map(\.kind),[.courtshipDisplay]);XCTAssertEqual(observations.map(\.source),[.preview])
            XCTAssertEqual(observations.first?.species,[.spottedDove])
            execution.start(in:e);execution.cancel(.removed,in:e);XCTAssertNotNil(execution.advance(0.1,in:e))
            F.advance(e,0.2);XCTAssertEqual(F.terminals(e,run).count,1);XCTAssertEqual(observations.count,1)
            XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0);XCTAssertEqual(e.pendingCount,0)
        }}}
    }

    func testEitherRoleClickedOrRemovedDuringEveryStageCancelsWholeGroupAndPreservesNewOwner() throws {
        for role in 0..<2 {for elapsed in F.stages {for cause in ["click","remove"] {for paused in [false,true] {
            let e=F.engine(),run=try F.start(e)
            let participants=try XCTUnwrap(e.runtime.runs[run]).execution.participants
            F.advance(e,elapsed);let target=participants[role],feet=e.birds.map(\.position)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            if paused {e.handle(.pause(true))}
            if cause=="click" {
                var world=e.world;world.pointer=try XCTUnwrap(e.bird(target)).position;world.buttonsDown=true
                e.updateWorld(world);e.handle(.pointerClick)
            } else {e.handle(.remove(target))}
            F.clean(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.cancelled])
            XCTAssertTrue(observations.isEmpty)
            if cause=="click" {
                XCTAssertEqual(e.birds.map(\.position),feet)
                var world=e.world;world.buttonsDown=false;world.pointer=CGPoint(x:20,y:20);e.updateWorld(world)
                XCTAssertTrue(e.handle(.relocate(target)).accepted)
                let owner=try XCTUnwrap(e.runtime.owners[target]),bird=try XCTUnwrap(e.bird(target)),revision=bird.motionRevision
                F.advance(e,0.1)
                XCTAssertNotEqual(owner,run);XCTAssertEqual(bird.motionRevision,revision)
                XCTAssertFalse(e.runtime.owners.values.contains(run))
            } else {
                XCTAssertNil(e.bird(target));XCTAssertEqual(e.residentCount,1)
                let survivor=try XCTUnwrap(e.birds.first)
                XCTAssertEqual(survivor.state,.perched);XCTAssertFalse(survivor.needsDestination)
                XCTAssertTrue(e.hasUsablePerch(survivor))
            }
            XCTAssertEqual(F.terminals(e,run).count,1)
        }}}}
    }

    func testEveryStageWorldContentOrSettingsInvalidationTerminatesEvenWhilePaused() throws {
        for elapsed in F.stages {for paused in [false,true] {
            for cause in ["move","resize","removeHost","pid","screens","displays","displayID","scale","frames","child","master","species"] {
                let e=F.engine(),run=try F.start(e);F.advance(e,elapsed)
                if paused {e.handle(.pause(true))}
                var world=e.world
                switch cause {
                case "move":world.surfaces[0].rect.origin.x+=1
                case "resize":world.surfaces[0].rect.size.width-=1
                case "removeHost":world.surfaces=[]
                case "pid":world.surfaces[0]=Surface(id:2701,pid:99,rect:world.surfaces[0].rect)
                case "screens":world.screens[0].size.width-=1
                case "displays":world.displays[0].size.height-=1
                case "displayID":world.displayIDs=["replacement"]
                case "scale":world.scale*=1.1
                case "frames":world.availableFrames[F.species]?.remove("courtObserve")
                case "child":var s=e.settings;s.courtshipEnabled=false;e.applySettings(s)
                case "master":var s=e.settings;s.socialInteractions=false;e.applySettings(s)
                default:
                    var s=e.settings;let index=try XCTUnwrap(s.probabilities.entries.firstIndex{$0.id==F.species})
                    s.probabilities.setManualWeight(at:index,to:0);e.applySettings(s)
                }
                e.updateWorld(world,sampleDT:0.1);F.clean(e,run)
                XCTAssertNotEqual(F.terminals(e,run).first?.type,.completed,"\(cause)/\(elapsed)/\(paused)")
                for bird in e.birds {
                    XCTAssertTrue(bird.position.x.isFinite && bird.position.y.isFinite)
                    if bird.state == .perched {XCTAssertTrue(e.hasUsablePerch(bird))}
                    else {XCTAssertEqual(bird.state,.flying)}
                }
                e.handle(.pause(false));F.advance(e,0.2)
                XCTAssertEqual(F.terminals(e,run).count,1);XCTAssertEqual(e.leasedBirdCount,0)
            }
        }}
    }

    func testPauseFreezesBothRolesAtEveryStageAndResumeCompletesTheRemainingTime() throws {
        for elapsed in F.stages {
            let e=F.engine(),run=try F.start(e);F.advance(e,elapsed)
            e.handle(.pause(true))
            let before=BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            let age=try XCTUnwrap(e.runtime.runs[run]).age
            F.advance(e,20);e.updateWorld(e.world,sampleDT:1)
            let after=BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(after.events,before.events)
            XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
            XCTAssertEqual(after.courtshipCooldownRemaining,before.courtshipCooldownRemaining)
            XCTAssertEqual(e.runtime.runs[run]?.age,age)
            e.handle(.pause(false));F.advance(e,4-elapsed-0.05)
            XCTAssertNotNil(e.runtime.runs[run]);F.advance(e,0.1);F.clean(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        }
    }

    func testSleepShutdownAndSpaceChangesCleanBothRolesWithoutObservationOrQueuedReplay() throws {
        for reason:BehaviorReason in [.sleep,.shutdown,.screensChanged,.spaceChanged] {for elapsed in F.stages {
            let e=F.engine(),run=try F.start(e);F.advance(e,elapsed)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            e.handle(.pause(true));e.handle(.cancelAmbient(reason));F.clean(e,run)
            XCTAssertEqual(F.terminals(e,run).first?.reason,reason)
            e.handle(.pause(false));F.advance(e,7)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.cancelled]);XCTAssertTrue(observations.isEmpty)
            XCTAssertEqual(e.events.filter{$0.kind == .courtshipDisplay && $0.type == .started}.count,1)
        }}
    }

    func testAnExternalNewMotionForEitherRoleSurvivesGroupCancellationAtEveryStage() throws {
        for role in 0..<2 {for elapsed in F.stages {
            let e=F.engine(),run=try F.start(e),execution=try XCTUnwrap(e.runtime.runs[run]?.execution)
            F.advance(e,elapsed);let id=execution.participants[role],bird=try XCTUnwrap(e.bird(id))
            let foot=bird.position
            bird.fly(to:CGPoint(x:1800,y:1000),host:nil,arc:40,allowsOrbit:false,random:{0.5})
            let revision=bird.motionRevision;e.updateWorld(e.world)
            F.clean(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.failed])
            XCTAssertEqual(bird.motionRevision,revision);XCTAssertEqual(bird.position,foot)
            XCTAssertFalse(bird.needsDestination);F.advance(e,0.2)
            XCTAssertNotEqual(bird.position,foot);XCTAssertEqual(bird.motionRevision,revision)
        }}
    }

    func testRuntimeSixSecondHardLimitReleasesTheRealLeasedExecutionWithoutFalseCompletion() throws {
        let e=F.engine(),run=try F.start(e),feet=e.birds.map(\.position)
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        XCTAssertEqual(try XCTUnwrap(e.runtime.runs[run]).execution.timeout,6)
        // Direct Runtime boundary injection verifies the hard guard separately
        // from the ordinary command's real four-second successful execution.
        e.runtime.advance(6+BehaviorEngine.step,in:e)
        F.clean(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.failed])
        XCTAssertEqual(F.terminals(e,run).first?.reason,.timedOut)
        XCTAssertEqual(e.birds.map(\.position),feet);XCTAssertTrue(observations.isEmpty)
        e.runtime.cancel(run,reason:.removed,in:e);XCTAssertEqual(F.terminals(e,run).count,1)
    }
}
