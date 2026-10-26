import AppKit
import BirdingCore

/// Main-session entry: try FoodTraySettingsVerification.run(into:&checks,folder:folder).
/// Call only after the whole B14 batch is ready. Never starts the desktop, its
/// timers, mouse monitors or population, and writes only below the supplied folder.
enum FoodTraySettingsVerification {
    private static let display=CGRect(x:0,y:0,width:1400,height:900)
    private static let target=CGPoint(x:900,y:550)

    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("food-tray-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        checks["foodTrayVerificationCompleted"]=false
        defer {
            let own=checks.filter{$0.key.hasPrefix("foodTray")}
            let report:[String:Any]=["passed":!own.isEmpty && own.values.allSatisfy{$0},"checks":own,
                "scope":"Isolated native settings, engine-clock placement, real artwork/renderer contact; no desktop startup or live input injection."]
            if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
                try? data.write(to:output.appendingPathComponent("report.json"),options:.atomic)
            }
        }
        let d=DesktopController();d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        d.settingsURL=output.appendingPathComponent("settings.json");d.legacyURL=output.appendingPathComponent("legacy.json")
        d.visitorMemoryPersistenceEnabled=false;d.visitorMemoryURL=output.appendingPathComponent("visitors.json")
        let defaults=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["foodTrayDefaultEnabledWithoutWriting"] = defaults.foodTrayEnabled && !FileManager.default.fileExists(atPath:d.settingsURL.path)
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(defaults)) as! [String:Any]
        legacy.removeValue(forKey:"foodTrayEnabled")
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:legacy))
        checks["foodTrayMissingLegacyKeyDefaultsTrue"]=migrated.foodTrayEnabled
        legacy["foodTrayEnabled"]="false"
        do {_ = try BirdSettings.decode(JSONSerialization.data(withJSONObject:legacy));checks["foodTrayMalformedSettingRejected"]=false}
        catch {checks["foodTrayMalformedSettingRejected"]=true}
        for enabled in [false,true] {
            var value=defaults;value.foodTrayEnabled=enabled
            let decoded=try BirdSettings.decode(JSONEncoder().encode(value))
            checks["foodTrayCodableRoundTrip-\(enabled)"]=decoded.foodTrayEnabled==enabled
        }

        // A real perch draft must survive all immediate tray commands unchanged.
        var saved=defaults
        saved.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"",displayFrame:display,x:0.2,y:0.25)]
        d.settings=saved
        let w=SpeciesSettingsWindow(desktop:d);d.settingsWindow=w;w.showWindow(nil)
        defer {w.cancel()}
        let draftAnchor=FixedPerchAnchor(slot:1,displayID:"",displayFrame:display,x:0.3,y:0.25)
        w.draft.fixedPerches=[draftAnchor]
        let anchors=w.draft.fixedPerches
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            let suffix=language == .chinese ? "zh":"en"
            checkControls(w,suffix:suffix,checks:&checks)
            w.foodTrayButton.performClick(nil)
            checks["foodTrayToggleOnlyEditsDraft-"+suffix] = !w.draft.foodTrayEnabled && d.settings.foodTrayEnabled &&
                w.draft.fixedPerches==anchors && !FileManager.default.fileExists(atPath:d.settingsURL.path)
            w.previewFoodTrayButton.performClick(nil)
            checks["foodTrayPreviewNeverSpawns-"+suffix] = d.birds.isEmpty && d.engine.pendingCount==0 &&
                d.engine.habitatSnapshot().isEmpty && w.draft.fixedPerches==anchors
            w.foodTrayButton.performClick(nil)
            cancellation(w,name:"button-"+suffix,checks:&checks) {w.cancelFoodTrayPlacementButton.performClick(nil)}
            cancellation(w,name:"remove-"+suffix,checks:&checks) {w.removeFoodTrayButton.performClick(nil)}
            cancellation(w,name:"build-"+suffix,checks:&checks) {w.build()}
            cancellation(w,name:"relocalize-"+suffix,checks:&checks) {w.relocalize()}
            cancellation(w,name:"draft-off-"+suffix,checks:&checks) {w.foodTrayButton.performClick(nil)}
            w.foodTrayButton.performClick(nil)
        }
        w.foodTrayButton.state = .off;w.save()
        let off=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["foodTraySaveReadsNativeCheckboxAndPersistsFalse"] = !off.foodTrayEnabled && !d.settings.foodTrayEnabled &&
            off.fixedPerches==anchors
        w.foodTrayButton.performClick(nil)
        let sequence=d.engine.events.last?.sequence
        w.placeFoodTrayButton.performClick(nil)
        checks["foodTrayPlaceReadsSavedSwitch"] = w.draft.foodTrayEnabled && !d.engine.hasFoodTrayPlacement &&
            d.engine.events.last?.sequence != sequence && d.engine.events.last?.reason == .disabled
        w.previewFoodTrayButton.performClick(nil)
        checks["foodTrayPreviewReadsSavedSwitch"] = d.engine.events.last?.reason == .disabled && d.birds.isEmpty &&
            w.message.stringValue==w.foodTrayMessage(.disabled)
        w.save()
        let on=try BirdSettings.load(from:d.settingsURL,legacyURL:d.legacyURL)
        checks["foodTraySaveAppliesAndReloadsTrue"] = on.foodTrayEnabled && d.settings.foodTrayEnabled && on.fixedPerches==anchors
        let bytes=try Data(contentsOf:d.settingsURL)
        w.placeFoodTrayButton.performClick(nil)
        checks["foodTrayNativePlaceSchedulesEngineClock"] = d.engine.hasFoodTrayPlacement &&
            !w.placeFoodTrayButton.isEnabled && w.cancelFoodTrayPlacementButton.isEnabled
        fixtureWorld(d.engine,point:CGPoint(x:700,y:400))
        advance(d.engine,1)
        d.engine.handle(.pause(true));advance(d.engine,5)
        checks["foodTrayPendingCountdownFreezesDuringPause"] = d.engine.hasFoodTrayPlacement && d.engine.habitatSnapshot().isEmpty
        d.engine.handle(.pause(false));fixtureWorld(d.engine,point:target)
        advance(d.engine,1.9)
        checks["foodTrayNoEarlyPlacement"] = d.engine.hasFoodTrayPlacement && d.engine.habitatSnapshot().isEmpty
        advance(d.engine,0.2);d.consumeBehaviorEvents();w.refreshFoodTrayControls()
        let placed=d.engine.habitatSnapshot().first
        checks["foodTrayDelayedPlacementSamplesLatestPointer"] = !d.engine.hasFoodTrayPlacement &&
            placed?.rect.midX==target.x && placed?.rect.minY==target.y && placed?.remainingUses==3 &&
            (placed?.remainingLifetime ?? 0)>179 && d.birds.isEmpty && w.draft.fixedPerches==anchors
        let lifetime=placed?.remainingLifetime
        d.engine.handle(.pause(true));advance(d.engine,4);w.refreshFoodTrayControls()
        checks["foodTrayLifetimeAndStatusFreezeDuringPause"] = lifetime != nil &&
            d.engine.habitatSnapshot().first?.remainingLifetime==lifetime && w.foodTrayStatus.stringValue.contains("3 / 3")
        d.engine.handle(.pause(false))
        let duplicate=d.engine.handle(.placeFoodTrayAfter(3))
        checks["foodTrayExistingObjectRejectsDuplicateWithoutRefill"] = duplicate == .rejected(.busy) &&
            d.engine.habitatSnapshot().first?.id==placed?.id &&
            d.engine.habitatSnapshot().first?.remainingLifetime==lifetime && !d.engine.hasFoodTrayPlacement
        for language:AppLanguage in [.chinese,.english] {
            d.language=language
            let busy=w.foodTrayMessage(.busy,placing:true)
            checks["foodTrayExistingObjectExplainsRemoveFirst-\(language)"] =
                busy.contains(language == .chinese ? "先移除":"Remove it before") &&
                w.foodTrayMessage(.busy) == d.behaviorMessage(.busy)
        }
        let serialized=try Data(contentsOf:d.settingsURL)
        let keys=try JSONSerialization.jsonObject(with:serialized) as! [String:Any]
        checks["foodTrayPlacementNeverWritesPositionOrDraft"] = bytes==serialized &&
            keys.keys.filter{$0.lowercased().contains("foodtray")}==["foodTrayEnabled"] &&
            w.draft.fixedPerches==anchors && d.settings.fixedPerches==anchors
        let snapshot=d.engine.habitatSnapshot().map(\.id)
        w.cancelFoodTrayPlacementClicked()
        checks["foodTrayCancelPendingKeepsPlacedObject"] = d.engine.habitatSnapshot().map(\.id)==snapshot
        w.removeFoodTrayButton.performClick(nil)
        checks["foodTrayRemoveOnlyRemovesTray"] = d.engine.habitatSnapshot().isEmpty &&
            d.engine.world.surfaces.contains{$0.isFixedPerch} && d.settings.fixedPerches==anchors &&
            w.draft.fixedPerches==anchors && d.birds.isEmpty && !d.engine.hasFoodTrayPlacement
        cancellation(w,name:"failed-save",checks:&checks) {
            d.settingsURL=output;w.foodTrayButton.state = .off;w.save()
        }
        d.settingsURL=output.appendingPathComponent("settings.json")
        let afterFailure=try Data(contentsOf:d.settingsURL)
        checks["foodTrayFailedSaveRetainsActiveAndFile"] = d.settings.foodTrayEnabled && !w.draft.foodTrayEnabled && bytes==afterFailure
        w.foodTrayButton.state = .on;w.foodTraySettingsChanged()
        cancellation(w,name:"save",checks:&checks) {w.save()}
        cancellation(w,name:"reset",checks:&checks) {w.resetDefaults()}
        checks["foodTrayResetOnlyChangesDraft"] = w.draft.foodTrayEnabled && d.settings.fixedPerches==anchors
        cancellation(w,name:"close",checks:&checks) {w.window?.performClose(nil)}
        w.showWindow(nil)
        cancellation(w,name:"cancel",checks:&checks) {w.cancel()}
        let reopened=SpeciesSettingsWindow(desktop:d);reopened.showWindow(nil)
        checks["foodTrayReopenRestoresSavedPreferenceAndPerches"] = reopened.draft.foodTrayEnabled && reopened.draft.fixedPerches==anchors
        cancellation(reopened,name:"window-replacement",checks:&checks) {
            d.settingsWindow=SpeciesSettingsWindow(desktop:d)
            reopened.cancel()
        }
        // Verify the weak engine reference also cancels when an unowned settings controller is released.
        weak var releasedController:SpeciesSettingsWindow?
        var releasedWindow:NSWindow?
        autoreleasepool {
            let controller=SpeciesSettingsWindow(desktop:d)
            releasedController=controller;releasedWindow=controller.window
            controller.showWindow(nil);controller.placeFoodTray()
            checks["foodTrayDeinitCancellationArmed"]=d.engine.hasFoodTrayPlacement
            // AppKit action dispatch retains temporary objects until the pool
            // drains. Hide without sending the window-close cancellation path.
            controller.window?.orderOut(nil)
        }
        checks["foodTrayDeinitCancelsPending"] = releasedController==nil && !d.engine.hasFoodTrayPlacement
        releasedWindow?.close()
        try checkArtAndRenderer(into:&checks,folder:output)
        checks["foodTrayVerificationRemainsIsolated"] = d.timer==nil && d.status==nil && d.panels.isEmpty && d.views.isEmpty &&
            d.globalMouseMonitor==nil && d.localMouseMonitor==nil && !d.visitorMemoryPersistenceEnabled &&
            d.visitorMemoryPersistence==nil && !FileManager.default.fileExists(atPath:d.visitorMemoryURL.path) && d.birds.isEmpty
        checks["foodTrayVerificationCompleted"]=true
    }

    private static func fixtureWorld(_ engine:BehaviorEngine,point:CGPoint,scale:CGFloat=1) {
        engine.updateWorld(BehaviorWorld(screens:[display],displays:[display],scale:scale,pointer:point,
            availableFrames:[:],fixedPerchArtAvailable:FixedPerchArt.shared != nil,
            foodTrayArtAvailable:HabitatObjectRenderer.foodTrayArtAvailable))
    }
    private static func advance(_ engine:BehaviorEngine,_ seconds:Double) {
        for _ in 0..<Int((seconds*60).rounded()) {engine.advance(1.0/60)}
    }
    private static func cancellation(_ w:SpeciesSettingsWindow,name:String,checks:inout [String:Bool],action:()->Void) {
        w.refreshFoodTrayControls();w.placeFoodTrayButton.performClick(nil)
        checks["foodTrayCancellationArmed-"+name]=w.desktop.engine.hasFoodTrayPlacement
        action()
        let engine=w.desktop.engine
        checks["foodTrayPendingCancelled-"+name] = !engine.hasFoodTrayPlacement
        fixtureWorld(engine,point:target);advance(engine,3.2)
        checks["foodTrayNoStalePlacement-"+name]=engine.habitatSnapshot().isEmpty && !engine.hasFoodTrayPlacement
    }
    private static func checkControls(_ w:SpeciesSettingsWindow,suffix:String,checks:inout [String:Bool]) {
        let controls=[w.foodTrayButton!,w.placeFoodTrayButton!,w.removeFoodTrayButton!,
                      w.cancelFoodTrayPlacementButton!,w.previewFoodTrayButton!]
        checks["foodTrayAccessibleNativeButtons-"+suffix]=controls.allSatisfy {
            $0.target === w && $0.action != nil && $0.identifier != nil && $0.accessibilityLabel()==$0.title && !$0.title.isEmpty
        }
        checks["foodTrayNativeControlsFit-"+suffix]=controls.allSatisfy {
            $0.superview?.bounds.contains($0.frame)==true && $0.intrinsicContentSize.width<=$0.frame.width
        }
        guard let view=w.foodTrayButton.superview,
              let help=view.subviews.first(where:{$0.identifier?.rawValue=="foodTrayHelp"}) as? NSTextField else {
            checks["foodTrayHelpPresent-"+suffix]=false;return
        }
        let text=help.stringValue
        let expected=suffix=="zh" ? ["3 份","180 秒","暂停","麻雀","珠颈斑鸠","鼠标靠近","安全恢复","不会删除栖木","不生成鸟","没有惩罚"]:
            ["3 portions","180 seconds","Pausing","Tree Sparrow","Spotted Dove","nearby pointer","safely restores","perches","without spawning","penalty"]
        checks["foodTrayCompleteBilingualHelp-"+suffix]=expected.allSatisfy{text.contains($0)}
        let fitted=help.cell?.cellSize(forBounds:CGRect(x:0,y:0,width:help.frame.width,height:10000)).height ?? .infinity
        checks["foodTrayHelpFitsWithoutClipping-"+suffix]=fitted<=help.frame.height && view.bounds.contains(help.frame)
    }

    private struct Raster {
        let width:Int,height:Int,bytes:[UInt8]
        init(_ image:CGImage) throws {
            width=image.width;height=image.height
            guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw FoodTraySettingsVerification.failure("Cannot decode RGBA pixels")}
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            guard let data=context.data else {throw FoodTraySettingsVerification.failure("Missing bitmap pixels")}
            bytes=Array(UnsafeBufferPointer(start:data.bindMemory(to:UInt8.self,capacity:width*height*4),count:width*height*4))
        }
        func alpha(_ x:Int,_ y:Int)->UInt8 {bytes[(y*width+x)*4+3]}
        func goldenSeedNear(_ p:CGPoint,radius:Int)->Bool {
            let x=Int(p.x.rounded()),y=Int(p.y.rounded())
            guard max(0,y-radius)<=min(height-1,y+radius),max(0,x-radius)<=min(width-1,x+radius) else {return false}
            for row in max(0,y-radius)...min(height-1,y+radius) {for col in max(0,x-radius)...min(width-1,x+radius) {
                let i=(row*width+col)*4,r=Int(bytes[i]),g=Int(bytes[i+1]),b=Int(bytes[i+2])
                if bytes[i+3]>=128 && r>140 && g>70 && b<150 && r*100>g*112 && g*100>b*112 {return true}
            }}
            return false
        }
        func nearestBillTip()->CGPoint? {
            var result:CGPoint?,distance=CGFloat.infinity
            for y in 0..<height {for x in 0..<width where alpha(x,y)>0 {
                let p=CGPoint(x:(CGFloat(x)+0.5)*48/CGFloat(width),y:(CGFloat(y)+0.5)*48/CGFloat(height))
                let d=hypot(p.x-40,p.y-39)
                if d<distance {distance=d;result=p}
            }}
            return result
        }
    }
    private static func checkArtAndRenderer(into checks:inout [String:Bool],folder:URL) throws {
        guard let art=FoodTrayArt.shared,let url=ScenePropAssets.foodTrayURL,
              let raw=NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
            checks["foodTrayRealArtworkAvailable"]=false;return
        }
        checks["foodTrayRealArtworkAvailable"]=HabitatObjectRenderer.foodTrayArtAvailable
        let source=try Raster(raw),crop=try Raster(art.image)
        var left=source.width,right = -1,top=source.height,bottom = -1
        for y in 0..<source.height {for x in 0..<source.width where source.alpha(x,y)>=32 {
            left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)
        }}
        checks["foodTrayActualCGAlphaCrop"] = art.sourceAlphaBounds==CGRect(x:left,y:top,width:right-left+1,height:bottom-top+1) &&
            crop.width==right-left+1 && crop.height==bottom-top+1
        let sourceContact=CGFloat(top)+art.contactY
        let center=(left+right)/2
        let firstOpaqueRow:Int?=(top...bottom).first(where:{source.alpha(center,$0)>=128})
        let rearRim:Int=firstOpaqueRow ?? bottom
        checks["foodTraySeedContactBelowRearRim"] = (375...395).contains(sourceContact) && sourceContact>CGFloat(rearRim+60)
        var evidence=[[String:Any]]()
        for scale:CGFloat in [1,1.5,3] {
            let engine=BehaviorEngine(seed:1414);engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
            let foot=CGPoint(x:700,y:550)
            fixtureWorld(engine,point:foot,scale:scale);engine.handle(.placeFoodTrayAfter(0));advance(engine,1.0/60)
            guard let state=engine.habitatSnapshot().first else {throw failure("Cannot place renderer fixture")}
            let root=CALayer();root.frame=display;root.isGeometryFlipped=true
            let renderer=HabitatObjectRenderer()
            CATransaction.begin();CATransaction.setDisableActions(true)
            renderer.update([state],on:root,desktopRect:display)
            CATransaction.commit()
            guard let container=root.sublayers?.first,let texture=container.sublayers?.first else {throw failure("Missing real food tray layer")}
            let ratio=container.frame.width/CGFloat(crop.width)
            checks["foodTrayRealLayerFootContact-\(scale)"] = abs(container.frame.midX-foot.x)<0.001 &&
                abs(container.frame.minY+art.contactY*ratio-foot.y)<0.001 &&
                abs(container.frame.width-128*scale)<0.001 &&
                abs(container.frame.height/CGFloat(crop.height)-ratio)<0.001 && texture.contents != nil
            for species:SpeciesID in [.treeSparrow,.spottedDove] {
                let birdArt=BirdArt(species:species),birdScale=scale*SpeciesCatalog.standard.profile(species).relativeScale
                for name in ["feedDown0","feedDown1"] {for rightFacing in [true,false] {
                    guard let billImage=DetailedBirdArt.feedingImage(name,species:species,part:.bill),
                          let tip=try Raster(billImage).nearestBillTip() else {throw failure("Missing actual bill alpha")}
                    let bill=CGPoint(x:foot.x+(rightFacing ? tip.x-29:29-tip.x)*birdScale,y:foot.y+(tip.y-39)*birdScale)
                    let local=CGPoint(x:(bill.x-container.frame.minX)/ratio,y:(bill.y-container.frame.minY)/ratio)
                    let nearSeed=crop.goldenSeedNear(local,radius:max(2,Int(ceil(2*birdScale/ratio))))
                    let key="\(species.rawValue)-\(name)-\(rightFacing ? "right":"left")-\(scale)"
                    checks["foodTrayActualBillMeetsSeed-"+key]=nearSeed && hypot(tip.x-40,tip.y-39)<=1.5*48/CGFloat(billImage.width)
                    evidence.append(["case":key,"billWorld":[bill.x,bill.y],"seedCropPixel":[local.x,local.y],
                        "goldenSeedPixelsNearBill":nearSeed,"sourceContactY":sourceContact,"imageRect":NSStringFromRect(container.frame)])
                    if scale==3 {try contactImage(root:root,art:birdArt,name:name,foot:foot,scale:birdScale,right:rightFacing,
                        bill:bill,to:folder.appendingPathComponent("contact-"+key+".png"))}
                }}
            }
            // Higher-level window blockers must reach the real layer mask.
            var world=engine.world
            world.surfaces=[Surface(id:900,pid:42,rect:container.frame,layer:1)]
            engine.updateWorld(world)
            let masked=engine.habitatSnapshot()
            renderer.update(masked,on:root,desktopRect:display)
            checks["foodTrayRendererMasksHigherWindows-\(scale)"] = masked.first?.blockers.contains(container.frame)==true && container.isHidden
            renderer.update([],on:root,desktopRect:display)
            checks["foodTrayRendererRemovesStaleLayers-\(scale)"]=root.sublayers?.isEmpty != false
        }
        try JSONSerialization.data(withJSONObject:["sourceSize":[source.width,source.height],
            "alphaBounds":NSStringFromRect(art.sourceAlphaBounds),"contactYInSource":sourceContact,"rearRimY":rearRim,
            "kind":"Real native RGBA bill and food tray CGImage/CALayer contact; tolerance is two bird logical pixels around the tip.",
            "contacts":evidence],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("image-contact-evidence.json"),options:.atomic)
    }
    private static func contactImage(root:CALayer,art:BirdArt,name:String,foot:CGPoint,scale:CGFloat,right:Bool,
                                     bill:CGPoint,to url:URL) throws {
        guard let context=CGContext(data:nil,width:Int(display.width),height:Int(display.height),bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot draw contact image")}
        context.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor);context.fill(display)
        context.translateBy(x:0,y:display.height);context.scaleBy(x:1,y:-1);context.interpolationQuality = .none
        root.render(in:context)
        art.draw(name:name,at:foot,scale:scale,right:right,context:context)
        context.setStrokeColor(NSColor.systemGreen.cgColor);context.setLineWidth(1)
        context.move(to:CGPoint(x:foot.x-200,y:foot.y));context.addLine(to:CGPoint(x:foot.x+200,y:foot.y));context.strokePath()
        context.setStrokeColor(NSColor.systemOrange.cgColor);context.strokeEllipse(in:CGRect(x:bill.x-4,y:bill.y-4,width:8,height:8))
        guard let image=context.makeImage(),let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {throw failure("Cannot encode contact image")}
        try data.write(to:url,options:.atomic)
    }
    private static func failure(_ message:String)->NSError {
        NSError(domain:"FoodTraySettingsVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }
}
