import AppKit
import BirdingCore

/// Called by ExpandedVerification. Drives the production engine without starting
/// DesktopController, loading/saving preferences, installing timers, or injecting
/// pointer input. PNG evidence composites actual native layers, not the desktop.
enum ChaseVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("chase-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        let h=try Harness(folder:evidence)
        defer {h.close()}
        for species:SpeciesID in [.treeSparrow,.barnSwallow,.redWhiskeredBulbul] {
            try h.complete(species,into:&checks)
        }
        for index in 0..<2 {try h.click(index,into:&checks)}
        for cause in ["host-removed","space-changed","chase-disabled","social-disabled","missing-frames"] {
            try h.interrupt(cause,into:&checks)
        }
        for gate in ["chase-disabled","social-disabled","missing-frames","no-space"] {
            try h.reject(gate,into:&checks)
        }
        checks["chaseNoTimersOrUserFileWrites"]=h.d.timer==nil && h.d.globalMouseMonitor==nil &&
            h.d.localMouseMonitor==nil && h.d.visitorMemoryPersistence==nil &&
            !h.d.visitorMemoryPersistenceEnabled &&
            [h.d.settingsURL,h.d.legacyURL,h.d.visitorMemoryURL].allSatisfy {
                $0.deletingLastPathComponent()==evidence && !FileManager.default.fileExists(atPath:$0.path)
            }
        checks["chaseFinalResourcesReleased"]=h.clearResources
        h.close()
        checks["chaseFixtureWindowsHiddenAfterRun"] = !h.overlay.isVisible && !h.hostWindow.isVisible
        try h.writeReport(checks)
    }

    private final class Harness {
        let d:DesktopController
        let folder:URL,display:CGRect,work:CGRect
        let hostWindow:NSWindow,hostView:NSView,overlay:OverlayPanel,view:DesktopView
        let dt=1.0/60
        var host=Surface(id:0,rect:.zero)
        var birds:[Bird]=[],ids:[BirdID]=[],origins:[CGPoint]=[],fractions:[CGFloat]=[]
        var corridor=CGRect.zero,caseName="",run:BehaviorRunID?
        var trajectory:[[String:Any]]=[],cases:[[String:Any]]=[],artifacts:[[String:Any]]=[]
        var eventLog:[UInt64:BehaviorEvent]=[:]
        var previous:[CGPoint]=[],flightPaths:[[CGPoint]]=[[],[]]
        var populationOK=true,pointerOK=true,layersOK=true,anchorsOK=true,hitsOK=true,transparentOK=true
        var continuous=true,contained=true,slotsOK=true,separated=true
        var flightFrames:[Set<String>]=[[],[]],firstAir:[Double?]=[nil,nil]
        var minimumSeparation=CGFloat.greatestFiniteMagnitude,pairedAirTicks=0

        init(folder:URL) throws {
            // Build local objects before publishing the fully initialized harness.
            let d=DesktopController()
            guard let screen=NSScreen.screens.first,let display=d.displayRects.first,let work=d.screenRects.first else {
                throw NSError(domain:"ChaseVerification",code:1,
                    userInfo:[NSLocalizedDescriptionKey:"Native chase verification requires a display."])
            }
            d.settingsURL=folder.appendingPathComponent("unused-settings.json")
            d.legacyURL=folder.appendingPathComponent("unused-legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("unused-visitors.json")
            d.visitorMemoryPersistenceEnabled=false
            d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            let hostWindow=NSWindow(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
            hostWindow.isReleasedWhenClosed=false;hostWindow.hasShadow=false;hostWindow.ignoresMouseEvents=true
            hostWindow.backgroundColor=NSColor(calibratedWhite:0.92,alpha:1)
            let hostView=NSView(frame:.zero);hostView.wantsLayer=true
            hostView.layer?.backgroundColor=hostWindow.backgroundColor.cgColor
            hostWindow.contentView=hostView
            let overlay=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            overlay.isReleasedWhenClosed=false;overlay.hasShadow=false;overlay.ignoresMouseEvents=true
            overlay.isOpaque=false;overlay.backgroundColor = .clear;overlay.level = .floating
            let view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size))
            view.controller=d;view.desktopRect=display;overlay.contentView=view
            self.d=d;self.folder=folder;self.display=display;self.work=work
            self.hostWindow=hostWindow;self.hostView=hostView;self.overlay=overlay;self.view=view
        }

        func close() {
            d.engine.handle(.cancelAmbient(.shutdown))
            overlay.orderOut(nil);hostWindow.orderOut(nil)
        }
        var clearResources:Bool {
            d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 &&
                d.engine.reservedLandingCount==0 && d.engine.scenePropCount==0 && !d.engine.ambientBusy
        }
        var samePopulation:Bool {
            birds.count==2 && ids.count==2 && d.engine.birds.count==2 &&
                birds.enumerated().allSatisfy {index,bird in
                    d.engine.birds[index] === bird && d.engine.id(of:bird)==ids[index]
                } && d.residentCount==2 && d.engine.passingCount==0 && d.engine.departingCount==0 &&
                d.engine.pendingCount==0 && d.arrivalCount==0 && d.departureCount==0
        }
        func events() {
            for event in d.engine.events {eventLog[event.sequence]=event}
        }
        func terminals(_ id:BehaviorRunID?) -> [BehaviorEvent] {
            events()
            guard let id else {return []}
            return eventLog.values.filter{$0.runID==id && [.completed,.failed,.cancelled].contains($0.type)}
                .sorted{$0.sequence<$1.sequence}
        }
        func advance(_ count:Int=1) {
            for _ in 0..<count {d.syncWorld();d.engine.advance(dt);events()}
        }

        /// Window placement is selected using the real pointer and a conservative
        /// envelope enclosing the entire planned loop, including sprite extent.
        /// If none fits, the fixture fails explicitly; the mouse is never moved.
        func fixture(_ species:SpeciesID,name:String) {
            d.paused=false;d.engine.handle(.cancelAmbient(.screensChanged));events()
            var settings=d.settings
            settings.chaseEnabled=true;settings.socialInteractions=true;settings.hoverDelay=0
            settings.sideHopEnabled=false;settings.takeoffPreparationEnabled=false;settings.edgePeekEnabled=false
            d.settings=settings
            d.engine.autonomousRouting=false;d.hoverTracker=HoverTracker<BirdID>();d.hoveredBird=nil
            d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
            caseName=name;run=nil
            birds=(0..<2).map {_ in Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(species),random:{0.5})}
            let relative=birds[0].profile.relativeScale
            // At most the default scale, reduced on a small display so that a
            // real pointer in its center can still clear an entire corner loop.
            d.scale=max(0.5,min(1,min((work.width/2-128)/(620*relative),(work.height-150)/(480*relative))))
            let scale=d.spriteScale(for:birds[0])
            // Chase.swift tries radii 180/220/270, ry=0.55*rx, with the
            // bottom of the shared ring 110*scale above these two feet.
            // Include radius 270, complete sprite extents, and sweep padding.
            let width=560*scale,height:CGFloat=100
            let candidates=[work.minX+16+30*scale,work.maxX-width-16-30*scale].flatMap { x in
                [work.minY+16+460*scale,work.maxY-height-20].map { y in
                    CGRect(x:x,y:y,width:width,height:height)
                }
            }
            func envelope(_ rect:CGRect) -> CGRect {
                CGRect(x:rect.midX-310*scale,y:rect.minY-460*scale,width:620*scale,height:480*scale)
            }
            func distance(_ rect:CGRect) -> CGFloat {
                let p=d.pointerPosition,r=envelope(rect)
                return hypot(max(0,max(r.minX-p.x,p.x-r.maxX)),max(0,max(r.minY-p.y,p.y-r.maxY)))
            }
            let feasible=candidates.filter{display.contains(envelope($0)) && work.contains($0)}
            let rect=(feasible.isEmpty ? candidates:feasible).max{distance($0)<distance($1)} ?? .zero
            hostWindow.setFrame(Geometry.quartz(rect,primaryHeight:d.primaryHeight),display:true)
            hostView.frame=CGRect(origin:.zero,size:hostWindow.frame.size);hostView.layer?.frame=hostView.bounds
            hostWindow.orderFrontRegardless();overlay.orderFrontRegardless()
            host=Surface(id:UInt32(hostWindow.windowNumber),pid:ProcessInfo.processInfo.processIdentifier,
                rect:Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight))
            corridor=envelope(host.rect)
            let lo=Geometry.perchX(0,rect:host.rect),hi=Geometry.perchX(1,rect:host.rect)
            for (index,bird) in birds.enumerated() {
                bird.fraction=(host.rect.midX+(index==0 ? -50:50)*scale-lo)/max(1,hi-lo)
                bird.facingRight=true;bird.perch(on:host,spriteScale:scale);bird.perchDuration=600;bird.tick(0.6)
            }
            d.surfaces=[host];d.birds=birds;d.syncWorld()
            ids=birds.compactMap{d.engine.id(of:$0)};origins=birds.map(\.position);fractions=birds.map(\.fraction)
            previous=origins;flightPaths=[[],[]];flightFrames=[[],[]];firstAir=[nil,nil]
            populationOK=true;pointerOK=true;layersOK=true;anchorsOK=true;hitsOK=true;transparentOK=true
            continuous=true;contained=true;slotsOK=true;separated=true;pairedAirTicks=0
            minimumSeparation = .greatestFiniteMagnitude
        }

        var usableFixture:Bool {
            samePopulation && hostWindow.isVisible && host.id==UInt32(hostWindow.windowNumber) && !host.isGround &&
                host.rect==Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight) && display.contains(corridor) &&
                !corridor.insetBy(dx:-100,dy:-100).contains(d.pointerPosition) && !d.engine.world.buttonsDown &&
                birds.allSatisfy{$0.state == .perched && $0.stateTime>=0.45 && $0.edge == .top &&
                    $0.hostID==host.id && (0...1).contains($0.fraction)} &&
                birds[0].profile.id==birds[1].profile.id
        }
        @discardableResult func start() -> Bool {
            d.syncWorld()
            let sequence=d.engine.events.last?.sequence ?? 0
            let result=d.engine.handle(.chase(.preview));events()
            run=d.engine.events.last{$0.sequence>sequence && $0.kind == .chase && $0.type == .started}?.runID
            return result.accepted && run != nil
        }
        var returned:Bool {
            birds.enumerated().allSatisfy {index,bird in
                bird.state == .perched && bird.hostID==host.id && bird.edge == .top &&
                    Geometry.distance(bird.position,origins[index])<0.001 && abs(bird.fraction-fractions[index])<0.000001
            }
        }

        /// Every integration tick records both models and both actual sprite
        /// layers. Hit/hover probes call production pixel routing directly; they
        /// do not feed a fabricated pointer into BehaviorWorld or NSEvent.
        func record(_ label:String,crop:Bool=false,probe:Bool=true) throws {
            view.updateSprites();events()
            let states=d.engine.renderSnapshot(),layers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            populationOK = populationOK && samePopulation
            let protected=corridor.insetBy(dx:-100,dy:-100)
            pointerOK = pointerOK && !protected.contains(d.pointerPosition) &&
                !protected.contains(d.engine.world.pointer) && !d.engine.world.buttonsDown
            layersOK = layersOK && states.count==2 && layers.count==2
            if states.count==2 {
                let overlap=states[0].rect.intersection(states[1].rect)
                separated = separated && (overlap.isNull || overlap.isEmpty)
            }
            var members:[[String:Any]]=[]
            for (index,bird) in birds.enumerated() {
                guard index<ids.count,let state=states.first(where:{$0.id==ids[index]}),
                      let layerIndex=states.firstIndex(where:{$0.id==state.id}),layerIndex<layers.count,
                      let texture=layers[layerIndex].sublayers?.first,let art=d.arts[state.species],
                      let image=art.frames[state.frameName] else {layersOK=false;anchorsOK=false;continue}
                let layer=layers[layerIndex],foot=Self.foot(layer,state:state,display:display)
                layersOK = layersOK && !layer.isHidden && (texture.contents as AnyObject?) === image &&
                    texture.affineTransform().a == (state.facingRight ? 1:-1)
                anchorsOK = anchorsOK && Geometry.distance(foot,bird.position)<0.001 && state.position==bird.position
                contained = contained && display.contains(state.rect) && corridor.contains(state.rect)
                continuous = continuous && Geometry.distance(previous[index],bird.position)<max(20,18*state.scale)
                previous[index]=bird.position
                if d.engine.behavior(of:bird) == .chase {
                    slotsOK = slotsOK && d.engine.activeRunCount==1 && d.engine.leasedBirdCount==2 &&
                        d.engine.reservedLandingCount==2 && d.engine.scenePropCount==0 && d.engine.ambientBusy
                    if bird.state == .flying {
                        if firstAir[index]==nil {firstAir[index]=d.engine.time}
                        flightFrames[index].insert(state.frameName);flightPaths[index].append(bird.position)
                    }
                }
                if probe {
                    if let pixel=pixelPoint(state,opaque:true,states:states) {
                        hitsOK = hitsOK && d.bird(at:pixel) === bird && state.hoverable
                        d.updateHover(now:d.engine.time,at:pixel)
                        hitsOK = hitsOK && d.hoveredBird === bird
                        view.updateSprites()
                        hitsOK = hitsOK && (view.layer?.sublayers?.contains{($0 as? CATextLayer)?.isHidden == false} ?? false)
                        d.hoverTracker=HoverTracker<BirdID>();d.hoveredBird=nil
                    } else {hitsOK=false}
                    if let pixel=pixelPoint(state,opaque:false,states:states) {
                        let eventCount=d.engine.events.last?.sequence
                        transparentOK = transparentOK && d.bird(at:pixel)==nil && !d.relocateBird(at:pixel) &&
                            d.engine.events.last?.sequence==eventCount && overlay.ignoresMouseEvents && !overlay.canBecomeKey
                    } else {transparentOK=false}
                }
                members.append(["id":state.id.rawValue,"species":state.species.rawValue,"state":bird.state.rawValue,
                    "frame":state.frameName,"position":Self.point(bird.position),"fraction":bird.fraction,
                    "layerFoot":Self.point(foot),"layerFrame":NSStringFromRect(layer.frame),
                    "hopOffset":state.hopOffset,"facingRight":state.facingRight,"hoverable":state.hoverable,
                    "motionRevision":bird.motionRevision,"stateTime":bird.stateTime,
                    "hostID":bird.hostID.map{Int($0)} ?? -1,"behavior":d.engine.behavior(of:bird)?.rawValue ?? "none"])
            }
            if birds.count==2,birds.allSatisfy({$0.state == .flying && d.engine.behavior(of:$0) == .chase}) {
                pairedAirTicks+=1;minimumSeparation=min(minimumSeparation,Geometry.distance(birds[0].position,birds[1].position))
            }
            trajectory.append(["case":caseName,"label":label,"time":d.engine.time,"runID":run?.rawValue ?? 0,
                "pointer":Self.point(d.pointerPosition),"worldPointer":Self.point(d.engine.world.pointer),
                "buttonsDown":d.engine.world.buttonsDown,"paused":d.paused,
                "activeRuns":d.engine.activeRunCount,"leases":d.engine.leasedBirdCount,
                "reservations":d.engine.reservedLandingCount,"population":d.engine.birds.count,
                "hostWindowVisible":hostWindow.isVisible,"members":members])
            if crop {
                d.hoveredBird=nil;view.updateSprites()
                let name=caseName+"-"+label+"-layer-composite.png"
                let area=states.reduce(corridor){$0.union($1.rect)}
                    .insetBy(dx:-16,dy:-32).intersection(display).integral
                try Self.snapshot(view,hostView:hostWindow.isVisible ? hostView:nil,host:host.rect,display:display,
                    crop:area,to:folder.appendingPathComponent(name))
                artifacts.append(["file":name,"case":caseName,"label":label,"time":d.engine.time,
                    "kind":"native-layer-crop-composite; not a desktop screenshot","crop":NSStringFromRect(area)])
            }
        }

        func pauseEvidence() throws -> Bool {
            d.paused=true;view.updateSprites()
            let states=d.engine.renderSnapshot(),positions=birds.map(\.position),ages=birds.map(\.stateTime)
            let revisions=birds.map(\.motionRevision),fractions=birds.map(\.fraction),kinds=birds.map(\.state)
            let layers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            let frames=layers.map(\.frame),contents=layers.map{$0.sublayers?.first?.contents as AnyObject?}
            let transforms=layers.map{$0.sublayers?.first?.affineTransform()},eventCount=d.engine.events.last?.sequence
            advance(60);view.updateSprites()
            let after=d.engine.renderSnapshot(),afterLayers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            let frozen=states.count==2 && after.count==2 && layers.count==2 && afterLayers.count==2 &&
                birds.map(\.position)==positions && birds.map(\.stateTime)==ages && birds.map(\.motionRevision)==revisions &&
                birds.map(\.fraction)==fractions && birds.map(\.state)==kinds &&
                zip(states,after).allSatisfy{$0.id==$1.id && $0.frameName==$1.frameName && $0.rect==$1.rect &&
                    $0.facingRight==$1.facingRight && $0.hopOffset==$1.hopOffset} &&
                afterLayers.enumerated().allSatisfy {index,layer in
                    layer.frame==frames[index] && contents[index] != nil &&
                        (layer.sublayers?.first?.contents as AnyObject?) === contents[index] &&
                        layer.sublayers?.first?.affineTransform()==transforms[index]
                } && d.engine.events.last?.sequence==eventCount && d.engine.activeRunCount==1 &&
                d.engine.leasedBirdCount==2 && d.engine.reservedLandingCount==2 &&
                birds.allSatisfy{d.engine.behavior(of:$0) == .chase}
            try record("paused-flight",crop:true,probe:false)
            d.paused=false
            return frozen
        }

        func complete(_ species:SpeciesID,into checks:inout [String:Bool]) throws {
            fixture(species,name:species.rawValue+"-complete")
            let prefix="chase-"+species.rawValue
            checks[prefix+"RealWindowSettledPairAndLivePointer"]=usableFixture
            try record("settled",crop:true)
            let accepted=start(),startEvent=d.engine.events.last{$0.runID==run && $0.type == .started}
            let startPositions=birds.map(\.position),ages=birds.map(\.stateTime),revisions=birds.map(\.motionRevision)
            checks[prefix+"OneEncounterTwoExistingBirdsTwoReservations"]=accepted && samePopulation && run != nil &&
                Set(startEvent?.participants ?? [])==Set(ids) && startEvent?.source == .preview &&
                d.engine.activeRunCount==1 && d.engine.leasedBirdCount==2 && d.engine.reservedLandingCount==2 &&
                d.engine.scenePropCount==0 && d.engine.ambientBusy && birds.allSatisfy{d.engine.behavior(of:$0) == .chase}
            let busy=d.engine.handle(.chase(.preview))
            checks[prefix+"SharesSignificantEncounterBudget"]=accepted && busy == .rejected(.busy) &&
                d.engine.handle(.socialGreeting(.preview)) == .rejected(.busy) && d.engine.activeRunCount==1
            for _ in 0..<6 {d.syncWorld();view.updateSprites();_ = d.engine.renderSnapshot()}
            checks[prefix+"OnlyIntegrationMovesFeet"]=accepted && startPositions==origins && birds.map(\.position)==startPositions &&
                birds.map(\.stateTime)==ages && birds.map(\.motionRevision)==revisions
            var paused=false,resumed=false,milestones=Set<String>()
            for tick in 0..<30*60 {
                if !accepted {break}
                advance()
                let air=birds.filter{$0.state == .flying}.count
                let milestone=air==1 ? "staggered-takeoff":(air==2 ? "both-airborne":"landing")
                let capture=milestones.insert(milestone).inserted || tick==60 || tick==120 || tick==180
                try record(capture ? milestone+"-\(tick)":"tick",crop:capture)
                if air==2 && !paused {
                    checks[prefix+"PauseFreezesBothModelsAndLayers"]=try pauseEvidence();paused=true
                    let positions=birds.map(\.position),eventRun=run
                    advance();try record("resumed-flight",crop:true)
                    resumed=birds.map(\.position) != positions && run==eventRun &&
                        birds.allSatisfy{d.engine.behavior(of:$0) == .chase} && terminals(run).isEmpty
                }
                if !terminals(run).isEmpty {break}
            }
            try record("finished",crop:true)
            let ends=terminals(run),scale=d.spriteScale(for:birds[0])
            checks[prefix+"PauseFreezesBothModelsAndLayers"]=paused && (checks[prefix+"PauseFreezesBothModelsAndLayers"] ?? false)
            checks[prefix+"ResumeContinuesSameRun"]=accepted && resumed
            checks[prefix+"StaggeredTakeoff"]=accepted && firstAir[0] != nil && firstAir[1] != nil &&
                (firstAir[1] ?? 0)-(firstAir[0] ?? 0)>=0.2 &&
                (firstAir[1] ?? 0)-(firstAir[0] ?? 0)<=1.5+dt
            checks[prefix+"BothFlyWithSafeSeparation"]=accepted && separated && pairedAirTicks>=12 && minimumSeparation>=32*scale &&
                flightFrames.allSatisfy{$0.filter{$0.hasPrefix("fly")}.count>=2}
            checks[prefix+"SameLoopAndOwnOriginalLandings"]=accepted && followsSameLoop(scale:scale) && returned
            checks[prefix+"ActualArtLayersAndFootAnchors"]=accepted && layersOK && anchorsOK && continuous
            checks[prefix+"OpaquePixelsHitAndHover"]=accepted && hitsOK && pairedAirTicks>0
            checks[prefix+"TransparentPixelsPassThrough"]=accepted && transparentOK
            checks[prefix+"LivePointerClearsWholePath"]=accepted && pointerOK && contained
            checks[prefix+"NeverAddsBirds"]=accepted && populationOK && samePopulation
            checks[prefix+"CompletesOnceAndReleasesBothReservations"]=accepted && ends.count==1 &&
                ends.first?.type == .completed && clearResources && slotsOK && birds.allSatisfy{d.engine.behavior(of:$0)==nil}
            summarize(accepted:accepted,extra:["firstAirTimes":firstAir.map{$0 ?? -1},
                "pairedAirSeconds":Double(pairedAirTicks)*dt,"minimumAirSeparation":pairedAirTicks>0 ? minimumSeparation:-1,
                "flightFrames":flightFrames.map{$0.sorted()}])
        }

        /// Chase.swift's entry is 110*scale above the perch. Above that entry,
        /// samples belong to the shared ring, excluding separate connectors.
        /// Require a full turn and shared geometry, not merely two return hops.
        func followsSameLoop(scale:CGFloat) -> Bool {
            let central=flightPaths.map {path in path.filter{$0.y<host.rect.minY-112*scale}}
            guard central.allSatisfy({$0.count>=24}) else {return false}
            for path in central {
                guard let minX=path.map(\.x).min(),let maxX=path.map(\.x).max(),
                      let minY=path.map(\.y).min(),let maxY=path.map(\.y).max(),
                      maxX-minX>300*scale,maxY-minY>160*scale else {return false}
                let center=CGPoint(x:(minX+maxX)/2,y:(minY+maxY)/2)
                var turn=0.0
                for (a,b) in zip(path,path.dropFirst()) {
                    var delta = atan2(Double(b.y-center.y),Double(b.x-center.x)) -
                        atan2(Double(a.y-center.y),Double(a.x-center.x))
                    if delta>Double.pi {delta-=2*Double.pi}
                    if delta < -Double.pi {delta+=2*Double.pi}
                    turn+=delta
                }
                guard abs(turn)>5.5,abs(turn)<2*Double.pi+0.1 else {return false}
            }
            return central.enumerated().allSatisfy {index,path in
                path.filter {p in central[1-index].contains{Geometry.distance(p,$0)<16*scale}}.count*10>=path.count*9
            }
        }

        func waitForPair() throws -> Bool {
            for _ in 0..<12*60 {
                advance();try record("tick",probe:false)
                if birds.allSatisfy({$0.state == .flying && d.engine.behavior(of:$0) == .chase}) {return true}
                if !terminals(run).isEmpty {break}
            }
            return false
        }
        func click(_ index:Int,into checks:inout [String:Bool]) throws {
            fixture(.treeSparrow,name:"click-member-\(index)")
            let fixtureOK=usableFixture,accepted=start(),air=accepted ? try waitForPair():false
            try record("before-click",crop:true)
            let clicked=birds[index],partner=birds[1-index],position=clicked.position,partnerPosition=partner.position
            let revision=clicked.motionRevision,states=d.engine.renderSnapshot()
            let pixel=states.first{$0.id==ids[index]}.flatMap{pixelPoint($0,opaque:true,states:states)}
            let relocated=pixel.map{d.relocateBird(at:$0)} ?? false
            events()
            let replacement=d.engine.events.last{$0.kind == .relocate && $0.type == .started}?.runID
            let ends=terminals(run)
            checks["chaseClickMember\(index)PreemptsOnlyClickedBird"]=fixtureOK && accepted && air && relocated &&
                clicked.position==position && partner.position==partnerPosition && clicked.motionRevision>revision &&
                d.engine.behavior(of:clicked) == .relocate && d.engine.behavior(of:partner)==nil &&
                ends.count==1 && ends.first?.type == .cancelled && d.engine.activeRunCount==1 &&
                d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==0 && !d.engine.ambientBusy && samePopulation
            try record("click-preempted",crop:true,probe:false)
            // Recovery is the production autonomous route from the current foot.
            // The verifier does not perch, fly, or manually route the partner.
            d.engine.autonomousRouting=true
            let replacementRevision=clicked.motionRevision
            advance();try record("recovery-planned-at-actual-foot",crop:true,probe:false)
            let partnerStartsHere=partner.position==partnerPosition
            var partnerRecovered=false,clickedMoved=false,onlyOneReplacement=true
            for tick in 0..<46*60 {
                advance();try record("recovery-tick",probe:false)
                clickedMoved = clickedMoved || Geometry.distance(clicked.position,position)>1
                partnerRecovered = partnerRecovered || (partner.state == .perched && !partner.needsDestination)
                onlyOneReplacement = onlyOneReplacement && d.engine.behavior(of:partner) != .relocate &&
                    clicked.motionRevision==replacementRevision && terminals(run).count==1 && d.engine.reservedLandingCount==0
                if tick==6 || tick==60 {try record("recovery-\(tick)",crop:true,probe:false)}
                if partnerRecovered && !terminals(replacement).isEmpty {break}
            }
            try record("recovered",crop:true,probe:false)
            let replacementEnds=terminals(replacement)
            checks["chaseClickMember\(index)PartnerRecoversAndReplacementCleansUp"]=relocated && partnerRecovered && clickedMoved &&
                partnerStartsHere && continuous && onlyOneReplacement && populationOK && samePopulation && clearResources && replacementEnds.count==1 &&
                replacementEnds.first?.type == .completed
            summarize(accepted:accepted,extra:["clickedID":ids[index].rawValue,"replacementRun":replacement?.rawValue ?? 0,
                "partnerRecovered":partnerRecovered])
        }

        func interrupt(_ cause:String,into checks:inout [String:Bool]) throws {
            fixture(.treeSparrow,name:cause)
            let fixtureOK=usableFixture,accepted=start(),air=accepted ? try waitForPair():false
            try record("before-cancel",crop:true,probe:false)
            let positions=birds.map(\.position)
            switch cause {
            case "host-removed":hostWindow.orderOut(nil);d.surfaces=[];d.syncWorld()
            case "space-changed":d.engine.handle(.cancelAmbient(.spaceChanged))
            case "chase-disabled":var value=d.settings;value.chaseEnabled=false;d.settings=value
            case "social-disabled":var value=d.settings;value.socialInteractions=false;d.settings=value
            default:d.frameCapabilities[.treeSparrow] = ["stand"];d.syncWorld()
            }
            events()
            let ends=terminals(run)
            let expected:BehaviorReason=cause=="host-removed" ? .targetInvalid:
                (cause=="space-changed" ? .spaceChanged:(cause=="missing-frames" ? .missingFrames:.settingsChanged))
            checks["chaseSafeExit-"+cause]=fixtureOK && accepted && air && birds.map(\.position)==positions &&
                ends.count==1 && ends.first?.reason==expected && ends.first?.type != .completed &&
                clearResources && samePopulation && birds.allSatisfy{d.engine.behavior(of:$0)==nil}
            try record("cancelled",crop:true,probe:false)
            d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
            if cause=="host-removed" {hostWindow.orderFrontRegardless();d.surfaces=[host]}
            d.engine.autonomousRouting=true
            var recovered=false
            for _ in 0..<46*60 {
                advance();try record("recovery-tick",probe:false)
                if birds.allSatisfy({$0.state == .perched && !$0.needsDestination}) {recovered=true;break}
            }
            checks["chaseRecovery-"+cause]=accepted && recovered && clearResources && populationOK && samePopulation &&
                terminals(run).count==1 && birds.allSatisfy{d.engine.behavior(of:$0)==nil}
            try record("recovered",crop:true,probe:false);summarize(accepted:accepted,extra:["cause":cause])
        }

        func reject(_ gate:String,into checks:inout [String:Bool]) throws {
            fixture(.treeSparrow,name:"reject-"+gate)
            let fixtureOK=usableFixture
            switch gate {
            case "chase-disabled":var value=d.settings;value.chaseEnabled=false;d.settings=value
            case "social-disabled":var value=d.settings;value.socialInteractions=false;d.settings=value
            case "missing-frames":d.frameCapabilities[.treeSparrow] = ["stand"];d.syncWorld()
            default:
                // Restrict geometry, never pointer input. Restore before rendering
                // (DesktopView resamples world geometry from the controller).
                var world=d.engine.world
                world.screens=[];world.displays=[];d.engine.updateWorld(world)
            }
            let positions=birds.map(\.position),revision=birds.map(\.motionRevision)
            let result=d.engine.handle(.chase(.preview));events()
            let expected:BehaviorReason=gate=="missing-frames" ? .missingFrames:(gate=="no-space" ? .noSpace:.disabled)
            checks["chaseRejects-"+gate]=fixtureOK && result == .rejected(expected) && clearResources &&
                samePopulation && birds.map(\.position)==positions && birds.map(\.motionRevision)==revision
            try record("rejected",crop:true,probe:false)
            summarize(accepted:false,extra:["gate":gate,"result":String(describing:result)])
        }

        func pixelPoint(_ state:BirdRenderState,opaque:Bool,states:[BirdRenderState]) -> CGPoint? {
            guard let art=d.arts[state.species] else {return nil}
            for pixel in 0..<48*48 where art.contains(frame:state.frameName,x:pixel%48,y:pixel/48)==opaque {
                let x=state.facingRight ? pixel%48:47-pixel%48
                let point=CGPoint(x:state.rect.minX+(CGFloat(x)+0.5)*state.scale,
                    y:state.rect.minY+(CGFloat(pixel/48)+0.5)*state.scale)
                guard !state.blockers.contains(where:{$0.contains(point)}),
                      !states.contains(where:{$0.id != state.id && $0.rect.contains(point)}) else {continue}
                return point
            }
            return nil
        }
        func summarize(accepted:Bool,extra:[String:Any]=[:]) {
            let ends=terminals(run)
            var value:[String:Any]=["case":caseName,"accepted":accepted,"runID":run?.rawValue ?? 0,
                "birdIDs":ids.map(\.rawValue),"origins":origins.map(Self.point),"fractions":fractions,
                "hostID":host.id,"hostRect":NSStringFromRect(host.rect),"scale":d.scale,
                "spriteScale":birds.first.map{d.spriteScale(for:$0)} ?? 0,
                "routeEnvelope":NSStringFromRect(corridor),"pointerSafetyMargin":100,
                "terminalEvents":ends.map{["type":$0.type.rawValue,"reason":$0.reason?.rawValue ?? ""]}]
            value.merge(extra){_,new in new};cases.append(value)
        }
        func writeReport(_ checks:[String:Bool]) throws {
            events()
            let own=checks.filter{$0.key.hasPrefix("chase")}
            let orderedEvents=eventLog.values.sorted{$0.sequence<$1.sequence}.map {event -> [String:Any] in
                ["sequence":event.sequence,"time":event.time,"runID":event.runID?.rawValue ?? 0,
                    "kind":event.kind?.rawValue ?? "none","source":event.source.rawValue,
                    "type":event.type.rawValue,"reason":event.reason?.rawValue ?? "",
                    "participants":event.participants.map(\.rawValue)]
            }
            let report:[String:Any]=["milestone":"M5i","seed":String(d.engine.seed),"checks":own,"passed":own.values.allSatisfy{$0},
                "cases":cases,"artifacts":artifacts,"trajectoryFile":"chase-trajectory.json",
                "imageEvidence":"Actual BirdArt/DesktopView and real host-window layer crop composites; not desktop screenshots.",
                "input":"Live NSEvent pointer and pressed buttons, no warp or synthetic pointer samples. Direct pixel routing probes hover/click.",
                "execution":"Manual fixed engine steps; no controller start, timers, user settings load/save, or bird spawning.",
                "representativeSpecies":[SpeciesID.treeSparrow.rawValue,SpeciesID.barnSwallow.rawValue,SpeciesID.redWhiskeredBulbul.rawValue],
                "m6cScope":"Red-whiskered Bulbul: complete real-window pair, actual layers/feet, separation, pause and original landings; legacy cases retained.",
                "supportedSpecies":ChaseBehavior.supportedSpecies.map(\.rawValue).sorted(),
                "events":orderedEvents]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
                .write(to:folder.appendingPathComponent("chase-report.json"),options:.atomic)
            try JSONSerialization.data(withJSONObject:["coordinateSystem":"Quartz desktop points, y increases downward",
                "samples":trajectory],options:[.prettyPrinted,.sortedKeys])
                .write(to:folder.appendingPathComponent("chase-trajectory.json"),options:.atomic)
        }
        static func point(_ point:CGPoint) -> [CGFloat] {[point.x,point.y]}
        static func foot(_ layer:CALayer,state:BirdRenderState,display:CGRect) -> CGPoint {
            CGPoint(x:layer.frame.minX+display.minX+(state.facingRight ? 29:19)*state.scale,
                y:layer.frame.minY+display.minY+(39-state.hopOffset)*state.scale)
        }
        static func snapshot(_ view:DesktopView,hostView:NSView?,host:CGRect,display:CGRect,crop:CGRect,to url:URL) throws {
            guard !crop.isEmpty,let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(crop.width),
                pixelsHigh:Int(crop.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,
                colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else {
                throw NSError(domain:"ChaseVerification",code:2)
            }
            view.layoutSubtreeIfNeeded();hostView?.layoutSubtreeIfNeeded()
            view.displayIfNeeded();hostView?.displayIfNeeded()
            let ctx=graphics.cgContext
            ctx.setFillColor(NSColor(calibratedWhite:0.22,alpha:1).cgColor);ctx.fill(CGRect(origin:.zero,size:crop.size))
            ctx.translateBy(x:-crop.minX,y:crop.maxY);ctx.scaleBy(x:1,y:-1)
            if let hostView {
                ctx.saveGState();ctx.translateBy(x:host.minX,y:host.maxY);ctx.scaleBy(x:1,y:-1)
                hostView.layer?.render(in:ctx);ctx.restoreGState()
            }
            ctx.translateBy(x:display.minX,y:display.minY);view.layer?.render(in:ctx)
            guard let png=bitmap.representation(using:.png,properties:[:]) else {
                throw NSError(domain:"ChaseVerification",code:3)
            }
            try png.write(to:url,options:.atomic)
        }
    }
}
