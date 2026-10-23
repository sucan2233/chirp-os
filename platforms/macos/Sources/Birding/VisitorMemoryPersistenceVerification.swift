import Foundation
import BirdingCore

enum VisitorMemoryPersistenceVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let files=FileManager.default
        let root=folder.appendingPathComponent("visitor-memory-"+UUID().uuidString,isDirectory:true)
        try files.createDirectory(at:root,withIntermediateDirectories:true)
        // No probe, snapshot, read, or write of the real user archive is needed.
        // Every enabled instance below is explicitly pointed into this directory.
        let userURL=VisitorMemoryPersistence.defaultURL
        checks["visitorPersistenceEvidenceUsesIsolatedDirectory"]=root.standardizedFileURL != userURL.deletingLastPathComponent().standardizedFileURL
        let archive=sampleArchive()

        let missingURL=root.appendingPathComponent("missing/visitors.json")
        var missingLogs:[String]=[]
        let missing=VisitorMemoryPersistence(url:missingURL,enabled:true,log:{missingLogs.append($0)})
        let empty=BehaviorEngine(seed:73),initial=empty.visitorMemoryArchive
        checks["visitorPersistenceConstructionDoesNotCreateFiles"] = !files.fileExists(atPath:missingURL.deletingLastPathComponent().path) && !missing.loaded
        missing.load(into:empty,now:0)
        missing.persistIfNeeded(from:empty,now:30)
        missing.flush(from:empty,now:31)
        checks["visitorPersistenceMissingFileStartsEmptyWithoutWriting"]=empty.visitorMemoryArchive==initial &&
            !missing.writesDisabled && missingLogs.isEmpty && missing.saveAttempts==0 && !files.fileExists(atPath:missingURL.path)

        // Restore a learned core archive after the missing-file bootstrap. No
        // platform code invents identity, counters, or familiarity values.
        try empty.restoreVisitorMemory(archive)
        missing.flush(from:empty,now:32)
        let loaded=try VisitorMemoryArchive.load(from:missingURL)
        let reloadedEngine=BehaviorEngine(seed:999)
        let reloaded=VisitorMemoryPersistence(url:missingURL,enabled:true)
        reloaded.load(into:reloadedEngine,now:0)
        checks["visitorPersistenceSaveReloadThroughEngineAndArchive"]=missing.successfulSaves==1 && loaded==archive &&
            reloadedEngine.visitorMemoryArchive==archive && !reloaded.writesDisabled
        let returning=bird()
        reloadedEngine.installFixtureBirds([returning])
        let visitor=reloadedEngine.visitor(of:returning),previous=archive.profiles.first
        checks["visitorPersistenceReloadRetainsIdentityFamiliarityAndVisits"]=visitor != nil &&
            visitor?.id==previous?.id && visitor?.familiarity==previous?.familiarity &&
            visitor?.visits==(previous?.visits ?? 0)+1

        // Exercise the actual controller injection and scheduling entry points,
        // without start(), windows, timers, or the user's settings file.
        let desktop=DesktopController()
        desktop.visitorMemoryPersistenceEnabled=true
        desktop.visitorMemoryURL=root.appendingPathComponent("desktop/visitors.json")
        checks["visitorPersistenceDesktopInitDoesNotLoad"]=desktop.visitorMemoryPersistence==nil
        desktop.loadVisitorMemory(now:0)
        desktop.birds=[bird()]
        let dirty=desktop.engine.visitorMemoryArchive
        for frame in 1..<1800 {desktop.persistVisitorMemoryIfNeeded(now:Double(frame)/60)}
        checks["visitorPersistenceNoImmediateOrPerFrameWrites"]=desktop.visitorMemoryPersistence?.saveAttempts==0 &&
            !files.fileExists(atPath:desktop.visitorMemoryURL.path)
        desktop.persistVisitorMemoryIfNeeded(now:30)
        let periodicSaved=try VisitorMemoryArchive.load(from:desktop.visitorMemoryURL)
        checks["visitorPersistenceDirtyArchiveSavesAtThirtySeconds"]=desktop.visitorMemoryPersistence?.successfulSaves==1 &&
            periodicSaved==dirty
        for frame in 1801...5400 {desktop.persistVisitorMemoryIfNeeded(now:Double(frame)/60)}
        desktop.flushVisitorMemory()
        checks["visitorPersistenceUnchangedArchiveSkipsPeriodicAndExitWrites"]=desktop.visitorMemoryPersistence?.saveAttempts==1
        desktop.birds=[];desktop.birds=[bird()]
        let finalArchive=desktop.engine.visitorMemoryArchive
        desktop.flushVisitorMemory()
        let exitSaved=try VisitorMemoryArchive.load(from:desktop.visitorMemoryURL)
        checks["visitorPersistenceExitFlushSavesDirtyArchive"]=desktop.visitorMemoryPersistence?.successfulSaves==2 &&
            exitSaved==finalArchive
        let beforeDisabling=try Data(contentsOf:desktop.visitorMemoryURL)
        var disabledSettings=desktop.settings;disabledSettings.visitorMemoryEnabled=false
        desktop.settings=disabledSettings
        desktop.flushVisitorMemory()
        let afterDisabling=try Data(contentsOf:desktop.visitorMemoryURL)
        checks["visitorPersistenceSettingsOffRetainsPriorArchive"]=desktop.engine.visitorMemoryArchive==finalArchive &&
            afterDisabling==beforeDisabling &&
            desktop.visitorMemoryPersistence?.saveAttempts==2

        let invalidFiles:[(String,Data)]=[
            ("future",Data("{\"version\":2147483647,\"futureFormat\":true}".utf8)),
            ("corrupt",Data("{\"version\":1,\"profiles\":".utf8))
        ]
        for (name,bytes) in invalidFiles {
            let url=root.appendingPathComponent("boot-\(name).json")
            try bytes.write(to:url,options:.atomic)
            var logs:[String]=[]
            let engine=BehaviorEngine(seed:73)
            let persistence=VisitorMemoryPersistence(url:url,enabled:true,log:{logs.append($0)})
            persistence.load(into:engine,now:0)
            engine.installFixtureBirds([bird()])
            persistence.load(into:engine,now:1)
            for time in [30.0,60,90] {
                persistence.persistIfNeeded(from:engine,now:time)
                persistence.flush(from:engine,now:time)
            }
            let bootRetained=try Data(contentsOf:url)
            checks["visitorPersistence\(name.capitalized)BootFileRetainedAndSessionWritesDisabled"]=persistence.writesDisabled &&
                persistence.saveAttempts==0 && logs.count==1 && bootRetained==bytes

            let replacementURL=root.appendingPathComponent("replacement-\(name).json")
            try archive.save(to:replacementURL)
            let running=BehaviorEngine(seed:73)
            var retryLogs:[String]=[]
            let replacement=VisitorMemoryPersistence(url:replacementURL,enabled:true,log:{retryLogs.append($0)})
            replacement.load(into:running,now:0)
            running.installFixtureBirds([bird()])
            try bytes.write(to:replacementURL,options:.atomic)
            replacement.persistIfNeeded(from:running,now:30)
            for frame in 1..<1800 {
                let now=30+Double(frame)/60
                replacement.persistIfNeeded(from:running,now:now)
                replacement.flush(from:running,now:now)
            }
            let firstRetained=try Data(contentsOf:replacementURL)
            checks["visitorPersistence\(name.capitalized)MidrunReplacementRetainedWithBoundedRetry"]=replacement.saveAttempts==1 &&
                replacement.successfulSaves==0 && retryLogs.count==1 && firstRetained==bytes
            replacement.persistIfNeeded(from:running,now:60)
            let retryRetained=try Data(contentsOf:replacementURL)
            checks["visitorPersistence\(name.capitalized)RetriesWithoutLogSpam"]=replacement.saveAttempts==2 &&
                retryLogs.count==1 && retryRetained==bytes
        }

        let protectedFlags=["--verify-settings","--verify-anything","--integration","--fixture","--stress-behavior","--stress-other"]
        for (index,flag) in protectedFlags.enumerated() {
            let url=root.appendingPathComponent("disabled-\(index).json")
            let sentinel=Data("untouched verification sentinel".utf8)
            try sentinel.write(to:url)
            let engine=BehaviorEngine(seed:73)
            var logs:[String]=[]
            let persistence=VisitorMemoryPersistence(url:url,arguments:["Birding",flag],log:{logs.append($0)})
            persistence.load(into:engine,now:0);engine.installFixtureBirds([bird()])
            persistence.persistIfNeeded(from:engine,now:30);persistence.flush(from:engine,now:31)
            let retained=try Data(contentsOf:url)
            checks["visitorPersistenceDisabledMode\(flag.dropFirst(2))"] = !persistence.enabled &&
                persistence.saveAttempts==0 && logs.isEmpty && retained==sentinel
        }
        let explicitlyDisabled=VisitorMemoryPersistence(url:root.appendingPathComponent("explicit-disabled.json"),enabled:false,arguments:["Birding"])
        explicitlyDisabled.load(into:empty,now:0);explicitlyDisabled.flush(from:empty,now:30)
        checks["visitorPersistenceExplicitDisableDoesNotTouchDisk"]=explicitlyDisabled.saveAttempts==0 &&
            !files.fileExists(atPath:explicitlyDisabled.url.path)
        let protected=VisitorMemoryPersistence(url:userURL,enabled:true,arguments:["Birding","--verify-settings"])
        protected.load(into:empty,now:0);protected.flush(from:empty,now:30)
        checks["visitorPersistenceVerifierCannotEnableUserArchive"] = !protected.enabled && !protected.writesDisabled && protected.saveAttempts==0
        let isolated=VisitorMemoryPersistence(url:root.appendingPathComponent("explicit-override.json"),enabled:true,arguments:["Birding","--verify-settings"])
        let isolatedEngine=BehaviorEngine(seed:73)
        isolated.load(into:isolatedEngine,now:0);isolatedEngine.installFixtureBirds([bird()])
        isolated.flush(from:isolatedEngine,now:1)
        checks["visitorPersistenceVerifierAllowsExplicitIsolatedOverride"]=isolated.enabled && isolated.successfulSaves==1

        let recordingURL=root.appendingPathComponent("recording-readonly.json")
        try archive.save(to:recordingURL)
        let beforeRecording=try Data(contentsOf:recordingURL)
        let recordingEngine=BehaviorEngine(seed:999,recordInputs:true)
        let recording=VisitorMemoryPersistence(url:recordingURL,arguments:["Birding","--record-behavior"])
        recording.load(into:recordingEngine,now:0)
        let restored=recordingEngine.visitorMemoryArchive
        let restoreRecorded=try recordingEngine.recordedInputs().inputs.contains{$0.kind == "visitorMemory" && $0.visitorMemory==archive}
        recordingEngine.installFixtureBirds([bird()])
        recording.persistIfNeeded(from:recordingEngine,now:30);recording.flush(from:recordingEngine,now:31)
        let afterRecording=try Data(contentsOf:recordingURL)
        checks["visitorPersistenceRecordingLoadsAndRecordsRestoreButNeverWrites"]=recording.enabled && !recording.writesEnabled &&
            restored==archive && restoreRecorded && recordingEngine.visitorMemoryArchive != archive &&
            recording.saveAttempts==0 && afterRecording==beforeRecording

        // A regular file in place of the parent directory forces a real IO
        // failure even when the verifier runs with elevated filesystem access.
        let blocker=root.appendingPathComponent("blocked-parent")
        let failureURL=blocker.appendingPathComponent("visitors.json")
        let failureEngine=BehaviorEngine(seed:73)
        var failureLogs:[String]=[]
        let failure=VisitorMemoryPersistence(url:failureURL,enabled:true,log:{failureLogs.append($0)})
        failure.load(into:failureEngine,now:0);failureEngine.installFixtureBirds([bird()])
        let expected=failureEngine.visitorMemoryArchive,sentinel=Data("retain this file".utf8)
        try sentinel.write(to:blocker)
        failure.persistIfNeeded(from:failureEngine,now:30)
        for frame in 1..<1800 {failure.flush(from:failureEngine,now:30+Double(frame)/60)}
        let retainedBlocker=try Data(contentsOf:blocker)
        checks["visitorPersistenceWriteFailureLeavesExistingBytesAndCoreUnchanged"]=failure.saveAttempts==1 &&
            failure.successfulSaves==0 && failureLogs.count==1 && retainedBlocker==sentinel &&
            failureEngine.visitorMemoryArchive==expected
        try files.removeItem(at:blocker)
        failure.persistIfNeeded(from:failureEngine,now:60)
        let recoveredArchive=try VisitorMemoryArchive.load(from:failureURL)
        checks["visitorPersistenceWriteFailureRecoversAtNextBoundedRetry"]=failure.saveAttempts==2 && failure.successfulSaves==1 &&
            recoveredArchive==expected
    }

    private static func bird() -> Bird {
        Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
    }
    private static func sampleArchive() -> VisitorMemoryArchive {
        let memory=VisitorMemory(seed:73)
        if let visitor=memory.acquire(species:.treeSparrow) {
            for _ in 0..<60 {memory.learn(visitor.id,elapsed:0.05)}
            memory.release(visitor.id)
        }
        return memory.archive
    }
}
