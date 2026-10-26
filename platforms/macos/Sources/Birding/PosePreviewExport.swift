import AppKit
import ImageIO
import BirdingCore

extension BirdArt {
    /// Presentation-only looping reference. Production timing remains in the
    /// owning execution; the short stand/cling interval illustrates current-state release.
    static func exportPosePreviews(to folder:URL) throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let existingSpecies=Self.poseExportSpecies
        let exportSpecies=existingSpecies+LivelyMotion.species.filter{!existingSpecies.contains($0)}
        for species in exportSpecies {
            let art=BirdArt(species:species),profile=SpeciesBehaviorProfile.profile(for:species)
            let bird=SpeciesCatalog.standard.profile(species)
            let giftLeaf=profile.allows(.visitorGift) ? CarryArt.leafImage():nil
            var sideTrackIDs=Set<String>()
            var tracks:[PoseClip]=[(BehaviorKind.watch,2.0),(.alert,1.5),(.rest,4),(.takeoffPreparation,0.45)].compactMap {
                profile.poseClip(for:$0.0,duration:$0.1,lookingFar:true)
            }
            let signatures=(0..<2).compactMap{LivelyMotion.clip(species:species,variant:$0)}
            if !signatures.isEmpty {
                let side=LivelyMotion.isSideMotion(species)
                if let before=legacyIdlePreview(species:species,side:side) {
                    tracks.append(before)
                    if side {sideTrackIDs.insert(before.id)}
                }
                tracks += signatures
                if side {sideTrackIDs.formUnion(signatures.map(\.id))}
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
            if let pickup=PoseClip.nestMaterialPickup(species:species),let place=PoseClip.nestMaterialPlace(species:species),
               let fly=PoseClip.nestBeakAnchor(species:species,frame:"fly1"),
               let glide=PoseClip.nestBeakAnchor(species:species,frame:"glide1") {
                let flight=[PoseClip.Frame(name:"fly1",duration:0.25,beak:fly),
                            PoseClip.Frame(name:"glide1",duration:0.25,beak:glide)]
                if let clip=PoseClip(id:"\(species.rawValue).nestMaterial.preview",frames:pickup.frames+flight+place.frames) {tracks.append(clip)}
            }
            if let build=PoseClip.nestBuild(species:species) {tracks.append(build)}
            tracks=tracks.filter{clip in clip.frames.allSatisfy{art.frames[$0.name] != nil}}
            let courtInitiator=PoseClip.courtship(species:species,role:.initiator)
            let courtObserver=PoseClip.courtship(species:species,role:.observer)
            let courtPair=courtInitiator != nil && courtObserver != nil &&
                [courtInitiator,courtObserver].compactMap{$0}.allSatisfy{clip in clip.requiredFrames.allSatisfy{art.frames[$0] != nil}}
            guard !tracks.isEmpty else {continue}
            let nesting=profile.allows(.nestMaterialCarry) || profile.allows(.nestBuild)
            for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
                let size=scale*bird.relativeScale,baseCell=max(140,Int(ceil(48*size))+32)
                let cell=nesting ? max(baseCell,Int(ceil(144*scale))+64):baseCell
                let footY=CGFloat(cell-6)-(nesting ? 24*scale:0)
                // Full facing-union sprite spacing plus the specified twelve
                // desktop points. The pair adds a cell, never a new GIF name.
                let pairGap=58*size+12,pairWidth=courtPair ? max(cell,Int(ceil(pairGap+58*size))+32):0
                let width=cell*tracks.count+pairWidth,height=cell+42
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
                        let side=sideTrackIDs.contains(clip.id)
                        let frame=clip.sample(at:age)?.name ?? (side ? "cling0":"stand")
                        let isNest=clip.id=="\(species.rawValue).nestMaterial.preview" || clip.id=="\(species.rawValue).nestBuild"
                        let center=CGFloat(i*cell+cell/2),direction:CGFloat=right ? 1:-1
                        let foot=CGPoint(x:center-(isNest ? (5*scale+11*size)*direction:0),y:footY)
                        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.4).cgColor)
                        if side {
                            context.move(to:CGPoint(x:foot.x,y:8));context.addLine(to:foot)
                        } else {
                            context.move(to:CGPoint(x:CGFloat(i*cell+8),y:foot.y));context.addLine(to:CGPoint(x:CGFloat((i+1)*cell-8),y:foot.y))
                        }
                        context.strokePath()
                        if clip.id=="\(species.rawValue).nestBuild" {
                            let contact=CGPoint(x:center,y:foot.y)
                            drawNestPreviewAsset(NestArt.image(),at:contact,anchor:NestArtGeometry.nestAnchor,scale:scale,in:context)
                            if let overlay=NestArt.overlayImage(progress:age<1.9 ? 1:2) {
                                drawNestPreviewAsset(overlay,at:contact,anchor:NestArtGeometry.nestAnchor,scale:scale,in:context)
                            }
                        }
                        art.draw(name:frame,at:foot,scale:size,right:right,context:context)
                        if isNest,let ground=PoseClip.nestBeakAnchor(species:species,frame:"carryGrip") {
                            let carrying=clip.id=="\(species.rawValue).nestMaterial.preview"
                            let attached=carrying && age>=0.7 && age<2.1
                            let visible=carrying || age<1.9
                            let bill:PoseClip.Anchor?=attached ? PoseClip.nestBeakAnchor(species:species,frame:frame):ground
                            if visible,let bill=bill {
                                let point=bill.world(foot:foot,scale:size,facingRight:right)
                                drawNestPreviewAsset(NestArt.twigImage(),at:point,anchor:TwigGeometry.grip,
                                    scale:scale,right:right,in:context)
                            }
                        }
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
                        let trackLabel=String(clip.id.dropFirst(species.rawValue.count+1))+(side ? " / side":"")
                        ("\(trackLabel)\n\(frame)" as NSString).draw(at:.zero,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor(calibratedWhite:0.2,alpha:1)])
                        context.restoreGState()
                    }
                    if courtPair,let initiator=courtInitiator,let observer=courtObserver {
                        let age=time.truncatingRemainder(dividingBy:initiator.duration+0.35)
                        let center=CGFloat(cell*tracks.count)+CGFloat(pairWidth)/2
                        let left=CGPoint(x:center-pairGap/2,y:footY),rightFoot=CGPoint(x:center+pairGap/2,y:footY)
                        let initiatingFoot=right ? left:rightFoot,observingFoot=right ? rightFoot:left
                        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.4).cgColor)
                        context.move(to:CGPoint(x:CGFloat(cell*tracks.count+8),y:left.y))
                        context.addLine(to:CGPoint(x:CGFloat(width-8),y:left.y));context.strokePath()
                        art.draw(name:initiator.sample(at:age)?.name ?? "stand",at:initiatingFoot,scale:size,right:right,context:context)
                        art.draw(name:observer.sample(at:age)?.name ?? "stand",at:observingFoot,scale:size,right:!right,context:context)
                        context.saveGState();context.translateBy(x:CGFloat(cell*tracks.count+8),y:CGFloat(height-10));context.scaleBy(x:1,y:-1)
                        ("courtshipDisplay / initiator + observer\n4.0s shared age / roles only" as NSString).draw(at:.zero,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor(calibratedWhite:0.2,alpha:1)])
                        context.restoreGState()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    CGImageDestinationAddImage(destination,rep.cgImage!,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.05,kCGImagePropertyGIFUnclampedDelayTime:0.05]] as CFDictionary)
                }
                guard CGImageDestinationFinalize(destination) else {throw NSError(domain:"PosePreviewExport",code:2)}
            }}
        }
    }
    /// Capture the old scheduler's active time window at the GIF's 20 Hz,
    /// including the side-specific window and frames. This is artwork evidence
    /// only: the unused beak field is a placeholder, not a contact anchor.
    private static func legacyIdlePreview(species:SpeciesID,side:Bool) -> PoseClip? {
        let window=LivelyMotion.window(species),step=0.05
        let frames=(0..<Int(ceil(window.duration/step))).map {index in
            let offset=Double(index)*step
            let name=SpeciesBehavior.frame(species,age:window.start+offset,side:side) ?? (side ? "cling0":"stand")
            return PoseClip.Frame(name:name,duration:min(step,window.duration-offset),beak:PoseClip.footAnchor)
        }
        return PoseClip(id:"\(species.rawValue).before",frames:frames)
    }
    /// Pose illustration only: no real transport route, stock mutation or run
    /// completion is implied by these independently looping source panels.
    private static func drawNestPreviewAsset(_ image:CGImage,at point:CGPoint,anchor:CGPoint,
                                              scale:CGFloat,right:Bool=true,in c:CGContext) {
        c.saveGState();c.translateBy(x:point.x,y:point.y);c.scaleBy(x:right ? scale:-scale,y:scale)
        c.translateBy(x:-anchor.x,y:-anchor.y)
        c.translateBy(x:0,y:CGFloat(image.height));c.scaleBy(x:1,y:-1)
        c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));c.restoreGState()
    }
}
