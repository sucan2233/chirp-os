import AppKit
import BirdingCore

/// Native evidence uses production commands and the same layers and opaque
/// pixels as DesktopView. No controller is started and no user settings load.
enum PassiveMotionVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("passive-motion-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        for kind:BehaviorKind in [.sideHop,.takeoffPreparation] {
            let prefix="passiveMotion-"+kind.rawValue
            let names=["SettledFixture", "PreviewLeasesExistingBird", "RealFramesAndLayers",
                       "VisiblePixelsHitAndHover", "FootAnchorMotion", "PauseFreezesModelAndLayer",
                       "ResumeContinuesSameRun", "CompletesAndReleases", "PreviewNeverChangesPopulation",
                       "ClickInterruptsImmediately", "ClickFlightContinuesWithoutSnapBack"]
            for name in names {checks[prefix+name]=false}

            let d=DesktopController()
            d.settingsURL=evidence.appendingPathComponent(kind.rawValue+"-settings.json")
            d.legacyURL=evidence.appendingPathComponent(kind.rawValue+"-legacy.json")
            d.automaticPopulation=false;d.scale=1.5;d.settings.hoverDelay=0
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            guard let display=d.displayRects.first,let work=d.screenRects.first,let screen=NSScreen.screens.first else {
                throw NSError(domain:"PassiveMotionVerification",code:1,
                              userInfo:[NSLocalizedDescriptionKey:"Native motion verification requires a display."])
            }
            let host=Surface(id:961,pid:42,rect:CGRect(x:work.minX+60,y:work.midY+100,width:work.width-120,height:100))
            let target=Surface(id:962,pid:42,rect:CGRect(x:work.minX+60,y:work.midY-140,width:work.width-120,height:100))
            func fixture() -> Bird {
                d.engine.handle(.cancelAmbient(.screensChanged))
                d.surfaces=[target,host]
                let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.treeSparrow),random:{0.5})
                bird.perch(on:host,spriteScale:d.spriteScale(for:bird))
                bird.perchDuration=600;bird.facingRight=false;bird.tick(2)
                d.birds=[bird];d.syncWorld(at:d.pointerPosition,buttonsDown:false)
                return bird
            }
            func advance(_ ticks:Int=1) {
                for _ in 0..<ticks {
                    // Preview needs no distant pointer. Use the same live input
                    // as rendering/hit testing so safety checks never alternate
                    // between a synthetic location and the actual mouse.
                    d.syncWorld(at:d.pointerPosition,buttonsDown:false);d.engine.advance(1.0/60)
                }
            }
            let bird=fixture(),origin=bird.position
            checks[prefix+"SettledFixture"]=bird.state == .perched && bird.stateTime>=0.45 &&
                d.engine.renderSnapshot().first?.hopOffset == 0
            let window=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
            let view=DesktopView(frame:CGRect(origin:.zero,size:window.frame.size))
            view.controller=d;view.desktopRect=display;window.contentView=view
            window.orderFrontRegardless();defer {window.orderOut(nil)}

            let started=d.engine.handle(command(for:kind))
            let event=d.engine.events.last {$0.kind==kind && $0.type == .started && $0.source == .preview}
            let run=event?.runID,id=d.engine.id(of:bird)
            checks[prefix+"PreviewLeasesExistingBird"]=started.accepted && run != nil && id != nil &&
                event?.participants == id.map{[$0]} && d.engine.behavior(of:bird)==kind &&
                d.engine.activeRunCount==1 && d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==1

            var observed=Set<String>(),rendered=true,hit=true,geometry=true,populationStable=true
            var sawAir=false,sawLanding=false,sawTranslation=false,sawRise=false,preparationPlanted=true
            var trajectory:[[String:Any]]=[]
            func record(_ label:String) throws {
                guard let state=d.engine.renderSnapshot().first, state.id==id else {
                    rendered=false;geometry=false;return
                }
                view.updateSprites()
                guard let container=sprite(in:view),let texture=container.sublayers?.first,
                      let art=d.arts[state.species],let image=art.frames[state.frameName] else {
                    rendered=false;geometry=false;return
                }
                rendered = rendered && !container.isHidden && (texture.contents as AnyObject?) === image &&
                    texture.affineTransform().a == (state.facingRight ? 1:-1)
                // Recover the foot from the actual container, including facing,
                // scale and presentation offset; frame-name evidence alone is insufficient.
                let foot=CGPoint(x:container.frame.minX+display.minX+(state.facingRight ? 29:19)*state.scale,
                                 y:container.frame.minY+display.minY+(39-state.hopOffset)*state.scale)
                geometry = geometry && Geometry.distance(foot,bird.position)<0.001 && state.position==bird.position
                if let point=visiblePoint(state,in:d) {
                    hit = hit && d.bird(at:point) === bird
                    d.updateHover(now:d.engine.time,at:point);hit = hit && d.hoveredBird === bird
                } else {hit=false}
                trajectory.append(["label":label,"time":d.engine.time,"frame":state.frameName,
                    "position":NSStringFromPoint(bird.position),"layerFoot":NSStringFromPoint(foot),
                    "layerFrame":NSStringFromRect(container.frame),"host":bird.hostID.map{Int($0)} ?? -1,
                    "behavior":d.engine.behavior(of:bird)?.rawValue ?? "none"])
                try SettingsVerification.snapshot(window,to:evidence.appendingPathComponent(prefix+"-"+label+".png"))
            }
            func samePopulation() -> Bool {
                d.engine.birds.count==1 && d.engine.birds.first === bird && d.engine.id(of:bird)==id &&
                    d.residentCount==1 && d.engine.passingCount==0 && d.engine.departingCount==0 &&
                    d.engine.pendingCount==0 && d.arrivalCount==0 && d.departureCount==0
            }
            if let state=d.engine.renderSnapshot().first {observed.insert(state.frameName)}
            try record("start")
            advance(6)
            try record("before-pause")
            d.paused=true;view.updateSprites()
            let frozen=d.engine.renderSnapshot().first,position=bird.position,revision=bird.motionRevision
            let stateTime=bird.stateTime,events=d.engine.events.count
            let frame=sprite(in:view)?.frame,contents=sprite(in:view)?.sublayers?.first?.contents as AnyObject?
            let slots=d.engine.reservedLandingCount
            advance(120);view.updateSprites()
            let afterPause=d.engine.renderSnapshot().first
            checks[prefix+"PauseFreezesModelAndLayer"]=started.accepted && d.paused && frozen != nil &&
                bird.position==position && bird.motionRevision==revision && bird.stateTime==stateTime &&
                afterPause?.id==frozen?.id && afterPause?.frameName==frozen?.frameName &&
                afterPause?.rect==frozen?.rect && afterPause?.facingRight==frozen?.facingRight &&
                d.engine.behavior(of:bird)==kind && d.engine.events.count==events &&
                d.engine.activeRunCount==1 && d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==slots &&
                frame != nil && sprite(in:view)?.frame==frame && contents != nil &&
                (sprite(in:view)?.sublayers?.first?.contents as AnyObject?) === contents
            try record("paused")
            d.paused=false;advance()
            checks[prefix+"ResumeContinuesSameRun"]=started.accepted && d.engine.behavior(of:bird)==kind &&
                d.engine.events.filter{$0.runID==run && $0.type == .started}.count==1 &&
                (bird.position != position || bird.stateTime != stateTime || d.engine.renderSnapshot().first?.frameName != frozen?.frameName)

            var screenshotMilestones=Set<String>()
            for _ in 0..<12*60 {
                let active=d.engine.behavior(of:bird)==kind
                if let state=d.engine.renderSnapshot().first {
                    if active {observed.insert(state.frameName)}
                    sawTranslation = sawTranslation || abs(bird.position.x-origin.x)>1
                    sawRise = sawRise || bird.position.y<origin.y-1
                    sawAir = sawAir || bird.state == .flying
                    sawLanding = sawLanding || bird.state == .landing
                    if kind == .takeoffPreparation && active {
                        preparationPlanted = preparationPlanted && bird.position==origin && bird.state == .perched && state.hopOffset==0
                    }
                    let milestone=active ? state.frameName:(bird.state == .flying ? "departed":"settled")
                    if screenshotMilestones.insert(milestone).inserted {try record(milestone)}
                } else {rendered=false}
                populationStable = populationStable && samePopulation()
                if let run, !terminalEvents(in:d.engine,run:run).isEmpty {
                    if kind == .sideHop || Geometry.distance(bird.position,origin)>1 {break}
                }
                advance()
            }
            let terminal=run.map{terminalEvents(in:d.engine,run:$0)} ?? []
            try record("completed")
            checks[prefix+"PreviewNeverChangesPopulation"]=started.accepted && populationStable && samePopulation()
            checks[prefix+"RealFramesAndLayers"]=started.accepted && rendered &&
                (kind == .sideHop ? Set(["stand","land0","land1","land2"]).isSubset(of:observed):Set(["takeoffCrouch","takeoffPush"]).isSubset(of:observed))
            checks[prefix+"VisiblePixelsHitAndHover"]=started.accepted && !trajectory.isEmpty && hit
            checks[prefix+"FootAnchorMotion"]=started.accepted && geometry && sawAir &&
                (kind == .sideHop ? sawTranslation && sawRise && sawLanding && bird.state == .perched &&
                    bird.hostID==host.id && abs(bird.position.y-origin.y)<0.001:
                    preparationPlanted && Geometry.distance(bird.position,origin)>1)
            checks[prefix+"CompletesAndReleases"]=started.accepted && terminal.count==1 && terminal.first?.type == .completed &&
                d.engine.behavior(of:bird)==nil && d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0

            // Interrupt a moving hop / a planted preparation. Read the opaque
            // pixel from the current production pose and use native click routing.
            let clicked=fixture(),clickID=d.engine.id(of:clicked)
            let restarted=d.engine.handle(command(for:kind))
            let clickRun=d.engine.events.last {$0.kind==kind && $0.type == .started}?.runID
            advance(6)
            let clickOrigin=clicked.position,clickRevision=clicked.motionRevision
            let clickPoint=d.engine.renderSnapshot().first.flatMap{visiblePoint($0,in:d)}
            let relocated=clickPoint.map{d.relocateBird(at:$0)} ?? false
            let clickEnds=clickRun.map{terminalEvents(in:d.engine,run:$0)} ?? []
            checks[prefix+"ClickInterruptsImmediately"]=restarted.accepted && relocated && clickRun != nil &&
                clickEnds.count==1 && clickEnds.first?.type == .cancelled &&
                d.engine.behavior(of:clicked) == .relocate && d.engine.id(of:clicked)==clickID &&
                d.engine.birds.count==1 && d.engine.birds.first === clicked && clicked.position==clickOrigin &&
                clicked.motionRevision>clickRevision && d.engine.activeRunCount==1 && d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==0
            view.updateSprites()
            try SettingsVerification.snapshot(window,to:evidence.appendingPathComponent(prefix+"-click-interruption.png"))
            let relocationRevision=clicked.motionRevision
            advance(6)
            checks[prefix+"ClickFlightContinuesWithoutSnapBack"]=relocated && d.engine.behavior(of:clicked) == .relocate &&
                clicked.motionRevision==relocationRevision && Geometry.distance(clicked.position,clickOrigin)>0.01 &&
                d.engine.reservedLandingCount==0 && (clickRun.map{terminalEvents(in:d.engine,run:$0).count} ?? 0)==1
            let data=try JSONSerialization.data(withJSONObject:["kind":kind.rawValue,"trajectory":trajectory,
                "observedFrames":observed.sorted(),"terminalEvents":terminal.map{$0.type.rawValue},
                "clickTerminalEvents":clickEnds.map{$0.type.rawValue}],options:[.prettyPrinted,.sortedKeys])
            try data.write(to:evidence.appendingPathComponent(prefix+"-evidence.json"),options:.atomic)
        }
    }

    private static func command(for kind:BehaviorKind) -> EngineCommand {
        kind == .sideHop ? .sideHop(.preview):.prepareTakeoff(.preview)
    }
    private static func terminalEvents(in engine:BehaviorEngine,run:BehaviorRunID) -> [BehaviorEvent] {
        engine.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}
    }
    private static func sprite(in view:DesktopView) -> CALayer? {
        view.layer?.sublayers?.first{$0.mask is CAShapeLayer}
    }
    private static func visiblePoint(_ state:BirdRenderState,in d:DesktopController) -> CGPoint? {
        guard let art=d.arts[state.species] else {return nil}
        for pixel in 0..<48*48 where art.contains(frame:state.frameName,x:pixel%48,y:pixel/48) {
            let x=state.facingRight ? pixel%48:47-pixel%48
            let point=CGPoint(x:state.rect.minX+(CGFloat(x)+0.5)*state.scale,
                              y:state.rect.minY+(CGFloat(pixel/48)+0.5)*state.scale)
            if !state.blockers.contains(where:{$0.contains(point)}) {return point}
        }
        return nil
    }
}
