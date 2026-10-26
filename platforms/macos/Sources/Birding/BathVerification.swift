import AppKit
import BirdingCore

/// Main owns the CLI. Every visit below is a production placement + preview
/// command using existing fixture residents, actual art and DesktopView layers.
enum BathVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("bath-native-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        checks["bathNativeCompleted"]=false
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("bath")},"visits":evidence,
            "limits":"Native layers on the attached display, with synthetic host geometry. Physical display hotplug and long desktop sessions require separate acceptance."],to:output.appendingPathComponent("report.json"))}
        try BathArtVerification.run(into:&checks,folder:output)
        let f=try Fixture(folder:output)
        defer {f.close()}
        for species:SpeciesID in [.treeSparrow,.lightVentedBulbul] {
            for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
                try visit(f,species:species,scale:scale,right:right,into:&checks,evidence:&evidence,folder:output)
            }}
        }
        try interruptions(f,into:&checks,evidence:&evidence,folder:output)
        checks["bathNativeNoDesktopStartupOrPersistence"]=f.d.timer==nil && f.d.globalMouseMonitor==nil && f.d.localMouseMonitor==nil &&
            f.d.panels.isEmpty && f.d.views.isEmpty && !f.d.automaticPopulation &&
            !FileManager.default.fileExists(atPath:f.d.settingsURL.path) &&
            !FileManager.default.fileExists(atPath:f.d.visitorMemoryURL.path) &&
            !FileManager.default.fileExists(atPath:f.d.observationJournalURL.path)
        checks["bathNativeCompleted"]=true
    }

    private final class Fixture {
        let d:DesktopController,window:OverlayPanel,view:DesktopView,work:CGRect,display:CGRect
        let suite:String,preferences:UserDefaults
        let settings:SpeciesSettingsWindow
        var host:Surface!,target=CGPoint.zero,origin=CGPoint.zero
        init(folder:URL) throws {
            let d=DesktopController();self.d=d
            guard let screen=NSScreen.screens.first,let work=d.screenRects.first,let display=d.displayRects.first,
                  work.width>=800,work.height>=580 else {throw failure("Bath native verification requires an 800 × 580 work area")}
            self.work=work;self.display=display
            suite="Birding.BathVerification."+UUID().uuidString
            guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate native preferences")}
            self.preferences=preferences;d.preferences=preferences
            d.automaticPopulation=false;d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            d.pointerButtonsDown={false};d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false
            d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("visitors.json");d.observationJournalURL=folder.appendingPathComponent("journal.json")
            var value=d.settings;value.perchActions=false;value.passiveAttentionEnabled=false
            value.pointerVisits=false;value.flockPasses=false;value.socialInteractions=false;value.ambientLeafPlayEnabled=false
            value.hoverDelay=0;d.settings=value
            window=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
            view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size));view.controller=d;view.desktopRect=display
            window.contentView=view;window.orderFrontRegardless()
            settings=SpeciesSettingsWindow(desktop:d);d.settingsWindow=settings
            d.engine.observationObserver={ [weak d] event in _ = d?.observationJournal.observe(event,at:Date(timeIntervalSince1970:1_700_000_000+event.simulationTime)) }
        }
        func close() {
            d.engine.handle(.cancelAmbient(.shutdown));settings.cancel();window.orderOut(nil)
            preferences.removePersistentDomain(forName:suite)
        }
        func install(_ species:SpeciesID,scale:CGFloat=1,right:Bool=true) -> Bird {
            d.engine.handle(.cancelAmbient(.shutdown));d.engine.handle(.clearCurrentScene)
            d.birds=[];d.paused=false;d.scale=scale
            var settings=d.settings;settings.bathEnabled=true;d.settings=settings
            // Two real corridors, mirrored for direction. Select the vertical
            // corridor farther from the actual pointer, which native actions
            // resample. No fake pointer, changed production clearance or retry.
            let width=work.width*0.28,x=right ? work.minX+work.width*0.06:work.maxX-work.width*0.06-width
            let ys=[work.minY+max(210,150*scale),work.maxY-100]
            let pointer=d.pointerPosition
            let chosen=ys.max {a,b in
                let centerX=work.midX
                return Geometry.distance(pointer,CGPoint(x:centerX,y:a-30*scale))<Geometry.distance(pointer,CGPoint(x:centerX,y:b-30*scale))
            }!
            host=Surface(id:7101,pid:42,rect:CGRect(x:x,y:chosen,width:width,height:80))
            target=CGPoint(x:work.minX+work.width*(right ? 0.72:0.28),y:chosen-60*scale)
            d.surfaces=[host]
            let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(species),random:{0.5})
            bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;bird.facingRight=right
            d.birds=[bird];sync()
            // Tick through the engine so quietTime and disturbance settle too.
            // At age nine both supported species are outside their idle hops.
            for _ in 0..<9*120 {step()}
            origin=bird.position;return bird
        }
        func sync() {d.syncWorld(buttonsDown:false)}
        func step() {sync();d.engine.advance(1.0/120)}
        func start() -> (BehaviorResult,BehaviorRunID?) {
            sync();let placed=d.engine.handle(.placeBath(at:target))
            guard placed.accepted else {return (placed,nil)}
            settings.previewBathButton.performClick(nil)
            let event=d.engine.events.last
            return (event?.type == .started ? .accepted:.rejected(event?.reason ?? .unavailableBird),event?.type == .started ? event?.runID:nil)
        }
        func sprite(_ id:BirdID)->CALayer? {view.layer?.sublayers?.first{$0.name=="bird-sprite-\(id.rawValue)"}}
        func seek(_ frame:String)->Bool {
            for _ in 0..<35*120 {
                guard d.engine.activeRunCount>0 else {return false}
                if d.engine.renderSnapshot().first?.frameName==frame {return true};step()
            };return false
        }
    }

    private static func visit(_ f:Fixture,species:SpeciesID,scale:CGFloat,right:Bool,into checks:inout [String:Bool],
                              evidence:inout [[String:Any]],folder:URL) throws {
        let d=f.d,bird=f.install(species,scale:scale,right:right),id=d.engine.id(of:bird)!
        let prefix="bathNative-\(species.rawValue)-\(scale)-\(right ? "right":"left")-"
        let before=d.observationJournal.archive.entries.first{$0.species==species && $0.behavior=="bathVisit"}?.previewCount ?? 0
        let ecology=d.engine.ecology(of:bird)
        checks[prefix+"RealSettledQuietFixture"]=bird.stateTime>=9-0.001 && abs(bird.hopOffset)<0.001 &&
            (ecology?.quietTime ?? 0)>=8 && (ecology?.disturbance ?? 1)<0.35
        let (result,run)=f.start()
        checks[prefix+"ProductionPlacementAndSettingsPreviewStart"]=result.accepted && run != nil && d.engine.behavior(of:bird) == .bathVisit
        guard let run else {
            evidence.append(["case":prefix,"startResult":String(describing:result),"events":d.engine.events.suffix(4).map{["type":$0.type.rawValue,"reason":$0.reason?.rawValue ?? "none"]}]);return
        }
        var observed=Set<String>(),flightSeen=false,departureSeen=false,flightClear=true,geometry=true,masked=true
        var layerOrder=true,splashes=true,contact=true,feet=true,population=true,splashFrames=Set<String>()
        var paused=false,pauseOK=false,hiddenToePixels=0
        var hiddenHitsClear=true,visibleHitsOriginal=true,frontHitsClear=true
        var waterHitPixels=0,feetHitPixels=0,visibleHitPixels=0,frontHitPixels=0
        var bodyVisible=true,noHiddenPixelLeaks=true,bodyPixels=0,occludedPixels=0
        let frontRaster=try BathArtVerification.Raster(BathArt.image(layer:.front))
        for _ in 0..<35*120 {
            guard d.engine.behavior(of:bird) == .bathVisit,let state=d.engine.renderSnapshot().first else {break}
            f.view.updateSprites()
            let baths=d.engine.habitatSnapshot().filter{$0.kind == .bath}
            guard let layer=f.sprite(id),let mask=layer.mask as? CAShapeLayer,
                  let bath=baths.first else {masked=false;break}
            population = population && d.birds.count==1 && d.birds.first === bird && d.engine.id(of:bird)==id &&
                d.arrivalCount==0 && d.departureCount==0 && d.engine.pendingCount==0
            let immersion=d.engine.bathImmersionSnapshot()[id]
            if bird.state != .perched {
                if !flightSeen || (!observed.isEmpty && !departureSeen) {
                    try snapshot(f.view,around:bath.rect.union(state.rect).insetBy(dx:-20,dy:-20),
                        to:folder.appendingPathComponent(prefix+(observed.isEmpty ? "approach":"departure")+"-actual-layer.png"))
                }
                flightSeen=true;departureSeen = departureSeen || !observed.isEmpty
                flightClear = flightClear && immersion==nil && mask.mask==nil
            }
            let props=d.engine.propSnapshot().filter{$0.kind == .waterSplash}
            splashes = splashes && props.count<=6 && Set(props.map(\.id)).count==props.count
            for prop in props {
                splashFrames.insert(prop.frameName)
                let particle=f.view.layer?.sublayers?.first{$0.name=="scene-prop-\(prop.id.rawValue)"}
                let texture=particle?.sublayers?.first
                splashes = splashes && prop.anchor==CGPoint(x:0.5,y:22.0/24.0) && prop.size==24*scale &&
                    particle?.zPosition==1 && particle?.frame==prop.rect.offsetBy(dx:-f.display.minX,dy:-f.display.minY) &&
                    texture?.anchorPoint==prop.anchor && (texture?.contents as AnyObject?) === BathArt.splashImage(prop.frameName) &&
                    particle?.opacity==Float(prop.opacity)
            }
            let rear=f.view.layer?.sublayers?.first{$0.name=="habitat-bath-rear-\(bath.id.rawValue)"}
            let front=f.view.layer?.sublayers?.first{$0.name=="habitat-bath-front-\(bath.id.rawValue)"}
            layerOrder = layerOrder && rear?.zPosition == -0.5 && front?.zPosition==0.5 && layer.zPosition==0 &&
                rear?.frame==bath.rect.offsetBy(dx:-f.display.minX,dy:-f.display.minY) && front?.frame==rear?.frame &&
                (rear?.sublayers?.first?.contents as AnyObject?) === BathArt.image(layer:.rear) &&
                (front?.sublayers?.first?.contents as AnyObject?) === BathArt.image(layer:.front)
            let siblings=f.view.layer?.sublayers ?? []
            if let rear,let front,let rearIndex=siblings.firstIndex(where:{$0 === rear}),
               let birdIndex=siblings.firstIndex(where:{$0 === layer}),let frontIndex=siblings.firstIndex(where:{$0 === front}) {
                layerOrder = layerOrder && rearIndex<birdIndex && birdIndex<frontIndex && props.allSatisfy {prop in
                    siblings.firstIndex(where:{$0.name=="scene-prop-\(prop.id.rawValue)"}).map{$0>frontIndex} ?? false
                }
            } else {layerOrder=false}
            if let immersion {
                masked = masked && mask.mask==nil
                geometry = geometry && state.facingRight==right && Geometry.distance(state.position,f.target)<0.001 &&
                    abs(immersion.waterlineY-state.position.y)<0.001 && abs(state.hopOffset)<0.001
                let toe=CGPoint(x:immersion.feetRect.midX,y:immersion.feetRect.midY)
                feet = feet && !allows(mask,world:toe,birdRect:state.rect)
                if !observed.contains(state.frameName) {
                    guard let birdArt=d.arts[species],let art=birdArt.frames[state.frameName] else {masked=false;break}
                    let raster=try BathArtVerification.Raster(art)
                    // Check every actual native alpha pixel against the engine's
                    // water/feet geometry, retaining tail outside the ellipse.
                    for y in 0..<raster.height {for x in 0..<raster.width where raster.alpha(x,y)>0 {
                        let px=(CGFloat(x)+0.5)*48/CGFloat(raster.width),py=(CGFloat(y)+0.5)*48/CGFloat(raster.height)
                        let p=CGPoint(x:state.rect.minX+(right ? px:48-px)*state.scale,y:state.rect.minY+py*state.scale)
                        let submerged=p.y>immersion.waterlineY && BathGeometry.containsContact(p,waterRect:immersion.waterRect)
                        let hidden=submerged || immersion.feetRect.contains(p) || state.blockers.contains{$0.contains(p)}
                        let visible=allows(mask,world:p,birdRect:state.rect)
                        masked = masked && visible == !hidden
                        if immersion.feetRect.contains(p),!visible {hiddenToePixels+=1}
                        // Native alpha is finer than the existing 48-point hit
                        // sampling. Only assert hits that the current art API
                        // would accept, using its actual mirrored coordinates.
                        guard artContains(birdArt,state:state,point:p) else {continue}
                        // A transparent area of the front canvas is not an
                        // occluder; test the authored foreground pixels only.
                        let coveredByFront=frontAlpha(p,baths:baths,raster:frontRaster)>0
                        let hit=d.bird(at:p)
                        if submerged {waterHitPixels+=1}
                        if immersion.feetRect.contains(p) {feetHitPixels+=1}
                        if hidden {hiddenHitsClear = hiddenHitsClear && hit==nil}
                        if coveredByFront {frontHitPixels+=1;frontHitsClear = frontHitsClear && hit==nil}
                        if !hidden && !coveredByFront {
                            visibleHitPixels+=1;visibleHitsOriginal = visibleHitsOriginal && hit === bird
                        }
                    }}
                }
                if state.frameName=="bathTouch" {
                    let anchor=PoseClip.beakAnchor(species:species,frame:state.frameName).world(foot:state.position,scale:state.scale,facingRight:right)
                    contact = contact && abs(anchor.y-immersion.waterlineY)<1e-5 &&
                        BathGeometry.containsContact(anchor,waterRect:immersion.waterRect) && allows(mask,world:anchor,birdRect:state.rect)
                }
                if !paused && state.frameName=="bath1" && !props.isEmpty {
                    paused=true;d.paused=true
                    let frozen=d.engine.renderSnapshot(),particles=d.engine.propSnapshot(),lifetime=bath.remainingLifetime
                    for _ in 0..<120 {f.step()}
                    let after=d.engine.renderSnapshot(),afterProps=d.engine.propSnapshot()
                    pauseOK=frozen.first?.frameName==after.first?.frameName && frozen.first?.rect==after.first?.rect &&
                        d.engine.habitatSnapshot().first?.remainingLifetime==lifetime && particles.count==afterProps.count &&
                        zip(particles,afterProps).allSatisfy{a,b in a.id==b.id && a.frameName==b.frameName && a.position==b.position && a.opacity==b.opacity}
                    d.paused=false
                }
                if observed.insert(state.frameName).inserted {
                    let url=folder.appendingPathComponent(prefix+state.frameName+"-actual-layer.png")
                    let actual=try snapshot(f.view,around:bath.rect.union(state.rect).insetBy(dx:-20,dy:-20),to:url)
                    let pixels=try compositePixels(f.view,layer:layer,state:state,art:d.arts[species]!,
                        immersion:immersion,baths:baths,front:frontRaster,actual:actual)
                    bodyVisible = bodyVisible && pixels.expectedBody>=4 && pixels.body>=max(4,pixels.expectedBody/2)
                    noHiddenPixelLeaks = noHiddenPixelLeaks && pixels.leaked==0
                    bodyPixels+=pixels.body;occludedPixels+=pixels.occluded
                    if state.frameName=="bath1" {try snapshot(f.view,around:bath.rect.union(state.rect).insetBy(dx:-20,dy:-20),to:folder.appendingPathComponent(prefix+"preview.png"))}
                    evidence.append(["case":prefix,"frame":state.frameName,"foot":NSStringFromPoint(state.position),
                        "waterlineY":immersion.waterlineY,"feetRect":NSStringFromRect(immersion.feetRect),"splashCount":props.count,
                        "renderedBodyPixels":pixels.body,"expectedBodyPixels":pixels.expectedBody,
                        "occludedPixelSamples":pixels.occluded,"leakedBirdPixels":pixels.leaked,"screenshot":url.lastPathComponent])
                }
            }
            f.step()
        }
        let ends=d.engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
        let count=d.observationJournal.archive.entries.first{$0.species==species && $0.behavior=="bathVisit"}?.previewCount ?? 0
        checks[prefix+"SevenPhasesInActualLayers"]=Set(BathGeometry.frameNames).isSubset(of:observed)
        checks[prefix+"NativeMirroredWaterlineAndFixedFoot"]=geometry
        checks[prefix+"ContextualWaterAndToeMaskMatchesAlpha"]=masked && feet && contact && hiddenToePixels>0
        checks[prefix+"HiddenWaterAndFeetAlphaHitNil"]=hiddenHitsClear && waterHitPixels>0 && feetHitPixels>0
        checks[prefix+"VisibleAlphaHitsOriginalBird"]=visibleHitsOriginal && visibleHitPixels>0
        checks[prefix+"RootCompositeShowsVisibleBirdBody"]=bodyVisible && bodyPixels>0
        checks[prefix+"RootCompositeWaterFeetAndFrontHaveNoBirdContribution"]=noHiddenPixelLeaks && occludedPixels>0
        evidence.append(["case":prefix,"hitSamples":["water":waterHitPixels,"feet":feetHitPixels,
            "visible":visibleHitPixels,"basinFront":frontHitPixels],"hiddenHitsClear":hiddenHitsClear,
            "visibleHitsOriginal":visibleHitsOriginal,"frontHitsClear":frontHitsClear])
        checks[prefix+"ApproachAndDepartureHaveNoImmersionMask"]=flightSeen && departureSeen && flightClear
        checks[prefix+"RearBirdFrontSplashOrder"]=layerOrder
        checks[prefix+"SixBoundedAnchoredFourFrameSplashLayers"]=splashes && splashFrames==Set(BathGeometry.splashFrameNames)
        checks[prefix+"PauseFreezesPoseParticlesAndObjectLifetime"]=paused && pauseOK
        checks[prefix+"SafeReturnCommitsOnceAndKeepsResident"]=population && ends.count==1 && ends.first?.type == .completed &&
            bird.state == .perched && Geometry.distance(bird.position,f.origin)<0.001 &&
            d.engine.habitatSnapshot().first?.remainingUses==2 && count==before+1 && clearResources(d.engine)
        // Bath poses do not overlap the front wall in every frame. Exercise
        // that independent occluder with one controlled airborne geometry
        // sample per existing case, after the production visit has ended.
        let frontOnly=try frontOnlyOcclusion(f,bird:bird,id:id,right:right,folder:folder,prefix:prefix,evidence:&evidence)
        checks[prefix+"BasinFrontAlphaHitNil"]=frontHitsClear && frontOnly
        d.engine.handle(.clearCurrentScene);for _ in 0..<260 {f.step()};f.view.updateSprites()
        checks[prefix+"AllSceneLayersRemoved"]=d.engine.habitatSnapshot().isEmpty && d.engine.propSnapshot().isEmpty &&
            f.view.layer?.sublayers?.contains{$0.name?.hasPrefix("habitat-bath-")==true || $0.name?.hasPrefix("scene-prop-")==true}==false
    }

    private static func interruptions(_ f:Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        // One real seven-phase run per interrupt, rather than multiplying the
        // full species/scale matrix by every lifecycle condition.
        for (frame,action) in [("bathInspect","click"),("bathTouch","disable"),("bathLower","remove"),
                               ("bath0","hostRemoved"),("bath1","birdRemoved"),("bath2","pausedRemove"),("bathRise","sleep")] {
            let bird=f.install(.treeSparrow),id=f.d.engine.id(of:bird)!,before=f.d.observationJournal.archive
            let (_,run)=f.start(),reached=f.seek(frame)
            let d=f.d;f.view.updateSprites();var clicked=false,hitOriginal=false
            let sequence=d.engine.events.last?.sequence ?? 0
            switch action {
            case "click":
                if reached,let state=d.engine.renderSnapshot().first,let image=d.arts[.treeSparrow]?.frames[state.frameName] {
                    let raster=try BathArtVerification.Raster(image)
                    outer:for y in 0..<raster.height {for x in 0..<raster.width where raster.alpha(x,y)>0 {
                        let px=(CGFloat(x)+0.5)*state.rect.width/CGFloat(raster.width)
                        let p=CGPoint(x:state.rect.minX+(state.facingRight ? px:state.rect.width-px),
                            y:state.rect.minY+(CGFloat(y)+0.5)*state.rect.height/CGFloat(raster.height))
                        guard let layer=f.sprite(id),let mask=layer.mask as? CAShapeLayer,
                              allows(mask,world:p,birdRect:state.rect),d.bird(at:p) === bird else {continue}
                        hitOriginal=true
                        if let event=NativeVerificationInput.leftDown(at:p) {
                            d.handleMouseDown(event);clicked=true
                        }
                        break outer
                    }}
                }
            case "disable":var settings=d.settings;settings.bathEnabled=false;d.settings=settings
            case "remove":d.engine.handle(.removeBath)
            case "hostRemoved":d.surfaces=[];f.sync()
            case "birdRemoved":d.engine.handle(.remove(id))
            case "pausedRemove":d.paused=true;d.engine.handle(.removeBath)
            default:d.engine.handle(.cancelAmbient(.sleep))
            }
            let ends=d.engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
            let replacement=d.engine.events.first{$0.sequence>sequence && $0.kind == .relocate && $0.type == .started && $0.participants==[id]}
            let clickReplaced=clicked && hitOriginal && replacement?.runID != nil &&
                ends.first?.type == .cancelled && ends.first?.reason == .replaced &&
                (ends.first?.sequence ?? UInt64.max)<(replacement?.sequence ?? 0) &&
                d.engine.behavior(of:bird) == .relocate && d.engine.id(of:bird)==id
            checks["bathNativeInterrupt-"+frame+"-"+action]=run != nil && reached && ends.count==1 && ends.first?.type != .completed &&
                d.observationJournal.archive==before && d.engine.bathImmersionSnapshot().isEmpty &&
                d.engine.habitatReservationCount==0 && (action != "click" || clickReplaced)
            if action=="click" {checks["bathNativeClickHitsOriginalAndStartsRelocateAfterBathReplaced"]=clickReplaced}
            d.paused=false;for _ in 0..<260 {f.step()};f.view.updateSprites()
            checks["bathNativeInterruptPropsReleased-"+action]=d.engine.propSnapshot().isEmpty &&
                d.engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}.count==1
            evidence.append(["phase":frame,"interrupt":action,"reached":reached,"terminal":ends.first?.type.rawValue ?? "none",
                "terminalReason":ends.first?.reason?.rawValue ?? "none","hitOriginal":hitOriginal,
                "relocateStarted":replacement != nil,"bathReplacedByRelocate":clickReplaced])
        }
    }
    private static func clearResources(_ e:BehaviorEngine)->Bool {
        e.activeRunCount==0 && e.leasedBirdCount==0 && e.reservedLandingCount==0 && e.habitatReservationCount==0 && e.propSnapshot().isEmpty && e.bathImmersionSnapshot().isEmpty
    }
    private static func artContains(_ art:BirdArt,state:BirdRenderState,point:CGPoint)->Bool {
        let x=(point.x-state.position.x)/state.scale+(state.facingRight ? 29:19)
        let y=(point.y-state.position.y)/state.scale-state.hopOffset+39
        return x>=0 && x<48 && y>=0 && y<48 &&
            art.contains(frame:state.frameName,x:state.facingRight ? Int(x):47-Int(x),y:Int(y))
    }
    private static func frontAlpha(_ point:CGPoint,baths:[HabitatObjectRenderState],raster:BathArtVerification.Raster)->UInt8 {
        var alpha:UInt8=0
        for bath in baths where bath.rect.contains(point) && !bath.blockers.contains(where:{$0.contains(point)}) {
            let x=min(raster.width-1,max(0,Int((point.x-bath.rect.minX)/bath.rect.width*CGFloat(raster.width))))
            let y=min(raster.height-1,max(0,Int((point.y-bath.rect.minY)/bath.rect.height*CGFloat(raster.height))))
            alpha=max(alpha,raster.alpha(x,y))
        }
        return alpha
    }
    private static func frontOnlyOcclusion(_ f:Fixture,bird:Bird,id:BirdID,right:Bool,folder:URL,prefix:String,
                                          evidence:inout [[String:Any]]) throws -> Bool {
        let d=f.d,position=bird.position,state=bird.state,facing=bird.facingRight
        // Synthetic geometry only: reuse this fixture resident and its actual
        // flight artwork, without starting or modifying a production journey.
        // No simulation time advances in this deliberately overlapping pose.
        bird.state = .flying;bird.position=CGPoint(x:f.target.x,y:f.target.y+26*d.scale);bird.facingRight=right
        defer {bird.position=position;bird.state=state;bird.facingRight=facing;f.view.updateSprites()}
        f.view.updateSprites()
        let baths=d.engine.habitatSnapshot().filter{$0.kind == .bath}
        guard let rendered=d.engine.renderSnapshot().first(where:{$0.id==id}),
              let art=d.arts[rendered.species],let image=art.frames[rendered.frameName],
              let layer=f.sprite(id),let mask=layer.mask as? CAShapeLayer else {return false}
        let source=try BathArtVerification.Raster(image),front=try BathArtVerification.Raster(BathArt.image(layer:.front))
        let noImmersion=d.engine.bathImmersionSnapshot()[id]==nil && mask.mask==nil
        var covered=0,clearCanvas=0,coveredClear=true,clearHitsOriginal=true
        for y in 0..<source.height {for x in 0..<source.width where source.alpha(x,y)>0 {
            let px=(CGFloat(x)+0.5)*48/CGFloat(source.width),py=(CGFloat(y)+0.5)*48/CGFloat(source.height)
            let point=CGPoint(x:rendered.rect.minX+(right ? px:48-px)*rendered.scale,
                y:rendered.rect.minY+py*rendered.scale)
            guard artContains(art,state:rendered,point:point),allows(mask,world:point,birdRect:rendered.rect),
                  !rendered.blockers.contains(where:{$0.contains(point)}) else {continue}
            let hit=d.bird(at:point)
            if frontAlpha(point,baths:baths,raster:front)>0 {
                covered+=1;coveredClear = coveredClear && hit==nil
            } else if baths.contains(where:{$0.rect.contains(point)}) {
                clearCanvas+=1;clearHitsOriginal = clearHitsOriginal && hit === bird
            }
        }}
        let crop=baths.reduce(rendered.rect){$0.union($1.rect)}.insetBy(dx:-20,dy:-20)
        let url=folder.appendingPathComponent(prefix+"front-only-airborne-geometry.png")
        let actual=try snapshot(f.view,around:crop,to:url)
        let baseline=try captureWithoutBird(f.view,layer:layer,around:actual.crop)
        let shown=try BathArtVerification.Raster(actual.image),hidden=try BathArtVerification.Raster(baseline.image)
        var frontPixels=0,frontLeaks=0,transparentPixels=0
        for y in 0..<shown.height {for x in 0..<shown.width {
            let p=CGPoint(x:actual.crop.minX+CGFloat(x)+0.5,y:actual.crop.minY+CGFloat(y)+0.5)
            guard artContains(art,state:rendered,point:p),!rendered.blockers.contains(where:{$0.contains(p)}) else {continue}
            let a=y*shown.stride+x*4,b=y*hidden.stride+x*4
            let changed=(0..<4).contains{shown.bytes[a+$0] != hidden.bytes[b+$0]}
            let corners=[CGPoint(x:p.x-0.51,y:p.y-0.51),CGPoint(x:p.x+0.51,y:p.y-0.51),
                         CGPoint(x:p.x-0.51,y:p.y+0.51),CGPoint(x:p.x+0.51,y:p.y+0.51)]
            if corners.allSatisfy({frontAlpha($0,baths:baths,raster:front)==255}) {
                frontPixels+=1;if changed {frontLeaks+=1}
            } else if frontAlpha(p,baths:baths,raster:front)==0,
                      baths.contains(where:{$0.rect.contains(p)}),changed {transparentPixels+=1}
        }}
        evidence.append(["case":prefix,"fixture":"Controlled airborne geometry; no production flight route claimed",
            "frame":rendered.frameName,"noImmersion":noImmersion,"frontOnlySamples":covered,
            "transparentFrontCanvasSamples":clearCanvas,"frontOnlyHitsNil":coveredClear,
            "frontCompositeSamples":frontPixels,"frontCompositeLeaks":frontLeaks,"transparentCanvasBirdPixels":transparentPixels,
            "transparentCanvasHitsOriginal":clearHitsOriginal,"screenshot":url.lastPathComponent])
        return noImmersion && covered>0 && coveredClear && clearCanvas>0 && clearHitsOriginal &&
            frontPixels>0 && frontLeaks==0 && transparentPixels>0
    }
    private struct CompositePixels {var body=0,expectedBody=0,occluded=0,leaked=0}
    private static func compositePixels(_ view:DesktopView,layer:CALayer,state:BirdRenderState,art:BirdArt,
                                        immersion:BathImmersionState,baths:[HabitatObjectRenderState],
                                        front:BathArtVerification.Raster,actual:LayerCapture) throws -> CompositePixels {
        // Same production root, same masks/foreground/splashes, no ticking.
        // Hiding only this bird establishes its actual composited contribution.
        let baseline=try captureWithoutBird(view,layer:layer,around:actual.crop)
        let shown=try BathArtVerification.Raster(actual.image),hidden=try BathArtVerification.Raster(baseline.image)
        guard baseline.crop==actual.crop,shown.width==hidden.width,shown.height==hidden.height else {
            throw failure("Bath composite comparison crop changed")
        }
        var result=CompositePixels()
        for y in 0..<shown.height {for x in 0..<shown.width {
            let p=CGPoint(x:actual.crop.minX+CGFloat(x)+0.5,y:actual.crop.minY+CGFloat(y)+0.5)
            guard artContains(art,state:state,point:p) else {continue}
            let a=y*shown.stride+x*4,b=y*hidden.stride+x*4
            let changed=(0..<4).contains{shown.bytes[a+$0] != hidden.bytes[b+$0]}
            if p.y<immersion.waterlineY-3*state.scale,
               !state.blockers.contains(where:{$0.contains(p)}),frontAlpha(p,baths:baths,raster:front)==0 {
                result.expectedBody+=1;if changed {result.body+=1}
            }
            // Require the whole output pixel to lie inside the hidden region;
            // antialiased geometric boundaries are not opaque interior pixels.
            let corners=[CGPoint(x:p.x-0.51,y:p.y-0.51),CGPoint(x:p.x+0.51,y:p.y-0.51),
                         CGPoint(x:p.x-0.51,y:p.y+0.51),CGPoint(x:p.x+0.51,y:p.y+0.51)]
            let water=corners.allSatisfy{$0.y>immersion.waterlineY && BathGeometry.containsContact($0,waterRect:immersion.waterRect)}
            let feet=corners.allSatisfy{immersion.feetRect.contains($0)}
            let blocked=state.blockers.contains{rect in corners.allSatisfy{rect.contains($0)}}
            let wall=corners.allSatisfy{frontAlpha($0,baths:baths,raster:front)==255}
            if water || feet || blocked || wall {result.occluded+=1;if changed {result.leaked+=1}}
        }}
        return result
    }
    private static func allows(_ mask:CAShapeLayer,world point:CGPoint,birdRect:CGRect)->Bool {
        let local=CGPoint(x:point.x-birdRect.minX,y:point.y-birdRect.minY)
        var current:CALayer?=mask
        while let layer=current {
            if let shape=layer as? CAShapeLayer,let path=shape.path,
               !path.contains(local,using:shape.fillRule == .evenOdd ? .evenOdd:.winding,transform:.identity) {return false}
            current=layer.mask
        };return true
    }
    // Always world coordinates: capture accepts world crops, and pixel probes
    // compare against world-space art, water, feet and basin geometry.
    private struct LayerCapture {let image:CGImage,crop:CGRect}
    private static func captureWithoutBird(_ view:DesktopView,layer:CALayer,around rect:CGRect) throws -> LayerCapture {
        CATransaction.begin();CATransaction.setDisableActions(true)
        let wasHidden=layer.isHidden;layer.isHidden=true
        defer {layer.isHidden=wasHidden;CATransaction.commit()}
        return try capture(view,around:rect)
    }
    @discardableResult
    private static func snapshot(_ view:DesktopView,around rect:CGRect,to url:URL) throws -> LayerCapture {
        let result=try capture(view,around:rect)
        try writePNG(result.image,to:url);return result
    }
    private static func capture(_ view:DesktopView,around rect:CGRect) throws -> LayerCapture {
        let crop=rect.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY).intersection(view.bounds).integral
        guard !crop.isEmpty,let root=view.layer,
              let context=CGContext(data:nil,width:Int(crop.width),height:Int(crop.height),bitsPerComponent:8,bytesPerRow:0,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot capture native bath layers")}
        context.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor);context.fill(CGRect(origin:.zero,size:crop.size))
        context.translateBy(x:0,y:crop.height);context.scaleBy(x:1,y:-1)
        context.translateBy(x:-crop.minX,y:-crop.minY);root.render(in:context)
        guard let image=context.makeImage() else {throw failure("Cannot read native bath composite")}
        return LayerCapture(image:image,crop:crop.offsetBy(dx:view.desktopRect.minX,dy:view.desktopRect.minY))
    }
    static func writePNG(_ context:CGContext,to url:URL) throws {
        guard let image=context.makeImage() else {throw failure("Cannot encode bath evidence")}
        try writePNG(image,to:url)
    }
    private static func writePNG(_ image:CGImage,to url:URL) throws {
        guard let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {throw failure("Cannot encode bath evidence")}
        try png.write(to:url,options:.atomic)
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"BathVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
