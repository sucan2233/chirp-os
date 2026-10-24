import AppKit
import BirdingCore

/// Main registers this verifier. Native controls invoke the real commands;
/// files, preferences, host geometry and the simulation clock are isolated.
enum LeafCarrySettingsVerification {
    private static let host=Surface(id:7201,pid:42,rect:CGRect(x:180,y:420,width:1040,height:120))
    private static let target=CGPoint(x:800,y:420)
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("leaf-carry-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("leafCarrySettings")}],to:output.appendingPathComponent("report.json"))}
        let suite="Birding.LeafCarrySettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate preferences")}
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=DesktopController();d.preferences=preferences;d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false
        d.settingsURL=output.appendingPathComponent("settings.json");d.legacyURL=output.appendingPathComponent("legacy.json")
        d.visitorMemoryURL=output.appendingPathComponent("visitors.json");d.observationJournalURL=output.appendingPathComponent("journal.json")
        d.surfaces=[host];d.pointerButtonsDown={false}
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["leafCarrySettingsDefaultOnWithoutWriting"]=defaults.leafCarryEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(defaults)) as! [String:Any]
        legacy.removeValue(forKey:"leafCarryEnabled");legacy["hoverDelay"]=0.37;legacy["pointerFollowEnabled"]=true
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:legacy))
        checks["leafCarrySettingsMissingKeyPreservesExistingValues"]=migrated.leafCarryEnabled && migrated.hoverDelay==0.37 && migrated.pointerFollowEnabled
        d.settings=migrated
        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel();d.engine.handle(.cancelAmbient(.shutdown))}
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            let key="leafCarrySettings-"+language.rawValue+"-"
            let controls=[w.leafCarryButton!,w.placeCarryLeafButton!,w.cancelCarryLeafPlacementButton!,w.removeCarryLeafButton!,w.previewLeafCarryButton!]
            checks[key+"NativeAccessibleControls"]=controls.allSatisfy {
                $0.target === w && $0.action != nil && $0.identifier != nil && $0.accessibilityLabel()==$0.title &&
                $0.superview?.bounds.contains($0.frame)==true && $0.intrinsicContentSize.width<=$0.frame.width
            }
            guard let view=w.leafCarryButton.superview,let help=view.subviews.first(where:{$0.identifier?.rawValue=="leafCarryHelp"}) as? NSTextField else {throw failure("Missing leaf carry help")}
            checks[key+"ProfileAndSeparateDynamicLeafHelpFits"]=SpeciesBehaviorProfile.species(for:.leafCarry)==[.treeSparrow] &&
                help.stringValue.contains(language.leafCarrySupport) && help.stringValue.contains(language.text("动态落叶","moving Leaf play")) &&
                help.cell?.wraps==true && help.cell?.usesSingleLineMode==false &&
                (help.cell?.cellSize(forBounds:CGRect(x:0,y:0,width:help.frame.width,height:10000)).height ?? .infinity)<=help.frame.height
            w.leafCarryButton.performClick(nil)
            checks[key+"ToggleDraftOnly"] = !w.draft.leafCarryEnabled && d.settings.leafCarryEnabled
            w.leafCarryButton.performClick(nil)
            let actions:[(String,()->Void)]=[("cancel",{w.cancelCarryLeafPlacementButton.performClick(nil)}),
                ("remove",{w.removeCarryLeafButton.performClick(nil)}),("clear",{w.clearCurrentScene()}),
                ("language",{w.relocalize()}),("rebuild",{w.build()})]
            for (name,action) in actions {
                w.placeCarryLeafButton.performClick(nil)
                checks[key+"PlacementArmed-"+name]=d.engine.hasCarryLeafPlacement
                action();world(d,point:target);advance(d.engine,3.2)
                checks[key+"PlacementCancelled-"+name] = !d.engine.hasCarryLeafPlacement && leaves(d.engine).isEmpty
            }
            for reason:BehaviorReason in [.paused,.disabled,.settingsChanged,.busy,.missingFrames,.noSpecies,.noSpace,.targetInvalid,.pointerNearby,.unavailableBird,.userInput] {
                w.message.stringValue=w.leafCarryMessage(reason)
                checks[key+"ReasonFits-"+reason.rawValue]=EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            }
            for reason:BehaviorReason in [.busy,.noSpace] {
                w.message.stringValue=w.leafCarryMessage(reason,placing:true)
                checks[key+"PlacementReasonFits-"+reason.rawValue]=EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            }
            checks[key+"BusyDoesNotRequireClearingAllObjects"] = !w.leafCarryMessage(.busy,placing:true).contains(language.sceneBusyMessage)
            scroll(w)
            try SettingsVerification.snapshot(w.window!,to:output.appendingPathComponent("leaf-carry-controls-"+language.rawValue+".png"))
        }
        // Pending-placement cancellation must not refresh controls from the
        // draft before Save reads their native values.
        w.placeCarryLeafButton.performClick(nil)
        w.leafCarryButton.state = .off;w.hoverDelayField.stringValue="0.43"
        let details=w.detailFields[0][0].stringValue,perches=w.draft.fixedPerches
        w.cancelCarryLeafPlacementButton.performClick(nil)
        checks["leafCarrySettingsCancelPlacementKeepsUnsavedNativeValues"] = w.leafCarryButton.state == .off &&
            w.hoverDelayField.stringValue=="0.43" && w.detailFields[0][0].stringValue==details && w.draft.fixedPerches==perches
        w.save()
        let off=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["leafCarrySettingsSaveReloadOffPreservesDraft"] = !off.leafCarryEnabled && !d.settings.leafCarryEnabled &&
            off.hoverDelay==0.43 && off.pointerFollowEnabled && off.fixedPerches==perches
        w.leafCarryButton.performClick(nil);w.placeCarryLeafButton.performClick(nil)
        checks["leafCarrySettingsPlacementReadsSavedSwitch"]=w.draft.leafCarryEnabled && !d.engine.hasCarryLeafPlacement && d.engine.events.last?.reason == .disabled
        w.previewLeafCarryButton.performClick(nil)
        checks["leafCarrySettingsPreviewReadsSavedSwitch"]=d.engine.events.last?.reason == .disabled && d.birds.isEmpty
        w.save();w.placeCarryLeafButton.performClick(nil)
        let placementWorld=d.engine.world
        world(d,point:CGPoint(x:500,y:420))
        checks["leafCarrySettingsPointerSamplePreservesPlacementWorld"]=d.engine.hasCarryLeafPlacement &&
            d.engine.world.screens==placementWorld.screens && d.engine.world.displays==placementWorld.displays &&
            d.engine.world.displayIDs==placementWorld.displayIDs && d.engine.world.scale==placementWorld.scale
        advance(d.engine,1)
        d.paused=true;advance(d.engine,4)
        checks["leafCarrySettingsPendingPauseFreezes"]=d.engine.hasCarryLeafPlacement && leaves(d.engine).isEmpty
        d.paused=false;world(d,point:target);advance(d.engine,1.9)
        checks["leafCarrySettingsNoEarlyPlacement"]=d.engine.hasCarryLeafPlacement && leaves(d.engine).isEmpty
        advance(d.engine,0.2);d.consumeBehaviorEvents();w.refreshLeafCarryControls()
        let placed=leaves(d.engine).first
        checks["leafCarrySettingsProductionLatestPointerPlacement"]=placed != nil && !d.engine.hasCarryLeafPlacement &&
            placed?.size==16 && placed?.position==target && placed?.anchor==CGPoint(x:10.0/16,y:12.0/16) &&
            d.birds.isEmpty && w.removeCarryLeafButton.isEnabled
        let frozen=placed?.position
        d.paused=true;advance(d.engine,4)
        checks["leafCarrySettingsPlacedLeafFreezes"]=frozen != nil && leaves(d.engine).first?.position==frozen && leaves(d.engine).first?.opacity==placed?.opacity
        d.paused=false
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();scroll(w)
            try SettingsVerification.snapshot(w.window!,to:output.appendingPathComponent("leaf-carry-placed-"+language.rawValue+".png"))
        }
        w.removeCarryLeafButton.performClick(nil);world(d,point:target);advance(d.engine,0.3)
        checks["leafCarrySettingsClearRemovesLeaf"]=leaves(d.engine).isEmpty && !d.engine.hasCarryLeafPlacement && w.draft.fixedPerches==perches
        world(d,point:CGPoint(x:800,y:250))
        let airborne=d.engine.handle(.placeCarryLeaf(at:CGPoint(x:800,y:250)))
        checks["leafCarrySettingsOpenAirDoesNotSupportLeaf"]=airborne == .rejected(.noSpace) && leaves(d.engine).isEmpty
        let closing:[(String,()->Void)]=[("save",{w.save()}),("reset",{w.resetDefaults()}),
            ("close",{w.window?.performClose(nil)}),("cancel",{w.cancel()})]
        for (name,action) in closing {
            w.showWindow(nil);w.placeCarryLeafButton.performClick(nil)
            checks["leafCarrySettingsLifecycleArmed-"+name]=d.engine.hasCarryLeafPlacement
            action();world(d,point:target);advance(d.engine,3.2)
            checks["leafCarrySettingsLifecycleCancelled-"+name] = !d.engine.hasCarryLeafPlacement && leaves(d.engine).isEmpty
        }
        let reopened=SpeciesSettingsWindow(desktop:d)
        checks["leafCarrySettingsReopenUsesSavedValue"]=reopened.draft.leafCarryEnabled==d.settings.leafCarryEnabled &&
            reopened.leafCarryButton.state==(d.settings.leafCarryEnabled ? .on:.off)
        reopened.cancel()
        let json=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as! [String:Any]
        checks["leafCarrySettingsOnlyBooleanPersisted"]=json.keys.filter{$0.lowercased().contains("carry")}==["leafCarryEnabled"]
        try journal(d,into:&checks,folder:output)
        checks["leafCarrySettingsNoDesktopStartupOrPersistence"]=d.timer==nil && d.globalMouseMonitor==nil && d.localMouseMonitor==nil &&
            d.panels.isEmpty && d.views.isEmpty && !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path) &&
            !FileManager.default.fileExists(atPath:d.observationJournalURL.path)
    }
    private static func journal(_ d:DesktopController,into checks:inout [String:Bool],folder:URL) throws {
        let now=Date(timeIntervalSince1970:1_700_000_000)
        for (index,source) in [BehaviorSource.automatic,.preview,.user].enumerated() {
            _=d.observationJournal.observe(BehaviorObservation(sequence:UInt64(index+1),simulationTime:Double(index),
                kind:.leafCarry,source:source,species:[.treeSparrow],runID:UInt64(index+1)),at:now)
        }
        let w=ObservationJournalWindow(desktop:d);w.showWindow(nil);defer {w.window?.close()}
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.sourceFilter.selectedSegment=0
            for query in ["leafCarry","携带叶片","Leaf Carrying"] {
                w.searchField.stringValue=query;w.searchChanged(nil)
                checks["leafCarrySettingsJournalSearch-"+language.rawValue+"-"+query]=w.renderedEntries.count==1 &&
                    w.renderedEntries.first?.behavior=="leafCarry" && w.behaviorName("leafCarry")==language.text("携带叶片","Leaf Carrying")
            }
            let entry=w.renderedEntries.first
            checks["leafCarrySettingsJournalSourceCounts-"+language.rawValue]=entry?.automaticCount==1 && entry?.previewCount==1 && entry?.userCount==1
            try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("leaf-carry-journal-"+language.rawValue+".png"))
        }
    }
    private static func leaves(_ engine:BehaviorEngine)->[ScenePropRenderState] {engine.propSnapshot().filter{$0.kind == .leafToken}}
    private static func world(_ desktop:DesktopController,point:CGPoint) {
        // Native settings actions also call syncWorld. Keep the same screens,
        // displays, IDs, art capabilities and fixture host on both paths; only
        // the sampled pointer changes. A synthetic display switch correctly
        // cancels pending placement and cannot stand in for pointer movement.
        desktop.syncWorld(at:point,buttonsDown:false)
    }
    private static func advance(_ engine:BehaviorEngine,_ seconds:Double) {for _ in 0..<Int((seconds*120).rounded()) {engine.advance(1.0/120)}}
    private static func scroll(_ w:SpeciesSettingsWindow) {
        w.tabs.selectTabViewItem(at:2)
        guard let view=w.tabs.tabViewItems[2].view as? NSScrollView else {return}
        view.contentView.scroll(to:CGPoint(x:0,y:5830));view.reflectScrolledClipView(view.contentView)
        w.window?.contentView?.layoutSubtreeIfNeeded()
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"LeafCarrySettingsVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
