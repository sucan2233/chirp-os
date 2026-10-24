import AppKit
import BirdingCore

/// Actual production controls, routes, persistent leaf identity and root-layer
/// captures. Durable quota and real two-process races have a separate owner.
enum GiftVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("gift-native-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("giftNative")},"evidence":evidence,
            "limits":"Unmodified production root CALayers on the attached display, ordinary fixture hosts and real pointer sampling. Negative-screen geometry belongs to core coverage; no physical hotplug or WindowServer claim."],to:output.appendingPathComponent("report.json"))}
        try autoreleasepool {
            let f=try Fixture(folder:output);defer {f.close()}
            for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
                try journey(f,scale:scale,right:right,into:&checks,evidence:&evidence,folder:output)
            }}
            try interruptions(f,into:&checks,evidence:&evidence,folder:output)
            try authorizations(f,into:&checks,evidence:&evidence)
            try separateControllerSessions(f,into:&checks)
            checks["giftNativeIsolatedResourcesAndNoLedgerForPreview"]=f.d.timer==nil && f.d.views.isEmpty && f.d.panels.isEmpty &&
                f.d.globalMouseMonitor==nil && f.d.localMouseMonitor==nil && !f.d.automaticPopulation &&
                f.d.giftLedgerPersistence==nil && f.d.visitorMemoryPersistence==nil &&
                !FileManager.default.fileExists(atPath:f.d.giftLedgerURL.path) &&
                !FileManager.default.fileExists(atPath:f.d.visitorMemoryURL.path) &&
                !FileManager.default.fileExists(atPath:f.d.observationJournalURL.path)
        }
        try autoreleasepool {try automaticDelivery(into:&checks,evidence:&evidence,folder:output)}
    }
    private final class Fixture {
        let d:DesktopController,window:OverlayPanel,view:DesktopView,settings:SpeciesSettingsWindow
        let work:CGRect,display:CGRect,suite:String,preferences:UserDefaults
        var archive:VisitorMemoryArchive
        var bird:Bird!,host:Surface!,leafID:ScenePropID!,receiver:ResolvedFixedPerch!
        var layoutEvidence=[String:Any]()
        var leafPoint=CGPoint.zero
        var observedVisibleRuns=Set<UInt64>()
        init(folder:URL) throws {
            let d=DesktopController(verificationSeed:0x474946544E415449);self.d=d
            guard let screen=NSScreen.screens.first,let work=d.screenRects.first,let display=d.displayRects.first,
                  work.width>=1000,work.height>=620 else {throw failure("Gift native verification requires a 1000 × 620 work area")}
            self.work=work;self.display=display
            let memory=VisitorMemory(seed:73)
            guard let visitor=memory.acquire(species:.azureWingedMagpie) else {throw failure("Cannot seed isolated visitor")}
            for _ in 0..<4000 {memory.learn(visitor.id,elapsed:0.05)}
            for _ in 0..<2 {memory.release(visitor.id);_=memory.acquire(species:.azureWingedMagpie)}
            archive=memory.archive
            suite="Birding.GiftVerification."+UUID().uuidString
            guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate preferences")}
            self.preferences=preferences;d.preferences=preferences;d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            d.pointerButtonsDown={false};d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false
            d.giftLedgerPersistenceEnabled=false;d.giftLedgerURL=folder.appendingPathComponent("gifts.json")
            d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("visitors.json");d.observationJournalURL=folder.appendingPathComponent("journal.json")
            window=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
            view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size));view.controller=d;view.desktopRect=display
            window.contentView=view;window.orderFrontRegardless()
            settings=SpeciesSettingsWindow(desktop:d);d.settingsWindow=settings
            d.engine.observationObserver={ [weak self,weak d] event in
                guard let d else {return}
                if let self,event.kind == .visitorGift,let object=d.engine.carriedObjectSnapshot().first(where:{$0.id==self.leafID}),
                   object.isVisitorGift,object.state == .placed,object.giftDelivery?.arrived==true,
                   let prop=d.engine.propSnapshot().first(where:{$0.id==object.id}),prop.opacity>0,
                   prop.blockers.allSatisfy({!$0.intersects(prop.rect)}) {
                    self.observedVisibleRuns.insert(event.runID)
                }
                _=d.observationJournal.observe(event,at:Date(timeIntervalSince1970:1_700_000_000+event.simulationTime))
            }
        }
        func close() {
            d.cancelGiftAuthorization();d.engine.handle(.cancelAmbient(.shutdown));d.giftAuthorizationProvider=nil
            settings.cancel();d.settingsWindow=nil;d.engine.observationObserver=nil
            window.orderOut(nil);window.close();preferences.removePersistentDomain(forName:suite)
        }
        func install(scale:CGFloat=1,right:Bool=true) throws -> BehaviorResult {
            d.cancelGiftAuthorization();d.engine.handle(.cancelAmbient(.shutdown));d.engine.handle(.clearCurrentScene)
            d.giftAuthorizationProvider=nil;d.birds=[];d.paused=false;d.scale=scale
            d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            try d.engine.restoreVisitorMemory(archive)
            var value=d.settings;value.visitorGiftsEnabled=true;value.visitorMemoryEnabled=true;value.fixedPerchesEnabled=true
            value.leafCarryEnabled=true;value.perchActions=false;value.passiveAttentionEnabled=false
            value.pointerVisits=false;value.flockPasses=false;value.socialInteractions=false;value.ambientLeafPlayEnabled=false
            value.hoverDelay=0
            let profile=d.catalog.profile(.azureWingedMagpie),effective=scale*profile.relativeScale
            // Read the same authored anchors and both token headings as the
            // production carrier envelope, including transport/stand frames.
            // This arranges ordinary fixture geometry; admission still runs
            // exclusively through the native button and production planner.
            var area=Geometry.landingFootprint(at:.zero,scale:effective)
            for name in CarryArtGeometry.frameNames+TransportArtGeometry.frameNames {
                guard let anchor=PoseClip.carryBeakAnchor(species:.azureWingedMagpie,frame:name) else {
                    throw failure("Gift fixture is missing carrier anchor "+name)
                }
                for facing in [true,false] {for leafFacing in [true,false] {
                    area=area.union(CarriedObjectGeometry.bounds(
                        position:anchor.world(foot:.zero,scale:effective,facingRight:facing),
                        anchor:CarriedObjectGeometry.grip,worldScale:scale,facingRight:leafFacing))
                }}
            }
            let base=CGRect(x:work.minX+40,y:0,width:work.width-80,height:100)
            let originX=Geometry.foot(on:Surface(id:7601,pid:42,rect:base),fraction:right ? 0.16:0.84,edge:.top,scale:effective).x
            let leafX=work.minX+work.width*(right ? 0.38:0.62)
            let pickupX=CarriedObjectGeometry.pickupFoot(surface:CGPoint(x:leafX,y:0),worldScale:scale,
                birdScale:effective,facingRight:right).x
            guard let releaseAnchor=PoseClip.carryBeakAnchor(species:.azureWingedMagpie,frame:"carryPlace") else {
                throw failure("Gift fixture is missing release anchor")
            }
            // Equal pickup/release foot heights bound the complete approach,
            // carrying and turning return arcs inside one horizontal band.
            // HabitatJourney's arc is <= min(90*s, distance*.2). The other
            // cubics have one raised control; max(3*t*(1-t)^2) is 4/9.
            let receiverOffset=48*scale+releaseAnchor.world(foot:.zero,scale:effective,facingRight:right).y
            let approachLift=min(90*effective,abs(pickupX-originX)*0.2)
            let lift=max(approachLift,max(80*scale,80*effective)*4/9)
            let peak=max(FlightBehavior.cruiseSpeed(.azureWingedMagpie,multiplier:profile.speed),160*Double(scale))
            let padding=CGFloat(peak/60)+4+8
            let above=lift-area.minY+padding
            let below=max(100,max(area.maxY+padding,receiverOffset+28*scale))
            let pointer=d.pointerPosition,radius=max(100,72*effective)
            let protected=CGRect(x:pointer.x-radius,y:pointer.y-radius,width:2*radius,height:2*radius)
            let low=ceil(work.minY+above+8),high=floor(work.maxY-below-8)
            func corridor(_ y:CGFloat)->CGRect {
                CGRect(x:work.minX,y:y-above,width:work.width,height:above+below)
            }
            let heights=low<=high ? [low,high]:[]
            layoutEvidence=["pointer":NSStringFromPoint(pointer),"pointerRadius":radius,
                "carrierLocalFootprint":NSStringFromRect(area),"effectiveBirdScale":effective,
                "candidateCorridors":heights.map{NSStringFromRect(corridor($0))}]
            guard let baseline=heights.first(where:{work.contains(corridor($0)) && display.contains(corridor($0)) &&
                !corridor($0).intersects(protected)}) else {
                throw failure("Gift fixture has no complete corridor clear of the live pointer; move the pointer toward a screen edge. Production admission was not bypassed.")
            }
            let receiverX=work.minX+work.width*(right ? 0.80:0.20),receiverY=baseline+receiverOffset
            guard let anchor=FixedPerchAnchor.capture(slot:1,point:CGPoint(x:receiverX,y:receiverY),
                displayIDs:d.fixedPerchDisplayIDs,displays:d.displayRects) else {throw failure("Cannot capture receiving anchor")}
            value.fixedPerches=[anchor];d.settings=value
            // DestinationPlanner requires ordinary recovery/relocation windows
            // to be at least 100pt tall. A 45pt host forced hostless fallback.
            host=Surface(id:7601,pid:42,rect:base.offsetBy(dx:0,dy:baseline))
            leafPoint=CGPoint(x:leafX,y:baseline)
            layoutEvidence["corridor"]=NSStringFromRect(corridor(baseline))
            layoutEvidence["hostRect"]=NSStringFromRect(host.rect)
            layoutEvidence["leafSurface"]=NSStringFromPoint(leafPoint)
            layoutEvidence["receiverFoot"]=NSStringFromPoint(CGPoint(x:receiverX,y:receiverY))
            bird=Bird(position:.zero,fraction:right ? 0.16:0.84,profile:d.catalog.profile(.azureWingedMagpie),random:{0.5})
            bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;bird.facingRight=right
            // Placement's existing production rule derives leaf orientation
            // from a nearby eligible sparrow. Remove that fixture resident only
            // after the real placement command; never mutate a leaf store.
            let helper=Bird(position:.zero,fraction:right ? 0.02:0.98,profile:d.catalog.profile(.treeSparrow),random:{0.5})
            helper.perch(on:host,spriteScale:d.spriteScale(for:helper));helper.perchDuration=600
            d.surfaces=[host];d.birds=[bird,helper];advance(9)
            for _ in 0..<5*120 {
                if let state=d.engine.renderSnapshot().first(where:{$0.species == .azureWingedMagpie}),abs(state.hopOffset)<0.001 {break}
                step()
            }
            d.syncWorld(buttonsDown:false)
            receiver=d.engine.fixedPerchSnapshot().first
            let placed=d.engine.handle(.placeCarryLeaf(at:leafPoint))
            d.birds=[bird];d.syncWorld(buttonsDown:false)
            leafID=d.engine.carriedObjectSnapshot().first?.id
            settings.refreshVisitorGiftControls()
            return placed
        }
        func start()->BehaviorRunID? {
            let sequence=d.engine.events.last?.sequence ?? 0
            settings.previewVisitorGiftButton.performClick(nil)
            // Drain only the platform's asynchronous memory-token callback;
            // no simulation time, resident motion or route is manufactured.
            let deadline=ProcessInfo.processInfo.systemUptime+0.5
            while d.engine.giftAuthorizationRequest != nil,ProcessInfo.processInfo.systemUptime<deadline {
                _=RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.001))
            }
            return d.engine.events.last{$0.sequence>sequence && $0.kind == .visitorGift && $0.type == .started}?.runID
        }
        func step() {d.syncWorld(buttonsDown:false);d.engine.advance(1.0/120);d.reconcileGiftAuthorization()}
        func advance(_ seconds:Double) {for _ in 0..<Int((seconds*120).rounded()) {step()}}
        func prop()->CALayer? {guard let leafID else {return nil};return view.layer?.sublayers?.first{$0.name=="scene-prop-\(leafID.rawValue)"}}
        func sprite()->CALayer? {guard let id=d.engine.id(of:bird) else {return nil};return view.layer?.sublayers?.first{$0.name=="bird-sprite-\(id.rawValue)"}}
    }
    private static func journey(_ f:Fixture,scale:CGFloat,right:Bool,into checks:inout [String:Bool],
                                evidence:inout [[String:Any]],folder:URL) throws {
        let placed=try f.install(scale:scale,right:right),d=f.d,bird=f.bird!
        d.language=right ? .chinese:.english;f.settings.relocalize()
        let key="giftNative-\(scale)-\(right ? "right":"left")-",before=count(d),landings=bird.landedCount
        let initial=d.engine.carriedObjectSnapshot().first,origin=bird.position,id=d.engine.id(of:bird)
        let run=f.start()
        checks[key+"RealPlacementAndNativePreviewStart"]=placed.accepted && run != nil && initial?.facingRight==right &&
            bird.position==origin && d.residentCount==1 && d.engine.visitor(of:bird).map{$0.visits>=3 && $0.familiarity>=0.6}==true &&
            !SpeciesBehaviorProfile.species(for:.fixedPerchVisit).contains(.azureWingedMagpie) && f.receiver != nil
        guard let run,let initial,let receiver=f.receiver,
              let start=d.engine.events.first(where:{$0.runID==run && $0.type == .started}) else {
            evidence.append(["case":key,"placement":String(describing:placed),"reason":d.engine.events.last?.reason?.rawValue ?? "none",
                "layout":f.layoutEvidence]);return
        }
        let output=folder.appendingPathComponent(key+"journey",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var images=[URL](),times=[Double](),samples=[[String:Any]](),phases=Set<String>(),frames=Set<String>()
        var sameID=true,geometry=true,continuous=true,neverBranch=true,noEarlyCount=true
        var pickup=false,carrying=false,released=false,arrived=false,releaseTime:Double?,arrivalTime:Double?
        var pauseDone=false,pauseOK=false,pausedDuration=0.0,leafPixels=0,birdPixels=0,layerSamples=0,visibleSamples=0
        var previous=bird.position,previousProp=d.engine.propSnapshot().first{$0.id==initial.id},previousState=initial.state
        for tick in 0..<36*120 {
            guard d.engine.behavior(of:bird) == .visitorGift,let state=d.engine.renderSnapshot().first,
                  let object=d.engine.carriedObjectSnapshot().first,let prop=d.engine.propSnapshot().first(where:{$0.id==initial.id}) else {break}
            f.view.updateSprites();frames.insert(state.frameName)
            sameID = sameID && object.id==initial.id && prop.id==initial.id && d.engine.carriedObjectSnapshot().count==1 &&
                d.engine.propSnapshot().filter{$0.kind == .leafToken}.count==1 && d.engine.id(of:bird)==id && d.birds.count==1
            continuous = continuous && Geometry.distance(previous,bird.position)<max(20,20*state.scale)
            previous=bird.position
            neverBranch = neverBranch && !(bird.state == .perched && bird.hostID==receiver.surface.id) &&
                !(bird.state == .landing && bird.hostID==receiver.surface.id)
            if object.giftDelivery?.arrived != true {noEarlyCount = noEarlyCount && count(d)==before}
            if previousState == .available,object.state == .attached {
                pickup=true
                geometry = geometry && previousProp.map{close($0.rect,prop.rect)}==true
            }
            if object.state == .attached {
                carrying = carrying || bird.state == .flying
                if let beak=PoseClip.carryBeakAnchor(species:.azureWingedMagpie,frame:state.frameName) {
                    let foot=CGPoint(x:state.position.x,y:state.position.y+state.hopOffset*state.scale)
                    geometry = geometry && Geometry.distance(prop.position,beak.world(foot:foot,scale:state.scale,facingRight:state.facingRight))<1e-5 && object.owner==id
                } else {geometry=false}
            }
            if let delivery=object.giftDelivery {
                if !released {
                    released=true;releaseTime=d.engine.time-pausedDuration
                    let beak=PoseClip.carryBeakAnchor(species:.azureWingedMagpie,frame:"carryPlace")?.world(foot:state.position,scale:state.scale,facingRight:right)
                    geometry = geometry && beak.map{Geometry.distance($0,delivery.releaseGrip)<1e-5}==true &&
                        delivery.receiverSlot==receiver.slot && delivery.receiverRevision>0 && delivery.receiverFoot==receiver.foot &&
                        delivery.duration<=GiftReceiverGeometry.maximumFallDuration && object.owner==nil && bird.state == .flying
                }
                if delivery.arrived,!arrived {arrived=true;arrivalTime=d.engine.time-pausedDuration}
            }
            let phase=object.giftDelivery.map{$0.arrived ? "received":"falling"} ??
                (object.state == .attached ? (bird.state == .flying ? "carrying":"pickup-grip"):
                    (bird.state == .perched ? state.frameName:"approach"))
            let first=phases.insert(phase).inserted
            if tick%8==0 || first || (object.giftDelivery?.arrived==false && tick%4==0) {
                try autoreleasepool {
                    let file=output.appendingPathComponent(String(format:"%04d-actual-layer.png",images.count))
                    let actual=try InsectCatchVerification.snapshot(f.view,around:f.work,to:file)
                    images.append(file);times.append(d.engine.time-start.time-pausedDuration)
                    samples.append(["image":file.lastPathComponent,"simulationTime":d.engine.time,"unpausedRunAge":times.last!,
                        "phase":phase,"frame":state.frameName,"bird":NSStringFromPoint(state.position),"state":bird.state.rawValue,
                        "leafID":object.id.rawValue,"leafRect":NSStringFromRect(prop.rect),"deliveryAge":object.giftDelivery.map{$0.age as Any} ?? NSNull(),
                        "previewCount":count(d)])
                    if first,let leaf=f.prop(),let sprite=f.sprite() {
                        let lp=try InsectCatchVerification.contribution(f.view,layer:leaf,actual:actual,region:prop.rect)
                        let bp=try InsectCatchVerification.contribution(f.view,layer:sprite,actual:actual,region:state.rect)
                        leafPixels+=lp;birdPixels+=bp;layerSamples+=1
                        geometry = geometry && lp>0 && bp>=4 && layerMatches(prop,layer:leaf,view:f.view)
                        if deliverySurfaceMatches(object,prop:prop,layer:leaf,view:f.view,foot:receiver.foot) {visibleSamples+=1}
                    }
                }
            }
            if !pauseDone,object.state == .attached,bird.state == .flying {
                pauseDone=true;d.paused=true;let frozen=prop,foot=bird.position,archive=d.observationJournal.archive
                f.advance(1);pausedDuration+=1
                pauseOK=d.engine.propSnapshot().first{$0.id==initial.id}?.position==frozen.position && bird.position==foot &&
                    d.engine.carriedObjectSnapshot().first?.state == .attached && d.observationJournal.archive==archive
                d.paused=false
            }
            previousState=object.state;previousProp=prop;f.step()
        }
        f.view.updateSprites()
        let ends=terminal(d.engine,run:run),object=d.engine.carriedObjectSnapshot().first
        // Arrival can finish a run in the very same fixed step. Its terminal
        // snapshot and observation still establish that exact visible endpoint.
        if !arrived,object?.giftDelivery?.arrived==true {
            arrived=true;arrivalTime=d.engine.time-pausedDuration
        }
        if let prop=d.engine.propSnapshot().first(where:{$0.id==initial.id}),let leaf=f.prop() {
            let file=output.appendingPathComponent("delivered-actual-layer.png")
            let actual=try InsectCatchVerification.snapshot(f.view,around:f.work,to:file)
            let n=try InsectCatchVerification.contribution(f.view,layer:leaf,actual:actual,region:prop.rect)
            leafPixels+=n;geometry = geometry && n>0
            if let object,deliverySurfaceMatches(object,prop:prop,layer:leaf,view:f.view,foot:receiver.foot) {visibleSamples+=1}
            images.append(file);times.append(d.engine.time-start.time-pausedDuration)
        }
        let gif=folder.appendingPathComponent(key+"journey-actual-layers.gif")
        if !images.isEmpty {try InsectCatchVerification.writeGIF(images,times:times,to:gif)}
        checks[key+"RealPickupFlyPastReleaseAndReceivedGift"]=pickup && carrying && released && arrived &&
            Set(CarryArtGeometry.frameNames).isSubset(of:frames) && object?.giftDelivery?.arrived==true && bird.state == .perched && bird.landedCount>=landings+2
        checks[key+"DropWithinPointEightSeconds"]=releaseTime != nil && arrivalTime != nil &&
            arrivalTime! - releaseTime! <= 0.8+1e-8 && arrivalTime! > releaseTime!
        checks[key+"VisibleReceiverBeforeUniquePreviewRecord"]=noEarlyCount && ends.count==1 && ends.first?.type == .completed &&
            f.observedVisibleRuns.contains(run.rawValue) && count(d)==before+1 && visibleSamples>0 &&
            (ends.first?.time ?? .infinity)-start.time-pausedDuration<=35+1e-8
        checks[key+"SameEntityNoTeleportAndNoBranchLanding"]=sameID && continuous && neverBranch && d.arrivalCount==0 && d.departureCount==0
        checks[key+"ActualMirroredLayersHaveBirdAndGiftPixels"]=geometry && leafPixels>0 && birdPixels>0 && layerSamples>=4 && visibleSamples>0
        checks[key+"PauseFreezesAttachmentAndCount"]=pauseDone && pauseOK
        checks[key+"TerminalReleasesLeasesAndToken"]=clear(d.engine) && object?.owner==nil && object?.reservedByRun==nil
        let beforeClear=count(d),entity=object?.id
        f.settings.clearVisitorGiftButton.performClick(nil);f.advance(0.3);f.view.updateSprites()
        checks[key+"ClearRemovesGiftAndLayerWithoutCounting"]=d.engine.carriedObjectSnapshot().isEmpty && f.prop()==nil &&
            count(d)==beforeClear && clear(d.engine) && entity==initial.id
        evidence.append(["case":key,"source":"production native preview button / asynchronous memory token; no ledger IO",
            "releaseTime":releaseTime.map{$0 as Any} ?? NSNull(),"arrivalTime":arrivalTime.map{$0 as Any} ?? NSNull(),
            "dropSeconds":releaseTime.flatMap{a in arrivalTime.map{$0-a}}.map{$0 as Any} ?? NSNull(),
            "terminal":ends.first?.type.rawValue ?? "none","reason":ends.first?.reason?.rawValue ?? "none",
            "birdPixels":birdPixels,"giftPixels":leafPixels,"visibleReceiverSamples":visibleSamples,
            "samples":samples,"journeyGIF":gif.lastPathComponent,"layout":f.layoutEvidence,
            "capture":"Actual root CALayer, 15 Hz plus phase changes and 30 Hz descent; JSON simulation timestamps authoritative."])
    }
    private static func interruptions(_ f:Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        for action in ["click","clear","disable","sleep"] {
            let placed=try f.install(),d=f.d,before=d.observationJournal.archive,bird=f.bird!
            guard placed.accepted,let run=f.start() else {checks["giftNativeInterrupt-"+action]=false;continue}
            var attached=false
            for _ in 0..<35*120 {
                if d.engine.carriedObjectSnapshot().first?.state == .attached,bird.state == .flying {attached=true;break}
                if d.engine.behavior(of:bird) != .visitorGift {break};f.step()
            }
            f.view.updateSprites();let sequence=d.engine.events.last?.sequence ?? 0,position=bird.position
            var hit=false,relocated=false
            switch action {
            case "click":
                if let state=d.engine.renderSnapshot().first,let point=InsectCatchVerification.visiblePoint(state,in:d) {
                    hit=d.bird(at:point) === bird
                    if hit,let cg=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left),let event=NSEvent(cgEvent:cg) {d.handleMouseDown(event)}
                }
                relocated=d.engine.events.contains{$0.sequence>sequence && $0.kind == .relocate && $0.type == .started} && d.engine.behavior(of:bird) == .relocate
            case "clear":f.settings.clearVisitorGiftButton.performClick(nil)
            case "disable":var value=d.settings;value.visitorGiftsEnabled=false;d.settings=value
            default:d.engine.handle(.cancelAmbient(.sleep))
            }
            let noJump=Geometry.distance(position,bird.position)<1e-5
            f.advance(0.3)
            if action=="click" {
                for _ in 0..<35*120 {if d.engine.behavior(of:bird) != .relocate {break};f.step()}
            }
            f.view.updateSprites()
            let ends=terminal(d.engine,run:run)
            checks["giftNativeInterrupt-"+action]=attached && ends.count==1 && ends.first?.type != .completed &&
                noJump && clear(d.engine) && d.engine.carriedObjectSnapshot().isEmpty && f.prop()==nil && d.observationJournal.archive==before
            let relocationEnds=d.engine.events.filter{$0.sequence>sequence && $0.kind == .relocate && [.completed,.failed,.cancelled].contains($0.type)}
            let landed=bird.state == .perched && bird.hostID==f.host.id && d.surfaces.contains(f.host) &&
                Geometry.distance(bird.position,Geometry.foot(on:f.host,fraction:bird.fraction,edge:bird.edge,scale:d.spriteScale(for:bird)))<1e-5
            if action=="click" {
                checks["giftNativeActualClickHitsCarrierAndStartsRelocation"]=hit && relocated && ends.first?.reason == .replaced
                checks["giftNativeActualClickRelocationCompletesOnOrdinaryHost"]=relocationEnds.count==1 && relocationEnds.first?.type == .completed && landed
            }
            if let state=d.engine.renderSnapshot().first {
                _=try InsectCatchVerification.snapshot(f.view,around:state.rect.insetBy(dx:-30,dy:-30),to:folder.appendingPathComponent("gift-interrupt-"+action+"-actual-layer.png"))
            }
            evidence.append(["interrupt":action,"attached":attached,"hitOriginal":hit,"relocationStarted":relocated,
                "relocationTerminal":relocationEnds.first?.type.rawValue ?? "none","landedOnOrdinaryHost":landed,
                "resourcesClear":clear(d.engine),"journalUnchanged":d.observationJournal.archive==before,
                "layout":f.layoutEvidence,"reason":ends.first?.reason?.rawValue ?? "none"])
        }
    }
    private static func authorizations(_ f:Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]]) throws {
        for action in ["cancel","pause","close","replacement"] {
            let placed=try f.install(),d=f.d,before=d.observationJournal.archive
            var held=[(GiftAuthorizationRequest,(GiftAuthorizationResult)->Void)]()
            d.giftAuthorizationProvider={request,completion in held.append((request,completion))}
            d.engine.ambientEnabled=true
            if action=="close" {f.settings.showWindow(nil)}
            let sequence=d.engine.events.last?.sequence ?? 0
            let requested=d.engine.handle(.visitorGift(.automatic))
            guard placed.accepted,requested.accepted,let first=held.first else {
                checks["giftNativeAuthorization-"+action]=false;evidence.append(["authorization":action,"reason":d.engine.events.last?.reason?.rawValue ?? "none"]);continue
            }
            let old=d.giftAuthorizationAttempt
            switch action {
            case "pause":d.paused=true
            case "close":f.settings.window?.performClose(nil)
            case "replacement":
                // Deliberately cancel core A without a tick/reconcile. B must
                // retire A's adapter before publishing B's provider request.
                d.engine.handle(.cancelVisitorGiftRequest)
                _=d.engine.handle(.visitorGift(.automatic))
            default:d.cancelGiftAuthorization()
            }
            let newer=d.giftAuthorizationAttempt,pending=d.engine.giftAuthorizationRequest
            let token=GiftAuthorizationResult(granted:.init(id:UUID(),binding:first.0.binding))
            first.1(token);first.1(token)
            checks["giftNativeAuthorization-"+action]=d.engine.activeRunCount==0 && d.engine.activeGiftAuthorizationCount==0 &&
                d.observationJournal.archive==before && !d.engine.events.contains{$0.sequence>sequence && $0.kind == .visitorGift && $0.type == .started}
            if action=="replacement" {
                checks["giftNativeStaleAttemptDoesNotBusyOrCancelReplacement"]=held.count==2 && newer != nil && newer !== old &&
                    d.giftAuthorizationAttempt === newer && d.engine.giftAuthorizationRequest==pending && pending?.binding==held.last?.0.binding &&
                    pending?.binding != first.0.binding
                if held.count==2 {
                    held[1].1(.init(denied:held[1].0.binding,reason:.globalCooldown))
                    checks["giftNativeTypedDenialReturnsOnSameEngine"]=d.engine.lastGiftAuthorizationDenial == .globalCooldown && clear(d.engine)
                }
            } else {checks["giftNativeCancelledAuthorizationReleasesPlatformAttempt-"+action]=d.giftAuthorizationAttempt==nil && d.engine.giftAuthorizationRequest==nil}
            evidence.append(["authorization":action,"heldResults":held.count,"lateAndDuplicateAttempts":2,"activeRuns":d.engine.activeRunCount])
            d.cancelGiftAuthorization();d.giftAuthorizationProvider=nil;d.paused=false;d.engine.ambientEnabled=false
        }
    }
    private static func deliverySurfaceMatches(_ object:CarriedObject,prop:ScenePropRenderState,layer:CALayer,view:DesktopView,foot:CGPoint)->Bool {
        guard object.giftDelivery?.arrived==true,let texture=layer.sublayers?.first,let root=view.layer else {return false}
        let surface=texture.convert(CGPoint(x:10*prop.size/16,y:12*prop.size/16),to:root)
        return Geometry.distance(surface,CGPoint(x:foot.x-view.desktopRect.minX,y:foot.y-view.desktopRect.minY))<1e-5
    }
    private static func automaticDelivery(into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        let output=folder.appendingPathComponent("automatic-durable-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let f=try Fixture(folder:output);defer {f.close()}
        let d=f.d
        d.visitorMemoryPersistenceEnabled=true;d.giftLedgerPersistenceEnabled=true
        d.loadVisitorMemory(now:0)
        let bootstrap=try VisitorMemoryArchive.load(from:d.visitorMemoryURL)
        // Learn through the real memory store, within the namespace that the
        // actual persistence bootstrap just established. Never replace its seed.
        guard let seed=UInt64(bootstrap.seed) else {throw failure("Invalid bootstrapped visitor seed")}
        let memory=VisitorMemory(seed:seed)
        guard let visitor=memory.acquire(species:.azureWingedMagpie) else {throw failure("Cannot prepare durable familiar visitor")}
        for _ in 0..<4000 {memory.learn(visitor.id,elapsed:0.05)}
        for _ in 0..<2 {memory.release(visitor.id);_=memory.acquire(species:.azureWingedMagpie)}
        f.archive=memory.archive
        let placed=try f.install()
        d.engine.ambientEnabled=true
        let sequence=d.engine.events.last?.sequence ?? 0,before=d.observationJournal.archive
        let result=d.engine.handle(.visitorGift(.automatic)),request=d.engine.giftAuthorizationRequest
        let deadline=ProcessInfo.processInfo.systemUptime+5.5
        while d.engine.giftAuthorizationRequest != nil,ProcessInfo.processInfo.systemUptime<deadline {
            _=RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.005))
        }
        let start=d.engine.events.last{$0.sequence>sequence && $0.kind == .visitorGift && $0.type == .started && $0.source == .automatic}
        checks["giftNativeAutomaticRealBootstrapProviderAndObserver"]=placed.accepted && result.accepted && request != nil && start != nil &&
            bootstrap.profiles.isEmpty && bootstrap.seed==d.engine.visitorMemoryArchive.seed &&
            d.visitorMemoryPersistence?.bootstrapCreated==true && d.visitorMemoryPersistence?.giftNamespaceAvailable==true &&
            d.giftAuthorizationProvider==nil && d.giftLedgerPersistence?.enabled==true && d.giftAuthorizationAttempt==nil &&
            d.engine.lastGiftAuthorizationDenial==nil
        guard let start,let run=start.runID,let request,let leafID=f.leafID else {
            evidence.append(["automatic":"real durable provider did not start","denial":d.engine.lastGiftAuthorizationDenial?.rawValue ?? "none",
                "reason":d.engine.events.last?.reason?.rawValue ?? "none"]);return
        }
        let authorized=try GiftLedger.load(from:d.giftLedgerURL),persisted=try VisitorMemoryArchive.load(from:d.visitorMemoryURL)
        checks["giftNativeAutomaticGrantBindsPersistedVisitorExactlyOnce"]=authorized.grants.count==1 &&
            authorized.grants.first?.visitorArchiveSeed==persisted.seed && persisted.seed==request.binding.visitorArchiveSeed &&
            authorized.grants.first?.visitorID==request.binding.visitorID &&
            persisted.profiles.contains{$0.id==request.binding.visitorID && $0.species == .azureWingedMagpie && $0.visits>=3 && $0.familiarity>=0.6}
        var pickup=false,flight=false,released=false,arrived=false,noEarlyCount=true,neverBranch=true
        var releaseTime:Double?,arrivalTime:Double?,leafPixels=0,birdPixels=0,phases=Set<String>(),samples=[[String:Any]]()
        for _ in 0..<36*120 {
            guard d.engine.behavior(of:f.bird) == .visitorGift,let object=d.engine.carriedObjectSnapshot().first,
                  let state=d.engine.renderSnapshot().first,let prop=d.engine.propSnapshot().first(where:{$0.id==leafID}) else {break}
            pickup = pickup || object.state == .attached
            flight = flight || (object.state == .attached && f.bird.state == .flying)
            neverBranch = neverBranch && !(f.bird.hostID==f.receiver.surface.id && (f.bird.state == .perched || f.bird.state == .landing))
            if object.giftDelivery?.arrived != true {noEarlyCount = noEarlyCount && d.observationJournal.archive==before}
            if object.giftDelivery != nil,!released {released=true;releaseTime=d.engine.time}
            if object.giftDelivery?.arrived==true,!arrived {arrived=true;arrivalTime=d.engine.time}
            let phase=object.giftDelivery.map{$0.arrived ? "received":"falling"} ?? (object.state == .attached ? (f.bird.state == .flying ? "carrying":"pickup"):"approach")
            if phases.insert(phase).inserted {
                try autoreleasepool {
                    f.view.updateSprites()
                    let file=output.appendingPathComponent("automatic-"+phase+"-actual-layer.png")
                    let actual=try InsectCatchVerification.snapshot(f.view,around:f.work,to:file)
                    if let leaf=f.prop(),let sprite=f.sprite() {
                        leafPixels += try InsectCatchVerification.contribution(f.view,layer:leaf,actual:actual,region:prop.rect)
                        birdPixels += try InsectCatchVerification.contribution(f.view,layer:sprite,actual:actual,region:state.rect)
                    }
                    samples.append(["phase":phase,"simulationTime":d.engine.time,"image":file.lastPathComponent,"leafID":object.id.rawValue])
                }
            }
            f.step()
        }
        let ends=terminal(d.engine,run:run),object=d.engine.carriedObjectSnapshot().first
        if !arrived,object?.giftDelivery?.arrived==true {arrived=true;arrivalTime=d.engine.time}
        f.view.updateSprites()
        var visibleEndpoint=false
        if let object,let prop=d.engine.propSnapshot().first(where:{$0.id==leafID}),let leaf=f.prop() {
            let file=output.appendingPathComponent("automatic-delivered-actual-layer.png")
            let actual=try InsectCatchVerification.snapshot(f.view,around:f.work,to:file)
            let pixels=try InsectCatchVerification.contribution(f.view,layer:leaf,actual:actual,region:prop.rect)
            leafPixels+=pixels
            visibleEndpoint=pixels>0 && deliverySurfaceMatches(object,prop:prop,layer:leaf,view:f.view,foot:f.receiver.foot)
        }
        let entry=d.observationJournal.archive.entries.first{$0.species == .azureWingedMagpie && $0.behavior=="visitorGift"}
        checks["giftNativeAutomaticDurableGrantToVisibleDeliveryAndNaturalCount"]=pickup && flight && released && arrived && neverBranch &&
            noEarlyCount && visibleEndpoint && leafPixels>0 && birdPixels>0 && ends.count==1 && ends.first?.type == .completed &&
            f.observedVisibleRuns.contains(run.rawValue) && entry?.automaticCount==1 && entry?.previewCount==0 &&
            f.bird.state == .perched && clear(d.engine)
        let fallDuration:Double?=releaseTime.flatMap { release in arrivalTime.map { $0-release } }
        checks["giftNativeAutomaticRealDropWithinPointEightSeconds"]=fallDuration.map { $0>0 && $0<=0.80000001 } == true
        let journal=d.observationJournal.archive
        f.settings.clearVisitorGiftButton.performClick(nil);f.advance(0.3);f.view.updateSprites()
        let retained=try GiftLedger.load(from:d.giftLedgerURL)
        checks["giftNativeAutomaticCleanupKeepsConsumedLedgerAndUniqueCount"]=retained==authorized && retained.grants.count==1 &&
            d.observationJournal.archive==journal && d.engine.carriedObjectSnapshot().isEmpty && f.prop()==nil && clear(d.engine)
        evidence.append(["automatic":"real temporary visitor bootstrap -> asynchronous GiftLedgerPersistence -> core observer -> pickup -> fly-past -> visible gift -> automatic count",
            "namespace":persisted.seed,"requestID":request.binding.requestID,"visitorID":request.binding.visitorID,
            "ledgerGrants":retained.grants.count,"releaseTime":releaseTime.map{$0 as Any} ?? NSNull(),
            "arrivalTime":arrivalTime.map{$0 as Any} ?? NSNull(),"leafPixels":leafPixels,"birdPixels":birdPixels,"samples":samples])
    }
    private static func separateControllerSessions(_ f:Fixture,into checks:inout [String:Bool]) throws {
        _=try f.install()
        func controller()->DesktopController {
            let d=DesktopController(verificationSeed:73)
            d.preferences=f.preferences;d.automaticPopulation=false;d.pointerButtonsDown={false}
            d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false;d.giftLedgerPersistenceEnabled=false
            d.settingsURL=f.d.settingsURL;d.legacyURL=f.d.legacyURL;d.visitorMemoryURL=f.d.visitorMemoryURL
            d.observationJournalURL=f.d.observationJournalURL;d.giftLedgerURL=f.d.giftLedgerURL
            d.settings=f.d.settings;d.surfaces=f.d.surfaces
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            return d
        }
        func prepare(_ d:DesktopController) throws {
            try d.engine.restoreVisitorMemory(f.archive)
            let bird=Bird(position:.zero,fraction:0.16,profile:d.catalog.profile(.azureWingedMagpie),random:{0.5})
            bird.perch(on:f.host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600
            d.birds=[bird]
            for _ in 0..<9*120 {d.syncWorld(buttonsDown:false);d.engine.advance(1.0/120)}
            let result=d.engine.handle(.placeCarryLeaf(at:f.leafPoint))
            if !result.accepted {throw failure("Separate controller could not place its own leaf")}
            d.engine.ambientEnabled=true
        }
        let original=controller()
        try prepare(original)
        var first:GiftAuthorizationRequest?,oldCompletion:((GiftAuthorizationResult)->Void)?
        original.giftAuthorizationProvider={request,completion in first=request;oldCompletion=completion}
        _=original.engine.handle(.visitorGift(.automatic))
        let newer=controller();try prepare(newer)
        var second:GiftAuthorizationRequest?,newCompletion:((GiftAuthorizationResult)->Void)?
        newer.giftAuthorizationProvider={request,completion in second=request;newCompletion=completion}
        _=newer.engine.handle(.visitorGift(.automatic))
        guard let first,let second,let oldCompletion,let newCompletion else {
            checks["giftNativeOldControllerCannotAuthorizeNewIdenticalRequest"]=false;return
        }
        original.cancelGiftAuthorization()
        let pending=newer.giftAuthorizationAttempt
        oldCompletion(.init(granted:.init(id:UUID(),binding:first.binding)))
        checks["giftNativeOldControllerCannotAuthorizeNewIdenticalRequest"]=first.binding==second.binding &&
            original.engine !== newer.engine && newer.engine.giftAuthorizationRequest==second &&
            newer.giftAuthorizationAttempt === pending && newer.engine.activeRunCount==0 && original.engine.activeRunCount==0
        newCompletion(.init(denied:second.binding,reason:.globalCooldown))
        checks["giftNativeSeparateControllerDenialAndCleanup"]=newer.engine.lastGiftAuthorizationDenial == .globalCooldown &&
            clear(newer.engine) && newer.giftAuthorizationAttempt==nil && original.giftAuthorizationAttempt==nil &&
            original.giftLedgerPersistence==nil && newer.giftLedgerPersistence==nil
        newer.cancelGiftAuthorization();original.giftAuthorizationProvider=nil;newer.giftAuthorizationProvider=nil
    }
    private static func layerMatches(_ prop:ScenePropRenderState,layer:CALayer,view:DesktopView)->Bool {
        guard let texture=layer.sublayers?.first,let root=view.layer,let mask=layer.mask as? CAShapeLayer else {return false}
        let pivot=texture.convert(CGPoint(x:prop.anchor.x*prop.size,y:prop.anchor.y*prop.size),to:root)
        return !layer.isHidden && close(layer.frame,prop.rect.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY)) &&
            texture.anchorPoint==prop.anchor && texture.bounds.size==CGSize(width:prop.size,height:prop.size) &&
            (texture.affineTransform().a<0)==prop.mirrored && (texture.contents as AnyObject?) === CarryArt.leafImage() &&
            Geometry.distance(pivot,CGPoint(x:prop.position.x-view.desktopRect.minX,y:prop.position.y-view.desktopRect.minY))<1e-5 && mask.mask==nil && mask.path != nil
    }
    private static func close(_ a:CGRect,_ b:CGRect)->Bool {abs(a.minX-b.minX)<1e-4 && abs(a.minY-b.minY)<1e-4 && abs(a.width-b.width)<1e-4 && abs(a.height-b.height)<1e-4}
    private static func count(_ d:DesktopController)->Int {d.observationJournal.archive.entries.first{$0.species == .azureWingedMagpie && $0.behavior=="visitorGift"}?.previewCount ?? 0}
    // Runtime derives receiver reservations exclusively from active runs;
    // no active run therefore also means no retained receiver reservation.
    private static func clear(_ e:BehaviorEngine)->Bool {e.activeRunCount==0 && e.leasedBirdCount==0 && e.reservedLandingCount==0 && e.activeGiftAuthorizationCount==0 && e.giftAuthorizationRequest==nil}
    private static func terminal(_ e:BehaviorEngine,run:BehaviorRunID)->[BehaviorEvent] {e.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}}
    private static func failure(_ text:String)->NSError {NSError(domain:"GiftVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
