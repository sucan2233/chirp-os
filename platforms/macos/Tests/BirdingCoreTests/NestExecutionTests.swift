import XCTest
@testable import BirdingCore

final class NestExecutionTests:XCTestCase {
    private typealias F=NestTestSupport
    private enum Boundary:CaseIterable {
        case approach,observe,lower,grip,lift,carry,place,recover,departure
    }
    private func reach(_ boundary:Boundary,_ e:BehaviorEngine,_ run:BehaviorRunID)throws {
        let active=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestMaterialCarryExecution)
        try F.until(e,run) {
            switch boundary {
            case .approach:return active.age>0.1 && !active.pickedUp && active.pickupAge==0
            case .observe:return active.pickupAge>=0.1 && active.pickupAge<0.4
            case .lower:return active.pickupAge>=0.5 && active.pickupAge<0.7
            case .grip:return active.pickupAge>=0.75 && active.pickupAge<0.9
            case .lift:return active.pickupAge>=1.0 && active.pickupAge<1.2
            case .carry:return active.pickedUp && !active.delivered && active.phase == .carry
            case .place:return active.placeAge>=0.2 && !active.delivered
            case .recover:return active.delivered && active.placeAge<0.7
            case .departure:return active.delivered && active.phase == .departure
            }
        }
    }

    func testRealTransportOnPositiveAndFullyNegativeScreensHasMirroredContactOneEntityAndSafeReturnAtThreeScales() throws {
        for scale:CGFloat in [0.5,1,2] {for negative in [false,true] {for right in [false,true] {for ground in [false,true] {
            let e=try F.prepared(scale:scale,negative:negative,right:right,ground:ground,screens:4)
            let bird=e.birds[0],identity=ObjectIdentifier(bird),origin=bird.position,initial=try F.nest(e)
            let ids=Set(initial.materials.map(\.id)),run=try F.start(e)
            let active=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestMaterialCarryExecution),plan=active.plan
            let material=plan.materialID,started=e.time
            let vmax=try XCTUnwrap((plan.approach.route.legs+plan.carrying.route.legs+plan.departure.route.legs).map{$0.timing.peakSpeed}.max())
            XCTAssertEqual(active.timeout,35);XCTAssertEqual(bird.position,origin)
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            var pickups=0,deliveries=0,sawAttached=false
            for _ in 0..<35*60 {
                guard e.runtime.runs[run] != nil else {break}
                try F.conserved(e,ids:ids)
                let value=try F.material(e,material),prop=try XCTUnwrap(F.tokens(e).first{$0.id==material})
                let render=try XCTUnwrap(e.renderSnapshot().first{$0.id==plan.id})
                XCTAssertTrue(e.world.displays[0].contains(render.rect));XCTAssertTrue(e.world.displays[0].contains(prop.rect))
                XCTAssertEqual(prop.size,16*scale);XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0)
                XCTAssertTrue(observations.isEmpty,"A delivered twig does not complete the exit flight")
                if value.state == .attached {
                    sawAttached=true;XCTAssertEqual(value.owner,plan.id);XCTAssertEqual(value.reservedByRun,run)
                    let anchor=try XCTUnwrap(PoseClip.nestBeakAnchor(species:.spottedDove,frame:render.frameName))
                    let beak=anchor.world(foot:CGPoint(x:bird.position.x,y:bird.position.y+render.hopOffset*render.scale),
                        scale:render.scale,facingRight:render.facingRight)
                    XCTAssertEqual(prop.position.x,beak.x,accuracy:1e-8);XCTAssertEqual(prop.position.y,beak.y,accuracy:1e-8)
                    let union=plan.localFootprint.offsetBy(dx:bird.position.x,dy:bird.position.y)
                    XCTAssertLessThanOrEqual(prop.rect.minX+1e-8,union.maxX)
                    XCTAssertGreaterThanOrEqual(prop.rect.minX,union.minX-1e-8);XCTAssertLessThanOrEqual(prop.rect.maxX,union.maxX+1e-8)
                    XCTAssertGreaterThanOrEqual(prop.rect.minY,union.minY-1e-8);XCTAssertLessThanOrEqual(prop.rect.maxY,union.maxY+1e-8)
                }
                let before=bird.position,time=e.time,rect=prop.rect
                e.advance(BehaviorEngine.step)
                XCTAssertLessThanOrEqual(Geometry.distance(before,bird.position),CGFloat(vmax*(e.time-time))+0.002)
                let after=try F.material(e,material)
                if value.state != after.state {
                    let next=try XCTUnwrap(F.tokens(e).first{$0.id==material})
                    if after.state == .attached {
                        pickups+=1
                        XCTAssertEqual(next.rect.minX,rect.minX,accuracy:0.001);XCTAssertEqual(next.rect.minY,rect.minY,accuracy:0.001)
                        XCTAssertEqual(next.rect.maxX,rect.maxX,accuracy:0.001);XCTAssertEqual(next.rect.maxY,rect.maxY,accuracy:0.001)
                        XCTAssertEqual(after.pickupRunID,run);XCTAssertEqual(try F.nest(e).available,2)
                    } else if after.state == .delivered {
                        deliveries+=1;XCTAssertNil(after.owner);XCTAssertEqual(after.deliveryRunID,run)
                        // The store changes from raw grip(3,12) to resting
                        // surface(8,12), so compare ink bounds, not anchor
                        // positions. carryPlace(40,39) contacts after Bird.tick;
                        // the authored zero-rotation twig spans x0...16,y6...12.
                        let right=plan.facingRight,direction:CGFloat=right ? 1:-1
                        let bill=CGPoint(x:bird.position.x+direction*11*e.spriteScale(for:bird),y:bird.position.y)
                        let expected=CGRect(x:bill.x-(right ? 3:13)*scale,y:bill.y-6*scale,width:16*scale,height:6*scale)
                        XCTAssertEqual(next.rect.minX,expected.minX,accuracy:0.001)
                        XCTAssertEqual(next.rect.minY,expected.minY,accuracy:0.001)
                        XCTAssertEqual(next.rect.maxX,expected.maxX,accuracy:0.001)
                        XCTAssertEqual(next.rect.maxY,expected.maxY,accuracy:0.001)
                        XCTAssertEqual(try F.nest(e).progress,0)
                    }
                }
            }
            F.released(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            XCTAssertTrue(sawAttached);XCTAssertEqual(pickups,1);XCTAssertEqual(deliveries,1)
            XCTAssertLessThanOrEqual(e.time-started,35+BehaviorEngine.step)
            XCTAssertEqual(observations.map(\.kind),[.nestMaterialCarry]);XCTAssertEqual(observations.map(\.source),[.preview])
            XCTAssertEqual(ObjectIdentifier(bird),identity);XCTAssertEqual(bird.state,.perched)
            let host=try XCTUnwrap(e.world.surfaces.first{$0.id==bird.hostID && $0.pid==bird.hostPID})
            XCTAssertFalse(host.isHabitat);XCTAssertTrue(e.hasUsablePerch(bird))
            XCTAssertEqual(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,scale:e.spriteScale(for:bird)))
            XCTAssertEqual(try F.nest(e).available,2);XCTAssertEqual(try F.nest(e).delivered,1)
            XCTAssertEqual(try F.nest(e).progress,0);XCTAssertFalse(try F.nest(e).completed)
            XCTAssertEqual(e.sceneFocus?.nestID,initial.id);try F.conserved(e,ids:ids);F.clear(e)
        }}}}
    }

    func testPauseFreezesEveryCarryStageMaterialsPoseLifetimeAndClocksThenActuallyCompletes() throws {
        for boundary in Boundary.allCases {
            let e=try F.prepared(),run=try F.start(e);try reach(boundary,e,run)
            let active=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestMaterialCarryExecution)
            e.handle(.pause(true))
            let nest=try F.nest(e),birds=e.renderSnapshot().map{RecordedBirdState($0,engine:e)}
            let props=e.propSnapshot().map(RecordedPropState.init),age=active.age,phaseAge=active.phaseAge
            let remaining=e.scheduler.remaining,cooldown=e.scheduler.nestCooldownRemaining
            F.advance(e,3)
            XCTAssertEqual(try F.nest(e),nest);XCTAssertEqual(e.renderSnapshot().map{RecordedBirdState($0,engine:e)},birds)
            XCTAssertEqual(e.propSnapshot().map(RecordedPropState.init),props);XCTAssertEqual(active.age,age);XCTAssertEqual(active.phaseAge,phaseAge)
            XCTAssertEqual(e.scheduler.remaining,remaining);XCTAssertEqual(e.scheduler.nestCooldownRemaining,cooldown)
            XCTAssertEqual(e.handle(.nestMaterialCarry(.preview)),.rejected(.paused))
            e.handle(.pause(false));F.finish(e,run);F.released(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed]);XCTAssertEqual(try F.nest(e).delivered,1)
        }
    }

    func testEveryCarryStageInterruptKeepsOnlyCommittedMaterialsAndNeverCountsAnObservation() throws {
        for boundary in Boundary.allCases {for paused in [false,true] {
            for cause in ["click","removeBird","removeNest","host","pid","frames","art","screen","disable","sleep"] {
                let e=try F.prepared(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird)),run=try F.start(e)
                try reach(boundary,e,run)
                let active=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestMaterialCarryExecution)
                let materialID=active.plan.materialID,material=try F.material(e,materialID),feet=bird.position
                let ids=Set(try F.nest(e).materials.map(\.id))
                var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
                if paused {e.handle(.pause(true))}
                switch cause {
                case "click":e.handle(.pointerClick)
                case "removeBird":e.handle(.remove(id))
                case "removeNest":e.handle(.removeNest)
                case "host":var w=e.world;w.surfaces.removeAll{$0.id==3701};e.updateWorld(w)
                case "pid":var w=e.world;let h=w.surfaces[0];w.surfaces[0]=Surface(id:h.id,pid:h.pid+1,rect:h.rect);e.updateWorld(w)
                case "frames":var w=e.world;w.availableFrames[.spottedDove]?.remove("carryPlace");e.updateWorld(w)
                case "art":var w=e.world;w.nestArtAvailable=false;e.updateWorld(w)
                case "screen":var w=e.world;w.screens=[];e.updateWorld(w)
                case "disable":var s=e.settings;s.nestBuildingEnabled=false;e.applySettings(s)
                default:e.handle(.cancelAmbient(.sleep))
                }
                let context="\(boundary)/\(cause)/paused=\(paused)"
                XCTAssertEqual(bird.position,feet,context);F.released(e,run)
                XCTAssertNotEqual(F.terminals(e,run).first?.type,.completed,context);XCTAssertTrue(observations.isEmpty,context)
                let keepsScene=["click","removeBird","frames"].contains(cause)
                if keepsScene {
                    try F.conserved(e,ids:ids)
                    let after=try F.material(e,materialID)
                    let expected:NestMaterialState=material.state == .attached ? .spent:material.state
                    XCTAssertEqual(after.state,expected,context)
                    XCTAssertEqual(try F.nest(e).available,material.state == .available ? 3:2,context)
                    if expected == .spent && !paused {
                        XCTAssertEqual(after.fadeRemaining,0.2,accuracy:1e-9)
                    }
                } else if paused {XCTAssertTrue(e.nestSnapshot().isEmpty,context)}
                e.handle(.pause(false));F.advance(e,2.25)
                XCTAssertFalse(F.tokens(e).contains{$0.id==materialID && e.nestSnapshot().first?.materials.first{$0.id==materialID}?.state == .spent})
                if !keepsScene {XCTAssertTrue(e.nestSnapshot().isEmpty,context)}
                e.handle(.cancelAmbient(.sleep));XCTAssertTrue(F.tokens(e).isEmpty);XCTAssertTrue(e.nestSnapshot().isEmpty)
                XCTAssertEqual(F.terminals(e,run).count,1);XCTAssertTrue(observations.isEmpty)
            }
        }}
    }

    func testPausedSceneRemovalThenExplicitRelocationKeepsTheNewOwnerOnResume() throws {
        let e=try F.prepared(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird)),run=try F.start(e)
        try reach(.carry,e,run);e.handle(.pause(true));let feet=bird.position
        e.handle(.removeNest);F.released(e,run)
        XCTAssertTrue(e.nestSnapshot().isEmpty);XCTAssertTrue(F.tokens(e).isEmpty);XCTAssertEqual(bird.position,feet)
        let replacement=try LeafCarryTestSupport.start(e.handle(.relocate(id))),revision=bird.motionRevision
        F.advance(e,0.1);e.handle(.pause(false));F.advance(e,0.1)
        XCTAssertEqual(e.runtime.owners[id],replacement);XCTAssertEqual(bird.motionRevision,revision)
        F.advance(e,30);XCTAssertEqual(F.terminals(e,replacement).map(\.type),[.completed])
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.cancelled])
    }
}
