import AppKit
import BirdingCore

/// Native settings contract only. Core verification owns migration and rhythm
/// policy; this fixture never starts a desktop, clocks, birds or persistence.
enum ActivityRhythmSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("activity-rhythm-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        let suite="Birding.ActivityRhythmSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {
            throw NSError(domain:"ActivityRhythmSettingsVerification",code:1)
        }
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=isolatedDesktop(preferences:preferences,folder:evidence)
        checks["activityRhythmUIStartsWithEverydayDefault"] = d.settings.activityRhythm == .steady &&
            !FileManager.default.fileExists(atPath:d.settingsURL.path)

        for mode in ActivityRhythmMode.allCases {
            let cancelled=SpeciesSettingsWindow(desktop:d)
            cancelled.showWindow(nil)
            let before=try settingsData(d.settings)
            let sent=choose(mode,in:cancelled)
            let after=try settingsData(d.settings)
            checks["activityRhythmSelectionOnlyChangesDraft-"+mode.rawValue] = sent &&
                cancelled.draft.activityRhythm==mode && selectedMode(cancelled)==mode &&
                cancelled.message.stringValue==cancelled.t("尚未保存","Unsaved changes") && before==after
            cancelled.cancel()
            checks["activityRhythmCancelDiscardsDraft-"+mode.rawValue] = cancelled.window?.isVisible == false &&
                d.settings.activityRhythm == .steady && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        }

        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel()}
        checks["activityRhythmReopenShowsSavedDefault"] = w.draft.activityRhythm == .steady &&
            selectedMode(w) == .steady && w.activityRhythmPopup.isEnabled
        w.tabs.selectTabViewItem(at:2)
        // Unrelated edits must survive every rhythm, including dormant child
        // preferences while their master switches are disabled.
        w.hoverDelayField.stringValue="0.25";w.detailFields[0][2].stringValue="1.25"
        w.manualAdjustmentButton.performClick(nil);w.fields[0].stringValue="350";w.controlTextDidEndEditing(Notification(name:NSControl.textDidEndEditingNotification,object:w.fields[0]))
        for mode in ActivityRhythmMode.allCases {
            for perch in [false,true] {
                for encounters in [false,true] {
                    for memory in [false,true] {
                        configure(w,perch:perch,encounters:encounters,memory:memory)
                        let suffix="-\(mode.rawValue)-perch-\(perch)-encounters-\(encounters)-memory-\(memory)"
                        let activeBefore=try settingsData(d.settings)
                        let draftBefore=try settingsData(w.draft,ignoringRhythm:true)
                        let enabledBefore=controlEnablement(w)
                        let sent=choose(mode,in:w)
                        let activeAfter=try settingsData(d.settings)
                        let draftAfter=try settingsData(w.draft,ignoringRhythm:true)
                        checks["activityRhythmIndependentDraft"+suffix] = sent && selectedMode(w)==mode &&
                            w.draft.activityRhythm==mode && w.activityRhythmPopup.isEnabled &&
                            activeBefore==activeAfter && draftBefore==draftAfter &&
                            !enabledBefore.isEmpty && controlEnablement(w)==enabledBefore
                        w.save()
                        let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
                        let object=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as? [String:Any]
                        let expected=try settingsData(w.draft),active=try settingsData(d.settings)
                        let stored=try settingsData(saved)
                        checks["activityRhythmSaveAppliesExactCombination"+suffix] = saved.activityRhythm==mode &&
                            d.settings.activityRhythm==mode && (object?["activityRhythm"] as? String)==mode.rawValue &&
                            expected==stored && active==stored && saved.perchActions==perch &&
                            saved.pointerVisits==encounters && saved.visitorMemoryEnabled==memory &&
                            saved.hoverDelay==0.25 && saved.catalog.species[0].speed==1.25 &&
                            saved.probabilities.manualAdjustmentEnabled &&
                            w.message.stringValue==w.t("已保存 · 交互设置立即生效，鸟种参数用于新飞入的小鸟。","Saved · Interaction settings apply now; species settings affect new arrivals.")
                        let reloaded=isolatedDesktop(preferences:preferences,folder:evidence)
                        try reloaded.loadSpeciesConfig()
                        let reloadedData=try settingsData(reloaded.settings)
                        checks["activityRhythmReloadKeepsExactCombination"+suffix] = reloadedData==stored
                        checks["activityRhythmReloadRemainsIsolated"+suffix] = isIsolated(reloaded,preferences:preferences,folder:evidence)
                    }
                }
            }
        }

        // Save reads the native selection as well as the last dispatched action.
        choose(.steady,in:w)
        w.activityRhythmPopup.selectItem(at:ActivityRhythmMode.allCases.firstIndex(of:.quiet)!)
        w.save()
        let nativeSelection=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["activityRhythmSaveReadsNativeSelection"] = w.draft.activityRhythm == .quiet &&
            d.settings.activityRhythm == .quiet && nativeSelection.activityRhythm == .quiet

        choose(.localDayNight,in:w);w.save()
        let savedURL=d.settingsURL,savedBytes=try Data(contentsOf:d.settingsURL)
        let savedActive=try settingsData(d.settings)
        choose(.quiet,in:w)
        w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="1.5"
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            let suffix=language == .chinese ? "zh":"en"
            checks["activityRhythmDraftSurvivesLanguageChange-"+suffix] = w.draft.activityRhythm == .quiet &&
                selectedMode(w) == .quiet && d.settings.activityRhythm == .localDayNight &&
                w.hoverDelayField.stringValue=="0.75" && w.detailFields[0][2].stringValue=="1.5" &&
                w.draft.probabilities.manualAdjustmentEnabled &&
                (w.tabs.selectedTabViewItem?.identifier as? String)=="interaction"
            for mode in ActivityRhythmMode.allCases {
                choose(mode,in:w);w.relocalize()
                checks["activityRhythmRebuildKeepsSelection-"+suffix+"-"+mode.rawValue] =
                    selectedMode(w)==mode && w.draft.activityRhythm==mode &&
                    w.hoverDelayField.stringValue=="0.75" && w.detailFields[0][2].stringValue=="1.5" &&
                    d.settings.activityRhythm == .localDayNight
                try checkLayout(w,suffix:suffix+"-"+mode.rawValue,folder:evidence,checks:&checks)
            }
            // Writing over the isolated evidence directory deterministically
            // fails without relying on file permissions or the user's files.
            d.settingsURL=evidence;w.save();d.settingsURL=savedURL
            let afterFailure=try settingsData(d.settings)
            let afterFailureBytes=try Data(contentsOf:savedURL)
            let stored=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
            checks["activityRhythmFailedSaveKeepsActiveFileAndDraft-"+suffix] =
                w.draft.activityRhythm == .quiet && selectedMode(w) == .quiet &&
                afterFailure==savedActive && afterFailureBytes==savedBytes && stored.activityRhythm == .localDayNight &&
                w.hoverDelayField.stringValue=="0.75" && w.detailFields[0][2].stringValue=="1.5" &&
                w.message.stringValue==w.t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.")
        }

        w.hoverDelayField.stringValue="invalid";w.save()
        let afterInvalidDelay=try settingsData(d.settings)
        let bytesAfterInvalidDelay=try Data(contentsOf:savedURL)
        checks["activityRhythmInvalidDelayPreventsPartialApply"] = afterInvalidDelay==savedActive &&
            bytesAfterInvalidDelay==savedBytes && w.draft.activityRhythm == .quiet &&
            (w.tabs.selectedTabViewItem?.identifier as? String)=="interaction"
        w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="9";w.save()
        let afterInvalidDetails=try settingsData(d.settings)
        let bytesAfterInvalidDetails=try Data(contentsOf:savedURL)
        checks["activityRhythmInvalidDetailsPreventsPartialApply"] = afterInvalidDetails==savedActive &&
            bytesAfterInvalidDetails==savedBytes && w.draft.activityRhythm == .quiet &&
            (w.tabs.selectedTabViewItem?.identifier as? String)=="behavior"
        w.detailFields[0][2].stringValue="1.5";w.save()
        let quiet=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
        checks["activityRhythmRetrySavesRetainedDraft"] = d.settings.activityRhythm == .quiet &&
            quiet.activityRhythm == .quiet && quiet.hoverDelay==0.75 && quiet.catalog.species[0].speed==1.5

        let beforeReset=try Data(contentsOf:savedURL)
        w.resetDefaults()
        let afterReset=try Data(contentsOf:savedURL)
        checks["activityRhythmResetOnlyEditsDraft"] = w.draft.activityRhythm == .steady &&
            selectedMode(w) == .steady && w.activityRhythmPopup.isEnabled &&
            d.settings.activityRhythm == .quiet && beforeReset==afterReset &&
            w.message.stringValue==w.t("已恢复默认（尚未保存）。","Defaults restored (not saved).")
        w.cancel()
        let reset=SpeciesSettingsWindow(desktop:d);d.settingsWindow=reset;reset.showWindow(nil)
        defer {reset.cancel()}
        checks["activityRhythmCancelledResetReopensSavedMode"] = reset.draft.activityRhythm == .quiet &&
            selectedMode(reset) == .quiet && d.settings.activityRhythm == .quiet
        reset.resetDefaults();reset.save()
        let restored=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
        let defaultData=try settingsData(BirdSettings()),restoredData=try settingsData(restored)
        let restoredActive=try settingsData(d.settings)
        checks["activityRhythmRestoredDefaultsSavedAndApplied"] = selectedMode(reset) == .steady &&
            restored.activityRhythm == .steady && defaultData==restoredData && restoredActive==defaultData
        checks["activityRhythmVerificationRemainsIsolated"] = isIsolated(d,preferences:preferences,folder:evidence)
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

    private static func isIsolated(_ d:DesktopController,preferences:UserDefaults,folder:URL) -> Bool {
        d.timer==nil && d.status==nil && d.globalMouseMonitor==nil && d.localMouseMonitor==nil &&
            d.panels.isEmpty && d.views.isEmpty && d.birds.isEmpty && !d.automaticPopulation &&
            !d.engine.populationEnabled && !d.engine.ambientEnabled && !d.engine.autonomousRouting &&
            d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 && !d.engine.hasLeafPreview &&
            !d.visitorMemoryPersistenceEnabled && d.visitorMemoryPersistence==nil &&
            !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path) &&
            d.visitorMemoryURL==folder.appendingPathComponent("visitors.json") &&
            d.settingsURL==folder.appendingPathComponent("settings.json") &&
            d.legacyURL==folder.appendingPathComponent("legacy.json") && d.preferences === preferences
    }

    // Compare every setting except the behavior explicitly under test.
    private static func settingsData(_ value:BirdSettings,ignoringRhythm:Bool=false) throws -> Data {
        var value=value
        if ignoringRhythm {value.activityRhythm = .steady}
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private static func selectedMode(_ w:SpeciesSettingsWindow) -> ActivityRhythmMode? {
        let index=w.activityRhythmPopup.indexOfSelectedItem
        return ActivityRhythmMode.allCases.indices.contains(index) ? ActivityRhythmMode.allCases[index]:nil
    }

    @discardableResult private static func choose(_ mode:ActivityRhythmMode,in w:SpeciesSettingsWindow) -> Bool {
        guard let index=ActivityRhythmMode.allCases.firstIndex(of:mode),let action=w.activityRhythmPopup.action else {return false}
        w.activityRhythmPopup.selectItem(at:index)
        return w.activityRhythmPopup.sendAction(action,to:w.activityRhythmPopup.target)
    }

    private static func set(_ button:NSButton,to enabled:Bool) {
        if (button.state == .on) != enabled {button.performClick(nil)}
    }

    private static func configure(_ w:SpeciesSettingsWindow,perch:Bool,encounters:Bool,memory:Bool) {
        set(w.perchActionsButton,to:true)
        set(w.passiveAttentionButton,to:memory);set(w.sideHopButton,to:!memory)
        set(w.takeoffPreparationButton,to:encounters);set(w.perchActionsButton,to:perch)
        set(w.pointerVisitsButton,to:true);set(w.pointerFollowButton,to:memory)
        set(w.pointerVisitsButton,to:encounters);set(w.flockPassesButton,to:!encounters)
        set(w.socialInteractionsButton,to:memory)
        set(w.leafPlayButton,to:true);set(w.ambientLeafPlayButton,to:!memory)
        set(w.leafPlayButton,to:encounters);set(w.visitorMemoryButton,to:memory)
        w.ambientFrequencyPopup.selectItem(at:encounters ? 2:0);w.ambientSettingsChanged()
    }

    private static func controlEnablement(_ w:SpeciesSettingsWindow) -> [Bool] {
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return []}
        return document.subviews.compactMap{$0 as? NSControl}.map(\.isEnabled)
    }

    private static func checkLayout(_ w:SpeciesSettingsWindow,suffix:String,folder:URL,checks:inout [String:Bool]) throws {
        let prefix="activityRhythmLayout-"+suffix
        for name in ["Labels","ExistingPositions","Reachable","FooterVisible","TitlesFit","HelpFits","NoOverlap","Screenshot"] {
            checks[prefix+name]=false
        }
        w.tabs.selectTabViewItem(at:2)
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return}
        func label(_ identifier:String) -> NSTextField? {
            document.subviews.compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue==identifier}
        }
        guard let heading=label("activityRhythmSectionTitle"),let caption=label("activityRhythmLabel"),
              let help=label("activityRhythmHelp"),let visitors=label("visitorMemoryHelp") else {return}
        let top=max(0,heading.frame.minY-12),limit=max(0,document.bounds.height-scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:CGPoint(x:0,y:min(top,limit)));scroll.reflectScrolledClipView(scroll.contentView)
        w.window?.contentView?.layoutSubtreeIfNeeded()
        let expected=[w.t("保持日常","Keep everyday rhythm"),w.t("跟随本地昼夜","Follow local day/night"),w.t("安静陪伴","Quiet companionship")]
        checks[prefix+"Labels"] = w.activityRhythmPopup.itemTitles==expected &&
            heading.stringValue==w.t("陪伴节奏","Companionship rhythm") &&
            caption.stringValue==w.t("活动节奏","Activity rhythm") &&
            w.activityRhythmPopup.accessibilityLabel()==caption.stringValue
        checks[prefix+"ExistingPositions"] = w.hoverDelaySlider.frame.minY==122 &&
            w.pointerVisitsButton.frame.minY==310 && w.perchActionsButton.frame.minY==916 &&
            w.sideHopButton.frame.minY==1322 && w.previewSideHopButton.frame.minY==1480 &&
            label("leafSectionTitle")?.frame.minY==1600 && w.leafPlayButton.frame.minY==1642 &&
            w.releaseLeafButton.frame.minY==1808 && label("visitorMemorySectionTitle")?.frame.minY==1960 &&
            w.visitorMemoryButton.frame.minY==2002 && visitors.frame.maxY<heading.frame.minY
        let views:[NSView]=[heading,caption,w.activityRhythmPopup,help]
        checks[prefix+"Reachable"] = views.allSatisfy{!$0.isHidden && document.visibleRect.contains($0.frame)} &&
            w.activityRhythmPopup.isEnabled && w.activityRhythmPopup.numberOfItems==3 &&
            w.activityRhythmPopup.itemArray.allSatisfy{!$0.isHidden && $0.isEnabled} &&
            w.message.superview.map{$0.bounds.contains(w.message.frame)} == true
        let footerActions:Set<Selector>=[#selector(SpeciesSettingsWindow.resetDefaults),#selector(SpeciesSettingsWindow.cancel),#selector(SpeciesSettingsWindow.save)]
        let footer=w.window?.contentView?.subviews.compactMap{$0 as? NSButton}.filter {
            $0.action.map{footerActions.contains($0)} ?? false
        } ?? []
        checks[prefix+"FooterVisible"] = footer.count==3 && footer.allSatisfy {button in
            !button.isHidden && button.isEnabled && button.superview.map{parent in parent.bounds.contains(button.frame)} == true &&
                button.intrinsicContentSize.width<=button.frame.width
        }
        let labels=[heading,caption]
        checks[prefix+"TitlesFit"] = labels.allSatisfy {
            ($0.cell?.cellSize(forBounds:$0.bounds).height ?? .infinity)<=$0.frame.height
        } && w.activityRhythmPopup.intrinsicContentSize.width<=w.activityRhythmPopup.frame.width &&
            w.activityRhythmPopup.intrinsicContentSize.height<=w.activityRhythmPopup.frame.height &&
            expected.allSatisfy {
                let size=($0 as NSString).size(withAttributes:[.font:w.activityRhythmPopup.font ?? NSFont.systemFont(ofSize:NSFont.systemFontSize)])
                return size.width+44<=w.activityRhythmPopup.frame.width
            }
        checks[prefix+"HelpFits"] = !help.stringValue.isEmpty &&
            document.visibleRect.contains(help.frame) &&
            (help.cell?.cellSize(forBounds:help.bounds).height ?? .infinity)<=help.frame.height
        checks[prefix+"NoOverlap"] = document.subviews.enumerated().allSatisfy {index,view in
            document.bounds.contains(view.frame) && document.subviews.dropFirst(index+1).allSatisfy{!view.frame.intersects($0.frame)}
        }
        let url=folder.appendingPathComponent("activity-rhythm-settings-"+suffix+".png")
        try SettingsVerification.snapshot(w.window!,to:url)
        checks[prefix+"Screenshot"] = NSImage(contentsOf:url).map{$0.size.width>0 && $0.size.height>0} ?? false
    }
}
