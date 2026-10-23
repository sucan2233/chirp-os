import XCTest
@testable import BirdingCore

final class FixedPerchLayoutTests: XCTestCase {
    private let left=CGRect(x:-1600,y:-300,width:1600,height:1000)
    private let right=CGRect(x:0,y:0,width:1600,height:1000)

    private func anchor(slot:Int=1,id:String="left",frame:CGRect?=nil,x:Double=0.25,y:Double=0.5) -> FixedPerchAnchor {
        FixedPerchAnchor(slot:slot,displayID:id,displayFrame:frame ?? left,x:x,y:y)
    }

    private func world(_ displays:[CGRect],ids:[String]=[],screens:[CGRect]?=nil,scale:CGFloat=1) -> BehaviorWorld {
        var world=BehaviorWorld(screens:screens ?? displays,displays:displays,scale:scale)
        world.displayIDs=ids
        return world
    }

    func testCaptureNormalizesNegativeCoordinatesAndRejectsOffscreenPoints() throws {
        let point=CGPoint(x:-1200,y:200)
        let captured=try XCTUnwrap(FixedPerchAnchor.capture(slot:2,point:point,displayIDs:["left","right"],displays:[left,right]))
        XCTAssertEqual(captured.slot,2)
        XCTAssertEqual(captured.displayID,"left")
        XCTAssertEqual(captured.displayFrame,left)
        XCTAssertEqual(captured.x,0.25)
        XCTAssertEqual(captured.y,0.5)
        XCTAssertEqual(FixedPerchAnchor.capture(slot:1,point:point,displayIDs:[],displays:[left])?.displayID,"")
        for p in [CGPoint(x:-1700,y:200),CGPoint(x:-800,y:-400),CGPoint(x:CGFloat.nan,y:0),CGPoint(x:0,y:CGFloat.infinity)] {
            XCTAssertNil(FixedPerchAnchor.capture(slot:1,point:p,displayIDs:[],displays:[left,right]))
        }
        XCTAssertNil(FixedPerchAnchor.capture(slot:0,point:point,displayIDs:[],displays:[left]))
        XCTAssertNil(FixedPerchAnchor.capture(slot:4,point:point,displayIDs:[],displays:[left]))
        XCTAssertNil(FixedPerchAnchor.capture(slot:1,point:point,displayIDs:[String(repeating:"x",count:129)],displays:[left]))
        XCTAssertNil(FixedPerchAnchor.capture(slot:1,point:point,displayIDs:[],displays:[]))
        XCTAssertNil(FixedPerchAnchor.capture(slot:1,point:.zero,displayIDs:[],displays:[.infinite]))
    }

    func testResolvedGeometryAndReservedSurfaceIdentity() throws {
        let perch=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[anchor()],world:world([left,right],ids:["left","right"])).first)
        XCTAssertEqual(FixedPerchLayout.maximumCount,3)
        XCTAssertEqual(perch.slot,1)
        XCTAssertEqual(perch.foot,CGPoint(x:-1200,y:200))
        XCTAssertEqual(perch.surface.id,0xFF000001)
        XCTAssertEqual(perch.surface.pid,Int32.min+18)
        XCTAssertTrue(perch.surface.isFixedPerch)
        XCTAssertFalse(perch.surface.isGround)
        XCTAssertEqual(perch.surface.rect,CGRect(x:-1290,y:200,width:180,height:1))
        XCTAssertEqual(perch.rect,CGRect(x:-1264,y:200,width:128,height:24))
    }

    func testDisplayIDSurvivesEnumerationChangesAndMovedDisplayGeometry() throws {
        let original=anchor()
        let first=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[original],world:world([left,right],ids:["left","right"])).first)
        let reordered=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[original],world:world([right,left],ids:["right","left"],screens:[left,right])).first)
        XCTAssertEqual(first.foot,reordered.foot)
        let moved=CGRect(x:1600,y:-100,width:1200,height:800)
        let match=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[original],world:world([left,moved],ids:["replacement","left"])).first)
        XCTAssertEqual(match.foot,CGPoint(x:1900,y:300))
        XCTAssertEqual(original.displayFrame,left)
    }

    func testDisconnectedDisplayFallsBackAndReconnectRestoresOriginalPosition() throws {
        let original=anchor()
        let detached=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[original],world:world([right],ids:["right"])).first)
        XCTAssertEqual(detached.foot,CGPoint(x:400,y:500))
        let restored=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[original],world:world([right,left],ids:["right","left"])).first)
        XCTAssertEqual(restored.foot,CGPoint(x:-1200,y:200))
        XCTAssertEqual(original,anchor())
    }

    func testGeometryFallbackPrefersExactFrameThenLargestIntersectionThenNearestCenter() throws {
        let exact=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[anchor(id:"")],world:world([right,left])).first)
        XCTAssertEqual(exact.foot,CGPoint(x:-1200,y:200))
        let large=CGRect(x:-1500,y:-300,width:1400,height:1000)
        let small=CGRect(x:-100,y:0,width:1600,height:1000)
        let intersecting=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[anchor()],world:world([small,large])).first)
        XCTAssertEqual(intersecting.foot,CGPoint(x:-1150,y:200))
        let far=CGRect(x:3000,y:0,width:1600,height:1000)
        let nearest=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[anchor()],world:world([far,right])).first)
        XCTAssertEqual(nearest.foot,CGPoint(x:400,y:500))
    }

    func testEqualDistanceFallbackIsStableAcrossDisplayOrderAndPartialIDs() throws {
        let saved=anchor(frame: CGRect(x:0,y:0,width:1000,height:1000),x:0.5)
        let a=CGRect(x:-2000,y:0,width:1000,height:1000),b=CGRect(x:2000,y:0,width:1000,height:1000)
        let first=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[saved],world:world([a,b],ids:["unknown"])).first)
        let second=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[saved],world:world([b,a])).first)
        XCTAssertEqual(first.foot,second.foot)
        XCTAssertEqual(first.foot,CGPoint(x:-1500,y:500))
    }

    func testWorkAreaChangesClampFeetWithoutChangingSavedCoordinates() throws {
        let saved=anchor(id:"right",frame:right,x:1,y:1)
        let area=CGRect(x:100,y:30,width:1300,height:800)
        let first=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[saved],world:world([right],screens:[area])).first)
        XCTAssertEqual(first.foot,CGPoint(x:1336,y:806))
        let smaller=CGRect(x:200,y:100,width:600,height:500)
        let clamped=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[saved],world:world([right],screens:[smaller])).first)
        XCTAssertEqual(clamped.foot,CGPoint(x:736,y:576))
        let restored=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[saved],world:world([right])).first)
        XCTAssertEqual(restored.foot,CGPoint(x:1536,y:976))
        XCTAssertEqual(saved.x,1);XCTAssertEqual(saved.y,1)
        let topLeft=anchor(id:"right",frame:right,x:0,y:0)
        let top=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[topLeft],world:world([right],screens:[area])).first)
        XCTAssertEqual(top.foot,CGPoint(x:164,y:110))
    }

    func testWorkAreaAndDisplayJointlyLimitLayout() throws {
        let oversized=CGRect(x:-100,y:-100,width:1800,height:1200)
        let saved=anchor(id:"right",frame:right,x:0,y:0)
        let perch=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[saved],world:world([right],screens:[oversized])).first)
        XCTAssertEqual(perch.foot,CGPoint(x:64,y:80))
        XCTAssertTrue(right.contains(perch.rect))
        let fallback=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[saved],world:world([right],screens:[])).first)
        XCTAssertEqual(fallback.foot,perch.foot)
        XCTAssertTrue(FixedPerchLayout.resolve(anchors:[saved],world:world([right],screens:[left])).isEmpty)
    }

    func testScaleChangesMarginsAndDimensionsIncludingMinimumClearance() throws {
        let edge=anchor(id:"right",frame:right,x:0,y:0)
        for scale:CGFloat in [0.25,0.5,1,1.5,2] {
            let perch=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[edge],world:world([right],scale:scale)).first)
            XCTAssertEqual(perch.foot.x,max(64*scale,48))
            XCTAssertEqual(perch.foot.y,max(80*scale,48))
            XCTAssertEqual(perch.surface.rect.width,84+96*scale)
            XCTAssertEqual(perch.surface.rect.midX,perch.foot.x)
            XCTAssertEqual(perch.rect,CGRect(x:perch.foot.x-64*scale,y:perch.foot.y,width:128*scale,height:24*scale))
            let bottom=anchor(id:"right",frame:right,x:1,y:1)
            let lower=try XCTUnwrap(FixedPerchLayout.resolve(anchors:[bottom],world:world([right],scale:scale)).first)
            XCTAssertEqual(lower.foot.y,right.maxY-max(24*scale,24))
        }
    }

    func testNoSpaceNoDisplaysAndHostileRuntimeGeometryProduceNoPerches() {
        XCTAssertTrue(FixedPerchLayout.resolve(anchors:[anchor()],world:BehaviorWorld()).isEmpty)
        XCTAssertTrue(FixedPerchLayout.resolve(anchors:[anchor()],world:BehaviorWorld(screens:[left])).isEmpty)
        for frame in [CGRect(x:0,y:0,width:128,height:1000),CGRect(x:0,y:0,width:1600,height:104),
                      CGRect.zero,CGRect.infinite,CGRect(x:CGFloat.nan,y:0,width:1600,height:1000)] {
            XCTAssertTrue(FixedPerchLayout.resolve(anchors:[anchor()],world:world([frame])).isEmpty)
        }
        for scale:CGFloat in [0,-1,.nan,.infinity,CGFloat.greatestFiniteMagnitude] {
            XCTAssertTrue(FixedPerchLayout.resolve(anchors:[anchor()],world:world([right],scale:scale)).isEmpty)
        }
        for bad in [anchor(x:.nan),anchor(y:.infinity),anchor(slot:4),anchor(frame:.infinite)] {
            XCTAssertTrue(FixedPerchLayout.resolve(anchors:[bad],world:world([right])).isEmpty)
        }
        let invalidWork=world([right],screens:[.infinite])
        XCTAssertTrue(FixedPerchLayout.resolve(anchors:[anchor()],world:invalidWork).isEmpty)
    }

    func testNearbySlotsReserveBirdSpaceAndPreferLowestSlotRegardlessOfInputOrder() {
        let first=anchor(x:0.5,y:0.5),same=anchor(slot:2,x:0.5,y:0.5)
        let aboveBird=anchor(slot:3,x:0.5,y:0.55)
        let resolved=FixedPerchLayout.resolve(anchors:[aboveBird,same,first],world:world([left]))
        XCTAssertEqual(resolved.map(\.slot),[1])
        let separated=anchor(slot:2,x:0.75,y:0.5)
        let all=FixedPerchLayout.resolve(anchors:[aboveBird,separated,first],world:world([left]))
        XCTAssertEqual(all.map(\.slot),[1,2])
        XCTAssertFalse(all[0].rect.intersects(all[1].rect))
    }

    func testLargeScaleBirdSpacesCannotOverlapEvenWhenPerchImagesDoNot() {
        let first=anchor(x:0.25),close=anchor(slot:2,x:0.4125)
        // At 2x these images are 256pt wide with centers 260pt apart. Birds
        // at the ledge ends still need 308pt, so the second slot is suppressed.
        XCTAssertEqual(FixedPerchLayout.resolve(anchors:[first,close],world:world([left],scale:2)).map(\.slot),[1])
    }

    func testWorkAreaContractionSuppressesCollisionAndExpansionRestoresSlots() {
        let anchors=[anchor(x:0.25),anchor(slot:2,x:0.75),anchor(slot:3,x:0.5,y:0.85)]
        XCTAssertEqual(FixedPerchLayout.resolve(anchors:anchors,world:world([left])).map(\.slot),[1,2,3])
        let tiny=CGRect(x:-900,y:100,width:200,height:200)
        XCTAssertEqual(FixedPerchLayout.resolve(anchors:anchors,world:world([left],screens:[tiny])).map(\.slot),[1])
        XCTAssertEqual(FixedPerchLayout.resolve(anchors:anchors,world:world([left])).map(\.slot),[1,2,3])
    }

    func testPhysicalSurfaceIDCollisionSkipsOnlyThatSlotAndExistingFixedSurfaceDoesNotCollide() {
        let anchors=[anchor(),anchor(slot:2,x:0.75)]
        var snapshot=world([left])
        snapshot.surfaces=[Surface(id:0xFF000001,pid:44,rect:CGRect(x:-1000,y:500,width:300,height:200))]
        XCTAssertEqual(FixedPerchLayout.resolve(anchors:anchors,world:snapshot).map(\.slot),[2])
        snapshot.surfaces=[Surface(id:0xFF000001,pid:Int32.min+18,rect:.zero,isFixedPerch:true)]
        XCTAssertEqual(FixedPerchLayout.resolve(anchors:anchors,world:snapshot).map(\.slot),[1,2])
    }
}
