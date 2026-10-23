import AppKit
import BirdingCore

/// Native settings coverage in an isolated desktop. No desktop timers, population
/// scheduler or visitor-memory writer; the behavior verifier owns interaction trajectories.
enum AllopreeningSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("allopreening-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        checks["allopreeningVerificationCompleted"]=false
        defer {
            let own=checks.filter{$0.key.hasPrefix("allopreening")}
            saveJSON(["passed":!own.isEmpty && own.values.allSatisfy{$0},"checks":own],
                     to:evidence.appendingPathComponent("report.json"))
        }
        let suite="Birding.AllopreeningSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {
            throw NSError(domain:"AllopreeningSettingsVerification",code:1)
        }
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=isolatedDesktop(preferences:preferences,folder:evidence)
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["allopreeningDefaultsOnWithoutWriting"] = defaults.allopreeningEnabled && defaults.socialInteractions &&
            defaults.schemaVersion==1 && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        let cancelled=SpeciesSettingsWindow(desktop:d);cancelled.showWindow(nil)
        configure(cancelled,master:false,child:false)
        checks["allopreeningOnlyEditsDraft"] = !cancelled.draft.allopreeningEnabled &&
            !cancelled.draft.socialInteractions && d.settings.allopreeningEnabled && d.settings.socialInteractions &&
            cancelled.message.stringValue==cancelled.t("尚未保存","Unsaved changes")
        cancelled.cancel()
        checks["allopreeningCancelDoesNotApplyOrWrite"] = cancelled.window?.isVisible == false &&
            d.settings.allopreeningEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel()}
        checks["allopreeningReopenDiscardsCancelledDraft"] = w !== cancelled && w.draft.allopreeningEnabled &&
            w.allopreeningButton.state == .on && w.allopreeningButton.isEnabled
        w.tabs.selectTabViewItem(at:2)
        w.hoverDelayField.stringValue="0.25";w.detailFields[0][2].stringValue="1.25"
        w.sliders[0].doubleValue=35;w.sliderChanged(w.sliders[0]);w.locks[0].performClick(nil)
        set(w.chaseButton,to:false);set(w.travelTogetherButton,to:false)
        for child in [false,true] {
            configure(w,master:true,child:child)
            let before=try settingsData(w.draft)
            set(w.socialInteractionsButton,to:false)
            w.allopreeningButton.performClick(nil);w.relocalize()
            let suffix=child ? "on":"off"
            checks["allopreeningMasterRetainsDisabledPreference-"+suffix] = !w.allopreeningButton.isEnabled &&
                w.draft.allopreeningEnabled==child && w.allopreeningButton.state == (child ? .on:.off) &&
                w.previewAllopreeningButton.isEnabled
            set(w.socialInteractionsButton,to:true)
            let after=try settingsData(w.draft)
            checks["allopreeningMasterRestoresPreferenceWithoutOtherChanges-"+suffix] =
                w.allopreeningButton.isEnabled && before==after && d.settings.allopreeningEnabled
        }

        for (master,child) in [(false,true),(true,false),(false,false),(true,true)] {
            configure(w,master:master,child:child);w.save()
            let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
            let expected=try settingsData(w.draft),active=try settingsData(d.settings),stored=try settingsData(saved)
            let reloaded=isolatedDesktop(preferences:preferences,folder:evidence);try reloaded.loadSpeciesConfig()
            let restarted=try settingsData(reloaded.settings)
            checks["allopreeningSaveAndReload-master-\(master)-child-\(child)"] =
                saved.socialInteractions==master && saved.allopreeningEnabled==child &&
                w.allopreeningButton.isEnabled==master && expected==active && active==stored && stored==restarted &&
                saved.hoverDelay==0.25 && saved.catalog.species[0].speed==1.25 && saved.probabilities.entries[0].locked &&
                !saved.chaseEnabled && !saved.travelTogetherEnabled
        }
        configure(w,master:true,child:true)
        w.allopreeningButton.state = .off;w.save()
        let native=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["allopreeningSaveReadsNativeCheckboxAndApplies"] = !native.allopreeningEnabled &&
            !d.settings.allopreeningEnabled && !w.draft.allopreeningEnabled && native.socialInteractions &&
            w.message.stringValue==w.t("已保存 · 交互设置立即生效，鸟种参数用于新飞入的小鸟。","Saved · Interaction settings apply now; species settings affect new arrivals.")

        set(w.allopreeningButton,to:true)
        w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="1.5"
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let suffix=language == .chinese ? "zh":"en"
            checks["allopreeningLanguageRebuildKeepsDraftAndRawEdits-"+suffix] =
                w.draft.allopreeningEnabled && !d.settings.allopreeningEnabled &&
                w.allopreeningButton.state == .on && w.hoverDelayField.stringValue=="0.75" &&
                w.detailFields[0][2].stringValue=="1.5" && w.draft.probabilities.entries[0].locked
            for master in [true,false] {
                configure(w,master:master,child:true)
                try checkLayout(w,suffix:suffix+(master ? "-enabled":"-master-off"),folder:evidence,checks:&checks)
            }
            configure(w,master:true,child:true)
            checkRejection(w,reasons:[.disabled],suffix:"saved-child-off-"+suffix,checks:&checks)
            d.paused=true
            checkRejection(w,reasons:[.paused],suffix:"paused-"+suffix,checks:&checks)
            d.paused=false
        }
        let url=d.settingsURL,bytes=try Data(contentsOf:d.settingsURL),beforeFailure=try settingsData(d.settings)
        d.settingsURL=evidence;w.save();d.settingsURL=url
        let afterFailure=try settingsData(d.settings),afterBytes=try Data(contentsOf:url)
        checks["allopreeningFailedSaveKeepsActiveFileAndDraft"] = beforeFailure==afterFailure && bytes==afterBytes &&
            !d.settings.allopreeningEnabled && w.draft.allopreeningEnabled &&
            w.hoverDelayField.stringValue=="0.75" && w.detailFields[0][2].stringValue=="1.5" &&
            w.message.stringValue==w.t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.")
        w.hoverDelayField.stringValue="invalid";w.save()
        let invalidDelay=try settingsData(d.settings),invalidDelayBytes=try Data(contentsOf:url)
        checks["allopreeningInvalidDelayPreventsPartialApply"] = beforeFailure==invalidDelay && bytes==invalidDelayBytes &&
            w.draft.allopreeningEnabled && (w.tabs.selectedTabViewItem?.identifier as? String)=="interaction"
        w.hoverDelayField.stringValue="0.75"
        w.detailFields[0][2].stringValue="9";w.save()
        let afterInvalid=try settingsData(d.settings),invalidBytes=try Data(contentsOf:url)
        checks["allopreeningInvalidDetailsPreventPartialApply"] = beforeFailure==afterInvalid && bytes==invalidBytes &&
            w.draft.allopreeningEnabled && (w.tabs.selectedTabViewItem?.identifier as? String)=="behavior"
        w.detailFields[0][2].stringValue="1.5";w.save()
        let retry=try BirdSettings.load(from:url,legacyURL:d.legacyURL)
        checks["allopreeningRetrySavesRetainedDraft"] = retry.allopreeningEnabled && d.settings.allopreeningEnabled &&
            retry.hoverDelay==0.75 && retry.catalog.species[0].speed==1.5

        checkPreviewGates(w,checks:&checks)
        configure(w,master:true,child:false);w.save()
        let beforeReset=try Data(contentsOf:url)
        w.resetDefaults()
        let resetBytes=try Data(contentsOf:url)
        checks["allopreeningRestoreDefaultsOnlyEditsDraft"] = w.draft.allopreeningEnabled &&
            w.allopreeningButton.state == .on && w.allopreeningButton.isEnabled &&
            !d.settings.allopreeningEnabled && beforeReset==resetBytes
        w.cancel()
        let reset=SpeciesSettingsWindow(desktop:d);d.settingsWindow=reset;reset.showWindow(nil)
        defer {reset.cancel()}
        checks["allopreeningCancelledResetReopensSavedOff"] = !reset.draft.allopreeningEnabled &&
            reset.allopreeningButton.state == .off
        reset.resetDefaults();reset.save()
        let restored=try BirdSettings.load(from:url,legacyURL:d.legacyURL)
        checks["allopreeningDefaultsSaveAndApply"] = restored.allopreeningEnabled && restored.socialInteractions &&
            d.settings.allopreeningEnabled && d.settings.socialInteractions
        checks["allopreeningVerificationRemainsIsolated"] = d.timer==nil && d.status==nil &&
            d.globalMouseMonitor==nil && d.localMouseMonitor==nil && d.panels.isEmpty && d.views.isEmpty &&
            d.birds.isEmpty && !d.automaticPopulation && !d.engine.populationEnabled && !d.engine.ambientEnabled &&
            !d.engine.autonomousRouting && d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 &&
            !d.visitorMemoryPersistenceEnabled && d.visitorMemoryPersistence==nil &&
            !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path)
        checks["allopreeningVerificationCompleted"]=true
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
        set(w.socialInteractionsButton,to:true);set(w.allopreeningButton,to:child);set(w.socialInteractionsButton,to:master)
    }
    private static func checkRejection(_ w:SpeciesSettingsWindow,reasons:Set<BehaviorReason>,suffix:String,
                                       checks:inout [String:Bool]) {
        let e=w.desktop.engine,sequence=e.events.last?.sequence
        let birds=e.birds,positions=birds.map(\.position),states=birds.map(\.state),revisions=birds.map(\.motionRevision)
        let counts=[e.birds.count,e.residentCount,e.passingCount,e.departingCount,e.pendingCount,e.arrivalCount,e.departureCount]
        let runs=e.activeRunCount,leases=e.leasedBirdCount,slots=e.reservedLandingCount
        w.previewAllopreeningButton.performClick(nil)
        let event=e.events.last
        checks["allopreeningPreviewRejection-"+suffix] = event?.sequence != sequence && event?.kind == .allopreening &&
            event?.source == .preview && event?.type == .rejected && event?.reason.map {reason in
                reasons.contains(reason) && w.message.stringValue==w.allopreeningPreviewMessage(reason)
            } == true
        checks["allopreeningRejectedPreviewPreservesBirdsAndMotion-"+suffix] =
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
            checks["allopreeningPreviewUsesSavedEnabledSwitches-"+suffix] = d.settings.allopreeningEnabled &&
                d.settings.socialInteractions && !w.draft.allopreeningEnabled && !w.draft.socialInteractions
            configure(w,master:false,child:true);w.save();set(w.socialInteractionsButton,to:true)
            checkRejection(w,reasons:[.disabled],suffix:"saved-master-off-"+suffix,checks:&checks)
            w.activityRhythmPopup.selectItem(at:ActivityRhythmMode.allCases.firstIndex(of:.quiet)!)
            w.activityRhythmSettingsChanged();w.save()
            checkRejection(w,reasons:[.noCompanion,.noSpecies,.unavailableBird,.missingBird],
                           suffix:"quiet-manual-empty-"+suffix,checks:&checks)
            checks["allopreeningQuietAllowsManualPreviewThroughSavedGates-"+suffix] =
                d.settings.activityRhythm == .quiet && d.engine.events.last?.reason != .disabled
            checks["allopreeningSameSpeciesWindowCandidateMessage-"+suffix] = w.allopreeningPreviewMessage(.noCompanion)==w.t(
                "请等待两只家燕或两只暗绿绣眼鸟在同一窗口相邻停稳，并把鼠标移远。",
                "Let two Barn Swallows or two Swinhoe’s White-eyes settle together on one window; move the pointer away.")
            checks["allopreeningAllMessagesFit-"+suffix] =
                [BehaviorReason.noSpecies,.noCompanion,.missingBird,.unavailableBird,.noSpace,.disabled,.settingsChanged,.paused,.busy,.missingFrames,.pointerNearby,.userInput].allSatisfy {reason in
                    w.message.stringValue=w.allopreeningPreviewMessage(reason)
                    return (w.message.cell?.cellSize(forBounds:w.message.bounds).height ?? .infinity)<=w.message.frame.height
                }
            // Unsupported pairs and different supported species must stay untouched.
            let host=Surface(id:956,rect:CGRect(x:100,y:600,width:1000,height:180))
            d.surfaces=[host]
            for species:[SpeciesID] in [[.treeSparrow,.treeSparrow],[.barnSwallow,.swinhoesWhiteEye]] {
                let birds=species.enumerated().map {index,id -> Bird in
                    let bird=Bird(position:.zero,fraction:CGFloat(0.4+Double(index)*0.2),profile:d.catalog.profile(id),random:{0.5})
                    bird.perch(on:host);bird.perchDuration=600
                    return bird
                }
                d.engine.installFixtureBirds(birds)
                let candidate=species[0] == .treeSparrow ? "unsupported-pair-":"mixed-species-"
                checkRejection(w,reasons:[.noCompanion,.noSpecies,.unavailableBird,.missingBird],
                               suffix:candidate+suffix,checks:&checks)
                checks["allopreeningInvalidPairStaysPerched-"+candidate+suffix] =
                    birds.allSatisfy{$0.state == .perched && d.engine.behavior(of:$0)==nil}
                d.birds=[]
            }
            d.surfaces=[]
        }
    }

    private static func checkLayout(_ w:SpeciesSettingsWindow,suffix:String,folder:URL,checks:inout [String:Bool]) throws {
        let prefix="allopreeningLayout-"+suffix
        checks[prefix+"SectionPresent"]=false
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return}
        func label(_ id:String) -> NSTextField? {
            document.subviews.compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue==id}
        }
        guard let heading=label("allopreeningSectionTitle"),let help=label("allopreeningHelp"),
              let previewHelp=label("allopreeningPreviewHelp") else {return}
        checks[prefix+"SectionPresent"]=true
        let limit=max(0,document.bounds.height-scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:CGPoint(x:0,y:min(max(0,heading.frame.minY-12),limit)))
        scroll.reflectScrolledClipView(scroll.contentView);w.window?.contentView?.layoutSubtreeIfNeeded()
        let views:[NSView]=[heading,w.allopreeningButton,help,w.previewAllopreeningButton,previewHelp]
        checks[prefix+"Labels"] = heading.stringValue==w.t("同伴理羽","Companion preening") &&
            w.allopreeningButton.title==heading.stringValue &&
            w.allopreeningButton.accessibilityLabel()==w.allopreeningButton.title &&
            w.previewAllopreeningButton.title==w.t("预览同伴理羽","Preview companion preening") &&
            w.allopreeningButton.identifier?.rawValue=="allopreeningEnabled" &&
            w.previewAllopreeningButton.identifier?.rawValue=="previewAllopreening"
        let expected:Set<SpeciesID>=[.barnSwallow,.swinhoesWhiteEye]
        checks[prefix+"SpeciesNames"] = expected.allSatisfy{help.stringValue.contains(w.language.name($0))}
        checks[prefix+"ExistingCoordinates"] = w.hoverDelaySlider.frame.minY==122 && w.pointerVisitsButton.frame.minY==310 &&
            w.socialInteractionsButton.frame.minY==418 && w.perchActionsButton.frame.minY==916 &&
            w.sideHopButton.frame.minY==1322 && label("leafSectionTitle")?.frame.minY==1600 &&
            w.visitorMemoryButton.frame.minY==2002 && w.activityRhythmPopup.frame.minY==2222 &&
            w.edgePeekButton.frame.minY==2582 && w.chaseButton.frame.minY==2992 &&
            w.previewChaseButton.frame.minY==3180 && label("chasePreviewHelp")?.frame.maxY==3330 &&
            label("travelTogetherSectionTitle")?.frame.minY==3380 && w.travelTogetherButton.frame.minY==3422 &&
            w.previewTravelTogetherButton.frame.minY==3610 && label("travelTogetherPreviewHelp")?.frame.maxY==3760 &&
            heading.frame.minY>3760
        checks[prefix+"Reachable"] = views.allSatisfy{!$0.isHidden && document.visibleRect.contains($0.frame)} &&
            w.allopreeningButton.isEnabled==w.draft.socialInteractions && w.previewAllopreeningButton.isEnabled
        checks[prefix+"TitlesAndHelpFit"] = [w.allopreeningButton!,w.previewAllopreeningButton!].allSatisfy {
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
        try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("allopreening-settings-"+suffix+".png"))
    }
}
