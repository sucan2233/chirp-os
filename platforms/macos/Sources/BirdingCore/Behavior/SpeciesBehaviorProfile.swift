import Foundation

/// Product permission is independent of frame completeness and runtime eligibility.
/// The ordered lists are also the UI/export source; callers retain their existing
/// candidate sorting and random streams.
public struct SpeciesBehaviorProfile {
    public let species:SpeciesID
    public static let dedicatedKinds:[BehaviorKind] = [.edgePeek,.chase,.travelTogether,.allopreening,.fixedPerchVisit,.foodTrayVisit,.bathVisit,.leafCarry]
    private static let permissions:[BehaviorKind:[SpeciesID]] = [
        .edgePeek:[.treeSparrow,.chineseBlackbird,.hoopoe,.whimbrel,.lightVentedBulbul,.magpieRobin],
        .chase:[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling,.redWhiskeredBulbul],
        .travelTogether:[.treeSparrow,.barnSwallow,.spottedDove,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling,.redWhiskeredBulbul],
        .allopreening:[.barnSwallow,.swinhoesWhiteEye],
        .fixedPerchVisit:[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.redWhiskeredBulbul,.magpieRobin,.redBilledLeiothrix,.lightVentedBulbul],
        .foodTrayVisit:[.treeSparrow,.spottedDove],
        .bathVisit:[.treeSparrow,.lightVentedBulbul],
        .leafCarry:[.treeSparrow]
    ]
    public static let ambientFlockSpecies:[SpeciesID] = [.treeSparrow,.barnSwallow,.swinhoesWhiteEye,
        .lightVentedBulbul,.azureWingedMagpie,.mallard,.blackHeadedGull,.blackCollaredStarling]
    public static let poseSpecies:[SpeciesID] = [.treeSparrow,.spottedDove,.barnSwallow,.nightHeron,
        .lightVentedBulbul,.redWhiskeredBulbul,.chineseBlackbird,.magpieRobin,.swinhoesWhiteEye,
        .azureWingedMagpie,.redBilledLeiothrix,.littleOwl]
    public static let carryFrameNames=["carryLook","carryLower","carryGrip","carryPlace"]
    public static let bathFrameNames=BathGeometry.frameNames
    public static let peekSpecies:[SpeciesID] = [.lightVentedBulbul,.magpieRobin]
    public static let peekFrameNames:[String] = ["peekLower","peekLook","peekRecover"]
    public static func profile(for species:SpeciesID) -> Self {Self(species:species)}
    public static func species(for kind:BehaviorKind) -> [SpeciesID] {
        if kind == .flockPass {return ambientFlockSpecies}
        return permissions[kind] ?? SpeciesCatalog.standard.species.map(\.id)
    }
    public func allows(_ kind:BehaviorKind) -> Bool {Self.species(for:kind).contains(species)}
    /// Dedicated artwork augments the existing behavior contract; admission,
    /// live validation and support export must all use this species-level set.
    public func requiredFrames(for kind:BehaviorKind) -> Set<String> {
        let base=BehaviorDefinitions.definition(for:kind).requiredFrames
        return kind == .edgePeek && Self.peekSpecies.contains(species)
            ? base.union(Self.peekFrameNames):base
    }
    public var poseFrameNames:[String] {Self.poseSpecies.contains(species) ? PoseClip.frameNames:[]}
    public func poseClip(for kind:BehaviorKind,duration:Double,lookingFar:Bool=false) -> PoseClip? {
        guard Self.poseSpecies.contains(species) else {return nil}
        return PoseClip.enhancement(species:species,kind:kind,duration:duration,lookingFar:lookingFar)
    }
}

public struct SpeciesSupportAudit:Codable {
    public struct Behavior:Codable {
        public let kind:BehaviorKind
        public let productAllowed:Bool
        public let missingFrames:[String]
        public let contentSupported:Bool
    }
    public let species:SpeciesID
    public let capabilities:[BirdCapability]
    public let behaviors:[Behavior]
    public let poseFrames:[String]
    public let missingPoseFrames:[String]
    public init(species:SpeciesID,availableFrames:Set<String>) {
        self.species=species
        let profile=SpeciesBehaviorProfile.profile(for:species)
        capabilities=BirdCapability.allCases.filter{$0.requiredFrames.isSubset(of:availableFrames)}
        behaviors=BehaviorDefinitions.all.map {definition in
            let allowed=profile.allows(definition.kind)
            let missing=profile.requiredFrames(for:definition.kind).subtracting(availableFrames).sorted()
            return Behavior(kind:definition.kind,productAllowed:allowed,missingFrames:missing,contentSupported:allowed && missing.isEmpty)
        }
        poseFrames=profile.poseFrameNames
        missingPoseFrames=poseFrames.filter{!availableFrames.contains($0)}
    }
}
