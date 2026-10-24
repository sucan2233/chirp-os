import XCTest
@testable import BirdingCore

final class NestBuildTests:XCTestCase {
    private typealias F=NestTestSupport
    private enum Boundary:String,CaseIterable {
        case approach,place,adjust0,adjust1,beforeCommit,afterCommit,departure,settle
    }
    private func reach(_ boundary:Boundary,_ e:BehaviorEngine,_ run:BehaviorRunID)throws->NestBuildExecution {
        let execution=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestBuildExecution)
        try F.until(e,run) {
            let frame=e.renderSnapshot().first{$0.id==execution.plan.id}?.frameName
            switch boundary {
            case .approach:return execution.phase == .approach && execution.phaseAge>=0.1
            case .place:return execution.phase == .build && !execution.arranged && frame=="nestPlace"
            case .adjust0:return execution.phase == .build && frame=="nestAdjust0"
            case .adjust1:return execution.phase == .build && frame=="nestAdjust1"
            case .beforeCommit:return execution.phase == .build && !execution.arranged && frame=="nestSettle"
            case .afterCommit:return execution.phase == .build && execution.arranged
            case .departure:return execution.phase == .departure && execution.phaseAge>=0.1 && e.birds[0].state == .flying
            case .settle:return execution.phase == .settle && execution.phaseAge>=0.1 && e.birds[0].state == .perched
            }
        }
        XCTAssertNotNil(e.runtime.runs[run],boundary.rawValue)
        XCTAssertTrue(F.terminals(e,run).isEmpty,boundary.rawValue)
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
        for boundary in [Boundary.afterCommit,.departure,.settle] {
        let e=try F.prepared();var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        let ids=Set(try F.nest(e).materials.map(\.id))
        var buildRuns:[BehaviorRunID]=[]
        for index in 1...3 {
            _=try F.deliver(e)
            let run=try F.start(e,build:true);buildRuns.append(run)
            let active=try reach(index==3 ? boundary:.afterCommit,e,run),committed=try F.nest(e)
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
        let bird=e.birds[0]
        for _ in 0..<36*60 {
            if bird.state == .perched && !bird.needsDestination && !bird.isCoordinatedFlying {break}
            e.advance(BehaviorEngine.step)
        }
        try assertSafeReturn(e,bird:bird,context:"third commit/\(boundary.rawValue)")
        F.advance(e,0.5);XCTAssertEqual(try F.nest(e).progress,3);XCTAssertEqual(observations.count,5)
        for command:EngineCommand in [.nestBuild(.preview),.nestMaterialCarry(.preview)] {
            XCTAssertEqual(e.handle(command),.rejected(.noSpace))
        }
        XCTAssertEqual(buildRuns.flatMap{F.terminals(e,$0)}.filter{$0.type == .completed}.count,2)
        F.clear(e);XCTAssertEqual(observations.count,5)
        }
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

    func testEveryBuildStageInterruptKeepsCommittedProgressReleasesResourcesAndActuallyRecovers() throws {
        for boundary in Boundary.allCases {for paused in [false,true] {
            for cause in ["click","removeBird","removeNest","clear","host","pid","hostMoved","frames","art",
                          "screen","scale","buttonsDown","disable","sleep","shutdown","screensChanged","spaceChanged"] {
                let e=try F.prepared();_=try F.deliver(e)
                let run=try F.start(e,build:true),active=try reach(boundary,e,run)
                let before=try F.nest(e),bird=e.birds[0],feet=bird.position,id=try XCTUnwrap(e.id(of:bird))
                let ids=Set(before.materials.map(\.id)),context="\(boundary.rawValue)/\(cause)/paused=\(paused)"
                var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
                XCTAssertEqual(before.progress,active.arranged ? 1:0,context)
                if paused {
                    e.handle(.pause(true));let props=e.propSnapshot().map(RecordedPropState.init),age=active.age,phaseAge=active.phaseAge
                    let poses=e.renderSnapshot().map{RecordedBirdState($0,engine:e)}
                    F.advance(e,2);XCTAssertEqual(try F.nest(e),before,context);XCTAssertEqual(active.age,age,context)
                    XCTAssertEqual(active.phaseAge,phaseAge,context)
                    XCTAssertEqual(e.renderSnapshot().map{RecordedBirdState($0,engine:e)},poses,context)
                    XCTAssertEqual(e.propSnapshot().map(RecordedPropState.init),props,context);XCTAssertEqual(bird.position,feet,context)
                }
                switch cause {
                case "click":e.handle(.pointerClick)
                case "removeBird":e.handle(.remove(id))
                case "removeNest":e.handle(.removeNest)
                case "clear":e.handle(.clearCurrentScene)
                case "host":var w=e.world;w.surfaces.removeAll{$0.id==3701};e.updateWorld(w)
                case "pid":var w=e.world;let h=w.surfaces[0];w.surfaces[0]=Surface(id:h.id,pid:h.pid+1,rect:h.rect);e.updateWorld(w)
                case "hostMoved":var w=e.world;w.surfaces[0].rect.origin.x+=1;e.updateWorld(w)
                case "frames":var w=e.world;w.availableFrames[.spottedDove]?.remove("nestSettle");e.updateWorld(w)
                case "art":var w=e.world;w.nestArtAvailable=false;e.updateWorld(w)
                case "screen":var w=e.world;w.screens=[];w.displays=[];w.displayIDs=[];e.updateWorld(w)
                case "scale":var w=e.world;w.scale=0.5;e.updateWorld(w)
                case "buttonsDown":var w=e.world;w.buttonsDown=true;e.updateWorld(w)
                case "disable":var s=e.settings;s.nestBuildingEnabled=false;e.applySettings(s)
                case "sleep":e.handle(.cancelAmbient(.sleep))
                case "shutdown":e.handle(.cancelAmbient(.shutdown))
                case "screensChanged":e.handle(.cancelAmbient(.screensChanged))
                case "spaceChanged":e.handle(.cancelAmbient(.spaceChanged))
                default:XCTFail("Unhandled build interruption: \(cause)")
                }
                F.released(e,run);XCTAssertEqual(bird.position,feet,context)
                XCTAssertNotEqual(F.terminals(e,run).first?.type,.completed,context);XCTAssertTrue(observations.isEmpty,context)
                // Removal retires the whole ledger. A retained ledger must
                // preserve each committed identity, including its provenance.
                let keepsScene=["click","removeBird","frames","buttonsDown","hostMoved"].contains(cause)
                if keepsScene {
                    try assertCommittedState(e,before:before,ids:ids,context:context)
                } else {XCTAssertTrue(e.nestSnapshot().isEmpty,context)}
                if paused {
                    F.advance(e,1);XCTAssertEqual(bird.position,feet,context)
                    XCTAssertTrue(observations.isEmpty,context);F.released(e,run)
                }
                e.handle(.pause(false))
                // Let the production recovery queue and Bird.tick finish;
                // behavior == nil alone does not mean the return flight landed.
                for _ in 0..<36*60 {
                    if e.bird(id)==nil || bird.state == .perched && !bird.needsDestination && !bird.isCoordinatedFlying {break}
                    e.advance(BehaviorEngine.step)
                }
                if ["removeBird","host","screen"].contains(cause) {
                    XCTAssertNil(e.bird(id),context)
                } else {try assertSafeReturn(e,bird:bird,context:context)}
                F.released(e,run);XCTAssertEqual(F.terminals(e,run).count,1,context);XCTAssertTrue(observations.isEmpty,context)
                if keepsScene {try assertCommittedState(e,before:before,ids:ids,context:context)}
                e.handle(.cancelAmbient(.sleep))
                XCTAssertTrue(e.nestSnapshot().isEmpty);XCTAssertTrue(F.tokens(e).isEmpty);XCTAssertNil(e.sceneFocus)
                XCTAssertTrue(observations.isEmpty);XCTAssertEqual(F.terminals(e,run).count,1)
            }
        }}
    }

    func testPauseAtEveryBuildStageResumesToAnActualSafeCompletedVisit() throws {
        for boundary in Boundary.allCases {
            let e=try F.prepared();_=try F.deliver(e)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            let run=try F.start(e,build:true),active=try reach(boundary,e,run),bird=e.birds[0],exit=active.plan.exit
            e.handle(.pause(true));let nest=try F.nest(e),age=active.age,wait=e.scheduler.remaining,cooldown=e.scheduler.nestCooldownRemaining
            let phaseAge=active.phaseAge,buildAge=active.buildAge,phase=active.phase
            let poses=e.renderSnapshot().map{RecordedBirdState($0,engine:e)},props=e.propSnapshot().map(RecordedPropState.init)
            F.advance(e,3);XCTAssertEqual(try F.nest(e),nest);XCTAssertEqual(active.age,age)
            XCTAssertEqual(active.phaseAge,phaseAge);XCTAssertEqual(active.buildAge,buildAge);XCTAssertEqual(active.phase,phase)
            XCTAssertEqual(e.renderSnapshot().map{RecordedBirdState($0,engine:e)},poses)
            XCTAssertEqual(e.propSnapshot().map(RecordedPropState.init),props)
            XCTAssertEqual(e.scheduler.remaining,wait);XCTAssertEqual(e.scheduler.nestCooldownRemaining,cooldown)
            XCTAssertNotNil(e.runtime.runs[run]);XCTAssertTrue(F.terminals(e,run).isEmpty);XCTAssertTrue(observations.isEmpty)
            XCTAssertEqual(e.handle(.nestBuild(.preview)),.rejected(.paused))
            e.handle(.pause(false));F.finish(e,run);F.released(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed]);XCTAssertEqual(try F.nest(e).progress,1)
            XCTAssertEqual(observations.map(\.runID),[run.rawValue]);XCTAssertEqual(observations.map(\.kind),[.nestBuild])
            XCTAssertEqual(observations.map(\.source),[.preview]);try assertSafeReturn(e,bird:bird,context:boundary.rawValue)
            XCTAssertEqual(bird.hostID,exit.host.id);XCTAssertEqual(bird.hostPID,exit.host.pid)
            XCTAssertLessThan(Geometry.distance(bird.position,exit.foot),0.001)
            let completed=try F.nest(e)
            XCTAssertEqual(completed.materials.filter{$0.state == .arranged}.map(\.id),[active.plan.materialID])
            XCTAssertEqual(completed.materials.filter{$0.state == .arranged}.map(\.arrangementRunID),[run])
            XCTAssertEqual(completed.materials.map(\.deliveryRunID),nest.materials.map(\.deliveryRunID))
            F.advance(e,0.5);XCTAssertEqual(observations.count,1);XCTAssertEqual(F.terminals(e,run).count,1)
            try assertCommittedState(e,before:completed,ids:Set(nest.materials.map(\.id)),context:boundary.rawValue)
            F.clear(e)
        }
    }

    func testDepartureAndSettleRelocationRetainsTheNewOwnerAndCommittedTwigAcrossPauseResume() throws {
        for boundary in [Boundary.departure,.settle] {for paused in [false,true] {
            let e=try F.prepared();_=try F.deliver(e)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            let run=try F.start(e,build:true);_=try reach(boundary,e,run)
            let bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird)),before=try F.nest(e),foot=bird.position
            let ids=Set(before.materials.map(\.id)),context="\(boundary.rawValue)/relocate/paused=\(paused)"
            if paused {e.handle(.pause(true))}
            let replacement=try LeafCarryTestSupport.start(e.handle(.relocate(id))),revision=bird.motionRevision
            XCTAssertNil(e.runtime.runs[run],context);XCTAssertEqual(F.terminals(e,run).map(\.type),[.cancelled],context)
            XCTAssertEqual(F.terminals(e,run).first?.reason,.replaced,context)
            XCTAssertEqual(e.runtime.owners[id],replacement,context);XCTAssertEqual(e.leasedBirdCount,1,context)
            XCTAssertEqual(e.habitatReservationCount,0,context);XCTAssertEqual(e.reservedLandingCount,0,context)
            XCTAssertNil(try F.nest(e).reservation,context)
            XCTAssertTrue(try F.nest(e).materials.allSatisfy{$0.owner==nil && $0.reservedByRun==nil},context)
            XCTAssertEqual(bird.position,foot,context);try assertCommittedState(e,before:before,ids:ids,context:context)
            if paused {
                // Explicit click relocation is allowed to run while paused.
                F.advance(e,1);XCTAssertTrue(e.paused,context)
                XCTAssertGreaterThan(Geometry.distance(bird.position,foot),0,context)
                XCTAssertEqual(e.runtime.owners[id],replacement,context);XCTAssertEqual(bird.motionRevision,revision,context)
                XCTAssertTrue(F.terminals(e,replacement).isEmpty,context)
            }
            e.handle(.pause(false));F.finish(e,replacement)
            F.released(e,run);F.released(e,replacement)
            XCTAssertEqual(F.terminals(e,replacement).map(\.type),[.completed],context)
            try assertSafeReturn(e,bird:bird,context:context)
            try assertCommittedState(e,before:before,ids:ids,context:context)
            F.advance(e,0.5);XCTAssertTrue(observations.isEmpty,context)
            XCTAssertEqual(F.terminals(e,run).count,1,context);F.clear(e)
        }}
    }

    private func assertCommittedState(_ e:BehaviorEngine,before:NestSnapshot,ids:Set<ScenePropID>,context:String)throws {
        try F.conserved(e,ids:ids)
        let after=try F.nest(e)
        XCTAssertEqual(after.id,before.id,context)
        XCTAssertEqual(after.progress,before.progress,context);XCTAssertEqual(after.completed,before.completed,context)
        XCTAssertEqual(after.materials.map(\.state),before.materials.map(\.state),context)
        XCTAssertEqual(after.materials.map(\.pickupRunID),before.materials.map(\.pickupRunID),context)
        XCTAssertEqual(after.materials.map(\.deliveryRunID),before.materials.map(\.deliveryRunID),context)
        XCTAssertEqual(after.materials.map(\.arrangementRunID),before.materials.map(\.arrangementRunID),context)
    }

    private func assertSafeReturn(_ e:BehaviorEngine,bird:Bird,context:String)throws {
        XCTAssertTrue(e.birds.contains{$0 === bird},context);XCTAssertEqual(bird.state,.perched,context)
        XCTAssertFalse(bird.needsDestination,context);XCTAssertFalse(bird.isDeparting,context)
        XCTAssertFalse(bird.isCoordinatedFlying,context);XCTAssertNil(e.behavior(of:bird),context)
        XCTAssertTrue(e.hasUsablePerch(bird),context)
        let host=try XCTUnwrap(e.world.surfaces.first{$0.id==bird.hostID && $0.pid==bird.hostPID},context)
        XCTAssertFalse(host.isHabitat,context)
        XCTAssertLessThan(Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:bird.edge,
            scale:e.spriteScale(for:bird))),0.001,context)
    }
}
