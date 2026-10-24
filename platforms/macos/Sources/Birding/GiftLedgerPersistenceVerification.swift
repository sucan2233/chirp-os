import Foundation
import BirdingCore

/// Isolated native evidence. Main calls worker(arguments:) BEFORE constructing
/// NSApplication; run(into:folder:) launches this same executable twice, not two
/// store objects pretending to be processes. All IO stays under fresh folders.
enum GiftLedgerPersistenceVerification {
    private struct Job:Codable {
        let operation:String
        let seed:UInt64
        let wallTime:Double
        let requestID:String
        let visitorFile:String
    }
    private struct WorkerResult:Codable {
        let processID:Int32
        let namespace:String
        let result:GiftAuthorizationResult?
        let error:String?
    }
    private static let wallTime=2_000_000_000.0
    private static func require(_ condition:Bool,_ message:String) throws {
        if !condition {throw NSError(domain:"GiftLedgerPersistenceVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    }
    private static func root(_ folder:URL,_ name:String) throws -> URL {
        let value=folder.appendingPathComponent("gift-ledger-\(name)-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:value,withIntermediateDirectories:true)
        return value
    }
    private static func learned(seed:UInt64=73,visits:Int=3) throws -> VisitorMemoryArchive {
        let memory=VisitorMemory(seed:seed)
        guard let first=memory.acquire(species:.azureWingedMagpie) else {throw GiftLedgerError.denied(.notEligible)}
        for _ in 0..<4000 {memory.learn(first.id,elapsed:0.05)}
        for _ in 1..<visits {memory.release(first.id);_=memory.acquire(species:.azureWingedMagpie)}
        return memory.archive
    }
    private static func request(_ archive:VisitorMemoryArchive,id:String="1",source:BehaviorSource = .automatic)->GiftAuthorizationRequest {
        .init(binding:.init(requestID:id,visitorArchiveSeed:archive.seed,visitorID:archive.profiles[0].id,
            birdID:BirdID(1),species:.azureWingedMagpie,source:source,leafID:ScenePropID(1),receiverSlot:1,receiverRevision:1))
    }
    private static func wait(_ seconds:Double,until predicate:()->Bool)->Bool {
        let end=ProcessInfo.processInfo.systemUptime+seconds
        while !predicate(),ProcessInfo.processInfo.systemUptime<end {
            _=RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.005))
        }
        return predicate()
    }

    /// CLI: --gift-ledger-worker /absolute/isolated/gift-ledger-.../job.json
    /// Exit status is nil when not requested; no controller, rendering or real
    /// default persistence path is accessed by this helper.
    static func worker(arguments:[String]=CommandLine.arguments)->Int32? {
        guard let index=arguments.firstIndex(of:"--gift-ledger-worker") else {return nil}
        guard index+1<arguments.count,arguments[index+1].hasPrefix("/") else {return 2}
        let jobURL=URL(fileURLWithPath:arguments[index+1]).standardizedFileURL
        let directory=jobURL.deletingLastPathComponent().resolvingSymlinksInPath()
        guard directory.lastPathComponent.hasPrefix("gift-ledger-"),
              directory != GiftLedgerPersistence.defaultURL.deletingLastPathComponent().resolvingSymlinksInPath() else {return 2}
        let output=jobURL.appendingPathExtension("result.json")
        do {
            let job=try JSONDecoder().decode(Job.self,from:GiftLedgerFileAccess.read(jobURL,maximumBytes:4096))
            try require(["bootstrap","grant"].contains(job.operation) && job.wallTime.isFinite &&
                ["visitors.json","visitors-0.json","visitors-1.json"].contains(job.visitorFile),"invalid worker job")
            try Data().write(to:jobURL.appendingPathExtension("ready"),options:.atomic)
            let barrier=directory.appendingPathComponent("go")
            let deadline=ProcessInfo.processInfo.systemUptime+10
            while !FileManager.default.fileExists(atPath:barrier.path),ProcessInfo.processInfo.systemUptime<deadline {
                Thread.sleep(forTimeInterval:0.005)
            }
            try require(FileManager.default.fileExists(atPath:barrier.path),"worker barrier timeout")
            let engine=BehaviorEngine(seed:job.seed)
            let visitors=VisitorMemoryPersistence(url:directory.appendingPathComponent(job.visitorFile),
                enabled:true,arguments:["Birding","--verify-gift-ledger"],log:{_ in})
            visitors.load(into:engine,now:0)
            try require(visitors.giftNamespaceAvailable,"visitor namespace unavailable")
            var authorization:GiftAuthorizationResult?
            if job.operation == "grant" {
                let archive=engine.visitorMemoryArchive
                guard let identity=visitors.giftIdentitySnapshot(archive:archive),!archive.profiles.isEmpty else {
                    throw GiftLedgerError.denied(.namespaceUnavailable)
                }
                authorization=identity.authorize(request(archive,id:job.requestID),
                    store:GiftLedgerStore(url:directory.appendingPathComponent("gifts.json")),
                    deadline:ProcessInfo.processInfo.systemUptime+5,
                    clock:.init(wallTime:{job.wallTime},monotonicTime:{ProcessInfo.processInfo.systemUptime}))
            }
            let value=WorkerResult(processID:ProcessInfo.processInfo.processIdentifier,
                namespace:engine.visitorMemoryArchive.seed,result:authorization,error:nil)
            try JSONEncoder().encode(value).write(to:output,options:.atomic)
            return 0
        } catch {
            let value=WorkerResult(processID:ProcessInfo.processInfo.processIdentifier,namespace:"",result:nil,error:String(describing:error))
            try? JSONEncoder().encode(value).write(to:output,options:.atomic)
            return 1
        }
    }

    private static func pair(in directory:URL,operation:String,differentNamespaces:Bool=false) throws -> [WorkerResult] {
        guard let executable=Bundle.main.executableURL else {throw GiftLedgerError.denied(.storageUnavailable)}
        var children:[Process]=[],jobs:[URL]=[]
        defer {for child in children where child.isRunning {child.terminate()}}
        for index in 0..<2 {
            let jobURL=directory.appendingPathComponent("worker-\(index).json")
            let visitorFile=operation == "grant" ? "visitors-\(index).json":"visitors.json"
            if operation == "grant" {
                // Independent visitor locks ensure this race exercises the
                // shared ledger's flock, not accidental outer serialization.
                let archive:VisitorMemoryArchive
                if differentNamespaces {archive=try learned(seed:UInt64(73+index))}
                else {archive=try VisitorMemoryArchive.load(from:directory.appendingPathComponent("visitors.json"))}
                try archive.save(to:directory.appendingPathComponent(visitorFile))
            }
            let job=Job(operation:operation,seed:UInt64(700+index),wallTime:wallTime,requestID:String(index+1),visitorFile:visitorFile)
            try JSONEncoder().encode(job).write(to:jobURL,options:.atomic)
            let child=Process();child.executableURL=executable
            child.arguments=["--gift-ledger-worker",jobURL.path]
            child.standardOutput=FileHandle.nullDevice;child.standardError=FileHandle.nullDevice
            try child.run();children.append(child);jobs.append(jobURL)
        }
        try require(wait(5,until:{jobs.allSatisfy{FileManager.default.fileExists(atPath:$0.appendingPathExtension("ready").path)}}),"both worker processes must reach the barrier")
        try Data().write(to:directory.appendingPathComponent("go"),options:.atomic)
        try require(wait(10,until:{children.allSatisfy{!$0.isRunning}}),"workers must terminate")
        try require(children.allSatisfy{$0.terminationStatus==0},"worker failed")
        return try jobs.map {try JSONDecoder().decode(WorkerResult.self,from:Data(contentsOf:$0.appendingPathExtension("result.json")))}
    }

    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let bootstrap=try root(folder,"bootstrap")
        let created=try pair(in:bootstrap,operation:"bootstrap")
        let shared=try VisitorMemoryArchive.load(from:bootstrap.appendingPathComponent("visitors.json"))
        checks["giftLedgerTwoRealProcessesCreateOneStableNamespace"]=Set(created.map(\.processID)).count==2 &&
            created.allSatisfy{$0.namespace==shared.seed && $0.error==nil} && shared.profiles.isEmpty

        let contest=try root(folder,"contest"),archive=try learned()
        try archive.save(to:contest.appendingPathComponent("visitors.json"))
        let raced=try pair(in:contest,operation:"grant")
        let results=raced.compactMap(\.result)
        checks["giftLedgerTwoRealProcessesGrantExactlyOnce"]=Set(raced.map(\.processID)).count==2 && results.count==2 &&
            results.filter{$0.token != nil}.count==1 && results.filter{$0.denial == .alreadyGranted}.count==1 &&
            results.allSatisfy(\.isValid)
        let ledgerURL=contest.appendingPathComponent("gifts.json")
        checks["giftLedgerCrossProcessTransactionRetainsPermanentKey"]=try GiftLedger.load(from:ledgerURL).grants.count==1
        let retry=GiftLedgerStore(url:ledgerURL).authorize(request(archive,id:"3"),visitorArchive:archive,
            deadline:ProcessInfo.processInfo.systemUptime+5,
            clock:.init(wallTime:{wallTime+2*86_400},monotonicTime:{ProcessInfo.processInfo.systemUptime}))
        checks["giftLedgerDiscardedTokenDoesNotRefundAcrossStoreRestart"]=retry.denial == .alreadyGranted

        let global=try root(folder,"global")
        let globalResults=try pair(in:global,operation:"grant",differentNamespaces:true).compactMap(\.result)
        let globalLedger=try GiftLedger.load(from:global.appendingPathComponent("gifts.json"))
        checks["giftLedgerTwoProcessesDifferentNamespacesShareGlobalCooldown"]=globalResults.count==2 &&
            globalResults.filter{$0.token != nil}.count==1 && globalResults.filter{$0.denial == .globalCooldown}.count==1 &&
            globalLedger.grants.count==1

        try checkNamespaces(into:&checks,folder:folder)
        try checkBridge(into:&checks,folder:folder)
        try checkCancellationConcurrency(into:&checks,folder:folder)
    }

    private static func checkNamespaces(into checks:inout [String:Bool],folder:URL) throws {
        let directory=try root(folder,"identity"),url=directory.appendingPathComponent("visitors.json")
        let first=BehaviorEngine(seed:73),second=BehaviorEngine(seed:999)
        let a=VisitorMemoryPersistence(url:url,enabled:true,arguments:["Birding","--verify-settings"],log:{_ in})
        let b=VisitorMemoryPersistence(url:url,enabled:true,arguments:["Birding","--verify-settings"],log:{_ in})
        a.load(into:first,now:0);b.load(into:second,now:0)
        checks["giftNamespaceFirstCreationAdoptedBeforeRegistration"]=a.bootstrapCreated && !b.bootstrapCreated &&
            first.visitorMemoryArchive==second.visitorMemoryArchive && second.visitorMemoryArchive.seed=="73" &&
            first.residentCount==0 && second.residentCount==0
        let accepted=try learned(),stale=try learned(visits:4)
        try first.restoreVisitorMemory(accepted);try second.restoreVisitorMemory(stale)
        a.flush(from:first,now:1)
        let bytes=try Data(contentsOf:url)
        b.flush(from:second,now:1)
        let afterStale=try Data(contentsOf:url)
        checks["giftNamespaceOldInstanceCannotOverwriteNewPersistentIdentities"]=a.successfulSaves==1 &&
            b.successfulSaves==0 && afterStale==bytes
        let failed=b.giftIdentitySnapshot(archive:stale)?.authorize(request(stale),
            store:GiftLedgerStore(url:directory.appendingPathComponent("gifts.json")),
            deadline:ProcessInfo.processInfo.systemUptime+5,clock:.live)
        checks["giftNamespaceStaleGiftSnapshotRefusesQuotaConsumption"]=failed?.denial == .namespaceUnavailable &&
            !FileManager.default.fileExists(atPath:directory.appendingPathComponent("gifts.json").path)

        for (name,data) in [("future",Data("{\"version\":99}".utf8)),("corrupt",Data("broken".utf8))] {
            let badURL=directory.appendingPathComponent(name+".json");try data.write(to:badURL)
            let engine=BehaviorEngine(seed:5)
            let persistence=VisitorMemoryPersistence(url:badURL,enabled:true,arguments:["Birding"],log:{_ in})
            persistence.load(into:engine,now:0)
            let retained=try Data(contentsOf:badURL)
            checks["giftNamespace\(name)RefusesTemporarySeedAndPreservesBytes"]=persistence.writesDisabled &&
                !persistence.giftNamespaceAvailable && persistence.giftIdentitySnapshot(archive:engine.visitorMemoryArchive)==nil &&
                retained==data
        }

        let recordingEngine=BehaviorEngine(seed:8,recordInputs:true)
        let readonly=VisitorMemoryPersistence(url:url,arguments:["Birding","--record-behavior"],log:{_ in})
        readonly.load(into:recordingEngine,now:0)
        let recordingResult=readonly.giftIdentitySnapshot(archive:accepted)?.authorize(request(accepted),
            store:GiftLedgerStore(url:directory.appendingPathComponent("recording-gifts.json")),
            deadline:ProcessInfo.processInfo.systemUptime+5,clock:.live)
        let afterRecording=try Data(contentsOf:url)
        checks["giftRecordingCanAuthorizeDurableIdentityWithoutWritingVisitorArchive"] = !readonly.writesEnabled &&
            recordingResult?.token != nil && afterRecording==bytes

        let emptyURL=directory.appendingPathComponent("empty-visitors.json")
        try VisitorMemory(seed:73).archive.save(to:emptyURL)
        let freshRecording=BehaviorEngine(seed:73)
        let emptyReader=VisitorMemoryPersistence(url:emptyURL,arguments:["Birding","--record-behavior"],log:{_ in})
        emptyReader.load(into:freshRecording,now:0)
        let temporaryLedger=directory.appendingPathComponent("temporary-gifts.json")
        let unpersisted=emptyReader.giftIdentitySnapshot(archive:accepted)?.authorize(request(accepted),
            store:GiftLedgerStore(url:temporaryLedger),deadline:ProcessInfo.processInfo.systemUptime+5,clock:.live)
        checks["giftRecordingCannotAuthorizeUnpersistedVisitorID"]=unpersisted?.denial == .namespaceUnavailable &&
            !FileManager.default.fileExists(atPath:temporaryLedger.path)
    }

    private static func checkCancellationConcurrency(into checks:inout [String:Bool],folder:URL) throws {
        try require(Thread.isMainThread,"cancellation checks collect callbacks on main")
        func drainCallbacks(_ message:String) throws {
            // Called after the worker barrier: include every already-enqueued
            // callback, so an extra delivery cannot hide behind the first one.
            var drained=false
            DispatchQueue.main.async {drained=true}
            try require(wait(1,until:{drained}),message)
        }
        let directory=try root(folder,"cancel-race"),archive=try learned()
        let visitorURL=directory.appendingPathComponent("visitors.json")
        try archive.save(to:visitorURL)
        let engine=BehaviorEngine(seed:73)
        let visitors=VisitorMemoryPersistence(url:visitorURL,enabled:true,arguments:["Birding"],log:{_ in})
        visitors.load(into:engine,now:0)

        // Hold a real transaction inside its locked clock read, then cancel it.
        // Keep B queued while A finishes, so C must still observe B as busy.
        let entered=DispatchSemaphore(value:0),releaseTransaction=DispatchSemaphore(value:0)
        let betweenEntered=DispatchSemaphore(value:0),releaseNext=DispatchSemaphore(value:0)
        defer {releaseTransaction.signal();releaseNext.signal()}
        let queue=DispatchQueue(label:"GiftLedgerVerification.cancel-in-flight")
        let url=directory.appendingPathComponent("in-flight.json")
        let clock=GiftLedgerClock(wallTime:{
            // Only the first transaction is gated; later requests see its grant.
            if !FileManager.default.fileExists(atPath:url.path) {
                entered.signal();_=releaseTransaction.wait(timeout:.now()+4)
            }
            return wallTime
        },monotonicTime:{ProcessInfo.processInfo.systemUptime})
        let bridge=GiftLedgerPersistence(url:url,enabled:true,arguments:["Birding"],workerQueue:queue,clock:clock)
        var results:[String:[GiftAuthorizationResult]]=[:]
        func submit(_ id:String) {
            bridge.request(request(archive,id:id),visitorMemory:visitors,archive:archive) {
                results[id,default:[]].append($0)
            }
        }
        submit("1")
        try require(entered.wait(timeout:.now()+2) == .success,"A must enter a real ledger transaction")
        queue.async {betweenEntered.signal();_=releaseNext.wait(timeout:.now()+4)}
        bridge.cancelPending();bridge.cancelPending()
        submit("2")
        releaseTransaction.signal()
        try require(betweenEntered.wait(timeout:.now()+2) == .success,"A must finish with B still queued")
        submit("3")
        bridge.cancelPending()
        submit("4")
        releaseNext.signal()
        let drained=DispatchSemaphore(value:0);queue.async {drained.signal()}
        try require(drained.wait(timeout:.now()+2) == .success,"replacement worker drain")
        try drainCallbacks("cancel/replacement callbacks")
        let ledger=try GiftLedger.load(from:url)
        checks["giftBridgeCancelledTransactionCannotClearReplacementOrDeliverTwice"]=results.count==4 &&
            results.allSatisfy {id,values in values.count==1 && values[0].isValid && values[0].binding.requestID==id} &&
            results["1"]?.first?.denial == .timedOut && results["2"]?.first?.denial == .timedOut &&
            results["3"]?.first?.denial == .busy && results["4"]?.first?.denial == .alreadyGranted &&
            ledger.grants.count==1 && bridge.blockingDenial==nil

        // Completion wins before cancellation, but main has not delivered it.
        // Cancellation must not replace that result, and B must enter at once.
        let finishedURL=directory.appendingPathComponent("finished.json")
        let finishedQueue=DispatchQueue(label:"GiftLedgerVerification.finish-before-cancel")
        let finished=GiftLedgerPersistence(url:finishedURL,enabled:true,arguments:["Birding"],workerQueue:finishedQueue)
        var won:[GiftAuthorizationResult]=[],replacement:[GiftAuthorizationResult]=[]
        finished.request(request(archive),visitorMemory:visitors,archive:archive) {won.append($0)}
        let finishedWork=DispatchSemaphore(value:0);finishedQueue.async {finishedWork.signal()}
        try require(finishedWork.wait(timeout:.now()+2) == .success,"completion must win before cancel")
        try require(won.isEmpty,"main must still withhold the winning completion")
        finished.cancelPending()
        finished.request(request(archive,id:"2"),visitorMemory:visitors,archive:archive) {replacement.append($0)}
        let replacementWork=DispatchSemaphore(value:0);finishedQueue.async {replacementWork.signal()}
        try require(replacementWork.wait(timeout:.now()+2) == .success,"replacement must finish")
        try drainCallbacks("winning completion callbacks")
        checks["giftBridgeCompletedClaimReleasesPendingBeforeCallbackDelivery"]=won.count==1 && won[0].token != nil &&
            replacement.count==1 && replacement[0].denial == .alreadyGranted

        // In addition to both controlled orders above, race the worker's return
        // against controller cancellation. B is submitted immediately after
        // cancel returns; neither valid winner may leave a transient busy slot.
        var raced=true
        for index in 0..<32 {
            let raceURL=directory.appendingPathComponent("race-\(index).json")
            let raceEntered=DispatchSemaphore(value:0),raceRelease=DispatchSemaphore(value:0)
            defer {raceRelease.signal()}
            let raceClock=GiftLedgerClock(wallTime:{wallTime},monotonicTime:{
                if FileManager.default.fileExists(atPath:raceURL.path),
                   !Thread.isMainThread {
                    raceEntered.signal();_=raceRelease.wait(timeout:.now()+4)
                }
                return ProcessInfo.processInfo.systemUptime
            })
            let raceQueue=DispatchQueue(label:"GiftLedgerVerification.claim-race.\(index)")
            let race=GiftLedgerPersistence(url:raceURL,enabled:true,arguments:["Birding"],workerQueue:raceQueue,clock:raceClock)
            var first:[GiftAuthorizationResult]=[],next:[GiftAuthorizationResult]=[]
            race.request(request(archive),visitorMemory:visitors,archive:archive) {first.append($0)}
            try require(raceEntered.wait(timeout:.now()+2) == .success,"race must reach committed deadline check")
            // B is canceled while the serial worker is gated after A; it should
            // therefore time out by cancellation, never by a false busy denial.
            let holdB=DispatchSemaphore(value:0)
            defer {holdB.signal()}
            raceQueue.async {_=holdB.wait(timeout:.now()+4)}
            raceRelease.signal();race.cancelPending()
            race.request(request(archive,id:"2"),visitorMemory:visitors,archive:archive) {next.append($0)}
            race.cancelPending();holdB.signal()
            let done=DispatchSemaphore(value:0);raceQueue.async {done.signal()}
            try require(done.wait(timeout:.now()+2) == .success,"racing workers must drain")
            try drainCallbacks("racing callbacks")
            let retained=try GiftLedger.load(from:raceURL)
            raced = raced && first.count==1 && first[0].isValid && first[0].binding.requestID=="1" &&
                (first[0].token != nil || first[0].denial == .timedOut) && next.count==1 &&
                next[0].binding.requestID=="2" && next[0].denial == .timedOut && retained.grants.count==1
        }
        checks["giftBridgeConcurrentFinishCancelImmediatelyAdmitsReplacementExactlyOnce"]=raced
    }

    private static func checkBridge(into checks:inout [String:Bool],folder:URL) throws {
        let directory=try root(folder,"bridge"),archive=try learned(),visitorURL=directory.appendingPathComponent("visitors.json")
        try archive.save(to:visitorURL)
        let engine=BehaviorEngine(seed:9)
        let visitors=VisitorMemoryPersistence(url:visitorURL,enabled:true,arguments:["Birding"],log:{_ in})
        visitors.load(into:engine,now:0)
        let futureURL=directory.appendingPathComponent("future.json"),future=Data("{\"version\":99}".utf8)
        try future.write(to:futureURL)
        let protected=GiftLedgerPersistence(url:futureURL,enabled:true,arguments:["Birding","--verify-settings"])
        var protectedResults:[GiftAuthorizationResult]=[]
        protected.request(request(archive),visitorMemory:visitors,archive:archive) {protectedResults.append($0)}
        try require(wait(6,until:{protectedResults.count==1}),"future ledger callback")
        let retainedFuture=try Data(contentsOf:futureURL)
        checks["giftBridgeFutureLedgerStopsAutomaticGiftsWithoutOverwrite"]=protectedResults[0].denial == .unsupportedVersion &&
            protected.blockingDenial == .unsupportedVersion && retainedFuture==future

        let previewURL=directory.appendingPathComponent("preview.json")
        let preview=GiftLedgerPersistence(url:previewURL,enabled:true,arguments:["Birding"])
        var previews:[GiftAuthorizationResult]=[]
        preview.request(request(archive,source:.preview),visitorMemory:visitors,archive:archive) {previews.append($0)}
        try require(wait(1,until:{previews.count==1}),"preview rejection")
        checks["giftBridgePreviewCannotConsumeAutomaticLedger"]=previews[0].denial == .invalidRequest &&
            !FileManager.default.fileExists(atPath:previewURL.path) && !FileManager.default.fileExists(atPath:previewURL.appendingPathExtension("lock").path)

        let queue=DispatchQueue(label:"GiftLedgerVerification.blocked"),gate=DispatchSemaphore(value:0)
        let queueEntered=DispatchSemaphore(value:0)
        queue.async {queueEntered.signal();_=gate.wait(timeout:.now()+10)}
        try require(queueEntered.wait(timeout:.now()+1) == .success,"worker queue gate")
        defer {gate.signal()}
        let timeoutURL=directory.appendingPathComponent("timeout.json")
        let timeout=GiftLedgerPersistence(url:timeoutURL,enabled:true,arguments:["Birding"],workerQueue:queue)
        var timeouts:[GiftAuthorizationResult]=[],busy:[GiftAuthorizationResult]=[]
        let began=ProcessInfo.processInfo.systemUptime
        timeout.request(request(archive),visitorMemory:visitors,archive:archive) {timeouts.append($0)}
        timeout.request(request(archive,id:"2"),visitorMemory:visitors,archive:archive) {busy.append($0)}
        try require(wait(6,until:{timeouts.count==1 && busy.count==1}),"queued deadline callbacks")
        let elapsed=ProcessInfo.processInfo.systemUptime-began
        gate.signal();let drained=DispatchSemaphore(value:0);queue.async {drained.signal()}
        try require(drained.wait(timeout:.now()+2) == .success,"late worker drain")
        _=wait(0.1,until:{false})
        checks["giftBridgeFiveSecondsIncludesQueueAndDeliversOnce"]=timeouts.count==1 && timeouts[0].denial == .timedOut &&
            busy.count==1 && busy[0].denial == .busy && elapsed>=4.9 && elapsed<6 &&
            !FileManager.default.fileExists(atPath:timeoutURL.path)

        let lateURL=directory.appendingPathComponent("late.json"),origin=ProcessInfo.processInfo.systemUptime
        let lateClock=GiftLedgerClock(wallTime:{wallTime},monotonicTime:{
            FileManager.default.fileExists(atPath:lateURL.path) ? origin+6:origin
        })
        let late=GiftLedgerPersistence(url:lateURL,enabled:true,arguments:["Birding"],clock:lateClock)
        var lateResults:[GiftAuthorizationResult]=[]
        late.request(request(archive),visitorMemory:visitors,archive:archive) {lateResults.append($0)}
        try require(wait(6,until:{lateResults.count==1}),"commit/deadline race callback")
        let consumed=try GiftLedger.load(from:lateURL)
        checks["giftBridgeCommitDeadlineRaceRetainsQuotaWithoutToken"]=lateResults[0].denial == .timedOut &&
            lateResults[0].token==nil && consumed.grants.count==1

        // Exercise actual main-queue congestion separately from a deadline
        // crossing inside atomic IO. The worker must finish before the deadline,
        // but its queued result cannot run until main resumes after five seconds.
        try require(Thread.isMainThread,"native bridge checks require main queue")
        let deliveryURL=directory.appendingPathComponent("delivery-expired.json")
        let deliveryQueue=DispatchQueue(label:"GiftLedgerVerification.delivery")
        let delivery=GiftLedgerPersistence(url:deliveryURL,enabled:true,arguments:["Birding"],workerQueue:deliveryQueue)
        var deliveries:[GiftAuthorizationResult]=[]
        let deliveryBegan=ProcessInfo.processInfo.systemUptime
        delivery.request(request(archive),visitorMemory:visitors,archive:archive) {deliveries.append($0)}
        let workDone=DispatchSemaphore(value:0);deliveryQueue.async {workDone.signal()}
        try require(workDone.wait(timeout:.now()+4) == .success,"worker must commit before delivery timeout")
        let beforeDelivery=try GiftLedger.load(from:deliveryURL)
        try require(deliveries.isEmpty && beforeDelivery.grants.count==1 &&
            ProcessInfo.processInfo.systemUptime-deliveryBegan<5,"main must still be withholding a committed result")
        Thread.sleep(forTimeInterval:max(0,deliveryBegan+5.05-ProcessInfo.processInfo.systemUptime))
        try require(wait(1,until:{deliveries.count==1}),"expired main delivery")
        let afterDelivery=try GiftLedger.load(from:deliveryURL)
        checks["giftBridgeMainQueueExpiryRetainsCommittedQuotaAndReturnsOnlyTimeout"]=deliveries.count==1 &&
            deliveries[0].denial == .timedOut && deliveries[0].token==nil && afterDelivery==beforeDelivery

        let cancelQueue=DispatchQueue(label:"GiftLedgerVerification.cancel"),cancelGate=DispatchSemaphore(value:0)
        cancelQueue.async {_=cancelGate.wait(timeout:.now()+5)}
        defer {cancelGate.signal()}
        let cancelURL=directory.appendingPathComponent("cancelled.json")
        let cancelled=GiftLedgerPersistence(url:cancelURL,enabled:true,arguments:["Birding"],workerQueue:cancelQueue)
        var cancellations:[GiftAuthorizationResult]=[]
        cancelled.request(request(archive),visitorMemory:visitors,archive:archive) {cancellations.append($0)}
        cancelled.cancelPending();cancelled.cancelPending()
        try require(wait(1,until:{cancellations.count==1}),"cancellation callback")
        cancelGate.signal();let cancelDrained=DispatchSemaphore(value:0);cancelQueue.async {cancelDrained.signal()}
        try require(cancelDrained.wait(timeout:.now()+2) == .success,"cancelled worker drain")
        _=wait(0.1,until:{false})
        checks["giftBridgeCancellationDeliversOnceAndQueuedWorkCannotGrant"]=cancellations.count==1 &&
            cancellations[0].denial == .timedOut && !FileManager.default.fileExists(atPath:cancelURL.path)

        let stagedDirectory=try root(folder,"staged-identity"),stagedURL=stagedDirectory.appendingPathComponent("visitors.json")
        let stagedEngine=BehaviorEngine(seed:73)
        let stagedVisitors=VisitorMemoryPersistence(url:stagedURL,enabled:true,arguments:["Birding"],log:{_ in})
        stagedVisitors.load(into:stagedEngine,now:0);try stagedEngine.restoreVisitorMemory(archive)
        let staged=GiftLedgerPersistence(url:stagedDirectory.appendingPathComponent("gifts.json"),enabled:true,arguments:["Birding"])
        var stagedResults:[GiftAuthorizationResult]=[]
        staged.request(request(archive),visitorMemory:stagedVisitors,archive:archive) {stagedResults.append($0)}
        try require(wait(6,until:{stagedResults.count==1}),"persistent identity before grant")
        let durable=try VisitorMemoryArchive.load(from:stagedURL)
        checks["giftBridgePersistsSelectedIdentityBeforeEmittingToken"]=stagedResults[0].token != nil && durable==archive

        for flag in ["--verify-gifts","--stress-behavior","--fixture","--integration","--replay-behavior","--export-art","--gift-ledger-worker"] {
            let isolatedURL=directory.appendingPathComponent("disabled-\(flag.dropFirst(2)).json")
            let disabled=GiftLedgerPersistence(url:isolatedURL,arguments:["Birding",flag])
            let protectedDefault=GiftLedgerPersistence(enabled:true,arguments:["Birding",flag])
            checks["giftBridgeDefaultIsolation\(flag.dropFirst(2))"] = !disabled.enabled && !protectedDefault.enabled &&
                !VisitorMemoryPersistence.automaticEnabled(arguments:["Birding",flag]) &&
                !FileManager.default.fileExists(atPath:isolatedURL.path)
        }
    }
}
