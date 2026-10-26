import Foundation
import XCTest
@testable import BirdingCore

/// Deferred E5 source contracts; native pixels and integration require the
/// coordinator's complete-build verification, not these geometry assertions.
final class ExpansionLargeArtGeometryTests: XCTestCase {
    private typealias Geometry = ExpansionLargeArtGeometry
    private let expected:[(SpeciesID,[String])] = [
        (.orientalTurtleDove,["turtleShoulderReady","turtleShoulderTurn","turtleShoulderLift","turtleShoulderSettle"]),
        (.eurasianCollaredDove,["collaredTurnReady","collaredTurnEase","collaredTurnReturn","collaredTurnSettle"]),
        (.uplandBuzzard,["uplandWatchReady","uplandWatchLoosen","uplandWatchFold","uplandWatchSettle"]),
        (.himalayanVulture,["vultureGazeReady","vultureGazeDraw","vultureGazeRecover","vultureGazeSettle"]),
        (.commonPheasant,["pheasantPeerReady","pheasantPeerLower","pheasantPeerLift","pheasantPeerSettle"]),
        (.greaterCoucal,["coucalLiftReady","coucalLiftGape","coucalLiftClose","coucalLiftSettle"])
    ]

    func testFrozenE5SpeciesAndAppendOrder() {
        XCTAssertEqual(Geometry.species,expected.map { $0.0 })
        var total=0
        for (species,signature) in expected {
            let frames=Geometry.frameNames(for:species)
            XCTAssertEqual(Geometry.signatureFrameNames(for:species),signature)
            XCTAssertEqual(frames,PoseClip.frameNames+signature)
            XCTAssertEqual(Set(frames).count,14)
            total+=frames.count
        }
        XCTAssertEqual(total,84)
    }

    func testUnsupportedSpeciesHistoricalFramesAndForeignSignaturesReturnNil() {
        for species in SpeciesID.allCases where !Geometry.species.contains(species) {
            XCTAssertNil(Geometry.anatomy(for:species))
            XCTAssertNil(Geometry.pose(species:species,frame:"lookNear"))
            XCTAssertNil(Geometry.beakAnchor(species:species,frame:"lookNear"))
            XCTAssertTrue(Geometry.frameNames(for:species).isEmpty)
            XCTAssertTrue(Geometry.signatureFrameNames(for:species).isEmpty)
        }
        for (species,own) in expected {
            let foreign=expected.flatMap { $0.1 }.filter { !own.contains($0) }
            for frame in ["stand","blink","breathe","idle0","preen0","fly0","land0",""]+foreign {
                XCTAssertNil(Geometry.pose(species:species,frame:frame),"\(species).\(frame)")
                XCTAssertNil(Geometry.beakAnchor(species:species,frame:frame),"\(species).\(frame)")
            }
        }
    }

    func testBeakAnchorsUsePhysicalTipsIncludingDescendingRaptorHooks() throws {
        for species in Geometry.species {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            for frame in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:frame))
                let vertices=p.billVertices(anatomy:a), tip=try XCTUnwrap(vertices.last)
                let anchor=try XCTUnwrap(Geometry.beakAnchor(species:species,frame:frame))
                let pitch=p.head.pitch
                XCTAssertEqual(anchor.x,p.head.x+tip.0*cos(pitch)-tip.1*sin(pitch),accuracy:1e-10)
                XCTAssertEqual(anchor.y,p.head.y+tip.0*sin(pitch)+tip.1*cos(pitch),accuracy:1e-10)
                if a.bill == .hooked {
                    let elbowX=try XCTUnwrap(vertices.map { $0.0 }.max())
                    XCTAssertLessThan(tip.0,elbowX)
                    XCTAssertGreaterThan(tip.1,2.5)
                    let elbow=p.headPoint(elbowX,0.2)
                    XCTAssertGreaterThan(hypot(anchor.x-elbow.0,anchor.y-elbow.1),2)
                }
            }
        }
    }

    func testAllAuthoredPartsHaveCanvasMargin() throws {
        for species in Geometry.species {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            for frame in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:frame))
                var vertices=p.bodyVertices(anatomy:a)+p.tailVertices(anatomy:a)+p.neckVertices(anatomy:a)
                vertices+=p.wingVertices(anatomy:a)
                if p.wing > 0.18 { vertices+=p.wingVertices(anatomy:a,far:true) }
                if species == .himalayanVulture { vertices+=p.ruffVertices(anatomy:a) }
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
                    XCTAssertTrue((1.0...47.0).contains(vertex.0),"\(species).\(frame) x=\(vertex.0)")
                    XCTAssertTrue((1.0...47.0).contains(vertex.1),"\(species).\(frame) y=\(vertex.1)")
                }
            }
        }
    }

    func testCollarsUseMovingNeckSectionsAndVultureHasIndependentRuff() throws {
        for species in [SpeciesID.orientalTurtleDove,.eurasianCollaredDove,.commonPheasant,.himalayanVulture] {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            for frame in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:frame))
                for along in [0.2,0.6,0.85] {
                    let center=p.neckCenter(along,anatomy:a), tangent=p.neckTangent(along,anatomy:a)
                    let left=p.neckPoint(along,-0.5,anatomy:a), right=p.neckPoint(along,0.5,anatomy:a)
                    XCTAssertEqual((left.0+right.0)/2,center.0,accuracy:1e-10)
                    XCTAssertEqual((left.1+right.1)/2,center.1,accuracy:1e-10)
                    XCTAssertEqual((right.0-left.0)*tangent.0+(right.1-left.1)*tangent.1,0,accuracy:1e-9)
                }
                if species == .himalayanVulture {
                    XCTAssertLessThan(a.neckWidth,a.headWidth/2)
                    let left=p.ruffPoint(-1,0,anatomy:a), right=p.ruffPoint(1,0,anatomy:a)
                    XCTAssertGreaterThan(hypot(right.0-left.0,right.1-left.1),a.headWidth)
                    XCTAssertEqual(p.ruffVertices(anatomy:a).count,24)
                }
            }
        }
    }

    func testDistinctJointRowsAndCompleteSignaturePhases() throws {
        for (species,names) in expected {
            var joints=Set<[Double]>()
            for name in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:name))
                let row=[p.body.y,p.body.height,p.body.lean,p.body.fluff,
                         p.head.x,p.head.y,p.head.pitch,p.neck.x,p.neck.y,
                         p.tail.x,p.tail.y,p.wing,p.shoulder,p.turn,p.gape,p.stance]
                XCTAssertTrue(joints.insert(row).inserted,"Duplicate joint row \(species).\(name)")
            }
            let poses=try names.map { try XCTUnwrap(Geometry.pose(species:species,frame:$0)) }
            XCTAssertGreaterThan(poses[1].wing,poses[0].wing)
            XCTAssertLessThan(poses[2].wing,poses[1].wing)
            XCTAssertLessThan(poses[3].wing,poses[2].wing)
            switch species {
            case .orientalTurtleDove:
                XCTAssertGreaterThan(poses[1].head.pitch,2)
                XCTAssertLessThan(poses[1].head.x,poses[0].head.x-3)
                XCTAssertLessThan(poses[2].head.pitch,0)
            case .eurasianCollaredDove:
                XCTAssertLessThan(poses[0].turn,0)
                XCTAssertGreaterThan(poses[1].turn,0.6)
                XCTAssertGreaterThan(poses[1].shoulder,poses[2].shoulder)
            case .uplandBuzzard:
                XCTAssertGreaterThan(poses[1].shoulder,1)
                XCTAssertLessThan(poses[2].shoulder,0)
            case .himalayanVulture:
                XCTAssertGreaterThan(poses[1].head.y-poses[0].head.y,4)
                XCTAssertGreaterThan(poses[1].neck.y-poses[0].neck.y,3)
                XCTAssertLessThan(poses[2].head.y,poses[1].head.y)
            case .commonPheasant:
                XCTAssertGreaterThan(poses[1].head.y-poses[0].head.y,4)
                XCTAssertLessThan(poses[1].tail.y,poses[0].tail.y)
                XCTAssertGreaterThan(poses[3].tail.y,poses[2].tail.y)
            case .greaterCoucal:
                XCTAssertGreaterThan(poses[1].gape,0.6)
                XCTAssertLessThan(poses[2].gape,poses[1].gape)
                XCTAssertEqual(poses[3].gape,0)
            default: XCTFail("Unexpected E5 species")
            }
            let frames=try names.map { name in
                PoseClip.Frame(name:name,duration:0.3,
                               beak:try XCTUnwrap(Geometry.beakAnchor(species:species,frame:name)))
            }
            let clip=try XCTUnwrap(PoseClip(id:"\(species.rawValue).e5",frames:frames))
            XCTAssertEqual(clip.foot,PoseClip.Anchor(29,39))
            XCTAssertEqual(clip.duration,1.2,accuracy:1e-10)
            XCTAssertEqual(clip.sample(at:0.75)?.name,names[2])
            XCTAssertNil(clip.sample(at:1.3))
        }
    }

    func testImmutableFeetAndDistinctLongTailAnatomy() throws {
        XCTAssertEqual(Geometry.toePaths.count,2)
        XCTAssertEqual(Geometry.toePaths[0].map { $0.0 },[25,27,29])
        XCTAssertEqual(Geometry.toePaths[1].map { $0.0 },[29,31,33])
        for path in Geometry.toePaths { XCTAssertEqual(path.map { $0.1 },[39,38.5,39]) }
        XCTAssertEqual(Geometry.toePaths[0][2].0,PoseClip.footAnchor.x)
        XCTAssertEqual(Geometry.toePaths[0][2].1,PoseClip.footAnchor.y)
        XCTAssertEqual(Geometry.toePaths[1][0].0,PoseClip.footAnchor.x)
        XCTAssertEqual(Geometry.toePaths[1][0].1,PoseClip.footAnchor.y)
        let pheasant=try XCTUnwrap(Geometry.anatomy(for:.commonPheasant))
        let coucal=try XCTUnwrap(Geometry.anatomy(for:.greaterCoucal))
        XCTAssertEqual(pheasant.tail,.tapered)
        XCTAssertEqual(coucal.tail,.graduated)
        XCTAssertLessThan(pheasant.width,coucal.width)
        XCTAssertLessThan(pheasant.tailWidth,coucal.tailWidth)
        // Compare proportion with the short-tailed dove instead of imposing
        // one absolute length on differently proportioned species.
        let dove=try XCTUnwrap(Geometry.anatomy(for:.orientalTurtleDove))
        let dovePose=try XCTUnwrap(Geometry.pose(species:.orientalTurtleDove,frame:"lookNear"))
        let doveRoot=dovePose.tailPoint(0,0,anatomy:dove)
        let doveTailRatio=hypot(doveRoot.0-dovePose.tail.x,doveRoot.1-dovePose.tail.y)/dove.width
        for species in [SpeciesID.commonPheasant,.greaterCoucal] {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            let p=try XCTUnwrap(Geometry.pose(species:species,frame:"lookNear"))
            let root=p.tailPoint(0,0,anatomy:a)
            XCTAssertGreaterThan(hypot(root.0-p.tail.x,root.1-p.tail.y)/a.width,doveTailRatio,species.rawValue)
        }
    }
}
