import AppKit
import BirdingCore

/// Native settings coverage in an isolated desktop. No desktop timers, population
/// scheduler or visitor-memory writer; the behavior verifier owns flight trajectories.
enum TravelTogetherSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("travel-together-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        checks["travelTogetherVerificationCompleted"]=false
        defer {
            let own=checks.filter{$0.key.hasPrefix("travelTogether")}
            saveJSON(["passed":!own.isEmpty && own.values.allSatisfy{$0},"checks":own],
                     to:evidence.appendingPathComponent("report.json"))
        }
        let suite="Birding.TravelTogetherSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {
            throw NSError(domain:"TravelTogetherSettingsVerification",code:1)
        }
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=isolatedDesktop(preferences:preferences,folder:evidence)
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["travelTogetherDefaultsOnWithoutWriting"] = defaults.travelTogetherEnabled && defaults.socialInteractions &&
            defaults.schemaVersion==1 && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        let cancelled=SpeciesSettingsWindow(desktop:d);cancelled.showWindow(nil)
        configure(cancelled,master:false,child:false)
        checks["travelTogetherOnlyEditsDraft"] = !cancelled.draft.travelTogetherEnabled &&
            !cancelled.draft.socialInteractions && d.settings.travelTogetherEnabled && d.settings.socialInteractions &&
            cancelled.message.stringValue==cancelled.t("尚未保存","Unsaved changes")
        cancelled.cancel()
        checks["travelTogetherCancelDoesNotApplyOrWrite"] = cancelled.window?.isVisible == false &&
            d.settings.travelTogetherEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel()}
        checks["travelTogetherReopenDiscardsCancelledDraft"] = w !== cancelled && w.draft.travelTogetherEnabled &&
            w.travelTogetherButton.state == .on && w.travelTogetherButton.isEnabled
        w.tabs.selectTabViewItem(at:2)
        w.hoverDelayField.stringValue="0.25";w.detailFields[0][2].stringValue="1.25"
        w.sliders[0].doubleValue=35;w.sliderChanged(w.sliders[0]);w.locks[0].performClick(nil)
        for child in [false,true] {
            configure(w,master:true,child:child)
            let before=try settingsData(w.draft)
            set(w.socialInteractionsButton,to:false)
            w.travelTogetherButton.performClick(nil);w.relocalize()
            let suffix=child ? "on":"off"
            checks["travelTogetherMasterRetainsDisabledPreference-"+suffix] = !w.travelTogetherButton.isEnabled &&
                w.draft.travelTogetherEnabled==child && w.travelTogetherButton.state == (child ? .on:.off) &&
                w.previewTravelTogetherButton.isEnabled
            set(w.socialInteractionsButton,to:true)
            let after=try settingsData(w.draft)
            checks["travelTogetherMasterRestoresPreferenceWithoutOtherChanges-"+suffix] =
                w.travelTogetherButton.isEnabled && before==after && d.settings.travelTogetherEnabled
        }

        configure(w,master:false,child:true);w.save()
        let masterOff=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        let expected=try settingsData(w.draft),active=try settingsData(d.settings),stored=try settingsData(masterOff)
        let reloaded=isolatedDesktop(preferences:preferences,folder:evidence);try reloaded.loadSpeciesConfig()
        let restarted=try settingsData(reloaded.settings)
        checks["travelTogetherSaveAndReloadRetainChildWithMasterOff"] = !masterOff.socialInteractions &&
            masterOff.travelTogetherEnabled && !w.travelTogetherButton.isEnabled && expected==active && active==stored &&
            stored==restarted && masterOff.hoverDelay==0.25 && masterOff.catalog.species[0].speed==1.25 &&
            masterOff.probabilities.entries[0].locked
        configure(w,master:true,child:true)
        w.travelTogetherButton.state = .off;w.save()
        let native=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["travelTogetherSaveReadsNativeCheckboxAndApplies"] = !native.travelTogetherEnabled &&
            !d.settings.travelTogetherEnabled && !w.draft.travelTogetherEnabled && native.socialInteractions &&
            w.message.stringValue==w.t("已保存 · 交互设置立即生效，鸟种参数用于新飞入的小鸟。","Saved · Interaction settings apply now; species settings affect new arrivals.")

        set(w.travelTogetherButton,to:true)
        w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="1.5"
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let suffix=language == .chinese ? "zh":"en"
            checks["travelTogetherLanguageRebuildKeepsDraftAndRawEdits-"+suffix] =
                w.draft.travelTogetherEnabled && !d.settings.travelTogetherEnabled &&
                w.travelTogetherButton.state == .on && w.hoverDelayField.stringValue=="0.75" &&
                w.detailFields[0][2].stringValue=="1.5" && w.draft.probabilities.entries[0].locked
            try checkLayout(w,suffix:suffix,folder:evidence,checks:&checks)
            checkRejection(w,reasons:[.disabled],suffix:"saved-child-off-"+suffix,checks:&checks)
            d.paused=true
            checkRejection(w,reasons:[.paused],suffix:"paused-"+suffix,checks:&checks)
            d.paused=false
        }
        let url=d.settingsURL,bytes=try Data(contentsOf:d.settingsURL),beforeFailure=try settingsData(d.settings)
        d.settingsURL=evidence;w.save();d.settingsURL=url
        let afterFailure=try settingsData(d.settings),afterBytes=try Data(contentsOf:url)
        checks["travelTogetherFailedSaveKeepsActiveFileAndDraft"] = beforeFailure==afterFailure && bytes==afterBytes &&
            !d.settings.travelTogetherEnabled && w.draft.travelTogetherEnabled &&
            w.hoverDelayField.stringValue=="0.75" && w.detailFields[0][2].stringValue=="1.5" &&
            w.message.stringValue==w.t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.")
        w.detailFields[0][2].stringValue="9";w.save()
        let afterInvalid=try settingsData(d.settings),invalidBytes=try Data(contentsOf:url)
        checks["travelTogetherInvalidDetailsPreventPartialApply"] = beforeFailure==afterInvalid && bytes==invalidBytes &&
            w.draft.travelTogetherEnabled && (w.tabs.selectedTabViewItem?.identifier as? String)=="behavior"
        w.detailFields[0][2].stringValue="1.5";w.save()
        let retry=try BirdSettings.load(from:url,legacyURL:d.legacyURL)
        checks["travelTogetherRetrySavesRetainedDraft"] = retry.travelTogetherEnabled && d.settings.travelTogetherEnabled &&
            retry.hoverDelay==0.75 && retry.catalog.species[0].speed==1.5

        checkPreviewGates(w,checks:&checks)
        configure(w,master:true,child:false);w.save()
        let beforeReset=try Data(contentsOf:url)
        w.resetDefaults()
        let resetBytes=try Data(contentsOf:url)
        checks["travelTogetherRestoreDefaultsOnlyEditsDraft"] = w.draft.travelTogetherEnabled &&
            w.travelTogetherButton.state == .on && w.travelTogetherButton.isEnabled &&
            !d.settings.travelTogetherEnabled && beforeReset==resetBytes
        w.cancel()
        let reset=SpeciesSettingsWindow(desktop:d);d.settingsWindow=reset;reset.showWindow(nil)
        defer {reset.cancel()}
        checks["travelTogetherCancelledResetReopensSavedOff"] = !reset.draft.travelTogetherEnabled &&
            reset.travelTogetherButton.state == .off
        reset.resetDefaults();reset.save()
        let restored=try BirdSettings.load(from:url,legacyURL:d.legacyURL)
        checks["travelTogetherDefaultsSaveAndApply"] = restored.travelTogetherEnabled && restored.socialInteractions &&
            d.settings.travelTogetherEnabled && d.settings.socialInteractions
        checks["travelTogetherVerificationRemainsIsolated"] = d.timer==nil && d.status==nil &&
            d.globalMouseMonitor==nil && d.localMouseMonitor==nil && d.panels.isEmpty && d.views.isEmpty &&
            d.birds.isEmpty && !d.automaticPopulation && !d.engine.populationEnabled && !d.engine.ambientEnabled &&
            !d.engine.autonomousRouting && d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 &&
            !d.visitorMemoryPersistenceEnabled && d.visitorMemoryPersistence==nil &&
            !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path)
        checks["travelTogetherVerificationCompleted"]=true
    }

    private static func isolatedDesktop(preferences:UserDefaults,folder:URL) -> DesktopController {
        let d=DesktopController();d.preferences=preferences;d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
        d.visitorMemoryPersistenceEnabled=false;d.visitorMemoryURL=folder.appendingPathComponent("visitors.json")
        return d
    }
    private static func settingsData(_ settings:BirdSettings) throws -> Data {
        var value=settings;value.pendingSpecies=[]
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
    private static func set(_ button:NSButton,to enabled:Bool) {
        if (button.state == .on) != enabled {button.performClick(nil)}
    }
    private static func configure(_ w:SpeciesSettingsWindow,master:Bool,child:Bool) {
        set(w.socialInteractionsButton,to:true);set(w.travelTogetherButton,to:child);set(w.socialInteractionsButton,to:master)
    }
    private static func checkRejection(_ w:SpeciesSettingsWindow,reasons:Set<BehaviorReason>,suffix:String,
                                       checks:inout [String:Bool]) {
        let e=w.desktop.engine,sequence=e.events.last?.sequence
        let birds=e.birds,positions=birds.map(\.position),states=birds.map(\.state),revisions=birds.map(\.motionRevision)
        let counts=[e.birds.count,e.residentCount,e.passingCount,e.departingCount,e.pendingCount,e.arrivalCount,e.departureCount]
        let runs=e.activeRunCount,leases=e.leasedBirdCount,slots=e.reservedLandingCount
        w.previewTravelTogetherButton.performClick(nil)
        let event=e.events.last
        checks["travelTogetherPreviewRejection-"+suffix] = event?.sequence != sequence && event?.kind == .travelTogether &&
            event?.source == .preview && event?.type == .rejected && event?.reason.map {reason in
                reasons.contains(reason) && w.message.stringValue==w.travelTogetherPreviewMessage(reason)
            } == true
        checks["travelTogetherRejectedPreviewPreservesBirdsAndMotion-"+suffix] =
            counts==[e.birds.count,e.residentCount,e.passingCount,e.departingCount,e.pendingCount,e.arrivalCount,e.departureCount] &&
            zip(birds,e.birds).allSatisfy{$0.0 === $0.1} && e.birds.map(\.position)==positions &&
            e.birds.map(\.state)==states && e.birds.map(\.motionRevision)==revisions &&
            e.activeRunCount==runs && e.leasedBirdCount==leases && e.reservedLandingCount==slots
    }
    private static func checkPreviewGates(_ w:SpeciesSettingsWindow,checks:inout [String:Bool]) {
        let d=w.desktop
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            let suffix=language == .chinese ? "zh":"en"
            configure(w,master:true,child:true);w.save()
            configure(w,master:false,child:false)
            checkRejection(w,reasons:[.noCompanion,.noSpecies,.unavailableBird,.missingBird],
                           suffix:"saved-on-empty-"+suffix,checks:&checks)
            checks["travelTogetherPreviewUsesSavedEnabledSwitches-"+suffix] = d.settings.travelTogetherEnabled &&
                d.settings.socialInteractions && !w.draft.travelTogetherEnabled && !w.draft.socialInteractions
            configure(w,master:false,child:true);w.save();set(w.socialInteractionsButton,to:true)
            checkRejection(w,reasons:[.disabled],suffix:"saved-master-off-"+suffix,checks:&checks)
            w.activityRhythmPopup.selectItem(at:ActivityRhythmMode.allCases.firstIndex(of:.quiet)!)
            w.activityRhythmSettingsChanged();w.save()
            checkRejection(w,reasons:[.noCompanion,.noSpecies,.unavailableBird,.missingBird],
                           suffix:"quiet-manual-empty-"+suffix,checks:&checks)
            checks["travelTogetherQuietAllowsManualPreviewThroughSavedGates-"+suffix] =
                d.settings.activityRhythm == .quiet && d.engine.events.last?.reason != .disabled
            checks["travelTogetherFlyingCandidateMessage-"+suffix] = w.travelTogetherPreviewMessage(.noCompanion)==w.t(
                "请等待两只支持结队的同种居民鸟正在独立飞行；不会让停栖鸟起飞。",
                "Wait for two supported same-species residents flying independently; perched birds stay perched.")
            checks["travelTogetherAllMessagesFit-"+suffix] =
                [BehaviorReason.noSpecies,.noCompanion,.missingBird,.unavailableBird,.noSpace,.disabled,.paused,.busy,.missingFrames].allSatisfy {reason in
                    w.message.stringValue=w.travelTogetherPreviewMessage(reason)
                    return (w.message.cell?.cellSize(forBounds:w.message.bounds).height ?? .infinity)<=w.message.frame.height
                }
            // An already-perched supported pair must never be lifted by this button.
            let host=Surface(id:956,rect:CGRect(x:100,y:600,width:1000,height:180))
            d.surfaces=[host]
            let birds=[CGFloat(0.4),CGFloat(0.6)].map {fraction -> Bird in
                let bird=Bird(position:.zero,fraction:fraction,profile:d.catalog.profile(.treeSparrow),random:{0.5})
                bird.perch(on:host);bird.perchDuration=600
                return bird
            }
            d.engine.installFixtureBirds(birds)
            checkRejection(w,reasons:[.noCompanion,.noSpecies,.unavailableBird,.missingBird],
                           suffix:"perched-pair-"+suffix,checks:&checks)
            checks["travelTogetherPerchedBirdsNeverTakeOff-"+suffix] = birds.allSatisfy{$0.state == .perched && d.engine.behavior(of:$0)==nil}
            d.birds=[];d.surfaces=[]
        }
    }

    private static func checkLayout(_ w:SpeciesSettingsWindow,suffix:String,folder:URL,checks:inout [String:Bool]) throws {
        let prefix="travelTogetherLayout-"+suffix
        checks[prefix+"SectionPresent"]=false
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return}
        func label(_ id:String) -> NSTextField? {
            document.subviews.compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue==id}
        }
        guard let heading=label("travelTogetherSectionTitle"),let help=label("travelTogetherHelp"),
              let previewHelp=label("travelTogetherPreviewHelp") else {return}
        checks[prefix+"SectionPresent"]=true
        let limit=max(0,document.bounds.height-scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:CGPoint(x:0,y:min(max(0,heading.frame.minY-12),limit)))
        scroll.reflectScrolledClipView(scroll.contentView);w.window?.contentView?.layoutSubtreeIfNeeded()
        let views:[NSView]=[heading,w.travelTogetherButton,help,w.previewTravelTogetherButton,previewHelp]
        checks[prefix+"Labels"] = heading.stringValue==w.t("飞行中临时结队","Travel together in flight") &&
            w.travelTogetherButton.title==heading.stringValue &&
            w.travelTogetherButton.accessibilityLabel()==w.travelTogetherButton.title &&
            w.previewTravelTogetherButton.title==w.t("预览飞行中结队","Preview travel together") &&
            w.travelTogetherButton.identifier?.rawValue=="travelTogetherEnabled" &&
            w.previewTravelTogetherButton.identifier?.rawValue=="previewTravelTogether"
        let expected:Set<SpeciesID>=[.treeSparrow,.barnSwallow,.spottedDove,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling]
        checks[prefix+"SpeciesNames"] = TravelTogetherBehavior.supportedSpecies==expected &&
            expected.allSatisfy{help.stringValue.contains(w.language.name($0))}
        checks[prefix+"ExistingCoordinates"] = w.hoverDelaySlider.frame.minY==122 && w.pointerVisitsButton.frame.minY==310 &&
            w.socialInteractionsButton.frame.minY==418 && w.perchActionsButton.frame.minY==916 &&
            w.sideHopButton.frame.minY==1322 && label("leafSectionTitle")?.frame.minY==1600 &&
            w.visitorMemoryButton.frame.minY==2002 && w.activityRhythmPopup.frame.minY==2222 &&
            w.edgePeekButton.frame.minY==2582 && w.chaseButton.frame.minY==2992 &&
            w.previewChaseButton.frame.minY==3180 && label("chasePreviewHelp")?.frame.maxY==3330 && heading.frame.minY>3330
        checks[prefix+"Reachable"] = views.allSatisfy{!$0.isHidden && document.visibleRect.contains($0.frame)} &&
            w.travelTogetherButton.isEnabled==w.draft.socialInteractions && w.previewTravelTogetherButton.isEnabled
        checks[prefix+"TitlesAndHelpFit"] = [w.travelTogetherButton!,w.previewTravelTogetherButton!].allSatisfy {
            $0.intrinsicContentSize.width<=$0.frame.width && $0.intrinsicContentSize.height<=$0.frame.height
        } && [heading,help,previewHelp].allSatisfy {
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
        try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("travel-together-settings-"+suffix+".png"))
    }
}
