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
            func birdCounts() -> [Int] {
                [d.engine.birds.count,d.engine.residentCount,d.engine.passingCount,d.engine.departingCount,
                 d.engine.pendingCount,d.engine.arrivalCount,d.engine.departureCount]
            }
            d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
            let login = VerificationLoginItem(); d.loginService = login
            d.makeMenu()
            let status=d.status!
            checks["statusItemVisibleWithNamedTemplateIcon"] = status.isVisible && status.autosaveName == "ChirpOS.Main" && status.button?.image?.isTemplate == true && status.button?.image?.size == NSSize(width:18,height:18)
            d.status.isVisible=false;d.restoreStatusItem()
            checks["reopenRestoresSameStatusItemAndMenu"] = d.status === status && status.isVisible && status.menu?.items.contains{$0.action == #selector(DesktopController.showSpeciesSettings)} == true
            checks["developmentBuildIdentifiedInMenu"] = !d.isDevelopmentBuild || status.menu?.items.first?.title == "啾啾测试版 · 本地开发"
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
            let cancelledWindow=d.settingsWindow!
            cancelledWindow.pointerFollowButton.performClick(nil)
            checks["pointerFollowCancelledDraftWasEdited"] = cancelledWindow.draft.pointerFollowEnabled && !d.settings.pointerFollowEnabled
            cancelledWindow.socialInteractionsButton.performClick(nil)
            checks["socialCancelledDraftWasEdited"] = !cancelledWindow.draft.socialInteractions && d.settings.socialInteractions
            cancelledWindow.cancel()
            checks["socialCancelDoesNotApplyOrSave"] = cancelledWindow.window?.isVisible == false && d.settings.socialInteractions && !FileManager.default.fileExists(atPath:d.settingsURL.path)
            checks["pointerFollowCancelDoesNotApplyOrSave"] = !d.settings.pointerFollowEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)
            d.showSpeciesSettings()
            let w=d.settingsWindow!
            checks["pointerFollowReopeningDiscardsCancelledDraft"] = w !== cancelledWindow && !w.draft.pointerFollowEnabled && w.pointerFollowButton.state == .off && w.pointerFollowButton.isEnabled
            checks["pointerFollowChineseLabel"] = w.pointerFollowButton.title == "绕飞时跟随鼠标移动"
            w.pointerFollowButton.performClick(nil)
            checks["pointerFollowToggleOnlyChangesDraft"] = w.draft.pointerFollowEnabled && !d.settings.pointerFollowEnabled
            checks["pointerPreviewMessageUsesSavedOffChinese"] = d.pointerVisitPreviewMessage == "正在预览绕鼠标飞行。移动鼠标或点击可结束。"
            w.pointerVisitsButton.performClick(nil)
            checks["pointerMasterDisablesFollowWithoutClearingDraft"] = !w.draft.pointerVisits && !w.pointerFollowButton.isEnabled && w.pointerFollowButton.state == .on && w.draft.pointerFollowEnabled
            w.pointerFollowButton.performClick(nil)
            checks["disabledPointerFollowCannotBeToggled"] = w.draft.pointerFollowEnabled && w.pointerFollowButton.state == .on
            w.pointerVisitsButton.performClick(nil)
            checks["pointerMasterReenablesFollowingPreference"] = w.draft.pointerVisits && w.pointerFollowButton.isEnabled && w.pointerFollowButton.state == .on
            checks["socialReopeningDiscardsCancelledDraft"] = w !== cancelledWindow && w.draft.socialInteractions && w.socialInteractionsButton.state == .on
            checks["socialInteractionsDefaultOn"] = w.draft.socialInteractions && d.settings.socialInteractions && w.socialInteractionsButton.state == .on
            checks["socialInteractionsChineseLabels"] = w.socialInteractionsButton.title == "双鸟互动" && w.previewSocialGreetingButton.title == "预览双鸟招呼"
            checkSocialMotionLabels(w,language:"Chinese",checks:&checks)
            w.socialInteractionsButton.performClick(nil)
            checks["socialToggleOnlyChangesDraft"] = !w.draft.socialInteractions && w.socialInteractionsButton.state == .off && d.settings.socialInteractions
            let beforeMissingCompanion=birdCounts(),beforeMissingCompanionSequence=d.engine.events.last?.sequence
            w.previewSocialGreetingButton.performClick(nil)
            checks["socialPreviewUsesSavedEnabledSwitch"] = !w.draft.socialInteractions && d.settings.socialInteractions && d.engine.events.last?.sequence != beforeMissingCompanionSequence && d.engine.events.last?.kind == .socialGreeting && d.engine.events.last?.source == .preview && d.engine.events.last?.type == .rejected && d.engine.events.last?.reason == .noCompanion
            checks["socialMissingCompanionExplainedChinese"] = w.message.stringValue == d.behaviorMessage(.noCompanion) && w.message.stringValue.contains("两只")
            checks["socialMissingCompanionDoesNotCreateBirds"] = birdCounts() == beforeMissingCompanion && d.engine.activeRunCount == 0 && d.engine.leasedBirdCount == 0
            checkSocialMotionRejections(w,reason:.noCompanion,language:"Chinese",checks:&checks)
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
            checks["socialDraftSurvivesLanguageChange"] = !w.draft.socialInteractions && w.socialInteractionsButton.state == .off && d.settings.socialInteractions
            checks["socialInteractionsEnglishLabels"] = w.socialInteractionsButton.title == "Two-bird interactions" && w.previewSocialGreetingButton.title == "Preview two-bird greeting"
            checkSocialMotionLabels(w,language:"English",checks:&checks)
            checks["pointerFollowDraftSurvivesLanguageChange"] = w.draft.pointerFollowEnabled && w.pointerFollowButton.state == .on && w.pointerFollowButton.isEnabled && !d.settings.pointerFollowEnabled
            checks["pointerFollowEnglishLabel"] = w.pointerFollowButton.title == "Follow pointer movement while circling"
            checks["pointerPreviewMessageUsesSavedOffEnglish"] = d.pointerVisitPreviewMessage == "Pointer visit started. Move the pointer or click to end it."
            d.paused=false
            checkSocialMotionRejections(w,reason:.noCompanion,language:"English",checks:&checks)
            d.paused=true
            let beforePausedGreeting=birdCounts(),beforePausedGreetingSequence=d.engine.events.last?.sequence
            w.previewSocialGreetingButton.performClick(nil)
            checks["socialPreviewPaused"] = d.engine.events.last?.sequence != beforePausedGreetingSequence && d.engine.events.last?.kind == .socialGreeting && d.engine.events.last?.source == .preview && d.engine.events.last?.reason == .paused && w.message.stringValue == d.behaviorMessage(.paused) && birdCounts() == beforePausedGreeting
            checkSocialMotionRejections(w,reason:.paused,language:"English",checks:&checks)
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
            checks["socialSettingSavedAndAppliedImmediately"] = !saved.socialInteractions && !d.settings.socialInteractions
            checks["pointerFollowSavedAndAppliedImmediately"] = saved.pointerFollowEnabled && d.settings.pointerFollowEnabled
            let reloaded=DesktopController();reloaded.settingsURL=d.settingsURL;reloaded.legacyURL=d.legacyURL
            try reloaded.loadSpeciesConfig()
            checks["hoverDelaySurvivesRestart"] = reloaded.settings.hoverDelay == 0.25
            checks["perchSettingSurvivesRestart"] = !reloaded.settings.perchActions
            checks["socialSettingSurvivesRestart"] = !reloaded.settings.socialInteractions
            checks["pointerFollowSurvivesRestart"] = reloaded.settings.pointerFollowEnabled
            w.pointerFollowButton.performClick(nil)
            checks["pointerPreviewMessageUsesSavedOnEnglish"] = !w.draft.pointerFollowEnabled && d.pointerVisitPreviewMessage == "Pointer visit started. Moving keeps it following; click to end it."
            // The UI may contain an enabled draft while the saved switch is off.
            // Both buttons must still go through the engine's saved-settings gate.
            d.paused=false;w.perchActionsButton.performClick(nil)
            w.socialInteractionsButton.performClick(nil)
            let beforeDisabledGreeting=birdCounts(),beforeDisabledGreetingSequence=d.engine.events.last?.sequence
            w.previewSocialGreetingButton.performClick(nil)
            checks["socialPreviewUsesSavedDisabledSwitch"] = w.draft.socialInteractions && !d.settings.socialInteractions && d.engine.events.last?.sequence != beforeDisabledGreetingSequence && d.engine.events.last?.kind == .socialGreeting && d.engine.events.last?.source == .preview && d.engine.events.last?.type == .rejected && d.engine.events.last?.reason == .disabled && w.message.stringValue == d.behaviorMessage(.disabled)
            checks["socialDisabledPreviewPreservesPopulation"] = birdCounts() == beforeDisabledGreeting && d.engine.activeRunCount == 0 && d.engine.leasedBirdCount == 0
            checkSocialMotionRejections(w,reason:.disabled,language:"English",checks:&checks)
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
            checks["failedSocialSavePreservesActiveAndStoredSettings"] = w.draft.socialInteractions && !d.settings.socialInteractions && !afterFailedSave.socialInteractions && w.message.stringValue == "Could not save. Try again; active settings are unchanged."
            checks["failedPointerFollowSavePreservesActiveAndStoredSettings"] = !w.draft.pointerFollowEnabled && d.settings.pointerFollowEnabled && afterFailedSave.pointerFollowEnabled
            w.pointerFollowButton.performClick(nil)
            w.socialInteractionsButton.performClick(nil)
            w.perchActionsButton.performClick(nil);d.paused=true
            w.tabs.selectTabViewItem(at:2)
            try snapshot(w.window!,to:folder.appendingPathComponent("interaction-en.png"))
            if let scroll=w.tabs.tabViewItems[2].view as? NSScrollView {
                scroll.contentView.scroll(to:CGPoint(x:0,y:200));scroll.reflectScrolledClipView(scroll.contentView)
                try snapshot(w.window!,to:folder.appendingPathComponent("encounters-en.png"))
                checkSocialLayout(w,language:"English",checks:&checks)
                try snapshot(w.window!,to:folder.appendingPathComponent("social-greetings-en.png"))
                scroll.contentView.scroll(to:CGPoint(x:0,y:w.perchActionsButton.frame.minY-42));scroll.reflectScrolledClipView(scroll.contentView)
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
            checks["socialChineseToggleRestored"] = !w.draft.socialInteractions && w.socialInteractionsButton.state == .off && w.socialInteractionsButton.title == "双鸟互动" && w.previewSocialGreetingButton.title == "预览双鸟招呼"
            checkSocialMotionLabels(w,language:"Chinese",checks:&checks)
            checks["pointerFollowChineseToggleRestored"] = w.draft.pointerFollowEnabled && w.pointerFollowButton.state == .on && w.pointerFollowButton.title == "绕飞时跟随鼠标移动"
            checks["pointerPreviewMessageUsesSavedOnChinese"] = d.pointerVisitPreviewMessage == "正在预览绕鼠标飞行。移动鼠标会继续跟随，点击可结束。"
            w.tabs.selectTabViewItem(at:2)
            try snapshot(w.window!,to:folder.appendingPathComponent("interaction-zh.png"))
            if let scroll=w.tabs.tabViewItems[2].view as? NSScrollView {
                scroll.contentView.scroll(to:CGPoint(x:0,y:200));scroll.reflectScrolledClipView(scroll.contentView)
                try snapshot(w.window!,to:folder.appendingPathComponent("encounters-zh.png"))
                checkSocialLayout(w,language:"Chinese",checks:&checks)
                try snapshot(w.window!,to:folder.appendingPathComponent("social-greetings-zh.png"))
                scroll.contentView.scroll(to:CGPoint(x:0,y:w.perchActionsButton.frame.minY-42));scroll.reflectScrolledClipView(scroll.contentView)
                checks["perchPreviewsReachableChinese"] = scroll.documentView!.visibleRect.contains(w.perchActionsButton.frame) && scroll.documentView!.visibleRect.contains(w.previewRestButton.frame) && scroll.documentView!.visibleRect.contains(w.previewPreenButton.frame)
                try snapshot(w.window!,to:folder.appendingPathComponent("perch-activities-zh.png"))
            }
            w.pointerVisitsButton.performClick(nil);w.flockPassesButton.performClick(nil)
            w.ambientFrequencyPopup.selectItem(at:2);w.ambientSettingsChanged()
            w.relocalize()
            checks["ambientDraftSurvivesRebuild"] = !w.draft.pointerVisits && !w.draft.flockPasses && w.ambientFrequencyPopup.indexOfSelectedItem == 2
            checks["socialDraftSurvivesAmbientRebuild"] = !w.draft.socialInteractions && w.socialInteractionsButton.state == .off
            checks["pointerFollowDisabledPreferenceSurvivesRebuild"] = w.draft.pointerFollowEnabled && w.pointerFollowButton.state == .on && !w.pointerFollowButton.isEnabled
            w.save()
            let ambientSaved=try BirdSettings.decode(Data(contentsOf:d.settingsURL))
            checks["ambientSettingsPersistAndApply"] = !ambientSaved.pointerVisits && !d.settings.pointerVisits && !ambientSaved.flockPasses && ambientSaved.ambientFrequency == .high
            checks["ambientEditsPreservePerchAndHoverSettings"] = !ambientSaved.perchActions && !d.settings.perchActions && ambientSaved.hoverDelay == 0.25 && d.settings.hoverDelay == 0.25
            checks["ambientEditsPreserveSocialSetting"] = !ambientSaved.socialInteractions && !d.settings.socialInteractions
            checks["pointerFollowPreferencePersistsWithVisitsDisabled"] = ambientSaved.pointerFollowEnabled && d.settings.pointerFollowEnabled && !ambientSaved.pointerVisits
            var oldPointerObject=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as! [String:Any]
            oldPointerObject.removeValue(forKey:"pointerFollowEnabled")
            let pointerMigrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:oldPointerObject))
            checks["oldSettingsDisablePointerFollowingWithoutLosingOtherEdits"] = !pointerMigrated.pointerFollowEnabled && pointerMigrated.pointerVisits == ambientSaved.pointerVisits && pointerMigrated.socialInteractions == ambientSaved.socialInteractions && pointerMigrated.perchActions == ambientSaved.perchActions && pointerMigrated.hoverDelay == ambientSaved.hoverDelay && pointerMigrated.flockPasses == ambientSaved.flockPasses && pointerMigrated.ambientFrequency == ambientSaved.ambientFrequency && pointerMigrated.probabilities == ambientSaved.probabilities && pointerMigrated.catalog.species == ambientSaved.catalog.species
            var oldSocialObject=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as! [String:Any]
            oldSocialObject.removeValue(forKey:"socialInteractions")
            let socialMigrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:oldSocialObject))
            checks["oldSettingsEnableSocialWithoutLosingOtherEdits"] = socialMigrated.socialInteractions && socialMigrated.perchActions == ambientSaved.perchActions && socialMigrated.hoverDelay == ambientSaved.hoverDelay && socialMigrated.pointerVisits == ambientSaved.pointerVisits && socialMigrated.flockPasses == ambientSaved.flockPasses && socialMigrated.ambientFrequency == ambientSaved.ambientFrequency && socialMigrated.probabilities == ambientSaved.probabilities && socialMigrated.catalog.species == ambientSaved.catalog.species
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
            checks["socialDefaultsRestoredWithoutApplying"] = w.draft.socialInteractions && w.socialInteractionsButton.state == .on && !d.settings.socialInteractions
            checks["pointerFollowDefaultsRestoredWithoutApplying"] = !w.draft.pointerFollowEnabled && w.pointerFollowButton.state == .off && w.pointerFollowButton.isEnabled && d.settings.pointerFollowEnabled
            w.save()
            let defaultsSaved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
            checks["perchDefaultsSaveAndReload"] = defaultsSaved.perchActions && d.settings.perchActions && defaultsSaved.hoverDelay == 1 && defaultsSaved.pointerVisits && defaultsSaved.flockPasses && defaultsSaved.ambientFrequency == .low
            checks["socialDefaultsSaveAndReload"] = defaultsSaved.socialInteractions && d.settings.socialInteractions
            checks["pointerFollowDefaultsSaveAndReload"] = !defaultsSaved.pointerFollowEnabled && !d.settings.pointerFollowEnabled
            w.scrollToSpecies(.nightHeron)
            if let scroll=w.tabs.tabViewItems[0].view as? NSScrollView {
                checks["manualMigrationScrollsToFirstNewBird"] = scroll.documentView!.visibleRect.intersects(w.fields[7].frame)
            }
            w.cancel()
            try checkPassiveSettings(folder:folder,checks:&checks)
            try PassiveMotionSettingsVerification.run(into:&checks,folder:folder)
            try VisitorMemorySettingsVerification.run(into:&checks,folder:folder)
            try VisitorMemoryPersistenceVerification.run(into:&checks,folder:folder)
            try checkLeafSettings(folder:folder,checks:&checks)
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
    private static func checkPassiveSettings(folder:URL,checks:inout [String:Bool]) throws {
        let d=DesktopController();d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.settingsURL=folder.appendingPathComponent("passive-settings.json")
        d.legacyURL=folder.appendingPathComponent("passive-legacy.json")
        let cancelled=SpeciesSettingsWindow(desktop:d)
        cancelled.showWindow(nil);cancelled.passiveAttentionButton.performClick(nil);cancelled.cancel()
        checks["passiveCancelDoesNotApplyOrSave"] = !cancelled.draft.passiveAttentionEnabled && d.settings.passiveAttentionEnabled && cancelled.window?.isVisible == false && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w
        w.showWindow(nil)
        defer {w.cancel()}
        checks["passiveDefaultOnAndCancelledDraftDiscarded"] = w.draft.passiveAttentionEnabled && w.passiveAttentionButton.state == .on && w.passiveAttentionButton.isEnabled
        for enabled in [false,true] {
            w.passiveAttentionButton.performClick(nil)
            checks["passiveToggleOnlyChangesDraft-\(enabled)"] = w.draft.passiveAttentionEnabled == enabled && d.settings.passiveAttentionEnabled
            w.perchActionsButton.performClick(nil)
            checks["passiveMasterDisablesWithoutClearingDraft-\(enabled)"] = !w.passiveAttentionButton.isEnabled && w.draft.passiveAttentionEnabled == enabled && w.passiveAttentionButton.state == (enabled ? .on:.off)
            w.passiveAttentionButton.performClick(nil)
            w.relocalize()
            checks["disabledPassivePreferenceCannotBeToggledOrLostOnRebuild-\(enabled)"] = !w.passiveAttentionButton.isEnabled && w.draft.passiveAttentionEnabled == enabled && w.passiveAttentionButton.state == (enabled ? .on:.off)
            w.perchActionsButton.performClick(nil)
            checks["passiveMasterReenablesPreference-\(enabled)"] = w.passiveAttentionButton.isEnabled && w.draft.passiveAttentionEnabled == enabled && w.passiveAttentionButton.state == (enabled ? .on:.off)
        }
        w.passiveAttentionButton.performClick(nil);w.save()
        let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["passiveSettingSavedAndAppliedImmediately"] = !saved.passiveAttentionEnabled && !d.settings.passiveAttentionEnabled && saved.perchActions && d.settings.perchActions
        let reloaded=DesktopController();reloaded.settingsURL=d.settingsURL;reloaded.legacyURL=d.legacyURL
        try reloaded.loadSpeciesConfig()
        checks["passiveSettingSurvivesRestart"] = !reloaded.settings.passiveAttentionEnabled && reloaded.settings.perchActions
        w.passiveAttentionButton.performClick(nil)
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let suffix=language == .chinese ? "zh":"en"
            checks["passiveDraftSurvivesRelocalization-\(suffix)"] = w.draft.passiveAttentionEnabled && w.passiveAttentionButton.state == .on && !d.settings.passiveAttentionEnabled
            checks["passiveLabels-\(suffix)"] = w.passiveAttentionButton.title == w.t("留意鼠标与短暂警觉","Watch the pointer and briefly become alert") && w.previewWatchButton.title == w.t("预览留意鼠标","Preview observation") && w.previewAlertButton.title == w.t("预览短暂警觉","Preview brief alert")
            checkAttentionRejections(w,reason:.disabled,suffix:suffix,checks:&checks)
            d.paused=true
            checkAttentionRejections(w,reason:.paused,suffix:suffix,checks:&checks)
            d.paused=false
            if let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView {
                scroll.contentView.scroll(to:CGPoint(x:0,y:max(0,w.perchActionsButton.frame.minY-42)))
                scroll.reflectScrolledClipView(scroll.contentView)
                let controls=[w.perchActionsButton!,w.passiveAttentionButton!,w.previewRestButton!,w.previewPreenButton!,w.previewWatchButton!,w.previewAlertButton!]
                checks["passiveControlsReachable-\(suffix)"] = controls.allSatisfy{document.visibleRect.contains($0.frame)}
                checks["passiveTitlesFit-\(suffix)"] = controls.allSatisfy{$0.intrinsicContentSize.width <= $0.frame.width}
                let helpIdentifiers:Set<String>=["perchActivitiesHelp","perchPreviewHelp"]
                let help=document.subviews.compactMap{$0 as? NSTextField}.filter {
                    $0.identifier.map{helpIdentifiers.contains($0.rawValue)} ?? false
                }
                checks["passiveHelpFullyVisible-\(suffix)"] = help.count == 2 && help.allSatisfy {
                    document.visibleRect.contains($0.frame) && ($0.cell?.cellSize(forBounds:$0.bounds).height ?? .infinity) <= $0.frame.height
                }
                checks["passiveControlsDoNotOverlap-\(suffix)"] = document.subviews.enumerated().allSatisfy { index,view in
                    document.bounds.contains(view.frame) && document.subviews.dropFirst(index+1).allSatisfy{!view.frame.intersects($0.frame)}
                }
                try snapshot(w.window!,to:folder.appendingPathComponent("passive-settings-\(suffix).png"))
            } else {checks["passiveControlsReachable-\(suffix)"]=false}
        }
        let url=d.settingsURL;d.settingsURL=folder
        w.save();d.settingsURL=url
        let afterFailure=try BirdSettings.decode(Data(contentsOf:url))
        checks["passiveFailedSavePreservesActiveAndStoredSettings"] = w.draft.passiveAttentionEnabled && !d.settings.passiveAttentionEnabled && !afterFailure.passiveAttentionEnabled && w.message.stringValue == "Could not save. Try again; active settings are unchanged."
        w.perchActionsButton.performClick(nil);w.save()
        let masterOff=try BirdSettings.decode(Data(contentsOf:url))
        checks["passiveOnPreferenceSavedExactlyWithMasterOff"] = masterOff.passiveAttentionEnabled && !masterOff.perchActions && d.settings.passiveAttentionEnabled && !d.settings.perchActions && !w.passiveAttentionButton.isEnabled
        w.perchActionsButton.performClick(nil)
        checkAttentionRejections(w,reason:.disabled,suffix:"saved-master-off",checks:&checks)
        w.resetDefaults()
        checks["passiveDefaultsRestoredWithoutApplying"] = w.draft.passiveAttentionEnabled && w.draft.perchActions && w.passiveAttentionButton.state == .on && w.passiveAttentionButton.isEnabled && !d.settings.perchActions
        w.save()
        let restored=try BirdSettings.decode(Data(contentsOf:url))
        checks["passiveDefaultsSaveAndReload"] = restored.passiveAttentionEnabled && restored.perchActions && d.settings.passiveAttentionEnabled && d.settings.perchActions
        w.passiveAttentionButton.performClick(nil);w.perchActionsButton.performClick(nil)
        // Native preview buttons use saved settings despite both draft gates being off.
        // Use a real display with an isolated bird far from the pointer.
        if let screen=d.screenRects.first {
            let host=Surface(id:952,rect:CGRect(x:screen.minX+80,y:screen.midY+80,width:screen.width-160,height:100))
            d.surfaces=[host]
            let fraction:CGFloat=d.pointerPosition.x < screen.midX ? 0.8:0.2
            let bird=Bird(position:.zero,fraction:fraction,profile:d.catalog.profile(.treeSparrow),random:{0.5})
            bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;bird.tick(2)
            d.engine.installFixtureBirds([bird])
            for language:AppLanguage in [.chinese,.english] {
                d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
                let suffix=language == .chinese ? "zh":"en"
                let previews:[(kind:BehaviorKind,button:NSButton,message:String)] = [
                    (.watch,w.previewWatchButton,w.t("正在预览留意鼠标：观察朝向、站立和眨眼；小鸟停稳即可，鼠标可以远离。","Previewing observation: watch facing, standing and blinking on a settled bird, even far from the pointer.")),
                    (.alert,w.previewAlertButton,w.t("正在预览短暂警觉：小鸟保持停栖，安静后恢复；无需把鼠标移近。","Previewing brief alertness: the bird stays perched and settles when quiet; no need to move the pointer closer."))]
                for preview in previews {
                    let origin=bird.position,revision=bird.motionRevision,sequence=d.engine.events.last?.sequence
                    preview.button.performClick(nil)
                    let event=d.engine.events.last
                    checks["attentionPreviewUsesSettledBirdAndSavedEnabledSettings-\(suffix)-\(preview.kind.rawValue)"] = !w.draft.passiveAttentionEnabled && !w.draft.perchActions && d.settings.passiveAttentionEnabled && d.settings.perchActions && event?.sequence != sequence && event?.type == .started && event?.kind == preview.kind && event?.source == .preview && d.engine.birds.count == 1 && d.engine.birds.first === bird
                    checks["attentionPreviewAcceptsFarPointer-\(suffix)-\(preview.kind.rawValue)"] = Geometry.distance(d.engine.world.pointer,bird.position)>max(200,144*d.spriteScale(for:bird))*1.2 && event?.type == .started
                    checks["attentionPreviewInstructions-\(suffix)-\(preview.kind.rawValue)"] = w.message.stringValue == preview.message
                    checks["attentionPreviewDoesNotMoveBird-\(suffix)-\(preview.kind.rawValue)"] = bird.position == origin && bird.motionRevision == revision && bird.state == .perched
                    checks["attentionPreviewMessageFits-\(suffix)-\(preview.kind.rawValue)"] = (w.message.cell?.cellSize(forBounds:w.message.bounds).height ?? .infinity) <= w.message.frame.height
                    d.engine.handle(.cancelAmbient(.screensChanged))
                }
            }
        } else {checks["attentionPreviewUsesSettledBirdAndSavedEnabledSettings"]=false}
    }
    private static func checkAttentionRejections(_ window:SpeciesSettingsWindow,reason:BehaviorReason,suffix:String,checks:inout [String:Bool]) {
        let d=window.desktop
        let previews:[(kind:BehaviorKind,button:NSButton)] = [(.watch,window.previewWatchButton),(.alert,window.previewAlertButton)]
        for preview in previews {
            let before=d.engine.birds.count,sequence=d.engine.events.last?.sequence
            preview.button.performClick(nil)
            let event=d.engine.events.last
            checks["attentionPreviewRejection-\(suffix)-\(reason.rawValue)-\(preview.kind.rawValue)"] = event?.sequence != sequence && event?.kind == preview.kind && event?.type == .rejected && event?.source == .preview && event?.reason == reason && window.message.stringValue == d.behaviorMessage(reason)
            checks["attentionRejectedPreviewPreservesPopulation-\(suffix)-\(reason.rawValue)-\(preview.kind.rawValue)"] = d.engine.birds.count == before && d.engine.activeRunCount == 0 && d.engine.leasedBirdCount == 0
        }
    }
    private static func checkLeafSettings(folder:URL,checks:inout [String:Bool]) throws {
        // Keep leaf fixtures independent of the existing settings checks.
        let d=DesktopController();d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.settingsURL=folder.appendingPathComponent("leaf-settings.json")
        d.legacyURL=folder.appendingPathComponent("leaf-legacy.json")
        let cancelled=SpeciesSettingsWindow(desktop:d)
        cancelled.showWindow(nil)
        cancelled.ambientLeafPlayButton.performClick(nil)
        checks["ambientLeafToggleOnlyChangesDraft"] = !cancelled.draft.ambientLeafPlayEnabled && d.settings.ambientLeafPlayEnabled
        cancelled.leafPlayButton.performClick(nil)
        checks["ambientLeafDisabledOffDraftPreserved"] = !cancelled.ambientLeafPlayButton.isEnabled && cancelled.ambientLeafPlayButton.state == .off && !cancelled.draft.ambientLeafPlayEnabled
        cancelled.ambientLeafPlayButton.performClick(nil)
        checks["disabledAmbientLeafOffCannotBeToggled"] = !cancelled.draft.ambientLeafPlayEnabled && cancelled.ambientLeafPlayButton.state == .off
        checks["leafToggleOnlyChangesDraft"] = !cancelled.draft.leafPlayEnabled && d.settings.leafPlayEnabled
        cancelled.cancel()
        checks["leafCancelDoesNotApplyOrSave"] = cancelled.window?.isVisible == false && d.settings.ambientLeafPlayEnabled && d.settings.leafPlayEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w
        w.showWindow(nil)
        defer {w.cancel()}
        checks["leafDefaultOnAndCancelledDraftDiscarded"] = w.draft.leafPlayEnabled && w.leafPlayButton.state == .on
        checks["ambientLeafDefaultOnAndCancelledDraftDiscarded"] = w.draft.ambientLeafPlayEnabled && w.ambientLeafPlayButton.state == .on && w.ambientLeafPlayButton.isEnabled
        w.leafPlayButton.performClick(nil)
        checks["ambientLeafDisabledOnDraftPreserved"] = !w.ambientLeafPlayButton.isEnabled && w.ambientLeafPlayButton.state == .on && w.draft.ambientLeafPlayEnabled
        w.ambientLeafPlayButton.performClick(nil)
        checks["disabledAmbientLeafOnCannotBeToggled"] = w.draft.ambientLeafPlayEnabled && w.ambientLeafPlayButton.state == .on
        w.leafPlayButton.performClick(nil)
        checks["ambientLeafMasterReenablesPreference"] = w.ambientLeafPlayButton.isEnabled && w.ambientLeafPlayButton.state == .on
        w.ambientLeafPlayButton.performClick(nil)
        w.leafPlayButton.performClick(nil)
        let before=d.engine.birds.count
        w.releaseLeafButton.performClick(nil)
        checks["leafPreviewUsesSavedEnabledSwitch"] = !w.draft.leafPlayEnabled && d.settings.leafPlayEnabled && d.engine.hasLeafPreview && d.engine.scenePropCount == 0 && w.message.stringValue.contains("3 秒")
        w.clearLeafButton.performClick(nil)
        d.consumeBehaviorEvents()
        checks["leafClearCancelsPendingPreview"] = !d.engine.hasLeafPreview && d.engine.scenePropCount == 0 && d.engine.birds.count == before && w.message.stringValue == "已清除落叶，并取消等待中的预览。"
        for _ in 0..<240 {d.engine.advance(BehaviorEngine.step)}
        checks["leafClearedPreviewNeverStartsLater"] = !d.engine.hasLeafPreview && d.engine.scenePropCount == 0 && d.engine.birds.count == before && !d.engine.events.contains{$0.kind == .leafPlay && $0.type == .started}
        w.save()
        let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["leafSettingSavedAndAppliedImmediately"] = !saved.leafPlayEnabled && !d.settings.leafPlayEnabled
        checks["ambientLeafSettingSavedWithMasterOff"] = !saved.ambientLeafPlayEnabled && !d.settings.ambientLeafPlayEnabled
        let reloaded=DesktopController();reloaded.settingsURL=d.settingsURL;reloaded.legacyURL=d.legacyURL
        try reloaded.loadSpeciesConfig()
        checks["leafSettingSurvivesRestart"] = !reloaded.settings.leafPlayEnabled
        checks["ambientLeafSettingSurvivesRestart"] = !reloaded.settings.ambientLeafPlayEnabled
        w.leafPlayButton.performClick(nil)
        w.ambientLeafPlayButton.performClick(nil)
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let suffix=language == .chinese ? "zh":"en"
            checks["leafDraftSurvivesRelocalization-\(suffix)"] = w.draft.leafPlayEnabled && w.leafPlayButton.state == .on && !d.settings.leafPlayEnabled
            checks["ambientLeafDraftSurvivesRelocalization-\(suffix)"] = w.draft.ambientLeafPlayEnabled && w.ambientLeafPlayButton.state == .on && w.ambientLeafPlayButton.isEnabled && !d.settings.ambientLeafPlayEnabled
            checks["leafLabels-\(suffix)"] = w.ambientLeafPlayButton.title == w.t("偶尔自动出现落叶游戏","Occasional automatic leaf play") && w.leafPlayButton.title == w.t("开启落叶游戏","Enable leaf play") && w.releaseLeafButton.title == w.t("放一片落叶","Release a leaf") && w.clearLeafButton.title == w.t("清除落叶","Clear leaf")
            let sequence=d.engine.events.last?.sequence
            w.releaseLeafButton.performClick(nil)
            let event=d.engine.events.last
            checks["leafPreviewUsesSavedDisabledSwitch-\(suffix)"] = event?.sequence != sequence && event?.kind == .leafPlay && event?.source == .preview && event?.type == .rejected && event?.reason == .disabled && !d.engine.hasLeafPreview && w.message.stringValue == d.behaviorMessage(.disabled)
            checks["leafRejectedPreviewPreservesPopulation-\(suffix)"] = d.engine.birds.count == before && d.engine.scenePropCount == 0 && d.engine.leasedBirdCount == 0
            if let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView {
                // Leaf play is no longer the last section. Navigate to its own
                // heading and retain the full controls/help visibility checks.
                let heading=document.subviews.first{$0.identifier?.rawValue=="leafSectionTitle"}
                let top=max(0,(heading?.frame.minY ?? w.leafPlayButton.frame.minY)-12)
                scroll.contentView.scroll(to:CGPoint(x:0,y:min(top,document.bounds.height-scroll.contentView.bounds.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
                let controls=[w.leafPlayButton!,w.ambientLeafPlayButton!,w.releaseLeafButton!,w.clearLeafButton!]
                checks["leafControlsReachable-\(suffix)"] = controls.allSatisfy{document.visibleRect.contains($0.frame)}
                checks["leafControlTitlesFit-\(suffix)"] = controls.allSatisfy{$0.intrinsicContentSize.width <= $0.frame.width}
                checks["leafSectionFollowsPerchActivities-\(suffix)"] = w.leafPlayButton.frame.minY > max(w.previewPreenButton.frame.maxY,w.previewAlertButton.frame.maxY)
                checks["leafLayoutDoesNotOverlap-\(suffix)"] = document.subviews.enumerated().allSatisfy { index,view in
                    document.bounds.contains(view.frame) && document.subviews.dropFirst(index+1).allSatisfy{!view.frame.intersects($0.frame)}
                }
                let leafIdentifiers:Set<String>=["leafSectionTitle","leafPlayHelp","leafPreviewHelp"]
                let leafLabels=document.subviews.compactMap{$0 as? NSTextField}.filter {
                    $0.identifier.map{leafIdentifiers.contains($0.rawValue)} ?? false
                }
                checks["leafHelpFullyVisible-\(suffix)"] = leafLabels.count == 3 && leafLabels.allSatisfy {
                    document.visibleRect.contains($0.frame) && ($0.cell?.cellSize(forBounds:$0.bounds).height ?? .infinity) <= $0.frame.height
                }
                try snapshot(w.window!,to:folder.appendingPathComponent("leaf-play-\(suffix).png"))
            } else {checks["leafControlsReachable-\(suffix)"]=false}
        }
        let url=d.settingsURL;d.settingsURL=folder
        w.save();d.settingsURL=url
        let afterFailure=try BirdSettings.decode(Data(contentsOf:url))
        checks["leafFailedSavePreservesActiveAndStoredSettings"] = w.draft.leafPlayEnabled && !d.settings.leafPlayEnabled && !afterFailure.leafPlayEnabled && w.message.stringValue == "Could not save. Try again; active settings are unchanged."
        checks["ambientLeafFailedSavePreservesActiveAndStoredSettings"] = w.draft.ambientLeafPlayEnabled && !d.settings.ambientLeafPlayEnabled && !afterFailure.ambientLeafPlayEnabled
        w.resetDefaults()
        checks["ambientLeafDefaultsRestoredWithoutApplying"] = w.draft.ambientLeafPlayEnabled && w.ambientLeafPlayButton.state == .on && w.ambientLeafPlayButton.isEnabled && !d.settings.ambientLeafPlayEnabled
        checks["leafDefaultsRestoredWithoutApplying"] = w.draft.leafPlayEnabled && w.leafPlayButton.state == .on && !d.settings.leafPlayEnabled
        w.save()
        let restored=try BirdSettings.decode(Data(contentsOf:url))
        checks["leafDefaultsSaveAndReload"] = d.settings.leafPlayEnabled && restored.leafPlayEnabled
        checks["ambientLeafDefaultsSaveAndReload"] = d.settings.ambientLeafPlayEnabled && restored.ambientLeafPlayEnabled
        w.ambientLeafPlayButton.performClick(nil);w.save()
        let automaticOff=try BirdSettings.decode(Data(contentsOf:url))
        checks["ambientLeafCanBeSavedOffWithMasterOn"] = d.settings.leafPlayEnabled && !d.settings.ambientLeafPlayEnabled && !automaticOff.ambientLeafPlayEnabled
        d.paused=true;w.releaseLeafButton.performClick(nil)
        checks["leafPausedPreviewExplained"] = !d.engine.hasLeafPreview && d.engine.events.last?.kind == .leafPlay && d.engine.events.last?.reason == .paused && w.message.stringValue == d.behaviorMessage(.paused)
        d.paused=false
        w.releaseLeafButton.performClick(nil)
        for _ in 0..<120 {d.engine.advance(BehaviorEngine.step)}
        checks["leafPreviewWaitsThreeSeconds"] = d.engine.hasLeafPreview && d.engine.scenePropCount == 0
        checks["leafManualPreviewIgnoresAutomaticSwitch"] = !d.settings.ambientLeafPlayEnabled && d.engine.hasLeafPreview
        for _ in 0..<66 {d.engine.advance(BehaviorEngine.step)}
        d.consumeBehaviorEvents()
        checks["leafDelayedUnavailableBirdExplained"] = !d.engine.hasLeafPreview && d.engine.events.last(where:{$0.kind == .leafPlay && $0.type == .previewResult})?.reason == .unavailableBird && w.message.stringValue == d.behaviorMessage(.unavailableBird) && d.engine.birds.count == before
        // Use a deterministic world to exercise the same clear button on a live scene.
        let screen=CGRect(x:0,y:0,width:1400,height:1000)
        let host=Surface(id:951,rect:CGRect(x:100,y:750,width:1200,height:180))
        let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host);bird.perchDuration=600
        d.engine.installFixtureBirds([bird])
        d.engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],scale:1,
            pointer:CGPoint(x:20,y:20),buttonsDown:false,availableFrames:d.frameCapabilities))
        let result=d.engine.handle(.leafPlay(at:CGPoint(x:700,y:450),source:.preview))
        checks["leafActiveSceneUsesExistingBird"] = result.accepted && d.engine.scenePropCount == 1 && d.engine.propSnapshot().count == 1 && d.engine.birds.count == 1 && d.engine.birds.first === bird
        w.clearLeafButton.performClick(nil)
        checks["leafClearCancelsActiveScene"] = result.accepted && d.engine.scenePropCount == 0 && d.engine.propSnapshot().isEmpty && d.engine.activeRunCount == 0 && d.engine.leasedBirdCount == 0 && d.engine.birds.first === bird
        w.clearLeafButton.performClick(nil)
        checks["leafClearIsRepeatable"] = d.engine.scenePropCount == 0 && !d.engine.hasLeafPreview && d.engine.birds.count == 1 && w.message.stringValue == "Leaf cleared; pending preview cancelled."
    }
    private static func socialMotionPreviews(_ window:SpeciesSettingsWindow) -> [(kind:BehaviorKind,button:NSButton,chinese:String,english:String)] {
        [(.sideBySide,window.previewSideBySideButton,"预览并排停靠","Preview side-by-side perch"),
         (.giveWay,window.previewGiveWayButton,"预览让座","Preview giving way"),
         (.pairedTakeoff,window.previewPairedTakeoffButton,"预览结伴起飞","Preview paired takeoff")]
    }
    private static func checkSocialMotionLabels(_ window:SpeciesSettingsWindow,language:String,checks:inout [String:Bool]) {
        for preview in socialMotionPreviews(window) {
            checks["socialMotionLabel\(language)-\(preview.kind.rawValue)"] = preview.button.title == window.t(preview.chinese,preview.english)
        }
        checks["socialCompanionReason\(language)"] = window.desktop.behaviorMessage(.noCompanion) == window.t("请等待两只距离合适的小鸟在可见边缘停稳，再预览双鸟互动。","Wait for two suitably spaced birds to settle on visible edges, then try the two-bird interaction.")
        checks["socialSpaceReason\(language)"] = window.desktop.behaviorMessage(.noSpace) == window.t("可见空间不足。请等待小鸟在更开阔、未被遮挡的位置停稳。","Not enough visible space. Wait for birds to settle in a clear, unobstructed area.")
    }
    private static func checkSocialMotionRejections(_ window:SpeciesSettingsWindow,reason:BehaviorReason,language:String,checks:inout [String:Bool]) {
        let desktop=window.desktop,engine=desktop.engine
        func population() -> [Int] {
            [engine.birds.count,engine.residentCount,engine.passingCount,engine.departingCount,
             engine.pendingCount,engine.arrivalCount,engine.departureCount]
        }
        for preview in socialMotionPreviews(window) {
            let key="socialMotion\(language)-\(reason.rawValue)-\(preview.kind.rawValue)"
            let before=population(),sequence=engine.events.last?.sequence
            preview.button.performClick(nil)
            let event=engine.events.last
            checks[key] = event?.sequence != sequence && event?.kind == preview.kind && event?.source == .preview && event?.type == .rejected && event?.reason == reason && window.message.stringValue == desktop.behaviorMessage(reason)
            checks[key+"PreservesPopulation"] = population() == before && engine.activeRunCount == 0 && engine.leasedBirdCount == 0
            if reason == .disabled {
                checks[key+"UsesSavedSwitch"] = window.draft.socialInteractions && !desktop.settings.socialInteractions
            } else if reason == .noCompanion {
                checks[key+"UsesSavedSwitch"] = !window.draft.socialInteractions && desktop.settings.socialInteractions
            }
        }
    }
    private static func checkSocialLayout(_ window:SpeciesSettingsWindow,language:String,checks:inout [String:Bool]) {
        guard let scroll=window.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {
            checks["socialControlsReachable\(language)"]=false
            checks["pointerFollowControlReachable\(language)"]=false
            for preview in socialMotionPreviews(window) {checks["socialMotionReachable\(language)-\(preview.kind.rawValue)"]=false}
            return
        }
        scroll.contentView.scroll(to:CGPoint(x:0,y:max(0,window.pointerVisitsButton.frame.minY-20)))
        scroll.reflectScrolledClipView(scroll.contentView)
        checks["pointerFollowControlReachable\(language)"] = document.visibleRect.contains(window.pointerVisitsButton.frame) && document.visibleRect.contains(window.pointerFollowButton.frame)
        checks["pointerFollowTitleFits\(language)"] = window.pointerFollowButton.intrinsicContentSize.width <= window.pointerFollowButton.frame.width
        scroll.contentView.scroll(to:CGPoint(x:0,y:max(0,window.socialInteractionsButton.frame.minY-20)))
        scroll.reflectScrolledClipView(scroll.contentView)
        checks["socialControlsReachable\(language)"] = document.visibleRect.contains(window.socialInteractionsButton.frame) && document.visibleRect.contains(window.previewSocialGreetingButton.frame) && document.visibleRect.contains(window.ambientFrequencyPopup.frame)
        for preview in socialMotionPreviews(window) {
            checks["socialMotionReachable\(language)-\(preview.kind.rawValue)"] = document.visibleRect.contains(preview.button.frame)
            checks["socialMotionTitleFits\(language)-\(preview.kind.rawValue)"] = preview.button.intrinsicContentSize.width <= preview.button.frame.width
        }
        checks["interactionControlsDoNotOverlap\(language)"] = document.subviews.enumerated().allSatisfy { index,view in
            document.bounds.contains(view.frame) && document.subviews.dropFirst(index+1).allSatisfy{!view.frame.intersects($0.frame)}
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
