import AppKit
import BirdingCore

/// M5j / B13: real native hosts, production art/layers, live pointer input,
/// and manual engine steps. Never starts the controller or loads user settings.
enum TravelTogetherVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("travel-together-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        let h=try Harness(folder:evidence)
        defer {h.close()}
        for species:SpeciesID in [.spottedDove,.blackCollaredStarling] {try h.complete(species,into:&checks)}
        for index in 0..<2 {try h.click(index,into:&checks)}
        for cause in ["host-removed","setting-disabled"] {try h.interrupt(cause,into:&checks)}
        for gate in ["stationary","opposite-directions","setting-disabled","social-disabled"] {try h.reject(gate,into:&checks)}
        checks["travelTogetherNoTimersOrUserFileWrites"]=h.d.timer==nil && h.d.globalMouseMonitor==nil &&
            h.d.localMouseMonitor==nil && h.d.visitorMemoryPersistence==nil && !h.d.visitorMemoryPersistenceEnabled &&
            [h.d.settingsURL,h.d.legacyURL,h.d.visitorMemoryURL].allSatisfy {
                $0.deletingLastPathComponent()==evidence && !FileManager.default.fileExists(atPath:$0.path)
            }
        checks["travelTogetherFinalResourcesReleased"]=h.clearResources
        h.close()
        checks["travelTogetherFixtureWindowsHiddenAfterRun"] = !h.overlay.isVisible && !h.hostWindow.isVisible
        try h.writeReport(checks)
        print("Travel together native evidence: \(evidence.path)")
    }

    private final class Harness {
        let d:DesktopController
        let folder:URL,display:CGRect,work:CGRect
        let hostWindow:NSWindow,hostView:NSView,overlay:OverlayPanel,view:DesktopView
        let dt=1.0/60
        var host=Surface(id:0,rect:.zero),corridor=CGRect.zero
        var birds:[Bird]=[],ids:[BirdID]=[],targets:[CGPoint]=[],fractions:[CGFloat]=[],origins:[CGPoint]=[]
        var caseName="",run:BehaviorRunID?
        var trajectory:[[String:Any]]=[],cases:[[String:Any]]=[],artifacts:[[String:Any]]=[]
        var eventLog:[UInt64:BehaviorEvent]=[:]
        var previous:[CGPoint]=[],velocities:[CGPoint]=[],previousVelocities:[CGPoint]=[]
        var populationOK=true,pointerOK=true,layersOK=true,anchorsOK=true,hitsOK=true,transparentOK=true
        var continuous=true,contained=true,slotsOK=true,separated=true
        var frames:[Set<String>]=[[],[]]
        var minimumGap=CGFloat.greatestFiniteMagnitude,maximumSpeedJump=0.0,maximumVelocityJump=0.0
        var initialGap:CGFloat=0,incomingLateral:CGFloat=0,sharedTicks=0,longestSharedTicks=0
        var sharedOffset:CGPoint?,diverged=false
        var requiredFixtureWidth=0.0

        init(folder:URL) throws {
            let d=DesktopController()
            guard let screen=NSScreen.screens.first,let display=d.displayRects.first,let work=d.screenRects.first else {
                throw NSError(domain:"TravelTogetherVerification",code:1,
                    userInfo:[NSLocalizedDescriptionKey:"Native travel-together verification requires a display."])
            }
            d.settingsURL=folder.appendingPathComponent("unused-settings.json")
            d.legacyURL=folder.appendingPathComponent("unused-legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("unused-visitors.json")
            d.visitorMemoryPersistenceEnabled=false;d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            let hostWindow=NSWindow(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
            hostWindow.isReleasedWhenClosed=false;hostWindow.hasShadow=false;hostWindow.ignoresMouseEvents=true
            hostWindow.backgroundColor=NSColor(calibratedWhite:0.92,alpha:1)
            let hostView=NSView(frame:.zero);hostView.wantsLayer=true
            hostView.layer?.backgroundColor=hostWindow.backgroundColor.cgColor;hostWindow.contentView=hostView
            let overlay=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            overlay.isReleasedWhenClosed=false;overlay.hasShadow=false;overlay.ignoresMouseEvents=true
            overlay.isOpaque=false;overlay.backgroundColor = .clear;overlay.level = .floating
            let view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size))
            view.controller=d;view.desktopRect=display;overlay.contentView=view
            self.d=d;self.folder=folder;self.display=display;self.work=work
            self.hostWindow=hostWindow;self.hostView=hostView;self.overlay=overlay;self.view=view
        }
        func close() {
            d.engine.handle(.cancelAmbient(.shutdown));overlay.orderOut(nil);hostWindow.orderOut(nil)
        }
        var clearResources:Bool {
            d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0 &&
                d.engine.scenePropCount==0 && !d.engine.ambientBusy
        }
        var samePopulation:Bool {
            birds.count==2 && ids.count==2 && d.engine.birds.count==2 && birds.enumerated().allSatisfy {i,bird in
                d.engine.birds[i] === bird && d.engine.id(of:bird)==ids[i]
            } && d.residentCount==2 && d.engine.passingCount==0 && d.engine.departingCount==0 &&
                d.engine.pendingCount==0 && d.arrivalCount==0 && d.departureCount==0
        }
        func events() {for event in d.engine.events {eventLog[event.sequence]=event}}
        func terminals(_ id:BehaviorRunID?) -> [BehaviorEvent] {
            events();guard let id else {return []}
            return eventLog.values.filter{$0.runID==id && [.completed,.failed,.cancelled].contains($0.type)}
                .sorted{$0.sequence<$1.sequence}
        }
        func advance(_ count:Int=1) {
            for _ in 0..<count {d.syncWorld();d.engine.advance(dt);events()}
        }

        /// All route fixture geometry lives here, independent of private planner
        /// stages. The wide host gives two actual destinations on its top edge.
        /// Choose the upper/lower strip furthest from the unmodified live mouse.
        func fixture(_ species:SpeciesID,name:String,mode:String="ordinary") {
            d.paused=false;d.engine.handle(.cancelAmbient(.screensChanged));events()
            var settings=d.settings
            settings.travelTogetherEnabled=true;settings.socialInteractions=true;settings.hoverDelay=0
            settings.sideHopEnabled=false;settings.takeoffPreparationEnabled=false;settings.edgePeekEnabled=false
            d.settings=settings;d.engine.autonomousRouting=false
            d.hoverTracker=HoverTracker<BirdID>();d.hoveredBird=nil
            d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
            caseName=name;run=nil
            birds=(0..<2).map {_ in Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(species),random:{0.5})}
            // Prefer default size; shrink only if neither strip can clear the
            // actual pointer. Flight speed and timing retain production values.
            func envelope(_ r:CGRect,scale:CGFloat) -> CGRect {
                CGRect(x:work.minX+20,y:r.minY-330*scale,width:work.width-40,height:355*scale)
            }
            func distance(_ r:CGRect,scale:CGFloat) -> CGFloat {
                let p=d.pointerPosition,a=envelope(r,scale:scale)
                return hypot(max(0,max(a.minX-p.x,p.x-a.maxX)),max(0,max(a.minY-p.y,p.y-a.maxY)))
            }
            var rect=CGRect.zero
            for candidateScale:CGFloat in [1,0.85,0.7,0.55,0.5] {
                d.scale=candidateScale
                let sprite=d.spriteScale(for:birds[0])
                // Agreed B13 route budget: entry with moving endpoints, 2.2s
                // common segment, then a complete exit to the nearer target.
                // Use the planner's slower valid candidate, not a slower Bird.
                let incoming=FlightBehavior.cruiseSpeed(species,multiplier:birds[0].profile.speed)
                let common=min(incoming,min(220*sprite,190*sprite*sqrt(birds[0].profile.speed)))*0.85
                let entry=max(230*sprite,(incoming+common)/2+common*0.6)
                let exit=max(140*sprite,common*0.8)
                // 154: native host and perch margins; 190*sprite: initial and
                // near-target insets; 32*sprite: curvature/sweep allowance.
                let requiredWidth=incoming*0.325+entry+common*2.2+exit+154+222*sprite
                requiredFixtureWidth=requiredWidth
                // Ordinary destination selection requires a host at least 100
                // points high. Recovery must be able to choose this real host.
                let candidates=[work.minY+330*sprite+20,work.maxY-120].map {
                    CGRect(x:work.minX+35,y:$0,width:work.width-70,height:100)
                }
                rect=candidates.max{distance($0,scale:sprite)<distance($1,scale:sprite)} ?? .zero
                if work.width>=requiredWidth && display.contains(envelope(rect,scale:sprite)) &&
                    work.contains(rect) && distance(rect,scale:sprite)>101 {break}
            }
            let scale=d.spriteScale(for:birds[0])
            hostWindow.setFrame(Geometry.quartz(rect,primaryHeight:d.primaryHeight),display:true)
            hostView.frame=CGRect(origin:.zero,size:hostWindow.frame.size);hostView.layer?.frame=hostView.bounds
            hostWindow.orderFrontRegardless();overlay.orderFrontRegardless()
            host=Surface(id:UInt32(hostWindow.windowNumber),pid:ProcessInfo.processInfo.processIdentifier,
                rect:Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight))
            corridor=envelope(host.rect,scale:scale)
            let lo=Geometry.perchX(0,rect:host.rect),hi=Geometry.perchX(1,rect:host.rect)
            targets=[CGPoint(x:hi-170*scale,y:host.rect.minY),CGPoint(x:hi-20*scale,y:host.rect.minY)]
            fractions=targets.map{($0.x-lo)/max(1,hi-lo)}
            for (i,bird) in birds.enumerated() {
                bird.fraction=fractions[i];bird.perch(on:host,spriteScale:scale);bird.perchDuration=600
                if mode != "stationary" {
                    bird.position=CGPoint(x:lo+20*scale,y:host.rect.minY-(i==0 ? 90:280)*scale)
                    if mode=="opposite-directions" && i==1 {
                        bird.position.x=hi-20*scale;targets[i].x=lo+20*scale
                        fractions[i]=(targets[i].x-lo)/max(1,hi-lo);bird.fraction=fractions[i]
                    }
                    bird.fly(to:targets[i],host:host,arc:0,airspace:display.insetBy(dx:30*scale,dy:40*scale),
                        allowsOrbit:false,random:{0.5})
                }
            }
            d.surfaces=[host];d.birds=birds;d.syncWorld()
            // Advance ordinary production flights before issuing preview. This
            // also establishes their measured, nonzero incoming velocities.
            advance(38)
            let before=birds.map(\.position);advance()
            velocities=zip(before,birds).map{CGPoint(x:($1.position.x-$0.x)/dt,y:($1.position.y-$0.y)/dt)}
            ids=birds.compactMap{d.engine.id(of:$0)};origins=birds.map(\.position)
            previous=origins;previousVelocities=velocities;initialGap=Geometry.distance(origins[0],origins[1])
            incomingLateral=lateralSeparation
            populationOK=true;pointerOK=true;layersOK=true;anchorsOK=true;hitsOK=true;transparentOK=true
            continuous=true;contained=true;slotsOK=true;separated=true;frames=[[],[]]
            minimumGap = .greatestFiniteMagnitude;maximumSpeedJump=0;maximumVelocityJump=0
            sharedTicks=0;longestSharedTicks=0;sharedOffset=nil;diverged=false
        }
        var usableFixture:Bool {
            samePopulation && hostWindow.isVisible && host.id==UInt32(hostWindow.windowNumber) && !host.isGround &&
                host.rect==Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight) && display.contains(corridor) &&
                !corridor.insetBy(dx:-100,dy:-100).contains(d.pointerPosition) && !d.engine.world.buttonsDown &&
                birds.allSatisfy{$0.state == .flying && $0.stateTime>=0.5 && !$0.needsDestination &&
                    d.engine.behavior(of:$0)==nil && $0.flightSpeed>=60} && initialGap>80*d.spriteScale(for:birds[0]) &&
                Geometry.distance(targets[0],targets[1])>80*d.spriteScale(for:birds[0])
        }
        var sameHeading:Bool {
            guard velocities.count==2 else {return false}
            let a=velocities[0],b=velocities[1]
            return (a.x*b.x+a.y*b.y)/max(1,Geometry.distance(.zero,a)*Geometry.distance(.zero,b))>=0.85 &&
                lateralSeparation>=140*d.spriteScale(for:birds[0])
        }
        var lateralSeparation:CGFloat {
            guard velocities.count==2,origins.count==2 else {return 0}
            let a=velocities[0],b=velocities[1]
            let sa=max(1,Geometry.distance(.zero,a)),sb=max(1,Geometry.distance(.zero,b))
            let direction=CGPoint(x:a.x/sa+b.x/sb,y:a.y/sa+b.y/sb)
            let length=max(0.000001,Geometry.distance(.zero,direction))
            return abs((origins[1].y-origins[0].y)*direction.x-(origins[1].x-origins[0].x)*direction.y)/length
        }
        @discardableResult func start() -> Bool {
            d.syncWorld();let sequence=d.engine.events.last?.sequence ?? 0
            let result=d.engine.handle(.travelTogether(.preview));events()
            run=d.engine.events.last{$0.sequence>sequence && $0.kind == .travelTogether && $0.type == .started}?.runID
            return result.accepted && run != nil
        }
        var returned:Bool {
            birds.enumerated().allSatisfy {i,bird in
                bird.state == .perched && bird.hostID==host.id && bird.edge == .top &&
                    Geometry.distance(bird.position,targets[i])<0.001 && abs(bird.fraction-fractions[i])<0.000001
            }
        }

        /// Observe velocities from successive actual feet, never plan internals.
        /// A stable parallel segment counts only after visible convergence.
        func record(_ label:String,crop:Bool=false,probe:Bool=true,moving:Bool=false) throws {
            view.updateSprites();events()
            let states=d.engine.renderSnapshot(),layers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            populationOK = populationOK && samePopulation
            let protected=corridor.insetBy(dx:-100,dy:-100)
            pointerOK = pointerOK && !protected.contains(d.pointerPosition) && !protected.contains(d.engine.world.pointer) &&
                !d.engine.world.buttonsDown
            layersOK = layersOK && states.count==2 && layers.count==2
            if states.count==2 {
                let overlap=states[0].rect.intersection(states[1].rect)
                separated = separated && (overlap.isNull || overlap.isEmpty)
            }
            var members:[[String:Any]]=[]
            for (i,bird) in birds.enumerated() {
                guard i<ids.count,let state=states.first(where:{$0.id==ids[i]}),
                      let layerIndex=states.firstIndex(where:{$0.id==state.id}),layerIndex<layers.count,
                      let texture=layers[layerIndex].sublayers?.first,let art=d.arts[state.species],
                      let image=art.frames[state.frameName] else {layersOK=false;anchorsOK=false;continue}
                let layer=layers[layerIndex],foot=Self.foot(layer,state:state,display:display)
                layersOK = layersOK && !layer.isHidden && (texture.contents as AnyObject?) === image &&
                    texture.affineTransform().a == (state.facingRight ? 1:-1)
                anchorsOK = anchorsOK && Geometry.distance(foot,bird.position)<0.001 && state.position==bird.position
                contained = contained && display.contains(state.rect)
                pointerOK = pointerOK && !state.rect.insetBy(dx:-100,dy:-100).contains(d.pointerPosition)
                if moving {
                    let v=CGPoint(x:(bird.position.x-previous[i].x)/dt,y:(bird.position.y-previous[i].y)/dt)
                    let speed=Double(Geometry.distance(.zero,v)),old=Double(Geometry.distance(.zero,previousVelocities[i]))
                    let jump=Double(Geometry.distance(v,previousVelocities[i]))
                    maximumSpeedJump=max(maximumSpeedJump,abs(speed-old));maximumVelocityJump=max(maximumVelocityJump,jump)
                    continuous = continuous && v.x.isFinite && v.y.isFinite && speed<900 &&
                        abs(speed-old)<=max(18,old*0.12) && jump<=max(28,old*0.18)
                    velocities[i]=v;previousVelocities[i]=v;previous[i]=bird.position
                }
                if d.engine.behavior(of:bird) == .travelTogether {
                    slotsOK = slotsOK && d.engine.activeRunCount==1 && d.engine.leasedBirdCount==2 &&
                        d.engine.reservedLandingCount==2 && d.engine.scenePropCount==0 && d.engine.ambientBusy
                    if bird.state == .flying {frames[i].insert(state.frameName)}
                }
                if probe {
                    if let pixel=pixelPoint(state,opaque:true,states:states) {
                        hitsOK = hitsOK && d.bird(at:pixel) === bird && state.hoverable
                        d.updateHover(now:d.engine.time,at:pixel);view.updateSprites()
                        hitsOK = hitsOK && d.hoveredBird === bird &&
                            (view.layer?.sublayers?.contains{($0 as? CATextLayer)?.isHidden == false} ?? false)
                        d.hoverTracker=HoverTracker<BirdID>();d.hoveredBird=nil
                    } else {hitsOK=false}
                    if let pixel=pixelPoint(state,opaque:false,states:states) {
                        let sequence=d.engine.events.last?.sequence
                        transparentOK = transparentOK && d.bird(at:pixel)==nil && !d.relocateBird(at:pixel) &&
                            d.engine.events.last?.sequence==sequence && overlay.ignoresMouseEvents && !overlay.canBecomeKey
                    } else {transparentOK=false}
                }
                members.append(["id":state.id.rawValue,"species":state.species.rawValue,"state":bird.state.rawValue,
                    "frame":state.frameName,"foot":Self.point(bird.position),"layerFoot":Self.point(foot),
                    "layerFrame":NSStringFromRect(layer.frame),"velocity":Self.point(velocities[i]),"speed":bird.flightSpeed,
                    "fraction":bird.fraction,"motionRevision":bird.motionRevision,"stateTime":bird.stateTime,
                    "hoverable":state.hoverable,"behavior":d.engine.behavior(of:bird)?.rawValue ?? "none"])
            }
            if moving && birds.allSatisfy({$0.state == .flying && d.engine.behavior(of:$0) == .travelTogether}) {
                let gap=Geometry.distance(birds[0].position,birds[1].position),scale=d.spriteScale(for:birds[0])
                minimumGap=min(minimumGap,gap)
                let speeds=velocities.map{Geometry.distance(.zero,$0)}
                let dot=(velocities[0].x*velocities[1].x+velocities[0].y*velocities[1].y)/max(1,speeds[0]*speeds[1])
                let parallel=gap<initialGap-18*scale && speeds.min()!>60 && dot>0.98 &&
                    Geometry.distance(velocities[0],velocities[1])<max(8,speeds.min()!*0.04)
                sharedTicks=parallel ? sharedTicks+1:0
                longestSharedTicks=max(longestSharedTicks,sharedTicks)
                let offset=CGPoint(x:birds[1].position.x-birds[0].position.x,
                                   y:birds[1].position.y-birds[0].position.y)
                if sharedTicks>=108,sharedOffset==nil {sharedOffset=offset}
                // Two distinct slots on one ledge can reduce lateral spacing
                // while increasing fore/aft spacing. Detect a visible change
                // in the relative position vector, not just scalar distance.
                if let sharedOffset,!parallel,Geometry.distance(offset,sharedOffset)>18*scale {diverged=true}
            } else if moving {sharedTicks=0}
            trajectory.append(["case":caseName,"label":label,"time":d.engine.time,"runID":run?.rawValue ?? 0,
                "pointer":Self.point(d.pointerPosition),"worldPointer":Self.point(d.engine.world.pointer),
                "buttonsDown":d.engine.world.buttonsDown,"paused":d.paused,"activeRuns":d.engine.activeRunCount,
                "leases":d.engine.leasedBirdCount,"reservations":d.engine.reservedLandingCount,"members":members,
                "sharedSeconds":Double(sharedTicks)*dt,"diverged":diverged])
            if crop {
                d.hoveredBird=nil;view.updateSprites()
                let name=caseName+"-"+label+"-layer-composite.png"
                let area=states.reduce(corridor){$0.union($1.rect)}.insetBy(dx:-16,dy:-32).intersection(display).integral
                try Self.snapshot(view,hostView:hostWindow.isVisible ? hostView:nil,host:host.rect,display:display,
                    crop:area,to:folder.appendingPathComponent(name))
                artifacts.append(["file":name,"case":caseName,"label":label,"time":d.engine.time,
                    "kind":"native-layer-crop-composite; not a desktop screenshot","crop":NSStringFromRect(area)])
            }
        }

        func pauseEvidence() throws -> Bool {
            d.paused=true;view.updateSprites()
            let before=d.engine.renderSnapshot(),positions=birds.map(\.position),ages=birds.map(\.stateTime)
            let revisions=birds.map(\.motionRevision),sequence=d.engine.events.last?.sequence
            let layers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            let rects=layers.map(\.frame),images=layers.map{$0.sublayers?.first?.contents as AnyObject?}
            let transforms=layers.map{$0.sublayers?.first?.affineTransform()}
            advance(60);view.updateSprites()
            let after=d.engine.renderSnapshot(),afterLayers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            let frozen=before.count==2 && after.count==2 && layers.count==2 && afterLayers.count==2 &&
                birds.map(\.position)==positions && birds.map(\.stateTime)==ages && birds.map(\.motionRevision)==revisions &&
                zip(before,after).allSatisfy{$0.id==$1.id && $0.frameName==$1.frameName && $0.rect==$1.rect &&
                    $0.facingRight==$1.facingRight && $0.hopOffset==$1.hopOffset} &&
                afterLayers.enumerated().allSatisfy {i,layer in
                    layer.frame==rects[i] && images[i] != nil && (layer.sublayers?.first?.contents as AnyObject?) === images[i] &&
                        layer.sublayers?.first?.affineTransform()==transforms[i]
                } && d.engine.events.last?.sequence==sequence && d.engine.activeRunCount==1 &&
                d.engine.leasedBirdCount==2 && d.engine.reservedLandingCount==2 && terminals(run).isEmpty
            try record("paused",crop:true,probe:false);d.paused=false
            return frozen
        }
        func complete(_ species:SpeciesID,into checks:inout [String:Bool]) throws {
            fixture(species,name:species.rawValue+"-complete")
            let prefix="travelTogether-"+species.rawValue
            checks[prefix+"AlreadyFlyingDistinctPairRealWindowLivePointer"]=usableFixture && sameHeading
            try record("ordinary-flight",crop:true)
            let feet=birds.map(\.position),incoming=velocities,accepted=start()
            let event=d.engine.events.last{$0.runID==run && $0.type == .started}
            checks[prefix+"PreviewUsesTwoExistingBirdsWithoutMovingFeet"]=accepted && samePopulation &&
                birds.map(\.position)==feet && birds.allSatisfy{$0.state == .flying} &&
                Set(event?.participants ?? [])==Set(ids) && event?.source == .preview &&
                d.engine.leasedBirdCount==2 && d.engine.reservedLandingCount==2
            let revisions=birds.map(\.motionRevision),ages=birds.map(\.stateTime)
            for _ in 0..<3 {d.syncWorld();view.updateSprites();_ = d.engine.renderSnapshot()}
            checks[prefix+"RenderingDoesNotAdvanceFlight"]=accepted && birds.map(\.position)==feet &&
                birds.map(\.motionRevision)==revisions && birds.map(\.stateTime)==ages
            checks[prefix+"SharesEncounterBudget"]=accepted && d.engine.handle(.travelTogether(.preview)) == .rejected(.busy) &&
                d.engine.handle(.chase(.preview)) == .rejected(.busy) && d.engine.activeRunCount==1
            checks[prefix+"IncomingVelocityContinuesWithoutStop"]=false
            var paused=false,resumed=false,captures=Set<String>()
            for tick in 0..<30*60 {
                if !accepted {break}
                advance();try record("tick",moving:true)
                if tick==0 {
                    checks[prefix+"IncomingVelocityContinuesWithoutStop"]=zip(incoming,velocities).allSatisfy {a,b in
                        let sa=Geometry.distance(.zero,a),sb=Geometry.distance(.zero,b)
                        return sb>=sa*0.65 && sb<=sa*1.35 && (a.x*b.x+a.y*b.y)/max(1,sa*sb)>0.9
                    }
                }
                let label=diverged ? "separated":(sharedTicks>=108 ? "shared-1.8s":(sharedTicks>=12 ? "converged":"joining"))
                if captures.insert(label).inserted {try record(label,crop:true)}
                if sharedTicks>=12 && !paused {
                    checks[prefix+"PauseFreezesModelsFramesAndLayers"]=try pauseEvidence();paused=true
                    let positions=birds.map(\.position)
                    advance();try record("resumed",crop:true,moving:true)
                    resumed=birds.map(\.position) != positions && terminals(run).isEmpty &&
                        birds.allSatisfy{d.engine.behavior(of:$0) == .travelTogether}
                }
                if !terminals(run).isEmpty {break}
            }
            try record("finished",crop:true)
            let ends=terminals(run)
            checks[prefix+"ConvergesAndFliesParallelForAtLeast1.8Seconds"]=accepted && longestSharedTicks>=108 &&
                minimumGap<initialGap-18*d.spriteScale(for:birds[0]) && frames.allSatisfy{$0.count>=2} && separated
            checks[prefix+"SeparatesAndLandsAtBothOriginalTargets"]=accepted && diverged && returned
            checks[prefix+"ContinuousFeetSpeedAndActualLayers"]=accepted && continuous && layersOK && anchorsOK
            checks[prefix+"OpaqueHitHoverAndTransparentPassThrough"]=accepted && hitsOK && transparentOK
            checks[prefix+"LivePointerSafeAndPopulationUnchanged"]=accepted && pointerOK && contained && populationOK
            checks[prefix+"PauseFreezesModelsFramesAndLayers"]=paused && (checks[prefix+"PauseFreezesModelsFramesAndLayers"] ?? false)
            checks[prefix+"ResumeContinuesSameRun"]=resumed
            checks[prefix+"CompletesOnceAndReleasesResources"]=accepted && ends.count==1 && ends.first?.type == .completed &&
                clearResources && slotsOK && samePopulation && birds.allSatisfy{d.engine.behavior(of:$0)==nil}
            summarize(accepted:accepted)
        }
        func waitForShared() throws -> Bool {
            for _ in 0..<12*60 {
                advance();try record("joining",probe:false,moving:true)
                if sharedTicks>=12 {return true}
                if !terminals(run).isEmpty {break}
            }
            return false
        }
        func click(_ index:Int,into checks:inout [String:Bool]) throws {
            fixture(.spottedDove,name:"click-member-\(index)")
            let fixtureOK=usableFixture && sameHeading,accepted=start(),shared=accepted ? try waitForShared():false
            try record("before-click",crop:true,probe:false)
            let feet=birds.map(\.position),clicked=birds[index],partner=birds[1-index],states=d.engine.renderSnapshot()
            let pixel=states.first{$0.id==ids[index]}.flatMap{pixelPoint($0,opaque:true,states:states)}
            let relocated=pixel.map{d.relocateBird(at:$0)} ?? false
            let replacement=d.engine.events.last{$0.kind == .relocate && $0.type == .started}?.runID
            let ends=terminals(run)
            checks["travelTogetherClickMember\(index)CancelsPairAtActualFeet"]=fixtureOK && accepted && shared && relocated &&
                birds.map(\.position)==feet && d.engine.behavior(of:clicked) == .relocate && d.engine.behavior(of:partner)==nil &&
                ends.count==1 && ends.first?.type == .cancelled && d.engine.activeRunCount==1 &&
                d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==0 && !d.engine.ambientBusy && samePopulation
            try record("click-cancelled",crop:true,probe:false)
            d.engine.autonomousRouting=true
            var recovered=false
            for _ in 0..<46*60 {
                advance();try record("recovery",probe:false,moving:true)
                if partner.state == .perched && !partner.needsDestination && !terminals(replacement).isEmpty {recovered=true;break}
            }
            checks["travelTogetherClickMember\(index)PartnerAndReplacementRecover"]=relocated && recovered &&
                clearResources && samePopulation && populationOK && anchorsOK && terminals(run).count==1 &&
                terminals(replacement).count==1 && terminals(replacement).first?.type == .completed
            try record("recovered",crop:true,probe:false);summarize(accepted:accepted,extra:["clickedID":ids[index].rawValue])
        }
        func interrupt(_ cause:String,into checks:inout [String:Bool]) throws {
            fixture(.blackCollaredStarling,name:cause)
            let fixtureOK=usableFixture && sameHeading,accepted=start(),shared=accepted ? try waitForShared():false
            try record("before-cancel",crop:true,probe:false)
            let feet=birds.map(\.position)
            if cause=="host-removed" {hostWindow.orderOut(nil);d.surfaces=[];d.syncWorld()}
            else {var settings=d.settings;settings.travelTogetherEnabled=false;d.settings=settings}
            let ends=terminals(run),expected:BehaviorReason=cause=="host-removed" ? .targetInvalid:.settingsChanged
            checks["travelTogetherSafeExit-"+cause]=fixtureOK && accepted && shared && birds.map(\.position)==feet &&
                ends.count==1 && ends.first?.type != .completed && ends.first?.reason==expected &&
                clearResources && samePopulation && birds.allSatisfy{d.engine.behavior(of:$0)==nil}
            try record("cancelled",crop:true,probe:false)
            // Restore a real host only after evidence of removal, then allow the
            // production routing path to recover from the current feet.
            if cause=="host-removed" {hostWindow.orderFrontRegardless();d.surfaces=[host]}
            d.engine.autonomousRouting=true
            var recovered=false
            for _ in 0..<46*60 {
                advance();try record("recovery",probe:false,moving:true)
                if birds.allSatisfy({$0.state == .perched && !$0.needsDestination}) {recovered=true;break}
            }
            checks["travelTogetherRecovery-"+cause]=accepted && recovered && clearResources && samePopulation &&
                populationOK && anchorsOK && terminals(run).count==1
            try record("recovered",crop:true,probe:false);summarize(accepted:accepted)
        }
        func reject(_ gate:String,into checks:inout [String:Bool]) throws {
            fixture(.spottedDove,name:"reject-"+gate,mode:gate)
            let ordinary=usableFixture
            if gate=="setting-disabled" {var settings=d.settings;settings.travelTogetherEnabled=false;d.settings=settings}
            if gate=="social-disabled" {var settings=d.settings;settings.socialInteractions=false;d.settings=settings}
            let feet=birds.map(\.position),revisions=birds.map(\.motionRevision),states=birds.map(\.state)
            let prerequisite:Bool
            if gate=="stationary" {prerequisite=birds.allSatisfy{$0.state == .perched && $0.flightSpeed==0}}
            else if gate=="opposite-directions" {prerequisite=ordinary && velocities[0].x*velocities[1].x<0}
            else {prerequisite=ordinary}
            let result=d.engine.handle(.travelTogether(.preview));events()
            let rejected:Bool
            if case .rejected(let reason)=result {rejected = gate.hasSuffix("disabled") ? reason == .disabled:true}
            else {rejected=false}
            checks["travelTogetherRejects-"+gate]=prerequisite && rejected && clearResources && samePopulation &&
                birds.map(\.position)==feet && birds.map(\.motionRevision)==revisions && birds.map(\.state)==states
            try record("rejected",crop:true,probe:false)
            summarize(accepted:false,extra:["gate":gate,"result":String(describing:result)])
        }
        func summarize(accepted:Bool,extra:[String:Any]=[:]) {
            var value:[String:Any]=["case":caseName,"accepted":accepted,"runID":run?.rawValue ?? 0,
                "birdIDs":ids.map(\.rawValue),"commandFeet":origins.map(Self.point),"originalTargets":targets.map(Self.point),
                "fractions":fractions,"hostID":host.id,"hostRect":NSStringFromRect(host.rect),"scale":d.scale,
                "scaleReduced":d.scale<1,"scaleReason":d.scale<1 ? "default fixture cannot fit route budget, display and live pointer exclusion":"default scale fits",
                "spriteScale":d.spriteScale(for:birds[0]),"routeEnvelope":NSStringFromRect(corridor),
                "requiredFixtureWidth":requiredFixtureWidth,"availableWorkWidth":work.width,
                "incomingLateralSeparation":incomingLateral,"fixtureMinimumLateralSeparation":140*d.spriteScale(for:birds[0]),
                "pointerSafetyMargin":100,"ordinaryFlightWarmupSeconds":0.65,"initialGap":initialGap,
                "longestSharedSeconds":Double(longestSharedTicks)*dt,"divergedBeforeLanding":diverged,
                "minimumGap":minimumGap == .greatestFiniteMagnitude ? -1:minimumGap,
                "maximumSpeedJumpPerTick":maximumSpeedJump,"maximumVelocityJumpPerTick":maximumVelocityJump,
                "flightFrames":frames.map{$0.sorted()},"terminalEvents":terminals(run).map{
                    ["type":$0.type.rawValue,"reason":$0.reason?.rawValue ?? ""]}]
            value.merge(extra){_,new in new};cases.append(value)
        }
        func writeReport(_ checks:[String:Bool]) throws {
            events();let own=checks.filter{$0.key.hasPrefix("travelTogether")}
            let report:[String:Any]=["milestone":"M5j","behavior":"B13","seed":String(d.engine.seed),
                "checks":own,"passed":own.values.allSatisfy{$0},"cases":cases,"artifacts":artifacts,
                "trajectoryFile":"travel-together-trajectory.json",
                "imageEvidence":"Actual BirdArt/DesktopView and real NSWindow layer crop composites; not desktop screenshots.",
                "input":"Live NSEvent pointer/buttons; no mouse warp. Pixel probes call production hit/hover/click routing.",
                "execution":"Isolated controller; fixed steps; no start/timers, user settings reads/writes, or preview spawning.",
                "sharedCriterion":"After convergence by 18 sprite points: both airborne, speed >60, heading dot >0.98, relative velocity <max(8,4% speed), continuously >=1.8s. Then both still airborne, parallel criterion ends and relative position vector changes by >18 sprite points before landing at distinct original targets.",
                "representativeSpecies":[SpeciesID.spottedDove.rawValue,SpeciesID.blackCollaredStarling.rawValue],
                "requestedSupportedSpecies":[SpeciesID.treeSparrow,.barnSwallow,.spottedDove,.lightVentedBulbul,
                    .azureWingedMagpie,.blackCollaredStarling].map(\.rawValue),
                "events":eventLog.values.sorted{$0.sequence<$1.sequence}.map {event -> [String:Any] in
                    ["sequence":event.sequence,"time":event.time,"runID":event.runID?.rawValue ?? 0,
                        "kind":event.kind?.rawValue ?? "none","source":event.source.rawValue,"type":event.type.rawValue,
                        "reason":event.reason?.rawValue ?? "","participants":event.participants.map(\.rawValue)]}]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
                .write(to:folder.appendingPathComponent("travel-together-report.json"),options:.atomic)
            try JSONSerialization.data(withJSONObject:["coordinateSystem":"Quartz desktop points; y increases downward",
                "samples":trajectory],options:[.prettyPrinted,.sortedKeys])
                .write(to:folder.appendingPathComponent("travel-together-trajectory.json"),options:.atomic)
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
        static func point(_ point:CGPoint) -> [CGFloat] {[point.x,point.y]}
        static func foot(_ layer:CALayer,state:BirdRenderState,display:CGRect) -> CGPoint {
            CGPoint(x:layer.frame.minX+display.minX+(state.facingRight ? 29:19)*state.scale,
                y:layer.frame.minY+display.minY+(39-state.hopOffset)*state.scale)
        }
        static func snapshot(_ view:DesktopView,hostView:NSView?,host:CGRect,display:CGRect,crop:CGRect,to url:URL) throws {
            guard !crop.isEmpty,let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(crop.width),
                pixelsHigh:Int(crop.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,
                colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else {
                throw NSError(domain:"TravelTogetherVerification",code:2)
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
                throw NSError(domain:"TravelTogetherVerification",code:3)
            }
            try png.write(to:url,options:.atomic)
        }
    }
}
