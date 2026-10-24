import XCTest
@testable import BirdingCore

final class NestObjectTests:XCTestCase {
    private typealias F=NestTestSupport

    func testPlacementCreatesOneSceneAndExactlyThreeStableMaterialsAtLiteralScaledAnchors() throws {
        for scale:CGFloat in [0.5,1,2] {for negative in [false,true] {for ground in [false,true] {
            let e=F.engine(scale:scale,negative:negative,ground:ground,residents:0,species:nil)
            let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
            let point=F.point(e),surfaces=e.world.surfaces,settings=try encoder.encode(e.settings)
            XCTAssertEqual(e.handle(.placeNest(at:point)),.accepted)
            let nest=try F.nest(e),ids=Set(nest.materials.map(\.id))
            XCTAssertEqual(e.nestSnapshot().count,1);XCTAssertEqual(e.habitatSnapshot().count,1)
            XCTAssertEqual(e.habitatSnapshot().first?.kind,.nest);XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3)
            XCTAssertEqual(nest.rect,CGRect(x:point.x-72*scale,y:point.y-24*scale,width:144*scale,height:48*scale))
            XCTAssertEqual(nest.trayRect,CGRect(x:point.x-136*scale,y:point.y-12*scale,width:32*scale,height:16*scale))
            XCTAssertEqual(nest.materials.map(\.slot),[0,1,2]);XCTAssertEqual(ids.count,3)
            XCTAssertEqual(nest.materials.map(\.state),[.available,.available,.available])
            XCTAssertEqual(nest.remainingLifetime,900);XCTAssertEqual(nest.progress,0);XCTAssertFalse(nest.completed)
            XCTAssertTrue(nest.canContinue);XCTAssertFalse(nest.retiring);XCTAssertNil(nest.reservation)
            for (i,material) in nest.materials.enumerated() {
                XCTAssertEqual(material.position.x,nest.trayRect.minX+CGFloat(8+i*8)*scale,accuracy:1e-9)
                XCTAssertEqual(material.position.y,nest.trayRect.minY+12*scale,accuracy:1e-9)
                XCTAssertNil(material.owner);XCTAssertNil(material.reservedByRun)
                XCTAssertNil(material.pickupRunID);XCTAssertNil(material.deliveryRunID);XCTAssertNil(material.arrangementRunID)
            }
            XCTAssertTrue(e.world.displays[0].contains(nest.rect));XCTAssertTrue(e.world.displays[0].contains(nest.trayRect))
            XCTAssertEqual(nest.parentAnchor.isGround,ground);XCTAssertEqual(e.sceneFocus?.nestID,nest.id)
            XCTAssertEqual(F.tokens(e).count,3);XCTAssertEqual(e.activeRunCount,0);XCTAssertTrue(e.birds.isEmpty)
            XCTAssertEqual(e.world.surfaces.filter{!$0.isHabitat},surfaces)
            XCTAssertEqual(try encoder.encode(e.settings),settings)
            try F.conserved(e,ids:ids);F.clear(e)
        }}}
    }

    func testTrayTriesLeftThenRightAndWholeGroupMustFitOneActualSupportAndOneDisplay() throws {
        let e=F.engine(residents:0,species:nil),host=e.world.surfaces[0]
        let point=CGPoint(x:host.rect.minX+100,y:host.rect.minY)
        XCTAssertEqual(e.handle(.placeNest(at:point)),.accepted)
        let nest=try F.nest(e)
        XCTAssertEqual(nest.trayFoot.x,point.x+120,accuracy:1e-9)
        F.clear(e)
        for cause in ["narrow","fixed","sideLayer","noHost","panel","seam"] {
            let other=F.engine(residents:0,species:nil);let p=F.point(other);var world=other.world
            switch cause {
            case "narrow":world.surfaces=[Surface(id:3701,pid:42,rect:CGRect(x:p.x-80,y:p.y,width:160,height:100))]
            case "fixed":world.surfaces=[Surface(id:3701,pid:42,rect:host.rect,isFixedPerch:true)]
            case "sideLayer":world.surfaces=[Surface(id:3701,pid:42,rect:host.rect,layer:1)]
            case "noHost":world.surfaces=[]
            case "panel":world.surfaces.insert(Surface(id:3799,pid:77,rect:CGRect(x:p.x-125,y:p.y-8,width:1,height:2),layer:1),at:0)
                world.surfaces.insert(Surface(id:3798,pid:77,rect:CGRect(x:p.x+125,y:p.y-8,width:1,height:2),layer:1),at:0)
            default:world.displays=[CGRect(x:0,y:0,width:p.x,height:2200),CGRect(x:p.x,y:0,width:2400-p.x,height:2200)]
            }
            other.updateWorld(world)
            XCTAssertEqual(other.handle(.placeNest(at:p)),.rejected(.noSpace),cause)
            XCTAssertTrue(other.nestSnapshot().isEmpty);XCTAssertTrue(other.habitatSnapshot().isEmpty)
            XCTAssertTrue(F.tokens(other).isEmpty);XCTAssertNil(other.sceneFocus)
        }
    }

    func testNestFoodAndBathShareOneCapacityAndRejectedPlacementsNeverDestroyOrRefillTheUsersScene() throws {
        for first in ["food","bath","nest"] {
            let e=F.engine(residents:0,species:nil),point=F.point(e)
            let command:EngineCommand=first=="food" ? .placeFoodTray(at:point):first=="bath" ? .placeBath(at:point):.placeNest(at:point)
            XCTAssertEqual(e.handle(command),.accepted);F.advance(e,1)
            let before=e.habitatSnapshot().map(RecordedHabitatObjectState.init),nests=e.nestSnapshot().map(RecordedNestState.init)
            for command:EngineCommand in [.placeNest(at:point),.placeNestAfter(1),.placeBath(at:point),.placeBathAfter(1),
                                          .placeFoodTray(at:point),.placeFoodTrayAfter(1)] {
                XCTAssertEqual(e.handle(command),.rejected(.busy))
                XCTAssertEqual(e.habitatSnapshot().map(RecordedHabitatObjectState.init),before)
                XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),nests)
            }
            XCTAssertFalse(e.hasNestPlacement);XCTAssertFalse(e.hasBathPlacement);XCTAssertFalse(e.hasFoodTrayPlacement)
            // A nest-specific clear must not remove the user's other object.
            if first != "nest" {
                XCTAssertEqual(e.handle(.removeNest),.accepted)
                XCTAssertEqual(e.habitatSnapshot().map(RecordedHabitatObjectState.init),before)
            }
            e.handle(.clearCurrentScene);F.advance(e,2.25);XCTAssertTrue(e.habitatSnapshot().isEmpty)
        }
        let e=try F.prepared(),before=e.nestSnapshot().map(RecordedNestState.init)
        for command:EngineCommand in [.clearLeaf,.removeCarryLeaf,.removeFoodTray,.removeBath,.clearVisitorGift,.clearInsect] {
            XCTAssertEqual(e.handle(command),.accepted);XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),before)
        }
    }

    func testDelayedPlacementUsesCurrentRealPointerFreezesAndCancelsWithoutMaterialAllocation() throws {
        let e=F.engine(residents:0,species:nil);var world=e.world;world.pointer=F.point(e);e.updateWorld(world)
        XCTAssertEqual(e.handle(.placeNestAfter(2)),.scheduled);F.advance(e,0.5)
        e.handle(.pause(true));F.advance(e,5);XCTAssertTrue(e.hasNestPlacement);XCTAssertTrue(e.nestSnapshot().isEmpty)
        XCTAssertEqual(e.handle(.placeNest(at:F.point(e))),.rejected(.paused))
        e.handle(.pause(false));F.advance(e,1.6);XCTAssertFalse(e.hasNestPlacement)
        let first=try F.nest(e);XCTAssertEqual(first.foot,world.pointer);F.clear(e)
        for cancel:EngineCommand in [.cancelNestPlacement,.removeNest,.clearCurrentScene,.cancelAmbient(.sleep)] {
            XCTAssertEqual(e.handle(.placeNestAfter(1)),.scheduled);e.handle(cancel)
            XCTAssertFalse(e.hasNestPlacement);F.advance(e,1.1);XCTAssertTrue(e.nestSnapshot().isEmpty)
        }
        XCTAssertEqual(e.handle(.placeNest(at:F.point(e))),.accepted)
        XCTAssertTrue(Set(try F.nest(e).materials.map(\.id)).isDisjoint(with:first.materials.map(\.id)))
    }

    func testNineHundredSecondLifetimeAndRetirementFreezeAndPausedDeletionIsImmediate() throws {
        let e=try F.prepared();F.advance(e,899)
        let nest=try F.nest(e);XCTAssertEqual(nest.remainingLifetime,1,accuracy:1e-7)
        e.handle(.pause(true));F.advance(e,100)
        XCTAssertEqual(try F.nest(e),nest)
        e.handle(.pause(false));F.advance(e,1.1)
        XCTAssertNil(e.sceneFocus)
        if let retired=e.nestSnapshot().first {XCTAssertTrue(retired.retiring);XCTAssertFalse(retired.canContinue)}
        F.advance(e,2.1);XCTAssertTrue(e.nestSnapshot().isEmpty);XCTAssertTrue(F.tokens(e).isEmpty)
        XCTAssertFalse(e.world.surfaces.contains{$0.habitatKind == .nest})
        for command:EngineCommand in [.removeNest,.cancelAmbient(.sleep),.cancelAmbient(.shutdown)] {
            let e=try F.prepared();e.handle(.pause(true));e.handle(command)
            XCTAssertTrue(e.nestSnapshot().isEmpty);XCTAssertTrue(F.tokens(e).isEmpty);XCTAssertNil(e.sceneFocus)
            XCTAssertFalse(e.world.surfaces.contains{$0.habitatKind == .nest})
        }
    }

    func testLightHostMotionKeepsIdentityAndFractionButPIDLayerScreenAndArtChangesRetireTheScene() throws {
        let e=try F.prepared(),initial=try F.nest(e),host=e.world.surfaces.first{$0.id==3701}!
        var world=e.world;world.surfaces[0]=Surface(id:host.id,pid:host.pid,rect:host.rect.offsetBy(dx:3,dy:-2))
        e.updateWorld(world,sampleDT:0.1)
        let moved=try F.nest(e)
        XCTAssertEqual(moved.id,initial.id);XCTAssertEqual(moved.materials.map(\.id),initial.materials.map(\.id))
        XCTAssertEqual(moved.parentAnchor,initial.parentAnchor)
        XCTAssertEqual(moved.foot.x,initial.foot.x+3,accuracy:1e-9);XCTAssertEqual(moved.foot.y,initial.foot.y-2,accuracy:1e-9)
        for cause in ["host","pid","layer","screen","displayID","scale","art","setting"] {for paused in [false,true] {
            let e=try F.prepared();if paused {e.handle(.pause(true))};var w=e.world
            switch cause {
            case "host":w.surfaces.removeAll{$0.id==3701}
            case "pid":w.surfaces[0]=Surface(id:host.id,pid:host.pid+1,rect:host.rect)
            case "layer":w.surfaces[0]=Surface(id:host.id,pid:host.pid,rect:host.rect,layer:1)
            case "screen":w.screens=[]
            case "displayID":w.displayIDs=["replacement"]
            case "scale":w.scale*=1.1
            case "art":w.nestArtAvailable=false
            default:var s=e.settings;s.nestBuildingEnabled=false;e.applySettings(s)
            }
            if cause != "setting" {e.updateWorld(w,sampleDT:0.1)}
            if paused {XCTAssertTrue(e.nestSnapshot().isEmpty,cause)}
            e.handle(.pause(false));F.advance(e,2.25)
            XCTAssertTrue(e.nestSnapshot().isEmpty,cause);XCTAssertTrue(F.tokens(e).isEmpty,cause);XCTAssertNil(e.sceneFocus)
        }}
    }
}
