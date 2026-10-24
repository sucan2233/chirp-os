import AppKit
import BirdingCore

/// Native controls use production actions; only time, preferences and placement
/// geometry are supplied by the fixture. Main registers this after all M6d work.
enum BathSettingsVerification {
    private static let display=CGRect(x:0,y:0,width:1400,height:900)
    private static let target=CGPoint(x:900,y:550)
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("bath-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        checks["bathSettingsCompleted"]=false
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("bathSettings")},"evidence":evidence],to:output.appendingPathComponent("report.json"))}
        let suite="Birding.BathSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate preferences")}
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=DesktopController();d.preferences=preferences;d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false
        d.settingsURL=output.appendingPathComponent("settings.json");d.legacyURL=output.appendingPathComponent("legacy.json")
        d.visitorMemoryURL=output.appendingPathComponent("visitors.json");d.observationJournalURL=output.appendingPathComponent("journal.json")
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["bathSettingsDefaultOnWithoutWriting"]=defaults.bathEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(defaults)) as! [String:Any]
        legacy.removeValue(forKey:"bathEnabled");legacy["hoverDelay"]=0.37;legacy["pointerFollowEnabled"]=true
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:legacy))
        checks["bathSettingsOldMissingKeyPreservesOtherValues"]=migrated.bathEnabled && migrated.hoverDelay==0.37 && migrated.pointerFollowEnabled
        d.settings=migrated
        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel();d.engine.handle(.clearCurrentScene)}
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            let key="bathSettings-"+language.rawValue
            let controls=[w.bathButton!,w.placeBathButton!,w.removeBathButton!,w.cancelBathPlacementButton!,w.clearCurrentSceneButton!,w.previewBathButton!]
            checks[key+"NativeAccessibleControls"]=controls.allSatisfy {
                $0.target === w && $0.action != nil && $0.identifier != nil && $0.accessibilityLabel()==$0.title &&
                $0.superview?.bounds.contains($0.frame)==true && $0.intrinsicContentSize.width<=$0.frame.width
            }
            guard let view=w.bathButton.superview,let help=view.subviews.first(where:{$0.identifier?.rawValue=="bathHelp"}) as? NSTextField else {throw failure("Missing bath help")}
            checks[key+"ProfileSpeciesAndHelpFits"]=help.stringValue.contains(language.supportedSpeciesNames(for:.bathVisit)) &&
                SpeciesBehaviorProfile.species(for:.bathVisit)==[.treeSparrow,.lightVentedBulbul] &&
                (help.cell?.cellSize(forBounds:CGRect(x:0,y:0,width:help.frame.width,height:10000)).height ?? .infinity)<=help.frame.height
            w.bathButton.performClick(nil)
            checks[key+"ToggleDraftOnly"] = !w.draft.bathEnabled && d.settings.bathEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)
            w.bathButton.performClick(nil)
            let cancellations:[(String,()->Void)]=[("cancel",{w.cancelBathPlacementButton.performClick(nil)}),
                                   ("remove",{w.removeBathButton.performClick(nil)}),
                                   ("clear",{w.clearCurrentSceneButton.performClick(nil)}),
                                   ("rebuild",{w.build()}),("language",{w.relocalize()})]
            for (name,action) in cancellations {
                w.placeBathButton.performClick(nil)
                checks[key+"PendingArmed-"+name]=d.engine.hasBathPlacement
                action();world(d.engine,point:target);advance(d.engine,3.2)
                checks[key+"PendingCancelled-"+name] = !d.engine.hasBathPlacement && d.engine.habitatSnapshot().isEmpty
            }
            scroll(w)
            try SettingsVerification.snapshot(w.window!,to:output.appendingPathComponent("bath-controls-"+language.rawValue+".png"))
            for reason:BehaviorReason in [.paused,.disabled,.busy,.missingFrames,.noSpecies,.noSpace,.targetInvalid,.pointerNearby,.unavailableBird] {
                w.message.stringValue=w.bathMessage(reason)
                checks[key+"ReasonFits-"+reason.rawValue]=EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            }
        }
        w.bathButton.state = .off;w.save()
        let off=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["bathSettingsNativeSaveAndReloadOff"] = !off.bathEnabled && !d.settings.bathEnabled && off.hoverDelay==0.37 && off.pointerFollowEnabled
        w.bathButton.performClick(nil);w.placeBathButton.performClick(nil)
        checks["bathSettingsPlaceUsesSavedSwitch"]=w.draft.bathEnabled && !d.engine.hasBathPlacement && d.engine.events.last?.reason == .disabled
        w.previewBathButton.performClick(nil)
        checks["bathSettingsPreviewUsesSavedSwitch"]=d.engine.events.last?.reason == .disabled && d.birds.isEmpty
        w.save();let savedBytes=try Data(contentsOf:d.settingsURL),draftPerches=w.draft.fixedPerches
        w.placeBathButton.performClick(nil)
        checks["bathSettingsNativePlacementUsesEngineClock"]=d.engine.hasBathPlacement && !w.placeBathButton.isEnabled && w.cancelBathPlacementButton.isEnabled
        world(d.engine,point:CGPoint(x:650,y:400));advance(d.engine,1)
        d.paused=true;advance(d.engine,5)
        checks["bathSettingsPendingFreezesWhilePaused"]=d.engine.hasBathPlacement && d.engine.habitatSnapshot().isEmpty
        d.paused=false;world(d.engine,point:target);advance(d.engine,1.9)
        checks["bathSettingsNoEarlyPlacement"]=d.engine.hasBathPlacement && d.engine.habitatSnapshot().isEmpty
        advance(d.engine,0.2);d.consumeBehaviorEvents();w.refreshBathControls()
        let bath=d.engine.habitatSnapshot().first
        checks["bathSettingsLatestPointerFullCanvasAndMetadata"]=bath?.kind == .bath && bath?.rect==BathGeometry.rect(foot:target,scale:1) &&
            bath?.remainingUses==3 && (bath?.remainingLifetime ?? 0)>299 && !d.engine.hasBathPlacement && d.birds.isEmpty
        let lifetime=bath?.remainingLifetime
        d.paused=true;advance(d.engine,4);w.refreshBathControls()
        checks["bathSettingsLifetimeFreezeAndStatus"]=lifetime != nil && d.engine.habitatSnapshot().first?.remainingLifetime==lifetime && w.bathStatus.stringValue.contains("3 / 3")
        d.paused=false
        world(d.engine,point:target)
        let duplicate=d.engine.handle(.placeFoodTray(at:target))
        checks["bathSettingsTrayCannotReplaceBath"]=duplicate == .rejected(.busy) && d.engine.habitatSnapshot().first?.id==bath?.id
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();scroll(w)
            w.message.stringValue=w.bathMessage(.busy,placing:true)
            checks["bathSettingsBusyExplainsClear-"+language.rawValue]=w.message.stringValue==language.sceneBusyMessage && EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            try SettingsVerification.snapshot(w.window!,to:output.appendingPathComponent("bath-placed-"+language.rawValue+".png"))
            evidence.append(["language":language.rawValue,"message":w.message.stringValue,"status":w.bathStatus.stringValue])
        }
        w.clearCurrentSceneButton.performClick(nil);advance(d.engine,2.1)
        checks["bathSettingsClearRemovesObjectWithoutPerchDraftChange"]=d.engine.habitatSnapshot().isEmpty && !d.engine.hasBathPlacement && w.draft.fixedPerches==draftPerches
        world(d.engine,point:target)
        let tray=d.engine.handle(.placeFoodTray(at:target)),trayID=d.engine.habitatSnapshot().first?.id
        w.refreshBathControls();w.refreshFoodTrayControls()
        let rejected=d.engine.handle(.placeBath(at:target))
        checks["bathSettingsBathCannotReplaceTray"]=tray.accepted && rejected == .rejected(.busy) && d.engine.habitatSnapshot().first?.id==trayID
        w.removeBathButton.performClick(nil)
        checks["bathSettingsRemoveBathKeepsTray"]=d.engine.habitatSnapshot().first?.id==trayID
        w.clearCurrentSceneButton.performClick(nil);advance(d.engine,2.1)
        let closing:[(String,()->Void)]=[("save",{w.save()}),("reset",{w.resetDefaults()}),("close",{w.window?.performClose(nil)}),("cancel",{w.cancel()})]
        for (name,action) in closing {
            w.showWindow(nil);w.placeBathButton.performClick(nil)
            checks["bathSettingsCloseLifecycleArmed-"+name]=d.engine.hasBathPlacement
            action();world(d.engine,point:target);advance(d.engine,3.2)
            checks["bathSettingsCloseLifecycleCancels-"+name] = !d.engine.hasBathPlacement && d.engine.habitatSnapshot().isEmpty
        }
        // Only settings saves above may write; placement never adds position keys.
        let json=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as! [String:Any]
        checks["bathSettingsOnlyBooleanIsPersisted"]=json.keys.filter{$0.lowercased().contains("bath")}==["bathEnabled"] && !savedBytes.isEmpty
        checks["bathSettingsIsolation"]=d.timer==nil && d.globalMouseMonitor==nil && d.localMouseMonitor==nil &&
            d.birds.isEmpty && d.panels.isEmpty && d.views.isEmpty && !d.engine.hasBathPlacement &&
            !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path) && !FileManager.default.fileExists(atPath:d.observationJournalURL.path)
        checks["bathSettingsCompleted"]=true
    }
    private static func world(_ engine:BehaviorEngine,point:CGPoint) {
        engine.updateWorld(BehaviorWorld(screens:[display],displays:[display],scale:1,pointer:point,
            foodTrayArtAvailable:HabitatObjectRenderer.foodTrayArtAvailable,bathArtAvailable:HabitatObjectRenderer.bathArtAvailable))
    }
    private static func advance(_ engine:BehaviorEngine,_ seconds:Double) {for _ in 0..<Int((seconds*60).rounded()) {engine.advance(1.0/60)}}
    private static func scroll(_ w:SpeciesSettingsWindow) {
        w.tabs.selectTabViewItem(at:2)
        guard let view=w.tabs.tabViewItems[2].view as? NSScrollView else {return}
        view.contentView.scroll(to:CGPoint(x:0,y:5250));view.reflectScrolledClipView(view.contentView)
        w.window?.contentView?.layoutSubtreeIfNeeded()
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"BathSettingsVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
