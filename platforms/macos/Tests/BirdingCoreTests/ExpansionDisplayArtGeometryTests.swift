import Foundation
import XCTest
@testable import BirdingCore

/// Authored with E3; intentionally left for the coordinator's unified test run.
final class ExpansionDisplayArtGeometryTests: XCTestCase {
    private typealias Geometry = ExpansionDisplayArtGeometry
    private let expected: [(SpeciesID,[String])] = [
        (.eurasianMagpie,["eurasianTailReady","eurasianTailBalance","eurasianTailReturn","eurasianTailSettle"]),
        (.greyTreepie,["treepieTailReady","treepieTailSweep","treepieLookBack","treepieTailSettle"]),
        (.redBilledBlueMagpie,["redBlueTailReady","redBlueTailArc","redBlueHeadReturn","redBlueTailSettle"]),
        (.yellowBilledBlueMagpie,["yellowBlueTailReady","yellowBlueTailPoise","yellowBlueTailReturn","yellowBlueTailSettle"]),
        (.ashyDrongo,["ashyForkReady","ashyForkOpen","ashyForkClose","ashyForkSettle"]),
        (.blueWhistlingThrush,["whistleTailReady","whistleTailFan","whistleTailFold","whistleTailSettle"]),
        (.sootyHeadedBulbul,["sootyCallReady","sootyCallOpen","sootyCallClose","sootyCallSettle"]),
        (.brownBreastedBulbul,["brownCallReady","brownCallOpen","brownCallReturn","brownCallSettle"]),
        (.blackBulbul,["blackCallReady","blackCallOpen","blackCallClose","blackCallSettle"]),
        (.collaredFinchbill,["collarBillReady","collarBillFlex","collarBillLift","collarBillSettle"]),
        (.taiwanBarbet,["taiwanCallReady","taiwanCallOpen","taiwanCallReturn","taiwanCallSettle"]),
        (.blueThroatedBarbet,["blueThroatReady","blueThroatOpen","blueThroatReturn","blueThroatSettle"])
    ]

    func testFrozenSpeciesAndFrameOrder() {
        let base=["lookNear","lookFar","alertRise","alertHold","alertRelax",
                  "restLower","restTuck","restWake","takeoffCrouch","takeoffPush"]
        XCTAssertEqual(Geometry.species,expected.map { $0.0 })
        for (species,signature) in expected {
            XCTAssertEqual(Geometry.signatureFrameNames(for:species),signature,species.rawValue)
            XCTAssertEqual(Geometry.frameNames(for:species),base+signature,species.rawValue)
            XCTAssertEqual(Set(Geometry.frameNames(for:species)).count,14,species.rawValue)
        }
        XCTAssertEqual(Geometry.species.reduce(0) { $0+Geometry.frameNames(for:$1).count },168)
    }

    func testHistoricalAndUnrelatedNamesAreNotClaimed() {
        for species in SpeciesID.allCases where !Geometry.species.contains(species) {
            XCTAssertTrue(Geometry.frameNames(for:species).isEmpty)
            XCTAssertTrue(Geometry.signatureFrameNames(for:species).isEmpty)
            XCTAssertNil(Geometry.anatomy(for:species))
            XCTAssertNil(Geometry.pose(species:species,frame:"lookNear"))
            XCTAssertNil(Geometry.beakAnchor(species:species,frame:"lookNear"))
        }
        for species in Geometry.species {
            let otherSignatures=expected.filter { $0.0 != species }.flatMap { $0.1 }
            for frame in ["stand","breathe","blink","idle0","idle1","idle2","preen0", "fly0",
                          "land0","glide0","tailPoise","forkOpen","unknownE3"]+otherSignatures {
                XCTAssertNil(Geometry.pose(species:species,frame:frame),"\(species).\(frame)")
                XCTAssertNil(Geometry.beakAnchor(species:species,frame:frame),"\(species).\(frame)")
            }
        }
    }

    func testBeakContactIsTheRenderedTipAndBillsHaveCanvasMargin() throws {
        for species in Geometry.species {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            for frame in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:frame))
                let anchor=try XCTUnwrap(Geometry.beakAnchor(species:species,frame:frame))
                let tip=p.billVertices(anatomy:a)[1], angle=p.head.pitch
                XCTAssertEqual(anchor.x,p.head.x+tip.0*cos(angle)-tip.1*sin(angle),accuracy:1e-10)
                XCTAssertEqual(anchor.y,p.head.y+tip.0*sin(angle)+tip.1*cos(angle),accuracy:1e-10)
                var vertices=p.billVertices(anatomy:a)
                if p.gape > 0 { vertices += p.lowerBillVertices(anatomy:a) }
                for vertex in vertices {
                    let point=p.headPoint(vertex.0,vertex.1)
                    XCTAssertTrue(point.0.isFinite && (1...47).contains(point.0),"\(species).\(frame) bill x")
                    XCTAssertTrue(point.1.isFinite && (1...47).contains(point.1),"\(species).\(frame) bill y")
                }
            }
        }
    }

    func testAllFourteenPosesArticulateRatherThanTranslateTheWholeBird() throws {
        for species in Geometry.species {
            let poses=try Geometry.frameNames(for:species).map {
                try XCTUnwrap(Geometry.pose(species:species,frame:$0))
            }
            let vectors=poses.map { p in
                [p.body.y,p.body.height,p.body.lean,p.body.fluff,p.head.x,p.head.y,p.head.pitch,
                 p.tail.x,p.tail.y,p.wing,p.spread,p.turn,p.gape,p.stance,p.crest]
            }
            for i in vectors.indices {
                for j in vectors.indices where j > i {
                    XCTAssertNotEqual(vectors[i],vectors[j],"\(species): \(i),\(j)")
                }
            }
            XCTAssertGreaterThan(Set(poses.map { $0.head.y-$0.body.y }).count,8,species.rawValue)
            XCTAssertGreaterThan(Set(poses.map { $0.tail.y-$0.body.y }).count,8,species.rawValue)
            XCTAssertGreaterThan(Set(poses.map { $0.wing }).count,6,species.rawValue)
            let crouch=poses[8], push=poses[9]
            XCTAssertGreaterThan(crouch.body.y,push.body.y)
            XCTAssertGreaterThan(push.wing,crouch.wing)
            XCTAssertNotEqual(crouch.head.pitch,push.head.pitch)
        }
    }

    func testSignaturesPrepareEmphasizeRecoverAndSettle() throws {
        let calling:Set<SpeciesID>=[.sootyHeadedBulbul,.brownBreastedBulbul,.blackBulbul,
                                   .collaredFinchbill,.taiwanBarbet,.blueThroatedBarbet]
        for (species,names) in expected {
            let poses=try names.map { try XCTUnwrap(Geometry.pose(species:species,frame:$0)) }
            if calling.contains(species) {
                XCTAssertGreaterThan(poses[1].gape,poses[0].gape)
                XCTAssertGreaterThan(poses[1].gape,poses[2].gape)
                XCTAssertEqual(poses[3].gape,0)
            } else {
                XCTAssertGreaterThan(poses[1].spread,poses[0].spread)
                XCTAssertGreaterThan(poses[1].spread,poses[2].spread)
                XCTAssertLessThan(poses[3].spread,poses[0].spread)
            }
            let frames=try zip(names,[0.24,0.42,0.28,0.36]).map { name,time in
                PoseClip.Frame(name:name,duration:time,
                               beak:try XCTUnwrap(Geometry.beakAnchor(species:species,frame:name)))
            }
            let clip=try XCTUnwrap(PoseClip(id:"\(species.rawValue).e3",frames:frames))
            XCTAssertEqual(clip.foot,PoseClip.Anchor(29,39))
            XCTAssertEqual(clip.sample(at:0.1)?.name,names[0])
            XCTAssertEqual(clip.sample(at:0.4)?.name,names[1])
            XCTAssertEqual(clip.sample(at:0.8)?.name,names[2])
            XCTAssertEqual(clip.sample(at:1.1)?.name,names[3])
            XCTAssertNil(clip.sample(at:1.31))
        }
    }

    func testPerchContactIsFixedAcrossAllFrames() {
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
