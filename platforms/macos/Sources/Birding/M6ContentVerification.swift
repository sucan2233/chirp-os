import AppKit
import BirdingCore

/// M6a/b historical coverage, M6c, and M6f.1 catch/insect source art.
/// The caller owns CLI registration/execution.
/// Uses installed fixture birds, isolated defaults and production commands/layers;
/// never starts DesktopController, loads preferences, schedules timers or saves settings.
enum M6ContentVerification {
    private static let m6bSpecies:[SpeciesID]=[.treeSparrow,.spottedDove,.barnSwallow,.nightHeron]
    private static let m6cSpecies:[SpeciesID]=[.lightVentedBulbul,.redWhiskeredBulbul,.chineseBlackbird,
        .magpieRobin,.swinhoesWhiteEye,.azureWingedMagpie,.redBilledLeiothrix,.littleOwl]
    private static let species:[SpeciesID]=m6bSpecies+m6cSpecies
    private static let peekSpecies:[SpeciesID]=[.lightVentedBulbul,.magpieRobin]
    private static let peekNames=["peekLower","peekLook","peekRecover"]
    private static let names=["lookNear","lookFar","alertRise","alertHold","alertRelax",
                              "restLower","restTuck","restWake","takeoffCrouch","takeoffPush"]
    private static let kinds:[BehaviorKind]=[.watch,.alert,.rest,.takeoffPreparation]
    private static let scales:[CGFloat]=[0.5,1,2]

    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("m6-content-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        checks["m6ContentCompleted"]=false
        var evidence=[[String:Any]](),allPosePixels=Set<Data>(),historicalPixels=Set<Data>(),peekPixels=Set<Data>()
        defer {
            let own=checks.filter{$0.key.hasPrefix("m6")}
            saveJSON(["scope":"M6a/M6b historical checks retained; M6c twelve-species poses and two-species edge peeking; M6f.1 authored catch/insect art",
                      "historicalScope":["poseSpecies":m6bSpecies.map(\.rawValue),"independentPoseFrames":40,"commonFrames":34],
                      "currentScope":["poseSpecies":species.map(\.rawValue),"independentPoseFrames":120,
                                      "peekSpecies":peekSpecies.map(\.rawValue),"peekFrames":6,
                                      "catchSpecies":[SpeciesID.barnSwallow.rawValue],"catchFrames":3,"insectFrames":4],
                      "wingBoundaryScope":["enforcedPoseSpecies":m6cSpecies.map(\.rawValue),"poseFrames":80,
                                           "enforcedPeekSpecies":peekSpecies.map(\.rawValue),"peekFrames":6,
                                           "diagnosticOnlySpecies":m6bSpecies.map(\.rawValue),"diagnosticOnlyFrames":40],
                      "passed":!own.isEmpty && own.values.allSatisfy{$0},"checks":own,"frames":evidence,
                      "limits":"Synthetic window geometry and native CALayer rendering. Historical M6b boundary counts are diagnostic only; historical frames are not certified clear of boundary contact. Physical display changes, sleep/wake and long-running desktop use require separate acceptance."],
                     to:output.appendingPathComponent("report.json"))
        }
        checkPermissions(into:&checks)
        try checkCatchArt(into:&checks,evidence:&evidence,folder:output)
        let fixture=try Fixture(folder:output)
        defer {fixture.close()}
        try checkSettings(fixture,into:&checks,folder:output)
        for id in species {
            let art=fixture.desktop.arts[id]!
            try checkArt(art,into:&checks,evidence:&evidence,allPosePixels:&allPosePixels,folder:output)
            if m6bSpecies.contains(id) {
                for name in names {historicalPixels.insert(try Raster(art.frames[name]!).pixels)}
            }
            for scale in scales {for right in [true,false] {
                try preview(art,scale:scale,right:right,folder:output)
                for kind in kinds {
                    try checkNative(fixture,species:id,kind:kind,scale:scale,right:right,
                                    into:&checks,evidence:&evidence,folder:output)
                }
            }}
            // Every authored phase is clicked once, at normal size. Lifecycle
            // cases below use one representative per behavior, not a Cartesian product.
            for name in names {
                checkClick(fixture,species:id,frame:name,into:&checks)
            }
        }
        checks["m6FortyIndependentNativePoseImages"]=historicalPixels.count==40
        checks["m6cOneHundredTwentyIndependentNativePoseImages"]=allPosePixels.count==120
        for id in peekSpecies {
            let art=fixture.desktop.arts[id]!
            try checkArt(art,frameNames:peekNames,into:&checks,evidence:&evidence,allPosePixels:&peekPixels,folder:output)
            for scale in scales {for right in [true,false] {
                try preview(art,frameNames:peekNames,scale:scale,right:right,folder:output)
            }}
        }
        checks["m6cSixIndependentPeekImagesDistinctFromPoses"]=peekPixels.count==6 && peekPixels.isDisjoint(with:allPosePixels)
        for kind in kinds {checkLifecycle(fixture,kind:kind,into:&checks)}
        fixture.desktop.engine.handle(.cancelAmbient(.shutdown))
        checks["m6FixtureNoTimersMonitorsOrPersistence"]=fixture.desktop.timer==nil &&
            fixture.desktop.globalMouseMonitor==nil && fixture.desktop.localMouseMonitor==nil &&
            !fixture.desktop.visitorMemoryPersistenceEnabled && !fixture.desktop.observationJournalPersistenceEnabled &&
            fixture.desktop.visitorMemoryPersistence==nil && fixture.desktop.observationPersistence==nil &&
            !FileManager.default.fileExists(atPath:fixture.desktop.settingsURL.path) &&
            !FileManager.default.fileExists(atPath:fixture.desktop.visitorMemoryURL.path) &&
            !FileManager.default.fileExists(atPath:fixture.desktop.observationJournalURL.path)
        checks["m6ContentCompleted"]=true
    }

    private static func checkPermissions(into checks:inout [String:Bool]) {
        let legacy:[(BehaviorKind,[SpeciesID])]=[
            (.edgePeek,[.treeSparrow,.chineseBlackbird,.hoopoe,.whimbrel]),
            (.chase,[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling]),
            (.travelTogether,[.treeSparrow,.barnSwallow,.spottedDove,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling]),
            (.allopreening,[.barnSwallow,.swinhoesWhiteEye]),
            (.fixedPerchVisit,[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.redWhiskeredBulbul,.magpieRobin,.redBilledLeiothrix]),
            (.foodTrayVisit,[.treeSparrow,.spottedDove])]
        let additions:[BehaviorKind:[SpeciesID]]=[.edgePeek:peekSpecies,.fixedPerchVisit:[.lightVentedBulbul],
            .chase:[.redWhiskeredBulbul],.travelTogether:[.redWhiskeredBulbul]]
        for (kind,expected) in legacy {
            let actual=SpeciesBehaviorProfile.species(for:kind),current=expected+(additions[kind] ?? [])
            // Historical membership/order remains a prefix; only the explicit
            // M6c additions may follow it. No M6b acceptance is discarded.
            checks["m6LegacyPermissionOrder-"+kind.rawValue]=Array(actual.prefix(expected.count))==expected &&
                expected.allSatisfy{SpeciesBehaviorProfile.profile(for:$0).allows(kind)}
            checks["m6cExactPermissionExpansion-"+kind.rawValue]=actual==current &&
                SpeciesID.allCases.allSatisfy {SpeciesBehaviorProfile.profile(for:$0).allows(kind)==current.contains($0)}
        }
        checks["m6LegacyAmbientFlockOrder"]=SpeciesBehaviorProfile.ambientFlockSpecies ==
            [.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.lightVentedBulbul,.azureWingedMagpie,.mallard,.blackHeadedGull,.blackCollaredStarling]
        checks["m6ExactlyFourSpeciesTenOrderedPoseNames"]=Array(SpeciesBehaviorProfile.poseSpecies.prefix(4))==m6bSpecies &&
            PoseClip.frameNames==names && BirdArt.poseNames==names && Set(names).count==10
        checks["m6cExactlyTwelvePoseSpeciesAndThreePeekNames"]=SpeciesBehaviorProfile.poseSpecies==species &&
            species.count==12 && SpeciesBehaviorProfile.peekSpecies==peekSpecies && BirdArt.peekNames==peekNames
        checks["m6LegacyCommonThirtyFourFramesRetained"]=BirdArt.names.count==34
        for id in peekSpecies {
            let clip=PoseClip.edgePeek(species:id)
            checks["m6cPeekClipFramesTimingAndFoot-"+id.rawValue]=clip?.frames.map(\.name)==peekNames &&
                clip?.frames.map(\.duration)==[0.32,0.96,0.32] && clip?.foot==PoseClip.footAnchor && clip?.maximumLoops==1
        }
        for id in SpeciesID.allCases {
            let old = BirdArt.names +
                ([SpeciesID.barnSwallow,.swinhoesWhiteEye].contains(id) ? BirdArt.allopreeningNames:[]) +
                ([SpeciesID.treeSparrow,.spottedDove].contains(id) ? BirdArt.feedingNames:[])
            let extra=species.contains(id) ? names:[]
            let peek=peekSpecies.contains(id) ? peekNames:[]
            let profile=SpeciesBehaviorProfile.profile(for:id)
            checks["m6ManifestAppendsWithoutReordering-"+id.rawValue]=BirdArt.names(for:id)==old+extra+peek+([SpeciesID.treeSparrow,.lightVentedBulbul].contains(id) ? ["bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise"]:[]) + (id == .treeSparrow ? ["carryLook","carryLower","carryGrip","carryPlace"]:[]) + (id == .barnSwallow ? CatchArtGeometry.frameNames:[]) &&
                SpeciesBehaviorProfile.profile(for:id).poseFrameNames==extra
            checks["m6cPeekRequiredFrames-"+id.rawValue]=Set(profile.requiredFrames(for:.edgePeek)) ==
                BehaviorDefinitions.definition(for:.edgePeek).requiredFrames.union(peek)
        }
    }

    private struct Raster {
        let image:CGImage
        let bytes:[UInt8]
        init(_ image:CGImage) throws {
            guard image.bitsPerPixel==32,image.bitsPerComponent==8,
                  image.alphaInfo == .premultipliedLast,
                  let data=image.dataProvider?.data,let pointer=CFDataGetBytePtr(data) else {
                throw failure("Expected native RGBA artwork")
            }
            self.image=image;bytes=Array(UnsafeBufferPointer(start:pointer,count:CFDataGetLength(data)))
        }
        var pixels:Data {
            var data=Data()
            for y in 0..<image.height {data.append(contentsOf:bytes[(y*image.bytesPerRow)..<(y*image.bytesPerRow+image.width*4)])}
            return data
        }
        func alpha(_ x:Int,_ y:Int) -> Bool {bytes[y*image.bytesPerRow+x*4+3]>0}
        func logicalAlpha(_ x:Int,_ y:Int) -> Bool {alpha(x*image.width/48,y*image.height/48)}
        /// Count contact in the semantic body, including both raised wings.
        /// Contact can reveal clipping but does not prove source paths exceed
        /// the canvas. M6c requires a transparent margin; historical M6b frames
        /// retain diagnostic counts. Lower tail carriage is excluded.
        var wingBoundaryAlphaCount:Int {
            let rows=min(image.height,Int(ceil(CGFloat(image.height)*32/48)))
            var count=(0..<image.width).filter{alpha($0,0)}.count
            for y in 1..<rows {
                if alpha(0,y) {count+=1}
                if alpha(image.width-1,y) {count+=1}
            }
            return count
        }
        var toes:Data {
            var data=Data()
            for y in 0..<image.height where CGFloat(y)*48/CGFloat(image.height)>=38 {
                for x in 0..<image.width where (24..<35).contains(CGFloat(x)*48/CGFloat(image.width)) {
                    let start=y*image.bytesPerRow+x*4;data.append(contentsOf:bytes[start..<start+4])
                }
            }
            return data
        }
    }

    private static func checkArt(_ art:BirdArt,frameNames:[String]=M6ContentVerification.names,into checks:inout [String:Bool],evidence:inout [[String:Any]],allPosePixels:inout Set<Data>,folder:URL) throws {
        let peeking=frameNames==peekNames,prefix=(peeking ? "m6cPeekArt-":"m6Art-")+art.species.rawValue+"-"
        let wingBoundaryEnforced=peeking ? peekSpecies.contains(art.species):m6cSpecies.contains(art.species)
        let old=try BirdArt.names(for:art.species).filter{!frameNames.contains($0)}.map {name -> Data in
            guard let image=art.frames[name] else {throw failure("Missing legacy frame \(name)")}
            return try Raster(image).pixels
        }
        var unique=Set<Data>(),toes:Data?,parts=[[CGImage]]()
        var independent=true,hit=true,density=true,anchors=true,feet=true,semantic=true,wings=true
        for name in frameNames {
            guard let image=art.frames[name],let authored=DetailedBirdArt.poseImage(name,species:art.species),
                  let sourceAnchor=DetailedBirdArt.poseBillAnchor(name,species:art.species),
                  let stand=art.frames["stand"] else {throw failure("Missing M6 artwork: \(art.species.rawValue)/\(name)")}
            let raster=try Raster(image),source=try Raster(authored)
            allPosePixels.insert(raster.pixels)
            independent = independent && unique.insert(raster.pixels).inserted && !old.contains(raster.pixels)
            semantic = semantic && raster.pixels==source.pixels
            density = density && image.width==stand.width && image.height==stand.height
            let anchor=PoseClip.beakAnchor(species:art.species,frame:name)
            let error=hypot(sourceAnchor.x-CGFloat(anchor.x),sourceAnchor.y-CGFloat(anchor.y))
            anchors = anchors && error<1e-5
            var layers=[CGImage]()
            for part:DetailedBirdArt.FoundationPosePart in [.body,.feet,.headNeck,.bill] {
                guard let layer=DetailedBirdArt.poseImage(name,species:art.species,part:part) else {throw failure("Missing semantic layer \(name)")}
                let pixels=try Raster(layer)
                semantic = semantic && layer.width==image.width && layer.height==image.height && pixels.bytes.contains(where:{$0>0})
                layers.append(layer)
            }
            let foot=try Raster(layers[1])
            let boundaryAlpha=try Raster(layers[0]).wingBoundaryAlphaCount
            wings = wings && boundaryAlpha==0
            if let toes {feet = feet && toes==foot.toes} else {toes=foot.toes}
            feet = feet && foot.bytes.contains(where:{$0>0})
            for y in 0..<48 {for x in 0..<48 {
                hit = hit && art.contains(frame:name,x:x,y:y)==raster.logicalAlpha(x,y)
            }}
            hit = hit && !art.contains(frame:name,x:-1,y:20) && !art.contains(frame:name,x:48,y:20)
            parts.append([image]+layers)
            evidence.append(["species":art.species.rawValue,"frame":name,"nativeSize":[image.width,image.height],
                             "sourceBillAnchor":[sourceAnchor.x,sourceAnchor.y],"clipBillAnchor":[anchor.x,anchor.y],
                             "anchorDistance":error,"billMayBeHidden":name=="restTuck",
                             "bodyWingBoundaryAlphaCount":boundaryAlpha,
                             "wingBoundaryEnforced":wingBoundaryEnforced,
                             "wingBoundaryRegion":"Native top row and left/right columns above logical y=32; lower tail excluded."])
        }
        checks[prefix+(peeking ? "ThreeIndependentFramesNotLegacyAliases":"TenIndependentFramesNotLegacyAliases")]=independent && unique.count==frameNames.count
        checks[prefix+"ProductionSpriteMatchesAuthoredArtAndSemanticLayersExist"]=semantic
        checks[prefix+"NativeDensityMatchesExistingSpecies"]=density
        checks[prefix+(peeking ? "FixedToesAcrossAllThreePoses":"FixedToesAcrossAllTenPoses")]=feet
        checks[prefix+"BillAnchorsMatchSourceWithin1eMinus5"]=anchors
        checks[prefix+"HitMasksMatchActualProductionAlpha"]=hit
        // This new margin requirement applies to the 80 M6c poses and six
        // peek frames. Keep all 40 historical counts without relabelling a
        // contacting frame as a pass or changing its frozen source pixels.
        if wingBoundaryEnforced {checks[prefix+"WingsAndUpperBodyDoNotTouchCanvasBoundary"]=wings}
        try contactSheet(art,frameNames:frameNames,parts:parts,to:folder.appendingPathComponent(art.species.rawValue+(peeking ? "-peek":"")+"-contact-sheet.png"))
    }

    /// Authored-source and production-atlas checks only. Contact timing,
    /// actual journeys and cancellation remain in the dedicated platform suite.
    private static func checkCatchArt(into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        let art=BirdArt(species:.barnSwallow),names=CatchArtGeometry.frameNames
        let legacy=try BirdArt.names(for:.barnSwallow).filter{!names.contains($0)}.map {try Raster(art.frames[$0]!).pixels}
        var unique=Set<Data>(),parts=[[CGImage]]()
        checks["m6f1CatchPermissionOnlyBarnSwallow"]=SpeciesBehaviorProfile.species(for:.insectCatch)==[.barnSwallow] &&
            SpeciesBehaviorProfile.catchFrameNames==names && BirdArt.catchNames==names
        checks["m6f1CatchReferenceFootUnchanged"]=CatchArtGeometry.footAnchor==CGPoint(x:29,y:39) &&
            PoseClip.footAnchor==PoseClip.Anchor(29,39)
        for name in names {
            guard let image=art.frames[name],let source=DetailedBirdArt.catchImage(name,species:.barnSwallow),
                  let p=CatchArtGeometry.pose(species:.barnSwallow,frame:name),
                  let anchor=PoseClip.catchBeakAnchor(species:.barnSwallow,frame:name) else {throw failure("Missing catch source \(name)")}
            let raster=try Raster(image),authored=try Raster(source)
            var layers=[CGImage](),semantic=true
            for part:DetailedBirdArt.FoundationPosePart in [.body,.feet,.headNeck,.bill] {
                guard let layer=DetailedBirdArt.catchImage(name,species:.barnSwallow,part:part) else {throw failure("Missing catch semantic part")}
                let pixels=try Raster(layer)
                semantic = semantic && layer.width==image.width && layer.height==image.height && pixels.bytes.contains(where:{$0>0})
                layers.append(layer)
            }
            let body=try Raster(layers[0]),neck=try Raster(layers[2])
            let boundary=(0..<body.image.width).contains{body.alpha($0,0) || body.alpha($0,body.image.height-1)} ||
                (0..<body.image.height).contains{body.alpha(0,$0) || body.alpha(body.image.width-1,$0)}
            var neckAbove=true
            for y in 0..<neck.image.height where CGFloat(y)*48/CGFloat(neck.image.height)>=39 {
                for x in 0..<neck.image.width {neckAbove = neckAbove && !neck.alpha(x,y)}
            }
            let independent=unique.insert(raster.pixels).inserted && !legacy.contains(raster.pixels)
            checks["m6f1CatchArt-"+name+"-IndependentNativeSourceAndFourParts"]=independent && semantic && raster.pixels==authored.pixels
            checks["m6f1CatchArt-"+name+"-SameDensityAsLegacy"]=image.width==art.frames["stand"]!.width && image.height==art.frames["stand"]!.height
            checks["m6f1CatchArt-"+name+"-WingMarginAndNeckAboveFootPlane"] = !boundary && neckAbove
            checks["m6f1CatchArt-"+name+"-BeakAtActualUpperTip"]=abs(anchor.x-Double(p.billTip.x))<1e-9 && abs(anchor.y-Double(p.billTip.y))<1e-9
            parts.append([image]+layers)
            evidence.append(["species":"barnSwallow","frame":name,"nativeSize":[image.width,image.height],
                "sourceBillAnchor":[p.billTip.x,p.billTip.y],"referenceFoot":[29,39],
                "feet":"tucked in flight; reference anchor is not a ground-contact claim"])
        }
        checks["m6f1ThreeDistinctCatchPoses"]=unique.count==3
        for name in TransportArtGeometry.frameNames {
            let anchor=PoseClip.catchBeakAnchor(species:.barnSwallow,frame:name)
            let source=DetailedBirdArt.catchBillAnchor(name,species:.barnSwallow)
            checks["m6f1CatchTransportAnchor-"+name]=anchor != nil && source != nil &&
                abs(CGFloat(anchor!.x)-source!.x)<1e-9 && abs(CGFloat(anchor!.y)-source!.y)<1e-9
        }
        checks["m6f1NoFutureFlycatcherArt"]=CatchArtGeometry.frameNames.allSatisfy {
            DetailedBirdArt.catchImage($0,species:.yellowRumpedFlycatcher)==nil &&
            PoseClip.catchBeakAnchor(species:.yellowRumpedFlycatcher,frame:$0)==nil
        }
        try contactSheet(art,frameNames:names,parts:parts,to:folder.appendingPathComponent("barnSwallow-catch-contact-sheet.png"))
        for scale in scales {for right in [true,false] {try preview(art,frameNames:names,scale:scale,right:right,folder:folder)}}
        var insects=Set<Data>()
        for name in InsectArt.frameNames {
            guard let image=InsectArt.image(name) else {throw failure("Missing insect \(name)")}
            let pixels=try Raster(image),w=image.width,h=image.height
            let margin=(0..<w).allSatisfy{!pixels.alpha($0,0) && !pixels.alpha($0,h-1)} &&
                (0..<h).allSatisfy{!pixels.alpha(0,$0) && !pixels.alpha(w-1,$0)}
            checks["m6f1InsectArt-"+name+"-IndependentTransparentCanvasAndFixedThorax"]=insects.insert(pixels.pixels).inserted &&
                w==16 && h==16 && margin && pixels.alpha(8,8)
        }
        checks["m6f1InsectArtCoreGeometryContract"]=insects.count==4 && InsectArt.anchor==CGPoint(x:8,y:8) &&
            InsectArt.collisionRadius==3 && InsectArt.logicalSize==CGSize(width:16,height:16) &&
            InsectTrajectory.logicalSize==16 && InsectTrajectory.lifetime==CatchArtGeometry.insectLifetime &&
            abs(InsectArt.frameDuration-1.0/12.0)<1e-12
    }

    private final class Fixture {
        let desktop:DesktopController
        let window:OverlayPanel,view:DesktopView
        let work:CGRect,display:CGRect
        let suite:String,preferences:UserDefaults
        var host:Surface!,pointer=CGPoint.zero
        init(folder:URL) throws {
            let desktop=DesktopController()
            guard let screen=NSScreen.screens.first,let work=desktop.screenRects.first,let display=desktop.displayRects.first else {
                throw failure("M6 native content acceptance requires a display")
            }
            self.desktop=desktop;self.work=work;self.display=display
            suite="Birding.M6ContentVerification."+UUID().uuidString
            guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot create isolated defaults")}
            self.preferences=preferences
            desktop.preferences=preferences;desktop.pointerButtonsDown={false}
            desktop.automaticPopulation=false;desktop.engine.populationEnabled=false
            desktop.engine.ambientEnabled=false;desktop.engine.autonomousRouting=false
            desktop.visitorMemoryPersistenceEnabled=false;desktop.observationJournalPersistenceEnabled=false
            desktop.settingsURL=folder.appendingPathComponent("settings.json")
            desktop.legacyURL=folder.appendingPathComponent("legacy.json")
            desktop.visitorMemoryURL=folder.appendingPathComponent("visitors.json")
            desktop.observationJournalURL=folder.appendingPathComponent("journal.json")
            window=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
            view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size))
            view.controller=desktop;view.desktopRect=display;window.contentView=view
            window.orderFrontRegardless()
        }
        func close() {
            desktop.engine.handle(.cancelAmbient(.shutdown));window.orderOut(nil)
            preferences.removePersistentDomain(forName:suite)
        }
        func install(_ species:SpeciesID,scale:CGFloat=1,right:Bool=true) -> Bird {
            desktop.engine.handle(.cancelAmbient(.screensChanged));desktop.paused=false
            var settings=BirdSettings();settings.hoverDelay=0;desktop.settings=settings;desktop.scale=scale
            desktop.hoverTracker=HoverTracker<BirdID>();desktop.hoveredID=nil
            // A short source host remains valid but cannot be selected by the
            // ordinary planner (which requires height >=100). Only the target
            // is eligible, so both takeoff directions are exercised deterministically.
            let width=work.width*0.36,left=work.minX+work.width*0.05,rightX=work.maxX-work.width*0.05-width
            host=Surface(id:6901,pid:42,rect:CGRect(x:right ? left:rightX,y:work.midY+90,width:width,height:80))
            let target=Surface(id:6902,pid:42,rect:CGRect(x:right ? rightX:left,y:work.midY-100,width:width,height:110))
            desktop.surfaces=[target,host]
            let bird=Bird(position:.zero,fraction:0.5,profile:desktop.catalog.profile(species),random:{0.5})
            bird.perch(on:host,spriteScale:desktop.spriteScale(for:bird));bird.perchDuration=600;bird.tick(2);bird.facingRight=right
            desktop.birds=[bird]
            let pointerDistance=max(130,110*desktop.spriteScale(for:bird))
            pointer=CGPoint(x:bird.position.x+(right ? 1:-1)*pointerDistance,y:bird.position.y-30)
            sync();return bird
        }
        func sync() {desktop.syncWorld(at:pointer,buttonsDown:false)}
        func step() {sync();desktop.engine.advance(1.0/120)}
        func start(_ kind:BehaviorKind) -> BehaviorRunID? {
            sync();let result=desktop.engine.handle(command(kind))
            if case .started(let id)=result {return id};return nil
        }
        func seek(_ frame:String,kind:BehaviorKind) -> Bool {
            for _ in 0..<12*120 {
                guard desktop.engine.behavior(of:desktop.birds[0])==kind else {return false}
                if desktop.engine.renderSnapshot().first?.frameName==frame {return true}
                step()
            }
            return false
        }
    }

    private static func command(_ kind:BehaviorKind) -> EngineCommand {
        switch kind {
        case .watch:return .attention(.watch,.preview)
        case .alert:return .attention(.alert,.preview)
        case .rest:return .perchAction(.rest,.preview)
        default:return .prepareTakeoff(.preview)
        }
    }
    private static func frames(_ kind:BehaviorKind) -> [String] {
        switch kind {
        case .watch:return Array(names[0..<2])
        case .alert:return Array(names[2..<5])
        case .rest:return Array(names[5..<8])
        default:return Array(names[8..<10])
        }
    }
    private static func kind(for frame:String) -> BehaviorKind {kinds.first{frames($0).contains(frame)}!}
    private static func sprite(_ view:DesktopView) -> CALayer? {view.layer?.sublayers?.first{$0.mask is CAShapeLayer}}
    private static func point(_ state:BirdRenderState,art:BirdArt,opaque:Bool) -> CGPoint? {
        for y in 0..<48 {for x in 0..<48 where art.contains(frame:state.frameName,x:x,y:y)==opaque {
            return CGPoint(x:state.rect.minX+(CGFloat(state.facingRight ? x:47-x)+0.5)*state.scale,
                           y:state.rect.minY+(CGFloat(y)+0.5)*state.scale)
        }}
        return nil
    }
    private static func terminals(_ d:DesktopController,_ run:BehaviorRunID) -> [BehaviorEvent] {
        d.engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }

    private static func checkNative(_ f:Fixture,species:SpeciesID,kind:BehaviorKind,scale:CGFloat,right:Bool,
                                    into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        let d=f.desktop,bird=f.install(species,scale:scale,right:right),origin=bird.position
        let key="m6Native-\(species.rawValue)-\(kind.rawValue)-\(scale)-\(right ? "right":"left")-"
        let run=f.start(kind),id=d.engine.id(of:bird)
        var observed=Set<String>(),layers=true,hits=true,geometry=true,namesOK=true,population=true
        for _ in 0..<12*120 {
            guard d.engine.behavior(of:bird)==kind,let state=d.engine.renderSnapshot().first else {break}
            population = population && d.birds.count==1 && d.birds.first === bird && d.engine.id(of:bird)==id &&
                d.residentCount==1 && d.engine.pendingCount==0 && d.arrivalCount==0 && d.departureCount==0
            if observed.insert(state.frameName).inserted {
                f.view.updateSprites()
                guard let layer=sprite(f.view),let texture=layer.sublayers?.first,
                      let art=d.arts[species],let image=art.frames[state.frameName],
                      let hit=point(state,art:art,opaque:true),let clear=point(state,art:art,opaque:false) else {
                    layers=false;break
                }
                layers = layers && !layer.isHidden && (texture.contents as AnyObject?) === image &&
                    texture.affineTransform().a==(right ? 1:-1) && state.facingRight==right &&
                    texture.magnificationFilter == .nearest && texture.minificationFilter == .nearest
                let foot=CGPoint(x:layer.frame.minX+f.display.minX+(right ? 29:19)*state.scale,
                                 y:layer.frame.minY+f.display.minY+(39-state.hopOffset)*state.scale)
                geometry = geometry && Geometry.distance(foot,origin)<0.001 && bird.position==origin
                hits = hits && d.bird(at:hit) === bird && d.bird(at:clear)==nil
                for language:AppLanguage in [.chinese,.english] {
                    d.language=language;d.updateHover(now:d.engine.time,at:hit);f.view.updateSprites()
                    let label=f.view.layer?.sublayers?.compactMap{$0 as? CATextLayer}.first
                    namesOK = namesOK && d.hoveredBird === bird && label?.isHidden==false &&
                        (label?.string as? String)==language.name(species)
                }
                let url=folder.appendingPathComponent(key+state.frameName+"-actual-layer.png")
                try layerSnapshot(f.view,around:layer.frame.insetBy(dx:-100,dy:-70),to:url)
                evidence.append(["species":species.rawValue,"kind":kind.rawValue,"frame":state.frameName,
                    "userScale":scale,"effectiveScale":state.scale,"facingRight":right,
                    "layerFoot":NSStringFromPoint(foot),"screenshot":url.lastPathComponent])
                d.updateHover(now:d.engine.time,at:clear);f.view.updateSprites()
                namesOK = namesOK && d.hoveredBird==nil &&
                    f.view.layer?.sublayers?.compactMap{$0 as? CATextLayer}.first?.isHidden==true
            }
            f.step()
        }
        let ends=run.map{terminals(d,$0)} ?? []
        checks[key+"AllExpectedFramesInActualLayers"]=run != nil && Set(frames(kind)).isSubset(of:observed) && layers
        checks[key+"FootAnchorAndSpeciesScale"]=run != nil && geometry && abs(d.spriteScale(for:bird)-scale*bird.profile.relativeScale)<1e-8
        checks[key+"OpaqueHitTransparentMissAndBilingualName"]=run != nil && hits && namesOK
        checks[key+"CompletesOnceReleasesAndPreservesPopulation"]=run != nil && population && ends.count==1 &&
            ends.first?.type == .completed && d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0
    }

    private static func checkClick(_ f:Fixture,species:SpeciesID,frame:String,into checks:inout [String:Bool]) {
        let d=f.desktop,bird=f.install(species),kind=kind(for:frame),run=f.start(kind)
        let reached=run != nil && f.seek(frame,kind:kind)
        let origin=bird.position,revision=bird.motionRevision,id=d.engine.id(of:bird)
        let state=d.engine.renderSnapshot().first,art=d.arts[species]!
        let hit=state.flatMap{point($0,art:art,opaque:true)}
        if reached,let hit,let event=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:hit,mouseButton:.left),
           let native=NSEvent(cgEvent:event) {d.handleMouseDown(native)}
        let ends=run.map{terminals(d,$0)} ?? []
        let moved=d.engine.behavior(of:bird) == .relocate
        checks["m6Click-\(species.rawValue)-\(frame)-ImmediateSameBird"]=reached && moved &&
            bird.position==origin && bird.motionRevision>revision && d.engine.id(of:bird)==id &&
            d.birds.count==1 && d.birds.first === bird && d.hoveredBird==nil &&
            ends.count==1 && ends.first?.type == .cancelled && d.engine.reservedLandingCount==0
        for _ in 0..<6 {f.step()}
        checks["m6Click-\(species.rawValue)-\(frame)-ContinuesWithoutSnapBack"]=reached && moved &&
            Geometry.distance(origin,bird.position)>0.01 && d.engine.behavior(of:bird) == .relocate &&
            (run.map{terminals(d,$0).count} ?? 0)==1
    }

    private static func checkLifecycle(_ f:Fixture,kind:BehaviorKind,into checks:inout [String:Bool]) {
        let d=f.desktop,key="m6Lifecycle-"+kind.rawValue+"-"
        let bird=f.install(.treeSparrow),run=f.start(kind)
        f.step();d.paused=true
        let frozen=d.engine.renderSnapshot().first,position=bird.position,age=bird.stateTime
        for _ in 0..<120 {f.step()}
        let after=d.engine.renderSnapshot().first
        checks[key+"PauseFreezesPoseAndFoot"]=run != nil && frozen != nil && after?.frameName==frozen?.frameName &&
            after?.rect==frozen?.rect && bird.position==position && bird.stateTime==age &&
            d.engine.behavior(of:bird)==kind && d.engine.leasedBirdCount==1
        d.paused=false;f.step()
        checks[key+"ResumeKeepsSameRun"]=run != nil && d.engine.behavior(of:bird)==kind &&
            d.engine.events.filter{$0.runID==run && $0.type == .started}.count==1
        for action in ["disable","hostRemoved","birdRemoved","sleep","shutdown","pausedHostRemoved","occlusion"] {
            let current=f.install(.treeSparrow),active=f.start(kind)
            f.step()
            let state=d.engine.renderSnapshot().first
            let hit=state.flatMap{point($0,art:d.arts[.treeSparrow]!,opaque:true)}
            var blocker:CGRect?
            switch action {
            case "disable":var settings=d.settings;settings.perchActions=false;d.settings=settings
            case "hostRemoved","pausedHostRemoved":
                if action=="pausedHostRemoved" {d.paused=true}
                d.surfaces.removeAll{$0.id==f.host.id};f.sync()
            case "birdRemoved":if let id=d.engine.id(of:current) {d.engine.handle(.remove(id))}
            case "sleep":d.engine.handle(.cancelAmbient(.sleep))
            case "shutdown":d.engine.handle(.cancelAmbient(.shutdown))
            default:
                if let hit {
                    let cover=CGRect(x:hit.x-3,y:hit.y-3,width:6,height:6)
                    blocker=cover;d.surfaces.insert(Surface(id:6903,pid:43,rect:cover),at:0);f.sync()
                }
            }
            let ends=active.map{terminals(d,$0)} ?? []
            checks[key+action+"EndsOnceWithoutCompletionOrLeases"]=active != nil && ends.count==1 &&
                ends.first?.type != .completed && d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0 &&
                d.engine.reservedLandingCount==0
            if let blocker,let hit {
                d.updateHover(now:d.engine.time,at:hit);f.view.updateSprites()
                let container=sprite(f.view),mask=container?.mask as? CAShapeLayer
                let local=CGPoint(x:hit.x-(container?.frame.minX ?? 0)-f.display.minX,
                                  y:hit.y-(container?.frame.minY ?? 0)-f.display.minY)
                checks[key+"OcclusionUpdatesActualMaskAndClearsHitAndName"]=mask?.path != nil &&
                    mask?.path?.contains(local,using:.winding,transform:.identity)==false &&
                    d.bird(at:hit)==nil && d.hoveredBird==nil && blocker.contains(hit)
            }
            // A subsequent validation pass must not emit a duplicate terminal.
            f.sync()
            checks[key+action+"NoDuplicateTerminal"]=active != nil && (active.map{terminals(d,$0).count} ?? 0)==1
        }
    }

    private static func checkSettings(_ f:Fixture,into checks:inout [String:Bool],folder:URL) throws {
        let d=f.desktop,w=SpeciesSettingsWindow(desktop:d)
        w.showWindow(nil)
        defer {w.cancel()}
        let sections:[(BehaviorKind,String)]=[(.edgePeek,"edgePeekHelp"),(.chase,"chaseHelp"),
            (.travelTogether,"travelTogetherHelp"),(.allopreening,"allopreeningHelp"),
            (.fixedPerchVisit,"fixedPerchHelp"),(.foodTrayVisit,"foodTrayHelp")]
        for language:AppLanguage in [.chinese,.english] {
            d.language=language;w.relocalize()
            let suffix=language.rawValue
            guard let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let document=scroll.documentView else {
                checks["m6SettingsDocument-"+suffix]=false;continue
            }
            func label(_ id:String) -> NSTextField? {
                document.subviews.compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue==id}
            }
            for (kind,identifier) in sections {
                let field=label(identifier),expected=language.supportedSpeciesNames(for:kind)
                let fits=field.map{($0.cell?.cellSize(forBounds:$0.bounds).height ?? .infinity)<=$0.frame.height} ?? false
                checks["m6SettingsSameProfileOrder-\(kind.rawValue)-\(suffix)"]=field?.stringValue.contains(expected)==true &&
                    !expected.isEmpty && fits
            }
            for identifier in ["perchActivitiesHelp","perchPreviewHelp","passiveMotionHelp"] {
                let field=label(identifier)
                let speciesHelp=label("perchActivitiesHelp")?.stringValue ?? ""
                let sameScope=identifier=="perchActivitiesHelp" ? field?.stringValue.contains(language.poseSpeciesNames)==true:
                    field?.stringValue.contains(language.poseSupportReference)==true
                checks["m6SettingsPoseSpeciesAndHelpFits-\(identifier)-\(suffix)"]=sameScope &&
                    species.allSatisfy{speciesHelp.contains(language.name($0))} &&
                    (field.map{($0.cell?.cellSize(forBounds:$0.bounds).height ?? .infinity)<=$0.frame.height} ?? false)
            }
            let previewMessages:[(BehaviorKind,String)]=[
                (.allopreening,w.allopreeningPreviewMessage(.noSpecies)),
                (.foodTrayVisit,w.foodTrayMessage(.noSpecies))]
            // Fixed-perch preview correctly asks for a saved perch before
            // reporting species eligibility; this fixture deliberately has none.
            for (kind,text) in previewMessages {
                checks["m6SettingsPreviewUsesSameSpecies-\(kind.rawValue)-\(suffix)"]=text.contains(language.supportedSpeciesNames(for:kind))
            }
            // Exercise the actual edge-peek rejection route with an unsupported
            // resident instead of checking a second copy of the expected text.
            _=f.install(.redWhiskeredBulbul);w.previewEdgePeek()
            checks["m6SettingsEdgePeekRejectionUsesProfile-"+suffix]=d.engine.events.last?.reason == .noSpecies &&
                w.message.stringValue.contains(language.supportedSpeciesNames(for:.edgePeek))
            checks["m6SettingsEdgePeekRejectionMessageFullyVisible-"+suffix]=EdgePeekSettingsVerification.messageIsFullyVisible(w.message)
            w.tabs.selectTabViewItem(at:2)
            scroll.contentView.scroll(to:CGPoint(x:0,y:870));scroll.reflectScrolledClipView(scroll.contentView)
            try SettingsVerification.snapshot(w.window!,to:folder.appendingPathComponent("pose-support-settings-"+suffix+".png"))
        }
    }

    private static func bitmap(width:Int,height:Int) throws -> CGContext {
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("Cannot allocate M6 evidence bitmap")
        }
        context.translateBy(x:0,y:CGFloat(height));context.scaleBy(x:1,y:-1)
        context.interpolationQuality = .none;return context
    }
    private static func label(_ text:String,x:CGFloat,y:CGFloat,in context:CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        context.saveGState();context.translateBy(x:x,y:y);context.scaleBy(x:1,y:-1)
        (text as NSString).draw(at:.zero,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:11,weight:.medium),
                                                       .foregroundColor:NSColor.white])
        context.restoreGState();NSGraphicsContext.restoreGraphicsState()
    }
    private static func draw(_ image:CGImage,foot:CGPoint,scale:CGFloat,right:Bool,in context:CGContext) {
        context.saveGState();context.translateBy(x:foot.x,y:foot.y)
        context.scaleBy(x:right ? scale:-scale,y:scale);context.translateBy(x:-29,y:-39)
        context.translateBy(x:0,y:48);context.scaleBy(x:1,y:-1)
        context.draw(image,in:CGRect(x:0,y:0,width:48,height:48));context.restoreGState()
    }
    private static func contactSheet(_ art:BirdArt,frameNames:[String],parts:[[CGImage]],to url:URL) throws {
        let height=frameNames.count*150+80,context=try bitmap(width:1320,height:height)
        context.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor)
        context.fill(CGRect(x:0,y:0,width:1320,height:height))
        let stage=frameNames==CatchArtGeometry.frameNames ? "M6f.1 catch":(m6bSpecies.contains(art.species) ? "M6b historical":"M6c")
        label(art.species.rawValue+" / "+stage+" / actual sprite + authored semantic parts / 3x",x:20,y:22,in:context)
        let headings=["production","body (incl. overlays)","feet / toes","head + neck","bill"]
        for (column,title) in headings.enumerated() {label(title,x:260+CGFloat(column)*210-70,y:45,in:context)}
        for (row,name) in frameNames.enumerated() {
            let y=CGFloat(row)*150+180
            label(name,x:15,y:y-50,in:context)
            for column in 0..<5 {draw(parts[row][column],foot:CGPoint(x:260+CGFloat(column)*210,y:y),scale:3,right:true,in:context)}
        }
        // Semantic body contains later shoulder/wing overlays; it is not a
        // claim that four flattened layers reconstruct the full painter order.
        try png(context,to:url)
    }
    private static func preview(_ art:BirdArt,frameNames:[String]=M6ContentVerification.names,scale:CGFloat,right:Bool,folder:URL) throws {
        let effective=scale*SpeciesCatalog.standard.profile(art.species).relativeScale
        let rowHeight=max(120,Int(ceil(48*effective))+42),width=900,height=rowHeight*frameNames.count+50
        let context=try bitmap(width:width,height:height)
        context.setFillColor(NSColor(calibratedRed:0.09,green:0.13,blue:0.16,alpha:1).cgColor)
        context.fill(CGRect(x:0,y:0,width:width,height:height))
        label("\(art.species.rawValue) / \(scale)x user scale / \(right ? "right":"left") / original + occluded",x:16,y:22,in:context)
        for (index,name) in frameNames.enumerated() {
            let y=CGFloat(index*rowHeight)+40+39*effective
            label(name,x:15,y:y-10,in:context)
            let foot=CGPoint(x:340,y:y),masked=CGPoint(x:680,y:y)
            let rect=CGRect(x:masked.x-(right ? 29:19)*effective,y:y-39*effective,width:48*effective,height:48*effective)
            context.setStrokeColor(NSColor.gray.cgColor);context.setLineWidth(1)
            context.move(to:CGPoint(x:200,y:y));context.addLine(to:CGPoint(x:870,y:y));context.strokePath()
            art.draw(name:name,at:foot,scale:effective,right:right,context:context)
            context.saveGState()
            context.clip(to:Geometry.visiblePieces(rect,blockers:[CGRect(x:rect.midX,y:rect.minY,width:rect.width/2,height:rect.height)]))
            art.draw(name:name,at:masked,scale:effective,right:right,context:context)
            context.restoreGState()
            let anchor=PoseClip.beakAnchor(species:art.species,frame:name).world(foot:foot,scale:effective,facingRight:right)
            context.setStrokeColor(NSColor.systemOrange.cgColor)
            context.strokeEllipse(in:CGRect(x:anchor.x-3,y:anchor.y-3,width:6,height:6))
        }
        let track=frameNames==CatchArtGeometry.frameNames ? "-catch":(frameNames==peekNames ? "-peek":"")
        try png(context,to:folder.appendingPathComponent("\(art.species.rawValue)\(track)-\(scale)x-\(right ? "right":"left")-preview.png"))
    }
    /// Crop the real DesktopView root, retaining its sprite transform, mask and
    /// name label; this is the same CALayer rendering path as old native fixtures.
    private static func layerSnapshot(_ view:DesktopView,around rect:CGRect,to url:URL) throws {
        let crop=rect.intersection(view.bounds).integral
        guard !crop.isEmpty,let layer=view.layer else {throw failure("No actual native layer to capture")}
        let context=try bitmap(width:Int(crop.width),height:Int(crop.height))
        context.translateBy(x:-crop.minX,y:-crop.minY);layer.render(in:context)
        try png(context,to:url)
    }
    private static func png(_ context:CGContext,to url:URL) throws {
        guard let image=context.makeImage(),let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {
            throw failure("Cannot encode \(url.lastPathComponent)")
        }
        try data.write(to:url,options:.atomic)
    }
    private static func failure(_ message:String) -> NSError {
        NSError(domain:"M6ContentVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }
}
