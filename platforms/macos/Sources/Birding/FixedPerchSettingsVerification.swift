import AppKit
import BirdingCore

/// Isolated native controls and persistence coverage. The one-shot placement
/// timer is installed through the production button, then sampled deterministically.
/// No application startup, desktop animation timer or user configuration writer.
enum FixedPerchSettingsVerification {
    private static let displays=[CGRect(x:0,y:0,width:1440,height:900),
                                 CGRect(x:-1280,y:-200,width:1280,height:1024)]
    private static let displayIDs=["verification-main","verification-left"]

    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("fixed-perch-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        checks["fixedPerchVerificationCompleted"]=false
        defer {
            let own=checks.filter{$0.key.hasPrefix("fixedPerch")}
            saveJSON(["passed":!own.isEmpty && own.values.allSatisfy{$0},"checks":own],
                     to:evidence.appendingPathComponent("report.json"))
        }
        let suite="Birding.FixedPerchSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {
            throw NSError(domain:"FixedPerchSettingsVerification",code:1)
        }
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=isolatedDesktop(preferences:preferences,folder:evidence)
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["fixedPerchDefaultsOnAndEmptyWithoutWriting"] = defaults.fixedPerchesEnabled &&
            defaults.fixedPerches.isEmpty && !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let cancelled=SpeciesSettingsWindow(desktop:d);cancelled.showWindow(nil)
        capture(cancelled,slot:2,point:CGPoint(x:-960,y:56),suffix:"cancelled-draft",checks:&checks)
        checks["fixedPerchCaptureOnlyChangesDraft"] = cancelled.draft.fixedPerches.count==1 &&
            d.settings.fixedPerches.isEmpty && d.engine.fixedPerchSnapshot().isEmpty &&
            !FileManager.default.fileExists(atPath:d.settingsURL.path)
        try checkCancellation(cancelled,suffix:"cancel",checks:&checks) {cancelled.cancel()}
        checks["fixedPerchCancelDoesNotApplyOrWrite"] = cancelled.window?.isVisible == false &&
            d.settings.fixedPerches.isEmpty && !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let closed=SpeciesSettingsWindow(desktop:d);closed.showWindow(nil)
        try checkCancellation(closed,suffix:"window-close",checks:&checks) {closed.window?.performClose(nil)}
        checks["fixedPerchWindowCloseDoesNotWrite"] = closed.window?.isVisible == false &&
            !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel()}
        w.tabs.selectTabViewItem(at:2)
        checks["fixedPerchReopenDiscardsCancelledDraft"] = w.draft.fixedPerches.isEmpty &&
            w.fixedPerchesButton.state == .on && w.fixedPerchSlotPopup.numberOfItems==3 &&
            w.placeFixedPerchButton.isEnabled && !w.removeFixedPerchButton.isEnabled
        capture(w,slot:1,point:CGPoint(x:360,y:225),suffix:"slot-1",checks:&checks)
        capture(w,slot:2,point:CGPoint(x:-960,y:56),suffix:"negative-display",checks:&checks)
        let left=w.draft.fixedPerches.first{$0.slot==2}
        checks["fixedPerchCaptureUsesContainingDisplayAndNormalizedCoordinates"] =
            left?.displayID==displayIDs[1] && left?.displayFrame==displays[1] && left?.x==0.25 && left?.y==0.25 &&
            w.fixedPerchStatus.stringValue.contains("25.0%")
        capture(w,slot:3,point:CGPoint(x:1080,y:675),suffix:"slot-3",checks:&checks)
        let allAnchors=w.draft.fixedPerches
        checks["fixedPerchHasExactlyThreeIndependentSlots"] = allAnchors.map(\.slot)==[1,2,3] &&
            w.fixedPerchSlotPopup.itemTitles.allSatisfy{$0.contains(w.t("已放置","Placed"))}
        let beforeMove=w.draft.fixedPerches
        capture(w,slot:2,point:CGPoint(x:-640,y:312),suffix:"move-slot-2",checks:&checks)
        checks["fixedPerchMoveReplacesOnlySelectedSlot"] = w.draft.fixedPerches.count==3 &&
            w.draft.fixedPerches.first{$0.slot==2}?.x==0.5 &&
            w.draft.fixedPerches.filter{$0.slot != 2}==beforeMove.filter{$0.slot != 2}
        let beforeInvalid=w.draft.fixedPerches
        capture(w,slot:2,point:CGPoint(x:5000,y:5000),suffix:"outside-display",checks:&checks)
        checks["fixedPerchInvalidCaptureKeepsDraft"] = beforeInvalid==w.draft.fixedPerches &&
            w.message.stringValue==w.t("鼠标不在可用屏幕内，草稿未改变，请重试。",
                                       "Pointer is outside available displays. Draft unchanged; try again.")

        // Fixed perches have their own master, independent of existing parent switches.
        set(w.perchActionsButton,to:false);set(w.socialInteractionsButton,to:false)
        checks["fixedPerchIndependentOfPerchAndSocialParents"] = w.placeFixedPerchButton.isEnabled &&
            w.removeFixedPerchButton.isEnabled && w.draft.fixedPerchesEnabled
        set(w.fixedPerchesButton,to:false)
        w.placeFixedPerchButton.performClick(nil);w.removeFixedPerchButton.performClick(nil)
        checks["fixedPerchDisabledChildrenCannotLoseAnchors"] = !w.draft.fixedPerchesEnabled &&
            w.draft.fixedPerches==beforeInvalid && !w.placeFixedPerchButton.isEnabled &&
            !w.removeFixedPerchButton.isEnabled && w.fixedPerchCaptureTimer==nil && w.previewFixedPerchButton.isEnabled
        w.relocalize()
        checks["fixedPerchRebuildRetainsDisabledAnchors"] = !w.draft.fixedPerchesEnabled &&
            w.draft.fixedPerches==beforeInvalid && w.selectedFixedPerchSlot==2
        set(w.fixedPerchesButton,to:true)
        checks["fixedPerchReenableRestoresChildren"] = w.placeFixedPerchButton.isEnabled &&
            w.removeFixedPerchButton.isEnabled && w.draft.fixedPerches==beforeInvalid
        try checkCancellation(w,suffix:"master-off",checks:&checks) {set(w.fixedPerchesButton,to:false)}
        set(w.fixedPerchesButton,to:true)
        try checkCancellation(w,suffix:"slot-change",checks:&checks) {select(w,slot:3)}
        try checkCancellation(w,suffix:"build",checks:&checks) {w.build()}
        w.placeFixedPerchButton.performClick(nil)
        let oldRequest=w.fixedPerchCaptureRequest,oldTimer=w.fixedPerchCaptureTimer
        w.cancelFixedPerchCapture();w.placeFixedPerchButton.performClick(nil)
        let currentRequest=w.fixedPerchCaptureRequest
        if let oldRequest {
            w.captureFixedPerch(request:oldRequest,point:CGPoint(x:720,y:450),displayIDs:displayIDs,displays:displays)
        }
        checks["fixedPerchStaleRequestCannotReplaceNewCapture"] = oldRequest != nil && currentRequest != nil &&
            oldRequest != currentRequest && w.fixedPerchCaptureRequest==currentRequest &&
            oldTimer?.isValid==false && w.fixedPerchCaptureTimer?.isValid==true && w.draft.fixedPerches==beforeInvalid
        w.cancelFixedPerchCapture()

        w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="1.5"
        w.manualAdjustmentButton.performClick(nil)
        for language:AppLanguage in [.chinese,.english] {
            d.language=language
            let suffix=language == .chinese ? "zh":"en"
            try checkCancellation(w,suffix:"relocalize-"+suffix,checks:&checks) {w.relocalize()}
            checks["fixedPerchLanguageRebuildPreservesRawEdits-"+suffix] = w.hoverDelayField.stringValue=="0.75" &&
                w.detailFields[0][2].stringValue=="1.5" && w.draft.probabilities.manualAdjustmentEnabled &&
                w.draft.fixedPerches==beforeInvalid && w.selectedFixedPerchSlot==3
            try checkLayout(w,suffix:suffix+"-placed",folder:evidence,checks:&checks)
            set(w.fixedPerchesButton,to:false)
            try checkLayout(w,suffix:suffix+"-disabled",folder:evidence,checks:&checks)
            set(w.fixedPerchesButton,to:true)
            checkRejection(w,reasons:nil,suffix:"unsaved-"+suffix,checks:&checks)
            checks["fixedPerchPreviewExplainsMissingSavedAnchor-"+suffix] =
                w.message.stringValue==w.fixedPerchPreviewMessage(.targetInvalid) && d.settings.fixedPerches.isEmpty
        }

        try checkCancellation(w,suffix:"save",checks:&checks) {w.save()}
        let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        let reloaded=isolatedDesktop(preferences:preferences,folder:evidence);try reloaded.loadSpeciesConfig()
        checks["fixedPerchSaveAppliesAndReloadsAllAnchors"] = saved.fixedPerches==beforeInvalid &&
            d.settings.fixedPerches==saved.fixedPerches && reloaded.settings.fixedPerches==saved.fixedPerches &&
            saved.fixedPerchesEnabled && saved.hoverDelay==0.75 && saved.catalog.species[0].speed==1.5 &&
            saved.probabilities.manualAdjustmentEnabled && !saved.perchActions && !saved.socialInteractions
        w.fixedPerchesButton.state = .off;w.save()
        let native=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["fixedPerchSaveReadsNativeCheckboxWithoutLosingPositions"] = !native.fixedPerchesEnabled &&
            !d.settings.fixedPerchesEnabled && native.fixedPerches==beforeInvalid &&
            w.draft.fixedPerches==beforeInvalid && !w.placeFixedPerchButton.isEnabled
        set(w.fixedPerchesButton,to:true);w.save()

        select(w,slot:2)
        try checkCancellation(w,suffix:"remove",checks:&checks) {w.removeFixedPerchButton.performClick(nil)}
        let removed=w.draft.fixedPerches
        checks["fixedPerchRemoveOnlyChangesSelectedDraftSlot"] = removed.map(\.slot)==[1,3] &&
            d.settings.fixedPerches==beforeInvalid && !w.removeFixedPerchButton.isEnabled &&
            w.fixedPerchSlotPopup.titleOfSelectedItem?.contains(w.t("未放置","Not placed"))==true
        let bytes=try Data(contentsOf:d.settingsURL),active=try settingsData(d.settings)
        let url=d.settingsURL;d.settingsURL=evidence
        defer {d.settingsURL=url}
        try checkCancellation(w,suffix:"failed-save",checks:&checks) {w.save()}
        d.settingsURL=url
        let afterFailure=try settingsData(d.settings),afterBytes=try Data(contentsOf:url)
        checks["fixedPerchFailedSaveRetainsDraftAndActiveFile"] = active==afterFailure && bytes==afterBytes &&
            w.draft.fixedPerches==removed && w.message.stringValue==w.t(
                "保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.")
        w.hoverDelayField.stringValue="invalid"
        try checkCancellation(w,suffix:"invalid-save",checks:&checks) {w.save()}
        let invalidActive=try settingsData(d.settings),invalidBytes=try Data(contentsOf:url)
        checks["fixedPerchInvalidSaveHasNoPartialApply"] = active==invalidActive && bytes==invalidBytes &&
            w.draft.fixedPerches==removed && (w.tabs.selectedTabViewItem?.identifier as? String)=="interaction"
        w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="9";w.save()
        let invalidDetailsActive=try settingsData(d.settings),invalidDetailsBytes=try Data(contentsOf:url)
        checks["fixedPerchInvalidDetailsHaveNoPartialApply"] = active==invalidDetailsActive &&
            bytes==invalidDetailsBytes && w.draft.fixedPerches==removed &&
            (w.tabs.selectedTabViewItem?.identifier as? String)=="behavior"
        w.detailFields[0][2].stringValue="1.5";w.save()
        let retried=try BirdSettings.load(from:url,legacyURL:d.legacyURL)
        checks["fixedPerchRetrySavesRetainedRemoval"] = retried.fixedPerches==removed && d.settings.fixedPerches==removed

        try checkPreviewGates(w,checks:&checks)
        let beforeReset=try Data(contentsOf:url),savedBeforeReset=d.settings.fixedPerches
        try checkCancellation(w,suffix:"reset",checks:&checks) {w.resetDefaults()}
        let resetBytes=try Data(contentsOf:url)
        checks["fixedPerchDefaultsOnlyEditDraft"] = w.draft.fixedPerchesEnabled && w.draft.fixedPerches.isEmpty &&
            w.fixedPerchesButton.state == .on && w.fixedPerchSlotPopup.indexOfSelectedItem==0 &&
            d.settings.fixedPerches==savedBeforeReset && beforeReset==resetBytes
        w.cancel()
        let reset=SpeciesSettingsWindow(desktop:d);d.settingsWindow=reset;reset.showWindow(nil)
        defer {reset.cancel()}
        checks["fixedPerchCancelledDefaultsReopenSavedAnchors"] = reset.draft.fixedPerches==savedBeforeReset &&
            reset.draft.fixedPerchesEnabled==d.settings.fixedPerchesEnabled
        reset.resetDefaults();reset.save()
        let restored=try BirdSettings.load(from:url,legacyURL:d.legacyURL)
        checks["fixedPerchDefaultsSaveAndApply"] = restored.fixedPerchesEnabled && restored.fixedPerches.isEmpty &&
            d.settings.fixedPerchesEnabled && d.settings.fixedPerches.isEmpty
        checks["fixedPerchVerificationRemainsIsolated"] = d.timer==nil && d.status==nil &&
            d.globalMouseMonitor==nil && d.localMouseMonitor==nil && d.panels.isEmpty && d.views.isEmpty &&
            d.birds.isEmpty && !d.automaticPopulation && !d.engine.populationEnabled && !d.engine.ambientEnabled &&
            !d.engine.autonomousRouting && d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 &&
            !d.visitorMemoryPersistenceEnabled && d.visitorMemoryPersistence==nil &&
            !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path) &&
            w.fixedPerchCaptureTimer==nil && reset.fixedPerchCaptureTimer==nil
        checks["fixedPerchVerificationCompleted"]=true
    }

    private static func isolatedDesktop(preferences:UserDefaults,folder:URL) -> DesktopController {
        let d=DesktopController();d.preferences=preferences;d.automaticPopulation=false
        // Control fixtures assume released buttons; exercise the pressed gate explicitly below.
        d.pointerButtonsDown={false}
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
        d.visitorMemoryPersistenceEnabled=false;d.visitorMemoryURL=folder.appendingPathComponent("visitors.json")
        return d
    }
    private static func settingsData(_ settings:BirdSettings) throws -> Data {
        let value=settings
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
    private static func set(_ button:NSButton,to enabled:Bool) {
        if (button.state == .on) != enabled {button.performClick(nil)}
    }
    private static func select(_ w:SpeciesSettingsWindow,slot:Int) {
        w.fixedPerchSlotPopup.selectItem(at:slot-1)
        if let action=w.fixedPerchSlotPopup.action {
            NSApp.sendAction(action,to:w.fixedPerchSlotPopup.target,from:w.fixedPerchSlotPopup)
        }
    }
    private static func capture(_ w:SpeciesSettingsWindow,slot:Int,point:CGPoint,suffix:String,
                                checks:inout [String:Bool]) {
        let saved=w.desktop.settings.fixedPerches,snapshot=w.desktop.engine.fixedPerchSnapshot()
        let sequence=w.desktop.engine.events.last?.sequence
        select(w,slot:slot)
        let actionStarted=Date()
        w.placeFixedPerchButton.performClick(nil)
        let actionReturned=Date()
        let timer=w.fixedPerchCaptureTimer,request=w.fixedPerchCaptureRequest
        // AppKit may animate/drain events before performClick returns. Verify
        // the three-second schedule against its creation window, not a maximum
        // 0.5-second button-dispatch latency on this machine.
        let deadline=timer?.fireDate.timeIntervalSinceNow ?? -1
        let scheduledInAction=timer.map {
            $0.fireDate>=actionStarted.addingTimeInterval(2.95) &&
            $0.fireDate<=actionReturned.addingTimeInterval(3.05)
        } ?? false
        checks["fixedPerchProductionButtonInstallsOneShotTimer-"+suffix] = timer?.isValid==true &&
            timer?.timeInterval==0 && scheduledInAction && request != nil && !w.placeFixedPerchButton.isEnabled &&
            w.selectedFixedPerchSlot==slot
        if checks["fixedPerchProductionButtonInstallsOneShotTimer-"+suffix] == false {
            print("Fixed perch timer diagnostic: \(suffix), valid=\(timer?.isValid ?? false), interval=\(timer?.timeInterval ?? -1), remaining=\(deadline), request=\(request != nil), enabled=\(w.placeFixedPerchButton.isEnabled), slot=\(w.selectedFixedPerchSlot)")
        }
        if let request {w.captureFixedPerch(request:request,point:point,displayIDs:displayIDs,displays:displays)}
        checks["fixedPerchSamplingClearsTimer-"+suffix] = timer?.isValid==false &&
            w.fixedPerchCaptureTimer==nil && w.fixedPerchCaptureRequest==nil && w.placeFixedPerchButton.isEnabled
        checks["fixedPerchSamplingNeverTouchesEngine-"+suffix] = w.desktop.settings.fixedPerches==saved &&
            w.desktop.engine.fixedPerchSnapshot().map(\.surface)==snapshot.map(\.surface) &&
            w.desktop.engine.events.last?.sequence==sequence
    }
    private static func checkCancellation(_ w:SpeciesSettingsWindow,suffix:String,checks:inout [String:Bool],
                                          action:() -> Void) throws {
        w.placeFixedPerchButton.performClick(nil)
        let timer=w.fixedPerchCaptureTimer,request=w.fixedPerchCaptureRequest
        checks["fixedPerchCancellationArmsProductionTimer-"+suffix] = timer?.isValid==true && request != nil
        action()
        let after=try settingsData(w.draft),message=w.message.stringValue
        timer?.fire()
        if let request {w.captureFixedPerch(request:request,point:CGPoint(x:720,y:450),displayIDs:displayIDs,displays:displays)}
        let stale=try settingsData(w.draft)
        checks["fixedPerchPendingCaptureCancelled-"+suffix] = timer?.isValid==false &&
            w.fixedPerchCaptureTimer==nil && w.fixedPerchCaptureRequest==nil && after==stale &&
            w.message.stringValue==message
    }
    private static func checkRejection(_ w:SpeciesSettingsWindow,reasons:Set<BehaviorReason>?,suffix:String,
                                       checks:inout [String:Bool]) {
        let e=w.desktop.engine,sequence=e.events.last?.sequence
        let birds=e.birds,positions=birds.map(\.position),states=birds.map(\.state),revisions=birds.map(\.motionRevision)
        let counts=[e.birds.count,e.residentCount,e.passingCount,e.departingCount,e.pendingCount,e.arrivalCount,e.departureCount]
        let runs=e.activeRunCount,leases=e.leasedBirdCount,slots=e.reservedLandingCount
        w.previewFixedPerchButton.performClick(nil)
        let event=e.events.last
        checks["fixedPerchPreviewRejection-"+suffix] = event?.sequence != sequence && event?.kind == .fixedPerchVisit &&
            event?.source == .preview && event?.type == .rejected && event?.reason.map {reason in
                (reasons?.contains(reason) ?? true) && w.message.stringValue==w.fixedPerchPreviewMessage(reason)
            } == true
        checks["fixedPerchRejectedPreviewPreservesBirdsAndMotion-"+suffix] =
            counts==[e.birds.count,e.residentCount,e.passingCount,e.departingCount,e.pendingCount,e.arrivalCount,e.departureCount] &&
            zip(birds,e.birds).allSatisfy{$0.0 === $0.1} && e.birds.map(\.position)==positions &&
            e.birds.map(\.state)==states && e.birds.map(\.motionRevision)==revisions &&
            e.activeRunCount==runs && e.leasedBirdCount==leases && e.reservedLandingCount==slots
    }
    private static func checkPreviewGates(_ w:SpeciesSettingsWindow,checks:inout [String:Bool]) throws {
        let d=w.desktop
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let suffix=language == .chinese ? "zh":"en"
            set(w.fixedPerchesButton,to:false);w.save();set(w.fixedPerchesButton,to:true)
            checkRejection(w,reasons:[.disabled],suffix:"saved-off-"+suffix,checks:&checks)
            checks["fixedPerchPreviewUsesSavedDisabledSwitch-"+suffix] = !d.settings.fixedPerchesEnabled &&
                w.draft.fixedPerchesEnabled && !d.settings.fixedPerches.isEmpty
            w.save();select(w,slot:1);w.removeFixedPerchButton.performClick(nil);set(w.fixedPerchesButton,to:false)
            d.pointerButtonsDown={true}
            checkRejection(w,reasons:[.userInput],suffix:"physical-button-down-"+suffix,checks:&checks)
            d.pointerButtonsDown={false}
            checkRejection(w,reasons:[.noSpecies,.missingBird,.unavailableBird,.noCompanion,.noSpace],
                           suffix:"saved-on-empty-birds-"+suffix,checks:&checks)
            checks["fixedPerchPreviewUsesSavedPositionsAndEnabledSwitch-"+suffix] =
                d.settings.fixedPerchesEnabled && !w.draft.fixedPerchesEnabled &&
                d.settings.fixedPerches.count>w.draft.fixedPerches.count
            set(w.fixedPerchesButton,to:true)
            // Restore the saved anchors after exercising draft-only removal.
            w.draft.fixedPerches=d.settings.fixedPerches;w.relocalize()
            d.paused=true
            checkRejection(w,reasons:[.paused],suffix:"paused-"+suffix,checks:&checks)
            d.paused=false
            w.activityRhythmPopup.selectItem(at:ActivityRhythmMode.allCases.firstIndex(of:.quiet)!)
            w.activityRhythmSettingsChanged();w.save()
            checkRejection(w,reasons:[.noSpecies,.missingBird,.unavailableBird,.noCompanion,.noSpace],
                           suffix:"quiet-manual-"+suffix,checks:&checks)
            checks["fixedPerchQuietAllowsManualPreviewThroughSavedGates-"+suffix] =
                d.settings.activityRhythm == .quiet && d.engine.events.last?.reason != .disabled
            let host=Surface(id:958,rect:CGRect(x:100,y:600,width:1000,height:180))
            let unsupported=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.chineseBlackbird),random:{0.5})
            unsupported.perch(on:host);unsupported.perchDuration=600
            d.surfaces=[host];d.birds=[unsupported]
            checkRejection(w,reasons:[.noSpecies,.noSpace],suffix:"unsupported-species-"+suffix,checks:&checks)
            checks["fixedPerchUnsupportedBirdStaysPerched-"+suffix] =
                unsupported.state == .perched && d.engine.behavior(of:unsupported)==nil
            d.birds=[];d.surfaces=[]
            checks["fixedPerchPreviewMessagesFit-"+suffix] =
                [BehaviorReason.noSpecies,.missingBird,.unavailableBird,.noSpace,.disabled,.settingsChanged,
                 .paused,.busy,.missingFrames,.pointerNearby,.targetInvalid].allSatisfy {reason in
                    w.message.stringValue=w.fixedPerchPreviewMessage(reason)
                    return (w.message.cell?.cellSize(forBounds:w.message.bounds).height ?? .infinity)<=w.message.frame.height
                }
        }
    }
    private static func checkLayout(_ w:SpeciesSettingsWindow,suffix:String,folder:URL,
                                    checks:inout [String:Bool]) throws {
        let prefix="fixedPerchLayout-"+suffix
        checks[prefix+"SectionPresent"]=false
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return}
        func label(_ id:String) -> NSTextField? {
            document.subviews.compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue==id}
        }
        guard let heading=label("fixedPerchSectionTitle"),let help=label("fixedPerchHelp"),
              let slotLabel=label("fixedPerchSlotLabel") else {return}
        checks[prefix+"SectionPresent"]=true
        let limit=max(0,document.bounds.height-scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:CGPoint(x:0,y:min(max(0,heading.frame.minY-8),limit)))
        scroll.reflectScrolledClipView(scroll.contentView);w.window?.contentView?.layoutSubtreeIfNeeded()
        let views:[NSView]=[heading,w.fixedPerchesButton,slotLabel,w.fixedPerchSlotPopup,w.fixedPerchStatus,
                            w.placeFixedPerchButton,w.removeFixedPerchButton,w.previewFixedPerchButton,help]
        checks[prefix+"Labels"] = heading.stringValue==w.t("固定小栖木","Fixed perches") &&
            w.fixedPerchesButton.title==w.t("启用固定小栖木","Enable fixed perches") &&
            w.previewFixedPerchButton.title==w.t("预览访问","Preview visit") &&
            w.removeFixedPerchButton.title==w.t("移除该栖木","Remove this perch") &&
            w.fixedPerchSlotPopup.numberOfItems==3 && w.fixedPerchesButton.accessibilityLabel()==w.fixedPerchesButton.title
        checks[prefix+"SpeciesNames"] = FixedPerchVisitBehavior.supportedSpecies.allSatisfy {
            help.stringValue.contains(w.language.name($0))
        }
        checks[prefix+"ExistingCoordinates"] = w.hoverDelaySlider.frame.minY==122 &&
            w.perchActionsButton.frame.minY==916 && w.allopreeningButton.frame.minY==3852 &&
            label("allopreeningPreviewHelp")?.frame.maxY==4150 && heading.frame.minY>4150
        checks[prefix+"Reachable"] = views.allSatisfy{!$0.isHidden && document.visibleRect.contains($0.frame)} &&
            w.placeFixedPerchButton.isEnabled==w.draft.fixedPerchesEnabled &&
            w.removeFixedPerchButton.isEnabled==w.draft.fixedPerchesEnabled && w.previewFixedPerchButton.isEnabled
        checks[prefix+"TextFits"] = [w.fixedPerchesButton!,w.placeFixedPerchButton!,w.removeFixedPerchButton!,w.previewFixedPerchButton!].allSatisfy {
            $0.intrinsicContentSize.width<=$0.frame.width && $0.intrinsicContentSize.height<=$0.frame.height
        } && [heading,slotLabel,w.fixedPerchStatus!,help].allSatisfy {
            ($0.cell?.cellSize(forBounds:$0.bounds).height ?? .infinity)<=$0.frame.height
        }
        checks[prefix+"NoOverlap"] = document.subviews.enumerated().allSatisfy {index,view in
            document.bounds.contains(view.frame) && document.subviews.dropFirst(index+1).allSatisfy{!view.frame.intersects($0.frame)}
        }
        let actions:Set<Selector>=[#selector(SpeciesSettingsWindow.resetDefaults),#selector(SpeciesSettingsWindow.cancel),#selector(SpeciesSettingsWindow.save)]
        let footer=w.window?.contentView?.subviews.compactMap{$0 as? NSButton}.filter {
            $0.action.map{actions.contains($0)} ?? false
        } ?? []
        checks[prefix+"FooterVisible"] = footer.count==3 && footer.allSatisfy {
            !$0.isHidden && $0.isEnabled && $0.superview?.bounds.contains($0.frame)==true &&
                $0.intrinsicContentSize.width<=$0.frame.width
        } && w.message.superview?.bounds.contains(w.message.frame)==true
        try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("fixed-perch-settings-"+suffix+".png"))
    }
}
