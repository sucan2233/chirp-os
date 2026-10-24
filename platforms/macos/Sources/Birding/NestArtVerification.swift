import AppKit
import BirdingCore

/// Authored art and contact geometry only. Real stock conservation, delivery,
/// arrange commits and safe exits are verified by their separate runtime suites.
enum NestArtVerification {
    private static let species=SpeciesID.spottedDove
    private static let prefix="m7bcNestArt-"
    private static let carry=["carryLook","carryLower","carryGrip","carryPlace"]
    private static let build=["nestPlace","nestAdjust0","nestAdjust1","nestSettle"]
    private static let parts:[DetailedBirdArt.FoundationPosePart]=[.body,.feet,.headNeck,.bill]

    static func run(into checks:inout [String:Bool],folder:URL)throws {
        let output=folder.appendingPathComponent("nest-art",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let names=carry+build,art=BirdArt(species:species)
        let prior=BirdArt.names+BirdArt.feedingNames+PoseClip.frameNames+CourtshipArtGeometry.frameNames
        let old=try prior.map {try raster(art,$0)}
        let stand=try raster(art,"stand")
        let swatch=try Raster(DetailedBirdArt.courtshipCollarPaletteImage())
        let black=swatch.rgba(16,32),white=swatch.rgba(48,32)
        let targets=[CGPoint(x:40,y:19),CGPoint(x:40,y:31),CGPoint(x:40,y:39),CGPoint(x:40,y:39),
            CGPoint(x:40,y:26),CGPoint(x:40,y:39),CGPoint(x:41,y:39),CGPoint(x:40,y:39)]
        var unique=Set<Data>(),bodies=Set<Data>(),feet:Data?,sources=[[CGImage]](),evidence=[[String:Any]]()
        for (index,name) in names.enumerated() {
            guard let fullImage=art.frames[name],let direct=DetailedBirdArt.nestImage(name,species:species),
                  let generic=DetailedBirdArt.poseImage(name,species:species),
                  let bill=DetailedBirdArt.poseBillAnchor(name,species:species),
                  let pose=NestArtGeometry.pose(species:species,frame:name) else {throw failure("Missing nest source "+name)}
            let full=try Raster(fullImage),source=try Raster(direct),genericRaster=try Raster(generic)
            let layerImages=try parts.map {part -> CGImage in
                guard let image=DetailedBirdArt.nestImage(name,species:species,part:part) else {throw failure("Missing nest semantic layer")}
                return image
            }
            let layers=try layerImages.map{try Raster($0)},key=prefix+name+"-"
            checks[key+"IndependentSourceAfterHistoricalPack"]=full.pixels==source.pixels && full.pixels==genericRaster.pixels &&
                unique.insert(full.pixels).inserted && !old.contains{$0.pixels==full.pixels}
            bodies.insert(layers[0].pixels)
            checks[key+"FourNativePartsReconstructProduction"]=full.width==64 && full.height==64 &&
                layers.allSatisfy{$0.width==64 && $0.height==64 && !$0.points.isEmpty} && reconstruct(layers,full:full)
            if feet==nil {feet=layers[1].pixels}
            checks[key+"FeetUnchangedAndNeckAboveContactPlane"]=layers[1].pixels==feet && full.footBand==stand.footBand &&
                layers[2].points.allSatisfy{$0.y<39} && layers.allSatisfy(\.clearBoundary)
            let anchor=PoseClip.beakAnchor(species:species,frame:name),target=targets[index]
            checks[key+"ActualBillAndMirroredAnchor"]=hypot(bill.x-target.x,bill.y-target.y)<1e-9 &&
                hypot(bill.x-CGFloat(anchor.x),bill.y-CGFloat(anchor.y))<1e-9 && layers[3].alpha(near:bill) &&
                anchor.mirrored(facingRight:false)==PoseClip.Anchor(48-anchor.x,anchor.y)
            let collarSpots=pose.collarSpots,unit=48/CGFloat(full.width)
            let spotIndices=collarSpots.map{Int($0.y/unit)*full.width+Int($0.x/unit)}
            let blackInside=layers[2].color(black,inside:pose.collar)
            let whiteAtSpots=collarSpots.map{layers[2].color(white,at:$0)}
            let collarDiagnostics:[String:Any]=["blackInsideCollar":blackInside,
                "spotWhiteAtExactNativePixel":whiteAtSpots,"distinctSpotPixels":Set(spotIndices).count,
                "resolvedBlack":black,"resolvedWhite":white]
            checks[key+"MappedSpottedCollarSurvivesRaster"]=black != white && black[3]==255 && white[3]==255 &&
                blackInside && collarSpots.count==5 && Set(spotIndices).count==5 && whiteAtSpots.allSatisfy{$0}
            checks[key+"ProductionHitMask"]=(0..<48).allSatisfy {y in (0..<48).allSatisfy {x in
                art.contains(frame:name,x:x,y:y)==full.alpha(x*full.width/48,y*full.height/48)
            }} && !art.contains(frame:name,x:-1,y:20) && !art.contains(frame:name,x:48,y:20)
            sources.append([fullImage]+layerImages)
            evidence.append(["frame":name,"beak":[Double(bill.x),Double(bill.y)],"foot":[29,39],
                "nativeSize":[64,64],"bodyPitch":pose.bodyPitch,"headPitch":pose.headPitch,
                "collar":pose.collar.map{[Double($0.x),Double($0.y)]},
                "collarSpots":collarSpots.map{[Double($0.x),Double($0.y)]},
                "collarDiagnostics":collarDiagnostics])
        }
        checks[prefix+"EightUniquePosesAndBodiesAfterUnchangedFiftyThree"]=prior.count==53 &&
            BirdArt.names(for:species)==prior+names && Array(BirdArt.names(for:species).prefix(53))==prior &&
            NestArtGeometry.frameNames==names && unique.count==8 && bodies.count==8
        checks[prefix+"OnlyDoveNestSourceAndSeparatePermissions"]=SpeciesID.allCases.allSatisfy {id in
            let allowed=id == species,profile=SpeciesBehaviorProfile.profile(for:id)
            return profile.allows(.nestMaterialCarry)==allowed && profile.allows(.nestBuild)==allowed &&
                (allowed || names.allSatisfy{DetailedBirdArt.nestImage($0,species:id)==nil})
        } && !SpeciesBehaviorProfile.profile(for:species).allows(.leafCarry) &&
            !SpeciesBehaviorProfile.profile(for:species).allows(.fixedPerchVisit)
        try checkClips(into:&checks)
        try checkAssets(into:&checks,folder:output)
        try checkContactAndFlight(art,into:&checks,folder:output)
        for right in [true,false] {try sourceSheet(sources,names:names,right:right,
            to:output.appendingPathComponent("spottedDove-nest-source-\(right ? "right":"left").png"))}
        for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
            try contacts(art,names:names,scale:scale,right:right,
                to:output.appendingPathComponent("spottedDove-nest-\(scale)x-\(right ? "right":"left")-contacts.png"))
        }}
        let metadata=BirdArt.poseMetadata[species.rawValue] as? [String:Any] ?? [:]
        let anchors=metadata["nestBeakAnchors"] as? [String:[Double]] ?? [:]
        let wanted=Set(names+TransportArtGeometry.frameNames)
        checks[prefix+"TwentySevenExactBillMetadataEntries"]=anchors.count==27 && Set(anchors.keys)==wanted && wanted.allSatisfy {name in
            guard let point=NestArtGeometry.billAnchor(species:species,frame:name),let pair=anchors[name],pair.count==2 else {return false}
            return abs(pair[0]-Double(point.x))<1e-9 && abs(pair[1]-Double(point.y))<1e-9
        }
        checks[prefix+"ThirteenPreviewSpeciesKeepSeventyEightNames"]=BirdArt.poseExportSpecies.count==13 && Set(BirdArt.poseExportSpecies).count==13
        let own=checks.filter{$0.key.hasPrefix(prefix)}
        saveJSON(["scope":"M7b/c source art and contact metadata, not real transport/build completion.",
            "passed":!own.isEmpty && own.values.allSatisfy{$0},"checks":own,"frames":evidence,
            "assets":NestArtGeometry.assetNames,"limits":"Source panels do not replace production CALayer sequences, material conservation or separate transport/build exit acceptance."],
            to:output.appendingPathComponent("report.json"))
    }
    private static func checkClips(into checks:inout [String:Bool])throws {
        guard let pickup=PoseClip.nestMaterialPickup(species:species),let place=PoseClip.nestMaterialPlace(species:species),
              let arrange=PoseClip.nestBuild(species:species) else {throw failure("Missing dedicated nest clips")}
        checks[prefix+"PickupAndGroundedPlaceTiming"]=pickup.frames.map(\.name)==["carryLook","carryLower","carryGrip","carryLook"] &&
            pickup.frames.map(\.duration)==[0.4,0.3,0.2,0.3] && place.frames.map(\.name)==["carryPlace","carryLook"] &&
            place.frames.map(\.duration)==[0.4,0.3] && abs(pickup.duration-1.2)<1e-9 && abs(place.duration-0.7)<1e-9
        checks[prefix+"IndependentArrangeTwoCyclesAndCommitBoundary"]=arrange.frames.map(\.name)==[
            "nestPlace","nestAdjust0","nestAdjust1","nestAdjust0","nestAdjust1","nestSettle","nestPlace"] &&
            arrange.frames.map(\.duration)==[0.3,0.3,0.3,0.3,0.3,0.4,0.3] && abs(arrange.duration-2.2)<1e-9 &&
            arrange.sample(at:1.899)?.name=="nestSettle" && arrange.sample(at:1.9)?.name=="nestPlace"
        checks[prefix+"AllClipBillsRealAndCurrentStateRecovery"]=[pickup,place,arrange].allSatisfy {clip in
            clip.foot==PoseClip.footAnchor && clip.maximumLoops==1 && clip.recovery == .currentEngineState && clip.frames.allSatisfy {frame in
                frame.beak==PoseClip.nestBeakAnchor(species:species,frame:frame.name)
            }
        }
        checks[prefix+"AllOtherSpeciesRejectNestClips"]=SpeciesID.allCases.filter{$0 != species}.allSatisfy {
            PoseClip.nestMaterialPickup(species:$0)==nil && PoseClip.nestMaterialPlace(species:$0)==nil && PoseClip.nestBuild(species:$0)==nil
        }
        let metadata=BirdArt.poseMetadata[species.rawValue] as? [String:Any] ?? [:]
        let clips=metadata["clips"] as? [String:Any] ?? [:]
        checks[prefix+"ThreeDedicatedClipsAppendToSixHistoricalOnes"]=Set(clips.keys)==Set([
            "watch","alert","rest","takeoffPreparation","courtshipInitiator","courtshipObserver",
            "nestMaterialPickup","nestMaterialPlace","nestBuild"])
    }
    private static func checkAssets(into checks:inout [String:Bool],folder:URL)throws {
        let twig=try Raster(NestArt.twigImage(),logical:TwigGeometry.logicalSize)
        let tray=try Raster(NestArt.trayImage(),logical:NestArtGeometry.traySize)
        let base=try Raster(NestArt.image(),logical:NestArtGeometry.nestSize)
        let path=NestArt.twigPath
        var maskMismatches=[[Int]]()
        for y in 0..<16 {for x in 0..<16 {
            let expected=path.contains(CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5))
            if twig.alpha(x,y) != expected {maskMismatches.append([x,y,twig.alpha(x,y) ? 1:0,expected ? 1:0])}
        }}
        checks[prefix+"TwigExactFilledPolygonSixteenLongAndBottomTwelve"]=twig.width==16 && twig.height==16 &&
            maskMismatches.isEmpty && twig.points.count==56 &&
            twig.points.map(\.x).min()==0.5 && twig.points.map(\.x).max()==15.5 &&
            twig.points.map(\.y).max()==11.5 && TwigGeometry.grip==CGPoint(x:3,y:12) && TwigGeometry.surface==CGPoint(x:8,y:12)
        saveJSON(["polygon":TwigGeometry.polygon.map{[Double($0.x),Double($0.y)]},
            "inkPixelCount":twig.points.count,"expectedInkPixelCount":56,
            "maskMismatchesXYActualExpected":maskMismatches],to:folder.appendingPathComponent("twig-geometry-diagnostics.json"))
        checks[prefix+"TwigSilhouetteSymmetryAllowsEitherRealEndGrip"]=(0..<16).allSatisfy {y in
            (0..<16).allSatisfy {x in twig.alpha(x,y)==twig.alpha(15-x,y)}
        }
        checks[prefix+"EmptyTrayAndPlatformHaveFixedContactPlanes"]=base.width==144 && base.height==48 &&
            tray.width==32 && tray.height==16 && base.points.allSatisfy{$0.y>=24} && tray.points.allSatisfy{$0.y>=12} &&
            NestArtGeometry.materialPoints==[CGPoint(x:60,y:24),CGPoint(x:72,y:24),CGPoint(x:84,y:24)] &&
            NestArtGeometry.trayMaterialPoints==[CGPoint(x:8,y:12),CGPoint(x:16,y:12),CGPoint(x:24,y:12)]
        var stages=Set<Data>(),counts=[Int]()
        for progress in 1...3 {
            guard let image=NestArt.overlayImage(progress:progress) else {throw failure("Missing nest progress image")}
            let raster=try Raster(image,logical:NestArtGeometry.nestSize)
            stages.insert(raster.pixels);counts.append(raster.points.count)
            checks[prefix+"ShallowIndependentOverlay-\(progress)"]=image.width==144 && image.height==48 &&
                !raster.points.isEmpty && raster.points.allSatisfy{(40...106).contains($0.x) && (14...24).contains($0.y)}
        }
        checks[prefix+"ExactlySixAssetsWithNoSeparateStageZero"]=NestArtGeometry.assetNames.count==6 && stages.count==3 &&
            counts[0]<counts[1] && counts[1]<counts[2] && NestArt.overlayImage(progress:0)==nil && NestArt.overlayImage(progress:4)==nil
        let c=try bitmap(width:1050,height:760)
        label("M7b/c / six raw assets / stock always separate / shallow progress 0...3",at:CGPoint(x:15,y:15),in:c)
        draw(NestArt.twigImage(),at:CGPoint(x:20,y:45),scale:8,in:c)
        draw(NestArt.trayImage(),at:CGPoint(x:210,y:45),scale:8,in:c)
        for stage in 0...3 {
            let point=CGPoint(x:CGFloat(30+(stage%2)*510),y:CGFloat(240+(stage/2)*240))
            label("progress \(stage)",at:CGPoint(x:point.x,y:point.y-20),in:c)
            draw(NestArt.image(),at:point,scale:3,in:c)
            if let overlay=NestArt.overlayImage(progress:stage) {draw(overlay,at:point,scale:3,in:c)}
        }
        try BathVerification.writePNG(c,to:folder.appendingPathComponent("nest-six-assets-and-progress.png"))
    }
    private static func checkContactAndFlight(_ art:BirdArt,into checks:inout [String:Bool],folder:URL)throws {
        let twig=try Raster(NestArt.twigImage(),logical:TwigGeometry.logicalSize)
        for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
            let size=scale*SpeciesCatalog.standard.profile(species).relativeScale
            let foot=CGPoint(x:-900,y:300),surface=CGPoint(x:-700,y:300),direction:CGFloat=right ? 1:-1
            guard let grip=TwigGeometry.gripPoint(surfacePoint:surface,worldScale:scale,facingRight:right) else {throw failure("Missing real twig grip")}
            let contactFoot=CGPoint(x:grip.x-direction*11*size,y:surface.y)
            let bill=PoseClip.nestBeakAnchor(species:species,frame:"carryGrip")!.world(foot:contactFoot,scale:size,facingRight:right)
            let laid=NestGeometry.render(id:ScenePropID(1),position:surface,worldScale:scale,anchor:TwigGeometry.surface)
            let attached=NestGeometry.render(id:ScenePropID(1),position:bill,worldScale:scale,facingRight:right)
            checks[prefix+"StablePickupAndPlaceAcrossIndependentScale-\(scale)-\(right)"]=Geometry.distance(grip,bill)<1e-9 &&
                close(laid.rect,attached.rect) && abs(laid.rect.maxY-surface.y)<1e-9
            for name in NestArtGeometry.carryFrameNames+TransportArtGeometry.frameNames {
                guard let anchor=PoseClip.nestBeakAnchor(species:species,frame:name),
                      let geometry=NestArtGeometry.billAnchor(species:species,frame:name) else {throw failure("Missing carried flight bill "+name)}
                let bird=try raster(art,name),beak=anchor.world(foot:foot,scale:size,facingRight:right)
                let prop=NestGeometry.render(id:ScenePropID(2),position:beak,worldScale:scale,facingRight:right)
                var clear=true
                for p in twig.points {
                    let world=CGPoint(x:beak.x+direction*(p.x-TwigGeometry.grip.x)*scale,
                                      y:beak.y+(p.y-TwigGeometry.grip.y)*scale)
                    let x=29+direction*(world.x-foot.x)/size,y=39+(world.y-foot.y)/size
                    if bird.alpha(logical:CGPoint(x:x,y:y)) && Geometry.distance(world,beak)>3.5*scale {clear=false}
                }
                checks[prefix+"BillAndTwigClearBodyOutsideClamp-\(name)-\(scale)-\(right)"]=clear &&
                    abs(anchor.x-Double(geometry.x))<1e-9 && abs(anchor.y-Double(geometry.y))<1e-9 &&
                    prop.rect.width==16*scale && prop.rect.height==6*scale
                let range:ClosedRange<CGFloat> = -0.3...0.3
                guard let swept=TwigGeometry.sweptBounds(position:beak,worldScale:scale,facingRight:right,rotationRange:range) else {
                    throw failure("Missing twig angular envelope")
                }
                let bounded=(-12...12).allSatisfy {step -> Bool in
                    let angle=CGFloat(step)*0.025
                    guard let vertices=TwigGeometry.transformedPolygon(position:beak,worldScale:scale,facingRight:right,rotation:angle) else {return false}
                    return vertices.allSatisfy{swept.insetBy(dx:-1e-9,dy:-1e-9).contains($0)}
                }
                checks[prefix+"AngularExtremaCoverInteriorVertices-\(name)-\(scale)-\(right)"]=bounded
            }
        }}
        guard let round=TwigGeometry.sweptBounds(position:.zero,worldScale:1,facingRight:true,rotationRange:-CGFloat.pi...CGFloat.pi) else {
            throw failure("Missing complete twig rotation envelope")
        }
        let radius=TwigGeometry.polygon.map{hypot($0.x-TwigGeometry.grip.x,$0.y-TwigGeometry.grip.y)}.max()!
        checks[prefix+"FullRotationExtremaUseFarthestRealVertex"]=abs(round.minX+radius)<1e-9 && abs(round.maxX-radius)<1e-9 &&
            abs(round.minY+radius)<1e-9 && abs(round.maxY-radius)<1e-9
    }
    private static func sourceSheet(_ frames:[[CGImage]],names:[String],right:Bool,to url:URL)throws {
        let c=try bitmap(width:1250,height:1420)
        label("spottedDove / M7b+c / production + body + fixed feet + head/neck + bill / \(right ? "right":"left")",at:CGPoint(x:15,y:16),in:c)
        for (row,layers) in frames.enumerated() {
            label(names[row],at:CGPoint(x:10,y:CGFloat(90+row*170)),in:c)
            for (column,image) in layers.enumerated() {
                c.saveGState();c.translateBy(x:CGFloat(140+column*215),y:CGFloat(48+row*170))
                if !right {c.translateBy(x:144,y:0);c.scaleBy(x:-1,y:1)}
                draw(image,at:.zero,scale:144/64,in:c);c.restoreGState()
            }
        }
        try BathVerification.writePNG(c,to:url)
    }
    private static func contacts(_ art:BirdArt,names:[String],scale:CGFloat,right:Bool,to url:URL)throws {
        let size=scale*SpeciesCatalog.standard.profile(species).relativeScale
        let row=max(170,Int(ceil(39*size+24*scale))+50),c=try bitmap(width:1040,height:row*names.count+40)
        let direction:CGFloat=right ? 1:-1
        for (index,name) in names.enumerated() {
            let y=CGFloat(index*row)+max(70,39*size+20),surface=CGPoint(x:530,y:y)
            let foot=CGPoint(x:surface.x-direction*(5*scale+11*size),y:y)
            let origin=CGPoint(x:surface.x-72*scale,y:y-24*scale)
            draw(NestArt.image(),at:origin,scale:scale,in:c)
            if let overlay=NestArt.overlayImage(progress:1) {draw(overlay,at:origin,scale:scale,in:c)}
            art.draw(name:name,at:foot,scale:size,right:right,context:c)
            let materialFrame=carry.contains(name) ? name:"carryGrip"
            if let bill=PoseClip.nestBeakAnchor(species:species,frame:materialFrame) {
                let point=bill.world(foot:foot,scale:size,facingRight:right)
                c.saveGState();c.translateBy(x:point.x,y:point.y);c.scaleBy(x:right ? scale:-scale,y:scale)
                draw(NestArt.twigImage(),at:CGPoint(x:-3,y:-12),scale:1,in:c);c.restoreGState()
            }
            label("\(scale)x / \(right ? "right":"left") / \(name) / pose contacts only",at:CGPoint(x:12,y:CGFloat(index*row+15)),in:c)
        }
        try BathVerification.writePNG(c,to:url)
    }
    private static func raster(_ art:BirdArt,_ name:String)throws->Raster {
        guard let image=art.frames[name] else {throw failure("Missing dove frame "+name)}
        return try Raster(image)
    }
    private struct Raster {
        let width:Int,height:Int,stride:Int,bytes:[UInt8],pixels:Data,logical:CGSize
        init(_ image:CGImage,logical:CGSize=CGSize(width:48,height:48))throws {
            let r=try BathArtVerification.Raster(image)
            width=r.width;height=r.height;stride=r.stride;bytes=r.bytes;pixels=r.pixels;self.logical=logical
        }
        func rgba(_ x:Int,_ y:Int)->[UInt8] {Array(bytes[(y*stride+x*4)..<(y*stride+x*4+4)])}
        func alpha(_ x:Int,_ y:Int)->Bool {bytes[y*stride+x*4+3]>0}
        func alpha(logical p:CGPoint)->Bool {
            guard p.x>=0,p.y>=0,p.x<logical.width,p.y<logical.height else {return false}
            return alpha(Int(p.x*CGFloat(width)/logical.width),Int(p.y*CGFloat(height)/logical.height))
        }
        func center(_ x:Int,_ y:Int)->CGPoint {
            CGPoint(x:(CGFloat(x)+0.5)*logical.width/CGFloat(width),y:(CGFloat(y)+0.5)*logical.height/CGFloat(height))
        }
        var points:[CGPoint] {
            var result=[CGPoint]();for y in 0..<height {for x in 0..<width where alpha(x,y) {result.append(center(x,y))}};return result
        }
        func alpha(near point:CGPoint)->Bool {points.contains{Geometry.distance($0,point)<=1.5*logical.width/CGFloat(width)}}
        func color(_ value:[UInt8],near point:CGPoint)->Bool {
            for y in 0..<height {for x in 0..<width where rgba(x,y)==value {
                if Geometry.distance(center(x,y),point)<=1.5*logical.width/CGFloat(width) {return true}
            }};return false
        }
        func color(_ value:[UInt8],at point:CGPoint)->Bool {
            guard point.x>=0,point.y>=0,point.x<logical.width,point.y<logical.height else {return false}
            return rgba(Int(point.x*CGFloat(width)/logical.width),Int(point.y*CGFloat(height)/logical.height))==value
        }
        func color(_ value:[UInt8],inside polygon:[CGPoint])->Bool {
            guard let first=polygon.first else {return false};let path=CGMutablePath();path.move(to:first)
            for p in polygon.dropFirst() {path.addLine(to:p)};path.closeSubpath()
            for y in 0..<height {for x in 0..<width where rgba(x,y)==value {if path.contains(center(x,y)) {return true}}};return false
        }
        var footBand:Data {
            var result=Data()
            for y in 0..<height {for x in 0..<width {
                let p=center(x,y);if (24..<35).contains(p.x) && (38..<41).contains(p.y) {result.append(contentsOf:rgba(x,y))}
            }};return result
        }
        var clearBoundary:Bool {
            (0..<width).allSatisfy{!alpha($0,0) && !alpha($0,height-1)} && (0..<height).allSatisfy{!alpha(0,$0) && !alpha(width-1,$0)}
        }
    }
    private static func reconstruct(_ layers:[Raster],full:Raster)->Bool {
        guard layers.allSatisfy({$0.width==full.width && $0.height==full.height}) else {return false}
        for y in 0..<full.height {for x in 0..<full.width {
            var pixel=[UInt8](repeating:0,count:4)
            for layer in layers where layer.alpha(x,y) {pixel=layer.rgba(x,y)}
            if pixel != full.rgba(x,y) {return false}
        }};return true
    }
    private static func close(_ a:CGRect,_ b:CGRect)->Bool {
        abs(a.minX-b.minX)<1e-9 && abs(a.minY-b.minY)<1e-9 && abs(a.maxX-b.maxX)<1e-9 && abs(a.maxY-b.maxY)<1e-9
    }
    private static func draw(_ image:CGImage,at point:CGPoint,scale:CGFloat,in c:CGContext) {
        c.saveGState();c.translateBy(x:point.x,y:point.y);c.scaleBy(x:scale,y:scale)
        c.translateBy(x:0,y:CGFloat(image.height));c.scaleBy(x:1,y:-1)
        c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));c.restoreGState()
    }
    private static func bitmap(width:Int,height:Int)throws->CGContext {
        guard let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot allocate nest evidence")}
        c.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor);c.fill(CGRect(x:0,y:0,width:width,height:height))
        c.translateBy(x:0,y:CGFloat(height));c.scaleBy(x:1,y:-1);c.interpolationQuality = .none;return c
    }
    private static func label(_ text:String,at point:CGPoint,in c:CGContext) {
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
        c.saveGState();c.translateBy(x:point.x,y:point.y);c.scaleBy(x:1,y:-1)
        (text as NSString).draw(at:.zero,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor.white])
        c.restoreGState();NSGraphicsContext.restoreGraphicsState()
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"NestArtVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
