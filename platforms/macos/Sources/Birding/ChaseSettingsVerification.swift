import AppKit
import BirdingCore

/// Native controls and temporary settings, without spawning fixture birds.
/// Never starts a desktop, population scheduler, timer or visitor-memory writer.
enum ChaseSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("chase-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        checks["chaseVerificationCompleted"]=false
        defer {
            let ownChecks=checks.filter{$0.key.hasPrefix("chase")}
            saveJSON(["passed":!ownChecks.isEmpty && ownChecks.values.allSatisfy{$0},"checks":ownChecks],
                     to:evidence.appendingPathComponent("report.json"))
        }
        let suite="Birding.ChaseSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {
            throw NSError(domain:"ChaseSettingsVerification",code:1)
        }
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=isolatedDesktop(preferences:preferences,folder:evidence)
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["chaseDefaultOnWithoutCreatingSettings"] = defaults.chaseEnabled && defaults.socialInteractions &&
            defaults.schemaVersion==1 && !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let cancelled=SpeciesSettingsWindow(desktop:d);cancelled.showWindow(nil)
        cancelled.chaseButton.performClick(nil);cancelled.socialInteractionsButton.performClick(nil)
        checks["chaseOnlyEditsDraft"] = !cancelled.draft.chaseEnabled && !cancelled.draft.socialInteractions &&
            d.settings.chaseEnabled && d.settings.socialInteractions &&
            cancelled.message.stringValue==cancelled.t("尚未保存","Unsaved changes")
        cancelled.cancel()
        checks["chaseCancelDoesNotApplyOrSave"] = cancelled.window?.isVisible == false &&
            d.settings.chaseEnabled && d.settings.socialInteractions && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel()}
        checks["chaseReopenDiscardsCancelledDraft"] = w !== cancelled && w.draft.chaseEnabled &&
            w.chaseButton.state == .on && w.chaseButton.isEnabled
        w.tabs.selectTabViewItem(at:2)
        w.hoverDelayField.stringValue="0.25";w.detailFields[0][2].stringValue="1.25"
        w.sliders[0].doubleValue=35;w.sliderChanged(w.sliders[0]);w.locks[0].performClick(nil)

        for child in [false,true] {
            configure(w,master:true,child:child)
            let otherBefore=try settingsData(w.draft,ignoringChase:true)
            set(w.socialInteractionsButton,to:false)
            let suffix="-\(child)"
            checks["chaseMasterDisablesAndRetainsPreference"+suffix] = !w.draft.socialInteractions &&
                !w.chaseButton.isEnabled && w.draft.chaseEnabled==child &&
                w.chaseButton.state == (child ? .on:.off) && w.previewChaseButton.isEnabled
            w.chaseButton.performClick(nil);w.relocalize()
            checks["chaseDisabledPreferenceSurvivesClickAndRebuild"+suffix] = !w.chaseButton.isEnabled &&
                w.draft.chaseEnabled==child && w.chaseButton.state == (child ? .on:.off)
            set(w.socialInteractionsButton,to:true)
            let otherAfter=try settingsData(w.draft,ignoringChase:true)
            checks["chaseMasterRestoresPreferenceWithoutOtherChanges"+suffix] = w.chaseButton.isEnabled &&
                w.draft.chaseEnabled==child && otherBefore==otherAfter && d.settings.chaseEnabled
        }

        for master in [false,true] {
            for child in [false,true] {
                configure(w,master:master,child:child);w.save()
                let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
                let object=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as? [String:Any]
                let expected=try settingsData(w.draft),active=try settingsData(d.settings),stored=try settingsData(saved)
                let suffix="-master-\(master)-child-\(child)"
                checks["chaseSaveAppliesExactPreferenceCombination"+suffix] =
                    matches(saved,master:master,child:child) && matches(d.settings,master:master,child:child) &&
                    (object?["chaseEnabled"] as? Bool)==child && (object?["socialInteractions"] as? Bool)==master &&
                    (object?["schemaVersion"] as? Int)==1 && expected==stored && active==stored &&
                    saved.hoverDelay==0.25 && saved.catalog.species[0].speed==1.25 && saved.probabilities.entries[0].locked &&
                    w.chaseButton.isEnabled==master &&
                    w.message.stringValue==w.t("已保存 · 交互设置立即生效，鸟种参数用于新飞入的小鸟。","Saved · Interaction settings apply now; species settings affect new arrivals.")
                let reloaded=isolatedDesktop(preferences:preferences,folder:evidence)
                try reloaded.loadSpeciesConfig()
                let reloadedData=try settingsData(reloaded.settings)
                checks["chaseReloadKeepsExactPreferenceCombination"+suffix] = reloadedData==stored &&
                    isIsolated(reloaded,preferences:preferences,folder:evidence)
            }
        }
        // Save must read the native checkbox even without a dispatched action.
        configure(w,master:true,child:true);w.chaseButton.state = .off;w.save()
        let native=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["chaseSaveReadsNativeCheckbox"] = !native.chaseEnabled && !d.settings.chaseEnabled && !w.draft.chaseEnabled

        for language:AppLanguage in [.chinese,.english] {
            d.language=language
            let suffix=language == .chinese ? "zh":"en"
            configure(w,master:true,child:false);w.save()
            configure(w,master:true,child:true)
            w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="1.5"
            w.relocalize()
            checks["chaseDraftAndRawEditsSurviveLanguageRebuild-"+suffix] = w.draft.chaseEnabled &&
                w.chaseButton.state == .on && w.chaseButton.isEnabled && !d.settings.chaseEnabled &&
                w.hoverDelayField.stringValue=="0.75" && w.detailFields[0][2].stringValue=="1.5" &&
                w.draft.probabilities.entries[0].locked && (w.tabs.selectedTabViewItem?.identifier as? String)=="interaction"
            checkRejection(w,reasons:[.disabled],suffix:"saved-child-off-"+suffix,checks:&checks)
            d.paused=true
            checkRejection(w,reasons:[.paused],suffix:"paused-"+suffix,checks:&checks)
            d.paused=false
            let savedURL=d.settingsURL,savedBytes=try Data(contentsOf:d.settingsURL)
            let savedActive=try settingsData(d.settings)
            d.settingsURL=evidence;w.save();d.settingsURL=savedURL
            let afterFailure=try settingsData(d.settings),afterBytes=try Data(contentsOf:savedURL)
            checks["chaseFailedSaveRetainsActiveFileAndDraft-"+suffix] = afterFailure==savedActive &&
                afterBytes==savedBytes && w.draft.chaseEnabled && !d.settings.chaseEnabled &&
                w.hoverDelayField.stringValue=="0.75" && w.detailFields[0][2].stringValue=="1.5" &&
                w.message.stringValue==w.t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.")
            w.save()
            let retried=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
            checks["chaseRetrySavesRetainedDraft-"+suffix] = retried.chaseEnabled && d.settings.chaseEnabled &&
                retried.hoverDelay==0.75 && retried.catalog.species[0].speed==1.5
            for master in [true,false] {
                configure(w,master:master,child:true);w.relocalize()
                try checkLayout(w,suffix:suffix+(master ? "-enabled":"-master-off"),folder:evidence,checks:&checks)
            }
            configure(w,master:false,child:true);w.save()
            configure(w,master:true,child:true)
            checkRejection(w,reasons:[.disabled],suffix:"saved-master-off-"+suffix,checks:&checks)
        }

        configure(w,master:true,child:false)
        let beforeInvalid=try settingsData(d.settings),bytesBeforeInvalid=try Data(contentsOf:d.settingsURL)
        w.hoverDelayField.stringValue="invalid";w.save()
        let invalidDelayActive=try settingsData(d.settings),invalidDelayBytes=try Data(contentsOf:d.settingsURL)
        checks["chaseInvalidDelayPreventsPartialApply"] = invalidDelayActive==beforeInvalid &&
            invalidDelayBytes==bytesBeforeInvalid && !w.draft.chaseEnabled &&
            (w.tabs.selectedTabViewItem?.identifier as? String)=="interaction"
        w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="9";w.save()
        let invalidDetailsActive=try settingsData(d.settings),invalidDetailsBytes=try Data(contentsOf:d.settingsURL)
        checks["chaseInvalidDetailsPreventsPartialApply"] = invalidDetailsActive==beforeInvalid &&
            invalidDetailsBytes==bytesBeforeInvalid && !w.draft.chaseEnabled &&
            (w.tabs.selectedTabViewItem?.identifier as? String)=="behavior"
        w.detailFields[0][2].stringValue="1.5";w.save()
        let beforeReset=try Data(contentsOf:d.settingsURL)
        w.resetDefaults()
        let afterReset=try Data(contentsOf:d.settingsURL)
        checks["chaseResetOnlyChangesDraft"] = w.draft.chaseEnabled && w.draft.socialInteractions &&
            w.chaseButton.state == .on && w.chaseButton.isEnabled && !d.settings.chaseEnabled &&
            beforeReset==afterReset &&
            w.message.stringValue==w.t("已恢复默认（尚未保存，锁定已清除）。","Defaults restored (not saved; locks cleared).")
        w.cancel()
        let reset=SpeciesSettingsWindow(desktop:d);d.settingsWindow=reset;reset.showWindow(nil)
        defer {reset.cancel()}
        checks["chaseCancelResetReopensSavedOff"] = !reset.draft.chaseEnabled && reset.chaseButton.state == .off
        reset.resetDefaults();reset.save()
        let restored=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        let restoredData=try settingsData(restored),defaultData=try settingsData(BirdSettings())
        checks["chaseRestoreDefaultsSavesAndApplies"] = restored.chaseEnabled && d.settings.chaseEnabled &&
            restoredData==defaultData && reset.chaseButton.state == .on && reset.chaseButton.isEnabled
        checkPreviewRejections(reset,checks:&checks)
        d.birds=[];d.surfaces=[]
        checks["chaseVerificationRemainsIsolated"] = isIsolated(d,preferences:preferences,folder:evidence)
        checks["chaseVerificationCompleted"]=true
    }

    private static func isolatedDesktop(preferences:UserDefaults,folder:URL) -> DesktopController {
        let d=DesktopController();d.preferences=preferences;d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
        d.visitorMemoryPersistenceEnabled=false;d.visitorMemoryURL=folder.appendingPathComponent("visitors.json")
        return d
    }

    private static func isIsolated(_ d:DesktopController,preferences:UserDefaults,folder:URL) -> Bool {
        d.timer==nil && d.status==nil && d.globalMouseMonitor==nil && d.localMouseMonitor==nil &&
            d.panels.isEmpty && d.views.isEmpty && d.birds.isEmpty && !d.automaticPopulation &&
            !d.engine.populationEnabled && !d.engine.ambientEnabled && !d.engine.autonomousRouting &&
            d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0 &&
            !d.engine.hasLeafPreview && d.engine.scenePropCount==0 && d.arrivalCount==0 && d.departureCount==0 &&
            !d.visitorMemoryPersistenceEnabled && d.visitorMemoryPersistence==nil &&
            !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path) &&
            d.visitorMemoryURL==folder.appendingPathComponent("visitors.json") &&
            d.settingsURL==folder.appendingPathComponent("settings.json") &&
            d.legacyURL==folder.appendingPathComponent("legacy.json") && d.preferences === preferences
    }

    private static func settingsData(_ settings:BirdSettings,ignoringChase:Bool=false) throws -> Data {
        var value=settings;value.pendingSpecies=[]
        if ignoringChase {value.chaseEnabled=true}
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private static func set(_ button:NSButton,to enabled:Bool) {
        if (button.state == .on) != enabled {button.performClick(nil)}
    }
    private static func configure(_ w:SpeciesSettingsWindow,master:Bool,child:Bool) {
        set(w.socialInteractionsButton,to:true);set(w.chaseButton,to:child);set(w.socialInteractionsButton,to:master)
    }
    private static func matches(_ value:BirdSettings,master:Bool,child:Bool) -> Bool {
        value.socialInteractions==master && value.chaseEnabled==child
    }
    private static func population(_ d:DesktopController) -> [Int] {
        [d.birds.count,d.residentCount,d.engine.passingCount,d.engine.departingCount,d.engine.pendingCount,
         d.arrivalCount,d.departureCount,d.engine.scenePropCount]
    }

    private static func checkRejection(_ w:SpeciesSettingsWindow,reasons:Set<BehaviorReason>,suffix:String,
                                       checks:inout [String:Bool]) {
        let d=w.desktop,counts=population(w.desktop),sequence=d.engine.events.last?.sequence
        let runs=d.engine.activeRunCount,leases=d.engine.leasedBirdCount,slots=d.engine.reservedLandingCount
        let positions=d.birds.map(\.position),revisions=d.birds.map(\.motionRevision)
        w.previewChaseButton.performClick(nil)
        let event=d.engine.events.last
        checks["chasePreviewRejection-"+suffix] = event?.sequence != sequence && event?.kind == .chase &&
            event?.type == .rejected && event?.source == .preview &&
            event?.reason.map {reason in
                let expected=w.chasePreviewMessage(reason)
                return reasons.contains(reason) && w.message.stringValue==expected
            } == true
        checks["chaseRejectedPreviewKeepsPopulationMotionAndLeases-"+suffix] = population(d)==counts &&
            d.engine.activeRunCount==runs && d.engine.leasedBirdCount==leases && d.engine.reservedLandingCount==slots &&
            d.birds.map(\.position)==positions && d.birds.map(\.motionRevision)==revisions
        checks["chaseRejectionMessageFits-"+suffix] =
            (w.message.cell?.cellSize(forBounds:w.message.bounds).height ?? .infinity)<=w.message.frame.height
    }

    private static func checkPreviewRejections(_ w:SpeciesSettingsWindow,checks:inout [String:Bool]) {
        let d=w.desktop
        // No fixture birds are needed: these settings checks never request a
        // successful run. The native behavior verifier owns flight trajectories.
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let suffix=language == .chinese ? "zh":"en"
            configure(w,master:false,child:false)
            checkRejection(w,reasons:[.noCompanion,.missingBird,.unavailableBird,.noSpecies],
                           suffix:"saved-enabled-no-pair-"+suffix,checks:&checks)
            checks["chasePreviewReadsSavedEnabledSettings-"+suffix] = !w.draft.chaseEnabled &&
                !w.draft.socialInteractions && d.settings.chaseEnabled && d.settings.socialInteractions
            checks["chaseUnsupportedSpeciesMessageIsSpecific-"+suffix] =
                w.chasePreviewMessage(.noSpecies)==w.t("此处没有支持追逐的鸟种，请参考上方鸟种说明。","No supported chase species here. See the species list above.") &&
                w.chasePreviewMessage(.noSpecies) != d.behaviorMessage(.noSpecies)
            checks["chaseCompanionAndSpaceMessagesAreSpecific-"+suffix] =
                w.chasePreviewMessage(.noCompanion)==w.t("请等待两只支持追逐的同种鸟在附近停稳。","Wait for two supported birds of the same species to settle nearby.") &&
                w.chasePreviewMessage(.noSpace)==w.t("追逐和落回的空间不足，请等待更开阔的位置。","Not enough room to chase and return. Wait for a clearer area.")
            checks["chaseDisabledMessageNamesBothSwitches-"+suffix] =
                w.chasePreviewMessage(.disabled)==w.t("请先保存并开启双鸟互动和短暂追逐。","Save and enable Two-bird interactions and Brief chases first.")
            checks["chaseAllRejectionMessagesFit-"+suffix] =
                [BehaviorReason.noSpecies,.noCompanion,.noSpace,.disabled,.paused,.busy,.missingFrames].allSatisfy {reason in
                    w.message.stringValue=w.chasePreviewMessage(reason)
                    return (w.message.cell?.cellSize(forBounds:w.message.bounds).height ?? .infinity)<=w.message.frame.height
                }
        }
        configure(w,master:true,child:true)
        w.activityRhythmPopup.selectItem(at:ActivityRhythmMode.allCases.firstIndex(of:.quiet)!)
        w.activityRhythmSettingsChanged();w.save()
        checkRejection(w,reasons:[.noCompanion,.missingBird,.unavailableBird,.noSpecies],suffix:"quiet-manual-preview",checks:&checks)
        checks["chaseQuietStillAllowsManualPreviewThroughSavedGates"] = d.settings.activityRhythm == .quiet &&
            d.settings.chaseEnabled && d.settings.socialInteractions && d.engine.events.last?.reason != .disabled
    }

    private static func scrollToSection(_ w:SpeciesSettingsWindow) {
        w.tabs.selectTabViewItem(at:2)
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView,
              let heading=document.subviews.first(where:{$0.identifier?.rawValue=="chaseSectionTitle"}) else {return}
        let limit=max(0,document.bounds.height-scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:CGPoint(x:0,y:min(max(0,heading.frame.minY-12),limit)))
        scroll.reflectScrolledClipView(scroll.contentView);w.window?.contentView?.layoutSubtreeIfNeeded()
    }

    private static func checkLayout(_ w:SpeciesSettingsWindow,suffix:String,folder:URL,checks:inout [String:Bool]) throws {
        let prefix="chaseLayout-"+suffix
        for name in ["Labels","ExistingPositions","SpeciesNames","Reachable","TitlesFit","HelpFits","NoOverlap","FooterVisible","Screenshot"] {
            checks[prefix+name]=false
        }
        scrollToSection(w)
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return}
        func label(_ identifier:String) -> NSTextField? {
            document.subviews.compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue==identifier}
        }
        guard let heading=label("chaseSectionTitle"),let help=label("chaseHelp"),
              let previewHelp=label("chasePreviewHelp"),let edgeHelp=label("edgePeekPreviewHelp") else {return}
        let controls=[w.chaseButton!,w.previewChaseButton!]
        let views:[NSView]=[heading,w.chaseButton,w.previewChaseButton,help,previewHelp]
        checks[prefix+"Labels"] = heading.stringValue==w.t("短暂追逐","Brief chases") &&
            w.chaseButton.title==w.t("短暂追逐","Brief chases") &&
            w.chaseButton.accessibilityLabel()==w.chaseButton.title &&
            w.previewChaseButton.title==w.t("预览短暂追逐","Preview brief chase") &&
            w.chaseButton.identifier?.rawValue=="chaseEnabled" &&
            w.previewChaseButton.identifier?.rawValue=="previewChase"
        checks[prefix+"ExistingPositions"] = w.hoverDelaySlider.frame.minY==122 && w.pointerVisitsButton.frame.minY==310 &&
            w.perchActionsButton.frame.minY==916 && w.sideHopButton.frame.minY==1322 && w.previewSideHopButton.frame.minY==1480 &&
            label("leafSectionTitle")?.frame.minY==1600 && w.visitorMemoryButton.frame.minY==2002 &&
            label("activityRhythmSectionTitle")?.frame.minY==2180 && w.activityRhythmPopup.frame.minY==2222 &&
            label("edgePeekSectionTitle")?.frame.minY==2540 && w.edgePeekButton.frame.minY==2582 &&
            w.previewEdgePeekButton.frame.minY==2750 && edgeHelp.frame.minY==2796 && edgeHelp.frame.maxY<heading.frame.minY
        let species:[SpeciesID]=[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling]
        checks[prefix+"SpeciesNames"] = species.allSatisfy{help.stringValue.contains(w.language.name($0))}
        checks[prefix+"Reachable"] = views.allSatisfy{!$0.isHidden && document.visibleRect.contains($0.frame)} &&
            w.chaseButton.isEnabled==w.draft.socialInteractions && w.previewChaseButton.isEnabled
        checks[prefix+"TitlesFit"] = controls.allSatisfy {
            $0.intrinsicContentSize.width<=$0.frame.width && $0.intrinsicContentSize.height<=$0.frame.height
        } && (heading.cell?.cellSize(forBounds:heading.bounds).height ?? .infinity)<=heading.frame.height
        checks[prefix+"HelpFits"] = [help,previewHelp].allSatisfy {
            !$0.stringValue.isEmpty && document.visibleRect.contains($0.frame) &&
                ($0.cell?.cellSize(forBounds:$0.bounds).height ?? .infinity)<=$0.frame.height
        }
        checks[prefix+"NoOverlap"] = document.subviews.enumerated().allSatisfy {index,view in
            document.bounds.contains(view.frame) && document.subviews.dropFirst(index+1).allSatisfy{!view.frame.intersects($0.frame)}
        }
        let actions:Set<Selector>=[#selector(SpeciesSettingsWindow.resetDefaults),#selector(SpeciesSettingsWindow.cancel),#selector(SpeciesSettingsWindow.save)]
        let footer=w.window?.contentView?.subviews.compactMap{$0 as? NSButton}.filter {
            $0.action.map{actions.contains($0)} ?? false
        } ?? []
        checks[prefix+"FooterVisible"] = footer.count==3 && footer.allSatisfy {button in
            !button.isHidden && button.isEnabled && button.superview.map{parent in parent.bounds.contains(button.frame)} == true &&
                button.intrinsicContentSize.width<=button.frame.width
        } && w.message.superview.map{$0.bounds.contains(w.message.frame)} == true
        let url=folder.appendingPathComponent("chase-settings-"+suffix+".png")
        try SettingsVerification.snapshot(w.window!,to:url)
        checks[prefix+"Screenshot"] = NSImage(contentsOf:url).map{$0.size.width>0 && $0.size.height>0} ?? false
    }
}
