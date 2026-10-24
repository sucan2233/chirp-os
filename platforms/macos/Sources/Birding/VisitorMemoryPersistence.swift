import Foundation
import BirdingCore

/// The in-process baseline participates in the same file-locked compare/swap as
/// periodic saves and gift saves. Background work never reads the live engine.
fileprivate final class VisitorPersistenceBaseline {
    private let lock=NSLock()
    private var value:VisitorMemoryArchive?
    private var healthy=false
    func read()->(VisitorMemoryArchive?,Bool) {
        lock.lock();defer {lock.unlock()};return (value,healthy)
    }
    func set(_ archive:VisitorMemoryArchive?,healthy:Bool) {
        lock.lock();defer {lock.unlock()};value=archive;self.healthy=healthy
    }
}

/// Immutable engine snapshot with a thread-safe persistence baseline. Holding
/// visitors.lock until the ledger commits establishes the persistent identity
/// used by that grant. No path takes these locks in reverse order.
struct GiftVisitorIdentitySnapshot {
    let url:URL
    let archive:VisitorMemoryArchive
    let allowsWrites:Bool
    fileprivate let baseline:VisitorPersistenceBaseline

    static func isSuccessor(_ next:VisitorMemoryArchive,of old:VisitorMemoryArchive)->Bool {
        guard next.seed==old.seed,let nextID=UInt64(next.nextID),let oldID=UInt64(old.nextID),
              let ordinal=UInt64(next.visitOrdinal),let oldOrdinal=UInt64(old.visitOrdinal),
              nextID>=oldID,ordinal>=oldOrdinal else {return false}
        let previous=Dictionary(uniqueKeysWithValues:old.profiles.map{($0.id,$0)})
        for profile in next.profiles {
            guard let id=UInt64(profile.id) else {return false}
            if let prior=previous[profile.id] {
                guard profile.species==prior.species,profile.seed==prior.seed,
                      profile.visits>=prior.visits,profile.calmSeconds>=prior.calmSeconds,
                      UInt64(profile.lastVisitOrdinal)! >= UInt64(prior.lastVisitOrdinal)! else {return false}
            } else if id<oldID {return false}
        }
        let nextKeys=Set(next.profiles.map(\.id))
        if old.profiles.contains(where:{!nextKeys.contains($0.id)}),
           !(nextID>oldID && next.profiles.count==VisitorMemoryArchive.maximumProfiles) {return false}
        return true
    }

    /// Caller must hold the stable visitor lock. Never merge an independently
    /// advanced archive: two instances may have assigned the same ID differently.
    func persistLocked() throws {
        try archive.validate()
        guard let expected=baseline.read().0,archive.seed==expected.seed,
              try GiftLedgerFileAccess.exists(url) else {
            throw GiftLedgerError.denied(.namespaceUnavailable)
        }
        let disk=try VisitorMemoryArchive.load(from:url)
        guard disk==archive || (disk==expected && Self.isSuccessor(archive,of:disk)) else {
            throw GiftLedgerError.denied(.namespaceUnavailable)
        }
        if disk != archive {
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            let data=try encoder.encode(archive)
            guard data.count<=VisitorMemoryArchive.maximumBytes else {throw GiftLedgerError.denied(.namespaceUnavailable)}
            try GiftLedgerFileAccess.atomicWrite(data,to:url)
        }
        baseline.set(archive,healthy:true)
    }
    func authorize(_ request:GiftAuthorizationRequest,store:GiftLedgerStore,
                   deadline:Double,clock:GiftLedgerClock)->GiftAuthorizationResult {
        do {
            return try GiftLedgerFileAccess.withLock(for:url,deadline:deadline,clock:clock) {
                guard baseline.read().1 else {throw GiftLedgerError.denied(.namespaceUnavailable)}
                guard request.binding.visitorArchiveSeed==archive.seed,
                      let profile=archive.profiles.first(where:{$0.id==request.binding.visitorID}),
                      profile.species==request.binding.species else {throw GiftLedgerError.denied(.namespaceUnavailable)}
                guard profile.visits>=3,profile.familiarity>=0.6 else {throw GiftLedgerError.denied(.notEligible)}
                if allowsWrites {try persistLocked()}
                else {
                    // A real recording keeps visitors.json read-only. Existing
                    // durable identities can still receive recorded real grants;
                    // new identities cannot acquire a namespace by implication.
                    let disk=try VisitorMemoryArchive.load(from:url)
                    guard disk==baseline.read().0,disk.seed==archive.seed,
                          let durable=disk.profiles.first(where:{$0.id==profile.id}),
                          durable.species==profile.species,durable.seed==profile.seed else {
                        throw GiftLedgerError.denied(.namespaceUnavailable)
                    }
                }
                return store.authorize(request,visitorArchive:archive,deadline:deadline,clock:clock)
            }
        } catch let error as GiftLedgerError {
            return GiftAuthorizationResult(denied:request.binding,reason:error.denial)
        } catch {
            return GiftAuthorizationResult(denied:request.binding,reason:.namespaceUnavailable)
        }
    }
}

/// The core owns the archive and its serialization. This adapter only schedules IO.
/// Construction is inert; callers load after settings and before registering birds.
final class VisitorMemoryPersistence {
    static let saveInterval:Double = 30
    static var defaultURL:URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Birding/visitors.json")
    }
    /// Behavior recording may load real visitors; diagnostic modes need opt-in.
    static func automaticEnabled(arguments:[String]) -> Bool {
        !arguments.contains { argument in
            argument.hasPrefix("--verify") || argument.hasPrefix("--stress") ||
                argument.hasPrefix("--gift-ledger-worker") || argument.hasPrefix("--replay-") ||
                argument.hasPrefix("--export-") ||
                ["--integration","--fixture"].contains {
                    argument == $0 || argument.hasPrefix($0+"=")
                }
        }
    }

    let url:URL
    /// enabled gates loading; recording sessions additionally prohibit writes.
    let enabled:Bool
    let writesEnabled:Bool
    private(set) var loaded=false
    private(set) var writesDisabled=false
    private(set) var saveAttempts=0
    private(set) var successfulSaves=0
    private let baseline=VisitorPersistenceBaseline()
    private var savedArchive:VisitorMemoryArchive? {baseline.read().0}
    private(set) var bootstrapCreated=false
    var giftNamespaceAvailable:Bool {loaded && enabled && !writesDisabled && baseline.read().1}
    var giftNamespaceDenial:GiftAuthorizationDenial? {giftNamespaceAvailable ? nil:.namespaceUnavailable}
    private var lastCheck:Double=0
    private var retryAfter:Double?
    private var loggedSaveFailure=false
    private let log:(String)->Void

    init(url:URL=VisitorMemoryPersistence.defaultURL,enabled:Bool?=nil,
         arguments:[String]=CommandLine.arguments,
         log:@escaping (String)->Void={NSLog("Birding visitor memory: %@",$0)}) {
        self.url=url
        let automatic=Self.automaticEnabled(arguments:arguments)
        // An explicit verifier override must also supply an isolated path.
        let effectiveEnabled=(enabled ?? automatic) &&
            (automatic || url.standardizedFileURL != Self.defaultURL.standardizedFileURL)
        self.enabled=effectiveEnabled
        self.writesEnabled=effectiveEnabled && !arguments.contains {
            $0 == "--record-behavior" || $0.hasPrefix("--record-behavior=")
        }
        self.log=log
    }

    func load(into engine:BehaviorEngine,now:Double) {
        guard !loaded,now.isFinite else {return}
        loaded=true;lastCheck=now
        guard enabled else {return}
        do {
            let archive:VisitorMemoryArchive
            if writesEnabled {
                archive=try GiftLedgerFileAccess.withLock(for:url,deadline:ProcessInfo.processInfo.systemUptime+5) {
                    if try GiftLedgerFileAccess.exists(url) {return try VisitorMemoryArchive.load(from:url)}
                    let initial=engine.visitorMemoryArchive
                    try initial.validate()
                    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
                    try GiftLedgerFileAccess.atomicWrite(encoder.encode(initial),to:url)
                    bootstrapCreated=true
                    return initial
                }
            } else {archive=try VisitorMemoryArchive.load(from:url)}
            try engine.restoreVisitorMemory(archive)
            baseline.set(engine.visitorMemoryArchive,healthy:true)
        } catch {
            let failure=error as NSError
            if failure.domain == NSCocoaErrorDomain &&
                [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(failure.code) {
                // Read-only recordings may start without a visitor file, but
                // that temporary namespace must never authorize real gifts.
                baseline.set(engine.visitorMemoryArchive,healthy:false)
            } else {
                writesDisabled=true
                log("load failed; writes disabled for this session: \(error.localizedDescription)")
            }
        }
    }

    func persistIfNeeded(from engine:BehaviorEngine,now:Double) {
        guard loaded,writesEnabled,!writesDisabled,now.isFinite,now-lastCheck>=Self.saveInterval else {return}
        lastCheck=now
        flush(from:engine,now:now)
    }

    func flush(from engine:BehaviorEngine,now:Double) {
        guard loaded,writesEnabled,!writesDisabled,now.isFinite,
              retryAfter.map({now >= $0}) ?? true else {return}
        let archive=engine.visitorMemoryArchive
        guard savedArchive != archive else {return}
        saveAttempts+=1
        do {
            // Do not wait behind asynchronous gift IO on the simulation thread.
            // A busy lock is retried by the existing bounded save schedule.
            try GiftLedgerFileAccess.withLock(for:url,deadline:ProcessInfo.processInfo.systemUptime+5,waitForLock:false) {
                try GiftVisitorIdentitySnapshot(url:url,archive:archive,allowsWrites:true,baseline:baseline).persistLocked()
            }
            successfulSaves+=1
            retryAfter=nil;loggedSaveFailure=false
        } catch {
            retryAfter=now+Self.saveInterval
            if !loggedSaveFailure {
                log("save failed; retrying at most every 30 seconds: \(error.localizedDescription)")
                loggedSaveFailure=true
            }
        }
    }

    /// Called on the controller thread before dispatching background IO.
    func giftIdentitySnapshot(archive:VisitorMemoryArchive)->GiftVisitorIdentitySnapshot? {
        guard giftNamespaceAvailable,archive.seed==savedArchive?.seed else {return nil}
        return GiftVisitorIdentitySnapshot(url:url,archive:archive,allowsWrites:writesEnabled,baseline:baseline)
    }
}

extension DesktopController {
    /// Injection properties must be set before this first call (or start()).
    func loadVisitorMemory(now:Double=ProcessInfo.processInfo.systemUptime) {
        guard visitorMemoryPersistence == nil else {return}
        let persistence=VisitorMemoryPersistence(url:visitorMemoryURL,enabled:visitorMemoryPersistenceEnabled)
        visitorMemoryPersistence=persistence
        persistence.load(into:engine,now:now)
    }
    func persistVisitorMemoryIfNeeded(now:Double) {
        visitorMemoryPersistence?.persistIfNeeded(from:engine,now:now)
    }
    func flushVisitorMemory() {
        visitorMemoryPersistence?.flush(from:engine,now:ProcessInfo.processInfo.systemUptime)
    }
}
