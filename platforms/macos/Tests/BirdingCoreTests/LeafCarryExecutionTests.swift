import XCTest
@testable import BirdingCore

final class LeafCarryExecutionTests:XCTestCase {
    private typealias F=LeafCarryTestSupport
    private typealias Phase=LeafCarryExecution.Phase
    private let phases:[Phase]=[.approach,.observe,.lower,.grip,.lift,.carry,.place,.recover]

    private func prepared(scale:CGFloat=1,right:Bool=true,seed:UInt64=971)throws->BehaviorEngine {
        let e=F.engine(scale:scale,right:right,seed:seed)
        XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.facingRight,right)
        return e
    }
    private func execution(_ e:BehaviorEngine,_ run:BehaviorRunID)throws->LeafCarryExecution {
        try XCTUnwrap(e.runtime.runs[run]?.execution as? LeafCarryExecution)
    }
    private func reach(_ phase:Phase,in e:BehaviorEngine,run:BehaviorRunID)throws {
        for _ in 0..<25*60 {
            guard let active=e.runtime.runs[run]?.execution as? LeafCarryExecution else {break}
            if active.phase==phase {return}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Real leafCarry did not reach \(phase); terminals=\(F.terminals(e,run))")
        throw NSError(domain:"LeafCarryExecutionTests",code:1)
    }

    func testActualCarryUsesOneEntityMirroredContactsFullBoundsAndBoundedRoutesAtAllThreeScales() throws {
        for scale:CGFloat in [0.5,1,2] {
            for right in [false,true] {
                let e=try prepared(scale:scale,right:right),bird=e.birds[0]
                let identity=ObjectIdentifier(bird),origin=bird.position,id=try XCTUnwrap(e.id(of:bird))
                let objectID=try XCTUnwrap(e.carriedObjectSnapshot().first?.id)
                var observations:[BehaviorObservation]=[];let journal=ObservationJournal()
                e.observationObserver={value in
                    observations.append(value);journal.observe(value,at:Date(timeIntervalSince1970:1_790_000_000))
                }
                let run=try F.start(e.handle(.leafCarry(.preview))),active=try execution(e,run),plan=active.plan
                let maximumSpeed=try XCTUnwrap((plan.approach.route.legs+plan.carrying.route.legs).map{$0.timing.peakSpeed}.max())
                let endpoints=try XCTUnwrap(plan.endpoints(in:e))
                XCTAssertEqual(active.timeout,25);XCTAssertEqual(bird.position,origin)
                XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
                XCTAssertEqual(e.reservedLandingCount,2);XCTAssertTrue(e.ambientBusy)
                let from=try XCTUnwrap(plan.source.point(in:e.world)),to=try XCTUnwrap(plan.placement.point(in:e.world))
                XCTAssertTrue((80.0...240.0).contains(Double(Geometry.distance(from,to)/scale)))
                XCTAssertEqual(to.x>from.x,right)
                var seen=Set<String>(),pickupCount=0,placeCount=0
                for _ in 0..<25*60 {
                    guard e.runtime.runs[run] != nil else {break}
                    let object=try XCTUnwrap(e.carriedObjectSnapshot().first)
                    let token=try XCTUnwrap(F.tokens(e).first),pose=try XCTUnwrap(e.renderSnapshot().first)
                    XCTAssertEqual(e.carriedObjectSnapshot().count,1);XCTAssertEqual(F.tokens(e).count,1)
                    XCTAssertEqual(object.id,objectID);XCTAssertEqual(token.id,objectID)
                    XCTAssertEqual(object.reservedByRun,run);XCTAssertEqual(token.size,16*scale)
                    XCTAssertEqual(token.mirrored,!right);XCTAssertEqual(token.rotation,0)
                    XCTAssertTrue(F.display.contains(pose.rect));XCTAssertTrue(F.display.contains(token.rect))
                    XCTAssertTrue(e.bounds(of:bird).insetBy(dx:-1e-8,dy:-1e-8).contains(pose.rect))
                    if object.state == .attached {
                        XCTAssertEqual(object.owner,id);XCTAssertEqual(object.remainingLifetime,0)
                        let anchor=try XCTUnwrap(PoseClip.carryBeakAnchor(species:.treeSparrow,frame:pose.frameName))
                        let beak=anchor.world(foot:CGPoint(x:bird.position.x,y:bird.position.y+pose.hopOffset*pose.scale),
                            scale:pose.scale,facingRight:pose.facingRight)
                        XCTAssertEqual(token.position.x,beak.x,accuracy:1e-8)
                        XCTAssertEqual(token.position.y,beak.y,accuracy:1e-8)
                        XCTAssertTrue(e.bounds(of:bird).insetBy(dx:-1e-8,dy:-1e-8).contains(token.rect))
                    } else {XCTAssertNil(object.owner)}
                    seen.insert(active.phase.rawValue)
                    if [.observe,.lower,.grip,.lift].contains(active.phase) {
                        XCTAssertEqual(bird.position.x,endpoints.pickupFoot.x,accuracy:0.001)
                        XCTAssertEqual(bird.position.y,endpoints.pickupFoot.y,accuracy:0.001)
                    }
                    if [.place,.recover].contains(active.phase) {
                        XCTAssertEqual(bird.position.x,endpoints.destinationFoot.x,accuracy:0.001)
                        XCTAssertEqual(bird.position.y,endpoints.destinationFoot.y,accuracy:0.001)
                    }
                    if object.state == .placed {XCTAssertNil(e.sceneFocus)}
                    else {XCTAssertEqual(e.sceneFocus?.leafID,objectID)}
                    XCTAssertTrue(observations.isEmpty,"Placement alone does not complete the recovery")
                    let position=bird.position,time=e.time,state=object.state,rect=token.rect
                    e.advance(BehaviorEngine.step)
                    XCTAssertLessThanOrEqual(Geometry.distance(position,bird.position),CGFloat(maximumSpeed*(e.time-time))+0.002)
                    let next=try XCTUnwrap(e.carriedObjectSnapshot().first)
                    if state != next.state {
                        let after=try XCTUnwrap(F.tokens(e).first)
                        XCTAssertEqual(after.rect.minX,rect.minX,accuracy:0.001)
                        XCTAssertEqual(after.rect.minY,rect.minY,accuracy:0.001)
                        XCTAssertEqual(after.rect.size,rect.size);XCTAssertEqual(after.mirrored,token.mirrored)
                        if next.state == .attached {pickupCount+=1}
                        if next.state == .placed {placeCount+=1;XCTAssertEqual(next.remainingLifetime,8)}
                    }
                }
                F.assertReleased(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
                XCTAssertEqual(seen,Set(phases.map(\.rawValue)));XCTAssertEqual(pickupCount,1);XCTAssertEqual(placeCount,1)
                XCTAssertEqual(observations.count,1);XCTAssertEqual(observations.first?.kind,.leafCarry)
                XCTAssertEqual(observations.first?.source,.preview);XCTAssertEqual(observations.first?.species,[.treeSparrow])
                XCTAssertEqual(journal.archive.entries.first?.previewCount,1)
                XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.placed)
                XCTAssertNil(e.carriedObjectSnapshot().first?.reservedByRun);XCTAssertNil(e.sceneFocus)
                XCTAssertEqual(bird.state,.perched);XCTAssertEqual(e.birds.map(ObjectIdentifier.init),[identity])
                XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                F.advance(e,8.1)
                XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertTrue(F.tokens(e).isEmpty)
                XCTAssertEqual(F.terminals(e,run).count,1);XCTAssertEqual(observations.count,1)
            }
        }
    }

    func testEveryRequiredFrameAndAllFortyFiveUnlistedSpeciesRejectWithoutReclaimingTheAvailableLeaf() throws {
        for missing in F.required.sorted() {
            let e=try prepared(),bird=e.birds[0],position=bird.position,revision=bird.motionRevision
            let original=e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init)
            var world=e.world;world.availableFrames[.treeSparrow]?.remove(missing);e.updateWorld(world)
            XCTAssertEqual(e.handle(.leafCarry(.preview)),.rejected(.missingFrames),missing)
            XCTAssertEqual(e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),original)
            XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
        for species in SpeciesID.allCases where species != .treeSparrow {
            let e=F.engine(species:species),bird=e.birds[0],position=bird.position
            XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)
            let original=e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init)
            XCTAssertEqual(e.handle(.leafCarry(.preview)),.rejected(.noSpecies),species.rawValue)
            XCTAssertEqual(e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),original)
            XCTAssertEqual(bird.position,position);XCTAssertEqual(e.residentCount,1)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.arrivalCount,0)
        }
    }

    func testPauseFreezesEveryPhaseIncludingAttachedContactAndPlacedLifetimeThenCompletesOnce() throws {
        for phase in phases {
            let e=try prepared(),run=try F.start(e.handle(.leafCarry(.preview)))
            try reach(phase,in:e,run:run)
            let active=try execution(e,run),age=e.runtime.runs[run]?.age,phaseAge=active.phaseAge
            e.handle(.pause(true))
            let before=BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            F.advance(e,10)
            for _ in 0..<3 {e.updateWorld(e.world);_=e.renderSnapshot();_=e.propSnapshot()}
            let after=BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(after.props,before.props)
            XCTAssertEqual(after.carriedObjects,before.carriedObjects);XCTAssertEqual(after.sceneFocusID,before.sceneFocusID)
            XCTAssertEqual(after.sceneFocusKind,before.sceneFocusKind);XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
            XCTAssertEqual(after.sceneCooldownRemaining,before.sceneCooldownRemaining)
            XCTAssertEqual(e.runtime.runs[run]?.age,age);XCTAssertEqual(active.phaseAge,phaseAge)
            XCTAssertEqual(e.handle(.leafCarry(.preview)),.rejected(.paused))
            e.handle(.pause(false));F.advance(e,26)
            F.assertReleased(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
        }
    }

    func testEveryPhaseCancellationKeepsOnlyCommittedObjectsAndNeverRecordsCompletion() throws {
        for phase in phases {
            for paused in [false,true] {
                for cause in ["click","relocate","removeBird","removeLeaf","clearProps","clearScene","disable","host","pid","layer",
                              "frames","art","screens","display","scale","buttons","pointer","sleep","space","shutdown"] {
                    // Proximity is a live motion constraint; paused metadata
                    // must immediately process deletion/invalid hosts instead.
                    if paused && cause == "pointer" {continue}
                    let e=try prepared(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
                    var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
                    let run=try F.start(e.handle(.leafCarry(.preview)))
                    try reach(phase,in:e,run:run)
                    let placed=e.carriedObjectSnapshot().first?.state == .placed
                    let token=try XCTUnwrap(F.tokens(e).first),actual=bird.position
                    if paused {e.handle(.pause(true))}
                    var replacement:BehaviorRunID?
                    switch cause {
                    case "click":e.handle(.pointerClick)
                    case "relocate":replacement=try F.start(e.handle(.relocate(id)))
                    case "removeBird":e.handle(.remove(id))
                    case "removeLeaf":e.handle(.removeCarryLeaf)
                    case "clearProps":e.handle(.clearProps)
                    case "clearScene":e.handle(.clearCurrentScene)
                    case "disable":var settings=e.settings;settings.leafCarryEnabled=false;e.applySettings(settings)
                    case "host":var world=e.world;world.surfaces=[];e.updateWorld(world)
                    case "pid":var world=e.world;world.surfaces[0]=Surface(id:F.host.id,pid:F.host.pid+1,rect:F.host.rect);e.updateWorld(world)
                    case "layer":var world=e.world;world.surfaces[0]=Surface(id:F.host.id,pid:F.host.pid,rect:F.host.rect,layer:1);e.updateWorld(world)
                    case "frames":var world=e.world;world.availableFrames[.treeSparrow]?.remove("carryPlace");e.updateWorld(world)
                    case "art":var world=e.world;world.leafCarryArtAvailable=false;e.updateWorld(world)
                    case "screens":var world=e.world;world.screens[0].size.width-=1;e.updateWorld(world)
                    case "display":var world=e.world;world.displays[0].size.width-=1;e.updateWorld(world)
                    case "scale":var world=e.world;world.scale*=1.1;e.updateWorld(world)
                    case "buttons":var world=e.world;world.buttonsDown=true;e.updateWorld(world)
                    case "pointer":var world=e.world;world.pointer=bird.position;e.updateWorld(world)
                    case "sleep":e.handle(.cancelAmbient(.sleep))
                    case "space":e.handle(.cancelAmbient(.spaceChanged))
                    default:e.handle(.cancelAmbient(.shutdown))
                    }
                    let context="\(phase) / \(cause) / paused=\(paused)"
                    XCTAssertEqual(bird.position,actual,context)
                    XCTAssertEqual(F.terminals(e,run).count,1,context)
                    XCTAssertNotEqual(F.terminals(e,run).first?.type,.completed,context)
                    XCTAssertNil(e.runtime.runs[run]);XCTAssertFalse(e.runtime.owners.values.contains(run))
                    XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.habitatReservationCount,0)
                    XCTAssertFalse(e.ambientBusy);XCTAssertTrue(observations.isEmpty)
                    XCTAssertFalse(e.carriedObjectSnapshot().contains{$0.owner != nil || $0.reservedByRun != nil})
                    let keepsPlaced=placed && ["click","relocate","removeBird","frames","buttons","pointer"].contains(cause)
                    if keepsPlaced {
                        XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.placed,context)
                        XCTAssertEqual(F.tokens(e).first?.id,token.id)
                        XCTAssertEqual(F.tokens(e).first?.rect,token.rect)
                    } else if let fading=F.tokens(e).first {
                        XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.retired,context)
                        XCTAssertEqual(fading.id,token.id);XCTAssertEqual(fading.rect,token.rect)
                    }
                    if let replacement {XCTAssertEqual(e.runtime.owners[id],replacement)}
                    e.handle(.pause(false));F.advance(e,2.1)
                    if !keepsPlaced {XCTAssertTrue(e.carriedObjectSnapshot().isEmpty,context)}
                    XCTAssertEqual(F.terminals(e,run).count,1);XCTAssertTrue(observations.isEmpty)
                    e.handle(.cancelAmbient(.sleep));XCTAssertEqual(e.activeRunCount,0)
                    XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
                }
            }
        }
    }

    func testPlacedLeafAndNewBathCoexistButRecoveryStillHoldsTheGlobalEncounter() throws {
        for delayed in [false,true] {
            let e=try prepared(),run=try F.start(e.handle(.leafCarry(.preview)))
            try reach(.recover,in:e,run:run)
            let object=try XCTUnwrap(e.carriedObjectSnapshot().first),token=try XCTUnwrap(F.tokens(e).first)
            XCTAssertEqual(object.state,.placed);XCTAssertNil(e.sceneFocus);XCTAssertEqual(e.activeRunCount,1)
            if delayed {
                var world=e.world;world.pointer=CGPoint(x:1700,y:650);e.updateWorld(world)
                XCTAssertEqual(e.handle(.placeBathAfter(0)),.scheduled)
                e.advance(BehaviorEngine.step)
            } else {XCTAssertTrue(e.handle(.placeBath(at:CGPoint(x:1700,y:650))).accepted)}
            XCTAssertEqual(e.habitatSnapshot().first?.kind,.bath)
            let focus=try XCTUnwrap(e.sceneFocus);XCTAssertNotNil(focus.objectID)
            XCTAssertEqual(e.carriedObjectSnapshot().first?.id,object.id)
            XCTAssertEqual(F.tokens(e).first?.rect,token.rect)
            for command:EngineCommand in [.bathVisit(.preview),.foodTrayVisit(.preview),.fixedPerchVisit(.preview),
                                          .leafCarry(.preview),.flockPass(.preview)] {
                XCTAssertEqual(e.handle(command),.rejected(.busy))
            }
            F.advance(e,0.5)
            F.assertReleased(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            XCTAssertEqual(e.sceneFocus,focus,"The old leaf's terminal must not clear a replacement bath focus")
            XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.placed)
            F.advance(e,8)
            XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertEqual(e.sceneFocus,focus)
            XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3)
        }
    }

    func testAvailableLeafAndFoodTrayCoexistInEitherPlacementOrderIncludingDelayedPlacement() throws {
        for leafFirst in [false,true] {
            for delayed in [false,true] {
                let e=F.engine(species:nil),food=CGPoint(x:1700,y:650)
                if leafFirst {XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)}
                else {XCTAssertTrue(e.handle(.placeFoodTray(at:food)).accepted)}
                if delayed {
                    var world=e.world;world.pointer=leafFirst ? food:F.point;e.updateWorld(world)
                    XCTAssertEqual(e.handle(leafFirst ? .placeFoodTrayAfter(0):.placeCarryLeafAfter(0)),.scheduled)
                    e.advance(BehaviorEngine.step)
                } else {XCTAssertTrue(e.handle(leafFirst ? .placeFoodTray(at:food):.placeCarryLeaf(at:F.point)).accepted)}
                XCTAssertEqual(e.habitatSnapshot().first?.kind,.foodTray)
                XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available)
                XCTAssertEqual(e.sceneFocus?.leafID,e.carriedObjectSnapshot().first?.id)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.habitatSnapshot().count,1)
                e.handle(.removeFoodTray);F.advance(e,2.1)
                XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available)
                XCTAssertNotNil(e.sceneFocus?.leafID)
                e.handle(.removeCarryLeaf);F.advance(e,0.3)
                XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
            }
        }
    }

    func testHardDeadlineAndExternalRouteReplacementFailWithoutCompletionOrDuplicateObjects() throws {
        for timeout in [false,true] {
            let e=try prepared(),bird=e.birds[0],run=try F.start(e.handle(.leafCarry(.preview)))
            try reach(.grip,in:e,run:run)
            let actual=bird.position
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            var revision=bird.motionRevision
            if timeout {e.runtime.advance(25.01,in:e)}
            else {
                bird.fly(to:CGPoint(x:1900,y:1100),host:F.host,arc:0,allowsOrbit:false,random:{0.5})
                revision=bird.motionRevision;e.updateWorld(e.world)
            }
            F.assertReleased(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.failed])
            XCTAssertEqual(F.terminals(e,run).first?.reason,timeout ? .timedOut:.targetInvalid)
            XCTAssertEqual(bird.position,actual);XCTAssertTrue(observations.isEmpty)
            if !timeout {XCTAssertEqual(bird.motionRevision,revision)}
            F.advance(e,0.3);XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
            if !timeout {XCTAssertEqual(bird.motionRevision,revision)}
            XCTAssertTrue(observations.isEmpty);XCTAssertEqual(F.terminals(e,run).count,1)
        }
    }

    func testPausedDeletionThenRelocationDoesNotInstallASecondRecoveryRouteOnResume() throws {
        let e=try prepared(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
        let carry=try F.start(e.handle(.leafCarry(.preview)))
        try reach(.carry,in:e,run:carry);F.advance(e,0.1)
        e.handle(.pause(true));let actual=bird.position
        e.handle(.removeCarryLeaf)
        F.assertReleased(e,carry);XCTAssertEqual(F.terminals(e,carry).map(\.type),[.cancelled])
        XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertEqual(bird.position,actual)
        let relocation=try F.start(e.handle(.relocate(id))),revision=bird.motionRevision
        F.advance(e,0.1);XCTAssertNotEqual(bird.position,actual)
        e.handle(.pause(false));F.advance(e,0.1)
        XCTAssertEqual(e.runtime.owners[id],relocation);XCTAssertEqual(bird.motionRevision,revision)
        F.advance(e,30)
        XCTAssertEqual(F.terminals(e,relocation).map(\.type),[.completed])
        XCTAssertEqual(F.terminals(e,carry).map(\.type),[.cancelled])
    }
}
