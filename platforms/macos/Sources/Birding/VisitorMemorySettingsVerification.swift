import AppKit
import BirdingCore

/// Exercises native controls without starting a desktop, population or timers.
enum VisitorMemorySettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("visitor-memory-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        let suite="Birding.VisitorMemorySettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {
            throw NSError(domain:"VisitorMemorySettingsVerification",code:1)
        }
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=isolatedDesktop(preferences:preferences,folder:evidence)
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["visitorMemoryDefaultsOnWithoutCreatingSettings"]=defaults.visitorMemoryEnabled &&
            defaults.schemaVersion==BirdSettings.currentSchemaVersion && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        try checkMigration(into:&checks)

        let cancelled=SpeciesSettingsWindow(desktop:d)
        cancelled.showWindow(nil)
        cancelled.visitorMemoryButton.performClick(nil)
        checks["visitorMemoryToggleOnlyChangesDraft"] = !cancelled.draft.visitorMemoryEnabled &&
            cancelled.visitorMemoryButton.state == .off && d.settings.visitorMemoryEnabled &&
            cancelled.message.stringValue==cancelled.t("尚未保存","Unsaved changes")
        cancelled.cancel()
        checks["visitorMemoryCancelDiscardsEdit"] = !cancelled.draft.visitorMemoryEnabled &&
            cancelled.window?.isVisible == false && d.settings.visitorMemoryEnabled &&
            !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel()}
        w.tabs.selectTabViewItem(at:2)
        checks["visitorMemoryReopenRestoresDefaults"]=w !== cancelled && w.draft.visitorMemoryEnabled &&
            w.visitorMemoryButton.state == .on && w.visitorMemoryButton.isEnabled
        for master in [false,true] {
            set(w.perchActionsButton,to:master)
            for enabled in [false,true] {
                set(w.visitorMemoryButton,to:enabled)
                let suffix="-perch-\(master)-memory-\(enabled)"
                checks["visitorMemoryIndependentControl"+suffix]=w.visitorMemoryButton.isEnabled &&
                    w.draft.perchActions==master && w.draft.visitorMemoryEnabled==enabled &&
                    w.draft.passiveAttentionEnabled && w.draft.sideHopEnabled && w.draft.takeoffPreparationEnabled
                // Rebuilding must not turn the independent switch into a child
                // of the perch master or clear any disabled child preferences.
                w.relocalize()
                checks["visitorMemoryRebuildKeepsIndependentControl"+suffix]=w.visitorMemoryButton.isEnabled &&
                    w.visitorMemoryButton.state == (enabled ? .on:.off) && w.draft.visitorMemoryEnabled==enabled &&
                    w.draft.perchActions==master && w.draft.passiveAttentionEnabled &&
                    w.draft.sideHopEnabled && w.draft.takeoffPreparationEnabled
                w.save()
                let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
                let object=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as? [String:Any]
                checks["visitorMemorySaveAppliesExactCombination"+suffix]=saved.visitorMemoryEnabled==enabled &&
                    saved.perchActions==master && d.settings.visitorMemoryEnabled==enabled && d.settings.perchActions==master &&
                    (object?["visitorMemoryEnabled"] as? Bool)==enabled && (object?["schemaVersion"] as? Int)==BirdSettings.currentSchemaVersion
                let reloaded=isolatedDesktop(preferences:preferences,folder:evidence)
                try reloaded.loadSpeciesConfig()
                checks["visitorMemoryReloadKeepsExactCombination"+suffix]=reloaded.settings.visitorMemoryEnabled==enabled &&
                    reloaded.settings.perchActions==master
            }
        }

        // Saved memory is on while the unsaved switch is off, with the perch
        // master off, so both rebuilding and failed saving have observable state.
        set(w.perchActionsButton,to:false);w.save()
        set(w.visitorMemoryButton,to:false)
        w.hoverDelayField.stringValue="0.25";w.detailFields[0][2].stringValue="1.25"
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            let suffix=language == .chinese ? "zh":"en"
            checks["visitorMemoryDraftSurvivesLanguageChange-"+suffix] = !w.draft.visitorMemoryEnabled &&
                w.visitorMemoryButton.state == .off && w.visitorMemoryButton.isEnabled &&
                !w.draft.perchActions && d.settings.visitorMemoryEnabled && !d.settings.perchActions &&
                w.hoverDelayField.stringValue=="0.25" && w.detailFields[0][2].stringValue=="1.25" &&
                (w.tabs.selectedTabViewItem?.identifier as? String)=="interaction"
            try checkLayout(w,suffix:suffix,folder:evidence,checks:&checks)
        }

        let savedURL=d.settingsURL,before=try Data(contentsOf:savedURL)
        d.settingsURL=evidence
        w.save()
        d.settingsURL=savedURL
        let afterFailure=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
        let afterFailureData=try Data(contentsOf:savedURL)
        checks["visitorMemoryFailedSaveKeepsCurrentAndFile"] = !w.draft.visitorMemoryEnabled &&
            d.settings.visitorMemoryEnabled && afterFailure.visitorMemoryEnabled && !d.settings.perchActions &&
            d.settings.hoverDelay==1 && d.settings.catalog.species[0].speed==SpeciesCatalog.standard.species[0].speed &&
            afterFailureData==before &&
            w.message.stringValue==w.t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.")

        w.save()
        let disabled=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
        checks["visitorMemoryOffSavedAndApplied"] = !d.settings.visitorMemoryEnabled &&
            !disabled.visitorMemoryEnabled
        w.resetDefaults()
        let beforeResetSave=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
        checks["visitorMemoryResetOnlyChangesDraft"]=w.draft.visitorMemoryEnabled &&
            w.visitorMemoryButton.state == .on && w.visitorMemoryButton.isEnabled &&
            !d.settings.visitorMemoryEnabled && !beforeResetSave.visitorMemoryEnabled
        w.save()
        let restored=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
        checks["visitorMemoryRestoredDefaultsSavedAndApplied"]=d.settings.visitorMemoryEnabled &&
            restored.visitorMemoryEnabled
        checks["visitorMemoryVerificationNeverStartsDesktop"]=d.timer==nil && d.panels.isEmpty && d.views.isEmpty &&
            d.birds.isEmpty && !d.automaticPopulation && !d.engine.populationEnabled && !d.engine.ambientEnabled &&
            !d.visitorMemoryPersistenceEnabled && d.visitorMemoryPersistence==nil &&
            !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path)
    }

    private static func isolatedDesktop(preferences:UserDefaults,folder:URL) -> DesktopController {
        let d=DesktopController();d.preferences=preferences;d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.settingsURL=folder.appendingPathComponent("settings.json")
        d.legacyURL=folder.appendingPathComponent("legacy.json")
        d.visitorMemoryPersistenceEnabled=false
        d.visitorMemoryURL=folder.appendingPathComponent("visitors.json")
        return d
    }

    private static func set(_ button:NSButton,to enabled:Bool) {
        if (button.state == .on) != enabled {button.performClick(nil)}
    }

    private static func checkMigration(into checks:inout [String:Bool]) throws {
        var original=BirdSettings();original.visitorMemoryEnabled=false;original.perchActions=false
        original.catalog.species[0].speed=1.25;original.probabilities.setManualWeight(at:0,to:1234)
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            for nullValue in [false,true] {
                var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
                if let version {object["schemaVersion"]=version}
                else {object["schemaVersion"]=BirdSettings.currentSchemaVersion}
                if nullValue {object["visitorMemoryEnabled"]=NSNull()}
                else {object.removeValue(forKey:"visitorMemoryEnabled")}
                let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:object))
                let suffix="-version-\(version.map{String($0)} ?? "missing")-null-\(nullValue)"
                checks["visitorMemoryAdditiveMigration"+suffix]=migrated.visitorMemoryEnabled && migrated.schemaVersion==BirdSettings.currentSchemaVersion &&
                    !migrated.perchActions && migrated.catalog.species==original.catalog.species &&
                    migrated.probabilities==original.probabilities
            }
        }
    }

    private static func checkLayout(_ w:SpeciesSettingsWindow,suffix:String,folder:URL,checks:inout [String:Bool]) throws {
        let prefix="visitorMemoryLayout-"+suffix
        for name in ["Labels","ExistingPositions","Reachable","TitlesFit","HelpFits","NoOverlap","Screenshot"] {
            checks[prefix+name]=false
        }
        w.tabs.selectTabViewItem(at:2)
        checks[prefix+"Labels"]=w.visitorMemoryButton.title==w.t("记住熟客与安静相处","Remember returning visitors")
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return}
        func label(_ identifier:String) -> NSTextField? {
            document.subviews.compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue==identifier}
        }
        let heading=label("visitorMemorySectionTitle"),help=label("visitorMemoryHelp")
        guard let heading else {return}
        // Rhythm settings follow this section; scrolling to the bottom would
        // hide the visitor controls. Navigate by the section's stable heading.
        let top=max(0,heading.frame.minY-12)
        let limit=max(0,document.bounds.height-scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:CGPoint(x:0,y:min(top,limit)))
        scroll.reflectScrolledClipView(scroll.contentView)
        w.window?.contentView?.layoutSubtreeIfNeeded()
        checks[prefix+"ExistingPositions"]=label("leafSectionTitle")?.frame.minY==1600 &&
            w.leafPlayButton.frame.minY==1642 && w.releaseLeafButton.frame.minY==1808 &&
            w.sideHopButton.frame.minY==1322 && w.previewSideHopButton.frame.minY==1480 &&
            heading.frame.minY==1960 && document.bounds.height>1940
        checks[prefix+"Reachable"] = !w.visitorMemoryButton.isHidden && document.visibleRect.contains(w.visitorMemoryButton.frame) &&
            document.visibleRect.contains(heading.frame)
        checks[prefix+"TitlesFit"]=w.visitorMemoryButton.intrinsicContentSize.width<=w.visitorMemoryButton.frame.width &&
            w.visitorMemoryButton.intrinsicContentSize.height<=w.visitorMemoryButton.frame.height &&
            (heading.cell?.cellSize(forBounds:heading.bounds).height ?? .infinity)<=heading.frame.height
        checks[prefix+"HelpFits"]=help.map {
            !$0.stringValue.isEmpty && document.visibleRect.contains($0.frame) &&
                ($0.cell?.cellSize(forBounds:$0.bounds).height ?? .infinity)<=$0.frame.height
        } == true
        checks[prefix+"NoOverlap"]=document.subviews.enumerated().allSatisfy {index,view in
            document.bounds.contains(view.frame) && document.subviews.dropFirst(index+1).allSatisfy{!view.frame.intersects($0.frame)}
        }
        let url=folder.appendingPathComponent("visitor-memory-settings-"+suffix+".png")
        try SettingsVerification.snapshot(w.window!,to:url)
        checks[prefix+"Screenshot"]=NSImage(contentsOf:url).map{$0.size.width>0 && $0.size.height>0} ?? false
    }
}
