import XCTest
@testable import BirdingCore

final class NestBuildTests:XCTestCase {
    private typealias F=NestTestSupport
    private func reach(_ time:Double,_ e:BehaviorEngine,_ run:BehaviorRunID)throws->NestBuildExecution {
        let execution=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestBuildExecution)
        try F.until(e,run) {execution.buildAge>=time}
        return execution
    }

    func testRealBuildUsesOnlyOneDeliveredTwigAndCountsOnlyAfterSafeDepartureAcrossScreensScalesAndHeadings() throws {
        for scale:CGFloat in [0.5,1,2] {for negative in [false,true] {for right in [false,true] {for ground in [false,true] {
            let e=try F.prepared(scale:scale,negative:negative,right:right,ground:ground,screens:4)
            let carry=try F.deliver(e),initial=try F.nest(e),ids=Set(initial.materials.map(\.id))
            let material=try XCTUnwrap(initial.materials.first{$0.state == .delivered}),bird=e.birds[0]
            let identity=ObjectIdentifier(bird)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            let run=try F.start(e,build:true,source:.user),started=e.time
            let active=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestBuildExecution),plan=active.plan
            let vmax=try XCTUnwrap((plan.approach.route.legs+plan.departure.route.legs).map{$0.timing.peakSpeed}.max())
            XCTAssertEqual(active.timeout,30);XCTAssertEqual(plan.materialID,material.id)
            var committed=false,commits=0,sawFrames=Set<String>()
            for _ in 0..<30*60 {
                guard e.runtime.runs[run] != nil else {break}
                let nest=try F.nest(e),pose=try XCTUnwrap(e.renderSnapshot().first{$0.id==plan.id})
                try F.conserved(e,ids:ids);sawFrames.insert(pose.frameName)
                XCTAssertTrue(e.world.displays[0].contains(pose.rect));XCTAssertTrue(observations.isEmpty)
                XCTAssertEqual(nest.progress,committed ? 1:0);XCTAssertEqual(nest.available,2)
                let position=bird.position,time=e.time
                e.advance(BehaviorEngine.step)
                XCTAssertLessThanOrEqual(Geometry.distance(position,bird.position),CGFloat(vmax*(e.time-time))+0.002)
                let after=try F.material(e,material.id)
                if after.state == .arranged && !committed {
                    committed=true;commits+=1;XCTAssertTrue(active.arranged)
                    XCTAssertEqual(after.arrangementRunID,run);XCTAssertEqual(after.deliveryRunID,carry)
                    XCTAssertEqual(try F.nest(e).progress,1);XCTAssertFalse(try F.nest(e).completed)
                    XCTAssertNotNil(e.runtime.runs[run]);XCTAssertTrue(observations.isEmpty)
                    let before=e.nestSnapshot().map(RecordedNestState.init)
                    // Re-resolving the same committed motion cannot consume
                    // another twig or increment the progress a second time.
                    _=active.resolveMotion(in:e);_=active.resolveMotion(in:e)
                    XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),before)
                }
            }
            F.released(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            XCTAssertEqual(commits,1);XCTAssertTrue(F.build.isSubset(of:sawFrames))
            XCTAssertLessThanOrEqual(e.time-started,30+BehaviorEngine.step)
            XCTAssertEqual(observations.map(\.kind),[.nestBuild]);XCTAssertEqual(observations.map(\.source),[.user])
            XCTAssertEqual(ObjectIdentifier(bird),identity);XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0)
            XCTAssertEqual(bird.state,.perched);XCTAssertTrue(e.hasUsablePerch(bird))
            XCTAssertFalse(try XCTUnwrap(e.world.surfaces.first{$0.id==bird.hostID}).isHabitat)
            XCTAssertEqual(try F.nest(e).progress,1);XCTAssertEqual(try F.nest(e).delivered,0)
            XCTAssertEqual(e.sceneFocus?.nestID,initial.id);F.clear(e)
        }}}}
    }

    func testThirdArrangementCompletesThePlatformBeforeObservationAndCancellationCannotRollItBackOrCountAFourthAction() throws {
        let e=try F.prepared();var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        let ids=Set(try F.nest(e).materials.map(\.id))
        var buildRuns:[BehaviorRunID]=[]
        for index in 1...3 {
            _=try F.deliver(e)
            let run=try F.start(e,build:true);buildRuns.append(run)
            let active=try reach(1.9,e,run),committed=try F.nest(e)
            XCTAssertEqual(committed.progress,index);XCTAssertEqual(committed.completed,index==3)
            XCTAssertEqual(observations.filter{$0.kind == .nestBuild}.count,index-1)
            XCTAssertNotNil(e.runtime.runs[run]);try F.conserved(e,ids:ids)
            let before=e.nestSnapshot().map(RecordedNestState.init)
            for _ in 0..<4 {_=active.resolveMotion(in:e)}
            XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),before)
            if index==3 {e.handle(.pointerClick)} else {F.finish(e,run)}
            F.released(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[index==3 ? .cancelled:.completed])
            if index<3 {F.advance(e,1.1)}
        }
        let final=try F.nest(e)
        XCTAssertEqual(final.progress,3);XCTAssertTrue(final.completed);XCTAssertFalse(final.canContinue)
        XCTAssertEqual(final.materials.map(\.state),[.arranged,.arranged,.arranged]);XCTAssertNil(e.sceneFocus)
        XCTAssertEqual(observations.filter{$0.kind == .nestMaterialCarry}.count,3)
        XCTAssertEqual(observations.filter{$0.kind == .nestBuild}.count,2)
        XCTAssertEqual(observations.count,5);XCTAssertEqual(Set(observations.map(\.runID)).count,5)
        F.advance(e,2);XCTAssertEqual(try F.nest(e).progress,3)
        for command:EngineCommand in [.nestBuild(.preview),.nestMaterialCarry(.preview)] {
            XCTAssertEqual(e.handle(command),.rejected(.noSpace))
        }
        XCTAssertEqual(buildRuns.flatMap{F.terminals(e,$0)}.filter{$0.type == .completed}.count,2)
        F.clear(e);XCTAssertEqual(observations.count,5)
    }

    func testDeliveredTwigSurvivesCancelledTransportAndIsStillEligibleForOneRealBuild() throws {
        let e=try F.prepared(),carry=try F.start(e)
        let active=try XCTUnwrap(e.runtime.runs[carry]?.execution as? NestMaterialCarryExecution)
        try F.until(e,carry) {active.delivered}
        let id=active.plan.materialID;var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        e.handle(.pointerClick);F.released(e,carry)
        XCTAssertEqual(try F.material(e,id).state,.delivered);XCTAssertEqual(try F.nest(e).progress,0)
        XCTAssertTrue(observations.isEmpty);XCTAssertEqual(F.terminals(e,carry).map(\.type),[.cancelled])
        // Allow existing safe recovery and settling, without inventing a pose.
        F.advance(e,12)
        let build=try F.start(e,build:true);F.finish(e,build);F.released(e,build)
        XCTAssertEqual(F.terminals(e,build).map(\.type),[.completed]);XCTAssertEqual(try F.material(e,id).state,.arranged)
        XCTAssertEqual(try F.nest(e).progress,1);XCTAssertEqual(observations.map(\.kind),[.nestBuild])
    }

    func testPauseAndInterruptsOnBothSidesOfArrangementKeepExactlyTheCommittedProgress() throws {
        for time in [0.1,0.5,1.0,1.6,2.0] {for paused in [false,true] {
            for cause in ["click","removeBird","removeNest","host","frames","disable","sleep"] {
                let e=try F.prepared();_=try F.deliver(e)
                let run=try F.start(e,build:true),active=try reach(time,e,run)
                let before=try F.nest(e),bird=e.birds[0],feet=bird.position,id=try XCTUnwrap(e.id(of:bird))
                var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
                if paused {
                    e.handle(.pause(true));let props=e.propSnapshot().map(RecordedPropState.init),age=active.age
                    F.advance(e,2);XCTAssertEqual(try F.nest(e),before);XCTAssertEqual(active.age,age)
                    XCTAssertEqual(e.propSnapshot().map(RecordedPropState.init),props);XCTAssertEqual(bird.position,feet)
                }
                switch cause {
                case "click":e.handle(.pointerClick)
                case "removeBird":e.handle(.remove(id))
                case "removeNest":e.handle(.removeNest)
                case "host":var w=e.world;w.surfaces.removeAll{$0.id==3701};e.updateWorld(w)
                case "frames":var w=e.world;w.availableFrames[.spottedDove]?.remove("nestSettle");e.updateWorld(w)
                case "disable":var s=e.settings;s.nestBuildingEnabled=false;e.applySettings(s)
                default:e.handle(.cancelAmbient(.sleep))
                }
                F.released(e,run);XCTAssertEqual(bird.position,feet)
                XCTAssertNotEqual(F.terminals(e,run).first?.type,.completed);XCTAssertTrue(observations.isEmpty)
                if ["click","removeBird","frames"].contains(cause) {
                    XCTAssertEqual(try F.nest(e).progress,time<1.9 ? 0:1)
                    XCTAssertEqual(try F.nest(e).materials.map(\.state),before.materials.map(\.state))
                } else if paused {XCTAssertTrue(e.nestSnapshot().isEmpty)}
                e.handle(.pause(false));F.advance(e,2.25);e.handle(.cancelAmbient(.sleep))
                XCTAssertTrue(e.nestSnapshot().isEmpty);XCTAssertTrue(F.tokens(e).isEmpty);XCTAssertNil(e.sceneFocus)
                XCTAssertTrue(observations.isEmpty);XCTAssertEqual(F.terminals(e,run).count,1)
            }
        }}
    }

    func testPauseAtEveryBuildStageResumesToAnActualSafeCompletedVisit() throws {
        for time in [0.1,0.5,1.0,1.6,2.0] {
            let e=try F.prepared();_=try F.deliver(e)
            let run=try F.start(e,build:true),active=try reach(time,e,run)
            e.handle(.pause(true));let nest=try F.nest(e),age=active.age,wait=e.scheduler.remaining,cooldown=e.scheduler.nestCooldownRemaining
            F.advance(e,3);XCTAssertEqual(try F.nest(e),nest);XCTAssertEqual(active.age,age)
            XCTAssertEqual(e.scheduler.remaining,wait);XCTAssertEqual(e.scheduler.nestCooldownRemaining,cooldown)
            XCTAssertEqual(e.handle(.nestBuild(.preview)),.rejected(.paused))
            e.handle(.pause(false));F.finish(e,run);F.released(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed]);XCTAssertEqual(try F.nest(e).progress,1)
            XCTAssertEqual(e.birds[0].state,.perched);XCTAssertTrue(e.hasUsablePerch(e.birds[0]))
        }
    }
}
