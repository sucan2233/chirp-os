import AppKit
import ImageIO
import BirdingCore

extension BirdArt {
    /// Presentation-only looping reference. Production timing remains in the
    /// owning execution; the short stand interval illustrates current-state release.
    static func exportPosePreviews(to folder:URL) throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for species in Self.poseExportSpecies {
            let art=BirdArt(species:species),profile=SpeciesBehaviorProfile.profile(for:species)
            let bird=SpeciesCatalog.standard.profile(species)
            let giftLeaf=profile.allows(.visitorGift) ? CarryArt.leafImage():nil
            var tracks:[PoseClip]=[(BehaviorKind.watch,2.0),(.alert,1.5),(.rest,4),(.takeoffPreparation,0.45)].compactMap {
                profile.poseClip(for:$0.0,duration:$0.1,lookingFar:true)
            }
            if let peek=PoseClip.edgePeek(species:species) {tracks.append(peek)}
            if let bath=PoseClip.bath(species:species) {tracks.append(bath)}
            if let pickup=PoseClip.leafCarryPickup(species:species),let place=PoseClip.leafCarryPlace(species:species),
               let carry=PoseClip(id:"\(species.rawValue).leafCarry.preview",frames:pickup.frames+place.frames) {tracks.append(carry)}
            if let pickup=PoseClip.visitorGiftPickup(species:species),let release=PoseClip.visitorGiftRelease(species:species),
               let fly=PoseClip.carryBeakAnchor(species:species,frame:"fly1"),
               let glide=PoseClip.carryBeakAnchor(species:species,frame:"glide1"),
               let carry=PoseClip(id:"\(species.rawValue).visitorGift.preview",frames:pickup.frames +
                    [PoseClip.Frame(name:"fly1",duration:0.25,beak:fly),
                     PoseClip.Frame(name:"glide1",duration:0.25,beak:glide)]+release.frames) {tracks.append(carry)}
            if let recovery=PoseClip.insectCatchRecovery(species:species),
               let clip=PoseClip(id:"\(species.rawValue).insectCatch.preview",
                    frames:[PoseClip.Frame(name:"catchOpen",duration:0.24,
                        beak:PoseClip.beakAnchor(species:species,frame:"catchOpen"))]+recovery.frames) {
                // The .24s open hold illustrates art only; production contact
                // is decided by the core's continuous interception sweep.
                tracks.append(clip)
            }
            tracks=tracks.filter{clip in clip.frames.allSatisfy{art.frames[$0.name] != nil}}
            guard !tracks.isEmpty else {continue}
            for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
                let size=scale*bird.relativeScale,cell=max(140,Int(ceil(48*size))+32)
                let width=cell*tracks.count,height=cell+42
                let url=folder.appendingPathComponent("\(species.rawValue)-\(scale)x-\(right ? "right":"left")-loop.gif")
                guard let destination=CGImageDestinationCreateWithURL(url as CFURL,"com.compuserve.gif" as CFString,100,nil) else {
                    throw NSError(domain:"PosePreviewExport",code:1)
                }
                CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
                for tick in 0..<100 {
                    let time=Double(tick)*0.05
                    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
                    let graphics=NSGraphicsContext(bitmapImageRep:rep)!,context=graphics.cgContext
                    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
                    context.setFillColor(NSColor(calibratedRed:0.94,green:0.93,blue:0.88,alpha:1).cgColor)
                    context.fill(CGRect(x:0,y:0,width:width,height:height))
                    context.translateBy(x:0,y:CGFloat(height));context.scaleBy(x:1,y:-1)
                    for (i,clip) in tracks.enumerated() {
                        let age=time.truncatingRemainder(dividingBy:clip.duration+0.35)
                        let frame=clip.sample(at:age)?.name ?? "stand"
                        let foot=CGPoint(x:CGFloat(i*cell+cell/2),y:CGFloat(cell-6))
                        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.4).cgColor)
                        context.move(to:CGPoint(x:CGFloat(i*cell+8),y:foot.y));context.addLine(to:CGPoint(x:CGFloat((i+1)*cell-8),y:foot.y));context.strokePath()
                        art.draw(name:frame,at:foot,scale:size,right:right,context:context)
                        // Presentation-only prop: independent world scale, not
                        // baked into a bird frame or scaled with its body size.
                        if clip.id=="\(species.rawValue).visitorGift.preview",age>=0.7,age<1.7,let leaf=giftLeaf,
                           let anchor=PoseClip.carryBeakAnchor(species:species,frame:frame) {
                            let grip=anchor.world(foot:foot,scale:size,facingRight:right)
                            context.saveGState();context.translateBy(x:grip.x,y:grip.y)
                            context.scaleBy(x:right ? scale:-scale,y:scale)
                            context.translateBy(x:-CarryArtGeometry.leafGripAnchor.x,y:-CarryArtGeometry.leafGripAnchor.y)
                            context.translateBy(x:0,y:16);context.scaleBy(x:1,y:-1)
                            context.draw(leaf,in:CGRect(x:0,y:0,width:16,height:16));context.restoreGState()
                        }
                        context.saveGState();context.translateBy(x:CGFloat(i*cell+8),y:CGFloat(height-10));context.scaleBy(x:1,y:-1)
                        ("\(clip.id.dropFirst(species.rawValue.count+1))\n\(frame)" as NSString).draw(at:.zero,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor(calibratedWhite:0.2,alpha:1)])
                        context.restoreGState()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    CGImageDestinationAddImage(destination,rep.cgImage!,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.05,kCGImagePropertyGIFUnclampedDelayTime:0.05]] as CFDictionary)
                }
                guard CGImageDestinationFinalize(destination) else {throw NSError(domain:"PosePreviewExport",code:2)}
            }}
        }
    }
}
