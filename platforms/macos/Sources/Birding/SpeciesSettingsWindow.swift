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
    var sideHopButton:NSButton!
    var takeoffPreparationButton:NSButton!
    var previewSideHopButton:NSButton!
    var previewTakeoffPreparationButton:NSButton!
    var previewWatchButton:NSButton!
    var previewAlertButton:NSButton!
    var previewRestButton:NSButton!
    var previewPreenButton:NSButton!
    var leafPlayButton:NSButton!
    var ambientLeafPlayButton:NSButton!
    var releaseLeafButton:NSButton!
    var clearLeafButton:NSButton!
    var visitorMemoryButton:NSButton!
    var activityRhythmPopup:NSPopUpButton!
    var edgePeekButton:NSButton!
    var previewEdgePeekButton:NSButton!
    var chaseButton:NSButton!
    var previewChaseButton:NSButton!
    var travelTogetherButton:NSButton!
    var previewTravelTogetherButton:NSButton!
    var allopreeningButton:NSButton!
    var previewAllopreeningButton:NSButton!
    var fixedPerchesButton:NSButton!
    var fixedPerchSlotPopup:NSPopUpButton!
    var fixedPerchStatus:NSTextField!
    var placeFixedPerchButton:NSButton!
    var removeFixedPerchButton:NSButton!
    var previewFixedPerchButton:NSButton!
    var foodTrayButton:NSButton!
    var placeFoodTrayButton:NSButton!
    var removeFoodTrayButton:NSButton!
    var cancelFoodTrayPlacementButton:NSButton!
    var previewFoodTrayButton:NSButton!
    var foodTrayStatus:NSTextField!
    var bathButton:NSButton!
    var placeBathButton:NSButton!
    var removeBathButton:NSButton!
    var cancelBathPlacementButton:NSButton!
    var clearCurrentSceneButton:NSButton!
    var previewBathButton:NSButton!
    var bathStatus:NSTextField!
    var leafCarryButton:NSButton!
    var placeCarryLeafButton:NSButton!
    var cancelCarryLeafPlacementButton:NSButton!
    var removeCarryLeafButton:NSButton!
    var previewLeafCarryButton:NSButton!
    var leafCarryStatus:NSTextField!
    private weak var foodTrayEngine:BehaviorEngine?
    private var ownsFoodTrayPlacement=false
    private var ownsBathPlacement=false
    private var ownsCarryLeafPlacement=false
    private(set) var selectedFixedPerchSlot=1
    private(set) var fixedPerchCaptureTimer:Timer?
    private(set) var fixedPerchCaptureRequest:UUID?
    private var debugEnabled=false
    private var debugButton:NSButton!
    var language: AppLanguage { desktop.language }
    func t(_ zh:String,_ en:String) -> String { language.text(zh,en) }
    init(desktop:DesktopController) {
        self.desktop = desktop; self.draft = desktop.settings
        foodTrayEngine=desktop.engine
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:690),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        super.init(window:window)
        NotificationCenter.default.addObserver(self,selector:#selector(fixedPerchWindowWillClose(_:)),
                                               name:NSWindow.willCloseNotification,object:window)
        build(); window.center()
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit {
        fixedPerchCaptureTimer?.invalidate()
        if ownsFoodTrayPlacement,foodTrayEngine?.hasFoodTrayPlacement == true {foodTrayEngine?.handle(.cancelFoodTrayPlacement)}
        if ownsBathPlacement,foodTrayEngine?.hasBathPlacement == true {foodTrayEngine?.handle(.cancelBathPlacement)}
        if ownsCarryLeafPlacement,foodTrayEngine?.hasCarryLeafPlacement == true {foodTrayEngine?.handle(.cancelCarryLeafPlacement)}
        NotificationCenter.default.removeObserver(self)
    }
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
        cancelFixedPerchCapture()
        cancelFoodTrayPlacement()
        cancelBathPlacement()
        cancelCarryLeafPlacement()
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
        let interactionView=SettingsContentView(frame:NSRect(x:0,y:0,width:754,height:6410))
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
        label(t("招呼、并排停靠、让座和结伴起飞需要两只距离合适、在可见边缘停稳的小鸟及足够空间，共用此开关。短暂追逐和飞行中临时结队另有子开关，见下方；结队只选择正在飞行的鸟。默认开启，保存后生效。","Greetings, side-by-side perching, giving way and paired takeoff need two suitably spaced birds settled on visible edges, with room to move. This master also controls Brief chases and Travel together in flight, with separate preferences below. Travel together uses birds already in flight. On by default; save to apply."),NSRect(x:20,y:584,width:710,height:76),in:interactionView,size:12)
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
        label(t("观察、警觉、缩身休息与起飞准备的专用鸟种：\n\(language.poseSpeciesNames)。\n其余鸟种保留原表现。停稳后可休息或理羽；鼠标靠近或点击会结束。警觉安静后恢复，不移动。\n默认开启，保存后生效；总开关也控制留意与警觉。","Dedicated watch, alert, rest and takeoff poses:\n\(language.poseSpeciesNames).\nOther birds keep existing poses. Rest/preening ends on approach or click; alertness settles without moving.\nOn by default; save to apply. The master also controls watch/alert."),NSRect(x:20,y:990,width:710,height:100),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("perchActivitiesHelp")
        previewRestButton=button(t("预览闭眼休息","Preview eyes-closed rest"),#selector(previewRest),NSRect(x:20,y:1104,width:230,height:32),in:interactionView)
        previewPreenButton=button(t("预览整理羽毛","Preview preening"),#selector(previewPreen),NSRect(x:270,y:1104,width:210,height:32),in:interactionView)
        previewWatchButton=button(t("预览留意鼠标","Preview observation"),#selector(previewWatch),NSRect(x:20,y:1150,width:230,height:32),in:interactionView)
        previewAlertButton=button(t("预览短暂警觉","Preview brief alert"),#selector(previewAlert),NSRect(x:270,y:1150,width:210,height:32),in:interactionView)
        label(t("预览读取已保存设置，使用现有停稳小鸟；休息和理羽需移开鼠标。\n专用姿态使用\(language.poseSupportReference)，其余保留原表现；留意与警觉允许鼠标远离，不可用时说明原因。","Previews use saved settings and settled birds; move away for rest/preening.\nDedicated poses use \(language.poseSupportReference); others keep existing poses. Watch/alert allows a distant pointer; rejections explain why."),NSRect(x:20,y:1196,width:710,height:60),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("perchPreviewHelp")
        label(t("让路与起飞","Making room and taking off"),NSRect(x:20,y:1280,width:710,height:30),in:interactionView,size:20)
        sideHopButton=NSButton(checkboxWithTitle:t("鼠标靠近时小跳让路","Hop aside when the pointer approaches"),target:self,action:#selector(perchSettingsChanged))
        sideHopButton.frame=NSRect(x:20,y:1322,width:710,height:26);sideHopButton.state=draft.sideHopEnabled ? .on:.off
        sideHopButton.isEnabled=draft.perchActions;interactionView.addSubview(sideHopButton)
        takeoffPreparationButton=NSButton(checkboxWithTitle:t("自主起飞前稍作准备","Prepare before autonomous takeoff"),target:self,action:#selector(perchSettingsChanged))
        takeoffPreparationButton.frame=NSRect(x:20,y:1358,width:710,height:26);takeoffPreparationButton.state=draft.takeoffPreparationEnabled ? .on:.off
        takeoffPreparationButton.isEnabled=draft.perchActions;interactionView.addSubview(takeoffPreparationButton)
        label(t("鼠标靠近时可能沿边缘侧跳；空间不足或持续靠近时不反复跳开。\n起飞前下蹲、蹬伸使用\(language.poseSupportReference)，其余保留原有准备。点击换位立即响应，不等待下蹲。\n默认开启，受停栖总开关控制；保存后生效。","Birds may hop aside; tight space or continued proximity prevents repeat hops.\nCrouch/push uses \(language.poseSupportReference); others keep existing preparation. Clicks relocate immediately, without waiting for a crouch.\nOn by default; controlled by Perch activities. Save to apply."),NSRect(x:20,y:1396,width:710,height:70),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("passiveMotionHelp")
        previewSideHopButton=button(t("预览小跳让路","Preview hopping aside"),#selector(previewSideHop),NSRect(x:20,y:1480,width:260,height:32),in:interactionView)
        previewTakeoffPreparationButton=button(t("预览起飞准备","Preview takeoff preparation"),#selector(previewTakeoffPreparation),NSRect(x:300,y:1480,width:290,height:32),in:interactionView)
        label(t("预览使用已保存的设置和现有小鸟。请先让鸟停稳，并留出一段可见边缘。\n预览小跳无需把鼠标移近；起飞准备还需要一个安全的停靠目标。","Previews use saved settings and existing birds. Let a bird settle on a clear ledge.\nHop previews work with a distant pointer; takeoff preparation also needs a safe destination."),NSRect(x:20,y:1528,width:710,height:54),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("passiveMotionPreviewHelp")
        label(t("落叶游戏","Leaf play"),NSRect(x:20,y:1600,width:710,height:30),in:interactionView,size:20).identifier=NSUserInterfaceItemIdentifier("leafSectionTitle")
        leafPlayButton=NSButton(checkboxWithTitle:t("开启落叶游戏","Enable leaf play"),target:self,action:#selector(leafSettingsChanged))
        leafPlayButton.frame=NSRect(x:20,y:1642,width:710,height:26);leafPlayButton.state=draft.leafPlayEnabled ? .on:.off
        interactionView.addSubview(leafPlayButton)
        ambientLeafPlayButton=NSButton(checkboxWithTitle:t("偶尔自动出现落叶游戏","Occasional automatic leaf play"),target:self,action:#selector(leafSettingsChanged))
        ambientLeafPlayButton.frame=NSRect(x:40,y:1678,width:690,height:26);ambientLeafPlayButton.state=draft.ambientLeafPlayEnabled ? .on:.off
        ambientLeafPlayButton.isEnabled=draft.leafPlayEnabled;interactionView.addSubview(ambientLeafPlayButton)
        label(t("一只已停稳的小鸟会观察、跟随落叶，再返回停靠处；不会生成小鸟。\n自动落叶很少出现，与绕飞、过境和双鸟互动共享出现频率，条件不合适时跳过。\n两项默认开启，保存后生效。自动开关只控制自动落叶；手动预览仍可使用。","A settled bird observes and follows a leaf, then returns to its perch. No birds are spawned.\nAutomatic leaf play is rare and shares the encounter frequency with pointer visits, flocks and two-bird interactions; unsuitable conditions are skipped.\nBoth default on; save to apply. The automatic switch only controls automatic leaves; manual preview remains available."),NSRect(x:20,y:1716,width:710,height:78),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("leafPlayHelp")
        releaseLeafButton=button(t("放一片落叶","Release a leaf"),#selector(releaseLeaf),NSRect(x:20,y:1808,width:210,height:32),in:interactionView)
        clearLeafButton=button(t("清除落叶","Clear leaf"),#selector(clearLeaf),NSRect(x:250,y:1808,width:210,height:32),in:interactionView)
        label(t("预览使用已保存的设置。点击后有 3 秒准备时间，请把鼠标移到屏幕中部的空旷位置。\n清除落叶会取消等待中的预览和正在进行的落叶场景。条件不合适时会在下方提示原因。","Previews use saved settings. After clicking, move the pointer to a clear area near screen center within 3 seconds.\nClear leaf cancels both pending previews and the active leaf scene. If unavailable, the reason appears below."),NSRect(x:20,y:1856,width:710,height:66),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("leafPreviewHelp")
        label(t("熟客与安静相处","Returning visitors"),NSRect(x:20,y:1960,width:710,height:30),in:interactionView,size:20).identifier=NSUserInterfaceItemIdentifier("visitorMemorySectionTitle")
        visitorMemoryButton=NSButton(checkboxWithTitle:t("记住熟客与安静相处","Remember returning visitors"),target:self,action:#selector(visitorMemorySettingsChanged))
        visitorMemoryButton.frame=NSRect(x:20,y:2002,width:710,height:26);visitorMemoryButton.state=draft.visitorMemoryEnabled ? .on:.off
        visitorMemoryButton.identifier=NSUserInterfaceItemIdentifier("visitorMemoryEnabled")
        interactionView.addSubview(visitorMemoryButton)
        label(t("记忆只保存在本机；鼠标在附近安静停留，会逐渐增加熟悉度，不改变小鸟原有的个性。\n点击换位仍立即响应。关闭后停止学习与熟悉度效果，已有记忆保留；重新开启后，熟客可继续相处。\n默认开启，独立于停栖小动作总开关，保存后生效。","Memory stays on this Mac. Calm pointer proximity gradually builds familiarity while each bird’s original traits stay unchanged.\nClicks still move birds immediately. Turning this off stops learning and familiarity effects; existing memories resume when reenabled.\nOn by default, independent of perch activities. Save to apply."),NSRect(x:20,y:2040,width:710,height:110),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("visitorMemoryHelp")
        label(t("陪伴节奏","Companionship rhythm"),NSRect(x:20,y:2180,width:710,height:30),in:interactionView,size:20).identifier=NSUserInterfaceItemIdentifier("activityRhythmSectionTitle")
        label(t("活动节奏","Activity rhythm"),NSRect(x:20,y:2228,width:120,height:26),in:interactionView).identifier=NSUserInterfaceItemIdentifier("activityRhythmLabel")
        activityRhythmPopup=NSPopUpButton(frame:NSRect(x:145,y:2222,width:420,height:32),pullsDown:false)
        activityRhythmPopup.addItems(withTitles:[t("保持日常","Keep everyday rhythm"),t("跟随本地昼夜","Follow local day/night"),t("安静陪伴","Quiet companionship")])
        activityRhythmPopup.selectItem(at:ActivityRhythmMode.allCases.firstIndex(of:draft.activityRhythm)!)
        activityRhythmPopup.target=self;activityRhythmPopup.action=#selector(activityRhythmSettingsChanged)
        activityRhythmPopup.identifier=NSUserInterfaceItemIdentifier("activityRhythmPopup")
        activityRhythmPopup.setAccessibilityLabel(t("活动节奏","Activity rhythm"));interactionView.addSubview(activityRhythmPopup)
        label(t("跟随本地昼夜：按本机时段减少夜间显著互动，并按鸟种调整打盹节奏。\n\n安静陪伴：停止新触发的自动绕飞、鸟群过境、社交场景和落叶；正在进行的互动自然结束，手动预览不会取消。保留自然飞行、被动观察、警觉和侧跳；已有开关仍然适用。\n\n所有模式点击换位都立即响应。默认保持日常；保存后生效。不会强制入睡、改变鸟的数量或离线累计。","Local day/night uses this Mac’s local time to reduce noticeable interactions at night and adjusts dozing rhythms by species.\n\nQuiet companionship stops new automatic pointer visits, passing flocks, social scenes and leaves. Interactions already in progress finish naturally; manual previews are not cancelled. Natural flight, passive observation, alertness and side hops remain available, subject to their existing switches.\n\nClicks move birds immediately in every mode. Default: keep everyday rhythm. Save to apply. No forced sleep, bird count changes or offline accumulation."),NSRect(x:20,y:2270,width:710,height:234),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("activityRhythmHelp")
        label(t("探头观察","Edge peeking"),NSRect(x:20,y:2540,width:710,height:30),in:interactionView,size:20).identifier=NSUserInterfaceItemIdentifier("edgePeekSectionTitle")
        edgePeekButton=NSButton(checkboxWithTitle:t("窗口边缘探头观察","Peek over window edges"),target:self,action:#selector(perchSettingsChanged))
        edgePeekButton.frame=NSRect(x:20,y:2582,width:710,height:26);edgePeekButton.state=draft.edgePeekEnabled ? .on:.off
        edgePeekButton.isEnabled=draft.perchActions;edgePeekButton.identifier=NSUserInterfaceItemIdentifier("edgePeekEnabled")
        edgePeekButton.setAccessibilityLabel(t("窗口边缘探头观察","Peek over window edges"));interactionView.addSubview(edgePeekButton)
        label(t("支持鸟种：","Supported species: ")+language.supportedSpeciesNames(for:.edgePeek)+t("。\n小鸟在窗口上沿端点附近的安全空间内靠近边缘、低头观察，再退回原位。地面或远离端点的窗口中央不会被强制拉来参加；空间不足时跳过。\n默认开启，受停栖小动作总开关控制。关闭总开关会保留此项偏好；保存后生效。",".\nNear a window’s top-edge endpoint, a bird approaches within safe space, looks down, then retreats to its starting spot. Ground birds and birds far from endpoints stay where they are. Insufficient space skips the activity.\nOn by default, controlled by Perch activities. Turning off the master preserves this preference. Save to apply."),NSRect(x:20,y:2620,width:710,height:116),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("edgePeekHelp")
        previewEdgePeekButton=button(t("预览探头观察","Preview edge peeking"),#selector(previewEdgePeek),NSRect(x:20,y:2750,width:260,height:32),in:interactionView)
        previewEdgePeekButton.identifier=NSUserInterfaceItemIdentifier("previewEdgePeek")
        label(t("预览读取已保存的设置，使用现有小鸟，不改变鸟的数量。请让上述鸟种在窗口上沿端点附近停稳，并留出安全的靠近和退回空间。\n暂停、没有合适小鸟、空间不足、缺少对应帧或尚未保存开启时，会在下方提示原因。","Previews use saved settings and existing birds; the bird count stays unchanged. Let a supported bird settle near a window’s top-edge endpoint with safe room to approach and retreat.\nPausing, no suitable bird, insufficient space, missing frames or a saved switch being off are explained below."),NSRect(x:20,y:2796,width:710,height:116),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("edgePeekPreviewHelp")
        label(t("短暂追逐","Brief chases"),NSRect(x:20,y:2950,width:710,height:30),in:interactionView,size:20).identifier=NSUserInterfaceItemIdentifier("chaseSectionTitle")
        chaseButton=NSButton(checkboxWithTitle:t("短暂追逐","Brief chases"),target:self,action:#selector(ambientSettingsChanged))
        chaseButton.frame=NSRect(x:20,y:2992,width:710,height:26);chaseButton.state=draft.chaseEnabled ? .on:.off
        chaseButton.isEnabled=draft.socialInteractions;chaseButton.identifier=NSUserInterfaceItemIdentifier("chaseEnabled")
        chaseButton.setAccessibilityLabel(chaseButton.title);interactionView.addSubview(chaseButton)
        let chaseNames=language.supportedSpeciesNames(for:.chase)
        label(t("附近两只同种小鸟先后起飞，追逐几秒，再各自落回停靠处。\n支持鸟种：","Two nearby birds of the same species take off in sequence, chase for a few seconds, then each returns to its perch.\nSupported species: ")+chaseNames+t("。\n默认开启，受双鸟互动总开关控制；关闭总开关保留此项偏好，保存后生效。安静陪伴模式不自动触发。",".\nOn by default, controlled by Two-bird interactions. Turning off the master preserves this preference; save to apply. Quiet companionship prevents automatic chases."),NSRect(x:20,y:3030,width:710,height:136),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("chaseHelp")
        previewChaseButton=button(t("预览短暂追逐","Preview brief chase"),#selector(previewChase),NSRect(x:20,y:3180,width:260,height:32),in:interactionView)
        previewChaseButton.identifier=NSUserInterfaceItemIdentifier("previewChase")
        label(t("预览使用已保存的设置和现有小鸟，不会生成或传送鸟。请让两只支持追逐的同种鸟在附近停稳，并留出飞行和落回的空间。\n暂停、未保存开启、没有合适同伴或空间不足时，下方会提示原因。安静陪伴仍可手动预览。","Previews use saved settings and existing birds, without spawning or teleporting any. Let two supported birds of the same species settle nearby, with room to fly and return.\nPausing, saved switches being off, no suitable companion or insufficient space are explained below. Manual previews remain available in Quiet companionship."),NSRect(x:20,y:3226,width:710,height:104),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("chasePreviewHelp")
        label(t("飞行中临时结队","Travel together in flight"),NSRect(x:20,y:3380,width:710,height:30),in:interactionView,size:20).identifier=NSUserInterfaceItemIdentifier("travelTogetherSectionTitle")
        travelTogetherButton=NSButton(checkboxWithTitle:t("飞行中临时结队","Travel together in flight"),target:self,action:#selector(ambientSettingsChanged))
        travelTogetherButton.frame=NSRect(x:20,y:3422,width:710,height:26);travelTogetherButton.state=draft.travelTogetherEnabled ? .on:.off
        travelTogetherButton.isEnabled=draft.socialInteractions;travelTogetherButton.identifier=NSUserInterfaceItemIdentifier("travelTogetherEnabled")
        travelTogetherButton.setAccessibilityLabel(travelTogetherButton.title);interactionView.addSubview(travelTogetherButton)
        let travelNames=language.supportedSpeciesNames(for:.travelTogether)
        label(t("两只原本独立飞行的同种居民鸟逐渐靠拢，同行约 2 秒，再分开飞向各自原目标。不会让停栖的小鸟起飞。\n支持鸟种：","Two resident birds of the same species, already flying independently, gradually draw closer, travel together for about 2 seconds, then separate toward their original destinations. Perched birds stay perched.\nSupported species: ")+travelNames+t("。\n默认开启，受双鸟互动总开关控制；关闭总开关保留此项偏好，保存后生效。安静陪伴不触发新的自动结队，当前结队可自然完成。",".\nOn by default, controlled by Two-bird interactions; turning off the master preserves this preference. Save to apply. Quiet companionship prevents new automatic pairs; current pairs finish naturally."),NSRect(x:20,y:3460,width:710,height:136),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("travelTogetherHelp")
        previewTravelTogetherButton=button(t("预览飞行中结队","Preview travel together"),#selector(previewTravelTogether),NSRect(x:20,y:3610,width:280,height:32),in:interactionView)
        previewTravelTogetherButton.identifier=NSUserInterfaceItemIdentifier("previewTravelTogether")
        label(t("预览使用已保存的设置，只选择现有、正在独立飞行的同种居民鸟，不会让停栖鸟起飞、生成或传送鸟。没有合适候选时，请等待上述鸟种的两只同种鸟自然飞行，并留出同行与分开的空间。\n暂停、未保存开启、缺少同伴或空间不足时，下方会提示原因。安静陪伴仍可手动预览。","Previews use saved settings and existing same-species residents already flying independently. No takeoff, spawning or teleporting. If no pair is available, wait for two supported birds of the same species to fly naturally, with room to travel together and separate.\nPausing, saved switches being off, missing companions or insufficient space are explained below. Manual previews remain available in Quiet companionship."),NSRect(x:20,y:3656,width:710,height:104),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("travelTogetherPreviewHelp")
        label(t("同伴理羽","Companion preening"),NSRect(x:20,y:3810,width:710,height:30),in:interactionView,size:20).identifier=NSUserInterfaceItemIdentifier("allopreeningSectionTitle")
        allopreeningButton=NSButton(checkboxWithTitle:t("同伴理羽","Companion preening"),target:self,action:#selector(ambientSettingsChanged))
        allopreeningButton.frame=NSRect(x:20,y:3852,width:710,height:26);allopreeningButton.state=draft.allopreeningEnabled ? .on:.off
        allopreeningButton.isEnabled=draft.socialInteractions;allopreeningButton.identifier=NSUserInterfaceItemIdentifier("allopreeningEnabled")
        allopreeningButton.setAccessibilityLabel(allopreeningButton.title);interactionView.addSubview(allopreeningButton)
        let companionNames=language.supportedSpeciesNames(for:.allopreening)
        label(t("相邻的两只同种小鸟在同一窗口边缘停稳后，轻轻靠近、梳理头颈，再退回原位，全程约 6 秒。\n支持鸟种：","Two calm birds of the same species, perched beside each other on one window, draw closer, gently preen the head and neck, then return to their starting spots in about 6 seconds.\nSupported species: ")+companionNames+t("。\n默认开启，受双鸟互动总开关控制；关闭总开关保留此项偏好。保存后生效，安静陪伴仅停止自动理羽。",".\nOn by default, controlled by Two-bird interactions; turning off the master preserves this preference. Save to apply. Quiet companionship stops automatic preening."),NSRect(x:20,y:3890,width:710,height:112),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("allopreeningHelp")
        previewAllopreeningButton=button(t("预览同伴理羽","Preview companion preening"),#selector(previewAllopreening),NSRect(x:20,y:4016,width:290,height:32),in:interactionView)
        previewAllopreeningButton.identifier=NSUserInterfaceItemIdentifier("previewAllopreening")
        label(t("预览使用已保存的设置和现有小鸟，不会增加小鸟。请让两只上述同种鸟在同一窗口边缘相邻停稳，并把鼠标移远。\n暂停、尚未保存开启、没有合适同伴或空间不足时，下方会提示原因。安静陪伴仍可手动预览。","Previews use saved settings and existing birds, without adding birds. Let two supported birds of the same species settle beside each other on one window and move the pointer away.\nPausing, saved switches being off, no suitable companion or insufficient space are explained below. Manual preview works in Quiet companionship."),NSRect(x:20,y:4062,width:710,height:88),in:interactionView,size:12).identifier=NSUserInterfaceItemIdentifier("allopreeningPreviewHelp")
        buildFixedPerches(in:interactionView)
        buildFoodTray(in:interactionView)
        buildBath(in:interactionView)
        buildLeafCarry(in:interactionView)
        let debugView=SettingsContentView(frame:NSRect(x:0,y:0,width:754,height:400))
        let debug=NSTabViewItem(identifier:"debug");debug.label=t("调试","Debug");debug.view=scroll(debugView);tabs.addTabViewItem(debug)
        label(t("更新提示预览","Update notification preview"),NSRect(x:20,y:20,width:710,height:30),in:debugView,size:20)
        label(t("模拟更新会显示通知和图标红点。点击通知或菜单中的安装更新可查看确认框；选择安装后结束模拟，选择晚点再说则保留提示。不会下载、安装或重启。","Simulate a ready update with a notification and icon badge. Click the notification or install menu item to review it. Confirm to end the simulation, or choose Later to keep the prompt. No download, installation or restart occurs."),NSRect(x:20,y:64,width:710,height:95),in:debugView)
        _=button(t("模拟有更新","Simulate update"),#selector(simulateUpdate),NSRect(x:20,y:172,width:180,height:32),in:debugView)
        tabs.selectTabViewItem(at:min(selected,debugEnabled ? 3:2))
        message=label("",NSRect(x:26,y:603,width:784,height:34),in:root,size:12)
        // This initially empty label later receives bilingual support lists.
        // Keep word wrapping explicit and reserve two full text lines above
        // the existing footer buttons, including the cell's drawing insets.
        message.maximumNumberOfLines=0;message.lineBreakMode = .byWordWrapping
        message.cell?.usesSingleLineMode=false;message.cell?.isScrollable=false;message.cell?.wraps=true
        _=button(t("恢复默认","Restore Defaults"),#selector(resetDefaults),NSRect(x:22,y:642,width:148,height:30),in:root)
        _=button(t("取消","Cancel"),#selector(cancel),NSRect(x:562,y:642,width:100,height:30),in:root)
        let save=button(t("保存并应用","Save & Apply"),#selector(save),NSRect(x:672,y:642,width:144,height:30),in:root); save.keyEquivalent="\r"
        refresh()
    }
    private func buildFixedPerches(in view:NSView) {
        label(t("固定小栖木","Fixed perches"),NSRect(x:20,y:4200,width:710,height:30),in:view,size:20).identifier=NSUserInterfaceItemIdentifier("fixedPerchSectionTitle")
        fixedPerchesButton=NSButton(checkboxWithTitle:t("启用固定小栖木","Enable fixed perches"),target:self,action:#selector(fixedPerchesChanged))
        fixedPerchesButton.frame=NSRect(x:20,y:4242,width:710,height:26)
        fixedPerchesButton.identifier=NSUserInterfaceItemIdentifier("fixedPerchesEnabled")
        fixedPerchesButton.setAccessibilityLabel(fixedPerchesButton.title);view.addSubview(fixedPerchesButton)
        label(t("栖木槽位","Perch slot"),NSRect(x:20,y:4288,width:120,height:26),in:view).identifier=NSUserInterfaceItemIdentifier("fixedPerchSlotLabel")
        fixedPerchSlotPopup=NSPopUpButton(frame:NSRect(x:145,y:4282,width:540,height:32),pullsDown:false)
        fixedPerchSlotPopup.target=self;fixedPerchSlotPopup.action=#selector(fixedPerchSlotChanged)
        fixedPerchSlotPopup.identifier=NSUserInterfaceItemIdentifier("fixedPerchSlot")
        fixedPerchSlotPopup.setAccessibilityLabel(t("栖木槽位","Perch slot"));view.addSubview(fixedPerchSlotPopup)
        fixedPerchStatus=label("",NSRect(x:20,y:4324,width:710,height:48),in:view,size:12)
        fixedPerchStatus.identifier=NSUserInterfaceItemIdentifier("fixedPerchStatus")
        placeFixedPerchButton=button("",#selector(placeFixedPerch),NSRect(x:20,y:4386,width:390,height:32),in:view)
        placeFixedPerchButton.identifier=NSUserInterfaceItemIdentifier("placeFixedPerch")
        removeFixedPerchButton=button(t("移除该栖木","Remove this perch"),#selector(removeFixedPerch),NSRect(x:430,y:4386,width:300,height:32),in:view)
        removeFixedPerchButton.identifier=NSUserInterfaceItemIdentifier("removeFixedPerch")
        removeFixedPerchButton.setAccessibilityLabel(removeFixedPerchButton.title)
        previewFixedPerchButton=button(t("预览访问","Preview visit"),#selector(previewFixedPerch),NSRect(x:20,y:4430,width:240,height:32),in:view)
        previewFixedPerchButton.identifier=NSUserInterfaceItemIdentifier("previewFixedPerch")
        previewFixedPerchButton.setAccessibilityLabel(previewFixedPerchButton.title)
        let names=language.supportedSpeciesNames(for:.fixedPerchVisit)
        label(t("最多 3 个栖木。点击放置后移动鼠标，3 秒后记录所在屏幕与相对坐标；放置、移动和移除仅改草稿，保存并应用后生效。关闭开关保留位置。\n支持鸟种：",
                "Up to 3 perches. Click Place, then move the pointer; after 3 seconds capture its display and relative coordinates. Place, move and remove edit the draft. Save & Apply to activate; turning off keeps positions.\nSupported species: ")+names+t("。\n安静陪伴停止新自动访问；屏幕断开时暂映射到可用屏幕，重连后恢复原位置。\n预览只使用已保存栖木和现有小鸟，不增加小鸟；缺少已保存栖木、合适小鸟或空间时，下方说明原因。",
                ".\nQuiet companionship stops new automatic visits. Disconnected displays map temporarily to an available display; reconnect to restore.\nPreview uses saved perches and existing birds, without adding birds. Missing perches, suitable birds or space are explained below."),NSRect(x:20,y:4476,width:710,height:150),in:view,size:12).identifier=NSUserInterfaceItemIdentifier("fixedPerchHelp")
        refreshFixedPerchControls()
    }
    private func refreshFixedPerchControls() {
        guard fixedPerchesButton != nil else {return}
        fixedPerchesButton.state=draft.fixedPerchesEnabled ? .on:.off
        fixedPerchSlotPopup.removeAllItems()
        for slot in 1...3 {
            let placed=draft.fixedPerches.contains{$0.slot==slot}
            fixedPerchSlotPopup.addItem(withTitle:t("栖木 \(slot) · ","Perch \(slot) · ")+(placed ? t("已放置","Placed"):t("未放置","Not placed")))
        }
        fixedPerchSlotPopup.selectItem(at:selectedFixedPerchSlot-1)
        let anchor=draft.fixedPerches.first{$0.slot==selectedFixedPerchSlot}
        if let anchor {
            let displayIndex=anchor.displayID.isEmpty ? desktop.displayRects.firstIndex(of:anchor.displayFrame):
                desktop.fixedPerchDisplayIDs.firstIndex(of:anchor.displayID)
            let display=displayIndex.map{t("屏幕 \($0+1)","Display \($0+1)")} ?? t("原屏幕暂未连接","Original display disconnected")
            fixedPerchStatus.stringValue=t("已放置 · ","Placed · ")+display+"\n" +
                t("相对坐标：","Relative coordinates: ")+String(format:"X %.1f%% · Y %.1f%%",anchor.x*100,anchor.y*100)
        } else {fixedPerchStatus.stringValue=t("此槽位尚未放置栖木。","No perch has been placed in this slot.")}
        refreshFixedPerchPlacementButton()
        removeFixedPerchButton.isEnabled=draft.fixedPerchesEnabled && anchor != nil
        // Preview intentionally remains available while the draft is off: it reads saved settings.
        previewFixedPerchButton.isEnabled=true
    }
    private func refreshFixedPerchPlacementButton() {
        guard let placeFixedPerchButton else {return}
        let placed=draft.fixedPerches.contains{$0.slot==selectedFixedPerchSlot}
        let pending=fixedPerchCaptureRequest != nil
        placeFixedPerchButton.title=pending ? t("等待采样 · 请移动鼠标…","Waiting for capture · Move the pointer…"):
            (placed ? t("3 秒后在鼠标处移动","Move to pointer in 3 seconds"):t("3 秒后在鼠标处放置","Place at pointer in 3 seconds"))
        placeFixedPerchButton.setAccessibilityLabel(placeFixedPerchButton.title)
        placeFixedPerchButton.isEnabled=draft.fixedPerchesEnabled && !pending
    }
    @objc func fixedPerchesChanged() {
        let enabled=fixedPerchesButton.state == .on
        cancelFixedPerchCapture()
        draft.fixedPerchesEnabled=enabled
        refreshFixedPerchControls();message.stringValue=t("尚未保存","Unsaved changes")
    }
    @objc func fixedPerchSlotChanged() {
        let slot=max(1,min(3,fixedPerchSlotPopup.indexOfSelectedItem+1))
        cancelFixedPerchCapture()
        selectedFixedPerchSlot=slot
        refreshFixedPerchControls()
        message.stringValue=t("已切换槽位；等待中的放置已取消。","Slot selected; any pending placement was cancelled.")
    }
    @objc func placeFixedPerch() {
        guard draft.fixedPerchesEnabled,window?.isVisible == true else {return}
        cancelFixedPerchCapture()
        let request=UUID();fixedPerchCaptureRequest=request
        // One-shot UI input sampling only. Bird motion remains on the engine clock.
        let timer=Timer(timeInterval:3,repeats:false) { [weak self] _ in
            guard let self,self.fixedPerchCaptureRequest==request else {return}
            self.captureFixedPerch(request:request,point:self.desktop.pointerPosition,
                                   displayIDs:self.desktop.fixedPerchDisplayIDs,displays:self.desktop.displayRects)
        }
        fixedPerchCaptureTimer=timer;RunLoop.main.add(timer,forMode:.common)
        refreshFixedPerchControls()
        message.stringValue=t("3 秒后记录鼠标位置；仅修改草稿，请移动到目标屏幕。","Capturing in 3 seconds; draft only. Move the pointer to your target display.")
    }
    /// Deterministic sampling boundary also used by the isolated settings verifier.
    func captureFixedPerch(request:UUID,point:CGPoint,displayIDs:[String],displays:[CGRect]) {
        guard fixedPerchCaptureRequest==request,window?.isVisible == true,draft.fixedPerchesEnabled else {return}
        let slot=selectedFixedPerchSlot
        cancelFixedPerchCapture()
        guard let anchor=FixedPerchAnchor.capture(slot:slot,point:point,displayIDs:displayIDs,displays:displays) else {
            refreshFixedPerchControls()
            message.stringValue=t("鼠标不在可用屏幕内，草稿未改变，请重试。","Pointer is outside available displays. Draft unchanged; try again.")
            return
        }
        draft.fixedPerches.removeAll{$0.slot==slot};draft.fixedPerches.append(anchor)
        draft.fixedPerches.sort{$0.slot<$1.slot}
        refreshFixedPerchControls()
        message.stringValue=t("已记录栖木位置（尚未保存）；保存并应用后生效。","Perch position captured in draft; Save & Apply to activate.")
    }
    @objc func removeFixedPerch() {
        guard draft.fixedPerchesEnabled else {return}
        cancelFixedPerchCapture()
        draft.fixedPerches.removeAll{$0.slot==selectedFixedPerchSlot}
        refreshFixedPerchControls();message.stringValue=t("已移除该栖木（尚未保存）。","Perch removed from draft (not saved).")
    }
    func cancelFixedPerchCapture() {
        fixedPerchCaptureTimer?.invalidate();fixedPerchCaptureTimer=nil;fixedPerchCaptureRequest=nil
        // Do not overwrite native checkbox/input values before Save reads them.
        refreshFixedPerchPlacementButton()
    }
    @objc private func fixedPerchWindowWillClose(_ notification:Notification) {
        cancelFixedPerchCapture();cancelFoodTrayPlacement();cancelBathPlacement();cancelCarryLeafPlacement()
    }
    @objc func previewFixedPerch() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.fixedPerchVisit(.preview))
        if case .rejected(let reason)=result {message.stringValue=fixedPerchPreviewMessage(reason)}
        else {message.stringValue=t("正在预览访问已保存的固定栖木。","Previewing a visit to a saved fixed perch.")}
    }
    func fixedPerchPreviewMessage(_ reason:BehaviorReason) -> String {
        if FixedPerchArt.shared == nil {
            return t("栖木图像未能载入，请重新安装完整测试版。","Perch artwork could not load. Reinstall the complete test app.")
        }
        if reason == .disabled || reason == .settingsChanged {
            return t("请先保存并启用固定小栖木。","Save and enable fixed perches first.")
        }
        if reason == .paused {return desktop.behaviorMessage(reason)}
        if desktop.settings.fixedPerches.isEmpty {
            return t("请先放置栖木并保存，预览只使用已保存的位置。","Place a perch and save first. Preview uses saved positions only.")
        }
        switch reason {
        case .noSpecies,.noCompanion,.missingBird,.unavailableBird:
            return t("请等待现有支持鸟种空闲并停稳：","Wait for an existing supported bird to settle and become available: ")+language.supportedSpeciesNames(for:.fixedPerchVisit)+t("。",".")
        case .noSpace,.targetInvalid:
            if desktop.engine.fixedPerchSnapshot().isEmpty {
                return t("已保存栖木暂无可用屏幕空间，请调整位置并保存。","Saved perches have no usable display space. Adjust their positions and save.")
            }
            return t("栖木或飞行空间不足，请调整位置并保存。","Not enough perch or flight space. Adjust the position and save.")
        default:return desktop.behaviorMessage(reason)
        }
    }
    private func buildFoodTray(in view:NSView) {
        label(t("临时食盘","Temporary food tray"),NSRect(x:20,y:4670,width:710,height:30),in:view,size:20).identifier=NSUserInterfaceItemIdentifier("foodTraySectionTitle")
        foodTrayButton=NSButton(checkboxWithTitle:t("启用临时食盘","Enable temporary food tray"),target:self,action:#selector(foodTraySettingsChanged))
        foodTrayButton.frame=NSRect(x:20,y:4712,width:710,height:26)
        foodTrayButton.state=draft.foodTrayEnabled ? .on:.off
        foodTrayButton.identifier=NSUserInterfaceItemIdentifier("foodTrayEnabled")
        foodTrayButton.setAccessibilityLabel(foodTrayButton.title);view.addSubview(foodTrayButton)
        placeFoodTrayButton=button(t("3 秒后在鼠标处放置食盘","Place tray at pointer in 3 seconds"),#selector(placeFoodTray),NSRect(x:20,y:4758,width:350,height:32),in:view)
        removeFoodTrayButton=button(t("移除食盘","Remove food tray"),#selector(removeFoodTray),NSRect(x:390,y:4758,width:340,height:32),in:view)
        cancelFoodTrayPlacementButton=button(t("取消等待中的放置","Cancel pending placement"),#selector(cancelFoodTrayPlacementClicked),NSRect(x:20,y:4804,width:350,height:32),in:view)
        previewFoodTrayButton=button(t("预览食盘访问","Preview food tray visit"),#selector(previewFoodTray),NSRect(x:390,y:4804,width:340,height:32),in:view)
        for (control,id) in [(placeFoodTrayButton!,"placeFoodTray"),(removeFoodTrayButton!,"removeFoodTray"),
                             (cancelFoodTrayPlacementButton!,"cancelFoodTrayPlacement"),(previewFoodTrayButton!,"previewFoodTray")] {
            control.identifier=NSUserInterfaceItemIdentifier(id);control.setAccessibilityLabel(control.title)
        }
        label(t("每次放置含 3 份食物，最多保留 180 秒；暂停动画会冻结食盘寿命和放置倒计时。支持鸟种：\(language.supportedSpeciesNames(for:.foodTrayVisit))。鼠标靠近会取消取食。\n\n开关默认开启，保存后生效。同时只保留一个食盘，请先移除再放置。放置和移除立即生效，不修改栖木位置草稿，不保存食盘位置；下次启动需重新放置。移除会取消等待中的放置，让访问中的小鸟安全恢复；不会删除栖木。\n\n点击放置后把鼠标移到目标处，3 秒后由引擎采样光标。关闭、取消或重建设置窗口会取消等待中的放置。预览使用已保存开关、已放置食盘与现有小鸟，不生成鸟。无需定时喂养，不喂没有惩罚。",
                "Each tray holds 3 portions and lasts up to 180 seconds. Pausing animation freezes its lifetime and placement countdown. Supported species: \(language.supportedSpeciesNames(for:.foodTrayVisit)). A nearby pointer cancels feeding.\n\nOn by default; save to apply the switch. Only one tray at a time: remove it before placing another. Place and Remove apply immediately, without editing perch position drafts or saving tray positions. Place again after restarting. Removal cancels pending placement and safely restores visiting birds; perches stay in place.\n\nAfter clicking Place, move the pointer to the target; the engine samples it after 3 seconds. Closing, cancelling or rebuilding Settings cancels pending placement. Preview uses the saved switch, a placed tray and existing birds, without spawning birds. No feeding schedule or penalty for not feeding."),NSRect(x:20,y:4852,width:710,height:274),in:view,size:12).identifier=NSUserInterfaceItemIdentifier("foodTrayHelp")
        foodTrayStatus=label("",NSRect(x:20,y:5142,width:710,height:62),in:view,size:12)
        foodTrayStatus.identifier=NSUserInterfaceItemIdentifier("foodTrayStatus")
        foodTrayStatus.setAccessibilityLabel(t("临时食盘状态","Temporary food tray status"))
        refreshFoodTrayControls()
    }
    /// Read engine state only; never copy temporary placement into the settings draft.
    func refreshFoodTrayControls() {
        guard foodTrayStatus != nil else {return}
        let pending=desktop.engine.hasFoodTrayPlacement
        if !pending {ownsFoodTrayPlacement=false}
        placeFoodTrayButton.isEnabled = !pending
        cancelFoodTrayPlacementButton.isEnabled=pending
        let tray=desktop.engine.habitatSnapshot().first{$0.kind == .foodTray}
        removeFoodTrayButton.isEnabled=pending || tray != nil
        // These actions read saved settings, even if the checkbox draft is off.
        previewFoodTrayButton.isEnabled=true
        if pending {
            foodTrayStatus.stringValue=t("等待引擎计时：请移动鼠标到目标位置；暂停时倒计时冻结。","Waiting on the engine clock: move the pointer to the target. Pausing freezes the countdown.")
        } else if let tray {
            let seconds=Int(ceil(min(180,max(0,tray.remainingLifetime))))
            foodTrayStatus.stringValue=tray.retiring
                ? t("食盘正在收回，访问中的小鸟将安全恢复。","Tray is retiring; visiting birds will recover safely.")
                : t("临时食盘已放置 · 剩余 \(tray.remainingUses) / 3 份 · \(seconds) 秒","Temporary tray placed · \(tray.remainingUses) / 3 portions · \(seconds) seconds remaining")
        } else {
            foodTrayStatus.stringValue=HabitatObjectRenderer.foodTrayArtAvailable
                ? t("尚未放置临时食盘；位置不会保存。","No temporary tray placed; its position is never saved.")
                : t("食盘图像未能载入，暂不能放置食盘。","Food tray artwork could not load; placement is unavailable.")
        }
    }
    @objc func foodTraySettingsChanged() {
        draft.foodTrayEnabled=foodTrayButton.state == .on
        if !draft.foodTrayEnabled {cancelFoodTrayPlacement()}
        message.stringValue=t("尚未保存 · 食盘开关保存后生效。","Unsaved · Save to apply the tray switch.")
    }
    @objc func placeFoodTray() {
        guard window?.isVisible == true else {return}
        desktop.syncWorld()
        let result=desktop.engine.handle(.placeFoodTrayAfter(3))
        if case .rejected(let reason)=result {message.stringValue=foodTrayMessage(reason,placing:true)}
        else {
            ownsFoodTrayPlacement=true
            message.stringValue=t("3 秒后直接放置临时食盘，请移动鼠标到目标位置。","Placing a temporary tray in 3 seconds; move the pointer to the target.")
        }
        refreshFoodTrayControls()
    }
    func cancelFoodTrayPlacement() {
        if desktop.engine.hasFoodTrayPlacement {desktop.engine.handle(.cancelFoodTrayPlacement)}
        ownsFoodTrayPlacement=false
        refreshFoodTrayControls()
    }
    @objc func cancelFoodTrayPlacementClicked() {
        cancelFoodTrayPlacement()
        desktop.consumeBehaviorEvents()
        message.stringValue=t("已取消等待中的食盘放置；已放置食盘保留。","Pending placement cancelled; an existing tray stays in place.")
    }
    @objc func removeFoodTray() {
        desktop.engine.handle(.removeFoodTray)
        desktop.consumeBehaviorEvents()
        refreshFoodTrayControls()
        message.stringValue=t("已移除食盘并取消等待中的放置；栖木保留。","Tray removed and pending placement cancelled; perches stay in place.")
    }
    @objc func previewFoodTray() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.foodTrayVisit(.preview))
        if case .rejected(let reason)=result {message.stringValue=foodTrayMessage(reason)}
        else {message.stringValue=t("正在预览现有小鸟访问食盘，不会生成鸟。","Previewing an existing bird’s tray visit; no birds are spawned.")}
        refreshFoodTrayControls()
    }
    func foodTrayMessage(_ reason:BehaviorReason,placing:Bool=false) -> String {
        if !HabitatObjectRenderer.foodTrayArtAvailable {
            return t("食盘图像未能载入，请安装完整版本后重试。","Food tray artwork could not load. Install the complete app and try again.")
        }
        switch reason {
        case .busy:
            if placing,!desktop.engine.habitatSnapshot().isEmpty {
                if desktop.engine.habitatSnapshot().contains(where:{$0.kind != .foodTray}) {return language.sceneBusyMessage}
                return t("已有临时食盘，请先移除食盘再放置；食物和剩余时间不会重置。","A temporary tray is already placed. Remove it before placing another; food and remaining time stay unchanged.")
            }
            return desktop.behaviorMessage(reason)
        case .disabled,.settingsChanged:return t("请先保存并启用临时食盘。","Save and enable the temporary food tray first.")
        case .noSpecies,.noCompanion,.missingBird,.unavailableBird:
            return t("请等待现有支持鸟种空闲并停稳：","Wait for an existing supported bird to settle and become available: ")+language.supportedSpeciesNames(for:.foodTrayVisit)+t("；预览不会生成鸟。","; preview never spawns birds.")
        case .targetInvalid,.removed:
            return t("请先放置可用食盘，再把鼠标移远后预览。","Place an available tray first, then move the pointer away before previewing.")
        case .noSpace:
            if desktop.engine.habitatSnapshot().isEmpty {
                return t("请先在开阔位置放置食盘，留出小鸟访问的空间。","Place a tray in a clear area first, with room for birds to visit.")
            }
            return t("食盘访问路线空间不足，请移除后在更开阔的位置重新放置。","Not enough flight space to visit. Remove the tray, then place it in a clearer area.")
        case .pointerNearby:return t("鼠标靠近会取消取食，请先把鼠标移离食盘与小鸟。","A nearby pointer cancels feeding. Move it away from the tray and birds.")
        default:return desktop.behaviorMessage(reason)
        }
    }
    private func buildBath(in view:NSView) {
        label(t("浅水浴盆","Shallow bird bath"),NSRect(x:20,y:5260,width:710,height:30),in:view,size:20).identifier=NSUserInterfaceItemIdentifier("bathSectionTitle")
        bathButton=NSButton(checkboxWithTitle:t("开启浴盆访问","Enable bath visits"),target:self,action:#selector(bathSettingsChanged))
        bathButton.frame=NSRect(x:20,y:5302,width:710,height:26);bathButton.state=draft.bathEnabled ? .on:.off
        bathButton.identifier=NSUserInterfaceItemIdentifier("bathEnabled");bathButton.setAccessibilityLabel(bathButton.title);view.addSubview(bathButton)
        placeBathButton=button(t("3 秒后在鼠标处放置浴盆","Place bath at pointer in 3 seconds"),#selector(placeBath),NSRect(x:20,y:5348,width:350,height:32),in:view)
        removeBathButton=button(t("移除浴盆","Remove bath"),#selector(removeBath),NSRect(x:390,y:5348,width:340,height:32),in:view)
        cancelBathPlacementButton=button(t("取消等待中的浴盆放置","Cancel pending bath placement"),#selector(cancelBathPlacementClicked),NSRect(x:20,y:5394,width:350,height:32),in:view)
        clearCurrentSceneButton=button(t("清除当前场景","Clear current scene"),#selector(clearCurrentScene),NSRect(x:390,y:5394,width:340,height:32),in:view)
        previewBathButton=button(t("预览洗澡","Preview bathing"),#selector(previewBath),NSRect(x:20,y:5440,width:350,height:32),in:view)
        for (control,id) in [(placeBathButton!,"placeBath"),(removeBathButton!,"removeBath"),
                             (cancelBathPlacementButton!,"cancelBathPlacement"),(clearCurrentSceneButton!,"clearCurrentScene"),
                             (previewBathButton!,"previewBath")] {
            control.identifier=NSUserInterfaceItemIdentifier(id);control.setAccessibilityLabel(control.title)
        }
        label(t("支持鸟种：","Supported species: ")+language.supportedSpeciesNames(for:.bathVisit)+t("。\n浴盆最多保留 300 秒，供成功洗澡 3 次；完成洗澡并安全离开落稳才扣次数和记录，取消不计。暂停冻结放置、寿命与水花。\n\n开关默认开启，保存后生效。放置后不会立即召鸟；预览使用已保存开关、现有停稳小鸟和真实空间，不生成鸟、不改鸟种概率。鼠标靠近会取消访问。\n\n点击放置后移动鼠标，3 秒后采样目标位置。浴盆与食盘共用一个场景位，已有场景时先清除，不自动替换；固定栖木保留。关闭、取消、保存、重置或重建设置会取消等待中的放置。浴盆与位置不跨重启保存，无需定时照料。",
            ".\nA bath lasts up to 300 seconds or 3 successful visits. A visit is counted only after bathing and a safe departure and landing; cancellation does not count. Pausing freezes placement, lifetime and splashes.\n\nOn by default; save to apply. Placement does not summon birds immediately. Previews use saved settings, existing settled birds and safe space, without spawning birds or changing species probabilities. A nearby pointer cancels visits.\n\nAfter Place, move the pointer; its position is sampled after 3 seconds. Baths and trays share one scene slot: clear an existing scene first; perches remain. Closing, cancelling, saving, resetting or rebuilding Settings cancels pending placement. Baths and positions are not saved across restarts. No care schedule is required."),NSRect(x:20,y:5486,width:710,height:220),in:view,size:12).identifier=NSUserInterfaceItemIdentifier("bathHelp")
        bathStatus=label("",NSRect(x:20,y:5722,width:710,height:70),in:view,size:12)
        bathStatus.identifier=NSUserInterfaceItemIdentifier("bathStatus");bathStatus.setAccessibilityLabel(t("浴盆状态","Bath status"))
        refreshBathControls()
    }
    func refreshBathControls() {
        guard bathStatus != nil else {return}
        let pending=desktop.engine.hasBathPlacement
        if !pending {ownsBathPlacement=false}
        let objects=desktop.engine.habitatSnapshot(),bath=objects.first{$0.kind == .bath}
        placeBathButton.isEnabled = !pending
        cancelBathPlacementButton.isEnabled=pending
        removeBathButton.isEnabled=pending || bath != nil
        clearCurrentSceneButton.isEnabled=pending || desktop.engine.hasFoodTrayPlacement || desktop.engine.hasCarryLeafPlacement || !objects.isEmpty || desktop.engine.scenePropCount>0
        previewBathButton.isEnabled=true
        if pending {bathStatus.stringValue=t("等待 3 秒采样鼠标位置；暂停冻结倒计时。","Waiting to sample the pointer after 3 seconds; pausing freezes the countdown.")}
        else if let bath {
            bathStatus.stringValue=bath.retiring ? t("浴盆正在收回，小鸟将安全离开。","Bath is retiring; the bird will leave safely."):
                t("浴盆已放置 · 剩余 \(bath.remainingUses) / 3 次 · \(Int(ceil(max(0,bath.remainingLifetime)))) 秒","Bath placed · \(bath.remainingUses) / 3 visits · \(Int(ceil(max(0,bath.remainingLifetime)))) seconds remaining")
        } else if let object=objects.first {bathStatus.stringValue=language.habitatName(object.kind)+t("已占用场景位。"," occupies the scene slot.")+language.sceneBusyMessage}
        else {bathStatus.stringValue=HabitatObjectRenderer.bathArtAvailable ?
            t("尚未放置浴盆；所需鸟种：","No bath placed. Required species: ")+language.supportedSpeciesNames(for:.bathVisit)+t("。","."):
            t("浴盆素材未能载入，暂不能放置或预览。","Bath artwork could not load; placement and previews are unavailable.")}
    }
    @objc func bathSettingsChanged() {
        draft.bathEnabled=bathButton.state == .on
        if !draft.bathEnabled {cancelBathPlacement()}
        message.stringValue=t("尚未保存 · 浴盆开关保存后生效。","Unsaved · Save to apply the bath switch.")
    }
    @objc func placeBath() {
        guard window?.isVisible == true else {return}
        desktop.syncWorld()
        let result=desktop.engine.handle(.placeBathAfter(3))
        if case .rejected(let reason)=result {message.stringValue=bathMessage(reason,placing:true)}
        else {ownsBathPlacement=true;message.stringValue=t("3 秒后放置临时浴盆，请把鼠标移到开阔位置。","Placing a temporary bath in 3 seconds; move the pointer to a clear area.")}
        refreshBathControls();refreshFoodTrayControls()
    }
    func cancelBathPlacement() {
        if desktop.engine.hasBathPlacement {desktop.engine.handle(.cancelBathPlacement)}
        ownsBathPlacement=false;refreshBathControls()
    }
    @objc func cancelBathPlacementClicked() {
        cancelBathPlacement();desktop.consumeBehaviorEvents()
        message.stringValue=t("已取消等待中的浴盆放置；已放置场景保留。","Pending bath placement cancelled; an existing scene stays in place.")
    }
    @objc func removeBath() {
        desktop.engine.handle(.removeBath);desktop.consumeBehaviorEvents()
        refreshBathControls();refreshFoodTrayControls()
        message.stringValue=t("已移除浴盆并取消等待中的放置；固定栖木保留。","Bath removed and pending placement cancelled; fixed perches remain.")
    }
    @objc func clearCurrentScene() {
        desktop.engine.handle(.clearCurrentScene);desktop.consumeBehaviorEvents()
        ownsBathPlacement=false;ownsFoodTrayPlacement=false;ownsCarryLeafPlacement=false
        refreshBathControls();refreshFoodTrayControls();refreshLeafCarryControls()
        message.stringValue=t("已清除当前临时场景并取消待放置操作；固定栖木保留。","Current temporary scene cleared and pending placement cancelled; fixed perches remain.")
    }
    @objc func previewBath() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.bathVisit(.preview))
        if case .rejected(let reason)=result {message.stringValue=bathMessage(reason)}
        else {message.stringValue=t("正在预览洗澡：观察、试水、洗澡、甩水，再安全离开落稳。","Previewing bathing: inspect, touch the water, bathe, shake, then leave and land safely.")}
        refreshBathControls()
    }
    func bathMessage(_ reason:BehaviorReason,placing:Bool=false) -> String {
        if !HabitatObjectRenderer.bathArtAvailable {return t("浴盆或水花素材未能载入，请安装完整版本后重试。","Bath or splash artwork could not load. Install the complete app and retry.")}
        switch reason {
        case .busy:return placing ? language.sceneBusyMessage:desktop.behaviorMessage(reason)
        case .disabled,.settingsChanged:return t("请先保存并开启浴盆访问。","Save and enable bath visits first.")
        case .noSpecies,.noCompanion,.missingBird,.unavailableBird:
            return t("请等待现有支持鸟种停稳并安静下来：","Wait for an existing supported bird to settle calmly: ")+language.supportedSpeciesNames(for:.bathVisit)+t("。",".")
        case .missingFrames:return t("洗澡专用帧不完整，无法预览；所需鸟种：","Bathing frames are incomplete. Required species: ")+language.supportedSpeciesNames(for:.bathVisit)+t("。",".")
        case .targetInvalid,.removed:return t("请先放置可用浴盆，再把鼠标移远后预览。","Place an available bath first, then move the pointer away before previewing.")
        case .noSpace:
            if !placing && !desktop.engine.habitatSnapshot().contains(where:{$0.kind == .bath}) {
                return t("请先放置浴盆，再把鼠标移远并等待支持鸟种停稳。","Place a bath first, then move the pointer away and let a supported bird settle.")
            }
            return placing ? t("浴盆与小鸟需要完整空间，请把鼠标移到更开阔的位置后重试。","The bath and bird need clear space. Move the pointer to a more open area and retry."):
                t("浴盆、飞入与离开的空间不足，或原停靠处不可用；请调整场景后重试。","Not enough room at the bath or along the arrival and departure routes, or the original perch is unavailable. Adjust the scene and retry.")
        case .pointerNearby,.pointerMoved:return t("请把鼠标移离浴盆、小鸟与访问路线后再试。","Move the pointer away from the bath, bird and visit route, then retry.")
        default:return desktop.behaviorMessage(reason)
        }
    }
    private func buildLeafCarry(in view:NSView) {
        label(t("静止叶片与携带","Static leaf carrying"),NSRect(x:20,y:5840,width:710,height:30),in:view,size:20).identifier=NSUserInterfaceItemIdentifier("leafCarrySectionTitle")
        leafCarryButton=NSButton(checkboxWithTitle:t("开启静止叶片携带","Enable static leaf carrying"),target:self,action:#selector(leafCarrySettingsChanged))
        leafCarryButton.frame=NSRect(x:20,y:5882,width:710,height:26);leafCarryButton.state=draft.leafCarryEnabled ? .on:.off
        leafCarryButton.identifier=NSUserInterfaceItemIdentifier("leafCarryEnabled");leafCarryButton.setAccessibilityLabel(leafCarryButton.title);view.addSubview(leafCarryButton)
        placeCarryLeafButton=button(t("3 秒后放置静止叶片","Place static leaf in 3 seconds"),#selector(placeCarryLeaf),NSRect(x:20,y:5928,width:350,height:32),in:view)
        removeCarryLeafButton=button(t("清除携带叶片","Clear carrying leaf"),#selector(removeCarryLeaf),NSRect(x:390,y:5928,width:340,height:32),in:view)
        cancelCarryLeafPlacementButton=button(t("取消等待中的叶片放置","Cancel pending leaf placement"),#selector(cancelCarryLeafPlacementClicked),NSRect(x:20,y:5974,width:350,height:32),in:view)
        previewLeafCarryButton=button(t("预览携带叶片","Preview leaf carrying"),#selector(previewLeafCarry),NSRect(x:390,y:5974,width:340,height:32),in:view)
        for (control,id) in [(placeCarryLeafButton!,"placeCarryLeaf"),(removeCarryLeafButton!,"removeCarryLeaf"),
                             (cancelCarryLeafPlacementButton!,"cancelCarryLeafPlacement"),(previewLeafCarryButton!,"previewLeafCarry")] {
            control.identifier=NSUserInterfaceItemIdentifier(id);control.setAccessibilityLabel(control.title)
        }
        label(language.leafCarrySupport+t("\n这是风格化的物件互动，独立于上方动态落叶追随。麻雀观察、低头叼起静止叶片，短途飞行后放下并恢复；不会生成鸟或改变鸟种概率。\n\n默认开启，保存后生效；放置与预览读取已保存开关。点击放置后，把鼠标移到普通窗口顶部或地面边缘，3 秒后采样；任意空中坐标不能承载叶片。请移开鼠标并留出拾取、携带与放下的空间。\n\n全局仅一枚可拾取叶片，拾取前保留 180 秒；成功放下后展示 8 秒，再淡出。暂停冻结倒计时、飞行与附着。清除会取消等待或当前携带，并收回叶片；点击鸟仍立即换位。\n\n关闭、取消、保存、重置或重建设置会取消等待中的放置，不改其他草稿。叶片和位置不跨重启保存。",
            "\nA stylized object interaction, separate from moving Leaf play above. A sparrow looks, lowers its head, grips a static leaf, flies a short distance, places it and recovers. No birds are spawned and species probabilities stay unchanged.\n\nOn by default; save to apply. Placement and preview use the saved switch. After Place, move the pointer to a normal window's top edge or a ground edge; it is sampled after 3 seconds. A point in open air cannot support a leaf. Move away and leave safe room to pick up, carry and place it.\n\nOne pickable leaf at a time, lasting 180 seconds before pickup. A placed leaf stays for 8 seconds, then fades. Pausing freezes countdowns, flight and attachment. Clear cancels pending or active carrying and removes the leaf; bird clicks still relocate immediately.\n\nClosing, cancelling, saving, resetting or rebuilding Settings cancels pending placement without editing other drafts. Leaves and positions are not saved across restarts."),NSRect(x:20,y:6022,width:710,height:268),in:view,size:12).identifier=NSUserInterfaceItemIdentifier("leafCarryHelp")
        leafCarryStatus=label("",NSRect(x:20,y:6306,width:710,height:76),in:view,size:12)
        leafCarryStatus.identifier=NSUserInterfaceItemIdentifier("leafCarryStatus");leafCarryStatus.setAccessibilityLabel(t("携带叶片状态","Carrying leaf status"))
        refreshLeafCarryControls()
    }
    func refreshLeafCarryControls() {
        guard leafCarryStatus != nil else {return}
        let pending=desktop.engine.hasCarryLeafPlacement
        if !pending {ownsCarryLeafPlacement=false}
        let leaves=desktop.engine.propSnapshot().filter{$0.kind == .leafToken}
        placeCarryLeafButton.isEnabled = !pending
        cancelCarryLeafPlacementButton.isEnabled=pending
        removeCarryLeafButton.isEnabled=pending || !leaves.isEmpty
        previewLeafCarryButton.isEnabled=true
        if pending {leafCarryStatus.stringValue=t("等待 3 秒采样承载边缘；暂停冻结倒计时。","Waiting to sample a supporting edge after 3 seconds; pausing freezes the countdown.")}
        else if !leaves.isEmpty {leafCarryStatus.stringValue=t("场景中有一枚携带叶片；可清除收回。位置不保存。","A carrying leaf is in the scene; Clear removes it. Its position is not saved.")}
        else {leafCarryStatus.stringValue=ScenePropRenderer.leafCarryArtAvailable ?
            t("尚未放置静止叶片。","No static leaf placed. ")+language.leafCarrySupport:
            t("携带叶片素材未能载入，暂不能放置或预览。","Carrying leaf artwork could not load; placement and previews are unavailable.")}
    }
    @objc func leafCarrySettingsChanged() {
        draft.leafCarryEnabled=leafCarryButton.state == .on
        if !draft.leafCarryEnabled {cancelCarryLeafPlacement()}
        message.stringValue=t("尚未保存 · 静止叶片携带保存后生效。","Unsaved · Save to apply static leaf carrying.")
    }
    @objc func placeCarryLeaf() {
        guard window?.isVisible == true else {return}
        desktop.syncWorld()
        let result=desktop.engine.handle(.placeCarryLeafAfter(3))
        if case .rejected(let reason)=result {message.stringValue=leafCarryMessage(reason,placing:true)}
        else {ownsCarryLeafPlacement=true;message.stringValue=t("3 秒后放置静止叶片，请把鼠标移到普通窗口顶部或地面边缘。","Placing a static leaf in 3 seconds; move the pointer to a window top or ground edge.")}
        refreshLeafCarryControls();refreshBathControls()
    }
    func cancelCarryLeafPlacement() {
        if desktop.engine.hasCarryLeafPlacement {desktop.engine.handle(.cancelCarryLeafPlacement)}
        ownsCarryLeafPlacement=false;refreshLeafCarryControls()
    }
    @objc func cancelCarryLeafPlacementClicked() {
        cancelCarryLeafPlacement();desktop.consumeBehaviorEvents()
        message.stringValue=t("已取消等待中的静止叶片放置；现有叶片保留。","Pending static leaf placement cancelled; an existing leaf stays in place.")
    }
    @objc func removeCarryLeaf() {
        desktop.engine.handle(.removeCarryLeaf);desktop.consumeBehaviorEvents()
        refreshLeafCarryControls();refreshBathControls()
        message.stringValue=t("已清除携带叶片并取消等待中的放置。","Carrying leaf cleared and pending placement cancelled.")
    }
    @objc func previewLeafCarry() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.leafCarry(.preview))
        if case .rejected(let reason)=result {message.stringValue=leafCarryMessage(reason)}
        else {message.stringValue=t("正在预览携带叶片：观察、拾取、短途携带、放下并恢复。","Previewing leaf carrying: look, pick up, fly a short distance, place and recover.")}
        refreshLeafCarryControls()
    }
    func leafCarryMessage(_ reason:BehaviorReason,placing:Bool=false)->String {
        if !ScenePropRenderer.leafCarryArtAvailable {return t("携带叶片素材未能载入，请安装完整版本后重试。","Carrying leaf artwork could not load. Install the complete app and retry.")}
        switch reason {
        case .disabled,.settingsChanged:return t("请先保存并开启静止叶片携带。","Save and enable static leaf carrying first.")
        case .noSpecies,.noCompanion,.missingBird,.unavailableBird:
            return t("请等待现有支持鸟种空闲并停稳。","Wait for an existing supported bird to settle and become available. ")+language.leafCarrySupport
        case .missingFrames:return t("携带专用姿态或飞行喙锚不完整，无法预览。","Carrying poses or flight bill anchors are incomplete. ")+language.leafCarrySupport
        case .targetInvalid,.removed:return t("请先在普通窗口顶部或地面边缘放置静止叶片，再移开鼠标。","Place a static leaf on a window top or ground edge first, then move the pointer away.")
        case .noSpace:return placing ?
            t("这里没有可用承载边缘或完整叶片空间，请选择普通窗口顶部或地面边缘。","No usable supporting edge or leaf clearance here. Choose a normal window top or ground edge."):
            t("拾取、携带或放下空间不足，请在更开阔的同屏边缘重新放置叶片。","Not enough room to pick up, carry or place. Put the leaf on a clearer edge on the same display.")
        case .busy:return placing ?
            t("已有叶片、场景互动或放置操作正在占用位置。请等待结束，或取消等待中的放置；如需替换叶片，请先清除叶片。","A leaf, scene interaction or placement is already active. Wait or cancel pending placement; clear the existing leaf only to replace it."):
            t("请等待当前场景互动或放置操作结束，再预览携带。","Wait for the current scene interaction or placement to finish before previewing carrying.")
        case .pointerNearby,.pointerMoved:return t("请把鼠标移离小鸟、叶片和携带路线后再试。","Move the pointer away from the bird, leaf and carrying route, then retry.")
        default:return desktop.behaviorMessage(reason)
        }
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
        draft.chaseEnabled=chaseButton.state == .on
        chaseButton.isEnabled=draft.socialInteractions
        draft.travelTogetherEnabled=travelTogetherButton.state == .on
        travelTogetherButton.isEnabled=draft.socialInteractions
        draft.allopreeningEnabled=allopreeningButton.state == .on
        allopreeningButton.isEnabled=draft.socialInteractions
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
        draft.sideHopEnabled=sideHopButton.state == .on
        draft.takeoffPreparationEnabled=takeoffPreparationButton.state == .on
        sideHopButton.isEnabled=draft.perchActions;takeoffPreparationButton.isEnabled=draft.perchActions
        draft.edgePeekEnabled=edgePeekButton.state == .on
        edgePeekButton.isEnabled=draft.perchActions
        message.stringValue=t("尚未保存","Unsaved changes")
    }
    @objc func leafSettingsChanged() {
        draft.leafPlayEnabled=leafPlayButton.state == .on
        draft.ambientLeafPlayEnabled=ambientLeafPlayButton.state == .on
        ambientLeafPlayButton.isEnabled=draft.leafPlayEnabled
        message.stringValue=t("尚未保存","Unsaved changes")
    }
    @objc func visitorMemorySettingsChanged() {
        draft.visitorMemoryEnabled=visitorMemoryButton.state == .on
        message.stringValue=t("尚未保存","Unsaved changes")
    }
    @objc func activityRhythmSettingsChanged() {
        let index=activityRhythmPopup.indexOfSelectedItem
        guard ActivityRhythmMode.allCases.indices.contains(index) else {return}
        draft.activityRhythm=ActivityRhythmMode.allCases[index]
        message.stringValue=t("尚未保存","Unsaved changes")
    }
    @objc func releaseLeaf() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.releaseLeafAfter(3))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("3 秒后尝试放下落叶：请将鼠标移到屏幕中部的空旷位置。","Releasing in 3 seconds: move the pointer to a clear area near screen center.")}
    }
    @objc func clearLeaf() {
        desktop.engine.handle(.clearLeaf)
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
    @objc func previewSideHop() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.sideHop(.preview))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("正在预览小跳让路，小鸟会沿当前边缘挪开一步。","Previewing a short hop along the current ledge.")}
    }
    @objc func previewTakeoffPreparation() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.prepareTakeoff(.preview))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("正在预览起飞准备：专用鸟会下蹲、蹬伸，其余保留原表现；点击可立即换位。","Previewing takeoff preparation: dedicated crouch/push poses, existing poses for other species; clicks relocate immediately.")}
    }
    @objc func previewEdgePeek() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.edgePeek(.preview))
        if case .rejected(let reason)=result {
            message.stringValue=reason == .noSpecies
                ? t("请等待支持鸟种在窗口上沿端点附近停稳：","Wait for a supported bird to settle near a window’s top-edge endpoint: ")+language.supportedSpeciesNames(for:.edgePeek)+t("。",".")
                : desktop.behaviorMessage(reason)
        }
        else {message.stringValue=t("正在预览探头观察：小鸟会安全靠近边缘、低头，再退回原位。","Previewing edge peeking: the bird approaches safely, looks down, then retreats.")}
    }
    @objc func previewChase() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.chase(.preview))
        if case .rejected(let reason)=result {message.stringValue=chasePreviewMessage(reason)}
        else {message.stringValue=t("正在预览短暂追逐：两鸟先后起飞，追逐几秒，再各自落回。","Previewing a brief chase: two birds take off in turn, chase briefly, then return.")}
    }
    func chasePreviewMessage(_ reason:BehaviorReason) -> String {
        switch reason {
        case .noSpecies:
            return t("此处没有支持追逐的鸟种，请参考上方鸟种说明。","No supported chase species here. See the species list above.")
        case .noCompanion,.missingBird,.unavailableBird:
            return t("请等待两只支持追逐的同种鸟在附近停稳。","Wait for two supported birds of the same species to settle nearby.")
        case .noSpace:
            return t("追逐和落回的空间不足，请等待更开阔的位置。","Not enough room to chase and return. Wait for a clearer area.")
        case .disabled,.settingsChanged:
            return t("请先保存并开启双鸟互动和短暂追逐。","Save and enable Two-bird interactions and Brief chases first.")
        default:return desktop.behaviorMessage(reason)
        }
    }
    @objc func previewTravelTogether() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.travelTogether(.preview))
        if case .rejected(let reason)=result {message.stringValue=travelTogetherPreviewMessage(reason)}
        else {message.stringValue=t("正在预览飞行中结队：两鸟靠拢同行约 2 秒，再分开飞向各自原目标。","Previewing travel together: birds draw closer for about 2 seconds, then resume their original routes.")}
    }
    func travelTogetherPreviewMessage(_ reason:BehaviorReason) -> String {
        switch reason {
        case .noSpecies:
            return t("没有支持结队的飞行鸟种，请参考上方鸟种说明；不会让停栖鸟起飞。","No supported species in flight. See the list above; perched birds will stay perched.")
        case .noCompanion,.missingBird,.unavailableBird:
            return t("请等待两只支持结队的同种居民鸟正在独立飞行；不会让停栖鸟起飞。","Wait for two supported same-species residents flying independently; perched birds stay perched.")
        case .noSpace:
            return t("飞行中靠拢、同行与分开的空间不足，请等待更开阔的飞行路线。","Not enough room to draw closer, fly together and separate. Wait for clearer flight routes.")
        case .disabled,.settingsChanged:
            return t("请先保存并开启双鸟互动和飞行中临时结队。","Save and enable Two-bird interactions and Travel together in flight first.")
        default:return desktop.behaviorMessage(reason)
        }
    }
    @objc func previewAllopreening() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.allopreening(.preview))
        if case .rejected(let reason)=result {message.stringValue=allopreeningPreviewMessage(reason)}
        else {message.stringValue=t("正在预览同伴理羽：两鸟靠近、轻理头颈，再退回原位，约 6 秒。","Previewing companion preening: birds draw closer, gently preen, then return in about 6 seconds.")}
    }
    func allopreeningPreviewMessage(_ reason:BehaviorReason) -> String {
        switch reason {
        case .noSpecies:
            return t("请等待支持同伴理羽的鸟种停稳：","Wait for a supported companion-preening species to settle: ")+language.supportedSpeciesNames(for:.allopreening)+t("。",".")
        case .noCompanion,.missingBird,.unavailableBird:
            return t("请让两只支持理羽的同种鸟在同一窗口相邻停稳，并把鼠标移远。支持鸟种：","Let two supported birds of the same species settle together on one window; move the pointer away. Supported species: ")+language.supportedSpeciesNames(for:.allopreening)+t("。",".")
        case .noSpace:
            return t("同伴理羽的靠近和退回空间不足，请等待更开阔的窗口边缘。","Not enough room to approach and return. Wait for a clearer window edge.")
        case .disabled,.settingsChanged:
            return t("请先保存并开启双鸟互动和同伴理羽。","Save and enable Two-bird interactions and Companion preening first.")
        default:return desktop.behaviorMessage(reason)
        }
    }
    @objc func previewWatch() {
        desktop.syncWorld()
        let result=desktop.engine.handle(.attention(.watch,.preview))
        if case .rejected(let reason)=result {message.stringValue=desktop.behaviorMessage(reason)}
        else {message.stringValue=t("正在预览留意鼠标：专用鸟种显示观察姿态，其余保留原表现；小鸟停稳即可，鼠标可以远离。","Previewing observation: pose species use dedicated poses; others keep existing poses. Settled birds can be far from the pointer.")}
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
        draft.sideHopEnabled=sideHopButton.state == .on
        draft.takeoffPreparationEnabled=takeoffPreparationButton.state == .on
        sideHopButton.isEnabled=draft.perchActions;takeoffPreparationButton.isEnabled=draft.perchActions
        draft.edgePeekEnabled=edgePeekButton.state == .on
        edgePeekButton.isEnabled=draft.perchActions
        draft.socialInteractions=socialInteractionsButton.state == .on
        draft.chaseEnabled=chaseButton.state == .on
        chaseButton.isEnabled=draft.socialInteractions
        draft.travelTogetherEnabled=travelTogetherButton.state == .on
        travelTogetherButton.isEnabled=draft.socialInteractions
        draft.allopreeningEnabled=allopreeningButton.state == .on
        allopreeningButton.isEnabled=draft.socialInteractions
        draft.leafPlayEnabled=leafPlayButton.state == .on
        draft.ambientLeafPlayEnabled=ambientLeafPlayButton.state == .on
        ambientLeafPlayButton.isEnabled=draft.leafPlayEnabled
        draft.visitorMemoryEnabled=visitorMemoryButton.state == .on
        draft.activityRhythm=ActivityRhythmMode.allCases[activityRhythmPopup.indexOfSelectedItem]
        draft.fixedPerchesEnabled=fixedPerchesButton.state == .on
        draft.foodTrayEnabled=foodTrayButton.state == .on
        draft.bathEnabled=bathButton.state == .on
        draft.leafCarryEnabled=leafCarryButton.state == .on
        refreshFixedPerchControls()
        return true
    }
    @objc func save() {
        cancelFixedPerchCapture()
        cancelFoodTrayPlacement()
        cancelBathPlacement()
        cancelCarryLeafPlacement()
        window?.makeFirstResponder(nil)
        guard readInteraction() else {tabs.selectTabViewItem(at:2);message.stringValue=t("请输入 0–10 秒之间的有效等待时间。","Enter a valid hover delay between 0 and 10 seconds.");return}
        guard readDetails() else { tabs.selectTabViewItem(at:1); message.stringValue=t("请检查体型与动作数值：最长停留不能小于最短停留。","Check size and behavior ranges; maximum perch time must not be below minimum."); return }
        do { try desktop.applySettings(draft); message.stringValue=t("已保存 · 交互设置立即生效，鸟种参数用于新飞入的小鸟。","Saved · Interaction settings apply now; species settings affect new arrivals.") }
        catch { message.stringValue=t("保存失败，请重试。当前设置未改变。","Could not save. Try again; active settings are unchanged.") }
    }
    @objc func resetDefaults() { cancelFixedPerchCapture();window?.makeFirstResponder(nil); draft=BirdSettings();selectedFixedPerchSlot=1; build(); message.stringValue=t("已恢复默认（尚未保存，锁定已清除）。","Defaults restored (not saved; locks cleared).") }
    @objc func cancel() { cancelFixedPerchCapture();cancelFoodTrayPlacement();cancelBathPlacement();cancelCarryLeafPlacement();window?.close() }
    func relocalize() {
        cancelFixedPerchCapture()
        window?.makeFirstResponder(nil)
        let raw = detailFields.map { $0.map(\.stringValue) }
        let rawDelay=hoverDelayField.stringValue
        build()
        for i in raw.indices { for j in raw[i].indices { detailFields[i][j].stringValue = raw[i][j] } }
        hoverDelayField.stringValue=rawDelay
    }
}
