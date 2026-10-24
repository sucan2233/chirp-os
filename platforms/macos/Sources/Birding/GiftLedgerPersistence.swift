import Foundation
import BirdingCore

/// Async adapter only: Desktop owns forwarding the result to the engine's
/// recorded input boundary. Neither IO workers nor timeout workers touch Engine.
final class GiftLedgerPersistence {
    static let authorizationTimeout:Double=5
    static var defaultURL:URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Birding/gifts.json")
    }
    private final class Pending {
        let request:GiftAuthorizationRequest
        let deadline:Double
        let completion:(GiftAuthorizationResult)->Void
        init(_ request:GiftAuthorizationRequest,deadline:Double,completion:@escaping(GiftAuthorizationResult)->Void) {
            self.request=request;self.deadline=deadline;self.completion=completion
        }
    }
    let store:GiftLedgerStore
    let enabled:Bool
    private let workerQueue:DispatchQueue
    private let resultQueue:DispatchQueue
    private let timeoutQueue=DispatchQueue(label:"Birding.gift-ledger.timeout",qos:.utility)
    private let clock:GiftLedgerClock
    private let lock=NSLock()
    private var pending:Pending?
    private var stoppedReason:GiftAuthorizationDenial?
    var blockingDenial:GiftAuthorizationDenial? {lock.lock();defer {lock.unlock()};return stoppedReason}

    init(url:URL=GiftLedgerPersistence.defaultURL,enabled:Bool?=nil,
         arguments:[String]=CommandLine.arguments,
         workerQueue:DispatchQueue=DispatchQueue(label:"Birding.gift-ledger.io",qos:.utility),
         resultQueue:DispatchQueue = .main,clock:GiftLedgerClock = .live) {
        store=GiftLedgerStore(url:url);self.workerQueue=workerQueue;self.resultQueue=resultQueue;self.clock=clock
        let automatic=VisitorMemoryPersistence.automaticEnabled(arguments:arguments) &&
            !arguments.contains(where:{$0.hasPrefix("--replay-") || $0.hasPrefix("--gift-ledger-worker")})
        self.enabled=(enabled ?? automatic) && (automatic || url.standardizedFileURL != Self.defaultURL.standardizedFileURL)
    }

    /// Invoke on the controller thread to snapshot visitor persistence state.
    /// Deadline starts before queueing. A rejected/disabled call still receives
    /// exactly one asynchronous result, and never reads or writes a ledger.
    func request(_ request:GiftAuthorizationRequest,visitorMemory:VisitorMemoryPersistence,
                 archive:VisitorMemoryArchive,completion:@escaping(GiftAuthorizationResult)->Void) {
        let began=clock.monotonicTime()
        func reject(_ reason:GiftAuthorizationDenial) {
            resultQueue.async {completion(.init(denied:request.binding,reason:reason))}
        }
        guard request.binding.isValid,request.binding.source == .automatic else {reject(.invalidRequest);return}
        guard enabled else {reject(.storageUnavailable);return}
        guard began.isFinite else {reject(.timedOut);return}
        lock.lock()
        if let reason=stoppedReason {lock.unlock();reject(reason);return}
        if pending != nil {lock.unlock();reject(.busy);return}
        let item=Pending(request,deadline:began+Self.authorizationTimeout,completion:completion)
        pending=item;lock.unlock()
        guard let identity=visitorMemory.giftIdentitySnapshot(archive:archive) else {
            finish(item,result:.init(denied:request.binding,reason:.namespaceUnavailable));return
        }
        timeoutQueue.asyncAfter(deadline:.now()+Self.authorizationTimeout) { [self,item] in
            finish(item,result:.init(denied:request.binding,reason:.timedOut))
        }
        workerQueue.async { [self,item,identity] in
            guard isPending(item) else {return}
            let result=identity.authorize(request,store:store,deadline:item.deadline,clock:clock)
            finish(item,result:result)
        }
    }

    /// Engine invalidates its request first. This adapter cannot undo a transaction
    /// already committing on another queue; late consumption is never refunded.
    func cancelPending() {
        lock.lock()
        guard let item=pending else {lock.unlock();return}
        let result=GiftAuthorizationResult(denied:item.request.binding,reason:.timedOut)
        let claimed=claimLocked(item,result:result)
        lock.unlock()
        if claimed {deliver(item,result:result)}
    }

    private func isPending(_ item:Pending)->Bool {
        lock.lock();defer {lock.unlock()};return pending === item
    }

    /// Requires lock. Pending identity is also the completion claim: removing it
    /// and admitting the next request are one transition. An old worker/timeout
    /// cannot clear a replacement request or change its blocking state.
    private func claimLocked(_ item:Pending,result:GiftAuthorizationResult)->Bool {
        guard pending === item else {return false}
        pending=nil
        if let reason=result.denial,
           [GiftAuthorizationDenial.namespaceUnavailable,.clockRollback,.storageUnavailable,
            .unsupportedVersion,.invalidLedger,.ledgerFull].contains(reason) {stoppedReason=reason}
        return true
    }

    private func finish(_ item:Pending,result:GiftAuthorizationResult) {
        lock.lock()
        let claimed=claimLocked(item,result:result)
        lock.unlock()
        if claimed {deliver(item,result:result)}
    }

    private func deliver(_ item:Pending,result:GiftAuthorizationResult) {
        resultQueue.async { [clock,item] in
            // Main-queue congestion must not resurrect an expired authorization.
            let now=clock.monotonicTime()
            let delivered = !now.isFinite || now>=item.deadline ?
                GiftAuthorizationResult(denied:item.request.binding,reason:.timedOut):result
            item.completion(delivered)
        }
    }
}
