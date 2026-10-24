import AppKit
import BirdingCore

/// Source/metadata acceptance complements the real command/layer journeys in
/// BathVerification. It never substitutes a constructed pose for a live visit.
enum BathArtVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let whole=try Raster(BathArt.image()),rear=try Raster(BathArt.image(layer:.rear)),front=try Raster(BathArt.image(layer:.front))
        checks["bathArtFrozenCanvasAndContactMetadata"]=whole.width==128 && whole.height==40 &&
            BathArt.waterlineY==20 && BathArt.footAnchor==CGPoint(x:64,y:20) && BathArt.birdWaterlineY==39 &&
            BathArt.splashLogicalSize==CGSize(width:24,height:24) && BathArt.splashAnchor==CGPoint(x:12,y:22)
        var partition=true
        for y in 0..<whole.height {for x in 0..<whole.width {
            let a=rear.rgba(x,y),b=front.rgba(x,y),source=whole.rgba(x,y)
            partition = partition && !(a[3]>0 && b[3]>0) && (a[3]>0 ? a:b)==source
        }}
        checks["bathArtRearFrontPartitionWholeWithoutDrift"]=partition
        var splashPixels=Set<Data>()
        for name in BathGeometry.splashFrameNames {
            guard let image=BathArt.splashImage(name) else {throw failure("Missing "+name)}
            let raster=try Raster(image);splashPixels.insert(raster.pixels)
            checks["bathArtSplashNativeAlpha-"+name]=image.width==24 && image.height==24 && raster.hasAlpha
        }
        checks["bathArtFourIndependentSplashFrames"]=splashPixels.count==4
        var poses=Set<Data>(),evidence=[[String:Any]]()
        for species:SpeciesID in [.treeSparrow,.lightVentedBulbul] {
            let art=BirdArt(species:species),profile=SpeciesBehaviorProfile.profile(for:species)
            let clip=PoseClip.bath(species:species)
            let expected=["bathInspect","bathTouch","bathLower"]+Array(repeating:["bath0","bath1","bath2"],count:3).flatMap{$0}+["bathRise"]
            checks["bathArtRequiredSevenFrameClip-"+species.rawValue]=clip?.frames.map(\.name)==expected &&
                abs((clip?.duration ?? 0)-4.4)<1e-8 &&
                Set(BathGeometry.frameNames).isSubset(of:profile.requiredFrames(for:.bathVisit))
            var frames=[[CGImage]]()
            let old=try art.frames.filter{!BathGeometry.frameNames.contains($0.key)}.values.map{try Raster($0).pixels}
            for name in BathGeometry.frameNames {
                guard let image=art.frames[name],let source=DetailedBirdArt.bathImage(name,species:species),
                      let bill=DetailedBirdArt.bathBillAnchor(name,species:species) else {throw failure("Missing "+species.rawValue+"/"+name)}
                let raster=try Raster(image),sourceRaster=try Raster(source),key="bathArt-"+species.rawValue+"-"+name
                checks[key+"IndependentProductionSource"]=poses.insert(raster.pixels).inserted && !old.contains(raster.pixels) && raster.pixels==sourceRaster.pixels
                let anchor=PoseClip.beakAnchor(species:species,frame:name)
                let anchorError=hypot(bill.x-CGFloat(anchor.x),bill.y-CGFloat(anchor.y))
                checks[key+"BillAnchorMatchesSource"]=anchorError<1e-5
                let contacts=DetailedBirdArt.bathWaterContacts(name,species:species)
                let metadata=PoseClip.bathWaterContacts(species:species,frame:name)
                let errors=zip(contacts,metadata).map {point,anchor in hypot(point.x-CGFloat(anchor.x),point.y-CGFloat(anchor.y))}
                checks[key+"WaterContactsMatchSource"]=contacts.count==metadata.count && errors.allSatisfy{$0<1e-5}
                if name=="bathTouch" {checks[key+"BillAtWaterline"]=bill==CGPoint(x:40,y:39)}
                var layers=[image]
                for part:DetailedBirdArt.FoundationPosePart in [.body,.feet,.headNeck,.bill] {
                    guard let layer=DetailedBirdArt.bathImage(name,species:species,part:part) else {throw failure("Missing semantic layer")}
                    layers.append(layer)
                }
                let feet=try Raster(layers[2]),body=try Raster(layers[1])
                checks[key+"UnmaskedSourceFeetAndWingMargin"]=feet.hasAlpha && body.hasAlpha && body.upperBoundaryAlpha==0 &&
                    raster.width==art.frames["stand"]?.width && raster.height==art.frames["stand"]?.height
                frames.append(layers)
                evidence.append(["species":species.rawValue,"frame":name,"anchorError":anchorError,"waterContactErrors":errors,
                    "bodyUpperBoundaryAlpha":body.upperBoundaryAlpha,"sourceUnmasked":true])
            }
            for right in [true,false] {try sourceSheet(frames,species:species,right:right,to:folder.appendingPathComponent("bath-"+species.rawValue+(right ? "-right":"-left")+"-contact-sheet.png"))}
        }
        checks["bathArtFourteenIndependentSourceFrames"]=poses.count==14
        saveJSON(["sourceFrames":evidence,"scope":"Unmasked editable source and frozen metadata; actual contextual masking is checked in production BathVerification journeys."],to:folder.appendingPathComponent("bath-art-evidence.json"))
    }
    struct Raster {
        let width:Int,height:Int,stride:Int,bytes:[UInt8]
        init(_ image:CGImage) throws {
            guard image.bitsPerPixel==32,image.bitsPerComponent==8,image.alphaInfo == .premultipliedLast,
                  let data=image.dataProvider?.data,let pointer=CFDataGetBytePtr(data) else {throw failure("Expected native RGBA source")}
            width=image.width;height=image.height;stride=image.bytesPerRow
            bytes=Array(UnsafeBufferPointer(start:pointer,count:CFDataGetLength(data)))
        }
        var pixels:Data {
            var value=Data();for y in 0..<height {value.append(contentsOf:bytes[(y*stride)..<(y*stride+width*4)])};return value
        }
        func rgba(_ x:Int,_ y:Int)->[UInt8] {Array(bytes[(y*stride+x*4)..<(y*stride+x*4+4)])}
        func alpha(_ x:Int,_ y:Int)->UInt8 {bytes[y*stride+x*4+3]}
        var hasAlpha:Bool {(0..<height).contains{y in (0..<width).contains{alpha($0,y)>0}}}
        var upperBoundaryAlpha:Int {
            var count=(0..<width).filter{alpha($0,0)>0}.count
            for y in 1..<min(height,Int(ceil(Double(height)*32/48))) {
                if alpha(0,y)>0 {count+=1};if alpha(width-1,y)>0 {count+=1}
            };return count
        }
    }
    private static func sourceSheet(_ frames:[[CGImage]],species:SpeciesID,right:Bool,to url:URL) throws {
        guard let context=CGContext(data:nil,width:1040,height:1120,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot allocate source sheet")}
        context.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor);context.fill(CGRect(x:0,y:0,width:1040,height:1120))
        context.translateBy(x:0,y:1120);context.scaleBy(x:1,y:-1);context.interpolationQuality = .none
        func label(_ text:String,_ x:CGFloat,_ y:CGFloat) {
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:true)
            (text as NSString).draw(at:CGPoint(x:x,y:y),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:11,weight:.regular),.foregroundColor:NSColor.white])
            NSGraphicsContext.restoreGraphicsState()
        }
        label(species.rawValue+" / raw production, body, feet, head-neck, bill / "+(right ? "right":"left"),15,12)
        for (row,layers) in frames.enumerated() {
            label(BathGeometry.frameNames[row],10,CGFloat(row*150+55))
            for (column,image) in layers.enumerated() {
                context.saveGState();context.translateBy(x:CGFloat(180+column*170),y:CGFloat(row*150+40))
                if !right {context.translateBy(x:144,y:0);context.scaleBy(x:-1,y:1)}
                context.translateBy(x:0,y:144);context.scaleBy(x:1,y:-1)
                context.draw(image,in:CGRect(x:0,y:0,width:144,height:144));context.restoreGState()
            }
        }
        try BathVerification.writePNG(context,to:url)
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"BathArtVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
