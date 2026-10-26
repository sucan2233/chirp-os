import XCTest
@testable import BirdingCore

final class ExpansionCompletionTests: XCTestCase {
    func testFiveBatchesExactlyCoverRemainingFortyEightWithoutChangingE0OrOriginalCohorts() {
        let approved=ExpansionCompletionFixture.newSpecies
        let e0:[SpeciesID]=[.eurasianGreatTit,.whiteWagtail,.indianWhiteEye,.crestedMyna,.eurasianNuthatch,.greatEgret]
        let original=Set(SpeciesCatalog.standard.species.prefix(46).map(\.id))
        XCTAssertEqual(ExpansionArtCatalog.species,approved)
        XCTAssertEqual(approved.count,48)
        XCTAssertEqual(Set(approved).count,48)
        XCTAssertTrue(original.isDisjoint(with:Set(approved)))
        XCTAssertTrue(Set(e0).isDisjoint(with:Set(approved)))
        XCTAssertEqual(original.union(e0).union(approved),Set(SpeciesID.allCases))
        XCTAssertEqual(SpeciesBehaviorProfile.expansionPilotSpecies,e0)
        XCTAssertEqual(SpeciesBehaviorProfile.expansionPoseSpecies,e0+approved)
        XCTAssertEqual(approved.reduce(0){$0+ExpansionArtCatalog.appendedFrameNames(for:$1).count},672)
        XCTAssertEqual(ExpansionPilotArtGeometry.species.reduce(0){$0+ExpansionPilotArtGeometry.frameNames(for:$1).count},84)
    }

    func testNewGeometryOwnsOnlyFourteenAppendedFramesAndKeepsContactGeometrySeparate() throws {
        for species in ExpansionCompletionFixture.newSpecies {
            let names=ExpansionArtCatalog.appendedFrameNames(for:species)
            XCTAssertEqual(names.count,14)
            XCTAssertEqual(Set(names).count,14)
            XCTAssertEqual(Array(names.prefix(10)),PoseClip.frameNames)
            XCTAssertEqual(Array(names.suffix(4)),LivelyMotion.frameNames(for:species))
            for frame in names {
                let anchor=try XCTUnwrap(ExpansionArtCatalog.beakAnchor(species:species,frame:frame))
                XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite)
                XCTAssertTrue((0..<48).contains(anchor.x) && (0..<48).contains(anchor.y),"\(species)/\(frame): \(anchor)")
                XCTAssertEqual(PoseClip.beakAnchor(species:species,frame:frame),anchor)
            }
            for frame in ["stand","idle0","preen0","fly1","land1","catchOpen","carryGrip","courtRaise","nestPlace"] {
                XCTAssertNil(ExpansionArtCatalog.beakAnchor(species:species,frame:frame))
            }
            let previous=SpeciesBehavior.motion(species),current=LivelyMotion.window(species)
            XCTAssertEqual(previous.cycle,current.cycle)
            XCTAssertEqual(previous.start,current.start)
            XCTAssertEqual(previous.duration,current.duration)
            XCTAssertFalse(LivelyMotion.isSideMotion(species))
        }
        for species in SpeciesBehaviorProfile.legacySpecies+SpeciesBehaviorProfile.expansionPilotSpecies {
            XCTAssertTrue(ExpansionArtCatalog.appendedFrameNames(for:species).isEmpty)
        }
    }
}
