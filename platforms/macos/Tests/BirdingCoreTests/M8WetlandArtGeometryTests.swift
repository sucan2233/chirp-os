import Foundation
import XCTest
@testable import BirdingCore

final class M8WetlandArtGeometryTests: XCTestCase {
    private typealias Geometry = M8WetlandArtGeometry

    func testBatchMembershipAndAppendOrder() {
        let expected: [SpeciesID] = [.nightHeron,.greyHeron,.chinesePondHeron,
            .blackWingedStilt,.whimbrel,.littleRingedPlover,.commonMoorhen,.eurasianCoot]
        XCTAssertEqual(Geometry.species,expected)
        var count=0
        for id in expected {
            let signature=Geometry.signatureFrameNames(for:id)
            let names=Geometry.frameNames(for:id)
            XCTAssertEqual(signature.count,4,id.rawValue)
            XCTAssertEqual(Set(signature).count,4,id.rawValue)
            XCTAssertTrue(Set(signature).isDisjoint(with:PoseClip.frameNames),id.rawValue)
            XCTAssertEqual(names,(id == .nightHeron ? []:PoseClip.frameNames)+signature,id.rawValue)
            XCTAssertEqual(Set(names).count,names.count,id.rawValue)
            count += names.count
        }
        XCTAssertEqual(count,102)
    }

    func testHistoricalNightHeronAndUnownedInputsFallThrough() {
        for name in PoseClip.frameNames+[
            "stand","breathe","blink","idle0","idle1","idle2","preen0","preen1"
        ] {
            XCTAssertNil(Geometry.pose(species:.nightHeron,frame:name),name)
            XCTAssertNil(Geometry.beakAnchor(species:.nightHeron,frame:name),name)
        }
        for id in SpeciesID.allCases where !Geometry.species.contains(id) {
            XCTAssertTrue(Geometry.frameNames(for:id).isEmpty,id.rawValue)
            XCTAssertTrue(Geometry.signatureFrameNames(for:id).isEmpty,id.rawValue)
            XCTAssertNil(Geometry.anatomy(for:id),id.rawValue)
            for name in PoseClip.frameNames+["shoulderGather","curveDip","breastLower"] {
                XCTAssertNil(Geometry.pose(species:id,frame:name),id.rawValue)
                XCTAssertNil(Geometry.beakAnchor(species:id,frame:name),id.rawValue)
            }
        }
        for id in Geometry.species {
            for name in ["stand","idle0","fly0","notAnM8dFrame"] {
                XCTAssertNil(Geometry.pose(species:id,frame:name),"\(id).\(name)")
                XCTAssertNil(Geometry.beakAnchor(species:id,frame:name),"\(id).\(name)")
            }
        }
    }

    func testEveryAppendedBillAnchorMatchesItsDrawingPrimitive() throws {
        for id in Geometry.species {
            let anatomy=try XCTUnwrap(Geometry.anatomy(for:id))
            for name in Geometry.frameNames(for:id) {
                let pose=try XCTUnwrap(Geometry.pose(species:id,frame:name))
                let anchor=try XCTUnwrap(Geometry.beakAnchor(species:id,frame:name))
                let path=pose.billPath(anatomy:anatomy)
                XCTAssertEqual(path.count,4,"\(id).\(name)")
                let tip=path[anatomy.curvedBill ? 3:1]
                let cosine=cos(pose.head.pitch), sine=sin(pose.head.pitch)
                XCTAssertEqual(anchor.x,pose.head.x+tip.0*cosine-tip.1*sine,accuracy:1e-10)
                XCTAssertEqual(anchor.y,pose.head.y+tip.0*sine+tip.1*cosine,accuracy:1e-10)
                XCTAssertEqual(anchor.mirrored(facingRight:false).x,48-anchor.x,accuracy:1e-10)
                XCTAssertEqual(anchor.mirrored(facingRight:false).y,anchor.y,accuracy:1e-10)
            }
        }
    }

    func testHeadAndBillKeepLogicalCanvasMargins() throws {
        // This is only a geometric head/bill bound, not raster/outline proof.
        // Full-art native-density clipping and uniqueness belong to integration.
        for id in Geometry.species {
            let anatomy=try XCTUnwrap(Geometry.anatomy(for:id))
            for name in Geometry.frameNames(for:id) {
                let pose=try XCTUnwrap(Geometry.pose(species:id,frame:name))
                var localPoints=pose.billPath(anatomy:anatomy)
                for n in 0..<32 {
                    let angle=Double(n)*Double.pi/16
                    localPoints.append((cos(angle)*pose.headWidth(anatomy:anatomy)/2,
                                        sin(angle)*anatomy.headHeight/2))
                }
                for local in localPoints {
                    let point=pose.headPoint(local.0,local.1)
                    XCTAssertTrue(point.0.isFinite && point.1.isFinite,"\(id).\(name)")
                    XCTAssertTrue((1.0...47.0).contains(point.0),"\(id).\(name): x=\(point.0)")
                    XCTAssertTrue((1.0...47.0).contains(point.1),"\(id).\(name): y=\(point.1)")
                }
            }
        }
    }

    func testWhimbrelUsesACurvedEndpointInEveryPose() throws {
        let anatomy=try XCTUnwrap(Geometry.anatomy(for:.whimbrel))
        XCTAssertTrue(anatomy.curvedBill)
        for name in Geometry.frameNames(for:.whimbrel) {
            let pose=try XCTUnwrap(Geometry.pose(species:.whimbrel,frame:name))
            let path=pose.billPath(anatomy:anatomy)
            XCTAssertGreaterThan(path[3].1,path[2].1+3,name)
            XCTAssertGreaterThan(path[2].0,path[3].0,name)
            XCTAssertGreaterThan(path[3].0,path[0].0+7,name)
        }
    }

    func testSignatureLandmarksFollowThePerSpeciesPlan() throws {
        func pose(_ id:SpeciesID, _ frame:String) throws -> Geometry.Pose {
            try XCTUnwrap(Geometry.pose(species:id,frame:frame))
        }
        let gathered=try pose(.nightHeron,"shoulderGather")
        let turned=try pose(.nightHeron,"shoulderTurn")
        let awake=try pose(.nightHeron,"shoulderWake")
        XCTAssertGreaterThan(turned.body.fluff,gathered.body.fluff)
        XCTAssertGreaterThan(turned.turn,gathered.turn)
        XCTAssertGreaterThan(awake.eye,turned.eye)
        let greyPoise=try pose(.greyHeron,"distantPoise")
        let greyReach=try pose(.greyHeron,"distantReach")
        XCTAssertLessThan(greyReach.head.y,greyPoise.head.y)
        XCTAssertGreaterThan(greyReach.head.x,greyPoise.head.x)
        let pondPoise=try pose(.chinesePondHeron,"lowPoise")
        let pondReach=try pose(.chinesePondHeron,"lowReach")
        XCTAssertGreaterThan(pondReach.head.y,pondPoise.head.y)
        XCTAssertGreaterThan(pondReach.body.lean,pondPoise.body.lean)
        let stiltTurn=try pose(.blackWingedStilt,"stiltTurn")
        let stiltInspect=try pose(.blackWingedStilt,"stiltInspect")
        XCTAssertGreaterThan(stiltTurn.turn,0.5)
        XCTAssertGreaterThan(stiltInspect.head.pitch,0.7)
        let curvePoise=try XCTUnwrap(Geometry.beakAnchor(species:.whimbrel,frame:"curvePoise"))
        let curveDip=try XCTUnwrap(Geometry.beakAnchor(species:.whimbrel,frame:"curveDip"))
        XCTAssertGreaterThan(curveDip.y,curvePoise.y+5)
        let ploverLower=try pose(.littleRingedPlover,"ploverLower")
        let ploverTap=try pose(.littleRingedPlover,"ploverTap")
        XCTAssertGreaterThan(ploverTap.head.y,ploverLower.head.y+5)
        let tailReady=try pose(.commonMoorhen,"railTailReady")
        let tailLift=try pose(.commonMoorhen,"railTailLift")
        XCTAssertLessThan(tailLift.tail.y,tailReady.tail.y-5)
        let breastLower=try pose(.eurasianCoot,"breastLower")
        let breastTip=try XCTUnwrap(Geometry.beakAnchor(species:.eurasianCoot,frame:"breastLower"))
        XCTAssertLessThan(breastTip.x,breastLower.head.x)
        XCTAssertGreaterThan(breastTip.y,breastLower.head.y+5)
        XCTAssertGreaterThan(try pose(.eurasianCoot,"breastShake").ruffle,0.8)
    }
}
