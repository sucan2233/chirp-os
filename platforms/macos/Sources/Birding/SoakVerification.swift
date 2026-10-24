import Foundation

/// Offline evidence inspection only. Does not start a desktop, advance a clock,
/// launch a subprocess, or convert a 30s smoke into 2h/8h acceptance.
/// A caller may run this after the real --soak-duration 30 process has exited.
enum SoakVerification {
    static func inspectCompletedSmoke(at folder: URL) throws -> [String: Bool] {
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        func read(_ name: String) throws -> [String: Any] {
            guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(name))) as? [String: Any] else {
                throw DesktopSoakSession.SessionError.invalid("invalid \(name)")
            }
            return object
        }
        func number(_ object: [String: Any], _ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue }
        let manifest = try read("manifest.json"), summary = try read("summary.json")
        let natural = summary["naturalEnd"] as? [String: Any] ?? [:]
        let cleanup = summary["afterCleanup"] as? [String: Any] ?? [:]
        let counts = cleanup["resourceCounts"] as? [String: NSNumber] ?? [:]
        var checks: [String: Bool] = [:]
        checks["soakSmokeIsExplicitlyThirtySeconds"] = number(manifest, "durationSeconds") == 30 && summary["mode"] as? String == "smoke"
        checks["soakSmokeCompletedRealWallDuration"] = summary["reason"] as? String == "durationReached" &&
            (number(summary, "wallSecondsBeforeCleanup") ?? 0) >= 30 && summary["wallDurationReached"] as? Bool == true
        checks["soakSmokeDoesNotClaimLongRunOrHumanObservation"] = summary["eightHourRun"] as? String == "notEstablished" &&
            summary["manualTwoHourObservation"] as? String == "notAssessed_requiresSeparateHumanRecord" &&
            summary["stageAcceptance"] as? String == "notGrantedByThisReport"
        checks["soakSmokeFivePathsStayInsideIsolatedOutput"] = ["settings", "legacy", "visitors", "journal", "gifts"].allSatisfy {
            guard let path = manifest[$0] as? String else { return false }
            return URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent() == root
        }
        checks["soakSmokeIndependentPreferencesAndNoLegacyImport"] = (manifest["preferencesDomain"] as? String)?.hasPrefix("dev.birding.desktop.soak.") == true &&
            !FileManager.default.fileExists(atPath: root.appendingPathComponent("legacy.json").path)
        let preferences = try read("preferences.json")
        checks["soakSmokeRequestedPopulationPersistedOnlyInIsolatedDomain"] = number(preferences, "populationLower") == number(manifest, "birds") &&
            number(preferences, "populationUpper") == number(manifest, "birds") && number(manifest, "birds") != nil
        let isolation = try read("preference-isolation.json")
        let autosaveName = manifest["statusAutosaveName"] as? String ?? ""
        let sessionID = String(autosaveName.dropFirst("ChirpOS.Soak.".count))
        let standardDomain = manifest["standardPreferencesDomain"] as? String ?? ""
        checks["soakSmokePreferenceIsolationReportMatchesManifestAndSummary"] = number(manifest, "preferenceIsolationVersion") == 1 &&
            number(isolation, "schemaVersion") == 1 && !standardDomain.isEmpty &&
            isolation["standardPreferencesDomain"] as? String == standardDomain &&
            NSDictionary(dictionary: isolation).isEqual(to: summary["preferencesIsolation"] as? [String: Any] ?? [:]) &&
            manifest["standardDefaultsRedirected"] as? Bool == false && isolation["standardDefaultsRedirected"] as? Bool == false
        checks["soakSmokeStatusUsesExplicitSessionUniqueAutosaveName"] = autosaveName.hasPrefix("ChirpOS.Soak.") &&
            UUID(uuidString: sessionID) != nil && manifest["preferencesDomain"] as? String == "dev.birding.desktop.soak." + sessionID &&
            autosaveName != "ChirpOS.Main" && manifest["statusAutosaveMode"] as? String == "sessionUniqueName" &&
            isolation["expectedStatusAutosaveName"] as? String == autosaveName &&
            isolation["statusAutosaveNameAtRemoval"] as? String == autosaveName &&
            isolation["statusAutosaveConfigured"] as? Bool == true && isolation["statusAutosaveMatchesAtRemoval"] as? Bool == true
        let removed = isolation["sessionAutosaveKeysRemoved"] as? [String]
        let remaining = isolation["sessionAutosaveKeysRemaining"] as? [String]
        checks["soakSmokeOnlyThisSessionsAutosaveKeysCleanedAndNoneRemain"] = removed != nil && remaining?.isEmpty == true &&
            removed?.allSatisfy { $0.contains(autosaveName) && !$0.contains("ChirpOS.Main") } == true
        checks["soakSmokeDefaultApplicationAndProductionPreferencesUnchanged"] =
            (isolation["defaultApplicationDomainChangedKeysAfterCleanup"] as? [String])?.isEmpty == true &&
            (isolation["protectedProductionPreferenceKeysChanged"] as? [String])?.isEmpty == true &&
            isolation["defaultApplicationDomainUnchanged"] as? Bool == true && isolation["productionPreferenceKeysUnchanged"] as? Bool == true
        checks["soakSmokeIsolatedSuiteRemovedAndPreferenceCleanupSucceeded"] = isolation["isolatedPreferencesDomainRemoved"] as? Bool == true &&
            isolation["isolationSucceeded"] as? Bool == true && summary["preferenceIsolationSucceeded"] as? Bool == true
        checks["soakSmokeBinaryIdentityRecorded"] = (manifest["binarySHA256"] as? String)?.count == 64 &&
            (manifest["binaryPath"] as? String)?.hasPrefix("/") == true && (number(manifest, "pid") ?? 0) > 0
        checks["soakSmokeProductionSchedulingActuallyRan"] = (number(natural, "tickCount") ?? 0) > 0 &&
            (number(natural, "arrivals") ?? 0) > 0 && natural["populationEnabled"] as? Bool == true &&
            natural["ambientEnabled"] as? Bool == true && natural["autonomousRouting"] as? Bool == true
        let simulated = number(natural, "simulationSeconds") ?? -1
        let wall = number(natural, "wallSeconds") ?? -1
        checks["soakSmokeSimulationDidNotOutrunWallClock"] = simulated > 0 && wall >= 30 && simulated <= wall + 0.05
        checks["soakSmokePersistenceFlushAndCleanupSucceeded"] = summary["cleanupSucceeded"] as? Bool == true &&
            summary["visitorFlushSucceeded"] as? Bool == true && summary["journalFlushSucceeded"] as? Bool == true
        let requiredZero = ["birds", "pendingBirds", "runs", "leases", "landingReservations", "habitatReservations",
            "giftReceiverReservations", "props", "habitats", "carriedObjects", "insects", "pendingPointer", "pendingLeaf",
            "pendingFoodPlacement", "pendingBathPlacement", "pendingCarryPlacement", "pendingInsectPreview",
            "pendingGift", "giftTokens", "platformGiftAttempt", "sceneFocus", "activeVisitors"]
        let nestZero = ["nests", "nestMaterials", "pendingNestPlacement"]
        checks["soakSmokeAllResourceCountsExplicitAndZero"] = requiredZero.allSatisfy { counts[$0]?.intValue == 0 } &&
            ((number(manifest, "simulationVersion") ?? 0) < 18 || nestZero.allSatisfy { counts[$0]?.intValue == 0 })
        let layers = summary["layersAfterClose"] as? [String: NSNumber] ?? [:]
        checks["soakSmokeWindowsLayersTimerAndMouseReleased"] = summary["windowsClosed"] as? Bool == true &&
            summary["timerStopped"] as? Bool == true && summary["mouseMonitorsStopped"] as? Bool == true &&
            summary["zeroDynamicLayersAfterRefresh"] as? Bool == true && layers["total"]?.intValue == 0
        checks["soakSmokeNoReportedEvidenceErrors"] = (summary["errors"] as? [String])?.isEmpty == true

        var eventCount: UInt64 = 0, previous: UInt64 = 0, consecutive = true
        var eventCounts: [String: UInt64] = [:]
        try forEachLine(root.appendingPathComponent("events.jsonl")) { record in
            guard let raw = record["sequence"] as? String, let sequence = UInt64(raw),
                  let type = record["type"] as? String, let kind = record["kind"] as? String,
                  let source = record["source"] as? String, let reason = record["reason"] as? String else {
                throw DesktopSoakSession.SessionError.invalid("malformed event line")
            }
            consecutive = consecutive && sequence == previous + 1
            previous = sequence; eventCount += 1
            let key = [type, kind.isEmpty ? "none" : kind, source, reason.isEmpty ? "none" : reason].joined(separator: "/")
            eventCounts[key, default: 0] += 1
        }
        let totals = summary["eventCounts"] as? [String: NSNumber] ?? [:]
        checks["soakSmokeEventStreamMatchesFullCounters"] = consecutive && (summary["eventTotal"] as? NSNumber)?.uint64Value == eventCount &&
            number(summary, "eventSequenceGaps") == 0 && totals.count == eventCounts.count &&
            eventCounts.allSatisfy { totals[$0.key]?.uint64Value == $0.value }
        var samples = 0, periodic = 0, naturalLine: Int?, cleanupLine: Int?
        var measuredRSS = false, measuredCPU = false
        var statusSamples = 0, statusNamesIsolated = true
        try forEachLine(root.appendingPathComponent("telemetry.jsonl")) { record in
            samples += 1
            if record["label"] as? String == "periodic" { periodic += 1 }
            if record["label"] as? String == "naturalEnd" { naturalLine = samples }
            if record["label"] as? String == "resourcesAfterCleanup" { cleanupLine = samples }
            if let rss = number(record, "rssBytes"), rss.isFinite && rss > 0 { measuredRSS = true }
            if let cpu = number(record, "processCPUSeconds"), cpu.isFinite && cpu > 0,
               let percent = number(record, "intervalCPUPercentOneCore"), percent.isFinite && percent >= 0 { measuredCPU = true }
            if ["started", "periodic", "naturalEnd", "resourcesAfterCleanup", "resourcesAfterIODrain"].contains(record["label"] as? String ?? "") {
                statusSamples += 1
                let persistence = record["persistence"] as? [String: Any] ?? [:]
                statusNamesIsolated = statusNamesIsolated && persistence["statusItemPresent"] as? Bool == true &&
                    persistence["statusAutosaveName"] as? String == autosaveName &&
                    persistence["statusAutosaveMode"] as? String == "sessionUniqueName" &&
                    persistence["statusAutosaveIsolated"] as? Bool == true && persistence["standardDefaultsRedirected"] as? Bool == false
            }
        }
        checks["soakSmokePeriodicNativeProcessMeasurementsExist"] = periodic >= 2 && measuredRSS && measuredCPU
        checks["soakSmokeNaturalSnapshotPrecedesCleanup"] = naturalLine != nil && cleanupLine != nil && naturalLine! < cleanupLine!
        checks["soakSmokeActualStatusNameIsolatedThroughoutRecordedLifetime"] = statusSamples >= periodic + 3 && statusNamesIsolated
        return checks
    }

    /// Bounded reader also works for an eight-hour event stream. Never loads
    /// the full JSONL into memory or silently accepts a truncated final line.
    private static func forEachLine(_ url: URL, body: ([String: Any]) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw DesktopSoakSession.SessionError.invalid("invalid JSONL object")
                }
                try body(object)
            }
            guard pending.count <= 262_144 else { throw DesktopSoakSession.SessionError.invalid("oversized JSONL line") }
        }
        guard pending.isEmpty else { throw DesktopSoakSession.SessionError.invalid("truncated JSONL stream") }
    }
}
