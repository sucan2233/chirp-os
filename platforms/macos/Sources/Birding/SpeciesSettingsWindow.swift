import AppKit
import BirdingCore

final class SettingsContentView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect:NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.intersection(bounds).fill() }
}
final class DebugUnlockView:NSView {
    var unlock:(()->Void)?
    private var lastDoubleClick:TimeInterval?
    override func mouseDown(with event:NSEvent) {
        guard event.clickCount > 0,event.clickCount % 2 == 0 else { return }
        if let lastDoubleClick,event.timestamp-lastDoubleClick <= 3 { unlock?();self.lastDoubleClick=nil }
        else { lastDoubleClick=event.timestamp }
    }
}
final class SpeciesSettingsWindow: NSWindowController, NSTextFieldDelegate {
    unowned let desktop: DesktopController
    var draft: BirdSettings
    var sliders:[NSSlider] = [], fields:[NSTextField] = [], locks:[NSButton] = []
    var detailFields:[[NSTextField]] = []
    var message: NSTextField!
    var tabs: NSTabView!
    var hoverDelaySlider:NSSlider!
    var hoverDelayField:NSTextField!
    var pointerVisitsButton:NSButton!
    var pointerFollowButton:NSButton!
    var flockPassesButton:NSButton!
    var socialInteractionsButton:NSButton!
    var previewSocialGreetingButton:NSButton!
    var previewSideBySideButton:NSButton!
    var previewGiveWayButton:NSButton!
    var previewPairedTakeoffButton:NSButton!
    var ambientFrequencyPopup:NSPopUpButton!
    var perchActionsButton:NSButton!
    var passiveAttentionButton:NSButton!
    var previewWatchButton:NSButton!
    var previewAlertButton:NSButton!
    var previewRestButton:NSButton!
    var previewPreenButton:NSButton!
    var leafPlayButton:NSButton!
    var ambientLeafPlayButton:NSButton!
    var releaseLeafButton:NSButton!
    var clearLeafButton:NSButton!
    private var debugEnabled=false
    private var debugButton:NSButton!
    var language: AppLanguage { desktop.language }
    func t(_ zh:String,_ en:String) -> String { language.text(zh,en) }
    init(desktop:DesktopController) {
        self.desktop = desktop; self.draft = desktop.settings
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:690),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        super.init(window:window)
        build(); window.center()
    }
    required init?(coder:NSCoder) { fatalError() }
    @discardableResult func label(_ text:String,_ rect:NSRect,in view:NSView,size:CGFloat = 13) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString:text); l.font = .systemFont(ofSize:size); l.frame = rect; view.addSubview(l); return l
    }
    func button(_ title:String,_ action:Selector,_ rect:NSRect,in view:NSView) -> NSButton {
        let b = NSButton(title:title,target:self,action:action); b.bezelStyle = .rounded; b.frame = rect; view.addSubview(b); return b
    }
    func scroll(_ content:NSView) -> NSScrollView {
        let view=NSScrollView(frame:NSRect(x:0,y:0,width:780,height:446))
        view.hasVerticalScroller=true; view.documentView=content
        return view
    }
    func build() {
        let selected = tabs?.indexOfTabViewItem(tabs!.selectedTabViewItem!) ?? 0
        sliders=[]; fields=[]; locks=[]; detailFields=[]
        let root = SettingsContentView(frame:NSRect(x:0,y:0,width:840,height:690)); root.wantsLayer=true; window!.contentView = root
        window!.title = t("鸟种设置","Bird Settings")
        label(t("让哪些鸟来做客？","Which birds should visit?"),NSRect(x:26,y:22,width:760,height:35),in:root,size:25)
        label(t("鸟种参数影响新飞入的小鸟；交互设置保存后立即生效。","Species settings affect new arrivals; interaction settings apply immediately after saving."),NSRect(x:26,y:65,width:785,height:40),in:root)
        let probabilityButton=button(t("出现概率","Arrival probabilities"),#selector(selectPage(_:)),NSRect(x:135,y:112,width:175,height:30),in:root); probabilityButton.tag=0
        let behaviorButton=button(t("体型与动作","Size & behavior"),#selector(selectPage(_:)),NSRect(x:320,y:112,width:150,height:30),in:root); behaviorButton.tag=1
        let interactionButton=button(t("交互","Interaction"),#selector(selectPage(_:)),NSRect(x:480,y:112,width:140,height:30),in:root); interactionButton.tag=2
        debugButton=button(t("调试","Debug"),#selector(selectPage(_:)),NSRect(x:630,y:112,width:100,height:30),in:root)
        debugButton.tag=3;debugButton.isHidden = !debugEnabled
        let unlock=DebugUnlockView(frame:NSRect(x:790,y:10,width:40,height:44))
        unlock.unlock={ [weak self] in self?.debugEnabled=true;self?.debugButton.isHidden=false }
        root.addSubview(unlock)
        tabs = NSTabView(frame:NSRect(x:30,y:150,width:780,height:446)); tabs.tabViewType = .noTabsNoBorder; root.addSubview(tabs)
        let probabilityView = SettingsContentView(frame:NSRect(x:0,y:0,width:754,height:CGFloat(110+draft.catalog.species.count*47)))
        let first = NSTabViewItem(identifier:"probabilities"); first.label=t("出现概率","Arrival probabilities"); first.view=scroll(probabilityView); tabs.addTabViewItem(first)
        label(t("鸟种","Species"),NSRect(x:20,y:14,width:240,height:23),in:probabilityView)
        label(t("概率（%）","Probability (%)"),NSRect(x:294,y:14,width:305,height:23),in:probabilityView)
        for (i,entry) in draft.probabilities.entries.enumerated() {
            let y = CGFloat(44+i*47)
            let icon = NSImageView(frame:NSRect(x:16,y:y,width:38,height:38))
            icon.image = NSImage(cgImage:desktop.arts[entry.id]!.frames["stand"]!,size:NSSize(width:38,height:38)); probabilityView.addSubview(icon)
            label(language.name(entry.id),NSRect(x:62,y:y+8,width:222,height:26),in:probabilityView)
            let slider = NSSlider(value:0,minValue:0,maxValue:100,target:self,action:#selector(sliderChanged(_:)))
            slider.isContinuous=true; slider.tag=i; slider.frame=NSRect(x:290,y:y+8,width:236,height:24)
            slider.setAccessibilityLabel(language.name(entry.id)+t(" 概率"," probability")); probabilityView.addSubview(slider); sliders.append(slider)
            let field = NSTextField(frame:NSRect(x:542,y:y+7,width:72,height:25)); field.tag=i; field.delegate=self; field.alignment = .right
            field.setAccessibilityLabel(language.name(entry.id)+t(" 概率百分比"," probability percentage")); probabilityView.addSubview(field); fields.append(field)
            label("%",NSRect(x:620,y:y+10,width:20,height:20),in:probabilityView)
            let lock = NSButton(checkboxWithTitle:t("锁定","Lock"),target:self,action:#selector(lockChanged(_:)))
            lock.tag=i; lock.frame=NSRect(x:657,y:y+7,width:95,height:25); probabilityView.addSubview(lock); locks.append(lock)
        }
        label(t("总计 100.00% · 锁定项不变；其他未锁定项按原比例分配，均为零时平均分配。\n默认频率用于游戏；新增鸟种可在启动提示中选择分配方式。","Total 100.00% · Locked values stay fixed. Other unlocked values redistribute proportionally, or equally when all are zero. Game defaults are estimates. Choose how to allocate new species in the startup prompt."),NSRect(x:20,y:CGFloat(52+draft.catalog.species.count*47),width:710,height:54),in:probabilityView,size:12)
        let detailView = SettingsContentView(frame:probabilityView.frame)
        let second = NSTabViewItem(identifier:"behavior"); second.label=t("体型与动作","Size & behavior"); second.view=scroll(detailView); tabs.addTabViewItem(second)
        let titles = [t("体长 cm","Length cm"),t("振翅 次/秒","Beats / sec"),t("飞速 倍率","Speed ×"),t("最短停留 秒","Min perch s"),t("最长停留 秒","Max perch s")]
        label(t("鸟种","Species"),NSRect(x:20,y:14,width:235,height:25),in:detailView)
        for (j,title) in titles.enumerated() { label(title,NSRect(x:270+j*97,y:14,width:95,height:30),in:detailView,size:11) }
        for (i,entry) in draft.probabilities.entries.enumerated() {
            let p=draft.catalog.profile(entry.id), y=CGFloat(52+i*45)
            label(language.name(entry.id),NSRect(x:20,y:y+3,width:238,height:30),in:detailView)
            var row:[NSTextField]=[]
            for (j,value) in [p.adultLengthCM,p.flapFPS/8,p.speed,p.perchMin,p.perchMax].enumerated() {
                let f=NSTextField(frame:NSRect(x:CGFloat(270+j*97),y:y,width:84,height:26)); f.stringValue=String(value)
                f.tag=100+i*10+j; f.delegate=self; f.alignment = .right; f.setAccessibilityLabel(language.name(entry.id)+" "+titles[j]); detailView.addSubview(f); row.append(f)
            }
            detailFields.append(row)
        }
        label(t("体长以成年鸟为参考；振翅和停留时长是动画参数，可按喜好调整。\n体长 8–110 cm · 振翅 0.5–7.5 次/秒 · 飞速 0.5–2× · 最短 2–300 秒 · 最长不超过 600 秒。","Adult body length sets relative size; animation timing is adjustable.\nLength 8–110 cm · Beats 0.5–7.5/s · Speed 0.5–2× · Minimum perch 2–300s · Maximum ≤600s."),NSRect(x:20,y:CGFloat(52+draft.catalog.species.count*45),width:715,height:55),in:detailView,size:12)
        let interactionView=SettingsContentView(frame:NSRect(x:0,y:0,width:754,height:1620))
        let interaction=NSTabViewItem(identifier:"interaction");interaction.label=t("交互","Interaction");interaction.view=scroll(interactionView);tabs.addTabViewItem(interaction)
        label(t("名字显示","Bird names"),NSRect(x:20,y:20,width:710,height:30),in:interactionView,size:20)
        label(t("鼠标在小鸟身上停留多久后显示名字？","How long should the pointer hover before showing a bird’s name?"),NSRect(x:20,y:66,width:710,height:40),in:interactionView)
        hoverDelaySlider=NSSlider(value:draft.hoverDelay,minValue:0,maxValue:10,target:self,action:#selector(hoverDelayChanged(_:)))
        hoverDelaySlider.isContinuous=true;hoverDelaySlider.frame=NSRect(x:20,y:122,width:490,height:28)
        hoverDelaySlider.setAccessibilityLabel(t("悬停显示名字的等待时间","Bird name hover delay"));interactionView.addSubview(hoverDelaySlider)
        hoverDelayField=NSTextField(frame:NSRect(x:540,y:122,width:80,height:26));hoverDelayField.stringValue=String(format:"%g",draft.hoverDelay)
        hoverDelayField.alignment = .right;hoverDelayField.delegate=self
        hoverDelayField.setAccessibilityLabel(t("悬停等待时间（秒）","Hover delay in seconds"));interactionView.addSubview(hoverDelayField)
        label(t("秒","seconds"),NSRect(x:632,y:125,width:95,height:24),in:interactionView)
        label(t("0–10 秒，支持小数。默认 1 秒；设为 0 可立即显示。\n保存后立即生效，重启应用后保留。点击小鸟可让它换个位置。","0–10 seconds; decimals allowed. Default: 1 second. Set 0 to show immediately.\nApplies after saving and persists across restarts. Click a bird to move it to another spot."),NSRect(x:20,y:178,width:710,height:75),in:interactionView,size:12)
        label(t("偶尔来点小惊喜","Occasional encounters"),NSRect(x:20,y:266,width:710,height:30),in:interactionView,size:20)
        pointerVisitsButton=NSButton(checkboxWithTitle:t("偶尔绕鼠标飞一圈","Occasionally circle the pointer"),target:self,action:#selector(ambientSettingsChanged))
        pointerVisitsButton.frame=NSRect(x:20,y:310,width:710,height:26);pointerVisitsButton.state=draft.pointerVisits ? .on:.off;interactionView.addSubview(pointerVisitsButton)
        pointerFollowButton=NSButton(checkboxWithTitle:t("绕飞时跟随鼠标移动","Follow pointer movement while circling"),target:self,action:#selector(ambientSettingsChanged))
        pointerFollowButton.frame=NSRect(x:40,y:346,width:690,height:26);pointerFollowButton.state=draft.pointerFollowEnabled ? .on:.off
        pointerFollowButton.isEnabled=draft.pointerVisits;interactionView.addSubview(pointerFollowButton)
        flockPassesButton=NSButton(checkboxWithTitle:t("偶尔有 3–5 只鸟结伴飞过","Occasionally let 3–5 birds fly past together"),target:self,action:#selector(ambientSettingsChanged))
        flockPassesButton.frame=NSRect(x:20,y:382,width:710,height:26);flockPassesButton.state=draft.flockPasses ? .on:.off;interactionView.addSubview(flockPassesButton)
        socialInteractionsButton=NSButton(checkboxWithTitle:t("双鸟互动","Two-bird interactions"),target:self,action:#selector(ambientSettingsChanged))
        socialInteractionsButton.frame=NSRect(x:20,y:418,width:710,height:26);socialInteractionsButton.state=draft.socialInteractions ? .on:.off;interactionView.addSubview(socialInteractionsButton)
        label(t("发生频率","Frequency"),NSRect(x:20,y:465,width:120,height:26),in:interactionView)
        ambientFrequencyPopup=NSPopUpButton(frame:NSRect(x:145,y:459,width:420,height:32),pullsDown:false)
        ambientFrequencyPopup.addItems(withTitles:[t("低 · 每 3–6 分钟尝试一次（默认）","Low · One attempt every 3–6 minutes (default)"),t("中 · 每 1.5–3 分钟尝试一次","Medium · One attempt every 1.5–3 minutes"),t("高 · 每 45–90 秒尝试一次","High · One attempt every 45–90 seconds")])
        ambientFrequencyPopup.selectItem(at:AmbientFrequency.allCases.firstIndex(of:draft.ambientFrequency)!)
        ambientFrequencyPopup.target=self;ambientFrequencyPopup.action=#selector(ambientSettingsChanged)
        ambientFrequencyPopup.setAccessibilityLabel(t("偶发动作频率","Encounter frequency"));interactionView.addSubview(ambientFrequencyPopup)
        label(t("绕飞、过境、双鸟互动和少见的自动落叶共享出现频率，每次至多一种，条件不合适时跳过。绕飞需鼠标静止 3 秒且有空间；默认移动或点击结束，开启跟随后移动继续、点击结束。过境鸟不占常驻数量。","Pointer visits, passing flocks, two-bird interactions and rare automatic leaves share the encounter frequency: at most one per attempt; unsuitable conditions are skipped. Circling needs 3 seconds of stillness and space. Moving or clicking ends it; following allows movement until a click. Passing birds do not count as residents."),NSRect(x:20,y:507,width:710,height:70),in:interactionView,size:12)
        label(t("双鸟互动包括招呼、并排停靠、让座和结伴起飞，需要两只距离合适、在可见边缘停稳的小鸟及足够空间。四种动作共用此开关，默认开启，保存后生效。","Two-bird interactions include greetings, side-by-side perching, giving way and paired takeoff. They need two suitably spaced birds settled on visible edges, with room to move. This switch controls all four; on by default and applied after saving."),NSRect(x:20,y:584,width:710,height:76),in:interactionView,size:12)
        _=button(t("预览绕鼠标","Preview pointer visit"),#selector(previewPointerVisit),NSRect(x:20,y:674,width:210,height:32),in:interactionView)
        _=button(t("预览鸟群过境","Preview passing flock"),#selector(previewFlockPass),NSRect(x:250,y:674,width:210,height:32),in:interactionView)
        previewSocialGreetingButton=button(t("预览双鸟招呼","Preview two-bird greeting"),#selector(previewSocialGreeting),NSRect(x:480,y:674,width:250,height:32),in:interactionView)
        previewSideBySideButton=button(t("预览并排停靠","Preview side-by-side perch"),#selector(previewSideBySide),NSRect(x:20,y:720,width:210,height:32),in:interactionView)
        previewGiveWayButton=button(t("预览让座","Preview giving way"),#selector(previewGiveWay),NSRect(x:250,y:720,width:210,height:32),in:interactionView)
        previewPairedTakeoffButton=button(t("预览结伴起飞","Preview paired takeoff"),#selector(previewPairedTakeoff),NSRect(x:480,y:720,width:250,height:32),in:interactionView)
        label(t("预览使用已保存的设置。双鸟互动预览不会生成临时鸟或改变鸟的数量；没有合适同伴或空间不足时会在下方提示原因。绕飞预览将在 3 秒后尝试，请把鼠标移到屏幕中部并停住。","Previews use saved settings. Two-bird previews never create temporary birds or change the bird count. Missing companions or insufficient space are explained below. Pointer preview tries after 3 seconds; move the pointer near screen center and hold still."),NSRect(x:20,y:766,width:710,height:76),in:interactionView,size:12)
        label(t("停栖时的小动作","While perched"),NSRect(x:20,y:874,width:710,height:30),in:interactionView,size:20)
        perchActionsButton=NSButton(checkboxWithTitle:t("停栖小动作","Perch activities"),target:self,action:#selector(perchSettingsChanged))
        perchActionsButton.frame=NSRect(x:20,y:916,width:710,height:26);perchActionsButton.state=draft.perchActions ? .on:.off
        interactionView.addSubview(perchActionsButton)
        passiveAttentionButton=NSButton(checkboxWithTitle:t("留意鼠标与短暂警觉","Watch the pointer and briefly become alert"),target:self,action:#selector(perchSettingsChanged))
        passiveAttentionButton.frame=NSRect(x:40,y:952,width:690,height:26);passiveAttentionButton.state=draft.passiveAttentionEnabled ? .on:.off
        passiveAttentionButton.isEnabled=draft.perchActions;interactionView.addSubview(passiveAttentionButton)
        label(t("停稳后偶尔闭眼休息，着陆后可能整理羽毛；鼠标靠近或点击会结束这些动作。\n留意鼠标时只使用朝向、站立和眨眼；鼠标在附近快速移动会引起短暂警觉，安静后恢复，不会新增移动。\n两项默认开启，保存后生效；停栖总开关也控制留意与警觉。","Settled birds may rest with eyes closed or preen after landing; a nearby pointer or click ends these activities.\nObservation uses facing, standing and blinking. Fast nearby pointer movement causes brief alertness; quiet restores calm, without added movement.\nBoth default on and apply after saving. The perch master switch also controls observation and alertness."),NSRect(x:20,y:990,width:710,height:100),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("perchActivitiesHelp")
        previewRestButton=button(t("预览闭眼休息","Preview eyes-closed rest"),#selector(previewRest),NSRect(x:20,y:1104,width:230,height:32),in:interactionView)
        previewPreenButton=button(t("预览整理羽毛","Preview preening"),#selector(previewPreen),NSRect(x:270,y:1104,width:210,height:32),in:interactionView)
        previewWatchButton=button(t("预览留意鼠标","Preview observation"),#selector(previewWatch),NSRect(x:20,y:1150,width:230,height:32),in:interactionView)
        previewAlertButton=button(t("预览短暂警觉","Preview brief alert"),#selector(previewAlert),NSRect(x:270,y:1150,width:210,height:32),in:interactionView)
        label(t("预览使用已保存的设置。请先让小鸟停稳；休息和理羽需把鼠标移开。\n留意和警觉可选中远离鼠标的可用小鸟，只展示朝向、站立和眨眼。条件不合适时在下方提示。","Previews use saved settings. Let a bird settle; move the pointer away for rest and preening.\nObservation and alert previews can use an available bird far from the pointer, showing facing, standing and blinking. If unavailable, the reason appears below."),NSRect(x:20,y:1196,width:710,height:60),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("perchPreviewHelp")
        label(t("落叶游戏","Leaf play"),NSRect(x:20,y:1280,width:710,height:30),in:interactionView,size:20).identifier=NSUserInterfaceItemIdentifier("leafSectionTitle")
        leafPlayButton=NSButton(checkboxWithTitle:t("开启落叶游戏","Enable leaf play"),target:self,action:#selector(leafSettingsChanged))
        leafPlayButton.frame=NSRect(x:20,y:1322,width:710,height:26);leafPlayButton.state=draft.leafPlayEnabled ? .on:.off
        interactionView.addSubview(leafPlayButton)
        ambientLeafPlayButton=NSButton(checkboxWithTitle:t("偶尔自动出现落叶游戏","Occasional automatic leaf play"),target:self,action:#selector(leafSettingsChanged))
        ambientLeafPlayButton.frame=NSRect(x:40,y:1358,width:690,height:26);ambientLeafPlayButton.state=draft.ambientLeafPlayEnabled ? .on:.off
        ambientLeafPlayButton.isEnabled=draft.leafPlayEnabled;interactionView.addSubview(ambientLeafPlayButton)
        label(t("一只已停稳的小鸟会观察、跟随落叶，再返回停靠处；不会生成小鸟。\n自动落叶很少出现，与绕飞、过境和双鸟互动共享出现频率，条件不合适时跳过。\n两项默认开启，保存后生效。自动开关只控制自动落叶；手动预览仍可使用。","A settled bird observes and follows a leaf, then returns to its perch. No birds are spawned.\nAutomatic leaf play is rare and shares the encounter frequency with pointer visits, flocks and two-bird interactions; unsuitable conditions are skipped.\nBoth default on; save to apply. The automatic switch only controls automatic leaves; manual preview remains available."),NSRect(x:20,y:1396,width:710,height:78),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("leafPlayHelp")
        releaseLeafButton=button(t("放一片落叶","Release a leaf"),#selector(releaseLeaf),NSRect(x:20,y:1488,width:210,height:32),in:interactionView)
        clearLeafButton=button(t("清除落叶","Clear leaf"),#selector(clearLeaf),NSRect(x:250,y:1488,width:210,height:32),in:interactionView)
        label(t("预览使用已保存的设置。点击后有 3 秒准备时间，请把鼠标移到屏幕中部的空旷位置。\n清除落叶会取消等待中的预览和正在进行的落叶场景。条件不合适时会在下方提示原因。","Previews use saved settings. After clicking, move the pointer to a clear area near screen center within 3 seconds.\nClear leaf cancels both pending previews and the active leaf scene. If unavailable, the reason appears below."),NSRect(x:20,y:1536,width:710,height:66),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("leafPreviewHelp")
        let debugView=SettingsContentView(frame:NSRect(x:0,y:0,width:754,height:400))
        let debug=NSTabViewItem(identifier:"debug");debug.label=t("调试","Debug");debug.view=scroll(debugView);tabs.addTabViewItem(debug)
        label(t("更新提示预览","Update notification preview"),NSRect(x:20,y:20,width:710,height:30),in:debugView,size:20)
        label(t("模拟更新会显示通知和图标红点。点击通知或菜单中的安装更新可查看确认框；选择安装后结束模拟，选择晚点再说则保留提示。不会下载、安装或重启。","Simulate a ready update with a notification and icon badge. Click the notification or install menu item to review it. Confirm to end the simulation, or choose Later to keep the prompt. No download, installation or restart occurs."),NSRect(x:20,y:64,width:710,height:95),in:debugView)
        _=button(t("模拟有更新","Simulate update"),#selector(simulateUpdate),NSRect(x:20,y:172,width:180,height:32),in:debugView)
        tabs.selectTabViewItem(at:min(selected,debugEnabled ? 3:2))
        message=label("",NSRect(x:26,y:603,width:784,height:28),in:root,size:12)
        _=button(t("恢复默认","Restore Defaults"),#selector(resetDefaults),NSRect(x:22,y:642,width:148,height:30),in:root)
        _=button(t("取消","Cancel"),#selector(cancel),NSRect(x:562,y:642,width:100,height:30),in:root)
        let save=button(t("保存并应用","Save & Apply"),#selector(save),NSRect(x:672,y:642,width:144,height:30),in:root); save.keyEquivalent="\r"
        refresh()
    }
    @objc func simulateUpdate() {
        let started=desktop.updater?.simulateUpdate() == true
        message.stringValue=started ? t("已显示模拟更新，可点击通知或菜单查看。","Simulated update ready; click the notification or menu to review."):t("更新器正在忙碌，请稍后重试。","The updater is busy; try again shortly.")
    }
    @objc func ambientSettingsChanged() {
        draft.pointerVisits=pointerVisitsButton.state == .on
        draft.pointerFollowEnabled=pointerFollowButton.state == .on
        pointerFollowButton.isEnabled=draft.pointerVisits
        draft.flockPasses=flockPassesButton.state == .on
        draft.socialInteractions=socialInteractionsButton.state == .on
        draft.ambientFrequency=AmbientFrequency.allCases[ambientFrequencyPopup.indexOfSelectedItem]
        message.stringValue=t("尚未保存","Unsaved changes")
    }
    @objc func previewPointerVisit() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.previewPointerAfter(3))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("3 秒后尝试绕飞：请将鼠标移到屏幕中部并停住。","Trying in 3 seconds: move the pointer near screen center and hold still.")}
    }
    @objc func previewFlockPass() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.flockPass(.preview))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("鸟群即将飞过。","A flock is about to pass.")}
    }
    @objc func perchSettingsChanged() {
        draft.perchActions=perchActionsButton.state == .on
        draft.passiveAttentionEnabled=passiveAttentionButton.state == .on
        passiveAttentionButton.isEnabled=draft.perchActions
        message.stringValue=t("尚未保存","Unsaved changes")
    }
    @objc func leafSettingsChanged() {
        draft.leafPlayEnabled=leafPlayButton.state == .on
        draft.ambientLeafPlayEnabled=ambientLeafPlayButton.state == .on
        ambientLeafPlayButton.isEnabled=draft.leafPlayEnabled
        message.stringValue=t("尚未保存","Unsaved changes")
    }
    @objc func releaseLeaf() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.releaseLeafAfter(3))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("3 秒后尝试放下落叶：请将鼠标移到屏幕中部的空旷位置。","Releasing in 3 seconds: move the pointer to a clear area near screen center.")}
    }
    @objc func clearLeaf() {
        desktop.engine.handle(.clearProps)
        // Consume the cancellation before presenting this explicit result, so
        // the next frame cannot replace it with an input-rejection message.
        desktop.consumeBehaviorEvents()
        message.stringValue=t("已清除落叶，并取消等待中的预览。","Leaf cleared; pending preview cancelled.")
    }
    @objc func previewSocialGreeting() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.socialGreeting(.preview))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("正在预览双鸟招呼。小鸟会轮流朝同伴做小动作，不发出声音。","Previewing a two-bird greeting. The birds take turns making small movements toward each other, silently.")}
    }
    @objc func previewSideBySide() { previewSocialMotion(.sideBySide) }
    @objc func previewGiveWay() { previewSocialMotion(.giveWay) }
    @objc func previewPairedTakeoff() { previewSocialMotion(.pairedTakeoff) }
    private func previewSocialMotion(_ kind:SocialMotionKind) {
        desktop.syncWorld()
        let result=desktop.engine.handle(.socialMotion(kind,.preview))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {
            switch kind {
            case .sideBySide:message.stringValue=t("正在预览并排停靠：一只小鸟会移到同伴身旁停下。","Previewing side-by-side perching: one bird moves to settle beside its companion.")
            case .giveWay:message.stringValue=t("正在预览让座：一只小鸟会让出位置，另一只随后移入。","Previewing giving way: one bird makes room, then its companion moves into the space.")
            case .pairedTakeoff:message.stringValue=t("正在预览结伴起飞：两只小鸟会相继起飞，一起飞向新的停靠位置。","Previewing paired takeoff: two birds take off in sequence and fly to new perches together.")
            }
        }
    }
    @objc func previewWatch() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.attention(.watch,.preview))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("正在预览留意鼠标：观察朝向、站立和眨眼；小鸟停稳即可，鼠标可以远离。","Previewing observation: watch facing, standing and blinking on a settled bird, even far from the pointer.")}
    }
    @objc func previewAlert() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.attention(.alert,.preview))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("正在预览短暂警觉：小鸟保持停栖，安静后恢复；无需把鼠标移近。","Previewing brief alertness: the bird stays perched and settles when quiet; no need to move the pointer closer.")}
    }
    @objc func previewRest() { previewPerchAction(.rest) }
    @objc func previewPreen() { previewPerchAction(.preen) }
    private func previewPerchAction(_ kind:PerchActionKind) {
        desktop.syncWorld()
        let result=desktop.engine.handle(.perchAction(kind,.preview))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {
            switch kind {
            case .rest:message.stringValue=t("正在预览闭眼休息。鼠标靠近或点击可结束。","Previewing eyes-closed rest. Move the pointer close or click to end it.")
            case .preen:message.stringValue=t("正在预览整理羽毛。鼠标靠近或点击可结束。","Previewing preening. Move the pointer close or click to end it.")
            }
        }
    }
    @objc func selectPage(_ sender:NSButton) { window?.makeFirstResponder(nil); tabs.selectTabViewItem(at:sender.tag) }
    func scrollToSpecies(_ id:SpeciesID) {
        guard let i=draft.probabilities.entries.firstIndex(where:{$0.id==id}),
              let scroll=tabs.tabViewItems[0].view as? NSScrollView else{return}
        tabs.selectTabViewItem(at:0)
        scroll.contentView.scroll(to:CGPoint(x:0,y:max(0,fields[i].frame.minY-45)))
        scroll.reflectScrolledClipView(scroll.contentView)
        window?.makeFirstResponder(fields[i])
    }
    func refresh() {
        for (i,e) in draft.probabilities.entries.enumerated() {
            sliders[i].doubleValue=Double(e.points)/100; fields[i].stringValue=String(format:"%.2f",Double(e.points)/100)
            locks[i].state=e.locked ? .on:.off
            sliders[i].isEnabled=draft.probabilities.canAdjust(i); fields[i].isEnabled=sliders[i].isEnabled
            let tip=t("可用上限：","Available maximum: ")+String(format:"%.2f%%",Double(draft.probabilities.maximum(at:i))/100)
            sliders[i].toolTip=tip; fields[i].toolTip=tip
        }
    }
    func number(_ s:String) -> Double? {
        Double(s.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"%",with:"").replacingOccurrences(of:",",with:"."))
    }
    func change(_ i:Int,_ value:Double) {
        guard value.isFinite else { return }
        let requested=Int((min(100,max(0,value))*100).rounded())
        let actual=draft.probabilities.adjust(at:i,to:requested)
        message.stringValue = actual != requested || value < 0 || value > 100
            ? t("已限制到可用概率，锁定项保持不变。","Limited to the available probability; locked values were preserved.") : t("尚未保存","Unsaved changes")
        refresh()
    }
    @objc func sliderChanged(_ sender:NSSlider) { let value=sender.doubleValue; window?.makeFirstResponder(nil); change(sender.tag,value) }
    @objc func hoverDelayChanged(_ sender:NSSlider) {
        let value=(sender.doubleValue*10).rounded()/10
        window?.makeFirstResponder(nil)
        draft.hoverDelay=value;hoverDelaySlider.doubleValue=value
        hoverDelayField.stringValue=String(format:"%g",value)
        message.stringValue=t("尚未保存","Unsaved changes")
    }
    @objc func lockChanged(_ sender:NSButton) {
        let locked=sender.state == .on
        window?.makeFirstResponder(nil)
        draft.probabilities.setLocked(locked,at:sender.tag); refresh()
        message.stringValue=t("尚未保存 · 仅剩一个未锁定项时无法调整概率。","Unsaved changes · Adjustment needs at least two unlocked species.")
    }
    func controlTextDidEndEditing(_ obj:Notification) {
        guard let f=obj.object as? NSTextField else { return }
        if f === hoverDelayField {
            if readInteraction() {message.stringValue=t("尚未保存","Unsaved changes")}
            else {message.stringValue=t("请输入 0–10 秒之间的有效数值。","Enter a valid delay between 0 and 10 seconds.")}
            return
        }
        if f.tag < 100 {
            guard let value=number(f.stringValue),value.isFinite else {
                message.stringValue=t("请输入有效的百分比数值。","Enter a valid percentage."); refresh(); return
            }
            change(f.tag,value)
        } else { message.stringValue=t("尚未保存","Unsaved changes") }
    }
    func readDetails() -> Bool {
        var catalog=draft.catalog
        for (i,entry) in draft.probabilities.entries.enumerated() {
            let row=detailFields[i], values=row.map { number($0.stringValue) }
            guard values.allSatisfy({$0?.isFinite == true}) else { return false }
            let v=values.map{$0!}
            guard (8...110).contains(v[0]), (0.5...7.5).contains(v[1]), (0.5...2).contains(v[2]), (2...300).contains(v[3]), v[4]>=v[3],v[4]<=600 else { return false }
            let index=draft.catalog.species.firstIndex{$0.id==entry.id}!
            catalog.species[index].adultLengthCM=v[0]; catalog.species[index].flapFPS=v[1]*8
            catalog.species[index].speed=v[2]; catalog.species[index].perchMin=v[3]; catalog.species[index].perchMax=v[4]
        }
        draft.catalog=catalog
        return true
    }
    func readInteraction() -> Bool {
        guard let value=number(hoverDelayField.stringValue),value.isFinite,BirdSettings.hoverDelayRange.contains(value) else {return false}
        draft.hoverDelay=value;hoverDelaySlider.doubleValue=value
        hoverDelayField.stringValue=String(format:"%g",value)
        draft.pointerVisits=pointerVisitsButton.state == .on
        draft.pointerFollowEnabled=pointerFollowButton.state == .on
        pointerFollowButton.isEnabled=draft.pointerVisits
        draft.flockPasses=flockPassesButton.state == .on
        draft.ambientFrequency=AmbientFrequency.allCases[ambientFrequencyPopup.indexOfSelectedItem]
        draft.perchActions=perchActionsButton.state == .on
        draft.passiveAttentionEnabled=passiveAttentionButton.state == .on
        passiveAttentionButton.isEnabled=draft.perchActions
        draft.socialInteractions=socialInteractionsButton.state == .on
        draft.leafPlayEnabled=leafPlayButton.state == .on
        draft.ambientLeafPlayEnabled=ambientLeafPlayButton.state == .on
        ambientLeafPlayButton.isEnabled=draft.leafPlayEnabled
        return true
    }
    @objc func save() {
        window?.makeFirstResponder(nil)
        guard readInteraction() else {tabs.selectTabViewItem(at:2);message.stringValue=t("请输入 0–10 秒之间的有效等待时间。","Enter a valid hover delay between 0 and 10 seconds.");return}
        guard readDetails() else { tabs.selectTabViewItem(at:1); message.stringValue=t("请检查体型与动作数值：最长停留不能小于最短停留。","Check size and behavior ranges; maximum perch time must not be below minimum."); return }
        do { try desktop.applySettings(draft); message.stringValue=t("已保存 · 交互设置立即生效，鸟种参数用于新飞入的小鸟。","Saved · Interaction settings apply now; species settings affect new arrivals.") }
        catch { message.stringValue=t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.") }
    }
    @objc func resetDefaults() { window?.makeFirstResponder(nil); draft=BirdSettings(); build(); message.stringValue=t("已恢复默认（尚未保存，锁定已清除）。","Defaults restored (not saved; locks cleared).") }
    @objc func cancel() { window?.close() }
    func relocalize() {
        window?.makeFirstResponder(nil)
        let raw = detailFields.map { $0.map(\.stringValue) }
        let rawDelay=hoverDelayField.stringValue
        build()
        for i in raw.indices { for j in raw[i].indices { detailFields[i][j].stringValue = raw[i][j] } }
        hoverDelayField.stringValue=rawDelay
    }
}
