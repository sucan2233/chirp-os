import AppKit
import BirdingCore

/// Native evidence only, invoked by SettingsVerification after implementation.
/// All observation delivery, preferences and file paths belong to this fixture.
enum ObservationJournalUIVerification {
    static func run(into checks: inout [String: Bool], folder: URL) throws {
        let evidence = folder.appendingPathComponent("observation-journal-ui-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let suite = "Birding.ObservationJournalUIVerification." + UUID().uuidString
        guard let preferences = UserDefaults(suiteName: suite) else {
            throw NSError(domain: "ObservationJournalUIVerification", code: 1)
        }
        defer { preferences.removePersistentDomain(forName: suite) }
        let d = DesktopController()
        d.isolatedSession = true
        d.preferences = preferences
        d.automaticPopulation = false
        d.engine.populationEnabled = false; d.engine.ambientEnabled = false; d.engine.autonomousRouting = false
        d.settingsURL = evidence.appendingPathComponent("settings.json")
        d.legacyURL = evidence.appendingPathComponent("legacy.json")
        d.visitorMemoryPersistenceEnabled = false
        d.visitorMemoryURL = evidence.appendingPathComponent("visitors.json")
        d.observationJournalURL = evidence.appendingPathComponent("observations.json")
        d.observationJournalPersistenceEnabled = true
        d.loadObservationJournal(now: 0)
        guard let persistence = d.observationPersistence else {
            throw NSError(domain: "ObservationJournalUIVerification", code: 2)
        }
        try d.settings.save(to: d.settingsURL)
        let savedSettings = try Data(contentsOf: d.settingsURL)
        let settings = SpeciesSettingsWindow(desktop: d)
        d.settingsWindow = settings
        settings.draft.hoverDelay = 0.37; settings.hoverDelayField.stringValue = "0.37"
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let activeSettings = try encoder.encode(d.settings), draft = try encoder.encode(settings.draft)
        let preferencesBefore = preferences.persistentDomain(forName: suite)

        let w = ObservationJournalWindow(desktop: d)
        guard let window = w.window else { throw NSError(domain: "ObservationJournalUIVerification", code: 3) }
        defer { window.close(); settings.cancel() }
        w.refresh()
        checks["observationUIInitiallyHiddenDoesNoWork"] = !window.isVisible && w.renderCount == 0 && w.renderedRevision == nil
        w.showWindow(nil)
        checks["handbookDefaultsToDiscoveries"] = w.selectedView == .discoveries && w.selectedSource == .collected &&
            w.renderedSpecies.isEmpty && w.scrollView.documentView === w.speciesTableView
        w.selectAllSpecies()
        checks["handbookAllSpeciesNeedsNoDiscovery"] = w.renderedSpecies.count == SpeciesID.allCases.count &&
            d.observationJournal.discoveredSpeciesCount == 0
        w.selectView(.behaviors); select(.all, in: w)
        checks["observationUIEmptyChinese"] = window.title == "观鸟手册" && w.renderedEntries.isEmpty &&
            w.tableView.numberOfRows == 0 && !w.emptyStateLabel.isHidden &&
            w.emptyStateLabel.stringValue.contains("还没有记录") && w.sourceFilter.label(forSegment: 0) == "全部"
        try snapshot(window, name: "empty-zh", folder: evidence, checks: &checks)
        d.language = .english; w.relocalize()
        checks["observationUIEmptyEnglish"] = window.title == "Birdwatching handbook" &&
            w.emptyStateLabel.stringValue.contains("No records yet") && w.sourceFilter.label(forSegment: 1) == "Natural"
        try snapshot(window, name: "empty-en", folder: evidence, checks: &checks)

        window.orderOut(nil)
        let hiddenRenders = w.renderCount
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var sequence: UInt64 = 0
        func record(_ species: SpeciesID, _ behavior: BehaviorKind, _ source: BehaviorSource, seconds: Double) {
            sequence += 1
            let date = base.addingTimeInterval(seconds)
            d.observationDate = { date }
            d.engine.observationObserver?(BehaviorObservation(sequence: sequence, simulationTime: Double(sequence),
                kind: behavior, source: source, species: [species], runID: sequence))
        }
        for seconds in [0.0, 60] { record(.treeSparrow, .rest, .automatic, seconds: seconds) }
        record(.treeSparrow, .rest, .preview, seconds: 120)
        for seconds in [180.0, 240, 300] { record(.treeSparrow, .rest, .user, seconds: seconds) }
        for seconds in [40.0, 80, 160, 320, 380] { record(.barnSwallow, .preen, .preview, seconds: seconds) }
        for seconds in [100.0, 200] { record(.spottedDove, .foodTrayVisit, .user, seconds: seconds) }
        record(.swinhoesWhiteEye, .allopreening, .automatic, seconds: 220)
        w.refresh()
        checks["observationUIObservationNeverOpensWindow"] = d.observationWindow == nil &&
            !window.isVisible && d.observationJournal.archive.entries.count == 4 && w.renderCount == hiddenRenders
        d.observationWindow = w
        d.language = .chinese
        w.showWindow(nil)
        checks["observationUIShowsProductionAggregates"] = w.renderedEntries.count == 4 &&
            w.tableView.numberOfRows == 4 && w.renderedRevision == d.observationJournal.revision
        let unchangedRenders = w.renderCount
        for _ in 0..<5 { w.refresh() }
        checks["observationUIUnchangedTicksDoNoWork"] = w.renderCount == unchangedRenders
        let archiveBeforeControls = d.observationJournal.archive
        try snapshot(window, name: "all-zh", folder: evidence, checks: &checks)

        w.selectSpecies(.treeSparrow)
        search("麻雀", in: w); select(.natural, in: w)
        w.selectAllSpecies()
        checks["handbookSwitchPreservesSearchSourceSelection"] = w.selectedView == .allSpecies &&
            w.searchField.stringValue == "麻雀" && w.selectedSource == .natural && w.selectedSpecies == .treeSparrow &&
            w.renderedSpecies == [.treeSparrow] && w.detailText.string.contains("手动记录：0")
        search("", in: w); w.selectView(.discoveries)
        checks["handbookPreviewOnlyDoesNotDiscover"] = Set(w.renderedSpecies) == [.treeSparrow, .spottedDove, .swinhoesWhiteEye] &&
            !d.observationJournal.isDiscovered(.barnSwallow) && d.observationJournal.manualRecordCount == 0
        w.showUndiscovered.state = .on; w.refresh()
        checks["handbookShowUndiscoveredListsEntireCatalog"] = w.renderedSpecies.count == SpeciesID.allCases.count
        w.selectSpecies(.barnSwallow)
        checks["handbookUndiscoveredUsesSilhouette"] = w.previewView.silhouette && !w.previewAction.isEnabled
        w.selectAllSpecies()
        w.previewAction.selectedSegment = 2
        _ = w.previewAction.sendAction(w.previewAction.action, to: w.previewAction.target)
        w.refresh()
        checks["handbookPreviewDoesNotMutateOrUnlock"] = !w.previewView.silhouette &&
            d.observationJournal.archive == archiveBeforeControls && !d.observationJournal.isDiscovered(.barnSwallow)
        try snapshot(window, name: "all-species-preview", folder: evidence, checks: &checks)
        w.previewAction.selectedSegment = 0
        _ = w.previewAction.sendAction(w.previewAction.action, to: w.previewAction.target)
        w.selectView(.behaviors); select(.collected, in: w)
        checks["handbookRealActivityFilterExcludesPreviewOnly"] = w.renderedEntries.count == 3 &&
            !w.renderedEntries.contains {$0.species == .barnSwallow}
        select(.all, in: w)
        let allDates = dates(w, species: .treeSparrow)
        let sourceFixtures: [(ObservationJournalWindow.SourceFilter, Set<SpeciesID>)] = [
            (.natural, [.treeSparrow, .swinhoesWhiteEye]),
            (.preview, [.treeSparrow, .barnSwallow]),
            (.manual, [.treeSparrow, .spottedDove])
        ]
        for (source, expected) in sourceFixtures {
            select(source, in: w)
            checks["observationUISourceMembership-\(source.rawValue)"] = Set(w.renderedEntries.map(\.species)) == expected
            let counts = sourceCounts(w, species: .treeSparrow)
            checks["observationUIFilteredCountsCoverAllSources-\(source.rawValue)"] = counts == ["2", "1", "3"]
            checks["observationUIFilteredDatesCoverAllSources-\(source.rawValue)"] = dates(w, species: .treeSparrow) == allDates &&
                allDates.count == 2 && allDates.allSatisfy { !$0.isEmpty } && allDates[0] != allDates[1]
        }
        select(.preview, in: w)
        search("整理羽毛", in: w)
        let previewCounts = sourceCounts(w, species: .barnSwallow)
        checks["observationUIPreviewOnlyIsNotNatural"] = w.renderedEntries.count == 1 && previewCounts == ["0", "5", "0"] &&
            w.renderedEntries.first?.automaticCount == 0 && w.renderedEntries.first?.totalCount == 5 &&
            w.sourceNoteLabel.stringValue.contains("预览不解锁鸟种或动作")
        checks["observationUIDatesAreRecordedNotDiscoveredChinese"] = column("first", in: w)?.title == "最早历史记录" &&
            column("last", in: w)?.title == "最近记录"
        try snapshot(window, name: "preview-only-zh", folder: evidence, checks: &checks)
        d.language = .english; w.relocalize()
        checks["observationUIRelocalizePreservesSearchAndSource"] = w.selectedSource == .preview &&
            w.searchField.stringValue == "整理羽毛" && w.renderedEntries.count == 1 &&
            w.renderedEntries.first?.species == .barnSwallow && window.title == "Birdwatching handbook" &&
            sourceCounts(w, species: .barnSwallow) == previewCounts
        checks["observationUIDatesAreRecordedNotDiscoveredEnglish"] = column("first", in: w)?.title == "Earliest history" &&
            column("last", in: w)?.title == "Last recorded" &&
            w.sourceNoteLabel.stringValue.contains("Dates combine historical sources") &&
            w.sourceNoteLabel.stringValue.contains("Previews unlock neither species nor actions")
        try snapshot(window, name: "preview-only-en", folder: evidence, checks: &checks)

        select(.all, in: w)
        for (query, species) in [("麻雀", SpeciesID.treeSparrow), ("bArN sWaLlOw", .barnSwallow),
                                 ("麻雀 休息", .treeSparrow), ("companion preening", .swinhoesWhiteEye)] {
            search(query, in: w)
            checks["observationUISearch-" + query] = w.renderedEntries.count == 1 && w.renderedEntries.first?.species == species
        }
        search("no-matching-bird-" + UUID().uuidString, in: w)
        checks["observationUINoMatchEnglish"] = w.renderedEntries.isEmpty && w.tableView.numberOfRows == 0 &&
            !w.emptyStateLabel.isHidden && w.emptyStateLabel.stringValue.contains("No matching records") &&
            !w.emptyStateLabel.stringValue.contains("No records yet")
        try snapshot(window, name: "no-match-en", folder: evidence, checks: &checks)
        d.language = .chinese; w.relocalize()
        checks["observationUINoMatchChinese"] = !w.emptyStateLabel.isHidden && w.emptyStateLabel.stringValue.contains("没有匹配的记录")
        try snapshot(window, name: "no-match-zh", folder: evidence, checks: &checks)
        search("   ", in: w)
        checks["observationUIWhitespaceSearchShowsAll"] = w.renderedEntries.count == 4 && w.emptyStateLabel.isHidden
        search("", in: w)
        checks["observationUIControlsNeverMutateArchive"] = d.observationJournal.archive == archiveBeforeControls

        if let row = w.renderedEntries.firstIndex(where: { $0.species == .treeSparrow }) {
            let spriteCell = cell("species", row: row, in: w)
            let sprite = spriteCell?.imageView?.image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let expected = d.arts[.treeSparrow]?.frames["stand"]
            let actualBytes = (sprite?.dataProvider?.data).map { $0 as Data }
            let expectedBytes = (expected?.dataProvider?.data).map { $0 as Data }
            checks["observationUIUsesExistingSpeciesSprite"] = sprite?.width == 48 && sprite?.height == 48 &&
                actualBytes != nil && actualBytes == expectedBytes
            checks["observationUICellAccessibility"] = spriteCell?.imageView?.accessibilityLabel() == d.language.name(.treeSparrow) &&
                spriteCell?.textField?.accessibilityLabel() == "鸟种" &&
                cell("natural", row: row, in: w)?.textField?.accessibilityLabel() == "自然发生"
            w.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            let selected = w.renderedEntries[row]
            w.persistenceMessage = "保存状态测试"; w.refresh()
            checks["observationUIRefreshPreservesSelection"] = w.renderedEntries.indices.contains(w.tableView.selectedRow) &&
                w.renderedEntries[w.tableView.selectedRow].species == selected.species &&
                w.renderedEntries[w.tableView.selectedRow].behavior == selected.behavior
        } else {
            checks["observationUIUsesExistingSpeciesSprite"] = false
            checks["observationUICellAccessibility"] = false
            checks["observationUIRefreshPreservesSelection"] = false
        }
        let messageRenders = w.renderCount
        checks["observationUIPersistenceMessageVisible"] = !w.persistenceLabel.isHidden && w.persistenceLabel.stringValue == "保存状态测试"
        w.refresh()
        checks["observationUIUnchangedStatusDoesNoWork"] = w.renderCount == messageRenders
        w.persistenceMessage = ""; w.refresh()
        checks["observationUIClearedPersistenceMessageHidden"] = w.persistenceLabel.isHidden && w.renderCount == messageRenders + 1

        // A real load failure supplies localized text without modifying the
        // fixture journal or involving the user's persistent archive.
        let unreadableURL = evidence.appendingPathComponent("unreadable-observations.json")
        let unreadableData = Data("invalid archive".utf8)
        try unreadableData.write(to: unreadableURL)
        let failed = ObservationJournalPersistence(url: unreadableURL, enabled: true, arguments: [], log: { _ in })
        failed.load(into: ObservationJournal(), now: 0)
        d.observationPersistence = failed
        for language: AppLanguage in [.chinese, .english] {
            d.language = language; w.relocalize()
            checks["observationUILocalizedPersistence-" + language.rawValue] = !w.persistenceLabel.isHidden &&
                !w.persistenceMessage.isEmpty && w.persistenceMessage == failed.statusMessage(language: language) &&
                w.persistenceLabel.stringValue == w.persistenceMessage
            try snapshot(window, name: "persistence-" + language.rawValue, folder: evidence, checks: &checks)
        }
        let preservedUnreadableData = try Data(contentsOf: unreadableURL)
        checks["observationUIErrorStatusDoesNotRewriteFile"] = failed.writesDisabled && failed.saveAttempts == 0 &&
            preservedUnreadableData == unreadableData
        d.observationPersistence = persistence
        w.relocalize()

        let rendersBeforeObservation = w.renderCount
        record(.barnSwallow, .preen, .preview, seconds: 500)
        checks["observationUIObservationWaitsForDesktopRefresh"] = w.renderCount == rendersBeforeObservation &&
            w.renderedRevision != d.observationJournal.revision
        w.refresh()
        checks["observationUIVisibleRevisionRefreshes"] = w.renderCount == rendersBeforeObservation + 1 &&
            sourceCounts(w, species: .barnSwallow) == ["0", "6", "0"] && w.renderedRevision == d.observationJournal.revision
        let visibleEntries = w.renderedEntries, visibleRevision = w.renderedRevision, visibleRenders = w.renderCount
        window.orderOut(nil)
        record(.treeSparrow, .rest, .automatic, seconds: 600)
        w.sourceFilter.selectedSegment = ObservationJournalWindow.SourceFilter.natural.rawValue
        w.searchField.stringValue = "休息"
        d.language = .chinese; w.relocalize(); w.refresh()
        checks["observationUIHiddenChangesDoNoWorkOrOpen"] = !window.isVisible && w.renderCount == visibleRenders &&
            w.renderedRevision == visibleRevision && w.renderedEntries == visibleEntries
        w.showWindow(nil)
        checks["observationUIReopenAppliesPendingRevisionAndFilters"] = w.renderCount == visibleRenders + 1 &&
            w.selectedSource == .natural && w.searchField.stringValue == "休息" &&
            w.renderedEntries.count == 1 && sourceCounts(w, species: .treeSparrow) == ["3", "1", "3"] &&
            w.renderedRevision == d.observationJournal.revision && window.title == "观鸟手册"

        select(.all, in: w); search("", in: w)
        checks["observationUIAccessibilityAndNativeKeyboard"] = w.searchField.accessibilityLabel() == "搜索观察记录" &&
            w.sourceFilter.accessibilityLabel() == "记录来源筛选" && w.tableView.accessibilityLabel() == "观察记录列表" &&
            w.searchField.nextKeyView === w.sourceFilter && w.sourceFilter.nextKeyView === w.tableView &&
            w.tableView.nextKeyView === w.searchField && w.tableView.acceptsFirstResponder &&
            w.sourceFilter.action != nil && w.searchField.action != nil
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "f",
            charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3) {
            window.makeFirstResponder(w.tableView)
            checks["observationUICommandFFocusesSearch"] = window.performKeyEquivalent(with: event) &&
                w.searchField.currentEditor() != nil && window.firstResponder === w.searchField.currentEditor()
        } else { checks["observationUICommandFFocusesSearch"] = false }
        for language: AppLanguage in [.chinese, .english] {
            d.language = language; w.relocalize()
            for size in [NSSize(width: 900, height: 500), NSSize(width: 1360, height: 820)] {
                window.setContentSize(size); window.contentView?.layoutSubtreeIfNeeded()
                let suffix = language.rawValue + "-" + String(Int(size.width))
                let root = window.contentView!
                let controls: [NSView] = [w.headingLabel, w.localOnlyLabel, w.viewSelector, w.searchField, w.sourceFilter,
                                         w.summaryLabel, w.scrollView, w.sourceNoteLabel, w.detailScroll, w.previewView, w.previewAction]
                let rects = controls.map { $0.convert($0.bounds, to: root) }
                checks["observationUIResizeLayout-" + suffix] = rects.allSatisfy { root.bounds.contains($0) && $0.width > 0 && $0.height > 0 } &&
                    rects.enumerated().allSatisfy { index, rect in rects.dropFirst(index + 1).allSatisfy { !rect.intersects($0) } } &&
                    w.scrollView.hasVerticalScroller && w.scrollView.hasHorizontalScroller &&
                    w.tableView.tableColumns.allSatisfy { $0.width >= $0.minWidth }
                checks["observationUIExplanationFits-" + suffix] = [w.localOnlyLabel, w.sourceNoteLabel].allSatisfy {
                    ($0.cell?.cellSize(forBounds: $0.bounds).height ?? .infinity) <= $0.frame.height
                }
                try snapshot(window, name: "layout-" + suffix, folder: evidence, checks: &checks)
            }
        }
        // New v2 records use the same completed-observation path and source
        // filters as historical entries. Do not rewrite or renumber old rows.
        record(.treeSparrow,.bathVisit,.automatic,seconds:700)
        record(.treeSparrow,.bathVisit,.preview,seconds:710)
        record(.lightVentedBulbul,.bathVisit,.preview,seconds:720)
        w.refresh()
        checks["observationUIBathV3RetainsHistoricalRows"] = ObservationArchive.currentVersion==3 &&
            d.observationJournal.archive.entries.count==6 && archiveBeforeControls.entries.allSatisfy {old in
                d.observationJournal.archive.entries.contains{$0.species==old.species && $0.behavior==old.behavior}
            }
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize();select(.all,in:w)
            for query in ["bathVisit","洗澡","Bathing"] {
                search(query,in:w)
                checks["observationUIBathSearch-"+language.rawValue+"-"+query] = w.renderedEntries.count==2 &&
                    w.renderedEntries.allSatisfy{$0.behavior=="bathVisit"} &&
                    w.renderedEntries.indices.allSatisfy {row in
                        cell("behavior",row:row,in:w)?.textField?.stringValue==language.text("洗澡","Bathing")
                    }
            }
            select(.natural,in:w)
            checks["observationUIBathNaturalExcludesPreviewOnly-"+language.rawValue] = w.renderedEntries.count==1 &&
                w.renderedEntries.first?.species == .treeSparrow && sourceCounts(w,species:.treeSparrow)==["1","1","0"]
            select(.preview,in:w)
            checks["observationUIBathPreviewKeepsNaturalSeparate-"+language.rawValue] = w.renderedEntries.count==2 &&
                sourceCounts(w,species:.lightVentedBulbul)==["0","1","0"]
            try snapshot(window,name:"bath-v2-"+language.rawValue,folder:evidence,checks:&checks)
        }
        // Exercise real v1 loading and future-envelope protection in separate
        // files. The UI remains a reader; no archive flush is requested here.
        let v1URL=evidence.appendingPathComponent("journal-v1.json")
        let oldArchive=ObservationArchive(entries:archiveBeforeControls.entries)
        let encodedOld=try JSONSerialization.jsonObject(with:encoder.encode(oldArchive)) as! [String:Any]
        let oldEnvelope:[String:Any] = ["formatVersion":1,"entries":encodedOld["entries"] ?? encodedOld["behaviorEntries"]!]
        let oldBytes=try JSONSerialization.data(withJSONObject:oldEnvelope,options:.sortedKeys)
        try oldBytes.write(to:v1URL)
        let migrated=ObservationJournal(),v1Persistence=ObservationJournalPersistence(url:v1URL,enabled:true,arguments:[],log:{_ in})
        v1Persistence.load(into:migrated,now:0)
        let v1After=try Data(contentsOf:v1URL)
        let backups=try FileManager.default.contentsOfDirectory(at:ObservationArchiveStore(url:v1URL).backupsURL,includingPropertiesForKeys:nil)
        let preservedLegacy=try backups.contains {try Data(contentsOf:$0)==oldBytes}
        let committed=try ObservationArchive.decode(v1After)
        checks["observationUIV1MigrationKeepsRowsAndByteBackup"] = !v1Persistence.writesDisabled &&
            migrated.archive.entries==archiveBeforeControls.entries && committed.entries==archiveBeforeControls.entries &&
            migrated.archive.formatVersion==3 && preservedLegacy && v1Persistence.saveAttempts==0
        // Migration is allowed to commit v3; subsequent handbook reads are not.
        d.observationPersistence=v1Persistence
        w.relocalize();w.refresh()
        let v1AfterUI=try Data(contentsOf:v1URL)
        checks["observationUIV1DisplayDoesNotWrite"] = v1AfterUI==v1After && v1Persistence.saveAttempts==0
        let futureURL=evidence.appendingPathComponent("journal-future.json")
        let futureBytes=try JSONSerialization.data(withJSONObject:["formatVersion":ObservationArchive.currentVersion+1,"entries":[]] as [String:Any])
        try futureBytes.write(to:futureURL)
        let future=ObservationJournalPersistence(url:futureURL,enabled:true,arguments:[],log:{_ in})
        future.load(into:ObservationJournal(),now:0);d.observationPersistence=future
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            checks["observationUIFutureVersionVisibleAndProtected-"+language.rawValue] = future.writesDisabled &&
                !w.persistenceLabel.isHidden && !w.persistenceLabel.stringValue.isEmpty &&
                w.persistenceLabel.stringValue==future.statusMessage(language:language)
            try snapshot(window,name:"future-v2-"+language.rawValue,folder:evidence,checks:&checks)
        }
        let futureAfter=try Data(contentsOf:futureURL)
        checks["observationUIFutureVersionNeverOverwritten"] = futureAfter==futureBytes && future.saveAttempts==0
        d.observationPersistence=persistence;w.relocalize()
        let currentSettings = try encoder.encode(d.settings), currentDraft = try encoder.encode(settings.draft)
        let currentSavedSettings = try Data(contentsOf: d.settingsURL)
        checks["observationUIReadOnlySettingsAndDraft"] = currentSettings == activeSettings && currentDraft == draft &&
            currentSavedSettings == savedSettings && settings.hoverDelayField.stringValue == "0.37" &&
            NSDictionary(dictionary: preferences.persistentDomain(forName: suite) ?? [:]).isEqual(to: preferencesBefore ?? [:])
        // Both menu surfaces invoke the same read-only controller. Keep the
        // fixture's status item and main menu scoped to this acceptance check.
        let originalMenu=NSApp.mainMenu
        defer {
            if let status=d.status {NSStatusBar.system.removeStatusItem(status);d.status=nil}
            NSApp.mainMenu=originalMenu
        }
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;d.makeMenu()
            let title=d.t("观鸟手册…","Birdwatching handbook…")
            let item=NSApp.mainMenu?.items.first?.submenu?.items.first{$0.title==title}
            let statusItem=d.status?.menu?.items.first{$0.title==title}
            checks["observationUIMenuAndKeyboardEntry-"+language.rawValue]=item?.action == #selector(DesktopController.showObservationJournal) &&
                item?.target === d && item?.keyEquivalent == "j" && item?.keyEquivalentModifierMask == .command &&
                statusItem?.action == item?.action && statusItem?.target === d
        }
        let behaviorsBeforeManual=d.observationJournal.archive.entries
        let acceptedManual=d.observationJournal.recordManual(species:.littleOwl,at:base.addingTimeInterval(800))
        d.language = .chinese;w.relocalize();search("",in:w);w.selectView(.discoveries);w.selectSpecies(.littleOwl)
        checks["handbookManualRecordHasSharedDetailWithoutCompletingBehavior"] = acceptedManual &&
            w.renderedSpecies.contains(.littleOwl) && w.detailText.string.contains("手动记录：1") &&
            d.observationJournal.archive.entries==behaviorsBeforeManual && d.observationJournal.manualRecordCount==1
        w.selectAllSpecies()
        checks["handbookManualDetailSharedAcrossViews"] = w.selectedSpecies == .littleOwl &&
            w.detailText.string.contains("手动观鸟记录") && w.detailText.string.contains("手动记录：1")
        checks["observationUINeverWritesObservationsOrStartsDesktop"] = persistence.enabled && persistence.saveAttempts == 0 &&
            !FileManager.default.fileExists(atPath: d.observationJournalURL.path) &&
            !FileManager.default.fileExists(atPath: d.visitorMemoryURL.path) &&
            d.timer == nil && d.panels.isEmpty && d.views.isEmpty && d.engine.birds.isEmpty
    }

    private static func select(_ source: ObservationJournalWindow.SourceFilter, in w: ObservationJournalWindow) {
        w.sourceFilter.selectedSegment = source.rawValue
        _ = w.sourceFilter.sendAction(w.sourceFilter.action, to: w.sourceFilter.target)
    }
    private static func search(_ query: String, in w: ObservationJournalWindow) {
        w.searchField.stringValue = query
        // Typing uses the native delegate, while Return uses the field action.
        w.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: w.searchField))
        _ = w.searchField.sendAction(w.searchField.action, to: w.searchField.target)
    }
    private static func column(_ key: String, in w: ObservationJournalWindow) -> NSTableColumn? {
        w.tableView.tableColumns.first { $0.identifier.rawValue == key }
    }
    private static func cell(_ key: String, row: Int, in w: ObservationJournalWindow) -> NSTableCellView? {
        guard let column = column(key, in: w) else { return nil }
        return w.tableView(w.tableView, viewFor: column, row: row) as? NSTableCellView
    }
    private static func sourceCounts(_ w: ObservationJournalWindow, species: SpeciesID) -> [String] {
        guard let row = w.renderedEntries.firstIndex(where: { $0.species == species }) else { return [] }
        return ["natural", "preview", "manual"].map { cell($0, row: row, in: w)?.textField?.stringValue ?? "" }
    }
    private static func dates(_ w: ObservationJournalWindow, species: SpeciesID) -> [String] {
        guard let row = w.renderedEntries.firstIndex(where: { $0.species == species }) else { return [] }
        return ["first", "last"].map { cell($0, row: row, in: w)?.textField?.stringValue ?? "" }
    }
    private static func snapshot(_ window: NSWindow, name: String, folder: URL, checks: inout [String: Bool]) throws {
        let url = folder.appendingPathComponent("journal-" + name + ".png")
        try SettingsVerification.snapshot(window, to: url)
        checks["observationUIScreenshot-" + name] = NSImage(contentsOf: url).map { $0.size.width > 0 && $0.size.height > 0 } ?? false
    }
}
