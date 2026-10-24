import AppKit
import BirdingCore

/// Editable sources and metadata only; InsectCatchVerification separately
/// captures actual engine journeys through DesktopView's production layers.
enum InsectCatchArtVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let art=BirdArt(species:.barnSwallow),names=CatchArtGeometry.frameNames
        let old=try art.frames.filter{!names.contains($0.key)}.values.map{try BathArtVerification.Raster($0).pixels}
        var distinct=Set<Data>(),rows=[[CGImage]](),evidence=[[String:Any]]()
        checks["insectCatchArtOnlyDeliveredSwallow"]=SpeciesBehaviorProfile.species(for:.insectCatch)==[.barnSwallow] &&
            Set(names).isSubset(of:SpeciesBehaviorProfile.profile(for:.barnSwallow).requiredFrames(for:.insectCatch)) &&
            !SpeciesBehaviorProfile.profile(for:.yellowRumpedFlycatcher).allows(.insectCatch)
        for name in names {
            guard let image=art.frames[name],let source=DetailedBirdArt.catchImage(name,species:.barnSwallow),
                  let bill=DetailedBirdArt.catchBillAnchor(name,species:.barnSwallow),
                  let anchor=PoseClip.catchBeakAnchor(species:.barnSwallow,frame:name) else {throw failure("Missing swallow source: "+name)}
            let pixels=try BathArtVerification.Raster(image),original=try BathArtVerification.Raster(source)
            let error=hypot(bill.x-CGFloat(anchor.x),bill.y-CGFloat(anchor.y))
            checks["insectCatchArt-"+name+"IndependentProductionSource"]=pixels.pixels==original.pixels &&
                distinct.insert(pixels.pixels).inserted && !old.contains(pixels.pixels)
            checks["insectCatchArt-"+name+"BillMatchesDrawing"]=error<1e-5 &&
                anchor.mirrored(facingRight:false)==PoseClip.Anchor(48-Double(bill.x),Double(bill.y))
            var layers=[image]
            for part:DetailedBirdArt.FoundationPosePart in [.body,.feet,.headNeck,.bill] {
                guard let layer=DetailedBirdArt.catchImage(name,species:.barnSwallow,part:part) else {throw failure("Missing catch semantic layer")}
                layers.append(layer)
            }
            let body=try BathArtVerification.Raster(layers[1])
            let semanticLayersHaveAlpha=try layers.dropFirst().allSatisfy{try BathArtVerification.Raster($0).hasAlpha}
            checks["insectCatchArt-"+name+"CompleteWingCanvasAndSemanticLayers"]=boundaryAlpha(body)==0 &&
                semanticLayersHaveAlpha &&
                image.width==art.frames["stand"]?.width && image.height==art.frames["stand"]?.height
            rows.append(layers);evidence.append(["frame":name,"billAnchorError":error,"bodyBoundaryAlpha":boundaryAlpha(body)])
        }
        for name in TransportArtGeometry.frameNames {
            guard let source=DetailedBirdArt.catchBillAnchor(name,species:.barnSwallow),
                  let anchor=PoseClip.catchBeakAnchor(species:.barnSwallow,frame:name),art.frames[name] != nil else {throw failure("Missing catch transport anchor: "+name)}
            checks["insectCatchArtTransport-"+name+"BillMatchesSource"]=hypot(source.x-CGFloat(anchor.x),source.y-CGFloat(anchor.y))<1e-5
        }
        let recovery=PoseClip.insectCatchRecovery(species:.barnSwallow)
        checks["insectCatchArtRecoveryClosesThenRecovers"]=recovery?.frames.map(\.name)==["catchClose","catchRecover"] &&
            abs((recovery?.duration ?? 0)-0.48)<1e-8 && recovery?.foot==PoseClip.footAnchor
        var insects=Set<Data>()
        for name in InsectArt.frameNames {
            guard let image=InsectArt.image(name) else {throw failure("Missing insect frame: "+name)}
            let pixels=try BathArtVerification.Raster(image)
            checks["insectCatchArt-"+name+"IndependentThoraxAndUnclippedWings"]=image.width==16 && image.height==16 &&
                pixels.alpha(8,8)>0 && boundaryAlpha(pixels)==0 && insects.insert(pixels.pixels).inserted
        }
        checks["insectCatchArtFrozenWorldGeometry"]=InsectArt.logicalSize==CGSize(width:16,height:16) &&
            InsectArt.anchor==CGPoint(x:8,y:8) && InsectArt.collisionRadius==3 &&
            InsectTrajectory.logicalSize==16 && InsectTrajectory.lifetime==12 && InsectArt.frameNames==["insect0","insect1","insect2","insect3"]
        for right in [true,false] {try sheet(rows,right:right,to:folder.appendingPathComponent("insect-catch-source-"+(right ? "right":"left")+".png"))}
        saveJSON(["frames":evidence,"scope":"Unmasked editable source only; real contact, recovery and layer composition are verified by the native runtime verifier."],to:folder.appendingPathComponent("insect-catch-art-evidence.json"))
    }
    private static func boundaryAlpha(_ r:BathArtVerification.Raster)->Int {
        (0..<r.width).filter{r.alpha($0,0)>0 || r.alpha($0,r.height-1)>0}.count +
            (1..<(r.height-1)).filter{r.alpha(0,$0)>0 || r.alpha(r.width-1,$0)>0}.count
    }
    private static func sheet(_ rows:[[CGImage]],right:Bool,to url:URL) throws {
        guard let context=CGContext(data:nil,width:1040,height:730,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot allocate catch source sheet")}
        context.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor);context.fill(CGRect(x:0,y:0,width:1040,height:730))
        context.translateBy(x:0,y:730);context.scaleBy(x:1,y:-1);context.interpolationQuality = .none
        func label(_ text:String,_ x:CGFloat,_ y:CGFloat) {
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:true)
            (text as NSString).draw(at:CGPoint(x:x,y:y),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:11,weight:.regular),.foregroundColor:NSColor.white])
            NSGraphicsContext.restoreGraphicsState()
        }
        label("Barn Swallow / raw source, body, feet, head-neck, bill / "+(right ? "right":"left"),15,12)
        for (row,layers) in rows.enumerated() {
            label(CatchArtGeometry.frameNames[row],10,CGFloat(65+row*175))
            for (column,image) in layers.enumerated() {
                context.saveGState();context.translateBy(x:CGFloat(180+column*170),y:CGFloat(40+row*175))
                if !right {context.translateBy(x:144,y:0);context.scaleBy(x:-1,y:1)}
                context.translateBy(x:0,y:144);context.scaleBy(x:1,y:-1)
                context.draw(image,in:CGRect(x:0,y:0,width:144,height:144));context.restoreGState()
            }
        }
        for (index,name) in InsectArt.frameNames.enumerated() {
            label(name,CGFloat(180+index*170),590)
            context.saveGState();context.translateBy(x:CGFloat(180+index*170),y:615+64);context.scaleBy(x:1,y:-1)
            context.draw(InsectArt.image(name)!,in:CGRect(x:0,y:0,width:64,height:64));context.restoreGState()
        }
        try BathVerification.writePNG(context,to:url)
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"InsectCatchArtVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
