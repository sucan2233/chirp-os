import AppKit
import BirdingCore

/// M6f.2 production button -> perched resident -> real sweep -> settled return.
/// The only replaced route is the explicitly frozen physical miss fixture.
enum FlycatcherInsectCatchVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("flycatcher-insect-catch-native-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("flycatcherCatchNative")},"evidence":evidence,
            "limits":"Production model CALayers on the attached display, isolated ordinary hosts and real pointer sampling. No WindowServer or physical hotplug claim."],to:output.appendingPathComponent("report.json"))}
        // One controller/window pair for the suite; per-frame autorelease pools
        // bound image encoders without retaining thousands of Cocoa objects.
        try autoreleasepool {
            let f=try Fixture(folder:output);defer {f.close()}
            for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
                try journey(f,scale:scale,right:right,into:&checks,evidence:&evidence,folder:output)
            }}
            try journey(f,scale:1,right:f.d.pointerPosition.x>=f.work.midX,ground:true,into:&checks,evidence:&evidence,folder:output)
            try miss(f,into:&checks,evidence:&evidence,folder:output)
            try interruptions(f,into:&checks,evidence:&evidence,folder:output)
            checks["flycatcherCatchNativeIsolatedAndBounded"]=f.d.timer==nil && f.d.panels.isEmpty && f.d.views.isEmpty &&
                f.d.globalMouseMonitor==nil && f.d.localMouseMonitor==nil && !f.d.automaticPopulation &&
                !FileManager.default.fileExists(atPath:f.d.settingsURL.path) &&
                !FileManager.default.fileExists(atPath:f.d.visitorMemoryURL.path) &&
                !FileManager.default.fileExists(atPath:f.d.observationJournalURL.path)
        }
    }
    private final class Fixture {
        let d:DesktopController,window:OverlayPanel,view:DesktopView,settings:SpeciesSettingsWindow
        let work:CGRect,display:CGRect,suite:String,preferences:UserDefaults
        var bird:Bird!,host:Surface!,origin=CGPoint.zero
        var observedSettledRuns=Set<UInt64>()
        init(folder:URL) throws {
            let d=DesktopController(verificationSeed:0x464C594341544348);self.d=d
            guard let screen=NSScreen.screens.first,let work=d.screenRects.first,let display=d.displayRects.first,
                  work.width>=1000,work.height>=620 else {throw failure("Flycatcher native verification requires a 1000 × 620 work area")}
            self.work=work;self.display=display
            suite="Birding.FlycatcherInsectCatchVerification."+UUID().uuidString
            guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate preferences")}
            self.preferences=preferences;d.preferences=preferences;d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
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
            d.engine.observationObserver={ [weak self,weak d] event in
                if let self,event.kind == .insectCatch,self.bird != nil,FlycatcherInsectCatchVerification.validFoot(self) {
                    self.observedSettledRuns.insert(event.runID)
                }
                _=d?.observationJournal.observe(event,at:Date(timeIntervalSince1970:1_700_000_000+event.simulationTime))
            }
        }
        func close() {
            d.engine.handle(.cancelAmbient(.shutdown));settings.cancel();d.settingsWindow=nil
            window.orderOut(nil);window.close();preferences.removePersistentDomain(forName:suite)
        }
        func install(scale:CGFloat=1,right:Bool=true,ground:Bool=false) {
            d.engine.handle(.cancelAmbient(.shutdown));d.birds=[];d.paused=false;d.scale=scale
            var value=d.settings;value.insectCatchEnabled=true;d.settings=value
            let fraction:CGFloat=right ? 0.35:0.65,pointer=d.pointerPosition
            let ys=[work.minY+max(240,150*scale),work.maxY-70]
            let y=ys.max {a,b in
                Geometry.distance(pointer,CGPoint(x:work.minX+work.width*fraction,y:a-60*scale)) <
                Geometry.distance(pointer,CGPoint(x:work.minX+work.width*fraction,y:b-60*scale))
            }!
            let floor=Geometry.ground(id:7402,display:display,workArea:work)
            host=ground ? floor:Surface(id:7401,pid:42,rect:CGRect(x:work.minX+40,y:y,width:work.width-80,height:60))
            bird=Bird(position:.zero,fraction:fraction,profile:d.catalog.profile(.yellowRumpedFlycatcher),random:{0.5})
            bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;bird.facingRight=right
            origin=bird.position;d.surfaces=ground ? [floor]:[host,floor];d.birds=[bird]
            d.syncWorld(buttonsDown:false);settings.refreshInsectCatchControls();settings.refreshBathControls()
        }
        func start()->BehaviorRunID? {
            let sequence=d.engine.events.last?.sequence ?? 0
            settings.previewFlycatcherInsectCatchButton.performClick(nil)
            return d.engine.events.last{$0.sequence>sequence && $0.type == .started && $0.kind == .insectCatch}?.runID
        }
        func step() {d.syncWorld(buttonsDown:false);d.engine.advance(1.0/120)}
        func advance(_ seconds:Double) {for _ in 0..<Int((seconds*120).rounded()) {step()}}
        func sprite()->CALayer? {
            guard let id=d.engine.id(of:bird) else {return nil}
            return view.layer?.sublayers?.first{$0.name=="bird-sprite-\(id.rawValue)"}
        }
        func prop(_ id:ScenePropID)->CALayer? {view.layer?.sublayers?.first{$0.name=="scene-prop-\(id.rawValue)"}}
    }
    private static func journey(_ f:Fixture,scale:CGFloat,right:Bool,ground:Bool=false,into checks:inout [String:Bool],
                                evidence:inout [[String:Any]],folder:URL) throws {
        f.install(scale:scale,right:right,ground:ground)
        let d=f.d,bird=f.bird!,id=d.engine.id(of:bird)!,origin=f.origin,revision=bird.motionRevision
        let key="flycatcherCatchNative-\(scale)-\(right ? "right":"left")-\(ground ? "ground":"window")-"
        let before=count(d),misses=d.engine.insectMissedTargetCount,landings=bird.landedCount
        let wasSettled=bird.state == .perched && bird.edge == .top && validFoot(f)
        let run=f.start()
        checks[key+"NativeButtonDirectlyStartsFromExistingPerch"]=wasSettled && run != nil &&
            !d.engine.hasInsectCatchPreview && d.engine.insectPreviewRemaining==nil && bird.position==origin &&
            bird.motionRevision>revision && d.engine.behavior(of:bird) == .insectCatch &&
            d.residentCount==1 && d.arrivalCount==0 && d.departureCount==0 && !f.host.isHabitat && f.host.isGround==ground
        guard let run,let insect=d.engine.insectSnapshot(),let start=d.engine.events.first(where:{$0.runID==run && $0.type == .started}) else {
            evidence.append(["case":key,"startFailed":true,"reason":d.engine.events.last?.reason?.rawValue ?? "none"]);return
        }
        let trajectory=insect.trajectory,side=16*scale,initial=trajectory.position(at:0)
        checks[key+"WholeInsectEntersFromOutside"]=trajectory.worldScale==scale && trajectory.visibleFrom>0 && trajectory.terminalAge<=12 &&
            !trajectory.display.intersects(CGRect(x:initial.x-side/2,y:initial.y-side/2,width:side,height:side))
        // A second species shares the same capacity; neither button may install
        // another entity or replace the active flycatcher with a waiting preview.
        f.settings.previewInsectCatchButton.performClick(nil)
        f.settings.previewFlycatcherInsectCatchButton.performClick(nil)
        checks[key+"BothButtonsShareSingleInsectAndLease"]=d.engine.activeRunCount==1 && d.engine.leasedBirdCount==1 &&
            d.engine.reservedLandingCount==1 && d.engine.insectSnapshot()?.id==insect.id && !d.engine.hasInsectCatchPreview &&
            d.engine.events.filter{$0.runID==run && $0.type == .started}.count==1
        let sequenceFolder=folder.appendingPathComponent(key+"journey",isDirectory:true)
        try FileManager.default.createDirectory(at:sequenceFolder,withIntermediateDirectories:true)
        var images=[URL](),imageTimes=[Double](),samples=[[String:Any]](),motionSamples=[[String:Any]](),stages=Set<String>(),frames=Set<String>()
        var contactSeen=false,contactValid=false,airborne=false,landingSeen=false,identity=true,geometry=true,continuous=true
        var noEarlyCount=true,pixels=true,bodyPixels=0,insectPixels=0,visibleInsectSamples=0
        var pauseDone=false,pauseOK=false,pausedDuration=0.0,enteredToContact:Double?
        var previousFoot=bird.position,previousTime=d.engine.time,previousInsect:Insect?,maxStepRatio:CGFloat=0,stepSamples=0
        let fullyEntered=InsectCatchVerification.fullyEnteredAge(trajectory)
        for tick in 0..<25*120 {
            guard d.engine.behavior(of:bird) == .insectCatch,let state=d.engine.renderSnapshot().first else {break}
            f.view.updateSprites();frames.insert(state.frameName)
            airborne = airborne || (bird.state == .flying && Geometry.distance(state.position,origin)>1)
            landingSeen = landingSeen || bird.state == .landing
            identity = identity && d.birds.count==1 && d.birds.first === bird && d.engine.id(of:bird)==id &&
                d.engine.propSnapshot().filter{$0.kind == .insect}.count<=1 && d.engine.reservedLandingCount==1
            continuous = continuous && Geometry.distance(previousFoot,state.position)<max(20,20*state.scale)
            noEarlyCount = noEarlyCount && count(d)==before
            let live=d.engine.insectSnapshot(),prop=d.engine.propSnapshot().first{$0.kind == .insect}
            if tick%2==0,let live {
                var sample:[String:Any] = ["engineTime":d.engine.time,"insectAge":live.age,"position":NSStringFromPoint(live.position)]
                if let previousInsect {
                    let distance=Geometry.distance(previousInsect.position,live.position)
                    sample["stepSeconds"]=live.age-previousInsect.age;sample["displacementPoints"]=distance
                    sample["displacementPerInsectWidth"]=distance/side
                    maxStepRatio=max(maxStepRatio,distance/side);stepSamples+=1
                };motionSamples.append(sample);previousInsect=live
            }
            if let live,let prop,let layer=f.prop(prop.id) {
                geometry = geometry && live.id==insect.id && live.trajectory==trajectory && prop.id==insect.id &&
                    Geometry.distance(prop.position,trajectory.position(at:live.age))<1e-5 && prop.size==side &&
                    InsectCatchVerification.layerMatches(prop,layer:layer,view:f.view)
            } else if live != nil {geometry=false}
            if let sprite=f.sprite(),let texture=sprite.sublayers?.first {
                geometry = geometry && (texture.contents as AnyObject?) === d.arts[state.species]?.frames[state.frameName] &&
                    (texture.affineTransform().a>0)==state.facingRight && (sprite.mask as? CAShapeLayer)?.mask==nil
            } else {geometry=false}
            if !contactSeen,let contact=d.engine.lastInsectContact,contact.runID==run {
                contactSeen=true;enteredToContact=fullyEntered.map{contact.insectAge-$0}
                if let anchor=DetailedBirdArt.catchBillAnchor("catchOpen",species:.yellowRumpedFlycatcher),
                   let metadata=PoseClip.catchBeakAnchor(species:.yellowRumpedFlycatcher,frame:"catchOpen") {
                    let offset=metadata.world(foot:.zero,scale:state.scale,facingRight:right)
                    let foot=CGPoint(x:contact.beakPosition.x-offset.x,y:contact.beakPosition.y-offset.y)
                    contactValid=Geometry.distance(anchor,CGPoint(x:metadata.x,y:metadata.y))<1e-5 &&
                        contact.birdID==id && contact.insectID==insect.id && contact.time>=previousTime-1e-8 && contact.time<=d.engine.time+1e-8 &&
                        trajectory.isVisible(at:contact.insectAge) && Geometry.distance(contact.insectPosition,trajectory.position(at:contact.insectAge))<1e-5 &&
                        Geometry.distance(contact.beakPosition,contact.insectPosition)<=trajectory.collisionRadius+1e-7 &&
                        InsectCatchVerification.segmentDistance(foot,previousFoot,state.position)<1e-4 &&
                        d.engine.insectSnapshot()==nil && count(d)==before && state.facingRight==right
                }
                evidence.append(["case":key,"contactTime":contact.time,"insectAge":contact.insectAge,
                    "beak":NSStringFromPoint(contact.beakPosition),"insect":NSStringFromPoint(contact.insectPosition),
                    "contactValid":contactValid,"fullyEnteredAge":fullyEntered.map{$0 as Any} ?? NSNull(),
                    "fullyEnteredToContactSeconds":enteredToContact.map{$0 as Any} ?? NSNull()])
            }
            let stage=CatchArtGeometry.frameNames.contains(state.frameName) ? state.frameName:
                (bird.state == .landing ? "landing":(contactSeen ? "return":"outbound"))
            let firstStage=stages.insert(stage).inserted
            // Fixed world crop, unchanged production speed. Thirty-Hz images
            // cover the whole return; displacement is sampled separately at 60 Hz.
            if tick%4==0 || firstStage {
                try autoreleasepool {
                    let file=sequenceFolder.appendingPathComponent(String(format:"%04d-actual-layer.png",images.count))
                    let actual=try InsectCatchVerification.snapshot(f.view,around:f.display,to:file)
                    images.append(file);imageTimes.append(d.engine.time-start.time-pausedDuration)
                    samples.append(["engineTime":d.engine.time,"unpausedRunAge":imageTimes.last!,"image":file.lastPathComponent,
                        "bird":NSStringFromPoint(state.position),"birdState":bird.state.rawValue,"birdFrame":state.frameName,
                        "insectAge":live.map{$0.age as Any} ?? NSNull(),"insect":live.map{NSStringFromPoint($0.position) as Any} ?? NSNull()])
                    if firstStage,let sprite=f.sprite() {
                        let body=try InsectCatchVerification.contribution(f.view,layer:sprite,actual:actual,region:state.rect)
                        bodyPixels+=body;pixels = pixels && body>=4
                    }
                    if !contactSeen,let prop,let layer=f.prop(prop.id),f.display.contains(prop.rect),visibleInsectSamples<4 {
                        let changed=try InsectCatchVerification.contribution(f.view,layer:layer,actual:actual,region:prop.rect)
                        insectPixels+=changed;visibleInsectSamples+=1;pixels = pixels && changed>0
                    }
                }
            }
            if !pauseDone,let live,live.age>=0.25 {
                pauseDone=true;d.paused=true;let frozen=state,archive=d.observationJournal.archive
                f.advance(1);pausedDuration+=1
                pauseOK=d.engine.insectSnapshot()==live && d.engine.renderSnapshot().first?.position==frozen.position &&
                    d.engine.renderSnapshot().first?.frameName==frozen.frameName && d.engine.reservedLandingCount==1 &&
                    terminal(d.engine,run:run).isEmpty && d.observationJournal.archive==archive
                d.paused=false
            }
            previousFoot=state.position;previousTime=d.engine.time;f.step()
        }
        f.view.updateSprites()
        let settled=validFoot(f),ends=terminal(d.engine,run:run)
        let finalURL=sequenceFolder.appendingPathComponent("settled-actual-layer.png")
        if let state=d.engine.renderSnapshot().first {
            let actual=try InsectCatchVerification.snapshot(f.view,around:f.display,to:finalURL)
            images.append(finalURL);imageTimes.append(d.engine.time-start.time-pausedDuration)
            if let sprite=f.sprite() {let n=try InsectCatchVerification.contribution(f.view,layer:sprite,actual:actual,region:state.rect);bodyPixels+=n;pixels = pixels && n>=4}
        }
        let gif=folder.appendingPathComponent(key+"journey-actual-layers.gif")
        if !images.isEmpty {try InsectCatchVerification.writeGIF(images,times:imageTimes,to:gif)}
        let speeds=zip(trajectory.waypoints,trajectory.waypoints.dropFirst()).map {a,b in Double(Geometry.distance(a.position,b.position))/(b.time-a.time)}
        checks[key+"RealTakeoffContactRecoveryAndLanding"]=airborne && contactSeen && contactValid &&
            Set(CatchArtGeometry.frameNames).isSubset(of:frames) && landingSeen && bird.landedCount==landings+1 && settled &&
            Geometry.distance(bird.position,origin)<0.001 && bird.hostID==f.host.id
        checks[key+"CompletionRequiresSettledValidFootAndExactlyOneCount"]=noEarlyCount && ends.count==1 && ends.first?.type == .completed &&
            settled && f.observedSettledRuns.contains(run.rawValue) && count(d)==before+1 && d.engine.insectMissedTargetCount==misses &&
            (ends.first?.time ?? .infinity)-start.time-pausedDuration<=25+1e-6
        checks[key+"SingleIdentityNoTeleportAndCleanup"]=identity && continuous && clear(d.engine) && d.engine.insectSnapshot()==nil && f.prop(insect.id)==nil &&
            d.residentCount==1 && d.arrivalCount==0 && d.departureCount==0
        checks[key+"RealMirroredLayersContainVisibleBirdAndInsect"]=geometry && pixels && bodyPixels>0 && insectPixels>0 && visibleInsectSamples>0
        checks[key+"PauseFreezesRunInsectReservationAndCount"]=pauseDone && pauseOK
        checks[key+"InsectMovesAtMostHalfCanvasPer60HzStep"]=stepSamples>0 && maxStepRatio<=0.5+1e-8 && !speeds.isEmpty &&
            speeds.allSatisfy{$0<=480*Double(scale)+1e-6 && $0/60/Double(side)<=0.5+1e-8}
        checks[key+"FullyVisibleForPointEightSecondsBeforeActualContact"]=contactSeen && enteredToContact.map{$0>=0.8-1e-8}==true
        evidence.append(["case":key,"ground":ground,"origin":NSStringFromPoint(origin),"finalFoot":NSStringFromPoint(bird.position),
            "finalState":bird.state.rawValue,"terminal":ends.first?.type.rawValue ?? "none","reason":ends.first?.reason?.rawValue ?? "none",
            "settledAtObservationDelivery":f.observedSettledRuns.contains(run.rawValue),
            "worldScale":scale,"insectWidthPoints":side,"segmentSpeedsPointsPerSecond":speeds,
            "segmentSpeedsPerWorldScale":speeds.map{$0/Double(scale)},"maxActual60HzDisplacementPerCanvas":maxStepRatio,
            "samples":samples,"insectMotion60Hz":motionSamples,"journeyGIF":gif.lastPathComponent,
            "capture":"Unmodified production root CALayer at 30 Hz plus phase changes and settled endpoint; world crop. GIF centisecond quantization; JSON simulation timestamps authoritative."])
    }
    private static func miss(_ f:Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        f.install();let d=f.d,bird=f.bird!,before=d.observationJournal.archive,misses=d.engine.insectMissedTargetCount,w=d.engine.world
        let y=f.display.minY+16*d.scale,half=9*d.scale
        guard let trajectory=InsectTrajectory(waypoints:[
            .init(time:0,position:CGPoint(x:f.display.maxX+half,y:y)),
            .init(time:6,position:CGPoint(x:f.display.minX-half,y:y))],display:f.display,worldScale:d.scale,
            screens:w.screens,displays:w.displays,displayIDs:w.displayIDs) else {throw failure("Invalid physical miss trajectory")}
        let result=d.engine.startInsectCatchFixture(species:.yellowRumpedFlycatcher,trajectory:trajectory)
        guard case .started(let run)=result,let insect=d.engine.insectSnapshot() else {
            checks["flycatcherCatchNativeFrozenMissRealResolverAndSettledFailure"]=false
            evidence.append(["missStart":String(describing:result)]);return
        }
        var contactAbsent=true,unchanged=true,recovery=false,airborne=false,frames=Set<String>(),noEarlyCount=true
        for _ in 0..<25*120 {
            guard d.engine.behavior(of:bird) == .insectCatch else {break}
            contactAbsent = contactAbsent && d.engine.lastInsectContact?.runID != run
            airborne = airborne || (bird.state == .flying && Geometry.distance(bird.position,f.origin)>1)
            noEarlyCount = noEarlyCount && d.observationJournal.archive==before
            if let live=d.engine.insectSnapshot() {unchanged = unchanged && live.id==insect.id && live.trajectory==trajectory}
            if let state=d.engine.renderSnapshot().first,frames.insert(state.frameName).inserted {
                recovery = recovery || state.frameName=="catchRecover";f.view.updateSprites()
                _=try InsectCatchVerification.snapshot(f.view,around:state.rect.insetBy(dx:-20,dy:-20),to:folder.appendingPathComponent("flycatcher-miss-"+state.frameName+"-actual-layer.png"))
            };f.step()
        }
        let ends=terminal(d.engine,run:run)
        checks["flycatcherCatchNativeFrozenMissRealResolverAndSettledFailure"]=airborne && contactAbsent && unchanged && recovery && frames.contains("catchOpen") &&
            !frames.contains("catchClose") && ends.count==1 && ends.first?.type == .failed && ends.first?.reason == .missedTarget && validFoot(f) &&
            Geometry.distance(bird.position,f.origin)<0.001 && clear(d.engine) && noEarlyCount && d.observationJournal.archive==before && d.engine.insectMissedTargetCount==misses+1
        f.advance(12.2);f.view.updateSprites()
        checks["flycatcherCatchNativeMissInsectExpiresWithoutLayerOrJournal"]=d.engine.insectSnapshot()==nil && f.prop(insect.id)==nil && d.observationJournal.archive==before
        evidence.append(["miss":"Frozen legal nonintersecting top corridor; public production-admission fixture bridge, real executor and resolver.",
            "contactAbsent":contactAbsent,"trajectoryUnchanged":unchanged,"finalState":bird.state.rawValue,
            "reason":ends.first?.reason?.rawValue ?? "none"])
    }
    private static func interruptions(_ f:Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        for action in ["originRemoved","newObstacle","click","clear","disable","pausedDisable","sleep"] {
            f.install();let d=f.d,bird=f.bird!,id=d.engine.id(of:bird)!,before=d.observationJournal.archive
            guard let run=f.start(),let insect=d.engine.insectSnapshot() else {
                checks["flycatcherCatchNativeInterrupt-"+action]=false;evidence.append(["interrupt":action,"startFailed":true]);continue
            }
            f.advance(0.3);f.view.updateSprites()
            let position=bird.position,sequence=d.engine.events.last?.sequence ?? 0
            let beforeActionInsect=d.engine.insectSnapshot()
            var hit=false,clicked=false,obstacle:CGRect?,noJump=true,noCollision=true
            switch action {
            case "originRemoved":d.surfaces.removeAll{$0.id==f.host.id};d.syncWorld(buttonsDown:false)
            case "newObstacle":
                // A new utility panel across the future outbound corridor,
                // ahead of the current bird, never covering its present pixels.
                let s=d.spriteScale(for:bird)
                let rect=CGRect(x:f.origin.x+60*s,y:f.origin.y-140*s,width:50*s,height:130*s)
                obstacle=rect;d.surfaces.insert(Surface(id:7403,pid:77,rect:rect,layer:10),at:0);d.syncWorld(buttonsDown:false)
            case "click":
                if let state=d.engine.renderSnapshot().first,let point=InsectCatchVerification.visiblePoint(state,in:d) {
                    hit=d.bird(at:point) === bird
                    if hit,let event=NativeVerificationInput.leftDown(at:point) {d.handleMouseDown(event);clicked=true}
                }
            case "clear":f.settings.clearInsectButton.performClick(nil)
            case "disable","pausedDisable":
                if action=="pausedDisable" {d.paused=true}
                var value=d.settings;value.insectCatchEnabled=false;d.settings=value
            default:d.engine.handle(.cancelAmbient(.sleep))
            }
            noJump=Geometry.distance(bird.position,position)<1e-5
            if action=="click" {
                let relocate=d.engine.events.first{$0.sequence>sequence && $0.type == .started && $0.kind == .relocate && $0.participants==[id]}
                let ends=terminal(d.engine,run:run),same=d.engine.insectSnapshot()
                checks["flycatcherCatchNativeClickHitsOriginalAndActuallyRelocates"]=hit && clicked && relocate != nil && d.engine.behavior(of:bird) == .relocate &&
                    ends.count==1 && ends.first?.reason == .replaced && (ends.first?.sequence ?? .max)<(relocate?.sequence ?? 0)
                checks["flycatcherCatchNativeClickLeavesIndependentInsect"]=same?.id==insect.id && same?.trajectory==insect.trajectory &&
                    same != nil && same?.age==beforeActionInsect?.age && same?.remainingLifetime==beforeActionInsect?.remainingLifetime
                f.advance(0.15)
                let later=d.engine.insectSnapshot()
                checks["flycatcherCatchNativeUncaughtInsectContinuesWithoutReset"]=later?.id==insect.id && later?.trajectory==insect.trajectory &&
                    (later?.age ?? 0)>(same?.age ?? .infinity) && (later?.remainingLifetime ?? .infinity)<(same?.remainingLifetime ?? 0) &&
                    later.map{Geometry.distance($0.position,insect.trajectory.position(at:$0.age))<1e-5}==true
            }
            if ["clear","disable","pausedDisable","sleep"].contains(action) {
                checks["flycatcherCatchNativeImmediateClear-"+action]=d.engine.insectSnapshot()==nil && !d.engine.hasInsectCatchPreview
            }
            d.paused=false
            var previous=bird.position
            for _ in 0..<25*120 {
                if let obstacle {
                    let footprint=Geometry.landingFootprint(at:bird.position,scale:d.spriteScale(for:bird))
                    noCollision = noCollision && !footprint.intersects(obstacle)
                }
                noJump = noJump && Geometry.distance(previous,bird.position)<20*d.spriteScale(for:bird)
                if d.engine.behavior(of:bird)==nil,bird.state == .perched {break}
                previous=bird.position;f.step()
            }
            let ends=terminal(d.engine,run:run)
            f.view.updateSprites()
            if let state=d.engine.renderSnapshot().first {
                _=try InsectCatchVerification.snapshot(f.view,around:state.rect.union(obstacle ?? state.rect).insetBy(dx:-20,dy:-20),
                    to:folder.appendingPathComponent("flycatcher-interrupt-"+action+"-actual-layer.png"))
            }
            checks["flycatcherCatchNativeInterrupt-"+action]=ends.count==1 && ends.first?.type != .completed && d.engine.lastInsectContact?.runID != run &&
                d.observationJournal.archive==before && validFoot(f) && noJump && noCollision && clear(d.engine)
            if action=="originRemoved" {checks["flycatcherCatchNativeLostOriginReturnsToDifferentValidHost"]=bird.hostID != f.host.id && validFoot(f)}
            f.advance(12.2);f.view.updateSprites()
            checks["flycatcherCatchNativeInterruptCleanup-"+action]=clear(d.engine) && d.engine.insectSnapshot()==nil && f.prop(insect.id)==nil &&
                d.observationJournal.archive==before && d.residentCount==1 && d.arrivalCount==0 && d.departureCount==0
            evidence.append(["interrupt":action,"hitOriginal":hit,"clicked":clicked,"noJump":noJump,"noObstacleCollision":noCollision,
                "obstacle":obstacle.map{NSStringFromRect($0) as Any} ?? NSNull(),"finalHostID":bird.hostID.map{$0 as Any} ?? NSNull(),
                "finalState":bird.state.rawValue,"finalFootValid":validFoot(f),"reason":ends.first?.reason?.rawValue ?? "none"])
        }
    }
    private static func validFoot(_ f:Fixture)->Bool {
        let b=f.bird!,e=f.d.engine,s=f.d.spriteScale(for:b)
        guard b.state == .perched,b.edge == .top,!b.needsDestination,
              let host=e.world.surfaces.first(where:{$0.id==b.hostID}),!host.isHabitat,host.isGround || host.layer==0 else {return false}
        let foot=Geometry.foot(on:host,fraction:b.fraction,edge:.top,scale:s)
        return Geometry.distance(foot,b.position)<0.001 && e.world.displays.contains{$0.contains(Geometry.landingFootprint(at:foot,scale:s))} &&
            Geometry.isLandingVisible(on:host.id,at:foot,surfaces:e.world.surfaces,scale:s)
    }
    private static func count(_ d:DesktopController)->Int {d.observationJournal.archive.entries.first{$0.species == .yellowRumpedFlycatcher && $0.behavior=="insectCatch"}?.previewCount ?? 0}
    private static func terminal(_ e:BehaviorEngine,run:BehaviorRunID)->[BehaviorEvent] {e.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}}
    private static func clear(_ e:BehaviorEngine)->Bool {e.activeRunCount==0 && e.leasedBirdCount==0 && e.reservedLandingCount==0 && !e.hasInsectCatchPreview}
    private static func failure(_ text:String)->NSError {NSError(domain:"FlycatcherInsectCatchVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
