import AppKit
import BirdingCore

enum CourtshipSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("courtship-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("courtshipSettings")}],to:output.appendingPathComponent("report.json"))}
        try autoreleasepool {
            let f=try CourtshipVerification.Fixture(folder:output);defer {f.close()}
            try controls(f,into:&checks,folder:output)
        }
        // Drain hosted AppKit/SwiftUI controls before building the journal.
        try autoreleasepool {try journal(into:&checks,folder:output)}
    }
    private static func controls(_ f:CourtshipVerification.Fixture,into checks:inout [String:Bool],folder:URL) throws {
        let d=f.d,defaults=BirdSettings()
        checks["courtshipSettingsDefaultEnabledWithoutWriting"]=defaults.courtshipEnabled && defaults.socialInteractions &&
            !FileManager.default.fileExists(atPath:d.settingsURL.path)
        var old=try JSONSerialization.jsonObject(with:JSONEncoder().encode(defaults)) as! [String:Any]
        old.removeValue(forKey:"courtshipEnabled");old["hoverDelay"]=0.37;old["socialInteractions"]=false
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:old))
        checks["courtshipSettingsMissingFieldDefaultsWithoutLosingExistingValues"]=migrated.courtshipEnabled &&
            !migrated.socialInteractions && migrated.hoverDelay==0.37 && migrated.probabilities==defaults.probabilities
        autoreleasepool {
            let cancelled=SpeciesSettingsWindow(desktop:d);cancelled.showWindow(nil)
            cancelled.courtshipButton.performClick(nil);cancelled.cancel()
            checks["courtshipSettingsCancelDoesNotApplyOrWrite"] = !cancelled.draft.courtshipEnabled && d.settings.courtshipEnabled &&
                cancelled.window?.isVisible==false && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        }
        let w=f.controls;w.showWindow(nil)
        checks["courtshipSettingsReopenDiscardsCancelledDraft"]=w.draft.courtshipEnabled && w.courtshipButton.state == .on
        w.hoverDelayField.stringValue="0.25";w.detailFields[0][2].stringValue="1.25"
        for child in [false,true] {
            configure(w,master:true,child:child);set(w.socialInteractionsButton,false)
            w.courtshipButton.performClick(nil);w.relocalize()
            checks["courtshipSettingsMasterRetainsPreference-\(child)"] = !w.courtshipButton.isEnabled &&
                w.draft.courtshipEnabled==child && w.courtshipButton.state==(child ? .on:.off) && w.previewCourtshipButton.isEnabled
            set(w.socialInteractionsButton,true)
        }
        for (master,child) in [(false,true),(true,false),(false,false),(true,true)] {
            configure(w,master:master,child:child);w.save()
            let saved=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
            let expected=try canonical(w.draft),active=try canonical(d.settings),stored=try canonical(saved)
            checks["courtshipSettingsSaveApplyReopen-\(master)-\(child)"]=saved.courtshipEnabled==child &&
                saved.socialInteractions==master && expected==active && active==stored &&
                saved.hoverDelay==0.25 && saved.catalog.species[0].speed==1.25
        }
        configure(w,master:true,child:true);w.courtshipButton.state = .off;w.save()
        checks["courtshipSettingsSaveReadsNativeCheckbox"] = !d.settings.courtshipEnabled && !w.draft.courtshipEnabled
        set(w.courtshipButton,true)
        let url=d.settingsURL,bytes=try Data(contentsOf:url),before=try canonical(d.settings)
        d.settingsURL=folder;w.save();d.settingsURL=url
        let after=try canonical(d.settings),afterBytes=try Data(contentsOf:url)
        checks["courtshipSettingsFailedSaveRetainsActiveFileAndDraft"]=before==after && bytes==afterBytes &&
            w.draft.courtshipEnabled && !d.settings.courtshipEnabled &&
            w.message.stringValue==w.t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.")
        for language:AppLanguage in [.chinese,.english] {
            var savedOff=d.settings;savedOff.courtshipEnabled=false;d.settings=savedOff
            configure(w,master:true,child:true)
            d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
            let key="courtshipSettings-"+language.rawValue+"-"
            checks[key+"LanguageKeepsUnsavedDraft"]=w.draft.courtshipEnabled && !d.settings.courtshipEnabled &&
                w.hoverDelayField.stringValue=="0.25" && w.detailFields[0][2].stringValue=="1.25"
            try layout(w,key:key,into:&checks,folder:folder)
            for reason:BehaviorReason in [.disabled,.settingsChanged,.paused,.noSpecies,.noCompanion,.missingBird,
                .unavailableBird,.noSpace,.targetInvalid,.missingFrames,.pointerNearby,.busy,.userInput] {
                w.message.stringValue=w.courtshipPreviewMessage(reason)
                checks[key+"MessageFits-"+reason.rawValue]=EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            }
            try gates(f,key:key,into:&checks)
        }
        configure(w,master:true,child:false);w.save();let savedBytes=try Data(contentsOf:url)
        w.resetDefaults()
        let resetBytes=try Data(contentsOf:url)
        checks["courtshipSettingsRestoreDefaultsOnlyEditsDraft"]=w.draft.courtshipEnabled &&
            w.courtshipButton.state == .on && !d.settings.courtshipEnabled && resetBytes==savedBytes
        w.save()
        let restored=try BirdSettings.load(from:url,legacyURL:d.legacyURL)
        checks["courtshipSettingsDefaultsSaveAndApply"]=restored.courtshipEnabled && restored.socialInteractions &&
            d.settings.courtshipEnabled && d.settings.socialInteractions
        d.birds=[];d.surfaces=[]
        checks["courtshipSettingsNoStartupOrUnrelatedPersistence"]=d.timer==nil && d.status==nil &&
            d.globalMouseMonitor==nil && d.localMouseMonitor==nil && d.panels.isEmpty && d.views.isEmpty &&
            d.visitorMemoryPersistence==nil && d.observationPersistence==nil && d.giftLedgerPersistence==nil &&
            [d.visitorMemoryURL,d.observationJournalURL,d.giftLedgerURL].allSatisfy{!FileManager.default.fileExists(atPath:$0.path)}
    }
    private static func gates(_ f:CourtshipVerification.Fixture,key:String,into checks:inout [String:Bool]) throws {
        let d=f.d,w=f.controls
        func rejected(_ name:String,_ reason:BehaviorReason) {
            let seq=d.engine.events.last?.sequence ?? 0,archive=d.observationJournal.archive
            let birds=d.birds,feet=birds.map(\.position),revisions=birds.map(\.motionRevision),probability=d.settings.probabilities
            w.previewCourtshipButton.performClick(nil)
            let event=d.engine.events.last
            checks[key+"Rejection-"+name]=(event?.sequence ?? 0)>seq && event?.kind == .courtshipDisplay &&
                event?.source == .preview && event?.type == .rejected && event?.reason==reason &&
                w.message.stringValue==w.courtshipPreviewMessage(reason) && EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            checks[key+"RejectionPreservesResidents-"+name]=d.birds.count==birds.count && zip(d.birds,birds).allSatisfy{$0.0 === $0.1} &&
                birds.map(\.position)==feet && birds.map(\.motionRevision)==revisions && d.settings.probabilities==probability &&
                d.observationJournal.archive==archive && CourtshipVerification.clear(d.engine)
        }
        try f.install(count:0);rejected("empty",.noCompanion)
        try f.install(count:1);rejected("one-resident",.noCompanion)
        try f.install(species:.treeSparrow);rejected("unsupported-existing-pair",.noCompanion)
        try f.install()
        var v=d.settings
        guard let index=v.probabilities.entries.firstIndex(where:{$0.id == .spottedDove}) else {throw failure("No dove probability")}
        v.probabilities.setManualWeight(at:index,to:0);d.settings=v
        rejected("saved-zero-probability",.noSpecies)
        try f.install();d.paused=true;rejected("paused",.paused);d.paused=false
        try f.install();v=d.settings;v.courtshipEnabled=false;d.settings=v
        configure(w,master:true,child:true);rejected("saved-child-off-draft-on",.disabled)
        try f.install();v=d.settings;v.socialInteractions=false;d.settings=v
        configure(w,master:true,child:true);rejected("saved-master-off-draft-on",.disabled)
        try f.install();d.frameCapabilities[.spottedDove]?.remove("courtBow0")
        rejected("missing-dedicated-frame",.missingFrames)
        try f.install();v=d.settings;v.activityRhythm = .quiet;d.settings=v
        configure(w,master:false,child:false)
        let originalIDs=f.ids,feet=f.origins,prior=CourtshipVerification.entry(d),beforeCount=prior?.previewCount ?? 0
        guard let run=f.start() else {checks[key+"SavedOnPreviewInQuietWithoutAddingBirds"]=false;return}
        checks[key+"SavedOnPreviewInQuietWithoutAddingBirds"] = !w.draft.courtshipEnabled && !w.draft.socialInteractions &&
            d.settings.courtshipEnabled && d.settings.socialInteractions && d.settings.activityRhythm == .quiet &&
            d.birds.count==2 && f.birds.compactMap{d.engine.id(of:$0)}==originalIDs && f.birds.map(\.position)==feet
        let sequence=d.engine.events.last?.sequence ?? 0
        w.previewCourtshipButton.performClick(nil)
        checks[key+"BusyPreviewKeepsExistingPair"]=d.engine.events.last?.reason == .busy &&
            (d.engine.events.last?.sequence ?? 0)>sequence && d.engine.activeRunCount==1 && d.engine.leasedBirdCount==2 &&
            d.birds.count==2 && f.birds.map(\.position)==feet && CourtshipVerification.entry(d)==prior
        f.advance(4.1)
        let ends=d.engine.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}
        checks[key+"NativePreviewFinishesOnceAndRestoresBoth"]=ends.count==1 && ends.first?.type == .completed &&
            f.birds.map(\.position)==feet && f.birds.allSatisfy{$0.state == .perched} && CourtshipVerification.clear(d.engine) &&
            CourtshipVerification.entry(d)?.previewCount==beforeCount+1
    }
    private static func layout(_ w:SpeciesSettingsWindow,key:String,into checks:inout [String:Bool],folder:URL) throws {
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let doc=scroll.documentView else {throw failure("Missing settings scroll")}
        func label(_ id:String)->NSTextField? {doc.subviews.compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue==id}}
        guard let heading=label("courtshipSectionTitle"),let help=label("courtshipHelp"),let preview=label("courtshipPreviewHelp") else {throw failure("Missing courtship labels")}
        scroll.contentView.scroll(to:CGPoint(x:0,y:min(heading.frame.minY-12,max(0,doc.bounds.height-scroll.contentView.bounds.height))))
        scroll.reflectScrolledClipView(scroll.contentView);w.window?.contentView?.layoutSubtreeIfNeeded()
        let views:[NSView]=[heading,w.courtshipButton,help,w.previewCourtshipButton,preview]
        let visible=views.allSatisfy{!$0.isHidden && doc.visibleRect.contains($0.frame)}
        let buttons:[NSButton]=[w.courtshipButton,w.previewCourtshipButton]
        let accessible=buttons.allSatisfy {button in
            let wired=button.action != nil && button.target === w
            let labeled=button.accessibilityLabel()==button.title
            let fits=button.intrinsicContentSize.width<=button.frame.width
            return wired && labeled && fits
        }
        let enabled=w.courtshipButton.isEnabled==w.draft.socialInteractions && w.previewCourtshipButton.isEnabled
        checks[key+"BilingualControlsAccessibleAndReachable"]=visible && accessible && enabled
        checks[key+"SingleSourceSpeciesAndNoPairPromise"]=help.stringValue.contains(w.language.courtshipSupport) &&
            preview.stringValue.contains(w.language.courtshipRequirement) &&
            help.stringValue.contains(w.t("不推断性别、永久配偶或繁殖成功","no sex, permanent pairing or breeding success"))
        let noOverlaps=doc.subviews.enumerated().allSatisfy {i,view in
            doc.bounds.contains(view.frame) && doc.subviews.dropFirst(i+1).allSatisfy{!view.frame.intersects($0.frame)}
        }
        let wrappingValid=[help,preview].allSatisfy { field in
            let bounds=CGRect(x:0,y:0,width:field.frame.width,height:10000)
            let height:CGFloat=field.cell?.cellSize(forBounds:bounds).height ?? .infinity
            return field.cell?.wraps==true && field.cell?.usesSingleLineMode==false && height<=field.frame.height
        }
        checks[key+"RealWrappingAndNoOverlaps"]=noOverlaps && wrappingValid
        try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("courtship-controls-"+w.language.rawValue+".png"))
    }
    private static func journal(into checks:inout [String:Bool],folder:URL) throws {
        let f=try CourtshipVerification.Fixture(folder:folder);defer {f.close()}
        let d=f.d,date=Date(timeIntervalSince1970:1_700_000_000)
        try d.observationJournal.restore(ObservationArchive(entries:[ObservationEntry(species:.spottedDove,
            behavior:"courtshipDisplay",firstSeen:date,lastSeen:date,automaticCount:1,previewCount:2,userCount:1)]))
        let w=ObservationJournalWindow(desktop:d);w.showWindow(nil);defer {w.close()}
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.searchField.stringValue="courtshipDisplay";w.refresh()
            let key="courtshipSettingsJournal-"+language.rawValue
            checks[key]=w.renderedEntries.count==1 && w.behaviorName("courtshipDisplay")==language.text("求偶展示","Courtship Display") &&
                w.renderedEntries.first?.automaticCount==1 && w.renderedEntries.first?.previewCount==2 && w.renderedEntries.first?.userCount==1
            for filter in [ObservationJournalWindow.SourceFilter.natural,.preview,.manual] {
                w.sourceFilter.selectedSegment=filter.rawValue;w.refresh()
                checks[key+"-"+String(filter.rawValue)]=w.renderedEntries.count==1
            }
            w.sourceFilter.selectedSegment=ObservationJournalWindow.SourceFilter.all.rawValue;w.refresh()
            try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("courtship-journal-"+language.rawValue+".png"))
        }
        let bytes=try JSONEncoder().encode(d.observationJournal.archive)
        let decoded=try ObservationArchive.decode(bytes)
        checks["courtshipSettingsJournalRoundTripKeepsIndependentSources"]=decoded==d.observationJournal.archive
        var future=try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
        future["formatVersion"]=ObservationArchive.currentVersion+1
        do {_=try ObservationArchive.decode(JSONSerialization.data(withJSONObject:future));checks["courtshipSettingsJournalFutureVersionProtected"]=false}
        catch {checks["courtshipSettingsJournalFutureVersionProtected"]=true}
    }
    private static func configure(_ w:SpeciesSettingsWindow,master:Bool,child:Bool) {
        set(w.socialInteractionsButton,true);set(w.courtshipButton,child);set(w.socialInteractionsButton,master)
    }
    private static func set(_ button:NSButton,_ enabled:Bool) {if (button.state == .on) != enabled {button.performClick(nil)}}
    private static func canonical(_ settings:BirdSettings) throws -> Data {
        let value=settings
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys;return try encoder.encode(value)
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"CourtshipSettingsVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
