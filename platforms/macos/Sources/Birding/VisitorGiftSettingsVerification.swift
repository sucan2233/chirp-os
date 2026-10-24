import AppKit
import BirdingCore

/// Independent native controls and journal projection coverage. Successful
/// routes, pending authorization and delivery belong to the gift journey fixture;
/// this verifier never manufactures an active gift or opens a durable ledger.
enum VisitorGiftSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("visitor-gift-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("visitorGiftSettings")}],to:output.appendingPathComponent("report.json"))}
        let suite="Birding.VisitorGiftSettingsVerification."+UUID().uuidString
        guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate preferences")}
        defer {preferences.removePersistentDomain(forName:suite)}
        let d=DesktopController(verificationSeed:1971)
        d.preferences=preferences;d.automaticPopulation=false;d.pointerButtonsDown={false}
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false;d.giftLedgerPersistenceEnabled=false
        d.settingsURL=output.appendingPathComponent("settings.json");d.legacyURL=output.appendingPathComponent("legacy.json")
        d.visitorMemoryURL=output.appendingPathComponent("visitors.json")
        d.observationJournalURL=output.appendingPathComponent("journal.json");d.giftLedgerURL=output.appendingPathComponent("gifts.json")
        d.observationDate={Date(timeIntervalSince1970:1_700_000_000)}
        d.loadObservationJournal(now:0)
        defer {d.cancelGiftAuthorization();d.engine.handle(.cancelAmbient(.shutdown))}
        guard let work=d.screenRects.first,work.width>160 else {throw failure("Settings verification requires a display")}
        let host=Surface(id:7401,pid:42,rect:CGRect(x:work.minX+30,y:work.midY,width:work.width-60,height:100))
        d.surfaces=[host]
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["visitorGiftSettingsDefaultOffWithoutWriting"] = !defaults.visitorGiftsEnabled &&
            !FileManager.default.fileExists(atPath:d.settingsURL.path)
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(defaults)) as! [String:Any]
        legacy.removeValue(forKey:"visitorGiftsEnabled");legacy["hoverDelay"]=0.37;legacy["pointerFollowEnabled"]=true
        let legacyData=try JSONSerialization.data(withJSONObject:legacy)
        let decoded=try JSONDecoder().decode(BirdSettings.self,from:legacyData)
        let migrated=try BirdSettings.decode(legacyData)
        var expected=defaults;expected.hoverDelay=0.37;expected.pointerFollowEnabled=true
        // Codable preserves absent pendingSpecies as nil. The existing public
        // loader normalizes it to an ordered list, empty for a complete catalog.
        // Keep both full comparisons: gift migration must change no preference.
        var normalizedExpected=expected;normalizedExpected.pendingSpecies=[]
        let decodedData=try encoded(decoded),expectedData=try encoded(expected)
        let migratedData=try encoded(migrated),normalizedData=try encoded(normalizedExpected)
        checks["visitorGiftSettingsMissingKeyDefaultsOffPreservesExistingValues"] = !decoded.visitorGiftsEnabled &&
            !migrated.visitorGiftsEnabled && decoded.pendingSpecies==nil && migrated.pendingSpecies==[] &&
            decodedData==expectedData && migratedData==normalizedData
        var fixtureSettings=migrated
        fixtureSettings.perchActions=false;fixtureSettings.passiveAttentionEnabled=false
        d.settings=fixtureSettings
        let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.azureWingedMagpie),random:{0.5})
        bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;bird.tick(1.1)
        d.birds=[bird];d.syncWorld(buttonsDown:false)
        // Release the rebuilt settings controls before allocating journal UI.
        try autoreleasepool {try controls(d,bird:bird,settings:fixtureSettings,into:&checks,folder:output)}
        try autoreleasepool {try journal(d,into:&checks,folder:output)}
        d.flushObservationJournal()
        checks["visitorGiftSettingsNoUserPreferencesStartupOrDurableArchives"]=d.preferences === preferences &&
            preferences.persistentDomain(forName:suite)==nil && d.timer==nil && d.panels.isEmpty && d.views.isEmpty &&
            d.globalMouseMonitor==nil && d.localMouseMonitor==nil && !d.automaticPopulation &&
            !d.engine.populationEnabled && !d.engine.ambientEnabled && !d.engine.autonomousRouting &&
            d.visitorMemoryPersistence==nil && d.giftLedgerPersistence==nil && d.giftAuthorizationAttempt==nil &&
            d.observationPersistence?.enabled==false && d.observationPersistence?.successfulSaves==0 &&
            [d.visitorMemoryURL,d.observationJournalURL,d.giftLedgerURL].allSatisfy {
                !FileManager.default.fileExists(atPath:$0.path) && !FileManager.default.fileExists(atPath:$0.path+".lock")
            }
    }

    private static func controls(_ d:DesktopController,bird:Bird,settings fixtureSettings:BirdSettings,
                                 into checks:inout [String:Bool],folder:URL) throws {
        let origin=bird.position,revision=bird.motionRevision
        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel();d.settingsWindow=nil}
        let initialDetails=w.detailFields.map{$0.map(\.stringValue)}
        for language:AppLanguage in [.chinese,.english] {
            try d.applySettings(fixtureSettings);w.draft=fixtureSettings
            d.language=language;w.relocalize()
            // Relocalization deliberately preserves native edits. Reset only
            // this fixture's previous language pass before checking Save again.
            w.hoverDelayField.stringValue=String(fixtureSettings.hoverDelay)
            for i in initialDetails.indices {for j in initialDetails[i].indices {
                w.detailFields[i][j].stringValue=initialDetails[i][j]
            }}
            let key="visitorGiftSettings-"+language.rawValue+"-"
            let controls=[w.visitorGiftsButton!,w.previewVisitorGiftButton!,w.cancelVisitorGiftRequestButton!,w.clearVisitorGiftButton!]
            checks[key+"AccessibleNativeControls"]=controls.allSatisfy {
                $0.target === w && $0.action != nil && $0.identifier != nil && $0.accessibilityLabel()==$0.title &&
                $0.superview?.bounds.contains($0.frame)==true && $0.intrinsicContentSize.width<=$0.frame.width
            } && Set(controls.compactMap{$0.identifier?.rawValue})==Set([
                "visitorGiftsEnabled","previewVisitorGift","cancelVisitorGiftRequest","clearVisitorGift"])
            checks[key+"LocalizedTitlesAndIdleStatus"]=w.visitorGiftsButton.title==language.text("开启熟客虚拟礼物","Enable virtual visitor gifts") &&
                w.previewVisitorGiftButton.title==language.text("模拟礼物预览","Preview a simulated gift") &&
                w.clearVisitorGiftButton.title==language.text("清除礼物","Clear gift") &&
                w.cancelVisitorGiftRequestButton.title==language.text("取消待授权申请","Cancel pending authorization") &&
                w.visitorGiftStatus.stringValue==language.visitorGiftSupport && w.previewVisitorGiftButton.isEnabled &&
                !w.cancelVisitorGiftRequestButton.isEnabled && w.visitorGiftsButton.state == .off
            guard let view=w.visitorGiftsButton.superview,
                  let heading=view.subviews.first(where:{$0.identifier?.rawValue=="visitorGiftSectionTitle"}) as? NSTextField,
                  let help=view.subviews.first(where:{$0.identifier?.rawValue=="visitorGiftHelp"}) as? NSTextField else {throw failure("Missing gift section or help")}
            checks[key+"FictionalOffByDefaultAndPreviewOnlyHelp"]=SpeciesBehaviorProfile.species(for:.visitorGift)==[.azureWingedMagpie] &&
                help.stringValue.contains(language.visitorGiftSupport) && help.stringValue.contains(language.text("默认关闭","Off by default")) &&
                help.stringValue.contains(language.text("不代表野生鸟类会送礼","not a claim about wild birds")) &&
                help.stringValue.contains(language.text("仅记预览","count only as previews")) &&
                help.stringValue.contains("0.6") && help.stringValue.contains("120") && help.stringValue.contains("24")
            checks[key+"WrappedHelpAndStatusFit"]=fits(help) && fits(w.visitorGiftStatus)
            let section:[NSView]=controls.map{$0 as NSView}+[heading,help,w.visitorGiftStatus!]
            checks[key+"SectionWithinDocumentWithoutOverlap"]=section.enumerated().allSatisfy {index,item in
                view.bounds.contains(item.frame) && section.dropFirst(index+1).allSatisfy{!item.frame.intersects($0.frame)}
            }
            scroll(w,to:heading)
            checks[key+"ControlsReachable"]=view.visibleRect.contains(heading.frame) && controls.allSatisfy{view.visibleRect.contains($0.frame)}

            reject(w,d:d,reason:.disabled,key:key+"SavedDefaultOffRejects",into:&checks)
            w.visitorGiftsButton.performClick(nil)
            checks[key+"ToggleOnlyEditsDraft"]=w.draft.visitorGiftsEnabled && !d.settings.visitorGiftsEnabled
            reject(w,d:d,reason:.disabled,key:key+"PreviewReadsSavedSwitch",into:&checks)
            w.save()
            let enabled=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
            checks[key+"SaveReloadEnablesWithoutChangingOtherValues"]=enabled.visitorGiftsEnabled && d.settings.visitorGiftsEnabled &&
                enabled.hoverDelay==0.37 && enabled.pointerFollowEnabled && enabled.fixedPerches==fixtureSettings.fixedPerches
            let saved=d.settings
            checks[key+"RealResidentIsNotYetFamiliar"]=d.engine.visitor(of:bird).map{$0.visits<3 || $0.familiarity<0.6}==true
            reject(w,d:d,reason:.notFamiliar,key:key+"ExistingUnfamiliarVisitorRejects",into:&checks)
            d.birds=[]
            reject(w,d:d,reason:.noSpecies,key:key+"MissingResidentRejects",into:&checks)
            d.birds=[bird]
            for dependency in ["memory","perch","probability"] {
                var disabled=saved
                if dependency=="memory" {disabled.visitorMemoryEnabled=false}
                else if dependency=="perch" {disabled.fixedPerchesEnabled=false}
                else {
                    guard let index=disabled.probabilities.entries.firstIndex(where:{$0.id == .azureWingedMagpie}) else {throw failure("Missing magpie probability")}
                    disabled.probabilities.adjust(at:index,to:0)
                }
                try d.applySettings(disabled)
                reject(w,d:d,reason:.disabled,key:key+"SavedDependencyRejects-"+dependency,into:&checks)
                try d.applySettings(saved)
            }
            let frames=d.frameCapabilities
            d.frameCapabilities[.azureWingedMagpie]?.remove("carryPlace")
            reject(w,d:d,reason:.missingFrames,key:key+"MissingCarryArtRejects",into:&checks)
            d.frameCapabilities=frames;d.syncWorld(buttonsDown:false)
            d.paused=true
            reject(w,d:d,reason:.paused,key:key+"PausedRejects",into:&checks)
            d.paused=false
            checks[key+"RejectionsNeverMoveOrReplaceResident"]=d.birds.count==1 && d.birds.first === bird &&
                bird.position==origin && bird.motionRevision==revision && bird.state == .perched &&
                d.engine.arrivalCount==0 && d.engine.departureCount==0 && d.observationJournal.archive.entries.isEmpty
            for reason:BehaviorReason in [.notFamiliar,.authorizationDenied,.disabled,.settingsChanged,.noSpecies,.missingBird,
                                         .unavailableBird,.noCompanion,.missingFrames,.noSpace,.targetInvalid,.busy,.timedOut,.paused,.userInput] {
                w.message.stringValue=w.visitorGiftMessage(reason)
                checks[key+"ReasonFits-"+reason.rawValue]=EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            }
            // No pending request exists here. Exercise the production idle
            // cancellation action directly; do not enable or fake its button.
            w.visitorGiftsButton.state = .off;w.hoverDelayField.stringValue="0.43"
            w.detailFields[0][2].stringValue="1.25"
            let draft=try encoded(w.draft),active=try encoded(d.settings),file=try Data(contentsOf:d.settingsURL)
            let details=w.detailFields.map{$0.map(\.stringValue)},memory=d.engine.visitorMemoryArchive
            let archive=d.observationJournal.archive
            let actions:[(String,()->Void)]=[("IdleCancel",{w.cancelVisitorGiftRequestClicked()}),
                                           ("ClearWithoutGift",{w.clearVisitorGiftButton.performClick(nil)})]
            for (name,action) in actions {
                action()
                let currentDraft=try encoded(w.draft),currentSettings=try encoded(d.settings),currentFile=try Data(contentsOf:d.settingsURL)
                checks[key+name+"PreservesUnsavedNativeInputsAndArchives"]=currentDraft==draft && currentSettings==active && currentFile==file &&
                    w.visitorGiftsButton.state == .off && w.hoverDelayField.stringValue=="0.43" &&
                    w.detailFields.map({$0.map(\.stringValue)})==details && d.engine.visitorMemoryArchive==memory &&
                    d.observationJournal.archive==archive && idle(d) && EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            }
            scroll(w,to:heading)
            try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("visitor-gift-controls-"+language.rawValue+".png"))
            scroll(w,to:help)
            try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("visitor-gift-help-"+language.rawValue+".png"))
            w.save()
            let disabled=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
            checks[key+"SaveReloadOffKeepsEditedInputs"] = !disabled.visitorGiftsEnabled && !d.settings.visitorGiftsEnabled &&
                disabled.hoverDelay==0.43 && disabled.catalog.species[0].speed==1.25 &&
                disabled.pointerFollowEnabled && disabled.fixedPerches==fixtureSettings.fixedPerches
        }
        let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:d.settingsURL)) as! [String:Any]
        checks["visitorGiftSettingsOnlyBooleanPersisted"]=raw.keys.filter{$0.localizedCaseInsensitiveContains("gift")}==["visitorGiftsEnabled"]
        w.visitorGiftsButton.performClick(nil);w.cancel()
        let reopened=SpeciesSettingsWindow(desktop:d)
        defer {reopened.cancel()}
        checks["visitorGiftSettingsCancelAndReopenUseSavedOff"] = !d.settings.visitorGiftsEnabled &&
            !reopened.draft.visitorGiftsEnabled && reopened.visitorGiftsButton.state == .off && idle(d)
    }

    private static func journal(_ d:DesktopController,into checks:inout [String:Bool],folder:URL) throws {
        guard let observe=d.engine.observationObserver else {throw failure("Missing in-memory observation delivery")}
        // Inject completed observations into the production journal consumer.
        // These checks cover projection/source semantics, not route completion.
        let preview=BehaviorObservation(sequence:1,simulationTime:1,kind:.visitorGift,
            source:.preview,species:[.azureWingedMagpie],runID:1)
        observe(preview)
        let revision=d.observationJournal.revision
        observe(preview)
        checks["visitorGiftSettingsJournalDuplicateCompletionDoesNotCountTwice"]=d.observationJournal.revision==revision &&
            d.observationJournal.archive.entries.first?.previewCount==1
        observe(BehaviorObservation(sequence:2,simulationTime:2,kind:.rest,source:.automatic,species:[.treeSparrow],runID:2))
        let before=d.observationJournal.archive,settings=try encoded(d.settings),file=try Data(contentsOf:d.settingsURL)
        let w=ObservationJournalWindow(desktop:d);w.showWindow(nil)
        defer {w.window?.close()}
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();w.sourceFilter.selectedSegment=0
            let key="visitorGiftSettingsJournal-"+language.rawValue+"-"
            for query in ["visitorGift","熟客虚拟礼物","Virtual Visitor Gift",SpeciesID.azureWingedMagpie.rawValue,
                          AppLanguage.chinese.name(.azureWingedMagpie),AppLanguage.english.name(.azureWingedMagpie)] {
                w.searchField.stringValue=query;w.searchChanged(nil)
                checks[key+"Search-"+query]=w.renderedEntries.count==1 && w.renderedEntries.first?.behavior=="visitorGift" &&
                    w.renderedEntries.first?.species == .azureWingedMagpie &&
                    w.behaviorName("visitorGift")==language.text("熟客虚拟礼物","Virtual Visitor Gift")
            }
            w.searchField.stringValue="visitorGift";w.sourceFilter.selectedSegment=2;w.sourceChanged(nil)
            let entry=w.renderedEntries.first
            checks[key+"PreviewNeverCountsAsNatural"]=w.selectedSource == .preview && w.tableView.numberOfRows==1 &&
                entry?.automaticCount==0 && entry?.previewCount==1 && entry?.userCount==0 && entry?.totalCount==1 &&
                w.sourceNoteLabel.stringValue.contains(language.text("预览不计为自然发生","Previews do not count as natural occurrences"))
            try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("visitor-gift-journal-preview-"+language.rawValue+".png"))
            for source in [ObservationJournalWindow.SourceFilter.natural,.manual] {
                w.sourceFilter.selectedSegment=source.rawValue;w.sourceChanged(nil)
                checks[key+"PreviewExcludedFromSource-\(source.rawValue)"]=w.renderedEntries.isEmpty &&
                    w.tableView.numberOfRows==0 && !w.emptyStateLabel.isHidden
            }
        }
        let afterControls=try encoded(d.settings),afterFile=try Data(contentsOf:d.settingsURL)
        checks["visitorGiftSettingsJournalControlsReadOnly"]=d.observationJournal.archive==before &&
            afterControls==settings && afterFile==file && idle(d)
        observe(BehaviorObservation(sequence:3,simulationTime:3,kind:.visitorGift,
            source:.automatic,species:[.azureWingedMagpie],runID:3))
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            for source in [ObservationJournalWindow.SourceFilter.all,.natural,.preview] {
                w.sourceFilter.selectedSegment=source.rawValue;w.sourceChanged(nil)
                let entry=w.renderedEntries.first
                checks["visitorGiftSettingsJournalAggregateSources-"+language.rawValue+"-\(source.rawValue)"]=w.renderedEntries.count==1 &&
                    entry?.behavior=="visitorGift" && entry?.automaticCount==1 && entry?.previewCount==1 && entry?.userCount==0 && entry?.totalCount==2
            }
        }
        let data=try JSONEncoder().encode(d.observationJournal.archive)
        checks["visitorGiftSettingsJournalNewKindRoundTripsInMemory"]=(try ObservationArchive.decode(data))==d.observationJournal.archive
    }

    private static func reject(_ w:SpeciesSettingsWindow,d:DesktopController,reason:BehaviorReason,key:String,
                               into checks:inout [String:Bool]) {
        let sequence=d.engine.events.last?.sequence ?? 0,archive=d.observationJournal.archive
        w.previewVisitorGiftButton.performClick(nil)
        let event=d.engine.events.last
        checks[key]=event?.kind == .visitorGift && event?.source == .preview && event?.type == .rejected &&
            event?.reason==reason && (event?.sequence ?? 0)>sequence && idle(d) &&
            d.observationJournal.archive==archive && w.message.stringValue==w.visitorGiftMessage(reason) &&
            EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
    }
    private static func idle(_ d:DesktopController)->Bool {
        d.engine.giftAuthorizationRequest==nil && d.engine.activeGiftAuthorizationCount==0 && d.engine.activeRunCount==0 &&
            d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0 && d.engine.sceneFocus==nil &&
            d.engine.propSnapshot().allSatisfy{$0.kind != .leafToken}
    }
    private static func encoded(_ settings:BirdSettings) throws -> Data {
        let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(settings)
    }
    private static func fits(_ field:NSTextField)->Bool {
        field.cell?.wraps==true && field.cell?.usesSingleLineMode==false &&
            (field.cell?.cellSize(forBounds:CGRect(x:0,y:0,width:field.frame.width,height:10000)).height ?? .infinity)<=field.frame.height
    }
    private static func scroll(_ w:SpeciesSettingsWindow,to field:NSView) {
        w.tabs.selectTabViewItem(at:2)
        guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {return}
        let limit=max(0,document.bounds.height-scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:CGPoint(x:0,y:min(max(0,field.frame.minY-12),limit)))
        scroll.reflectScrolledClipView(scroll.contentView);w.window?.contentView?.layoutSubtreeIfNeeded()
    }
    private static func failure(_ text:String)->NSError {
        NSError(domain:"VisitorGiftSettingsVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])
    }
}
