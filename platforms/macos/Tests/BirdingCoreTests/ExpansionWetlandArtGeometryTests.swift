import Foundation
import XCTest
@testable import BirdingCore

/// Deferred E4 core contracts. Native raster uniqueness, old-image comparisons,
/// pigment bounds and visual acceptance require the coordinator's unified run.
final class ExpansionWetlandArtGeometryTests: XCTestCase {
    private typealias Geometry = ExpansionWetlandArtGeometry
    private let expected: [(SpeciesID,[String])] = [
        (.easternSpotBilledDuck,["spotShoulderReady","spotShoulderTurn","spotShoulderRecover","spotShoulderSettle"]),
        (.ruddyShelduck,["shelduckShoulderReady","shelduckShoulderTurn","shelduckShoulderRecover","shelduckShoulderSettle"]),
        (.easternCattleEgret,["cattleNeckReady","cattleNeckReach","cattleNeckRecover","cattleNeckSettle"]),
        (.blackTailedGull,["gullShoulderReady","gullShoulderTurn","gullShoulderRecover","gullShoulderSettle"]),
        (.greatCrestedGrebe,["crestedNeckReady","crestedNeckTurn","crestedNeckRecover","crestedNeckSettle"]),
        (.littleGrebe,["littleNeckReady","littleNeckTurn","littleNeckRecover","littleNeckSettle"])
    ]

    func testExactE4BudgetAndFrozenFrameOrder() {
        let base=["lookNear","lookFar","alertRise","alertHold","alertRelax",
                  "restLower","restTuck","restWake","takeoffCrouch","takeoffPush"]
        XCTAssertEqual(Geometry.species,expected.map { $0.0 })
        XCTAssertEqual(PoseClip.frameNames,base)
        for (species,signature) in expected {
            XCTAssertEqual(Geometry.signatureFrameNames(for:species),signature)
            XCTAssertEqual(Geometry.frameNames(for:species),base+signature)
            XCTAssertEqual(Set(Geometry.frameNames(for:species)).count,14)
        }
        XCTAssertEqual(Geometry.species.reduce(0) { $0+Geometry.frameNames(for:$1).count },84)
    }

    func testHistoricalWaterContactAndForeignFramesAreNotClaimed() {
        for species in SpeciesID.allCases where !Geometry.species.contains(species) {
            XCTAssertTrue(Geometry.frameNames(for:species).isEmpty)
            XCTAssertTrue(Geometry.signatureFrameNames(for:species).isEmpty)
            XCTAssertTrue(Geometry.toePaths(for:species).isEmpty)
            XCTAssertNil(Geometry.anatomy(for:species))
            XCTAssertNil(Geometry.pose(species:species,frame:"lookNear"))
            XCTAssertNil(Geometry.beakAnchor(species:species,frame:"lookNear"))
        }
        for species in Geometry.species {
            let foreign=expected.filter { $0.0 != species }.flatMap { $0.1 }
            for frame in ["stand","breathe","blink","idle0","idle1","idle2","preen0",
                          "preen1","fly0","glide0","land0","bathTouch","bathLower",
                          "carryGrip","neckReach","sideProbe",""]+foreign {
                XCTAssertNil(Geometry.pose(species:species,frame:frame),"\(species).\(frame)")
                XCTAssertNil(Geometry.beakAnchor(species:species,frame:frame),"\(species).\(frame)")
            }
        }
    }

    func testAnchorsFollowThePhysicalBillVertexThroughTurns() throws {
        for species in Geometry.species {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            for frame in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:frame))
                let anchor=try XCTUnwrap(Geometry.beakAnchor(species:species,frame:frame))
                let bill=p.billVertices(anatomy:a), tip=bill[2]
                XCTAssertEqual(bill.count,5)
                XCTAssertTrue(bill.indices.filter { $0 != 2 }.allSatisfy { bill[$0].0 < tip.0 })
                XCTAssertEqual(anchor.x,p.head.x+tip.0*cos(p.head.pitch)-tip.1*sin(p.head.pitch),accuracy:1e-10)
                XCTAssertEqual(anchor.y,p.head.y+tip.0*sin(p.head.pitch)+tip.1*cos(p.head.pitch),accuracy:1e-10)
                let body=a.bodyContour.map { p.bodyPoint($0.0,$0.1,anatomy:a) }
                let head=a.headContour.map { p.headPoint($0.0*p.headWidth(anatomy:a),$0.1*a.headHeight) }
                let billWorld=bill.map { p.headPoint($0.0,$0.1) }
                for point in body+head+billWorld {
                    XCTAssertTrue(point.0.isFinite && point.1.isFinite)
                    XCTAssertTrue((1.0...47.0).contains(point.0),"\(species).\(frame): x=\(point.0)")
                    XCTAssertTrue((1.0...47.0).contains(point.1),"\(species).\(frame): y=\(point.1)")
                }
            }
        }
    }

    func testNeckJoinsMovingHeadAndTorsoWithinCanvas() throws {
        for species in Geometry.species {
            let a=try XCTUnwrap(Geometry.anatomy(for:species))
            for frame in Geometry.frameNames(for:species) {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:frame))
                let path=p.neckPath(anatomy:a)
                XCTAssertEqual(path.count,4)
                let start=p.bodyPoint(0.81,0.36,anatomy:a)
                let end=p.headPoint(-a.headWidth*0.15,a.headHeight*0.18)
                let first=p.neckPoint(0,anatomy:a), last=p.neckPoint(1,anatomy:a)
                XCTAssertEqual(first.0,start.0,accuracy:1e-10)
                XCTAssertEqual(first.1,start.1,accuracy:1e-10)
                XCTAssertEqual(last.0,end.0,accuracy:1e-10)
                XCTAssertEqual(last.1,end.1,accuracy:1e-10)
                for i in 0...20 {
                    let point=p.neckPoint(Double(i)/20,anatomy:a), radius=a.neckWidth/2+1
                    XCTAssertGreaterThan(point.0-radius,0,"\(species).\(frame)")
                    XCTAssertLessThan(point.0+radius,48,"\(species).\(frame)")
                    XCTAssertGreaterThan(point.1-radius,0,"\(species).\(frame)")
                    XCTAssertLessThan(point.1+radius,48,"\(species).\(frame)")
                }
            }
        }
    }

    func testShelduckCollarRemainsCenteredAndNormalToBentNeck() throws {
        let a=try XCTUnwrap(Geometry.anatomy(for:.ruddyShelduck))
        for frame in Geometry.frameNames(for:.ruddyShelduck) {
            let p=try XCTUnwrap(Geometry.pose(species:.ruddyShelduck,frame:frame))
            let t=0.73, dt=0.00001, section=p.neckCrossSection(t,anatomy:a)
            let center=p.neckPoint(t,anatomy:a)
            let before=p.neckPoint(t-dt,anatomy:a), after=p.neckPoint(t+dt,anatomy:a)
            XCTAssertEqual(section.count,3)
            XCTAssertEqual(section[1].0,center.0,accuracy:1e-10)
            XCTAssertEqual(section[1].1,center.1,accuracy:1e-10)
            XCTAssertEqual((section[0].0+section[2].0)/2,center.0,accuracy:1e-10)
            XCTAssertEqual((section[0].1+section[2].1)/2,center.1,accuracy:1e-10)
            let across=(section[2].0-section[0].0,section[2].1-section[0].1)
            let along=((after.0-before.0)/(2*dt),(after.1-before.1)/(2*dt))
            XCTAssertEqual(hypot(across.0,across.1),a.neckWidth,accuracy:1e-8)
            XCTAssertEqual(across.0*along.0+across.1*along.1,0,accuracy:1e-5,frame)
        }
    }

    func testGrebesUseLowRearSupportAndDifferentBodyAndBillProportions() throws {
        let large=try XCTUnwrap(Geometry.anatomy(for:.greatCrestedGrebe))
        let small=try XCTUnwrap(Geometry.anatomy(for:.littleGrebe))
        let duck=try XCTUnwrap(Geometry.anatomy(for:.easternSpotBilledDuck))
        XCTAssertEqual(large.support,.rearGrebe)
        XCTAssertEqual(small.support,.rearGrebe)
        XCTAssertEqual(duck.support,.webbed)
        XCTAssertNotEqual(large.headHeight,small.headHeight)
        XCTAssertNotEqual(large.neckWidth,small.neckWidth)
        XCTAssertNotEqual(large.width,small.width)
        XCTAssertLessThan(large.tailWidth,duck.tailWidth)
        XCTAssertLessThan(small.tailWidth,duck.tailWidth)
        XCTAssertLessThan(large.billDepth,duck.billDepth)
        for species in Geometry.species {
            let paths=Geometry.toePaths(for:species)
            XCTAssertEqual(paths.count,2)
            XCTAssertTrue(paths.flatMap { $0 }.contains { PoseClip.Anchor($0.0,$0.1) == PoseClip.footAnchor })
            for path in paths { XCTAssertEqual(path.map { $0.1 },[39,38.5,39]) }
        }
        for species in [SpeciesID.greatCrestedGrebe,.littleGrebe] {
            let paths=Geometry.toePaths(for:species)
            XCTAssertEqual(paths.map { $0[1].0 },[23,27])
            for frame in Geometry.frameNames(for:species) where frame != "takeoffPush" {
                let p=try XCTUnwrap(Geometry.pose(species:species,frame:frame))
                XCTAssertGreaterThanOrEqual(p.body.y,22)
                XCTAssertGreaterThan(p.body.y+p.body.height,35)
                XCTAssertLessThan(p.body.y+p.body.height,37.5)
            }
        }
    }

    func testSignatureStagesRecoverIndependentHeadNeckWingAndTail() throws {
        for (species,names) in expected {
            let poses=try names.map { try XCTUnwrap(Geometry.pose(species:species,frame:$0)) }
            XCTAssertNotEqual(poses[0].head.pitch,poses[1].head.pitch)
            XCTAssertNotEqual(poses[0].neck.x,poses[1].neck.x)
            XCTAssertNotEqual(poses[0].tail.y,poses[1].tail.y)
            XCTAssertGreaterThan(poses[1].wing,poses[0].wing)
            XCTAssertLessThan(poses[2].wing,poses[1].wing)
            XCTAssertLessThan(poses[3].wing,poses[2].wing)
            XCTAssertLessThan(abs(poses[3].body.lean),0.2)
            switch species {
            case .easternSpotBilledDuck, .ruddyShelduck, .blackTailedGull:
                XCTAssertGreaterThan(poses[1].head.pitch,2)
                XCTAssertLessThan(poses[1].head.x,poses[0].head.x-4)
                XCTAssertLessThan(poses[2].head.pitch,0)
            case .easternCattleEgret:
                XCTAssertGreaterThan(poses[1].head.x,poses[0].head.x+2)
                XCTAssertLessThan(poses[2].head.y,poses[1].head.y-4)
                XCTAssertGreaterThan(poses[1].balance,poses[0].balance)
                XCTAssertEqual(poses[3].balance,0)
            case .greatCrestedGrebe, .littleGrebe:
                XCTAssertGreaterThan(poses[1].turn,0.9)
                XCTAssertLessThan(abs(poses[1].head.pitch),0.2)
                XCTAssertGreaterThan(poses[1].head.y,poses[0].head.y+1)
                XCTAssertGreaterThan(poses[1].ruffle,poses[2].ruffle)
            default: XCTFail("Unexpected E4 species")
            }
        }
    }

    func testSignatureClipsKeepFixedFootAndFiniteRecovery() throws {
        for (species,names) in expected {
            let frames=try names.map { frame in
                PoseClip.Frame(name:frame,duration:0.25,
                               beak:try XCTUnwrap(Geometry.beakAnchor(species:species,frame:frame)))
            }
            let clip=try XCTUnwrap(PoseClip(id:"\(species.rawValue).e4",frames:frames))
            XCTAssertEqual(clip.foot,PoseClip.Anchor(29,39))
            XCTAssertEqual(clip.maximumLoops,1)
            XCTAssertEqual(clip.duration,1,accuracy:1e-10)
            for i in names.indices {
                XCTAssertEqual(clip.sample(at:Double(i)*0.25+0.125)?.name,names[i])
            }
            XCTAssertNil(clip.sample(at:1))
        }
    }
}
