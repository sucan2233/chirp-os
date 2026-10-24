import XCTest
@testable import BirdingCore

final class BathObjectTests:XCTestCase {
    private let display=CGRect(x:-1000,y:-300,width:3000,height:1800)
    private let point=CGPoint(x:700,y:600)
    private func fixture(scale:CGFloat=1)->BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false;settings.passiveAttentionEnabled=false
        let e=BehaviorEngine(seed:901,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(.init(screens:[display],displays:[display],scale:scale,pointer:CGPoint(x:-900,y:-200)))
        return e
    }
    private func advance(_ e:BehaviorEngine,_ seconds:Double) {
        for _ in 0..<Int((seconds*60).rounded()) {e.advance(BehaviorEngine.step)}
    }

    func testBasinGeometryHasFixedInternalWaterlineAndMirroredBillContactAtActualSpeciesScales() throws {
        XCTAssertEqual(BathGeometry.basinSize,CGSize(width:128,height:40))
        XCTAssertEqual(BathGeometry.slotFoot,CGPoint(x:64,y:20));XCTAssertEqual(BathGeometry.waterlineY,20)
        XCTAssertEqual(BathGeometry.birdFootAnchor,CGPoint(x:29,y:39))
        XCTAssertEqual(BathGeometry.rightBeak,CGPoint(x:40,y:39));XCTAssertEqual(BathGeometry.leftBeak,CGPoint(x:8,y:39))
        for scale:CGFloat in [0.5,1,2] {
            let e=fixture(scale:scale)
            XCTAssertTrue(e.handle(.placeBath(at:point)).accepted)
            let bath=try XCTUnwrap(e.habitatSnapshot().first)
            XCTAssertEqual(bath.kind,.bath)
            XCTAssertEqual(bath.rect,CGRect(x:point.x-64*scale,y:point.y-20*scale,width:128*scale,height:40*scale))
            XCTAssertEqual(bath.remainingUses,3);XCTAssertEqual(bath.remainingLifetime,300)
            XCTAssertFalse(bath.retiring);XCTAssertEqual(e.activeRunCount,0);XCTAssertTrue(e.birds.isEmpty)
            XCTAssertEqual(BathGeometry.foot(in:bath.rect,scale:scale),point)
            let surface=try XCTUnwrap(e.world.surfaces.first{$0.habitatKind == .bath})
            XCTAssertEqual(surface.rect.minY,point.y)
            for species:SpeciesID in [.treeSparrow,.lightVentedBulbul] {
                let sprite=scale*e.settings.catalog.profile(species).relativeScale
                for right in [false,true] {
                    let contact=BathGeometry.touchPoint(foot:point,spriteScale:sprite,facingRight:right)
                    XCTAssertEqual(contact.x,point.x+(right ? 11:-11)*sprite,accuracy:1e-9)
                    XCTAssertEqual(contact.y,point.y)
                    let water=BathGeometry.waterRect(in:bath.rect,scale:scale)
                    let x=(contact.x-water.midX)/(water.width/2),y=(contact.y-water.midY)/(water.height/2)
                    XCTAssertLessThanOrEqual(x*x+y*y,1)
                }
            }
        }
    }

    func testFoodAndBathShareCapacityAndFailedPlacementNeverRefillsOrReplacesTheCurrentObject() throws {
        for bathFirst in [false,true] {
            let e=fixture()
            XCTAssertTrue(e.handle(bathFirst ? .placeBath(at:point):.placeFoodTray(at:point)).accepted)
            advance(e,5)
            let before=e.habitatSnapshot().map(RecordedHabitatObjectState.init)
            for command:EngineCommand in [.placeBath(at:CGPoint(x:1100,y:600)),.placeFoodTray(at:CGPoint(x:1100,y:600)),
                .placeBathAfter(1),.placeFoodTrayAfter(1)] {
                XCTAssertEqual(e.handle(command),.rejected(.busy))
                XCTAssertEqual(e.habitatSnapshot().map(RecordedHabitatObjectState.init),before)
            }
            XCTAssertFalse(e.hasBathPlacement);XCTAssertFalse(e.hasFoodTrayPlacement)
            e.handle(.clearCurrentScene);advance(e,2.1)
            XCTAssertTrue(e.habitatSnapshot().isEmpty)
            XCTAssertTrue(e.handle(bathFirst ? .placeFoodTray(at:point):.placeBath(at:point)).accepted)
            XCTAssertNotEqual(e.habitatSnapshot().first?.id.rawValue,UInt64(before[0].id))
            XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3)
        }
    }

    func testThreeSuccessfulRunCommitsAreIdempotentAndRetiringObjectCannotBeReused() throws {
        let e=fixture();XCTAssertTrue(e.handle(.placeBath(at:point)).accepted)
        let id=try XCTUnwrap(e.habitatSnapshot().first?.id)
        // Exercise the store's atomic commit separately from the real visit tests.
        for value:UInt64 in 1...3 {
            let run=BehaviorRunID(rawValue:value)
            XCTAssertTrue(e.habitatObjects.completeVisit(id,runID:run))
            XCTAssertFalse(e.habitatObjects.completeVisit(id,runID:run))
            XCTAssertEqual(e.habitatObjects.objects[id]?.remainingUses,3-Int(value))
        }
        XCTAssertFalse(e.habitatObjects.completeVisit(id,runID:BehaviorRunID(rawValue:4)))
        XCTAssertTrue(try XCTUnwrap(e.habitatObjects.objects[id]).retiring)
        XCTAssertEqual(e.habitatObjects.placeBath(at:point,in:e),.rejected(.busy))
        XCTAssertFalse(e.habitatObjects.placeFood(at:point,in:e))
        e.habitatObjects.advance(1.99);XCTAssertFalse(e.habitatObjects.removalDueIDs.contains(id))
        e.habitatObjects.advance(0.01);XCTAssertTrue(e.habitatObjects.removalDueIDs.contains(id))
        e.habitatObjects.remove(id)
        XCTAssertFalse(e.habitatObjects.completeVisit(id,runID:BehaviorRunID(rawValue:1)))
    }

    func testPlacementPreservesThreeIndependentFixedPerchSlotsAndCannotOverlapThem() {
        let e=fixture();var settings=e.settings
        settings.fixedPerches=(1...3).map {slot in
            FixedPerchAnchor(slot:slot,displayID:"",displayFrame:display,x:Double(slot)/4,y:0.25)
        }
        e.applySettings(settings)
        XCTAssertEqual(e.fixedPerchSnapshot().count,3)
        let old=e.fixedPerchSnapshot().map(RecordedFixedPerchState.init)
        XCTAssertTrue(e.handle(.placeBath(at:point)).accepted)
        XCTAssertEqual(e.fixedPerchSnapshot().map(RecordedFixedPerchState.init),old)
        e.handle(.clearCurrentScene);advance(e,2.1)
        XCTAssertEqual(e.fixedPerchSnapshot().map(RecordedFixedPerchState.init),old)
        let blocked=e.fixedPerchSnapshot()[0].foot
        XCTAssertEqual(e.handle(.placeBath(at:blocked)),.rejected(.noSpace))
        XCTAssertEqual(e.fixedPerchSnapshot().map(RecordedFixedPerchState.init),old)
    }

    func testPendingPlacementFreezesWhilePausedAndBothObjectArtAndBoundsAreRequired() throws {
        let e=fixture();var world=e.world;world.pointer=point;e.updateWorld(world)
        XCTAssertEqual(e.handle(.placeBathAfter(2)),.scheduled)
        advance(e,0.5);e.handle(.pause(true));advance(e,10)
        XCTAssertTrue(e.hasBathPlacement);XCTAssertTrue(e.habitatSnapshot().isEmpty)
        XCTAssertEqual(e.handle(.placeBath(at:point)),.rejected(.paused))
        e.handle(.pause(false));advance(e,1.6)
        XCTAssertFalse(e.hasBathPlacement);XCTAssertEqual(e.habitatSnapshot().count,1)
        e.handle(.clearCurrentScene);advance(e,2.1)
        world=e.world;world.bathArtAvailable=false;e.updateWorld(world)
        XCTAssertEqual(e.handle(.placeBath(at:point)),.rejected(.missingFrames))
        world.bathArtAvailable=true;e.updateWorld(world)
        for bad in [CGPoint(x:display.minX,y:600),CGPoint(x:display.maxX,y:600),
                    CGPoint(x:700,y:display.maxY),CGPoint(x:CGFloat.nan,y:600)] {
            XCTAssertEqual(e.handle(.placeBath(at:bad)),.rejected(.noSpace))
            XCTAssertTrue(e.habitatSnapshot().isEmpty)
        }
    }
}
