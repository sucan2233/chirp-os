import AppKit
import BirdingCore

/// Native acceptance evidence only: no controller startup, timers, settings save,
/// mouse warping, or synthetic pointer samples. The caller owns execution.
enum EdgePeekVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("edge-peek-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        let d=DesktopController()
        d.settingsURL=evidence.appendingPathComponent("unused-settings.json")
        d.legacyURL=evidence.appendingPathComponent("unused-legacy.json")
        d.visitorMemoryURL=evidence.appendingPathComponent("unused-visitors.json")
        d.visitorMemoryPersistenceEnabled=false
        d.automaticPopulation=false;d.scale=1.5
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        checks["edgePeekEnabledByDefault"]=d.settings.edgePeekEnabled
        var settings=d.settings
        settings.edgePeekEnabled=true;settings.perchActions=true;settings.hoverDelay=0
        settings.sideHopEnabled=false;settings.takeoffPreparationEnabled=false
        d.settings=settings
        guard let screen=NSScreen.screens.first,let display=d.displayRects.first,let work=d.screenRects.first else {
            throw NSError(domain:"EdgePeekVerification",code:1,
                          userInfo:[NSLocalizedDescriptionKey:"Native edge-peek verification requires a display."])
        }

        // A real, visible, non-ground window supplies the authoritative top edge.
        // In particular, neither a clipped visible piece nor its center is used.
        let hostWindow=NSWindow(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
        hostWindow.isReleasedWhenClosed=false;hostWindow.hasShadow=false
        hostWindow.ignoresMouseEvents=true;hostWindow.backgroundColor=NSColor(calibratedWhite:0.93,alpha:1)
        let hostView=NSView(frame:.zero);hostView.wantsLayer=true
        hostView.layer?.backgroundColor=hostWindow.backgroundColor.cgColor
        let caption=NSTextField(labelWithString:"Edge peek · native window top edge")
        caption.textColor=NSColor(calibratedWhite:0.25,alpha:1);hostView.addSubview(caption)
        hostWindow.contentView=hostView
        let window=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.hasShadow=false
        window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
        window.level = .floating
        let view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size))
        view.controller=d;view.desktopRect=display;window.contentView=view
        defer {
            d.engine.handle(.cancelAmbient(.shutdown))
            window.orderOut(nil);hostWindow.orderOut(nil)
        }

        var host=Surface(id:0,rect:.zero)
        var origin=CGPoint.zero,endpoint=CGPoint.zero,sourceFraction:CGFloat=0
        var trajectory:[[String:Any]]=[]
        var artifactNames:[String]=[]
        var caseName=""
        let dt=1.0/60
        func clearResources() -> Bool {
            d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 &&
                d.engine.reservedLandingCount==0 && d.engine.scenePropCount==0
        }
        func advance(_ count:Int=1) {
            for _ in 0..<count {
                // updateSprites / hit testing call syncWorld themselves. Every
                // path sees this same live pointer and real button state.
                d.syncWorld();d.engine.advance(dt)
            }
        }
        func corridor(_ a:CGPoint,_ b:CGPoint,scale:CGFloat) -> CGRect {
            let area=Geometry.landingFootprint(at:a,scale:scale)
                .union(Geometry.landingFootprint(at:b,scale:scale))
            return area.union(area.offsetBy(dx:0,dy:-12*scale))
        }
        func fixture(_ species:SpeciesID,right:Bool,fraction:CGFloat?=nil,ground:Bool=false,distance:CGFloat=90) -> Bird {
            d.paused=false;d.engine.handle(.cancelAmbient(.screensChanged))
            d.engine.autonomousRouting=false;d.hoveredBird=nil
            let bird=Bird(position:.zero,fraction:0,profile:d.catalog.profile(species),random:{0.5})
            let scale=d.spriteScale(for:bird),width=work.width-120
            // Choose a vertical placement as well as the farther endpoint. This
            // allows both directions without injecting a near/far fake mouse.
            let top=work.minY+max(80,51*scale+12),bottom=work.maxY-125
            let pointer=d.pointerPosition
            let candidates=[top,max(top,bottom)].map { y -> CGRect in
                CGRect(x:work.minX+60,y:y,width:width,height:110)
            }
            let rect=candidates.max { a,b in
                func distance(_ rect:CGRect) -> CGFloat {
                    let x=Geometry.perchX(right ? 1:0,rect:rect)
                    let center=CGPoint(x:x+(right ? -45:45)*scale,y:rect.minY-15*scale)
                    return Geometry.distance(pointer,center)
                }
                return distance(a)<distance(b)
            }!
            hostWindow.setFrame(Geometry.quartz(rect,primaryHeight:d.primaryHeight),display:true)
            hostView.frame=CGRect(origin:.zero,size:hostWindow.frame.size)
            hostView.layer?.frame=hostView.bounds
            caption.frame=CGRect(x:16,y:hostView.bounds.height-36,width:max(0,width-32),height:22)
            caption.stringValue="\(species.rawValue) · \(right ? "right":"left") · \(Int(distance)) × sprite scale"
            hostWindow.orderFrontRegardless();window.orderFrontRegardless()
            host=Surface(id:UInt32(hostWindow.windowNumber),pid:ProcessInfo.processInfo.processIdentifier,
                rect:Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight),isGround:ground)
            let left=Geometry.perchX(0,rect:host.rect),rightX=Geometry.perchX(1,rect:host.rect)
            sourceFraction=fraction ?? (right ? 1-distance*scale/(rightX-left):distance*scale/(rightX-left))
            bird.fraction=sourceFraction;bird.facingRight=right
            bird.perch(on:host,spriteScale:scale);bird.perchDuration=600
            // Settle before the sparrow's ordinary idle peck/hop starts at 1 s.
            bird.tick(0.6)
            origin=bird.position
            endpoint=Geometry.foot(on:host,fraction:right ? 1:0,edge:.top,scale:scale)
            d.surfaces=[host];d.birds=[bird];d.syncWorld()
            return bird
        }
        func record(_ bird:Bird,_ label:String,screenshot:Bool=false) throws {
            view.updateSprites()
            guard let state=d.engine.renderSnapshot().first,let container=sprite(in:view) else {return}
            let foot=layerFoot(container,state:state,display:display)
            trajectory.append(["case":caseName,"label":label,"time":d.engine.time,
                "birdID":state.id.rawValue,"species":state.species.rawValue,"state":bird.state.rawValue,
                "frame":state.frameName,"fraction":bird.fraction,"position":point(bird.position),
                "layerFoot":point(foot),"layerFrame":NSStringFromRect(container.frame),
                "hopOffset":state.hopOffset,"facingRight":state.facingRight,
                "pointer":point(d.pointerPosition),"buttonsDown":d.engine.world.buttonsDown,
                "motionRevision":bird.motionRevision,"hostID":bird.hostID.map{Int($0)} ?? -1,
                "hostRect":NSStringFromRect(host.rect),"hostWindowVisible":hostWindow.isVisible,
                "sourceFraction":sourceFraction,"source":point(origin),"endpoint":point(endpoint),
                "behavior":d.engine.behavior(of:bird)?.rawValue ?? "none",
                "activeRuns":d.engine.activeRunCount,"leases":d.engine.leasedBirdCount,
                "reservations":d.engine.reservedLandingCount,"population":d.engine.birds.count])
            if screenshot {
                let name=caseName+"-"+label+".png"
                let scale=d.spriteScale(for:bird)
                let crop=Geometry.landingFootprint(at:origin,scale:scale)
                    .union(Geometry.landingFootprint(at:endpoint,scale:scale))
                    .union(state.rect).insetBy(dx:-28,dy:-40)
                try snapshot(view,hostView:hostWindow.isVisible ? hostView:nil,hostRect:host.rect,display:display,
                    crop:crop.intersection(display),to:evidence.appendingPathComponent(name))
                artifactNames.append(name)
            }
        }
        func samePopulation(_ bird:Bird,_ id:BirdID?) -> Bool {
            d.engine.birds.count==1 && d.engine.birds.first === bird && id != nil && d.engine.id(of:bird)==id &&
                d.residentCount==1 && d.engine.passingCount==0 && d.engine.departingCount==0 &&
                d.engine.pendingCount==0 && d.arrivalCount==0 && d.departureCount==0
        }
        func pauseEvidence(_ bird:Bird,_ label:String) throws -> Bool {
            d.paused=true;view.updateSprites()
            let before=d.engine.renderSnapshot().first,position=bird.position,fraction=bird.fraction
            let age=bird.stateTime,revision=bird.motionRevision,state=bird.state
            let events=d.engine.events.count,slots=d.engine.reservedLandingCount
            let frame=sprite(in:view)?.frame,texture=sprite(in:view)?.sublayers?.first
            let contents=texture?.contents as AnyObject?,transform=texture?.affineTransform()
            advance(60);view.updateSprites()
            let after=d.engine.renderSnapshot().first
            let frozen=before != nil && bird.position==position && bird.fraction==fraction &&
                bird.stateTime==age && bird.state==state && bird.motionRevision==revision &&
                before?.frameName==after?.frameName && before?.rect==after?.rect &&
                before?.facingRight==after?.facingRight && d.engine.behavior(of:bird) == .edgePeek &&
                d.engine.events.count==events && d.engine.activeRunCount==1 && d.engine.leasedBirdCount==1 &&
                slots==2 && d.engine.reservedLandingCount==slots && frame != nil && sprite(in:view)?.frame==frame &&
                transform==sprite(in:view)?.sublayers?.first?.affineTransform() && contents != nil &&
                (sprite(in:view)?.sublayers?.first?.contents as AnyObject?) === contents
            try record(bird,label,screenshot:true)
            d.paused=false
            return frozen
        }

        let species:[SpeciesID]=[.treeSparrow,.chineseBlackbird,.hoopoe,.whimbrel]
        var coverage:[[String:Any]]=[]
        for speciesID in species {
            // The farther side is always attempted first; both sides retain
            // their own checks and cannot silently be skipped as ineligible.
            let rightFirst=d.pointerPosition.x<work.midX
            for right in [rightFirst,!rightFirst] {
                caseName=speciesID.rawValue+"-"+(right ? "right":"left")
                let prefix="edgePeek-"+caseName
                for name in ["RealWindowEndpointFixture","PreviewLeasesExistingBirdAndTwoSlots",
                             "OnlyTicksMoveFeet","RealLayersAndAnchors","DistinctDownwardFrames",
                             "ObservationSequenceAndDuration","OutwardHopAndExactReturn","LivePointerClearsWholePath",
                             "OpaquePixelsHitAndHover","TransparentPixelsPassThrough","CompletesOnceAndCleansUp",
                             "NeverAddsBirds","PauseFreezesFlight","PauseFreezesObservation","ResumeKeepsRun"] {
                    checks[prefix+name]=false
                }
                let bird=fixture(speciesID,right:right),scale=d.spriteScale(for:bird),id=d.engine.id(of:bird)
                let start=origin,goal=endpoint,fraction=sourceFraction
                let path=corridor(start,goal,scale:scale),safe=path.insetBy(dx:-48*scale,dy:-48*scale)
                checks[prefix+"RealWindowEndpointFixture"]=bird.state == .perched && bird.stateTime>=0.45 &&
                    bird.edge == .top && !host.isGround && host.id==UInt32(hostWindow.windowNumber) &&
                    host.rect==Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight) &&
                    abs(abs(goal.x-start.x)/scale-90)<0.001 && abs(start.y-host.rect.minY)<0.001 &&
                    (0...1).contains(fraction) && abs(fraction-0.5)>0.01 && display.contains(path)
                try record(bird,"source",screenshot:true)
                let started=d.engine.handle(.edgePeek(.preview))
                let event=d.engine.events.last{$0.kind == .edgePeek && $0.type == .started && $0.source == .preview}
                let run=event?.runID
                checks[prefix+"PreviewLeasesExistingBirdAndTwoSlots"]=started.accepted && run != nil &&
                    event?.participants==id.map{[$0]} && samePopulation(bird,id) &&
                    d.engine.behavior(of:bird) == .edgePeek && d.engine.activeRunCount==1 &&
                    d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==2 && d.engine.scenePropCount==0
                let revision=bird.motionRevision,age=bird.stateTime
                for _ in 0..<6 {d.syncWorld();view.updateSprites();_ = d.engine.renderSnapshot()}
                checks[prefix+"OnlyTicksMoveFeet"]=started.accepted && bird.position==start &&
                    bird.stateTime==age && bird.motionRevision==revision

                var layers=true,anchors=true,hits=true,transparent=true,population=true,pointerClear=true
                var movedOut=false,roseOut=false,roseBack=false,returning=false
                var flightPaused=false,observationPaused=false,resumed=true
                var observed:[String]=[],observationTicks=0,previous=start
                var smooth=true,allSlots=true
                for tick in 0..<7*60 {
                    advance();view.updateSprites()
                    guard let state=d.engine.renderSnapshot().first,let container=sprite(in:view),
                          let texture=container.sublayers?.first,let art=d.arts[state.species],
                          let image=art.frames[state.frameName] else {layers=false;break}
                    let active=d.engine.behavior(of:bird) == .edgePeek
                    layers = layers && state.id==id && !container.isHidden &&
                        (texture.contents as AnyObject?) === image && texture.affineTransform().a == (state.facingRight ? 1:-1)
                    anchors = anchors && Geometry.distance(layerFoot(container,state:state,display:display),bird.position)<0.001 &&
                        state.position==bird.position
                    smooth = smooth && Geometry.distance(previous,bird.position)<12*scale
                    previous=bird.position
                    population = population && samePopulation(bird,id)
                    pointerClear = pointerClear && !safe.contains(d.pointerPosition) && !d.engine.world.buttonsDown
                    if active {allSlots = allSlots && d.engine.reservedLandingCount==2}
                    if let point=pixelPoint(state,in:d,opaque:true) {
                        hits = hits && d.bird(at:point) === bird
                        d.updateHover(now:d.engine.time,at:point)
                        hits = hits && d.hoveredBird === bird
                        d.hoveredBird=nil
                    } else {hits=false}
                    if let point=pixelPoint(state,in:d,opaque:false) {
                        let eventCount=d.engine.events.count
                        transparent = transparent && d.bird(at:point)==nil && !d.relocateBird(at:point) &&
                            d.engine.events.count==eventCount && window.ignoresMouseEvents && !window.canBecomeKey
                    } else {transparent=false}
                    movedOut = movedOut || abs(bird.position.x-start.x)>10*scale
                    let observing=active && bird.state == .perched && Geometry.distance(bird.position,goal)<0.001 &&
                        ["idle0","idle1","idle2"].contains(state.frameName)
                    var milestone:String?
                    if observing {
                        observationTicks+=1
                        if observed.last != state.frameName {
                            observed.append(state.frameName);milestone="observe-\(observed.count)-"+state.frameName
                        }
                    }
                    if active && bird.state == .flying {
                        if observationTicks==0 {roseOut = roseOut || bird.position.y<start.y-scale}
                        else {
                            roseBack = roseBack || bird.position.y<start.y-scale
                            if !returning {returning=true;milestone="return-hop"}
                        }
                    }
                    if tick==6 {milestone="approach-hop"}
                    try record(bird,milestone ?? "tick",screenshot:milestone != nil)
                    if started.accepted && !flightPaused && tick==6 {
                        checks[prefix+"PauseFreezesFlight"]=try pauseEvidence(bird,"paused-flight")
                        flightPaused=true
                        let frozen=bird.position
                        // Resume is checked by the next actual integration tick.
                        advance();try record(bird,"resumed-flight")
                        resumed = resumed && bird.position != frozen && d.engine.behavior(of:bird) == .edgePeek
                        previous=bird.position
                    }
                    if started.accepted && observing && state.frameName=="idle2" && !observationPaused {
                        checks[prefix+"PauseFreezesObservation"]=try pauseEvidence(bird,"paused-idle2")
                        observationPaused=true
                    }
                    if let run,!terminalEvents(in:d.engine,run:run).isEmpty {break}
                }
                let ends=run.map{terminalEvents(in:d.engine,run:$0)} ?? []
                try record(bird,"returned",screenshot:true)
                let returned=Geometry.distance(bird.position,start)<0.001 && abs(bird.fraction-fraction)<0.000001 &&
                    bird.hostID==host.id && bird.state == .perched
                checks[prefix+"RealLayersAndAnchors"]=started.accepted && layers && anchors
                let images=["idle0","idle1","idle2"].compactMap{d.arts[speciesID]?.frames[$0]}
                let hashes=images.compactMap{bitmapHash($0)}
                checks[prefix+"DistinctDownwardFrames"]=started.accepted && hashes.count==3 && Set(hashes).count==3 &&
                    Set(["idle0","idle1","idle2"]).isSubset(of:Set(observed))
                checks[prefix+"ObservationSequenceAndDuration"]=started.accepted &&
                    observed==["idle0","idle1","idle2","idle1","idle0"] && abs(Double(observationTicks)*dt-1.6)<=2*dt
                checks[prefix+"OutwardHopAndExactReturn"]=started.accepted && movedOut && roseOut && roseBack && returning && smooth && returned
                checks[prefix+"LivePointerClearsWholePath"]=started.accepted && pointerClear
                checks[prefix+"OpaquePixelsHitAndHover"]=started.accepted && hits && observationTicks>0
                checks[prefix+"TransparentPixelsPassThrough"]=started.accepted && transparent && observationTicks>0
                checks[prefix+"NeverAddsBirds"]=started.accepted && population && samePopulation(bird,id)
                checks[prefix+"ResumeKeepsRun"]=started.accepted && resumed && flightPaused && observationPaused &&
                    d.engine.events.filter{$0.runID==run && $0.type == .started}.count==1 && ends.first?.type == .completed
                advance(6)
                checks[prefix+"CompletesOnceAndCleansUp"]=started.accepted && ends.count==1 && ends.first?.type == .completed &&
                    allSlots && clearResources() && d.engine.behavior(of:bird)==nil &&
                    (run.map{terminalEvents(in:d.engine,run:$0).count} ?? 0)==1
                coverage.append(["case":caseName,"accepted":started.accepted,"sourceFraction":fraction,
                    "origin":point(start),"endpoint":point(goal),"hostRect":NSStringFromRect(host.rect),
                    "scale":scale,"pointerSafetyRect":NSStringFromRect(safe),"frames":observed,
                    "observationSeconds":Double(observationTicks)*dt,"frameBitmapHashes":hashes,
                    "terminals":ends.map{["type":$0.type.rawValue,"reason":$0.reason?.rawValue ?? ""]}])
            }
        }

        // Native click routing must preempt both an airborne hop and the pose.
        for observing in [false,true] {
            caseName=observing ? "click-observing":"click-airborne"
            let bird=fixture(.treeSparrow,right:d.pointerPosition.x<work.midX),id=d.engine.id(of:bird)
            let started=d.engine.handle(.edgePeek(.preview)).accepted
            let run=d.engine.events.last{$0.kind == .edgePeek && $0.type == .started}?.runID
            var reached=false
            for _ in 0..<180 {
                advance()
                if observing {
                    if d.engine.renderSnapshot().first?.frameName=="idle2" && bird.state == .perched {reached=true;break}
                } else if Geometry.distance(bird.position,origin)>8 && bird.state == .flying {reached=true;break}
            }
            try record(bird,"before-click",screenshot:true)
            let position=bird.position,revision=bird.motionRevision
            let pixel=d.engine.renderSnapshot().first.flatMap{pixelPoint($0,in:d,opaque:true)}
            let clicked=pixel.map{d.relocateBird(at:$0)} ?? false
            let relocationRun=d.engine.events.last{$0.kind == .relocate && $0.type == .started}?.runID
            let ends=run.map{terminalEvents(in:d.engine,run:$0)} ?? []
            checks["edgePeek-"+caseName+"PreemptsFromCurrentFoot"]=started && reached && clicked &&
                bird.position==position && bird.motionRevision>revision && d.engine.behavior(of:bird) == .relocate &&
                samePopulation(bird,id) && ends.count==1 && ends.first?.type == .cancelled &&
                d.engine.reservedLandingCount==0 && d.engine.scenePropCount==0
            try record(bird,"clicked",screenshot:true)
            let relocationRevision=bird.motionRevision
            advance(6);try record(bird,"relocation-moving",screenshot:true)
            checks["edgePeek-"+caseName+"NoSnapBackOrStalePose"]=clicked && bird.motionRevision==relocationRevision &&
                Geometry.distance(bird.position,position)>0.01 && d.engine.behavior(of:bird) == .relocate &&
                d.engine.renderSnapshot().first?.frameName==bird.frameName &&
                d.engine.reservedLandingCount==0 && (run.map{terminalEvents(in:d.engine,run:$0).count} ?? 0)==1
            for _ in 0..<46*60 {
                if d.engine.behavior(of:bird) != .relocate {break}
                advance()
            }
            let relocationEnds=relocationRun.map{terminalEvents(in:d.engine,run:$0)} ?? []
            checks["edgePeek-"+caseName+"ReplacementFinishesAndCleansUp"]=clicked && clearResources() &&
                samePopulation(bird,id) && relocationEnds.count==1 && relocationEnds.first?.type == .completed
            try record(bird,"relocation-finished",screenshot:true)
        }

        caseName="host-invalidated"
        let lost=fixture(.treeSparrow,right:d.pointerPosition.x<work.midX),lostID=d.engine.id(of:lost)
        let accepted=d.engine.handle(.edgePeek(.preview)).accepted
        let lostRun=d.engine.events.last{$0.kind == .edgePeek && $0.type == .started}?.runID
        advance(6);try record(lost,"before-host-removal",screenshot:true)
        let airborne=lost.state == .flying,interrupted=lost.position
        hostWindow.orderOut(nil);d.surfaces=[];d.syncWorld()
        let lostEnds=lostRun.map{terminalEvents(in:d.engine,run:$0)} ?? []
        checks["edgePeekHostInvalidationReleasesWithoutTeleport"]=accepted && airborne && lost.position==interrupted &&
            lost.needsDestination && clearResources() && lostEnds.count==1 && lostEnds.first?.reason == .targetInvalid &&
            [.failed,.cancelled].contains(lostEnds[0].type)
        try record(lost,"host-removed",screenshot:true)
        // Return the window as a routing option; the cancelled run must never
        // reclaim its old reservations or reset the airborne origin.
        hostWindow.orderFrontRegardless();d.surfaces=[host];d.engine.autonomousRouting=true;advance()
        let recoveryStartsHere=lost.position==interrupted,revision=lost.motionRevision
        advance(6);try record(lost,"recovery-moving",screenshot:true)
        checks["edgePeekHostRecoveryStartsAtActualFoot"]=accepted && recoveryStartsHere &&
            Geometry.distance(lost.position,interrupted)>0.01 && lost.motionRevision==revision &&
            samePopulation(lost,lostID) && clearResources() &&
            (lostRun.map{terminalEvents(in:d.engine,run:$0).count} ?? 0)==1

        // Eligibility and settings use production commands, with the same live
        // pointer. These rejected requests must allocate no leases or slots.
        for gate in ["edgePeekEnabled","perchActions","ground","center","tooNear","tooFar","unsupported"] {
            caseName="reject-"+gate
            let bird=fixture(gate=="unsupported" ? .redWhiskeredBulbul:.treeSparrow,
                right:d.pointerPosition.x<work.midX,fraction:gate=="center" ? 0.5:nil,ground:gate=="ground",
                distance:gate=="tooNear" ? 70:(gate=="tooFar" ? 120:90))
            var value=settings
            if gate=="edgePeekEnabled" {value.edgePeekEnabled=false}
            if gate=="perchActions" {value.perchActions=false}
            d.settings=value
            let position=bird.position,id=d.engine.id(of:bird)
            let result=d.engine.handle(.edgePeek(.preview))
            let reason:BehaviorReason=["edgePeekEnabled","perchActions"].contains(gate) ? .disabled:
                (gate=="unsupported" ? .noSpecies:.noSpace)
            checks["edgePeekRejects-"+gate] = result == .rejected(reason) && clearResources() &&
                bird.position==position && samePopulation(bird,id)
            d.settings=settings
        }
        checks["edgePeekDoesNotStartTimersOrWriteUserFiles"]=d.timer==nil && d.globalMouseMonitor==nil &&
            d.localMouseMonitor==nil && d.visitorMemoryPersistence==nil && !d.visitorMemoryPersistenceEnabled &&
            [d.settingsURL,d.legacyURL,d.visitorMemoryURL].allSatisfy {
                $0.deletingLastPathComponent()==evidence && !FileManager.default.fileExists(atPath:$0.path)
            }
        let data=try JSONSerialization.data(withJSONObject:["coordinateSystem":"Quartz desktop points; y increases downward",
            "input":"Live NSEvent pointer and buttons for simulation, rendering and hit tests; no synthetic pointer",
            "screenshots":artifactNames,"coverage":coverage,"trajectory":trajectory,
            "checks":checks.filter{$0.key.hasPrefix("edgePeek")},
            "events":d.engine.events.map { event -> [String:Any] in
                ["sequence":event.sequence,"time":event.time,"runID":event.runID?.rawValue ?? 0,
                 "kind":event.kind?.rawValue ?? "none","source":event.source.rawValue,
                 "type":event.type.rawValue,"reason":event.reason?.rawValue ?? "",
                 "participants":event.participants.map(\.rawValue)]
            }],options:[.prettyPrinted,.sortedKeys])
        try data.write(to:evidence.appendingPathComponent("edge-peek-trajectory.json"),options:.atomic)
    }

    private static func terminalEvents(in engine:BehaviorEngine,run:BehaviorRunID) -> [BehaviorEvent] {
        engine.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}
    }
    private static func sprite(in view:DesktopView) -> CALayer? {
        view.layer?.sublayers?.first{$0.mask is CAShapeLayer}
    }
    private static func layerFoot(_ layer:CALayer,state:BirdRenderState,display:CGRect) -> CGPoint {
        CGPoint(x:layer.frame.minX+display.minX+(state.facingRight ? 29:19)*state.scale,
                y:layer.frame.minY+display.minY+(39-state.hopOffset)*state.scale)
    }
    private static func point(_ value:CGPoint) -> [CGFloat] {[value.x,value.y]}
    private static func pixelPoint(_ state:BirdRenderState,in d:DesktopController,opaque:Bool) -> CGPoint? {
        guard let art=d.arts[state.species] else {return nil}
        for pixel in 0..<48*48 where art.contains(frame:state.frameName,x:pixel%48,y:pixel/48)==opaque {
            let x=state.facingRight ? pixel%48:47-pixel%48
            let point=CGPoint(x:state.rect.minX+(CGFloat(x)+0.5)*state.scale,
                              y:state.rect.minY+(CGFloat(pixel/48)+0.5)*state.scale)
            if !state.blockers.contains(where:{$0.contains(point)}) {return point}
        }
        return nil
    }
    private static func bitmapHash(_ image:CGImage) -> String? {
        guard let data=image.dataProvider?.data,let bytes=CFDataGetBytePtr(data) else {return nil}
        var hash:UInt64=14695981039346656037
        for index in 0..<CFDataGetLength(data) {hash=(hash ^ UInt64(bytes[index])) &* 1099511628211}
        return String(hash,radix:16)
    }
    /// Crop actual native layer contents around the traversal. Compositing the
    /// real fixture window under DesktopView makes the top edge visible without
    /// Screen Recording permission or drawing a substitute bird/window sprite.
    private static func snapshot(_ view:DesktopView,hostView:NSView?,hostRect:CGRect,display:CGRect,
                                 crop:CGRect,to url:URL) throws {
        let crop=crop.integral
        guard !crop.isEmpty,let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(crop.width),
            pixelsHigh:Int(crop.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,
            colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else {
            throw NSError(domain:"EdgePeekVerification",code:2)
        }
        view.layoutSubtreeIfNeeded();hostView?.layoutSubtreeIfNeeded()
        view.displayIfNeeded();hostView?.displayIfNeeded()
        let ctx=graphics.cgContext
        ctx.setFillColor(NSColor(calibratedWhite:0.22,alpha:1).cgColor);ctx.fill(CGRect(origin:.zero,size:crop.size))
        ctx.translateBy(x:-crop.minX,y:crop.maxY);ctx.scaleBy(x:1,y:-1)
        if let hostView {
            ctx.saveGState();ctx.translateBy(x:hostRect.minX,y:hostRect.maxY);ctx.scaleBy(x:1,y:-1)
            hostView.layer?.render(in:ctx);ctx.restoreGState()
        }
        ctx.translateBy(x:display.minX,y:display.minY);view.layer?.render(in:ctx)
        guard let png=bitmap.representation(using:.png,properties:[:]) else {
            throw NSError(domain:"EdgePeekVerification",code:3)
        }
        try png.write(to:url,options:.atomic)
    }
}
