import AppKit
import BirdingCore

extension BirdArt {
    static func exportShared(to folder:URL) throws {
        try FileManager.default.createDirectory(at:folder.appendingPathComponent("art"),withIntermediateDirectories:true)
        let catalog = SpeciesCatalog.standard
        try JSONEncoder().encode(catalog).write(to:folder.appendingPathComponent("species.json"))
        for profile in catalog.species {
            let art = BirdArt(species:profile.id)
            let names=Self.names(for:profile.id)
            let size=art.frames["stand"]!.width
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
        for (name,image) in bathImages+[("leafToken",CarryArt.leafImage())]+insectImages {
            let rep=NSBitmapImageRep(cgImage:image)
            try rep.representation(using:.png,properties:[:])!.write(to:props.appendingPathComponent(name+".png"))
        }
        let insectMetadata:[String:Any]=["files":InsectArt.frameNames.map{$0+".png"},"logicalSize":[Int(InsectArt.logicalSize.width),Int(InsectArt.logicalSize.height)],"anchor":[Double(InsectArt.anchor.x),Double(InsectArt.anchor.y)],"collisionRadius":Double(InsectArt.collisionRadius),"frameDuration":InsectArt.frameDuration,"lifetime":CatchArtGeometry.insectLifetime,"maximumInstances":1,"scale":"worldScale","entry":"complete canvas starts offscreen"]
        let propMetadata:[String:Any]=["schemaVersion":1,"bathBasin":["file":"bathBasin.png","logicalSize":[128,40],"footAnchor":[64,20],"waterlineY":20,"waterEllipse":[16,10,96,20],"frontLayer":"derived from single basin art"],
            "waterSplash":["files":BathGeometry.splashFrameNames.map{$0+".png"},"logicalSize":[24,24],"anchor":[12,22],"frameDuration":0.1,"lifetime":0.4,"maximumInstances":6],"leafToken":["file":"leafToken.png","logicalSize":[16,16],"gripAnchor":[3,12],"surfaceAnchor":[10,12],"scale":"worldScale","availableLifetime":180,"placedLifetime":8,"fadeDuration":0.2,"giftLifetime":GiftReceiverGeometry.displayLifetime,"giftReceiverAnchor":"resolvedFixedPerch.foot","giftCarrierMayLand":false,"giftReleaseBeak":[Double(CarryArtGeometry.magpieReleaseBeak.x),Double(CarryArtGeometry.magpieReleaseBeak.y)]],"insect":insectMetadata,"clock":"singleEngineSimulationClock"]
        try JSONSerialization.data(withJSONObject:propMetadata,options:[.prettyPrinted,.sortedKeys]).write(to:props.appendingPathComponent("manifest.json"))
        try exportSupport(to:folder.appendingPathComponent("species-support.json"))
        // Includes catch-only flycatcher, magpie carry and both dove courtship roles,
        // without changing the atlas/prop schema or historical frame prefixes.
        let poseClips=Self.poseMetadata
        let metadata:[String:Any] = ["schemaVersion":2,"logicalFrameSize":48,"frameSizes":Dictionary(uniqueKeysWithValues:catalog.species.map{($0.id.rawValue,BirdArt(species:$0.id).frames["stand"]!.width)}),"footAnchor":[29,39],"frames":names,
                                    "speciesFrames":Dictionary(uniqueKeysWithValues:catalog.species.filter{Self.names(for:$0.id) != names}.map{($0.id.rawValue,Self.names(for:$0.id))}),
                                    "poseClips":poseClips,"poseClock":"owningBehaviorSimulationAge","source":"platforms/macos/Sources/Birding/{PixelArt,SpeciesArt,DetailedBirdArt,M6cPoseGeometry,BathArt,CarryArt,InsectArt}.swift; platforms/macos/Sources/BirdingCore/Behavior/CourtshipArtGeometry.swift"]
        try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("art/manifest.json"))
    }
}
