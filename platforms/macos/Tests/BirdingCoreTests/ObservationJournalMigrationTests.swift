import XCTest
@testable import BirdingCore

final class ObservationJournalMigrationTests:XCTestCase {
    // A literal archive from the v1 vocabulary, independent of current encoders.
    private let versionOne=Data(#"{"formatVersion":1,"entries":[{"species":"treeSparrow","behavior":"rest","firstSeen":811692800,"lastSeen":811692900,"automaticCount":2,"previewCount":3,"userCount":4},{"species":"spottedDove","behavior":"foodTrayVisit","firstSeen":811692800,"lastSeen":811692900,"automaticCount":1,"previewCount":0,"userCount":0}]}"#.utf8)

    func testVersionOneMigratesLosslesslyToVersionThreeAndWritesEvenWithoutNewObservations() throws {
        XCTAssertEqual(ObservationArchive.currentVersion,3)
        let migrated=try ObservationArchive.decode(versionOne)
        XCTAssertEqual(migrated.formatVersion,3);XCTAssertTrue(migrated.requiresMigration)
        XCTAssertEqual(migrated.entries.map(\.behavior),["rest","foodTrayVisit"])
        let sparrow=try XCTUnwrap(migrated.entries.first)
        XCTAssertEqual(sparrow.firstSeen,Date(timeIntervalSinceReferenceDate:811692800))
        XCTAssertEqual(sparrow.lastSeen,Date(timeIntervalSinceReferenceDate:811692900))
        XCTAssertEqual(sparrow.automaticCount,2);XCTAssertEqual(sparrow.previewCount,3)
        XCTAssertEqual(sparrow.userCount,4);XCTAssertEqual(sparrow.totalCount,9)
        XCTAssertEqual(migrated.migration.convertedVersions,[1])
        XCTAssertTrue(migrated.writerProgress.isEmpty)
        let discovery=try XCTUnwrap(migrated.speciesRecord(for:.treeSparrow))
        XCTAssertEqual(discovery.discoverySources,[.historicalBehavior])
        XCTAssertEqual(discovery.historicalFirstSeen,sparrow.firstSeen)
        XCTAssertEqual(discovery.manualCount,0)
        XCTAssertNil(discovery.firstDiscoveredAt);XCTAssertNil(discovery.lastDiscoveredAt)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("observations.json")
        try versionOne.write(to:file)
        let loaded=try ObservationArchive.load(from:file)
        XCTAssertEqual(try Data(contentsOf:file),versionOne,"Reading alone must not overwrite the source")
        try loaded.save(to:file)
        let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
        XCTAssertEqual(raw["formatVersion"] as? Int,3);XCTAssertNil(raw["requiresMigration"])
        XCTAssertEqual(raw["behaviorEntries"] as? NSArray,raw["entries"] as? NSArray)
        XCTAssertNotNil(raw["speciesRecords"]);XCTAssertNotNil(raw["migration"]);XCTAssertNotNil(raw["writerProgress"])
        let current=try ObservationArchive.load(from:file)
        XCTAssertFalse(current.requiresMigration);XCTAssertEqual(current,migrated)
        XCTAssertEqual(current.entries,migrated.entries)
        let journal=ObservationJournal();try journal.restore(current)
        XCTAssertEqual(journal.archive.entries.count,2)
        try journal.archive.save(to:file)
        XCTAssertFalse(try ObservationArchive.load(from:file).requiresMigration)
    }

    func testVersionTwoMigrationPreservesPreviewHistoryWithoutDiscoveringItsSpecies() throws {
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:versionOne) as? [String:Any])
        raw["formatVersion"]=2
        var entries=try XCTUnwrap(raw["entries"] as? [[String:Any]])
        entries[0]["automaticCount"]=0;entries[0]["userCount"]=0
        raw["entries"]=entries
        let migrated=try ObservationArchive.decode(JSONSerialization.data(withJSONObject:raw))
        XCTAssertEqual(migrated.formatVersion,3);XCTAssertTrue(migrated.requiresMigration)
        XCTAssertEqual(migrated.migration.convertedVersions,[2])
        XCTAssertEqual(migrated.entries.first?.previewCount,3)
        XCTAssertEqual(migrated.entries.first?.firstSeen,Date(timeIntervalSinceReferenceDate:811692800))
        XCTAssertEqual(migrated.entries.first?.lastSeen,Date(timeIntervalSinceReferenceDate:811692900))
        XCTAssertFalse(migrated.isDiscovered(.treeSparrow))
        XCTAssertTrue(migrated.isDiscovered(.spottedDove))
        XCTAssertTrue(migrated.speciesRecords.allSatisfy{$0.manualCount==0 && $0.firstDiscoveredAt==nil})
        let current=try ObservationArchive.decode(JSONEncoder().encode(migrated))
        XCTAssertEqual(current,migrated);XCTAssertFalse(current.requiresMigration)
        XCTAssertEqual(current.migration.convertedVersions,[2])
    }

    func testVersionOneCannotClaimNewContactEntriesAndVersionTwoRetainsStrictEntryValidation() throws {
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:versionOne) as? [String:Any])
        var entries=try XCTUnwrap(raw["entries"] as? [[String:Any]])
        for behavior in ["bathVisit","leafCarry","insectCatch"] {
            entries[0]["behavior"]=behavior;raw["entries"]=entries;raw["formatVersion"]=1
            XCTAssertThrowsError(try ObservationArchive.decode(JSONSerialization.data(withJSONObject:raw)))
            raw["formatVersion"]=2
            let current=try ObservationArchive.decode(JSONSerialization.data(withJSONObject:raw))
            XCTAssertEqual(current.entries.first?.behavior,behavior);XCTAssertTrue(current.requiresMigration)
            XCTAssertEqual(current.formatVersion,3);XCTAssertEqual(current.migration.convertedVersions,[2])
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
            let bytes=try JSONSerialization.data(withJSONObject:["formatVersion":4,"behaviorEntries":entries])
            try bytes.write(to:file)
            XCTAssertThrowsError(try ObservationArchive.decode(bytes)) {error in
                XCTAssertTrue(error.localizedDescription.contains("unsupported version 4"))
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
        XCTAssertEqual(Set(raw.keys),["formatVersion","behaviorEntries","entries","speciesRecords","migration","writerProgress"])
        XCTAssertEqual(raw["behaviorEntries"] as? NSArray,raw["entries"] as? NSArray)
        XCTAssertTrue(journal.archive.writerProgress.isEmpty)
        XCTAssertTrue(journal.archive.migration.convertedVersions.isEmpty)
        let discovery=try XCTUnwrap(journal.speciesRecord(for:.treeSparrow))
        XCTAssertEqual(discovery.manualCount,0)
        XCTAssertEqual(Set(discovery.discoverySources),[.automatic,.user])
        XCTAssertEqual(discovery.firstDiscoveredAt,date);XCTAssertEqual(discovery.lastDiscoveredAt,date)
        XCTAssertEqual(try ObservationArchive.decode(bytes),journal.archive)
    }
}
