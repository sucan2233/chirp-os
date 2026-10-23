import AppKit
import BirdingCore

func saveJSON(_ value: [String:Any], to url: URL) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted,.sortedKeys]) { try? data.write(to:url, options:.atomic) }
}

// A second process supplies real WindowServer windows; no Accessibility permission needed.
final class FixtureController {
    let folder: URL
    var host: NSWindow!
    var cover: NSWindow!
    var timer: Timer?
    var slowRemaining = 0
    var previousCommand = ""
    init(folder: URL) { self.folder = folder }
    func start() {
        let visible = NSScreen.screens.first!.visibleFrame
        let w = min(640, visible.width*0.6), h: CGFloat = 310
        host = window(frame:CGRect(x:visible.midX-w/2,y:visible.midY-h/2,width:w,height:h),title:"ChirpOS · Window habitat",color:NSColor(calibratedRed:0.13,green:0.22,blue:0.24,alpha:1))
        host.orderFrontRegardless()
        cover = window(frame:CGRect(x:host.frame.midX+14,y:host.frame.maxY-110,width:280,height:210),title:"ChirpOS · Foreground",color:NSColor(calibratedRed:0.31,green:0.24,blue:0.22,alpha:1))
        saveJSON(["host":host.windowNumber,"cover":cover.windowNumber,"pid":ProcessInfo.processInfo.processIdentifier], to:folder.appendingPathComponent("fixture.json"))
        timer = Timer.scheduledTimer(withTimeInterval:1.0/30,repeats:true) { [weak self] _ in self?.tick() }
    }
    func window(frame: CGRect,title:String,color:NSColor) -> NSWindow {
        let window = NSWindow(contentRect:frame,styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        // Fixtures measure exact WindowServer geometry. System order-in/out
        // animation can expose a scaled intermediate frame or a closing snapshot.
        window.animationBehavior = .none
        window.title = title; window.backgroundColor = color; window.isReleasedWhenClosed = false
        let label = NSTextField(wrappingLabelWithString: title.contains("Foreground") ? "FOREGROUND\n\nThis window should hide the bird.\n\nDrag me over its perch." : "BIRDING  /  红耳鹎\n\nA little life between your windows.\n\nMove this window slowly: the bird rides along.\nMove it quickly: the bird takes flight.")
        label.font = .systemFont(ofSize:18,weight:.medium); label.textColor = .white
        label.frame = CGRect(x:28,y:30,width:frame.width-56,height:frame.height-65)
        label.autoresizingMask = [.width,.height]; window.contentView?.addSubview(label)
        return window
    }
    func tick() {
        if let command = try? String(contentsOf:folder.appendingPathComponent("command"),encoding:.utf8), command != previousCommand {
            previousCommand = command
            switch command {
            case "slow": slowRemaining = 30
            case "cover":
                cover.setFrameOrigin(CGPoint(x:host.frame.midX+4,y:host.frame.maxY-100)); cover.orderFrontRegardless()
            case "uncover": cover.orderOut(nil)
            case "fast": host.setFrameOrigin(CGPoint(x:host.frame.minX+150,y:host.frame.minY))
            case "hide": host.orderOut(nil)
            case "show": host.orderFrontRegardless()
            case "quit": NSApp.terminate(nil)
            default: break
            }
            try? command.write(to:folder.appendingPathComponent("applied-command"),atomically:true,encoding:.utf8)
            recordState()
        }
        if slowRemaining > 0 {
            host.setFrameOrigin(CGPoint(x:host.frame.minX+3,y:host.frame.minY)); slowRemaining -= 1
            if slowRemaining==0 {recordState()}
        }
    }
    private func recordState() {
        saveJSON(["command":previousCommand,"host":NSStringFromRect(host.frame),"cover":NSStringFromRect(cover.frame),
            "coverVisible":cover.isVisible,"slowRemaining":slowRemaining],to:folder.appendingPathComponent("fixture-state.json"))
    }
}

final class IntegrationCheck {
    unowned let desktop: DesktopController
    let folder: URL
    private static let expectedChecks = [
        "readsOtherProcessWindow", "overlayNonactivatingAndClickThrough", "keepsOtherAppFocused",
        "slowMoveFollows", "feetStayOnWindowEdge", "frontWindowMasksPartOfBird",
        "renderedOcclusionHasNoPixelLeaks", "actualSpriteLayerHasVisiblePixelsAndNoLeaks",
        "zOrderRefreshesWhenCoverHidden", "fastMoveStartles", "playsLandingState",
        "flightLandsBackOnWindow", "hiddenHostReleasesBird"
    ]
    // Unreached checks remain failures, including when an observation times out.
    var results = Dictionary(uniqueKeysWithValues: IntegrationCheck.expectedChecks.map { ($0, false) })
    private enum ReturnPhase: String { case flying, landing, waitingForRelease }
    private var returnPhase: ReturnPhase = .flying
    private var observationTimer: Timer?
    private var simulationDeadline = 0.0
    private var wallDeadline = 0.0
    private var lastObservationTime = 0.0
    private var returnOrigin = CGPoint.zero
    private var returnRevision: UInt64 = 0
    private var landingsBeforeReturn = 0
    private var startlesBeforeReturn = 0
    private var sawFlightProgress = false
    private var landingFrames: [String] = []
    var hostID: UInt32 = 0
    var fixturePID: Int32 = 0
    var initial = CGPoint.zero
    var initialFrontPID: Int32 = 0
    var bird: Bird { desktop.birds[0] }
    init(desktop: DesktopController, folder:URL) { self.desktop = desktop; self.folder = folder }
    func after(_ seconds: Double,_ action: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline:.now()+seconds,execute:action) }
    func command(_ value:String) { try? value.write(to:folder.appendingPathComponent("command"),atomically:true,encoding:.utf8) }
    func host() -> Surface? { desktop.surfaces.first{$0.id == hostID} }
    func start() {
        guard let data = try? Data(contentsOf:folder.appendingPathComponent("fixture.json")),
              let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let id = json["host"] as? UInt32, let pid = json["pid"] as? Int32 else { finish(error:"fixture metadata missing"); return }
        hostID = id; fixturePID = pid
        initialFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        // The normal app starts empty; the fixture owns its single deterministic bird.
        desktop.automaticPopulation = false
        desktop.birds = [Bird(position:CGPoint(x:400,y:300),fraction:0.5)]
        after(0.6) {
            self.results["readsOtherProcessWindow"] = self.host()?.pid == self.fixturePID && self.fixturePID != ProcessInfo.processInfo.processIdentifier
            guard let host = self.host() else { self.finish(error:"WindowServer did not expose fixture"); return }
            self.bird.fraction = 0.5; self.bird.perch(on:host); self.bird.perchDuration = 999
            self.initial = self.bird.position
            self.results["overlayNonactivatingAndClickThrough"] = self.desktop.panels.allSatisfy{$0.ignoresMouseEvents && !$0.canBecomeKey && !$0.canBecomeMain}
            self.results["keepsOtherAppFocused"] = self.initialFrontPID == (NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
            self.command("slow")
        }
        after(2.3) {
            self.results["slowMoveFollows"] = self.bird.state == .perched && abs(self.bird.position.x-self.initial.x-90)<2 && self.bird.followedDistance>85
            self.results["feetStayOnWindowEdge"] = abs(self.bird.position.y-(self.host()?.rect.minY ?? -100))<0.1
            self.command("cover")
        }
        after(3.0) {
            let blockers = self.bird.blockers(in:self.desktop.surfaces)
            let bbox = self.desktop.bounds(of:self.bird)
            let pieces = Geometry.visiblePieces(bbox,blockers:blockers)
            let visibleArea = pieces.reduce(CGFloat(0)){$0+$1.width*$1.height}
            self.results["frontWindowMasksPartOfBird"] = visibleArea>0 && visibleArea<bbox.width*bbox.height && blockers.contains{$0.intersects(bbox)}
            self.saveMaskedBird()
            self.saveLayerSnapshot()
            self.observeUncoverAndStartle()
        }
    }
    private func observeUncoverAndStartle() {
        // Pixel inspection may take longer than a wall-clock callback interval.
        // Do not overwrite "uncover" with "fast" before the fixture consumed it.
        command("uncover")
        var waitingForStartle=false
        wallDeadline=ProcessInfo.processInfo.systemUptime+6
        let timer=Timer(timeInterval:1.0/60,repeats:true) { [weak self] _ in
            guard let self else {return}
            guard ProcessInfo.processInfo.systemUptime<self.wallDeadline else {
                self.finish(error:waitingForStartle ? "fixture fast movement was not observed":"fixture uncover was not observed");return
            }
            let applied=try? String(contentsOf:self.folder.appendingPathComponent("applied-command"),encoding:.utf8)
            if !waitingForStartle {
                guard applied=="uncover",self.bird.state == .perched,
                      !self.bird.blockers(in:self.desktop.surfaces).contains(where:{$0.intersects(self.desktop.bounds(of:self.bird))}) else {return}
                self.results["zOrderRefreshesWhenCoverHidden"]=true
                waitingForStartle=true;self.wallDeadline=ProcessInfo.processInfo.systemUptime+6
                self.command("fast")
            } else if applied=="fast",self.bird.state == .flying,self.bird.startledCount==1,self.bird.hostID==nil {
                self.results["fastMoveStartles"]=true
                self.observationTimer?.invalidate();self.observationTimer=nil
                self.beginReturnObservation()
            }
        }
        RunLoop.main.add(timer,forMode:.common);observationTimer=timer
    }
    private func beginReturnObservation() {
        guard let host = host() else { finish(error:"fixture host missing before return flight"); return }
        returnOrigin = bird.position
        landingsBeforeReturn = bird.landedCount
        startlesBeforeReturn = bird.startledCount
        bird.fly(to:CGPoint(x:Geometry.perchX(0.5,rect:host.rect),y:host.rect.minY),host:host,duration:0.8,arc:40)
        returnRevision = bird.motionRevision
        guard bird.flightDuration.isFinite && bird.flightDuration > 0 else {
            finish(error:"invalid return flight duration"); return
        }
        // fly's duration argument is not the path planner's actual flight duration.
        // Observe only normal desktop ticks; never advance the simulation here.
        simulationDeadline = desktop.engine.time + bird.flightDuration + 2
        wallDeadline = ProcessInfo.processInfo.systemUptime + min(30,max(5,bird.flightDuration*3+3))
        lastObservationTime = desktop.engine.time
        let timer = Timer(timeInterval:1.0/120,repeats:true) { [weak self] _ in self?.observeReturn() }
        RunLoop.main.add(timer,forMode:.common)
        observationTimer = timer
    }
    private func observeReturn() {
        let now = desktop.engine.time
        guard now < simulationDeadline && ProcessInfo.processInfo.systemUptime < wallDeadline else {
            finish(error:"timed out during \(returnPhase.rawValue): state=\(bird.state.rawValue), frame=\(bird.frameName), observed landing frames=\(landingFrames)")
            return
        }
        // Polling the same simulation frame twice is not evidence of progress.
        guard now > lastObservationTime else { return }
        lastObservationTime = now
        if returnPhase == .waitingForRelease {
            if host() == nil && bird.state == .flying && bird.hostID == nil && bird.depthID == nil &&
                bird.startledCount == startlesBeforeReturn+1 && bird.startledCount == 2 &&
                bird.landedCount == landingsBeforeReturn+1 && bird.motionRevision == (returnRevision &+ 1) {
                results["hiddenHostReleasesBird"] = true
                finish(error:nil)
            }
            return
        }
        guard let host = host(), bird.hostID == hostID, bird.motionRevision == returnRevision,
              bird.startledCount == startlesBeforeReturn else {
            finish(error:"return flight lost its fixture host or was replaced"); return
        }
        switch bird.state {
        case .flying:
            guard returnPhase == .flying && bird.depthID == nil && bird.landedCount == landingsBeforeReturn else {
                finish(error:"unexpected flight state during return landing"); return
            }
            if bird.stateTime > 0 && Geometry.distance(bird.position,returnOrigin) > 0.1 {
                sawFlightProgress = true
            }
        case .landing:
            guard sawFlightProgress && isOnReturnPerch(host) && bird.landedCount == landingsBeforeReturn+1 else {
                finish(error:"landing did not follow observed flight onto the fixture edge"); return
            }
            returnPhase = .landing
            let frame = bird.frameName
            if landingFrames.last != frame {
                let expected = ["land0", "land1", "land2"]
                guard landingFrames.count < expected.count, frame == expected[landingFrames.count],
                      desktop.arts[bird.profile.id]?.frames[frame] != nil else {
                    finish(error:"missing or out-of-order landing pose: \(frame), observed=\(landingFrames)"); return
                }
                landingFrames.append(frame)
            }
            results["playsLandingState"] = landingFrames == ["land0", "land1", "land2"]
        case .perched:
            guard returnPhase == .landing, results["playsLandingState"] == true,
                  isOnReturnPerch(host), bird.landedCount == landingsBeforeReturn+1 else {
                finish(error:"return perch reached without the complete landing sequence or correct foot position"); return
            }
            results["flightLandsBackOnWindow"] = true
            returnPhase = .waitingForRelease
            simulationDeadline = now + 2
            wallDeadline = ProcessInfo.processInfo.systemUptime + 5
            command("hide")
        }
    }
    private func isOnReturnPerch(_ host: Surface) -> Bool {
        bird.hostID == hostID && bird.depthID == hostID && bird.edge == .top &&
            abs(bird.position.x-Geometry.perchX(0.5,rect:host.rect)) < 0.1 &&
            abs(bird.position.y-host.rect.minY) < 0.1
    }
    func saveMaskedBird() {
        let bbox = desktop.bounds(of:bird)
        let w = Int(bbox.width), h = Int(bbox.height)
        let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x:0,y:CGFloat(h)); ctx.scaleBy(x:1,y:-1)
        ctx.translateBy(x:-bbox.minX,y:-bbox.minY)
        let blockers = bird.blockers(in:desktop.surfaces)
        ctx.clip(to:Geometry.visiblePieces(bbox,blockers:blockers))
        desktop.arts[bird.profile.id]!.draw(name:bird.frameName,at:CGPoint(x:bird.position.x,y:bird.position.y+bird.hopOffset*desktop.spriteScale(for:bird)),scale:desktop.spriteScale(for:bird),right:bird.facingRight,context:ctx)
        let image = ctx.makeImage()!
        let rep = NSBitmapImageRep(cgImage:image)
        try? rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("occlusion.png"))
        var opaque = 0, leaked = 0
        for y in 0..<h { for x in 0..<w {
            // NSBitmapImageRep uses top-down image coordinates after the context flip.
            let alpha = rep.colorAt(x:x,y:y)?.alphaComponent ?? 0
            if alpha > 0 {
                opaque += 1
                let point = CGPoint(x:bbox.minX+CGFloat(x)+0.5,y:bbox.minY+CGFloat(y)+0.5)
                if blockers.contains(where:{$0.contains(point)}) { leaked += 1 }
            }
        } }
        results["renderedOcclusionHasNoPixelLeaks"] = opaque > 0 && leaked == 0
    }
    func saveLayerSnapshot() {
        guard let view = desktop.views.first(where:{$0.desktopRect.contains(bird.position)}),let root = view.layer else { return }
        view.updateSprites()
        let w = Int(view.bounds.width), h = Int(view.bounds.height)
        let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CALayer.render uses Quartz bottom-up coordinates, unlike our desktop view.
        ctx.translateBy(x:0,y:CGFloat(h)); ctx.scaleBy(x:1,y:-1)
        root.render(in:ctx)
        saveJSON(["view":NSStringFromRect(view.bounds),"root":NSStringFromRect(root.bounds),"layers":(root.sublayers ?? []).map{["frame":NSStringFromRect($0.frame),"mask":NSStringFromRect($0.mask?.bounds ?? .zero),"hidden":$0.isHidden] as [String:Any]}],to:folder.appendingPathComponent("layer-geometry.json"))
        if let full = ctx.makeImage() { try? NSBitmapImageRep(cgImage:full).representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("full-layer.png")) }
        let bbox = desktop.bounds(of:bird)
        let crop = bbox.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY).integral
        guard let image = ctx.makeImage()?.cropping(to:crop) else { return }
        let rep = NSBitmapImageRep(cgImage:image)
        try? rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("actual-layer.png"))
        var opaque = 0, leaked = 0
        let blockers = bird.blockers(in:desktop.surfaces)
        for y in 0..<image.height { for x in 0..<image.width {
            if (rep.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0 {
                opaque += 1
                let p = CGPoint(x:crop.minX+view.desktopRect.minX+CGFloat(x)+0.5,y:crop.minY+view.desktopRect.minY+CGFloat(y)+0.5)
                if blockers.contains(where:{$0.contains(p)}) { leaked += 1 }
            }
        } }
        results["actualSpriteLayerHasVisiblePixelsAndNoLeaks"] = opaque>0 && leaked == 0
    }
    func finish(error:String?) {
        observationTimer?.invalidate(); observationTimer = nil
        desktop.writeDiagnostics(to:folder.appendingPathComponent("diagnostics.json").path)
        saveJSON(["hostID":hostID,"fixturePID":fixturePID,"initial":NSStringFromPoint(initial),
            "bounds":NSStringFromRect(desktop.bounds(of:bird)),
            "surfaces":desktop.surfaces.map{["id":$0.id,"pid":$0.pid,"rect":NSStringFromRect($0.rect),"layer":$0.layer,"ground":$0.isGround] as [String:Any]}],
            to:folder.appendingPathComponent("window-evidence.json"))
        let passed = error == nil && Set(results.keys) == Set(Self.expectedChecks) && results.values.allSatisfy{$0}
        saveJSON(["passed":passed,"checks":results,"error":error ?? "","os":ProcessInfo.processInfo.operatingSystemVersionString],to:folder.appendingPathComponent("report.json"))
        command("quit")
        print("Desktop integration: \(passed ? "PASS" : "FAIL") — \(results.count) checks")
        fflush(stdout)
        exit(passed ? 0 : 1)
    }
}
