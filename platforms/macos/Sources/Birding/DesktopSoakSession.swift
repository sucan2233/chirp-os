import AppKit
import BirdingCore
import CryptoKit
import Darwin
import ServiceManagement

/// Owns an isolated *production* desktop, never a simulation driver. All engine
/// access is on the main thread. Only durable visitor snapshots cross to IO.
final class DesktopSoakSession: NSObject, NSWindowDelegate {
    enum SessionError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let message): return "Desktop soak: \(message)" }
        }
    }
    private enum Phase: String { case prepared, running, finishing, finished }
    let output: URL
    let duration: Double
    let requestedBirds: Int
    let desktop: DesktopController
    let preferencesDomain: String
    let statusAutosaveName: String
    let standardPreferencesDomain: String
    private let standardPreferencesBefore: [String: Any]
    private var statusAutosaveConfigured = false
    private(set) var isFinished = false
    /// Verification can retain the process after cleanup; CLI keeps this true.
    var terminateOnFinish = true
    var onFinish: (() -> Void)?

    private var phase = Phase.prepared
    private let ledgerQueue = DispatchQueue(label: "Birding.soak.ledger", qos: .utility)
    private var eventSink: SoakJSONLines?
    private var sampleSink: SoakJSONLines?
    private var sampleTimer: Timer?
    private var deadlineTimer: Timer?
    private var control: NSWindow?
    private var statusLabel: NSTextField?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var previousEventObserver: ((BehaviorEvent) -> Void)?
    private var previousTickObserver: ((Double, Double) -> Void)?
    private var observersInstalled = false
    private var waitingForTermination = false
    private var failureFinishScheduled = false
    private var failures: [String] = [] // Bounded; IO failure stops the session.
    private var startContinuous = 0.0
    private var startUptime = 0.0
    private var startDate = Date()
    private var startSimulation = 0.0
    private var accountingTime = 0.0
    private var sampledPaused = false
    private var sleeping = false
    private var locked: Bool?
    private var sleepSeconds = 0.0
    private var pausedSeconds = 0.0
    private var lockedSeconds = 0.0
    private var unknownLockSeconds = 0.0
    private var sleepCount = 0
    private var wakeCount = 0
    private var ticks: UInt64 = 0
    private var gapCounts = [UInt64](repeating: 0, count: 4)
    private var maximumTickGap = 0.0
    private var lastTickContinuous: Double?
    private var lastSampleContinuous = 0.0
    private var lastCPU: Double?
    private var initialCPU: Double?
    private var peakRSS: UInt64 = 0
    private var resourcePeaks: [String: Int] = [:]
    private var eventCounts: [String: UInt64] = [:]
    private var eventTotal: UInt64 = 0
    private var lastEventSequence: UInt64 = 0
    private var eventSequenceGaps: UInt64 = 0
    private var naturalState: [String: Any] = [:]
    private var cleanupState: [String: Any] = [:]
    private var finishReason = ""
    private var finalVisitorFlush = false
    private var finalJournalFlush = false
    private var naturalWallSeconds = 0.0
    private var naturalAwakeSeconds = 0.0

    init(output: URL, duration: Double, birds: Int) throws {
        guard Thread.isMainThread else { throw SessionError.invalid("must be created on the main thread") }
        guard output.isFileURL, output.path.hasPrefix("/"),
              [30.0, 7200.0, 28800.0].contains(duration), (1...50).contains(birds) else {
            throw SessionError.invalid("use an absolute new directory, duration 30/7200/28800 and 1...50 birds")
        }
        let arguments = CommandLine.arguments
        guard !arguments.contains(where: {
            $0.hasPrefix("--record-") || $0.hasPrefix("--replay-") ||
            $0.hasPrefix("--verify") || $0 == "--integration" || $0 == "--fixture" ||
            $0.hasPrefix("--stress") || $0.hasPrefix("--export-") || $0 == "--apply-update"
        }) else { throw SessionError.invalid("soak cannot share a process with recording, verification or fixture modes") }
        let canonical = output.standardizedFileURL.resolvingSymlinksInPath()
        try Self.claimEmptyDirectory(canonical)
        self.output = canonical
        self.duration = duration
        self.requestedBirds = birds
        let sessionID = UUID().uuidString
        preferencesDomain = "dev.birding.desktop.soak." + sessionID
        statusAutosaveName = "ChirpOS.Soak." + sessionID
        guard let applicationDomain = Bundle.main.bundleIdentifier, !applicationDomain.isEmpty else {
            throw SessionError.invalid("a bundle identifier is required to audit AppKit's default preferences")
        }
        standardPreferencesDomain = applicationDomain
        standardPreferencesBefore = UserDefaults.standard.persistentDomain(forName: applicationDomain) ?? [:]
        guard let preferences = UserDefaults(suiteName: preferencesDomain) else {
            throw SessionError.invalid("cannot create isolated defaults domain")
        }
        // Explicit local values avoid falling back to unrelated global defaults.
        preferences.set("en", forKey: "appLanguage")
        preferences.set(birds, forKey: "populationLower")
        preferences.set(birds, forKey: "populationUpper")
        // Default initializer retains the ordinary random seed and spawn policy.
        desktop = DesktopController()
        super.init()
        desktop.isolatedSession = true
        desktop.preferences = preferences
        desktop.loginService = SoakLoginItem()
        desktop.settingsURL = canonical.appendingPathComponent("settings.json")
        desktop.legacyURL = canonical.appendingPathComponent("legacy.json")
        desktop.visitorMemoryURL = canonical.appendingPathComponent("visitors.json")
        desktop.observationJournalURL = canonical.appendingPathComponent("journal.json")
        desktop.giftLedgerURL = canonical.appendingPathComponent("gifts.json")
        desktop.visitorMemoryPersistenceEnabled = true
        desktop.observationJournalPersistenceEnabled = true
        desktop.giftLedgerPersistenceEnabled = true
        desktop.giftLedgerPersistence = GiftLedgerPersistence(url: desktop.giftLedgerURL,
            enabled: true, workerQueue: ledgerQueue)
    }

    func start() throws {
        precondition(Thread.isMainThread)
        guard phase == .prepared else { throw SessionError.invalid("start may be called only once") }
        // All five paths are injected before start; legacy remains absent rather
        // than importing any user's old settings. Defaults remain real defaults.
        do {
            guard desktop.isolatedSession, desktop.updater == nil, desktop.integration == nil,
                  desktop.automaticPopulation, desktop.recordingPath == nil,
                  desktop.engine.events.isEmpty else { throw SessionError.invalid("controller is not pristine and isolated") }
            try BirdSettings().save(to: desktop.settingsURL)
            eventSink = try SoakJSONLines(url: output.appendingPathComponent("events.jsonl"))
            sampleSink = try SoakJSONLines(url: output.appendingPathComponent("telemetry.jsonl"))
            startContinuous = Self.continuousNow()
            startUptime = ProcessInfo.processInfo.systemUptime
            startDate = Date()
            startSimulation = desktop.engine.time
            accountingTime = startContinuous
            lastSampleContinuous = startContinuous
            locked = Self.readLockedState()
            initialCPU = Self.processUsage().cpu
            lastCPU = initialCPU
            try writeManifest()
            previousEventObserver = desktop.engine.eventObserver
            desktop.engine.eventObserver = { [weak self] event in
                guard let self else { return }
                self.previousEventObserver?(event)
                self.observe(event)
            }
            previousTickObserver = desktop.tickObserver
            desktop.tickObserver = { [weak self] uptime, rawDT in
                guard let self else { return }
                self.previousTickObserver?(uptime, rawDT)
                self.observeTick(uptime: uptime, rawDT: rawDT)
            }
            observersInstalled = true
            phase = .running
            installNotifications()
            // autosaveName is null_resettable: nil chooses an automatic name,
            // rather than disabling persistence. AppKit uses standard defaults,
            // so give this item a session-only identity before makeMenu runs.
            desktop.status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            desktop.status.autosaveName = statusAutosaveName
            statusAutosaveConfigured = desktop.status.autosaveName == statusAutosaveName && statusAutosaveName != "ChirpOS.Main"
            desktop.status.isVisible = true
            desktop.start()
            guard statusAutosaveConfigured, desktop.status.autosaveName == statusAutosaveName,
                  desktop.visitorMemoryPersistence?.giftNamespaceAvailable == true,
                  desktop.visitorMemoryPersistence?.writesEnabled == true,
                  desktop.observationPersistence?.enabled == true,
                  desktop.observationPersistence?.writesDisabled == false,
                  desktop.giftLedgerPersistence?.enabled == true else {
                throw SessionError.invalid("isolated persistence did not initialize successfully")
            }
            showControlWindow()
            try sample(label: "started")
            let telemetry = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.sampleAndCheckDeadline() }
            telemetry.tolerance = 0.25
            sampleTimer = telemetry
            RunLoop.main.add(telemetry, forMode: .common)
            let deadline = Timer(timeInterval: duration, repeats: false) { [weak self] _ in self?.sampleAndCheckDeadline() }
            deadlineTimer = deadline
            RunLoop.main.add(deadline, forMode: .common)
        } catch {
            noteFailure(error)
            finish(reason: "startupFailure")
            throw error
        }
    }

    /// Route Dock reopen here instead of recreating menus/settings while an
    /// asynchronous cleanup is draining. It never changes simulation state.
    func handleReopen() -> Bool {
        guard phase == .running else { return false }
        control?.makeKeyAndOrderFront(nil)
        return true
    }

    /// AppDelegate.applicationShouldTerminate must delegate here. Synchronous
    /// applicationWillTerminate alone cannot drain an in-flight ledger commit.
    func prepareForTermination() -> NSApplication.TerminateReply {
        precondition(Thread.isMainThread)
        if isFinished { return .terminateNow }
        waitingForTermination = true
        finish(reason: "applicationTermination")
        return .terminateLater
    }

    /// Idempotent, asynchronous only while previously queued ledger IO drains.
    /// Captures the natural state before issuing any cleanup commands.
    func finish(reason: String) {
        precondition(Thread.isMainThread)
        guard phase != .finishing, phase != .finished else { return }
        let wasRunning = phase == .running
        if wasRunning {
            accountTime()
            naturalWallSeconds = Self.continuousNow() - startContinuous
            naturalAwakeSeconds = ProcessInfo.processInfo.systemUptime - startUptime
            naturalState = snapshot(label: "naturalEnd")
            do { try sampleSink?.append(naturalState); try sampleSink?.flush() } catch { noteFailure(error) }
        }
        finishReason = reason
        phase = .finishing
        // Freeze callbacks before waiting for IO: wake/mouse/menu activity must
        // not start a fresh timer or request while cleanup is in progress.
        sampleTimer?.invalidate(); sampleTimer = nil
        deadlineTimer?.invalidate(); deadlineTimer = nil
        desktop.timer?.invalidate(); desktop.timer = nil
        desktop.stopMouseMonitoring()
        NotificationCenter.default.removeObserver(desktop)
        NSWorkspace.shared.notificationCenter.removeObserver(desktop)
        removeNotifications()
        desktop.status?.menu = nil
        NSApp.mainMenu = nil
        // Closing settings also cancels its capture timer and owned previews;
        // these events still belong to the cleanup stream, before IO barriers.
        desktop.settingsWindow?.cancelFixedPerchCapture()
        desktop.settingsWindow?.close(); desktop.settingsWindow = nil
        desktop.observationWindow?.close(); desktop.observationWindow = nil
        desktop.gallery?.close(); desktop.gallery = nil
        if wasRunning {
            desktop.cancelGiftAuthorization()
            desktop.engine.handle(.cancelAmbient(.shutdown))
            desktop.engine.handle(.clearProps)
            for bird in desktop.engine.birds {
                if let id = desktop.engine.id(of: bird) { desktop.engine.handle(.remove(id)) }
            }
            desktop.hoveredBird = nil
            desktop.consumeBehaviorEvents()
            for view in desktop.views { view.updateSprites() }
            cleanupState = snapshot(label: "resourcesAfterCleanup")
            do { try sampleSink?.append(cleanupState); try sampleSink?.flush() } catch { noteFailure(error) }
        }
        // The serial barrier follows every production ledger job. All result
        // deliveries queued by those jobs precede completeFinish on main.
        ledgerQueue.async { [self] in
            DispatchQueue.main.async { [self] in
                let identity = desktop.visitorMemoryPersistence?.giftIdentitySnapshot(archive: desktop.engine.visitorMemoryArchive)
                ledgerQueue.async { [self] in
                    var failure: String?
                    if let identity, identity.allowsWrites {
                        do {
                            try GiftLedgerFileAccess.withLock(for: identity.url,
                                deadline: ProcessInfo.processInfo.systemUptime + 5) { try identity.persistLocked() }
                        } catch { failure = "final visitor flush: \(error)" }
                    } else if wasRunning { failure = "final visitor flush: stable namespace unavailable" }
                    let flushError = failure
                    DispatchQueue.main.async { [self] in
                        finalVisitorFlush = identity != nil && flushError == nil
                        if let flushError { noteFailure(SessionError.invalid(flushError)) }
                        completeFinish()
                    }
                }
            }
        }
    }

    private func completeFinish() {
        desktop.flushObservationJournal()
        finalJournalFlush = desktop.observationPersistence.map { $0.loaded && $0.enabled && !$0.writesDisabled && !$0.saveFailed } ?? false
        if !naturalState.isEmpty && !finalJournalFlush { noteFailure(SessionError.invalid("final journal flush failed")) }
        // Flush need not create an empty journal or untouched gift ledger.
        // Record their actual presence, never fabricate evidence files.
        cleanupState = snapshot(label: "resourcesAfterIODrain")
        let zeroResources = resourcesAreZero()
        let zeroDynamicLayers = layerCounts()["dynamicContainers", default: 0] == 0
        if observersInstalled {
            desktop.engine.eventObserver = previousEventObserver
            desktop.tickObserver = previousTickObserver
            previousEventObserver = nil; previousTickObserver = nil
            observersInstalled = false
        }
        for panel in desktop.panels { panel.contentView = nil; panel.close() }
        desktop.views.removeAll(); desktop.panels.removeAll()
        let statusNameAtRemoval = desktop.status?.autosaveName
        if let status = desktop.status { NSStatusBar.system.removeStatusItem(status); desktop.status = nil }
        control?.delegate = nil; control?.close(); control = nil; statusLabel = nil
        let preferences = desktop.preferences.persistentDomain(forName: preferencesDomain) ?? [:]
        do { try writeJSON(preferences, name: "preferences.json") } catch { noteFailure(error) }
        desktop.preferences.removePersistentDomain(forName: preferencesDomain)
        let isolation = finishPreferenceIsolation(statusNameAtRemoval: statusNameAtRemoval)
        let preferencesIsolated = isolation["isolationSucceeded"] as? Bool == true
        if !preferencesIsolated { noteFailure(SessionError.invalid("preference isolation failed; see preference-isolation.json")) }
        do { try writeJSON(isolation, name: "preference-isolation.json") } catch { noteFailure(error) }
        do {
            try sampleSink?.append(cleanupState)
            try eventSink?.close(); try sampleSink?.close()
        } catch { noteFailure(error) }
        eventSink = nil; sampleSink = nil
        let windowsClosed = desktop.panels.isEmpty && desktop.views.isEmpty && control == nil &&
            desktop.settingsWindow == nil && desktop.observationWindow == nil && desktop.gallery == nil
        let summary: [String: Any] = [
            "schemaVersion": 1, "reason": finishReason, "requestedDurationSeconds": duration,
            "mode": duration == 30 ? "smoke" : "wallClockSoak", "wallSecondsBeforeCleanup": naturalWallSeconds,
            "awakeUptimeSecondsBeforeCleanup": naturalAwakeSeconds,
            "wallDurationReached": naturalWallSeconds >= duration,
            "awakeDurationReached": naturalAwakeSeconds >= duration,
            "manualTwoHourObservation": "notAssessed_requiresSeparateHumanRecord",
            "eightHourRun": duration == 28800 && naturalWallSeconds >= 28800 ? "durationReached_reviewEvidence" : "notEstablished",
            "physicalMultiMonitorAndSleepWakeAcceptance": "notAssessed",
            "stageAcceptance": "notGrantedByThisReport",
            "naturalEnd": naturalState, "afterCleanup": cleanupState,
            "eventTotal": eventTotal, "eventCounts": eventCounts, "eventSequenceGaps": eventSequenceGaps,
            "zeroResources": zeroResources, "zeroDynamicLayersAfterRefresh": zeroDynamicLayers,
            "windowsClosed": windowsClosed, "layersAfterClose": layerCounts(),
            "timerStopped": desktop.timer == nil, "mouseMonitorsStopped": desktop.globalMouseMonitor == nil && desktop.localMouseMonitor == nil,
            "visitorFlushSucceeded": finalVisitorFlush, "journalFlushSucceeded": finalJournalFlush,
            "preferenceIsolationSucceeded": preferencesIsolated, "preferencesIsolation": isolation,
            "filesPresent": persistencePresence(), "peakRSSBytes": peakRSS,
            "resourcePeaks": resourcePeaks, "errors": failures,
            "cleanupSucceeded": zeroResources && zeroDynamicLayers && windowsClosed && finalVisitorFlush && finalJournalFlush && preferencesIsolated && failures.isEmpty
        ]
        do { try writeJSON(summary, name: "summary.json") }
        catch { noteFailure(error); fputs("Desktop soak summary could not be saved: \(error)\n", stderr) }
        phase = .finished; isFinished = true
        onFinish?()
        if waitingForTermination { NSApp.reply(toApplicationShouldTerminate: true) }
        else if terminateOnFinish { NSApp.terminate(nil) }
    }

    private func observe(_ event: BehaviorEvent) {
        guard phase == .running || phase == .finishing else { return }
        eventTotal += 1
        if event.sequence != lastEventSequence + 1 { eventSequenceGaps += 1 }
        lastEventSequence = event.sequence
        let key = [event.type.rawValue, event.kind?.rawValue ?? "none", event.source.rawValue, event.reason?.rawValue ?? "none"].joined(separator: "/")
        eventCounts[key, default: 0] += 1
        let record: [String: Any] = ["sequence": String(event.sequence), "simulationTime": event.time,
            "wallSeconds": Self.continuousNow() - startContinuous, "phase": phase.rawValue,
            "type": event.type.rawValue, "kind": event.kind?.rawValue ?? "", "source": event.source.rawValue,
            "reason": event.reason?.rawValue ?? "", "run": event.runID.map { String($0.rawValue) } ?? "",
            "birds": event.participants.map { String($0.rawValue) }]
        do { try eventSink?.append(record) } catch { telemetryFailed(error) }
    }

    private func observeTick(uptime: Double, rawDT: Double) {
        guard phase == .running else { return }
        accountTime()
        sampledPaused = desktop.paused
        ticks += 1
        if rawDT.isFinite && rawDT >= 0 {
            maximumTickGap = max(maximumTickGap, rawDT)
            for (index, threshold) in [0.05, 0.25, 1.0, 10.0].enumerated() where rawDT > threshold { gapCounts[index] += 1 }
        }
        lastTickContinuous = Self.continuousNow()
        // Resource snapshots (including reservation arrays) are sampled only
        // every 10s; do not add dictionary sorting/allocation to every tick.
    }

    private func sampleAndCheckDeadline() {
        guard phase == .running else { return }
        do { try sample(label: "periodic") } catch { telemetryFailed(error); return }
        if Self.continuousNow() - startContinuous >= duration { finish(reason: "durationReached") }
    }

    private func sample(label: String) throws {
        accountTime()
        if let value = Self.readLockedState() { locked = value }
        let record = snapshot(label: label)
        try sampleSink?.append(record)
        try eventSink?.flush(); try sampleSink?.flush()
        let elapsed = Self.continuousNow() - startContinuous
        statusLabel?.stringValue = String(format: "%.0f / %.0f seconds • %d residents\nReal desktop timer • isolated files\nClose this window to clean up and exit.\nHuman observation is recorded separately.", elapsed, duration, desktop.residentCount)
    }

    private func snapshot(label: String) -> [String: Any] {
        let now = Self.continuousNow(), usage = Self.processUsage()
        let interval = now - lastSampleContinuous
        let cpuPercent: Any
        if let cpu = usage.cpu, let prior = lastCPU, interval > 0 { cpuPercent = max(0, cpu - prior) / interval * 100 }
        else { cpuPercent = NSNull() }
        lastSampleContinuous = now; lastCPU = usage.cpu
        if let rss = usage.rss { peakRSS = max(peakRSS, rss) }
        let counts = resourceCounts()
        for (key, value) in counts { resourcePeaks[key] = max(resourcePeaks[key, default: 0], value) }
        return ["schemaVersion": 1, "label": label, "utc": ISO8601DateFormatter().string(from: Date()),
            "wallSeconds": now - startContinuous, "awakeUptimeSeconds": ProcessInfo.processInfo.systemUptime - startUptime,
            "simulationSeconds": desktop.engine.time - startSimulation, "paused": desktop.paused,
            "sampledPausedWallSeconds": pausedSeconds, "sleepWallSeconds": sleepSeconds, "sleeping": sleeping,
            "sleepCount": sleepCount, "wakeCount": wakeCount, "locked": locked.map { $0 as Any } ?? NSNull(),
            "knownLockedWallSeconds": lockedSeconds, "unknownLockWallSeconds": unknownLockSeconds,
            "humanObservationSeconds": NSNull(), "tickCount": ticks,
            "tickGapsOver50ms250ms1s10s": gapCounts, "maximumRawTickGapSeconds": maximumTickGap,
            "secondsSinceObservedTick": lastTickContinuous.map { now - $0 } ?? 0,
            "rssBytes": usage.rss.map { $0 as Any } ?? NSNull(),
            "processCPUSeconds": usage.cpu.map { $0 as Any } ?? NSNull(),
            "sessionCPUSeconds": usage.cpu.flatMap { cpu in initialCPU.map { max(0, cpu - $0) } }.map { $0 as Any } ?? NSNull(),
            "intervalCPUPercentOneCore": cpuPercent, "resourceCounts": counts,
            "layers": layerCounts(), "eventsObserved": eventTotal, "eventSequenceGaps": eventSequenceGaps,
            "arrivals": desktop.arrivalCount, "departures": desktop.departureCount,
            "populationEnabled": desktop.engine.populationEnabled, "ambientEnabled": desktop.engine.ambientEnabled,
            "autonomousRouting": desktop.engine.autonomousRouting, "surfaceCount": desktop.surfaces.count,
            "displayCount": NSScreen.screens.count, "persistence": persistenceStatus()]
    }

    private func resourceCounts() -> [String: Int] {
        let e = desktop.engine
        return ["birds": e.birds.count, "residents": e.residentCount, "departing": e.departingCount,
            "transients": e.passingCount, "pendingBirds": e.pendingCount, "runs": e.activeRunCount,
            "leases": e.leasedBirdCount, "landingReservations": e.reservedLandingCount,
            "habitatReservations": e.habitatReservationCount, "giftReceiverReservations": e.giftReceiverReservationCount,
            "nests": e.nestSnapshot().count, "nestMaterials": e.nestSnapshot().reduce(0) {$0+$1.materials.count},
            "pendingNestPlacement": e.hasNestPlacement ? 1 : 0,
            "props": e.scenePropCount, "habitats": e.habitatSnapshot().count,
            "carriedObjects": e.carriedObjectSnapshot().count, "insects": e.insectSnapshot() == nil ? 0 : 1,
            "pendingPointer": e.hasPointerPreview ? 1 : 0, "pendingLeaf": e.hasLeafPreview ? 1 : 0,
            "pendingFoodPlacement": e.hasFoodTrayPlacement ? 1 : 0, "pendingBathPlacement": e.hasBathPlacement ? 1 : 0,
            "pendingCarryPlacement": e.hasCarryLeafPlacement ? 1 : 0, "pendingInsectPreview": e.hasInsectCatchPreview ? 1 : 0,
            "pendingGift": e.giftAuthorizationRequest == nil ? 0 : 1, "giftTokens": e.activeGiftAuthorizationCount,
            "platformGiftAttempt": desktop.giftAuthorizationAttempt == nil ? 0 : 1,
            "sceneFocus": e.sceneFocus == nil ? 0 : 1, "activeVisitors": e.activeVisitorCount]
    }
    private func resourcesAreZero() -> Bool { resourceCounts().values.allSatisfy { $0 == 0 } }

    private func layerCounts() -> [String: Int] {
        var result = ["total": 0, "masks": 0, "dynamicContainers": 0, "animations": 0]
        func visit(_ layer: CALayer) {
            result["total", default: 0] += 1
            result["animations", default: 0] += layer.animationKeys()?.count ?? 0
            if let name = layer.name, ["bird-sprite-", "scene-prop-", "habitat-"].contains(where: { name.hasPrefix($0) }) {
                result["dynamicContainers", default: 0] += 1
            }
            if let mask = layer.mask { result["masks", default: 0] += 1; visit(mask) }
            for child in layer.sublayers ?? [] { visit(child) }
        }
        for view in desktop.views { if let layer = view.layer { visit(layer) } }
        return result
    }

    private func persistenceStatus() -> [String: Any] {
        ["visitorsEnabled": desktop.visitorMemoryPersistence?.enabled ?? false,
         "visitorWritesEnabled": desktop.visitorMemoryPersistence?.writesEnabled ?? false,
         "visitorWritesDisabled": desktop.visitorMemoryPersistence?.writesDisabled ?? false,
         "visitorSaveAttempts": desktop.visitorMemoryPersistence?.saveAttempts ?? 0,
         "visitorSuccessfulSaves": desktop.visitorMemoryPersistence?.successfulSaves ?? 0,
         "journalEnabled": desktop.observationPersistence?.enabled ?? false,
         "journalWritesDisabled": desktop.observationPersistence?.writesDisabled ?? false,
         "journalSaveFailed": desktop.observationPersistence?.saveFailed ?? false,
         "journalSuccessfulSaves": desktop.observationPersistence?.successfulSaves ?? 0,
         "giftLedgerEnabled": desktop.giftLedgerPersistence?.enabled ?? false,
         "giftLedgerDenial": desktop.giftLedgerPersistence?.blockingDenial?.rawValue ?? "",
         "statusItemPresent": desktop.status != nil,
         "statusAutosaveName": desktop.status?.autosaveName as Any? ?? NSNull(),
         "statusAutosaveMode": "sessionUniqueName",
         "statusAutosaveIsolated": desktop.status != nil && desktop.status?.autosaveName == statusAutosaveName && statusAutosaveName != "ChirpOS.Main",
         "standardDefaultsRedirected": false]
    }
    /// The injected suite covers controller preferences, not AppKit. Only keys
    /// bearing our UUID name are ours to delete; never restore the whole domain
    /// over changes made by another running instance. Report any difference.
    private func finishPreferenceIsolation(statusNameAtRemoval: String?) -> [String: Any] {
        let defaults = UserDefaults.standard
        let beforeCleanup = defaults.persistentDomain(forName: standardPreferencesDomain) ?? [:]
        let sessionKeys = beforeCleanup.keys.filter { $0.contains(statusAutosaveName) }.sorted()
        for key in sessionKeys { defaults.removeObject(forKey: key) }
        let afterCleanup = defaults.persistentDomain(forName: standardPreferencesDomain) ?? [:]
        let remaining = afterCleanup.keys.filter { $0.contains(statusAutosaveName) }.sorted()
        let changes = Self.changedPreferenceKeys(standardPreferencesBefore, afterCleanup)
        let protectedChanges = changes.filter {
            ["appLanguage", "populationLower", "populationUpper"].contains($0) || $0.contains("ChirpOS.Main")
        }
        let suiteRemoved = desktop.preferences.persistentDomain(forName: preferencesDomain)?.isEmpty != false
        let nameMatches = statusAutosaveConfigured && statusNameAtRemoval == statusAutosaveName && statusAutosaveName != "ChirpOS.Main"
        return ["schemaVersion": 1, "standardPreferencesDomain": standardPreferencesDomain,
            "standardDefaultsRedirected": false, "statusAutosaveMode": "sessionUniqueName",
            "expectedStatusAutosaveName": statusAutosaveName, "statusAutosaveNameAtRemoval": statusNameAtRemoval as Any? ?? NSNull(),
            "statusAutosaveConfigured": statusAutosaveConfigured, "statusAutosaveMatchesAtRemoval": nameMatches,
            "sessionAutosaveKeysRemoved": sessionKeys, "sessionAutosaveKeysRemaining": remaining,
            "defaultApplicationDomainChangedKeysBeforeCleanup": Self.changedPreferenceKeys(standardPreferencesBefore, beforeCleanup),
            "defaultApplicationDomainChangedKeysAfterCleanup": changes, "defaultApplicationDomainUnchanged": changes.isEmpty,
            "protectedProductionPreferenceKeysChanged": protectedChanges, "productionPreferenceKeysUnchanged": protectedChanges.isEmpty,
            "isolatedPreferencesDomainRemoved": suiteRemoved,
            "isolationSucceeded": nameMatches && suiteRemoved && remaining.isEmpty && changes.isEmpty,
            "scope": "In-process default application-domain snapshots; no global-domain, post-exit disk or concurrent-writer attribution guarantee."]
    }
    private static func changedPreferenceKeys(_ before: [String: Any], _ after: [String: Any]) -> [String] {
        Set(before.keys).union(after.keys).filter { key in
            guard let a = before[key], let b = after[key] else { return true }
            return !NSDictionary(dictionary: ["value": a]).isEqual(to: ["value": b])
        }.sorted()
    }
    private func persistencePresence() -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: ["settings.json", "legacy.json", "visitors.json", "journal.json", "gifts.json"].map {
            ($0, FileManager.default.fileExists(atPath: output.appendingPathComponent($0).path))
        })
    }

    private func accountTime() {
        let now = Self.continuousNow()
        let delta = max(0, now - accountingTime)
        if sleeping { sleepSeconds += delta }
        if sampledPaused { pausedSeconds += delta }
        if locked == true { lockedSeconds += delta }
        if locked == nil { unknownLockSeconds += delta }
        accountingTime = now
    }

    private func installNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        func add(_ name: Notification.Name, _ update: @escaping () -> Void) {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.phase == .running else { return }
                self.accountTime(); update()
                do { try self.sampleSink?.append(["label": "workspaceNotification", "name": name.rawValue,
                    "wallSeconds": Self.continuousNow() - self.startContinuous]) } catch { self.telemetryFailed(error) }
            })
        }
        add(NSWorkspace.willSleepNotification) { [weak self] in self?.sleeping = true; self?.sleepCount += 1 }
        add(NSWorkspace.didWakeNotification) { [weak self] in self?.sleeping = false; self?.wakeCount += 1 }
        add(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.locked = true }
        add(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.locked = Self.readLockedState() }
        // These notifications are supplemental evidence, not proof of human
        // presence. Missing initial lock information remains explicitly unknown.
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let token = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                guard let self, self.phase == .running else { return }
                self.accountTime(); self.locked = value
                do { try self.sampleSink?.append(["label": "lockNotification", "locked": value,
                    "wallSeconds": Self.continuousNow() - self.startContinuous]) } catch { self.telemetryFailed(error) }
            }
            distributedObservers.append(token)
        }
    }
    private func removeNotifications() {
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        workspaceObservers.removeAll(); distributedObservers.removeAll()
    }
    private static func readLockedState() -> Bool? {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        if let onConsole = dictionary[kCGSessionOnConsoleKey as String] as? Bool, !onConsole { return true }
        return dictionary["CGSSessionScreenIsLocked"] as? Bool
    }

    private func showControlWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 170),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ChirpOS isolated desktop soak — \(Int(duration))s"
        window.isReleasedWhenClosed = false; window.delegate = self
        let label = NSTextField(wrappingLabelWithString: "Starting real desktop observation…")
        label.frame = NSRect(x: 20, y: 25, width: 440, height: 120)
        window.contentView?.addSubview(label)
        statusLabel = label; control = window
        window.center(); window.makeKeyAndOrderFront(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { finish(reason: "controlWindowClosed"); return false }

    private func writeManifest() throws {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let manifest: [String: Any] = ["schemaVersion": 1, "createdUTC": ISO8601DateFormatter().string(from: startDate),
            "output": output.path, "durationSeconds": duration, "birds": requestedBirds,
            "preferencesDomain": preferencesDomain, "bundlePath": Bundle.main.bundleURL.path,
            "preferenceIsolationVersion": 1, "statusAutosaveName": statusAutosaveName,
            "statusAutosaveMode": "sessionUniqueName", "standardPreferencesDomain": standardPreferencesDomain,
            "standardDefaultsRedirected": false,
            "binaryPath": executable.path, "binarySHA256": try Self.sha256(executable),
            "bundleVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "shortVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "simulationVersion": BehaviorInputLog.engineVersion, "engineSeed": String(desktop.engine.seed),
            "pid": ProcessInfo.processInfo.processIdentifier, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "cpuPercentDefinition": "process user+system delta / continuous wall delta * 100; one core=100%; sleep included in denominator",
            "lockEvidence": "sampled session state plus notifications; unknown is not unlocked; no human-presence inference",
            "pauseEvidence": "sampled at production tick boundaries; overlaps sleep and lock durations",
            "processorCount": ProcessInfo.processInfo.processorCount, "samplingIntervalSeconds": 10,
            "clock": "mach_continuous_time; sleep included; no engine advancement from observer",
            "settings": desktop.settingsURL.path, "legacy": desktop.legacyURL.path,
            "visitors": desktop.visitorMemoryURL.path, "journal": desktop.observationJournalURL.path,
            "gifts": desktop.giftLedgerURL.path, "productionPersistence": true,
            "manualObservation": "notEstablished", "smokeIsNotLongRunAcceptance": true]
        try writeJSON(manifest, name: "manifest.json")
    }
    private func writeJSON(_ object: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try GiftLedgerFileAccess.atomicWrite(data, to: output.appendingPathComponent(name))
    }
    private func noteFailure(_ error: Error) { if failures.count < 16 { failures.append(String(describing: error)) } }
    private func telemetryFailed(_ error: Error) {
        noteFailure(error)
        guard !failureFinishScheduled, phase == .running else { return }
        failureFinishScheduled = true
        DispatchQueue.main.async { [weak self] in self?.finish(reason: "telemetryFailure") }
    }
    private static func claimEmptyDirectory(_ url: URL) throws {
        let files = FileManager.default
        var directory: ObjCBool = false
        if files.fileExists(atPath: url.path, isDirectory: &directory) {
            guard directory.boolValue, try files.contentsOfDirectory(atPath: url.path).isEmpty else {
                throw SessionError.invalid("output must be new or empty; existing evidence is never overwritten")
            }
        } else { try files.createDirectory(at: url, withIntermediateDirectories: true) }
        // O_EXCL arbitrates two sessions that both observed an empty directory.
        let descriptor = Darwin.open(url.appendingPathComponent("session.claim").path,
            O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw SessionError.invalid("output directory is already claimed") }
        Darwin.close(descriptor)
    }
    private static let timebase: Double = {
        var value = mach_timebase_info_data_t()
        mach_timebase_info(&value)
        return Double(value.numer) / Double(value.denom) / 1_000_000_000
    }()
    private static func continuousNow() -> Double { Double(mach_continuous_time()) * timebase }
    private static func processUsage() -> (rss: UInt64?, cpu: Double?) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        var usage = rusage()
        let success = getrusage(RUSAGE_SELF, &usage) == 0
        let cpu: Double? = success ? Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
            Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000 : nil
        return (result == KERN_SUCCESS ? UInt64(info.resident_size) : nil, cpu)
    }
    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// No ServiceManagement reads/writes, prompts, or launch-at-login registration.
private struct SoakLoginItem: LoginItemManaging {
    var status: SMAppService.Status { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}

/// At most 64 KiB buffered regardless of run duration. Every event is written;
/// counters are separate, bounded by enum combinations rather than event IDs.
private final class SoakJSONLines {
    private var handle: FileHandle?
    private var buffer = Data()
    init(url: URL) throws {
        let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw DesktopSoakSession.SessionError.invalid("cannot create \(url.lastPathComponent)") }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    func append(_ object: [String: Any]) throws {
        guard let handle else { throw DesktopSoakSession.SessionError.invalid("JSONL stream already closed") }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(10)
        if buffer.count + data.count > 65_536 { try drain() }
        if data.count > 65_536 { try handle.write(contentsOf: data) }
        else { buffer.append(data) }
    }
    private func drain() throws {
        guard let handle else { return }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true) }
    }
    func flush() throws { try drain(); try handle?.synchronize() }
    func close() throws { try flush(); try handle?.close(); handle = nil }
    deinit { try? handle?.close() }
}
