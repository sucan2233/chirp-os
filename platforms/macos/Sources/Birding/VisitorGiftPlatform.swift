import Foundation
import BirdingCore

/// Identity includes the controller session and a unique attempt, in addition
/// to every core binding field. Reused numeric request IDs cannot revive IO.
final class GiftPlatformAttempt {
    let session:UUID
    let request:GiftAuthorizationRequest
    init(session:UUID,request:GiftAuthorizationRequest) {self.session=session;self.request=request}
}

extension DesktopController {
    func installGiftAuthorizationObserver() {
        engine.giftAuthorizationObserver={ [weak self] request in self?.authorizeVisitorGift(request) }
    }
    private func authorizeVisitorGift(_ request:GiftAuthorizationRequest) {
        precondition(Thread.isMainThread)
        guard engine.giftAuthorizationRequest==request else {return}
        // Core can cancel A and publish B before a render/tick reconciliation.
        // Retire A's provider before installing B, never after publishing B.
        reconcileGiftAuthorization()
        if request.binding.source == .preview {
            // Fictional previews are external, recordable in-memory inputs;
            // they neither construct a ledger provider nor touch its quota.
            let originalEngine=engine
            let result=GiftAuthorizationResult(granted:.init(id:UUID(),binding:request.binding))
            DispatchQueue.main.async { [weak self,weak originalEngine] in
                guard let self,let originalEngine,self.engine === originalEngine else {return}
                originalEngine.receiveGiftAuthorization(result)
                self.consumeBehaviorEvents();self.settingsWindow?.refreshVisitorGiftControls()
            }
            return
        }
        guard giftAuthorizationAttempt==nil else {
            engine.receiveGiftAuthorization(.init(denied:request.binding,reason:.busy));return
        }
        let attempt=GiftPlatformAttempt(session:giftAuthorizationSession,request:request)
        giftAuthorizationAttempt=attempt
        let originalEngine=engine
        let completion:(GiftAuthorizationResult)->Void={ [weak self,weak originalEngine,attempt] result in
            let deliver={ [weak self,weak originalEngine,attempt] in
                guard let self,let originalEngine,self.engine === originalEngine,result.isValid,
                      result.binding==attempt.request.binding else {return}
                // Late and duplicate results remain recordable external input
                // to this same engine. Core admission refuses to revive them.
                // A callback may never clear a newer platform attempt.
                if self.giftAuthorizationAttempt === attempt,self.giftAuthorizationSession==attempt.session {
                    self.giftAuthorizationAttempt=nil
                }
                self.engine.receiveGiftAuthorization(result)
                self.consumeBehaviorEvents()
                self.settingsWindow?.refreshVisitorGiftControls()
            }
            if Thread.isMainThread {deliver()} else {DispatchQueue.main.async(execute:deliver)}
        }
        if let provider=giftAuthorizationProvider {provider(request,completion);return}
        guard let memory=visitorMemoryPersistence else {
            completion(.init(denied:request.binding,reason:.namespaceUnavailable));return
        }
        if giftLedgerPersistence==nil {
            giftLedgerPersistence=GiftLedgerPersistence(url:giftLedgerURL,enabled:giftLedgerPersistenceEnabled)
        }
        giftLedgerPersistence?.request(request,visitorMemory:memory,archive:engine.visitorMemoryArchive,completion:completion)
    }
    /// Invalidate the session before cancellation can enqueue a late callback.
    /// The provider survives to preserve a session's blocking storage denial.
    func cancelGiftAuthorization() {
        precondition(Thread.isMainThread)
        giftAuthorizationSession=UUID();giftAuthorizationAttempt=nil
        engine.handle(.cancelVisitorGiftRequest)
        giftLedgerPersistence?.cancelPending()
    }
    /// Commands, pointer input or world changes may invalidate the core request
    /// independently of a settings window; retire its platform attempt as well.
    func reconcileGiftAuthorization() {
        guard let attempt=giftAuthorizationAttempt,engine.giftAuthorizationRequest != attempt.request else {return}
        giftAuthorizationSession=UUID();giftAuthorizationAttempt=nil
        giftLedgerPersistence?.cancelPending()
    }
}
