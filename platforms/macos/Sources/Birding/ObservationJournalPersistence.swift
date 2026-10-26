import AppKit
import BirdingCore

/// Main-thread adapter; all save transactions run on one utility queue. A failed
/// batch retains its immutable snapshot and sequence until it is acknowledged.
final class ObservationJournalPersistence {
    static let saveInterval:Double=30
    static var defaultURL:URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Birding/observations.json")
    }
    static func automaticEnabled(arguments:[String])->Bool {
        VisitorMemoryPersistence.automaticEnabled(arguments:arguments) && !arguments.contains {
            $0 == "--record-behavior" || $0.hasPrefix("--record-behavior=") ||
                $0 == "--replay-behavior" || $0.hasPrefix("--replay-behavior=") ||
                $0.hasPrefix("--soak") || $0.hasPrefix("--desktop-soak")
        }
    }
    let url:URL
    let enabled:Bool
    private(set) var loaded=false
    private(set) var importedModePreference:Bool?
    var importedObservationsEnabled:Bool? {importedModePreference}
    private(set) var importIssue:String?
    private let queue=DispatchQueue(label:"Birding.observation-journal.save",qos:.utility)
    private let group=DispatchGroup()
    private let stateLock=NSLock()
    private let store:ObservationArchiveStore
    private let lifeListURL:URL?
    private let legacySourceInactive:()->Bool
    private let log:(String)->Void
    private var lastCheck:Double=0
    private weak var journal:ObservationJournal?
    // Protected by stateLock, including writes from the serial worker.
    private var disabled=false
    private var attempts=0
    private var successes=0
    private var failed=false
    private var inFlight=false
    private var retryAfter:Double?
    private var requested:Request?
    private var acknowledged=ObservationArchive()
    private var acknowledgedSequence:UInt64=0
    private var hasPending=false
    private var terminating=false
    private struct Request {let archive:ObservationArchive;let now:Double;let terminating:Bool}
    private struct Batch {let local:ObservationArchive;let baseline:ObservationArchive;let sequence:UInt64}
    // Queue-owned state. Never updated from a stale main-queue callback.
    private var baseline=ObservationArchive()
    private var pending:Batch?
    private var nextSequence:UInt64=1
    private func read<T>(_ body:()->T)->T {stateLock.lock();defer {stateLock.unlock()};return body()}
    var sidecarURLs:[URL] {[store.lockURL,store.writersURL,store.backupsURL]}
    var writesDisabled:Bool {read{disabled}}
    var saveAttempts:Int {read{attempts}}
    var successfulSaves:Int {read{successes}}
    var saveFailed:Bool {read{failed}}
    var isSaving:Bool {read{inFlight}}
    var hasUnsavedChanges:Bool {read{hasPending || inFlight}}
    var lastSavedSequence:UInt64 {read{acknowledgedSequence}}

    init(url:URL=ObservationJournalPersistence.defaultURL,enabled:Bool?=nil,
         arguments:[String]=CommandLine.arguments,lifeListURL:URL?=nil,
         legacySourceInactive:(()->Bool)?=nil,
         log:@escaping(String)->Void={NSLog("Birding observation journal: %@",$0)}) {
        self.url=url;store=ObservationArchiveStore(url:url)
        let automatic=Self.automaticEnabled(arguments:arguments)
        let real=Self.defaultURL.resolvingSymlinksInPath().standardizedFileURL
        let destination=url.resolvingSymlinksInPath().standardizedFileURL
        self.enabled=(enabled ?? automatic) && (automatic || destination != real)
        // Isolated archives only ever import a sibling source. An explicit
        // cross-directory source cannot pull a real-user Life List into tests.
        let sibling=url.deletingLastPathComponent().appendingPathComponent("life-list.json")
        if let lifeListURL,
           lifeListURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL ==
            url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL {
            self.lifeListURL=lifeListURL
        } else {self.lifeListURL=sibling}
        self.legacySourceInactive=legacySourceInactive ?? {
            !NSWorkspace.shared.runningApplications.contains { app in
                guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {return false}
                let name=app.executableURL?.lastPathComponent.lowercased() ?? ""
                return name=="birding" || name=="chirpos" || app.bundleIdentifier==Bundle.main.bundleIdentifier && app.bundleIdentifier != nil
            }
        }
        self.log=log
    }
    func load(into journal:ObservationJournal,now:Double) {
        guard !loaded,now.isFinite else {return}
        loaded=true;lastCheck=now;self.journal=journal
        guard enabled else {return}
        // Startup is a barrier: migrate+backup+commit before runtime observers
        // attach. After this barrier no save work blocks frame delivery.
        let inactive=legacySourceInactive()
        do {
            let result=try queue.sync {try store.loadAndMigrate(lifeListURL:lifeListURL,legacySourceInactive:inactive)}
            try journal.restore(result.archive)
            baseline=journal.archive;acknowledged=journal.archive
            importedModePreference=result.importedModePreference;importIssue=result.importIssue
            if let issue=importIssue {log(issue)}
        } catch {
            // A failed migration can still display valid local aggregates, but
            // it must never accept writes that bypass its failed transaction.
            if let readable=try? ObservationArchive.load(from:url) {try? journal.restore(readable)}
            read {disabled=true}
            log("load/migration failed; original preserved and writes disabled: \(error.localizedDescription)")
        }
    }
    func persistIfNeeded(from journal:ObservationJournal,now:Double) {
        guard loaded,enabled,!writesDisabled,now.isFinite,now-lastCheck>=Self.saveInterval else {return}
        lastCheck=now;flush(from:journal,now:now)
    }
    func flush(from journal:ObservationJournal,now:Double,terminating:Bool=false) {
        guard loaded,enabled,!writesDisabled,now.isFinite else {return}
        if terminating {journal.stopAcceptingRecords()}
        let request=Request(archive:journal.archive,now:now,terminating:terminating)
        stateLock.lock()
        if self.terminating && !terminating {stateLock.unlock();return}
        if terminating {self.terminating=true}
        guard terminating || (retryAfter.map({now >= $0}) ?? true) else {stateLock.unlock();return}
        // One running worker plus one replaceable latest snapshot bounds memory.
        if inFlight {
            requested=request;stateLock.unlock()
        } else if !hasPending && sameContent(request.archive,acknowledged) {
            stateLock.unlock()
        } else {
            inFlight=true;hasPending=true;group.enter();stateLock.unlock()
            queue.async {self.drain(request)}
        }
        if terminating,group.wait(timeout:.now()+1.5) == .timedOut {
            // An already-finished failed save is not a timeout: drain has
            // retained its batch and reported the error exactly once. Only an
            // unfinished worker warrants this separate exit-timeout message.
            read {failed=true;hasPending=true}
            log("exit save timed out; pending observations are not confirmed saved")
        }
    }
    /// Waits on worker completion, not a main-thread callback. Safe for exit and
    /// verification; false means either timeout or retained unsaved increments.
    @discardableResult func waitForPendingSaves(timeout:Double=2)->Bool {
        guard timeout.isFinite,timeout>=0 else {return false}
        guard group.wait(timeout:.now()+timeout) == .success else {return false}
        return read{!failed && !hasPending}
    }
    private func sameContent(_ a:ObservationArchive,_ b:ObservationArchive)->Bool {
        a.entries==b.entries && a.speciesRecords==b.speciesRecords && a.migration==b.migration
    }
    private func drain(_ first:Request) {
        var request=first
        while true {
            do {
                // First recover an uncertain/failed old batch. Only then compute
                // a new delta, so intervening UI records are never lost or doubled.
                if pending != nil {try savePending(lockWait:request.terminating ? 0.5:0)}
                if !sameContent(request.archive,baseline) {
                    pending=Batch(local:request.archive,baseline:baseline,sequence:nextSequence)
                    try savePending(lockWait:request.terminating ? 0.5:0)
                }
                stateLock.lock()
                failed=false;retryAfter=nil
                if let next=requested {requested=nil;stateLock.unlock();request=next;continue}
                inFlight=false;hasPending=false;stateLock.unlock();group.leave();return
            } catch {
                stateLock.lock()
                let report = !failed
                failed=true;hasPending=true;retryAfter=request.now+Self.saveInterval
                if case ObservationStoreError.writerCapacity=error {disabled=true}
                // An exit request arriving during a failed periodic save gets
                // one bounded retry, bypassing the ordinary 30-second deadline.
                if let next=requested,next.terminating,!request.terminating {
                    requested=nil;stateLock.unlock();request=next;continue
                }
                requested=nil;inFlight=false;stateLock.unlock()
                if report {log("save failed; retained batch will retry: \(error.localizedDescription)")}
                group.leave();return
            }
        }
    }
    private func savePending(lockWait:Double) throws {
        guard let batch=pending else {return}
        read {attempts+=1}
        _ = try store.commit(local:batch.local,baseline:batch.baseline,sequence:batch.sequence,lockWait:lockWait)
        // Baseline is the captured local snapshot, not a merged disk snapshot:
        // another process's counts must not become this process's next delta.
        baseline=batch.local;pending=nil
        read {successes+=1;acknowledged=batch.local;acknowledgedSequence=batch.sequence}
        guard batch.sequence<UInt64.max else {
            read {disabled=true};throw ObservationStoreError.sequenceMismatch
        }
        nextSequence=batch.sequence+1
    }
    static func merge(local:ObservationArchive,baseline:ObservationArchive,disk:ObservationArchive?) throws -> ObservationArchive {
        try ObservationArchive.merging(local:local,baseline:baseline,disk:disk)
    }
    func statusMessage(language:AppLanguage)->String {
        if writesDisabled {
            return language.text("档案暂时只读，原文件已保留。本次新增记录尚未保存。",
                                 "The journal is read-only and the original is preserved. New records have not been saved.")
        }
        if saveFailed {
            return language.text("观鸟记录尚未保存，将稍后重试。", "Observations have not been saved. Saving will be retried.")
        }
        if journal?.capacityExceeded==true {
            return language.text("行为档案容量已满，部分完成事件未记录；已保存记录保持完整。",
                                 "The behavior archive is full. Some completed events were not recorded; existing records remain intact.")
        }
        if isSaving {return language.text("已记录，正在保存…", "Recorded, saving…")}
        if importIssue != nil {
            return language.text("旧 Life List 尚未导入，源文件已保留；行为记录仍可使用。",
                                 "The old Life List is pending import and preserved; behavior records remain available.")
        }
        return ""
    }
}

extension DesktopController {
    func loadObservationJournal(now:Double=ProcessInfo.processInfo.systemUptime) {
        guard observationPersistence == nil else {return}
        let persistence=ObservationJournalPersistence(url:observationJournalURL,enabled:observationJournalPersistenceEnabled,lifeListURL:lifeListURL)
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
