import AppKit
import BirdingCore

/// A read-only projection of completed observations. Desktop owns delivery and
/// persistence; this window never starts a timer or sends simulation commands.
final class ObservationJournalWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum SourceFilter: Int, CaseIterable {
        case all, natural, preview, manual
        func includes(_ entry: ObservationEntry) -> Bool {
            switch self {
            case .all: return true
            case .natural: return entry.automaticCount > 0
            case .preview: return entry.previewCount > 0
            case .manual: return entry.userCount > 0
            }
        }
    }

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
        let state = RenderState(revision: desktop.observationJournal.revision,
                                query: searchField.stringValue, source: sourceFilter.selectedSegment,
                                language: desktop.language, message: persistenceMessage)
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
        renderedState = state
        renderedRevision = state.revision
        renderCount += 1
        tableView.reloadData()
        if let selection, let row = renderedEntries.firstIndex(where: {
            $0.species == selection.species && $0.behavior == selection.behavior
        }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { tableView.deselectAll(nil) }
        summaryLabel.stringValue = desktop.t("显示 \(renderedEntries.count) / \(entries.count) 条记录",
                                             "Showing \(renderedEntries.count) of \(entries.count) records")
        emptyStateLabel.stringValue = entries.isEmpty
            ? desktop.t("还没有记录\n已完成的行为会在这里留下记录；预览会单独计数。",
                        "No records yet\nCompleted behaviors appear here; previews are counted separately.")
            : desktop.t("没有匹配的记录\n试试其他鸟种、行为或来源，或清除搜索。",
                        "No matching records\nTry another species, behavior or source, or clear the search.")
        emptyStateLabel.isHidden = !renderedEntries.isEmpty
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

    func numberOfRows(in tableView: NSTableView) -> Int { renderedEntries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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
        default: return behavior
        }
    }

    private func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date) + "\n" + timeFormatter.string(from: date)
    }

    private func localizeLabels() {
        window?.title = desktop.t("观察手册", "Observation journal")
        headingLabel.stringValue = window?.title ?? ""
        localOnlyLabel.stringValue = desktop.t("鸟种、已完成行为次数及记录日期仅保存在此 Mac。",
                                              "Species, completed behavior counts and recording dates stay on this Mac.")
        searchField.placeholderString = desktop.t("搜索鸟种或行为", "Search species or behavior")
        searchField.setAccessibilityLabel(desktop.t("搜索观察记录", "Search journal records"))
        searchField.toolTip = desktop.t("搜索中文或英文鸟种与行为 · ⌘F", "Search species and behaviors in Chinese or English · ⌘F")
        sourceFilter.setAccessibilityLabel(desktop.t("记录来源筛选", "Record source filter"))
        let titles = [desktop.t("全部", "All"), desktop.t("自然发生", "Natural"),
                      desktop.t("预览", "Preview"), desktop.t("手动触发", "Manual")]
        for (index, title) in titles.enumerated() { sourceFilter.setLabel(title, forSegment: index) }
        let columns = [desktop.t("鸟种", "Species"), desktop.t("行为", "Behavior"),
                       desktop.t("首次记录", "First recorded"), desktop.t("最近记录", "Last recorded"),
                       desktop.t("自然发生", "Natural"), desktop.t("预览", "Preview"), desktop.t("手动触发", "Manual")]
        for (column, title) in zip(tableView.tableColumns, columns) { column.title = title }
        tableView.setAccessibilityLabel(desktop.t("观察记录列表", "Journal records"))
        sourceNoteLabel.stringValue = desktop.t(
            "来源筛选选择包含该来源的记录；次数和日期始终汇总全部来源。预览不计为自然发生。",
            "Source filters select records containing that source; counts and dates always cover all sources. Previews do not count as natural occurrences.")
        sourceFilter.toolTip = sourceNoteLabel.stringValue
        sourceFilter.setAccessibilityHelp(sourceNoteLabel.stringValue)
        persistenceLabel.setAccessibilityLabel(desktop.t("观察记录保存状态", "Journal saving status"))
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
        sourceFilter.trackingMode = .selectOne; sourceFilter.selectedSegment = 0
        sourceFilter.target = self; sourceFilter.action = #selector(sourceChanged(_:))
        sourceFilter.identifier = NSUserInterfaceItemIdentifier("observationSource")
        for index in 0..<sourceFilter.segmentCount { sourceFilter.setWidth(94, forSegment: index) }

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
        for view in [headingLabel, localOnlyLabel, searchField, sourceFilter, summaryLabel,
                     tableContainer, sourceNoteLabel, persistenceLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        for view in [scrollView, emptyStateLabel] {
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
            searchField.topAnchor.constraint(equalTo: localOnlyLabel.bottomAnchor, constant: 12),
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
            scrollView.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: tableContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor),
            emptyStateLabel.centerXAnchor.constraint(equalTo: tableContainer.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: tableContainer.centerYAnchor),
            emptyStateLabel.widthAnchor.constraint(equalTo: tableContainer.widthAnchor, constant: -40)
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
