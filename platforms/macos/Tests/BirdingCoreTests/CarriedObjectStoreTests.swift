import XCTest
@testable import BirdingCore

final class CarriedObjectStoreTests:XCTestCase {
    private typealias F=LeafCarryTestSupport
    private let id=ScenePropID(81),bird=BirdID(11),run=BehaviorRunID(rawValue:21)
    private func contact(_ point:CGPoint,scale:CGFloat,right:Bool)->ScenePropRenderState {
        CarriedObjectGeometry.render(id:id,position:CGPoint(x:point.x+(right ? -7:7)*scale,y:point.y),
            anchor:CGPoint(x:3,y:12),worldScale:scale,facingRight:right)
    }

    func testOneIdentityHasExclusiveReservationAndPickupIsAtomicAtRealMatchingContact() throws {
        for scale:CGFloat in [0.5,1,2] {
            for right in [false,true] {
                let e=F.engine(species:nil,scale:scale),store=CarriedObjectStore()
                XCTAssertTrue(store.placeLeaf(id:id,at:F.point,facingRight:right,in:e).accepted)
                let original=try XCTUnwrap(store.objects[id])
                XCTAssertEqual(original.kind,.leaf);XCTAssertEqual(original.state,.available)
                XCTAssertEqual(original.remainingLifetime,180);XCTAssertNil(original.owner)
                XCTAssertNil(original.reservedByRun);XCTAssertEqual(original.facingRight,right)
                XCTAssertEqual(original.worldScale,scale)
                XCTAssertEqual(store.placeLeaf(id:ScenePropID(82),at:CGPoint(x:1500,y:1100),in:e),.rejected(.busy))
                XCTAssertTrue(store.reserve(id,run:run,bird:bird))
                XCTAssertFalse(store.reserve(id,run:BehaviorRunID(rawValue:22),bird:BirdID(12)))
                XCTAssertFalse(store.reserve(id,run:run,bird:bird))
                XCTAssertEqual(store.objects[id]?.state,.available);XCTAssertNil(store.objects[id]?.owner)
                let before=try XCTUnwrap(store.snapshot(in:e).first)
                let attached=contact(F.point,scale:scale,right:right)
                XCTAssertEqual(before.rect.minX,attached.rect.minX,accuracy:1e-9)
                XCTAssertEqual(before.rect.minY,attached.rect.minY,accuracy:1e-9)
                XCTAssertEqual(before.mirrored,attached.mirrored)
                var missed=attached;missed=CarriedObjectGeometry.render(id:id,
                    position:CGPoint(x:attached.position.x+1,y:attached.position.y),anchor:CGPoint(x:3,y:12),
                    worldScale:scale,facingRight:right)
                XCTAssertFalse(store.pickup(id,run:run,bird:bird,contact:missed))
                XCTAssertFalse(store.pickup(id,run:run,bird:BirdID(12),contact:attached))
                XCTAssertEqual(store.objects[id]?.state,.available)
                XCTAssertTrue(store.pickup(id,run:run,bird:bird,contact:attached))
                XCTAssertFalse(store.pickup(id,run:run,bird:bird,contact:attached))
                let object=try XCTUnwrap(store.objects[id])
                XCTAssertEqual(object.state,.attached);XCTAssertEqual(object.owner,bird)
                XCTAssertEqual(object.reservedByRun,run);XCTAssertEqual(object.remainingLifetime,0)
                XCTAssertEqual(store.objects.count,1);XCTAssertEqual(store.snapshot(in:e).map(\.id),[id])
            }
        }
    }

    func testPickupStopsTheNearlyExpiredAvailableClockAndPlacementStartsANewEightSecondClock() throws {
        let e=F.engine(species:nil),store=CarriedObjectStore()
        XCTAssertTrue(store.placeLeaf(id:id,at:F.point,in:e).accepted)
        _=store.advance(179.95,in:e)
        XCTAssertGreaterThan(try XCTUnwrap(store.objects[id]).remainingLifetime,0)
        XCTAssertTrue(store.reserve(id,run:run,bird:bird))
        XCTAssertTrue(store.pickup(id,run:run,bird:bird,contact:contact(F.point,scale:1,right:true)))
        XCTAssertTrue(store.advance(200,in:e).isEmpty,"The runtime's 25s deadline owns attached lifetime")
        XCTAssertEqual(store.objects[id]?.state,.attached);XCTAssertEqual(store.objects[id]?.owner,bird)
        let destination=CGPoint(x:F.point.x+160,y:F.point.y)
        let anchor=try XCTUnwrap(SurfaceAnchor.at(destination,on:F.host,scale:1))
        XCTAssertTrue(store.place(id,run:run,at:anchor,contact:contact(destination,scale:1,right:true),in:e))
        XCTAssertFalse(store.place(id,run:run,at:anchor,contact:contact(destination,scale:1,right:true),in:e))
        XCTAssertEqual(store.objects[id]?.state,.placed);XCTAssertNil(store.objects[id]?.owner)
        XCTAssertEqual(store.objects[id]?.remainingLifetime,8)
        store.releaseReservation(id,run:BehaviorRunID(rawValue:22))
        XCTAssertEqual(store.objects[id]?.reservedByRun,run)
        store.releaseReservation(id,run:run);XCTAssertNil(store.objects[id]?.reservedByRun)
        XCTAssertEqual(store.snapshot(in:e).map(\.id),[id]);XCTAssertNil(e.sceneFocus)
        _=store.advance(7.7,in:e);XCTAssertEqual(store.snapshot(in:e).first?.opacity,1)
        _=store.advance(0.2,in:e)
        XCTAssertEqual(try XCTUnwrap(store.snapshot(in:e).first).opacity,0.5,accuracy:1e-8)
        _=store.advance(0.11,in:e)
        XCTAssertTrue(store.snapshot(in:e).isEmpty,"The last .2s belongs inside the 8s display lifetime; no opacity reset or second fade")
        XCTAssertTrue(store.objects.isEmpty)
    }

    func testRetirementFreezesTheLastVisiblePointAndCannotBeRepeatedOrFreeCapacityBeforeFadeEnds() throws {
        let e=F.engine(species:nil),store=CarriedObjectStore()
        XCTAssertTrue(store.placeLeaf(id:id,at:F.point,in:e).accepted)
        let before=try XCTUnwrap(store.snapshot(in:e).first)
        store.retire(id,in:e)
        XCTAssertEqual(store.objects[id]?.state,.retired)
        XCTAssertNil(store.objects[id]?.owner);XCTAssertNil(store.objects[id]?.reservedByRun)
        _=store.advance(0.1,in:e)
        let half=try XCTUnwrap(store.snapshot(in:e).first)
        XCTAssertEqual(half.position,before.position);XCTAssertEqual(half.mirrored,before.mirrored)
        XCTAssertEqual(half.opacity,0.5,accuracy:1e-8)
        store.retire(id,in:e)
        XCTAssertEqual(store.snapshot(in:e).first?.opacity,half.opacity)
        XCTAssertEqual(store.placeLeaf(id:ScenePropID(82),at:F.point,in:e),.rejected(.busy))
        e.handle(.pause(true));_=store.advance(5,in:e)
        XCTAssertEqual(store.snapshot(in:e).first?.opacity,half.opacity)
        e.handle(.pause(false));_=store.advance(0.1,in:e)
        XCTAssertTrue(store.objects.isEmpty);XCTAssertTrue(store.snapshot(in:e).isEmpty)
        XCTAssertTrue(store.placeLeaf(id:ScenePropID(82),at:F.point,in:e).accepted)
        store.retire(ScenePropID(82),in:e,immediate:true)
        XCTAssertTrue(store.objects.isEmpty)
    }

    func testSurfaceAnchorFollowsTheSameHostFractionButRejectsReusedIdentityAndSpecialPerches() throws {
        let e=F.engine(species:nil),world=e.world
        let anchor=try XCTUnwrap(SurfaceAnchor.at(F.point,on:F.host,scale:1))
        XCTAssertEqual(anchor.hostID,F.host.id);XCTAssertEqual(anchor.hostPID,F.host.pid)
        XCTAssertEqual(anchor.point(in:world),F.point)
        var moved=world;moved.surfaces[0].rect.origin.x+=3;moved.surfaces[0].rect.origin.y+=2
        let point=try XCTUnwrap(anchor.point(in:moved))
        XCTAssertEqual(point.x,F.point.x+3,accuracy:1e-9);XCTAssertEqual(point.y,F.point.y+2,accuracy:1e-9)
        XCTAssertEqual(anchor.fraction,(F.point.x-Geometry.perchX(0,rect:F.host.rect)) /
            (Geometry.perchX(1,rect:F.host.rect)-Geometry.perchX(0,rect:F.host.rect)),accuracy:1e-9)
        XCTAssertTrue(SurfaceAnchor.acceptsChange(from:F.host,to:moved.surfaces[0],sampleDT:1.0/60))
        var replaced=world;replaced.surfaces[0]=Surface(id:F.host.id,pid:F.host.pid+1,rect:F.host.rect)
        XCTAssertNil(anchor.host(in:replaced));XCTAssertNil(anchor.point(in:replaced))
        for kind:HabitatSurfaceKind in [.fixedPerch,.foodTray,.bath] {
            let special=Surface(id:981,pid:42,rect:F.host.rect,habitatKind:kind)
            XCTAssertNil(SurfaceAnchor.at(F.point,on:special,scale:1))
        }
        XCTAssertNil(SurfaceAnchor.placement(at:CGPoint(x:1200,y:650),in:world,groundScale:1))
    }

    func testCombinedFootprintContainsTheWholeBirdAndOffsetLeafAtEveryAuthoredAnchorHeadingAndRotation() throws {
        let names=["stand","carryLook","carryLower","carryGrip","carryPlace"] +
            (0..<8).map{"fly\($0)"} + (0..<3).map{"land\($0)"}
        for scale:CGFloat in [0.5,1,2] {
            let sprite=scale*SpeciesCatalog.standard.profile(.treeSparrow).relativeScale
            let area=try XCTUnwrap(CarriedObjectGeometry.localFootprint(species:.treeSparrow,birdScale:sprite,
                worldScale:scale,rotationRange:0...(2*CGFloat.pi)))
            XCTAssertTrue(area.contains(Geometry.landingFootprint(at:.zero,scale:sprite)))
            var extendsBeyondBird=false
            let body=CGRect(x:-29*sprite,y:-39*sprite,width:58*sprite,height:48*sprite)
            for frame in names {
                let anchor=try XCTUnwrap(PoseClip.carryBeakAnchor(species:.treeSparrow,frame:frame))
                for right in [false,true] {
                    let grip=anchor.world(foot:.zero,scale:sprite,facingRight:right)
                    for sample in 0..<32 {
                        let rotation=CGFloat(sample)*2*CGFloat.pi/32
                        let leaf=CarriedObjectGeometry.bounds(position:grip,anchor:CGPoint(x:3,y:12),worldScale:scale,
                            facingRight:right,rotation:rotation)
                        XCTAssertTrue(area.insetBy(dx:-1e-8,dy:-1e-8).contains(leaf),"\(frame), right=\(right), rotation=\(sample)")
                        extendsBeyondBird = extendsBeyondBird || !body.contains(leaf)
                    }
                }
            }
            XCTAssertTrue(extendsBeyondBird,"A 48-unit bird-only envelope would miss part of the carried token")
        }
    }
}
