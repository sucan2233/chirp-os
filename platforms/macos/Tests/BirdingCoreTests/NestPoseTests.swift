import XCTest
@testable import BirdingCore

final class NestPoseTests:XCTestCase {
    private typealias F=NestTestSupport
    func testOnlyDoveHasTheEightFramesAndThreeSingleClockClipsWithoutExpandingLeafOrGiftPermissions() throws {
        XCTAssertEqual(SpeciesBehaviorProfile.nestCarryFrameNames,["carryLook","carryLower","carryGrip","carryPlace"])
        XCTAssertEqual(SpeciesBehaviorProfile.nestBuildFrameNames,["nestPlace","nestAdjust0","nestAdjust1","nestSettle"])
        for kind:BehaviorKind in [.nestMaterialCarry,.nestBuild] {
            XCTAssertEqual(SpeciesBehaviorProfile.species(for:kind),[.spottedDove])
        }
        XCTAssertEqual(SpeciesBehaviorProfile.species(for:.leafCarry),[.treeSparrow])
        XCTAssertEqual(SpeciesBehaviorProfile.species(for:.visitorGift),[.azureWingedMagpie])
        for species in SpeciesID.allCases {
            let allowed=species == .spottedDove
            XCTAssertEqual(PoseClip.nestMaterialPickup(species:species) != nil,allowed)
            XCTAssertEqual(PoseClip.nestMaterialPlace(species:species) != nil,allowed)
            XCTAssertEqual(PoseClip.nestBuild(species:species) != nil,allowed)
            if allowed {XCTAssertNil(PoseClip.leafCarryPickup(species:species));XCTAssertNil(PoseClip.leafCarryPlace(species:species))}
            for kind:BehaviorKind in [.nestMaterialCarry,.nestBuild] {
                let row=try XCTUnwrap(SpeciesSupportAudit(species:species,availableFrames:F.frames).behaviors.first{$0.kind==kind})
                XCTAssertEqual(row.productAllowed,allowed);XCTAssertEqual(row.contentSupported,allowed)
            }
        }
        let pickup=try XCTUnwrap(PoseClip.nestMaterialPickup(species:.spottedDove))
        let place=try XCTUnwrap(PoseClip.nestMaterialPlace(species:.spottedDove))
        let build=try XCTUnwrap(PoseClip.nestBuild(species:.spottedDove))
        XCTAssertEqual(pickup.frames.map(\.name),["carryLook","carryLower","carryGrip","carryLook"])
        XCTAssertEqual(pickup.frames.map(\.duration),[0.4,0.3,0.2,0.3])
        XCTAssertEqual(place.frames.map(\.name),["carryPlace","carryLook"])
        XCTAssertEqual(place.frames.map(\.duration),[0.4,0.3])
        XCTAssertEqual(build.frames.map(\.name),["nestPlace","nestAdjust0","nestAdjust1","nestAdjust0","nestAdjust1","nestSettle","nestPlace"])
        XCTAssertEqual(build.frames.map(\.duration),[0.3,0.3,0.3,0.3,0.3,0.4,0.3])
        for (clip,duration) in [(pickup,1.2),(place,0.7),(build,2.2)] {
            XCTAssertEqual(clip.duration,duration,accuracy:1e-12);XCTAssertEqual(clip.maximumLoops,1)
            XCTAssertEqual(clip.foot,.init(29,39));XCTAssertEqual(clip.recovery,.currentEngineState)
            XCTAssertNil(clip.sample(at:-0.1));XCTAssertNil(clip.sample(at:.nan));XCTAssertNil(clip.sample(at:clip.duration))
            XCTAssertEqual(try JSONDecoder().decode(PoseClip.self,from:JSONEncoder().encode(clip)),clip)
        }
        for (time,name) in [(0.69999,"carryLower"),(0.7,"carryGrip"),(0.89999,"carryGrip"),(0.9,"carryLook")] {
            XCTAssertEqual(pickup.sample(at:time)?.name,name)
        }
        XCTAssertEqual(place.sample(at:0.39999)?.name,"carryPlace");XCTAssertEqual(place.sample(at:0.4)?.name,"carryLook")
        XCTAssertEqual(build.sample(at:1.89999)?.name,"nestSettle");XCTAssertEqual(build.sample(at:1.9)?.name,"nestPlace")
    }

    func testAuthoredBillContactsAndTwigRotationContainIndependentPolygonVerticesAtEveryScaleAndHeading() throws {
        XCTAssertEqual(NestArtGeometry.nestSize,CGSize(width:144,height:48))
        XCTAssertEqual(NestArtGeometry.traySize,CGSize(width:32,height:16))
        XCTAssertEqual(TwigGeometry.logicalSize,CGSize(width:16,height:16))
        XCTAssertEqual(TwigGeometry.grip,CGPoint(x:3,y:12));XCTAssertEqual(TwigGeometry.surface,CGPoint(x:8,y:12))
        // Independent trace of the authored 56 opaque native cells. Keep this
        // literal separate from the production polygon used by the transform.
        let polygon:[CGPoint]=[(0,10),(3,10),(3,7),(5,7),(5,8),(6,8),(6,10),(7,10),(7,6),(9,6),
            (9,10),(10,10),(10,8),(11,8),(11,7),(13,7),(13,10),(16,10),(16,12),(0,12)].map{CGPoint(x:$0.0,y:$0.1)}
        XCTAssertEqual(TwigGeometry.polygon,polygon)
        for (frame,x,y):(String,Double,Double) in [("carryLook",40,19),("carryLower",40,31),("carryGrip",40,39),
            ("carryPlace",40,39),("nestPlace",40,26),("nestAdjust0",40,39),("nestAdjust1",41,39),("nestSettle",40,39)] {
            let anchor=try XCTUnwrap(PoseClip.nestBeakAnchor(species:.spottedDove,frame:frame))
            XCTAssertEqual(anchor.x,x,accuracy:1e-9);XCTAssertEqual(anchor.y,y,accuracy:1e-9)
            for scale:CGFloat in [0.5,1,2] {for right in [false,true] {
                let size=scale*SpeciesCatalog.standard.profile(.spottedDove).relativeScale,foot=CGPoint(x:-1000,y:-500)
                let point=anchor.world(foot:foot,scale:size,facingRight:right)
                XCTAssertEqual(point.x,foot.x+(right ? 1:-1)*CGFloat(x-29)*size,accuracy:1e-9)
                XCTAssertEqual(point.y,foot.y+CGFloat(y-39)*size,accuracy:1e-9)
                let sweep=try XCTUnwrap(TwigGeometry.sweptBounds(position:point,worldScale:scale,facingRight:right,rotationRange:-0.25...0.25))
                for angle:CGFloat in [-0.25,-0.12,0,0.13,0.25] {
                    let prop=NestGeometry.render(id:ScenePropID(73),position:point,worldScale:scale,facingRight:right,rotation:angle)
                    for vertex in polygon {
                        let dx=(vertex.x-3)*scale*(right ? 1:-1),dy=(vertex.y-12)*scale
                        let pixel=CGPoint(x:point.x+dx*cos(angle)-dy*sin(angle),y:point.y+dx*sin(angle)+dy*cos(angle))
                        // ULP-sized comparisons cover transform/extrema operation order.
                        let epsilon=max(abs(point.x),abs(point.y),1)*CGFloat.ulpOfOne*8
                        XCTAssertGreaterThanOrEqual(pixel.x,sweep.minX-epsilon);XCTAssertLessThanOrEqual(pixel.x,sweep.maxX+epsilon)
                        XCTAssertGreaterThanOrEqual(pixel.y,sweep.minY-epsilon);XCTAssertLessThanOrEqual(pixel.y,sweep.maxY+epsilon)
                        XCTAssertGreaterThanOrEqual(pixel.x,prop.rect.minX-epsilon);XCTAssertLessThanOrEqual(pixel.x,prop.rect.maxX+epsilon)
                        XCTAssertGreaterThanOrEqual(pixel.y,prop.rect.minY-epsilon);XCTAssertLessThanOrEqual(pixel.y,prop.rect.maxY+epsilon)
                    }
                }
            }}
        }
    }
}
