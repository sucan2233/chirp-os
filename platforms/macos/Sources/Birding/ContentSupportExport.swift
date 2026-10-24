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
            result[species.rawValue]=["clips":clips,"durationPolicy":"watch/alert/rest use owning run duration; transitions compress proportionally",
                "beakAnchors":Dictionary(uniqueKeysWithValues:profile.poseFrameNames.map {name in
                    let anchor=PoseClip.beakAnchor(species:species,frame:name)
                    return (name,[anchor.x,anchor.y])
                })]
        }
        return result
    }
}
