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
        for species in Self.poseExportSpecies {
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
            for (name,clip) in [("visitorGiftPickup",PoseClip.visitorGiftPickup(species:species)),("visitorGiftRelease",PoseClip.visitorGiftRelease(species:species))] {
                if let clip,let data=try? JSONEncoder().encode(clip),let object=try? JSONSerialization.jsonObject(with:data) {clips[name]=object}
            }
            if let clip=PoseClip.insectCatchRecovery(species:species),
               let data=try? JSONEncoder().encode(clip),let object=try? JSONSerialization.jsonObject(with:data) {
                clips["insectCatchRecovery"]=object
            }
            for (name,role):(String,CourtshipRole) in [("courtshipInitiator",.initiator),("courtshipObserver",.observer)] {
                if let clip=PoseClip.courtship(species:species,role:role),
                   let data=try? JSONEncoder().encode(clip),let object=try? JSONSerialization.jsonObject(with:data) {clips[name]=object}
            }
            let nestClips:[(String,PoseClip?)]=[("nestMaterialPickup",PoseClip.nestMaterialPickup(species:species)),
                ("nestMaterialPlace",PoseClip.nestMaterialPlace(species:species)),("nestBuild",PoseClip.nestBuild(species:species))]
            for (name,clip) in nestClips {
                if let clip,let data=try? JSONEncoder().encode(clip),
                   let object=try? JSONSerialization.jsonObject(with:data) {clips[name]=object}
            }
            let carry=profile.allows(.leafCarry) || profile.allows(.visitorGift)
            let courtship=CourtshipArtGeometry.species.contains(species)
            let nesting=profile.allows(.nestMaterialCarry) || profile.allows(.nestBuild)
            var anchorNames=profile.poseFrameNames
            if SpeciesBehaviorProfile.peekSpecies.contains(species) {anchorNames += Self.peekNames}
            if profile.allows(.bathVisit) {anchorNames += Self.bathNames}
            if carry {anchorNames += Self.carryNames}
            if profile.allows(.insectCatch) {anchorNames += Self.catchNames}
            if courtship {anchorNames += Self.courtshipNames}
            if profile.allows(.nestMaterialCarry) {anchorNames += Self.nestCarryNames}
            if profile.allows(.nestBuild) {anchorNames += Self.nestBuildNames}
            let giftPolicy=profile.allows(.visitorGift) ? "; visitorGift pickup 1.2s with atomic grip at 0.7s, airborne release 0.3s; token drop remains execution-owned":""
            let courtshipPolicy=courtship ? "; courtshipDisplay both roles sample shared run age 4.0s: face 0.4, raise 0.5, two bows 1.0 each (0.35/0.40/0.25), observe 0.5, recover 0.6; facing and mutual clearance are execution-owned":""
            let nestPolicy=nesting ? "; nestMaterialCarry pickup 1.2s with atomic grip at 0.7s, settled place 0.4s plus empty-bill recovery 0.3s; nestBuild 2.2s with commit at 1.9s before raised recovery; both visits complete only after execution-owned safe exit":""
            var entry:[String:Any]=["clips":clips,"durationPolicy":"watch/alert/rest use owning run duration; transitions compress proportionally; edgePeek samples its existing 1.6s observation phase; bathVisit samples 4.4s after landing, then existing shake for 0.8s; leafCarry pickup 1.2s with atomic grip at 0.7s, place 0.4s then recovery 0.3s; insectCatch holds catchOpen during interception, then catchClose 0.18s and catchRecover 0.30s after actual contact"+giftPolicy+courtshipPolicy+nestPolicy,
                "transportBeakAnchors":Dictionary(uniqueKeysWithValues:(carry || profile.allows(.insectCatch) ? Self.names(for:species):[]).compactMap {name -> (String,[Double])? in
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
            if courtship {
                entry["courtshipBeakAnchors"]=Dictionary(uniqueKeysWithValues:(Self.courtshipNames+["stand"]).compactMap {name -> (String,[Double])? in
                    guard let point=CourtshipArtGeometry.billAnchor(species:species,frame:name) else {return nil}
                    return (name,[Double(point.x),Double(point.y)])
                })
            }
            if nesting {
                let names=NestArtGeometry.frameNames+NestArtGeometry.transportFrameNames
                entry["nestBeakAnchors"]=Dictionary(uniqueKeysWithValues:names.compactMap {name -> (String,[Double])? in
                    guard let point=NestArtGeometry.billAnchor(species:species,frame:name) else {return nil}
                    return (name,[Double(point.x),Double(point.y)])
                })
            }
            result[species.rawValue]=entry
        }
        return result
    }
}
