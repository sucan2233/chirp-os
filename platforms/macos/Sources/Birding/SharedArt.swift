import AppKit
import BirdingCore

extension BirdArt {
    static func exportShared(to folder:URL) throws {
        let previousPigmentCheck=BirdPainter.verifyPigmentBounds
        BirdPainter.verifyPigmentBounds=true
        defer {BirdPainter.verifyPigmentBounds=previousPigmentCheck}
        try FileManager.default.createDirectory(at:folder.appendingPathComponent("art"),withIntermediateDirectories:true)
        let catalog = SpeciesCatalog.standard
        var frameSizes:[String:Int]=[:]
        try JSONEncoder().encode(catalog).write(to:folder.appendingPathComponent("species.json"))
        for profile in catalog.species {
            let art = BirdArt(species:profile.id)
            try art.validateHitCaches()
            let names=Self.names(for:profile.id)
            let size=art.frames["stand"]!.width
            frameSizes[profile.id.rawValue]=size
            let ctx = CGContext(data:nil,width:size*names.count,height:size,bitsPerComponent:8,bytesPerRow:0,
                                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .none
            for (i,name) in names.enumerated() { ctx.draw(art.frames[name]!,in:CGRect(x:i*size,y:0,width:size,height:size)) }
            let rep = NSBitmapImageRep(cgImage:ctx.makeImage()!)
            try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("art/\(profile.id.rawValue).png"))
        }
        let props=folder.appendingPathComponent("art/props")
        try FileManager.default.createDirectory(at:props,withIntermediateDirectories:true)
        let bathImages:[(String,CGImage)]=[("bathBasin",BathArt.image())] + BathGeometry.splashFrameNames.map{($0,BathArt.splashImage($0)!)}
        let insectImages=InsectArt.frameNames.map{($0,InsectArt.image($0)!)}
        let nestImages:[(String,CGImage)]=[("twigToken",NestArt.twigImage()),("nestPlatform",NestArt.image()),
            ("nestMaterialTray",NestArt.trayImage())]+(1...3).map{("nestOverlay\($0)",NestArt.overlayImage(progress:$0)!)}
        for (name,image) in bathImages+[("leafToken",CarryArt.leafImage())]+insectImages+nestImages {
            let rep=NSBitmapImageRep(cgImage:image)
            try rep.representation(using:.png,properties:[:])!.write(to:props.appendingPathComponent(name+".png"))
        }
        let insectMetadata:[String:Any]=["files":InsectArt.frameNames.map{$0+".png"},"logicalSize":[Int(InsectArt.logicalSize.width),Int(InsectArt.logicalSize.height)],"anchor":[Double(InsectArt.anchor.x),Double(InsectArt.anchor.y)],"collisionRadius":Double(InsectArt.collisionRadius),"frameDuration":InsectArt.frameDuration,"lifetime":CatchArtGeometry.insectLifetime,"maximumInstances":1,"scale":"worldScale","entry":"complete canvas starts offscreen"]
        var propMetadata:[String:Any]=["schemaVersion":1,"bathBasin":["file":"bathBasin.png","logicalSize":[128,40],"footAnchor":[64,20],"waterlineY":20,"waterEllipse":[16,10,96,20],"frontLayer":"derived from single basin art"],
            "waterSplash":["files":BathGeometry.splashFrameNames.map{$0+".png"},"logicalSize":[24,24],"anchor":[12,22],"frameDuration":0.1,"lifetime":0.4,"maximumInstances":6],"leafToken":["file":"leafToken.png","logicalSize":[16,16],"gripAnchor":[3,12],"surfaceAnchor":[10,12],"scale":"worldScale","availableLifetime":180,"placedLifetime":8,"fadeDuration":0.2,"giftLifetime":GiftReceiverGeometry.displayLifetime,"giftReceiverAnchor":"resolvedFixedPerch.foot","giftCarrierMayLand":false,"giftReleaseBeak":[Double(CarryArtGeometry.magpieReleaseBeak.x),Double(CarryArtGeometry.magpieReleaseBeak.y)]],"insect":insectMetadata,"clock":"singleEngineSimulationClock"]
        let twigMetadata:[String:Any]=["file":"twigToken.png","logicalSize":[16,16],"gripAnchor":[3,12],
            "surfaceAnchor":[8,12],"scale":"worldScale","contactRotation":0,
            "polygon":TwigGeometry.polygon.map{[Double($0.x),Double($0.y)]},
            "transform":"mirror anchor-relative x before rotation","maximumInkY":12]
        let nestMetadata:[String:Any]=["file":"nestPlatform.png","logicalSize":[144,48],"contactAnchor":[72,24],
            "contactY":24,"materialPoints":NestArtGeometry.materialPoints.map{[Double($0.x),Double($0.y)]},
            "scale":"worldScale","lifetime":900,"initialMaterials":3,"maximumVisitors":1]
        let trayMetadata:[String:Any]=["file":"nestMaterialTray.png","logicalSize":[32,16],"contactAnchor":[16,12],
            "contactY":12,"materialPoints":NestArtGeometry.trayMaterialPoints.map{[Double($0.x),Double($0.y)]},
            "horizontalOffset":120,"placementOrder":["left","right"],"scale":"worldScale","bakedMaterials":0]
        let progressMetadata:[String:Any]=["files":(1...3).map{"nestOverlay\($0).png"},"logicalSize":[144,48],
            "zeroUsesBase":true,"stages":[1,2,3],"contactY":24,"scale":"worldScale",
            "commit":"one delivered twig after settle, before raised recovery","looseTwigsBaked":false]
        propMetadata["twigToken"]=twigMetadata
        propMetadata["nestPlatform"]=nestMetadata
        propMetadata["nestMaterialTray"]=trayMetadata
        propMetadata["nestProgress"]=progressMetadata
        try JSONSerialization.data(withJSONObject:propMetadata,options:[.prettyPrinted,.sortedKeys]).write(to:props.appendingPathComponent("manifest.json"))
        try exportSupport(to:folder.appendingPathComponent("species-support.json"))
        // Includes catch-only flycatcher, magpie carry and both dove courtship roles,
        // without changing the atlas/prop schema or historical frame prefixes.
        let poseClips=Self.poseMetadata
        let metadata:[String:Any] = ["schemaVersion":2,"logicalFrameSize":48,"frameSizes":frameSizes,"footAnchor":[29,39],"frames":names,
                                    "speciesFrames":Dictionary(uniqueKeysWithValues:catalog.species.filter{Self.names(for:$0.id) != names}.map{($0.id.rawValue,Self.names(for:$0.id))}),
                                    "poseClips":poseClips,"poseClock":"owningBehaviorSimulationAge","signatureClock":"existingBirdStateTimeIdleWindow","source":"platforms/macos/Sources/Birding/{PixelArt,SpeciesArt,DetailedBirdArt,ExpansionBirdArt,M8PilotArt,ExpansionPilotArt,M8CommonArt,M8SmallArt,M8WetlandArt,M8RaptorArt,M8DistinctArt,M6cPoseGeometry,BathArt,CarryArt,InsectArt,NestArt}.swift; platforms/macos/Sources/BirdingCore/Behavior/{CourtshipArtGeometry,NestArtGeometry,TwigGeometry,M8PilotArtGeometry,ExpansionPilotArtGeometry,M8ArtCatalog,M8CommonArtGeometry,M8SmallArtGeometry,M8WetlandArtGeometry,M8RaptorArtGeometry,M8DistinctArtGeometry,LivelyMotion}.swift"]
        try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("art/manifest.json"))
    }
}
