import AppKit
import BirdingCore

/// B14 art-only acceptance. The main session can call run(into:folder:) after
/// the complete development batch; this file does not register an entry point.
/// No desktop controller, windows, timers, engine state or user settings.
enum FeedingArtVerification {
    private static let species:[SpeciesID]=[.treeSparrow,.spottedDove]
    private static let names=["feedLook","feedDown0","feedDown1","feedLift"]
    private static let canvas=CGRect(x:0,y:0,width:48,height:48)
    private static let footBand=CGRect(x:24,y:38,width:10,height:3)

    private struct Raster {
        let width:Int,height:Int,stride:Int,bytes:[UInt8]
        init(_ image:CGImage) throws {
            guard image.bitsPerPixel == 32,image.bitsPerComponent == 8,
                  image.alphaInfo == .premultipliedLast,
                  let data=image.dataProvider?.data,let pointer=CFDataGetBytePtr(data) else {
                throw FeedingArtVerification.failure("Expected an RGBA native-art bitmap")
            }
            width=image.width;height=image.height;stride=image.bytesPerRow
            bytes=Array(UnsafeBufferPointer(start:pointer,count:CFDataGetLength(data)))
        }
        var unit:CGFloat {48/CGFloat(width)}
        func pixel(_ x:Int,_ y:Int)->[UInt8] {
            Array(bytes[(y*stride+x*4)..<(y*stride+x*4+4)])
        }
        func point(_ x:Int,_ y:Int)->CGPoint {
            CGPoint(x:(CGFloat(x)+0.5)*unit,y:(CGFloat(y)+0.5)*unit)
        }
        func alpha(_ p:CGPoint)->Bool {
            guard FeedingArtVerification.canvas.contains(p) else {return false}
            return bytes[Int(p.y/unit)*stride+Int(p.x/unit)*4+3]>0
        }
        func pixels(in rect:CGRect)->[UInt8] {
            var result=[UInt8]()
            for y in 0..<height {for x in 0..<width where rect.contains(point(x,y)) {
                result.append(contentsOf:pixel(x,y))
            }}
            return result
        }
        func opaque(in rect:CGRect=FeedingArtVerification.canvas)->[CGPoint] {
            var result=[CGPoint]()
            for y in 0..<height {for x in 0..<width where bytes[y*stride+x*4+3]>0 {
                let p=point(x,y)
                if rect.contains(p) {result.append(p)}
            }}
            return result
        }
        var centroid:CGPoint {
            let points=opaque()
            guard !points.isEmpty else {return CGPoint(x:-100,y:-100)}
            return CGPoint(x:points.map(\.x).reduce(0,+)/CGFloat(points.count),
                           y:points.map(\.y).reduce(0,+)/CGFloat(points.count))
        }
    }

    private struct Pose {
        let image:CGImage,full:Raster,body:Raster,feet:Raster,head:Raster,bill:Raster
        let images:[CGImage]
        init(_ name:String,_ art:BirdArt) throws {
            guard let image=art.frames[name] else {throw FeedingArtVerification.failure("Missing \(name)")}
            self.image=image;full=try Raster(image)
            var layers=[CGImage]()
            for part:DetailedBirdArt.FeedingPart in [.body,.feet,.headNeck,.bill] {
                guard let layer=DetailedBirdArt.feedingImage(name,species:art.species,part:part) else {
                    throw FeedingArtVerification.failure("Missing feeding semantic layer: \(name) / \(part)")
                }
                layers.append(layer)
            }
            images=layers;body=try Raster(layers[0]);feet=try Raster(layers[1])
            head=try Raster(layers[2]);bill=try Raster(layers[3])
        }
        var layersMatchFull:Bool {
            let layers=[body,feet,head,bill]
            guard layers.allSatisfy({$0.width==full.width && $0.height==full.height}) else {return false}
            for y in 0..<full.height {for x in 0..<full.width {
                var expected=[UInt8](repeating:0,count:4)
                for layer in layers {
                    let p=layer.pixel(x,y)
                    if p[3]>0 {expected=p}
                }
                if expected != full.pixel(x,y) {return false}
            }}
            return true
        }
    }

    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("feeding-art",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        checks["feedingArtFourOrderedNames"]=BirdArt.feedingNames==names && Set(names).count==4
        var manifestOK=true,supportedOnly=true
        for id in SpeciesID.allCases {
            let legacy=BirdArt.names+([SpeciesID.barnSwallow,.swinhoesWhiteEye].contains(id) ? BirdArt.allopreeningNames:[])
            let peek=SpeciesBehaviorProfile.peekSpecies.contains(id) ? BirdArt.peekNames:[]
            let prior=legacy+(species.contains(id) ? names:[])+SpeciesBehaviorProfile.profile(for:id).poseFrameNames+peek
            // Later authored packs append after feeding and enhanced poses;
            // every earlier index must remain unchanged, including pre-catch.
            let bath=[SpeciesID.treeSparrow,.lightVentedBulbul].contains(id)
                ? ["bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise"]:[]
            let carry=[SpeciesID.treeSparrow,.azureWingedMagpie].contains(id) ? ["carryLook","carryLower","carryGrip","carryPlace"]:[]
            let preCatch=prior+bath+carry
            let catchFrames=[SpeciesID.barnSwallow,.yellowRumpedFlycatcher].contains(id)
                ? ["catchOpen","catchClose","catchRecover"]:[]
            let actual=BirdArt.names(for:id)
            manifestOK = manifestOK && BirdArt.names.count==34 && actual==preCatch+catchFrames &&
                Array(actual.prefix(preCatch.count))==preCatch &&
                Array(actual.prefix(prior.count))==prior &&
                Array(actual.prefix(legacy.count))==legacy && Set(actual).count==actual.count
            supportedOnly = supportedOnly && Set(actual).intersection(names)==(species.contains(id) ? Set(names):Set<String>())
            if !species.contains(id) {
                supportedOnly = supportedOnly && names.allSatisfy {
                    DetailedBirdArt.feedingImage($0,species:id)==nil
                }
            }
        }
        checks["feedingArtAppendsAfterUnchangedCommon34AndAllopreeningIndices"]=manifestOK
        checks["feedingArtOnlyTreeSparrowAndSpottedDove"]=supportedOnly
        var evidence=[[String:Any]]()
        for id in species {
            let art=BirdArt(species:id),key="feedingArt-\(id.rawValue)-"
            let poses=try names.map {try Pose($0,art)}
            let stand=try Raster(art.frames["stand"]!)
            let old=try ["stand","idle0","idle1","idle2","peck0","peck1"].map {
                try Raster(art.frames[$0]!).pixels(in:canvas)
            }
            let pixels=poses.map {$0.full.pixels(in:canvas)}
            var distinct=true
            for a in pixels.indices {for b in pixels.indices where a<b {
                distinct = distinct && pixels[a] != pixels[b]
            }}
            checks[key+"fourDistinctNativeFramesWithoutOldPeckAliases"]=distinct &&
                pixels.allSatisfy {!old.contains($0)}
            checks[key+"semanticLayersReconstructActualSprite"]=poses.allSatisfy(\.layersMatchFull)
            checks[key+"nativeDensityMatchesStand"]=poses.allSatisfy {
                $0.full.width==stand.width && $0.full.height==stand.height
            }
            checks[key+"fixedFeetMatchStandAt2939Anchor"]=poses.allSatisfy {
                $0.feet.bytes==poses[0].feet.bytes &&
                    $0.full.pixels(in:footBand)==stand.pixels(in:footBand) &&
                    !$0.feet.opaque(in:CGRect(x:24,y:38,width:5,height:3)).isEmpty &&
                    !$0.feet.opaque(in:CGRect(x:29,y:38,width:5,height:3)).isEmpty &&
                    $0.feet.opaque(in:footBand).allSatisfy {$0.y<=39+stand.unit}
            }
            let target=CGPoint(x:40,y:39)
            var contact=true,headBends=true,footPlane=true,hitMatches=true
            for (index,name) in names.enumerated() {
                let pose=poses[index],bill=pose.bill.opaque(),head=pose.head.opaque()
                let nearTip=bill.filter {hypot($0.x-target.x,$0.y-target.y)<=1.5*pose.bill.unit}
                let actualTip=bill.min {hypot($0.x-target.x,$0.y-target.y)<hypot($1.x-target.x,$1.y-target.y)}
                if index==1 || index==2 {
                    // Tip samples must exist in the real bill AND production
                    // sprite, and no mandible may extend below the floor.
                    contact = contact && !nearTip.isEmpty && nearTip.allSatisfy {pose.full.alpha($0)} &&
                        bill.allSatisfy {$0.y<=39+pose.bill.unit}
                    let footY=pose.feet.opaque(in:footBand).map(\.y).max() ?? -100
                    footPlane = footPlane && nearTip.contains {abs($0.y-footY)<=1.5*pose.bill.unit}
                    headBends = headBends && pose.head.centroid.y>poses[0].head.centroid.y+6 &&
                        pose.head.centroid.y>poses[3].head.centroid.y+6 &&
                        pose.head.bytes != poses[0].head.bytes
                }
                var opaqueCount=0,clearCount=0
                for y in 0..<48 {for x in 0..<48 {
                    let alpha=pose.full.alpha(CGPoint(x:x,y:y))
                    hitMatches = hitMatches && art.contains(frame:name,x:x,y:y)==alpha
                    if alpha {opaqueCount+=1} else {clearCount+=1}
                }}
                hitMatches = hitMatches && opaqueCount>80 && clearCount>100 &&
                    !art.contains(frame:name,x:-1,y:20) && !art.contains(frame:name,x:48,y:20)
                try png(pose.image,to:output.appendingPathComponent("\(id.rawValue)-\(name).png"))
                evidence.append(["species":id.rawValue,"frame":name,"nativeSize":[pose.full.width,pose.full.height],
                    "footAnchor":[29,39],"intendedDownTip":[40,39],"downPose":index==1 || index==2,
                    "headNeckCentroid":[Double(pose.head.centroid.x),Double(pose.head.centroid.y)],
                    "headNeckOpaqueCount":head.count,"billOpaqueCount":bill.count,
                    "nearestBillPixelToGroundTarget":actualTip.map {[Double($0.x),Double($0.y)]} ?? [],
                    "billPixelsNearGroundTarget":nearTip.map {[Double($0.x),Double($0.y)]},
                    "footOpaquePixelCenters":pose.feet.opaque(in:footBand).map {[Double($0.x),Double($0.y)]}])
            }
            checks[key+"bothDownBillsHaveActualAlphaNear4039"]=contact && footPlane
            checks[key+"headAndNeckReallyBendTowardGround"]=headBends
            checks[key+"liftRaisesHeadAndBillForSwallow"]=poses[3].head.centroid.y<poses[0].head.centroid.y &&
                poses[3].bill.centroid.y<poses[0].bill.centroid.y-1 && poses[3].head.bytes != poses[0].head.bytes
            checks[key+"downPhasesArticulateHeadWithFixedFeet"]=poses[1].head.bytes != poses[2].head.bytes &&
                poses[1].bill.bytes != poses[2].bill.bytes && poses[1].feet.bytes==poses[2].feet.bytes
            checks[key+"hitMaskMatchesProductionAlpha"]=hitMatches
            try preview(art,poses:poses,to:output.appendingPathComponent("\(id.rawValue)-contact-sheet.png"))
        }
        let own=checks.filter {$0.key.hasPrefix("feedingArt")}
        let report:[String:Any]=["behavior":"B14","kind":"native-procedural-art-alpha-evidence",
            "logicalCanvas":[48,48],"footAnchor":[29,39],"downBillTip":[40,39],
            "coordinateSystem":"Logical top-down coordinates, facing right. Left-facing world offsets reflect x about foot x=29; ground target is foot.x +/- 11*scale at foot.y.",
            "tolerance":"Contact samples within 1.5 native pixels of (40,39); mandible at most one native pixel below y=39. Foot band y=38...41 matches stand exactly.",
            "checks":own,"passed":own.values.allSatisfy {$0},"frames":evidence,
            "contactSheets":species.map {"\($0.rawValue)-contact-sheet.png"},
            "scope":"Art only; no behavioral duration, prop placement or engine acceptance is claimed."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            .write(to:output.appendingPathComponent("geometry-alpha-evidence.json"),options:.atomic)
    }

    private static func preview(_ art:BirdArt,poses:[Pose],to url:URL) throws {
        let width=1280,height=920
        guard let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("Cannot create feeding contact sheet")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false)
        defer {NSGraphicsContext.restoreGraphicsState()}
        ctx.setFillColor(NSColor(calibratedRed:0.10,green:0.14,blue:0.17,alpha:1).cgColor)
        ctx.fill(CGRect(x:0,y:0,width:width,height:height))
        ctx.translateBy(x:0,y:CGFloat(height));ctx.scaleBy(x:1,y:-1);ctx.interpolationQuality = .none
        func label(_ text:String,_ x:CGFloat,_ y:CGFloat) {
            ctx.saveGState();ctx.translateBy(x:x,y:y);ctx.scaleBy(x:1,y:-1)
            (text as NSString).draw(at:.zero,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:12,weight:.medium),
                                                           .foregroundColor:NSColor.white])
            ctx.restoreGState()
        }
        label("\(art.species.rawValue) / B14 / body, feet, head-neck, bill / fixed foot (29,39)",20,22)
        for (index,name) in names.enumerated() {
            let row=CGFloat(index)*220+40,foot=CGPoint(x:145,y:row+165)
            label(name+" / 4x right + left / 1x",20,row+8)
            ctx.setStrokeColor(NSColor(calibratedWhite:0.4,alpha:1).cgColor);ctx.setLineWidth(1)
            ctx.move(to:CGPoint(x:18,y:foot.y));ctx.addLine(to:CGPoint(x:480,y:foot.y));ctx.strokePath()
            art.draw(name:name,at:foot,scale:4,right:true,context:ctx)
            art.draw(name:name,at:CGPoint(x:355,y:foot.y),scale:4,right:false,context:ctx)
            art.draw(name:name,at:CGPoint(x:453,y:foot.y),scale:1,right:true,context:ctx)
            ctx.setStrokeColor(NSColor.systemOrange.cgColor)
            for p in [CGPoint(x:foot.x+44,y:foot.y),CGPoint(x:355-44,y:foot.y)] {
                ctx.strokeEllipse(in:CGRect(x:p.x-5,y:p.y-5,width:10,height:10))
            }
            for layer in 0..<4 {
                let x=CGFloat(540+layer*180)
                label(["body / wing / tail","feet","head / neck","bill"][layer],x-45,row+8)
                draw(poses[index].images[layer],at:CGPoint(x:x,y:foot.y),scale:3,context:ctx)
            }
        }
        guard let image=ctx.makeImage() else {throw failure("Cannot finish feeding contact sheet")}
        try png(image,to:url)
    }
    private static func draw(_ image:CGImage,at foot:CGPoint,scale:CGFloat,context:CGContext) {
        context.saveGState();context.translateBy(x:foot.x,y:foot.y);context.scaleBy(x:scale,y:scale)
        context.translateBy(x:-29,y:-39);context.translateBy(x:0,y:48);context.scaleBy(x:1,y:-1)
        context.draw(image,in:canvas);context.restoreGState()
    }
    private static func png(_ image:CGImage,to url:URL) throws {
        guard let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {
            throw failure("Cannot encode \(url.lastPathComponent)")
        }
        try data.write(to:url,options:.atomic)
    }
    private static func failure(_ message:String)->NSError {
        NSError(domain:"FeedingArtVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }
}
