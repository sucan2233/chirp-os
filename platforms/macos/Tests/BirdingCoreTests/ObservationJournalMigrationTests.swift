import XCTest
@testable import BirdingCore

final class ObservationJournalMigrationTests:XCTestCase {
    // A literal archive from the v1 vocabulary, independent of current encoders.
    private let versionOne=Data(#"{"formatVersion":1,"entries":[{"species":"treeSparrow","behavior":"rest","firstSeen":811692800,"lastSeen":811692900,"automaticCount":2,"previewCount":3,"userCount":4},{"species":"spottedDove","behavior":"foodTrayVisit","firstSeen":811692800,"lastSeen":811692900,"automaticCount":1,"previewCount":0,"userCount":0}]}"#.utf8)

    func testVersionOneMigratesLosslesslyToVersionTwoAndWritesEvenWithoutNewObservations() throws {
        XCTAssertEqual(ObservationArchive.currentVersion,2)
        let migrated=try ObservationArchive.decode(versionOne)
        XCTAssertEqual(migrated.formatVersion,2);XCTAssertTrue(migrated.requiresMigration)
        XCTAssertEqual(migrated.entries.map(\.behavior),["rest","foodTrayVisit"])
        let sparrow=try XCTUnwrap(migrated.entries.first)
        XCTAssertEqual(sparrow.firstSeen,Date(timeIntervalSinceReferenceDate:811692800))
        XCTAssertEqual(sparrow.lastSeen,Date(timeIntervalSinceReferenceDate:811692900))
        XCTAssertEqual(sparrow.automaticCount,2);XCTAssertEqual(sparrow.previewCount,3)
        XCTAssertEqual(sparrow.userCount,4);XCTAssertEqual(sparrow.totalCount,9)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("observations.json")
        try versionOne.write(to:file)
        let loaded=try ObservationArchive.load(from:file)
        XCTAssertEqual(try Data(contentsOf:file),versionOne,"Reading alone must not overwrite the source")
        try loaded.save(to:file)
        let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
        XCTAssertEqual(raw["formatVersion"] as? Int,2);XCTAssertNil(raw["requiresMigration"])
        let current=try ObservationArchive.load(from:file)
        XCTAssertFalse(current.requiresMigration);XCTAssertEqual(current,migrated)
        XCTAssertEqual(current.entries,migrated.entries)
        let journal=ObservationJournal();try journal.restore(current)
        XCTAssertEqual(journal.archive.entries.count,2)
        try journal.archive.save(to:file)
        XCTAssertFalse(try ObservationArchive.load(from:file).requiresMigration)
    }

    func testVersionOneCannotClaimNewContactEntriesAndVersionTwoRetainsStrictEntryValidation() throws {
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:versionOne) as? [String:Any])
        var entries=try XCTUnwrap(raw["entries"] as? [[String:Any]])
        for behavior in ["bathVisit","leafCarry","insectCatch"] {
            entries[0]["behavior"]=behavior;raw["entries"]=entries;raw["formatVersion"]=1
            XCTAssertThrowsError(try ObservationArchive.decode(JSONSerialization.data(withJSONObject:raw)))
            raw["formatVersion"]=2
            let current=try ObservationArchive.decode(JSONSerialization.data(withJSONObject:raw))
            XCTAssertEqual(current.entries.first?.behavior,behavior);XCTAssertFalse(current.requiresMigration)
        }
        for behavior in ["unknownFutureBehavior","relocate"] {
            entries[0]["behavior"]=behavior;raw["entries"]=entries
            XCTAssertThrowsError(try ObservationArchive.decode(JSONSerialization.data(withJSONObject:raw)))
        }
    }

    func testFutureVersionIsRejectedBeforeEntriesAndCannotBeOverwrittenByFallbackOrMigratedData() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("observations.json")
        for entries:Any in [[],"future incompatible entries",[["behavior":"unknown"]]] {
            let bytes=try JSONSerialization.data(withJSONObject:["formatVersion":3,"entries":entries])
            try bytes.write(to:file)
            XCTAssertThrowsError(try ObservationArchive.decode(bytes)) {error in
                XCTAssertTrue(error.localizedDescription.contains("unsupported version 3"))
            }
            XCTAssertThrowsError(try ObservationArchive.load(from:file))
            XCTAssertThrowsError(try ObservationArchive().save(to:file))
            XCTAssertThrowsError(try ObservationArchive.decode(self.versionOne).save(to:file))
            XCTAssertEqual(try Data(contentsOf:file),bytes)
        }
    }

    func testBathCountsEachCompletedSourceOnceAndArchiveContainsNoRuntimeState() throws {
        let journal=ObservationJournal(),date=Date(timeIntervalSince1970:1_790_000_000)
        for (index,source) in [BehaviorSource.automatic,.preview,.user].enumerated() {
            let observation=BehaviorObservation(sequence:UInt64(index+1),simulationTime:20,kind:.bathVisit,
                source:source,species:[.treeSparrow,.treeSparrow],runID:UInt64(index+1))
            XCTAssertTrue(journal.observe(observation,at:date))
            XCTAssertFalse(journal.observe(observation,at:date))
        }
        let value=try XCTUnwrap(journal.archive.entries.first)
        XCTAssertEqual(value.behavior,"bathVisit");XCTAssertEqual(value.totalCount,3)
        XCTAssertEqual(value.automaticCount,1);XCTAssertEqual(value.previewCount,1);XCTAssertEqual(value.userCount,1)
        let bytes=try JSONEncoder().encode(journal.archive)
        let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        XCTAssertEqual(Set(raw.keys),["formatVersion","entries"])
        XCTAssertEqual(try ObservationArchive.decode(bytes),journal.archive)
    }
}
