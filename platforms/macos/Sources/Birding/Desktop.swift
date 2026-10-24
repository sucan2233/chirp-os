import AppKit
import BirdingCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// Layer-hosted view: only tiny sprite textures change. Avoid AppKit's growing
// full-screen display lists during continuous partial redraw on macOS 26.
final class DesktopView: NSView {
    weak var controller: DesktopController?
    var desktopRect: CGRect = .zero
    private var sprites: [CALayer] = []
    private let propRenderer=ScenePropRenderer()
    private let fixedPerchRenderer=FixedPerchRenderer()
    private let habitatRenderer=HabitatObjectRenderer()
    private let nameLabel=CATextLayer()
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.isGeometryFlipped = true
        root.backgroundColor = NSColor.clear.cgColor
        root.frame = bounds
        layer = root; wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func updateSprites() {
        guard let controller, let root = layer else { return }
        let snapshot=controller.renderSnapshot()
        let propSnapshot=controller.engine.propSnapshot()
        let immersion=controller.engine.bathImmersionSnapshot()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        propRenderer.update(propSnapshot,on:root,desktopRect:desktopRect)
        fixedPerchRenderer.update(controller.engine.fixedPerchSnapshot(),world:controller.engine.world,on:root,desktopRect:desktopRect)
        habitatRenderer.update(controller.engine.habitatSnapshot(),on:root,desktopRect:desktopRect)
        while sprites.count > snapshot.count { sprites.removeLast().removeFromSuperlayer() }
        while sprites.count < snapshot.count {
            let container = CALayer()
            let texture = CALayer()
            texture.magnificationFilter = .nearest; texture.minificationFilter = .nearest
            container.addSublayer(texture); container.mask = CAShapeLayer()
            root.addSublayer(container); sprites.append(container)
        }
        for (index,bird) in snapshot.enumerated() {
            let container = sprites[index]
            container.name="bird-sprite-\(bird.id.rawValue)"
            let scale = bird.scale
            let side = 48*scale
            let rect = bird.rect
            let pieces = Geometry.visiblePieces(rect,blockers:bird.blockers)
            container.isHidden = !rect.intersects(desktopRect) || pieces.isEmpty
            guard !container.isHidden else { continue }
            container.frame = rect.offsetBy(dx:-desktopRect.minX,dy:-desktopRect.minY)
            let texture = container.sublayers![0]
            texture.bounds = CGRect(x:0,y:0,width:side,height:side)
            texture.position = CGPoint(x:side/2,y:side/2)
            texture.setAffineTransform(CGAffineTransform(scaleX:bird.facingRight ? 1 : -1,y:1))
            texture.contents = controller.arts[bird.species]!.frames[bird.frameName]
            let path = CGMutablePath()
            for piece in pieces { path.addRect(piece.offsetBy(dx:-rect.minX,dy:-rect.minY)) }
            let mask = container.mask as! CAShapeLayer
            mask.frame = CGRect(origin:.zero,size:rect.size)
            mask.path = path; mask.fillColor = NSColor.black.cgColor
            HabitatObjectRenderer.applyImmersion(immersion[bird.id],to:mask,birdRect:rect)
        }
        if nameLabel.superlayer == nil {
            nameLabel.fontSize=13;nameLabel.alignmentMode = .center
            nameLabel.foregroundColor=NSColor.white.cgColor
            nameLabel.backgroundColor=NSColor.black.withAlphaComponent(0.8).cgColor
            nameLabel.cornerRadius=6;nameLabel.contentsScale=window?.backingScaleFactor ?? 2
            root.addSublayer(nameLabel)
        }
        nameLabel.zPosition=1000
        nameLabel.isHidden=true
        if let hovered=controller.hoveredBird,let id=controller.engine.id(of:hovered),
           let bird=snapshot.first(where:{$0.id==id && $0.hoverable}),desktopRect.contains(bird.position) {
            let text=controller.language.name(bird.species)
            let width=min(desktopRect.width,ceil((text as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:13)]).width)+20)
            let pixel=controller.arts[bird.species]!.topPixel(frame:bird.frameName)
            let top=bird.position.y+(CGFloat(pixel)+bird.hopOffset-39)*bird.scale
            let x=min(desktopRect.maxX-width,max(desktopRect.minX,bird.position.x-width/2))
            let y=max(desktopRect.minY,top-28)
            nameLabel.frame=CGRect(x:x-desktopRect.minX,y:y-desktopRect.minY,width:width,height:23)
            nameLabel.string=text;nameLabel.isHidden=false
        }
        // Keep the physical sibling order consistent with zPosition too.
        // Software layer captures do not implement all CA compositing rules;
        // a newly appended rear basin must never paint over an existing bird.
        if propSnapshot.contains(where:{$0.kind == .leafToken || $0.kind == .insect}) || controller.engine.habitatSnapshot().contains(where:{$0.kind == .bath}) {
            root.sublayers=(root.sublayers ?? []).enumerated().sorted {a,b in
                a.element.zPosition==b.element.zPosition ? a.offset<b.offset:a.element.zPosition<b.element.zPosition
            }.map(\.element)
        }
        CATransaction.commit()
    }

}

final class DesktopController: NSObject {
    var loginService: LoginItemManaging = SystemLoginItem()
    var loginItem: NSMenuItem?
    var loginApprovalItem: NSMenuItem?
    let art = BirdArt()
    let arts = Dictionary(uniqueKeysWithValues: SpeciesID.allCases.map { ($0, BirdArt(species:$0)) })
    lazy var frameCapabilities=arts.mapValues{Set($0.frames.keys)}
    let engine:BehaviorEngine
    override init() {
        engine=BehaviorEngine(recordInputs:CommandLine.arguments.contains("--record-behavior"))
        super.init()
    }
    /// Isolated native fixtures keep ordinary routing and scheduler randomness
    /// reproducible without changing the production controller's random seed.
    init(verificationSeed:UInt64) {
        engine=BehaviorEngine(seed:verificationSeed)
        super.init()
    }
    var settings:BirdSettings {
        get {engine.settings}
        set {engine.applySettings(newValue)}
    }
    var catalog: SpeciesCatalog { settings.catalog }
    var preferences = UserDefaults.standard
    var isDevelopmentBuild:Bool {Bundle.main.object(forInfoDictionaryKey:"ChirpOSDevelopmentBuild") as? Bool == true}
    var language = AppLanguage.chinese
    var gallery:SpeciesGallery?
    var updater:UpdateController?
    var settingsWindow: SpeciesSettingsWindow?
    var settingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Birding/settings.json")
    var legacyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Birding/species.json")
    var visitorMemoryPersistenceEnabled=VisitorMemoryPersistence.automaticEnabled(arguments:CommandLine.arguments)
    var visitorMemoryURL=VisitorMemoryPersistence.defaultURL
    var visitorMemoryPersistence:VisitorMemoryPersistence?
    let observationJournal=ObservationJournal()
    var observationWindow:ObservationJournalWindow?
    var observationJournalURL=ObservationJournalPersistence.defaultURL
    var observationJournalPersistenceEnabled=ObservationJournalPersistence.automaticEnabled(arguments:CommandLine.arguments)
    var observationPersistence:ObservationJournalPersistence?
    var observationDate:()->Date={Date()}
    // Isolated native fixtures supply deterministic input; production samples AppKit.
    var pointerButtonsDown:()->Bool={NSEvent.pressedMouseButtons != 0}
    func t(_ zh:String,_ en:String) -> String { language.text(zh,en) }
    func spriteScale(for bird: Bird) -> CGFloat { scale * bird.profile.relativeScale }
    func loadSpeciesConfig() throws {
        settings = try BirdSettings.load(from:settingsURL,legacyURL:legacyURL)
    }
    func applySettings(_ value:BirdSettings) throws {
        var saved=value;saved.pendingSpecies=[]
        try saved.save(to:settingsURL)
        settings = saved
        hoverTracker=HoverTracker<BirdID>();hoveredBird=nil
    }
    @objc func showSpeciesGallery() {
        if gallery == nil {gallery=SpeciesGallery(desktop:self)}
        gallery?.showWindow(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showSpeciesSettings() {
        if let settingsWindow, settingsWindow.window?.isVisible == true {
            settingsWindow.window?.makeKeyAndOrderFront(nil)
        } else {
            settingsWindow = SpeciesSettingsWindow(desktop:self)
            settingsWindow?.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps:true)
    }
    @objc func toggleLanguage() {
        language = language == .chinese ? .english : .chinese
        preferences.set(language.rawValue,forKey:"appLanguage")
        makeMenu(); settingsWindow?.relocalize(); observationWindow?.relocalize()
    }
    func updateStatusLine() {
        let passing=engine.passingCount,departing=engine.departingCount
        statusLine.title = t("桌面鸟群 · \(residentCount) 只 · \(departing) 只正在离开 · \(passing) 只过境",
                             "Birds · \(residentCount) visiting · \(departing) departing · \(passing) passing")
    }
    var hoverTracker=HoverTracker<BirdID>()
    var hoveredID:BirdID?
    var hoveredBird:Bird? {
        get {hoveredID.flatMap{engine.bird($0)}}
        set {hoveredID=newValue.flatMap{engine.id(of:$0)}}
    }
    var lastBehaviorEvent:UInt64=0
    var globalMouseMonitor:Any?
    var localMouseMonitor:Any?
    // Mutable Bird access is retained only for the existing desktop fixtures.
    var birds:[Bird] {
        get {engine.birds}
        set {engine.installFixtureBirds(newValue)}
    }
    var surfaces: [Surface] = [] // Real windows front to back, followed by non-occluding virtual ground.
    var panels: [OverlayPanel] = []
    var views: [DesktopView] = []
    var population:Population {
        get {engine.population}
        set {engine.population=newValue}
    }
    var populationMenu: NSMenu!
    var populationItem: NSMenuItem!
    var automaticPopulation = true
    var lastArrivalPosition:CGPoint? {engine.lastArrivalPosition}
    var arrivalCount:Int {engine.arrivalCount}
    var departureCount:Int {engine.departureCount}
    var scale: CGFloat = 1
    var paused:Bool {
        get {engine.paused}
        set {engine.handle(.pause(newValue))}
    }
    var timer: Timer?
    var lastTick = ProcessInfo.processInfo.systemUptime
    var lastSample: Double = 0
    var lastDiagnostic: Double = 0
    var status: NSStatusItem!
    var statusLine: NSMenuItem!
    var diagnosticPath: String?
    var activityClock=LocalActivityClock()
    var recordingPath:String?
    var integration: IntegrationCheck?
    var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 900 }
    var screenRects: [CGRect] { NSScreen.screens.map { Geometry.quartz($0.visibleFrame, primaryHeight: primaryHeight) } }
    var displayRects: [CGRect] { NSScreen.screens.map { Geometry.quartz($0.frame, primaryHeight: primaryHeight) } }
    func groundSurfaces() -> [Surface] {
        NSScreen.screens.compactMap { screen in
            guard let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return Geometry.ground(id:UInt32.max-number.uint32Value,display:Geometry.quartz(screen.frame,primaryHeight:primaryHeight),workArea:Geometry.quartz(screen.visibleFrame,primaryHeight:primaryHeight))
        }
    }
    var residentCount:Int {engine.residentCount}
    func start() {
        // Keep existing local preferences when first switching to the isolated
        // development bundle identity. Species settings already share one file.
        if isDevelopmentBuild,let previous=preferences.persistentDomain(forName:"dev.birding.desktop") {
            for key in ["appLanguage","populationLower","populationUpper"] where preferences.object(forKey:key) == nil {
                if let value=previous[key] {preferences.set(value,forKey:key)}
            }
        }
        language = AppLanguage(rawValue:preferences.string(forKey:"appLanguage") ?? "zh") ?? .chinese
        if let saved = PopulationRange(lower: UserDefaults.standard.integer(forKey:"populationLower"), upper: UserDefaults.standard.integer(forKey:"populationUpper")) {
            population = Population(range:saved)
        }
        do { try loadSpeciesConfig() } catch { NSLog("Birding species configuration: %@; using bundled defaults",error.localizedDescription) }
        loadVisitorMemory()
        loadObservationJournal()
        makeMenu(); rebuildScreens(); startMouseMonitoring()
        if !CommandLine.arguments.contains(where:{$0.hasPrefix("--verify") || $0 == "--integration"}) {DispatchQueue.main.async { [weak self] in self?.promptNewSpecies() }}
        sampleWindows(dt: 1.0/30)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildScreens), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(waking), name: NSWorkspace.didWakeNotification, object: nil)
        startTimer()
    }
    func startTimer() {
        timer?.invalidate()
        lastTick = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.003
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    @objc func sleeping() { engine.handle(.cancelAmbient(.sleep));timer?.invalidate() }
    @objc func waking() { lastSample = 0; startTimer() }
    @objc func spaceChanged() { engine.handle(.cancelAmbient(.spaceChanged));lastSample = 0; sampleWindows(dt: 1); for v in views { v.needsDisplay = true } }
    @objc func rebuildScreens() {
        engine.handle(.cancelFoodTrayPlacement)
        engine.handle(.cancelBathPlacement)
        engine.handle(.cancelCarryLeafPlacement)
        engine.handle(.cancelInsectCatchPreview)
        engine.handle(.cancelAmbient(.screensChanged))
        panels.forEach { $0.orderOut(nil) }; panels.removeAll(); views.removeAll()
        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false; panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            panel.animationBehavior = .none
            let view = DesktopView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.controller = self; view.desktopRect = Geometry.quartz(screen.frame, primaryHeight: primaryHeight)
            panel.contentView = view; panel.orderFrontRegardless()
            panels.append(panel); views.append(view)
        }
        let grounds=groundSurfaces()
        surfaces.removeAll { $0.isGround };surfaces += grounds
        syncWorld()
        engine.reconcileLayout()
    }
    func sampleWindows(dt: Double) {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // Higher levels (menus, security/lock screen) already cover our panel in WindowServer.
        // Software masking is only needed for windows that the floating overlay covers.
        let own = ProcessInfo.processInfo.processIdentifier
        surfaces = list.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != own,
                  let layer = info[kCGWindowLayer as String] as? Int, layer >= 0, layer <= NSWindow.Level.floating.rawValue,
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.05,
                  let raw = info[kCGWindowBounds as String] as? [String:Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary), rect.width > 1, rect.height > 1 else { return nil }
            if layer == NSWindow.Level.floating.rawValue,
               ["dev.birding.desktop","dev.birding.desktop.development"].contains(NSRunningApplication(processIdentifier:pid)?.bundleIdentifier ?? "") { return nil }
            return Surface(id: id, pid: pid, rect: rect, layer: layer)
        }
        surfaces += groundSurfaces()
        syncWorld(sampleDT:dt)
    }
    func bounds(of bird:Bird) -> CGRect {syncWorld();return engine.bounds(of:bird)}
    @discardableResult
    func chooseDestination(_ bird:Bird,entering:Bool=false,avoiding:CGPoint?=nil) -> Bool {
        syncWorld();return engine.route(bird,entering:entering,avoiding:avoiding)
    }
    func bringInBird() {syncWorld();engine.bringInBird()}
    func sendAway(_ bird:Bird) {syncWorld();engine.sendAway(bird)}
    func advanceBirds(_ dt:Double,at point:CGPoint?=nil,buttonsDown:Bool?=nil) {
        syncWorld(at:point,buttonsDown:buttonsDown)
        engine.populationEnabled=automaticPopulation && integration == nil
        engine.ambientEnabled=engine.populationEnabled && !CommandLine.arguments.contains(where:{$0.hasPrefix("--verify") || $0 == "--integration"})
        engine.autonomousRouting=integration == nil
        engine.advance(dt)
        consumeBehaviorEvents()
        settingsWindow?.refreshFoodTrayControls()
        settingsWindow?.refreshBathControls()
        settingsWindow?.refreshLeafCarryControls()
        settingsWindow?.refreshInsectCatchControls()
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0,now-lastTick)); lastTick = now
        if now-lastSample >= 1.0/30 {
            sampleWindows(dt: lastSample>0 ? now-lastSample:1); lastSample = now
        }
        advanceBirds(dt)
        persistVisitorMemoryIfNeeded(now:now)
        persistObservationJournalIfNeeded(now:now)
        updateHover(now:now)
        for view in views { view.updateSprites() }
        if now-lastDiagnostic > 1 {
            lastDiagnostic = now
            updateStatusLine()
            if let diagnosticPath { writeDiagnostics(to: diagnosticPath) }
        }
    }
    func writeDiagnostics(to path: String) {
        let grounds=Set(surfaces.filter(\.isGround).map(\.id))
        let rendered=Dictionary(uniqueKeysWithValues:engine.renderSnapshot().map{($0.id,$0)})
        let statusFrame=status?.button?.window?.frame ?? .zero
        let obj: [String:Any] = ["windowCount": surfaces.filter{!$0.isGround}.count, "groundCount":surfaces.filter(\.isGround).count, "overlayCount":panels.count,
            "bundlePath":Bundle.main.bundleURL.path,"developmentBuild":isDevelopmentBuild,
            "statusItemVisible":status?.isVisible ?? false,"statusItemHasImage":status?.button?.image != nil,
            "statusItemFrame":[statusFrame.minX,statusFrame.minY,statusFrame.width,statusFrame.height],
            "statusItemOnScreen":NSScreen.screens.contains{$0.frame.intersects(statusFrame)},
            "renderer":"Core Animation sprite layers",
            "populationRange":[population.range.lower,population.range.upper],
            "residentCount":residentCount,"departingCount":engine.departingCount,
            "passingCount":engine.passingCount,"pendingCount":engine.pendingCount,
            "behaviorSeed":String(engine.seed),"behaviorTime":engine.time,
            "activityRhythm":settings.activityRhythm.rawValue,"localMinuteOfDay":engine.world.localMinuteOfDay ?? -1,
            "activeBehaviors":engine.activeRunCount,"leasedBirds":engine.leasedBirdCount,"reservedLandings":engine.reservedLandingCount,
            "sceneProps":engine.scenePropCount,"pendingLeafPlay":engine.hasLeafPreview,
            "behaviorEvents":engine.events.map {event in
                ["sequence":event.sequence,"time":event.time,"type":event.type.rawValue,
                 "run":event.runID?.rawValue ?? 0,"kind":event.kind?.rawValue ?? "",
                 "source":event.source.rawValue,"reason":event.reason?.rawValue ?? "",
                 "birds":event.participants.map(\.rawValue)] as [String:Any]
            },
            "ecology":birds.compactMap { bird -> [String:Any]? in
                guard let id=engine.id(of:bird),let state=engine.ecology(of:bird) else {return nil}
                let visitor=engine.visitor(of:bird)
                return ["bird":id.rawValue,"disturbance":state.disturbance,"quietTime":state.quietTime,
                    "visitorID":visitor?.id ?? "","familiarity":state.familiarity,
                    "storedFamiliarity":visitor?.familiarity ?? 0,"visits":visitor?.visits ?? 0,
                    "temperament":["boldness":state.temperament.boldness,"curiosity":state.temperament.curiosity,
                        "sociability":state.temperament.sociability,"activity":state.temperament.activity],
                    "cooldowns":Dictionary(uniqueKeysWithValues:state.cooldowns.map{($0.key.rawValue,$0.value)})]
            },
            "arrivals":arrivalCount,"departures":departureCount,
            "spriteScale":scale, "flightSpeedMultiplier":Bird.flightSpeedMultiplier,
            "nonactivating":panels.allSatisfy{ !$0.canBecomeKey && !$0.canBecomeMain && $0.ignoresMouseEvents },
            "birds":birds.map { bird -> [String:Any] in
                let visitor=engine.visitor(of:bird)
                return ["id":engine.id(of:bird)?.rawValue ?? 0,"role":engine.role(of:bird)?.rawValue ?? "",
                    "behavior":engine.behavior(of:bird)?.rawValue ?? "","species":bird.profile.id.rawValue,
                    "name":bird.profile.name,"relativeScale":bird.profile.relativeScale,"state":bird.state.rawValue,
                    "departing":bird.isDeparting,"onGround":bird.hostID.map{grounds.contains($0)} ?? false,
                    "host":bird.hostID ?? 0,"depth":bird.depthID ?? 0,"x":bird.position.x,"y":bird.position.y,
                    "frame":engine.id(of:bird).flatMap{rendered[$0]?.frameName} ?? bird.frameName,
                    "followed":bird.followedDistance,"startles":bird.startledCount,"landings":bird.landedCount,
                    "visitorID":visitor?.id ?? "","familiarity":engine.ecology(of:bird)?.familiarity ?? 0,
                    "storedFamiliarity":visitor?.familiarity ?? 0,"visits":visitor?.visits ?? 0]
            }]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted,.sortedKeys]) { try? data.write(to: URL(fileURLWithPath:path), options: .atomic) }
    }
    func makeMenu() {
        if status == nil {
            status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            status.autosaveName="ChirpOS.Main"
            status.isVisible=true
        }
        // Template artwork remains legible in light, dark and tinted menu bars.
        let icon=NSImage(systemSymbolName:"bird.fill",accessibilityDescription:t("啾啾","ChirpOS"))
            ?? NSImage(cgImage:art.frames["stand"]!,size:NSSize(width:18,height:18))
        icon.size=NSSize(width:18,height:18);icon.isTemplate=true
        status.button?.image = updater?.decorate(icon) ?? icon
        status.button?.imageScaling = .scaleProportionallyDown
        status.button?.toolTip = updater?.pending.map { t("啾啾 · 更新 \($0.release.version) 已就绪","ChirpOS · Update \($0.release.version) ready") }
            ?? (isDevelopmentBuild ? t("啾啾测试版 · 桌面观鸟","ChirpOS Dev · Desktop Birdwatching"):t("啾啾 · 桌面观鸟","ChirpOS · Desktop Birdwatching"))
        status.button?.setAccessibilityLabel(isDevelopmentBuild ? t("啾啾测试版菜单","ChirpOS Dev menu"):t("啾啾菜单","ChirpOS menu"))
        let menu = NSMenu()
        menu.delegate = self
        statusLine = NSMenuItem(title: t("桌面鸟群 · 等待第一只鸟飞来","Birds · Waiting for the first arrival"), action: nil, keyEquivalent: "")
        menu.addItem(statusLine); menu.addItem(.separator())
        add(menu,paused ? t("继续动画","Resume animation") : t("暂停动画","Pause animation"),#selector(togglePause),"p")
        add(menu,t("让小鸟飞一会儿","Let the birds fly"),#selector(scatter),"f")
        add(menu,t("大小：1× / 1.5×","Size: 1× / 1.5×"),#selector(toggleScale),"")
        populationItem = NSMenuItem(title:"",action:nil,keyEquivalent:"")
        populationMenu = NSMenu()
        for (index,label) in [t("3–5 只","3–5 birds"),t("8–12 只","8–12 birds"),t("15–20 只","15–20 birds")].enumerated() {
            let item = NSMenuItem(title:label,action:#selector(selectPopulation(_:)),keyEquivalent:"")
            item.target = self; item.tag = index; populationMenu.addItem(item)
        }
        populationMenu.addItem(.separator())
        add(populationMenu,t("自定义范围…","Custom range…"),#selector(customPopulation),"")
        populationItem.submenu = populationMenu; menu.addItem(populationItem)
        refreshPopulationMenu()
        menu.addItem(.separator())
        add(menu,t("图鉴…","Field guide…"),#selector(showSpeciesGallery),"")
        add(menu,t("观察手册…","Observation journal…"),#selector(showObservationJournal),"")
        add(menu,t("鸟种设置…","Bird settings…"),#selector(showSpeciesSettings),"")
        addLoginItem(to:menu)
        add(menu,language.switchTitle,#selector(toggleLanguage),"")
        add(menu,t("打开项目说明","Open README"),#selector(openReadme),"")
        updater?.addMenuItems(to:menu)
        add(menu,t("退出啾啾","Quit ChirpOS"),#selector(quit),"q")
        status.menu = menu
        updateStatusLine()
        if isDevelopmentBuild {menu.insertItem(NSMenuItem(title:t("啾啾测试版 · 本地开发","ChirpOS Dev · Local build"),action:nil,keyEquivalent:""),at:0)}
        let main=NSMenu()
        let application=NSMenuItem();main.addItem(application);application.submenu=NSMenu()
        add(application.submenu!,t("观察手册…","Observation journal…"),#selector(showObservationJournal),"j")
        application.submenu!.addItem(.separator())
        add(application.submenu!,t("退出啾啾","Quit ChirpOS"),#selector(quit),"q")
        let editItem=NSMenuItem(title:t("编辑","Edit"),action:nil,keyEquivalent:"")
        let edit=NSMenu(title:editItem.title);editItem.submenu=edit;main.addItem(editItem)
        for (title,action,key) in [(t("撤销","Undo"),"undo:","z"),(t("剪切","Cut"),"cut:","x"),(t("复制","Copy"),"copy:","c"),(t("粘贴","Paste"),"paste:","v"),(t("全选","Select All"),"selectAll:","a")] {
            edit.addItem(NSMenuItem(title:title,action:Selector(action),keyEquivalent:key))
        }
        NSApp.mainMenu=main
    }
    func restoreStatusItem() {
        makeMenu()
        status.isVisible=true
    }
    func add(_ menu: NSMenu,_ title: String,_ action: Selector,_ key: String) {
        let item = NSMenuItem(title:title,action:action,keyEquivalent:key); item.target = self; menu.addItem(item)
    }
    @objc func togglePause(_ sender: NSMenuItem) { paused.toggle();sender.title = paused ? t("继续动画","Resume animation") : t("暂停动画","Pause animation") }
    @objc func scatter() { syncWorld();engine.handle(.scatter) }
    @objc func toggleScale() { scale = scale == 1 ? 1.5 : 1; for v in views { v.needsDisplay = true } }
    let populationPresets = [PopulationRange.standard,PopulationRange(lower:8,upper:12)!,PopulationRange(lower:15,upper:20)!]
    func refreshPopulationMenu() {
        populationItem.title = t("鸟群范围：\(population.range.lower)–\(population.range.upper) 只","Population: \(population.range.lower)–\(population.range.upper) birds")
        for item in populationMenu.items where item.action == #selector(selectPopulation(_:)) {
            item.state = populationPresets[item.tag] == population.range ? .on : .off
        }
    }
    func applyPopulationRange(_ range: PopulationRange) {
        population.setRange(range)
        UserDefaults.standard.set(range.lower,forKey:"populationLower")
        UserDefaults.standard.set(range.upper,forKey:"populationUpper")
        refreshPopulationMenu()
    }
    @objc func selectPopulation(_ sender: NSMenuItem) { applyPopulationRange(populationPresets[sender.tag]) }
    @objc func customPopulation() {
        let alert = NSAlert()
        alert.messageText = t("设置鸟群数量范围","Set population range")
        alert.informativeText = t("输入最少和最多数量（1–50）。小鸟会陆续飞入或飞走，逐渐达到这个范围。","Enter minimum and maximum counts (1–50). Birds will gradually arrive or leave to reach this range.")
        alert.addButton(withTitle:t("保存","Save")); alert.addButton(withTitle:t("取消","Cancel"))
        let form = NSView(frame:NSRect(x:0,y:0,width:280,height:62))
        let lower = NSTextField(string:String(population.range.lower))
        let upper = NSTextField(string:String(population.range.upper))
        for (index,pair) in [(t("最少","Minimum"),lower),(t("最多","Maximum"),upper)].enumerated() {
            let label = NSTextField(labelWithString:pair.0)
            label.frame = NSRect(x:index*140,y:36,width:120,height:20)
            pair.1.frame = NSRect(x:index*140,y:4,width:120,height:26)
            form.addSubview(label); form.addSubview(pair.1)
        }
        alert.accessoryView = form
        NSApp.activate(ignoringOtherApps:true)
        while alert.runModal() == .alertFirstButtonReturn {
            if let lo = Int(lower.stringValue.trimmingCharacters(in:.whitespaces)),
               let hi = Int(upper.stringValue.trimmingCharacters(in:.whitespaces)),
               let range = PopulationRange(lower:lo,upper:hi) {
                applyPopulationRange(range); return
            }
            alert.informativeText = t("请输入 1–50 的整数，最多数量不能小于最少数量。","Enter integers from 1 to 50. Maximum must be at least minimum.")
        }
    }
    @objc func openReadme() {
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.open(root.appendingPathComponent("README.md"))
    }
    @objc func quit() { engine.handle(.cancelAmbient(.shutdown));stopMouseMonitoring();NSApp.terminate(nil) }
}
