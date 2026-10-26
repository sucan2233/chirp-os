import XCTest
@testable import BirdingCore

final class VisitorGiftAdmissionTests:XCTestCase {
    private typealias F=VisitorGiftTestSupport

    func testExistingVisitorVisitAndFamiliarityBoundariesAreRequiredEvenForPreview() throws {
        for (visits,calm,eligible) in [(1,180.0,false),(2,179.999,false),(2,180.0,true)] {
            let e=try F.engine(previousVisits:visits,calmSeconds:calm)
            XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.leafPoint())).accepted)
            let bird=e.birds[0],visitor=try XCTUnwrap(e.visitor(of:bird))
            XCTAssertEqual(visitor.visits,visits+1);XCTAssertEqual(visitor.familiarity,calm/300,accuracy:1e-12)
            XCTAssertEqual(visitor.id,"99");XCTAssertEqual(e.visitorMemoryArchive.seed,"73")
            if eligible {
                XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled)
                let binding=try XCTUnwrap(e.giftAuthorizationRequest).binding
                XCTAssertEqual(binding.visitorArchiveSeed,"73");XCTAssertEqual(binding.visitorID,"99")
                XCTAssertNotEqual(binding.visitorArchiveSeed,"9001","Profile temperament seed is not the archive namespace")
                e.handle(.cancelVisitorGiftRequest)
            } else {
                XCTAssertEqual(e.handle(.visitorGift(.preview)),.rejected(.notFamiliar))
                XCTAssertNil(e.giftAuthorizationRequest)
            }
            XCTAssertEqual(e.activeGiftAuthorizationCount,0);XCTAssertEqual(e.activeRunCount,0)
            XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available)
            XCTAssertFalse(e.carriedObjectSnapshot().first?.isVisitorGift ?? true)
        }
    }

    func testPreviewNeverBypassesSwitchesSpeciesContentOrdinarySupportOrReceiverGeometry() throws {
        XCTAssertEqual(VisitorGiftPlan.requiredFrames,F.frames.subtracting(["blink"]))
        for condition in ["disabled","memory","perches","probability","noBird","noLeaf","noReceiver","fixedBranch","art","perchArt"]+VisitorGiftPlan.requiredFrames.sorted().map({"missing:\($0)"}) {
            let e=try F.prepared(),bird=e.birds[0]
            var reason:BehaviorReason = .noSpace
            switch condition {
            case "disabled":var s=e.settings;s.visitorGiftsEnabled=false;e.applySettings(s);reason = .disabled
            case "memory":var s=e.settings;s.visitorMemoryEnabled=false;e.applySettings(s);reason = .disabled
            case "perches":var s=e.settings;s.fixedPerchesEnabled=false;e.applySettings(s);reason = .disabled
            case "probability":
                var s=e.settings;let index=try XCTUnwrap(s.probabilities.entries.firstIndex{$0.id==F.species})
                s.probabilities.setManualWeight(at:index,to:0);e.applySettings(s);reason = .disabled
            case "noBird":e.handle(.remove(try XCTUnwrap(e.id(of:bird))));reason = .noSpecies
            case "noLeaf":e.handle(.removeCarryLeaf);F.advance(e,0.3)
            case "noReceiver":var s=e.settings;s.fixedPerches=[];e.applySettings(s)
            case "fixedBranch":
                let perch=try XCTUnwrap(e.fixedPerchSnapshot().first)
                bird.perch(on:perch.surface,spriteScale:e.spriteScale(for:bird));bird.tick(1.1)
            case "art":var w=e.world;w.leafCarryArtAvailable=false;e.updateWorld(w);reason = .missingFrames
            case "perchArt":var w=e.world;w.fixedPerchArtAvailable=false;e.updateWorld(w);reason = .missingFrames
            default:
                var w=e.world;w.availableFrames[F.species]?.remove(String(condition.dropFirst("missing:".count)))
                e.updateWorld(w);reason = .missingFrames
            }
            let objects=e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),position=bird.position
            var requests=0;e.giftAuthorizationObserver={_ in requests+=1}
            XCTAssertEqual(e.handle(.visitorGift(.preview)),.rejected(reason),condition)
            XCTAssertEqual(requests,0,condition);XCTAssertNil(e.giftAuthorizationRequest,condition)
            XCTAssertEqual(e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),objects,condition)
            XCTAssertEqual(bird.position,position,condition);XCTAssertEqual(e.activeRunCount,0,condition)
            XCTAssertEqual(e.activeGiftAuthorizationCount,0,condition);XCTAssertEqual(e.leasedBirdCount,0,condition)
        }
        let e=try F.prepared();var world=e.world;world.availableFrames[F.species]?.remove("blink");e.updateWorld(world)
        XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled,"Blink is optional for this transport contract")
        XCTAssertNotNil(e.giftAuthorizationRequest);e.handle(.cancelVisitorGiftRequest)
    }

    func testGiftAuthorizationDoesNotExpandLegacyLeafCarryOrFixedPerchSpecies() throws {
        let e=try F.prepared()
        e.handle(.remove(try XCTUnwrap(e.id(of:e.birds[1]))))
        XCTAssertEqual(e.birds.map{$0.profile.id},[F.species])
        XCTAssertFalse(SpeciesBehaviorProfile.profile(for:F.species).allows(.leafCarry))
        XCTAssertFalse(SpeciesBehaviorProfile.profile(for:F.species).allows(.fixedPerchVisit))
        XCTAssertEqual(e.handle(.leafCarry(.preview)),.rejected(.noSpecies))
        XCTAssertEqual(e.handle(.fixedPerchVisit(.preview)),.rejected(.noSpecies))
        let (run,_)=try F.authorize(e);F.finish(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed]);F.released(e,run)
    }

    func testARealExecutionCannotPickUpOrReleaseUsingAnUnregisteredToken() throws {
        let e=try F.prepared(),plan=try XCTUnwrap(VisitorGiftPlan.candidates(in:e,source:.preview).first)
        let binding=GiftBinding(requestID:"1",visitorArchiveSeed:"73",visitorID:"99",birdID:plan.id,
            species:F.species,source:.preview,leafID:plan.leafID,receiverSlot:plan.receiverSlot,
            receiverRevision:plan.receiverRevision)
        let token=GiftAuthorizationToken(id:F.tokenID,binding:binding)
        let original=e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),position=e.birds[0].position
        let execution=VisitorGiftExecution(plan:plan,token:token)
        guard case .started(let run)=e.runtime.start(execution,source:.preview,in:e) else {
            return XCTFail("The runtime admits the real execution; execution must enforce the unregistered grant")
        }
        e.advance(BehaviorEngine.step)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.failed])
        XCTAssertFalse(execution.pickedUp);XCTAssertFalse(execution.released);XCTAssertFalse(execution.delivered)
        XCTAssertEqual(e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init).map(\.id),original.map(\.id))
        XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available)
        XCTAssertFalse(e.carriedObjectSnapshot().first?.isVisitorGift ?? true)
        XCTAssertEqual(e.birds[0].position,position);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
        XCTAssertTrue(e.runtime.giftReceiverReservations.isEmpty)
        XCTAssertNotNil(e.sceneFocus,"The rejected execution cannot reclaim an unreserved user's leaf")
    }

    func testOrdinaryPlacedLeafIsReusedWithoutCopyAndFeatureControlsEightVersusSixHundredSeconds() throws {
        for enabled in [false,true] {
            let e=try F.prepared(ordinaryCarryFirst:true),objectID=try XCTUnwrap(e.carriedObjectSnapshot().first?.id)
            var s=e.settings;s.visitorGiftsEnabled=enabled;e.applySettings(s)
            let run=try LeafCarryTestSupport.start(e.handle(.leafCarry(.preview)))
            for _ in 0..<25*60 {
                if e.carriedObjectSnapshot().first?.state == .placed {break}
                e.advance(BehaviorEngine.step)
            }
            let placed=try XCTUnwrap(e.carriedObjectSnapshot().first)
            XCTAssertEqual(placed.id,objectID);XCTAssertEqual(placed.state,.placed)
            XCTAssertEqual(placed.remainingLifetime,enabled ? 600:8,accuracy:BehaviorEngine.step+1e-8)
            XCTAssertFalse(placed.isVisitorGift);XCTAssertNil(e.sceneFocus)
            for _ in 0..<60 {if e.runtime.runs[run]==nil {break};e.advance(BehaviorEngine.step)}
            XCTAssertEqual(LeafCarryTestSupport.terminals(e,run).map(\.type),[.completed])
            if enabled {
                // The sparrow is still standing beside its real placement;
                // remove that resident through the public command before the
                // larger carrier can approach the same physical object.
                e.handle(.remove(try XCTUnwrap(e.id(of:e.birds[1]))))
                let (gift,_)=try F.authorize(e);F.finish(e,gift);F.released(e,gift)
                XCTAssertEqual(F.terminals(e,gift).map(\.type),[.completed])
                XCTAssertEqual(e.carriedObjectSnapshot().map(\.id),[objectID])
                XCTAssertTrue(e.carriedObjectSnapshot().first?.isVisitorGift ?? false)
                XCTAssertTrue(try XCTUnwrap(e.carriedObjectSnapshot().first?.giftDelivery).arrived)
            } else {
                F.advance(e,8.3);XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
                XCTAssertEqual(e.handle(.visitorGift(.preview)),.rejected(.disabled))
            }
        }
    }

    func testDeliveredGiftProtectsReceiverForItsLifetimeAndClearingRestoresActualFixedPerchAccess() throws {
        let e=try F.prepared(),(run,_)=try F.authorize(e)
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        let receiver=try XCTUnwrap(e.fixedPerchSnapshot().first),leaf=try XCTUnwrap(F.token(e))
        XCTAssertFalse(e.giftObstacleRects().isEmpty)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
        XCTAssertEqual(e.handle(.fixedPerchVisit(.preview)),.rejected(.noSpace))
        F.advance(e,20)
        XCTAssertEqual(F.token(e)?.id,leaf.id)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
        XCTAssertFalse(e.birds.contains{$0.hostID==receiver.surface.id})
        e.handle(.clearVisitorGift)
        XCTAssertTrue(e.giftObstacleRects().isEmpty);XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
        let visit=try LeafCarryTestSupport.start(e.handle(.fixedPerchVisit(.preview)))
        F.advance(e,30)
        XCTAssertEqual(F.terminals(e,visit).map(\.type),[.completed])
        XCTAssertTrue(e.birds.contains{$0.profile.id == .treeSparrow && $0.hostID==receiver.surface.id})
        XCTAssertFalse(e.birds.contains{$0.profile.id==F.species && $0.hostID==receiver.surface.id})
    }

    func testGiftAndLegacyFoodTrayOrFixedPerchRunsAreBusyInBothDirections() throws {
        for fixed in [false,true] {
            let e=try F.prepared();F.advance(e,9)
            if !fixed {
                var world=e.world
                world.availableFrames[.treeSparrow]?.formUnion(["feedLook","feedDown0","feedDown1","feedLift"])
                e.updateWorld(world)
                XCTAssertTrue(e.handle(.placeFoodTray(at:CGPoint(x:1800,y:650))).accepted)
            }
            let command:EngineCommand=fixed ? .fixedPerchVisit(.preview):.foodTrayVisit(.preview)
            let old=try LeafCarryTestSupport.start(e.handle(command))
            let position=e.birds[0].position,leaf=try XCTUnwrap(e.carriedObjectSnapshot().first?.id)
            XCTAssertEqual(e.handle(.visitorGift(.preview)),.rejected(.busy))
            XCTAssertNotNil(e.runtime.runs[old]);XCTAssertEqual(e.birds[0].position,position)
            XCTAssertEqual(e.carriedObjectSnapshot().first?.id,leaf)
            XCTAssertNil(e.giftAuthorizationRequest);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
            e.handle(.cancelAmbient(.shutdown))
        }
        let e=try F.prepared(),(run,_)=try F.authorize(e)
        for command:EngineCommand in [.foodTrayVisit(.preview),.fixedPerchVisit(.preview),.leafCarry(.preview),.bathVisit(.preview)] {
            XCTAssertEqual(e.handle(command),.rejected(.busy))
            XCTAssertNotNil(e.runtime.runs[run]);XCTAssertEqual(e.activeGiftAuthorizationCount,1)
        }
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
    }
}
