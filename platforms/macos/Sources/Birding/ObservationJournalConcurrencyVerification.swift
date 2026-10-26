import Foundation
import Darwin
import BirdingCore

enum ObservationJournalConcurrencyVerification {
    private static func settle(_ persistence:ObservationJournalPersistence) throws {
        _=persistence.waitForPendingSaves(timeout:3)
        guard !persistence.isSaving else {
            throw NSError(domain:"ObservationJournalConcurrencyVerification",code:1,
                          userInfo:[NSLocalizedDescriptionKey:"Observation save worker did not finish"])
        }
    }
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
        a.recordManual(species:.treeSparrow,at:first);b.recordManual(species:.treeSparrow,at:first)
        // Both journals loaded the same baseline. Serialize completion here to
        // specifically test stale-snapshot merging, independently of lock retry.
        pa.flush(from:a,now:1);try settle(pa)
        pb.flush(from:b,now:1);try settle(pb)
        let combined=try ObservationArchive.load(from:url)
        let rest=combined.entries.first{$0.behavior=="rest"}
        checks["journalConcurrentSnapshotsPreserveBothInstances"]=combined.entries.count==3 &&
            rest?.automaticCount==2 && rest?.userCount==1 && rest?.previewCount==0 &&
            combined.entries.first{$0.behavior=="edgePeek"}?.previewCount==1 &&
            combined.entries.first{$0.behavior=="flockPass"}?.automaticCount==1
        checks["journalConcurrentManualDeltasStaySeparate"]=combined.speciesRecord(for:.treeSparrow)?.manualCount==2
        checks["journalConcurrentDatesKeepEarliestAndLatest"]=rest?.firstSeen==first && rest?.lastSeen==first.addingTimeInterval(30)
        let lockPath=url.path+".lock"
        let inode=try FileManager.default.attributesOfItem(atPath:lockPath)[.systemFileNumber] as? NSNumber
        a.observe(event(3,.rest,.automatic),at:first.addingTimeInterval(50))
        pa.flush(from:a,now:2);try settle(pa)
        pb.flush(from:b,now:2);try settle(pb)
        let next=try ObservationArchive.load(from:url)
        checks["journalConcurrentFlushAddsOnlyUnsavedDelta"]=next.entries.count==3 &&
            next.entries.first{$0.behavior=="rest"}?.automaticCount==3 &&
            next.entries.first{$0.behavior=="rest"}?.userCount==1 && pa.successfulSaves==2 && pb.successfulSaves==1
        let reloaded=ObservationJournal()
        let reader=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{_ in})
        reader.load(into:reloaded,now:0)
        checks["journalNextLaunchReadsMergedDiscoveryCounts"]=reloaded.archive==next
        let sameInode=try FileManager.default.attributesOfItem(atPath:lockPath)[.systemFileNumber] as? NSNumber
        checks["journalSidecarLockSurvivesAtomicReplacement"]=inode != nil && inode==sameInode

        let descriptor=Darwin.open(lockPath,O_RDWR|O_CLOEXEC)
        guard descriptor>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        defer {Darwin.close(descriptor)}
        guard flock(descriptor,LOCK_EX|LOCK_NB)==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        defer {_ = flock(descriptor,LOCK_UN)}
        b.observe(event(3,.rest,.preview),at:first.addingTimeInterval(60))
        let before=try Data(contentsOf:url)
        let started=ProcessInfo.processInfo.systemUptime
        pb.flush(from:b,now:3)
        let elapsed=ProcessInfo.processInfo.systemUptime-started
        try settle(pb)
        let blocked=try Data(contentsOf:url)
        checks["journalLockContentionIsNonblockingAndPreservesFile"]=elapsed<1 && pb.saveFailed &&
            pb.saveAttempts==2 && pb.successfulSaves==1 && before==blocked
        _ = flock(descriptor,LOCK_UN)
        pb.flush(from:b,now:4);try settle(pb)
        checks["journalLockContentionUsesBoundedRetry"]=pb.saveAttempts==2
        pb.flush(from:b,now:5,terminating:true);try settle(pb)
        checks["journalExitBypassesPeriodicRetryDeadline"]=pb.successfulSaves==2
        let recovered=try ObservationArchive.load(from:url)
        checks["journalLockRetryRetainsEverySourceCount"] = !pb.saveFailed && pb.successfulSaves==2 &&
            recovered.entries.first{$0.behavior=="rest"}?.automaticCount==3 &&
            recovered.entries.first{$0.behavior=="rest"}?.userCount==1 &&
            recovered.entries.first{$0.behavior=="rest"}?.previewCount==1
        checks["journalExitStopsNewManualAndBehaviorRecords"] = !b.acceptingRecords &&
            !b.recordManual(species:.treeSparrow,at:first) && !b.observe(event(4,.rest,.preview),at:first)

        // A separate live session exercises the second exit; stopped journals
        // cannot manufacture a new pending delta after shutdown.
        let c=ObservationJournal()
        let pc=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{_ in})
        pc.load(into:c,now:0)
        let added=c.observe(event(1,.rest,.preview),at:first.addingTimeInterval(70))
        guard flock(descriptor,LOCK_EX|LOCK_NB)==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        let exitStarted=ProcessInfo.processInfo.systemUptime
        pc.flush(from:c,now:6,terminating:true)
        let exitElapsed=ProcessInfo.processInfo.systemUptime-exitStarted
        try settle(pc)
        checks["journalExitLockWaitIsBounded"]=added && exitElapsed>=0.45 && exitElapsed<1.5 && pc.saveFailed
        _ = flock(descriptor,LOCK_UN)
        pc.flush(from:c,now:7,terminating:true);try settle(pc)
        let final=try ObservationArchive.load(from:url)
        checks["journalExitRetryPreservesPendingDelta"] = final.entries.first{$0.behavior=="rest"}?.previewCount==2 &&
            pc.lastSavedSequence==1 && pc.successfulSaves==1 && !pc.saveFailed
        let writerDirectory=URL(fileURLWithPath:url.path+".writers",isDirectory:true)
        let slots=try FileManager.default.contentsOfDirectory(atPath:writerDirectory.path)
        checks["journalWriterSidecarsAreBoundedAndIsolated"]=slots.count<=ObservationArchive.maximumWriters &&
            slots.allSatisfy{$0.hasPrefix("slot-") && $0.hasSuffix(".lock")} &&
            pa.sidecarURLs.allSatisfy{$0.path.hasPrefix(root.path+"/")} && final.writerProgress.count==3
        try checkReleasedLease(into:&checks,url:url,date:first)
        try checkPendingNewEvents(into:&checks,root:root,date:first)
        withExtendedLifetime((pa,pb,pc)) {}
    }
    private static func checkReleasedLease(into checks:inout [String:Bool],url:URL,date:Date) throws {
        let before=try ObservationArchive.load(from:url).writerProgress.map(\.writerID)
        let journal=ObservationJournal()
        var owner:ObservationJournalPersistence?=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{_ in})
        owner!.load(into:journal,now:0);journal.recordManual(species:.treeSparrow,at:date)
        owner!.flush(from:journal,now:1);try settle(owner!)
        let after=try ObservationArchive.load(from:url)
        guard let progress=after.writerProgress.first(where:{!before.contains($0.writerID)}) else {
            throw ObservationJournalError.invalid("lease verification writer never committed")
        }
        let path=url.path+".writers/slot-\(progress.slot).lock"
        let fd=Darwin.open(path,O_RDWR|O_CLOEXEC)
        guard fd>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        defer {Darwin.close(fd)}
        let held=flock(fd,LOCK_EX|LOCK_NB) != 0
        owner=nil
        // Completion can precede release of the queue closure's last reference.
        // Retry only lock acquisition, never remove/replace the lock file.
        let deadline=ProcessInfo.processInfo.systemUptime+0.5
        var acquired=false
        repeat {
            acquired=flock(fd,LOCK_EX|LOCK_NB)==0
            if !acquired {Thread.sleep(forTimeInterval:0.005)}
        } while !acquired && ProcessInfo.processInfo.systemUptime<deadline
        checks["journalWriterLeaseHeldUntilOwnerEnds"]=held && acquired
        if acquired {_=flock(fd,LOCK_UN)}
    }
    private static func checkPendingNewEvents(into checks:inout [String:Bool],root:URL,date:Date) throws {
        let url=root.appendingPathComponent("pending-new-events.json")
        try ObservationArchive().save(to:url)
        let journal=ObservationJournal(),p=ObservationJournalPersistence(url:url,enabled:true,arguments:["Birding"],log:{_ in})
        p.load(into:journal,now:0)
        let fd=Darwin.open(url.path+".lock",O_RDWR|O_CLOEXEC)
        guard fd>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        defer {Darwin.close(fd)}
        guard flock(fd,LOCK_EX|LOCK_NB)==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        journal.recordManual(species:.treeSparrow,at:date)
        p.flush(from:journal,now:1);try settle(p)
        let failed=p.saveFailed
        journal.recordManual(species:.treeSparrow,at:date.addingTimeInterval(1))
        _=flock(fd,LOCK_UN)
        p.flush(from:journal,now:31);try settle(p)
        let saved=try ObservationArchive.load(from:url)
        checks["journalNewEventsDuringFailedSaveSurviveOrderedRetry"]=failed && !p.saveFailed &&
            saved.speciesRecord(for:.treeSparrow)?.manualCount==2 && p.lastSavedSequence==2 && p.successfulSaves==2
    }
}
