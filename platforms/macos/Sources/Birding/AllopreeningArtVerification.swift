import AppKit
import BirdingCore

// Procedural-art inspection only: no desktop windows, screenshots or timers.
// Called by ExpandedVerification after the complete development batch is ready.
enum AllopreeningArtVerification {
    private static let species:[SpeciesID]=[.barnSwallow,.swinhoesWhiteEye]
    private static let names=["allopreenGive0","allopreenGive1","allopreenGive2",
                              "allopreenReceive0","allopreenReceive1","allopreenReceive2"]
    private static let canvas=CGRect(x:0,y:0,width:48,height:48)
    private struct Raster {
        let width:Int,height:Int,stride:Int,bytes:[UInt8]
        init(_ image:CGImage) throws {
            guard image.bitsPerPixel == 32,let data=image.dataProvider?.data,
                  let pointer=CFDataGetBytePtr(data) else {
                throw AllopreeningArtVerification.failure("Expected an RGBA procedural-art bitmap")
            }
            width=image.width;height=image.height;stride=image.bytesPerRow
            bytes=Array(UnsafeBufferPointer(start:pointer,count:CFDataGetLength(data)))
        }
        var unit:CGFloat {48/CGFloat(width)}
        func pixel(_ x:Int,_ y:Int)->[UInt8] {
            Array(bytes[(y*stride+x*4)..<(y*stride+x*4+4)])
        }
        func alpha(_ p:CGPoint)->Bool {
            guard AllopreeningArtVerification.canvas.contains(p) else {return false}
            let x=min(width-1,Int(p.x*CGFloat(width)/48))
            let y=min(height-1,Int(p.y*CGFloat(height)/48))
            return bytes[y*stride+x*4+3]>0
        }
        func pixels(in rect:CGRect)->[UInt8] {
            var result=[UInt8]()
            for y in 0..<height {for x in 0..<width {
                let p=CGPoint(x:(CGFloat(x)+0.5)*48/CGFloat(width),
                              y:(CGFloat(y)+0.5)*48/CGFloat(height))
                if rect.contains(p) {result.append(contentsOf:pixel(x,y))}
            }}
            return result
        }
        func opaque(in rect:CGRect=AllopreeningArtVerification.canvas)->[CGPoint] {
            var result=[CGPoint]()
            for y in 0..<height {for x in 0..<width where bytes[y*stride+x*4+3]>0 {
                let p=CGPoint(x:(CGFloat(x)+0.5)*48/CGFloat(width),
                              y:(CGFloat(y)+0.5)*48/CGFloat(height))
                if rect.contains(p) {result.append(p)}
            }}
            return result
        }
    }
    private struct Pose {
        let full:Raster
        let body:Raster
        let feet:Raster
        let head:Raster
        let bill:Raster
        let images:[CGImage]
        init(_ name:String,_ art:BirdArt) throws {
            guard let image=art.frames[name] else {throw AllopreeningArtVerification.failure("Missing \(name)")}
            full=try Raster(image)
            var layers=[CGImage]()
            for part:DetailedBirdArt.AllopreeningPart in [.body,.feet,.headNeck,.bill] {
                guard let layer=DetailedBirdArt.allopreeningImage(name,species:art.species,part:part) else {
                    throw AllopreeningArtVerification.failure("Missing semantic layer for \(name)")
                }
                layers.append(layer)
            }
            images=layers
            body=try Raster(layers[0]);feet=try Raster(layers[1])
            head=try Raster(layers[2]);bill=try Raster(layers[3])
        }
        var layersMatchFull:Bool {
            let layers=[body,feet,head,bill]
            // All painter fills are opaque and antialiasing is disabled. The
            // last nontransparent semantic-layer pixel must be the full pixel.
            for y in 0..<full.height {for x in 0..<full.width {
                var expected=[UInt8](repeating:0,count:4)
                for layer in layers {
                    let p=layer.pixel(x,y)
                    if p[3]>0 {expected=p}
                }
                if full.pixel(x,y) != expected {return false}
            }}
            return true
        }
    }
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("allopreening-art",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        checks["allopreenArtFrameNamesAreSixDistinctPoses"]=Set(BirdArt.allopreeningNames)==Set(names) &&
            BirdArt.allopreeningNames.count == 6
        checks["allopreenArtCapabilityMatchesBehavior"]=Set(AllopreeningBehavior.supportedSpecies)==Set(species)
        let separation=CGFloat(AllopreeningBehavior.contactSeparation)
        checks["allopreenArtUsesFixed24UnitContactSeparation"]=separation == 24
        var onlySupported=true
        for id in SpeciesID.allCases {
            let art=BirdArt(species:id)
            // Other behaviors may append their own frames (for example B14
            // feeding). Inspect this family's names, including unexpected
            // allopreen variants, rather than every non-common34 frame.
            let allopreening=Set(art.frames.keys.filter {$0.hasPrefix("allopreen")})
            onlySupported = onlySupported && allopreening == (species.contains(id) ? Set(names):Set<String>())
        }
        checks["allopreenArtOnlySupportedSpeciesHaveAllopreeningFrames"]=onlySupported
        var evidence=[[String:Any]]()
        for id in species {
            let art=BirdArt(species:id),key="allopreenArt-\(id.rawValue)-"
            let poses=try names.map {try Pose($0,art)}
            let stand=try Raster(art.frames["stand"]!)
            let preen0=try Raster(art.frames["preen0"]!),preen1=try Raster(art.frames["preen1"]!)
            let bytes=poses.map {$0.full.pixels(in:canvas)}
            var distinct=true
            for a in bytes.indices {for b in bytes.indices where a<b {
                distinct = distinct && bytes[a] != bytes[b]
            }}
            checks[key+"sixFramesAreDifferent"]=distinct && bytes.allSatisfy {
                $0 != preen0.pixels(in:canvas) && $0 != preen1.pixels(in:canvas) && $0 != stand.pixels(in:canvas)
            }
            checks[key+"layersReconstructActualSpritePixels"]=poses.allSatisfy(\.layersMatchFull)
            let footBand=CGRect(x:24,y:36,width:10,height:5)
            checks[key+"feetRemainAtOriginal2939Anchor"]=poses.allSatisfy {
                $0.feet.bytes == poses[0].feet.bytes && $0.full.pixels(in:footBand)==stand.pixels(in:footBand) &&
                    !$0.feet.opaque(in:footBand).isEmpty
            }
            var localMotion=true
            for offset in [0,3] {
                for phase in 1...2 {
                    localMotion = localMotion && poses[offset+phase].body.bytes==poses[offset].body.bytes &&
                        poses[offset+phase].head.bytes != poses[offset].head.bytes
                }
            }
            checks[key+"motionIsInHeadRatherThanWholeBirdTranslation"]=localMotion
            var hitMatches=true,transparent=true,opaque=true
            for (index,name) in names.enumerated() {
                var clearCount=0,hitCount=0
                for y in 0..<48 {for x in 0..<48 {
                    let alpha=poses[index].full.alpha(CGPoint(x:x,y:y))
                    hitMatches = hitMatches && art.contains(frame:name,x:x,y:y)==alpha
                    if alpha {hitCount+=1} else {clearCount+=1}
                }}
                transparent = transparent && clearCount>100 && !art.contains(frame:name,x:0,y:0) &&
                    !art.contains(frame:name,x:47,y:47) && !art.contains(frame:name,x:-1,y:20) &&
                    !art.contains(frame:name,x:48,y:20)
                opaque = opaque && hitCount>80
                try png(art.frames[name]!,to:output.appendingPathComponent("\(id.rawValue)-\(name).png"))
            }
            checks[key+"pixelHitsUseActualAlphaAndRejectTransparentPixels"]=hitMatches && transparent && opaque
            var close=true,bodySeparate=true,onlyBillTouches=true,tipNearExpected=true,crownNearExpected=true
            for givePhase in 0..<3 {for receivePhase in 0..<3 {
                let give=poses[givePhase],receive=poses[3+receivePhase]
                // Independent layout math: giver foot (29,39), recipient foot
                // (29+24,39), and reflection around each bird's own foot.
                // Thus recipient local x maps to 2*29+24-x, not 48-x.
                let reflectedOrigin:CGFloat=2*29+separation
                func reflected(_ p:CGPoint)->CGPoint {CGPoint(x:reflectedOrigin-p.x,y:p.y)}
                let tip=give.bill.opaque().filter {$0.x>=44}
                let localCrown=receive.head.opaque(in:CGRect(x:33,y:17,width:7,height:7))
                let crown=localCrown.map(reflected)
                let distance=closest(tip,crown,cellSize:(give.bill.unit+receive.head.unit)/2)
                let bodyDistance=closest(give.body.opaque(),receive.body.opaque().map(reflected),
                                         cellSize:(give.body.unit+receive.body.unit)/2)
                close = close && !tip.isEmpty && !crown.isEmpty && distance.edges<=2
                tipNearExpected = tipNearExpected && tip.contains {hypot($0.x-45,$0.y-20)<=2}
                crownNearExpected = crownNearExpected && localCrown.contains {hypot($0.x-36,$0.y-20)<=2}
                bodySeparate = bodySeparate && bodyDistance.edges>=8
                var overlap=0,unwanted=0,bodyOverlap=0
                // Quarter-unit samples inspect both silhouettes after their
                // real anchor/mirror transforms. Only giver bill on recipient
                // crown/neck may overlap; receiver bill is a separate mask.
                for sy in 0..<(48*4) {for sx in 0..<(112*4) {
                    let p=CGPoint(x:(CGFloat(sx)+0.5)/4,y:(CGFloat(sy)+0.5)/4),q=reflected(p)
                    if give.body.alpha(p) && receive.body.alpha(q) {bodyOverlap+=1}
                    if give.full.alpha(p) && receive.full.alpha(q) {
                        overlap+=1
                        if !give.bill.alpha(p) || !receive.head.alpha(q) || receive.bill.alpha(q) {unwanted+=1}
                    }
                }}
                onlyBillTouches = onlyBillTouches && unwanted==0
                bodySeparate = bodySeparate && bodyOverlap==0
                evidence.append(["species":id.rawValue,"giverPhase":givePhase,"receiverPhase":receivePhase,
                    "footAnchor":[29,39],"footSeparation":Double(separation),"recipientXTransform":"82 - localX",
                    "billTipOpaquePixelCenters":tip.map {[Double($0.x),Double($0.y)]},
                    "crownOpaquePixelCount":crown.count,"minimumContactPixelCenterDistance":Double(distance.centers),
                    "minimumContactSilhouetteGap":Double(distance.edges),"bodySilhouetteGap":Double(bodyDistance.edges),
                    "overlapQuarterUnitSamples":overlap,"overlapOutsideBillAndHead":unwanted,
                    "bodyOverlapQuarterUnitSamples":bodyOverlap])
            }}
            checks[key+"billTipIsNear4520"]=tipNearExpected
            checks[key+"recipientCrownIsNear3620"]=crownNearExpected
            checks[key+"actualBillAndCrownAlphaWithinTwoUnitsAtAllPhasePairs"]=close
            checks[key+"bodyWingsAndTailStaySeparateAtFixedSpacing"]=bodySeparate
            checks[key+"anySilhouetteOverlapIsOnlyBillOnHeadOrNeck"]=onlyBillTouches
            try preview(art,poses:poses,separation:separation,to:output)
        }
        let report:[String:Any]=["kind":"procedural-art-raster-evidence","logicalCanvas":[48,48],
            "checksUseActualRenderedSemanticLayers":true,
            "previewLayout":"Rows: phases 0, 1, 2. Left: 6x composite and 1x pair. Right: body/wing/tail, feet, head/neck, bill at 3x. Amber ring marks the expected crown contact region.",
            "pixelDistanceDefinition":"Centers use native opaque pixels; silhouette gaps subtract the two half-pixel extents on each axis. Overlap samples use 0.25 logical units.",
            "pairs":evidence]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            .write(to:output.appendingPathComponent("geometry-alpha-evidence.json"))
    }
    private static func closest(_ a:[CGPoint],_ b:[CGPoint],cellSize:CGFloat)->(centers:CGFloat,edges:CGFloat) {
        var centers=CGFloat.greatestFiniteMagnitude,edges=CGFloat.greatestFiniteMagnitude
        for p in a {for q in b {
            let dx=abs(p.x-q.x),dy=abs(p.y-q.y)
            centers=min(centers,hypot(dx,dy))
            edges=min(edges,hypot(max(0,dx-cellSize),max(0,dy-cellSize)))
        }}
        return (centers,edges)
    }
    private static func preview(_ art:BirdArt,poses:[Pose],separation:CGFloat,to folder:URL) throws {
        // Left: the actual two sprite layers at 1x and 6x, all three phases.
        // Right: separated semantic layers, using the identical anchor layout.
        let width=1380,height=1080
        guard let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("Cannot create procedural preview canvas")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false)
        defer {NSGraphicsContext.restoreGraphicsState()}
        ctx.setFillColor(NSColor(calibratedRed:0.10,green:0.14,blue:0.17,alpha:1).cgColor)
        ctx.fill(CGRect(x:0,y:0,width:width,height:height))
        ctx.translateBy(x:0,y:CGFloat(height));ctx.scaleBy(x:1,y:-1);ctx.interpolationQuality = .none
        func label(_ text:String,x:CGFloat,y:CGFloat) {
            ctx.saveGState();ctx.translateBy(x:x,y:y);ctx.scaleBy(x:1,y:-1)
            (text as NSString).draw(at:.zero,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:13,weight:.medium),
                                                           .foregroundColor:NSColor.white])
            ctx.restoreGState()
        }
        for phase in 0..<3 {
            let row=CGFloat(phase)*350
            label("\(art.species.rawValue) / phase \(phase) / 6x",x:30,y:row+28)
            label("body / wing / tail",x:625,y:row+28)
            label("feet / anchor (29,39)",x:955,y:row+28)
            label("head / neck",x:625,y:row+188)
            label("bill",x:955,y:row+188)
            let y=CGFloat(phase)*350+290,foot=CGPoint(x:190,y:y),scale:CGFloat=6
            ctx.setStrokeColor(NSColor(calibratedWhite:0.4,alpha:1).cgColor);ctx.setLineWidth(1)
            ctx.move(to:CGPoint(x:30,y:y));ctx.addLine(to:CGPoint(x:610,y:y));ctx.strokePath()
            art.draw(name:"allopreenGive\(phase)",at:foot,scale:scale,right:true,context:ctx)
            art.draw(name:"allopreenReceive\(phase)",at:CGPoint(x:foot.x+separation*scale,y:y),scale:scale,right:false,context:ctx)
            art.draw(name:"allopreenGive\(phase)",at:CGPoint(x:62,y:y+45),scale:1,right:true,context:ctx)
            art.draw(name:"allopreenReceive\(phase)",at:CGPoint(x:62+separation,y:y+45),scale:1,right:false,context:ctx)
            label("1x / feet separated by 24 logical units",x:110,y:y+47)
            for layer in 0..<4 {
                let x:CGFloat=710+CGFloat(layer%2)*330,baseY=CGFloat(phase)*350+145+CGFloat(layer/2)*160
                draw(poses[phase].images[layer],at:CGPoint(x:x,y:baseY),scale:3,right:true,context:ctx)
                draw(poses[3+phase].images[layer],at:CGPoint(x:x+separation*3,y:baseY),scale:3,right:false,context:ctx)
            }
            let nape=CGPoint(x:foot.x+(82-36-29)*scale,y:y+(20-39)*scale)
            ctx.setStrokeColor(NSColor(calibratedRed:0.95,green:0.7,blue:0.3,alpha:1).cgColor)
            ctx.strokeEllipse(in:CGRect(x:nape.x-12,y:nape.y-12,width:24,height:24))
        }
        guard let image=ctx.makeImage() else {throw failure("Cannot finish procedural preview")}
        try png(image,to:folder.appendingPathComponent("\(art.species.rawValue)-pair-and-layers-6x.png"))
    }
    private static func draw(_ image:CGImage,at foot:CGPoint,scale:CGFloat,right:Bool,context:CGContext) {
        context.saveGState();context.translateBy(x:foot.x,y:foot.y)
        context.scaleBy(x:right ? scale:-scale,y:scale);context.translateBy(x:-29,y:-39)
        context.translateBy(x:0,y:48);context.scaleBy(x:1,y:-1)
        context.draw(image,in:canvas);context.restoreGState()
    }
    private static func png(_ image:CGImage,to url:URL) throws {
        guard let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {
            throw failure("Cannot encode \(url.lastPathComponent)")
        }
        try data.write(to:url)
    }
    private static func failure(_ message:String)->NSError {
        NSError(domain:"AllopreeningArtVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }
}
