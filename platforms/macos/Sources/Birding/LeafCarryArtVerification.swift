import AppKit
import BirdingCore

/// Source art acceptance. LeafCarryVerification owns real command journeys
/// and real layer captures; these sheets are explicitly raw source evidence.
enum LeafCarryArtVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let art=BirdArt(species:.treeSparrow),names=CarryArtGeometry.frameNames
        let leaf=CarryArt.leafImage(),token=try BathArtVerification.Raster(leaf)
        checks["leafCarryArtFrozenLeafCanvasAndAnchors"]=leaf.width==16 && leaf.height==16 &&
            CarryArt.leafGripAnchor==CGPoint(x:3,y:12) && CarryArt.leafSurfaceAnchor==CGPoint(x:10,y:12) && token.hasAlpha
        let bottom=(12..<token.height).allSatisfy{y in (0..<token.width).allSatisfy{token.alpha($0,y)==0}}
        checks["leafCarryArtSurfaceAndGripEndAtSupportingEdge"]=bottom && token.alpha(3,11)>0 &&
            (8...11).contains{token.alpha($0,11)>0}
        checks["leafCarryArtTransparentMarginAndUnclippedBlade"]=token.upperBoundaryAlpha==0 && token.alpha(0,0)==0
        let old=try art.frames.filter{!names.contains($0.key)}.values.map{try BathArtVerification.Raster($0).pixels}
        var distinct=Set<Data>(),frames=[[CGImage]](),evidence=[[String:Any]]()
        for name in names {
            guard let image=art.frames[name],let source=DetailedBirdArt.carryImage(name,species:.treeSparrow),
                  let bill=DetailedBirdArt.carryBillAnchor(name,species:.treeSparrow),
                  let anchor=PoseClip.carryBeakAnchor(species:.treeSparrow,frame:name) else {throw failure("Missing carry source or metadata: "+name)}
            let pixels=try BathArtVerification.Raster(image),original=try BathArtVerification.Raster(source)
            let error=hypot(bill.x-CGFloat(anchor.x),bill.y-CGFloat(anchor.y))
            checks["leafCarryArt-"+name+"IndependentEditableSource"]=pixels.pixels==original.pixels &&
                distinct.insert(pixels.pixels).inserted && !old.contains(pixels.pixels)
            checks["leafCarryArt-"+name+"BillAnchorMatchesSource"]=error<1e-5
            var layers=[image]
            for part:DetailedBirdArt.FoundationPosePart in [.body,.feet,.headNeck,.bill] {
                guard let layer=DetailedBirdArt.carryImage(name,species:.treeSparrow,part:part) else {throw failure("Missing carry semantic layer")}
                layers.append(layer)
            }
            let body=try BathArtVerification.Raster(layers[1]),feet=try BathArtVerification.Raster(layers[2])
            checks["leafCarryArt-"+name+"NativeLayersAndWingMargin"]=body.hasAlpha && feet.hasAlpha && body.upperBoundaryAlpha==0 && pixels.width==48 && pixels.height==48
            if ["carryGrip","carryPlace"].contains(name) {checks["leafCarryArt-"+name+"ContactAtFrozenBill"]=hypot(bill.x-40,bill.y-39)<1e-5}
            frames.append(layers);evidence.append(["frame":name,"billAnchorError":error,"bodyBoundaryAlpha":body.upperBoundaryAlpha])
        }
        let pickup=PoseClip.leafCarryPickup(species:.treeSparrow),place=PoseClip.leafCarryPlace(species:.treeSparrow)
        checks["leafCarryArtFourFramePickupAndPlacementClips"]=pickup?.frames.map(\.name)==["carryLook","carryLower","carryGrip","carryLook"] &&
            abs((pickup?.duration ?? 0)-1.2)<1e-8 && place?.frames.map(\.name)==["carryPlace","carryLook"] && abs((place?.duration ?? 0)-0.7)<1e-8
        // A landed carrier briefly uses stand between the transport and
        // authored contact clips; its bill is required by the real envelope.
        for name in ["stand"]+TransportArtGeometry.frameNames.filter({$0 != "stand"}) {
            guard let source=DetailedBirdArt.poseBillAnchor(name,species:.treeSparrow),
                  let anchor=PoseClip.carryBeakAnchor(species:.treeSparrow,frame:name),art.frames[name] != nil else {throw failure("Missing transport bill: "+name)}
            let error=hypot(source.x-CGFloat(anchor.x),source.y-CGFloat(anchor.y))
            checks["leafCarryArtTransport-"+name+"BillMatchesDrawing"]=error<1e-5
            evidence.append(["transportFrame":name,"billAnchorError":error])
        }
        checks["leafCarryArtPermissionOnlyExistingSparrow"]=SpeciesBehaviorProfile.species(for:.leafCarry)==[.treeSparrow] &&
            Set(names).isSubset(of:SpeciesBehaviorProfile.profile(for:.treeSparrow).requiredFrames(for:.leafCarry))
        for right in [true,false] {try sheet(frames,leaf:leaf,right:right,to:folder.appendingPathComponent("leaf-carry-source-"+(right ? "right":"left")+".png"))}
        saveJSON(["frames":evidence,"scope":"Raw editable source; native production composition is verified separately."],to:folder.appendingPathComponent("leaf-carry-art-evidence.json"))
    }
    private static func sheet(_ frames:[[CGImage]],leaf:CGImage,right:Bool,to url:URL) throws {
        guard let context=CGContext(data:nil,width:1000,height:760,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw failure("Cannot allocate carry source sheet")}
        context.setFillColor(NSColor(calibratedWhite:0.12,alpha:1).cgColor);context.fill(CGRect(x:0,y:0,width:1000,height:760))
        context.translateBy(x:0,y:760);context.scaleBy(x:1,y:-1);context.interpolationQuality = .none
        for (row,layers) in frames.enumerated() {for (column,image) in (layers+[leaf]).enumerated() {
            context.saveGState();context.translateBy(x:CGFloat(20+column*160),y:CGFloat(30+row*180))
            if !right {context.translateBy(x:144,y:0);context.scaleBy(x:-1,y:1)}
            context.translateBy(x:0,y:144);context.scaleBy(x:1,y:-1)
            context.draw(image,in:CGRect(x:0,y:0,width:column==5 ? 48:144,height:column==5 ? 48:144));context.restoreGState()
        }}
        try BathVerification.writePNG(context,to:url)
    }
    private static func failure(_ text:String)->NSError {NSError(domain:"LeafCarryArtVerification",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
}
