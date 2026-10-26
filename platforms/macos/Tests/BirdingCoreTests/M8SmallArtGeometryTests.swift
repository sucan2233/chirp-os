import Foundation
import XCTest
@testable import BirdingCore

final class M8SmallArtGeometryTests: XCTestCase {
    private typealias Geometry = M8SmallArtGeometry
    private let expected: [(SpeciesID,[String])] = [
        (.yellowBrowedWarbler,["canopyReady","canopyLift","canopyReturn","canopySettle"]),
        (.vinousThroatedParrotbill,["roundGather","roundTurn","roundSway","roundSettle"]),
        (.yellowRumpedFlycatcher,["wingPoise","wingFlick","wingLean","wingSettle"]),
        (.redFlankedBluetail,["blueTailReady","blueTailLift","blueTailLook","blueTailSettle"]),
        (.plumbeousWaterRedstart,["rustFanReady","rustFanOpen","rustFanLean","rustFanSettle"]),
        (.longTailedShrike,["vigilPoise","vigilReach","vigilHold","vigilSettle"]),
        (.blackDrongo,["forkPoise","forkOpen","forkFold","forkSettle"]),
        (.yellowBilledGrosbeak,["billLower","billFlex","billLift","billSettle"])
    ]

    func testExactSpeciesBudgetAndAppendOrder() {
        let base=["lookNear","lookFar","alertRise","alertHold","alertRelax",
                  "restLower","restTuck","restWake","takeoffCrouch","takeoffPush"]
        XCTAssertEqual(Geometry.species,expected.map { $0.0 })
        for (species,signature) in expected {
            XCTAssertEqual(Geometry.signatureFrameNames(for:species),signature)
            let frames=Geometry.frameNames(for:species)
            XCTAssertEqual(frames,base+signature,species.rawValue)
            XCTAssertEqual(Set(frames).count,14,species.rawValue)
        }
        XCTAssertEqual(Geometry.species.reduce(0) { $0+Geometry.frameNames(for:$1).count },112)
    }

    func testUnsupportedSpeciesAndExistingArtAreNotClaimed() {
        for species in SpeciesID.allCases where !expected.contains(where: { $0.0 == species }) {
            XCTAssertTrue(Geometry.frameNames(for:species).isEmpty,species.rawValue)
            XCTAssertTrue(Geometry.signatureFrameNames(for:species).isEmpty,species.rawValue)
            XCTAssertNil(Geometry.anatomy(for:species),species.rawValue)
            XCTAssertNil(Geometry.pose(species:species,frame:"lookNear"),species.rawValue)
            XCTAssertNil(Geometry.beakAnchor(species:species,frame:"lookNear"),species.rawValue)
        }
        for species in Geometry.species {
            for name in ["stand","idle0","fly0","catchOpen","catchClose","catchRecover",
                         "inspectLean","sideBrace","unknownM8c"] {
                XCTAssertNil(Geometry.pose(species:species,frame:name),"\(species).\(name)")
                XCTAssertNil(Geometry.beakAnchor(species:species,frame:name),"\(species).\(name)")
            }
        }
    }

    func testBillAnchorsUseTheActualVertexUnderHeadPitchAndTurn() throws {
        for species in Geometry.species {
            let anatomy=try XCTUnwrap(Geometry.anatomy(for:species))
            for name in Geometry.frameNames(for:species) {
                let pose=try XCTUnwrap(Geometry.pose(species:species,frame:name))
                let anchor=try XCTUnwrap(Geometry.beakAnchor(species:species,frame:name))
                let tip=pose.billVertices(anatomy:anatomy)[1]
                let pitch=pose.head.pitch
                XCTAssertEqual(anchor.x,pose.head.x+tip.0*cos(pitch)-tip.1*sin(pitch),accuracy:1e-10)
                XCTAssertEqual(anchor.y,pose.head.y+tip.0*sin(pitch)+tip.1*cos(pitch),accuracy:1e-10)
                var vertices=pose.billVertices(anatomy:anatomy)
                if pose.gape > 0 { vertices += pose.lowerBillVertices(anatomy:anatomy) }
                for vertex in vertices {
                    let point=pose.headPoint(vertex.0,vertex.1)
                    XCTAssertTrue((1.0...47.0).contains(Double(point.x)),"\(species).\(name): bill x")
                    XCTAssertTrue((1.0...47.0).contains(Double(point.y)),"\(species).\(name): bill y")
                }
            }
        }
    }

    func testEverySignatureFormsACompletePoseClip() throws {
        for (species,names) in expected {
            let frames=try names.map { name in
                PoseClip.Frame(name:name,duration:0.25,
                               beak:try XCTUnwrap(Geometry.beakAnchor(species:species,frame:name)))
            }
            let clip=try XCTUnwrap(PoseClip(id:"\(species.rawValue).m8c",frames:frames))
            XCTAssertEqual(clip.foot,PoseClip.Anchor(29,39))
            XCTAssertEqual(clip.duration,1,accuracy:1e-10)
            for index in names.indices {
                XCTAssertEqual(clip.sample(at:Double(index)*0.25+0.125)?.name,names[index])
            }
            XCTAssertNil(clip.sample(at:1))
        }
    }

    func testToeBandsKeepTheSharedPerchContact() {
        XCTAssertEqual(Geometry.toePaths.count,2)
        XCTAssertEqual(Geometry.toePaths.map { $0.count },[3,3])
        XCTAssertEqual(Geometry.toePaths[0].map { $0.0 },[25,27,29])
        XCTAssertEqual(Geometry.toePaths[1].map { $0.0 },[29,31,33])
        for path in Geometry.toePaths { XCTAssertEqual(path.map { $0.1 },[39,38.5,39]) }
        XCTAssertEqual(Geometry.toePaths[0][2].0,PoseClip.footAnchor.x)
        XCTAssertEqual(Geometry.toePaths[0][2].1,PoseClip.footAnchor.y)
        XCTAssertEqual(Geometry.toePaths[1][0].0,PoseClip.footAnchor.x)
        XCTAssertEqual(Geometry.toePaths[1][0].1,PoseClip.footAnchor.y)
    }
}
