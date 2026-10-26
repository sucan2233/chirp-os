import AppKit
import BirdingCore

extension ObservationJournalUIVerification {
    /// Coordinator entry point after all implementation is complete. The caller
    /// supplies an isolated desktop with the production artwork already loaded.
    static func verifyGalleryPreviewCapabilities(desktop: DesktopController, into checks: inout [String: Bool]) {
        guard desktop.isolatedSession else {
            checks["galleryCapabilityVerificationRequiresIsolation"] = false
            return
        }
        let originalLanguage = desktop.language
        let archive = desktop.observationJournal.archive
        let revision = desktop.observationJournal.revision
        let handbook = ObservationJournalWindow(desktop: desktop)
        defer {
            handbook.window?.close()
            desktop.language = originalLanguage
        }
        handbook.showWindow(nil)
        handbook.selectAllSpecies()
        let expansion = desktop.catalog.species.map(\.id).filter {
            SpeciesBehaviorProfile.profile(for: $0).isExpansionSpecies
        }
        for language in [AppLanguage.chinese, .english] {
            desktop.language = language
            handbook.relocalize()
            for species in expansion {
                handbook.selectSpecies(species)
                let frames = Set(desktop.arts[species]?.frames.keys.map {$0} ?? [])
                let audit = SpeciesSupportAudit(species: species, availableFrames: frames)
                let supported = audit.behaviors.filter {$0.kind != .relocate && $0.contentSupported}
                let key = "galleryCapability-\(language.rawValue)-\(species.rawValue)"
                let detail = handbook.detailText.string
                let row = handbook.renderedSpecies.firstIndex(of: species)!
                let cell = handbook.tableView(handbook.speciesTableView,
                    viewFor: handbook.speciesTableView.tableColumns.first, row: row) as? NSTableCellView
                let rowText = cell?.textField?.stringValue ?? ""
                if supported.isEmpty {
                    let unavailable = language.text("暂无可收集动作", "No collectible actions yet")
                    let basicArt = language.text("基础素材可预览", "Basic art available")
                    checks[key + "-explainsNoCollectibles"] = detail.contains(unavailable) && rowText.contains(unavailable) &&
                        !detail.contains("0 / 0") && !rowText.contains("0 / 0")
                    checks[key + "-basicArtMatchesAudit"] = audit.capabilities.contains(.standing) &&
                        detail.contains(basicArt) && rowText.contains(basicArt)
                } else {
                    let progress = language.text("已观察动作", "Observed actions")
                    checks[key + "-denominatorMatchesAudit"] = detail.contains(progress) &&
                        detail.contains(" / \(supported.count)") && rowText.contains(" / \(supported.count)") &&
                        !detail.contains(language.text("暂无可收集动作", "No collectible actions yet"))
                    checks[key + "-listsSupportedActions"] = supported.allSatisfy {
                        detail.contains(handbook.behaviorName($0.kind.rawValue))
                    }
                }
                handbook.previewAction.selectedSegment = 3
                _ = handbook.previewAction.sendAction(handbook.previewAction.action, to: handbook.previewAction.target)
                let preview = handbook.previewView
                let sampled = (0..<300).map {preview.frameName(at: Double($0) / 30)}
                checks[key + "-otherSelectionUsesAvailableArt"] = preview.action == .other &&
                    !preview.silhouette && Set(sampled).count > 1 && sampled.allSatisfy {frames.contains($0)}
                checks[key + "-otherSelectionUsesGallery"] = (0..<300).allSatisfy {
                    let profile = desktop.catalog.profile(species)
                    return sampled[$0] == GalleryPose.frame(species, age: Double($0) / 30,
                        fps: profile.flapFPS, action: .other, speedMultiplier: profile.speed)
                }
            }
            checks["galleryPreviewHelp-\(language.rawValue)"] = handbook.previewAction.toolTip?.contains(
                language.text("预览不解锁鸟种或动作", "Previews unlock neither species nor actions")) == true
        }
        handbook.previewAction.selectedSegment = 0
        _ = handbook.previewAction.sendAction(handbook.previewAction.action, to: handbook.previewAction.target)
        checks["galleryStillSelectionStaysStill"] = handbook.previewView.frameName(at: 10) == "stand"
        handbook.previewView.action = .other
        handbook.previewView.silhouette = true
        checks["galleryUndiscoveredSilhouetteStaysStill"] = handbook.previewView.frameName(at: 10) == "stand"
        checks["galleryPreviewsNeverMutateJournal"] = desktop.observationJournal.archive == archive &&
            desktop.observationJournal.revision == revision
    }
}
