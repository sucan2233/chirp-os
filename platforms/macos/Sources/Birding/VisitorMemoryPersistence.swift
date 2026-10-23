import Foundation
import BirdingCore

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
    private var savedArchive:VisitorMemoryArchive?
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
            let archive=try VisitorMemoryArchive.load(from:url)
            try engine.restoreVisitorMemory(archive)
            savedArchive=engine.visitorMemoryArchive
        } catch {
            let failure=error as NSError
            if failure.domain == NSCocoaErrorDomain &&
                [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(failure.code) {
                savedArchive=engine.visitorMemoryArchive
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
            // save(to:) checks the current destination again, protecting a file
            // replaced with a future/corrupt archive after initial loading.
            try archive.save(to:url)
            savedArchive=archive;successfulSaves+=1
            retryAfter=nil;loggedSaveFailure=false
        } catch {
            retryAfter=now+Self.saveInterval
            if !loggedSaveFailure {
                log("save failed; retrying at most every 30 seconds: \(error.localizedDescription)")
                loggedSaveFailure=true
            }
        }
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
