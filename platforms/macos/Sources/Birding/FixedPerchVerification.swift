import AppKit
import BirdingCore

/// M5l / B18 native acceptance. Explicit fixed steps, real windows, production
/// DesktopView/BirdArt, and evidence-only writes; never calls DesktopController.start().
enum FixedPerchVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        guard Thread.isMainThread else {throw failure("Native fixed perch acceptance must run on the main thread.")}
        let evidence=folder.appendingPathComponent("fixed-perch-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        checks["fixedPerchNativeCompleted"]=false
        let h=try Harness(folder:evidence)
        defer {h.close()}
        do {
            checks["fixedPerchNativeDefaultEnabledWithNoAnchors"]=h.d.settings.fixedPerchesEnabled && h.d.settings.fixedPerches.isEmpty
            try h.verifyArt(into:&checks)
            for species in [SpeciesID.barnSwallow,.swinhoesWhiteEye] {try h.complete(species,into:&checks)}
            for resting in [false,true] {
                try h.click(resting:resting,into:&checks)
                for cause in ["remove","move","disable","window-change","screen-change","parents"] {
                    try h.interrupt(cause,resting:resting,into:&checks)
                }
            }
            // Once the three-second visit has released its lease, the ordinary
            // resident still needs the same invalid-host recovery guarantees.
            for cause in ["remove","move","disable"] {try h.interrupt(cause,resting:true,released:true,into:&checks)}
            try h.multipleSlots(into:&checks)
            for gate in ["no-birds","blocked","disabled","no-slots","paused","art-unavailable","quiet-automatic"] {
                try h.reject(gate,into:&checks)
            }
            try h.occlusion(into:&checks)
            checks["fixedPerchNativeNoTimersMonitorsPreferencesOrVisitorWrites"]=h.isolated
            h.d.engine.handle(.cancelAmbient(.shutdown));h.events()
            checks["fixedPerchNativeFinalLeasesAndRunsReleased"]=h.resourcesClear
            h.close()
            checks["fixedPerchNativeFixtureWindowsHidden"] = !h.overlay.isVisible && !h.hostWindow.isVisible && !h.blockerWindow.isVisible
            checks["fixedPerchNativeCompleted"]=true
            try h.writeReport(checks)
        } catch {
            h.close()
            try? h.writeReport(checks,error:error.localizedDescription)
            throw error
        }
        print("Fixed perch native evidence: \(evidence.path)")
    }

    private static func failure(_ message:String)->NSError {
        NSError(domain:"FixedPerchVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }

    private final class Harness {
        let d:DesktopController,folder:URL,display:CGRect,work:CGRect
        let hostWindow:NSWindow,blockerWindow:NSPanel,overlay:OverlayPanel
        let hostView:NSView,blockerView:NSView,view:DesktopView
        let dt=1.0/60
        var host=Surface(id:0,rect:.zero)
        var birds:[Bird]=[],ids:[BirdID]=[],previous:[CGPoint]=[],origins:[CGPoint]=[]
        var run:BehaviorRunID?,caseName="",corridor=CGRect.zero
        var eventLog:[UInt64:BehaviorEvent]=[:]
        var trajectory:[[String:Any]]=[],cases:[[String:Any]]=[],artifacts:[[String:Any]]=[]
        var populationOK=true,layersOK=true,anchorsOK=true,pointerOK=true,exclusiveOK=true,continuous=true
        var maximumStep:CGFloat=0
        var artEvidence:[String:Any]=[:]
        var cachedArtPixels:Pixels?

        init(folder:URL) throws {
            let d=DesktopController()
            guard let screen=NSScreen.screens.first,let display=d.displayRects.first,let work=d.screenRects.first,
                  work.width>=680,work.height>=480 else {
                throw FixedPerchVerification.failure("Native acceptance requires a display with at least 680 × 480 work points.")
            }
            d.settingsURL=folder.appendingPathComponent("unused-settings.json")
            d.legacyURL=folder.appendingPathComponent("unused-legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("unused-visitors.json")
            d.visitorMemoryPersistenceEnabled=false;d.automaticPopulation=false
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            let hostWindow=NSWindow(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
            let blockerWindow=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            let hostView=NSView(frame:.zero),blockerView=NSView(frame:.zero)
            for (window,content) in [(hostWindow,hostView),(blockerWindow,blockerView)] {
                window.isReleasedWhenClosed=false;window.hasShadow=false;window.ignoresMouseEvents=true
                window.animationBehavior = .none;window.backgroundColor=NSColor(calibratedWhite:0.88,alpha:1)
                content.wantsLayer=true;content.layer?.backgroundColor=window.backgroundColor.cgColor
                window.contentView=content
            }
            let overlay=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            overlay.isReleasedWhenClosed=false;overlay.hasShadow=false;overlay.ignoresMouseEvents=true
            overlay.isOpaque=false;overlay.backgroundColor = .clear;overlay.level = .floating;overlay.animationBehavior = .none
            let view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size))
            view.controller=d;view.desktopRect=display;overlay.contentView=view
            self.d=d;self.folder=folder;self.display=display;self.work=work
            self.hostWindow=hostWindow;self.hostView=hostView;self.blockerWindow=blockerWindow
            self.blockerView=blockerView;self.overlay=overlay;self.view=view
        }
        func close() {
            d.engine.handle(.cancelAmbient(.shutdown));events()
            overlay.orderOut(nil);hostWindow.orderOut(nil);blockerWindow.orderOut(nil)
        }
        var isolated:Bool {
            d.timer==nil && d.globalMouseMonitor==nil && d.localMouseMonitor==nil && d.status==nil &&
                d.visitorMemoryPersistence==nil && !d.visitorMemoryPersistenceEnabled &&
                d.engine.activeVisitorCount==0 && d.engine.rememberedVisitorCount==0 &&
                [d.settingsURL,d.legacyURL,d.visitorMemoryURL].allSatisfy {
                    $0.deletingLastPathComponent()==folder && !FileManager.default.fileExists(atPath:$0.path)
                }
        }
        var resourcesClear:Bool {
            d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0 &&
                d.engine.scenePropCount==0 && !d.engine.ambientBusy
        }
        var visitResources:Bool {
            d.engine.activeRunCount==1 && d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==1 &&
                d.engine.scenePropCount==0 && !d.engine.ambientBusy
        }
        var samePopulation:Bool {
            d.birds.count==birds.count && ids.count==birds.count && birds.enumerated().allSatisfy {i,b in
                d.birds[i] === b && d.engine.id(of:b)==ids[i]
            } && d.residentCount==birds.count && d.engine.passingCount==0 && d.engine.departingCount==0 &&
                d.engine.pendingCount==0 && d.arrivalCount==0 && d.departureCount==0
        }
        func events() {for event in d.engine.events {eventLog[event.sequence]=event}}
        func terminals(_ id:BehaviorRunID?)->[BehaviorEvent] {
            events();guard let id else {return []}
            return eventLog.values.filter{$0.runID==id && [.completed,.cancelled,.failed].contains($0.type)}.sorted{$0.sequence<$1.sequence}
        }
        var activeBird:Bird? {
            guard let run,let id=eventLog.values.first(where:{$0.runID==run && $0.type == .started})?.participants.first else {return nil}
            return d.engine.bird(id)
        }
        var activePerch:ResolvedFixedPerch? {
            guard let bird=activeBird else {return nil}
            return d.engine.fixedPerchSnapshot().first{$0.surface.id==bird.hostID}
        }
        func advance() {d.syncWorld();d.engine.advance(dt);events()}
        func anchor(slot:Int,point:CGPoint) throws -> FixedPerchAnchor {
            guard let anchor=FixedPerchAnchor.capture(slot:slot,point:point,displayIDs:d.fixedPerchDisplayIDs,displays:d.displayRects) else {
                throw FixedPerchVerification.failure("Fixture point cannot be captured on an actual display.")
            }
            return anchor
        }
        func windowSurface(_ window:NSWindow)->Surface {
            Surface(id:UInt32(window.windowNumber),pid:ProcessInfo.processInfo.processIdentifier,
                rect:Geometry.quartz(window.frame,primaryHeight:d.primaryHeight),layer:window.level.rawValue)
        }
        func place(_ window:NSWindow,view:NSView,rect:CGRect) {
            // AppKit rounds NSWindow dimensions. Request integral dimensions and
            // derive all host/occluder geometry from the actual returned frame.
            let submitted=CGRect(x:rect.minX.rounded(),y:rect.minY.rounded(),width:rect.width.rounded(.up),height:rect.height.rounded(.up))
            window.setFrame(Geometry.quartz(submitted,primaryHeight:d.primaryHeight),display:true)
            view.frame=CGRect(origin:.zero,size:window.frame.size);view.layer?.frame=view.bounds
        }
        func fixture(_ species:SpeciesID = .barnSwallow,name:String,multiple:Bool=false) throws {
            d.paused=false;d.engine.handle(.cancelAmbient(.screensChanged));events();d.birds=[]
            blockerWindow.orderOut(nil);d.scale=0.75;d.engine.autonomousRouting=false
            var settings=d.settings
            settings.fixedPerchesEnabled=true;settings.fixedPerches=[];settings.visitorMemoryEnabled=false
            settings.socialInteractions=true;settings.perchActions=true;settings.activityRhythm = .steady
            settings.sideHopEnabled=false;settings.takeoffPreparationEnabled=false;settings.edgePeekEnabled=false
            settings.hoverDelay=0;d.settings=settings
            d.hoverTracker=HoverTracker<BirdID>();d.hoveredBird=nil;d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
            let starts:[CGFloat]=multiple ? [0.15,0.38,0.62,0.85]:[0.25]
            let targets:[CGFloat]=multiple ? [0.2,0.5,0.8]:[0.75]
            struct Layout {let baseline:CGFloat;let mirror:Bool;let area:CGRect}
            var layouts:[Layout]=[]
            let rise=0.12*work.height
            // Include the upper/lower limits of the existing conservative
            // corridor, rather than assuming 50% or 78% clears a live pointer.
            // Round before measuring so selection uses the actual host baseline.
            let baselines=[(work.minY+rise+120).rounded(.up),
                (work.minY+0.50*work.height).rounded(),(work.minY+0.78*work.height).rounded(),
                (work.maxY-100).rounded(.down)]
            for baseline in baselines {for mirror in [false,true] {
                let xs=(starts+targets).map{work.minX+(mirror ? 1-$0:$0)*work.width}
                let top=baseline-rise
                let area=CGRect(x:(xs.min() ?? 0)-40,y:top-120,width:(xs.max() ?? 0)-(xs.min() ?? 0)+80,height:rise+160)
                if work.contains(area),display.contains(area),baseline+100<=work.maxY {
                    layouts.append(Layout(baseline:baseline,mirror:mirror,area:area))
                }
            }}
            let pointer=d.pointerPosition
            func clearance(_ r:CGRect)->CGFloat {hypot(max(0,max(r.minX-pointer.x,pointer.x-r.maxX)),max(0,max(r.minY-pointer.y,pointer.y-r.maxY)))}
            guard let layout=layouts.filter({pointerIsClear(pointer,of:$0.area)}).max(by:{clearance($0.area)<clearance($1.area)}) else {
                cases.append(["case":name,"pointer":Self.point(pointer),"workArea":NSStringFromRect(work),
                    "candidateCorridors":layouts.map{NSStringFromRect($0.area)}])
                throw FixedPerchVerification.failure("\(name): no fixture corridor clears the live pointer by 100 points; move the pointer toward a screen edge.")
            }
            corridor=layout.area
            place(hostWindow,view:hostView,rect:CGRect(x:work.minX+24,y:layout.baseline,width:work.width-48,height:100))
            hostWindow.level = .normal;hostWindow.orderFrontRegardless();overlay.orderFrontRegardless();host=windowSurface(hostWindow)
            let lo=Geometry.perchX(0,rect:host.rect),hi=Geometry.perchX(1,rect:host.rect)
            birds=starts.map {x in
                let x=work.minX+(layout.mirror ? 1-x:x)*work.width
                let bird=Bird(position:.zero,fraction:(x-lo)/(hi-lo),profile:d.catalog.profile(species),random:{0.5})
                bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;bird.tick(0.6)
                return bird
            }
            settings.fixedPerches=try targets.enumerated().map {i,x in
                try anchor(slot:i+1,point:CGPoint(x:work.minX+(layout.mirror ? 1-x:x)*work.width,y:host.rect.minY-0.12*work.height))
            }
            d.surfaces=[host];d.birds=birds;d.settings=settings;d.syncWorld()
            ids=birds.compactMap{d.engine.id(of:$0)};previous=birds.map(\.position);origins=previous
            caseName=name;run=nil;maximumStep=0
            populationOK=true;layersOK=true;anchorsOK=true;pointerOK=true;exclusiveOK=true;continuous=true
            view.updateSprites()
        }
        func pointerIsClear(_ point:CGPoint,of area:CGRect)->Bool {
            point.x.isFinite && point.y.isFinite && !area.insetBy(dx:-100,dy:-100).contains(point)
        }
        var fixtureOK:Bool {
            hostWindow.isVisible && overlay.isVisible && host.rect==Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight) &&
                host.rect.width>=180 && host.rect.height>=100 && samePopulation && !d.engine.world.buttonsDown &&
                pointerIsClear(d.pointerPosition,of:corridor) &&
                d.engine.fixedPerchSnapshot().count==d.settings.fixedPerches.count &&
                birds.allSatisfy{$0.state == .perched && $0.stateTime>=0.5 && $0.hostID==host.id && !$0.needsDestination} &&
                d.engine.fixedPerchSnapshot().allSatisfy{$0.surface.isFixedPerch && $0.surface.id==UInt32(0xFF000000)+UInt32($0.slot)}
        }
        @discardableResult func start()->Bool {
            d.syncWorld()
            let result=d.engine.handle(.fixedPerchVisit(.preview));events()
            if case .started(let id)=result {run=id;return true}
            run=nil;return false
        }
        func ready(resting:Bool,released:Bool=false) throws -> Bool {
            for _ in 0..<20*60 {
                advance();try record("waiting")
                guard let bird=activeBird else {return false}
                if released {if !terminals(run).isEmpty {return terminals(run).count==1 && terminals(run).first?.type == .completed && bird.state == .perched}}
                else if resting {
                    if bird.state == .perched && d.engine.behavior(of:bird) == .fixedPerchVisit {return true}
                } else if bird.state == .flying,let index=birds.firstIndex(where:{$0 === bird}),
                          Geometry.distance(origins[index],bird.position)>3 {return true}
                if !terminals(run).isEmpty {return false}
            }
            return false
        }
        var spriteLayers:[CALayer] {view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []}
        var perchLayers:[CALayer] {view.layer?.sublayers?.filter{$0.name?.hasPrefix("fixed-perch-")==true} ?? []}
        func perchLayer(_ slot:Int)->CALayer? {perchLayers.first{$0.name=="fixed-perch-\(slot)"}}
        static func geometry(_ layer:CALayer,rect:CGRect)->Bool {
            // Compare stored bounds/center exactly; frame reconstruction can
            // shift a fractional origin by one ULP without a renderer defect.
            layer.bounds==CGRect(origin:.zero,size:rect.size) && layer.position==CGPoint(x:rect.midX,y:rect.midY) &&
                layer.anchorPoint==CGPoint(x:0.5,y:0.5) && layer.affineTransform()==CGAffineTransform.identity
        }
        static func origin(_ layer:CALayer)->CGPoint {
            CGPoint(x:layer.position.x-layer.bounds.width*layer.anchorPoint.x,y:layer.position.y-layer.bounds.height*layer.anchorPoint.y)
        }
        func record(_ label:String,crop:Bool=false) throws {
            view.updateSprites();events()
            let states=d.engine.renderSnapshot(),layers=spriteLayers,perches=d.engine.fixedPerchSnapshot()
            populationOK = populationOK && samePopulation
            pointerOK = pointerOK && pointerIsClear(d.engine.world.pointer,of:corridor) && !d.engine.world.buttonsDown
            layersOK = layersOK && layers.count==states.count && states.count==birds.count && perchLayers.count==perches.count
            exclusiveOK = exclusiveOK && perches.allSatisfy {p in birds.filter{$0.hostID==p.surface.id}.count<=1}
            var members:[[String:Any]]=[]
            for (i,bird) in birds.enumerated() {
                guard i<ids.count,let index=states.firstIndex(where:{$0.id==ids[i]}),index<layers.count,
                      let texture=layers[index].sublayers?.first,let image=d.arts[bird.profile.id]?.frames[states[index].frameName]
                else {layersOK=false;anchorsOK=false;continue}
                let state=states[index],layer=layers[index],origin=Self.origin(layer)
                let foot=CGPoint(x:origin.x+display.minX+(state.facingRight ? 29:19)*state.scale,
                    y:origin.y+display.minY+(39-state.hopOffset)*state.scale)
                let error=Geometry.distance(foot,bird.position)
                let pieces=Geometry.visiblePieces(state.rect,blockers:state.blockers)
                let visible=state.rect.intersects(display) && !pieces.isEmpty
                let geometry=Self.geometry(layer,rect:state.rect.offsetBy(dx:-display.minX,dy:-display.minY))
                layersOK = layersOK && layer.isHidden == !visible && (!visible || (geometry &&
                    (texture.contents as AnyObject?) === image && texture.affineTransform()==CGAffineTransform(scaleX:state.facingRight ? 1:-1,y:1)))
                anchorsOK = anchorsOK && (!visible || error<0.001) && state.position==bird.position
                let step=Geometry.distance(previous[i],bird.position);maximumStep=max(maximumStep,step)
                // Visit routes use FlightTiming, whose peak cannot exceed this
                // species' ordinary cruise speed. A tiny numeric epsilon only.
                if d.engine.behavior(of:bird) == .fixedPerchVisit {
                    continuous = continuous && step<=CGFloat(FlightBehavior.cruiseSpeed(bird.profile.id,multiplier:bird.profile.speed)*dt)+0.001
                }
                previous[i]=bird.position
                members.append(["id":state.id.rawValue,"species":state.species.rawValue,"state":bird.state.rawValue,
                    "frame":state.frameName,"foot":Self.point(bird.position),"layerFoot":Self.point(foot),"footError":error,
                    "host":bird.hostID.map{Int($0)} ?? -1,"fraction":bird.fraction,"scale":state.scale,
                    "stateTime":bird.stateTime,"revision":bird.motionRevision,"needsDestination":bird.needsDestination,
                    "behavior":d.engine.behavior(of:bird)?.rawValue ?? "none","layerHidden":layer.isHidden,"layerGeometry":geometry,
                    "layerBounds":NSStringFromRect(layer.bounds),"layerPosition":Self.point(layer.position)])
            }
            var props:[[String:Any]]=[]
            for perch in perches {
                let valid=perchGeometry(perch)
                layersOK = layersOK && valid
                props.append(["slot":perch.slot,"surface":perch.surface.id,"foot":Self.point(perch.foot),
                    "rect":NSStringFromRect(perch.rect),"artRect":FixedPerchArt.shared.map{NSStringFromRect($0.rect(for:perch))} ?? "missing",
                    "layerGeometry":valid,"occupants":birds.filter{$0.hostID==perch.surface.id}.compactMap{d.engine.id(of:$0)?.rawValue}])
            }
            trajectory.append(["case":caseName,"label":label,"time":d.engine.time,"run":run?.rawValue ?? 0,
                "paused":d.paused,"runs":d.engine.activeRunCount,"leases":d.engine.leasedBirdCount,"reservations":d.engine.reservedLandingCount,
                "pointer":Self.point(d.engine.world.pointer),"buttonsDown":d.engine.world.buttonsDown,"birds":members,"perches":props])
            if crop {try snapshot(label,states:states,perches:perches)}
        }
        func perchGeometry(_ perch:ResolvedFixedPerch)->Bool {
            guard let art=FixedPerchArt.shared,let layer=perchLayer(perch.slot),let texture=layer.sublayers?.first,
                  let mask=texture.mask as? CAShapeLayer else {return false}
            let rect=art.rect(for:perch),pieces=Geometry.visiblePieces(rect,blockers:Geometry.blockers(on:perch.surface,surfaces:d.engine.world.surfaces).map(\.rect))
            let visible=rect.intersects(display) && !pieces.isEmpty
            if !visible {return layer.isHidden && layer.mask==nil}
            return !layer.isHidden && layer.mask==nil && layer.zPosition<0 &&
                Self.geometry(layer,rect:rect.offsetBy(dx:-display.minX,dy:-display.minY)) &&
                Self.geometry(texture,rect:CGRect(origin:.zero,size:rect.size)) &&
                (texture.contents as AnyObject?) === art.image && mask.path != nil
        }
        func summarize(_ extra:[String:Any]=[:]) {
            var value:[String:Any]=["case":caseName,"run":run?.rawValue ?? 0,"birds":ids.map(\.rawValue),
                "host":host.id,"actualHostFrame":NSStringFromRect(host.rect),"corridor":NSStringFromRect(corridor),
                "pointer":Self.point(d.engine.world.pointer),"pointerExclusion":NSStringFromRect(corridor.insetBy(dx:-100,dy:-100)),
                "maximumStep":maximumStep,"invariants":["population":populationOK,"layers":layersOK,"anchors":anchorsOK,
                    "pointer":pointerOK,"exclusiveSlots":exclusiveOK,"visitContinuity":continuous],
                "terminals":terminals(run).map{["type":$0.type.rawValue,"reason":$0.reason?.rawValue ?? "","time":$0.time]}]
            value.merge(extra){_,new in new};cases.append(value)
        }

        // Both images are decoded through the same explicit CGContext format.
        // Compare row-for-row, and separately report the reflected comparison;
        // reflected agreement is diagnostic, never an alternative passing path.
        struct Pixels {
            let width:Int,height:Int,rgba:[UInt8]
            init(_ image:CGImage) throws {
                guard let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,
                    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw FixedPerchVerification.failure("Cannot decode actual artwork.")
                }
                context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
                guard let bytes=context.data else {throw FixedPerchVerification.failure("Missing artwork pixels.")}
                width=image.width;height=image.height;rgba=Array(UnsafeBufferPointer(start:bytes.assumingMemoryBound(to:UInt8.self),count:image.width*image.height*4))
            }
            func alpha(_ x:Int,_ y:Int)->UInt8 {(0..<width).contains(x) && (0..<height).contains(y) ? rgba[(y*width+x)*4+3]:0}
        }
        func verifyArt(into checks:inout [String:Bool]) throws {
            guard let art=FixedPerchArt.shared,let url=ScenePropAssets.fixedPerchURL,
                  let raw=NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
                checks["fixedPerchNativeRealArtAvailable"]=false
                throw FixedPerchVerification.failure("Actual fixed perch asset or generated cached image unavailable.")
            }
            checks["fixedPerchNativeRealArtAvailable"]=true
            let source=try Pixels(raw),cropped=try Pixels(art.image)
            cachedArtPixels=cropped
            var left=source.width,right = -1,top=source.height,bottom = -1
            for y in 0..<source.height {for x in 0..<source.width where source.alpha(x,y)>=32 {
                left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)
            }}
            let valid=right>=left && bottom>=top
            var rowMismatches=0,reflectedMismatches=0
            if valid {
                for y in 0..<cropped.height {for x in 0..<cropped.width {
                    if cropped.alpha(x,y) != source.alpha(left+x,top+y) {rowMismatches+=1}
                    if cropped.alpha(x,y) != source.alpha(left+x,bottom-y) {reflectedMismatches+=1}
                }}
            }
            let center=cropped.width/2,rail=Int(art.railY)
            let rawCenter=(left+right)/2
            let rawRail=valid ? (top...bottom).first{source.alpha(rawCenter,$0)>=128}:nil
            let croppedRail=(0..<cropped.height).first{cropped.alpha(center,$0)>=128}
            checks["fixedPerchNativeRawAndCroppedContainTransparentAndSolidAlpha"]=source.rgba.enumerated().contains{$0.offset%4==3 && $0.element==0} &&
                cropped.rgba.enumerated().contains{$0.offset%4==3 && $0.element==0} && cropped.rgba.enumerated().contains{$0.offset%4==3 && $0.element>=128}
            checks["fixedPerchNativeCroppedAlphaPreservesRawCGContextRowOrientation"]=valid && cropped.width==right-left+1 &&
                cropped.height==bottom-top+1 && rowMismatches==0
            checks["fixedPerchNativeCenterFootRailIsActualAlphaUpperEdge"]=art.railY==CGFloat(rail) && rawRail.map{$0-top}==rail &&
                croppedRail==rail && cropped.alpha(center,rail)>=128 && (0..<max(0,rail)).allSatisfy{cropped.alpha(center,$0)<128}
            checks["fixedPerchNativeArtIsCached"]=FixedPerchArt.shared === art
            artEvidence=["rawSize":[source.width,source.height],"croppedSize":[cropped.width,cropped.height],
                "alphaBounds":[left,top,right,bottom],"rawRailRow":rawRail ?? -1,"croppedCenterRailRow":croppedRail ?? -1,
                "railY":art.railY,"centerRailAlpha":cropped.alpha(center,rail),"rawToCroppedRowMismatches":rowMismatches,
                "reflectedRowMismatchesDiagnosticOnly":reflectedMismatches]
            let image=NSBitmapImageRep(cgImage:art.image)
            guard let png=image.representation(using:.png,properties:[:]) else {throw FixedPerchVerification.failure("Cannot encode actual cached art.")}
            try png.write(to:folder.appendingPathComponent("fixed-perch-cached-art.png"),options:.atomic)
            artifacts.append(["file":"fixed-perch-cached-art.png","kind":"actual cached production CGImage"])
        }

        func complete(_ species:SpeciesID,into checks:inout [String:Bool]) throws {
            try fixture(species,name:species.rawValue+"-complete")
            let prefix="fixedPerchNative-"+species.rawValue,valid=fixtureOK
            try record("initial",crop:true)
            let origin=birds[0].position,accepted=start()
            checks[prefix+"UsesExistingResidentAndOneLease"]=valid && accepted && visitResources && samePopulation &&
                birds[0].position==origin && eventLog.values.first{$0.runID==run && $0.type == .started}?.participants==ids
            let feet=birds.map(\.position),ages=birds.map(\.stateTime),revisions=birds.map(\.motionRevision)
            for _ in 0..<3 {view.updateSprites();_ = d.renderSnapshot()}
            checks[prefix+"RenderingDoesNotIntegrateMotion"]=accepted && birds.map(\.position)==feet && birds.map(\.stateTime)==ages && birds.map(\.motionRevision)==revisions
            var flew=false,landingFrames=Set<String>(),firstRest:Double?,paused=false,pausedSeconds=0.0
            var footFixed=true,woodContact=true,leaseHeld=true,restTicks=0,captured=Set<String>(),inputOK=false
            for _ in 0..<20*60 {
                if !accepted {break}
                advance();try record("tick")
                guard let bird=activeBird else {break}
                if bird.state == .flying,Geometry.distance(origin,bird.position)>3 {flew=true}
                if bird.state == .landing {landingFrames.insert(bird.frameName)}
                if bird.state == .perched,let perch=activePerch {
                    if firstRest==nil {firstRest=d.engine.time}
                    footFixed = footFixed && Geometry.distance(bird.position,perch.foot)<0.001 && bird.fraction==0.5
                    woodContact = woodContact && centerFootTouchesWood(perch,bird:bird)
                    if d.engine.behavior(of:bird) == .fixedPerchVisit {
                        restTicks+=1;leaseHeld = leaseHeld && visitResources
                        footFixed = footFixed && d.engine.renderSnapshot().first?.frameName=="stand" && d.engine.renderSnapshot().first?.hopOffset==0
                        if !paused {
                            checks[prefix+"PauseFreezesBirdPoseLayersAndLease"]=try pauseEvidence()
                            paused=true;pausedSeconds=60*dt;inputOK=probeInput()
                        }
                    }
                }
                let phase=bird.state.rawValue
                if captured.insert(phase).inserted {try record(phase,crop:true)}
                if !terminals(run).isEmpty {break}
            }
            try record("completed",crop:true)
            let ends=terminals(run),heldSeconds=firstRest.map{(ends.first?.time ?? 0)-$0-pausedSeconds} ?? -1
            checks[prefix+"FliesLandsAndHoldsActualCenterFootForThreeSeconds"]=accepted && flew && landingFrames==Set(["land0","land1","land2"]) &&
                restTicks>=180 && heldSeconds+1e-9>=3 && heldSeconds<=3+2*dt && footFixed && leaseHeld
            checks[prefix+"ActualRenderedFootTouchesOpaqueWoodAtAlphaUpperEdge"]=accepted && firstRest != nil && woodContact
            checks[prefix+"CompletesOnceAndStaysPerchedWithoutLease"]=accepted && ends.count==1 && ends.first?.type == .completed &&
                resourcesClear && activeBird?.state == .perched && activeBird.map{d.engine.behavior(of:$0)==nil && !$0.needsDestination} == true
            checks[prefix+"ActualBirdArtLayersAnchorsAndContinuousVisit"]=accepted && layersOK && anchorsOK && continuous && populationOK && pointerOK
            checks[prefix+"OpaqueHitHoverAndTransparentSpritePassThrough"]=accepted && inputOK
            let finalFeet=birds.map(\.position),beforeRestAge=birds.map(\.stateTime)
            for _ in 0..<60 {advance();try record("ordinary-idle")}
            checks[prefix+"ReturnsToOrdinaryStationaryResident"]=accepted && birds.map(\.position)==finalFeet && resourcesClear &&
                birds.enumerated().allSatisfy {i,b in b.state == .perched && !b.needsDestination && d.engine.behavior(of:b)==nil && b.stateTime>beforeRestAge[i]} && samePopulation
            let perches=d.engine.fixedPerchSnapshot(),roots=perchLayers
            d.engine.handle(.clearProps);view.updateSprites()
            checks[prefix+"ClearPropsKeepsPersistentPerches"]=accepted && samePerches(perches,d.engine.fixedPerchSnapshot()) &&
                roots.count==perchLayers.count && zip(roots,perchLayers).allSatisfy{$0 === $1} && resourcesClear && birds.map(\.position)==finalFeet
            try record("ordinary-idle",crop:true)
            summarize(["accepted":accepted,"flightObserved":flew,"landingFrames":landingFrames.sorted(),"holdSecondsExcludingPause":heldSeconds,
                "activeRestSamples":restTicks,"pauseSeconds":pausedSeconds])
        }
        func pauseEvidence() throws -> Bool {
            d.paused=true;view.updateSprites()
            let before=d.engine.renderSnapshot(),feet=birds.map(\.position),ages=birds.map(\.stateTime),revisions=birds.map(\.motionRevision)
            let sequence=d.engine.events.last?.sequence,layers=spriteLayers,props=perchLayers
            let geometry=layers.map{($0.bounds,$0.position,$0.sublayers?.first?.contents as AnyObject?,$0.sublayers?.first?.affineTransform())}
            let propGeometry=props.map{($0.bounds,$0.position,$0.sublayers?.first?.contents as AnyObject?)}
            for _ in 0..<60 {advance()}
            view.updateSprites();let after=d.engine.renderSnapshot()
            let frozen=visitResources && terminals(run).isEmpty && before.count==after.count && birds.map(\.position)==feet &&
                birds.map(\.stateTime)==ages && birds.map(\.motionRevision)==revisions && d.engine.events.last?.sequence==sequence &&
                zip(before,after).allSatisfy{$0.id==$1.id && $0.frameName==$1.frameName && $0.rect==$1.rect && $0.hopOffset==$1.hopOffset && $0.facingRight==$1.facingRight} &&
                spriteLayers.count==geometry.count && spriteLayers.enumerated().allSatisfy {i,l in
                    l === layers[i] && l.bounds==geometry[i].0 && l.position==geometry[i].1 &&
                        (l.sublayers?.first?.contents as AnyObject?) === geometry[i].2 && l.sublayers?.first?.affineTransform()==geometry[i].3
                } && perchLayers.count==propGeometry.count && perchLayers.enumerated().allSatisfy {i,l in
                    l === props[i] && l.bounds==propGeometry[i].0 && l.position==propGeometry[i].1 &&
                        (l.sublayers?.first?.contents as AnyObject?) === propGeometry[i].2
                }
            try record("paused",crop:true);d.paused=false
            return frozen
        }
        func centerFootTouchesWood(_ perch:ResolvedFixedPerch,bird:Bird)->Bool {
            guard let art=FixedPerchArt.shared,let root=perchLayer(perch.slot),let texture=root.sublayers?.first,
                  let mask=texture.mask as? CAShapeLayer,let pixels=cachedArtPixels,!root.isHidden else {return false}
            let origin=Self.origin(root),ratio=root.bounds.width/CGFloat(art.image.width)
            let projected=CGPoint(x:(bird.position.x-display.minX-origin.x)/ratio,y:(bird.position.y-display.minY-origin.y)/ratio)
            let x=pixels.width/2,y=Int(art.railY)
            // Projection can differ from an integer pixel row by one ULP. First
            // prove the exact rail within sub-pixel numeric error, then sample
            // that rail, rather than accidentally flooring to the preceding row.
            return ratio>0 && abs(projected.x-CGFloat(pixels.width)/2)<0.000001 && abs(projected.y-art.railY)<0.000001 &&
                pixels.alpha(x,y)>=128 && (0..<max(0,y)).allSatisfy{pixels.alpha(x,$0)<128} &&
                mask.path?.contains(CGPoint(x:projected.x*ratio,y:projected.y*ratio+0.01))==true &&
                Geometry.distance(bird.position,perch.foot)<0.001
        }
        func opaque(_ state:BirdRenderState,at point:CGPoint)->Bool {
            guard state.rect.contains(point),!state.blockers.contains(where:{$0.contains(point)}),let art=d.arts[state.species] else {return false}
            let x=Int((point.x-state.rect.minX)/state.scale),y=Int((point.y-state.rect.minY)/state.scale)
            return art.contains(frame:state.frameName,x:state.facingRight ? x:47-x,y:y)
        }
        func pixelPoint(_ state:BirdRenderState,solid:Bool)->CGPoint? {
            guard let art=d.arts[state.species] else {return nil}
            let states=d.engine.renderSnapshot()
            for pixel in 0..<48*48 where art.contains(frame:state.frameName,x:pixel%48,y:pixel/48)==solid {
                let x=state.facingRight ? pixel%48:47-pixel%48
                let p=CGPoint(x:state.rect.minX+(CGFloat(x)+0.5)*state.scale,y:state.rect.minY+(CGFloat(pixel/48)+0.5)*state.scale)
                guard !state.blockers.contains(where:{$0.contains(p)}) else {continue}
                let top=states.reversed().first{opaque($0,at:p)}
                if solid ? top?.id==state.id:top==nil {return p}
            }
            return nil
        }
        func probeInput()->Bool {
            guard let bird=activeBird,let id=d.engine.id(of:bird),let state=d.engine.renderSnapshot().first(where:{$0.id==id}),
                  let solid=pixelPoint(state,solid:true),let clear=pixelPoint(state,solid:false) else {return false}
            let sequence=d.engine.events.last?.sequence
            let hit=d.bird(at:solid) === bird
            d.updateHover(now:d.engine.time,at:solid);view.updateSprites()
            let hover=d.hoveredBird === bird && (view.layer?.sublayers?.contains{($0 as? CATextLayer)?.isHidden == false} ?? false)
            d.hoverTracker=HoverTracker<BirdID>();d.hoveredBird=nil
            return hit && hover && d.bird(at:clear)==nil && !d.relocateBird(at:clear) && d.engine.events.last?.sequence==sequence &&
                overlay.ignoresMouseEvents && !overlay.canBecomeKey && !overlay.canBecomeMain && !view.isOpaque
        }
        func recovery() throws -> Bool {
            d.engine.autonomousRouting=true
            for _ in 0..<46*60 {
                advance();try record("recovery")
                if resourcesClear && birds.allSatisfy({$0.state == .perched && !$0.needsDestination && d.engine.behavior(of:$0)==nil}) {
                    return samePopulation && populationOK && layersOK && anchorsOK
                }
            }
            return false
        }
        func click(resting:Bool,into checks:inout [String:Bool]) throws {
            try fixture(resting ? .swinhoesWhiteEye:.barnSwallow,name:"click-"+(resting ? "rest":"flight"))
            let valid=fixtureOK,accepted=start(),prepared=accepted ? try ready(resting:resting):false
            let pauseOK=prepared ? try pauseEvidence():false
            checks["fixedPerchNative-"+caseName+"PauseFreezesMotionFramesLayersAndLease"]=prepared && pauseOK
            try record("before-click",crop:true)
            let feet=birds.map(\.position),oldRun=run,sequence=d.engine.events.last?.sequence ?? 0
            let state=d.engine.renderSnapshot().first
            let clicked=state.flatMap{pixelPoint($0,solid:true)}.map{d.relocateBird(at:$0)} ?? false
            events();let replacement=d.engine.events.last{$0.sequence>sequence && $0.kind == .relocate && $0.type == .started}
            let ends=terminals(oldRun),prefix="fixedPerchNative-"+caseName
            checks[prefix+"CancelsVisitBeforeRelocationAtActualFeet"]=valid && accepted && prepared && clicked && birds.map(\.position)==feet &&
                ends.count==1 && ends.first?.type == .cancelled && ends.first?.reason == .replaced && (ends.first?.sequence ?? UInt64.max)<(replacement?.sequence ?? 0) &&
                birds.allSatisfy{d.engine.behavior(of:$0) == .relocate} && d.engine.reservedLandingCount==0 && samePopulation
            try record("click-handoff",crop:true)
            let recovered=try recovery(),replacementEnds=terminals(replacement?.runID)
            checks[prefix+"RelocationFinishesAndReleasesResources"]=clicked && recovered && replacementEnds.count==1 &&
                replacementEnds.first?.type == .completed && terminals(oldRun).count==1 &&
                zip(feet,birds).contains{Geometry.distance($0,$1.position)>1}
            try record("recovered",crop:true);summarize(["accepted":accepted,"prepared":prepared,"relocateRun":replacement?.runID?.rawValue ?? 0])
        }
        func interrupt(_ cause:String,resting:Bool,released:Bool=false,into checks:inout [String:Bool]) throws {
            try fixture(.barnSwallow,name:cause+"-"+(released ? "ordinary":(resting ? "rest":"flight")))
            let valid=fixtureOK,accepted=start(),prepared=accepted ? try ready(resting:resting,released:released):false
            try record("before-change",crop:true)
            let feet=birds.map(\.position),oldRun=run,oldPerches=d.engine.fixedPerchSnapshot(),oldRevisions=birds.map(\.motionRevision)
            var value=d.settings,changedWorld:[String:Any]=[:]
            switch cause {
            case "remove":value.fixedPerches=[];d.settings=value
            case "move":
                if let perch=oldPerches.first {
                    value.fixedPerches=[try anchor(slot:perch.slot,point:CGPoint(x:perch.foot.x,y:perch.foot.y+80))];d.settings=value
                }
            case "disable":value.fixedPerchesEnabled=false;d.settings=value
            case "window-change":
                if let perch=oldPerches.first {showBlocker(rect:Geometry.landingFootprint(at:perch.foot,scale:1).insetBy(dx:-12,dy:-12),high:true)}
            case "screen-change":
                var world=d.engine.world
                world.screens=world.screens.map{$0.insetBy(dx:1,dy:1)}
                world.displays=world.displays.map{$0.offsetBy(dx:1,dy:0)}
                changedWorld=["screens":world.screens.map(NSStringFromRect),"displays":world.displays.map(NSStringFromRect)]
                d.engine.updateWorld(world)
            default:
                value.perchActions=false;value.socialInteractions=false;value.activityRhythm = .quiet;d.settings=value
            }
            events();let ends=terminals(oldRun),prefix="fixedPerchNative-"+caseName
            let unchangedFeet=birds.map(\.position)==feet
            if cause=="parents" {
                checks[prefix+"IndependentParentSettingsKeepSameVisitAndAnchor"]=valid && accepted && prepared && unchangedFeet &&
                    birds.map(\.motionRevision)==oldRevisions && visitResources && ends.isEmpty && samePerches(oldPerches,d.engine.fixedPerchSnapshot())
                let finished=try ready(resting:true,released:true)
                checks[prefix+"CompletesUnderDisabledParentsAndQuiet"]=finished && resourcesClear && terminals(oldRun).count==1 &&
                    terminals(oldRun).first?.type == .completed && samePopulation
            } else {
                let expectedType:BehaviorEventType=released ? .completed:(cause=="disable" ? .cancelled:.failed)
                let expectedReason:BehaviorReason?=released ? nil:(cause=="disable" ? .settingsChanged:.targetInvalid)
                let terminal=ends.count==1 && ends.first?.type==expectedType && ends.first?.reason==expectedReason
                let invalidated=birds.allSatisfy{$0.needsDestination && $0.state == .flying && $0.hostID==nil}
                checks[prefix+"ReleasesAtActualFeetWithoutTeleport"]=valid && accepted && prepared && unchangedFeet && terminal &&
                    resourcesClear && invalidated && birds.allSatisfy{d.engine.behavior(of:$0)==nil} && samePopulation
                if cause=="remove" || cause=="disable" {
                    view.updateSprites()
                    checks[prefix+"RemovesOnlyPerchRenderRoots"]=d.engine.fixedPerchSnapshot().isEmpty && perchLayers.isEmpty && spriteLayers.count==birds.count
                }
                try record("changed",crop:true)
                blockerWindow.orderOut(nil);d.surfaces=[host];d.syncWorld()
                let recovered=try recovery()
                checks[prefix+"RecoversAsOrdinaryResident"]=prepared && recovered && terminals(oldRun).count==1 && continuous && exclusiveOK
            }
            try record("recovered",crop:true)
            summarize(["accepted":accepted,"prepared":prepared,"feetBefore":feet.map(Self.point),"instantFeetUnchanged":unchangedFeet,
                "screenStimulus":changedWorld,"screenStimulusKind":"Public updateWorld with changed display/work rectangles; no physical monitor reconfiguration."])
        }
        func samePerches(_ a:[ResolvedFixedPerch],_ b:[ResolvedFixedPerch])->Bool {
            a.count==b.count && zip(a,b).allSatisfy{$0.slot==$1.slot && $0.surface==$1.surface && $0.foot==$1.foot && $0.rect==$1.rect}
        }
        func showBlocker(rect:CGRect,high:Bool) {
            blockerWindow.level=high ? .floating:.normal
            place(blockerWindow,view:blockerView,rect:rect)
            blockerWindow.orderFrontRegardless();d.surfaces=[windowSurface(blockerWindow),host];d.syncWorld()
        }
        func reject(_ gate:String,into checks:inout [String:Bool]) throws {
            try fixture(name:"reject-"+gate)
            let valid=fixtureOK
            var value=d.settings
            switch gate {
            case "no-birds":d.birds=[];birds=[];ids=[];previous=[];origins=[]
            case "blocked":if let perch=d.engine.fixedPerchSnapshot().first {showBlocker(rect:Geometry.landingFootprint(at:perch.foot,scale:1).insetBy(dx:-12,dy:-12),high:true)}
            case "disabled":value.fixedPerchesEnabled=false;d.settings=value
            case "no-slots":value.fixedPerches=[];d.settings=value
            case "paused":d.paused=true
            case "quiet-automatic":value.activityRhythm = .quiet;d.settings=value
            default:break
            }
            d.syncWorld()
            if gate=="art-unavailable" {var world=d.engine.world;world.fixedPerchArtAvailable=false;d.engine.updateWorld(world)}
            let feet=birds.map(\.position),ages=birds.map(\.stateTime),revisions=birds.map(\.motionRevision),states=birds.map(\.state)
            let fractions=birds.map(\.fraction),sequence=d.engine.events.last?.sequence ?? 0
            let result=d.engine.handle(.fixedPerchVisit(gate=="quiet-automatic" ? .automatic:.preview));events()
            let reason:BehaviorReason
            switch gate {
            case "no-birds":reason = .noSpecies
            case "disabled","quiet-automatic":reason = .disabled
            case "paused":reason = .paused
            default:reason = .noSpace
            }
            let rejected=d.engine.events.last{$0.sequence>sequence && $0.kind == .fixedPerchVisit && $0.type == .rejected}
            checks["fixedPerchNativeRejects-"+gate]=valid && result == .rejected(reason) && rejected?.reason==reason && resourcesClear &&
                !d.engine.events.contains{$0.sequence>sequence && $0.kind == .fixedPerchVisit && $0.type == .started} &&
                samePopulation && birds.map(\.position)==feet && birds.map(\.stateTime)==ages && birds.map(\.motionRevision)==revisions &&
                birds.map(\.state)==states && birds.map(\.fraction)==fractions
            if gate=="art-unavailable" {
                checks["fixedPerchNativeMissingArtRemovesInvisibleLandingSurfaces"]=d.engine.fixedPerchSnapshot().isEmpty && !d.engine.world.surfaces.contains(where:{$0.isFixedPerch})
                // Capture the capability before DesktopView's real platform
                // sync correctly restores the actual, available artwork.
                cases.append(["case":caseName,"artAvailableDuringCommand":d.engine.world.fixedPerchArtAvailable,
                    "resolvedDuringCommand":d.engine.fixedPerchSnapshot().count,"result":String(describing:result)])
            }
            d.paused=false;try record("rejected",crop:true)
            if gate=="quiet-automatic" {
                let accepted=start(),finished=accepted ? try ready(resting:true,released:true):false
                checks["fixedPerchNativeQuietAllowsManualExistingBirdVisit"]=accepted && finished && resourcesClear && samePopulation
                try record("manual-preview-finished",crop:true)
            }
            summarize(["result":String(describing:result),"expectedReason":reason.rawValue,"fixture":valid])
        }
        func multipleSlots(into checks:inout [String:Bool]) throws {
            try fixture(.treeSparrow,name:"three-slots-four-residents",multiple:true)
            let valid=fixtureOK,perches=d.engine.fixedPerchSnapshot()
            var runs:[BehaviorRunID]=[],used=Set<UInt32>(),allStarted=true,clearPreserved=true
            for _ in 0..<3 {
                let accepted=start()
                allStarted = allStarted && accepted
                if let run {runs.append(run)}
                if let id=activeBird?.hostID {allStarted = allStarted && used.insert(id).inserted}
                else {allStarted=false}
                let roots=perchLayers,sequence=d.engine.events.last?.sequence
                d.engine.handle(.clearProps);events();view.updateSprites()
                clearPreserved = clearPreserved && samePerches(perches,d.engine.fixedPerchSnapshot()) && roots.count==perchLayers.count &&
                    zip(roots,perchLayers).allSatisfy{$0 === $1} && d.engine.events.last?.sequence==sequence
                // Complete each observed visit. No fixture bird is teleported to
                // a slot; subsequent previews must choose an unoccupied slot.
                let finished=accepted ? try ready(resting:true,released:true):false
                allStarted = allStarted && finished
                try record("occupied-\(used.count)",crop:true)
            }
            let feet=birds.map(\.position),sequence=d.engine.events.last?.sequence ?? 0
            let result=d.engine.handle(.fixedPerchVisit(.preview));events()
            checks["fixedPerchNativeThreeSlotsHaveDistinctRealVisitorsAndOneOccupantEach"]=valid && allStarted && runs.count==3 &&
                Set(runs).count==3 && used.count==3 && exclusiveOK && perches.allSatisfy{p in birds.filter{$0.hostID==p.surface.id && $0.state == .perched}.count==1} &&
                runs.allSatisfy{terminals($0).count==1 && terminals($0).first?.type == .completed} && samePopulation && populationOK
            checks["fixedPerchNativeFullSlotsRejectWithoutDoubleBookingOrSpawning"]=allStarted && result == .rejected(.noSpace) && resourcesClear &&
                samePopulation && birds.map(\.position)==feet && !d.engine.events.contains{$0.sequence>sequence && $0.kind == .fixedPerchVisit && $0.type == .started}
            checks["fixedPerchNativeClearPropsKeepsActiveVisitAndAllPerchRoots"]=allStarted && clearPreserved && layersOK && anchorsOK
            try record("full-slots-rejected",crop:true)
            summarize(["fixture":valid,"visitRuns":runs.map(\.rawValue),"usedSurfaces":used.sorted(),"fourthRequest":String(describing:result)])
        }
        func occlusion(into checks:inout [String:Bool]) throws {
            try fixture(name:"normal-window-versus-high-panel")
            let valid=fixtureOK
            guard let perch=d.engine.fixedPerchSnapshot().first,let art=FixedPerchArt.shared else {
                checks["fixedPerchNativeRealWindowOcclusionFixture"]=false;return
            }
            let rect=art.rect(for:perch),cover=rect.union(Geometry.landingFootprint(at:perch.foot,scale:1)).insetBy(dx:-8,dy:-8)
            showBlocker(rect:cover,high:false);view.updateSprites()
            let normalSurface=windowSurface(blockerWindow),normalMask=perchLayer(perch.slot)?.sublayers?.first?.mask as? CAShapeLayer
            let localFoot=CGPoint(x:perch.foot.x-rect.minX,y:perch.foot.y-rect.minY+0.01)
            let normalVisible=perchLayer(perch.slot)?.isHidden==false && normalMask?.path?.contains(localFoot)==true
            let accepted=start(),finished=accepted ? try ready(resting:true,released:true):false
            checks["fixedPerchNativeNormalWindowDoesNotMaskOrBlockFloatingPerch"]=valid && normalSurface.layer==0 && normalVisible &&
                Geometry.blockers(on:perch.surface,surfaces:d.engine.world.surfaces).isEmpty && accepted && finished && layersOK && anchorsOK
            try record("normal-window-visit",crop:true)
            // Use an actually visible nonactivating high-layer panel, but feed
            // its real frame/layer explicitly: production sampling excludes own
            // windows, so this does not claim to test foreign-process sampling.
            try fixture(name:"high-panel-masks-and-blocks")
            guard let target=d.engine.fixedPerchSnapshot().first else {return}
            let targetRect=art.rect(for:target)
            let partial=CGRect(x:target.foot.x-4,y:targetRect.minY-50,width:targetRect.maxX-target.foot.x+20,height:targetRect.height+100)
            showBlocker(rect:partial,high:true);view.updateSprites()
            let blocker=windowSurface(blockerWindow),layer=perchLayer(target.slot),mask=layer?.sublayers?.first?.mask as? CAShapeLayer
            let blocked=CGPoint(x:target.foot.x,y:target.foot.y+0.01),visible=CGPoint(x:targetRect.minX+1,y:target.foot.y+0.01)
            let blockedLocal=CGPoint(x:blocked.x-targetRect.minX,y:blocked.y-targetRect.minY)
            let visibleLocal=CGPoint(x:visible.x-targetRect.minX,y:visible.y-targetRect.minY)
            let info=CGWindowListCopyWindowInfo([.optionIncludingWindow,.excludeDesktopElements],CGWindowID(blockerWindow.windowNumber)) as? [[String:Any]]
            let windowInfo=info?.first{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value==blocker.id}
            let observedLayer=(windowInfo?[kCGWindowLayer as String] as? NSNumber)?.intValue
            let before=birds.map(\.position),result=d.engine.handle(.fixedPerchVisit(.preview));events()
            checks["fixedPerchNativeHighPanelMasksCoveredPixelsAndKeepsExposedPixels"]=fixtureOK && blockerWindow.isVisible &&
                blocker.layer>0 && blocker.rect.contains(blocked) && !blocker.rect.contains(visible) &&
                layer?.isHidden==false && mask?.path?.contains(blockedLocal)==false && mask?.path?.contains(visibleLocal)==true &&
                !Geometry.isLandingVisible(on:target.surface.id,at:target.foot,surfaces:d.engine.world.surfaces,scale:d.spriteScale(for:birds[0]))
            checks["fixedPerchNativeHighPanelRejectsDockingWithoutAddingBirds"]=result == .rejected(.noSpace) && resourcesClear &&
                birds.map(\.position)==before && samePopulation
            checks["fixedPerchNativeOverlayRenderingDoesNotTakeMouseOrActivation"]=overlay.ignoresMouseEvents &&
                !overlay.canBecomeKey && !overlay.canBecomeMain && !view.isOpaque && layer?.mask==nil && spriteLayers.count==birds.count
            try record("high-panel",crop:true)
            summarize(["normalVisitAccepted":accepted,"normalVisitFinished":finished,"highPanelResult":String(describing:result),
                "actualPanelLayer":blocker.layer,"windowServerLayerObservationAvailable":observedLayer != nil,"windowServerLayer":observedLayer ?? -1,"actualPanelRect":NSStringFromRect(blocker.rect)])
        }
        func snapshot(_ label:String,states:[BirdRenderState],perches:[ResolvedFixedPerch]) throws {
            var crop=host.rect
            for state in states {crop=crop.union(state.rect)}
            if let art=FixedPerchArt.shared {for perch in perches {crop=crop.union(art.rect(for:perch))}}
            crop=crop.insetBy(dx:-12,dy:-12).intersection(display).integral
            guard !crop.isEmpty,let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(crop.width),pixelsHigh:Int(crop.height),
                bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
                  let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else {throw FixedPerchVerification.failure("Cannot allocate native evidence image.")}
            view.layoutSubtreeIfNeeded();hostView.layoutSubtreeIfNeeded();blockerView.layoutSubtreeIfNeeded()
            let ctx=graphics.cgContext
            ctx.setFillColor(NSColor(calibratedWhite:0.22,alpha:1).cgColor);ctx.fill(CGRect(origin:.zero,size:crop.size))
            ctx.translateBy(x:-crop.minX,y:crop.maxY);ctx.scaleBy(x:1,y:-1)
            func drawWindow(_ content:NSView,_ rect:CGRect) {
                ctx.saveGState();ctx.translateBy(x:rect.minX,y:rect.maxY);ctx.scaleBy(x:1,y:-1);content.layer?.render(in:ctx);ctx.restoreGState()
            }
            if hostWindow.isVisible {drawWindow(hostView,host.rect)}
            if blockerWindow.isVisible,blockerWindow.level == .normal {drawWindow(blockerView,windowSurface(blockerWindow).rect)}
            ctx.saveGState();ctx.translateBy(x:display.minX,y:display.minY);view.layer?.render(in:ctx);ctx.restoreGState()
            if blockerWindow.isVisible,blockerWindow.level.rawValue>0 {drawWindow(blockerView,windowSurface(blockerWindow).rect)}
            guard let png=bitmap.representation(using:.png,properties:[:]) else {throw FixedPerchVerification.failure("Cannot encode native evidence image.")}
            let name=caseName+"-"+label+"-layer-composite.png"
            try png.write(to:folder.appendingPathComponent(name),options:.atomic)
            artifacts.append(["file":name,"case":caseName,"label":label,"time":d.engine.time,"crop":NSStringFromRect(crop),
                "kind":"Actual NSWindow/DesktopView CALayer crop composite; not a WindowServer desktop capture."])
        }
        static func point(_ p:CGPoint)->[CGFloat] {[p.x,p.y]}
        func writeReport(_ checks:[String:Bool],error:String?=nil) throws {
            events();let own=checks.filter{$0.key.hasPrefix("fixedPerchNative")}
            let report:[String:Any]=["milestone":"M5l","behavior":"B18","seed":String(d.engine.seed),"checks":own,
                "passed":error==nil && own.values.allSatisfy{$0},"error":error ?? "","cases":cases,"art":artEvidence,"artifacts":artifacts,
                "trajectory":"fixed-perch-trajectory.json","display":NSStringFromRect(display),"workArea":NSStringFromRect(work),
                "execution":"Main thread, explicit 1/60 fixed steps, no start/timers/input monitors/user preferences or visitor files.",
                "input":"Live pointer/buttons; direct production alpha-hit, hover and relocate probes. No input injection.",
                "screens":"Screen-change stimulus uses public updateWorld; physical display hotplug is not claimed.",
                "occlusion":"Visible own NSWindow/NSPanel frames and levels are fed explicitly into production world/masks; foreign-process window enumeration is not claimed.",
                "screenshots":"Actual layer crop composites with real BirdArt and fixed-perch CGImage; not desktop captures.",
                "geometry":"NSWindow uses actual returned frame; CALayer uses exact stored bounds/center, foot error < 0.001 points.",
                "events":eventLog.values.sorted{$0.sequence<$1.sequence}.map {e -> [String:Any] in
                    ["sequence":e.sequence,"time":e.time,"run":e.runID?.rawValue ?? 0,"kind":e.kind?.rawValue ?? "none",
                        "type":e.type.rawValue,"source":e.source.rawValue,"reason":e.reason?.rawValue ?? "","participants":e.participants.map(\.rawValue)]
                }]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("fixed-perch-evidence.json"),options:.atomic)
            try JSONSerialization.data(withJSONObject:["coordinateSystem":"Quartz desktop points; y increases downward","dt":dt,"samples":trajectory],options:[.prettyPrinted,.sortedKeys])
                .write(to:folder.appendingPathComponent("fixed-perch-trajectory.json"),options:.atomic)
        }
    }
}
