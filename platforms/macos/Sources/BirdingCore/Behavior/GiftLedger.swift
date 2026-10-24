import Foundation
import Darwin

/// Platform clocks are injected at the IO boundary, never read by the simulation.
public struct GiftLedgerClock {
    public let wallTime: () -> Double
    public let monotonicTime: () -> Double
    public init(wallTime: @escaping () -> Double, monotonicTime: @escaping () -> Double) {
        self.wallTime=wallTime;self.monotonicTime=monotonicTime
    }
    public static var live: Self {
        Self(wallTime:{Date().timeIntervalSince1970},monotonicTime:{ProcessInfo.processInfo.systemUptime})
    }
}

public enum GiftLedgerError: Error {
    case denied(GiftAuthorizationDenial)
    public var denial: GiftAuthorizationDenial {
        switch self {case .denied(let reason):return reason}
    }
}

/// Shared by ledger and visitor persistence. The lock file is stable: never
/// rename or unlink it when atomically replacing the adjacent data file.
public enum GiftLedgerFileAccess {
    public static func checkDeadline(_ deadline:Double,clock:GiftLedgerClock) throws {
        let now=clock.monotonicTime()
        guard deadline.isFinite,now.isFinite,now<deadline else {throw GiftLedgerError.denied(.timedOut)}
    }
    public static func withLock<T>(for url:URL,deadline:Double,clock:GiftLedgerClock = .live,waitForLock:Bool=true,
                                   _ body:() throws -> T) throws -> T {
        try checkDeadline(deadline,clock:clock)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let lockURL=url.appendingPathExtension("lock")
        let fd=Darwin.open(lockURL.path,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,mode_t(0o600))
        guard fd>=0 else {throw GiftLedgerError.denied(.storageUnavailable)}
        defer {Darwin.close(fd)}
        while flock(fd,LOCK_EX|LOCK_NB) != 0 {
            guard errno==EWOULDBLOCK || errno==EAGAIN || errno==EINTR else {
                throw GiftLedgerError.denied(.storageUnavailable)
            }
            guard waitForLock else {throw GiftLedgerError.denied(.busy)}
            try checkDeadline(deadline,clock:clock)
            Thread.sleep(forTimeInterval:min(0.01,max(0,deadline-clock.monotonicTime())))
        }
        defer {_=flock(fd,LOCK_UN)}
        try checkDeadline(deadline,clock:clock)
        return try body()
    }
    public static func exists(_ url:URL) throws -> Bool {
        do {_=try FileManager.default.attributesOfItem(atPath:url.path);return true}
        catch {
            let e=error as NSError
            if e.domain==NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(e.code) {return false}
            throw error
        }
    }
    public static func read(_ url:URL,maximumBytes:Int) throws -> Data {
        let handle=try FileHandle(forReadingFrom:url)
        defer {try? handle.close()}
        var data=Data()
        while let chunk=try handle.read(upToCount:maximumBytes+1-data.count),!chunk.isEmpty {
            data.append(chunk)
            guard data.count<=maximumBytes else {throw GiftLedgerError.denied(.invalidLedger)}
        }
        return data
    }
    /// Write and sync a sibling before rename, then sync the directory. A failure
    /// after rename is deliberately not rolled back: consumption may be durable.
    public static func atomicWrite(_ data:Data,to url:URL) throws {
        let parent=url.deletingLastPathComponent()
        let temporary=parent.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fd=Darwin.open(temporary.path,O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC|O_NOFOLLOW,mode_t(0o600))
        guard fd>=0 else {throw GiftLedgerError.denied(.storageUnavailable)}
        defer {Darwin.close(fd);_=Darwin.unlink(temporary.path)}
        try data.withUnsafeBytes { bytes in
            var offset=0
            while offset<bytes.count {
                let count=Darwin.write(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset)
                if count<0 && errno==EINTR {continue}
                guard count>0 else {throw GiftLedgerError.denied(.storageUnavailable)}
                offset+=count
            }
        }
        guard Darwin.fsync(fd)==0,Darwin.fcntl(fd,F_FULLFSYNC)==0,
              Darwin.rename(temporary.path,url.path)==0 else {
            throw GiftLedgerError.denied(.storageUnavailable)
        }
        let directory=Darwin.open(parent.path,O_RDONLY|O_DIRECTORY|O_CLOEXEC)
        guard directory>=0 else {throw GiftLedgerError.denied(.storageUnavailable)}
        defer {Darwin.close(directory)}
        guard Darwin.fsync(directory)==0,Darwin.fcntl(fd,F_FULLFSYNC)==0 else {
            throw GiftLedgerError.denied(.storageUnavailable)
        }
    }
}

public struct GiftLedger: Codable, Equatable {
    public static let currentVersion=1
    public static let maximumEntries=10_000
    public static let maximumBytes=2*1024*1024
    public static let minimumInterval:Double=24*60*60
    public struct Grant: Codable, Equatable {
        public let visitorArchiveSeed:String
        public let visitorID:String
        public let grantedAt:Double
    }
    public let version:Int
    public private(set) var grants:[Grant]
    public private(set) var lastGrantedAt:Double?
    public init() {version=Self.currentVersion;grants=[];lastGrantedAt=nil}
    private enum CodingKeys:String,CodingKey {case version,grants,lastGrantedAt}
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        version=try values.decode(Int.self,forKey:.version)
        guard version==Self.currentVersion else {throw GiftLedgerError.denied(.unsupportedVersion)}
        var list=try values.nestedUnkeyedContainer(forKey:.grants)
        var decoded:[Grant]=[]
        while !list.isAtEnd {
            guard decoded.count<Self.maximumEntries else {throw GiftLedgerError.denied(.invalidLedger)}
            decoded.append(try list.decode(Grant.self))
        }
        grants=decoded;lastGrantedAt=try values.decodeIfPresent(Double.self,forKey:.lastGrantedAt)
        try validate()
    }
    private struct Envelope:Decodable {let version:Int}
    public static func decode(_ data:Data) throws -> Self {
        guard data.count<=maximumBytes else {throw GiftLedgerError.denied(.invalidLedger)}
        do {
            guard try JSONDecoder().decode(Envelope.self,from:data).version==currentVersion else {
                throw GiftLedgerError.denied(.unsupportedVersion)
            }
            let value=try JSONDecoder().decode(Self.self,from:data)
            try value.validate();return value
        } catch let error as GiftLedgerError {throw error}
        catch {throw GiftLedgerError.denied(.invalidLedger)}
    }
    public static func load(from url:URL) throws -> Self {
        try decode(GiftLedgerFileAccess.read(url,maximumBytes:maximumBytes))
    }
    public func validate() throws {
        guard version==Self.currentVersion else {throw GiftLedgerError.denied(.unsupportedVersion)}
        guard grants.count<=Self.maximumEntries else {throw GiftLedgerError.denied(.invalidLedger)}
        var keys=Set<String>(),previous:Double?
        for grant in grants {
            guard let seed=UInt64(grant.visitorArchiveSeed),String(seed)==grant.visitorArchiveSeed,
                  let id=UInt64(grant.visitorID),id>0,String(id)==grant.visitorID,
                  grant.grantedAt.isFinite,grant.grantedAt>=0,
                  keys.insert(grant.visitorArchiveSeed+":"+grant.visitorID).inserted,
                  previous.map({grant.grantedAt-$0>=Self.minimumInterval}) ?? true else {
                throw GiftLedgerError.denied(.invalidLedger)
            }
            previous=grant.grantedAt
        }
        guard lastGrantedAt==previous else {throw GiftLedgerError.denied(.invalidLedger)}
    }
    fileprivate mutating func append(_ binding:GiftBinding,at time:Double) {
        grants.append(Grant(visitorArchiveSeed:binding.visitorArchiveSeed,visitorID:binding.visitorID,grantedAt:time))
        lastGrantedAt=time
    }
}

/// Synchronous IO API, also usable from isolated native child processes. The
/// caller persists visitor identity before entry; the platform holds that file's
/// lock through this transaction (visitor lock, then ledger lock, never reverse).
public final class GiftLedgerStore {
    public let url:URL
    public init(url:URL) {self.url=url}
    /// Precondition for production callers: visitorArchive is an immutable
    /// identity snapshot verified against its durable archive while holding that
    /// archive's stable flock. Keep the visitor lock held until this call returns.
    /// This store owns ONLY the ledger lock; passing an arbitrary in-memory
    /// archive does not establish persistent namespace/visitor identity.
    public func authorize(_ request:GiftAuthorizationRequest,visitorArchive:VisitorMemoryArchive,
                          deadline:Double,clock:GiftLedgerClock = .live) -> GiftAuthorizationResult {
        let binding=request.binding
        func denied(_ reason:GiftAuthorizationDenial)->GiftAuthorizationResult {.init(denied:binding,reason:reason)}
        guard binding.isValid,binding.source == .automatic else {return denied(.invalidRequest)}
        do {
            try visitorArchive.validate()
            guard visitorArchive.seed==binding.visitorArchiveSeed,
                  let profile=visitorArchive.profiles.first(where:{$0.id==binding.visitorID}),
                  profile.species==binding.species else {return denied(.namespaceUnavailable)}
            guard profile.visits>=3,profile.familiarity>=0.6 else {return denied(.notEligible)}
            return try GiftLedgerFileAccess.withLock(for:url,deadline:deadline,clock:clock) {
                var ledger:GiftLedger
                if try GiftLedgerFileAccess.exists(url) {ledger=try GiftLedger.load(from:url)}
                else {ledger=GiftLedger()}
                let now=clock.wallTime()
                guard now.isFinite,now>=0 else {return denied(.clockRollback)}
                if let last=ledger.lastGrantedAt,now<last {return denied(.clockRollback)}
                if ledger.grants.contains(where:{$0.visitorArchiveSeed==binding.visitorArchiveSeed && $0.visitorID==binding.visitorID}) {
                    return denied(.alreadyGranted)
                }
                guard ledger.grants.count<GiftLedger.maximumEntries else {return denied(.ledgerFull)}
                if let last=ledger.lastGrantedAt,now-last<GiftLedger.minimumInterval {return denied(.globalCooldown)}
                ledger.append(binding,at:now)
                let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
                let data=try encoder.encode(ledger)
                guard data.count<=GiftLedger.maximumBytes else {return denied(.ledgerFull)}
                try GiftLedgerFileAccess.checkDeadline(deadline,clock:clock)
                try GiftLedgerFileAccess.atomicWrite(data,to:url)
                // The deadline may expire during IO. Preserve the committed key;
                // return no token after the platform's deadline.
                try GiftLedgerFileAccess.checkDeadline(deadline,clock:clock)
                return GiftAuthorizationResult(granted:GiftAuthorizationToken(id:UUID(),binding:binding))
            }
        } catch let error as GiftLedgerError {return denied(error.denial)}
        catch {return denied(.storageUnavailable)}
    }
}
