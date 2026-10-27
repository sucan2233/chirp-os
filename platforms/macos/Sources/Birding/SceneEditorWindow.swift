import AppKit
import BirdingCore

private let scenePasteboard=NSPasteboard.PasteboardType("dev.chirpos.scene-item")
final class SceneEditingPanel:NSPanel {
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {false}
}
extension SceneItemKind {
    var sceneTitle:String {switch self {case .perch:return "栖木";case .foodTray:return "食盘";case .bath:return "浴盆";case .nest:return "巢台与材料盘";case .leaf:return "可携带叶片"}}
    var sceneImage:CGImage? {
        switch self {case .perch:return FixedPerchArt.shared?.image;case .foodTray:return FoodTrayArt.shared?.image
        case .bath:return BathArt.image();case .nest:return NestArt.image();case .leaf:return CarryArt.leafImage()}
    }
}
private final class SceneLibraryItem:NSView,NSDraggingSource {
    let kind:SceneItemKind
    init(kind:SceneItemKind,frame:NSRect) {self.kind=kind;super.init(frame:frame);setAccessibilityLabel("拖动放置"+kind.sceneTitle)}
    required init?(coder:NSCoder) {fatalError()}
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if let image=kind.sceneImage {NSImage(cgImage:image,size:.zero).draw(in:NSRect(x:8,y:25,width:92,height:32),from:.zero,operation:.sourceOver,fraction:1)}
        (kind.sceneTitle as NSString).draw(in:NSRect(x:2,y:2,width:118,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.labelColor])
    }
    override func mouseDown(with event:NSEvent) {
        let item=NSPasteboardItem();item.setString(kind.rawValue,forType:scenePasteboard)
        let drag=NSDraggingItem(pasteboardWriter:item)
        let image=kind.sceneImage.map{NSImage(cgImage:$0,size:NSSize(width:100,height:40))} ?? NSImage(size:NSSize(width:100,height:40))
        drag.setDraggingFrame(NSRect(x:0,y:20,width:100,height:40),contents:image)
        beginDraggingSession(with:[drag],event:event,source:self)
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {.copy}
}
final class SceneEditorWindow:NSWindowController,NSWindowDelegate {
    unowned let desktop:DesktopController
    var draft:SceneDraft
    var selected:UUID?
    var overlays:[SceneEditingPanel]=[]
    var canvases:[SceneEditorCanvas]=[]
    let message=NSTextField(wrappingLabelWithString:"")
    let inventory=NSTextField(wrappingLabelWithString:"")
    let instancePicker=NSPopUpButton(frame:.zero,pullsDown:false)
    private var applyButton:NSButton!
    private var undoButton:NSButton!
    private var redoButton:NSButton!
    private var previewButton:NSButton!
    private var closing=false
    init(desktop:DesktopController) {
        self.desktop=desktop;draft=desktop.engine.beginSceneEditing()
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:650,height:330),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.title="布置桌面";panel.isReleasedWhenClosed=false;panel.level=NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+3)
        super.init(window:panel);panel.delegate=self
        let root=SettingsContentView(frame:NSRect(x:0,y:0,width:650,height:330));panel.contentView=root
        let title=NSTextField(labelWithString:"把物件拖到桌面 · 最多 3 根栖木 + 3 个其他物件")
        title.font = .systemFont(ofSize:15,weight:.medium);title.frame=NSRect(x:20,y:16,width:610,height:25);root.addSubview(title)
        for (i,kind) in SceneItemKind.allCases.enumerated() {root.addSubview(SceneLibraryItem(kind:kind,frame:NSRect(x:20+i*124,y:48,width:120,height:68)))}
        instancePicker.frame=NSRect(x:20,y:118,width:610,height:28);instancePicker.target=self;instancePicker.action=#selector(selectInstance);root.addSubview(instancePicker)
        inventory.frame=NSRect(x:20,y:150,width:610,height:40);root.addSubview(inventory)
        message.frame=NSRect(x:20,y:192,width:610,height:38);message.font = .systemFont(ofSize:12);root.addSubview(message)
        func button(_ text:String,_ action:Selector,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat)->NSButton {
            let b=NSButton(title:text,target:self,action:action);b.bezelStyle = .rounded;b.frame=NSRect(x:x,y:y,width:width,height:30);root.addSubview(b);return b
        }
        undoButton=button("撤销",#selector(undoEdit),20,234,65);redoButton=button("重做",#selector(redoEdit),90,234,65)
        _=button("收回所选",#selector(removeSelected),165,234,95)
        _=button("补充所选资源",#selector(replenish),270,234,120)
        previewButton=button("体验一次",#selector(preview),400,234,100)
        _=button("取消",#selector(cancel),460,282,75)
        applyButton=button("应用布局",#selector(apply),540,282,95)
        _=button("继续动画",#selector(resume),20,282,100)
        _=button("移到当前屏幕",#selector(moveToCurrentDisplay),130,282,130)
        NotificationCenter.default.addObserver(self,selector:#selector(deactivated),name:NSApplication.didResignActiveNotification,object:nil)
        createOverlays();panel.center();refresh()
    }
    required init?(coder:NSCoder) {fatalError()}
    deinit {NotificationCenter.default.removeObserver(self)}
    private func createOverlays() {
        for screen in NSScreen.screens {
            let panel=SceneEditingPanel(contentRect:screen.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false;panel.hidesOnDeactivate=false
            panel.isReleasedWhenClosed=false;panel.level=NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+1)
            panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
            let canvas=SceneEditorCanvas(frame:NSRect(origin:.zero,size:screen.frame.size))
            canvas.editor=self;canvas.desktopRect=Geometry.quartz(screen.frame,primaryHeight:desktop.primaryHeight)
            panel.contentView=canvas;panel.orderFrontRegardless();overlays.append(panel);canvases.append(canvas)
        }
    }
    func refresh() {
        let engine=desktop.engine
        if engine.sceneEditPhase == .committed {finish();return}
        let busy=engine.sceneEditPhase == .applying
        instancePicker.removeAllItems();instancePicker.addItem(withTitle:"选择已布置物件（包括未连接屏幕上的物件）")
        for (index,item) in draft.layout.instances.enumerated() {
            let parked=item.point(in:engine.world)==nil || engine.sceneNeedsPlacement.contains(item.id)
            instancePicker.addItem(withTitle:"\(index+1). \(item.kind.sceneTitle)"+(parked ? " · 待定位":""))
        }
        instancePicker.selectItem(at:draft.layout.instances.firstIndex(where:{$0.id==selected}).map{$0+1} ?? 0)
        instancePicker.isEnabled = !busy
        overlays.forEach{$0.ignoresMouseEvents=busy}
        applyButton.isEnabled = !busy;undoButton.isEnabled=draft.canUndo && !busy;redoButton.isEnabled=draft.canRedo && !busy
        previewButton.isEnabled = !busy && draft.layout==engine.sceneArchive.layout && !engine.paused
        if busy {message.stringValue=engine.paused ? "应用已暂停，等待继续动画。":"正在等待使用中物件的小鸟安全离开…"}
        else if let error=engine.sceneError {message.stringValue=error}
        else {message.stringValue="拖动移动，方向键微调（Shift：10 像素），Delete 收回，Esc 取消。巢台与叶片会吸附到附近的窗口顶部或地面。"}
        if let item=draft.layout.instances.first(where:{$0.id==selected}) {
            let r=engine.sceneArchive.resources[item.id] ?? SceneResource(kind:item.kind)
            let state=item.kind == .nest ? "材料：\(r.materials.filter{$0 == .available}.count) 可用 · \(r.materials.filter{$0 == .delivered}.count) 已送达 · \(r.materials.filter{$0 == .arranged}.count) 已整理":
                item.kind == .leaf ? (r.leafConsumed ? "已消耗，可主动补充":"等待携带"):
                item.kind == .perch ? "等待小鸟停栖":"剩余 \(r.remainingUses) 次"
            inventory.stringValue=item.kind.sceneTitle+" · "+state+(item.point(in:engine.world)==nil ? " · 显示器未连接，保留位置":engine.sceneNeedsPlacement.contains(item.id) ? " · 原窗口待定位，请重新拖放":"")
        } else {inventory.stringValue="已布置 \(draft.layout.instances.count) / 6 · 等待访问时资源不会过期"}
        canvases.forEach{$0.needsDisplay=true}
    }
    func placement(kind:SceneItemKind,point:CGPoint,id:UUID?=nil)->SceneInstance? {
        var point=point
        var support:SceneSupport = .display
        if kind == .nest || kind == .leaf {
            let hosts=desktop.engine.world.surfaces.filter{!$0.isHabitat && !$0.isFixedPerch && $0.canHostBirds && point.x>$0.rect.minX+70 && point.x<$0.rect.maxX-70}
            if let host=hosts.min(by:{abs($0.rect.minY-point.y)<abs($1.rect.minY-point.y)}),abs(host.rect.minY-point.y)<90 {
                support=host.isGround ? .ground:.window
                point.y=host.rect.minY
                if host.isGround {point.y-=9*desktop.scale*CGFloat(desktop.settings.catalog.profile(kind == .nest ? .spottedDove:.treeSparrow).relativeScale)}
            }
        }
        let current=id.flatMap{value in draft.layout.instances.first{$0.id==value}}
        let used=Set(draft.layout.instances.filter{$0.kind == .perch && $0.id != id}.map{$0.anchor.slot})
        let slot=kind == .perch ? (current?.anchor.slot ?? (1...3).first{!used.contains($0)} ?? 0):1
        guard let anchor=FixedPerchAnchor.capture(slot:slot,point:point,displayIDs:desktop.engine.world.displayIDs,displays:desktop.engine.world.displays) else {return nil}
        return SceneInstance(id:current?.id ?? UUID(),kind:kind,anchor:anchor,revision:(current?.revision ?? 0)+1,support:support)
    }
    @discardableResult func place(_ item:SceneInstance)->Bool {
        guard desktop.engine.sceneEditPhase != .applying else {return false}
        var candidate=draft.layout
        candidate.instances.removeAll{$0.id==item.id};candidate.instances.append(item)
        if let error=desktop.engine.scenePlacementError(candidate) {message.stringValue=error;return false}
        draft.edit{$0=candidate};selected=item.id;refresh();return true
    }
    func moveSelected(dx:CGFloat,dy:CGFloat) {
        guard let current=draft.layout.instances.first(where:{$0.id==selected}),let point=current.point(in:desktop.engine.world),
              let changed=placement(kind:current.kind,point:CGPoint(x:point.x+dx,y:point.y+dy),id:current.id) else {return}
        _=place(changed)
    }
    @objc func undoEdit() {guard desktop.engine.sceneEditPhase != .applying else {return};draft.undo();refresh()}
    @objc func redoEdit() {guard desktop.engine.sceneEditPhase != .applying else {return};draft.redo();refresh()}
    @objc func removeSelected() {
        guard let id=selected,desktop.engine.sceneEditPhase != .applying else {return}
        draft.edit{$0.instances.removeAll{$0.id==id}};selected=nil;refresh()
    }
    @objc func replenish() {
        guard draft.layout==desktop.engine.sceneArchive.layout,let id=selected else {message.stringValue="请先应用位置修改，再补充资源。";return}
        if !desktop.engine.replenishSceneInstance(id) {message.stringValue=desktop.engine.sceneError ?? "物件正在使用中，暂不能补充。"} else {refresh()}
    }
    @objc func selectInstance() {
        let index=instancePicker.indexOfSelectedItem-1
        selected=draft.layout.instances.indices.contains(index) ? draft.layout.instances[index].id:nil;refresh()
    }
    @objc func moveToCurrentDisplay() {
        guard let item=draft.layout.instances.first(where:{$0.id==selected}) else {message.stringValue="请先选择物件。";return}
        let world=desktop.engine.world
        guard let display=world.displays.first(where:{$0.contains(world.pointer)}) ?? world.displays.first else {return}
        var point=CGPoint(x:display.midX,y:display.minY+display.height*0.6)
        if item.kind == .nest || item.kind == .leaf,
           let host=world.surfaces.first(where:{!$0.isHabitat && !$0.isFixedPerch && $0.canHostBirds && display.intersects($0.rect) && $0.rect.width>200}) {
            point=CGPoint(x:host.rect.midX,y:host.rect.minY)
        }
        if let moved=placement(kind:item.kind,point:point,id:item.id) {_=place(moved)}
    }
    @objc func resume() {desktop.paused=false;refresh()}
    @objc func apply() {_=desktop.engine.applySceneLayout(draft.layout,baseRevision:draft.baseRevision);refresh()}
    @objc func cancel() {desktop.engine.cancelSceneEditing();finish()}
    @objc func deactivated() {if window?.isVisible == true {cancel()}}
    func windowShouldClose(_ sender:NSWindow)->Bool {cancel();return true}
    func finish() {
        guard !closing else {return};closing=true
        overlays.forEach{$0.ignoresMouseEvents=true;$0.orderOut(nil);$0.close()};overlays=[];canvases=[]
        window?.orderOut(nil);desktop.engine.cancelSceneEditing();desktop.makeMenu()
    }
    @objc func preview() {
        guard draft.layout==desktop.engine.sceneArchive.layout,!desktop.paused,
              let item=draft.layout.instances.first(where:{$0.id==selected}) else {message.stringValue="请先应用布局并选中一个物件。";return}
        finish()
        if case .rejected(let reason)=desktop.engine.previewSceneInstance(item.id) {
            let alert=NSAlert();alert.messageText="暂时无法体验";alert.informativeText="需要合适的小鸟、可用资源和安全空间（\(reason.rawValue)）。";alert.runModal()
        }
    }
}
final class SceneEditorCanvas:NSView {
    weak var editor:SceneEditorWindow?
    var desktopRect:CGRect = .zero
    private var dragging:UUID?
    private var ghost:SceneInstance?
    private var validGhost=false
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    override init(frame:NSRect) {super.init(frame:frame);registerForDraggedTypes([scenePasteboard])}
    required init?(coder:NSCoder) {fatalError()}
    func rect(_ item:SceneInstance)->CGRect? {
        guard let editor,let p=item.point(in:editor.desktop.engine.world) else {return nil}
        let scale=editor.desktop.scale
        let size:CGSize=item.kind == .leaf ? CGSize(width:32,height:32):item.kind == .nest ? CGSize(width:180,height:48):CGSize(width:128,height:40)
        return CGRect(x:p.x-size.width*scale/2-desktopRect.minX,y:p.y-14*scale-desktopRect.minY,width:size.width*scale,height:size.height*scale)
    }
    override func draw(_ dirtyRect:NSRect) {
        guard let editor else {return}
        NSColor.black.withAlphaComponent(0.04).setFill();bounds.fill()
        let instances=editor.draft.layout.instances.filter{$0.id != ghost?.id}+(ghost.map{[$0]} ?? [])
        for item in instances {
            guard let r=rect(item),r.intersects(bounds) else {continue}
            let color: NSColor = ghost?.id==item.id ? (validGhost ? .systemGreen:.systemRed):.controlAccentColor
            color.withAlphaComponent(0.1).setFill();NSBezierPath(roundedRect:r.insetBy(dx:-8,dy:-8),xRadius:8,yRadius:8).fill()
            if let image=item.kind.sceneImage {
                NSGraphicsContext.current?.imageInterpolation = .none
                NSImage(cgImage:image,size:.zero).draw(in:r,from:.zero,operation:.sourceOver,fraction:0.85,respectFlipped:true,hints:nil)
            }
            if item.kind == .nest {
                NSImage(cgImage:NestArt.trayImage(),size:.zero).draw(in:NSRect(x:r.maxX-35,y:r.minY+20,width:32,height:16),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            }
            if editor.selected==item.id || ghost?.id==item.id {color.setStroke();let path=NSBezierPath(roundedRect:r.insetBy(dx:-8,dy:-8),xRadius:8,yRadius:8);path.lineWidth=2;path.stroke()}
            (item.kind.sceneTitle as NSString).draw(at:NSPoint(x:r.minX,y:r.maxY+10),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.labelColor,.backgroundColor:NSColor.windowBackgroundColor])
        }
    }
    func worldPoint(_ local:NSPoint)->CGPoint {CGPoint(x:local.x+desktopRect.minX,y:local.y+desktopRect.minY)}
    override func mouseDown(with event:NSEvent) {
        guard let editor,editor.desktop.engine.sceneEditPhase != .applying else {return}
        window?.makeFirstResponder(self)
        let p=convert(event.locationInWindow,from:nil)
        dragging=editor.draft.layout.instances.last(where:{rect($0)?.insetBy(dx:-12,dy:-12).contains(p) == true})?.id
        editor.selected=dragging;editor.refresh()
    }
    override func mouseDragged(with event:NSEvent) {
        guard let editor,let id=dragging,let item=editor.draft.layout.instances.first(where:{$0.id==id}) else {return}
        ghost=editor.placement(kind:item.kind,point:worldPoint(convert(event.locationInWindow,from:nil)),id:id)
        validateGhost()
    }
    func validateGhost() {
        guard let editor,let ghost else {validGhost=false;return}
        var candidate=editor.draft.layout;candidate.instances.removeAll{$0.id==ghost.id};candidate.instances.append(ghost)
        let error=editor.desktop.engine.scenePlacementError(candidate);validGhost=error==nil
        editor.message.stringValue=error ?? "松开鼠标放置；应用后生效。";needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {if let ghost,validGhost {_=editor?.place(ghost)};ghost=nil;dragging=nil;needsDisplay=true}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {draggingUpdated(sender)}
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation {
        guard let editor,let raw=sender.draggingPasteboard.string(forType:scenePasteboard),let kind=SceneItemKind(rawValue:raw) else {return []}
        ghost=editor.placement(kind:kind,point:worldPoint(convert(sender.draggingLocation,from:nil)));validateGhost();return validGhost ? .copy:[]
    }
    override func draggingExited(_ sender:NSDraggingInfo?) {ghost=nil;needsDisplay=true}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        defer {ghost=nil;needsDisplay=true}
        guard let ghost,validGhost else {return false};return editor?.place(ghost) ?? false
    }
    override func keyDown(with event:NSEvent) {
        let delta:CGFloat=event.modifierFlags.contains(.shift) ? 10:1
        if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers=="z" {
            if event.modifierFlags.contains(.shift) {editor?.redoEdit()} else {editor?.undoEdit()};return
        }
        switch event.keyCode {case 123:editor?.moveSelected(dx:-delta,dy:0);case 124:editor?.moveSelected(dx:delta,dy:0)
        case 125:editor?.moveSelected(dx:0,dy:delta);case 126:editor?.moveSelected(dx:0,dy:-delta)
        case 51,117:editor?.removeSelected();case 53:editor?.cancel();case 36:editor?.apply();default:super.keyDown(with:event)}
    }
}
