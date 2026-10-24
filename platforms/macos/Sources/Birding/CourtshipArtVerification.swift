import AppKit
import BirdingCore

/// Source art/metadata acceptance only. Does not create birds, infer sex or
/// certify a completed encounter. Main owns running this after the full batch.
enum CourtshipArtVerification {
    private static let id=SpeciesID.spottedDove
    private static let prefix="m7aCourtshipArt-"
    private static let names=["courtRaise","courtBow0","courtBow1","courtBowRecover","courtObserve"]
    private static let parts:[DetailedBirdArt.FoundationPosePart]=[.body,.feet,.headNeck,.bill]

    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("courtship-art",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let art=BirdArt(species:id)
        guard let stand=art.frames["stand"] else {throw failure("Missing dove stand")}
        let prior=BirdArt.names+BirdArt.feedingNames+PoseClip.frameNames
        let historical=try prior.map {name -> Raster in
            guard let image=art.frames[name] else {throw failure("Missing historical dove frame: "+name)}
            return try Raster(image)
        }
        let grounded=try Raster(stand)
        let palette=try Raster(DetailedBirdArt.courtshipCollarPaletteImage())
        let collarBlack=palette.rgba(16,32),collarWhite=palette.rgba(48,32)
        var unique=Set<Data>(),images=[[CGImage]](),bodies=[Data](),feet:Data?,evidence=[[String:Any]]()
        let intended=[CGPoint(x:39.5,y:13),CGPoint(x:41,y:24),CGPoint(x:41.5,y:30),CGPoint(x:40,y:19),CGPoint(x:38.5,y:16)]
        for (index,name) in names.enumerated() {
            guard let image=art.frames[name],let source=DetailedBirdArt.courtshipImage(name,species:id),
                  let generic=DetailedBirdArt.poseImage(name,species:id),
                  let point=DetailedBirdArt.poseBillAnchor(name,species:id),
                  let pose=CourtshipArtGeometry.pose(species:id,frame:name) else {throw failure("Missing courtship source: "+name)}
            let full=try Raster(image),authored=try Raster(source),genericRaster=try Raster(generic)
            let layerImages=try parts.map {part -> CGImage in
                guard let layer=DetailedBirdArt.courtshipImage(name,species:id,part:part) else {throw failure("Missing courtship semantic part")}
                return layer
            }
            let layers=try layerImages.map{try Raster($0)},key=prefix+name+"-"
            checks[key+"IndependentNativeSource"]=full.pixels==authored.pixels && full.pixels==genericRaster.pixels &&
                unique.insert(full.pixels).inserted && !historical.contains{$0.pixels==full.pixels}
            checks[key+"NativeSixtyFourAndFourParts"]=image.width==64 && image.height==64 && image.width==stand.width &&
                layers.allSatisfy{$0.width==64 && $0.height==64 && !$0.points.isEmpty}
            checks[key+"LayersReconstructProduction"]=reconstruct(layers,equals:full)
            checks[key+"OutlineInsideCanvasAndNeckAboveFeet"]=layers.allSatisfy(\.clearBoundary) &&
                layers[2].points.allSatisfy{$0.y<38} && layers[3].points.allSatisfy{$0.y<38}
            if feet==nil {feet=layers[1].pixels}
            checks[key+"SameFixedFeetAndStandFootBand"]=layers[1].pixels==feet && full.footBand==grounded.footBand &&
                !layers[1].points.filter{(24...29).contains($0.x) && $0.y>=38}.isEmpty &&
                !layers[1].points.filter{(29...34).contains($0.x) && $0.y>=38}.isEmpty
            let anchor=PoseClip.beakAnchor(species:id,frame:name),target=intended[index]
            let error=hypot(point.x-CGFloat(anchor.x),point.y-CGFloat(anchor.y))
            checks[key+"RealBillTargetAndMirror"]=error<1e-9 && hypot(point.x-target.x,point.y-target.y)<1e-9 &&
                layers[3].alpha(near:point) && anchor.mirrored(facingRight:false)==PoseClip.Anchor(48-anchor.x,anchor.y)
            let collarGeometry=pose.collar.count==4 && pose.collarSpots.count==5 &&
                pose.collar.allSatisfy{$0.x>0 && $0.x<48 && $0.y>0 && $0.y<38}
            let collarBlackPresent=layers[2].containsColor(collarBlack,inside:pose.collar)
            let collarSpotAlpha=pose.collarSpots.map{layers[2].alpha(near:$0)}
            let collarSpotWhite=pose.collarSpots.map{layers[2].containsColor(collarWhite,near:$0)}
            let collarDiagnostics:[String:Any]=["geometryValid":collarGeometry,"blackInsideCollar":collarBlackPresent,
                "spotAlpha":collarSpotAlpha,"spotWhite":collarSpotWhite]
            checks[key+"CollarTracksContinuousNeckSurface"]=collarGeometry && collarBlack != collarWhite &&
                collarBlack[3]==255 && collarWhite[3]==255 && collarBlackPresent &&
                collarSpotAlpha.allSatisfy{$0} && collarSpotWhite.allSatisfy{$0}
            checks[key+"ProductionHitMask"]=(0..<48).allSatisfy {y in (0..<48).allSatisfy {x in
                art.contains(frame:name,x:x,y:y)==full.alpha(x*full.width/48,y*full.height/48)
            }} && !art.contains(frame:name,x:-1,y:20) && !art.contains(frame:name,x:48,y:20)
            bodies.append(layers[0].pixels);images.append([image]+layerImages)
            evidence.append(["frame":name,"nativeSize":[image.width,image.height],"beak":[Double(point.x),Double(point.y)],
                "anchorError":error,"foot":[29,39],"bodyPitch":pose.bodyPitch,"headPitch":pose.headPitch,
                "body":[pose.body.minX,pose.body.minY,pose.body.width,pose.body.height],
                "collar":pose.collar.map{[Double($0.x),Double($0.y)]},
                "collarSpots":pose.collarSpots.map{[Double($0.x),Double($0.y)]},
                "collarDiagnostics":collarDiagnostics])
        }
        checks[prefix+"ExactlyFiveAfterUnchangedFortyEightPrefix"]=prior.count==48 && unique.count==5 &&
            BirdArt.courtshipNames==names && CourtshipArtGeometry.frameNames==names &&
            BirdArt.names(for:id)==prior+names+NestArtGeometry.frameNames && Array(BirdArt.names(for:id).prefix(48))==prior
        checks[prefix+"TorsoWingTailIndependentlyChange"]=Set(bodies).count==5
        checks[prefix+"OnlySpottedDoveProvided"]=CourtshipArtGeometry.species==[id] &&
            SpeciesBehaviorProfile.species(for:.courtshipDisplay)==[id] && SpeciesID.allCases.filter{$0 != id}.allSatisfy {species in
                Set(BirdArt.names(for:species)).isDisjoint(with:names) &&
                    names.allSatisfy{DetailedBirdArt.courtshipImage($0,species:species)==nil} &&
                    PoseClip.courtship(species:species,role:.initiator)==nil && PoseClip.courtship(species:species,role:.observer)==nil
            }
        guard let initiator=PoseClip.courtship(species:id,role:.initiator),
              let observer=PoseClip.courtship(species:id,role:.observer) else {throw failure("Missing role clips")}
        checks[prefix+"BothRolesRequireWholePackAndCurrentStateRecovery"]=[initiator,observer].allSatisfy {
            $0.requiredFrames==Set(names+["stand"]) && $0.foot==PoseClip.footAnchor && $0.maximumLoops==1 &&
                $0.recovery == .currentEngineState && abs($0.duration-4)<1e-9
        } && Set(names).isSubset(of:SpeciesBehaviorProfile.profile(for:id).requiredFrames(for:.courtshipDisplay))
        checks[prefix+"ExactInitiatorSequence"]=initiator.frames.map(\.name)==["stand","courtRaise","courtBow0","courtBow1","courtBowRecover","courtBow0","courtBow1","courtBowRecover","courtBowRecover","courtBowRecover"] &&
            initiator.frames.map(\.duration)==[0.4,0.5,0.35,0.4,0.25,0.35,0.4,0.25,0.5,0.6]
        checks[prefix+"ObserverOnlyTurnsInOwnHalfSecond"]=observer.frames.map(\.name)==["stand","stand","stand","courtObserve","stand"] &&
            observer.frames.map(\.duration)==[0.4,0.5,2,0.5,0.6] && observer.sample(at:2.89)?.name=="stand" &&
            observer.sample(at:2.9)?.name=="courtObserve" && observer.sample(at:3.4)?.name=="stand" && observer.sample(at:4)==nil
        guard let standBill=CourtshipArtGeometry.billAnchor(species:id,frame:"stand") else {throw failure("Missing real stand bill")}
        checks[prefix+"OrdinaryStandBillUsesUnchangedDrawing"]=standBill==CGPoint(x:40.5,y:17.5) && grounded.alpha(near:standBill)
        let metadata=BirdArt.poseMetadata[id.rawValue] as? [String:Any] ?? [:]
        let anchors=metadata["courtshipBeakAnchors"] as? [String:[Double]] ?? [:]
        let clips=metadata["clips"] as? [String:Any] ?? [:]
        checks[prefix+"RoleMetadataAndSixSharedBillAnchors"]=Set(anchors.keys)==Set(names+["stand"]) &&
            Set(clips.keys)==Set(["watch","alert","rest","takeoffPreparation","courtshipInitiator","courtshipObserver",
                "nestMaterialPickup","nestMaterialPlace","nestBuild"]) &&
            names.allSatisfy {name in
                guard let point=CourtshipArtGeometry.billAnchor(species:id,frame:name),let pair=anchors[name],pair.count==2 else {return false}
                return abs(pair[0]-Double(point.x))<1e-9 && abs(pair[1]-Double(point.y))<1e-9
            }
        checks[prefix+"ExistingThirteenPreviewSpeciesAndSeventyEightFiles"]=BirdArt.poseExportSpecies.count==13 &&
            Set(BirdArt.poseExportSpecies).count==13 && BirdArt.poseExportSpecies.contains(id)
        for right in [true,false] {try sheet(images,right:right,to:output.appendingPathComponent("spottedDove-courtship-source-\(right ? "right":"left").png"))}
        for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
            let birdScale=scale*SpeciesCatalog.standard.profile(id).relativeScale
            let a=CGPoint(x:300,y:200),b=CGPoint(x:300+58*birdScale+12,y:200)
            let first=Geometry.landingFootprint(at:a,scale:birdScale),second=Geometry.landingFootprint(at:b,scale:birdScale)
            var contained=true
            for index in names.indices {
                let pixels=try Raster(images[index][0]),foot=right ? a:b
                for point in pixels.points {
                    let world=PoseClip.Anchor(Double(point.x),Double(point.y)).world(foot:foot,scale:birdScale,facingRight:right)
                    contained = contained && (right ? first:second).contains(world)
                }
            }
            checks[prefix+"BothFacingCanvasUnionAndTwelvePointClearance-\(scale)-\(right)"]=contained &&
                !first.intersects(second) && abs(second.minX-first.maxX-12)<1e-9
            try preview(art,initiator:initiator,observer:observer,scale:scale,right:right,
                to:output.appendingPathComponent("spottedDove-courtship-\(scale)x-\(right ? "right":"left")-pair.png"))
        }}
        let own=checks.filter{$0.key.hasPrefix(prefix)}
        saveJSON(["scope":"M7a source art, role clip timing and metadata only; not actual two-resident admission or completion.",
            "passed":!own.isEmpty && own.values.allSatisfy{$0},"checks":own,"frames":evidence,
            "collarPaletteRGBA":["black":collarBlack,"white":collarWhite],
            "foot":[29,39],"nativeSize":[64,64],"logicalSize":[48,48],"roleDuration":4,
            "limits":"Static pair layouts and source alpha do not replace continuous production layers at 0.5x/1x/2x, interruption checks or physical desktop acceptance."],
            to:output.appendingPathComponent("report.json"))
    }

    private struct Raster {
        let pixels:Data,width:Int,height:Int,stride:Int,bytes:[UInt8]
        init(_ image:CGImage) throws {
            let value=try BathArtVerification.Raster(image)
            pixels=value.pixels;width=value.width;height=value.height;stride=value.stride;bytes=value.bytes
        }
        var unit:CGFloat {48/CGFloat(width)}
        func rgba(_ x:Int,_ y:Int)->[UInt8] {Array(bytes[(y*stride+x*4)..<(y*stride+x*4+4)])}
        func alpha(_ x:Int,_ y:Int)->Bool {bytes[y*stride+x*4+3]>0}
        var points:[CGPoint] {
            var value=[CGPoint]()
            for y in 0..<height {for x in 0..<width where alpha(x,y) {
                value.append(CGPoint(x:(CGFloat(x)+0.5)*unit,y:(CGFloat(y)+0.5)*unit))
            }}
            return value
        }
        func alpha(near point:CGPoint)->Bool {points.contains{hypot($0.x-point.x,$0.y-point.y)<=1.5*unit}}
        /// Match exact raster bytes after the source painter's color conversion,
        /// restricted to the collar, rather than any dark pixel in the head.
        func containsColor(_ color:[UInt8],inside polygon:[CGPoint])->Bool {
            guard let first=polygon.first else {return false}
            let path=CGMutablePath();path.move(to:first)
            for point in polygon.dropFirst() {path.addLine(to:point)}
            path.closeSubpath()
            for y in 0..<height {for x in 0..<width {
                let point=CGPoint(x:(CGFloat(x)+0.5)*unit,y:(CGFloat(y)+0.5)*unit)
                if rgba(x,y)==color && path.contains(point) {return true}
            }}
            return false
        }
        /// Every authored spot must retain nearby white raster, not merely an
        /// opaque neck or the eye highlight elsewhere in the semantic layer.
        func containsColor(_ color:[UInt8],near point:CGPoint)->Bool {
            for y in 0..<height {for x in 0..<width {
                let center=CGPoint(x:(CGFloat(x)+0.5)*unit,y:(CGFloat(y)+0.5)*unit)
                if rgba(x,y)==color && hypot(center.x-point.x,center.y-point.y)<=1.5*unit {return true}
            }}
            return false
        }
        var clearBoundary:Bool {
            (0..<width).allSatisfy{!alpha($0,0) && !alpha($0,height-1)} &&
                (0..<height).allSatisfy{!alpha(0,$0) && !alpha(width-1,$0)}
        }
        var footBand:Data {
            var result=Data()
            for y in 0..<height where (38..<41).contains((CGFloat(y)+0.5)*unit) {
                for x in 0..<width where (24..<35).contains((CGFloat(x)+0.5)*unit) {result.append(contentsOf:rgba(x,y))}
            }
            return result
        }
    }
    private static func reconstruct(_ layers:[Raster],equals full:Raster)->Bool {
        guard layers.allSatisfy({$0.width==full.width && $0.height==full.height}) else {return false}
        for y in 0..<full.height {for x in 0..<full.width {
            var pixel=[UInt8](repeating:0,count:4)
            for layer in layers {let p=layer.rgba(x,y);if p[3]>0 {pixel=p}}
            if pixel != full.rgba(x,y) {return false}
        }}
        return true
    }
    private static func sheet(_ frames:[[CGImage]],right:Bool,to url:URL) throws {
        let c=try bitmap(width:1250,height:900)
        label("spottedDove / M7a / raw source / \(right ? "right":"left") / fixed foot (29,39)",at:CGPoint(x:15,y:14),in:c)
        for (column,title) in ["production","body / wings / tail","feet","head / neck / collar","bill"].enumerated() {
            label(title,at:CGPoint(x:CGFloat(140+column*215),y:36),in:c)
        }
        for (row,layers) in frames.enumerated() {for (column,image) in layers.enumerated() {
            if column==0 {label(names[row],at:CGPoint(x:10,y:CGFloat(95+row*166)),in:c)}
            c.saveGState();c.translateBy(x:CGFloat(140+column*215),y:CGFloat(57+row*166))
            if !right {c.translateBy(x:144,y:0);c.scaleBy(x:-1,y:1)}
            c.translateBy(x:0,y:144);c.scaleBy(x:1,y:-1)
            c.draw(image,in:CGRect(x:0,y:0,width:144,height:144));c.restoreGState()
        }}
        try BathVerification.writePNG(c,to:url)
    }
    private static func preview(_ art:BirdArt,initiator:PoseClip,observer:PoseClip,scale:CGFloat,right:Bool,to url:URL) throws {
        let size=scale*SpeciesCatalog.standard.profile(id).relativeScale,gap=58*size+12
        let row=max(130,Int(ceil(48*size))+50),c=try bitmap(width:860,height:row*7+30)
        let ages=[0.2,0.6,1.0,1.4,1.8,3.1,3.7]
        for (index,age) in ages.enumerated() {
            let y=CGFloat(index*row)+39*size+30,left=CGPoint(x:430-gap/2,y:y),rightFoot=CGPoint(x:430+gap/2,y:y)
            let first=initiator.sample(at:age)?.name ?? "stand",second=observer.sample(at:age)?.name ?? "stand"
            label("\(scale)x / age \(age) / \(first) + \(second) / 12pt union gap",at:CGPoint(x:15,y:CGFloat(index*row+14)),in:c)
            c.setStrokeColor(NSColor.gray.cgColor);c.move(to:CGPoint(x:180,y:y));c.addLine(to:CGPoint(x:680,y:y));c.strokePath()
            art.draw(name:first,at:right ? left:rightFoot,scale:size,right:right,context:c)
            art.draw(name:second,at:right ? rightFoot:left,scale:size,right:!right,context:c)
        }
        try BathVerification.writePNG(c,to:url)
    }
    private static func bitmap(width:Int,height:Int)throws->CGContext {
        guard let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot allocate courtship evidence")}
        c.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor);c.fill(CGRect(x:0,y:0,width:width,height:height))
        c.translateBy(x:0,y:CGFloat(height));c.scaleBy(x:1,y:-1);c.interpolationQuality = .none
        return c
    }
    private static func label(_ text:String,at point:CGPoint,in c:CGContext) {
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
        c.saveGState();c.translateBy(x:point.x,y:point.y);c.scaleBy(x:1,y:-1)
        (text as NSString).draw(at:.zero,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor.white])
        c.restoreGState();NSGraphicsContext.restoreGraphicsState()
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"CourtshipArtVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
