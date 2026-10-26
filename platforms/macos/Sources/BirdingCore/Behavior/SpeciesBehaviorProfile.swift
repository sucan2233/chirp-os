import Foundation

/// Product permission is independent of frame completeness and runtime eligibility.
/// The ordered lists are also the UI/export source; callers retain their existing
/// candidate sorting and random streams.
public struct SpeciesBehaviorProfile {
    public let species:SpeciesID
    /// Freeze the reviewed pre-expansion cohort. Adding a catalog row must never
    /// silently authorize social, scene or generic recorded behaviors.
    public static let legacySpecies:[SpeciesID] = [
        .redWhiskeredBulbul,.treeSparrow,.lightVentedBulbul,.spottedDove,.chineseBlackbird,
        .magpieRobin,.longTailedShrike,.nightHeron,.plumbeousWaterRedstart,.littleEgret,
        .greyHeron,.commonKestrel,.peregrineFalcon,.blackKite,.commonBuzzard,.orientalMagpie,
        .azureWingedMagpie,.largeBilledCrow,.hoopoe,.barnSwallow,.mallard,.asianKoel,
        .swinhoesWhiteEye,.blackHeadedGull,.whimbrel,.piedKingfisher,.eurasianWoodcock,
        .blackDrongo,.chinesePondHeron,.yellowRumpedFlycatcher,.yellowBrowedWarbler,
        .greatTit,.commonMoorhen,.greatSpottedWoodpecker,.vinousThroatedParrotbill,
        .blackWingedStilt,.eurasianCoot,.redBilledLeiothrix,.blackCollaredStarling,
        .commonKingfisher,.littleRingedPlover,.yellowBilledGrosbeak,.redFlankedBluetail,
        .collaredScopsOwl,.asianBarredOwlet,.littleOwl
    ]
    private static let legacySpeciesSet=Set(legacySpecies)
    public var isExpansionSpecies:Bool {!Self.legacySpeciesSet.contains(species)}
    public var supportsSidePerching:Bool {
        species == .greatSpottedWoodpecker || species == .eurasianNuthatch
    }
    /// These slots intentionally render standing art. Their names are retained
    /// for the public 34-frame atlas contract, not evidence of an action clip.
    public var frameFallbacks:[String:String] {
        guard isExpansionSpecies else {return [:]}
        let names=["stretch","shake","poop0","poop1"] +
            (supportsSidePerching ? []:["cling0","cling1","peck0","peck1"])
        return Dictionary(uniqueKeysWithValues:names.map{($0,"stand")})
    }
    public var reviewedCapabilities:Set<BirdCapability> {
        isExpansionSpecies ? [.standing,.blinking,.flight,.landing]:Set(BirdCapability.allCases)
    }
    public func hasReviewedContent(for kind:BehaviorKind) -> Bool {
        // Base preen/idle drawings are still usable by the decorative scheduler.
        // A complete managed behavior needs its own review before it can count.
        !isExpansionSpecies || kind == .relocate
    }
    public static let dedicatedKinds:[BehaviorKind] = [.edgePeek,.chase,.travelTogether,.allopreening,.fixedPerchVisit,.foodTrayVisit,.bathVisit,.leafCarry,.insectCatch,.visitorGift,.courtshipDisplay,.nestMaterialCarry,.nestBuild]
    private static let permissions:[BehaviorKind:[SpeciesID]] = [
        .edgePeek:[.treeSparrow,.chineseBlackbird,.hoopoe,.whimbrel,.lightVentedBulbul,.magpieRobin],
        .chase:[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling,.redWhiskeredBulbul],
        .travelTogether:[.treeSparrow,.barnSwallow,.spottedDove,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling,.redWhiskeredBulbul],
        .allopreening:[.barnSwallow,.swinhoesWhiteEye],
        .fixedPerchVisit:[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.redWhiskeredBulbul,.magpieRobin,.redBilledLeiothrix,.lightVentedBulbul],
        .foodTrayVisit:[.treeSparrow,.spottedDove],
        .bathVisit:[.treeSparrow,.lightVentedBulbul],
        .leafCarry:[.treeSparrow],
        .insectCatch:[.barnSwallow,.yellowRumpedFlycatcher],
        .visitorGift:[.azureWingedMagpie],
        .courtshipDisplay:[.spottedDove],
        .nestMaterialCarry:[.spottedDove],
        .nestBuild:[.spottedDove]
    ]
    public static let ambientFlockSpecies:[SpeciesID] = [.treeSparrow,.barnSwallow,.swinhoesWhiteEye,
        .lightVentedBulbul,.azureWingedMagpie,.mallard,.blackHeadedGull,.blackCollaredStarling]
    public static let poseSpecies:[SpeciesID] = [.treeSparrow,.spottedDove,.barnSwallow,.nightHeron,
        .lightVentedBulbul,.redWhiskeredBulbul,.chineseBlackbird,.magpieRobin,.swinhoesWhiteEye,
        .azureWingedMagpie,.redBilledLeiothrix,.littleOwl]
    public static let catchFrameNames=["catchOpen","catchClose","catchRecover"]
    public static let courtshipFrameNames=["courtRaise","courtBow0","courtBow1","courtBowRecover","courtObserve"]
    public static let carryFrameNames=["carryLook","carryLower","carryGrip","carryPlace"]
    public static let nestCarryFrameNames=carryFrameNames
    public static let nestBuildFrameNames=["nestPlace","nestAdjust0","nestAdjust1","nestSettle"]
    public static let bathFrameNames=BathGeometry.frameNames
    public static let peekSpecies:[SpeciesID] = [.lightVentedBulbul,.magpieRobin]
    public static let peekFrameNames:[String] = ["peekLower","peekLook","peekRecover"]
    public static func profile(for species:SpeciesID) -> Self {Self(species:species)}
    public static func species(for kind:BehaviorKind) -> [SpeciesID] {
        if kind == .flockPass {return ambientFlockSpecies}
        if let allowed=permissions[kind] {return allowed}
        let catalog=SpeciesCatalog.standard.species.map(\.id)
        return kind == .relocate ? catalog:catalog.filter{legacySpeciesSet.contains($0)}
    }
    public func allows(_ kind:BehaviorKind) -> Bool {
        if kind == .flockPass {return Self.ambientFlockSpecies.contains(species)}
        if let allowed=Self.permissions[kind] {return allowed.contains(species)}
        return kind == .relocate || Self.legacySpeciesSet.contains(species)
    }
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
    public struct ContentReview:Codable {
        public let cohort:String
        public let fallbackFrames:[String:String]
        public let sidePerching:Bool
        public let managedBehaviorReviewPending:Bool
    }
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
    /// Optional so earlier exported support documents remain decodable.
    public let contentReview:ContentReview?
    public init(species:SpeciesID,availableFrames:Set<String>) {
        self.species=species
        let profile=SpeciesBehaviorProfile.profile(for:species)
        capabilities=BirdCapability.allCases.filter{
            profile.reviewedCapabilities.contains($0) && $0.requiredFrames.isSubset(of:availableFrames)
        }
        behaviors=BehaviorDefinitions.all.map {definition in
            let allowed=profile.allows(definition.kind)
            let missing=profile.requiredFrames(for:definition.kind).subtracting(availableFrames).sorted()
            return Behavior(kind:definition.kind,productAllowed:allowed,missingFrames:missing,
                contentSupported:allowed && profile.hasReviewedContent(for:definition.kind) && missing.isEmpty)
        }
        poseFrames=profile.poseFrameNames
        missingPoseFrames=poseFrames.filter{!availableFrames.contains($0)}
        contentReview=ContentReview(cohort:profile.isExpansionSpecies ? "upstream-v0.7-base":"local-46",
            fallbackFrames:profile.frameFallbacks,sidePerching:profile.supportsSidePerching,
            managedBehaviorReviewPending:profile.isExpansionSpecies)
    }
}
