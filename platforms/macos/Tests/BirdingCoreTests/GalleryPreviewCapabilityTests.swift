import XCTest
@testable import BirdingCore

final class GalleryPreviewCapabilityTests: XCTestCase {
    func testPreviouslyHiddenExpansionIdleArtworkIsVisibleInOther() {
        // The original peck/bow/watch/scan regressions, excluding crestedMyna,
        // whose reviewed signature preview now takes priority (covered below).
        let species: [SpeciesID] = [
            .silkyStarling, .greatCrestedGrebe, .uplandBuzzard, .littleGrebe,
            .carrionCrow, .plainLaughingthrush, .orientalTurtleDove,
            .rufousBreastedAccentor, .eurasianCollaredDove, .whiteCheekedStarling,
            .henricsLaughingthrush, .commonPheasant, .whiteBrowedLaughingthrush,
            .hornedLark, .redThroatedThrush, .daurianJackdaw,
            .himalayanVulture, .blackTailedGull
        ]
        for id in species {
            let frames = Set((0..<300).map {
                GalleryPose.frame(id, age: Double($0) / 30, fps: 20, action: .other)
            })
            XCTAssertEqual(frames, Set(["idle0", "idle1", "idle2"]), id.rawValue)
        }
    }

    func testOtherReusesSignatureClipsForGroundPilots() throws {
        let species: [SpeciesID] = [
            .greatTit, .orientalMagpie, .magpieRobin, .littleEgret, .mallard,
            .eurasianGreatTit, .whiteWagtail, .indianWhiteEye, .crestedMyna, .greatEgret
        ]
        for id in species {
            var frames = Set<String>()
            for step in 0..<600 {
                let age = Double(step) / 30
                let signature = try XCTUnwrap(LivelyMotion.previewFrame(species: id, age: age), id.rawValue)
                let actual = GalleryPose.frame(id, age: age, fps: 20, action: .other)
                XCTAssertEqual(actual, signature, "\(id.rawValue) at \(age)")
                frames.insert(actual)
            }
            XCTAssertGreaterThan(frames.count, 1, "\(id.rawValue) must animate")
        }
    }

    func testSidePreviewsPreferSignatureAndRetainExistingSideFallback() {
        for id in [SpeciesID.eurasianNuthatch, .greatSpottedWoodpecker] {
            var frames = Set<String>()
            for step in 0..<240 {
                let age = Double(step) / 30
                let actual = GalleryPose.frame(id, age: age, fps: 24, action: .other)
                if let signature = LivelyMotion.previewFrame(species: id, age: age) {
                    XCTAssertEqual(actual, signature)
                } else {
                    XCTAssertTrue(["cling0", "peck0", "peck1"].contains(actual), id.rawValue)
                }
                frames.insert(actual)
            }
            XCTAssertGreaterThan(frames.count, 1, id.rawValue)
        }
    }

    func testSelectingOtherPreservesLegacyNonPilotAndRestSelection() {
        for step in 0..<300 {
            let age = Double(step) / 30
            XCTAssertEqual(GalleryPose.frame(.blackKite, age: age, fps: 20, action: .other),
                           GalleryPose.frame(.blackKite, age: age, fps: 20, action: .resting))
            for id in [SpeciesID.crestedMyna, .silkyStarling, .greatCrestedGrebe, .eurasianNuthatch] {
                XCTAssertTrue(["stand", "breathe", "blink"].contains(
                    GalleryPose.frame(id, age: age, fps: 20, action: .resting)), id.rawValue)
            }
        }
        XCTAssertEqual(GalleryPose.frame(.silkyStarling, age: -1, fps: 20, action: .other), "idle0")
    }
}
