import AppKit
import BirdingCore

/// A read-only projection of completed observations. Desktop owns delivery and
/// persistence; this window never starts a timer or sends simulation commands.
final class ObservationJournalWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum SourceFilter: Int, CaseIterable {
        case all, natural, preview, manual, collected
        func includes(_ entry: ObservationEntry) -> Bool {
            switch self {
            case .all: return true
            case .collected: return entry.automaticCount > 0 || entry.userCount > 0
            case .natural: return entry.automaticCount > 0
            case .preview: return entry.previewCount > 0
            case .manual: return entry.userCount > 0
            }
        }
    }

    enum ViewMode: Int {case discoveries, allSpecies, behaviors}
    let viewSelector = NSSegmentedControl()
    let showUndiscovered = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let speciesTableView = NSTableView()
    let detailText = NSTextView()
    let detailScroll = NSScrollView()
    let previewView = JournalPreviewView()
    let previewAction = NSSegmentedControl()
    private(set) var renderedSpecies: [SpeciesID] = []
    private(set) var selectedSpecies: SpeciesID?
    private(set) var selectedView: ViewMode = .discoveries
    private var supportCache: [SpeciesID: SpeciesSupportAudit] = [:]
    private var restoringSelection = false

    unowned let desktop: DesktopController
    var persistenceMessage: String = ""
    let searchField = NSSearchField()
    let sourceFilter = NSSegmentedControl()
    let tableView = NSTableView()
    let scrollView = NSScrollView()
    let headingLabel = NSTextField(labelWithString: "")
    let localOnlyLabel = NSTextField(wrappingLabelWithString: "")
    let summaryLabel = NSTextField(labelWithString: "")
    let sourceNoteLabel = NSTextField(wrappingLabelWithString: "")
    let persistenceLabel = NSTextField(wrappingLabelWithString: "")
    let emptyStateLabel = NSTextField(wrappingLabelWithString: "")
    private(set) var renderedEntries: [ObservationEntry] = []
    private(set) var renderedRevision: UInt64?
    private(set) var renderCount = 0
    var selectedSource: SourceFilter { SourceFilter(rawValue: sourceFilter.selectedSegment) ?? .all }

    private struct RenderState: Equatable {
        let revision: UInt64
        let query: String
        let source: Int
        let language: AppLanguage
        let message: String
        let view: Int
        let showUndiscovered: Bool
        let settings: [Bool]
    }
    private var renderedState: RenderState?
    private var persistenceHeight: NSLayoutConstraint!
    private let dateFormatter = DateFormatter()
    private let timeFormatter = DateFormatter()

    init(desktop: DesktopController) {
        self.desktop = desktop
        let window = ObservationJournalNativeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1140, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 900, height: 500)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        super.init(window: window)
        window.journalSearchField = searchField
        build(in: window.contentView!)
        localizeLabels()
        window.initialFirstResponder = searchField
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refresh()
    }

    /// Called by Desktop's existing tick. Hidden and unchanged calls are O(1)
    /// and do not even copy the archive, sort entries or reload native views.
    func refresh() {
        guard window?.isVisible == true else { return }
        previewView.advance(paused: desktop.paused)
        let settings = desktop.settings
        let state = RenderState(revision: desktop.observationJournal.revision,
                                query: searchField.stringValue, source: sourceFilter.selectedSegment,
                                language: desktop.language, message: persistenceMessage,
                                view: selectedView.rawValue, showUndiscovered: showUndiscovered.state == .on,
                                settings: BehaviorDefinitions.all.map {$0.isEnabled(settings: settings, source: .automatic)})
        guard state != renderedState else { return }
        if renderedState?.language != state.language { localizeLabels() }

        let selection = renderedEntries.indices.contains(tableView.selectedRow) ? renderedEntries[tableView.selectedRow] : nil
        let entries = desktop.observationJournal.archive.entries
        let terms = state.query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        renderedEntries = entries.filter { entry in
            guard selectedSource.includes(entry) else { return false }
            guard !terms.isEmpty else { return true }
            let profile = desktop.catalog.profile(entry.species)
            let searchable = [profile.name, profile.englishName ?? "", entry.species.rawValue,
                              AppLanguage.chinese.name(entry.species), AppLanguage.english.name(entry.species),
                              behaviorName(entry.behavior, language: .chinese),
                              behaviorName(entry.behavior, language: .english), entry.behavior].joined(separator: " ")
            return terms.allSatisfy { searchable.localizedStandardContains($0) }
        }.sorted {
            if $0.lastSeen != $1.lastSeen { return $0.lastSeen > $1.lastSeen }
            if $0.species != $1.species { return $0.species.rawValue < $1.species.rawValue }
            return $0.behavior < $1.behavior
        }
        renderedSpecies = desktop.catalog.species.map(\.id).filter {id in
            guard selectedView != .discoveries || state.showUndiscovered || desktop.observationJournal.isDiscovered(id) else {return false}
            let profile = desktop.catalog.profile(id)
            let searchable = [profile.name, profile.englishName ?? "", profile.scientificName ?? "", id.rawValue,
                              AppLanguage.chinese.name(id), AppLanguage.english.name(id)] +
                entries.filter {$0.species == id}.flatMap {[behaviorName($0.behavior, language: .chinese), behaviorName($0.behavior, language: .english), $0.behavior]}
            return terms.allSatisfy {searchable.joined(separator: " ").localizedStandardContains($0)}
        }
        if selectedSpecies == nil {selectedSpecies = selectedView == .behaviors ? renderedEntries.first?.species : renderedSpecies.first}
        renderedState = state
        renderedRevision = state.revision
        renderCount += 1
        restoringSelection = true
        tableView.reloadData()
        speciesTableView.reloadData()
        scrollView.documentView = selectedView == .behaviors ? tableView : speciesTableView
        if selectedView == .behaviors {
            searchField.nextKeyView = sourceFilter; sourceFilter.nextKeyView = tableView; tableView.nextKeyView = searchField
        } else {
            searchField.nextKeyView = speciesTableView; speciesTableView.nextKeyView = previewAction; previewAction.nextKeyView = searchField
        }
        sourceFilter.isHidden = selectedView != .behaviors
        showUndiscovered.isHidden = selectedView != .discoveries
        if let selection, selection.species == selectedSpecies, let row = renderedEntries.firstIndex(where: {
            $0.species == selection.species && $0.behavior == selection.behavior
        }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if let row = renderedEntries.firstIndex(where: {$0.species == selectedSpecies}) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { tableView.deselectAll(nil) }
        if let row = renderedSpecies.firstIndex(where: {$0 == selectedSpecies}) {
            speciesTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {speciesTableView.deselectAll(nil)}
        restoringSelection = false
        summaryLabel.stringValue = desktop.t("显示 \(renderedEntries.count) / \(entries.count) 条记录",
                                             "Showing \(renderedEntries.count) of \(entries.count) records")
        emptyStateLabel.stringValue = entries.isEmpty
            ? desktop.t("还没有记录\n已完成的行为会在这里留下记录；预览会单独计数。",
                        "No records yet\nCompleted behaviors appear here; previews are counted separately.")
            : desktop.t("没有匹配的记录\n试试其他鸟种、行为或来源，或清除搜索。",
                        "No matching records\nTry another species, behavior or source, or clear the search.")
        if selectedView != .behaviors {
            summaryLabel.stringValue = desktop.t("已发现 \(desktop.observationJournal.discoveredSpeciesCount) / \(desktop.catalog.species.count) 种 · 手动记录 \(desktop.observationJournal.manualRecordCount) 次 · 显示 \(renderedSpecies.count) 种",
                "Discovered \(desktop.observationJournal.discoveredSpeciesCount) / \(desktop.catalog.species.count) species · \(desktop.observationJournal.manualRecordCount) manual records · Showing \(renderedSpecies.count)")
            emptyStateLabel.stringValue = desktop.t("暂无匹配鸟种\n手动记录或真实完成的行为会留下发现；可切换全部鸟种浏览。", "No matching species\nManual records and completed real behaviors add discoveries. Browse All species to explore.")
        }
        emptyStateLabel.isHidden = selectedView == .behaviors ? !renderedEntries.isEmpty : !renderedSpecies.isEmpty
        updateDetail()
        persistenceLabel.stringValue = persistenceMessage
        persistenceLabel.toolTip = persistenceMessage.isEmpty ? nil : persistenceMessage
        persistenceLabel.isHidden = persistenceMessage.isEmpty
        persistenceHeight.constant = persistenceMessage.isEmpty ? 0 : 34
    }

    func relocalize() {
        persistenceMessage = desktop.observationPersistence?.statusMessage(language: desktop.language) ?? persistenceMessage
        refresh()
    }

    @objc func searchChanged(_ sender: Any?) { refresh() }
    @objc func sourceChanged(_ sender: Any?) { refresh() }
    func controlTextDidChange(_ notification: Notification) { refresh() }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === speciesTableView ? renderedSpecies.count : renderedEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === speciesTableView {return speciesCell(row: row)}
        guard renderedEntries.indices.contains(row), let column = tableColumn else { return nil }
        let entry = renderedEntries[row]
        let key = column.identifier.rawValue
        let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView)
            ?? makeCell(identifier: column.identifier, species: key == "species")
        let field = cell.textField!
        switch key {
        case "species":
            field.stringValue = desktop.language.name(entry.species)
            if let sprite = desktop.arts[entry.species]?.frames["stand"] {
                cell.imageView?.image = NSImage(cgImage: sprite, size: NSSize(width: 48, height: 48))
            } else { cell.imageView?.image = nil }
            cell.imageView?.setAccessibilityLabel(field.stringValue)
        case "behavior": field.stringValue = behaviorName(entry.behavior)
        case "first": field.stringValue = dateText(entry.firstSeen)
        case "last": field.stringValue = dateText(entry.lastSeen)
        case "natural": field.stringValue = String(entry.automaticCount)
        case "preview": field.stringValue = String(entry.previewCount)
        case "manual": field.stringValue = String(entry.userCount)
        default: return nil
        }
        field.setAccessibilityLabel(column.title)
        field.toolTip = column.title + ": " + field.stringValue.replacingOccurrences(of: "\n", with: " ")
        return cell
    }

    /// Existing gallery callers join this controller without losing search,
    /// source filter or the currently selected species.
    func selectAllSpecies() {selectView(.allSpecies)}
    func selectView(_ view: ViewMode) {
        selectedView = view; viewSelector.selectedSegment = view.rawValue
        refresh()
    }
    func selectSpecies(_ species: SpeciesID) {
        selectedSpecies = species; renderedState = nil; refresh()
    }
    @objc private func viewChanged(_ sender: Any?) {
        selectView(ViewMode(rawValue: viewSelector.selectedSegment) ?? .discoveries)
    }
    @objc private func undiscoveredChanged(_ sender: Any?) {refresh()}
    @objc private func previewChanged(_ sender: Any?) {
        switch previewAction.selectedSegment {
        case 1: previewView.action = .resting
        case 2: previewView.action = .flying
        case 3: previewView.action = .other
        default: previewView.action = nil
        }
        previewView.reset()
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !restoringSelection, let table = notification.object as? NSTableView else {return}
        if table === speciesTableView, renderedSpecies.indices.contains(table.selectedRow) {
            selectedSpecies = renderedSpecies[table.selectedRow]
        } else if table === tableView, renderedEntries.indices.contains(table.selectedRow) {
            selectedSpecies = renderedEntries[table.selectedRow].species
        } else {return}
        updateDetail()
    }
    private func supportAudit(_ species: SpeciesID) -> SpeciesSupportAudit {
        if let cached = supportCache[species] {return cached}
        let frames = Set(desktop.arts[species]?.frames.keys.map {$0} ?? [])
        let audit = SpeciesSupportAudit(species: species, availableFrames: frames)
        supportCache[species] = audit
        return audit
    }
    private func supportedBehaviors(_ species: SpeciesID) -> [BehaviorKind] {
        supportAudit(species).behaviors.filter {$0.kind != .relocate && $0.contentSupported}.map(\.kind)
    }
    private func noCollectibleActionsText(_ species: SpeciesID) -> String {
        supportAudit(species).capabilities.contains(.standing)
            ? desktop.t("基础素材可预览 · 暂无可收集动作", "Basic art available · No collectible actions yet")
            : desktop.t("素材待补齐 · 暂无可收集动作", "Artwork incomplete · No collectible actions yet")
    }
    private func observedBehaviorCount(_ species: SpeciesID) -> Int {
        let supported = Set(supportedBehaviors(species).map(\.rawValue))
        return desktop.observationJournal.archive.entries.filter {
            $0.species == species && supported.contains($0.behavior) && ($0.automaticCount > 0 || $0.userCount > 0)
        }.count
    }
    private func speciesCell(row: Int) -> NSView? {
        guard renderedSpecies.indices.contains(row) else {return nil}
        let species = renderedSpecies[row]
        let identifier = NSUserInterfaceItemIdentifier("handbookSpecies")
        let cell = (speciesTableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? makeCell(identifier: identifier, species: true)
        let hidden = selectedView == .discoveries && !desktop.observationJournal.isDiscovered(species)
        let record = desktop.observationJournal.speciesRecord(for: species)
        var lines = [desktop.language.name(species)]
        if let first = record?.firstDiscoveredAt {
            lines.append(desktop.t("首次发现：", "First discovery: ") + dateFormatter.string(from: first))
        } else if let historical = record?.historicalFirstSeen {
            lines.append(desktop.t("最早历史记录：", "Earliest history: ") + dateFormatter.string(from: historical))
        } else if let manual = record?.manualFirstRecordedAt {
            lines.append(desktop.t("手动首次记录：", "First manual record: ") + dateFormatter.string(from: manual))
        } else {lines.append(record == nil ? desktop.t("尚未发现", "Undiscovered") : desktop.t("已发现，日期未知", "Discovered, date unknown"))}
        let supported = supportedBehaviors(species)
        if supported.isEmpty {
            lines.append(desktop.t("手动记录 \(record?.manualCount ?? 0) 次", "\(record?.manualCount ?? 0) manual records"))
            lines.append(noCollectibleActionsText(species))
        } else {
            lines.append(desktop.t("手动记录 \(record?.manualCount ?? 0) 次 · 动作 \(observedBehaviorCount(species)) / \(supported.count)",
                                   "\(record?.manualCount ?? 0) manual records · Actions \(observedBehaviorCount(species)) / \(supported.count)"))
        }
        cell.textField?.maximumNumberOfLines = 4
        cell.textField?.stringValue = lines.joined(separator: "\n")
        cell.textField?.toolTip = cell.textField?.stringValue
        if let sprite = desktop.arts[species]?.frames["stand"] {
            let image = NSImage(cgImage: sprite, size: NSSize(width: 48, height: 48))
            if hidden {
                image.lockFocus()
                NSColor.secondaryLabelColor.setFill()
                NSRect(x: 0, y: 0, width: 48, height: 48).fill(using: .sourceIn)
                image.unlockFocus()
            }
            cell.imageView?.image = image
        } else {cell.imageView?.image = nil}
        cell.imageView?.setAccessibilityLabel(desktop.language.name(species) + (hidden ? desktop.t("，未发现剪影", ", undiscovered silhouette") : ""))
        return cell
    }
    private func sourceName(_ source: ObservationDiscoverySource) -> String {
        switch source {
        case .manual: return desktop.t("手动观鸟记录", "Manual bird record")
        case .automatic: return desktop.t("自然行为完成", "Completed natural behavior")
        case .user: return desktop.t("主动触发行为完成", "Completed user-triggered behavior")
        case .historicalBehavior: return desktop.t("历史行为记录", "Historical behavior record")
        case .lifeList: return desktop.t("导入手动观鸟记录", "Imported manual bird record")
        }
    }
    private func updateDetail() {
        guard let species = selectedSpecies else {
            detailText.string = desktop.t("选择鸟种查看资料与记录。", "Select a species to view its profile and records.")
            previewView.art = nil; previewView.profile = nil; previewView.reset()
            previewAction.isEnabled = false
            return
        }
        let profile = desktop.catalog.profile(species)
        let record = desktop.observationJournal.speciesRecord(for: species)
        let hidden = selectedView == .discoveries && !desktop.observationJournal.isDiscovered(species)
        let changed = previewView.profile?.id != species
        previewView.art = desktop.arts[species]; previewView.profile = profile; previewView.silhouette = hidden
        previewAction.isEnabled = !hidden
        previewView.setAccessibilityLabel(desktop.language.name(species) + desktop.t("素材预览，不计进度", " art preview, no progress"))
        if changed {previewView.reset()} else {previewView.needsDisplay = true}
        var lines = [desktop.language.name(species), profile.englishName ?? "", profile.scientificName ?? "",
                     profile.appearanceNotes ?? "", desktop.t("体长参考：", "Length reference: ") + String(format: "%.1f cm", profile.adultLengthCM), ""]
        if let record {
            lines.append(desktop.t("发现来源：", "Discovery sources: ") + record.discoverySources.map(sourceName).joined(separator: " · "))
            if let date = record.firstDiscoveredAt {lines.append(desktop.t("首次明确发现：", "First known discovery: ") + dateText(date).replacingOccurrences(of: "\n", with: " "))}
            if let date = record.lastDiscoveredAt {lines.append(desktop.t("最近明确发现：", "Latest known discovery: ") + dateText(date).replacingOccurrences(of: "\n", with: " "))}
            if let date = record.historicalFirstSeen {lines.append(desktop.t("最早历史记录（可能混合来源）：", "Earliest history (may combine sources): ") + dateFormatter.string(from: date))}
            lines.append(desktop.t("手动记录：\(record.manualCount) 次", "Manual records: \(record.manualCount)"))
            lines.append(desktop.t("手动首次：", "First manual record: ") + (record.manualFirstRecordedAt.map {dateFormatter.string(from: $0)} ?? desktop.t("未知", "Unknown")))
            lines.append(desktop.t("手动最近：", "Latest manual record: ") + (record.manualLastRecordedAt.map {dateFormatter.string(from: $0)} ?? desktop.t("未知", "Unknown")))
        } else {lines.append(desktop.t("尚未发现。浏览资料与素材预览不会解锁。", "Undiscovered. Browsing and art previews do not unlock discoveries."))}
        let supported = supportedBehaviors(species)
        let entries = desktop.observationJournal.archive.entries.filter {$0.species == species}
        if supported.isEmpty {
            lines += ["", noCollectibleActionsText(species),
                      desktop.t("可浏览已有素材，也可手动记录发现。现有闲置画面不代表已开放对应行为；无需补齐动作进度。",
                                "Browse existing art or record a manual discovery. Idle artwork does not mean the corresponding behavior is available; there is no action progress to complete yet.")]
        } else {
            lines += ["", desktop.t("已观察动作 \(observedBehaviorCount(species)) / \(supported.count)", "Observed actions \(observedBehaviorCount(species)) / \(supported.count)"),
                      desktop.t("仅下列通过内容审核且素材完整的动作计入收集；真实完成后才记录。其他素材预览不表示已开放对应行为。",
                                "Only the reviewed actions below with complete artwork count toward collection, after real completion. Other art previews do not imply that those behaviors are available.")]
        }
        for kind in supported {
            let entry = entries.first {$0.behavior == kind.rawValue}
            let observed = (entry?.automaticCount ?? 0) > 0 || (entry?.userCount ?? 0) > 0
            let enabled = BehaviorDefinitions.definition(for: kind).isEnabled(settings: desktop.settings, source: .automatic)
            lines.append((observed ? "✓ " : "○ ") + behaviorName(kind.rawValue) + (enabled ? "" : desktop.t(" · 自动发生已关闭", " · automatic activity off")))
            if let entry {
                lines.append(desktop.t("  自然 \(entry.automaticCount) · 主动 \(entry.userCount) · 预览 \(entry.previewCount)",
                                       "  Natural \(entry.automaticCount) · User \(entry.userCount) · Preview \(entry.previewCount)"))
            }
        }
        let supportedIDs = Set(supported.map(\.rawValue))
        let historical = entries.filter {!supportedIDs.contains($0.behavior)}
        if !historical.isEmpty {
            lines += ["", desktop.t("其他历史记录（只读，不计支持动作进度）", "Other history (read-only; excluded from supported-action progress)")]
            for entry in historical {
                lines.append(behaviorName(entry.behavior) + desktop.t(" · 自然 \(entry.automaticCount) / 主动 \(entry.userCount) / 预览 \(entry.previewCount)",
                                                                    " · Natural \(entry.automaticCount) / User \(entry.userCount) / Preview \(entry.previewCount)"))
            }
        }
        lines += ["", desktop.t("仅展示累计次数与首尾日期，不推断逐次事件。预览不计发现或动作进度。", "Only totals and first/last dates are available. Previews count toward neither discoveries nor action progress.")]
        detailText.string = lines.joined(separator: "\n")
        if changed {detailText.scrollToBeginningOfDocument(nil)}
    }

    func behaviorName(_ behavior: String, language: AppLanguage? = nil) -> String {
        let language = language ?? desktop.language
        switch behavior {
        case "relocate": return language.text("更换位置", "Relocate")
        case "pointerVisit": return language.text("绕鼠标飞行", "Pointer visit")
        case "flockPass": return language.text("鸟群过境", "Passing flock")
        case "rest": return language.text("闭眼休息", "Eyes-closed rest")
        case "preen": return language.text("整理羽毛", "Preening")
        case "socialGreeting": return language.text("双鸟招呼", "Two-bird greeting")
        case "sideBySide": return language.text("并排停靠", "Side-by-side perch")
        case "giveWay": return language.text("让座", "Giving way")
        case "pairedTakeoff": return language.text("结伴起飞", "Paired takeoff")
        case "leafPlay": return language.text("落叶互动", "Leaf play")
        case "watch": return language.text("留意鼠标", "Watching the pointer")
        case "alert": return language.text("短暂警觉", "Brief alertness")
        case "sideHop": return language.text("小跳让路", "Side hop")
        case "takeoffPreparation": return language.text("起飞准备", "Takeoff preparation")
        case "edgePeek": return language.text("探头观察", "Edge peeking")
        case "chase": return language.text("短暂追逐", "Brief chase")
        case "travelTogether": return language.text("飞行中临时结队", "Travel together in flight")
        case "allopreening": return language.text("同伴理羽", "Companion preening")
        case "fixedPerchVisit": return language.text("访问固定栖木", "Fixed perch visit")
        case "foodTrayVisit": return language.text("访问临时食盘", "Food tray visit")
        case "bathVisit": return language.text("洗澡", "Bathing")
        case "leafCarry": return language.text("携带叶片", "Leaf Carrying")
        case "insectCatch": return language.text("捕虫", "Insect Catching")
        case "visitorGift": return language.text("熟客虚拟礼物", "Virtual Visitor Gift")
        case "courtshipDisplay": return language.text("求偶展示", "Courtship Display")
        case "nestMaterialCarry": return language.text("运送巢材", "Nest Material Delivery")
        case "nestBuild": return language.text("筑巢片段", "Nest Building")
        default: return behavior
        }
    }

    private func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date) + "\n" + timeFormatter.string(from: date)
    }

    private func localizeLabels() {
        window?.title = desktop.t("观鸟手册", "Birdwatching handbook")
        headingLabel.stringValue = window?.title ?? ""
        localOnlyLabel.stringValue = desktop.t("发现表示应用记录到有效活动；手动、行为和预览分别计数，资料仅保存在此 Mac。",
                                              "Discoveries reflect recorded activity. Manual records, behaviors and previews are counted separately on this Mac.")
        searchField.placeholderString = desktop.t("搜索鸟种或行为", "Search species or behavior")
        searchField.setAccessibilityLabel(desktop.t("搜索观察记录", "Search journal records"))
        searchField.toolTip = desktop.t("搜索中文或英文鸟种与行为 · ⌘F", "Search species and behaviors in Chinese or English · ⌘F")
        sourceFilter.setAccessibilityLabel(desktop.t("记录来源筛选", "Record source filter"))
        let titles = [desktop.t("全部", "All"), desktop.t("自然发生", "Natural"),
                      desktop.t("预览", "Preview"), desktop.t("主动触发", "User-triggered"), desktop.t("真实活动", "Real activity")]
        for (index, title) in titles.enumerated() { sourceFilter.setLabel(title, forSegment: index) }
        let columns = [desktop.t("鸟种", "Species"), desktop.t("行为", "Behavior"),
                       desktop.t("最早历史记录", "Earliest history"), desktop.t("最近记录", "Last recorded"),
                       desktop.t("自然发生", "Natural"), desktop.t("预览", "Preview"), desktop.t("主动触发", "User-triggered")]
        for (column, title) in zip(tableView.tableColumns, columns) { column.title = title }
        tableView.setAccessibilityLabel(desktop.t("观察记录列表", "Journal records"))
        sourceNoteLabel.stringValue = desktop.t(
            "日期汇总历史来源，不等同首次自然观察。预览不解锁鸟种或动作；手动记录不完成动作。",
            "Dates combine historical sources. Previews unlock neither species nor actions; manual recording completes no action.")
        sourceFilter.toolTip = sourceNoteLabel.stringValue
        sourceFilter.setAccessibilityHelp(sourceNoteLabel.stringValue)
        persistenceLabel.setAccessibilityLabel(desktop.t("观察记录保存状态", "Journal saving status"))
        for (i, title) in [desktop.t("我的发现", "My discoveries"), desktop.t("全部鸟种", "All species"), desktop.t("行为记录", "Behavior records")].enumerated() {viewSelector.setLabel(title, forSegment: i)}
        viewSelector.setAccessibilityLabel(desktop.t("手册视图", "Handbook view"))
        showUndiscovered.title = desktop.t("显示未发现", "Show undiscovered")
        for (i, title) in [desktop.t("静态", "Still"), desktop.t("休息", "Rest"), desktop.t("飞行", "Flight"), desktop.t("其他", "Other")].enumerated() {previewAction.setLabel(title, forSegment: i)}
        previewAction.setAccessibilityLabel(desktop.t("素材预览（不计进度）", "Art preview (no progress)"))
        let previewHelp = desktop.t("“其他”播放已有特色或闲置素材，不表示已开放对应行为。预览不解锁鸟种或动作。",
                                    "Other plays existing signature or idle artwork; it does not imply the corresponding behavior is available. Previews unlock neither species nor actions.")
        previewAction.toolTip = previewHelp
        previewAction.setAccessibilityHelp(previewHelp)
        previewView.toolTip = previewHelp
        let locale = Locale(identifier: desktop.language == .chinese ? "zh_CN" : "en_US")
        dateFormatter.locale = locale; dateFormatter.dateStyle = .medium; dateFormatter.timeStyle = .none
        timeFormatter.locale = locale; timeFormatter.dateStyle = .none; timeFormatter.timeStyle = .short
    }

    private func build(in root: NSView) {
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        headingLabel.font = .systemFont(ofSize: 25, weight: .regular)
        for label in [localOnlyLabel, summaryLabel, sourceNoteLabel, persistenceLabel] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
        }
        persistenceLabel.textColor = .labelColor
        persistenceLabel.isHidden = true
        emptyStateLabel.alignment = .center
        emptyStateLabel.font = .systemFont(ofSize: 14)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.isHidden = true
        searchField.delegate = self
        searchField.target = self; searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.identifier = NSUserInterfaceItemIdentifier("observationSearch")
        sourceFilter.segmentCount = SourceFilter.allCases.count
        sourceFilter.trackingMode = .selectOne; sourceFilter.selectedSegment = SourceFilter.collected.rawValue
        sourceFilter.target = self; sourceFilter.action = #selector(sourceChanged(_:))
        sourceFilter.identifier = NSUserInterfaceItemIdentifier("observationSource")
        for index in 0..<sourceFilter.segmentCount { sourceFilter.setWidth(index == 3 ? 116 : 88, forSegment: index) }

        viewSelector.segmentCount = 3; viewSelector.trackingMode = .selectOne
        viewSelector.selectedSegment = selectedView.rawValue
        viewSelector.target = self; viewSelector.action = #selector(viewChanged(_:))
        for index in 0..<3 {viewSelector.setWidth(160, forSegment: index)}
        showUndiscovered.target = self; showUndiscovered.action = #selector(undiscoveredChanged(_:))
        speciesTableView.dataSource = self; speciesTableView.delegate = self
        speciesTableView.rowHeight = 92; speciesTableView.headerView = nil
        speciesTableView.allowsMultipleSelection = false
        speciesTableView.backgroundColor = .white
        let speciesColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("handbookSpecies"))
        speciesColumn.width = 460; speciesColumn.minWidth = 360
        speciesTableView.addTableColumn(speciesColumn)
        speciesTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        speciesTableView.setAccessibilityLabel(desktop.t("手册鸟种列表", "Handbook species"))
        detailText.frame = NSRect(x: 0, y: 0, width: 320, height: 100)
        detailText.isEditable = false; detailText.isSelectable = true
        detailText.font = .systemFont(ofSize: 13); detailText.textContainerInset = NSSize(width: 8, height: 8)
        detailText.isVerticallyResizable = true; detailText.isHorizontallyResizable = false
        detailText.autoresizingMask = [.width]; detailText.textContainer?.widthTracksTextView = true
        detailScroll.documentView = detailText; detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .bezelBorder
        previewAction.segmentCount = 4; previewAction.trackingMode = .selectOne; previewAction.selectedSegment = 0
        previewAction.target = self; previewAction.action = #selector(previewChanged(_:))
        for index in 0..<4 {previewAction.setWidth(72, forSegment: index)}
        tableView.dataSource = self; tableView.delegate = self
        tableView.rowHeight = 64
        tableView.intercellSpacing = NSSize(width: 12, height: 4)
        tableView.backgroundColor = .white
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.identifier = NSUserInterfaceItemIdentifier("observationRecords")
        for (key, width) in [("species", 240.0), ("behavior", 180.0), ("first", 160.0), ("last", 160.0),
                             ("natural", 88.0), ("preview", 78.0), ("manual", 88.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.width = width; column.minWidth = width
            column.resizingMask = [.userResizingMask, .autoresizingMask]
            tableView.addTableColumn(column)
        }
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true; scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true; scrollView.backgroundColor = .white
        scrollView.borderType = .bezelBorder
        let tableContainer = NSView()
        for view in [headingLabel, localOnlyLabel, viewSelector, showUndiscovered, searchField, sourceFilter, summaryLabel,
                     tableContainer, sourceNoteLabel, persistenceLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        for view in [scrollView, emptyStateLabel, detailScroll, previewView, previewAction] {
            view.translatesAutoresizingMaskIntoConstraints = false; tableContainer.addSubview(view)
        }
        var constraints: [NSLayoutConstraint] = []
        for view in [headingLabel, localOnlyLabel, summaryLabel, tableContainer, sourceNoteLabel, persistenceLabel] {
            constraints += [view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
                            view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20)]
        }
        persistenceHeight = persistenceLabel.heightAnchor.constraint(equalToConstant: 0)
        constraints += [
            headingLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            headingLabel.heightAnchor.constraint(equalToConstant: 30),
            localOnlyLabel.topAnchor.constraint(equalTo: headingLabel.bottomAnchor, constant: 4),
            localOnlyLabel.heightAnchor.constraint(equalToConstant: 34),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            viewSelector.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            viewSelector.topAnchor.constraint(equalTo: localOnlyLabel.bottomAnchor, constant: 8),
            viewSelector.heightAnchor.constraint(equalToConstant: 28),
            showUndiscovered.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            showUndiscovered.centerYAnchor.constraint(equalTo: viewSelector.centerYAnchor),
            searchField.topAnchor.constraint(equalTo: viewSelector.bottomAnchor, constant: 10),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            sourceFilter.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 12),
            sourceFilter.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            sourceFilter.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            sourceFilter.heightAnchor.constraint(equalToConstant: 28),
            summaryLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            summaryLabel.heightAnchor.constraint(equalToConstant: 18),
            tableContainer.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
            tableContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
            tableContainer.bottomAnchor.constraint(equalTo: sourceNoteLabel.topAnchor, constant: -10),
            sourceNoteLabel.heightAnchor.constraint(equalToConstant: 34),
            sourceNoteLabel.bottomAnchor.constraint(equalTo: persistenceLabel.topAnchor, constant: -6),
            persistenceHeight,
            persistenceLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            scrollView.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: detailScroll.leadingAnchor, constant: -12),
            detailScroll.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor),
            detailScroll.widthAnchor.constraint(equalToConstant: 320),
            detailScroll.topAnchor.constraint(equalTo: previewAction.bottomAnchor, constant: 6),
            detailScroll.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: detailScroll.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: detailScroll.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: tableContainer.topAnchor),
            previewView.heightAnchor.constraint(equalToConstant: 112),
            previewAction.centerXAnchor.constraint(equalTo: detailScroll.centerXAnchor),
            previewAction.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 2),
            previewAction.heightAnchor.constraint(equalToConstant: 28),
            scrollView.topAnchor.constraint(equalTo: tableContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor),
            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: tableContainer.centerYAnchor),
            emptyStateLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ]
        NSLayoutConstraint.activate(constraints)
        searchField.nextKeyView = sourceFilter; sourceFilter.nextKeyView = tableView; tableView.nextKeyView = searchField
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier, species: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = .systemFont(ofSize: 13)
        field.maximumNumberOfLines = 2
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = field; cell.addSubview(field)
        var leading = cell.leadingAnchor
        var inset: CGFloat = 4
        if species {
            let icon = ObservationJournalSpriteView()
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.imageView = icon; cell.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48)
            ])
            leading = icon.trailingAnchor; inset = 10
        } else if ["natural", "preview", "manual"].contains(identifier.rawValue) {
            field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        } else if ["first", "last"].contains(identifier.rawValue) {
            field.font = .systemFont(ofSize: 12)
            field.textColor = .secondaryLabelColor
        }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leading, constant: inset),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}

private final class ObservationJournalSpriteView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class ObservationJournalNativeWindow: NSWindow {
    weak var journalSearchField: NSSearchField?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f", let journalSearchField {
            makeFirstResponder(journalSearchField)
            journalSearchField.selectText(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
