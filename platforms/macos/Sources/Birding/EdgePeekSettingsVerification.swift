import AppKit
import BirdingCore

/// Native controls, temporary settings and explicitly installed fixture birds.
/// Never starts a desktop, population scheduler, timer or visitor-memory writer.
enum EdgePeekSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("edge-peek-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        checks["edgePeekVerificationCompleted"]=false
        defer {
            let ownChecks=checks.filter{$0.key.hasPrefix("edgePeek")}
            saveJSON(["passed":!ownChecks.isEmpty && ownChecks.values.allSatisfy{$0},"checks":ownChecks],
                     to:evidence.appendingPathComponent("report.json"))
        }
        let suite="Birding.EdgePeekSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {
            throw NSError(domain:"EdgePeekSettingsVerification",code:1)
        }
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=isolatedDesktop(preferences:preferences,folder:evidence)
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["edgePeekDefaultOnWithoutCreatingSettings"] = defaults.edgePeekEnabled && defaults.perchActions &&
            defaults.schemaVersion==1 && !FileManager.default.fileExists(atPath:d.settingsURL.path)

        let cancelled=SpeciesSettingsWindow(desktop:d);cancelled.showWindow(nil)
        cancelled.edgePeekButton.performClick(nil);cancelled.perchActionsButton.performClick(nil)
        checks["edgePeekOnlyEditsDraft"] = !cancelled.draft.edgePeekEnabled && !cancelled.draft.perchActions &&
            d.settings.edgePeekEnabled && d.settings.perchActions &&
            cancelled.message.stringValue==cancelled.t("尚未保存","Unsaved changes")
        cancelled.cancel()
        checks["edgePeekCancelDoesNotApplyOrSave"] = cancelled.window?.isVisible == false &&
            d.settings.edgePeekEnabled && d.settings.perchActions && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel()}
        checks["edgePeekReopenDiscardsCancelledDraft"] = w !== cancelled && w.draft.edgePeekEnabled &&
            w.edgePeekButton.state == .on && w.edgePeekButton.isEnabled
        w.tabs.selectTabViewItem(at:2)
        w.hoverDelayField.stringValue="0.25";w.detailFields[0][2].stringValue="1.25"
        w.sliders[0].doubleValue=35;w.sliderChanged(w.sliders[0]);w.locks[0].performClick(nil)

        for child in [false,true] {
            configure(w,master:true,child:child)
            let otherBefore=try settingsData(w.draft,ignoringEdgePeek:true)
            set(w.perchActionsButton,to:false)
            let suffix="-\(child)"
            checks["edgePeekMasterDisablesAndRetainsPreference"+suffix] = !w.draft.perchActions &&
                !w.edgePeekButton.isEnabled && w.draft.edgePeekEnabled==child &&
                w.edgePeekButton.state == (child ? .on:.off) && w.previewEdgePeekButton.isEnabled
            w.edgePeekButton.performClick(nil);w.relocalize()
            checks["edgePeekDisabledPreferenceSurvivesClickAndRebuild"+suffix] = !w.edgePeekButton.isEnabled &&
                w.draft.edgePeekEnabled==child && w.edgePeekButton.state == (child ? .on:.off)
            set(w.perchActionsButton,to:true)
            let otherAfter=try settingsData(w.draft,ignoringEdgePeek:true)
            checks["edgePeekMasterRestoresPreferenceWithoutOtherChanges"+suffix] = w.edgePeekButton.isEnabled &&
                w.draft.edgePeekEnabled==child && otherBefore==otherAfter && d.settings.edgePeekEnabled
        }

        for master in [false,true] {
            for child in [false,true] {
                configure(w,master:master,child:child);w.save()
                let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
                let object=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as? [String:Any]
                let expected=try settingsData(w.draft),active=try settingsData(d.settings),stored=try settingsData(saved)
                let suffix="-master-\(master)-child-\(child)"
                checks["edgePeekSaveAppliesExactPreferenceCombination"+suffix] =
                    matches(saved,master:master,child:child) && matches(d.settings,master:master,child:child) &&
                    (object?["edgePeekEnabled"] as? Bool)==child && (object?["perchActions"] as? Bool)==master &&
                    (object?["schemaVersion"] as? Int)==1 && expected==stored && active==stored &&
                    saved.hoverDelay==0.25 && saved.catalog.species[0].speed==1.25 && saved.probabilities.entries[0].locked &&
                    w.edgePeekButton.isEnabled==master &&
                    w.message.stringValue==w.t("已保存 · 交互设置立即生效，鸟种参数用于新飞入的小鸟。","Saved · Interaction settings apply now; species settings affect new arrivals.")
                let reloaded=isolatedDesktop(preferences:preferences,folder:evidence)
                try reloaded.loadSpeciesConfig()
                let reloadedData=try settingsData(reloaded.settings)
                checks["edgePeekReloadKeepsExactPreferenceCombination"+suffix] = reloadedData==stored &&
                    isIsolated(reloaded,preferences:preferences,folder:evidence)
            }
        }
        // Save must read the native checkbox even without a dispatched action.
        configure(w,master:true,child:true);w.edgePeekButton.state = .off;w.save()
        let native=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["edgePeekSaveReadsNativeCheckbox"] = !native.edgePeekEnabled && !d.settings.edgePeekEnabled && !w.draft.edgePeekEnabled

        for language:AppLanguage in [.chinese,.english] {
            d.language=language
            let suffix=language == .chinese ? "zh":"en"
            configure(w,master:true,child:false);w.save()
            configure(w,master:true,child:true)
            w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="1.5"
            w.relocalize()
            checks["edgePeekDraftAndRawEditsSurviveLanguageRebuild-"+suffix] = w.draft.edgePeekEnabled &&
                w.edgePeekButton.state == .on && w.edgePeekButton.isEnabled && !d.settings.edgePeekEnabled &&
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
            checks["edgePeekFailedSaveRetainsActiveFileAndDraft-"+suffix] = afterFailure==savedActive &&
                afterBytes==savedBytes && w.draft.edgePeekEnabled && !d.settings.edgePeekEnabled &&
                w.hoverDelayField.stringValue=="0.75" && w.detailFields[0][2].stringValue=="1.5" &&
                w.message.stringValue==w.t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.")
            w.save()
            let retried=try BirdSettings.load(from:savedURL,legacyURL:d.legacyURL)
            checks["edgePeekRetrySavesRetainedDraft-"+suffix] = retried.edgePeekEnabled && d.settings.edgePeekEnabled &&
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
        checks["edgePeekInvalidDelayPreventsPartialApply"] = invalidDelayActive==beforeInvalid &&
            invalidDelayBytes==bytesBeforeInvalid && !w.draft.edgePeekEnabled &&
            (w.tabs.selectedTabViewItem?.identifier as? String)=="interaction"
        w.hoverDelayField.stringValue="0.75";w.detailFields[0][2].stringValue="9";w.save()
        let invalidDetailsActive=try settingsData(d.settings),invalidDetailsBytes=try Data(contentsOf:d.settingsURL)
        checks["edgePeekInvalidDetailsPreventsPartialApply"] = invalidDetailsActive==beforeInvalid &&
            invalidDetailsBytes==bytesBeforeInvalid && !w.draft.edgePeekEnabled &&
            (w.tabs.selectedTabViewItem?.identifier as? String)=="behavior"
        w.detailFields[0][2].stringValue="1.5";w.save()
        let beforeReset=try Data(contentsOf:d.settingsURL)
        w.resetDefaults()
        let afterReset=try Data(contentsOf:d.settingsURL)
        checks["edgePeekResetOnlyChangesDraft"] = w.draft.edgePeekEnabled && w.draft.perchActions &&
            w.edgePeekButton.state == .on && w.edgePeekButton.isEnabled && !d.settings.edgePeekEnabled &&
            beforeReset==afterReset &&
            w.message.stringValue==w.t("已恢复默认（尚未保存，锁定已清除）。","Defaults restored (not saved; locks cleared).")
        w.cancel()
        let reset=SpeciesSettingsWindow(desktop:d);d.settingsWindow=reset;reset.showWindow(nil)
        defer {reset.cancel()}
        checks["edgePeekCancelResetReopensSavedOff"] = !reset.draft.edgePeekEnabled && reset.edgePeekButton.state == .off
        reset.resetDefaults();reset.save()
        let restored=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        let restoredData=try settingsData(restored),defaultData=try settingsData(BirdSettings())
        checks["edgePeekRestoreDefaultsSavesAndApplies"] = restored.edgePeekEnabled && d.settings.edgePeekEnabled &&
            restoredData==defaultData && reset.edgePeekButton.state == .on && reset.edgePeekButton.isEnabled
        try checkPreviews(reset,folder:evidence,checks:&checks)
        d.birds=[];d.surfaces=[]
        checks["edgePeekVerificationRemainsIsolated"] = isIsolated(d,preferences:preferences,folder:evidence)
        checks["edgePeekVerificationCompleted"]=true
    }

    private static func isolatedDesktop(preferences:UserDefaults,folder:URL) -> DesktopController {
        let d=DesktopController();d.preferences=preferences;d.automaticPopulation=false
        // These controls test saved settings and preview gates, not live mouse input.
        d.pointerButtonsDown={false}
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

    private static func settingsData(_ settings:BirdSettings,ignoringEdgePeek:Bool=false) throws -> Data {
        var value=settings;value.pendingSpecies=[]
        if ignoringEdgePeek {value.edgePeekEnabled=true}
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private static func set(_ button:NSButton,to enabled:Bool) {
        if (button.state == .on) != enabled {button.performClick(nil)}
    }
    private static func configure(_ w:SpeciesSettingsWindow,master:Bool,child:Bool) {
        set(w.perchActionsButton,to:true);set(w.edgePeekButton,to:child);set(w.perchActionsButton,to:master)
    }
    private static func matches(_ value:BirdSettings,master:Bool,child:Bool) -> Bool {
        value.perchActions==master && value.edgePeekEnabled==child
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
        w.previewEdgePeekButton.performClick(nil)
        let event=d.engine.events.last
        checks["edgePeekPreviewRejection-"+suffix] = event?.sequence != sequence && event?.kind == .edgePeek &&
            event?.type == .rejected && event?.source == .preview &&
            event?.reason.map {reason in
                let expected=reason == .noSpecies
                    ? (w.t("请等待支持鸟种在窗口上沿端点附近停稳：","Wait for a supported bird to settle near a window’s top-edge endpoint: ")+d.language.supportedSpeciesNames(for:.edgePeek)+w.t("。","."))
                    : d.behaviorMessage(reason)
                return reasons.contains(reason) && w.message.stringValue==expected
            } == true
        checks["edgePeekRejectedPreviewKeepsPopulationMotionAndLeases-"+suffix] = population(d)==counts &&
            d.engine.activeRunCount==runs && d.engine.leasedBirdCount==leases && d.engine.reservedLandingCount==slots &&
            d.birds.map(\.position)==positions && d.birds.map(\.motionRevision)==revisions
        checks["edgePeekRejectionMessageFits-"+suffix] = messageIsFullyVisible(w.message)
    }

    /// Verify the real cell's mode, then lay out every character inside its
    /// drawing rectangle. cellSize alone can report a fitting single line
    /// while the native control clips the rest of a support list.
    static func messageIsFullyVisible(_ field:NSTextField) -> Bool {
        guard let cell=field.cell as? NSTextFieldCell,cell.wraps,!cell.usesSingleLineMode,!cell.isScrollable,
              cell.lineBreakMode == .byWordWrapping,field.maximumNumberOfLines==0,
              !field.isHidden,!field.stringValue.isEmpty,let font=field.font else {return false}
        let rect=cell.drawingRect(forBounds:field.bounds)
        guard rect.width>0,rect.height>0 else {return false}
        let style=NSMutableParagraphStyle();style.lineBreakMode=cell.lineBreakMode;style.alignment=field.alignment
        let storage=NSTextStorage(string:field.stringValue,attributes:[.font:font,.paragraphStyle:style])
        let layout=NSLayoutManager(),container=NSTextContainer(containerSize:rect.size)
        container.lineFragmentPadding=0;container.lineBreakMode=cell.lineBreakMode
        container.maximumNumberOfLines=field.maximumNumberOfLines
        storage.addLayoutManager(layout);layout.addTextContainer(container)
        let glyphs=layout.glyphRange(for:container)
        let characters=layout.characterRange(forGlyphRange:glyphs,actualGlyphRange:nil)
        let used=layout.usedRect(for:container)
        return characters.location==0 && NSMaxRange(characters)==storage.length &&
            used.maxX<=rect.width+0.001 && used.maxY<=rect.height+0.001
    }

    private static func checkPreviews(_ w:SpeciesSettingsWindow,folder:URL,checks:inout [String:Bool]) throws {
        let d=w.desktop
        guard let screen=d.screenRects.first,screen.width>=640,screen.height>=480 else {
            throw NSError(domain:"EdgePeekSettingsVerification",code:2,
                          userInfo:[NSLocalizedDescriptionKey:"Native edge-peek verification requires a display of at least 640 × 480."])
        }
        let manifest=d.frameCapabilities
        var previewEvidence=[[String:Any]]()
        defer {saveJSON(["previews":previewEvidence],to:folder.appendingPathComponent("edge-peek-preview-evidence.json"))}
        defer {d.engine.handle(.cancelAmbient(.screensChanged));d.birds=[];d.surfaces=[];d.frameCapabilities=manifest}
        // Pick the endpoint and vertical location away from the real pointer;
        // native preview intentionally resamples it through syncWorld().
        let y=screen.minY+(d.pointerPosition.y<screen.midY ? screen.height*0.72:screen.height*0.35)
        let host=Surface(id:981,pid:42,rect:CGRect(x:screen.minX+80,y:y,width:screen.width-160,height:90))
        func install(_ species:SpeciesID = .treeSparrow,center:Bool=false,ground:Bool=false) -> Bird {
            d.engine.handle(.cancelAmbient(.screensChanged));d.birds=[]
            let surface=Surface(id:host.id,pid:host.pid,rect:host.rect,isGround:ground)
            let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(species),random:{0.5})
            let span=Geometry.perchX(1,rect:host.rect)-Geometry.perchX(0,rect:host.rect)
            let inset=95*d.spriteScale(for:bird)/span
            bird.fraction=center ? 0.5:(d.pointerPosition.x<screen.midX ? 1-inset:inset)
            bird.perch(on:surface,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600
            // Production requires >=0.45 s settled and no base hop. At 2 s
            // magpie-robin is inside its 1...3.6 s tail/hop window. Advance
            // normally to 0.6 s, before every supported species' idle hop.
            bird.tick(0.6)
            d.surfaces=[surface];d.birds=[bird];d.syncWorld(buttonsDown:false)
            return bird
        }
        configure(w,master:false,child:false)
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let suffix=language == .chinese ? "zh":"en"
            for species in SpeciesBehaviorProfile.species(for:.edgePeek) {
                let bird=install(species),id=d.engine.id(of:bird),counts=population(d),sequence=d.engine.events.last?.sequence
                let settledAge=bird.stateTime,settledHop=bird.hopOffset
                let footError=Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,
                    edge:.top,scale:d.spriteScale(for:bird)))
                w.previewEdgePeekButton.performClick(nil)
                let event=d.engine.events.last,key="edgePeekSavedEnabledPreview-"+suffix+"-"+species.rawValue
                checks[key] = settledAge>=0.45 && abs(settledHop)<0.001 && footError<0.001 &&
                    !w.draft.edgePeekEnabled && !w.draft.perchActions && d.settings.edgePeekEnabled &&
                    d.settings.perchActions && event?.sequence != sequence && event?.type == .started &&
                    event?.kind == .edgePeek && event?.source == .preview && event?.participants == id.map{[$0]} &&
                    d.engine.behavior(of:bird) == .edgePeek && d.birds.count==1 && d.birds.first === bird &&
                    population(d)==counts && w.message.stringValue==w.t("正在预览探头观察：小鸟会安全靠近边缘、低头，再退回原位。","Previewing edge peeking: the bird approaches safely, looks down, then retreats.")
                checks[key+"MessageFits"] = messageIsFullyVisible(w.message)
                scrollToSection(w)
                try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("edge-peek-preview-"+suffix+"-"+species.rawValue+".png"))
                checkRejection(w,reasons:[.busy],suffix:"busy-"+suffix+"-"+species.rawValue,checks:&checks)
                let repeated=d.engine.events.last
                previewEvidence.append(["species":species.rawValue,"language":suffix,
                    "settledAge":settledAge,"settledHop":settledHop,"footError":footError,
                    "firstEventType":event?.type.rawValue ?? "none","firstEventReason":event?.reason?.rawValue ?? "none",
                    "repeatedEventType":repeated?.type.rawValue ?? "none","repeatedEventReason":repeated?.reason?.rawValue ?? "none",
                    "screenshot":"edge-peek-preview-"+suffix+"-"+species.rawValue+".png"])
            }
            d.engine.handle(.cancelAmbient(.screensChanged));d.birds=[]
            checkRejection(w,reasons:[.missingBird,.unavailableBird],suffix:"no-bird-"+suffix,checks:&checks)
            _=install(center:true)
            checkRejection(w,reasons:[.noSpace],suffix:"center-far-from-endpoint-"+suffix,checks:&checks)
            _=install(ground:true)
            checkRejection(w,reasons:[.noSpace],suffix:"ground-"+suffix,checks:&checks)
            _=install()
            d.frameCapabilities[.treeSparrow]=["stand","land0","land1","land2"]
            checkRejection(w,reasons:[.missingFrames],suffix:"missing-frames-"+suffix,checks:&checks)
            d.frameCapabilities=manifest
            _=install(.redWhiskeredBulbul)
            checkRejection(w,reasons:[.noSpecies],suffix:"unsupported-species-"+suffix,checks:&checks)
            checks["edgePeekUnsupportedSpeciesMessageIsSpecific-"+suffix] =
                d.engine.events.last?.reason == .noSpecies &&
                w.message.stringValue==(w.t("请等待支持鸟种在窗口上沿端点附近停稳：","Wait for a supported bird to settle near a window’s top-edge endpoint: ")+d.language.supportedSpeciesNames(for:.edgePeek)+w.t("。",".")) &&
                w.message.stringValue != d.behaviorMessage(.noSpecies)
            scrollToSection(w)
            let screenshot="edge-peek-unsupported-species-"+suffix+".png"
            try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent(screenshot))
            previewEvidence.append(["case":"unsupported-species","language":suffix,
                "eventType":d.engine.events.last?.type.rawValue ?? "none",
                "eventReason":d.engine.events.last?.reason?.rawValue ?? "none",
                "message":w.message.stringValue,"cellWraps":w.message.cell?.wraps ?? false,
                "cellUsesSingleLineMode":w.message.cell?.usesSingleLineMode ?? true,
                "cellScrollable":w.message.cell?.isScrollable ?? true,
                "maximumNumberOfLines":w.message.maximumNumberOfLines,
                "messageBounds":NSStringFromRect(w.message.bounds),
                "messageFullyVisible":messageIsFullyVisible(w.message),"screenshot":screenshot])
        }
    }

    private static func scrollToSection(_ w:SpeciesSettingsWindow) {
        w.tabs.selectTabViewItem(at:2)
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView,
              let heading=document.subviews.first(where:{$0.identifier?.rawValue=="edgePeekSectionTitle"}) else {return}
        let limit=max(0,document.bounds.height-scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:CGPoint(x:0,y:min(max(0,heading.frame.minY-12),limit)))
        scroll.reflectScrolledClipView(scroll.contentView);w.window?.contentView?.layoutSubtreeIfNeeded()
    }

    private static func checkLayout(_ w:SpeciesSettingsWindow,suffix:String,folder:URL,checks:inout [String:Bool]) throws {
        let prefix="edgePeekLayout-"+suffix
        for name in ["Labels","ExistingPositions","Reachable","TitlesFit","HelpFits","NoOverlap","FooterVisible","Screenshot"] {
            checks[prefix+name]=false
        }
        scrollToSection(w)
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return}
        func label(_ identifier:String) -> NSTextField? {
            document.subviews.compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue==identifier}
        }
        guard let heading=label("edgePeekSectionTitle"),let help=label("edgePeekHelp"),
              let previewHelp=label("edgePeekPreviewHelp"),let rhythm=label("activityRhythmHelp") else {return}
        let controls=[w.edgePeekButton!,w.previewEdgePeekButton!]
        let views:[NSView]=[heading,w.edgePeekButton,w.previewEdgePeekButton,help,previewHelp]
        checks[prefix+"Labels"] = heading.stringValue==w.t("探头观察","Edge peeking") &&
            w.edgePeekButton.title==w.t("窗口边缘探头观察","Peek over window edges") &&
            w.edgePeekButton.accessibilityLabel()==w.edgePeekButton.title &&
            w.previewEdgePeekButton.title==w.t("预览探头观察","Preview edge peeking")
        checks[prefix+"SpeciesNames"] = help.stringValue.contains(w.language.supportedSpeciesNames(for:.edgePeek)) &&
            SpeciesBehaviorProfile.species(for:.edgePeek).allSatisfy{help.stringValue.contains(w.language.name($0))}
        checks[prefix+"ExistingPositions"] = w.hoverDelaySlider.frame.minY==122 && w.pointerVisitsButton.frame.minY==310 &&
            w.perchActionsButton.frame.minY==916 && w.sideHopButton.frame.minY==1322 && w.previewSideHopButton.frame.minY==1480 &&
            label("leafSectionTitle")?.frame.minY==1600 && w.visitorMemoryButton.frame.minY==2002 &&
            label("activityRhythmSectionTitle")?.frame.minY==2180 && w.activityRhythmPopup.frame.minY==2222 &&
            rhythm.frame.minY==2270 && rhythm.frame.maxY<heading.frame.minY
        checks[prefix+"Reachable"] = views.allSatisfy{!$0.isHidden && document.visibleRect.contains($0.frame)} &&
            w.edgePeekButton.isEnabled==w.draft.perchActions && w.previewEdgePeekButton.isEnabled
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
        let url=folder.appendingPathComponent("edge-peek-settings-"+suffix+".png")
        try SettingsVerification.snapshot(w.window!,to:url)
        checks[prefix+"Screenshot"] = NSImage(contentsOf:url).map{$0.size.width>0 && $0.size.height>0} ?? false
    }
}
