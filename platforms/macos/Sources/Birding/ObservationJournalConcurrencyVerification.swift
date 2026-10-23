import Foundation
import Darwin
import BirdingCore

enum ObservationJournalConcurrencyVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let root=folder.appendingPathComponent("journal-concurrency-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent("observations.json")
        let first=Date(timeIntervalSince1970:1_790_000_000)
        let initial=ObservationArchive(entries:[ObservationEntry(species:.treeSparrow,behavior:"rest",
            firstSeen:first,lastSeen:first,automaticCount:1)])
        try initial.save(to:url)
        let a=ObservationJournal(),b=ObservationJournal()
        let pa=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{_ in})
        let pb=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{_ in})
        pa.load(into:a,now:0);pb.load(into:b,now:0)
        func event(_ sequence:UInt64,_ kind:BehaviorKind,_ source:BehaviorSource)->BehaviorObservation {
            BehaviorObservation(sequence:sequence,simulationTime:Double(sequence),kind:kind,source:source,
                species:[.treeSparrow],runID:sequence)
        }
        a.observe(event(1,.rest,.automatic),at:first.addingTimeInterval(10))
        a.observe(event(2,.edgePeek,.preview),at:first.addingTimeInterval(20))
        b.observe(event(1,.rest,.user),at:first.addingTimeInterval(30))
        b.observe(event(2,.flockPass,.automatic),at:first.addingTimeInterval(40))
        pa.flush(from:a,now:1);pb.flush(from:b,now:1)
        let combined=try ObservationArchive.load(from:url)
        let rest=combined.entries.first{$0.behavior=="rest"}
        checks["journalConcurrentSnapshotsPreserveBothInstances"]=combined.entries.count==3 &&
            rest?.automaticCount==2 && rest?.userCount==1 && rest?.previewCount==0 &&
            combined.entries.first{$0.behavior=="edgePeek"}?.previewCount==1 &&
            combined.entries.first{$0.behavior=="flockPass"}?.automaticCount==1
        checks["journalConcurrentDatesKeepEarliestAndLatest"]=rest?.firstSeen==first && rest?.lastSeen==first.addingTimeInterval(30)
        a.observe(event(3,.rest,.automatic),at:first.addingTimeInterval(50))
        pa.flush(from:a,now:2);pb.flush(from:b,now:2)
        let next=try ObservationArchive.load(from:url)
        checks["journalConcurrentFlushAddsOnlyUnsavedDelta"]=next.entries.count==3 &&
            next.entries.first{$0.behavior=="rest"}?.automaticCount==3 &&
            next.entries.first{$0.behavior=="rest"}?.userCount==1 && pa.successfulSaves==2 && pb.successfulSaves==1
        let reloaded=ObservationJournal()
        let reader=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{_ in})
        reader.load(into:reloaded,now:0)
        checks["journalNextLaunchReadsMergedDiscoveryCounts"]=reloaded.archive==next

        // Exercise the OS lock using a separate open file description. The UI
        // owner's flush must return instead of blocking on another process.
        let descriptor=Darwin.open(url.path+".lock",O_RDWR|O_CLOEXEC)
        guard descriptor>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        defer {Darwin.close(descriptor)}
        guard flock(descriptor,LOCK_EX|LOCK_NB)==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        defer {_ = flock(descriptor,LOCK_UN)}
        b.observe(event(3,.rest,.preview),at:first.addingTimeInterval(60))
        let before=try Data(contentsOf:url)
        let started=ProcessInfo.processInfo.systemUptime
        pb.flush(from:b,now:3)
        let elapsed=ProcessInfo.processInfo.systemUptime-started
        let blocked=try Data(contentsOf:url)
        checks["journalLockContentionIsNonblockingAndPreservesFile"]=elapsed<1 && pb.saveFailed &&
            pb.saveAttempts==2 && pb.successfulSaves==1 && before==blocked
        _ = flock(descriptor,LOCK_UN)
        pb.flush(from:b,now:4)
        checks["journalLockContentionUsesBoundedRetry"]=pb.saveAttempts==2
        pb.flush(from:b,now:5,terminating:true)
        checks["journalExitBypassesPeriodicRetryDeadline"]=pb.successfulSaves==2
        let recovered=try ObservationArchive.load(from:url)
        checks["journalLockRetryRetainsEverySourceCount"] = !pb.saveFailed && pb.successfulSaves==2 &&
            recovered.entries.first{$0.behavior=="rest"}?.automaticCount==3 &&
            recovered.entries.first{$0.behavior=="rest"}?.userCount==1 &&
            recovered.entries.first{$0.behavior=="rest"}?.previewCount==1
        guard flock(descriptor,LOCK_EX|LOCK_NB)==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        b.observe(event(4,.rest,.preview),at:first.addingTimeInterval(70))
        let exitStarted=ProcessInfo.processInfo.systemUptime
        pb.flush(from:b,now:6,terminating:true)
        let exitElapsed=ProcessInfo.processInfo.systemUptime-exitStarted
        checks["journalExitLockWaitIsBounded"]=exitElapsed>=0.45 && exitElapsed<1.5 && pb.saveFailed
        _ = flock(descriptor,LOCK_UN)
        pb.flush(from:b,now:7,terminating:true)
        checks["journalExitRetryPreservesPendingDelta"] = try ObservationArchive.load(from:url)
            .entries.first{$0.behavior=="rest"}?.previewCount==2
    }
}
