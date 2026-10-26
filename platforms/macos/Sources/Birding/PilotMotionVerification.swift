import AppKit
import BirdingCore

/// Isolated native art/UI verification; never reads or writes the user's archive.
enum PilotMotionVerification {
    static func run(to folder:URL) -> Int32 {
        var checks:[String:Bool]=[:]
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            var added=0
            for species in LivelyMotion.species {
                let art=BirdArt(species:species)
                let names=M8PilotArtGeometry.frameNames(for:species)+ExpansionPilotArtGeometry.frameNames(for:species)+M8ArtCatalog.appendedFrameNames(for:species)+ExpansionArtCatalog.appendedFrameNames(for:species)
                added+=names.count
                try art.validateHitCaches()
                checks["\(species.rawValue)-hitCaches"]=true
                checks["\(species.rawValue)-newFrames"]=names.allSatisfy{art.frames[$0] != nil}
                for variant in 0...1 {
                    let clip=LivelyMotion.clip(species:species,variant:variant)
                    checks["\(species.rawValue)-variant\(variant)"]=clip.map{$0.requiredFrames.isSubset(of:Set(art.frames.keys))} ?? false
                }
            }
            checks["exactly1280M8AndExpansionFrames"]=added==1280
            checks["all100SpeciesHaveSignature"]=Set(SpeciesID.allCases)==Set(LivelyMotion.species)
            checks["all100SpeciesHaveFoundation"]=Set(SpeciesID.allCases)==Set(SpeciesBehaviorProfile.poseSpecies)
            checks["all46OriginalSpeciesHaveSignature"]=Set(SpeciesBehaviorProfile.legacySpecies).isSubset(of:Set(LivelyMotion.species))
            checks["all46OriginalSpeciesHaveFoundation"]=Set(SpeciesBehaviorProfile.legacySpecies).isSubset(of:Set(SpeciesBehaviorProfile.poseSpecies))
            try ObservationJournalUIVerification.run(into:&checks,folder:folder)
            let data=try JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys])
            try data.write(to:folder.appendingPathComponent("checks.json"),options:.atomic)
            let failed=checks.filter{!$0.value}.keys.sorted()
            print("Pilot motion native: \(checks.count-failed.count)/\(checks.count)")
            for name in failed {print("FAIL: \(name)")}
            return failed.isEmpty ? 0:1
        } catch {
            fputs("Pilot motion verification: \(error)\n",stderr);return 1
        }
    }
}
