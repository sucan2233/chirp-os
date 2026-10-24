import AppKit
import BirdingCore

/// Native controls and engine time only. The timeout fixture intentionally
/// leaves its resident perched; it never manufactures an airborne candidate.
enum InsectCatchSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("insect-catch-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("insectCatchSettings")}],to:output.appendingPathComponent("report.json"))}
        let suite="Birding.InsectCatchSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate preferences")}
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=DesktopController();d.preferences=preferences;d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.pointerButtonsDown={false};d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false
        d.settingsURL=output.appendingPathComponent("settings.json");d.legacyURL=output.appendingPathComponent("legacy.json")
        d.visitorMemoryURL=output.appendingPathComponent("visitors.json");d.observationJournalURL=output.appendingPathComponent("journal.json")
        guard let work=d.screenRects.first else {throw failure("Settings verification requires a display")}
        let host=Surface(id:7301,pid:42,rect:CGRect(x:work.minX+30,y:work.midY,width:work.width-60,height:100))
        d.surfaces=[host]
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["insectCatchSettingsDefaultOnWithoutWriting"]=defaults.insectCatchEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(defaults)) as! [String:Any]
        legacy.removeValue(forKey:"insectCatchEnabled");legacy["hoverDelay"]=0.37;legacy["pointerFollowEnabled"]=true
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:legacy))
        checks["insectCatchSettingsMissingKeyPreservesDrafts"]=migrated.insectCatchEnabled && migrated.hoverDelay==0.37 && migrated.pointerFollowEnabled
        var fixtureSettings=migrated;fixtureSettings.perchActions=false;fixtureSettings.passiveAttentionEnabled=false
        d.settings=fixtureSettings
        let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.barnSwallow),random:{0.5})
        bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;d.birds=[bird]
        d.syncWorld(buttonsDown:false)
        // Drain the rebuilt settings controls (including AppKit's hosted
        // SwiftUI graphs) before constructing the journal's native controls.
        try autoreleasepool {try controls(d,bird:bird,settings:fixtureSettings,into:&checks,folder:output)}
        try autoreleasepool {try journal(d,into:&checks,folder:output)}
        checks["insectCatchSettingsNoRealPreferencesOrStartup"]=d.timer==nil && d.panels.isEmpty && d.views.isEmpty &&
            d.globalMouseMonitor==nil && d.localMouseMonitor==nil && d.preferences === preferences && !d.automaticPopulation &&
            !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path) && !FileManager.default.fileExists(atPath:d.observationJournalURL.path)
    }
    private static func controls(_ d:DesktopController,bird:Bird,settings fixtureSettings:BirdSettings,
                                 into checks:inout [String:Bool],folder output:URL) throws {
        let origin=bird.position,revision=bird.motionRevision
        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel();d.settingsWindow=nil;d.engine.handle(.cancelAmbient(.shutdown))}
        var disabledSpecies=fixtureSettings
        guard let swallow=disabledSpecies.probabilities.entries.firstIndex(where:{$0.id == .barnSwallow}) else {throw failure("Missing swallow probability")}
        disabledSpecies.probabilities.adjust(at:swallow,to:0)
        try d.applySettings(disabledSpecies)
        w.previewInsectCatchButton.performClick(nil)
        checks["insectCatchSettingsSavedZeroProbabilityRejectsExistingResident"]=d.engine.events.last?.reason == .noSpecies &&
            !d.engine.hasInsectCatchPreview && d.engine.insectSnapshot()==nil && d.engine.activeRunCount==0 &&
            d.birds.first === bird && bird.position==origin && bird.motionRevision==revision
        try d.applySettings(fixtureSettings)
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            let key="insectCatchSettings-"+language.rawValue+"-"
            let controls=[w.insectCatchButton!,w.previewInsectCatchButton!,w.cancelInsectCatchPreviewButton!,w.clearInsectButton!]
            checks[key+"AccessibleNativeControls"]=controls.allSatisfy {
                $0.target === w && $0.action != nil && $0.identifier != nil && $0.accessibilityLabel()==$0.title &&
                $0.superview?.bounds.contains($0.frame)==true && $0.intrinsicContentSize.width<=$0.frame.width
            }
            guard let view=w.insectCatchButton.superview,
                  let help=view.subviews.first(where:{$0.identifier?.rawValue=="insectCatchHelp"}) as? NSTextField else {throw failure("Missing insect help")}
            checks[key+"OnlyDeliveredSwallowPreview"]=SpeciesBehaviorProfile.species(for:.insectCatch)==[.barnSwallow] &&
                controls.filter{$0.identifier?.rawValue.hasPrefix("preview")==true}.count==1 &&
                w.previewInsectCatchButton.identifier?.rawValue=="previewBarnSwallowInsectCatch" &&
                !view.subviews.contains{$0.identifier?.rawValue.localizedCaseInsensitiveContains("flycatcher")==true}
            checks[key+"SingleSourceSpeciesAndWrappedHelpFits"]=help.stringValue.contains(language.insectCatchSupport) &&
                help.cell?.wraps==true && help.cell?.usesSingleLineMode==false &&
                (help.cell?.cellSize(forBounds:CGRect(x:0,y:0,width:help.frame.width,height:10000)).height ?? .infinity)<=help.frame.height
            w.insectCatchButton.performClick(nil)
            checks[key+"ToggleOnlyEditsDraft"] = !w.draft.insectCatchEnabled && d.settings.insectCatchEnabled
            w.insectCatchButton.performClick(nil)
            let sequence=d.engine.events.last?.sequence ?? 0
            w.previewInsectCatchButton.performClick(nil)
            checks[key+"PreviewWaitsWithoutRunOrInsect"]=waiting(d) && bird.position==origin && bird.motionRevision==revision
            scroll(w)
            try SettingsVerification.snapshot(w.window!,to:output.appendingPathComponent("insect-catch-waiting-"+language.rawValue+".png"))
            advance(d,1);let remaining=d.engine.insectPreviewRemaining
            d.paused=true;advance(d,4)
            checks[key+"PauseFreezesPendingDeadline"]=waiting(d) && remaining != nil &&
                d.engine.insectPreviewRemaining==remaining && bird.state == .perched && bird.position==origin
            d.paused=false;advance(d,8.9)
            checks[key+"DoesNotTimeoutBeforeTenUnpausedSeconds"]=waiting(d)
            advance(d,0.2);d.consumeBehaviorEvents();w.refreshInsectCatchControls()
            let events=d.engine.events.filter{$0.sequence>sequence && $0.kind == .insectCatch}
            checks[key+"DeadlineRejectsWithoutForcedFlight"]=events.filter{$0.type == .previewResult && $0.reason == .timedOut}.count==1 &&
                !events.contains{$0.type == .started} && !d.engine.hasInsectCatchPreview && d.engine.activeRunCount==0 && insects(d).isEmpty &&
                bird.state == .perched && bird.position==origin && bird.motionRevision==revision && d.birds.first === bird
            checks[key+"TimeoutMessageVisible"]=w.message.stringValue==w.insectCatchMessage(.timedOut) && EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            for reason:BehaviorReason in [.paused,.disabled,.settingsChanged,.busy,.noSpecies,.missingBird,.unavailableBird,.missingFrames,
                                         .noSpace,.targetInvalid,.pointerNearby,.timedOut,.missedTarget,.userInput] {
                w.message.stringValue=w.insectCatchMessage(reason)
                checks[key+"ReasonFits-"+reason.rawValue]=EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            }
            let actions:[(String,()->Void)]=[("cancel",{w.cancelInsectCatchPreviewButton.performClick(nil)}),
                ("clear",{w.clearInsectButton.performClick(nil)}),("relocalize",{w.relocalize()}),("build",{w.build()})]
            for (name,action) in actions {
                w.previewInsectCatchButton.performClick(nil)
                checks[key+"PendingArmed-"+name]=waiting(d)
                action();advance(d,10.2)
                checks[key+"PendingCancelled-"+name] = !d.engine.hasInsectCatchPreview && insects(d).isEmpty && d.engine.activeRunCount==0
            }
            scroll(w)
            try SettingsVerification.snapshot(w.window!,to:output.appendingPathComponent("insect-catch-controls-"+language.rawValue+".png"))
        }
        w.previewInsectCatchButton.performClick(nil)
        w.insectCatchButton.state = .off;w.hoverDelayField.stringValue="0.43"
        let details=w.detailFields[0][0].stringValue,perches=w.draft.fixedPerches
        w.cancelInsectCatchPreviewButton.performClick(nil)
        checks["insectCatchSettingsCancelPreservesUnsavedNativeInputs"] = !d.engine.hasInsectCatchPreview &&
            w.insectCatchButton.state == .off && w.hoverDelayField.stringValue=="0.43" && w.detailFields[0][0].stringValue==details && w.draft.fixedPerches==perches
        w.save()
        let off=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["insectCatchSettingsSaveReloadOffPreservesOtherValues"] = !off.insectCatchEnabled && !d.settings.insectCatchEnabled &&
            off.hoverDelay==0.43 && off.pointerFollowEnabled && off.fixedPerches==perches
        w.insectCatchButton.performClick(nil);w.previewInsectCatchButton.performClick(nil)
        checks["insectCatchSettingsPreviewReadsSavedSwitch"]=w.draft.insectCatchEnabled && !d.engine.hasInsectCatchPreview && d.engine.events.last?.reason == .disabled
        w.save()
        let lifecycle:[(String,()->Void)]=[("save",{w.save()}),("reset",{w.resetDefaults()}),
            ("close",{w.window?.performClose(nil)}),("cancel",{w.cancel()})]
        for (name,action) in lifecycle {
            w.showWindow(nil);w.previewInsectCatchButton.performClick(nil)
            checks["insectCatchSettingsLifecycleArmed-"+name]=waiting(d)
            action();advance(d,10.2)
            checks["insectCatchSettingsLifecycleCancelled-"+name] = !d.engine.hasInsectCatchPreview && insects(d).isEmpty && d.engine.activeRunCount==0
        }
        let reopened=SpeciesSettingsWindow(desktop:d)
        checks["insectCatchSettingsReopenUsesSavedSwitch"]=reopened.draft.insectCatchEnabled==d.settings.insectCatchEnabled &&
            reopened.insectCatchButton.state==(d.settings.insectCatchEnabled ? .on:.off)
        reopened.cancel()
        let json=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as! [String:Any]
        checks["insectCatchSettingsOnlyBooleanPersisted"]=json.keys.filter{$0.localizedCaseInsensitiveContains("insect")}==["insectCatchEnabled"]
    }
    private static func journal(_ d:DesktopController,into checks:inout [String:Bool],folder:URL) throws {
        let now=Date(timeIntervalSince1970:1_700_000_000)
        for (index,source) in [BehaviorSource.automatic,.preview,.user].enumerated() {
            _=d.observationJournal.observe(BehaviorObservation(sequence:UInt64(index+1),simulationTime:Double(index),kind:.insectCatch,
                source:source,species:[.barnSwallow],runID:UInt64(index+1)),at:now)
        }
        let w=ObservationJournalWindow(desktop:d);w.showWindow(nil);defer {w.window?.close()}
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.sourceFilter.selectedSegment=0
            for query in ["insectCatch","捕虫","Insect Catching"] {
                w.searchField.stringValue=query;w.searchChanged(nil)
                checks["insectCatchSettingsJournalSearch-"+language.rawValue+"-"+query]=w.renderedEntries.count==1 &&
                    w.renderedEntries.first?.behavior=="insectCatch" && w.behaviorName("insectCatch")==language.text("捕虫","Insect Catching")
            }
            let entry=w.renderedEntries.first
            checks["insectCatchSettingsJournalSourceCounts-"+language.rawValue]=entry?.automaticCount==1 && entry?.previewCount==1 && entry?.userCount==1
            try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("insect-catch-journal-"+language.rawValue+".png"))
        }
    }
    private static func waiting(_ d:DesktopController)->Bool {d.engine.hasInsectCatchPreview && d.engine.activeRunCount==0 && insects(d).isEmpty}
    private static func insects(_ d:DesktopController)->[ScenePropRenderState] {d.engine.propSnapshot().filter{$0.kind == .insect}}
    private static func advance(_ d:DesktopController,_ seconds:Double) {
        for _ in 0..<Int((seconds*120).rounded()) {d.syncWorld(buttonsDown:false);d.engine.advance(1.0/120)}
    }
    private static func scroll(_ w:SpeciesSettingsWindow) {
        w.tabs.selectTabViewItem(at:2)
        guard let view=w.tabs.tabViewItems[2].view as? NSScrollView else {return}
        view.contentView.scroll(to:CGPoint(x:0,y:6440));view.reflectScrolledClipView(view.contentView)
        w.window?.contentView?.layoutSubtreeIfNeeded()
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"InsectCatchSettingsVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
