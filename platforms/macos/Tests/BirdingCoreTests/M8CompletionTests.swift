import XCTest
@testable import BirdingCore

final class M8CompletionTests: XCTestCase {
    func testOriginalM8CohortRemainsCompleteAfterExpansionDelivery() {
        let original=Set(SpeciesCatalog.standard.species.prefix(46).map(\.id))
        let expansion:Set<SpeciesID>=[.eurasianGreatTit,.whiteWagtail,.indianWhiteEye,.crestedMyna,.eurasianNuthatch,.greatEgret]
        XCTAssertTrue(original.union(expansion).isSubset(of:Set(LivelyMotion.species)))
        XCTAssertTrue(original.union(expansion).isSubset(of:Set(SpeciesBehaviorProfile.poseSpecies)))
        XCTAssertEqual(Set(M8ArtCatalog.species).count,40)
        XCTAssertEqual(M8ArtCatalog.species.reduce(0){$0+M8ArtCatalog.appendedFrameNames(for:$1).count},450)
        for species in original {
            XCTAssertEqual(SpeciesBehaviorProfile.profile(for:species).poseFrameNames.count,10)
            XCTAssertEqual(LivelyMotion.frameNames(for:species).count,4)
        }

    }

    func testNewAnchorsAreFiniteAndInsideCanvasWithoutClaimingOldContactFrames() throws {
        let historical=["stand","idle0","preen0","fly1","land1","catchOpen","carryGrip","courtRaise","nestPlace"]
        for species in M8ArtCatalog.species {
            for frame in historical {XCTAssertNil(M8ArtCatalog.beakAnchor(species:species,frame:frame),"\(species)/\(frame)")}
            for frame in M8ArtCatalog.appendedFrameNames(for:species) {
                let anchor=try XCTUnwrap(M8ArtCatalog.beakAnchor(species:species,frame:frame))
                XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite)
                XCTAssertTrue((0..<48).contains(anchor.x) && (0..<48).contains(anchor.y),"\(species)/\(frame): \(anchor)")
                XCTAssertEqual(PoseClip.beakAnchor(species:species,frame:frame),anchor)
            }
        }
    }

    func testLongPauseSpeciesKeepTheirExistingOpportunityAndSideClipsStayRestricted() {
        for species in M8ArtCatalog.species {
            let old=SpeciesBehavior.motion(species),new=LivelyMotion.window(species)
            XCTAssertEqual(new.cycle,old.cycle)
            XCTAssertEqual(new.start,old.start)
            XCTAssertEqual(new.duration,old.duration)
            XCTAssertFalse(LivelyMotion.isSideMotion(species))
        }
        XCTAssertEqual(LivelyMotion.window(.nightHeron).cycle,53)
        XCTAssertEqual(LivelyMotion.window(.nightHeron).start,20)
        XCTAssertEqual(LivelyMotion.window(.commonBuzzard).cycle,27)
        XCTAssertEqual(Set(LivelyMotion.species.filter{LivelyMotion.isSideMotion($0)}),[.greatSpottedWoodpecker,.eurasianNuthatch])
    }
}
