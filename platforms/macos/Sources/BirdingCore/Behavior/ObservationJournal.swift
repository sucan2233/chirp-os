import Foundation

/// A completed run's value output, independent of recording and persistence.
public struct BehaviorObservation:Equatable {
    public let sequence:UInt64
    public let simulationTime:Double
    public let kind:BehaviorKind
    public let source:BehaviorSource
    public let species:[SpeciesID]
    public let runID:UInt64

    public init(sequence:UInt64,simulationTime:Double,kind:BehaviorKind,source:BehaviorSource,
                species:[SpeciesID],runID:UInt64) {
        self.sequence=sequence;self.simulationTime=simulationTime;self.kind=kind
        self.source=source;self.species=species;self.runID=runID
    }
}

public enum ObservationJournalError:Error,LocalizedError {
    case invalid(String)
    public var errorDescription:String? {
        if case let .invalid(reason)=self {return "Invalid observation journal: \(reason)"}
        return nil
    }
}

public struct ObservationEntry:Codable,Equatable {
    public let species:SpeciesID
    public let behavior:String
    public internal(set) var firstSeen:Date
    public internal(set) var lastSeen:Date
    public internal(set) var automaticCount:Int
    public internal(set) var previewCount:Int
    public internal(set) var userCount:Int
    public var totalCount:Int {
        // Even an invalid, directly constructed entry must not trap its reader.
        [automaticCount,previewCount,userCount].reduce(0) { total,count in
            let (sum,overflow)=total.addingReportingOverflow(max(0,count))
            return overflow ? Int.max:sum
        }
    }

    public init(species:SpeciesID,behavior:String,firstSeen:Date,lastSeen:Date,
                automaticCount:Int=0,previewCount:Int=0,userCount:Int=0) {
        self.species=species;self.behavior=behavior;self.firstSeen=firstSeen;self.lastSeen=lastSeen
        self.automaticCount=automaticCount;self.previewCount=previewCount;self.userCount=userCount
    }

    func validate() throws {
        guard !behavior.isEmpty,behavior.utf8.count<=128,behavior != BehaviorKind.relocate.rawValue,
              behavior.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0) || $0 == "_"}),
              ObservationArchive.validDate(firstSeen),ObservationArchive.validDate(lastSeen),firstSeen<=lastSeen,
              [automaticCount,previewCount,userCount].allSatisfy({(0...ObservationArchive.maximumCount).contains($0)}),
              totalCount>0 else {throw ObservationJournalError.invalid("invalid entry behavior, dates or counts")}
    }
}

/// Aggregates only; neither desktop inputs nor individual run history is saved.
/// Codable dates use Foundation's numeric seconds since its reference date.
public struct ObservationArchive:Codable,Equatable {
    public static let currentVersion=3
    public static let maximumEntries=4096
    public static let maximumBytes=4*1024*1024
    public static let maximumCount=1_000_000
    /// End of year 9999 in Unix seconds, independent of wall-clock time.
    public static let maximumTimestamp:Double=253_402_300_799
    public let formatVersion:Int
    public internal(set) var entries:[ObservationEntry]
    public static let maximumWriters=64
    public var behaviorEntries:[ObservationEntry] {entries}
    public func speciesRecord(for species:SpeciesID)->ObservationSpeciesRecord? {speciesRecords.first{$0.species==species}}
    public func isDiscovered(_ species:SpeciesID)->Bool {speciesRecord(for:species) != nil}
    public internal(set) var speciesRecords:[ObservationSpeciesRecord]
    public internal(set) var migration:ObservationMigration
    public internal(set) var writerProgress:[ObservationWriterProgress]
    /// Decode provenance only; never encoded or included in aggregate equality.
    /// Persistence must still write a migrated archive with no new observations.
    public let requiresMigration:Bool

    // Freeze the v1 vocabulary: adding a BehaviorKind must not retroactively
    // make a v1-tagged archive containing new behavior IDs a valid old archive.
    private static let versionOneBehaviors:Set<String> = [
        "pointerVisit","flockPass","rest","preen","socialGreeting","sideBySide","giveWay",
        "pairedTakeoff","leafPlay","watch","alert","sideHop","takeoffPreparation","edgePeek",
        "chase","travelTogether","allopreening","fixedPerchVisit","foodTrayVisit"
    ]

    public init(entries:[ObservationEntry]=[],speciesRecords:[ObservationSpeciesRecord]?=nil,
                migration:ObservationMigration=ObservationMigration(),writerProgress:[ObservationWriterProgress]=[]) {
        formatVersion=Self.currentVersion;self.entries=entries;requiresMigration=false
        self.speciesRecords=speciesRecords ?? Self.historicalRecords(entries)
        self.migration=migration;self.writerProgress=writerProgress
    }
    // Writer acknowledgments are storage metadata, not observed aggregates.
    public static func == (lhs:Self,rhs:Self)->Bool {
        lhs.formatVersion==rhs.formatVersion && lhs.entries==rhs.entries &&
            lhs.speciesRecords==rhs.speciesRecords && lhs.migration==rhs.migration
    }
    private enum CodingKeys:String,CodingKey {case formatVersion,entries,behaviorEntries,speciesRecords,migration,writerProgress}
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        let sourceVersion=try values.decode(Int.self,forKey:.formatVersion)
        guard (1...Self.currentVersion).contains(sourceVersion) else {
            throw ObservationJournalError.invalid("unsupported version \(sourceVersion)")
        }
        formatVersion=Self.currentVersion;requiresMigration=sourceVersion != Self.currentVersion
        let key:CodingKeys=sourceVersion==3 ? .behaviorEntries:.entries
        var nested=try values.nestedUnkeyedContainer(forKey:key)
        var decoded:[ObservationEntry]=[]
        while !nested.isAtEnd {
            guard decoded.count<Self.maximumEntries else {throw ObservationJournalError.invalid("too many entries")}
            decoded.append(try nested.decode(ObservationEntry.self))
        }
        entries=decoded
        if sourceVersion==3 {
            speciesRecords=try values.decode([ObservationSpeciesRecord].self,forKey:.speciesRecords)
            migration=try values.decode(ObservationMigration.self,forKey:.migration)
            writerProgress=try values.decode([ObservationWriterProgress].self,forKey:.writerProgress)
            if values.contains(.entries),try values.decode([ObservationEntry].self,forKey:.entries) != entries {
                throw ObservationJournalError.invalid("inconsistent compatibility entries")
            }
        } else {
            guard entries.allSatisfy({BehaviorKind(rawValue:$0.behavior) != nil}) else {
                throw ObservationJournalError.invalid("unknown legacy behavior")
            }
            speciesRecords=Self.historicalRecords(entries);migration=ObservationMigration()
            migration.convertedVersions=[sourceVersion];writerProgress=[]
        }
        try validate()
        guard sourceVersion != 1 || entries.allSatisfy({Self.versionOneBehaviors.contains($0.behavior)}) else {
            throw ObservationJournalError.invalid("behavior not supported by archive version 1")
        }
    }
    public func encode(to encoder:Encoder) throws {
        var values=encoder.container(keyedBy:CodingKeys.self)
        try values.encode(formatVersion,forKey:.formatVersion)
        try values.encode(entries,forKey:.behaviorEntries)
        // Existing archive readers still consume this compatibility mirror.
        try values.encode(entries,forKey:.entries)
        try values.encode(speciesRecords,forKey:.speciesRecords)
        try values.encode(migration,forKey:.migration)
        try values.encode(writerProgress,forKey:.writerProgress)
    }
    private static func historicalRecords(_ entries:[ObservationEntry])->[ObservationSpeciesRecord] {
        var records:[SpeciesID:ObservationSpeciesRecord]=[:]
        for entry in entries where entry.automaticCount>0 || entry.userCount>0 {
            var record=records[entry.species] ?? ObservationSpeciesRecord(species:entry.species)
            record.discover(source:.historicalBehavior,at:nil)
            record.historicalFirstSeen=min(record.historicalFirstSeen ?? entry.firstSeen,entry.firstSeen)
            records[entry.species]=record
        }
        return records.values.sorted{$0.species.rawValue<$1.species.rawValue}
    }
    static func validDate(_ date:Date)->Bool {
        let seconds=date.timeIntervalSince1970
        return seconds.isFinite && (0...maximumTimestamp).contains(seconds)
    }
    public func validate() throws {
        guard formatVersion==Self.currentVersion,entries.count<=Self.maximumEntries else {
            throw ObservationJournalError.invalid("unsupported version or too many entries")
        }
        guard speciesRecords.count<=SpeciesID.allCases.count,writerProgress.count<=Self.maximumWriters,
              Set(speciesRecords.map(\.species)).count==speciesRecords.count,
              Set(writerProgress.map(\.writerID)).count==writerProgress.count,
              Set(writerProgress.map(\.slot)).count==writerProgress.count,
              writerProgress.allSatisfy({(0..<Self.maximumWriters).contains($0.slot) && $0.sequence>0}),
              Set(migration.convertedVersions).count==migration.convertedVersions.count,
              migration.convertedVersions.allSatisfy({$0==1 || $0==2}) else {
            throw ObservationJournalError.invalid("invalid species, migration or writer ledger")
        }
        if let imported=migration.lifeList {
            guard imported.sourceSlot=="upstream-life-list",imported.fingerprint.count==64,
                  imported.fingerprint.allSatisfy({$0.isHexDigit}) else {
                throw ObservationJournalError.invalid("invalid Life List import marker")
            }
        }
        for record in speciesRecords {try record.validate()}
        var keys=Set<String>()
        for entry in entries {
            try entry.validate()
            guard keys.insert(entry.species.rawValue+":"+entry.behavior).inserted else {
                throw ObservationJournalError.invalid("duplicate species and behavior")
            }
        }
    }
    public static func decode(_ data:Data) throws -> Self {
        guard data.count<=maximumBytes else {throw ObservationJournalError.invalid("file exceeds 4 MiB")}
        do {return try JSONDecoder().decode(Self.self,from:data)}
        catch let error as ObservationJournalError {throw error}
        catch {throw ObservationJournalError.invalid("malformed archive: \(error.localizedDescription)")}
    }
    public static func load(from url:URL) throws -> Self {
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size<=maximumBytes else {throw ObservationJournalError.invalid("file exceeds 4 MiB")}
        let handle=try FileHandle(forReadingFrom:url)
        defer {try? handle.close()}
        var data=Data()
        while let chunk=try handle.read(upToCount:maximumBytes+1-data.count),!chunk.isEmpty {
            data.append(chunk)
            guard data.count<=maximumBytes else {throw ObservationJournalError.invalid("file exceeds 4 MiB")}
        }
        return try decode(data)
    }
    public func save(to url:URL) throws {
        try validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(self)
        guard data.count<=Self.maximumBytes else {throw ObservationJournalError.invalid("file exceeds 4 MiB")}
        let files=FileManager.default
        let exists:Bool
        do {_=try files.attributesOfItem(atPath:url.path);exists=true}
        catch {
            let failure=error as NSError
            guard failure.domain==NSCocoaErrorDomain,
                  [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(failure.code) else {throw error}
            exists=false
        }
        // An unreadable, corrupt or future destination must survive unchanged.
        if exists {_=try Self.load(from:url)}
        try files.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
    }
}

/// Single-owner session consumer. Restoring does not touch a simulation engine.
public final class ObservationJournal {
    private var stored=ObservationArchive()
    private var lastSequence:UInt64?
    private var manualRecorded=false
    public private(set) var acceptingRecords=true
    /// Sticky session diagnostic: subsequent successful existing-entry updates
    /// must not hide a rejected completion. Restore clears it before observing.
    public private(set) var capacityExceeded=false
    public private(set) var lastIssue:String?
    public private(set) var revision:UInt64=0
    public init() {}
    public var archive:ObservationArchive {stored}

    public func restore(_ archive:ObservationArchive) throws {
        guard lastSequence==nil,!manualRecorded,acceptingRecords else {throw ObservationJournalError.invalid("cannot restore after observing a session")}
        try archive.validate()
        var value=archive;value.entries.sort(by:Self.ordered)
        if stored != value {stored=value;bumpRevision()}
        lastSequence=nil;capacityExceeded=false;lastIssue=nil
    }
    public func speciesRecord(for species:SpeciesID)->ObservationSpeciesRecord? {
        stored.speciesRecords.first{$0.species==species}
    }
    public func isDiscovered(_ species:SpeciesID)->Bool {speciesRecord(for:species) != nil}
    public var discoveredSpeciesCount:Int {stored.speciesRecords.count}
    public var manualRecordCount:Int {stored.speciesRecords.reduce(0){$0+$1.manualCount}}
    /// Caller owns visit identity and must commit that identity on true, before
    /// asynchronous persistence. Retrying a save never invokes this method.
    @discardableResult public func recordManual(species:SpeciesID,at date:Date)->Bool {
        guard acceptingRecords,ObservationArchive.validDate(date) else {return false}
        var record=speciesRecord(for:species) ?? ObservationSpeciesRecord(species:species)
        guard record.manualCount<ObservationArchive.maximumCount else {return false}
        record.manualCount+=1
        record.manualFirstRecordedAt=record.manualFirstRecordedAt ?? date
        record.manualLastRecordedAt=max(record.manualLastRecordedAt ?? record.manualFirstRecordedAt!,date)
        record.discover(source:.manual,at:date)
        manualRecorded=true
        if speciesRecord(for:species) != record {put(record);bumpRevision()}
        return true
    }
    public func stopAcceptingRecords() {acceptingRecords=false}
    private func put(_ record:ObservationSpeciesRecord) {
        stored.speciesRecords.removeAll{$0.species==record.species};stored.speciesRecords.append(record)
        stored.speciesRecords.sort{$0.species.rawValue<$1.species.rawValue}
    }
    private static func ordered(_ a:ObservationEntry,_ b:ObservationEntry)->Bool {
        a.species == b.species ? a.behavior<b.behavior:a.species.rawValue<b.species.rawValue
    }
    private func bumpRevision() {if revision<UInt64.max {revision+=1}}

    /// Returns true only when persisted aggregates changed. Invalid input and
    /// duplicate event sequences have no effect; a backward clock clamps lastSeen.
    /// Runtime guarantees one completion per run. Run IDs can finish in any order,
    /// so only the completion event sequence is used for session deduplication.
    @discardableResult public func observe(_ observation:BehaviorObservation,at date:Date)->Bool {
        guard acceptingRecords,observation.sequence>0,lastSequence.map({observation.sequence>$0}) ?? true,
              observation.runID>0,observation.kind != .relocate,
              observation.simulationTime.isFinite,observation.simulationTime>=0,
              ObservationArchive.validDate(date),!observation.species.isEmpty else {return false}
        let participants=Set(observation.species).sorted(by:{$0.rawValue<$1.rawValue})
        let existing=Set(stored.entries.filter{$0.behavior==observation.kind.rawValue}.map(\.species))
        let required=participants.filter{!existing.contains($0)}.count
        guard required<=ObservationArchive.maximumEntries-stored.entries.count else {
            capacityExceeded=true
            lastIssue="Behavior archive capacity exceeded; this completion was not recorded."
            return false
        }
        lastSequence=observation.sequence
        var changed=false
        for species in participants {
            let behavior=observation.kind.rawValue
            let index:Int
            if let existing=stored.entries.firstIndex(where:{$0.species==species && $0.behavior==behavior}) {index=existing}
            else {
                index=stored.entries.count
                stored.entries.append(ObservationEntry(species:species,behavior:behavior,firstSeen:date,lastSeen:date))
                changed=true
            }
            let previous=stored.entries[index]
            stored.entries[index].lastSeen=max(previous.lastSeen,date)
            switch observation.source {
            case .automatic:stored.entries[index].automaticCount=min(ObservationArchive.maximumCount,previous.automaticCount+1)
            case .preview:stored.entries[index].previewCount=min(ObservationArchive.maximumCount,previous.previewCount+1)
            case .user:stored.entries[index].userCount=min(ObservationArchive.maximumCount,previous.userCount+1)
            }
            let entryChanged=previous != stored.entries[index]
            if entryChanged,observation.source != .preview {
                var record=speciesRecord(for:species) ?? ObservationSpeciesRecord(species:species)
                record.discover(source:observation.source == .automatic ? .automatic:.user,at:date)
                put(record)
            }
            changed = changed || entryChanged
        }
        if changed {stored.entries.sort(by:Self.ordered);bumpRevision()}
        return changed
    }
}
