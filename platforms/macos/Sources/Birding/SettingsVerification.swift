import AppKit
import BirdingCore
import ServiceManagement

enum SettingsVerification {
    static func run(to folder:URL) {
        var checks:[String:Bool]=[:]
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let suite="Birding.SettingsVerification."+UUID().uuidString
            let prefs=UserDefaults(suiteName:suite)!
            defer { prefs.removePersistentDomain(forName:suite) }
            let d=DesktopController();d.preferences=prefs
            d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
            let login = VerificationLoginItem(); d.loginService = login
            d.makeMenu()
            checks["loginInitiallyOff"] = d.loginItem?.state == .off && d.loginItem?.title == "随系统启动" && login.registerCalls == 0
            d.toggleLoginItem()
            checks["loginEnable"] = login.registerCalls == 1 && d.loginItem?.state == .on
            d.toggleLoginItem()
            checks["loginDisable"] = login.unregisterCalls == 1 && d.loginItem?.state == .off
            login.status = .requiresApproval; d.menuWillOpen(d.status.menu!)
            checks["loginApprovalVisible"] = d.loginItem?.state == .mixed && d.loginApprovalItem?.isHidden == false
            d.toggleLoginItem()
            checks["loginPendingCanCancel"] = login.unregisterCalls == 2 && d.loginItem?.state == .off && d.loginApprovalItem?.isHidden == true
            login.status = .enabled; d.menuWillOpen(d.status.menu!)
            checks["loginExternalChangeRefreshes"] = d.loginItem?.state == .on
            d.showSpeciesSettings()
            let w=d.settingsWindow!
            checks["hoverDelayDefaultsToOneSecond"] = w.hoverDelayField.doubleValue == 1 && w.hoverDelaySlider.doubleValue == 1
            checks["perchActivitiesDefaultOn"] = w.draft.perchActions && d.settings.perchActions && w.perchActionsButton.state == .on
            checks["perchActivitiesChineseLabels"] = w.perchActionsButton.title == "停栖小动作" && w.previewRestButton.title == "预览闭眼休息" && w.previewPreenButton.title == "预览整理羽毛"
            w.perchActionsButton.performClick(nil)
            checks["perchToggleOnlyChangesDraft"] = !w.draft.perchActions && w.perchActionsButton.state == .off && d.settings.perchActions
            w.hoverDelaySlider.doubleValue=0.5;w.hoverDelayChanged(w.hoverDelaySlider)
            checks["hoverDelaySliderUpdatesDraft"] = w.draft.hoverDelay == 0.5 && w.hoverDelayField.doubleValue == 0.5 && d.settings.hoverDelay == 1
            w.hoverDelayField.stringValue="0.25"
            w.controlTextDidEndEditing(Notification(name:NSControl.textDidEndEditingNotification,object:w.hoverDelayField))
            checks["hoverDelayAcceptsTypedDecimals"] = w.draft.hoverDelay == 0.25 && w.hoverDelaySlider.doubleValue == 0.25
            for invalid in ["-1","10.1","NaN","abc"] {
                w.hoverDelayField.stringValue=invalid;w.save()
                checks["invalidHoverDelayRejected-\(invalid)"] = d.settings.hoverDelay == 1 && !FileManager.default.fileExists(atPath:d.settingsURL.path) && (w.tabs.selectedTabViewItem?.identifier as? String) == "interaction"
            }
            w.hoverDelayField.stringValue="0.25"
            checks["allSpeciesEditable"] = w.sliders.count == SpeciesID.allCases.count && w.fields.count == SpeciesID.allCases.count && w.locks.count == SpeciesID.allCases.count
            let last=w.sliders.count-1
            w.sliders[last].doubleValue=3;w.sliderChanged(w.sliders[last])
            checks["lastSpeciesEditable"] = w.draft.probabilities.entries[last].points == 300
            checks["scrollableSpeciesPages"] = w.tabs.tabViewItems.allSatisfy { ($0.view as? NSScrollView)?.hasVerticalScroller == true }
            w.sliders[0].doubleValue=35;w.sliderChanged(w.sliders[0])
            checks["sliderUpdatesPercentAndTotal"] = w.fields[0].stringValue == "35.00" && w.draft.probabilities.isValid
            w.locks[0].performClick(nil)
            checks["lockDisablesSliderAndField"] = !w.sliders[0].isEnabled && !w.fields[0].isEnabled
            w.fields[1].stringValue="80"
            w.controlTextDidEndEditing(Notification(name:NSControl.textDidEndEditingNotification,object:w.fields[1]))
            checks["typedInputClampsAndPreservesLock"] = w.draft.probabilities.entries[0].points==3500 && w.draft.probabilities.entries[1].points==6500
            w.fields[1].stringValue="32.25"
            w.controlTextDidEndEditing(Notification(name:NSControl.textDidEndEditingNotification,object:w.fields[1]))
            checks["typedInputUpdatesSliderAndOtherRows"] = w.sliders[1].doubleValue == 32.25 && w.draft.probabilities.isValid && w.draft.probabilities.entries[2].points > 0
            let before=w.draft.probabilities
            w.fields[1].stringValue="NaN"
            w.controlTextDidEndEditing(Notification(name:NSControl.textDidEndEditingNotification,object:w.fields[1]))
            checks["invalidTextDoesNotChangeProbabilities"] = before == w.draft.probabilities
            w.detailFields[0][2].stringValue="9"
            w.save()
            checks["invalidBehaviorNotSaved"] = !FileManager.default.fileExists(atPath:d.settingsURL.path)
            w.detailFields[0][2].stringValue="1.25"
            d.paused=true;d.makeMenu();d.toggleLanguage()
            checks["loginEnglishLabel"] = d.loginItem?.title == "Launch at Login" && d.loginItem?.state == .on
            checks["englishMenuAndWindow"] = d.status.menu!.items.contains{$0.title == "中文"} && d.status.menu!.items.contains{$0.title=="Resume animation"} && w.window!.title == "Bird Settings"
            checks["languageKeepsUnsavedEdits"] = w.draft.probabilities == before && w.detailFields[0][2].stringValue == "1.25" && w.hoverDelayField.stringValue == "0.25"
            checks["perchDraftSurvivesLanguageChange"] = !w.draft.perchActions && w.perchActionsButton.state == .off && d.settings.perchActions
            checks["perchActivitiesEnglishLabels"] = w.perchActionsButton.title == "Perch activities" && w.previewRestButton.title == "Preview eyes-closed rest" && w.previewPreenButton.title == "Preview preening"
            for (name,button) in [("rest",w.previewRestButton!),("preen",w.previewPreenButton!)] {
                let sequence=d.engine.events.last?.sequence
                button.performClick(nil)
                checks["perchPreviewPaused-\(name)"] = d.engine.events.last?.sequence != sequence && d.engine.events.last?.reason == .paused && d.engine.events.last?.source == .preview && w.message.stringValue == d.behaviorMessage(.paused)
            }
            w.save()
            let saved=try BirdSettings.decode(Data(contentsOf:d.settingsURL))
            checks["saveAndReloadPreserveProbabilitiesLocksAndBehavior"] = saved.probabilities == w.draft.probabilities && saved.catalog.profile(.redWhiskeredBulbul).speed == 1.25
            checks["hoverDelaySavedAndAppliedImmediately"] = saved.hoverDelay == 0.25 && d.settings.hoverDelay == 0.25
            checks["perchSettingSavedAndAppliedImmediately"] = !saved.perchActions && !d.settings.perchActions
            let reloaded=DesktopController();reloaded.settingsURL=d.settingsURL;reloaded.legacyURL=d.legacyURL
            try reloaded.loadSpeciesConfig()
            checks["hoverDelaySurvivesRestart"] = reloaded.settings.hoverDelay == 0.25
            checks["perchSettingSurvivesRestart"] = !reloaded.settings.perchActions
            // The UI may contain an enabled draft while the saved switch is off.
            // Both buttons must still go through the engine's saved-settings gate.
            d.paused=false;w.perchActionsButton.performClick(nil)
            for (name,button) in [("rest",w.previewRestButton!),("preen",w.previewPreenButton!)] {
                let sequence=d.engine.events.last?.sequence
                button.performClick(nil)
                checks["perchPreviewUsesSavedSwitch-\(name)"] = w.draft.perchActions && !d.settings.perchActions && d.engine.events.last?.sequence != sequence && d.engine.events.last?.reason == .disabled && d.engine.events.last?.source == .preview && w.message.stringValue == d.behaviorMessage(.disabled)
            }
            let settingsURL=d.settingsURL
            d.settingsURL=folder // Writing settings over an existing directory must fail.
            w.save();d.settingsURL=settingsURL
            let afterFailedSave=try BirdSettings.decode(Data(contentsOf:settingsURL))
            checks["failedPerchSavePreservesActiveAndStoredSettings"] = w.draft.perchActions && !d.settings.perchActions && !afterFailedSave.perchActions && w.message.stringValue == "Could not save. Try again; active settings are unchanged."
            w.perchActionsButton.performClick(nil);d.paused=true
            w.tabs.selectTabViewItem(at:2)
            try snapshot(w.window!,to:folder.appendingPathComponent("interaction-en.png"))
            if let scroll=w.tabs.tabViewItems[2].view as? NSScrollView {
                scroll.contentView.scroll(to:CGPoint(x:0,y:200));scroll.reflectScrolledClipView(scroll.contentView)
                try snapshot(w.window!,to:folder.appendingPathComponent("encounters-en.png"))
                scroll.contentView.scroll(to:CGPoint(x:0,y:scroll.documentView!.bounds.height-scroll.contentView.bounds.height));scroll.reflectScrolledClipView(scroll.contentView)
                checks["perchPreviewsReachableEnglish"] = scroll.documentView!.visibleRect.contains(w.perchActionsButton.frame) && scroll.documentView!.visibleRect.contains(w.previewRestButton.frame) && scroll.documentView!.visibleRect.contains(w.previewPreenButton.frame)
                try snapshot(w.window!,to:folder.appendingPathComponent("perch-activities-en.png"))
            }
            checks["languagePreferenceSaved"] = prefs.string(forKey:"appLanguage") == "en"
            w.tabs.selectTabViewItem(at:0)
            try snapshot(w.window!,to:folder.appendingPathComponent("settings-en.png"))
            w.tabs.selectTabViewItem(at:1)
            try snapshot(w.window!,to:folder.appendingPathComponent("behavior-en.png"))
            d.toggleLanguage();w.tabs.selectTabViewItem(at:0)
            checks["chineseToggleRestored"] = d.status.menu!.items.contains{$0.title == "English"} && w.window!.title == "鸟种设置"
            checks["perchChineseToggleRestored"] = !w.draft.perchActions && w.perchActionsButton.state == .off && w.perchActionsButton.title == "停栖小动作" && w.previewRestButton.title == "预览闭眼休息" && w.previewPreenButton.title == "预览整理羽毛"
            w.tabs.selectTabViewItem(at:2)
            try snapshot(w.window!,to:folder.appendingPathComponent("interaction-zh.png"))
            if let scroll=w.tabs.tabViewItems[2].view as? NSScrollView {
                scroll.contentView.scroll(to:CGPoint(x:0,y:200));scroll.reflectScrolledClipView(scroll.contentView)
                try snapshot(w.window!,to:folder.appendingPathComponent("encounters-zh.png"))
                scroll.contentView.scroll(to:CGPoint(x:0,y:scroll.documentView!.bounds.height-scroll.contentView.bounds.height));scroll.reflectScrolledClipView(scroll.contentView)
                checks["perchPreviewsReachableChinese"] = scroll.documentView!.visibleRect.contains(w.perchActionsButton.frame) && scroll.documentView!.visibleRect.contains(w.previewRestButton.frame) && scroll.documentView!.visibleRect.contains(w.previewPreenButton.frame)
                try snapshot(w.window!,to:folder.appendingPathComponent("perch-activities-zh.png"))
            }
            w.pointerVisitsButton.performClick(nil);w.flockPassesButton.performClick(nil)
            w.ambientFrequencyPopup.selectItem(at:2);w.ambientSettingsChanged()
            w.relocalize()
            checks["ambientDraftSurvivesRebuild"] = !w.draft.pointerVisits && !w.draft.flockPasses && w.ambientFrequencyPopup.indexOfSelectedItem == 2
            w.save()
            let ambientSaved=try BirdSettings.decode(Data(contentsOf:d.settingsURL))
            checks["ambientSettingsPersistAndApply"] = !ambientSaved.pointerVisits && !d.settings.pointerVisits && !ambientSaved.flockPasses && ambientSaved.ambientFrequency == .high
            checks["ambientEditsPreservePerchAndHoverSettings"] = !ambientSaved.perchActions && !d.settings.perchActions && ambientSaved.hoverDelay == 0.25 && d.settings.hoverDelay == 0.25
            var oldObject=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as! [String:Any]
            oldObject.removeValue(forKey:"perchActions")
            let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:oldObject))
            checks["oldSettingsEnablePerchWithoutLosingOtherEdits"] = migrated.perchActions && migrated.hoverDelay == ambientSaved.hoverDelay && migrated.pointerVisits == ambientSaved.pointerVisits && migrated.flockPasses == ambientSaved.flockPasses && migrated.ambientFrequency == ambientSaved.ambientFrequency && migrated.probabilities == ambientSaved.probabilities && migrated.catalog.species == ambientSaved.catalog.species
            w.tabs.selectTabViewItem(at:0)
            try snapshot(w.window!,to:folder.appendingPathComponent("settings-zh.png"))
            for i in w.locks.indices where w.locks[i].state == .off { w.locks[i].performClick(nil) }
            checks["allLockedDisablesAllEditors"] = w.sliders.allSatisfy{!$0.isEnabled} && w.fields.allSatisfy{!$0.isEnabled}
            if let scroll=w.tabs.tabViewItems[0].view as? NSScrollView, let doc=scroll.documentView {
                scroll.contentView.scroll(to:CGPoint(x:0,y:doc.bounds.height-scroll.contentView.bounds.height))
                scroll.reflectScrolledClipView(scroll.contentView)
                checks["lastSpeciesReachable"] = doc.visibleRect.maxY >= w.locks.last!.frame.maxY
                w.tabs.selectTabViewItem(at:0)
                try snapshot(w.window!,to:folder.appendingPathComponent("settings-last.png"))
            }
            for delay in [0.0,10.0] {
                w.hoverDelayField.stringValue=String(delay);w.save()
                let boundary=try BirdSettings.decode(Data(contentsOf:d.settingsURL))
                checks["hoverDelayBoundarySaved-\(delay)"] = boundary.hoverDelay == delay && d.settings.hoverDelay == delay
            }
            w.resetDefaults()
            checks["ambientDefaultsRestored"] = w.draft.pointerVisits && w.draft.flockPasses && w.draft.ambientFrequency == .low
            checks["resetRestoresDefaultsAndUnlocks"] = w.draft.probabilities == BirdSettings().probabilities && w.draft.hoverDelay == 1 && w.hoverDelayField.doubleValue == 1
            checks["perchDefaultsRestoredWithoutApplying"] = w.draft.perchActions && w.perchActionsButton.state == .on && !d.settings.perchActions
            w.save()
            let defaultsSaved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
            checks["perchDefaultsSaveAndReload"] = defaultsSaved.perchActions && d.settings.perchActions && defaultsSaved.hoverDelay == 1 && defaultsSaved.pointerVisits && defaultsSaved.flockPasses && defaultsSaved.ambientFrequency == .low
            w.scrollToSpecies(.nightHeron)
            if let scroll=w.tabs.tabViewItems[0].view as? NSScrollView {
                checks["manualMigrationScrollsToFirstNewBird"] = scroll.documentView!.visibleRect.intersects(w.fields[7].frame)
            }
            w.cancel()
            d.showSpeciesGallery()
            checks["galleryMenuAndWindow"] = d.status.menu!.items.contains{$0.title=="图鉴…"} && d.gallery?.window?.isVisible == true
            if let gallery=d.gallery?.window {
                try snapshot(gallery,to:folder.appendingPathComponent("gallery.png"))
                let scroll=gallery.contentView!.subviews.first(where:{$0 is NSScrollView}) as! NSScrollView
                let grid=scroll.documentView as! BirdGalleryView
                let actions=gallery.contentView!.subviews.first(where:{$0 is NSSegmentedControl}) as! NSSegmentedControl
                checks["galleryActionPicker"] = actions.segmentCount == GalleryAction.allCases.count && grid.action == .resting
                for action in GalleryAction.allCases {
                    actions.selectedSegment=action.rawValue
                    actions.sendAction(actions.action!,to:actions.target)
                    checks["gallerySelect\(action)"] = grid.action == action
                    grid.started=ProcessInfo.processInfo.systemUptime-3.5
                    try snapshot(gallery,to:folder.appendingPathComponent("gallery-\(action).png"))
                }
                scroll.contentView.scroll(to:CGPoint(x:0,y:grid.cellHeight*2))
                actions.selectedSegment=GalleryAction.gliding.rawValue
                actions.sendAction(actions.action!,to:actions.target)
                try snapshot(gallery,to:folder.appendingPathComponent("gallery-raptors.png"))
                checks["actionPickerRemainsAboveScroll"] = actions.frame.minY >= scroll.frame.maxY
                checks["galleryIncludesAllRows"] = grid.frame.height == CGFloat((SpeciesID.allCases.count+grid.columns-1)/grid.columns)*grid.cellHeight
                checks["galleryFitsActualBirdSizes"] = grid.cellWidth >= 48*grid.maxScale && grid.cellHeight > 48*grid.maxScale
                gallery.close()
            }
            NSStatusBar.system.removeStatusItem(d.status)
            let passed=checks.values.allSatisfy{$0}
            saveJSON(["passed":passed,"checks":checks],to:folder.appendingPathComponent("report.json"))
            print("Settings UI: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
            exit(passed ? 0:1)
        } catch {
            saveJSON(["passed":false,"error":error.localizedDescription,"checks":checks],to:folder.appendingPathComponent("report.json"));exit(1)
        }
    }
    static func snapshot(_ window:NSWindow,to url:URL) throws {
        RunLoop.current.run(until:Date().addingTimeInterval(0.2))
        window.displayIfNeeded()
        let view=window.contentView!;view.layoutSubtreeIfNeeded()
        func inspect(_ v:NSView) -> [String:Any] {
            ["class":String(describing:type(of:v)),"frame":NSStringFromRect(v.frame),"hidden":v.isHidden,"text":(v as? NSTextField)?.stringValue ?? "","children":v.subviews.map(inspect)]
        }
        saveJSON(inspect(view),to:url.deletingPathExtension().appendingPathExtension("json"))
        func invalidate(_ v:NSView) {
            v.needsDisplay=true
            for child in v.subviews { invalidate(child) }
        }
        invalidate(view)
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(view.bounds.width),pixelsHigh:Int(view.bounds.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let graphics=NSGraphicsContext(bitmapImageRep:bitmap)!
        view.displayIfNeeded()
        let ctx=graphics.cgContext
        if view.isFlipped {ctx.translateBy(x:0,y:view.bounds.height);ctx.scaleBy(x:1,y:-1)}
        view.layer?.render(in:ctx)
        guard let png=bitmap.representation(using:.png,properties:[:]) else { throw NSError(domain:"Snapshot",code:2) }
        try png.write(to:url)
    }
}

// Test menu actions without changing the user's system login items.
private final class VerificationLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var registerCalls = 0
    var unregisterCalls = 0
    func register() throws { registerCalls += 1; status = .enabled }
    func unregister() throws { unregisterCalls += 1; status = .notRegistered }
}
