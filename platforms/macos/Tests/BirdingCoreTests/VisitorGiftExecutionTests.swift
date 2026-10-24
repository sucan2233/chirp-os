import XCTest
@testable import BirdingCore

final class VisitorGiftExecutionTests:XCTestCase {
    private typealias F=VisitorGiftTestSupport
    private let phases:[VisitorGiftExecution.Phase]=[.approach,.pickup,.carrying,.releasing,.returning]

    func testActualFamiliarMagpieDeliversSameLeafAndReturnsToOrdinaryHostAtThreeScalesAndBothHeadings() throws {
        for scale:CGFloat in [0.5,1,2] {
            for right in [false,true] {
                let e=try F.prepared(scale:scale,right:right),bird=e.birds[0]
                let identities=e.birds.map(ObjectIdentifier.init),leaf=try XCTUnwrap(e.carriedObjectSnapshot().first)
                let visitor=try XCTUnwrap(e.visitor(of:bird))
                XCTAssertEqual(visitor.id,"99");XCTAssertEqual(visitor.visits,3)
                XCTAssertGreaterThanOrEqual(visitor.familiarity,0.6);XCTAssertEqual(e.visitorMemoryArchive.seed,"73")
                var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
                let (run,active)=try F.authorize(e),plan=active.plan
                XCTAssertEqual(active.timeout,35);XCTAssertEqual(plan.releaseClip.duration,0.3,accuracy:1e-12)
                XCTAssertLessThanOrEqual(plan.maximumPlannedDuration,35)
                XCTAssertFalse(try XCTUnwrap(plan.pickup.host(in:e.world)).isFixedPerch)
                XCTAssertFalse(try XCTUnwrap(plan.destination.host(in:e.world)).isFixedPerch)
                XCTAssertEqual(e.activeGiftAuthorizationCount,1);XCTAssertEqual(e.runtime.giftReceiverReservations.count,1)
                XCTAssertEqual(e.residentCount,2);XCTAssertEqual(e.leasedBirdCount,1)
                let speed=(plan.approach.route.legs+plan.carrying.legs).map{$0.timing.peakSpeed}.max()!
                var seen=Set<VisitorGiftExecution.Phase>(),pickupCount=0,releaseCount=0
                var releaseTime:Double?,arrivalTime:Double?,arrivalLifetime:Double?
                for _ in 0..<35*60+1 {
                    guard e.runtime.runs[run] != nil else {break}
                    seen.insert(active.phase)
                    let object=try XCTUnwrap(e.carriedObjectSnapshot().first),token=try XCTUnwrap(F.token(e))
                    let pose=try XCTUnwrap(e.renderSnapshot().first{$0.id==plan.id})
                    XCTAssertEqual(e.carriedObjectSnapshot().count,1);XCTAssertEqual(object.id,leaf.id)
                    XCTAssertEqual(token.id,leaf.id);XCTAssertEqual(token.size,16*scale)
                    XCTAssertEqual(token.mirrored,!right);XCTAssertEqual(token.rotation,0)
                    XCTAssertTrue(F.display(scale).contains(token.rect));XCTAssertTrue(F.display(scale).contains(pose.rect))
                    XCTAssertNotEqual(bird.hostID,e.fixedPerchSnapshot().first?.surface.id)
                    if object.state == .attached {
                        XCTAssertEqual(object.owner,plan.id);XCTAssertEqual(object.remainingLifetime,0)
                        let anchor=try XCTUnwrap(PoseClip.carryBeakAnchor(species:F.species,frame:pose.frameName))
                        let beak=anchor.world(foot:CGPoint(x:bird.position.x,y:bird.position.y+pose.hopOffset*pose.scale),
                            scale:pose.scale,facingRight:pose.facingRight)
                        XCTAssertEqual(token.position.x,beak.x,accuracy:1e-8)
                        XCTAssertEqual(token.position.y,beak.y,accuracy:1e-8)
                    }
                    if let delivery=object.giftDelivery {
                        XCTAssertLessThanOrEqual(delivery.duration,0.8)
                        XCTAssertEqual(delivery.receiverSlot,1)
                        if delivery.arrived,arrivalTime==nil {arrivalTime=e.time;arrivalLifetime=object.remainingLifetime}
                    }
                    XCTAssertTrue(observations.isEmpty,"Visible release alone is insufficient until the bird safely returns")
                    let before=bird.position,time=e.time,state=object.state
                    e.advance(BehaviorEngine.step)
                    XCTAssertLessThanOrEqual(Geometry.distance(before,bird.position),CGFloat(speed*(e.time-time))+0.002)
                    let after=try XCTUnwrap(e.carriedObjectSnapshot().first)
                    if state != after.state {
                        let next=try XCTUnwrap(F.token(e))
                        XCTAssertEqual(next.rect.size,token.rect.size);XCTAssertEqual(next.mirrored,token.mirrored)
                        if after.state == .attached {
                            // Grounded pickup is an atomic pivot change with
                            // identical canvas bounds, not another motion step.
                            XCTAssertEqual(next.rect.minX,token.rect.minX,accuracy:0.001)
                            XCTAssertEqual(next.rect.minY,token.rect.minY,accuracy:0.001)
                            pickupCount+=1
                        }
                        if after.giftDelivery != nil {
                            // Release follows Bird.tick. Compare against this
                            // tick's authored carryPlace beak, not the old foot.
                            // Magpie release bill is (42,23), mirrored (6,23);
                            // the grounded grip's (40,39) is a different pose.
                            let beak=PoseClip.Anchor(42,23).world(foot:bird.position,
                                scale:plan.birdScale,facingRight:right)
                            XCTAssertEqual(next.position.x,beak.x,accuracy:1e-8)
                            XCTAssertEqual(next.position.y,beak.y,accuracy:1e-8)
                            XCTAssertLessThanOrEqual(Geometry.distance(token.rect.origin,next.rect.origin),
                                CGFloat(speed*(e.time-time))+0.002)
                            releaseCount+=1;releaseTime=e.time
                        }
                    }
                }
                F.released(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
                XCTAssertEqual(seen,Set(phases));XCTAssertEqual(pickupCount,1);XCTAssertEqual(releaseCount,1)
                let arrivedAt=try XCTUnwrap(arrivalTime),releasedAt=try XCTUnwrap(releaseTime)
                XCTAssertLessThanOrEqual(arrivedAt-releasedAt,0.8+BehaviorEngine.step)
                XCTAssertEqual(try XCTUnwrap(arrivalLifetime),120,accuracy:BehaviorEngine.step+1e-8)
                let delivered=try XCTUnwrap(e.carriedObjectSnapshot().first),token=try XCTUnwrap(F.token(e))
                XCTAssertTrue(delivered.isVisitorGift);XCTAssertEqual(delivered.id,leaf.id)
                XCTAssertTrue(try XCTUnwrap(delivered.giftDelivery).arrived)
                XCTAssertNil(delivered.owner);XCTAssertNil(delivered.reservedByRun)
                let receiver=try XCTUnwrap(e.fixedPerchSnapshot().first)
                // Independent art contract: surface anchor (10,12), leaf 16px.
                XCTAssertEqual(token.rect.minX,receiver.foot.x-(right ? 10:6)*scale,accuracy:1e-8)
                XCTAssertEqual(token.rect.minY,receiver.foot.y-12*scale,accuracy:1e-8)
                XCTAssertEqual(bird.position,plan.destinationFoot);XCTAssertEqual(bird.state,.perched)
                XCTAssertEqual(observations.count,1);XCTAssertEqual(observations.first?.kind,.visitorGift)
                XCTAssertEqual(observations.first?.source,.preview);XCTAssertEqual(observations.first?.species,[F.species])
                let terminal=try XCTUnwrap(F.terminals(e,run).first)
                let started=try XCTUnwrap(e.events.first{$0.runID==run && $0.type == .started})
                XCTAssertLessThanOrEqual(terminal.time-started.time,35)
                XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
                XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                e.handle(.clearVisitorGift)
                XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertTrue(e.giftObstacleRects().isEmpty)
                XCTAssertEqual(observations.count,1)
            }
        }
    }

    func testPauseFreezesEveryActualPhaseAndDeliveredLifetimeThenExpiresOnlyTheSameEntity() throws {
        for phase in phases {
            let e=try F.prepared(),(run,active)=try F.authorize(e)
            try F.reach(phase,e,run)
            e.handle(.pause(true))
            let age=e.runtime.runs[run]?.age
            let before=BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            F.advance(e,20)
            let after=BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(after.props,before.props)
            XCTAssertEqual(after.carriedObjects,before.carriedObjects);XCTAssertEqual(active.phase,phase)
            XCTAssertEqual(after.activeGiftAuthorizationCount,before.activeGiftAuthorizationCount)
            XCTAssertEqual(after.giftReceiverReservations,before.giftReceiverReservations)
            XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
            XCTAssertEqual(e.runtime.runs[run]?.age,age)
            e.handle(.pause(false));F.finish(e,run);F.released(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            let object=try XCTUnwrap(e.carriedObjectSnapshot().first)
            e.handle(.pause(true));F.advance(e,150)
            XCTAssertEqual(e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),[RecordedCarriedObjectState(object)])
            e.handle(.pause(false));F.advance(e,object.remainingLifetime-0.1)
            XCTAssertEqual(e.carriedObjectSnapshot().first?.id,object.id)
            XCTAssertLessThan(try XCTUnwrap(F.token(e)).opacity,1)
            F.advance(e,0.4)
            XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertTrue(e.propSnapshot().isEmpty)
            XCTAssertTrue(e.giftObstacleRects().isEmpty);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
            XCTAssertEqual(F.terminals(e,run).count,1)
        }
    }

    func testEachPhaseInterruptReclaimsUnreleasedLeafButKeepsReleasedGiftWithoutCompletion() throws {
        for phase in phases {
            for paused in [false,true] {
                for cause in ["click","relocate","removeBird","clear","disable","memory","receiver","hostPID","frames","art","sleep"] {
                    let e=try F.prepared(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
                    let (run,active)=try F.authorize(e);try F.reach(phase,e,run)
                    var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
                    let released=active.released,position=bird.position,objectID=try XCTUnwrap(F.token(e)).id
                    if paused {e.handle(.pause(true))}
                    var replacement:BehaviorRunID?
                    switch cause {
                    case "click":e.handle(.pointerClick)
                    case "relocate":
                        if case .started(let value)=e.handle(.relocate(id)) {replacement=value}
                        else {XCTFail("User relocation must immediately replace the gift")}
                    case "removeBird":e.handle(.remove(id))
                    case "clear":e.handle(.clearVisitorGift)
                    case "disable":var s=e.settings;s.visitorGiftsEnabled=false;e.applySettings(s)
                    case "memory":var s=e.settings;s.visitorMemoryEnabled=false;e.applySettings(s)
                    case "receiver":var s=e.settings;s.fixedPerches=[];e.applySettings(s)
                    case "hostPID":var w=e.world;w.surfaces[0]=Surface(id:F.host().id,pid:99,rect:F.host().rect);e.updateWorld(w)
                    case "frames":var w=e.world;w.availableFrames[F.species]?.remove("carryPlace");e.updateWorld(w)
                    case "art":var w=e.world;w.leafCarryArtAvailable=false;e.updateWorld(w)
                    default:e.handle(.cancelAmbient(.sleep))
                    }
                    let context="\(phase)/\(cause)/paused=\(paused)"
                    XCTAssertEqual(bird.position,position,context)
                    XCTAssertNil(e.runtime.runs[run],context);XCTAssertEqual(F.terminals(e,run).count,1,context)
                    XCTAssertNotEqual(F.terminals(e,run).first?.type,.completed,context)
                    XCTAssertEqual(e.activeGiftAuthorizationCount,0,context);XCTAssertTrue(observations.isEmpty,context)
                    XCTAssertEqual(e.runtime.giftReceiverReservations.count,0,context)
                    XCTAssertFalse(e.carriedObjectSnapshot().contains{$0.owner != nil || $0.reservedByRun != nil},context)
                    if let replacement {XCTAssertEqual(e.runtime.owners[id],replacement)}
                    let keep=released && ["click","relocate","removeBird","hostPID","frames"].contains(cause)
                    if keep {XCTAssertEqual(e.carriedObjectSnapshot().first?.id,objectID,context)}
                    e.handle(.pause(false));F.advance(e,1)
                    if keep {
                        XCTAssertEqual(e.carriedObjectSnapshot().first?.id,objectID,context)
                        XCTAssertTrue(try XCTUnwrap(e.carriedObjectSnapshot().first?.giftDelivery).arrived,context)
                    } else {XCTAssertTrue(e.carriedObjectSnapshot().isEmpty,context)}
                    XCTAssertEqual(F.terminals(e,run).count,1,context);XCTAssertTrue(observations.isEmpty,context)
                    e.handle(.cancelAmbient(.shutdown))
                    XCTAssertTrue(e.carriedObjectSnapshot().isEmpty,context);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
                }
            }
        }
    }

    func testClearingCommandsKeepOrdinaryLeavesAndGiftEntitiesInTheirOwnDomains() throws {
        let e=try F.prepared(),ordinary=try XCTUnwrap(F.token(e)).id
        e.handle(.clearVisitorGift)
        XCTAssertEqual(F.token(e)?.id,ordinary);XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available)
        let (run,_)=try F.authorize(e);try F.reach(.carrying,e,run)
        e.handle(.removeCarryLeaf)
        XCTAssertNotNil(e.runtime.runs[run]);XCTAssertEqual(F.token(e)?.id,ordinary)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.attached)
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        let gift=try XCTUnwrap(F.token(e)),remaining=try XCTUnwrap(e.carriedObjectSnapshot().first).remainingLifetime
        e.handle(.removeCarryLeaf)
        XCTAssertEqual(F.token(e)?.rect,gift.rect);XCTAssertEqual(F.token(e)?.id,ordinary)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.remainingLifetime,remaining)
        e.handle(.pause(true));e.handle(.clearVisitorGift)
        XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertTrue(e.propSnapshot().isEmpty)
        XCTAssertTrue(e.giftObstacleRects().isEmpty);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
        e.handle(.pause(false))
        XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.leafPoint())).accepted)
        let replacement=try XCTUnwrap(F.token(e)).id;XCTAssertNotEqual(replacement,ordinary)
        e.handle(.clearVisitorGift);XCTAssertEqual(F.token(e)?.id,replacement)
        e.handle(.clearProps);F.advance(e,0.3)
        XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
    }

    func testAfterMotionHardDeadlineClipsTheLastRealBirdStepBeforeTimeoutCleanup() throws {
        let e=try F.prepared(),(run,active)=try F.authorize(e)
        let bird=e.birds[0],halfStep=BehaviorEngine.step/2,position=bird.position
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        // Seed only the runtime clock near its hard deadline. This is isolated
        // deadline evidence, not a claim that a natural route lasts 35 seconds.
        e.runtime.advance(35-halfStep,in:e)
        XCTAssertEqual(try XCTUnwrap(e.runtime.runs[run]).age,35-halfStep,accuracy:1e-10)
        XCTAssertEqual(bird.position,position);XCTAssertTrue(F.terminals(e,run).isEmpty)
        let expected=active.plan.approach.route.position(at:halfStep)
        e.advance(BehaviorEngine.step)
        XCTAssertEqual(bird.position.x,expected.x,accuracy:0.001)
        XCTAssertEqual(bird.position.y,expected.y,accuracy:0.001)
        XCTAssertGreaterThan(Geometry.distance(position,bird.position),0)
        F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.failed])
        XCTAssertEqual(F.terminals(e,run).first?.reason,.timedOut)
        XCTAssertFalse(active.released);XCTAssertTrue(observations.isEmpty)
        F.advance(e,0.3);XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
    }

    func testRealDeliveryWorksOnAFullyNegativeDisplayAndFromAnOrdinaryGroundStart() throws {
        for negative in [false,true] {
            let offset=negative ? CGPoint(x:-3000,y:-3000):.zero
            let e=try F.engine(offset:offset),bird=e.birds[0]
            if !negative {
                // Ground is only the resident's starting host. The leaf and
                // final landing still use an ordinary window's genuine ledge.
                let ground=Surface(id:1980,pid:42,rect:CGRect(x:200,y:2199,width:2000,height:1),isGround:true)
                var world=e.world;world.surfaces.append(ground);e.updateWorld(world)
                bird.perch(on:ground,spriteScale:e.spriteScale(for:bird));bird.tick(1.1)
                XCTAssertEqual(bird.hostID,ground.id)
            } else {
                XCTAssertLessThan(try XCTUnwrap(e.world.displays.first).maxX,0)
                XCTAssertLessThan(try XCTUnwrap(e.world.displays.first).maxY,0)
            }
            XCTAssertTrue(e.handle(.placeCarryLeaf(at:CGPoint(x:1000+offset.x,y:1700+offset.y))).accepted)
            let (run,active)=try F.authorize(e)
            for _ in 0..<35*60 {
                if e.runtime.runs[run]==nil {break}
                let display=try XCTUnwrap(e.world.displays.first)
                XCTAssertTrue(display.contains(try XCTUnwrap(F.token(e)).rect))
                XCTAssertTrue(display.contains(try XCTUnwrap(e.renderSnapshot().first{$0.id==active.plan.id}).rect))
                e.advance(BehaviorEngine.step)
            }
            F.released(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            XCTAssertTrue(try XCTUnwrap(e.carriedObjectSnapshot().first?.giftDelivery).arrived)
            XCTAssertEqual(bird.position,active.plan.destinationFoot)
            XCTAssertFalse(try XCTUnwrap(active.plan.destination.host(in:e.world)).isFixedPerch)
        }
    }

    func testCancelledReleaseContinuesItsBoundedFallPauseFreezesItAndCarrierHasNoPermanentCollisionExemption() throws {
        let e=try F.prepared(),bird=e.birds[0],(run,_)=try F.authorize(e)
        try F.reach(.returning,e,run)
        let object=try XCTUnwrap(e.carriedObjectSnapshot().first)
        XCTAssertFalse(try XCTUnwrap(object.giftDelivery).arrived)
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        e.handle(.pointerClick);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.cancelled])
        F.advance(e,0.1)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.id,object.id)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.placed)
        e.handle(.pause(true))
        let before=try XCTUnwrap(e.carriedObjectSnapshot().first),rect=try XCTUnwrap(F.token(e)).rect
        F.advance(e,10)
        XCTAssertEqual(e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),[RecordedCarriedObjectState(before)])
        XCTAssertEqual(F.token(e)?.rect,rect)
        e.handle(.pause(false));F.advance(e,0.55)
        XCTAssertTrue(try XCTUnwrap(e.carriedObjectSnapshot().first?.giftDelivery).arrived)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.id,object.id);XCTAssertTrue(observations.isEmpty)
        let receiver=try XCTUnwrap(e.fixedPerchSnapshot().first),leafRect=try XCTUnwrap(F.token(e)).rect
        // An external ordinary flight genuinely approaches the delivered leaf.
        // No bird, gift position, owner or terminal state is teleported.
        bird.fly(to:receiver.foot,host:nil,duration:2,arc:0,allowsOrbit:false,random:{0.5})
        var retired=false
        for _ in 0..<5*60 {
            e.advance(BehaviorEngine.step)
            if e.carriedObjectSnapshot().first?.state == .retired {
                retired=true;XCTAssertTrue(e.bounds(of:bird).intersects(leafRect));break
            }
        }
        XCTAssertTrue(retired,"Arrival ends even the original carrier's temporary separation exemption")
        F.advance(e,0.3);XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
        XCTAssertTrue(e.giftObstacleRects().isEmpty);XCTAssertTrue(observations.isEmpty)
        XCTAssertEqual(F.terminals(e,run).count,1)
    }
}
