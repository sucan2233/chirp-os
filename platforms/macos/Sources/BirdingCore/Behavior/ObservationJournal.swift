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
    public fileprivate(set) var firstSeen:Date
    public fileprivate(set) var lastSeen:Date
    public fileprivate(set) var automaticCount:Int
    public fileprivate(set) var previewCount:Int
    public fileprivate(set) var userCount:Int
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

    fileprivate func validate() throws {
        guard let kind=BehaviorKind(rawValue:behavior),kind != .relocate,
              ObservationArchive.validDate(firstSeen),ObservationArchive.validDate(lastSeen),firstSeen<=lastSeen,
              [automaticCount,previewCount,userCount].allSatisfy({(0...ObservationArchive.maximumCount).contains($0)}),
              totalCount>0 else {throw ObservationJournalError.invalid("invalid entry behavior, dates or counts")}
    }
}

/// Aggregates only; neither desktop inputs nor individual run history is saved.
/// Codable dates use Foundation's numeric seconds since its reference date.
public struct ObservationArchive:Codable,Equatable {
    public static let currentVersion=1
    public static let maximumEntries=2048
    public static let maximumBytes=2*1024*1024
    public static let maximumCount=1_000_000
    /// End of year 9999 in Unix seconds, independent of wall-clock time.
    public static let maximumTimestamp:Double=253_402_300_799
    public let formatVersion:Int
    public fileprivate(set) var entries:[ObservationEntry]

    public init(entries:[ObservationEntry]=[]) {formatVersion=Self.currentVersion;self.entries=entries}
    private enum CodingKeys:String,CodingKey {case formatVersion,entries}
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        formatVersion=try values.decode(Int.self,forKey:.formatVersion)
        // Reject a future envelope before interpreting its nested payload.
        guard formatVersion==Self.currentVersion else {throw ObservationJournalError.invalid("unsupported version \(formatVersion)")}
        var nested=try values.nestedUnkeyedContainer(forKey:.entries)
        var decoded:[ObservationEntry]=[]
        while !nested.isAtEnd {
            guard decoded.count<Self.maximumEntries else {throw ObservationJournalError.invalid("too many entries")}
            decoded.append(try nested.decode(ObservationEntry.self))
        }
        entries=decoded
        try validate()
    }
    fileprivate static func validDate(_ date:Date)->Bool {
        let seconds=date.timeIntervalSince1970
        return seconds.isFinite && (0...maximumTimestamp).contains(seconds)
    }
    public func validate() throws {
        guard formatVersion==Self.currentVersion,entries.count<=Self.maximumEntries else {
            throw ObservationJournalError.invalid("unsupported version or too many entries")
        }
        var keys=Set<String>()
        for entry in entries {
            try entry.validate()
            guard keys.insert(entry.species.rawValue+":"+entry.behavior).inserted else {
                throw ObservationJournalError.invalid("duplicate species and behavior")
            }
        }
    }
    public static func decode(_ data:Data) throws -> Self {
        guard data.count<=maximumBytes else {throw ObservationJournalError.invalid("file exceeds 2 MiB")}
        do {return try JSONDecoder().decode(Self.self,from:data)}
        catch let error as ObservationJournalError {throw error}
        catch {throw ObservationJournalError.invalid("malformed archive: \(error.localizedDescription)")}
    }
    public static func load(from url:URL) throws -> Self {
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size<=maximumBytes else {throw ObservationJournalError.invalid("file exceeds 2 MiB")}
        let handle=try FileHandle(forReadingFrom:url)
        defer {try? handle.close()}
        var data=Data()
        while let chunk=try handle.read(upToCount:maximumBytes+1-data.count),!chunk.isEmpty {
            data.append(chunk)
            guard data.count<=maximumBytes else {throw ObservationJournalError.invalid("file exceeds 2 MiB")}
        }
        return try decode(data)
    }
    public func save(to url:URL) throws {
        try validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(self)
        guard data.count<=Self.maximumBytes else {throw ObservationJournalError.invalid("file exceeds 2 MiB")}
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
    public private(set) var revision:UInt64=0
    public init() {}
    public var archive:ObservationArchive {stored}

    public func restore(_ archive:ObservationArchive) throws {
        guard lastSequence==nil else {throw ObservationJournalError.invalid("cannot restore after observing a session")}
        try archive.validate()
        var value=archive;value.entries.sort(by:Self.ordered)
        if stored != value {stored=value;bumpRevision()}
        lastSequence=nil
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
        guard observation.sequence>0,lastSequence.map({observation.sequence>$0}) ?? true,
              observation.runID>0,observation.kind != .relocate,
              observation.simulationTime.isFinite,observation.simulationTime>=0,
              ObservationArchive.validDate(date),!observation.species.isEmpty else {return false}
        lastSequence=observation.sequence
        var changed=false
        for species in Set(observation.species).sorted(by:{$0.rawValue<$1.rawValue}) {
            let behavior=observation.kind.rawValue
            let index:Int
            if let existing=stored.entries.firstIndex(where:{$0.species==species && $0.behavior==behavior}) {index=existing}
            else {
                guard stored.entries.count<ObservationArchive.maximumEntries else {continue}
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
            changed = changed || previous != stored.entries[index]
        }
        if changed {stored.entries.sort(by:Self.ordered);bumpRevision()}
        return changed
    }
}
