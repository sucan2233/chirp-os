import AppKit
import BirdingCore

/// Editable-source acceptance only. Real gift authorization, journeys and
/// production layers belong to the separate core/platform acceptance suites.
enum VisitorGiftArtVerification {
    private static let id=SpeciesID.azureWingedMagpie
    private static let prefix="m6gCarryArt-"
    private static let parts:[DetailedBirdArt.FoundationPosePart]=[.body,.feet,.headNeck,.bill]

    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let art=BirdArt(species:id),names=CarryArtGeometry.frameNames
        let output=folder.appendingPathComponent("visitor-gift-art",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        guard let stand=art.frames["stand"] else {throw failure("Missing magpie stand")}
        let old=try art.frames.filter{!names.contains($0.key)}.values.map{try Raster($0)}
        let grounded=try Raster(stand)
        var distinct=Set<Data>(),images=[[CGImage]](),evidence=[[String:Any]](),pickupFeet:Data?
        for name in names {
            guard let image=art.frames[name],let source=DetailedBirdArt.carryImage(name,species:id),
                  let pose=CarryArtGeometry.pose(species:id,frame:name),
                  let anchor=PoseClip.carryBeakAnchor(species:id,frame:name) else {throw failure("Missing magpie carry source: "+name)}
            let full=try Raster(image),authored=try Raster(source)
            let layerImages=try parts.map {part -> CGImage in
                guard let value=DetailedBirdArt.carryImage(name,species:id,part:part) else {throw failure("Missing magpie semantic layer")}
                return value
            }
            let layers=try layerImages.map{try Raster($0)}
            let key=prefix+name+"-"
            checks[key+"IndependentNativeSource"]=full.pixels==authored.pixels &&
                distinct.insert(full.pixels).inserted && !old.contains(where:{$0.pixels==full.pixels})
            checks[key+"NativeDensityAndFourParts"]=image.width==stand.width && image.height==stand.height &&
                layers.allSatisfy{$0.width==full.width && $0.height==full.height && $0.hasAlpha}
            checks[key+"SemanticLayersReconstructSprite"]=reconstruct(layers,equals:full)
            checks[key+"WingTailAndNeckRemainInsideCanvas"]=layers[0].clearBoundary &&
                layers[2].opaquePoints.allSatisfy{$0.y<39}
            let error=hypot(CGFloat(anchor.x)-pose.billTip.x,CGFloat(anchor.y)-pose.billTip.y)
            checks[key+"RealUpperBillTipAndMirror"]=error<1e-9 && layers[3].hasAlpha(near:pose.billTip) &&
                anchor.mirrored(facingRight:false)==PoseClip.Anchor(48-anchor.x,anchor.y)
            if pose.release {
                checks[key+"AerialReleaseAt4223WithTuckedFeet"]=hypot(pose.billTip.x-42,pose.billTip.y-23)<1e-9 &&
                    layers[1].opaquePoints.allSatisfy{$0.y<34} && layers[0].opaquePoints.contains{$0.y<10}
            } else {
                if pickupFeet==nil {pickupFeet=layers[1].pixels}
                checks[key+"FixedPickupToesAtReferenceFoot"]=layers[1].pixels==pickupFeet &&
                    full.footBand==grounded.footBand && !layers[1].footBand.allSatisfy{$0==0}
                if name=="carryGrip" {
                    checks[key+"GroundContactAt4039"]=hypot(pose.billTip.x-40,pose.billTip.y-39)<1e-9 &&
                        layers[3].opaquePoints.allSatisfy{$0.y<39+layers[3].unit}
                }
            }
            checks[key+"ProductionHitAlpha"]=(0..<48).allSatisfy {y in (0..<48).allSatisfy {x in
                let px=x*full.width/48,py=y*full.height/48
                return art.contains(frame:name,x:x,y:y)==(full.bytes[py*full.stride+px*4+3]>0)
            }} && !art.contains(frame:name,x:-1,y:20) && !art.contains(frame:name,x:48,y:20)
            images.append([image]+layerImages)
            evidence.append(["frame":name,"nativeSize":[image.width,image.height],
                "beak":[Double(pose.billTip.x),Double(pose.billTip.y)],"anchorError":error,
                "referenceFoot":[29,39],"feet":pose.release ? "airborne and tucked":"fixed pickup contact"])
        }
        checks[prefix+"FourNewPosesAfterAllHistoricalFortyFour"]=distinct.count==4 &&
            BirdArt.names(for:id)==BirdArt.names+PoseClip.frameNames+names && BirdArt.names(for:id).count==48
        let pickup=PoseClip.visitorGiftPickup(species:id),release=PoseClip.visitorGiftRelease(species:id)
        checks[prefix+"DedicatedPickupAndAerialReleaseClips"]=pickup?.frames.map(\.name)==["carryLook","carryLower","carryGrip","carryLook"] &&
            abs((pickup?.duration ?? 0)-1.2)<1e-9 && release?.frames.map(\.name)==["carryPlace"] &&
            abs((release?.duration ?? 0)-0.3)<1e-9 && pickup?.foot==PoseClip.footAnchor && release?.foot==PoseClip.footAnchor
        checks[prefix+"GiftPermissionDoesNotGrantLeafCarryOrPerch"]=SpeciesBehaviorProfile.species(for:.visitorGift)==[id] &&
            SpeciesBehaviorProfile.species(for:.leafCarry)==[.treeSparrow] &&
            !SpeciesBehaviorProfile.profile(for:id).allows(.fixedPerchVisit) && PoseClip.leafCarryPickup(species:id)==nil &&
            PoseClip.leafCarryPlace(species:id)==nil
        checks[prefix+"GiftRequiresTheWholeFourFramePack"]=Set(names).isSubset(of:SpeciesBehaviorProfile.profile(for:id).requiredFrames(for:.visitorGift))
        checks[prefix+"NoUnprovidedCarrierArt"]=SpeciesID.allCases.filter{!CarryArtGeometry.species.contains($0)}.allSatisfy {species in
            names.allSatisfy{DetailedBirdArt.carryImage($0,species:species)==nil && PoseClip.carryBeakAnchor(species:species,frame:$0)==nil}
        }
        for name in TransportArtGeometry.frameNames {
            guard let image=art.frames[name],let point=DetailedBirdArt.transportBillAnchor(name,species:id),
                  let anchor=PoseClip.carryBeakAnchor(species:id,frame:name) else {throw failure("Missing magpie transport: "+name)}
            let pixels=try Raster(image),error=hypot(point.x-CGFloat(anchor.x),point.y-CGFloat(anchor.y))
            checks[prefix+name+"-RealTransportBill"]=error<1e-9 && pixels.hasAlpha(near:point)
            evidence.append(["transportFrame":name,"beak":[Double(point.x),Double(point.y)],"anchorError":error])
        }
        let metadata=BirdArt.poseMetadata[id.rawValue] as? [String:Any] ?? [:]
        let anchors=metadata["transportBeakAnchors"] as? [String:[Double]] ?? [:]
        let clips=metadata["clips"] as? [String:Any] ?? [:]
        checks[prefix+"MetadataIncludesExactlyTwentyThreeCarryAndTransportAnchors"]=Set(anchors.keys)==Set(names+TransportArtGeometry.frameNames) &&
            Set(clips.keys)==Set(["watch","alert","rest","takeoffPreparation","visitorGiftPickup","visitorGiftRelease"])
        var unionEvidence=[[String:Any]]()
        for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
            let birdScale=scale*SpeciesCatalog.standard.profile(id).relativeScale
            var unionMatches=true
            for name in names+TransportArtGeometry.frameNames {
                guard let anchor=PoseClip.carryBeakAnchor(species:id,frame:name) else {throw failure("Missing union anchor")}
                let grip=anchor.world(foot:.zero,scale:birdScale,facingRight:right)
                for rotation:CGFloat in [-0.3,0,0.3] {for leafRight in [true,false] {
                    guard let bounds=CarryArtGeometry.leafBounds(grip:grip,worldScale:scale,facingRight:leafRight,rotation:rotation) else {throw failure("Invalid leaf bounds")}
                    let actual=CarriedObjectGeometry.bounds(position:grip,anchor:CarryArtGeometry.leafGripAnchor,
                        worldScale:scale,facingRight:leafRight,rotation:rotation)
                    let same=zip([bounds.minX,bounds.minY,bounds.maxX,bounds.maxY],
                                 [actual.minX,actual.minY,actual.maxX,actual.maxY]).allSatisfy{abs($0.0-$0.1)<1e-8}
                    unionMatches = unionMatches && same &&
                        (rotation != 0 || abs(bounds.width-16*scale)<1e-9 && abs(bounds.height-16*scale)<1e-9)
                    let union=Geometry.landingFootprint(at:.zero,scale:birdScale).union(actual)
                    unionEvidence.append(["frame":name,"worldScale":scale,"birdScale":birdScale,"birdRight":right,
                        "leafRight":leafRight,"rotation":rotation,"union":[union.minX,union.minY,union.width,union.height]])
                }}
            }
            checks[prefix+"LeafWorldScaleAndUnion-\(scale)-\(right)"]=unionMatches
            try preview(art,scale:scale,right:right,to:output.appendingPathComponent("azureWingedMagpie-carry-\(scale)x-\(right ? "right":"left")-preview.png"))
        }}
        for right in [true,false] {try sheet(images,right:right,to:output.appendingPathComponent("azureWingedMagpie-carry-source-\(right ? "right":"left").png"))}
        for scale:CGFloat in [0.5,1,2] {
            let area=CGRect(x:0,y:0,width:2000,height:1600)
            let world=BehaviorWorld(screens:[area],displays:[area],scale:scale,displayIDs:["m6g-art"])
            let anchor=FixedPerchAnchor(slot:1,displayID:"m6g-art",displayFrame:area,x:0.5,y:0.5)
            guard let perch=FixedPerchLayout.resolve(anchors:[anchor],world:world).first,
                  let perchArt=FixedPerchArt.shared else {throw failure("Missing real fixed-perch rail geometry")}
            let rect=perchArt.rect(for:perch),receiver=GiftReceiverGeometry.anchor(on:perch)
            let rail=CGPoint(x:rect.midX,y:rect.minY+perchArt.railY*rect.width/CGFloat(perchArt.image.width))
            checks[prefix+"ReceiverMatchesActualCroppedRail-\(scale)"]=receiver==perch.foot &&
                hypot(receiver.x-rail.x,receiver.y-rail.y)<1e-9
        }
        let own=checks.filter{$0.key.hasPrefix(prefix)}
        saveJSON(["scope":"Raw source/metadata and conservative bird-token geometry; not real gift journeys or authorization.",
            "passed":own.values.allSatisfy{$0},"checks":own,"frames":evidence,"bodyLeafUnions":unionEvidence,
            "referenceFoot":[29,39],"pickupBill":[40,39],"releaseBill":[42,23],
            "receiverAnchor":"resolvedFixedPerch.foot; no carrier landing permission"],to:output.appendingPathComponent("report.json"))
    }

    private struct Raster {
        let pixels:Data,width:Int,height:Int,stride:Int,bytes:[UInt8]
        init(_ image:CGImage) throws {
            let value=try BathArtVerification.Raster(image)
            pixels=value.pixels;width=value.width;height=value.height;stride=value.stride;bytes=value.bytes
        }
        var unit:CGFloat {48/CGFloat(width)}
        func rgba(_ x:Int,_ y:Int)->[UInt8] {Array(bytes[(y*stride+x*4)..<(y*stride+x*4+4)])}
        var opaquePoints:[CGPoint] {
            var points=[CGPoint]()
            for y in 0..<height {for x in 0..<width where bytes[y*stride+x*4+3]>0 {
                points.append(CGPoint(x:(CGFloat(x)+0.5)*unit,y:(CGFloat(y)+0.5)*unit))
            }}
            return points
        }
        var hasAlpha:Bool {bytes.enumerated().contains{$0.offset%4==3 && $0.element>0}}
        var clearBoundary:Bool {
            (0..<width).allSatisfy{bytes[$0*4+3]==0 && bytes[(height-1)*stride+$0*4+3]==0} &&
                (0..<height).allSatisfy{bytes[$0*stride+3]==0 && bytes[$0*stride+(width-1)*4+3]==0}
        }
        var footBand:Data {
            var result=Data()
            for y in 0..<height where (CGFloat(y)+0.5)*unit>=38 && (CGFloat(y)+0.5)*unit<41 {
                for x in 0..<width where (24..<35).contains((CGFloat(x)+0.5)*unit) {result.append(contentsOf:rgba(x,y))}
            }
            return result
        }
        func hasAlpha(near point:CGPoint)->Bool {opaquePoints.contains{hypot($0.x-point.x,$0.y-point.y)<=1.5*unit}}
    }
    private static func reconstruct(_ layers:[Raster],equals full:Raster)->Bool {
        guard layers.allSatisfy({$0.width==full.width && $0.height==full.height}) else {return false}
        for y in 0..<full.height {for x in 0..<full.width {
            var pixel=[UInt8](repeating:0,count:4)
            for layer in layers {let sample=layer.rgba(x,y);if sample[3]>0 {pixel=sample}}
            if pixel != full.rgba(x,y) {return false}
        }}
        return true
    }
    private static func sheet(_ frames:[[CGImage]],right:Bool,to url:URL) throws {
        let context=try bitmap(width:1200,height:720)
        label("azureWingedMagpie / raw source / "+(right ? "right":"left"),at:CGPoint(x:15,y:12),in:context)
        for (i,title) in ["production","body / wings / tail","feet","head / neck","bill"].enumerated() {
            label(title,at:CGPoint(x:CGFloat(140+i*210),y:32),in:context)
        }
        for (row,layers) in frames.enumerated() {for (column,image) in layers.enumerated() {
            if column==0 {label(CarryArtGeometry.frameNames[row],at:CGPoint(x:10,y:CGFloat(90+row*165)),in:context)}
            context.saveGState();context.translateBy(x:CGFloat(140+column*210),y:CGFloat(55+row*165))
            if !right {context.translateBy(x:144,y:0);context.scaleBy(x:-1,y:1)}
            context.translateBy(x:0,y:144);context.scaleBy(x:1,y:-1)
            context.draw(image,in:CGRect(x:0,y:0,width:144,height:144));context.restoreGState()
        }}
        try BathVerification.writePNG(context,to:url)
    }
    private static func preview(_ art:BirdArt,scale:CGFloat,right:Bool,to url:URL) throws {
        let birdScale=scale*SpeciesCatalog.standard.profile(id).relativeScale
        let row=max(140,Int(ceil(48*birdScale))+40),context=try bitmap(width:780,height:row*4+30)
        for (i,name) in CarryArtGeometry.frameNames.enumerated() {
            let foot=CGPoint(x:350,y:CGFloat(i*row+20)+39*birdScale)
            label("\(name) / \(scale)x / \(right ? "right":"left") / separate world-scaled leaf",at:CGPoint(x:15,y:CGFloat(i*row+10)),in:context)
            art.draw(name:name,at:foot,scale:birdScale,right:right,context:context)
            if let anchor=PoseClip.carryBeakAnchor(species:id,frame:name) {
                let grip=anchor.world(foot:foot,scale:birdScale,facingRight:right)
                context.saveGState();context.translateBy(x:grip.x,y:grip.y)
                context.scaleBy(x:right ? scale:-scale,y:scale)
                context.translateBy(x:-3,y:-12);context.translateBy(x:0,y:16);context.scaleBy(x:1,y:-1)
                context.draw(CarryArt.leafImage(),in:CGRect(x:0,y:0,width:16,height:16));context.restoreGState()
            }
        }
        try BathVerification.writePNG(context,to:url)
    }
    private static func label(_ text:String,at point:CGPoint,in context:CGContext) {
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        context.saveGState();context.translateBy(x:point.x,y:point.y);context.scaleBy(x:1,y:-1)
        (text as NSString).draw(at:.zero,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor.white])
        context.restoreGState();NSGraphicsContext.restoreGraphicsState()
    }
    private static func bitmap(width:Int,height:Int)throws->CGContext {
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot allocate magpie art sheet")}
        context.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor)
        context.fill(CGRect(x:0,y:0,width:width,height:height));context.translateBy(x:0,y:CGFloat(height));context.scaleBy(x:1,y:-1)
        context.interpolationQuality = .none
        return context
    }
    private static func failure(_ message:String)->NSError {NSError(domain:"VisitorGiftArtVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
}
