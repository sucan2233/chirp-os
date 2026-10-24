import AppKit
import BirdingCore

/// Explicitly stepped production commands and the actual DesktopView root.
/// No scene-store injection, controller startup, preference loading or posted input.
enum NestMaterialVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("nest-material-native-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        var completed=false
        var caseErrors=[String:String]()
        defer {report(checks,evidence:evidence,prefix:"nestMaterialNative",folder:output,completed:completed,caseErrors:caseErrors)}
        for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
            runCase("scale-\(scale)-\(right ? "right":"left")",errors:&caseErrors) {
            let f=try Fixture(folder:output);defer {f.close()}
            try f.install(scale:scale,right:right);try f.place()
            _=journey(f,kind:.nestMaterialCarry,source:.preview,key:"nestMaterialNative-\(scale)-\(right ? "right":"left")-",
                capture:true,into:&checks,evidence:&evidence,folder:output)
        }}}
        runCase("automatic",errors:&caseErrors) {
            let f=try Fixture(folder:output);defer {f.close()}
            try f.install();try f.place()
            _=journey(f,kind:.nestMaterialCarry,source:.automatic,key:"nestMaterialNative-automatic-",
                capture:false,into:&checks,evidence:&evidence,folder:output)
        }
        runCase("interruptions",errors:&caseErrors) {
            let f=try Fixture(folder:output);defer {f.close()}
            try interruptions(f,build:false,into:&checks,evidence:&evidence,folder:output)
            f.d.engine.handle(.clearCurrentScene);f.advance(3);f.view.updateSprites()
            checks["nestMaterialNativeFinalResourcesAndIsolation"]=f.isolated && clear(f.d.engine) &&
                f.view.layer?.sublayers?.contains{$0.name?.hasPrefix("habitat-nest-")==true || $0.name?.hasPrefix("scene-prop-")==true}==false
        }
        try requireAllCases(caseErrors)
        completed=true
    }

    /// Independent fixtures can still run after another case is blocked. All
    /// exceptions remain failures, and the original route guards run unchanged.
    static func runCase(_ name:String,errors:inout [String:String],body:()throws->Void) {
        do {try autoreleasepool {try body()}}
        catch {errors[name]=error.localizedDescription}
    }
    static func requireAllCases(_ errors:[String:String]) throws {
        if !errors.isEmpty {
            throw failure(errors.keys.sorted().map {"\($0): \(errors[$0]!)"}.joined(separator:"\n"))
        }
    }

    final class Fixture {
        let d:DesktopController,overlay:OverlayPanel,view:DesktopView,hostWindow:NSWindow
        let work:CGRect,display:CGRect,suite:String,preferences:UserDefaults
        var host=Surface(id:0,rect:.zero),target=CGPoint.zero,bird:Bird?,layout=[String:Any](),crop=CGRect.zero
        private var window:SpeciesSettingsWindow?
        var controls:SpeciesSettingsWindow {
            if let window {return window}
            let value=SpeciesSettingsWindow(desktop:d);window=value;d.settingsWindow=value;return value
        }
        init(folder:URL) throws {
            let d=DesktopController(verificationSeed:0x4E4553544E415449);self.d=d
            guard let screen=NSScreen.screens.first,let work=d.screenRects.first,let display=d.displayRects.first else {
                throw failure("Nest verification needs an attached display")
            }
            self.work=work;self.display=display;suite="Birding.NestVerification."+UUID().uuidString
            guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate nest preferences")}
            self.preferences=preferences;d.preferences=preferences;d.pointerButtonsDown={false};d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false;d.giftLedgerPersistenceEnabled=false
            d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("visitors.json");d.observationJournalURL=folder.appendingPathComponent("journal.json")
            d.giftLedgerURL=folder.appendingPathComponent("gifts.json")
            hostWindow=NSWindow(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
            hostWindow.isReleasedWhenClosed=false;hostWindow.hasShadow=false;hostWindow.ignoresMouseEvents=true
            hostWindow.backgroundColor=NSColor(calibratedWhite:0.92,alpha:1)
            overlay=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            overlay.isReleasedWhenClosed=false;overlay.isOpaque=false;overlay.backgroundColor = .clear
            overlay.hasShadow=false;overlay.ignoresMouseEvents=true;overlay.level = .floating
            view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size));view.controller=d;view.desktopRect=display
            overlay.contentView=view
            d.engine.observationObserver={ [weak d] event in
                _=d?.observationJournal.observe(event,at:Date(timeIntervalSince1970:1_700_000_000+event.simulationTime))
            }
        }
        var isolated:Bool {
            d.timer==nil && d.status==nil && d.panels.isEmpty && d.views.isEmpty &&
                d.globalMouseMonitor==nil && d.localMouseMonitor==nil &&
                d.visitorMemoryPersistence==nil && d.observationPersistence==nil && d.giftLedgerPersistence==nil &&
                [d.legacyURL,d.visitorMemoryURL,d.observationJournalURL,d.giftLedgerURL].allSatisfy{!FileManager.default.fileExists(atPath:$0.path)}
        }
        func close() {
            d.engine.handle(.cancelAmbient(.shutdown));d.engine.handle(.clearCurrentScene);d.engine.observationObserver=nil
            window?.cancel();window=nil;d.settingsWindow=nil
            overlay.orderOut(nil);overlay.close();hostWindow.orderOut(nil);hostWindow.close()
            preferences.removePersistentDomain(forName:suite)
        }
        func step() {d.syncWorld(buttonsDown:false);d.engine.advance(1.0/120)}
        func advance(_ seconds:Double) {for _ in 0..<Int((seconds*120).rounded()) {step()}}
        func settle() {
            advance(2)
            for _ in 0..<600 {
                if d.engine.renderSnapshot().allSatisfy({abs($0.hopOffset)<0.001}) {return};step()
            }
        }
        func install(scale:CGFloat=1,right:Bool=true,species:SpeciesID = .spottedDove,ground:Bool=false) throws {
            d.paused=false;d.engine.handle(.cancelAmbient(.shutdown));d.engine.handle(.clearCurrentScene)
            advance(3);d.birds=[];d.scale=scale;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            var settings=BirdSettings();settings.nestBuildingEnabled=true;settings.socialInteractions=false
            settings.perchActions=false;settings.passiveAttentionEnabled=false;settings.sideHopEnabled=false
            settings.takeoffPreparationEnabled=false;settings.edgePeekEnabled=false
            settings.pointerVisits=false;settings.flockPasses=false;settings.ambientLeafPlayEnabled=false
            settings.insectCatchEnabled=false;settings.visitorGiftsEnabled=false;settings.visitorMemoryEnabled=false
            settings.courtshipEnabled=false;settings.hoverDelay=0;settings.fixedPerches=[];d.settings=settings
            d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
            let effective=scale*d.catalog.profile(.spottedDove).relativeScale
            let width=floor(work.width-32),left=ceil(work.minX+16),pointer=d.pointerPosition
            let low=ceil(work.minY+129*effective+56),high=floor(work.maxY-max(100,24*scale+40))
            let radius=max(100,72*effective)
            func area(_ y:CGFloat)->CGRect {
                CGRect(x:left,y:y-129*effective-36,width:width,height:129*effective+max(24*scale,9*effective)+72)
            }
            let ys=ground ? [Geometry.foot(on:Geometry.ground(id:7301,display:display,workArea:work),fraction:0.5,edge:.top,scale:effective).y]:[low,high]
            let candidates=ys.filter {y in
                let a=area(y)
                return low<=high && (ground || work.contains(a)) &&
                    !a.insetBy(dx:-radius,dy:-radius).contains(pointer)
            }
            guard let y=candidates.max(by:{abs($0-pointer.y)<abs($1-pointer.y)}) else {
                layout=["pointer":NSStringFromPoint(pointer),"scale":scale,"candidateBaselines":ys,"radius":radius]
                throw failure("No full-size nest corridor clear of the live pointer: \(layout)")
            }
            let rect=CGRect(x:left,y:y,width:width,height:100)
            hostWindow.setFrame(Geometry.quartz(rect,primaryHeight:d.primaryHeight),display:true)
            if ground {hostWindow.orderOut(nil);host=Geometry.ground(id:7301,display:display,workArea:work)}
            else {
                hostWindow.orderFrontRegardless()
                host=Surface(id:UInt32(hostWindow.windowNumber),pid:ProcessInfo.processInfo.processIdentifier,
                    rect:Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight))
            }
            // Force the real placement's left-first/right-fallback rule by using
            // opposite legal ends of the host, never by injecting a tray side.
            let nestX=right ? host.rect.maxX-86*scale:host.rect.minX+86*scale
            target=CGPoint(x:nestX,y:host.rect.minY)
            let x=right ? host.rect.minX+48*effective+16:host.rect.maxX-48*effective-16
            let lo=Geometry.perchX(0,rect:host.rect),hi=Geometry.perchX(1,rect:host.rect)
            let value=Bird(position:.zero,fraction:(x-lo)/(hi-lo),profile:d.catalog.profile(species),random:{0.5})
            value.perch(on:host,spriteScale:d.spriteScale(for:value));value.perchDuration=600;value.facingRight=right
            bird=value;d.surfaces=[host];d.birds=[value];overlay.orderFrontRegardless()
            settle();crop=area(y).intersection(display).insetBy(dx:-8,dy:-8)
            layout=["pointer":NSStringFromPoint(pointer),"scale":scale,"effectiveScale":effective,
                "host":NSStringFromRect(host.rect),"target":NSStringFromPoint(target),"corridor":NSStringFromRect(area(y)),
                "radius":radius,"ground":ground,"right":right]
        }
        func place() throws {
            d.syncWorld(buttonsDown:false)
            let result=d.engine.handle(.placeNest(at:target))
            guard result.accepted,let nest=d.engine.nestSnapshot().first else {throw failure("Production nest placement rejected: \(result), layout \(layout)")}
            layout["nest"]=NSStringFromRect(nest.rect);layout["tray"]=NSStringFromRect(nest.trayRect)
        }
        func start(_ kind:BehaviorKind,source:BehaviorSource = .preview)->BehaviorRunID? {
            d.syncWorld(buttonsDown:false);let sequence=d.engine.events.last?.sequence ?? 0
            if source == .preview {
                if kind == .nestBuild {controls.previewNestBuildButton.performClick(nil)}
                else {controls.previewNestMaterialButton.performClick(nil)}
            } else {
                d.engine.ambientEnabled=source == .automatic
                _=d.engine.handle(kind == .nestBuild ? .nestBuild(source):.nestMaterialCarry(source))
            }
            return d.engine.events.last{$0.sequence>sequence && $0.type == .started && $0.kind==kind}?.runID
        }
        func layer(_ name:String)->CALayer? {view.layer?.sublayers?.first{$0.name==name}}
        func seek(_ predicate:(NestSnapshot,BirdRenderState)->Bool,limit:Double=35)->Bool {
            for _ in 0..<Int(limit*120) {
                guard let nest=d.engine.nestSnapshot().first,let state=d.engine.renderSnapshot().first else {return false}
                if predicate(nest,state) {return true}
                guard let bird,d.engine.behavior(of:bird) != nil else {return false};step()
            };return false
        }
    }

    @discardableResult static func journey(_ f:Fixture,kind:BehaviorKind,source:BehaviorSource,key:String,capture:Bool,
        into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL)->Bool {
        // The throwing rendering implementation is kept separate so a capture
        // error is reported rather than misrepresented as a geometry pass.
        do {return try recordedJourney(f,kind:kind,source:source,key:key,capture:capture,into:&checks,evidence:&evidence,folder:folder)}
        catch {checks[key+"CaptureSucceeded"]=false;evidence.append(["case":key,"captureError":error.localizedDescription]);return false}
    }
    private static func recordedJourney(_ f:Fixture,kind:BehaviorKind,source:BehaviorSource,key:String,capture:Bool,
        into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws -> Bool {
        guard let bird=f.bird,let id=f.d.engine.id(of:bird),let initial=f.d.engine.nestSnapshot().first else {throw failure("Missing real nest fixture")}
        f.settle()
        let d=f.d,build=kind == .nestBuild,limit=build ? 30.0:35.0
        let before=entry(d,kind:kind),beforeCounts=counts(before),other=entry(d,kind:build ? .nestMaterialCarry:.nestBuild)
        let previousIDs=Set(initial.materials.map(\.id)),originalBird=bird
        // Fixture reuse retains lifetime counters, including a departure caused
        // by an earlier host-invalid case. This visit must not change them.
        let arrivalsBefore=d.arrivalCount,departuresBefore=d.departureCount
        guard let run=f.start(kind,source:source),let start=d.engine.events.last(where:{$0.runID==run && $0.type == .started}) else {
            checks[key+"RealCommandAndNativePreviewStart"]=false
            evidence.append(["case":key,"layout":f.layout,"reason":d.engine.events.last?.reason?.rawValue ?? "none"]);return false
        }
        checks[key+"RealCommandAndNativePreviewStart"]=start.source==source && start.participants==[id] && d.engine.leasedBirdCount==1
        let output=folder.appendingPathComponent(key+"journey",isDirectory:true)
        if capture {try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)}
        var images=[URL](),times=[Double](),samples=[[String:Any]](),frames=Set<String>()
        var conservation=true,identities=true,populationStable=true,anchor=true,layerGeometry=true,continuous=true,noEarlyRecord=true
        var pickup=false,delivery=false,commit=false,pickupContinuous=true,deliveryContinuous=true,attachedFlight=false
        var birdPixels=0,twigPixels=0,contactPixels=0,progressPixels=0,platformPixels=0,trayPixels=0
        var paused=0.0,pauseSeen=false,pauseOK=true,visibleSamples=true,contactSamples=true
        var previous=initial,previousProps=d.engine.propSnapshot(),previousFoot=bird.position
        let motionSpeedLimit=CGFloat(FlightBehavior.cruiseSpeed(.spottedDove,multiplier:bird.profile.speed))
        var previousMotionTime=d.engine.time,maxMotionDelta=0.0,maxFootStep:CGFloat=0
        var firstMotionViolation:[String:Any]?
        var selected:ScenePropID?,actualFacing:Bool?
        var previousContact:TwigReadback?,contactReadbacks=0,contactInkPixels=0,contactPixelMismatches=0
        var attachedFlightSamples=0,pickupContactSamples=0,placeContactSamples=0
        var selectedFlightPixels=0,selectedPickupPixels=0,selectedPlacePixels=0,selectedVisible=true
        for tick in 0..<Int((limit+1)*120) {
            guard d.engine.behavior(of:bird)==kind,let nest=d.engine.nestSnapshot().first,
                  let state=d.engine.renderSnapshot().first(where:{$0.id==id}) else {break}
            let props=d.engine.propSnapshot().filter{$0.kind == .twigToken};f.view.updateSprites();frames.insert(state.frameName)
            conservation = conservation && conserved(nest) && nest.progress==nest.arranged
            identities = identities && Set(nest.materials.map(\.id))==previousIDs && d.birds.count==1 && d.birds.first === originalBird &&
                Set(props.map(\.id)).count==props.count
            populationStable = populationStable && d.arrivalCount==arrivalsBefore && d.departureCount==departuresBefore
            // Callbacks may run twice per fixed engine step. HabitatJourney's
            // FlightTiming peak never exceeds this production cruise speed;
            // measure displacement against elapsed simulation time, not 120Hz.
            let motionDelta=d.engine.time-previousMotionTime,footStep=Geometry.distance(previousFoot,bird.position)
            let stepLimit=motionDelta>0 ? motionSpeedLimit*CGFloat(motionDelta)+0.5:CGFloat(1e-5)
            let validStep=motionDelta>=0 && footStep<=stepLimit
            continuous = continuous && validStep
            maxMotionDelta=max(maxMotionDelta,motionDelta);maxFootStep=max(maxFootStep,footStep)
            if !validStep,firstMotionViolation==nil {
                firstMotionViolation=["simulationTime":d.engine.time,"elapsed":motionDelta,"distance":footStep,
                    "limit":stepLimit,"from":NSStringFromPoint(previousFoot),"to":NSStringFromPoint(bird.position),"frame":state.frameName]
            }
            previousFoot=bird.position
            noEarlyRecord = noEarlyRecord && entry(d,kind:kind)==before && entry(d,kind:build ? .nestMaterialCarry:.nestBuild)==other
            for material in nest.materials {
                guard let old=previous.materials.first(where:{$0.id==material.id}) else {identities=false;continue}
                if old.state == .available,material.state == .attached {
                    pickup=true;selected=material.id;actualFacing=state.facingRight
                    pickupContinuous = pickupContinuous && matchingContact(material.id,old:previousProps,new:props)
                }
                if old.state == .attached,material.state == .delivered {
                    delivery=true;deliveryContinuous = deliveryContinuous && matchingContact(material.id,old:previousProps,new:props)
                }
                if old.state == .delivered,material.state == .arranged {commit=true;selected=material.id}
                if capture,!build,(old.state == .available && material.state == .attached || old.state == .attached && material.state == .delivered) {
                    if let previousContact,previousContact.id==material.id,
                       let prop=props.first(where:{$0.id==material.id}),let layer=f.layer("scene-prop-\(material.id.rawValue)") {
                        let current=try twigReadback(prop,layer:layer,view:f.view,worldCrop:previousContact.crop)
                        contactReadbacks+=1;contactInkPixels+=min(previousContact.inkPixels,current.inkPixels)
                        contactPixelMismatches+=zip(previousContact.alpha,current.alpha).filter{$0.0 != $0.1}.count
                        if previousContact.alpha.count != current.alpha.count || previousContact.inkPixels==0 || current.inkPixels==0 {contactPixelMismatches+=1}
                    } else {contactPixelMismatches+=1}
                }
                if material.state == .attached {
                    attachedFlight = attachedFlight || bird.state == .flying
                    if let bill=PoseClip.nestBeakAnchor(species:.spottedDove,frame:state.frameName),let prop=props.first(where:{$0.id==material.id}) {
                        let foot=CGPoint(x:state.position.x,y:state.position.y+state.hopOffset*state.scale)
                        anchor = anchor && material.owner==id && Geometry.distance(prop.position,bill.world(foot:foot,scale:state.scale,facingRight:state.facingRight))<1e-5 &&
                            prop.size==16*d.scale && prop.mirrored == !state.facingRight
                    } else {anchor=false}
                }
            }
            for prop in props {
                guard let layer=f.layer("scene-prop-\(prop.id.rawValue)") else {layerGeometry=false;continue}
                layerGeometry = layerGeometry && twigLayerMatches(prop,layer:layer,view:f.view)
            }
            let transition=nest.materials.map(\.state) != previous.materials.map(\.state)
            if capture,(tick%8==0 || transition) {
                try autoreleasepool {
                    let url=output.appendingPathComponent(String(format:"%04d-actual-layer.png",images.count))
                    let shot=try InsectCatchVerification.snapshot(f.view,around:f.crop,to:url)
                    images.append(url);times.append(d.engine.time-start.time-paused)
                    var b=0,t=0,p=0,base=0,tray=0,selectedPixels=0
                    let selectedID=selected ?? nest.reservation?.materialID
                    if let layer=f.layer("bird-sprite-\(id.rawValue)") {b=try InsectCatchVerification.contribution(f.view,layer:layer,actual:shot,region:state.rect)}
                    for prop in props {if let layer=f.layer("scene-prop-\(prop.id.rawValue)") {
                        let pixels=try InsectCatchVerification.contribution(f.view,layer:layer,actual:shot,region:prop.rect)
                        t+=pixels
                        if prop.id==selectedID {selectedPixels=pixels}
                    }}
                    if !build,let selectedID,let material=nest.materials.first(where:{$0.id==selectedID}) {
                        let inFlight=material.state == .attached && bird.state == .flying
                        let atPickup=material.state == .attached && state.frameName=="carryGrip"
                        let justDelivered=material.state == .delivered && previous.materials.first(where:{$0.id==selectedID})?.state == .attached
                        let atPlace=material.state == .attached && state.frameName=="carryPlace" || justDelivered
                        if inFlight {attachedFlightSamples+=1;selectedFlightPixels+=selectedPixels}
                        if atPickup {pickupContactSamples+=1;selectedPickupPixels+=selectedPixels}
                        if atPlace {placeContactSamples+=1;selectedPlacePixels+=selectedPixels}
                        if inFlight || atPickup || atPlace {selectedVisible = selectedVisible && selectedPixels>0}
                    }
                    if let layer=f.layer("habitat-nest-progress-\(nest.id.rawValue)"),nest.progress>0 {
                        p=try InsectCatchVerification.contribution(f.view,layer:layer,actual:shot,region:nest.rect)
                    }
                    if let layer=f.layer("habitat-nest-platform-\(nest.id.rawValue)") {
                        base=try InsectCatchVerification.contribution(f.view,layer:layer,actual:shot,region:nest.rect)
                        layerGeometry = layerGeometry && close(layer.frame,nest.rect.offsetBy(dx:-f.display.minX,dy:-f.display.minY)) && layer.mask?.mask==nil
                    }
                    if let layer=f.layer("habitat-nest-tray-\(nest.id.rawValue)") {
                        tray=try InsectCatchVerification.contribution(f.view,layer:layer,actual:shot,region:nest.trayRect)
                        layerGeometry = layerGeometry && close(layer.frame,nest.trayRect.offsetBy(dx:-f.display.minX,dy:-f.display.minY)) && layer.mask?.mask==nil
                    }
                    birdPixels+=b;twigPixels+=t;progressPixels+=p
                    platformPixels+=base;trayPixels+=tray;visibleSamples = visibleSamples && b>0 && base>0 && tray>0
                    if transition {contactPixels+=min(b,build ? p:t);contactSamples = contactSamples && b>0 && (build ? p>0:t>0)}
                    samples.append(["image":url.lastPathComponent,"simulationTime":d.engine.time,"runAge":times.last!,
                        "frame":state.frameName,"foot":NSStringFromPoint(state.position),"facingRight":state.facingRight,
                        "birdPixels":b,"twigPixels":t,"selectedMaterial":selectedID?.rawValue ?? 0,"selectedTwigPixels":selectedPixels,
                        "progressPixels":p,"platformPixels":base,"trayPixels":tray,
                        "materials":materialRows(nest),"progress":nest.progress])
                }
            }
            if capture,!pauseSeen,(build ? state.frameName=="nestSettle":nest.attached==1 && bird.state == .flying) {
                pauseSeen=true;d.paused=true
                let poses=d.engine.renderSnapshot(),tokens=d.engine.propSnapshot(),archive=d.observationJournal.archive
                f.advance(0.5);paused+=0.5
                pauseOK=d.engine.nestSnapshot().first==nest && d.engine.renderSnapshot().map(\.position)==poses.map(\.position) &&
                    d.engine.renderSnapshot().map(\.frameName)==poses.map(\.frameName) &&
                    d.engine.propSnapshot().map(\.position)==tokens.map(\.position) && d.observationJournal.archive==archive
                d.paused=false
            }
            previousContact=nil
            if capture,!build,["carryLower","carryPlace"].contains(state.frameName),
               let materialID=nest.reservation?.materialID,let prop=props.first(where:{$0.id==materialID}),
               let layer=f.layer("scene-prop-\(materialID.rawValue)") {
                previousContact=try twigReadback(prop,layer:layer,view:f.view)
            }
            previous=nest;previousProps=props;previousMotionTime=d.engine.time;f.step()
        }
        let ends=terminal(d.engine,run),final=d.engine.nestSnapshot().first,after=entry(d,kind:kind)
        let duration=(ends.first?.time ?? .infinity)-start.time-paused
        let delta=zip(beforeCounts,counts(after)).map{$0.1-$0.0},expected=source == .automatic ? [1,0,0]:(source == .preview ? [0,1,0]:[0,0,1])
        let completed=ends.count==1 && ends.first?.type == .completed
        checks[key+"FullRouteAndHardDeadline"]=completed && duration<=limit+1.0/120+1e-6 && bird.state == .perched &&
            bird.hostID==f.host.id && f.d.surfaces.contains(where:{$0.id==bird.hostID})
        let required=build ? SpeciesBehaviorProfile.nestBuildFrameNames:SpeciesBehaviorProfile.nestCarryFrameNames
        checks[key+"DedicatedFramesAndRealCommit"]=Set(required).isSubset(of:frames) && (build ? commit:pickup && delivery && attachedFlight)
        populationStable = populationStable && d.arrivalCount==arrivalsBefore && d.departureCount==departuresBefore
        checks[key+"ThreeStableMaterialsAndConservation"]=conservation && identities && populationStable && final.map(conserved)==true
        checks[key+"NoPopulationChangeDuringVisit"]=populationStable
        checks[key+"AtomicSingleStep"]=build ? final?.progress==initial.progress+1 && final?.delivered==initial.delivered-1:
            final?.available==initial.available-1 && final?.delivered==initial.delivered+1 && final?.progress==initial.progress
        checks[key+"RealContactAndTextureTransform"]=anchor && layerGeometry && (build || pickupContinuous && deliveryContinuous) && continuous
        checks[key+"ActualTextureAndMaskGeometry"]=layerGeometry
        checks[key+"FootMotionUsesSimulationClock"]=continuous
        if !build {
            checks[key+"BeakAnchorAndAttachmentGeometry"]=pickup && anchor
            checks[key+"PickupBoundsContinuous"]=pickup && pickupContinuous
            checks[key+"DeliveryBoundsContinuous"]=delivery && deliveryContinuous
        }
        checks[key+"UniqueCompletionAndIndependentSource"]=noEarlyRecord && delta==expected &&
            entry(d,kind:build ? .nestMaterialCarry:.nestBuild)==other && clearRun(d.engine)
        if capture {
            checks[key+"NonzeroActualRootContributions"] = !images.isEmpty && visibleSamples && contactSamples &&
                birdPixels>0 && twigPixels>0 && platformPixels>0 && trayPixels>0 && contactPixels>0 && (!build || progressPixels>0)
            checks[key+"PauseFreezesClockAndAllMaterialState"]=pauseSeen && pauseOK
            if !build {
                checks[key+"ActualCarryingDirection"]=actualFacing==(f.layout["right"] as? Bool)
                checks[key+"RootLayerContactInkDoesNotMove"]=contactReadbacks==2 && contactInkPixels>0 && contactPixelMismatches==0
                checks[key+"SelectedAttachedTwigVisibleInActualFlight"]=selectedVisible && attachedFlightSamples>0 && selectedFlightPixels>0
                checks[key+"SelectedTwigVisibleAtActualPickupContact"]=selectedVisible && pickupContactSamples>0 && selectedPickupPixels>0
                checks[key+"SelectedTwigVisibleAtActualPlaceContact"]=selectedVisible && placeContactSamples>0 && selectedPlacePixels>0
            }
            if !images.isEmpty {try InsectCatchVerification.writeGIF(images,times:times,to:folder.appendingPathComponent(key+"actual-layers.gif"))}
        }
        let countAfter=after;f.advance(0.25)
        checks[key+"NoDuplicateCompletionOrCommit"]=terminal(d.engine,run).count==1 && entry(d,kind:kind)==countAfter &&
            d.engine.nestSnapshot().first?.progress==final?.progress && d.engine.nestSnapshot().first?.materials.map(\.id)==final?.materials.map(\.id)
        evidence.append(["case":key,"layout":f.layout,"run":run.rawValue,"kind":kind.rawValue,"source":source.rawValue,
            "unpausedDuration":duration.isFinite ? duration as Any:NSNull(),"terminal":ends.first?.type.rawValue ?? "none",
            "reason":ends.first?.reason?.rawValue ?? "none","selectedMaterial":selected?.rawValue ?? 0,
            "actualFacingRight":actualFacing.map{$0 as Any} ?? NSNull(),"frames":frames.sorted(),"samples":samples,
            "rootContactReadbacks":contactReadbacks,"rootContactInkPixels":contactInkPixels,"rootContactPixelMismatches":contactPixelMismatches,
            "selectedFlightSamples":attachedFlightSamples,"selectedPickupSamples":pickupContactSamples,"selectedPlaceSamples":placeContactSamples,
            "selectedFlightPixels":selectedFlightPixels,"selectedPickupPixels":selectedPickupPixels,"selectedPlacePixels":selectedPlacePixels,
            "geometryInvariants":["anchor":anchor,"layer":layerGeometry,"pickup":pickupContinuous,"delivery":deliveryContinuous,"continuous":continuous],
            "motionSpeedLimit":motionSpeedLimit,"maxMotionDelta":maxMotionDelta,"maxFootStep":maxFootStep,
            "firstMotionViolation":firstMotionViolation as Any? ?? NSNull(),
            "populationBefore":["arrivals":arrivalsBefore,"departures":departuresBefore],
            "populationAfter":["arrivals":d.arrivalCount,"departures":d.departureCount],
            "materialConservation":conservation,"materialAndBirdIdentitiesStable":identities,
            "beforeMaterials":materialRows(initial),"afterMaterials":final.map(materialRows) ?? []])
        return completed
    }

    static func interruptions(_ f:Fixture,build:Bool,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        let kind:BehaviorKind=build ? .nestBuild:.nestMaterialCarry,prefix=build ? "nestBuildNative":"nestMaterialNative"
        let phases=build ? ["beforeCommit","afterCommit"]:["beforePickup","afterPickup","beforeDelivery","afterDelivery"]
        var cases=phases.map{($0,"click")}
        cases += [(phases[0],"disable"),(phases[0],"remove"),(phases[0],"host-invalid"),
            (phases[0],"paused-clear"),(phases[0],"bird-removed"),(phases[0],"sleep"),(phases[0],"shutdown")]
        for (phase,cause) in cases {try autoreleasepool {
            try f.install();try f.place()
            if build {
                let prepared=journey(f,kind:.nestMaterialCarry,source:.preview,key:prefix+"-prepare-\(phase)-\(cause)-",
                    capture:false,into:&checks,evidence:&evidence,folder:folder)
                guard prepared else {checks[prefix+"Interrupt-\(phase)-\(cause)"]=false;return}
                f.settle()
            }
            let d=f.d,key=prefix+"Interrupt-\(phase)-\(cause)",archive=d.observationJournal.archive
            guard let bird=f.bird,let id=d.engine.id(of:bird),let run=f.start(kind) else {checks[key]=false;return}
            let reached=f.seek {nest,state in
                switch phase {
                case "beforePickup":return state.frameName=="carryLower" && nest.available==3
                case "afterPickup":return nest.attached==1 && state.frameName=="carryLook"
                case "beforeDelivery":return nest.attached==1 && state.frameName=="carryPlace"
                case "afterDelivery":return nest.delivered==1
                case "beforeCommit":return state.frameName=="nestSettle" && nest.progress==0
                default:return nest.progress==1
                }
            }
            let before=d.engine.nestSnapshot().first,foot=bird.position,sequence=d.engine.events.last?.sequence ?? 0
            var hit=false,relocated=false
            switch cause {
            case "click":
                if let state=d.engine.renderSnapshot().first,let p=InsectCatchVerification.visiblePoint(state,in:d) {
                    hit=d.bird(at:p) === bird
                    if hit,let cg=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:p,mouseButton:.left),let event=NSEvent(cgEvent:cg) {
                        d.handleMouseDown(event)
                        relocated=d.engine.events.contains{$0.sequence>sequence && $0.kind == .relocate && $0.type == .started && $0.participants==[id]}
                    }
                }
            case "disable":var settings=d.settings;settings.nestBuildingEnabled=false;d.settings=settings
            case "remove":d.engine.handle(.removeNest)
            case "host-invalid":d.surfaces=[];d.syncWorld(buttonsDown:false)
            case "paused-clear":d.paused=true;d.engine.handle(.clearCurrentScene)
            case "bird-removed":d.engine.handle(.remove(id))
            case "sleep":d.engine.handle(.cancelAmbient(.sleep))
            default:d.engine.handle(.cancelAmbient(.shutdown))
            }
            let ends=terminal(d.engine,run),after=d.engine.nestSnapshot().first
            checks[key]=reached && ends.count==1 && ends.first?.type != .completed &&
                d.observationJournal.archive==archive && (cause != "click" || hit && relocated && ends.first?.reason == .replaced) &&
                Geometry.distance(foot,bird.position)<0.001
            if cause=="click",let before,let after {
                checks[key+"ConservationAndCommittedState"]=conserved(after) && after.progress==before.progress &&
                    after.delivered==before.delivered && after.available==before.available && after.attached==0 &&
                    after.spent==before.spent+before.attached
            }
            d.paused=false
            for _ in 0..<36*120 {
                if d.engine.behavior(of:bird)==nil {break};f.step()
            }
            f.advance(0.25)
            if cause=="click" {checks[key+"ActualRelocationCompletes"]=bird.state == .perched && d.engine.behavior(of:bird)==nil}
            d.engine.handle(.clearCurrentScene);f.advance(3);f.view.updateSprites()
            checks[key+"FinalCleanup"]=clear(d.engine)
            evidence.append(["interrupt":key,"reached":reached,"hitOriginal":hit,"relocateStarted":relocated,
                "reason":ends.first?.reason?.rawValue ?? "none","before":before.map(materialRows) ?? [],"after":after.map(materialRows) ?? []])
        }}
    }
    static func conserved(_ nest:NestSnapshot)->Bool {
        nest.materials.count==3 && Set(nest.materials.map(\.id)).count==3 &&
            nest.available+nest.attached+nest.delivered+nest.arranged+nest.spent==3 && nest.attached<=1
    }
    static func clearRun(_ engine:BehaviorEngine)->Bool {engine.activeRunCount==0 && engine.leasedBirdCount==0 && engine.reservedLandingCount==0 && engine.habitatReservationCount==0}
    static func clear(_ engine:BehaviorEngine)->Bool {clearRun(engine) && engine.nestSnapshot().isEmpty && engine.scenePropCount==0 && !engine.hasNestPlacement}
    static func entry(_ d:DesktopController,kind:BehaviorKind)->ObservationEntry? {d.observationJournal.archive.entries.first{$0.species == .spottedDove && $0.behavior==kind.rawValue}}
    static func counts(_ entry:ObservationEntry?)->[Int] {[entry?.automaticCount ?? 0,entry?.previewCount ?? 0,entry?.userCount ?? 0]}
    static func terminal(_ engine:BehaviorEngine,_ run:BehaviorRunID)->[BehaviorEvent] {engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}}
    static func materialRows(_ nest:NestSnapshot)->[[String:Any]] {nest.materials.map{["id":$0.id.rawValue,"slot":$0.slot,"state":$0.state.rawValue,
        "owner":$0.owner?.rawValue ?? 0,"position":NSStringFromPoint($0.position),"pickupRun":$0.pickupRunID?.rawValue ?? 0,
        "deliveryRun":$0.deliveryRunID?.rawValue ?? 0,"arrangementRun":$0.arrangementRunID?.rawValue ?? 0]}}
    static func report(_ checks:[String:Bool],evidence:[[String:Any]],prefix:String,folder:URL,completed:Bool,caseErrors:[String:String]=[:]) {
        let own=checks.filter{$0.key.hasPrefix(prefix)}
        let checksPassed = !own.isEmpty && own.values.allSatisfy{$0}
        saveJSON(["passed":completed && caseErrors.isEmpty && checksPassed,"completed":completed,"checksPassed":checksPassed,
            "caseErrors":caseErrors,"checks":own,"evidence":evidence,
            "scope":"Real production placement/preview/automatic commands, existing isolated residents, actual root-layer pixels. No system event injection, controller startup or user persistence. Core covers dt/replay/negative displays/pressure."],to:folder.appendingPathComponent("report.json"))
    }
    static func failure(_ text:String)->NSError {NSError(domain:"NestNativeVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
    private static func matchingContact(_ id:ScenePropID,old:[ScenePropRenderState],new:[ScenePropRenderState])->Bool {
        guard let a=old.first(where:{$0.id==id}),let b=new.first(where:{$0.id==id}) else {return false}
        return close(a.rect,b.rect)
    }
    static func close(_ a:CGRect,_ b:CGRect)->Bool {abs(a.minX-b.minX)<0.001 && abs(a.minY-b.minY)<0.001 && abs(a.width-b.width)<0.001 && abs(a.height-b.height)<0.001}
    private struct TwigReadback {
        let id:ScenePropID,crop:CGRect,alpha:[UInt8]
        var inkPixels:Int {alpha.filter{$0>0}.count}
    }
    /// Diagnostic subtraction of siblings from the actual root, with the real
    /// texture transform and mask intact. Full production screenshots above
    /// remain untouched. A shared world crop detects any pickup/delivery shift.
    private static func twigReadback(_ prop:ScenePropRenderState,layer:CALayer,view:DesktopView,worldCrop:CGRect?=nil) throws -> TwigReadback {
        guard let root=view.layer else {throw failure("Missing actual nest root layer")}
        let requested=worldCrop ?? prop.rect.insetBy(dx:-2,dy:-2)
        let local=requested.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY).intersection(view.bounds).integral
        guard !local.isEmpty,let context=CGContext(data:nil,width:Int(local.width),height:Int(local.height),bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot read actual twig contact pixels")}
        CATransaction.begin();CATransaction.setDisableActions(true)
        let siblings=(root.sublayers ?? []).filter{$0 !== layer},hidden=siblings.map(\.isHidden)
        for sibling in siblings {sibling.isHidden=true}
        defer {for (sibling,wasHidden) in zip(siblings,hidden) {sibling.isHidden=wasHidden};CATransaction.commit()}
        context.translateBy(x:0,y:local.height);context.scaleBy(x:1,y:-1)
        context.translateBy(x:-local.minX,y:-local.minY);root.render(in:context)
        guard let image=context.makeImage() else {throw failure("Missing twig contact raster")}
        let raster=try BathArtVerification.Raster(image)
        var alpha=[UInt8]();alpha.reserveCapacity(raster.width*raster.height)
        for y in 0..<raster.height {for x in 0..<raster.width {alpha.append(raster.alpha(x,y))}}
        return TwigReadback(id:prop.id,crop:local.offsetBy(dx:view.desktopRect.minX,dy:view.desktopRect.minY),alpha:alpha)
    }
    static func twigLayerMatches(_ prop:ScenePropRenderState,layer:CALayer,view:DesktopView)->Bool {
        guard let root=view.layer,let texture=layer.sublayers?.first,let mask=layer.mask as? CAShapeLayer,
              let canvas=TwigGeometry.canvasBounds(position:prop.position,anchor:CGPoint(x:prop.anchor.x*16,y:prop.anchor.y*16),
                worldScale:prop.size/16,facingRight:!prop.mirrored,rotation:prop.rotation) else {return false}
        let grip=texture.convert(CGPoint(x:prop.anchor.x*prop.size,y:prop.anchor.y*prop.size),to:root)
        let corners=[CGPoint.zero,CGPoint(x:prop.size,y:0),CGPoint(x:0,y:prop.size),CGPoint(x:prop.size,y:prop.size)].map{texture.convert($0,to:root)}
        let xs=corners.map(\.x),ys=corners.map(\.y)
        let actual=CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
        let c=cos(prop.rotation),s=sin(prop.rotation),m:CGFloat=prop.mirrored ? -1:1,tr=texture.affineTransform()
        return close(layer.frame,prop.rect.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY)) &&
            close(actual,canvas.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY)) &&
            Geometry.distance(grip,CGPoint(x:prop.position.x-view.desktopRect.minX,y:prop.position.y-view.desktopRect.minY))<1e-5 &&
            texture.bounds.size==CGSize(width:prop.size,height:prop.size) && texture.anchorPoint==prop.anchor &&
            abs(tr.a-c*m)<1e-5 && abs(tr.b-s*m)<1e-5 && abs(tr.c+s)<1e-5 && abs(tr.d-c)<1e-5 &&
            (texture.contents as AnyObject?) === NestArt.twigImage() && mask.mask==nil && mask.path != nil && !layer.isHidden
    }
}
