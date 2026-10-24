import AppKit
import BirdingCore

extension BirdArt {
    static func exportSupport(to url:URL) throws {
        let rows=SpeciesCatalog.standard.species.map {profile in
            SpeciesSupportAudit(species:profile.id,availableFrames:Set(BirdArt(species:profile.id).frames.keys))
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try encoder.encode(rows).write(to:url,options:.atomic)
    }
    static var poseMetadata:[String:Any] {
        var result:[String:Any]=[:]
        for species in SpeciesBehaviorProfile.poseSpecies {
            let profile=SpeciesBehaviorProfile.profile(for:species)
            var clips:[String:Any]=[:]
            for (kind,duration):(BehaviorKind,Double) in [(.watch,2),(.alert,1.5),(.rest,4),(.takeoffPreparation,0.45)] {
                guard let clip=profile.poseClip(for:kind,duration:duration,lookingFar:true),
                      let data=try? JSONEncoder().encode(clip),let object=try? JSONSerialization.jsonObject(with:data) else {continue}
                clips[kind.rawValue]=object
            }
            if let clip=PoseClip.edgePeek(species:species),
               let data=try? JSONEncoder().encode(clip),let object=try? JSONSerialization.jsonObject(with:data) {
                clips[BehaviorKind.edgePeek.rawValue]=object
            }
            if let clip=PoseClip.bath(species:species),
               let data=try? JSONEncoder().encode(clip),let object=try? JSONSerialization.jsonObject(with:data) {
                clips[BehaviorKind.bathVisit.rawValue]=object
            }
            for (name,clip) in [("leafCarryPickup",PoseClip.leafCarryPickup(species:species)),("leafCarryPlace",PoseClip.leafCarryPlace(species:species))] {
                if let clip,let data=try? JSONEncoder().encode(clip),let object=try? JSONSerialization.jsonObject(with:data) {clips[name]=object}
            }
            if let clip=PoseClip.insectCatchRecovery(species:species),
               let data=try? JSONEncoder().encode(clip),let object=try? JSONSerialization.jsonObject(with:data) {
                clips["insectCatchRecovery"]=object
            }
            let anchorNames=profile.poseFrameNames + (SpeciesBehaviorProfile.peekSpecies.contains(species) ? Self.peekNames:[]) + (profile.allows(.bathVisit) ? Self.bathNames:[]) + (profile.allows(.leafCarry) ? Self.carryNames:[]) + (profile.allows(.insectCatch) ? Self.catchNames:[])
            result[species.rawValue]=["clips":clips,"durationPolicy":"watch/alert/rest use owning run duration; transitions compress proportionally; edgePeek samples its existing 1.6s observation phase; bathVisit samples 4.4s after landing, then existing shake for 0.8s; leafCarry pickup 1.2s with atomic grip at 0.7s, place 0.4s then recovery 0.3s; insectCatch holds catchOpen during interception, then catchClose 0.18s and catchRecover 0.30s after actual contact",
                "transportBeakAnchors":Dictionary(uniqueKeysWithValues:(profile.allows(.leafCarry) || profile.allows(.insectCatch) ? Self.names(for:species):[]).compactMap {name -> (String,[Double])? in
                    guard let anchor=PoseClip.catchBeakAnchor(species:species,frame:name) ?? PoseClip.carryBeakAnchor(species:species,frame:name) else {return nil}
                    return (name,[anchor.x,anchor.y])
                }),
                "waterContactAnchors":Dictionary(uniqueKeysWithValues:(profile.allows(.bathVisit) ? Self.bathNames:[]).map {name in
                    (name,PoseClip.bathWaterContacts(species:species,frame:name).map{[$0.x,$0.y]})
                }),
                "beakAnchors":Dictionary(uniqueKeysWithValues:anchorNames.map {name in
                    let anchor=PoseClip.beakAnchor(species:species,frame:name)
                    return (name,[anchor.x,anchor.y])
                })]
        }
        return result
    }
}
