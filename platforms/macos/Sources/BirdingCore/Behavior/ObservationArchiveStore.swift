import Foundation
import CryptoKit
import Darwin

public enum ObservationStoreError:Error,LocalizedError {
    case writerCapacity,retiredWriter,sequenceMismatch,archiveRemoved,legacyPending(String)
    public var errorDescription:String? {
        switch self {
        case .writerCapacity:return "All 64 observation writer slots are active; this session is read-only."
        case .retiredWriter:return "This observation writer is no longer registered; its pending data was not replayed."
        case .sequenceMismatch:return "Observation commit sequence is not the next acknowledged sequence."
        case .archiveRemoved:return "The observation archive disappeared after loading; it has not been recreated."
        case let .legacyPending(reason):return "Life List import pending: \(reason)"
        }
    }
}

public struct ObservationStoreLoad {
    public let archive:ObservationArchive
    public let importIssue:String?
    public var importedModePreference:Bool? {archive.migration.lifeList?.enabled}
}

/// Use from one serial executor. Each object owns a fresh writer UUID and holds
/// its slot flock until deinit. Never resurrect a writer UUID in another object.
/// A released slot proves that writer cannot retry: no wall-clock expiry exists.
/// Slot files are fixed (0..<64), never unlinked, so lock identity stays stable.
public final class ObservationArchiveStore {
    public let url:URL
    public let writerID=UUID()
    private var slot:Int?
    private var lease:Int32 = -1
    private var committedSequence:UInt64=0
    private var expectsArchive=false
    public init(url:URL) {self.url=url}
    deinit {if lease>=0 {Darwin.close(lease)}}
    public var lockURL:URL {URL(fileURLWithPath:url.path+".lock")}
    public var writersURL:URL {URL(fileURLWithPath:url.path+".writers",isDirectory:true)}
    public var backupsURL:URL {URL(fileURLWithPath:url.path+".backups",isDirectory:true)}

    public static func fingerprint(_ data:Data)->String {
        SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    private static func missing(_ error:Error)->Bool {
        let error=error as NSError
        return error.domain==NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(error.code)
    }
    public static func readBounded(_ url:URL) throws -> Data {
        let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max)<=ObservationArchive.maximumBytes else {
            throw ObservationJournalError.invalid("archive is not a bounded regular file")
        }
        let handle=try FileHandle(forReadingFrom:url);defer {try? handle.close()}
        var bytes=Data()
        while let part=try handle.read(upToCount:ObservationArchive.maximumBytes+1-bytes.count),!part.isEmpty {
            bytes.append(part)
            guard bytes.count<=ObservationArchive.maximumBytes else {throw ObservationJournalError.invalid("file exceeds 4 MiB")}
        }
        return bytes
    }
    private func readOptional() throws -> (ObservationArchive,Data)? {
        do {
            let bytes=try Self.readBounded(url)
            return (try ObservationArchive.decode(bytes),bytes)
        } catch {if Self.missing(error) {return nil};throw error}
    }
    private func lock(wait:Double) throws -> Int32 {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let fd=Darwin.open(lockURL.path,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,mode_t(0o600))
        guard fd>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        let deadline=ProcessInfo.processInfo.systemUptime+max(0,wait)
        while flock(fd,LOCK_EX|LOCK_NB) != 0 {
            let code=errno
            guard (code==EWOULDBLOCK || code==EAGAIN),ProcessInfo.processInfo.systemUptime<deadline else {
                Darwin.close(fd);throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))
            }
            Thread.sleep(forTimeInterval:0.01)
        }
        return fd
    }
    /// Content-addressed byte backups never overwrite an earlier source. Their
    /// directory follows the archive path, including isolated verification paths.
    @discardableResult private func backup(_ bytes:Data,name:String) throws -> URL {
        try FileManager.default.createDirectory(at:backupsURL,withIntermediateDirectories:true)
        let target=backupsURL.appendingPathComponent(name+"-"+Self.fingerprint(bytes)+".json")
        do {try bytes.write(to:target,options:.withoutOverwriting)}
        catch {
            guard let existing=try? Self.readBounded(target),existing==bytes else {throw error}
        }
        let handle=try FileHandle(forWritingTo:target);defer {try? handle.close()}
        try handle.synchronize()
        return target
    }
    /// Startup-only transaction. Ordinary saves always execute asynchronously in
    /// the adapter. Migration must commit before accepting new runtime records.
    public func loadAndMigrate(lifeListURL:URL?=nil,legacySourceInactive:Bool=true) throws -> ObservationStoreLoad {
        let initial:(ObservationArchive,Data)?
        do {initial=try readOptional()}
        catch {
            if let bytes=try? Self.readBounded(url) {_ = try? backup(bytes,name:"unreadable-archive")}
            throw error
        }
        if initial==nil,lifeListURL==nil {return ObservationStoreLoad(archive:ObservationArchive(),importIssue:nil)}
        // With no sources, do not create an empty real-user archive or sidecars.
        if initial==nil,let source=lifeListURL {
            do {_=try FileManager.default.attributesOfItem(atPath:source.path)}
            catch {if Self.missing(error) {return ObservationStoreLoad(archive:ObservationArchive(),importIssue:nil)};throw error}
        }
        let fd=try lock(wait:0.5);defer {Darwin.close(fd)}
        let current=try readOptional()
        var archive=current?.0 ?? ObservationArchive()
        var changed=archive.requiresMigration
        if changed,let bytes=current?.1 {try backup(bytes,name:"legacy-observations")}
        var issue:String?
        if archive.migration.lifeList==nil,let source=lifeListURL {
            do {
                let bytes=try Self.readBounded(source)
                let legacy=try ObservationLegacyLifeList.decode(bytes)
                guard legacySourceInactive else {throw ObservationStoreError.legacyPending("another Birding process is running")}
                let attributes=try FileManager.default.attributesOfItem(atPath:source.path)
                guard let modified=attributes[.modificationDate] as? Date,Date().timeIntervalSince(modified)>=2 else {
                    throw ObservationStoreError.legacyPending("source was modified less than two seconds ago")
                }
                try backup(bytes,name:"life-list")
                guard try Self.readBounded(source)==bytes else {throw ObservationStoreError.legacyPending("source changed during import")}
                archive=try archive.importing(legacy,fingerprint:Self.fingerprint(bytes));changed=true
            } catch {
                if !Self.missing(error) {
                    issue=error.localizedDescription
                    if let bytes=try? Self.readBounded(source) {_ = try? backup(bytes,name:"pending-life-list")}
                }
            }
        }
        if changed {
            try archive.save(to:url)
            // Return the committed form with requiresMigration cleared.
            archive=try ObservationArchive.load(from:url)
        }
        expectsArchive=current != nil || changed
        return ObservationStoreLoad(archive:archive,importIssue:issue)
    }
    /// A pending batch keeps exactly the same baseline, local snapshot, writer
    /// and sequence until acknowledged. Sequence and aggregates commit together.
    public func commit(local:ObservationArchive,baseline:ObservationArchive,sequence:UInt64,lockWait:Double=0) throws -> ObservationArchive {
        guard sequence>0 else {throw ObservationStoreError.sequenceMismatch}
        let fd=try lock(wait:lockWait);defer {Darwin.close(fd)}
        let current=try readOptional()
        guard current != nil || !expectsArchive else {throw ObservationStoreError.archiveRemoved}
        var disk=current?.0 ?? ObservationArchive()
        if disk.requiresMigration,let bytes=current?.1 {try backup(bytes,name:"legacy-observations")}
        if let registered=disk.writerProgress.first(where:{$0.writerID==writerID}) {
            guard slot==registered.slot,lease>=0 else {throw ObservationStoreError.retiredWriter}
            if sequence<=registered.sequence {
                guard sequence==registered.sequence else {throw ObservationStoreError.sequenceMismatch}
                committedSequence=registered.sequence;expectsArchive=true;return disk
            }
            guard registered.sequence<UInt64.max,sequence==registered.sequence+1 else {throw ObservationStoreError.sequenceMismatch}
        } else {
            guard committedSequence==0,sequence==1 else {throw ObservationStoreError.retiredWriter}
            if slot==nil {try claimSlot(in:&disk)}
            // A failed first write can hold a slot not yet present on disk.
            disk.writerProgress.removeAll{$0.slot==slot}
        }
        var merged=try ObservationArchive.merging(local:local,baseline:baseline,disk:current==nil ? nil:disk)
        merged.writerProgress=disk.writerProgress.filter{$0.writerID != writerID}
        merged.writerProgress.append(ObservationWriterProgress(writerID:writerID,slot:slot!,sequence:sequence))
        merged.writerProgress.sort{$0.slot<$1.slot}
        try merged.save(to:url)
        committedSequence=sequence;expectsArchive=true
        return merged
    }
    private func claimSlot(in archive:inout ObservationArchive) throws {
        try FileManager.default.createDirectory(at:writersURL,withIntermediateDirectories:true)
        for candidate in 0..<ObservationArchive.maximumWriters {
            let path=writersURL.appendingPathComponent("slot-\(candidate).lock").path
            let fd=Darwin.open(path,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,mode_t(0o600))
            guard fd>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
            if flock(fd,LOCK_EX|LOCK_NB)==0 {
                slot=candidate;lease=fd
                archive.writerProgress.removeAll{$0.slot==candidate}
                return
            }
            let code=errno;Darwin.close(fd)
            guard code==EWOULDBLOCK || code==EAGAIN else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))}
        }
        throw ObservationStoreError.writerCapacity
    }
}
