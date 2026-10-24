import XCTest
@testable import BirdingCore

final class VisitorGiftAuthorizationIntegrationTests:XCTestCase {
    private typealias F=VisitorGiftTestSupport
    private func grant(_ binding:GiftBinding)->GiftAuthorizationResult {
        .init(granted:.init(id:F.tokenID,binding:binding))
    }

    func testUniquePendingBindsAllIdentitiesWithoutLeasingOrMovingBeforeExternalGrant() throws {
        let e=try F.prepared(),bird=e.birds[0],leaf=try XCTUnwrap(e.carriedObjectSnapshot().first)
        let position=bird.position,revision=bird.motionRevision
        var requests:[GiftAuthorizationRequest]=[];e.giftAuthorizationObserver={requests.append($0)}
        XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled)
        let request=try XCTUnwrap(e.giftAuthorizationRequest),binding=request.binding
        XCTAssertEqual(requests,[request]);XCTAssertTrue(binding.isValid)
        XCTAssertEqual(binding.birdID,e.id(of:bird));XCTAssertEqual(binding.leafID,leaf.id)
        XCTAssertEqual(binding.species,F.species);XCTAssertEqual(binding.source,.preview)
        XCTAssertEqual(binding.visitorID,"99");XCTAssertEqual(binding.visitorArchiveSeed,"73")
        XCTAssertEqual(binding.receiverSlot,1);XCTAssertGreaterThan(binding.receiverRevision,0)
        XCTAssertTrue(e.ambientBusy);XCTAssertEqual(e.activeRunCount,0)
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        XCTAssertTrue(e.runtime.giftReceiverReservations.isEmpty);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
        XCTAssertNil(e.carriedObjectSnapshot().first?.reservedByRun)
        for command:EngineCommand in [.visitorGift(.preview),.leafCarry(.preview),.fixedPerchVisit(.preview),
                                      .foodTrayVisit(.preview),.bathVisit(.preview)] {
            XCTAssertEqual(e.handle(command),.rejected(.busy))
        }
        F.advance(e,6)
        XCTAssertEqual(e.giftAuthorizationRequest,request,"Five seconds is a platform timeout input, never a simulation timer")
        XCTAssertEqual(requests.count,1);XCTAssertEqual(bird.position,position);XCTAssertEqual(bird.motionRevision,revision)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.id,leaf.id)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available)
        XCTAssertNil(e.carriedObjectSnapshot().first?.giftDelivery)
        e.receiveGiftAuthorization(grant(binding))
        let run=try XCTUnwrap(e.runtime.runs.values.first{$0.execution.kind == .visitorGift})
        XCTAssertEqual(e.activeGiftAuthorizationCount,1);XCTAssertNil(e.giftAuthorizationRequest)
        F.finish(e,run.id);F.released(e,run.id)
        XCTAssertEqual(F.terminals(e,run.id).map(\.type),[.completed]);XCTAssertEqual(requests.count,1)
    }

    func testGrantForAnyDifferentBindingCannotAuthorizeThePendingObjectOrDisplaceItsRequest() throws {
        let e=try F.prepared()
        XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled)
        let pending=try XCTUnwrap(e.giftAuthorizationRequest),b=pending.binding
        let alternatives:[GiftBinding]=[
            GiftBinding(requestID:"2",visitorArchiveSeed:b.visitorArchiveSeed,visitorID:b.visitorID,birdID:b.birdID,species:b.species,source:b.source,leafID:b.leafID,receiverSlot:b.receiverSlot,receiverRevision:b.receiverRevision),
            GiftBinding(requestID:b.requestID,visitorArchiveSeed:"74",visitorID:b.visitorID,birdID:b.birdID,species:b.species,source:b.source,leafID:b.leafID,receiverSlot:b.receiverSlot,receiverRevision:b.receiverRevision),
            GiftBinding(requestID:b.requestID,visitorArchiveSeed:b.visitorArchiveSeed,visitorID:"100",birdID:b.birdID,species:b.species,source:b.source,leafID:b.leafID,receiverSlot:b.receiverSlot,receiverRevision:b.receiverRevision),
            GiftBinding(requestID:b.requestID,visitorArchiveSeed:b.visitorArchiveSeed,visitorID:b.visitorID,birdID:BirdID(2),species:b.species,source:b.source,leafID:b.leafID,receiverSlot:b.receiverSlot,receiverRevision:b.receiverRevision),
            GiftBinding(requestID:b.requestID,visitorArchiveSeed:b.visitorArchiveSeed,visitorID:b.visitorID,birdID:b.birdID,species:.treeSparrow,source:b.source,leafID:b.leafID,receiverSlot:b.receiverSlot,receiverRevision:b.receiverRevision),
            GiftBinding(requestID:b.requestID,visitorArchiveSeed:b.visitorArchiveSeed,visitorID:b.visitorID,birdID:b.birdID,species:b.species,source:.automatic,leafID:b.leafID,receiverSlot:b.receiverSlot,receiverRevision:b.receiverRevision),
            GiftBinding(requestID:b.requestID,visitorArchiveSeed:b.visitorArchiveSeed,visitorID:b.visitorID,birdID:b.birdID,species:b.species,source:b.source,leafID:ScenePropID(2),receiverSlot:b.receiverSlot,receiverRevision:b.receiverRevision),
            GiftBinding(requestID:b.requestID,visitorArchiveSeed:b.visitorArchiveSeed,visitorID:b.visitorID,birdID:b.birdID,species:b.species,source:b.source,leafID:b.leafID,receiverSlot:2,receiverRevision:b.receiverRevision),
            GiftBinding(requestID:b.requestID,visitorArchiveSeed:b.visitorArchiveSeed,visitorID:b.visitorID,birdID:b.birdID,species:b.species,source:b.source,leafID:b.leafID,receiverSlot:b.receiverSlot,receiverRevision:b.receiverRevision+1)
        ]
        for other in alternatives {
            e.receiveGiftAuthorization(grant(other))
            XCTAssertEqual(e.giftAuthorizationRequest,pending)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
            XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available)
            XCTAssertNil(e.carriedObjectSnapshot().first?.giftDelivery)
        }
        e.receiveGiftAuthorization(grant(b))
        let run=try XCTUnwrap(e.runtime.runs.values.first{$0.execution.kind == .visitorGift})
        e.receiveGiftAuthorization(grant(b))
        XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.activeGiftAuthorizationCount,1)
        XCTAssertEqual(e.events.filter{$0.kind == .visitorGift && $0.type == .started}.count,1)
        F.finish(e,run.id);F.released(e,run.id)
        e.receiveGiftAuthorization(grant(b))
        XCTAssertEqual(e.events.filter{$0.kind == .visitorGift && $0.type == .started}.count,1)
        XCTAssertEqual(e.carriedObjectSnapshot().count,1)
    }

    func testExplicitPlatformTimeoutDeniesWithoutRefundOrAutomaticRetryAndLateGrantCannotAuthorizeNextRequest() throws {
        let e=try F.prepared();var requests:[GiftAuthorizationRequest]=[]
        e.giftAuthorizationObserver={requests.append($0)}
        XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled)
        let first=try XCTUnwrap(e.giftAuthorizationRequest)
        F.advance(e,5)
        XCTAssertEqual(e.giftAuthorizationRequest,first)
        e.receiveGiftAuthorization(.init(denied:first.binding,reason:.timedOut))
        XCTAssertNil(e.giftAuthorizationRequest);XCTAssertEqual(e.lastGiftAuthorizationDenial,.timedOut)
        XCTAssertEqual(e.events.last?.reason,.timedOut);XCTAssertFalse(e.ambientBusy)
        XCTAssertEqual(e.activeGiftAuthorizationCount,0);XCTAssertEqual(e.activeRunCount,0)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available)
        F.advance(e,1);XCTAssertEqual(requests.count,1)
        XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled)
        let second=try XCTUnwrap(e.giftAuthorizationRequest)
        XCTAssertNotEqual(first.binding.requestID,second.binding.requestID)
        e.receiveGiftAuthorization(grant(first.binding))
        e.receiveGiftAuthorization(.init(denied:first.binding,reason:.timedOut))
        XCTAssertEqual(e.giftAuthorizationRequest,second);XCTAssertEqual(e.activeRunCount,0)
        e.receiveGiftAuthorization(grant(second.binding))
        let run=try XCTUnwrap(e.runtime.runs.values.first{$0.execution.kind == .visitorGift})
        e.handle(.pointerClick)
        XCTAssertEqual(F.terminals(e,run.id).map(\.type),[.cancelled])
        XCTAssertEqual(requests.count,2,"Cancellation emits no replacement grant or refund request")
        e.receiveGiftAuthorization(grant(second.binding));F.advance(e,0.3)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
        XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertEqual(requests.count,2)
    }

    func testPendingInterruptInvalidatesLateGrantWithoutReclaimingUnstartedUserLeaf() throws {
        for cause in ["click","cancel","pause","relocate","removeBird","disable","receiverRevision","leaf","frames","sleep"] {
            let e=try F.prepared(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
            XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled)
            let binding=try XCTUnwrap(e.giftAuthorizationRequest).binding
            switch cause {
            case "click":e.handle(.pointerClick)
            case "cancel":e.handle(.cancelVisitorGiftRequest)
            case "pause":e.handle(.pause(true))
            case "relocate":_=e.handle(.relocate(id))
            case "removeBird":e.handle(.remove(id))
            case "disable":var s=e.settings;s.visitorGiftsEnabled=false;e.applySettings(s)
            case "receiverRevision":
                var s=e.settings;s.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"gift-display",displayFrame:F.display(),x:0.74,y:0.5)]
                e.applySettings(s)
            case "leaf":e.handle(.removeCarryLeaf)
            case "frames":var w=e.world;w.availableFrames[F.species]?.remove("carryGrip");e.updateWorld(w)
            default:e.handle(.cancelAmbient(.sleep))
            }
            XCTAssertNil(e.giftAuthorizationRequest,cause)
            e.receiveGiftAuthorization(grant(binding))
            XCTAssertEqual(e.activeGiftAuthorizationCount,0,cause)
            XCTAssertFalse(e.events.contains{$0.kind == .visitorGift && $0.type == .started},cause)
            XCTAssertTrue(e.runtime.giftReceiverReservations.isEmpty,cause)
            if !["leaf","sleep"].contains(cause) {
                XCTAssertEqual(e.carriedObjectSnapshot().first?.id,binding.leafID,cause)
                XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available,cause)
                XCTAssertFalse(e.carriedObjectSnapshot().first?.isVisitorGift ?? true,cause)
            }
        }
    }

    func testSameGeometryReceiverRecreationAnchorIdentityAndDisplayIdentityInvalidateOldAuthorization() throws {
        for change in ["deleteRecreate","anchorIdentity","displayIdentity"] {
            let e=try F.prepared(),originalSettings=e.settings
            let originalPerch=try XCTUnwrap(e.fixedPerchSnapshot().first)
            XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled)
            let old=try XCTUnwrap(e.giftAuthorizationRequest).binding
            switch change {
            case "deleteRecreate":
                var removed=originalSettings;removed.fixedPerches=[];e.applySettings(removed)
                e.applySettings(originalSettings)
            case "anchorIdentity":
                // With one display the fallback resolves the very same pixels;
                // a changed saved anchor identity must still revise its binding.
                var settings=originalSettings
                settings.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"different-saved-display",
                    displayFrame:F.display(),x:0.75,y:0.5)]
                e.applySettings(settings)
            default:
                var world=e.world;world.displayIDs=["different-physical-display"];e.updateWorld(world)
            }
            let current=try XCTUnwrap(e.fixedPerchSnapshot().first)
            XCTAssertEqual(current.slot,originalPerch.slot);XCTAssertEqual(current.foot,originalPerch.foot)
            XCTAssertEqual(current.rect,originalPerch.rect)
            XCTAssertNotEqual(e.giftReceiverRevision(slot:1),old.receiverRevision,change)
            XCTAssertNil(e.giftAuthorizationRequest,change)
            e.receiveGiftAuthorization(grant(old))
            XCTAssertEqual(e.activeRunCount,0,change);XCTAssertEqual(e.activeGiftAuthorizationCount,0,change)
            XCTAssertFalse(e.events.contains{$0.kind == .visitorGift && $0.type == .started},change)
            if change != "displayIdentity" {
                XCTAssertEqual(e.handle(.visitorGift(.preview)),.scheduled)
                let new=try XCTUnwrap(e.giftAuthorizationRequest)
                XCTAssertNotEqual(new.binding.requestID,old.requestID)
                e.receiveGiftAuthorization(grant(old))
                XCTAssertEqual(e.giftAuthorizationRequest,new)
                e.receiveGiftAuthorization(grant(new.binding))
                let run=try XCTUnwrap(e.runtime.runs.values.first{$0.execution.kind == .visitorGift})
                F.finish(e,run.id);F.released(e,run.id)
                XCTAssertEqual(F.terminals(e,run.id).map(\.type),[.completed])
            }
        }
    }
}
