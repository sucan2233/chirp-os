import AppKit
import BirdingCore

/// Drives real AppKit controls against isolated preferences and settings files.
enum PassiveMotionSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("passive-motion-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        let suite="Birding.PassiveMotionSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {
            throw NSError(domain:"PassiveMotionSettingsVerification",code:1)
        }
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=DesktopController();d.preferences=preferences;d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.settingsURL=evidence.appendingPathComponent("settings.json")
        d.legacyURL=evidence.appendingPathComponent("legacy.json")
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["passiveMotionDefaultsOnWithoutCreatingConfig"]=defaults.perchActions && defaults.sideHopEnabled &&
            defaults.takeoffPreparationEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let cancelled=SpeciesSettingsWindow(desktop:d)
        cancelled.showWindow(nil)
        cancelled.sideHopButton.performClick(nil);cancelled.takeoffPreparationButton.performClick(nil)
        cancelled.cancel()
        checks["passiveMotionCancelDiscardsBothEdits"] = !cancelled.draft.sideHopEnabled &&
            !cancelled.draft.takeoffPreparationEnabled && cancelled.window?.isVisible == false &&
            d.settings.sideHopEnabled && d.settings.takeoffPreparationEnabled &&
            !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel()}
        checks["passiveMotionReopenRestoresSavedDefaults"]=w !== cancelled && w.draft.sideHopEnabled &&
            w.draft.takeoffPreparationEnabled && w.sideHopButton.state == .on && w.takeoffPreparationButton.state == .on &&
            w.sideHopButton.isEnabled && w.takeoffPreparationButton.isEnabled
        // Both saved values remain true while each independent child is edited.
        for enabled in [false,true] {
            let other=w.draft.takeoffPreparationEnabled
            set(w.sideHopButton,to:enabled)
            checks["passiveMotionSideHopOnlyEditsDraft-\(enabled)"]=w.draft.sideHopEnabled==enabled &&
                w.draft.takeoffPreparationEnabled==other && d.settings.sideHopEnabled && d.settings.takeoffPreparationEnabled
            set(w.takeoffPreparationButton,to:enabled)
            checks["passiveMotionPreparationOnlyEditsDraft-\(enabled)"]=w.draft.takeoffPreparationEnabled==enabled &&
                w.draft.sideHopEnabled==enabled && d.settings.sideHopEnabled && d.settings.takeoffPreparationEnabled
            set(w.perchActionsButton,to:false)
            checks["passiveMotionMasterDisablesWithoutClearingChildren-\(enabled)"] = !w.draft.perchActions &&
                !w.sideHopButton.isEnabled && !w.takeoffPreparationButton.isEnabled &&
                w.draft.sideHopEnabled==enabled && w.draft.takeoffPreparationEnabled==enabled &&
                w.sideHopButton.state == (enabled ? .on:.off) && w.takeoffPreparationButton.state == (enabled ? .on:.off)
            w.sideHopButton.performClick(nil);w.takeoffPreparationButton.performClick(nil);w.relocalize()
            checks["passiveMotionDisabledChildrenSurviveClicksAndRebuild-\(enabled)"] = !w.sideHopButton.isEnabled &&
                !w.takeoffPreparationButton.isEnabled && w.draft.sideHopEnabled==enabled &&
                w.draft.takeoffPreparationEnabled==enabled && w.sideHopButton.state == (enabled ? .on:.off) &&
                w.takeoffPreparationButton.state == (enabled ? .on:.off)
            set(w.perchActionsButton,to:true)
            checks["passiveMotionMasterRestoresChildState-\(enabled)"]=w.sideHopButton.isEnabled &&
                w.takeoffPreparationButton.isEnabled && w.draft.sideHopEnabled==enabled && w.draft.takeoffPreparationEnabled==enabled
        }

        // Exercise every independent preference combination through Save and a
        // fresh controller's normal load path, including true children/master off.
        for master in [false,true] {
            for hop in [false,true] {
                for preparation in [false,true] {
                    configure(w,master:master,hop:hop,preparation:preparation);w.save()
                    let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
                    let object=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as? [String:Any]
                    let reloaded=DesktopController();reloaded.preferences=preferences
                    reloaded.settingsURL=d.settingsURL;reloaded.legacyURL=d.legacyURL
                    try reloaded.loadSpeciesConfig()
                    let suffix="-master-\(master)-hop-\(hop)-preparation-\(preparation)"
                    checks["passiveMotionSaveAppliesExactCombination"+suffix]=matches(saved,master:master,hop:hop,preparation:preparation) &&
                        matches(d.settings,master:master,hop:hop,preparation:preparation) &&
                        (object?["perchActions"] as? Bool) == master && (object?["sideHopEnabled"] as? Bool) == hop &&
                        (object?["takeoffPreparationEnabled"] as? Bool) == preparation
                    checks["passiveMotionReloadKeepsExactCombination"+suffix]=matches(reloaded.settings,master:master,hop:hop,preparation:preparation)
                }
            }
        }

        configure(w,master:false,hop:true,preparation:true);w.save()
        set(w.perchActionsButton,to:true)
        checkRejections(w,reason:.disabled,suffix:"saved-master-off",checks:&checks)
        configure(w,master:true,hop:false,preparation:false);w.save()
        set(w.sideHopButton,to:true);set(w.takeoffPreparationButton,to:true)
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            let suffix=language == .chinese ? "zh":"en"
            checks["passiveMotionDraftSurvivesLanguageChange-"+suffix]=w.draft.sideHopEnabled &&
                w.draft.takeoffPreparationEnabled && !d.settings.sideHopEnabled && !d.settings.takeoffPreparationEnabled
            checkRejections(w,reason:.disabled,suffix:suffix,checks:&checks)
            d.paused=true
            checkRejections(w,reason:.paused,suffix:suffix,checks:&checks)
            d.paused=false
            try checkLayout(w,suffix:suffix,folder:evidence,checks:&checks)
        }

        let savedURL=d.settingsURL;d.settingsURL=evidence
        w.save();d.settingsURL=savedURL
        let afterFailure=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
        checks["passiveMotionFailedSavePreservesBothActiveAndStoredChildren"]=w.draft.sideHopEnabled &&
            w.draft.takeoffPreparationEnabled && !d.settings.sideHopEnabled && !d.settings.takeoffPreparationEnabled &&
            !afterFailure.sideHopEnabled && !afterFailure.takeoffPreparationEnabled &&
            w.message.stringValue==w.t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.")
        w.resetDefaults()
        checks["passiveMotionRestoreDefaultsOnlyEditsDraft"]=w.draft.perchActions && w.draft.sideHopEnabled &&
            w.draft.takeoffPreparationEnabled && w.sideHopButton.state == .on && w.takeoffPreparationButton.state == .on &&
            !d.settings.sideHopEnabled && !d.settings.takeoffPreparationEnabled
        w.save()
        let restored=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
        checks["passiveMotionRestoredDefaultsSavedAndApplied"]=matches(restored,master:true,hop:true,preparation:true) &&
            matches(d.settings,master:true,hop:true,preparation:true)

        // Saved-enabled previews must still start when every corresponding draft
        // gate is off. Install one settled real bird afresh for each native button.
        configure(w,master:false,hop:false,preparation:false)
        guard let work=d.screenRects.first else {
            throw NSError(domain:"PassiveMotionSettingsVerification",code:2,
                          userInfo:[NSLocalizedDescriptionKey:"Native settings verification requires a display."])
        }
        let host=Surface(id:971,pid:42,rect:CGRect(x:work.minX+60,y:work.midY+100,width:work.width-120,height:100))
        let target=Surface(id:972,pid:42,rect:CGRect(x:work.minX+60,y:work.midY-140,width:work.width-120,height:100))
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let suffix=language == .chinese ? "zh":"en"
            for preview in previews(w) {
                let key="passiveMotionSavedEnabledPreview-\(suffix)-\(preview.kind.rawValue)"
                checks[key]=false;checks[key+"MessageFits"]=false
                d.engine.handle(.cancelAmbient(.screensChanged));d.surfaces=[target,host]
                let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.treeSparrow),random:{0.5})
                bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;bird.tick(2)
                d.birds=[bird];d.syncWorld(buttonsDown:false)
                let id=d.engine.id(of:bird),counts=population(d),sequence=d.engine.events.last?.sequence
                preview.button.performClick(nil)
                let event=d.engine.events.last
                checks[key] = !w.draft.perchActions && !w.draft.sideHopEnabled && !w.draft.takeoffPreparationEnabled &&
                    matches(d.settings,master:true,hop:true,preparation:true) && event?.sequence != sequence &&
                    event?.type == .started && event?.source == .preview && event?.kind==preview.kind &&
                    event?.participants == id.map{[$0]} && d.engine.behavior(of:bird)==preview.kind &&
                    d.birds.count==1 && d.birds.first === bird && population(d)==counts &&
                    w.message.stringValue==preview.message
                checks[key+"MessageFits"]=(w.message.cell?.cellSize(forBounds:w.message.bounds).height ?? .infinity)<=w.message.frame.height
                if let scroll=w.tabs.tabViewItems[2].view as? NSScrollView {
                    scroll.contentView.scroll(to:CGPoint(x:0,y:1260));scroll.reflectScrolledClipView(scroll.contentView)
                }
                try SettingsVerification.snapshot(w.window!,to:evidence.appendingPathComponent("preview-\(suffix)-\(preview.kind.rawValue).png"))
                d.engine.handle(.cancelAmbient(.screensChanged))
            }
            d.birds=[]
            checkRejections(w,reason:nil,suffix:"no-bird-"+suffix,checks:&checks)
        }
    }

    private static func set(_ button:NSButton,to enabled:Bool) {
        if (button.state == .on) != enabled {button.performClick(nil)}
    }
    private static func configure(_ w:SpeciesSettingsWindow,master:Bool,hop:Bool,preparation:Bool) {
        set(w.perchActionsButton,to:true)
        set(w.sideHopButton,to:hop);set(w.takeoffPreparationButton,to:preparation)
        set(w.perchActionsButton,to:master)
    }
    private static func matches(_ s:BirdSettings,master:Bool,hop:Bool,preparation:Bool) -> Bool {
        s.perchActions==master && s.sideHopEnabled==hop && s.takeoffPreparationEnabled==preparation
    }
    private static func population(_ d:DesktopController) -> [Int] {
        [d.birds.count,d.residentCount,d.engine.passingCount,d.engine.departingCount,d.engine.pendingCount,
         d.arrivalCount,d.departureCount]
    }
    private static func previews(_ w:SpeciesSettingsWindow) -> [(kind:BehaviorKind,button:NSButton,message:String)] {
        [(.sideHop,w.previewSideHopButton,w.t("正在预览小跳让路，小鸟会沿当前边缘挪开一步。","Previewing a short hop along the current ledge.")),
         (.takeoffPreparation,w.previewTakeoffPreparationButton,w.t("正在预览起飞准备：专用鸟会下蹲、蹬伸，其余保留原表现；点击可立即换位。","Previewing takeoff preparation: dedicated crouch/push poses, existing poses for other species; clicks relocate immediately."))]
    }
    private static func checkRejections(_ w:SpeciesSettingsWindow,reason:BehaviorReason?,suffix:String,checks:inout [String:Bool]) {
        let d=w.desktop
        for preview in previews(w) {
            let key="passiveMotionPreviewRejection-\(suffix)-\(preview.kind.rawValue)"
            checks[key]=false;checks[key+"KeepsPopulationAndLeases"]=false
            let counts=population(d),sequence=d.engine.events.last?.sequence
            preview.button.performClick(nil)
            let event=d.engine.events.last
            let expected=reason.map{event?.reason==$0} ?? (event?.reason == .missingBird || event?.reason == .unavailableBird)
            checks[key]=event?.sequence != sequence && event?.type == .rejected && event?.source == .preview &&
                event?.kind==preview.kind && expected && event?.reason.map{w.message.stringValue==d.behaviorMessage($0)} == true
            checks[key+"KeepsPopulationAndLeases"]=population(d)==counts && d.engine.activeRunCount==0 &&
                d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0
        }
    }
    private static func checkLayout(_ w:SpeciesSettingsWindow,suffix:String,folder:URL,checks:inout [String:Bool]) throws {
        let prefix="passiveMotionLayout-"+suffix
        for name in ["Labels","SectionPositions","Reachable","TitlesFit","HelpFits","NoOverlap","Screenshot"] {
            checks[prefix+name]=false
        }
        w.tabs.selectTabViewItem(at:2)
        let controls=[w.sideHopButton!,w.takeoffPreparationButton!,w.previewSideHopButton!,w.previewTakeoffPreparationButton!]
        checks[prefix+"Labels"]=w.sideHopButton.title==w.t("鼠标靠近时小跳让路","Hop aside when the pointer approaches") &&
            w.takeoffPreparationButton.title==w.t("自主起飞前稍作准备","Prepare before autonomous takeoff") &&
            w.previewSideHopButton.title==w.t("预览小跳让路","Preview hopping aside") &&
            w.previewTakeoffPreparationButton.title==w.t("预览起飞准备","Preview takeoff preparation")
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return}
        scroll.contentView.scroll(to:CGPoint(x:0,y:1260));scroll.reflectScrolledClipView(scroll.contentView)
        w.window?.contentView?.layoutSubtreeIfNeeded()
        let helpIDs:Set<String>=["passiveMotionHelp","passiveMotionPreviewHelp"]
        let help=document.subviews.compactMap{$0 as? NSTextField}.filter {
            $0.identifier.map{helpIDs.contains($0.rawValue)} ?? false
        }
        let heading=document.subviews.compactMap{$0 as? NSTextField}.first {
            $0.stringValue==w.t("让路与起飞","Making room and taking off")
        }
        checks[prefix+"SectionPositions"]=heading?.frame.minY==1280 && w.sideHopButton.frame.minY>=1280 &&
            w.takeoffPreparationButton.frame.minY>=1280 && w.previewSideHopButton.frame.minY==1480 &&
            w.previewTakeoffPreparationButton.frame.minY==1480
        checks[prefix+"Reachable"]=controls.allSatisfy{!$0.isHidden && document.visibleRect.contains($0.frame)}
        checks[prefix+"TitlesFit"]=controls.allSatisfy{$0.intrinsicContentSize.width<=$0.frame.width && $0.intrinsicContentSize.height<=$0.frame.height}
        checks[prefix+"HelpFits"]=help.count==2 && help.allSatisfy {
            !$0.stringValue.isEmpty && document.visibleRect.contains($0.frame) &&
                ($0.cell?.cellSize(forBounds:$0.bounds).height ?? .infinity)<=$0.frame.height
        }
        checks[prefix+"NoOverlap"]=document.subviews.enumerated().allSatisfy {index,view in
            document.bounds.contains(view.frame) && document.subviews.dropFirst(index+1).allSatisfy{!view.frame.intersects($0.frame)}
        }
        let url=folder.appendingPathComponent("passive-motion-settings-"+suffix+".png")
        try SettingsVerification.snapshot(w.window!,to:url)
        let image=NSImage(contentsOf:url)
        checks[prefix+"Screenshot"]=image.map{$0.size.width>0 && $0.size.height>0} ?? false
    }
}
