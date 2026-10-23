import AppKit
import BirdingCore
import Darwin

/// Read/write scheduling stays outside simulation. The journal contains only
/// species, completed behavior counts and discovery dates, never desktop input.
final class ObservationJournalPersistence {
    static let saveInterval:Double=30
    static var defaultURL:URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Birding/observations.json")
    }
    static func automaticEnabled(arguments:[String])->Bool {
        VisitorMemoryPersistence.automaticEnabled(arguments:arguments) && !arguments.contains {
            $0 == "--record-behavior" || $0.hasPrefix("--record-behavior=") ||
                $0 == "--replay-behavior" || $0.hasPrefix("--replay-behavior=")
        }
    }
    let url:URL
    let enabled:Bool
    private(set) var loaded=false
    private(set) var writesDisabled=false
    private(set) var saveAttempts=0
    private(set) var successfulSaves=0
    private(set) var saveFailed=false
    private var savedArchive:ObservationArchive?
    private var lastCheck:Double=0
    private var retryAfter:Double?
    private let log:(String)->Void

    init(url:URL=ObservationJournalPersistence.defaultURL,enabled:Bool?=nil,
         arguments:[String]=CommandLine.arguments,
         log:@escaping(String)->Void={NSLog("Birding observation journal: %@",$0)}) {
        self.url=url
        let automatic=Self.automaticEnabled(arguments:arguments)
        // Verification can opt in only with an isolated path. Recording/replay
        // never touches the real notebook, even with an explicit override.
        self.enabled=(enabled ?? automatic) &&
            (automatic || url.standardizedFileURL != Self.defaultURL.standardizedFileURL)
        self.log=log
    }
    func load(into journal:ObservationJournal,now:Double) {
        guard !loaded,now.isFinite else {return}
        loaded=true;lastCheck=now
        guard enabled else {return}
        do {
            try journal.restore(ObservationArchive.load(from:url))
            savedArchive=journal.archive
        } catch {
            let failure=error as NSError
            if failure.domain == NSCocoaErrorDomain &&
                [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(failure.code) {
                savedArchive=journal.archive
            } else {
                writesDisabled=true
                log("load failed; original file preserved and writes disabled: \(error.localizedDescription)")
            }
        }
    }
    func persistIfNeeded(from journal:ObservationJournal,now:Double) {
        guard loaded,enabled,!writesDisabled,now.isFinite,now-lastCheck>=Self.saveInterval else {return}
        lastCheck=now;flush(from:journal,now:now)
    }
    func flush(from journal:ObservationJournal,now:Double,terminating:Bool=false) {
        guard loaded,enabled,!writesDisabled,now.isFinite,
              (terminating || (retryAfter.map({now >= $0}) ?? true)) else {return}
        let archive=journal.archive
        guard archive != savedArchive else {return}
        saveAttempts+=1
        do {
            try saveMerged(archive,lockWait:terminating ? 0.5:0)
            savedArchive=archive;successfulSaves+=1;retryAfter=nil;saveFailed=false
        } catch {
            retryAfter=now+Self.saveInterval
            if !saveFailed {log("save failed; retrying at most every 30 seconds: \(error.localizedDescription)")}
            saveFailed=true
        }
    }
    /// Lock a stable sibling file, since atomic replacement changes the archive
    /// inode. Contention returns immediately and uses the normal bounded retry.
    private func saveMerged(_ local:ObservationArchive,lockWait:Double) throws {
        let files=FileManager.default
        try files.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let descriptor=Darwin.open(url.path+".lock",O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,mode_t(0o600))
        guard descriptor>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        defer {Darwin.close(descriptor)}
        let deadline=ProcessInfo.processInfo.systemUptime+lockWait
        while flock(descriptor,LOCK_EX|LOCK_NB) != 0 {
            let code=errno
            guard (code==EWOULDBLOCK || code==EAGAIN),ProcessInfo.processInfo.systemUptime<deadline else {
                throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))
            }
            Thread.sleep(forTimeInterval:0.01)
        }
        defer {_ = flock(descriptor,LOCK_UN)}
        let disk:ObservationArchive?
        do {disk=try ObservationArchive.load(from:url)}
        catch {
            let failure=error as NSError
            guard failure.domain==NSCocoaErrorDomain,
                  [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(failure.code) else {throw error}
            disk=nil
        }
        let merged=try Self.merge(local:local,baseline:savedArchive ?? ObservationArchive(),disk:disk)
        try merged.save(to:url)
    }
    /// Each process adds only its unsaved increments to the latest file. Keep
    /// the local baseline separate so another process's counts are never added
    /// twice on the next flush. Other-instance entries appear on the next launch.
    static func merge(local:ObservationArchive,baseline:ObservationArchive,disk:ObservationArchive?) throws -> ObservationArchive {
        try local.validate();try baseline.validate()
        guard let disk else {return local}
        try disk.validate()
        func key(_ entry:ObservationEntry)->String {entry.species.rawValue+":"+entry.behavior}
        let old=Dictionary(uniqueKeysWithValues:baseline.entries.map{(key($0),$0)})
        var merged=Dictionary(uniqueKeysWithValues:disk.entries.map{(key($0),$0)})
        for entry in local.entries {
            let previous=old[key(entry)]
            guard entry != previous else {continue}
            let increments=[entry.automaticCount-(previous?.automaticCount ?? 0),
                            entry.previewCount-(previous?.previewCount ?? 0),entry.userCount-(previous?.userCount ?? 0)]
            guard increments.allSatisfy({$0>=0}) else {throw ObservationJournalError.invalid("local counters moved backwards")}
            let existing=merged[key(entry)]
            let counts=[existing?.automaticCount ?? 0,existing?.previewCount ?? 0,existing?.userCount ?? 0]
            let totals=zip(counts,increments).map{min(ObservationArchive.maximumCount,$0+$1)}
            // A valid external archive may have deliberately omitted an old
            // entry. Only new observations reintroduce it, never stale history.
            guard totals.reduce(0,+)>0 else {continue}
            merged[key(entry)]=ObservationEntry(species:entry.species,behavior:entry.behavior,
                firstSeen:min(existing?.firstSeen ?? entry.firstSeen,entry.firstSeen),
                lastSeen:max(existing?.lastSeen ?? entry.lastSeen,entry.lastSeen),
                automaticCount:totals[0],previewCount:totals[1],userCount:totals[2])
        }
        let result=ObservationArchive(entries:merged.values.sorted {
            $0.species == $1.species ? $0.behavior<$1.behavior:$0.species.rawValue<$1.species.rawValue
        })
        try result.validate();return result
    }
    func statusMessage(language:AppLanguage)->String {
        if writesDisabled {
            return language.text("无法读取原观察记录，已保留原文件。本次发现暂存于内存，退出后不会保存。",
                                 "The saved journal could not be read and has been preserved. New discoveries are kept only for this session.")
        }
        if saveFailed {
            return language.text("观察记录暂时无法保存，将稍后重试。",
                                 "The journal could not be saved. Saving will be retried shortly.")
        }
        return ""
    }
}

extension DesktopController {
    func loadObservationJournal(now:Double=ProcessInfo.processInfo.systemUptime) {
        guard observationPersistence == nil else {return}
        let persistence=ObservationJournalPersistence(url:observationJournalURL,enabled:observationJournalPersistenceEnabled)
        observationPersistence=persistence
        persistence.load(into:observationJournal,now:now)
        // Direct completion delivery avoids losing discoveries when the bounded
        // diagnostics ring rolls over; it neither drives nor randomizes motion.
        engine.observationObserver={ [weak self] observation in
            guard let self else {return}
            _ = self.observationJournal.observe(observation,at:self.observationDate())
        }
    }
    func persistObservationJournalIfNeeded(now:Double) {
        observationPersistence?.persistIfNeeded(from:observationJournal,now:now)
        observationWindow?.persistenceMessage=observationPersistence?.statusMessage(language:language) ?? ""
        observationWindow?.refresh()
    }
    func flushObservationJournal() {
        observationPersistence?.flush(from:observationJournal,now:ProcessInfo.processInfo.systemUptime,terminating:true)
    }
    @objc func showObservationJournal() {
        loadObservationJournal()
        if observationWindow == nil {observationWindow=ObservationJournalWindow(desktop:self)}
        observationWindow?.persistenceMessage=observationPersistence?.statusMessage(language:language) ?? ""
        observationWindow?.showWindow(nil);observationWindow?.refresh()
        NSApp.activate(ignoringOtherApps:true)
    }
}
