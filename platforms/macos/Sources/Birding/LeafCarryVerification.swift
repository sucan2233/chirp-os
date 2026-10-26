import AppKit
import BirdingCore

/// Production placement, settings preview, engine journeys and DesktopView
/// composition. No synthetic pose is used for the journey screenshots.
enum LeafCarryVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("leaf-carry-native-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("leafCarry")},"evidence":evidence,
            "limits":"Actual model-layer composition on the attached display with isolated host geometry. These captures do not claim WindowServer or physical hotplug acceptance."],to:output.appendingPathComponent("report.json"))}
        let f=try Fixture(folder:output);defer {f.close()}
        for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
            try journey(f,scale:scale,right:right,into:&checks,evidence:&evidence,folder:output)
        }}
        // Exercise the real ground rule, including tail clearance at the
        // display bottom. Pick the horizontal corridor away from the pointer.
        let groundRight=f.d.pointerPosition.x>=f.work.midX
        try journey(f,scale:2,right:groundRight,ground:true,into:&checks,evidence:&evidence,folder:output)
        try interruptions(f,into:&checks,evidence:&evidence,folder:output)
        checks["leafCarryNativeNoStartupOrRealPreferences"]=f.d.timer==nil && f.d.panels.isEmpty && f.d.views.isEmpty &&
            f.d.globalMouseMonitor==nil && f.d.localMouseMonitor==nil && !f.d.automaticPopulation &&
            !FileManager.default.fileExists(atPath:f.d.settingsURL.path) &&
            !FileManager.default.fileExists(atPath:f.d.visitorMemoryURL.path) &&
            !FileManager.default.fileExists(atPath:f.d.observationJournalURL.path)
    }
    private final class Fixture {
        let d:DesktopController,window:OverlayPanel,view:DesktopView,work:CGRect,display:CGRect
        let suite:String,preferences:UserDefaults,settings:SpeciesSettingsWindow
        var host:Surface!,target=CGPoint.zero
        init(folder:URL) throws {
            let d=DesktopController();self.d=d
            guard let screen=NSScreen.screens.first,let work=d.screenRects.first,let display=d.displayRects.first,
                  work.width>=1000,work.height>=620 else {throw failure("Carry native verification requires a 1000 × 620 work area")}
            self.work=work;self.display=display
            suite="Birding.LeafCarryVerification."+UUID().uuidString
            guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate preferences")}
            self.preferences=preferences;d.preferences=preferences;d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            d.pointerButtonsDown={false};d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false
            d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("visitors.json");d.observationJournalURL=folder.appendingPathComponent("journal.json")
            var value=d.settings;value.perchActions=false;value.passiveAttentionEnabled=false
            value.hoverDelay=0;value.pointerVisits=false;value.flockPasses=false
            value.socialInteractions=false;value.ambientLeafPlayEnabled=false;d.settings=value
            window=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
            view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size));view.controller=d;view.desktopRect=display
            window.contentView=view;window.orderFrontRegardless()
            settings=SpeciesSettingsWindow(desktop:d);d.settingsWindow=settings
            d.engine.observationObserver={ [weak d] event in
                _=d?.observationJournal.observe(event,at:Date(timeIntervalSince1970:1_700_000_000+event.simulationTime))
            }
        }
        func close() {d.engine.handle(.cancelAmbient(.shutdown));settings.cancel();window.orderOut(nil);preferences.removePersistentDomain(forName:suite)}
        func install(scale:CGFloat=1,right:Bool=true,ground:Bool=false)->Bird {
            d.engine.handle(.cancelAmbient(.shutdown));d.engine.handle(.clearCurrentScene)
            d.birds=[];d.paused=false;d.scale=scale
            var value=d.settings;value.leafCarryEnabled=true
            // One accepted case also changes carrier size. The token must stay
            // at world scale while bill/foot geometry uses the larger bird.
            if let index=value.catalog.species.firstIndex(where:{$0.id == .treeSparrow}) {
                value.catalog.species[index].adultLengthCM = scale==1 && !right ? 20:SpeciesCatalog.standard.profile(.treeSparrow).adultLengthCM
            }
            d.settings=value
            let ys=[work.minY+max(200,140*scale),work.maxY-70],pointer=d.pointerPosition
            let y=ys.max {a,b in Geometry.distance(pointer,CGPoint(x:work.midX,y:a-35*scale))<Geometry.distance(pointer,CGPoint(x:work.midX,y:b-35*scale))}!
            host=ground ? Geometry.ground(id:7203,display:display,workArea:work):
                Surface(id:7202,pid:42,rect:CGRect(x:work.minX+40,y:y,width:work.width-80,height:60))
            let fraction:CGFloat=ground ? (right ? 0.12:0.88):(right ? 0.24:0.76)
            let bird=Bird(position:.zero,fraction:fraction,profile:d.catalog.profile(.treeSparrow),random:{0.5})
            bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;bird.facingRight=right
            target=CGPoint(x:work.minX+work.width*(ground ? (right ? 0.28:0.72):(right ? 0.65:0.35)),
                y:Geometry.foot(on:host,fraction:0.5,edge:.top,scale:d.spriteScale(for:bird)).y)
            d.surfaces=[host];d.birds=[bird]
            for _ in 0..<9*120 {step()}
            return bird
        }
        func step() {d.syncWorld(buttonsDown:false);d.engine.advance(1.0/120)}
        func advance(_ seconds:Double) {for _ in 0..<Int((seconds*120).rounded()) {step()}}
        func start()->(BehaviorResult,BehaviorRunID?) {
            d.syncWorld(buttonsDown:false)
            let placed=d.engine.handle(.placeCarryLeaf(at:target));guard placed.accepted else {return (placed,nil)}
            let sequence=d.engine.events.last?.sequence ?? 0
            settings.previewLeafCarryButton.performClick(nil)
            let started=d.engine.events.last{$0.sequence>sequence && $0.kind == .leafCarry && $0.type == .started}
            return (started == nil ? .rejected(d.engine.events.last?.reason ?? .unavailableBird):.accepted,started?.runID)
        }
        func sprite(_ id:BirdID)->CALayer? {view.layer?.sublayers?.first{$0.name=="bird-sprite-\(id.rawValue)"}}
        func prop(_ id:ScenePropID)->CALayer? {view.layer?.sublayers?.first{$0.name=="scene-prop-\(id.rawValue)"}}
        func seek(_ phase:String,bird:Bird)->Bool {
            for _ in 0..<25*120 {
                guard d.engine.behavior(of:bird) == .leafCarry,
                      let state=d.engine.renderSnapshot().first,let object=d.engine.carriedObjectSnapshot().first else {return false}
                if phase=="attachedFlight" && object.state == .attached && bird.state == .flying {return true}
                if phase=="placed" && object.state == .placed {return true}
                if state.frameName==phase {return true}
                step()
            };return false
        }
    }
    private static func journey(_ f:Fixture,scale:CGFloat,right:Bool,ground:Bool=false,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        let d=f.d,bird=f.install(scale:scale,right:right,ground:ground),id=d.engine.id(of:bird)!
        let key="leafCarryNative-\(ground ? "ground":"window")-\(scale)-\(right ? "right":"left")-",origin=bird.position
        let before=previewCount(d),ecology=d.engine.ecology(of:bird)
        checks[key+"SettledQuietFixture"]=bird.stateTime>=9-0.001 && abs(bird.hopOffset)<0.001 && (ecology?.quietTime ?? 0)>=8
        let (result,run)=f.start()
        checks[key+"ProductionPlacementAndNativePreview"]=result.accepted && run != nil && bird.position==origin && d.birds.count==1
        guard let run,let initial=d.engine.carriedObjectSnapshot().first else {
            evidence.append(["case":key,"start":String(describing:result),"reason":d.engine.events.last?.reason?.rawValue ?? "none"]);return
        }
        checks[key+"RealSupportingSurface"]=initial.surfaceAnchor.isGround==ground && f.host.isGround==ground &&
            initial.surfaceAnchor.hostID==f.host.id && initial.surfaceAnchor.hostPID==f.host.pid
        var phases=Set<String>(),frames=Set<String>(),sameID=true,oneEntity=true,geometry=true,continuous=true
        var pickup=false,placed=false,pickupContinuous=true,placeContinuous=true,attachedFlight=false
        var leafPixels=true,birdPixels=true,leafSamples=0,bodySamples=0,pauseDone=false,pauseOK=false
        var previousBird=bird.position,previousProp=d.engine.propSnapshot().first{$0.id==initial.id},previousState=initial.state
        for _ in 0..<25*120 {
            guard d.engine.behavior(of:bird) == .leafCarry,let state=d.engine.renderSnapshot().first,
                  let object=d.engine.carriedObjectSnapshot().first,let prop=d.engine.propSnapshot().first(where:{$0.kind == .leafToken}) else {break}
            f.view.updateSprites()
            sameID = sameID && object.id==initial.id && prop.id==initial.id
            oneEntity = oneEntity && d.engine.carriedObjectSnapshot().count==1 && d.engine.propSnapshot().filter{$0.kind == .leafToken}.count==1 &&
                d.birds.count==1 && d.birds.first === bird && d.arrivalCount==0 && d.departureCount==0
            continuous = continuous && Geometry.distance(previousBird,bird.position)<max(12,12*state.scale)
            previousBird=bird.position
            guard let leaf=f.prop(prop.id),let sprite=f.sprite(id),let texture=leaf.sublayers?.first else {geometry=false;break}
            geometry = geometry && layerMatches(prop,container:leaf,texture:texture,view:f.view) && prop.size==16*scale
            if object.state == .attached {
                if let anchor=PoseClip.carryBeakAnchor(species:state.species,frame:state.frameName) {
                    let foot=CGPoint(x:state.position.x,y:state.position.y+state.hopOffset*state.scale)
                    let beak=anchor.world(foot:foot,scale:state.scale,facingRight:state.facingRight)
                    geometry = geometry && object.owner==id && Geometry.distance(beak,prop.position)<1e-5 &&
                        prop.anchor==CGPoint(x:3.0/16,y:12.0/16) && prop.mirrored == !right
                } else {geometry=false}
                attachedFlight = attachedFlight || bird.state == .flying
            }
            if object.state != previousState,let previousProp {
                let aligned=close(previousProp.rect,prop.rect) && previousProp.id==prop.id
                if previousState == .available && object.state == .attached {pickup=true;pickupContinuous = pickupContinuous && aligned}
                if previousState == .attached && object.state == .placed {placed=true;placeContinuous = placeContinuous && aligned}
            }
            previousState=object.state;previousProp=prop
            frames.insert(state.frameName)
            let phase=object.state.rawValue+"-"+(bird.state == .flying ? "flight":state.frameName)
            if phases.insert(phase).inserted {
                let url=folder.appendingPathComponent(key+phase+"-actual-layer.png")
                let capture=try snapshot(f.view,around:state.rect.union(prop.rect).insetBy(dx:-18,dy:-18),to:url)
                let leafContribution=try contribution(f.view,layer:leaf,actual:capture,region:prop.rect)
                let birdContribution=try contribution(f.view,layer:sprite,actual:capture,region:state.rect)
                leafPixels = leafPixels && leafContribution>=max(2,Int(12*scale*scale))
                birdPixels = birdPixels && birdContribution>=4
                leafSamples+=leafContribution;bodySamples+=birdContribution
                evidence.append(["case":key,"phase":phase,"frame":state.frameName,"objectID":object.id.rawValue,
                    "owner":object.owner?.rawValue ?? 0,"leafRect":NSStringFromRect(prop.rect),"leafAnchor":NSStringFromPoint(prop.anchor),
                    "leafPixels":leafContribution,"birdPixels":birdContribution,"screenshot":url.lastPathComponent])
            }
            if !pauseDone,object.state == .attached,bird.state == .flying {
                pauseDone=true;d.paused=true
                let frozen=d.engine.renderSnapshot().first,token=d.engine.propSnapshot().first{$0.id==initial.id}
                let lifetime=object.remainingLifetime
                f.advance(2)
                pauseOK=d.engine.renderSnapshot().first?.position==frozen?.position && d.engine.renderSnapshot().first?.frameName==frozen?.frameName &&
                    d.engine.propSnapshot().first{$0.id==initial.id}?.position==token?.position &&
                    d.engine.carriedObjectSnapshot().first?.remainingLifetime==lifetime
                d.paused=false
            }
            f.step()
        }
        let ends=terminal(d.engine,run:run),final=d.engine.carriedObjectSnapshot().first
        checks[key+"CompleteRealPickupFlightPlaceRoute"]=Set(CarryArtGeometry.frameNames).isSubset(of:frames) && attachedFlight &&
            ends.count==1 && ends.first?.type == .completed && final?.state == .placed && bird.state == .perched
        checks[key+"SameIdentityOneEntityThroughContact"]=sameID && oneEntity && pickup && placed
        checks[key+"PickupAndReleaseKeepSameCanvasWithoutJump"]=pickupContinuous && placeContinuous && pickup && placed && continuous
        checks[key+"ActualLayerAnchorMirrorRotationAndWorldScale"]=geometry && initial.facingRight==right
        checks[key+"RootCompositeContainsLeafAndBirdPixels"]=leafPixels && birdPixels && leafSamples>0 && bodySamples>0
        checks[key+"PauseFreezesFlightAndAttachment"]=pauseDone && pauseOK
        checks[key+"CompletionCountsOnceAndReleasesRun"]=previewCount(d)==before+1 && d.engine.activeRunCount==0 &&
            d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0 && final?.owner==nil && final?.reservedByRun==nil
        let placedSnapshot=d.engine.propSnapshot().first{$0.id==initial.id}
        d.paused=true;f.advance(2)
        checks[key+"PlacedLeafPauseKeepsIdentityAndPosition"]=placedSnapshot != nil && d.engine.propSnapshot().first{$0.id==initial.id}?.position==placedSnapshot?.position
        d.paused=false;f.advance(8.5);f.view.updateSprites()
        checks[key+"DisplayLifetimeEndsWithoutPropsOrLayers"]=d.engine.carriedObjectSnapshot().isEmpty &&
            d.engine.propSnapshot().allSatisfy{$0.kind != .leafToken} && f.prop(initial.id)==nil && d.birds.first === bird
    }
    private static func interruptions(_ f:Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        let cases=[("carryLook","click"),("carryLower","disable"),("carryGrip","remove"),
            ("attachedFlight","hostRemoved"),("carryPlace","birdRemoved"),("placed","clickAfterPlace"),
            ("carryLower","pausedRemove"),("attachedFlight","sleep")]
        for (phase,action) in cases {
            let d=f.d,bird=f.install(),id=d.engine.id(of:bird)!,archive=d.observationJournal.archive
            let (_,run)=f.start(),reached=f.seek(phase,bird:bird)
            f.view.updateSprites()
            let before=d.engine.propSnapshot().first{$0.kind == .leafToken},sequence=d.engine.events.last?.sequence ?? 0
            var hitOriginal=false,clicked=false
            switch action {
            case "click","clickAfterPlace":
                if reached,let state=d.engine.renderSnapshot().first,let point=visiblePoint(state,in:d) {
                    hitOriginal=d.bird(at:point) === bird
                    if hitOriginal,let event=NativeVerificationInput.leftDown(at:point) {
                        d.handleMouseDown(event);clicked=true
                    }
                }
            case "disable":var value=d.settings;value.leafCarryEnabled=false;d.settings=value
            case "remove":d.engine.handle(.removeCarryLeaf)
            case "hostRemoved":d.surfaces=[];d.syncWorld(buttonsDown:false)
            case "birdRemoved":d.engine.handle(.remove(id))
            case "pausedRemove":d.paused=true;d.engine.handle(.removeCarryLeaf)
            default:d.engine.handle(.cancelAmbient(.sleep))
            }
            let ends=run.map{terminal(d.engine,run:$0)} ?? []
            let replacement=d.engine.events.first{$0.sequence>sequence && $0.type == .started && $0.kind == .relocate && $0.participants==[id]}
            let isClick=action=="click" || action=="clickAfterPlace"
            let relocated=hitOriginal && clicked && replacement?.runID != nil && d.engine.behavior(of:bird) == .relocate &&
                ends.first?.reason == .replaced && (ends.first?.sequence ?? UInt64.max)<(replacement?.sequence ?? 0)
            let after=d.engine.propSnapshot().first{$0.id==before?.id}
            let preserved=action=="clickAfterPlace"
            checks["leafCarryNativeInterrupt-"+phase+"-"+action]=run != nil && reached && ends.count==1 && ends.first?.type != .completed &&
                d.observationJournal.archive==archive && (!isClick || relocated) && d.engine.reservedLandingCount==0
            if preserved {
                checks["leafCarryNativePlacedLeafSurvivesClickWithoutCredit"]=d.engine.carriedObjectSnapshot().first?.state == .placed &&
                    after?.id==before?.id && after?.rect==before?.rect && d.observationJournal.archive==archive
            } else if action != "pausedRemove" && action != "sleep",let before,let after {
                checks["leafCarryNativeCancelFadeKeepsCurrentCanvas-"+action]=before.id==after.id && close(before.rect,after.rect)
            }
            d.paused=false;f.advance(preserved ? 8.5:0.3);f.view.updateSprites()
            checks["leafCarryNativeInterruptClearsObject-"+action]=d.engine.carriedObjectSnapshot().isEmpty &&
                d.engine.propSnapshot().allSatisfy{$0.kind != .leafToken} && (before.map{f.prop($0.id)==nil} ?? false)
            evidence.append(["phase":phase,"interrupt":action,"reached":reached,"reason":ends.first?.reason?.rawValue ?? "none",
                "hitOriginal":hitOriginal,"relocateStarted":replacement != nil,"run":run?.rawValue ?? 0])
        }
    }
    private static func visiblePoint(_ state:BirdRenderState,in d:DesktopController)->CGPoint? {
        guard let art=d.arts[state.species] else {return nil}
        for y in 0..<48 {for x in 0..<48 where art.contains(frame:state.frameName,x:x,y:y) {
            let px=CGFloat(x)+0.5
            let point=CGPoint(x:state.rect.minX+(state.facingRight ? px:48-px)*state.scale,
                y:state.rect.minY+(CGFloat(y)+0.5)*state.scale)
            if d.bird(at:point) != nil {return point}
        }};return nil
    }
    private static func layerMatches(_ prop:ScenePropRenderState,container:CALayer,texture:CALayer,view:DesktopView)->Bool {
        guard let root=view.layer,let mask=container.mask as? CAShapeLayer else {return false}
        let anchor=CGPoint(x:prop.anchor.x*prop.size,y:prop.anchor.y*prop.size)
        let grip=texture.convert(anchor,to:root)
        let points=[CGPoint.zero,CGPoint(x:prop.size,y:0),CGPoint(x:prop.size,y:prop.size),CGPoint(x:0,y:prop.size)].map{texture.convert($0,to:root)}
        let xs=points.map(\.x),ys=points.map(\.y)
        let actual=CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
        let transform=texture.affineTransform(),m:CGFloat=prop.mirrored ? -1:1
        let c=cos(prop.rotation),s=sin(prop.rotation)
        return !container.isHidden && close(container.frame,prop.rect.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY)) &&
            close(actual,container.frame) && Geometry.distance(grip,CGPoint(x:prop.position.x-view.desktopRect.minX,y:prop.position.y-view.desktopRect.minY))<1e-5 &&
            texture.anchorPoint==prop.anchor && texture.bounds.size==CGSize(width:prop.size,height:prop.size) &&
            abs(transform.a-c*m)<1e-5 && abs(transform.b-s*m)<1e-5 && abs(transform.c+s)<1e-5 && abs(transform.d-c)<1e-5 &&
            (texture.contents as AnyObject?) === CarryArt.leafImage() && mask.mask==nil && mask.path != nil
    }
    private struct Capture {let context:CGContext,crop:CGRect}
    private static func capture(_ view:DesktopView,around rect:CGRect) throws -> Capture {
        let local=rect.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY).intersection(view.bounds).integral
        guard !local.isEmpty,let root=view.layer,let context=CGContext(data:nil,width:Int(local.width),height:Int(local.height),bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot capture carry production layers")}
        context.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor);context.fill(CGRect(origin:.zero,size:local.size))
        context.translateBy(x:0,y:local.height);context.scaleBy(x:1,y:-1);context.translateBy(x:-local.minX,y:-local.minY)
        root.render(in:context)
        return Capture(context:context,crop:local.offsetBy(dx:view.desktopRect.minX,dy:view.desktopRect.minY))
    }
    private static func snapshot(_ view:DesktopView,around rect:CGRect,to url:URL) throws -> Capture {
        let result=try capture(view,around:rect);try BathVerification.writePNG(result.context,to:url);return result
    }
    private static func contribution(_ view:DesktopView,layer:CALayer,actual:Capture,region:CGRect) throws -> Int {
        CATransaction.begin();CATransaction.setDisableActions(true)
        let hidden=layer.isHidden;layer.isHidden=true
        defer {layer.isHidden=hidden;CATransaction.commit()}
        let baseline=try capture(view,around:actual.crop)
        guard let a=actual.context.makeImage(),let b=baseline.context.makeImage() else {throw failure("Cannot read carry composite")}
        let shown=try BathArtVerification.Raster(a),without=try BathArtVerification.Raster(b)
        guard actual.crop==baseline.crop,shown.width==without.width,shown.height==without.height else {throw failure("Carry composite crop changed")}
        var changed=0
        for y in 0..<shown.height {for x in 0..<shown.width {
            let point=CGPoint(x:actual.crop.minX+CGFloat(x)+0.5,y:actual.crop.minY+CGFloat(y)+0.5)
            guard region.insetBy(dx:-1,dy:-1).contains(point) else {continue}
            let i=y*shown.stride+x*4,j=y*without.stride+x*4
            if (0..<4).contains(where:{shown.bytes[i+$0] != without.bytes[j+$0]}) {changed+=1}
        }};return changed
    }
    private static func close(_ a:CGRect,_ b:CGRect)->Bool {
        abs(a.minX-b.minX)<1e-5 && abs(a.minY-b.minY)<1e-5 && abs(a.width-b.width)<1e-5 && abs(a.height-b.height)<1e-5
    }
    private static func terminal(_ e:BehaviorEngine,run:BehaviorRunID)->[BehaviorEvent] {e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}}
    private static func previewCount(_ d:DesktopController)->Int {d.observationJournal.archive.entries.first{$0.species == .treeSparrow && $0.behavior=="leafCarry"}?.previewCount ?? 0}
    private static func failure(_ text:String)->NSError {NSError(domain:"LeafCarryVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
