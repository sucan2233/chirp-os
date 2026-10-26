import XCTest
@testable import BirdingCore

final class UnifiedObservationArchiveTests:XCTestCase {
    private let date=Date(timeIntervalSince1970:1_790_000_000)
    private func event(_ sequence:UInt64,source:BehaviorSource)->BehaviorObservation {
        BehaviorObservation(sequence:sequence,simulationTime:Double(sequence),kind:.rest,
                            source:source,species:[.treeSparrow],runID:sequence)
    }
    private func legacy(version:Int,previewOnly:Bool=false) throws -> Data {
        try JSONSerialization.data(withJSONObject:["formatVersion":version,"entries":[[
            "species":"treeSparrow","behavior":"rest","firstSeen":date.timeIntervalSinceReferenceDate,
            "lastSeen":date.addingTimeInterval(20).timeIntervalSinceReferenceDate,
            "automaticCount":previewOnly ? 0:2,"previewCount":3,"userCount":0]]])
    }
    private func lifeList(count:Int=4,enabled:Bool=true) throws -> Data {
        try JSONSerialization.data(withJSONObject:["enabled":enabled,"introductionVersion":1,"records":[
            "treeSparrow":["count":count,"firstRecordedAt":"2025-01-01T00:00:00Z"]]])
    }
    private func root() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("UnifiedJournal-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:url)}
        return url
    }
    private func writeStable(_ bytes:Data,to url:URL) throws {
        try bytes.write(to:url)
        try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSinceNow:-10)],ofItemAtPath:url.path)
    }
    func testManualAndPreviewAndBehaviorHaveIndependentCounts() throws {
        let journal=ObservationJournal()
        XCTAssertTrue(journal.observe(event(1,source:.preview),at:date))
        XCTAssertFalse(journal.archive.isDiscovered(.treeSparrow))
        XCTAssertEqual(journal.manualRecordCount,0)
        let revision=journal.revision
        XCTAssertTrue(journal.recordManual(species:.treeSparrow,at:date))
        XCTAssertEqual(journal.revision,revision+1)
        XCTAssertEqual(journal.manualRecordCount,1)
        XCTAssertEqual(journal.archive.entries.first?.totalCount,1)
        XCTAssertTrue(journal.observe(event(2,source:.automatic),at:date.addingTimeInterval(2)))
        XCTAssertFalse(journal.observe(event(2,source:.automatic),at:date.addingTimeInterval(3)))
        XCTAssertEqual(journal.manualRecordCount,1)
        XCTAssertEqual(journal.archive.behaviorEntries.first?.automaticCount,1)
        XCTAssertEqual(Set(journal.speciesRecord(for:.treeSparrow)!.discoverySources),[.manual,.automatic])
        journal.stopAcceptingRecords()
        XCTAssertFalse(journal.recordManual(species:.treeSparrow,at:date))
        XCTAssertFalse(journal.observe(event(3,source:.user),at:date))
        XCTAssertEqual(try ObservationArchive.decode(JSONEncoder().encode(journal.archive)),journal.archive)
    }
    func testV1AndV2KeepMixedDatesAndPreviewDoesNotUnlockDiscovery() throws {
        for version in [1,2] {
            let migrated=try ObservationArchive.decode(legacy(version:version))
            XCTAssertEqual(migrated.formatVersion,3);XCTAssertTrue(migrated.requiresMigration)
            XCTAssertEqual(migrated.entries.first?.automaticCount,2)
            XCTAssertEqual(migrated.speciesRecord(for:.treeSparrow)?.manualCount,0)
            XCTAssertEqual(migrated.speciesRecord(for:.treeSparrow)?.historicalFirstSeen,date)
            XCTAssertNil(migrated.speciesRecord(for:.treeSparrow)?.firstDiscoveredAt)
            XCTAssertEqual(migrated.migration.convertedVersions,[version])
            let preview=try ObservationArchive.decode(legacy(version:version,previewOnly:true))
            XCTAssertFalse(preview.isDiscovered(.treeSparrow));XCTAssertEqual(preview.entries.first?.previewCount,3)
        }
    }
    func testCompatibilityMirrorAndUnknownFutureBehaviorArePreserved() throws {
        let entry=ObservationEntry(species:.treeSparrow,behavior:"futureBehavior",firstSeen:date,lastSeen:date,automaticCount:1)
        let archive=ObservationArchive(entries:[entry])
        let encoded=try JSONEncoder().encode(archive)
        XCTAssertEqual(try ObservationArchive.decode(encoded).entries,[entry])
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        raw["entries"]=[]
        XCTAssertThrowsError(try ObservationArchive.decode(JSONSerialization.data(withJSONObject:raw)))
        raw["formatVersion"]=4
        XCTAssertThrowsError(try ObservationArchive.decode(JSONSerialization.data(withJSONObject:raw)))
    }
    func testLifeListImportPreservesMissingLastDateAndFixedSlotPreventsReimport() throws {
        let source=try ObservationLegacyLifeList.decode(lifeList())
        let archive=try ObservationArchive().importing(source,fingerprint:String(repeating:"a",count:64))
        let record=try XCTUnwrap(archive.speciesRecord(for:.treeSparrow))
        XCTAssertEqual(record.manualCount,4);XCTAssertNotNil(record.manualFirstRecordedAt)
        XCTAssertNil(record.manualLastRecordedAt);XCTAssertNil(record.lastDiscoveredAt)
        XCTAssertNotNil(record.firstDiscoveredAt);XCTAssertTrue(archive.entries.isEmpty)
        let again=try archive.importing(source,fingerprint:String(repeating:"b",count:64))
        XCTAssertEqual(archive,again)
        XCTAssertThrowsError(try ObservationLegacyLifeList.decode(Data(#"{"enabled":true,"future":1,"records":{}}"#.utf8)))
        XCTAssertThrowsError(try ObservationLegacyLifeList.decode(Data(#"{"enabled":true,"records":{"unknown":{"count":1,"firstRecordedAt":"2025-01-01T00:00:00Z"}}}"#.utf8)))
        XCTAssertThrowsError(try ObservationLegacyLifeList.decode(lifeList(count:ObservationArchive.maximumCount+1)))
    }
    func testMigrationBackupsBothSourcesAndCommitsMarkerAtomically() throws {
        let folder=try root(),url=folder.appendingPathComponent("observations.json"),source=folder.appendingPathComponent("life-list.json")
        let old=try legacy(version:2),life=try lifeList()
        try old.write(to:url);try writeStable(life,to:source)
        let store=ObservationArchiveStore(url:url)
        let result=try store.loadAndMigrate(lifeListURL:source)
        XCTAssertNil(result.importIssue);XCTAssertEqual(result.importedModePreference,true)
        XCTAssertEqual(result.archive.speciesRecord(for:.treeSparrow)?.manualCount,4)
        XCTAssertEqual(result.archive.entries.first?.automaticCount,2)
        XCTAssertFalse(result.archive.requiresMigration)
        let backups=try FileManager.default.contentsOfDirectory(at:store.backupsURL,includingPropertiesForKeys:nil)
        let bytes=try backups.map{try Data(contentsOf:$0)}
        XCTAssertTrue(bytes.contains(old));XCTAssertTrue(bytes.contains(life))
        XCTAssertEqual(try Data(contentsOf:source),life)
        try writeStable(try lifeList(count:9),to:source)
        let restarted=try ObservationArchiveStore(url:url).loadAndMigrate(lifeListURL:source)
        XCTAssertEqual(restarted.archive.speciesRecord(for:.treeSparrow)?.manualCount,4)
        XCTAssertEqual(restarted.archive,result.archive)
    }
    func testPendingSourceDoesNotBlockValidBehaviorArchiveOrWriteImportMarker() throws {
        let folder=try root(),url=folder.appendingPathComponent("observations.json"),source=folder.appendingPathComponent("life-list.json")
        try legacy(version:1).write(to:url);try writeStable(try lifeList(),to:source)
        let result=try ObservationArchiveStore(url:url).loadAndMigrate(lifeListURL:source,legacySourceInactive:false)
        XCTAssertNotNil(result.importIssue);XCTAssertNil(result.archive.migration.lifeList)
        XCTAssertEqual(result.archive.entries.first?.automaticCount,2)
        XCTAssertEqual(result.archive.speciesRecord(for:.treeSparrow)?.manualCount,0)
    }
    func testCorruptAndFutureArchiveSurviveLoadAndCommit() throws {
        let folder=try root(),url=folder.appendingPathComponent("observations.json")
        for bytes in [Data("broken".utf8),Data(#"{"formatVersion":4,"entries":[]}"#.utf8)] {
            try bytes.write(to:url)
            let store=ObservationArchiveStore(url:url)
            XCTAssertThrowsError(try store.loadAndMigrate())
            XCTAssertThrowsError(try store.commit(local:ObservationArchive(),baseline:ObservationArchive(),sequence:1))
            XCTAssertEqual(try Data(contentsOf:url),bytes)
        }
    }
    func testWriterRetryIsIdempotentAndConcurrentDeltasKeepAllSources() throws {
        let url=try root().appendingPathComponent("observations.json")
        let a=ObservationArchiveStore(url:url),b=ObservationArchiveStore(url:url)
        let ja=ObservationJournal(),jb=ObservationJournal(),empty=ObservationArchive()
        ja.recordManual(species:.treeSparrow,at:date)
        jb.observe(event(1,source:.automatic),at:date)
        let first=ja.archive
        _=try a.commit(local:first,baseline:empty,sequence:1)
        _=try b.commit(local:jb.archive,baseline:empty,sequence:1)
        let afterRetry=try a.commit(local:first,baseline:empty,sequence:1)
        XCTAssertEqual(afterRetry.speciesRecord(for:.treeSparrow)?.manualCount,1)
        XCTAssertEqual(afterRetry.entries.first?.automaticCount,1)
        ja.recordManual(species:.treeSparrow,at:date.addingTimeInterval(3))
        let final=try a.commit(local:ja.archive,baseline:first,sequence:2)
        XCTAssertEqual(final.speciesRecord(for:.treeSparrow)?.manualCount,2)
        XCTAssertEqual(final.entries.first?.automaticCount,1)
        XCTAssertEqual(final.writerProgress.count,2)
        XCTAssertThrowsError(try a.commit(local:ja.archive,baseline:first,sequence:4))
    }
    func testWriterCapacityCannotEvictActiveWriterAndReleasedSlotIsReusable() throws {
        let url=try root().appendingPathComponent("observations.json"),journal=ObservationJournal()
        journal.recordManual(species:.treeSparrow,at:date)
        var writers:[ObservationArchiveStore]=[]
        for _ in 0..<ObservationArchive.maximumWriters {
            let writer=ObservationArchiveStore(url:url)
            _=try writer.commit(local:journal.archive,baseline:ObservationArchive(),sequence:1)
            writers.append(writer)
        }
        let extra=ObservationArchiveStore(url:url)
        XCTAssertThrowsError(try extra.commit(local:journal.archive,baseline:ObservationArchive(),sequence:1))
        XCTAssertEqual(try ObservationArchive.load(from:url).speciesRecord(for:.treeSparrow)?.manualCount,64)
        writers.removeFirst()
        let recovered=try extra.commit(local:journal.archive,baseline:ObservationArchive(),sequence:1)
        XCTAssertEqual(recovered.writerProgress.count,64)
        XCTAssertEqual(recovered.speciesRecord(for:.treeSparrow)?.manualCount,65)
        withExtendedLifetime(writers) {}
    }
    func testCapacityRejectsWholeCompletionBeforeConsumingItsSequence() throws {
        let entries=(0..<(ObservationArchive.maximumEntries-1)).map { index in
            ObservationEntry(species:.treeSparrow,behavior:"future\(index)",firstSeen:date,lastSeen:date,previewCount:1)
        }
        let journal=ObservationJournal();try journal.restore(ObservationArchive(entries:entries))
        let before=journal.archive,revision=journal.revision
        let multi=BehaviorObservation(sequence:10,simulationTime:1,kind:.rest,source:.automatic,
                                      species:[.treeSparrow,.littleOwl,.treeSparrow],runID:1)
        XCTAssertFalse(journal.observe(multi,at:date))
        XCTAssertTrue(journal.capacityExceeded);XCTAssertNotNil(journal.lastIssue)
        XCTAssertEqual(journal.archive,before);XCTAssertEqual(journal.revision,revision)
        XCTAssertFalse(journal.isDiscovered(.treeSparrow));XCTAssertFalse(journal.isDiscovered(.littleOwl))
        // The rejected event did not consume sequence 10. A one-entry event
        // using that same sequence can still fill the final available slot.
        XCTAssertTrue(journal.observe(event(10,source:.automatic),at:date))
        XCTAssertEqual(journal.archive.entries.count,ObservationArchive.maximumEntries)
        XCTAssertEqual(journal.archive.entries.first{$0.behavior=="rest"}?.automaticCount,1)
        XCTAssertFalse(journal.observe(event(10,source:.automatic),at:date))
        let full=journal.archive
        let missing=BehaviorObservation(sequence:11,simulationTime:2,kind:.preen,source:.user,
                                        species:[.littleOwl],runID:2)
        XCTAssertFalse(journal.observe(missing,at:date));XCTAssertEqual(journal.archive,full)
        XCTAssertTrue(journal.observe(event(11,source:.automatic),at:date))
        XCTAssertEqual(journal.archive.entries.first{$0.behavior=="rest"}?.automaticCount,2)
        XCTAssertTrue(journal.capacityExceeded,"A later accepted event must not conceal the rejected completion")
        try journal.archive.validate()
    }

    func testExternalRemovalCannotResurrectStaleHistory() throws {
        let url=try root().appendingPathComponent("observations.json"),journal=ObservationJournal()
        journal.recordManual(species:.treeSparrow,at:date)
        let store=ObservationArchiveStore(url:url)
        _=try store.commit(local:journal.archive,baseline:ObservationArchive(),sequence:1)
        try FileManager.default.removeItem(at:url)
        XCTAssertThrowsError(try store.commit(local:journal.archive,baseline:journal.archive,sequence:2))
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
    }
}
