import Foundation
import XCTest
@testable import BirdingCore

/// Source-only E2 contract tests. Native pixel, density and historical-image
/// comparisons belong to the coordinator's deferred unified acceptance run.
final class ExpansionGroundArtGeometryTests: XCTestCase {
    private typealias Geometry = ExpansionGroundArtGeometry
    private let expected: [(SpeciesID,[String])] = [
        (.silkyStarling,["silkBowReady","silkBowDown","silkBowRecover","silkBowSettle"]),
        (.whiteCheekedStarling,["cheekDipReady","cheekDipDown","cheekDipRecover","cheekDipSettle"]),
        (.carrionCrow,["crowInclineReady","crowInclineDown","crowInclineRecover","crowInclineSettle"]),
        (.daurianJackdaw,["jackdawLeanReady","jackdawLeanDown","jackdawLeanRecover","jackdawLeanSettle"]),
        (.redBilledChough,["choughProbeReady","choughProbeDown","choughProbeRecover","choughProbeSettle"]),
        (.plainLaughingthrush,["plainDipReady","plainDipDown","plainDipRecover","plainDipSettle"]),
        (.henricsLaughingthrush,["henricLookReady","henricLookDown","henricLookRecover","henricLookSettle"]),
        (.whiteBrowedLaughingthrush,["whiteBrowLeanReady","whiteBrowLeanDown","whiteBrowLeanRecover","whiteBrowLeanSettle"]),
        (.groundTit,["groundProbeReady","groundProbeDown","groundProbeRecover","groundProbeSettle"]),
        (.rufousBreastedAccentor,["accentorDipReady","accentorDipDown","accentorDipRecover","accentorDipSettle"]),
        (.hornedLark,["hornLookReady","hornLookDown","hornLookRecover","hornLookSettle"]),
        (.redThroatedThrush,["redThroatLeanReady","redThroatLeanDown","redThroatLeanRecover","redThroatLeanSettle"])
    ]

    func testFrozenSpeciesFrameBudgetAndOrder() {
        let base=["lookNear","lookFar","alertRise","alertHold","alertRelax",
                  "restLower","restTuck","restWake","takeoffCrouch","takeoffPush"]
        XCTAssertEqual(Geometry.species,expected.map { $0.0 })
        XCTAssertEqual(PoseClip.frameNames,base)
        for (species,signature) in expected {
            XCTAssertEqual(Geometry.signatureFrameNames(for:species),signature,species.rawValue)
            XCTAssertEqual(Geometry.frameNames(for:species),base+signature,species.rawValue)
            XCTAssertEqual(Set(Geometry.frameNames(for:species)).count,14)
        }
        XCTAssertEqual(Geometry.species.reduce(0) { $0+Geometry.frameNames(for:$1).count },168)
    }

    func testForeignSpeciesAndHistoricalFramesAreNotClaimed() {
        for species in SpeciesID.allCases where !Geometry.species.contains(species) {
            XCTAssertTrue(Geometry.frameNames(for:species).isEmpty)
            XCTAssertTrue(Geometry.signatureFrameNames(for:species).isEmpty)
            XCTAssertNil(Geometry.anatomy(for:species))
            XCTAssertNil(Geometry.pose(species:species,frame:"lookNear"))
            XCTAssertNil(Geometry.beakAnchor(species:species,frame:"lookNear"))
        }
        for species in Geometry.species {
            let foreign=expected.filter { $0.0 != species }.flatMap { $0.1 }
            for name in ["stand","breathe","blink","idle0","idle1","idle2",
                         "preen0","fly0","land0","peckLower","inspectLean",""]+foreign {
                XCTAssertNil(Geometry.pose(species:species,frame:name),"\(species).\(name)")
                XCTAssertNil(Geometry.beakAnchor(species:species,frame:name),"\(species).\(name)")
            }
        }
    }

    func testPhysicalBillTipAndDrawnGeometryKeepCanvasMargins() throws {
        for species in Geometry.species {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            for name in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:name))
                let anchor=try XCTUnwrap(Geometry.beakAnchor(species:species,frame:name))
                let vertices=p.billVertices(anatomy:a), tip=vertices[3]
                XCTAssertEqual(vertices.count,7)
                XCTAssertEqual(anchor.x,p.head.x+tip.0*cos(p.head.pitch)-tip.1*sin(p.head.pitch),accuracy:1e-10)
                XCTAssertEqual(anchor.y,p.head.y+tip.0*sin(p.head.pitch)+tip.1*cos(p.head.pitch),accuracy:1e-10)
                let bill=vertices.map { p.headPoint($0.0,$0.1) }
                let torso=a.bodyContour.map { p.bodyPoint($0.0,$0.1,anatomy:a) }
                let headCorners=[(-a.headWidth/2,-a.headHeight/2),
                                 (a.headWidth/2,-a.headHeight/2),
                                 (a.headWidth/2,a.headHeight/2),
                                 (-a.headWidth/2,a.headHeight/2)].map { p.headPoint($0.0,$0.1) }
                let tail=[(p.tail.x,p.tail.y-1.2),
                          (p.tail.x+a.tailWidth+p.fan*2.2,p.tail.y+1.5)]
                for point in bill+torso+headCorners+tail {
                    XCTAssertTrue(point.0.isFinite && point.1.isFinite,"\(species).\(name)")
                    XCTAssertTrue((1.0...47.0).contains(point.0),"\(species).\(name): x=\(point.0)")
                    XCTAssertTrue((1.0...47.0).contains(point.1),"\(species).\(name): y=\(point.1)")
                }
            }
        }
    }

    func testCurvedBillsAndCrowBillKeepIndependentAnatomy() throws {
        for species in [SpeciesID.redBilledChough,.groundTit,.plainLaughingthrush] {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            XCTAssertGreaterThanOrEqual(a.billLength,5.8,species.rawValue)
            XCTAssertGreaterThan(a.billCurve,3,species.rawValue)
            for name in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:name))
                let bill=p.billVertices(anatomy:a)
                XCTAssertGreaterThan(bill[3].1-bill[0].1,3)
                XCTAssertGreaterThan(bill[3].0,bill[2].0)
                XCTAssertGreaterThan(bill[3].0,bill[4].0)
            }
        }
        let crow=try XCTUnwrap(Geometry.anatomy(for:.carrionCrow))
        let jackdaw=try XCTUnwrap(Geometry.anatomy(for:.daurianJackdaw))
        let chough=try XCTUnwrap(Geometry.anatomy(for:.redBilledChough))
        let tit=try XCTUnwrap(Geometry.anatomy(for:.groundTit))
        let accentor=try XCTUnwrap(Geometry.anatomy(for:.rufousBreastedAccentor))
        XCTAssertGreaterThan(crow.billDepth,jackdaw.billDepth)
        XCTAssertGreaterThan(crow.billDepth,chough.billDepth)
        XCTAssertLessThan(crow.billCurve,1)
        XCTAssertLessThan(tit.kneeHeight,accentor.kneeHeight)
        XCTAssertGreaterThan(tit.billLength,accentor.billLength*2)
    }

    func testSignaturesLowerRecoverAndSettleWithIndependentJoints() throws {
        for (species,names) in expected {
            let poses=try names.map { try XCTUnwrap(Geometry.pose(species:species,frame:$0)) }
            let anchors=try names.map { try XCTUnwrap(Geometry.beakAnchor(species:species,frame:$0)) }
            XCTAssertGreaterThan(anchors[1].y,anchors[0].y+3,species.rawValue)
            XCTAssertLessThan(anchors[2].y,anchors[1].y-4,species.rawValue)
            XCTAssertLessThan(abs(poses[3].body.lean),0.3,species.rawValue)
            XCTAssertLessThan(poses[3].wing,poses[1].wing,species.rawValue)
            XCTAssertGreaterThan(poses[1].body.lean,poses[0].body.lean,species.rawValue)
            XCTAssertLessThan(poses[1].tail.y,poses[0].tail.y-2,species.rawValue)
            XCTAssertGreaterThan(poses[2].tail.y,poses[1].tail.y+2,species.rawValue)
            XCTAssertNotEqual(poses[0].head.pitch,poses[1].head.pitch)
            XCTAssertNotEqual(poses[0].stance,poses[1].stance)

            let frames=zip(names,anchors).map { PoseClip.Frame(name:$0.0,duration:0.25,beak:$0.1) }
            let clip=try XCTUnwrap(PoseClip(id:"\(species.rawValue).e2",frames:frames))
            XCTAssertEqual(clip.foot,PoseClip.Anchor(29,39))
            XCTAssertEqual(clip.duration,1,accuracy:1e-10)
            for i in names.indices {
                XCTAssertEqual(clip.sample(at:Double(i)*0.25+0.125)?.name,names[i])
            }
            XCTAssertNil(clip.sample(at:1))
        }
    }

    func testRestAndTakeoffHaveDistinctBodyAndWingConfigurations() throws {
        for species in Geometry.species {
            let lower=try XCTUnwrap(Geometry.pose(species:species,frame:"restLower"))
            let tuck=try XCTUnwrap(Geometry.pose(species:species,frame:"restTuck"))
            let crouch=try XCTUnwrap(Geometry.pose(species:species,frame:"takeoffCrouch"))
            let push=try XCTUnwrap(Geometry.pose(species:species,frame:"takeoffPush"))
            XCTAssertGreaterThan(tuck.head.pitch,2)
            XCTAssertGreaterThan(tuck.body.fluff,lower.body.fluff)
            XCTAssertGreaterThan(crouch.body.y,push.body.y+5)
            XCTAssertGreaterThan(push.wing,0.8)
            XCTAssertLessThan(crouch.wing,0.4)
            XCTAssertLessThan(crouch.stance,0)
            XCTAssertGreaterThan(push.stance,0)
        }
    }

    func testBothToeBandsMeetAtThePresentationFoot() throws {
        XCTAssertEqual(Geometry.toePaths.count,2)
        let rear=try XCTUnwrap(Geometry.toePaths.first?.last)
        let front=try XCTUnwrap(Geometry.toePaths.last?.first)
        XCTAssertEqual(PoseClip.Anchor(rear.0,rear.1),PoseClip.footAnchor)
        XCTAssertEqual(PoseClip.Anchor(front.0,front.1),PoseClip.footAnchor)
        for path in Geometry.toePaths {
            XCTAssertEqual(path.map { $0.1 },[39,38.5,39])
        }
    }
}
