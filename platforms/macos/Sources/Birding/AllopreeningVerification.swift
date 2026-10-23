import AppKit
import BirdingCore

/// M5k / B12 native acceptance. Uses public engine output and actual BirdArt;
/// DesktopController.start(), user preferences and input injection are never used.
enum AllopreeningVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let evidence=folder.appendingPathComponent("allopreening-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        let h=try Harness(folder:evidence)
        defer {h.close()}
        checks["allopreeningEnabledByDefault"]=h.d.settings.allopreeningEnabled && h.d.settings.socialInteractions
        try h.complete(.barnSwallow,into:&checks)
        try h.complete(.swinhoesWhiteEye,mirrored:true,into:&checks)
        // Public preview can select either helper. Keep real observed attempts
        // instead of swapping identities or driving a private planner to force it.
        for attempt in 1...12 {
            if h.mirroredContactSeen {break}
            try h.complete(.swinhoesWhiteEye,mirrored:true,suffix:"-mirror-\(attempt)",into:&checks)
        }
        checks["allopreeningMirroredHelperOnRightFacesLeftAtContact"]=h.mirroredContactSeen
        for index in 0..<2 {try h.click(index,into:&checks)}
        for cause in ["host-removed","child-off","social-off","third-bird","missing-frames"] {
            try h.interrupt(cause,into:&checks)
        }
        try h.interrupt("host-removed",duringApproach:true,into:&checks)
        for gate in ["child-off","social-off","missing-frames","stationary-no-eligible",
                     "single-bird","different-species","airborne","unsupported-species","paused"] {
            try h.reject(gate,into:&checks)
        }
        checks["allopreeningNoTimersOrUserFileWrites"]=h.d.timer==nil && h.d.globalMouseMonitor==nil &&
            h.d.localMouseMonitor==nil && h.d.visitorMemoryPersistence==nil && !h.d.visitorMemoryPersistenceEnabled &&
            [h.d.settingsURL,h.d.legacyURL,h.d.visitorMemoryURL].allSatisfy {
                $0.deletingLastPathComponent()==evidence && !FileManager.default.fileExists(atPath:$0.path)
            } && h.d.engine.activeVisitorCount==0 && h.d.engine.rememberedVisitorCount==0
        checks["allopreeningFinalResourcesReleased"]=h.clearResources
        h.close()
        checks["allopreeningFixtureWindowsHiddenAfterRun"] = !h.overlay.isVisible && !h.hostWindow.isVisible
        try h.writeReport(checks)
        print("Allopreening native evidence: \(evidence.path)")
    }

    private final class Harness {
        let d:DesktopController
        let folder:URL,display:CGRect,work:CGRect
        let hostWindow:NSWindow,hostView:NSView,overlay:OverlayPanel,view:DesktopView
        let dt=1.0/60
        let give:Set<String>=["allopreenGive0","allopreenGive1","allopreenGive2"]
        let receive:Set<String>=["allopreenReceive0","allopreenReceive1","allopreenReceive2"]
        var host=Surface(id:0,rect:.zero),corridor=CGRect.zero,requestedHostRect=CGRect.zero
        var fixtureAudit:[String:Bool]=[:]
        var birds:[Bird]=[],ids:[BirdID]=[],origins:[CGPoint]=[],fractions:[CGFloat]=[]
        var expectedBirds:[Bird]=[],expectedIDs:[BirdID]=[],previous:[CGPoint]=[]
        var caseName="",run:BehaviorRunID?,helper:Int?
        var trajectory:[[String:Any]]=[],cases:[[String:Any]]=[],artifacts:[[String:Any]]=[]
        var eventLog:[UInt64:BehaviorEvent]=[:]
        var populationOK=true,pointerOK=true,layersOK=true,anchorsOK=true,continuous=true,contained=true,slotsOK=true
        var hitsOK=true,transparentOK=true,receiverFixed=true,contactFeetFixed=true
        var approached=false,retreated=false,approachHop=false,returnHop=false
        var contactTicks=0,longestContactTicks=0,totalContactTicks=0
        var giveFrames=Set<String>(),receiveFrames=Set<String>()
        var contactFeet:[CGPoint]?,minimumGap=CGFloat.greatestFiniteMagnitude,maximumStep:CGFloat=0
        var mirroredContactSeen=false

        init(folder:URL) throws {
            let d=DesktopController()
            guard let screen=NSScreen.screens.first,let display=d.displayRects.first,let work=d.screenRects.first else {
                throw NSError(domain:"AllopreeningVerification",code:1,
                    userInfo:[NSLocalizedDescriptionKey:"Native allopreening verification requires a display."])
            }
            d.settingsURL=folder.appendingPathComponent("unused-settings.json")
            d.legacyURL=folder.appendingPathComponent("unused-legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("unused-visitors.json")
            d.visitorMemoryPersistenceEnabled=false;d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            var settings=d.settings;settings.visitorMemoryEnabled=false;d.settings=settings
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
        var pairResources:Bool {
            d.engine.activeRunCount==1 && d.engine.leasedBirdCount==2 && d.engine.reservedLandingCount==1 &&
                d.engine.scenePropCount==0 && d.engine.ambientBusy &&
                birds.count==2 && birds.allSatisfy{d.engine.behavior(of:$0) == .allopreening}
        }
        var samePopulation:Bool {
            d.engine.birds.count==expectedBirds.count && expectedIDs.count==expectedBirds.count &&
                expectedBirds.enumerated().allSatisfy {i,bird in
                    d.engine.birds[i] === bird && d.engine.id(of:bird)==expectedIDs[i]
                } && d.residentCount==expectedBirds.count && d.engine.passingCount==0 &&
                d.engine.departingCount==0 && d.engine.pendingCount==0 && d.arrivalCount==0 && d.departureCount==0
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

        /// Pick a real window location using the live mouse. Its protection area
        /// covers both original perches, the hops and the receiver's full sprite.
        func fixture(_ species:SpeciesID,name:String,gap:CGFloat=125,mirrored:Bool=false) {
            d.paused=false;d.engine.handle(.cancelAmbient(.screensChanged));events()
            var settings=d.settings
            settings.allopreeningEnabled=true;settings.socialInteractions=true;settings.visitorMemoryEnabled=false
            settings.hoverDelay=0;settings.sideHopEnabled=false;settings.takeoffPreparationEnabled=false
            settings.edgePeekEnabled=false;d.settings=settings
            d.engine.autonomousRouting=false;d.hoverTracker=HoverTracker<BirdID>();d.hoveredBird=nil
            d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
            birds=(0..<2).map{_ in Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(species),random:{0.5})}
            d.scale=max(0.5,min(1,(work.width-32)/(600*birds[0].profile.relativeScale)))
            // NSWindow rounds frame dimensions to whole screen points. Submit
            // that exact size up front; bird spacing still uses the actual scale.
            let scale=d.spriteScale(for:birds[0]),width=(600*scale).rounded(.up),height:CGFloat=100
            func envelope(_ rect:CGRect) -> CGRect {
                CGRect(x:rect.midX-(gap/2+40)*scale,y:rect.minY-64*scale,
                    width:(gap+80)*scale,height:80*scale)
            }
            let candidates=[work.minX+16,work.maxX-width-16].flatMap {x in
                [work.minY+16+64*scale,work.maxY-height-16].map{y in
                    CGRect(x:x.rounded(),y:y.rounded(),width:width,height:height)
                }
            }
            func distance(_ rect:CGRect) -> CGFloat {
                let p=d.pointerPosition,r=envelope(rect)
                return hypot(max(0,max(r.minX-p.x,p.x-r.maxX)),max(0,max(r.minY-p.y,p.y-r.maxY)))
            }
            let feasible=candidates.filter{work.contains($0) && display.contains(envelope($0))}
            let rect=(feasible.isEmpty ? candidates:feasible).max{distance($0)<distance($1)} ?? .zero
            requestedHostRect=rect
            hostWindow.setFrame(Geometry.quartz(rect,primaryHeight:d.primaryHeight),display:true)
            hostView.frame=CGRect(origin:.zero,size:hostWindow.frame.size);hostView.layer?.frame=hostView.bounds
            hostWindow.orderFrontRegardless();overlay.orderFrontRegardless()
            host=Surface(id:UInt32(hostWindow.windowNumber),pid:ProcessInfo.processInfo.processIdentifier,
                rect:Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight))
            corridor=envelope(host.rect)
            let lo=Geometry.perchX(0,rect:host.rect),hi=Geometry.perchX(1,rect:host.rect)
            for (i,bird) in birds.enumerated() {
                let left=mirrored ? i==1:i==0
                bird.fraction=(host.rect.midX+(left ? -gap/2:gap/2)*scale-lo)/max(1,hi-lo)
                bird.facingRight=left;bird.perch(on:host,spriteScale:scale);bird.perchDuration=600;bird.tick(0.6)
            }
            d.surfaces=[host];d.birds=birds;d.syncWorld()
            ids=birds.compactMap{d.engine.id(of:$0)};expectedBirds=birds;expectedIDs=ids
            origins=birds.map(\.position);fractions=birds.map(\.fraction);previous=origins
            caseName=name;run=nil;helper=nil;contactFeet=nil
            populationOK=true;pointerOK=true;layersOK=true;anchorsOK=true;continuous=true;contained=true;slotsOK=true
            hitsOK=true;transparentOK=true;receiverFixed=true;contactFeetFixed=true
            approached=false;retreated=false;approachHop=false;returnHop=false
            contactTicks=0;longestContactTicks=0;totalContactTicks=0;giveFrames=[];receiveFrames=[]
            minimumGap = .greatestFiniteMagnitude;maximumStep=0
            fixtureAudit=fixtureConditions
        }
        var fixtureConditions:[String:Bool] {
            let pair=birds.count==2 && ids.count==2
            return ["samePopulation":samePopulation,"twoBirds":pair,
                "visibleRealWindow":hostWindow.isVisible && !host.isGround && host.id==UInt32(hostWindow.windowNumber),
                "surfaceMatchesWindow":host.rect==Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight),
                "windowMatchesRequestedFrame":host.rect==requestedHostRect,
                "widthIs600ScaleRoundedUp":pair && host.rect.width==(600*d.spriteScale(for:birds[0])).rounded(.up),
                "heightIs100":host.rect.height==100,
                "spanInsideDisplay":display.contains(corridor),
                "livePointerOutsideSpan":!corridor.insetBy(dx:-100,dy:-100).contains(d.pointerPosition),
                "mouseButtonsReleased":!d.engine.world.buttonsDown,
                "settledOnHost":pair && birds.allSatisfy {
                    $0.state == .perched && $0.stateTime>=0.45 && $0.edge == .top && $0.hostID==host.id &&
                        (0...1).contains($0.fraction) && !$0.needsDestination
                },"sameSpecies":pair && birds[0].profile.id==birds[1].profile.id]
        }
        var usableFixture:Bool {fixtureConditions.values.allSatisfy{$0}}
        @discardableResult func start() -> Bool {
            d.syncWorld();let sequence=d.engine.events.last?.sequence ?? 0
            let result=d.engine.handle(.allopreening(.preview));events()
            run=d.engine.events.last{$0.sequence>sequence && $0.kind == .allopreening && $0.type == .started}?.runID
            return result.accepted && run != nil
        }
        var returned:Bool {
            birds.enumerated().allSatisfy {i,bird in
                bird.state == .perched && bird.hostID==host.id && bird.edge == .top &&
                    Geometry.distance(bird.position,origins[i])<0.001 && abs(bird.fraction-fractions[i])<0.000001
            }
        }
        func isContact(_ states:[BirdRenderState]) -> Bool {
            guard birds.count==2,let a=states.first(where:{$0.id==ids[0]}),
                  let b=states.first(where:{$0.id==ids[1]}) else {return false}
            return ((give.contains(a.frameName) && receive.contains(b.frameName)) ||
                (receive.contains(a.frameName) && give.contains(b.frameName))) &&
                abs(Geometry.distance(a.position,b.position)-24*a.scale)<=a.scale &&
                birds.allSatisfy{$0.state == .perched && d.engine.behavior(of:$0) == .allopreening}
        }

        /// Only integration samples contribute duration. Extra rendering, paused
        /// evidence and hover probes must never inflate the three-second hold.
        func record(_ label:String,crop:Bool=false,probe:Bool=false,integrated:Bool=false) throws {
            view.updateSprites();events()
            let states=d.engine.renderSnapshot(),layers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            populationOK = populationOK && samePopulation
            let protected=corridor.insetBy(dx:-100,dy:-100)
            pointerOK = pointerOK && !protected.contains(d.pointerPosition) && !protected.contains(d.engine.world.pointer) &&
                !d.engine.world.buttonsDown
            layersOK = layersOK && states.count==expectedBirds.count && layers.count==states.count
            let paired=birds.count==2 && birds.allSatisfy{d.engine.behavior(of:$0) == .allopreening}
            if paired {slotsOK = slotsOK && pairResources}
            var members:[[String:Any]]=[]
            for (i,bird) in birds.enumerated() {
                guard i<ids.count,let index=states.firstIndex(where:{$0.id==ids[i]}),index<layers.count,
                      let texture=layers[index].sublayers?.first,let art=d.arts[states[index].species],
                      let image=art.frames[states[index].frameName] else {layersOK=false;anchorsOK=false;continue}
                let state=states[index],layer=layers[index],foot=Self.foot(layer,state:state,display:display)
                let expectedFrame=state.rect.offsetBy(dx:-display.minX,dy:-display.minY)
                let geometryMatches=Self.layerGeometryMatches(layer,frame:expectedFrame)
                let imageMatches=(texture.contents as AnyObject?) === image
                let transformMatches=texture.affineTransform()==CGAffineTransform(scaleX:state.facingRight ? 1:-1,y:1)
                let footError=Geometry.distance(foot,bird.position)
                layersOK = layersOK && !layer.isHidden && imageMatches && transformMatches && geometryMatches
                anchorsOK = anchorsOK && footError<0.001 && state.position==bird.position
                if paired {contained = contained && display.contains(state.rect) && corridor.contains(state.rect)}
                let step=Geometry.distance(previous[i],bird.position)
                maximumStep=max(maximumStep,step);continuous = continuous && step<max(20,18*state.scale)
                previous[i]=bird.position
                if paired && helper==nil && Geometry.distance(bird.position,origins[i])>0.01 {helper=i}
                if probe {
                    if let point=pixelPoint(state,opaque:true,states:states) {
                        hitsOK = hitsOK && d.bird(at:point) === bird && state.hoverable
                        d.updateHover(now:d.engine.time,at:point);hitsOK = hitsOK && d.hoveredBird === bird
                        view.updateSprites()
                        hitsOK = hitsOK && (view.layer?.sublayers?.contains{($0 as? CATextLayer)?.isHidden == false} ?? false)
                        d.hoverTracker=HoverTracker<BirdID>();d.hoveredBird=nil
                    } else {hitsOK=false}
                    if let point=pixelPoint(state,opaque:false,states:states) {
                        let sequence=d.engine.events.last?.sequence
                        transparentOK = transparentOK && d.bird(at:point)==nil && !d.relocateBird(at:point) &&
                            d.engine.events.last?.sequence==sequence && overlay.ignoresMouseEvents && !overlay.canBecomeKey
                    } else {transparentOK=false}
                }
                members.append(["id":state.id.rawValue,"species":state.species.rawValue,"state":bird.state.rawValue,
                    "frame":state.frameName,"position":Self.point(bird.position),"fraction":bird.fraction,
                    "layerFoot":Self.point(foot),"layerFrame":NSStringFromRect(layer.frame),"hopOffset":state.hopOffset,
                    "expectedLayerFrame":NSStringFromRect(expectedFrame),"layerBounds":NSStringFromRect(layer.bounds),
                    "layerPosition":Self.point(layer.position),"footError":footError,"scale":state.scale,
                    "stateTime":bird.stateTime,"needsDestination":bird.needsDestination,"hostID":bird.hostID.map{Int($0)} ?? -1,
                    "layerChecks":["visible":!layer.isHidden,"image":imageMatches,"transform":transformMatches,
                        "geometry":geometryMatches,"snapshotFoot":state.position==bird.position,"anchor":footError<0.001],
                    "facingRight":state.facingRight,"hoverable":state.hoverable,"motionRevision":bird.motionRevision,
                    "behavior":d.engine.behavior(of:bird)?.rawValue ?? "none"])
            }
            let contact=isContact(states)
            if paired,let helper {
                let receiver=1-helper,scale=d.spriteScale(for:birds[helper])
                let gap=Geometry.distance(birds[0].position,birds[1].position)
                minimumGap=min(minimumGap,gap)
                receiverFixed = receiverFixed && Geometry.distance(birds[receiver].position,origins[receiver])<0.001 &&
                    abs(birds[receiver].fraction-fractions[receiver])<0.000001 && birds[receiver].state == .perched
                if gap<100*scale {approached=true}
                let hop=birds[helper].state == .flying && birds[helper].position.y<origins[helper].y-scale &&
                    ["land0","stand"].contains(birds[helper].frameName)
                if totalContactTicks==0 {approachHop = approachHop || hop}
                else if !contact && gap>30*scale {retreated=true;returnHop = returnHop || hop}
                if contact {
                    if contactFeet==nil {contactFeet=birds.map(\.position)}
                    contactFeetFixed = contactFeetFixed && birds.map(\.position)==contactFeet
                    if let giver=states.first(where:{$0.id==ids[helper]}),let recipient=states.first(where:{$0.id==ids[receiver]}) {
                        contactFeetFixed = contactFeetFixed && give.contains(giver.frameName) && receive.contains(recipient.frameName)
                        giveFrames.insert(giver.frameName);receiveFrames.insert(recipient.frameName)
                        if give.contains(giver.frameName) && receive.contains(recipient.frameName) &&
                            giver.position.x>recipient.position.x && !giver.facingRight && recipient.facingRight {
                            mirroredContactSeen=true
                        }
                    }
                }
            }
            if integrated && !d.paused {
                if contact {contactTicks+=1;totalContactTicks+=1;longestContactTicks=max(longestContactTicks,contactTicks)}
                else {contactTicks=0}
            }
            trajectory.append(["case":caseName,"label":label,"time":d.engine.time,"runID":run?.rawValue ?? 0,
                "integrated":integrated,"paused":d.paused,"contact":contact,"contactSeconds":Double(contactTicks)*dt,
                "pointer":Self.point(d.pointerPosition),"worldPointer":Self.point(d.engine.world.pointer),
                "buttonsDown":d.engine.world.buttonsDown,"activeRuns":d.engine.activeRunCount,
                "leases":d.engine.leasedBirdCount,"reservations":d.engine.reservedLandingCount,
                "population":d.engine.birds.count,"hostWindowVisible":hostWindow.isVisible,"members":members])
            if crop {
                d.hoveredBird=nil;view.updateSprites()
                let name=caseName+"-"+label+"-layer-composite.png"
                let area=states.reduce(corridor){$0.union($1.rect)}.insetBy(dx:-16,dy:-32).intersection(display).integral
                try Self.snapshot(view,hostView:hostWindow.isVisible ? hostView:nil,host:host.rect,
                    display:display,crop:area,to:folder.appendingPathComponent(name))
                artifacts.append(["file":name,"case":caseName,"label":label,"time":d.engine.time,
                    "kind":"native-layer-crop-composite; not a desktop screenshot","crop":NSStringFromRect(area)])
            }
        }

        func pauseEvidence() throws -> Bool {
            d.paused=true;view.updateSprites()
            let before=d.engine.renderSnapshot(),positions=birds.map(\.position),ages=birds.map(\.stateTime)
            let revisions=birds.map(\.motionRevision),placements=birds.map(\.fraction),kinds=birds.map(\.state)
            let sequence=d.engine.events.last?.sequence
            let layers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            let rects=layers.map(\.frame),images=layers.map{$0.sublayers?.first?.contents as AnyObject?}
            let transforms=layers.map{$0.sublayers?.first?.affineTransform()}
            advance(60);view.updateSprites()
            let after=d.engine.renderSnapshot(),afterLayers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            let frozen=before.count==2 && after.count==2 && layers.count==2 && afterLayers.count==2 &&
                birds.map(\.position)==positions && birds.map(\.stateTime)==ages && birds.map(\.motionRevision)==revisions &&
                birds.map(\.fraction)==placements && birds.map(\.state)==kinds &&
                zip(before,after).allSatisfy{$0.id==$1.id && $0.frameName==$1.frameName && $0.rect==$1.rect &&
                    $0.facingRight==$1.facingRight && $0.hopOffset==$1.hopOffset} &&
                afterLayers.enumerated().allSatisfy {i,layer in
                    layer.frame==rects[i] && images[i] != nil && (layer.sublayers?.first?.contents as AnyObject?) === images[i] &&
                        layer.sublayers?.first?.affineTransform()==transforms[i]
                } && d.engine.events.last?.sequence==sequence && pairResources && terminals(run).isEmpty
            try record("paused-contact",crop:true);d.paused=false
            return frozen
        }
        func complete(_ species:SpeciesID,mirrored:Bool=false,suffix:String="",into checks:inout [String:Bool]) throws {
            fixture(species,name:species.rawValue+"-complete"+suffix,mirrored:mirrored)
            let prefix="allopreening-"+species.rawValue+suffix
            let scale=d.spriteScale(for:birds[0])
            checks[prefix+"RealWindowSettledPairLivePointer"]=usableFixture &&
                abs(Geometry.distance(origins[0],origins[1])-125*scale)<0.001
            checks[prefix+"UsesActualCompleteArtManifest"]=give.union(receive).isSubset(of:d.frameCapabilities[species] ?? []) &&
                d.frameCapabilities[species]==d.arts[species].map{Set($0.frames.keys)}
            try record("settled",crop:true,probe:true)
            let accepted=start(),event=d.engine.events.last{$0.runID==run && $0.type == .started}
            checks[prefix+"TwoExistingBirdsOneSpanReservation"]=accepted && samePopulation && pairResources &&
                Set(event?.participants ?? [])==Set(ids) && event?.source == .preview && birds.map(\.position)==origins
            let feet=birds.map(\.position),ages=birds.map(\.stateTime),revisions=birds.map(\.motionRevision)
            for _ in 0..<3 {d.syncWorld();view.updateSprites();_ = d.engine.renderSnapshot()}
            checks[prefix+"RenderingDoesNotAdvanceMotion"]=accepted && birds.map(\.position)==feet &&
                birds.map(\.stateTime)==ages && birds.map(\.motionRevision)==revisions
            checks[prefix+"SharesEncounterBudget"]=accepted && d.engine.handle(.allopreening(.preview)) == .rejected(.busy) &&
                d.engine.handle(.chase(.preview)) == .rejected(.busy) && pairResources
            var paused=false,resumed=false,captures=Set<String>()
            for _ in 0..<16*60 {
                if !accepted {break}
                advance();try record("tick",integrated:true)
                let label=retreated ? "return-hop":(contactTicks>0 ? "contact":(approached ? "approach-hop":"starting"))
                if captures.insert(label).inserted {try record(label,crop:true,probe:true)}
                if contactTicks>=12 && !paused {
                    checks[prefix+"PauseFreezesModelsFramesAndLayers"]=try pauseEvidence();paused=true
                    advance();try record("resumed-contact",crop:true,integrated:true)
                    resumed=pairResources && isContact(d.engine.renderSnapshot()) && terminals(run).isEmpty
                }
                if contactTicks>=180 && captures.insert("contact-at-least-3s").inserted {
                    try record("contact-at-least-3s",crop:true,probe:true)
                }
                if !terminals(run).isEmpty {break}
            }
            try record("finished",crop:true,probe:true)
            let ends=terminals(run)
            checks[prefix+"HelperApproachesWithActualSideHop"]=accepted && approached && approachHop && helper != nil
            checks[prefix+"PairedContactAt24ScaleForAtLeast3Seconds"]=accepted && longestContactTicks>=180 &&
                Double(totalContactTicks)*dt<=4.2 && giveFrames==give && receiveFrames==receive && contactFeetFixed
            checks[prefix+"ReceiverKeepsOriginalFootAndFraction"]=accepted && receiverFixed && totalContactTicks>0
            checks[prefix+"HelperSeparatesWithSideHopAndBothReturnToOriginalFractions"]=accepted && retreated && returnHop && returned
            checks[prefix+"ContinuousMotionActualFramesAndLayerFootAnchors"]=accepted && continuous && anchorsOK && layersOK
            checks[prefix+"OpaqueHitHoverAndTransparentPassThrough"]=accepted && hitsOK && transparentOK
            checks[prefix+"LivePointerClearsWholeSpanAndPopulationUnchanged"]=accepted && pointerOK && contained && populationOK && samePopulation
            checks[prefix+"PauseFreezesModelsFramesAndLayers"]=paused && (checks[prefix+"PauseFreezesModelsFramesAndLayers"] ?? false)
            checks[prefix+"ResumeContinuesSameRun"]=resumed
            checks[prefix+"CompletesOnceAndReleasesPairAndSpan"]=accepted && ends.count==1 && ends.first?.type == .completed &&
                clearResources && slotsOK && birds.allSatisfy{d.engine.behavior(of:$0)==nil}
            summarize(accepted:accepted,extra:["fixtureAnchorOrderMirrored":mirrored])
        }
        func waitForContact(approach:Bool=false) throws -> Bool {
            for _ in 0..<8*60 {
                advance();try record("waiting",integrated:true)
                if approach ? approachHop:isContact(d.engine.renderSnapshot()) {return true}
                if !terminals(run).isEmpty {break}
            }
            return false
        }
        func click(_ index:Int,into checks:inout [String:Bool]) throws {
            fixture(index==0 ? .barnSwallow:.swinhoesWhiteEye,name:"click-member-\(index)")
            let fixtureOK=usableFixture,accepted=start(),contact=accepted ? try waitForContact():false
            try record("before-click",crop:true,probe:true)
            let feet=birds.map(\.position),clicked=birds[index],partner=birds[1-index],sequence=d.engine.events.last?.sequence ?? 0
            let states=d.engine.renderSnapshot()
            let pixel=states.first{$0.id==ids[index]}.flatMap{pixelPoint($0,opaque:true,states:states)}
            let relocated=pixel.map{d.relocateBird(at:$0)} ?? false
            events()
            let replacement=d.engine.events.last{$0.sequence>sequence && $0.kind == .relocate && $0.type == .started}
            let ends=terminals(run)
            checks["allopreeningClickMember\(index)CancelsPairBeforeRelocateAtActualFeet"]=fixtureOK && accepted && contact && relocated &&
                birds.map(\.position)==feet && ends.count==1 && ends.first?.type == .cancelled &&
                (ends.first?.sequence ?? UInt64.max)<(replacement?.sequence ?? 0) &&
                d.engine.behavior(of:clicked) == .relocate && d.engine.behavior(of:partner)==nil && samePopulation &&
                d.engine.activeRunCount==1 && d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==0 && !d.engine.ambientBusy
            try record("click-cancelled",crop:true)
            d.engine.autonomousRouting=true
            var recovered=false,ordinary=true,moved=false
            for _ in 0..<46*60 {
                advance();try record("recovery",integrated:true)
                ordinary = ordinary && d.engine.behavior(of:partner)==nil && terminals(run).count==1
                moved = moved || Geometry.distance(clicked.position,feet[index])>1
                if partner.state == .perched && !partner.needsDestination && !terminals(replacement?.runID).isEmpty {recovered=true;break}
            }
            let replacementEnds=terminals(replacement?.runID)
            checks["allopreeningClickMember\(index)PartnerOrdinaryRecoveryAndReplacementCleanup"]=relocated && recovered && ordinary && moved &&
                clearResources && samePopulation && populationOK && continuous && anchorsOK && layersOK &&
                replacementEnds.count==1 && replacementEnds.first?.type == .completed
            try record("recovered",crop:true)
            summarize(accepted:accepted,extra:["clickedID":ids[index].rawValue,"replacementRun":replacement?.runID?.rawValue ?? 0])
        }
        func interrupt(_ cause:String,duringApproach:Bool=false,into checks:inout [String:Bool]) throws {
            fixture(.barnSwallow,name:cause+(duringApproach ? "-approach":"-contact"))
            let fixtureOK=usableFixture,accepted=start(),ready=accepted ? try waitForContact(approach:duringApproach):false
            try record("before-cancel",crop:true)
            let feet=birds.map(\.position)
            var thirdInReturnSpan=false
            switch cause {
            case "host-removed":hostWindow.orderOut(nil);d.surfaces=[];d.syncWorld()
            case "child-off":var value=d.settings;value.allopreeningEnabled=false;d.settings=value
            case "social-off":var value=d.settings;value.socialInteractions=false;d.settings=value
            case "third-bird":
                // Occupy the helper's original perch, away from the contact pair:
                // cancellation here exercises the complete return-span protection.
                let index=helper ?? 0,scale=d.spriteScale(for:birds[0])
                let third=Bird(position:origins[index],fraction:fractions[index],profile:d.catalog.profile(.barnSwallow),random:{0.5})
                third.perch(on:host,spriteScale:scale);third.perchDuration=600;third.tick(0.6)
                thirdInReturnSpan=corridor.contains(third.position) && birds.allSatisfy{Geometry.distance($0.position,third.position)>48*scale}
                d.birds=birds+[third];expectedBirds=birds+[third];expectedIDs=expectedBirds.compactMap{d.engine.id(of:$0)}
                d.syncWorld()
            default:
                // Remove a real required frame from the manifest, never fabricate
                // a capability that is absent from the production renderer.
                d.frameCapabilities[.barnSwallow]?.remove("allopreenGive1");d.syncWorld()
            }
            events();let ends=terminals(run)
            let expected:BehaviorReason?=cause=="host-removed" ? .targetInvalid:
                (cause=="missing-frames" ? .missingFrames:(cause=="third-bird" ? nil:.settingsChanged))
            checks["allopreeningSafeExit-"+caseName]=fixtureOK && accepted && ready && birds.map(\.position)==feet &&
                ends.count==1 && ends.first?.type != .completed && (expected==nil || ends.first?.reason==expected) &&
                clearResources && samePopulation && birds.allSatisfy{d.engine.behavior(of:$0)==nil} &&
                (cause != "third-bird" || thirdInReturnSpan)
            try record("cancelled",crop:true)
            d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
            if cause=="host-removed" {hostWindow.orderFrontRegardless();d.surfaces=[host]}
            d.engine.autonomousRouting=true
            var recovered=false
            for _ in 0..<46*60 {
                advance();try record("recovery",integrated:true)
                if birds.allSatisfy({$0.state == .perched && !$0.needsDestination}) {recovered=true;break}
            }
            checks["allopreeningRecovery-"+caseName]=accepted && recovered && clearResources && populationOK && samePopulation &&
                continuous && anchorsOK && layersOK && terminals(run).count==1 && birds.allSatisfy{d.engine.behavior(of:$0)==nil}
            try record("recovered",crop:true)
            summarize(accepted:accepted,extra:["cause":cause,"thirdInOriginalReturnSpan":thirdInReturnSpan])
        }
        func reject(_ gate:String,into checks:inout [String:Bool]) throws {
            fixture(gate=="unsupported-species" ? .treeSparrow:.swinhoesWhiteEye,
                name:"reject-"+gate,gap:gate=="stationary-no-eligible" ? 300:125)
            let fixtureOK=usableFixture
            switch gate {
            case "child-off":var value=d.settings;value.allopreeningEnabled=false;d.settings=value
            case "social-off":var value=d.settings;value.socialInteractions=false;d.settings=value
            case "missing-frames":d.frameCapabilities[.swinhoesWhiteEye]?.remove("allopreenReceive2")
            case "single-bird":birds=Array(birds.prefix(1))
            case "different-species":
                let other=Bird(position:origins[1],fraction:fractions[1],profile:d.catalog.profile(.barnSwallow),random:{0.5})
                other.perch(on:host,spriteScale:d.spriteScale(for:other));other.perchDuration=600;other.tick(0.6);birds[1]=other
            case "airborne":
                for bird in birds {
                    bird.fly(to:CGPoint(x:bird.position.x+60,y:bird.position.y-50),host:host,duration:3,allowsOrbit:false,random:{0.5})
                }
            case "paused":d.paused=true
            default:break
            }
            d.birds=birds;ids=birds.compactMap{d.engine.id(of:$0)};expectedBirds=birds;expectedIDs=ids
            previous=birds.map(\.position);d.syncWorld()
            let feet=birds.map(\.position),revisions=birds.map(\.motionRevision),placements=birds.map(\.fraction)
            let ages=birds.map(\.stateTime),kinds=birds.map(\.state),sequence=d.engine.events.last?.sequence ?? 0
            let result=d.engine.handle(.allopreening(.preview));events()
            let rejected:Bool
            if case .rejected(let reason)=result {
                if gate=="child-off" || gate=="social-off" {rejected=reason == .disabled}
                else if gate=="missing-frames" {rejected=reason == .missingFrames}
                else if gate=="paused" {rejected=reason == .paused}
                else {rejected=true}
            } else {rejected=false}
            let noStart = !d.engine.events.contains{$0.sequence>sequence && $0.kind == .allopreening && $0.type == .started}
            checks["allopreeningRejects-"+gate]=fixtureOK && rejected && noStart && clearResources && samePopulation &&
                birds.map(\.position)==feet && birds.map(\.motionRevision)==revisions && birds.map(\.fraction)==placements &&
                birds.map(\.stateTime)==ages && birds.map(\.state)==kinds
            try record("rejected",crop:true);d.paused=false
            summarize(accepted:false,extra:["gate":gate,"result":String(describing:result),
                "stationaryMeaning":"Settled same-species pair 300 sprite points apart has no eligible adjacent companion."])
        }

        /// Evaluate every sprite's actual alpha at this desktop point. A partner's
        /// overlapping bitmap rectangle does not make its transparent pixels solid.
        func opaque(_ state:BirdRenderState,at point:CGPoint) -> Bool {
            guard state.rect.contains(point),!state.blockers.contains(where:{$0.contains(point)}),let art=d.arts[state.species] else {return false}
            let x=Int((point.x-state.rect.minX)/state.scale),y=Int((point.y-state.rect.minY)/state.scale)
            return art.contains(frame:state.frameName,x:state.facingRight ? x:47-x,y:y)
        }
        func pixelPoint(_ state:BirdRenderState,opaque wanted:Bool,states:[BirdRenderState]) -> CGPoint? {
            guard let art=d.arts[state.species] else {return nil}
            for pixel in 0..<48*48 where art.contains(frame:state.frameName,x:pixel%48,y:pixel/48)==wanted {
                let x=state.facingRight ? pixel%48:47-pixel%48
                let point=CGPoint(x:state.rect.minX+(CGFloat(x)+0.5)*state.scale,
                    y:state.rect.minY+(CGFloat(pixel/48)+0.5)*state.scale)
                guard !state.blockers.contains(where:{$0.contains(point)}) else {continue}
                let top=states.reversed().first{opaque($0,at:point)}
                if wanted ? top?.id==state.id:top==nil {return point}
            }
            return nil
        }
        func summarize(accepted:Bool,extra:[String:Any]=[:]) {
            var value:[String:Any]=["case":caseName,"accepted":accepted,"runID":run?.rawValue ?? 0,
                "birdIDs":ids.map(\.rawValue),"origins":origins.map(Self.point),"fractions":fractions,
                "helperID":helper.flatMap{$0<ids.count ? ids[$0].rawValue:nil} ?? 0,
                "hostID":host.id,"hostRect":NSStringFromRect(host.rect),"scale":d.scale,
                "requestedHostRect":NSStringFromRect(requestedHostRect),"fixtureChecks":fixtureAudit,
                "spriteScale":birds.first.map{d.spriteScale(for:$0)} ?? 0,"protectedSpan":NSStringFromRect(corridor),
                "pointerSafetyMargin":100,"longestContactSeconds":Double(longestContactTicks)*dt,
                "totalContactSeconds":Double(totalContactTicks)*dt,"giveFrames":giveFrames.sorted(),"receiveFrames":receiveFrames.sorted(),
                "minimumGap":minimumGap == .greatestFiniteMagnitude ? -1:minimumGap,"maximumStep":maximumStep,
                "invariants":["population":populationOK,"pointer":pointerOK,"layers":layersOK,"anchors":anchorsOK,
                    "continuous":continuous,"contained":contained,"resources":slotsOK,"opaqueHits":hitsOK,
                    "transparentPassThrough":transparentOK,"receiverFixed":receiverFixed,"contactFeetFixed":contactFeetFixed],
                "terminalEvents":terminals(run).map{["type":$0.type.rawValue,"reason":$0.reason?.rawValue ?? ""]}]
            value.merge(extra){_,new in new};cases.append(value)
        }
        func writeReport(_ checks:[String:Bool]) throws {
            events();let own=checks.filter{$0.key.hasPrefix("allopreening")}
            let report:[String:Any]=["milestone":"M5k","behavior":"B12","seed":String(d.engine.seed),
                "checks":own,"passed":own.values.allSatisfy{$0},"cases":cases,"artifacts":artifacts,
                "trajectoryFile":"allopreening-trajectory.json",
                "representativeSpecies":[SpeciesID.barnSwallow.rawValue,SpeciesID.swinhoesWhiteEye.rawValue],
                "imageEvidence":"Actual BirdArt/DesktopView and real NSWindow layer crop composites; not desktop screenshots.",
                "input":"Live NSEvent mouse/buttons; no warp. Direct production pixel hit/hover/relocate probes.",
                "execution":"Isolated settings and visitors; fixed steps, no start/timer/settings file load or save.",
                "contactCriterion":"Complementary Give/Receive 0...2 poses at 24 sprite-point foot spacing, both perched, receiver anchored; >=3 continuous simulated seconds excluding pause and extra render samples; <=4.2 seconds total.",
                "artBoundary":"Bitmap rectangles may overlap during contact. Contact pixels and independent bodies are checked by ArtVerifier.",
                "spanEvidence":"Exactly two leases and one reservation; a third bird at the helper's original perch cancels the pair while >48 sprite points away from both contact feet.",
                "events":eventLog.values.sorted{$0.sequence<$1.sequence}.map{event -> [String:Any] in
                    ["sequence":event.sequence,"time":event.time,"runID":event.runID?.rawValue ?? 0,
                        "kind":event.kind?.rawValue ?? "none","source":event.source.rawValue,"type":event.type.rawValue,
                        "reason":event.reason?.rawValue ?? "","participants":event.participants.map(\.rawValue)]
                }]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
                .write(to:folder.appendingPathComponent("allopreening-report.json"),options:.atomic)
            try JSONSerialization.data(withJSONObject:["coordinateSystem":"Quartz desktop points; y increases downward",
                "samples":trajectory],options:[.prettyPrinted,.sortedKeys])
                .write(to:folder.appendingPathComponent("allopreening-trajectory.json"),options:.atomic)
        }
        static func point(_ point:CGPoint) -> [CGFloat] {[point.x,point.y]}
        /// CALayer stores bounds and center, then reconstructs frame.origin on
        /// read. At fractional sprite scales that round trip changes an origin
        /// by an ULP. Check the stored geometry exactly instead of weakening the
        /// comparison with a pixel tolerance; foot-anchor tolerance is unchanged.
        static func layerGeometryMatches(_ layer:CALayer,frame:CGRect) -> Bool {
            layer.bounds==CGRect(origin:.zero,size:frame.size) &&
                layer.position==CGPoint(x:frame.midX,y:frame.midY) &&
                layer.anchorPoint==CGPoint(x:0.5,y:0.5) && layer.affineTransform()==CGAffineTransform.identity
        }
        static func foot(_ layer:CALayer,state:BirdRenderState,display:CGRect) -> CGPoint {
            CGPoint(x:layer.frame.minX+display.minX+(state.facingRight ? 29:19)*state.scale,
                y:layer.frame.minY+display.minY+(39-state.hopOffset)*state.scale)
        }
        static func snapshot(_ view:DesktopView,hostView:NSView?,host:CGRect,display:CGRect,crop:CGRect,to url:URL) throws {
            guard !crop.isEmpty,let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(crop.width),
                pixelsHigh:Int(crop.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,
                colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else {
                throw NSError(domain:"AllopreeningVerification",code:2)
            }
            view.layoutSubtreeIfNeeded();hostView?.layoutSubtreeIfNeeded();view.displayIfNeeded();hostView?.displayIfNeeded()
            let ctx=graphics.cgContext
            ctx.setFillColor(NSColor(calibratedWhite:0.22,alpha:1).cgColor);ctx.fill(CGRect(origin:.zero,size:crop.size))
            ctx.translateBy(x:-crop.minX,y:crop.maxY);ctx.scaleBy(x:1,y:-1)
            if let hostView {
                ctx.saveGState();ctx.translateBy(x:host.minX,y:host.maxY);ctx.scaleBy(x:1,y:-1)
                hostView.layer?.render(in:ctx);ctx.restoreGState()
            }
            ctx.translateBy(x:display.minX,y:display.minY);view.layer?.render(in:ctx)
            guard let png=bitmap.representation(using:.png,properties:[:]) else {
                throw NSError(domain:"AllopreeningVerification",code:3)
            }
            try png.write(to:url,options:.atomic)
        }
    }
}
