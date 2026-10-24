import Foundation
import BirdingCore

/// Native persistence checks use only caller-owned evidence files. No controller
/// is started, so settings, visitor archives, timers and desktop UI stay inert.
enum ObservationJournalPersistenceVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let files=FileManager.default
        let root=folder.appendingPathComponent("observation-journal-"+UUID().uuidString,isDirectory:true)
        try files.createDirectory(at:root,withIntermediateDirectories:true)
        // Computing this URL is safe; never stat, read, load or flush that path.
        let userURL=ObservationJournalPersistence.defaultURL
        checks["observationPersistenceEvidenceUsesIsolatedDirectory"]=root.standardizedFileURL != userURL.deletingLastPathComponent().standardizedFileURL
        let archive=sampleArchive()

        let missingURL=root.appendingPathComponent("missing/observations.json")
        let journal=ObservationJournal(),initial=journal.archive
        var missingLogs:[String]=[]
        let missing=ObservationJournalPersistence(url:missingURL,enabled:true,arguments:["Birding"],log:{missingLogs.append($0)})
        checks["observationPersistenceConstructionDoesNotCreateFiles"] = !missing.loaded &&
            !files.fileExists(atPath:missingURL.deletingLastPathComponent().path)
        missing.load(into:journal,now:0)
        for time in [30.0,60,90] {missing.persistIfNeeded(from:journal,now:time)}
        missing.flush(from:journal,now:91)
        checks["observationPersistenceMissingFileStartsEmptyWithoutWriting"]=missing.loaded &&
            journal.archive==initial && journal.archive.entries.isEmpty && !missing.writesDisabled &&
            missing.saveAttempts==0 && missingLogs.isEmpty && !files.fileExists(atPath:missingURL.path)
        try journal.restore(archive)
        missing.flush(from:journal,now:92)
        let stored=try ObservationArchive.load(from:missingURL)
        let restored=ObservationJournal()
        let reload=ObservationJournalPersistence(url:missingURL,enabled:true,arguments:["Birding"],log:{_ in})
        reload.load(into:restored,now:0)
        checks["observationPersistenceSaveReloadThroughJournalAndArchive"]=missing.successfulSaves==1 &&
            stored==archive && restored.archive==archive && !reload.writesDisabled
        let entry=restored.archive.entries.first
        checks["observationPersistenceReloadRetainsRealDatesAndDistinctSourceCounts"]=restored.archive.entries.count==1 &&
            entry?.species == .treeSparrow && entry?.behavior == BehaviorKind.rest.rawValue &&
            entry?.firstSeen==firstSeen && entry?.lastSeen==lastSeen &&
            entry?.automaticCount==2 && entry?.previewCount==3 && entry?.userCount==1 && entry?.totalCount==6
        let object=try JSONSerialization.jsonObject(with:Data(contentsOf:missingURL)) as? [String:Any]
        checks["observationPersistenceSavesVersionTwoEnvelope"]=(object?["formatVersion"] as? Int)==2 &&
            (object?["entries"] as? [Any])?.count==1

        try checkMigration(into:&checks,root:root,archive:archive)
        try checkDesktop(into:&checks,root:root)
        try checkProtectedFiles(into:&checks,root:root,archive:archive)
        try checkModes(into:&checks,root:root,userURL:userURL)
        try checkFailureRecovery(into:&checks,root:root)
    }

    private static func checkMigration(into checks:inout [String:Bool],root:URL,archive:ObservationArchive) throws {
        for (name,source) in [("Populated",archive),("Empty",ObservationArchive())] {
            let legacy=try envelope(source,version:1)
            for terminating in [false,true] {
                let mode=terminating ? "Exit":"Periodic"
                let url=root.appendingPathComponent("migration-\(name)-\(mode).json")
                try legacy.write(to:url,options:.atomic)
                let journal=ObservationJournal()
                var logs:[String]=[]
                let persistence=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{logs.append($0)})
                persistence.load(into:journal,now:0)
                let baseline=journal.archive,revision=journal.revision
                let loadedBytes=try Data(contentsOf:url)
                checks["observationPersistenceV1\(name)\(mode)LoadPreservesBytes"]=baseline==source &&
                    baseline.formatVersion==2 && !persistence.writesDisabled && persistence.saveAttempts==0 &&
                    loadedBytes==legacy && logs.isEmpty
                persistence.persistIfNeeded(from:journal,now:29.999)
                let beforeDeadline=try Data(contentsOf:url)
                checks["observationPersistenceV1\(name)\(mode)MigrationWaitsForSave"]=persistence.saveAttempts==0 &&
                    beforeDeadline==legacy
                if terminating {persistence.flush(from:journal,now:29.999,terminating:true)}
                else {persistence.persistIfNeeded(from:journal,now:30)}
                let storedBytes=try Data(contentsOf:url)
                let stored=try ObservationArchive.decode(storedBytes)
                let object=try JSONSerialization.jsonObject(with:storedBytes) as? [String:Any]
                checks["observationPersistenceV1\(name)\(mode)MigratesWithoutNewObservations"]=persistence.successfulSaves==1 &&
                    persistence.saveAttempts==1 && (object?["formatVersion"] as? Int)==2 &&
                    !stored.requiresMigration && stored==source && journal.archive==baseline &&
                    journal.revision==revision && logs.isEmpty
                persistence.persistIfNeeded(from:journal,now:60)
                persistence.flush(from:journal,now:61,terminating:true)
                let unchanged=try Data(contentsOf:url)
                checks["observationPersistenceV1\(name)\(mode)MigrationWritesOnlyOnce"]=persistence.saveAttempts==1 &&
                    unchanged==storedBytes
                let restored=ObservationJournal()
                let reload=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{logs.append($0)})
                reload.load(into:restored,now:0)
                reload.persistIfNeeded(from:restored,now:30)
                reload.flush(from:restored,now:31,terminating:true)
                checks["observationPersistenceV1\(name)\(mode)ReloadIsClean"]=restored.archive==source &&
                    !reload.writesDisabled && reload.saveAttempts==0 && logs.isEmpty
            }

            // Migration itself is a pending write, even without a new event.
            // A newer process may replace the file after our v1 load.
            let url=root.appendingPathComponent("migration-\(name)-future-replacement.json")
            try legacy.write(to:url,options:.atomic)
            let journal=ObservationJournal()
            var logs:[String]=[]
            let persistence=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{logs.append($0)})
            persistence.load(into:journal,now:0)
            let baseline=journal.archive,revision=journal.revision
            let future=try envelope(source,version:ObservationArchive.currentVersion+1)
            try future.write(to:url,options:.atomic)
            persistence.persistIfNeeded(from:journal,now:30)
            persistence.flush(from:journal,now:59.999)
            let preserved=try Data(contentsOf:url)
            checks["observationPersistenceV1\(name)MigrationPreservesFutureReplacement"]=persistence.saveAttempts==1 &&
                persistence.successfulSaves==0 && persistence.saveFailed && logs.count==1 &&
                preserved==future && journal.archive==baseline && journal.revision==revision
            persistence.persistIfNeeded(from:journal,now:60)
            persistence.flush(from:journal,now:61,terminating:true)
            let retried=try Data(contentsOf:url)
            checks["observationPersistenceV1\(name)MigrationRetryAndExitPreserveFuture"]=persistence.saveAttempts==3 &&
                persistence.successfulSaves==0 && persistence.saveFailed && logs.count==1 &&
                retried==future && journal.archive==baseline && journal.revision==revision
        }
    }

    private static func envelope(_ archive:ObservationArchive,version:Int) throws -> Data {
        let encoded=try JSONEncoder().encode(archive)
        var object=try JSONSerialization.jsonObject(with:encoded) as? [String:Any] ?? [:]
        object["formatVersion"]=version
        return try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])
    }

    private static func checkDesktop(into checks:inout [String:Bool],root:URL) throws {
        let files=FileManager.default
        let suite="Birding.ObservationJournalPersistenceVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {
            throw NSError(domain:"ObservationJournalPersistenceVerification",code:1,
                          userInfo:[NSLocalizedDescriptionKey:"Could not create isolated preferences."])
        }
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=DesktopController()
        d.preferences=preferences
        d.settingsURL=root.appendingPathComponent("desktop/settings.json")
        d.legacyURL=root.appendingPathComponent("desktop/legacy.json")
        d.visitorMemoryURL=root.appendingPathComponent("desktop/visitors.json")
        d.visitorMemoryPersistenceEnabled=false
        d.observationJournalURL=root.appendingPathComponent("desktop/observations.json")
        d.observationJournalPersistenceEnabled=true
        d.observationDate={firstSeen}
        d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        checks["observationPersistenceDesktopInitDoesNotLoad"]=d.observationPersistence==nil &&
            d.visitorMemoryPersistence==nil && d.observationJournal.archive.entries.isEmpty
        d.loadObservationJournal(now:0)
        let persistence=d.observationPersistence
        d.loadObservationJournal(now:1)
        checks["observationPersistenceDesktopLoadIsIdempotent"]=d.observationPersistence === persistence &&
            persistence?.loaded==true && d.engine.observationObserver != nil

        // A synthetic world avoids screen enumeration and live pointer input.
        // The observation itself comes from a genuinely completed engine run.
        let screen=CGRect(x:-1200,y:-400,width:3000,height:1800)
        let host=Surface(id:9871,rect:CGRect(x:-900,y:800,width:2300,height:400))
        d.engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],
            pointer:CGPoint(x:0,y:0),availableFrames:[.treeSparrow:["stand","blink"]]))
        let bird=Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host);bird.perchDuration=600
        d.birds=[bird]
        let started=d.engine.handle(.perchAction(.rest,.preview))
        let runID:BehaviorRunID?
        if case .started(let id)=started {runID=id} else {runID=nil}
        checks["observationPersistenceDesktopStartsWithoutRecordingDiscovery"]=runID != nil &&
            d.observationJournal.archive.entries.isEmpty && persistence?.saveAttempts==0
        let rejected=d.engine.handle(.perchAction(.rest,.preview))
        checks["observationPersistenceDesktopRejectedRunDoesNotDiscover"]=rejected == .rejected(.busy) &&
            d.observationJournal.archive.entries.isEmpty
        for _ in 0..<360 {d.engine.advance(BehaviorEngine.step)}
        let completion=d.engine.events.filter{$0.runID==runID && $0.type == .completed && $0.kind == .rest}
        let entry=d.observationJournal.archive.entries.first
        let dirty=d.observationJournal.archive
        checks["observationPersistenceDesktopObserverReceivesTrueEngineCompletion"]=completion.count==1 &&
            completion.first?.source == .preview && dirty.entries.count==1 &&
            entry?.species == .treeSparrow && entry?.behavior == BehaviorKind.rest.rawValue && entry?.previewCount==1 &&
            entry?.automaticCount==0 && entry?.userCount==0 && entry?.totalCount==1 &&
            entry?.firstSeen==firstSeen && entry?.lastSeen==firstSeen && d.observationJournal.revision>0
        let cancelled=d.engine.handle(.perchAction(.rest,.preview))
        d.engine.handle(.cancelAmbient(.sleep))
        for _ in 0..<360 {d.engine.advance(BehaviorEngine.step)}
        let cancelledID:BehaviorRunID?
        if case .started(let id)=cancelled {cancelledID=id} else {cancelledID=nil}
        checks["observationPersistenceDesktopCancelledRunDoesNotDiscover"]=cancelledID != nil &&
            d.engine.events.contains{$0.runID==cancelledID && $0.type == .cancelled} &&
            d.observationJournal.archive==dirty

        for frame in 1..<1800 {d.persistObservationJournalIfNeeded(now:Double(frame)/60)}
        checks["observationPersistenceNoImmediateOrPerFrameWrites"]=persistence?.saveAttempts==0 &&
            !files.fileExists(atPath:d.observationJournalURL.path)
        d.persistObservationJournalIfNeeded(now:30)
        let periodic=try ObservationArchive.load(from:d.observationJournalURL)
        checks["observationPersistenceDirtyArchiveSavesAtThirtySeconds"]=persistence?.successfulSaves==1 && periodic==dirty
        for frame in 1801...5400 {d.persistObservationJournalIfNeeded(now:Double(frame)/60)}
        d.flushObservationJournal()
        checks["observationPersistenceUnchangedArchiveSkipsPeriodicAndExitWrites"]=persistence?.saveAttempts==1
        _ = d.observationJournal.observe(observation(sequence:10_000,source:.user),at:lastSeen)
        let finalArchive=d.observationJournal.archive
        d.flushObservationJournal()
        let exitSaved=try ObservationArchive.load(from:d.observationJournalURL)
        d.flushObservationJournal()
        checks["observationPersistenceExitFlushSavesDirtyArchiveOnce"]=finalArchive != dirty &&
            persistence?.successfulSaves==2 && persistence?.saveAttempts==2 && exitSaved==finalArchive
        checks["observationPersistenceDesktopStaysHeadlessAndPopulationDisabled"]=d.timer==nil &&
            d.panels.isEmpty && d.views.isEmpty && d.status==nil && d.statusLine==nil &&
            d.settingsWindow==nil && d.observationWindow==nil && d.gallery==nil &&
            !d.engine.populationEnabled && !d.engine.ambientEnabled && !d.engine.autonomousRouting &&
            d.arrivalCount==0 && d.departureCount==0 && d.birds.count==1
        checks["observationPersistenceDesktopDoesNotTouchSettingsOrVisitors"]=d.visitorMemoryPersistence==nil &&
            !files.fileExists(atPath:d.settingsURL.path) && !files.fileExists(atPath:d.legacyURL.path) &&
            !files.fileExists(atPath:d.visitorMemoryURL.path)
    }

    private static func checkProtectedFiles(into checks:inout [String:Bool],root:URL,archive:ObservationArchive) throws {
        // Derive a future envelope from a valid file so only its version changes.
        let sampleURL=root.appendingPathComponent("version-template.json")
        try archive.save(to:sampleURL)
        var future=try JSONSerialization.jsonObject(with:Data(contentsOf:sampleURL)) as? [String:Any] ?? [:]
        future["formatVersion"]=ObservationArchive.currentVersion+1
        let invalid:[(String,Data)]=[
            ("Future",try JSONSerialization.data(withJSONObject:future,options:[.sortedKeys])),
            ("Corrupt",Data("{\"formatVersion\":1,\"entries\":".utf8))
        ]
        for (name,bytes) in invalid {
            let url=root.appendingPathComponent("boot-\(name).json")
            try bytes.write(to:url,options:.atomic)
            let journal=ObservationJournal()
            var logs:[String]=[]
            let persistence=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{logs.append($0)})
            persistence.load(into:journal,now:0)
            let emptyAfterLoad=journal.archive.entries.isEmpty
            _ = journal.observe(observation(sequence:1,source:.automatic),at:firstSeen)
            persistence.load(into:journal,now:1)
            for time in [30.0,60,90] {
                persistence.persistIfNeeded(from:journal,now:time)
                persistence.flush(from:journal,now:time)
            }
            let bootBytes=try Data(contentsOf:url)
            checks["observationPersistence\(name)BootPreservesBytesAndDisablesWrites"]=emptyAfterLoad &&
                persistence.writesDisabled && persistence.saveAttempts==0 && logs.count==1 && bootBytes==bytes &&
                journal.archive.entries.first?.automaticCount==1

            let replacementURL=root.appendingPathComponent("replacement-\(name).json")
            try archive.save(to:replacementURL)
            let running=ObservationJournal()
            var retryLogs:[String]=[]
            let replacement=ObservationJournalPersistence(url:replacementURL,enabled:true,arguments:["Birding"],log:{retryLogs.append($0)})
            replacement.load(into:running,now:0)
            _ = running.observe(observation(sequence:10_000,source:.user),at:lastSeen.addingTimeInterval(1))
            let dirty=running.archive
            try bytes.write(to:replacementURL,options:.atomic)
            replacement.persistIfNeeded(from:running,now:30)
            for frame in 1..<1800 {
                let now=30+Double(frame)/60
                replacement.persistIfNeeded(from:running,now:now)
                replacement.flush(from:running,now:now)
            }
            let firstBytes=try Data(contentsOf:replacementURL)
            checks["observationPersistence\(name)MidrunReplacementPreservesBytesWithBoundedRetry"]=replacement.saveAttempts==1 &&
                replacement.successfulSaves==0 && replacement.saveFailed && retryLogs.count==1 &&
                firstBytes==bytes && running.archive==dirty
            replacement.persistIfNeeded(from:running,now:60)
            let retriedBytes=try Data(contentsOf:replacementURL)
            checks["observationPersistence\(name)RetryDoesNotOverwriteOrSpamLogs"]=replacement.saveAttempts==2 &&
                replacement.successfulSaves==0 && retryLogs.count==1 && retriedBytes==bytes && running.archive==dirty
        }
    }

    private static func checkModes(into checks:inout [String:Bool],root:URL,userURL:URL) throws {
        let flags=["--record-behavior","--record-behavior=isolated.json","--replay-behavior","--replay-behavior=isolated.json",
                   "--verify-settings","--verify-anything","--verify-settings=isolated","--stress-behavior","--stress-other",
                   "--stress-behavior=73","--integration","--integration=isolated","--fixture","--fixture=isolated"]
        for (index,flag) in flags.enumerated() {
            let url=root.appendingPathComponent("disabled-\(index).json")
            let sentinel=Data("untouched isolated observation sentinel".utf8)
            try sentinel.write(to:url)
            let journal=ObservationJournal()
            var logs:[String]=[]
            let persistence=ObservationJournalPersistence(url:url,arguments:["Birding",flag],log:{logs.append($0)})
            persistence.load(into:journal,now:0)
            _ = journal.observe(observation(sequence:1,source:.preview),at:firstSeen)
            persistence.persistIfNeeded(from:journal,now:30);persistence.flush(from:journal,now:31)
            let retained=try Data(contentsOf:url)
            checks["observationPersistenceDisabledMode-\(index)-\(flag.dropFirst(2))"] = !persistence.enabled &&
                !ObservationJournalPersistence.automaticEnabled(arguments:["Birding",flag]) &&
                !persistence.writesDisabled && persistence.saveAttempts==0 && logs.isEmpty && retained==sentinel

            // Only inspect construction for the real path. Calling load here
            // would weaken the isolation guarantee if its enable guard regressed.
            let protected=ObservationJournalPersistence(url:userURL,enabled:true,arguments:["Birding",flag],log:{_ in})
            checks["observationPersistenceRealPathOverrideBlockedWithoutLoading-\(index)"] = !protected.enabled &&
                !protected.loaded && protected.saveAttempts==0

            let isolatedOverride=ObservationJournalPersistence(url:root.appendingPathComponent("override-\(index).json"),
                enabled:true,arguments:["Birding",flag],log:{_ in})
            let isolated=ObservationJournal()
            isolatedOverride.load(into:isolated,now:0)
            _ = isolated.observe(observation(sequence:1,source:.preview),at:firstSeen)
            isolatedOverride.flush(from:isolated,now:1)
            let overridden=try ObservationArchive.load(from:isolatedOverride.url)
            checks["observationPersistenceExplicitIsolatedOverrideAllowed-\(index)"]=isolatedOverride.enabled &&
                !isolatedOverride.writesDisabled && isolatedOverride.successfulSaves==1 && overridden==isolated.archive
        }
        let disabled=ObservationJournalPersistence(url:root.appendingPathComponent("explicit-disabled.json"),
            enabled:false,arguments:["Birding"],log:{_ in})
        let journal=ObservationJournal()
        disabled.load(into:journal,now:0)
        _ = journal.observe(observation(sequence:1,source:.automatic),at:firstSeen)
        disabled.persistIfNeeded(from:journal,now:30);disabled.flush(from:journal,now:31)
        checks["observationPersistenceExplicitDisableDoesNotTouchDisk"] = !disabled.enabled &&
            disabled.saveAttempts==0 && !FileManager.default.fileExists(atPath:disabled.url.path)
        checks["observationPersistenceNormalLaunchEnabledByDefault"]=ObservationJournalPersistence.automaticEnabled(arguments:["Birding"])
    }

    private static func checkFailureRecovery(into checks:inout [String:Bool],root:URL) throws {
        let files=FileManager.default
        let blocker=root.appendingPathComponent("blocked-parent")
        let url=blocker.appendingPathComponent("observations.json")
        let journal=ObservationJournal()
        var logs:[String]=[]
        let persistence=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{logs.append($0)})
        persistence.load(into:journal,now:0)
        _ = journal.observe(observation(sequence:1,source:.automatic),at:firstSeen)
        let dirty=journal.archive,sentinel=Data("retain this file".utf8)
        // A file as the parent forces IO failure even with elevated privileges.
        try sentinel.write(to:blocker)
        persistence.persistIfNeeded(from:journal,now:30)
        for frame in 1..<1800 {
            let now=30+Double(frame)/60
            persistence.persistIfNeeded(from:journal,now:now)
            persistence.flush(from:journal,now:now)
        }
        let retained=try Data(contentsOf:blocker)
        checks["observationPersistenceIOFailurePreservesBytesAndJournalWithBoundedRetry"]=persistence.saveAttempts==1 &&
            persistence.successfulSaves==0 && persistence.saveFailed && logs.count==1 &&
            retained==sentinel && journal.archive==dirty
        persistence.persistIfNeeded(from:journal,now:60)
        let retried=try Data(contentsOf:blocker)
        checks["observationPersistencePersistentIOFailureRetriesWithoutLogSpam"]=persistence.saveAttempts==2 &&
            persistence.successfulSaves==0 && logs.count==1 && retried==sentinel
        try files.removeItem(at:blocker)
        persistence.flush(from:journal,now:89.999)
        checks["observationPersistenceRecoveryStillRespectsRetryDeadline"]=persistence.saveAttempts==2 &&
            !files.fileExists(atPath:url.path)
        persistence.persistIfNeeded(from:journal,now:90)
        let recovered=try ObservationArchive.load(from:url)
        checks["observationPersistenceIOFailureRecoversAtNextBoundedRetry"]=persistence.saveAttempts==3 &&
            persistence.successfulSaves==1 && !persistence.saveFailed && !persistence.writesDisabled &&
            recovered==dirty && journal.archive==dirty
        persistence.persistIfNeeded(from:journal,now:120);persistence.flush(from:journal,now:121)
        checks["observationPersistenceRecoveredCleanArchiveSkipsWrites"]=persistence.saveAttempts==3 && logs.count==1
    }

    private static let firstSeen=Date(timeIntervalSince1970:1_761_234_567)
    private static let lastSeen=firstSeen.addingTimeInterval(2*24*60*60)

    private static func observation(sequence:UInt64,source:BehaviorSource)->BehaviorObservation {
        BehaviorObservation(sequence:sequence,simulationTime:Double(sequence)/60,kind:.rest,
                            source:source,species:[.treeSparrow],runID:sequence)
    }

    private static func sampleArchive()->ObservationArchive {
        let journal=ObservationJournal()
        let sources:[BehaviorSource]=[.automatic,.preview,.user,.preview,.automatic,.preview]
        for (index,source) in sources.enumerated() {
            _ = journal.observe(observation(sequence:UInt64(index+1),source:source),
                at:index==sources.count-1 ? lastSeen:firstSeen.addingTimeInterval(Double(index)*60))
        }
        return journal.archive
    }
}
