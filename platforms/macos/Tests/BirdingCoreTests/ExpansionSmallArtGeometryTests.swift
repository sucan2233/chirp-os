import Foundation
import XCTest
@testable import BirdingCore

/// Source contracts for the coordinator's deferred verification pass.
/// Raster uniqueness, pigment bounds and actual density require native art QA.
final class ExpansionSmallArtGeometryTests: XCTestCase {
    private typealias Geometry = ExpansionSmallArtGeometry
    private let expected: [(SpeciesID,[String])] = [
        (.marshTit,["marshReady","marshDip","marshReturn","marshSettle"]),
        (.greenBackedTit,["greenInspectReady","greenInspectReach","greenInspectLift","greenInspectSettle"]),
        (.blackThroatedBushtit,["chestnutReady","chestnutReach","chestnutRecoil","chestnutSettle"]),
        (.silverThroatedBushtit,["silverReady","silverPeer","silverReturn","silverSettle"]),
        (.whiskeredYuhina,["whiskerReady","whiskerLift","whiskerReturn","whiskerSettle"]),
        (.daurianRedstart,["daurianReady","daurianTailLift","daurianTailFall","daurianSettle"]),
        (.blueFrontedRedstart,["blueFrontReady","blueFrontTailLift","blueFrontReturn","blueFrontSettle"]),
        (.blackRedstart,["rufousReady","rufousTailLift","rufousReturn","rufousSettle"]),
        (.commonTailorbird,["tailorReady","tailorTailFan","tailorTailFold","tailorSettle"]),
        (.greyCappedGreenfinch,["greenfinchReady","greenfinchBillFlex","greenfinchLift","greenfinchSettle"]),
        (.twite,["twiteReady","twiteBillFlex","twiteReturn","twiteSettle"]),
        (.ornateSunbird,["sunbirdReady","sunbirdReach","sunbirdRecoil","sunbirdSettle"])
    ]

    func testFrozenSpeciesAndFrameAppendContract() {
        XCTAssertEqual(Geometry.species,expected.map { $0.0 })
        var total=0
        for (species,signature) in expected {
            let frames=Geometry.frameNames(for:species)
            XCTAssertEqual(Geometry.signatureFrameNames(for:species),signature)
            XCTAssertEqual(frames,PoseClip.frameNames+signature)
            XCTAssertEqual(Set(frames).count,14)
            total+=frames.count
        }
        XCTAssertEqual(total,168)
    }

    func testRejectsHistoricalFramesOtherSpeciesAndOtherBirdSignatures() {
        for species in SpeciesID.allCases where !Geometry.species.contains(species) {
            XCTAssertTrue(Geometry.frameNames(for:species).isEmpty)
            XCTAssertTrue(Geometry.signatureFrameNames(for:species).isEmpty)
            XCTAssertNil(Geometry.anatomy(for:species))
            XCTAssertNil(Geometry.pose(species:species,frame:"lookNear"))
            XCTAssertNil(Geometry.beakAnchor(species:species,frame:"lookNear"))
        }
        for (species,ownSignature) in expected {
            let otherSignatures=expected.flatMap { $0.1 }.filter { !ownSignature.contains($0) }
            for name in ["stand","breathe","blink","idle0","preen1","fly0","land0",""]+otherSignatures {
                XCTAssertNil(Geometry.pose(species:species,frame:name),"\(species).\(name)")
                XCTAssertNil(Geometry.beakAnchor(species:species,frame:name),"\(species).\(name)")
            }
        }
    }

    func testBillAnchorUsesRenderedTipWithPitchTurnAndOpenMandible() throws {
        for species in Geometry.species {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            for frame in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:frame))
                let anchor=try XCTUnwrap(Geometry.beakAnchor(species:species,frame:frame))
                let local=p.billVertices(anatomy:a)[1], pitch=p.head.pitch
                XCTAssertEqual(anchor.x,p.head.x+local.0*cos(pitch)-local.1*sin(pitch),accuracy:1e-10)
                XCTAssertEqual(anchor.y,p.head.y+local.0*sin(pitch)+local.1*cos(pitch),accuracy:1e-10)
                if species == .ornateSunbird {
                    // A straight-bill anchor at the same x would miss the curve.
                    XCTAssertEqual(local.1,3.9,accuracy:1e-10)
                    let straight=p.headPoint(local.0,0.55)
                    XCTAssertGreaterThan(hypot(anchor.x-straight.0,anchor.y-straight.1),3)
                }
            }
        }
    }

    func testAuthoredPartContoursLeaveTransparentCanvasMargin() throws {
        for species in Geometry.species {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            for frame in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:frame))
                var vertices=p.bodyVertices(anatomy:a)+p.tailVertices(species:species,anatomy:a)
                vertices+=p.wingVertices(anatomy:a)
                if p.wing > 0.18 { vertices+=p.wingVertices(anatomy:a,far:true) }
                var bill=p.billVertices(anatomy:a)
                if p.gape > 0 { bill+=p.lowerBillVertices(anatomy:a) }
                vertices+=bill.map { p.headPoint($0.0,$0.1) }
                for index in 0..<24 {
                    let angle=Double(index)*Double.pi/12
                    vertices.append(p.headPoint(cos(angle)*p.headWidth(anatomy:a)/2,
                                                sin(angle)*a.headHeight/2))
                }
                for vertex in vertices {
                    XCTAssertTrue(vertex.0.isFinite && vertex.1.isFinite,"\(species).\(frame)")
                    XCTAssertTrue((1.0...47.0).contains(vertex.0),"\(species).\(frame): x \(vertex.0)")
                    XCTAssertTrue((1.0...47.0).contains(vertex.1),"\(species).\(frame): y \(vertex.1)")
                }
            }
        }
    }

    func testSignatureEmphasisHasSpeciesSpecificArticulationAndSettles() throws {
        for (species,names) in expected {
            let poses=try names.map { try XCTUnwrap(Geometry.pose(species:species,frame:$0)) }
            let ready=poses[0], emphasis=poses[1], recovery=poses[2], settled=poses[3]
            XCTAssertGreaterThan(emphasis.wing,ready.wing)
            XCTAssertLessThan(settled.wing,recovery.wing)
            XCTAssertLessThan(recovery.wing,emphasis.wing)
            XCTAssertNotEqual(ready.body.height,emphasis.body.height)
            switch species {
            case .marshTit: XCTAssertGreaterThan(emphasis.head.y-ready.head.y,3)
            case .greenBackedTit: XCTAssertGreaterThan(emphasis.head.x-ready.head.x,1.3)
            case .blackThroatedBushtit, .whiskeredYuhina, .ornateSunbird:
                XCTAssertLessThan(emphasis.head.y-ready.head.y,-2)
                XCTAssertGreaterThan(recovery.head.y,emphasis.head.y)
            case .silverThroatedBushtit:
                XCTAssertGreaterThan(emphasis.head.x-ready.head.x,1.5)
                XCTAssertLessThan(recovery.head.x,emphasis.head.x)
            case .daurianRedstart, .blueFrontedRedstart, .blackRedstart, .commonTailorbird:
                XCTAssertLessThan(emphasis.tail.y-ready.tail.y,-6)
                XCTAssertGreaterThan(recovery.tail.y,emphasis.tail.y)
                XCTAssertGreaterThan(settled.tail.y,recovery.tail.y)
            case .greyCappedGreenfinch, .twite:
                XCTAssertGreaterThan(emphasis.gape,0.6)
                XCTAssertLessThan(recovery.gape,emphasis.gape)
                XCTAssertEqual(settled.gape,0)
            default: XCTFail("Unexpected E1 species")
            }
            let frames=try names.map { name in
                PoseClip.Frame(name:name,duration:0.25,
                               beak:try XCTUnwrap(Geometry.beakAnchor(species:species,frame:name)))
            }
            let clip=try XCTUnwrap(PoseClip(id:"\(species.rawValue).e1",frames:frames))
            XCTAssertEqual(clip.foot,PoseClip.Anchor(29,39))
            XCTAssertEqual(clip.duration,1,accuracy:1e-10)
            XCTAssertEqual(clip.sample(at:0.625)?.name,names[2])
            XCTAssertNil(clip.sample(at:1))
        }
    }

    func testFixedToesShareTheEstablishedPerchAnchor() {
        XCTAssertEqual(Geometry.toePaths.count,2)
        XCTAssertEqual(Geometry.toePaths[0].map { $0.0 },[25,27,29])
        XCTAssertEqual(Geometry.toePaths[1].map { $0.0 },[29,31,33])
        for path in Geometry.toePaths { XCTAssertEqual(path.map { $0.1 },[39,38.5,39]) }
        XCTAssertEqual(Geometry.toePaths[0][2].0,PoseClip.footAnchor.x)
        XCTAssertEqual(Geometry.toePaths[0][2].1,PoseClip.footAnchor.y)
        XCTAssertEqual(Geometry.toePaths[1][0].0,PoseClip.footAnchor.x)
        XCTAssertEqual(Geometry.toePaths[1][0].1,PoseClip.footAnchor.y)
    }
}
