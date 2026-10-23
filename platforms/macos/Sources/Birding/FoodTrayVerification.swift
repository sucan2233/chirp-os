import AppKit
import BirdingCore

/// B14 native evidence. Explicit simulation steps and real production layers;
/// never starts a controller, installs monitors, or loads/saves user settings.
enum FoodTrayVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        guard Thread.isMainThread else {throw failure("Food tray evidence requires the main thread.")}
        let output=folder.appendingPathComponent("food-tray-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        checks["foodTrayNativeCompleted"]=false
        let h=try Harness(folder:output)
        defer {h.close()}
        do {
            for species in [SpeciesID.treeSparrow,.spottedDove] {
                for scale:CGFloat in [0.5,1,2] {try h.journey(species,scale:scale,into:&checks)}
            }
            for feeding in [false,true] {
                try h.interrupt(feeding:feeding,remove:false,into:&checks)
                try h.interrupt(feeding:feeding,remove:true,into:&checks)
            }
            try h.occlusion(into:&checks)
            try h.lifetime(into:&checks)
            h.d.engine.handle(.removeFoodTray);h.close()
            checks["foodTrayNativeFinalResourcesReleased"]=h.clear && h.sameBird && h.d.engine.habitatSnapshot().isEmpty
            checks["foodTrayNativeIsolatedNoControllerStart"]=h.isolated
            checks["foodTrayNativeFixtureWindowsHidden"] = !h.overlay.isVisible && !h.hostWindow.isVisible && !h.panel.isVisible
            checks["foodTrayNativeCompleted"]=true
            try h.report(checks)
        } catch {try? h.report(checks,error:error.localizedDescription);throw error}
        print("Food tray native evidence: \(output.path)")
    }
    private static func failure(_ message:String)->NSError {
        NSError(domain:"FoodTrayVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }
    private final class Harness {
        let d:DesktopController,folder:URL,display:CGRect,work:CGRect
        let overlay:OverlayPanel,hostWindow:NSWindow,panel:NSPanel
        let view:DesktopView,hostView=NSView(frame:.zero),panelView=NSView(frame:.zero)
        let dt=BehaviorEngine.step,prefsName="FoodTrayVerification."+UUID().uuidString
        var host=Surface(id:0,rect:.zero),bird:Bird?,birdID:BirdID?,origin=CGPoint.zero,target=CGPoint.zero
        var name="",run:BehaviorRunID?,previous=CGPoint.zero
        var identityOK=true,geometryOK=true,continuous=true,contactOK=true,leasesOK=true
        var log:[UInt64:BehaviorEvent]=[:],trace:[[String:Any]]=[],cases:[[String:Any]]=[],images:[[String:Any]]=[]
        init(folder:URL) throws {
            let d=DesktopController()
            guard let screen=NSScreen.screens.first,let display=d.displayRects.first,let work=d.screenRects.first,
                  work.width>=800,work.height>=600 else {throw FoodTrayVerification.failure("Requires an 800 × 600 point work area.")}
            self.d=d;self.folder=folder;self.display=display;self.work=work
            hostWindow=NSWindow(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
            panel=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            overlay=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size))
            d.preferences=UserDefaults(suiteName:prefsName)!
            d.settingsURL=folder.appendingPathComponent("unused-settings.json")
            d.legacyURL=folder.appendingPathComponent("unused-legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("unused-visitors.json")
            d.visitorMemoryPersistenceEnabled=false;d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            for (window,content) in [(hostWindow,hostView),(panel,panelView)] {
                window.isReleasedWhenClosed=false;window.hasShadow=false;window.ignoresMouseEvents=true
                window.animationBehavior = .none;content.wantsLayer=true
                content.layer?.backgroundColor=NSColor(calibratedWhite:0.8,alpha:1).cgColor;window.contentView=content
            }
            overlay.isReleasedWhenClosed=false;overlay.isOpaque=false;overlay.backgroundColor = .clear
            overlay.hasShadow=false;overlay.level = .floating;overlay.ignoresMouseEvents=true;overlay.animationBehavior = .none
            view.controller=d;view.desktopRect=display;overlay.contentView=view
        }
        func close() {
            d.engine.handle(.cancelAmbient(.shutdown));events()
            overlay.orderOut(nil);hostWindow.orderOut(nil);panel.orderOut(nil)
        }
        var isolated:Bool {
            d.timer==nil && d.status==nil && d.globalMouseMonitor==nil && d.localMouseMonitor==nil &&
                d.preferences !== UserDefaults.standard && d.visitorMemoryPersistence==nil && !d.visitorMemoryPersistenceEnabled &&
                d.engine.activeVisitorCount==0 && d.engine.rememberedVisitorCount==0 &&
                [d.settingsURL,d.legacyURL,d.visitorMemoryURL].allSatisfy {
                    $0.deletingLastPathComponent()==folder && !FileManager.default.fileExists(atPath:$0.path)
                } && (d.preferences.persistentDomain(forName:prefsName)?.isEmpty ?? true)
        }
        var clear:Bool {d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0 && d.engine.habitatReservationCount==0 && d.engine.scenePropCount==0}
        var sameBird:Bool {
            guard let bird,let birdID else {return false}
            return d.birds.count==1 && d.birds.first === bird && d.engine.id(of:bird)==birdID && d.residentCount==1 &&
                d.engine.pendingCount==0 && d.engine.passingCount==0 && d.engine.departingCount==0 && d.arrivalCount==0 && d.departureCount==0
        }
        var sprite:CALayer? {view.layer?.sublayers?.first{$0.name==nil && $0.mask is CAShapeLayer}}
        var tray:CALayer? {view.layer?.sublayers?.first{$0.name?.hasPrefix("habitat-food-tray-")==true}}
        var state:BirdRenderState? {d.engine.renderSnapshot().first{$0.id==birdID}}
        func events() {for event in d.engine.events {log[event.sequence]=event}}
        func terminal(_ id:BehaviorRunID?)->[BehaviorEvent] {
            events();return log.values.filter{$0.runID==id && id != nil && [.completed,.cancelled,.failed].contains($0.type)}.sorted{$0.sequence<$1.sequence}
        }
        func surface(_ window:NSWindow)->Surface {
            Surface(id:UInt32(window.windowNumber),pid:ProcessInfo.processInfo.processIdentifier,
                rect:Geometry.quartz(window.frame,primaryHeight:d.primaryHeight),layer:window.level.rawValue)
        }
        func place(_ window:NSWindow,content:NSView,rect:CGRect) {
            window.setFrame(Geometry.quartz(rect.integral,primaryHeight:d.primaryHeight),display:true)
            content.frame=CGRect(origin:.zero,size:window.frame.size);content.layer?.frame=content.bounds
        }
        func fixture(_ species:SpeciesID = .treeSparrow,scale:CGFloat=1,name:String) throws {
            d.engine.handle(.removeFoodTray);d.engine.handle(.cancelAmbient(.screensChanged));events();d.paused=false;d.birds=[]
            self.name=name;run=nil;panel.orderOut(nil);d.scale=scale
            var settings=d.settings
            settings.foodTrayEnabled=true;settings.visitorMemoryEnabled=false;settings.fixedPerches=[]
            settings.perchActions=false;settings.passiveAttentionEnabled=false;settings.sideHopEnabled=false
            settings.takeoffPreparationEnabled=false;settings.edgePeekEnabled=false;settings.activityRhythm = .steady
            d.settings=settings;d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
            // Keep the live pointer away from the entire outbound/return corridor.
            // No cursor warping or synthetic global input is used.
            let ys:[CGFloat]=[0.42,0.78]
            let y=ys.max {abs(work.minY+$0*work.height-d.pointerPosition.y)<abs(work.minY+$1*work.height-d.pointerPosition.y)}!
            // Ordinary recovery/relocation only considers windows at least 100
            // points tall. A shorter fixture forces hostless fallback flights.
            place(hostWindow,content:hostView,rect:CGRect(x:work.minX+20,y:work.minY+y*work.height,width:work.width-40,height:100))
            hostWindow.orderFrontRegardless();overlay.orderFrontRegardless();host=surface(hostWindow)
            let b=Bird(position:.zero,fraction:0.2,profile:d.catalog.profile(species),random:{0.5})
            b.perch(on:host,spriteScale:d.spriteScale(for:b));b.perchDuration=600;b.tick(0.6)
            bird=b;d.surfaces=[host];d.birds=[b];d.syncWorld()
            birdID=d.engine.id(of:b);origin=b.position;previous=origin
            target=CGPoint(x:work.minX+work.width*0.73,y:host.rect.minY)
            identityOK=true;geometryOK=true;continuous=true;contactOK=true;leasesOK=true
            guard d.engine.handle(.placeFoodTray(at:target)).accepted else {throw FoodTrayVerification.failure("\(name): production placement rejected.")}
            try record("placed")
        }
        @discardableResult func start() throws -> Bool {
            d.syncWorld();let result=d.engine.handle(.foodTrayVisit(.preview));events()
            guard case .started(let id)=result else {throw FoodTrayVerification.failure("\(name): visit rejected: \(result)")}
            run=id;try record("observe");return true
        }
        func step(_ label:String="step") throws {d.syncWorld();d.engine.advance(dt);try record(label)}
        func phase()->String {
            guard let bird else {return "missing"}
            if d.engine.behavior(of:bird) != .foodTrayVisit {return "idle"}
            if bird.hostID==host.id {
                if bird.state == .flying {return "return"}
                if bird.state == .landing {return "return-land"}
                return Geometry.distance(bird.position,origin)<0.01 && bird.state == .perched ? (state?.frameName=="feedLook" ? "observe":"settle"):"invalid"
            }
            if bird.state == .flying {return "approach"}
            if bird.state == .landing {return "land"}
            return state?.frameName.hasPrefix("feed")==true ? "feed":"land"
        }
        func record(_ label:String) throws {
            view.updateSprites();events();guard let bird,let state else {throw FoodTrayVerification.failure("Missing fixture bird.")}
            identityOK = identityOK && sameBird
            let delta=Geometry.distance(previous,bird.position);previous=bird.position
            continuous = continuous && delta<=CGFloat(FlightBehavior.cruiseSpeed(bird.profile.id,multiplier:bird.profile.speed)*dt)+0.001
            let local=state.rect.offsetBy(dx:-display.minX,dy:-display.minY)
            let layer=sprite,texture=layer?.sublayers?.first
            geometryOK = geometryOK && layer?.bounds.size==local.size &&
                layer?.position==CGPoint(x:local.midX,y:local.midY) &&
                (texture?.contents as AnyObject?) === d.arts[state.species]?.frames[state.frameName] &&
                texture?.affineTransform()==CGAffineTransform(scaleX:state.facingRight ? 1:-1,y:1)
            let visiting=d.engine.behavior(of:bird) == .foodTrayVisit
            leasesOK = leasesOK && (visiting ? (d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==2 && d.engine.habitatReservationCount==1):d.engine.habitatReservationCount==0)
            var row:[String:Any]=["case":name,"label":label,"time":d.engine.time,"phase":phase(),"id":state.id.rawValue,
                "species":state.species.rawValue,"frame":state.frameName,"state":bird.state.rawValue,"foot":point(bird.position),
                "scale":state.scale,"host":bird.hostID.map{Int($0)} ?? -1,"fraction":bird.fraction,"stepDistance":delta,
                "leases":d.engine.leasedBirdCount,"landingSlots":d.engine.reservedLandingCount,"habitatSlots":d.engine.habitatReservationCount]
            if let object=d.engine.habitatSnapshot().first,let art=FoodTrayArt.shared {
                let rect=art.rect(for:object.rect),layerRect=rect.offsetBy(dx:-display.minX,dy:-display.minY)
                geometryOK = geometryOK && tray?.bounds.size==layerRect.size && tray?.position==CGPoint(x:layerRect.midX,y:layerRect.midY) &&
                    (tray?.sublayers?.first?.contents as AnyObject?) === art.image
                let seedY=rect.minY+art.contactY*rect.width/CGFloat(art.image.width)
                let tip=CGPoint(x:bird.position.x+11*state.scale,y:bird.position.y)
                let contact=phase()=="feed" && ["feedDown0","feedDown1"].contains(state.frameName)
                if contact {contactOK = contactOK && state.facingRight && abs(seedY-tip.y)<0.001 &&
                    abs(object.rect.minY-bird.position.y)<0.001 && rect.contains(CGPoint(x:tip.x,y:tip.y+0.001)) &&
                    alpha(art.image,point:CGPoint(x:(tip.x-rect.minX)*CGFloat(art.image.width)/rect.width,y:art.contactY))>0}
                row["trayRect"]=NSStringFromRect(rect);row["seedY"]=seedY;row["downBillWorld"]=point(tip)
                row["downContact"]=contact;row["portions"]=object.remainingUses;row["lifetime"]=object.remainingLifetime
            }
            trace.append(row)
        }
        func journey(_ species:SpeciesID,scale:CGFloat,into checks:inout [String:Bool]) throws {
            try fixture(species,scale:scale,name:"\(species.rawValue)-scale-\(scale)")
            // At 1× consume all three portions; scale endpoints each run a full journey.
            let visits=scale==1 ? 3:1
            for visit in 0..<visits {
                try start();let started=d.engine.time
                var times:[String:Double]=[:],seen=Set<String>(),frames=Set<String>()
                for _ in 0..<30*60 {
                    try step();let p=phase();if times[p]==nil {times[p]=d.engine.time}
                    if p=="feed",let state {frames.insert(state.frameName)}
                    if ["approach","land","return","settle"].contains(p),seen.insert(p).inserted {try snapshot("visit-\(visit+1)-"+p)}
                    if p=="feed",let state,["feedDown0","feedDown1"].contains(state.frameName),seen.insert(state.frameName).inserted {
                        try snapshot("visit-\(visit+1)-"+state.frameName)
                    }
                    if !terminal(run).isEmpty {break}
                }
                let ends=terminal(run),prefix="foodTrayNative-"+name+"-visit-\(visit+1)-"
                let elapsed=d.engine.time-(times["settle"] ?? d.engine.time)
                checks[prefix+"FullObserveFlightLandFeedReturnSettle"]=ends.count==1 && ends.first?.type == .completed &&
                    ["approach","land","feed","return","return-land","settle"].allSatisfy{times[$0] != nil} &&
                    abs((times["approach"] ?? started)-started-0.8)<=dt+1e-7 &&
                    abs((times["return"] ?? 0)-(times["feed"] ?? 0)-3.6)<=dt+1e-7 && abs(elapsed-0.6)<=dt+1e-7
                checks[prefix+"FourFeedingFramesAndSeedContact"]=frames==Set(BirdArt.feedingNames) && contactOK
                checks[prefix+"ProductionLayersContinuousIdentityAndSlots"]=geometryOK && continuous && identityOK && leasesOK && sameBird && clear
                checks[prefix+"ReturnsToOriginalHostFractionAndFoot"]=bird?.hostID==host.id && bird?.fraction==0.2 &&
                    bird.map{Geometry.distance($0.position,origin)<0.001 && $0.state == .perched && !$0.needsDestination}==true
                let object=d.engine.habitatSnapshot().first
                checks[prefix+"ConsumesExactlyOnePortion"]=visit==2 ? object==nil:object?.remainingUses==2-visit
                cases.append(["case":name,"visit":visit+1,"phaseTimes":times,"run":run?.rawValue ?? 0,"terminalCount":ends.count])
            }
        }
        func ready(feeding:Bool) throws {
            for _ in 0..<30*60 {
                try step()
                if feeding ? (phase()=="feed" && state?.frameName=="feedDown0"):(phase()=="approach" && bird.map{Geometry.distance($0.position,origin)>5}==true) {return}
                if !terminal(run).isEmpty {break}
            }
            throw FoodTrayVerification.failure("\(name): did not reach requested interruption phase.")
        }
        func interrupt(feeding:Bool,remove:Bool,into checks:inout [String:Bool]) throws {
            try fixture(feeding ? .spottedDove:.treeSparrow,name:(remove ? "remove":"click")+(feeding ? "-feed":"-flight"))
            try start();try ready(feeding:feeding);let oldRun=run
            d.paused=true;try record("paused")
            let before=bird!.position,frame=state!.frameName,lifetime=d.engine.habitatSnapshot().first!.remainingLifetime
            for _ in 0..<90 {try step("paused")}
            checks["foodTrayNative-"+name+"-PauseFreezesMotionFrameLifetimeAndLease"]=bird?.position==before && state?.frameName==frame &&
                d.engine.habitatSnapshot().first?.remainingLifetime==lifetime && terminal(oldRun).isEmpty && leasesOK
            try snapshot("paused")
            let clicked:Bool
            if remove {clicked=false;d.engine.handle(.removeFoodTray)}
            else {
                let s=state!,art=d.arts[s.species]!
                let solid=pixelPoint(s,art:art,solid:true),transparent=pixelPoint(s,art:art,solid:false)
                checks["foodTrayNative-"+name+"-TransparentAlphaPassesActualHitTesting"]=transparent.map{d.bird(at:$0)==nil && !d.relocateBird(at:$0)} ?? false
                clicked=solid.map{d.bird(at:$0) === bird && d.relocateBird(at:$0)} ?? false
            }
            events();let ends=terminal(oldRun)
            checks["foodTrayNative-"+name+"-SingleTerminalAndNoTeleport"]=ends.count==1 && ends.first?.type == .cancelled &&
                ends.first?.reason==(remove ? .removed:.replaced) && bird?.position==before && sameBird &&
                d.engine.habitatReservationCount==0 && (remove ? d.engine.habitatSnapshot().isEmpty:clicked)
            try record("handoff");try snapshot("handoff");d.paused=false
            // The normal recovery router is needed only after an explicit removal.
            if remove,let bird,bird.needsDestination {_=d.chooseDestination(bird)}
            for _ in 0..<30*60 {
                try step("recovery")
                if clear,bird?.state == .perched {break}
            }
            checks["foodTrayNative-"+name+"-RecoveryReleasesAllResources"]=clear && sameBird && bird?.state == .perched &&
                bird?.needsDestination==false && terminal(oldRun).count==1
        }
        func occlusion(into checks:inout [String:Bool]) throws {
            try fixture(name:"own-panel-mask")
            guard let object=d.engine.habitatSnapshot().first,let art=FoodTrayArt.shared else {throw FoodTrayVerification.failure("Missing tray art.")}
            let rect=art.rect(for:object.rect)
            panel.level = .floating
            place(panel,content:panelView,rect:CGRect(x:target.x-2,y:rect.minY-60,width:rect.width,height:rect.height+120))
            panel.orderFrontRegardless();let blocker=surface(panel)
            d.surfaces=[blocker,host];d.syncWorld();try record("occluded")
            let blocked=CGPoint(x:target.x+10,y:target.y),exposed=CGPoint(x:rect.minX+rect.width*0.2,y:target.y)
            func inMask(_ p:CGPoint)->Bool {((tray?.mask as? CAShapeLayer)?.path?.contains(CGPoint(x:p.x-rect.minX,y:p.y-rect.minY))) ?? false}
            checks["foodTrayNativeOwnPanelProductionMaskCutsCoveredKeepsExposed"]=blocker.layer>0 && !inMask(blocked) && inMask(exposed) && tray?.isHidden==false
            checks["foodTrayNativeOwnPanelRejectsUnsafeVisitWithoutNewBirds"]=d.engine.handle(.foodTrayVisit(.preview)) == .rejected(.noSpace) && clear && sameBird
            checks["foodTrayNativeSourceAlphaPreservedAndOverlayPassesInput"]=alpha(art.image,point:.zero)==0 &&
                art.image.width>0 && overlay.ignoresMouseEvents && !overlay.canBecomeKey && !overlay.canBecomeMain && !view.isOpaque
            let info=CGWindowListCopyWindowInfo([.optionIncludingWindow,.excludeDesktopElements],CGWindowID(panel.windowNumber)) as? [[String:Any]]
            let observed=info?.first{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value==blocker.id}
            cases.append(["case":name,"ownPanelRect":NSStringFromRect(blocker.rect),"ownPanelLayer":blocker.layer,
                "windowServerObservationAvailable":observed != nil,"windowServerObservedLayer":(observed?[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1,
                "windowServerOnscreen":(observed?[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                "limitation":"Own panel geometry explicitly fed to production masks. Foreign-process sampling and visual WindowServer visibility are unverified; locked sessions may hide the panel.",
                "sourceSize":NSStringFromSize(art.sourceSize),"alphaCrop":NSStringFromRect(art.sourceAlphaBounds)])
            try snapshot("occluded");panel.orderOut(nil);d.surfaces=[host];d.syncWorld()
        }
        func lifetime(into checks:inout [String:Bool]) throws {
            try fixture(name:"placement-lifetime");d.engine.handle(.removeFoodTray)
            d.syncWorld(at:target,buttonsDown:false)
            let scheduled=d.engine.handle(.placeFoodTrayAfter(3)) == .scheduled
            // No renderSnapshot here: it intentionally samples the live pointer.
            // The delayed placement fixture supplies an explicit point instead.
            for _ in 0..<179 {d.engine.advance(dt)}
            let waits=d.engine.habitatSnapshot().isEmpty && d.engine.hasFoodTrayPlacement
            d.engine.advance(dt);events()
            let placed=d.engine.habitatSnapshot().first
            checks["foodTrayNativeDelayedPlacementThreeSecondsNoSpawn"]=scheduled && waits && placed?.remainingUses==3 &&
                placed.map{abs($0.rect.midX-target.x)<0.001 && abs($0.rect.minY-target.y)<0.001}==true && sameBird
            for _ in 0..<(180*60+1) {d.engine.advance(dt)}
            events();view.updateSprites()
            checks["foodTrayNativeExpiresAt180SecondsWithoutLeasesOrNewBirds"]=placed?.remainingLifetime==180 &&
                d.engine.habitatSnapshot().isEmpty && !d.engine.hasFoodTrayPlacement && tray==nil && clear && sameBird
        }
        func pixelPoint(_ state:BirdRenderState,art:BirdArt,solid:Bool)->CGPoint? {
            for y in 0..<48 {for x in 0..<48 where art.contains(frame:state.frameName,x:x,y:y)==solid {
                let p=CGPoint(x:state.rect.minX+(CGFloat(state.facingRight ? x:47-x)+0.25)*state.scale,
                    y:state.rect.minY+(CGFloat(y)+0.25)*state.scale)
                if !state.blockers.contains(where:{$0.contains(p)}) {return p}
            }}
            return nil
        }
        func alpha(_ image:CGImage,point:CGPoint)->UInt8 {
            guard point.x>=0,point.y>=0,point.x<CGFloat(image.width),point.y<CGFloat(image.height),
                  let pixel=image.cropping(to:CGRect(x:Int(point.x),y:Int(point.y),width:1,height:1)),
                  let ctx=CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return 0}
            ctx.draw(pixel,in:CGRect(x:0,y:0,width:1,height:1))
            return ctx.data?.bindMemory(to:UInt8.self,capacity:4)[3] ?? 0
        }
        func snapshot(_ label:String) throws {
            view.updateSprites();let states=d.engine.renderSnapshot()
            var crop=host.rect
            for state in states {crop=crop.union(state.rect)}
            if let art=FoodTrayArt.shared {for object in d.engine.habitatSnapshot() {crop=crop.union(art.rect(for:object.rect))}}
            crop=crop.insetBy(dx:-10,dy:-10).intersection(display).integral
            guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(crop.width),pixelsHigh:Int(crop.height),bitsPerSample:8,
                samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
                  let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else {throw FoodTrayVerification.failure("Cannot allocate layer composite.")}
            let ctx=graphics.cgContext
            ctx.setFillColor(NSColor(calibratedWhite:0.18,alpha:1).cgColor);ctx.fill(CGRect(origin:.zero,size:crop.size))
            ctx.translateBy(x:-crop.minX,y:crop.maxY);ctx.scaleBy(x:1,y:-1)
            func drawWindow(_ content:NSView,_ rect:CGRect) {
                ctx.saveGState();ctx.translateBy(x:rect.minX,y:rect.maxY);ctx.scaleBy(x:1,y:-1);content.layer?.render(in:ctx);ctx.restoreGState()
            }
            drawWindow(hostView,host.rect)
            ctx.saveGState();ctx.translateBy(x:display.minX,y:display.minY);view.layer?.render(in:ctx);ctx.restoreGState()
            if panel.isVisible {drawWindow(panelView,surface(panel).rect)}
            guard let png=bitmap.representation(using:.png,properties:[:]) else {throw FoodTrayVerification.failure("Cannot encode composite.")}
            let file=name+"-"+label+"-layer-composite.png"
            try png.write(to:folder.appendingPathComponent(file),options:.atomic)
            images.append(["file":file,"case":name,"time":d.engine.time,"crop":NSStringFromRect(crop),"label":label,
                "kind":"Production DesktopView/BirdArt/FoodTrayArt CALayer composite; not a WindowServer screenshot."])
        }
        func point(_ p:CGPoint)->[CGFloat] {[p.x,p.y]}
        func report(_ checks:[String:Bool],error:String?=nil) throws {
            events();let own=checks.filter{$0.key.hasPrefix("foodTrayNative")}
            let evidence:[String:Any]=["behavior":"B14","seed":String(d.engine.seed),"passed":error==nil && own.values.allSatisfy{$0},
                "checks":own,"error":error ?? "","cases":cases,"images":images,"dt":dt,
                "execution":"Explicit fixed steps, isolated preferences and file paths; no DesktopController.start or global input injection.",
                "input":"Production BirdArt alpha hit testing and DesktopController.relocateBird; no global NSEvent delivery is claimed.",
                "contact":"Right-facing feet (29,39), down-bill (40,39). World bill = foot + (11*birdScale,0); seed line uses approved FoodTrayArt contactY below rear rim.",
                "scaleCoverage":"World scale 0.5, 1 and 2, with each species' production relativeScale; no claim of all editable adult-length combinations.",
                "occlusion":"Own panel actual frame/level explicitly supplied. Mask assertions are deterministic; WindowServer onscreen observation is metadata, never a pass condition.",
                "events":log.values.sorted{$0.sequence<$1.sequence}.map {e -> [String:Any] in
                    ["sequence":e.sequence,"time":e.time,"run":e.runID?.rawValue ?? 0,"type":e.type.rawValue,"kind":e.kind?.rawValue ?? "none",
                        "source":e.source.rawValue,"reason":e.reason?.rawValue ?? "","participants":e.participants.map(\.rawValue)]
                }]
            try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("food-tray-evidence.json"),options:.atomic)
            try JSONSerialization.data(withJSONObject:["coordinateSystem":"Quartz desktop points, top-down","samples":trace],options:[.prettyPrinted,.sortedKeys])
                .write(to:folder.appendingPathComponent("food-tray-trajectory.json"),options:.atomic)
        }
    }
}
