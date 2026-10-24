import AppKit
import BirdingCore
import ImageIO

/// Existing residents take off through ordinary autonomous routing. All route
/// images below capture DesktopView layers, never reconstructed pose previews.
enum InsectCatchVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("insect-catch-native-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("insectCatchNative")},"evidence":evidence,
            "limits":"Production model-layer composition on an attached display with isolated ledges and real pointer sampling. No WindowServer or physical hotplug claim."],to:output.appendingPathComponent("report.json"))}
        let f=try Fixture(folder:output);defer {f.close()}
        for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
            try journey(f,scale:scale,right:right,into:&checks,evidence:&evidence,folder:output)
        }}
        try miss(f,into:&checks,evidence:&evidence,folder:output)
        try interruptions(f,into:&checks,evidence:&evidence,folder:output)
        checks["insectCatchNativeIsolatedPreferencesAndNoStartup"]=f.d.timer==nil && f.d.panels.isEmpty && f.d.views.isEmpty &&
            f.d.globalMouseMonitor==nil && f.d.localMouseMonitor==nil && !f.d.automaticPopulation &&
            !FileManager.default.fileExists(atPath:f.d.settingsURL.path) && !FileManager.default.fileExists(atPath:f.d.visitorMemoryURL.path) &&
            !FileManager.default.fileExists(atPath:f.d.observationJournalURL.path)
    }
    private final class Fixture {
        let d:DesktopController,window:OverlayPanel,view:DesktopView,settings:SpeciesSettingsWindow
        let work:CGRect,display:CGRect,suite:String,preferences:UserDefaults
        var bird:Bird!,originalGoal:CGPoint?,originalHost:UInt32?,naturalFlightSeen=false
        init(folder:URL) throws {
            let d=DesktopController(verificationSeed:0x494E534543544E41);self.d=d
            guard let screen=NSScreen.screens.first,let work=d.screenRects.first,let display=d.displayRects.first,
                  work.width>=1000,work.height>=620 else {throw failure("Insect native verification requires a 1000 × 620 work area")}
            self.work=work;self.display=display
            suite="Birding.InsectCatchVerification."+UUID().uuidString
            guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate preferences")}
            self.preferences=preferences;d.preferences=preferences;d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.pointerButtonsDown={false}
            d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false
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
            d.engine.observationObserver={ [weak d] event in
                _=d?.observationJournal.observe(event,at:Date(timeIntervalSince1970:1_700_000_000+event.simulationTime))
            }
        }
        func close() {d.engine.handle(.cancelAmbient(.shutdown));settings.cancel();window.orderOut(nil);preferences.removePersistentDomain(forName:suite)}
        func install(scale:CGFloat=1,right:Bool=true) {
            d.engine.handle(.cancelAmbient(.shutdown));d.birds=[];d.paused=false;d.scale=scale
            var value=d.settings;value.insectCatchEnabled=true;d.settings=value
            d.engine.autonomousRouting=true;originalGoal=nil;originalHost=nil;naturalFlightSeen=false
            let ys=[work.minY+max(210,160*scale),work.maxY-80],pointer=d.pointerPosition
            let y=ys.filter{$0<=work.maxY-60}.max {a,b in
                Geometry.distance(pointer,CGPoint(x:work.midX,y:a-100*scale))<Geometry.distance(pointer,CGPoint(x:work.midX,y:b-100*scale))
            } ?? work.maxY-80
            // The initial ledge is too small to be a new ordinary destination.
            // The normal planner therefore selects the opposite visible ledge;
            // no fly(), route(), relocate(), or airborne position injection.
            let source=Surface(id:7302,pid:42,rect:CGRect(x:right ? work.minX+45:work.maxX-155,y:y,width:110,height:80))
            let destination=Surface(id:7303,pid:42,rect:CGRect(x:work.minX+work.width*(right ? 0.60:0.08),
                y:y,width:work.width*0.30,height:100))
            bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.barnSwallow),random:{0.5})
            bird.perch(on:source,spriteScale:d.spriteScale(for:bird));bird.perchDuration=2;bird.facingRight=right
            d.surfaces=[source,destination];d.birds=[bird];d.syncWorld(buttonsDown:false)
            settings.refreshInsectCatchControls();settings.refreshBathControls()
        }
        func sampleOrdinaryGoal() {
            if bird.state == .flying,d.engine.behavior(of:bird)==nil,
               let host=d.surfaces.first(where:{$0.id==bird.hostID}) {
                naturalFlightSeen=true;originalHost=host.id
                originalGoal=Geometry.foot(on:host,fraction:bird.fraction,edge:bird.edge,scale:d.spriteScale(for:bird))
            }
        }
        func step() {sampleOrdinaryGoal();d.syncWorld(buttonsDown:false);d.engine.advance(1.0/120);sampleOrdinaryGoal()}
        func advance(_ seconds:Double) {for _ in 0..<Int((seconds*120).rounded()) {step()}}
        func pendingStart()->BehaviorRunID? {
            settings.previewInsectCatchButton.performClick(nil)
            for _ in 0..<Int(10.1*120) {
                if d.engine.behavior(of:bird) == .insectCatch {
                    return d.engine.events.last{$0.type == .started && $0.kind == .insectCatch && $0.participants==[d.engine.id(of:bird)!]}?.runID
                }
                if !d.engine.hasInsectCatchPreview {return nil};step()
            };return nil
        }
        func ordinaryReady()->Bool {
            for _ in 0..<10*120 {
                if bird.state == .flying,bird.stateTime>=0.4,bird.flightSpeed>=60,d.engine.behavior(of:bird)==nil {return true}
                step()
            };return false
        }
        func seek(_ frame:String)->Bool {
            for _ in 0..<35*120 {
                guard d.engine.behavior(of:bird) == .insectCatch else {return false}
                if d.engine.renderSnapshot().first?.frameName==frame {return true};step()
            };return false
        }
        func sprite()->CALayer? {guard let id=d.engine.id(of:bird) else {return nil};return view.layer?.sublayers?.first{$0.name=="bird-sprite-\(id.rawValue)"}}
        func prop(_ id:ScenePropID)->CALayer? {view.layer?.sublayers?.first{$0.name=="scene-prop-\(id.rawValue)"}}
    }
    private static func journey(_ f:Fixture,scale:CGFloat,right:Bool,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        f.install(scale:scale,right:right)
        let d=f.d,bird=f.bird!,id=d.engine.id(of:bird)!,origin=bird.position,revision=bird.motionRevision
        let key="insectCatchNative-\(scale)-\(right ? "right":"left")-",before=count(d),misses=d.engine.insectMissedTargetCount
        f.settings.previewInsectCatchButton.performClick(nil)
        checks[key+"NativePreviewWaitsWithoutInsectRunOrTeleport"]=d.engine.hasInsectCatchPreview && d.engine.activeRunCount==0 &&
            d.engine.insectSnapshot()==nil && bird.position==origin && bird.motionRevision==revision && bird.state == .perched
        // The already armed preview is advanced without pressing its button a
        // second time (which correctly returns busy while waiting).
        var run:BehaviorRunID?
        for _ in 0..<Int(10.1*120) {
            if d.engine.behavior(of:bird) == .insectCatch {
                run=d.engine.events.last{$0.type == .started && $0.kind == .insectCatch && $0.participants==[id]}?.runID;break
            }
            if !d.engine.hasInsectCatchPreview {break};f.step()
        }
        checks[key+"ExistingResidentNaturallyStartsProductionRun"]=run != nil && f.naturalFlightSeen && f.originalGoal != nil &&
            d.residentCount==1 && d.birds.first === bird && d.arrivalCount==0 && d.departureCount==0
        guard let run,let insect=d.engine.insectSnapshot(),let goal=f.originalGoal,let host=f.originalHost,
              let start=d.engine.events.first(where:{$0.runID==run && $0.type == .started}) else {
            evidence.append(["case":key,"startFailed":true,"reason":d.engine.events.last?.reason?.rawValue ?? "none"]);return
        }
        let trajectory=insect.trajectory
        let initial=trajectory.position(at:0),side=16*scale
        checks[key+"WholeInsectStartsOutsideSelectedDisplay"] = !trajectory.display.intersects(CGRect(x:initial.x-side/2,y:initial.y-side/2,width:side,height:side)) &&
            trajectory.visibleFrom>0 && trajectory.terminalAge<=12 && trajectory.worldScale==scale
        let approachFolder=folder.appendingPathComponent(key+"approach-60hz",isDirectory:true)
        try FileManager.default.createDirectory(at:approachFolder,withIntermediateDirectories:true)
        let fullyEntered=fullyEnteredAge(trajectory)
        var approachImages=[URL](),approachTimes=[Double](),samples=[[String:Any]](),previousInsect:Insect?
        var frames=Set<String>(),screenshots=Set<String>(),insectFrames=Set<String>(),layers=true,pixels=true,bodySamples=0,insectSamples=0,visibleSamples=0
        var contactSeen=false,contactValid=false,continuous=true,identity=true,pauseDone=false,pauseOK=false
        var enteredToContact:Double?,sampledStepRatio:CGFloat=0,sampledSteps=0
        var previousFoot=bird.position,previousTime=d.engine.time,pausedDuration=0.0
        for tick in 0..<35*120 {
            guard d.engine.behavior(of:bird) == .insectCatch,let state=d.engine.renderSnapshot().first else {break}
            f.view.updateSprites();frames.insert(state.frameName)
            identity = identity && d.birds.count==1 && d.birds.first === bird && d.engine.id(of:bird)==id &&
                d.engine.propSnapshot().filter{$0.kind == .insect}.count<=1
            continuous = continuous && Geometry.distance(previousFoot,state.position)<max(20,20*state.scale)
            let live=d.engine.insectSnapshot(),prop=d.engine.propSnapshot().first{$0.kind == .insect}
            // Real root-layer frames at 60 Hz retain the frozen production
            // route and speed. PNGs also remain available beside the short GIF.
            if !contactSeen,tick<=4*120,(tick%2==0 || d.engine.lastInsectContact?.runID==run) {
                let url=approachFolder.appendingPathComponent(String(format:"%03d-actual-layer.png",approachImages.count))
                _=try snapshot(f.view,around:f.display,to:url);approachImages.append(url)
                let unpausedAge=d.engine.time-start.time-pausedDuration
                approachTimes.append(unpausedAge)
                var sample:[String:Any] = ["engineTime":d.engine.time,"unpausedRunAge":unpausedAge,
                    "image":url.lastPathComponent,"bird":NSStringFromPoint(state.position),"birdFrame":state.frameName]
                if let live {
                    sample["insectAge"]=live.age;sample["insect"]=NSStringFromPoint(live.position)
                    if let previousInsect {
                        let distance=Geometry.distance(previousInsect.position,live.position)
                        sample["stepSeconds"]=live.age-previousInsect.age;sample["displacementPoints"]=distance
                        sample["displacementPerInsectWidth"]=distance/side
                        sampledStepRatio=max(sampledStepRatio,distance/side);sampledSteps+=1
                    }
                    previousInsect=live
                }
                samples.append(sample)
            }
            if let live,let prop,let layer=f.prop(prop.id) {
                layers = layers && live.id==insect.id && live.trajectory==trajectory && prop.id==insect.id &&
                    Geometry.distance(prop.position,trajectory.position(at:live.age))<1e-5 && prop.size==side && layerMatches(prop,layer:layer,view:f.view)
            } else if live != nil {layers=false}
            if !contactSeen,let contact=d.engine.lastInsectContact,contact.runID==run {
                contactSeen=true
                enteredToContact=fullyEntered.map{contact.insectAge-$0}
                let anchor=DetailedBirdArt.catchBillAnchor("catchOpen",species:.barnSwallow)!
                let metadata=PoseClip.Anchor(Double(anchor.x),Double(anchor.y))
                let offset=metadata.world(foot:.zero,scale:state.scale,facingRight:right)
                let foot=CGPoint(x:contact.beakPosition.x-offset.x,y:contact.beakPosition.y-offset.y)
                contactValid=contact.birdID==id && contact.insectID==insect.id && contact.time>=previousTime-1e-8 && contact.time<=d.engine.time+1e-8 &&
                    trajectory.isVisible(at:contact.insectAge) && Geometry.distance(contact.insectPosition,trajectory.position(at:contact.insectAge))<1e-5 &&
                    Geometry.distance(contact.beakPosition,contact.insectPosition)<=trajectory.collisionRadius+1e-7 &&
                    segmentDistance(foot,previousFoot,state.position)<1e-4 && d.engine.insectSnapshot()==nil &&
                    count(d)==before && state.facingRight==right
                evidence.append(["case":key,"contactTime":contact.time,"insectAge":contact.insectAge,
                    "beak":NSStringFromPoint(contact.beakPosition),"insect":NSStringFromPoint(contact.insectPosition),
                    "distance":Geometry.distance(contact.beakPosition,contact.insectPosition),"contactValid":contactValid,
                    "fullyEnteredAge":fullyEntered.map{$0 as Any} ?? NSNull(),
                    "fullyEnteredToContactSeconds":fullyEntered.map{(contact.insectAge-$0) as Any} ?? NSNull()])
            }
            let phase=state.frameName+"-"+(prop?.frameName ?? "caught")
            let stage=CatchArtGeometry.frameNames.contains(state.frameName) ? state.frameName:"approach"
            let newStage=screenshots.insert(stage).inserted
            let newInsectFrame=prop.map{f.display.contains($0.rect) && insectFrames.insert($0.frameName).inserted} ?? false
            if newStage || newInsectFrame,let sprite=f.sprite() {
                let region=state.rect.union(prop?.rect ?? state.rect).insetBy(dx:-16,dy:-16)
                let url=folder.appendingPathComponent(key+phase+"-actual-layer.png")
                let actual=try snapshot(f.view,around:region,to:url)
                let body=try contribution(f.view,layer:sprite,actual:actual,region:state.rect)
                pixels = pixels && body>=4;bodySamples+=body
                if let prop,let layer=f.prop(prop.id),f.display.contains(prop.rect) {
                    let changed=try contribution(f.view,layer:layer,actual:actual,region:prop.rect)
                    pixels = pixels && changed>=1;insectSamples+=changed;visibleSamples+=1
                }
                evidence.append(["case":key,"phase":phase,"bodyPixels":body,"screenshot":url.lastPathComponent])
            }
            if !pauseDone,let live {
                pauseDone=true;d.paused=true
                let frozen=d.engine.renderSnapshot().first
                f.advance(1);pausedDuration+=1
                pauseOK=d.engine.insectSnapshot()?.age==live.age && d.engine.insectSnapshot()?.position==live.position &&
                    d.engine.insectSnapshot()?.remainingLifetime==live.remainingLifetime &&
                    d.engine.renderSnapshot().first?.position==frozen?.position && d.engine.renderSnapshot().first?.frameName==frozen?.frameName
                d.paused=false
            }
            previousFoot=state.position;previousTime=d.engine.time;f.step()
        }
        let gif=folder.appendingPathComponent(key+"approach-actual-layers.gif")
        try writeGIF(approachImages,times:approachTimes,to:gif)
        let speeds=zip(trajectory.waypoints,trajectory.waypoints.dropFirst()).map {a,b in
            Double(Geometry.distance(a.position,b.position))/(b.time-a.time)
        }
        evidence.append(["case":key,"worldScale":trajectory.worldScale,"insectWidthPoints":side,
            "segmentSpeedsPointsPerSecond":speeds,"segmentSpeedsPerWorldScale":speeds.map{$0/Double(trajectory.worldScale)},
            "nominal60HzDisplacementPerInsectWidth":speeds.map{$0/60/Double(side)},
            "approachSamples":samples,"approachGIF":gif.lastPathComponent,
            "capture":"Unmodified production root CALayer, fixed display crop, 60 Hz samples plus the contact boundary. GIF delays follow unpaused simulation time (format quantizes centiseconds; PNG timestamps remain exact)." ])
        let ends=terminal(d.engine,run:run)
        checks[key+"InsectMovesAtMostHalfCanvasPer60HzStep"]=sampledSteps>0 && sampledStepRatio<=0.5+1e-8 &&
            !speeds.isEmpty && speeds.allSatisfy{$0<=480*Double(trajectory.worldScale)+1e-6 && $0/60/Double(side)<=0.5+1e-8}
        checks[key+"FullyVisibleForAtLeastPointEightSecondsBeforeActualContact"]=contactSeen &&
            enteredToContact.map{$0>=0.8-1e-8}==true
        checks[key+"ActualContactPrecedesCloseAndRecovery"]=contactSeen && contactValid && Set(CatchArtGeometry.frameNames).isSubset(of:frames)
        checks[key+"FrozenSingleInsectAndRealLayerGeometry"]=identity && layers
        checks[key+"RootCompositeShowsRealBirdAndInsect"]=pixels && bodySamples>0 && insectSamples>0 && visibleSamples>0
        checks[key+"PauseFreezesBirdAndIndependentInsect"]=pauseDone && pauseOK
        checks[key+"ContactAndSafeRecoveryCompleteExactlyOnce"]=ends.count==1 && ends.first?.type == .completed &&
            (ends.first?.time ?? .infinity)-start.time-pausedDuration<=35+1e-6 && count(d)==before+1 &&
            d.engine.insectMissedTargetCount==misses && clearRun(d.engine) && d.engine.insectSnapshot()==nil && continuous
        d.engine.autonomousRouting=false
        for _ in 0..<35*120 {if bird.state == .perched {break};f.step()}
        checks[key+"OrdinaryFlightResumesSavedDestination"]=bird.state == .perched && bird.hostID==host && Geometry.distance(bird.position,goal)<0.001 &&
            d.birds.first === bird && d.engine.id(of:bird)==id && count(d)==before+1
    }
    private static func miss(_ f:Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        f.install();let d=f.d,bird=f.bird!,before=d.observationJournal.archive,misses=d.engine.insectMissedTargetCount
        let ready=f.ordinaryReady(),w=d.engine.world,scale=d.scale,half=9*scale,y=f.work.minY+16*scale
        guard let trajectory=InsectTrajectory(waypoints:[
            InsectWaypoint(time:0,position:CGPoint(x:f.display.maxX+half,y:y)),
            InsectWaypoint(time:6,position:CGPoint(x:f.display.minX-half,y:y))],display:f.display,worldScale:scale,
            screens:w.screens,displays:w.displays,displayIDs:w.displayIDs) else {throw failure("Invalid frozen miss trajectory")}
        let result=d.engine.startInsectCatchFixture(species:.barnSwallow,trajectory:trajectory)
        guard case .started(let run)=result else {
            checks["insectCatchNativeFrozenMissUsesRealExecutor"]=false;evidence.append(["missStart":String(describing:result),"ordinaryReady":ready]);return
        }
        guard let id=d.engine.insectSnapshot()?.id,let goal=f.originalGoal,let host=f.originalHost else {
            checks["insectCatchNativeFrozenMissUsesRealExecutor"]=false;return
        }
        var recovered=false,unchanged=true,contactAbsent=true,seen=Set<String>()
        for _ in 0..<35*120 {
            guard d.engine.behavior(of:bird) == .insectCatch else {break}
            if let insect=d.engine.insectSnapshot() {unchanged = unchanged && insect.id==id && insect.trajectory==trajectory}
            contactAbsent = contactAbsent && d.engine.lastInsectContact?.runID != run
            if let state=d.engine.renderSnapshot().first,seen.insert(state.frameName).inserted {
                recovered = recovered || state.frameName=="catchRecover";f.view.updateSprites()
                _=try snapshot(f.view,around:state.rect.insetBy(dx:-20,dy:-20),to:folder.appendingPathComponent("insect-catch-frozen-miss-"+state.frameName+"-actual-layer.png"))
            };f.step()
        }
        let ends=terminal(d.engine,run:run)
        checks["insectCatchNativeFrozenMissUsesRealExecutor"]=ready && unchanged && contactAbsent && recovered &&
            ends.count==1 && ends.first?.type == .failed && ends.first?.reason == .missedTarget &&
            d.engine.insectMissedTargetCount==misses+1 && d.observationJournal.archive==before && clearRun(d.engine)
        d.engine.autonomousRouting=false
        for _ in 0..<35*120 {if bird.state == .perched {break};f.step()}
        checks["insectCatchNativeMissRestoresOriginalGoalWithoutJournalEntry"]=bird.state == .perched && bird.hostID==host &&
            Geometry.distance(bird.position,goal)<0.001 && d.observationJournal.archive==before
        f.advance(12.2);f.view.updateSprites()
        checks["insectCatchNativeMissInsectExpiresWithoutLayer"]=d.engine.insectSnapshot()==nil && f.prop(id)==nil
        evidence.append(["miss":"frozen nonintersecting top corridor","waypoints":trajectory.waypoints.map{["time":$0.time,"point":NSStringFromPoint($0.position)]},
            "reason":ends.first?.reason?.rawValue ?? "none","contactAbsent":contactAbsent,"trajectoryUnchanged":unchanged])
    }
    private static func interruptions(_ f:Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        for action in ["click","disable","clear","sleep","birdRemoved","hostRemoved","pausedDisable"] {
            f.install();let d=f.d,bird=f.bird!,birdID=d.engine.id(of:bird)!,before=d.observationJournal.archive
            let run=f.pendingStart(),reached=f.seek("catchOpen")
            guard let run,let insect=d.engine.insectSnapshot(),reached else {
                checks["insectCatchNativeInterrupt-"+action]=false;evidence.append(["interrupt":action,"reached":reached]);continue
            }
            f.view.updateSprites();let sequence=d.engine.events.last?.sequence ?? 0
            var clicked=false,hit=false
            switch action {
            case "click":
                if let state=d.engine.renderSnapshot().first,let point=visiblePoint(state,in:d) {
                    hit=d.bird(at:point) === bird
                    if hit,let cg=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left),let event=NSEvent(cgEvent:cg) {d.handleMouseDown(event);clicked=true}
                }
            case "disable","pausedDisable":
                if action=="pausedDisable" {d.paused=true}
                var value=d.settings;value.insectCatchEnabled=false;d.settings=value
            case "clear":f.settings.clearInsectButton.performClick(nil)
            case "sleep":d.engine.handle(.cancelAmbient(.sleep))
            case "birdRemoved":d.engine.handle(.remove(birdID))
            default:d.surfaces.removeAll{$0.id==bird.hostID};d.syncWorld(buttonsDown:false)
            }
            if ["disable","clear","sleep","pausedDisable"].contains(action) {
                checks["insectCatchNativeImmediateInsectClear-"+action]=d.engine.insectSnapshot()==nil
            }
            if action=="click" {
                let next=d.engine.events.first{$0.sequence>sequence && $0.type == .started && $0.kind == .relocate && $0.participants==[birdID]}
                let ends=terminal(d.engine,run:run)
                checks["insectCatchNativeClickActuallyRelocatesAndReplacesCatch"]=hit && clicked && next != nil && d.engine.behavior(of:bird) == .relocate &&
                    ends.count==1 && ends.first?.reason == .replaced && (ends.first?.sequence ?? .max)<(next?.sequence ?? 0)
                let after=d.engine.insectSnapshot()
                checks["insectCatchNativeClickLeavesSameInsectAndRemainingRoute"]=after?.id==insect.id && after?.age==insect.age && after?.trajectory==insect.trajectory
                // Sample strictly before the immutable route's natural exit.
                let available=insect.trajectory.terminalAge-insect.age
                let sampleTicks=min(30,max(0,Int((available*120/2).rounded(.down))))
                for _ in 0..<sampleTicks {f.step()}
                let later=d.engine.insectSnapshot()
                checks["insectCatchNativeUncaughtInsectContinuesWithoutReset"]=sampleTicks>0 && later?.id==insect.id && later?.trajectory==insect.trajectory &&
                    (later?.age ?? 0)>insect.age && (later?.remainingLifetime ?? 12)<insect.remainingLifetime &&
                    later.map{Geometry.distance($0.position,insect.trajectory.position(at:$0.age))<1e-5}==true
            }
            d.paused=false
            // Original-host loss may first restore another ordinary target and
            // then publish failed(missedTarget), rather than cancel immediately.
            for _ in 0..<35*120 {if d.engine.behavior(of:bird) != .insectCatch {break};f.step()}
            let ends=terminal(d.engine,run:run)
            checks["insectCatchNativeInterrupt-"+action]=ends.count==1 && ends.first?.type != .completed &&
                d.engine.lastInsectContact?.runID != run && d.observationJournal.archive==before
            f.advance(12.2);f.view.updateSprites()
            checks["insectCatchNativeInterruptFinalCleanup-"+action]=d.engine.insectSnapshot()==nil && f.prop(insect.id)==nil &&
                d.engine.reservedLandingCount==0 && d.observationJournal.archive==before
            evidence.append(["interrupt":action,"hitOriginal":hit,"clicked":clicked,"reason":ends.first?.reason?.rawValue ?? "none"])
        }
    }
    static func fullyEnteredAge(_ t:InsectTrajectory)->Double? {
        let interior=t.display.insetBy(dx:8*t.worldScale,dy:8*t.worldScale)
        guard !interior.isEmpty else {return nil}
        for (a,b) in zip(t.waypoints,t.waypoints.dropFirst()) {
            var lo=0.0,hi=1.0,valid=true
            for (p,d,mn,mx) in [(a.position.x,b.position.x-a.position.x,interior.minX,interior.maxX),
                                (a.position.y,b.position.y-a.position.y,interior.minY,interior.maxY)] {
                if abs(d)<1e-12 {if p<mn || p>mx {valid=false};continue}
                let u=Double((mn-p)/d),v=Double((mx-p)/d)
                lo=max(lo,min(u,v));hi=min(hi,max(u,v))
            }
            if valid,lo<=hi {return a.time+(b.time-a.time)*lo}
        };return nil
    }
    static func writeGIF(_ frames:[URL],times:[Double],to url:URL) throws {
        guard !frames.isEmpty,frames.count==times.count,
              let destination=CGImageDestinationCreateWithURL(url as CFURL,"com.compuserve.gif" as CFString,frames.count,nil) else {
            throw failure("Cannot allocate actual-layer approach GIF")
        }
        CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for (index,file) in frames.enumerated() {
            guard let source=CGImageSourceCreateWithURL(file as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {
                throw failure("Cannot read actual-layer approach frame")
            }
            let delay=index+1<times.count ? times[index+1]-times[index]:1.0/60
            CGImageDestinationAddImage(destination,image,[kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFDelayTime:delay,kCGImagePropertyGIFUnclampedDelayTime:delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {throw failure("Cannot write actual-layer approach GIF")}
    }
    static func layerMatches(_ prop:ScenePropRenderState,layer:CALayer,view:DesktopView)->Bool {
        if !prop.rect.intersects(view.desktopRect) {return layer.isHidden}
        guard !layer.isHidden,let root=view.layer,let texture=layer.sublayers?.first,let mask=layer.mask as? CAShapeLayer else {return false}
        let anchor=texture.convert(CGPoint(x:prop.size*prop.anchor.x,y:prop.size*prop.anchor.y),to:root)
        return close(layer.frame,prop.rect.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY)) &&
            texture.anchorPoint==prop.anchor && texture.bounds.size==CGSize(width:prop.size,height:prop.size) &&
            Geometry.distance(anchor,CGPoint(x:prop.position.x-view.desktopRect.minX,y:prop.position.y-view.desktopRect.minY))<1e-5 &&
            (texture.contents as AnyObject?) === InsectArt.image(prop.frameName) && mask.path != nil && mask.mask==nil
    }
    static func visiblePoint(_ state:BirdRenderState,in d:DesktopController)->CGPoint? {
        guard let art=d.arts[state.species] else {return nil}
        for y in 0..<48 {for x in 0..<48 where art.contains(frame:state.frameName,x:x,y:y) {
            let p=CGPoint(x:state.rect.minX+(state.facingRight ? CGFloat(x)+0.5:47.5-CGFloat(x))*state.scale,
                y:state.rect.minY+(CGFloat(y)+0.5)*state.scale)
            if d.bird(at:p) != nil {return p}
        }};return nil
    }
    struct Capture {let context:CGContext,crop:CGRect}
    private static func capture(_ view:DesktopView,around rect:CGRect) throws -> Capture {
        let local=rect.offsetBy(dx:-view.desktopRect.minX,dy:-view.desktopRect.minY).intersection(view.bounds).integral
        guard !local.isEmpty,let root=view.layer,let context=CGContext(data:nil,width:Int(local.width),height:Int(local.height),bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot capture insect production layers")}
        context.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor);context.fill(CGRect(origin:.zero,size:local.size))
        context.translateBy(x:0,y:local.height);context.scaleBy(x:1,y:-1);context.translateBy(x:-local.minX,y:-local.minY);root.render(in:context)
        return Capture(context:context,crop:local.offsetBy(dx:view.desktopRect.minX,dy:view.desktopRect.minY))
    }
    static func snapshot(_ view:DesktopView,around rect:CGRect,to url:URL) throws -> Capture {
        let actual=try capture(view,around:rect);try BathVerification.writePNG(actual.context,to:url);return actual
    }
    static func contribution(_ view:DesktopView,layer:CALayer,actual:Capture,region:CGRect) throws -> Int {
        CATransaction.begin();CATransaction.setDisableActions(true)
        let hidden=layer.isHidden;layer.isHidden=true;defer {layer.isHidden=hidden;CATransaction.commit()}
        let baseline=try capture(view,around:actual.crop)
        guard let a=actual.context.makeImage(),let b=baseline.context.makeImage(),actual.crop==baseline.crop else {throw failure("Composite crop changed")}
        let shown=try BathArtVerification.Raster(a),without=try BathArtVerification.Raster(b)
        var count=0
        for y in 0..<shown.height {for x in 0..<shown.width {
            let p=CGPoint(x:actual.crop.minX+CGFloat(x)+0.5,y:actual.crop.minY+CGFloat(y)+0.5)
            guard region.insetBy(dx:-1,dy:-1).contains(p) else {continue}
            let i=y*shown.stride+x*4,j=y*without.stride+x*4
            if (0..<4).contains(where:{shown.bytes[i+$0] != without.bytes[j+$0]}) {count+=1}
        }};return count
    }
    static func segmentDistance(_ p:CGPoint,_ a:CGPoint,_ b:CGPoint)->CGFloat {
        let dx=b.x-a.x,dy=b.y-a.y,n=dx*dx+dy*dy
        let t=n>0 ? min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/n)):0
        return Geometry.distance(p,CGPoint(x:a.x+t*dx,y:a.y+t*dy))
    }
    private static func close(_ a:CGRect,_ b:CGRect)->Bool {abs(a.minX-b.minX)<1e-5 && abs(a.minY-b.minY)<1e-5 && abs(a.width-b.width)<1e-5 && abs(a.height-b.height)<1e-5}
    private static func count(_ d:DesktopController)->Int {d.observationJournal.archive.entries.first{$0.species == .barnSwallow && $0.behavior=="insectCatch"}?.previewCount ?? 0}
    private static func terminal(_ e:BehaviorEngine,run:BehaviorRunID)->[BehaviorEvent] {e.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}}
    private static func clearRun(_ e:BehaviorEngine)->Bool {e.activeRunCount==0 && e.leasedBirdCount==0 && e.reservedLandingCount==0}
    private static func failure(_ text:String)->NSError {NSError(domain:"InsectCatchVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
