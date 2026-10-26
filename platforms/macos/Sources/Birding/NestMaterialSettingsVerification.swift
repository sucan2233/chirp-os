import AppKit
import BirdingCore

enum NestMaterialSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("nest-material-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var completed=false
        defer {NestMaterialVerification.report(checks,evidence:[],prefix:"nestMaterialSettings",folder:output,completed:completed)}
        try autoreleasepool {
            let f=try NestMaterialVerification.Fixture(folder:output);defer {f.close()}
            try controls(f,into:&checks,folder:output)
        }
        // Release native controls before constructing the journal's view graph.
        try autoreleasepool {try journal(kind:.nestMaterialCarry,prefix:"nestMaterialSettings",into:&checks,folder:output)}
        completed=true
    }
    private static func controls(_ f:NestMaterialVerification.Fixture,into checks:inout [String:Bool],folder:URL) throws {
        let d=f.d,defaults=BirdSettings()
        checks["nestMaterialSettingsDefaultEnabled"]=defaults.nestBuildingEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        var old=try JSONSerialization.jsonObject(with:JSONEncoder().encode(defaults)) as! [String:Any]
        old.removeValue(forKey:"nestBuildingEnabled");old["socialInteractions"]=false;old["hoverDelay"]=0.37
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:old))
        checks["nestMaterialSettingsMissingFieldDefaultsWithoutLosingDrafts"]=migrated.nestBuildingEnabled &&
            !migrated.socialInteractions && migrated.hoverDelay==0.37 && migrated.probabilities==defaults.probabilities
        autoreleasepool {
            let cancelled=SpeciesSettingsWindow(desktop:d);cancelled.showWindow(nil)
            cancelled.nestBuildingButton.performClick(nil);cancelled.cancel()
            checks["nestMaterialSettingsCancelDoesNotApplyOrWrite"] = !cancelled.draft.nestBuildingEnabled && d.settings.nestBuildingEnabled &&
                cancelled.window?.isVisible==false && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        }
        let w=f.controls;w.showWindow(nil)
        w.hoverDelayField.stringValue="0.25";w.detailFields[0][2].stringValue="1.25"
        checks["nestMaterialSettingsReopenDiscardsCancelledDraft"]=w.draft.nestBuildingEnabled && w.nestBuildingButton.state == .on
        for social in [false,true] {for enabled in [false,true] {
            set(w.socialInteractionsButton,social);set(w.nestBuildingButton,enabled);w.save()
            let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
            checks["nestMaterialSettingsSaveIndependentOfSocial-\(social)-\(enabled)"]=saved.nestBuildingEnabled==enabled &&
                d.settings.nestBuildingEnabled==enabled && saved.socialInteractions==social && w.nestBuildingButton.isEnabled &&
                saved.hoverDelay==0.25 && saved.catalog.species[0].speed==1.25
        }}
        w.nestBuildingButton.state = .off;w.save()
        checks["nestMaterialSettingsSaveReadsNativeCheckbox"] = !w.draft.nestBuildingEnabled && !d.settings.nestBuildingEnabled
        set(w.nestBuildingButton,true)
        let url=d.settingsURL,bytes=try Data(contentsOf:url),active=try canonical(d.settings)
        d.settingsURL=folder;w.save();d.settingsURL=url
        let after=try canonical(d.settings),stored=try Data(contentsOf:url)
        checks["nestMaterialSettingsFailedSavePreservesFileActiveAndDraft"]=bytes==stored && active==after &&
            w.draft.nestBuildingEnabled && !d.settings.nestBuildingEnabled
        for language:AppLanguage in [.chinese,.english] {
            set(w.nestBuildingButton,true)
            var saved=d.settings;saved.nestBuildingEnabled=false;d.settings=saved
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let key="nestMaterialSettings-"+language.rawValue+"-"
            checks[key+"LanguageKeepsUnrelatedEdits"]=w.hoverDelayField.stringValue=="0.25" &&
                w.detailFields[0][2].stringValue=="1.25" && w.draft.nestBuildingEnabled && !d.settings.nestBuildingEnabled
            try layout(w,prefix:key,into:&checks,folder:folder)
            for reason:BehaviorReason in [.paused,.disabled,.settingsChanged,.userInput,.busy,.noSpecies,.noCompanion,
                .missingBird,.unavailableBird,.missingFrames,.noSpace,.targetInvalid,.removed,.pointerNearby,.pointerMoved,.timedOut] {
                w.message.stringValue=w.nestMessage(reason)
                checks[key+"RejectionMessageFits-"+reason.rawValue]=EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            }
            try f.install();try f.place()
            var value=d.settings;value.nestBuildingEnabled=false;d.settings=value
            rejection(f,build:false,reason:.disabled,key:key+"SavedOffDraftOn",into:&checks)
            try f.install();try f.place();d.paused=true
            rejection(f,build:false,reason:.paused,key:key+"Paused",into:&checks);d.paused=false
            try f.install();try f.place();d.birds=[]
            rejection(f,build:false,reason:.noSpecies,key:key+"NoResident",into:&checks)
            try f.install();try f.place()
            value=d.settings
            if let i=value.probabilities.entries.firstIndex(where:{$0.id == .spottedDove}) {value.probabilities.setManualWeight(at:i,to:0)}
            d.settings=value;rejection(f,build:false,reason:.noSpecies,key:key+"ProbabilityZero",into:&checks)
            try f.install();try f.place();d.frameCapabilities[.spottedDove]?.remove("carryGrip")
            rejection(f,build:false,reason:.missingFrames,key:key+"MissingFrame",into:&checks)
            try f.install();try f.place()
            set(w.nestBuildingButton,false);set(w.socialInteractionsButton,false)
            let before=d.observationJournal.archive,ids=d.birds.compactMap{d.engine.id(of:$0)}
            guard let run=f.start(.nestMaterialCarry) else {checks[key+"SavedOnDraftOffRealPreview"]=false;continue}
            checks[key+"SavedOnDraftOffRealPreview"] = !w.draft.nestBuildingEnabled && !w.draft.socialInteractions &&
                d.settings.nestBuildingEnabled && !d.settings.socialInteractions && d.birds.compactMap{d.engine.id(of:$0)}==ids &&
                d.engine.nestSnapshot().first?.materials.count==3 && d.observationJournal.archive==before
            rejection(f,build:false,reason:.busy,key:key+"BusyKeepsRun",into:&checks)
            d.engine.handle(.cancelAmbient(.shutdown));f.advance(0.25)
            checks[key+"CancelledPreviewNoCredit"]=NestMaterialVerification.terminal(d.engine,run).first?.type != .completed && d.observationJournal.archive==before
        }
        try f.install();w.showWindow(nil);set(w.nestBuildingButton,true)
        w.placeNestButton.performClick(nil)
        checks["nestMaterialSettingsProductionPendingCommand"]=d.engine.hasNestPlacement && d.engine.nestSnapshot().isEmpty
        f.advance(2.9)
        checks["nestMaterialSettingsNoEarlyPlacement"]=d.engine.hasNestPlacement && d.engine.nestSnapshot().isEmpty
        d.paused=true;f.advance(1)
        checks["nestMaterialSettingsPendingPauseFreezes"]=d.engine.hasNestPlacement && d.engine.nestSnapshot().isEmpty
        d.paused=false
        // The public world-input boundary samples a legal real host point at
        // the deadline. It never moves or posts input to the system pointer.
        for _ in 0..<18 {d.syncWorld(at:f.target,buttonsDown:false);d.engine.advance(1.0/120)}
        d.consumeBehaviorEvents();w.refreshNestControls()
        checks["nestMaterialSettingsDelayedPlacementSamplesLatestHostPoint"] = !d.engine.hasNestPlacement &&
            d.engine.nestSnapshot().first?.materials.count==3 && d.engine.nestSnapshot().first?.parentAnchor.hostID==f.host.id
        let nest=d.engine.nestSnapshot().first
        d.paused=true;f.advance(1)
        checks["nestMaterialSettingsPlacedScenePauseFreezes"]=nest != nil && d.engine.nestSnapshot().first==nest
        w.clearNestSceneButton.performClick(nil);d.paused=false;f.advance(3)
        checks["nestMaterialSettingsPausedClearReleasesScene"]=NestMaterialVerification.clear(d.engine)
        for action in ["cancel","save","language","window-close","draft-off"] {
            try f.install();w.showWindow(nil);set(w.nestBuildingButton,true);w.placeNestButton.performClick(nil)
            let pending=d.engine.hasNestPlacement
            switch action {
            case "cancel":w.cancelNestPlacementButton.performClick(nil)
            case "save":w.save()
            case "language":w.relocalize()
            case "window-close":w.window?.close()
            default:set(w.nestBuildingButton,false)
            }
            checks["nestMaterialSettingsPendingLifecycle-"+action]=pending && !d.engine.hasNestPlacement && d.engine.nestSnapshot().isEmpty
        }
        set(w.nestBuildingButton,false);w.save();let beforeReset=try Data(contentsOf:url)
        w.resetDefaults();let afterReset=try Data(contentsOf:url)
        checks["nestMaterialSettingsRestoreDefaultsOnlyEditsDraft"]=w.draft.nestBuildingEnabled && !d.settings.nestBuildingEnabled && beforeReset==afterReset
        checks["nestMaterialSettingsNoUnrelatedPersistenceOrStartup"]=f.isolated
    }
    static func rejection(_ f:NestMaterialVerification.Fixture,build:Bool,reason:BehaviorReason,key:String,into checks:inout [String:Bool]) {
        let d=f.d,w=f.controls,kind:BehaviorKind=build ? .nestBuild:.nestMaterialCarry
        let sequence=d.engine.events.last?.sequence ?? 0,archive=d.observationJournal.archive,ids=d.birds.compactMap{d.engine.id(of:$0)},nest=d.engine.nestSnapshot()
        if build {w.previewNestBuildButton.performClick(nil)} else {w.previewNestMaterialButton.performClick(nil)}
        let event=d.engine.events.last
        checks[key]=event?.kind==kind && event?.type == .rejected && event?.source == .preview && event?.reason==reason &&
            (event?.sequence ?? 0)>sequence && w.message.stringValue==w.nestMessage(reason,build:build) &&
            d.birds.compactMap{d.engine.id(of:$0)}==ids && d.engine.nestSnapshot()==nest && d.observationJournal.archive==archive
    }
    static func layout(_ w:SpeciesSettingsWindow,prefix:String,into checks:inout [String:Bool],folder:URL) throws {
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let doc=scroll.documentView,
              let help=doc.subviews.compactMap({$0 as? NSTextField}).first(where:{$0.identifier?.rawValue=="nestHelp"}) else {throw NestMaterialVerification.failure("Missing nest controls")}
        let controls=[w.nestBuildingButton!,w.placeNestButton!,w.cancelNestPlacementButton!,w.removeNestButton!,w.clearNestSceneButton!,w.previewNestMaterialButton!,w.previewNestBuildButton!]
        scroll.contentView.scroll(to:CGPoint(x:0,y:7990));scroll.reflectScrolledClipView(scroll.contentView)
        checks[prefix+"AllNativeControlsReachableAccessibleAndWired"]=controls.allSatisfy {
            doc.visibleRect.contains($0.frame) && $0.action != nil && $0.target === w && $0.accessibilityLabel()==$0.title && $0.intrinsicContentSize.width<=$0.frame.width
        } && w.nestBuildingButton.isEnabled
        checks[prefix+"HelpSingleSourceNoPairEggOrReplenishmentPromise"]=help.stringValue.contains(w.language.nestSupport) &&
            help.stringValue.contains(w.t("不推断性别、配偶或蛋","No sex, mate or egg")) &&
            help.stringValue.contains(w.t("固定三根","Exactly three"))
        checks[prefix+"WrapsAndNoControlOverlaps"]=help.cell?.wraps==true && help.cell?.usesSingleLineMode==false &&
            (help.cell?.cellSize(forBounds:CGRect(x:0,y:0,width:help.frame.width,height:10000)).height ?? .infinity)<=help.frame.height &&
            doc.subviews.enumerated().allSatisfy{i,view in doc.bounds.contains(view.frame) && doc.subviews.dropFirst(i+1).allSatisfy{!view.frame.intersects($0.frame)}}
        try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("nest-controls-"+w.language.rawValue+".png"))
        scroll.contentView.scroll(to:CGPoint(x:0,y:doc.bounds.height-scroll.contentView.bounds.height));scroll.reflectScrolledClipView(scroll.contentView)
        checks[prefix+"StatusReachableAndWraps"]=doc.visibleRect.contains(w.nestStatus.frame) &&
            EdgePeekSettingsVerification.messageIsFullyVisible(w.nestStatus)
        try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("nest-status-"+w.language.rawValue+".png"))
    }
    static func journal(kind:BehaviorKind,prefix:String,into checks:inout [String:Bool],folder:URL) throws {
        let f=try NestMaterialVerification.Fixture(folder:folder);defer {f.close()}
        let d=f.d,date=Date(timeIntervalSince1970:1_700_000_000)
        try d.observationJournal.restore(ObservationArchive(entries:[ObservationEntry(species:.spottedDove,behavior:kind.rawValue,
            firstSeen:date,lastSeen:date,automaticCount:1,previewCount:2,userCount:1)]))
        let w=ObservationJournalWindow(desktop:d);w.showWindow(nil);defer {w.close()}
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.searchField.stringValue=kind.rawValue;w.refresh()
            let name=kind == .nestBuild ? language.text("筑巢片段","Nest Building"):language.text("运送巢材","Nest Material Delivery")
            checks[prefix+"Journal-"+language.rawValue]=w.renderedEntries.count==1 && w.behaviorName(kind.rawValue)==name &&
                w.renderedEntries.first?.automaticCount==1 && w.renderedEntries.first?.previewCount==2 && w.renderedEntries.first?.userCount==1
            try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent(kind.rawValue+"-journal-"+language.rawValue+".png"))
        }
        let data=try JSONEncoder().encode(d.observationJournal.archive),roundTrip=try ObservationArchive.decode(data)
        checks[prefix+"JournalRoundTrip"]=roundTrip==d.observationJournal.archive
        var future=try JSONSerialization.jsonObject(with:data) as! [String:Any];future["formatVersion"]=ObservationArchive.currentVersion+1
        do {_=try ObservationArchive.decode(JSONSerialization.data(withJSONObject:future));checks[prefix+"JournalFutureProtected"]=false}
        catch {checks[prefix+"JournalFutureProtected"]=true}
    }
    static func set(_ button:NSButton,_ enabled:Bool) {if (button.state == .on) != enabled {button.performClick(nil)}}
    private static func canonical(_ settings:BirdSettings) throws -> Data {let e=JSONEncoder();e.outputFormatting = .sortedKeys;return try e.encode(settings)}
}
