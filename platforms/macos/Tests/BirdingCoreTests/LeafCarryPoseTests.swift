import XCTest
@testable import BirdingCore

final class LeafCarryPoseTests:XCTestCase {
    func testOnlyTheSparrowHasBothAuthoredClipsAndTheCompleteFourFrameAdmissionContract() throws {
        let frames:[String]=["carryLook","carryLower","carryGrip","carryPlace"]
        XCTAssertEqual(SpeciesBehaviorProfile.carryFrameNames,frames)
        XCTAssertEqual(SpeciesBehaviorProfile.species(for:.leafCarry),[.treeSparrow])
        XCTAssertEqual(BirdCapability.carryingLeaf.requiredFrames,Set(frames))
        let required=Set(["stand","land0","land1","land2"] + (0..<8).map{"fly\($0)"} + frames)
        XCTAssertEqual(BehaviorDefinitions.definition(for:.leafCarry).requiredFrames,required)
        for species in SpeciesID.allCases {
            let allowed=species == .treeSparrow,profile=SpeciesBehaviorProfile.profile(for:species)
            XCTAssertEqual(profile.allows(.leafCarry),allowed)
            XCTAssertEqual(PoseClip.leafCarryPickup(species:species) != nil,allowed)
            XCTAssertEqual(PoseClip.leafCarryPlace(species:species) != nil,allowed)
            let audit=SpeciesSupportAudit(species:species,availableFrames:required)
            let row=try XCTUnwrap(audit.behaviors.first{$0.kind == .leafCarry})
            XCTAssertEqual(row.productAllowed,allowed);XCTAssertEqual(row.contentSupported,allowed)
            for missing in frames {
                let partial=SpeciesSupportAudit(species:species,availableFrames:required.subtracting([missing]))
                let entry=try XCTUnwrap(partial.behaviors.first{$0.kind == .leafCarry})
                XCTAssertEqual(entry.missingFrames,[missing]);XCTAssertFalse(entry.contentSupported)
            }
        }
    }

    func testPickupAndPlaceSingleClockBoundariesMatchTheirLiteralDurations() throws {
        let pickup=try XCTUnwrap(PoseClip.leafCarryPickup(species:.treeSparrow))
        let place=try XCTUnwrap(PoseClip.leafCarryPlace(species:.treeSparrow))
        XCTAssertEqual(pickup.frames.map(\.name),["carryLook","carryLower","carryGrip","carryLook"])
        XCTAssertEqual(pickup.frames.map(\.duration),[0.4,0.3,0.2,0.3])
        XCTAssertEqual(place.frames.map(\.name),["carryPlace","carryLook"])
        XCTAssertEqual(place.frames.map(\.duration),[0.4,0.3])
        XCTAssertEqual(pickup.duration,1.2,accuracy:1e-12);XCTAssertEqual(place.duration,0.7,accuracy:1e-12)
        for clip in [pickup,place] {
            XCTAssertEqual(clip.maximumLoops,1);XCTAssertEqual(clip.foot,.init(29,39))
            XCTAssertEqual(clip.recovery,.currentEngineState)
            XCTAssertNil(clip.sample(at:-0.1));XCTAssertNil(clip.sample(at:.nan))
            XCTAssertNil(clip.sample(at:clip.duration));XCTAssertNil(clip.sample(at:25))
            XCTAssertEqual(try JSONDecoder().decode(PoseClip.self,from:JSONEncoder().encode(clip)),clip)
        }
        let samples:[(Double,String)]=[(0,"carryLook"),(0.39999,"carryLook"),(0.4,"carryLower"),
            (0.69999,"carryLower"),(0.7,"carryGrip"),(0.89999,"carryGrip"),(0.9,"carryLook"),(1.19999,"carryLook")]
        for (time,name) in samples {XCTAssertEqual(pickup.sample(at:time)?.name,name)}
        XCTAssertEqual(place.sample(at:0)?.name,"carryPlace")
        XCTAssertEqual(place.sample(at:0.39999)?.name,"carryPlace")
        XCTAssertEqual(place.sample(at:0.4)?.name,"carryLook")
        XCTAssertEqual(place.sample(at:0.69999)?.name,"carryLook")
    }

    func testContactBillAndLeafAnchorsUseWorldScaleAndReflectAroundTheActualFoot() throws {
        XCTAssertEqual(CarryArtGeometry.leafLogicalSize,CGSize(width:16,height:16))
        XCTAssertEqual(CarryArtGeometry.leafGripAnchor,CGPoint(x:3,y:12))
        XCTAssertEqual(CarryArtGeometry.leafSurfaceAnchor,CGPoint(x:10,y:12))
        XCTAssertEqual(CarryArtGeometry.contactBeak,CGPoint(x:40,y:39))
        let foot=CGPoint(x:-210,y:520)
        for scale:CGFloat in [0.5,1,2] {
            let sprite=scale*SpeciesCatalog.standard.profile(.treeSparrow).relativeScale
            for frame in ["carryGrip","carryPlace"] {
                let anchor=try XCTUnwrap(PoseClip.carryBeakAnchor(species:.treeSparrow,frame:frame))
                XCTAssertEqual(anchor.x,40,accuracy:1e-9);XCTAssertEqual(anchor.y,39,accuracy:1e-9)
                for right in [false,true] {
                    let bill=anchor.world(foot:foot,scale:sprite,facingRight:right)
                    XCTAssertEqual(bill.x,foot.x+(right ? 11:-11)*sprite,accuracy:1e-9)
                    XCTAssertEqual(bill.y,foot.y,accuracy:1e-9)
                    let token=try XCTUnwrap(CarryArtGeometry.leafBounds(grip:bill,worldScale:scale,facingRight:right))
                    XCTAssertEqual(token.width,16*scale,accuracy:1e-9)
                    XCTAssertEqual(token.height,16*scale,accuracy:1e-9)
                    XCTAssertEqual(token.minX,bill.x-(right ? 3:13)*scale,accuracy:1e-9)
                    XCTAssertEqual(token.minY,bill.y-12*scale,accuracy:1e-9)
                    let surface=CGPoint(x:bill.x+(right ? 7:-7)*scale,y:bill.y)
                    XCTAssertEqual(surface.y,foot.y)
                }
            }
        }
    }

    func testEveryTransportFrameHasAFinitePreciseSparrowBillWithoutExpandingLeafCarryEligibility() throws {
        let frames=(0..<8).map{"fly\($0)"} + (0..<3).map{"land\($0)"}
        for frame in frames {
            let anchor=try XCTUnwrap(PoseClip.carryBeakAnchor(species:.treeSparrow,frame:frame))
            XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite)
            XCTAssertTrue((0...48).contains(anchor.x));XCTAssertTrue((0...48).contains(anchor.y))
            let a=anchor.world(foot:.zero,scale:1,facingRight:true)
            let b=anchor.world(foot:.zero,scale:1,facingRight:false)
            XCTAssertEqual(a.x,-b.x,accuracy:1e-9);XCTAssertEqual(a.y,b.y,accuracy:1e-9)
            XCTAssertEqual(PoseClip.beakAnchor(species:.treeSparrow,frame:frame),anchor)
        }
        // M6g authors magpie anchors for visitorGift. Shared artwork does not
        // grant the magpie the sparrow-only leafCarry behavior or clips.
        XCTAssertFalse(SpeciesBehaviorProfile.profile(for:.azureWingedMagpie).allows(.leafCarry))
        for frame in frames+["carryGrip","carryPlace"] {
            let anchor=try XCTUnwrap(PoseClip.carryBeakAnchor(species:.azureWingedMagpie,frame:frame))
            XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite)
            XCTAssertTrue((0...48).contains(anchor.x));XCTAssertTrue((0...48).contains(anchor.y))
            let a=anchor.world(foot:.zero,scale:1,facingRight:true)
            let b=anchor.world(foot:.zero,scale:1,facingRight:false)
            XCTAssertEqual(a.x,-b.x,accuracy:1e-9);XCTAssertEqual(a.y,b.y,accuracy:1e-9)
        }
        for species in SpeciesID.allCases where species != .treeSparrow && species != .azureWingedMagpie {
            for frame in frames+["carryGrip","carryPlace"] {
                XCTAssertNil(PoseClip.carryBeakAnchor(species:species,frame:frame))
            }
        }
        XCTAssertNil(PoseClip.carryBeakAnchor(species:.treeSparrow,frame:"unknown"))
    }

    func testLeafTokenPropBoundsRetainMirroringAndRotationBeyondTheBirdCanvas() throws {
        for scale:CGFloat in [0.5,1,2] {
            for right in [false,true] {
                let grip=CGPoint(x:300,y:400)
                let prop=ScenePropRenderState(id:ScenePropID(1),kind:.leafToken,position:grip,size:16*scale,
                    rotation:0,opacity:1,blockers:[],frameName:"leafToken",anchor:CGPoint(x:3.0/16,y:12.0/16),mirrored:!right)
                XCTAssertEqual(prop.rect,CGRect(x:grip.x-(right ? 3:13)*scale,y:grip.y-12*scale,
                    width:16*scale,height:16*scale))
                let rotated=ScenePropRenderState(id:prop.id,kind:prop.kind,position:prop.position,size:prop.size,
                    rotation:.pi/2,opacity:prop.opacity,blockers:prop.blockers,frameName:prop.frameName,
                    anchor:prop.anchor,mirrored:prop.mirrored)
                XCTAssertEqual(rotated.rect.minX,grip.x-4*scale,accuracy:1e-9)
                XCTAssertEqual(rotated.rect.minY,grip.y-(right ? 3:13)*scale,accuracy:1e-9)
                XCTAssertEqual(rotated.rect.width,16*scale,accuracy:1e-9)
                XCTAssertEqual(rotated.rect.height,16*scale,accuracy:1e-9)
                let recorded=RecordedPropState(rotated)
                XCTAssertEqual(recorded.mirrored,!right)
                XCTAssertEqual(try JSONDecoder().decode(RecordedPropState.self,from:JSONEncoder().encode(recorded)),recorded)
            }
        }
        XCTAssertNil(CarryArtGeometry.leafBounds(grip:.zero,worldScale:0,facingRight:true))
        XCTAssertNil(CarryArtGeometry.leafBounds(grip:CGPoint(x:CGFloat.nan,y:0),worldScale:1,facingRight:true))
    }
}
