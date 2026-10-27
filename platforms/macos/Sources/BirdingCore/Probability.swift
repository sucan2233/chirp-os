import Foundation

public struct ProbabilityEntry: Equatable {
    public let id: SpeciesID
    public let weight: Double
}

/// Stores only explicit edits. System defaults are always resolved from the shipped catalog.
public struct ProbabilityDistribution: Codable, Equatable {
    public static let defaultProfileID = "cn-national-balanced-v2"
    public static let defaultProfileVersion = 1
    public static let minimumPositiveWeight = 0.000001
    public static let maximumWeight = 1_000_000.0
    public var manualAdjustmentEnabled = false
    public private(set) var overrides: [String: Double] = [:]

    public init() {}
    public var entries: [ProbabilityEntry] {
        SpeciesCatalog.standard.species.map { ProbabilityEntry(id: $0.id,
            weight: manualAdjustmentEnabled ? (overrides[$0.id.rawValue] ?? $0.weight) : $0.weight) }
    }
    public func weight(for id: SpeciesID) -> Double {
        if manualAdjustmentEnabled, let value = overrides[id.rawValue] { return value }
        return SpeciesCatalog.standard.profile(id).weight
    }
    public func participates(_ id: SpeciesID) -> Bool { weight(for: id) > 0 }
    public var totalWeight: Double { entries.reduce(0) { $0 + $1.weight } }
    public func share(for id: SpeciesID) -> Double {
        let total = totalWeight
        return total > 0 ? weight(for: id) / total : 0
    }
    public static func isValidWeight(_ value: Double) -> Bool {
        value.isFinite && (value == 0 || (minimumPositiveWeight...maximumWeight).contains(value))
    }
    public var isValid: Bool { overrides.allSatisfy { !$0.key.isEmpty && Self.isValidWeight($0.value) } }
    /// Explicit programmatic/manual edit. Callers control when the manual mode becomes active.
    @discardableResult public mutating func setWeight(_ weight: Double, for id: SpeciesID) -> Bool {
        guard Self.isValidWeight(weight) else { return false }
        overrides[id.rawValue] = weight
        return true
    }
    /// Applies an explicit edit and activates manual mode without redistributing other weights.
    @discardableResult public mutating func setManualWeight(at index: Int, to weight: Double) -> Bool {
        guard SpeciesCatalog.standard.species.indices.contains(index),
              setWeight(weight, for: SpeciesCatalog.standard.species[index].id) else { return false }
        manualAdjustmentEnabled = true
        return true
    }
    public mutating func resetToDefaults() { manualAdjustmentEnabled = false; overrides = [:] }
    public func choose(unit: Double) -> SpeciesID? {
        try? WeightedChoice(entries, weight: { $0.weight }).choose(unit: unit)?.id
    }
    public func choose(using random: () -> Double) -> SpeciesID? {
        try? WeightedChoice(entries, weight: { $0.weight }).choose(using: random)?.id
    }
    private enum CodingKeys: String, CodingKey { case manualAdjustmentEnabled, overrides }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        manualAdjustmentEnabled = try values.decode(Bool.self, forKey: .manualAdjustmentEnabled)
        overrides = try values.decode([String: Double].self, forKey: .overrides)
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .overrides, in: values, debugDescription: "Invalid relative weight.")
        }
    }
}

/// Decode-only legacy contract. There is no legacy probability engine or allocator in V2.
private struct LegacyProbabilityDistribution: Decodable {
    struct Entry: Decodable { let id: SpeciesID; let points: Int; let locked: Bool }
    let entries: [Entry]
    func validate(catalog: SpeciesCatalog) throws {
        guard !entries.isEmpty, Set(entries.map(\.id)).count == entries.count,
              Set(entries.map(\.id)) == Set(catalog.species.map(\.id)),
              entries.allSatisfy({ (0...10_000).contains($0.points) }),
              entries.reduce(0, { $0 + $1.points }) == 10_000 else {
            throw NSError(domain: "BirdSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: "旧概率配置无效，未迁移。"])
        }
    }
}

public struct ProbabilityMigration: Codable, Equatable {
    public let fromSchemaVersion: Int
    public let strategy: String
    public init(fromSchemaVersion: Int) {
        self.fromSchemaVersion = fromSchemaVersion; strategy = "replace-with-system-defaults"
    }
}
public enum BirdSettingsVersionError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case invalidVersion

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "配置文件版本 \(version) 高于当前支持的版本 \(BirdSettings.currentSchemaVersion)，请升级应用后再打开。"
        case .invalidVersion:
            return "配置文件的 schemaVersion 无效：必须是非负整数。"
        }
    }
}

public struct BirdSettings: Codable {
    public static let currentSchemaVersion = 3
    public let schemaVersion: Int
    public static let hoverDelayRange:ClosedRange<Double> = 0...10
    public var catalog: SpeciesCatalog
    public var probabilities: ProbabilityDistribution
    public var hoverDelay:Double = 1
    public var pointerVisits = true
    public var pointerFollowEnabled = false
    public var flockPasses = true
    public var socialInteractions = true
    public var perchActions = true
    public var passiveAttentionEnabled = true
    public var sideHopEnabled = true
    public var takeoffPreparationEnabled = true
    public var edgePeekEnabled = true
    public var chaseEnabled = true
    public var travelTogetherEnabled = true
    public var allopreeningEnabled = true
    public var leafPlayEnabled = true
    public var ambientLeafPlayEnabled = true
    public var visitorMemoryEnabled = true
    public var visitorGiftsEnabled = false
    public var courtshipEnabled = true
    public var nestBuildingEnabled = true
    public var fixedPerchesEnabled = true
    public var fixedPerches: [FixedPerchAnchor] = []
    public var insectCatchEnabled = true
    public var leafCarryEnabled = true
    public var bathEnabled = true
    public var foodTrayEnabled = true
    public var ambientFrequency: AmbientFrequency = .low
    public var activityRhythm: ActivityRhythmMode = .steady
    /// nil is the legacy core adapter, retained for old fixtures and explicit compatibility.
    public var companion:CompanionPreferences? = nil
    public static var companionDefaults:BirdSettings {var s=BirdSettings();s.companion=CompanionPreferences();return s}
    public var perchDefaultsVersion: Int? = nil
    public var migration: ProbabilityMigration? = nil
    public init(catalog:SpeciesCatalog = .standard) {
        schemaVersion=Self.currentSchemaVersion
        self.catalog = catalog; probabilities = ProbabilityDistribution(); perchDefaultsVersion=1
    }
    private enum CodingKeys:String,CodingKey {
        case schemaVersion
        case catalog,hoverDelay,perchDefaultsVersion,migration
        case probabilities = "speciesProbability"
        case pointerVisits,pointerFollowEnabled,flockPasses,ambientFrequency,perchActions,socialInteractions,leafPlayEnabled
        case passiveAttentionEnabled,ambientLeafPlayEnabled,sideHopEnabled,takeoffPreparationEnabled
        case companion
        case visitorMemoryEnabled,activityRhythm,edgePeekEnabled,chaseEnabled,travelTogetherEnabled,allopreeningEnabled
        case fixedPerchesEnabled,fixedPerches
        case foodTrayEnabled,bathEnabled,leafCarryEnabled,insectCatchEnabled,visitorGiftsEnabled,courtshipEnabled,nestBuildingEnabled
    }
    @discardableResult private static func validateSchemaVersion(in values:KeyedDecodingContainer<CodingKeys>) throws -> Int {
        // Absence alone denotes version 0; null and malformed values are not legacy versions.
        let version: Int
        if values.contains(.schemaVersion) {
            do { version=try values.decode(Int.self,forKey:.schemaVersion) }
            catch { throw BirdSettingsVersionError.invalidVersion }
        } else { version=0 }
        guard version>=0 else { throw BirdSettingsVersionError.invalidVersion }
        guard version<=currentSchemaVersion else { throw BirdSettingsVersionError.unsupportedVersion(version) }
        return version
    }
    // Check only the version contract when replacing a file, not its catalog or settings.
    private struct SchemaVersionHeader: Decodable {
        let version: Int
        init(from decoder:Decoder) throws {
            version = try BirdSettings.validateSchemaVersion(in:decoder.container(keyedBy:CodingKeys.self))
        }
    }
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        let sourceVersion = try Self.validateSchemaVersion(in:values)
        schemaVersion=Self.currentSchemaVersion
        catalog=try values.decode(SpeciesCatalog.self,forKey:.catalog)
        if sourceVersion < 2 {
            enum LegacyKeys: String, CodingKey { case probabilities }
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            try legacy.decode(LegacyProbabilityDistribution.self, forKey: .probabilities).validate(catalog: catalog)
            probabilities = ProbabilityDistribution()
            migration = ProbabilityMigration(fromSchemaVersion: sourceVersion)
        } else {
            probabilities = try values.decode(ProbabilityDistribution.self, forKey: .probabilities)
            migration = try values.decodeIfPresent(ProbabilityMigration.self, forKey: .migration)
        }
        hoverDelay=try values.decodeIfPresent(Double.self,forKey:.hoverDelay) ?? 1
        pointerVisits=try values.decodeIfPresent(Bool.self,forKey:.pointerVisits) ?? true
        pointerFollowEnabled=try values.decodeIfPresent(Bool.self,forKey:.pointerFollowEnabled) ?? false
        flockPasses=try values.decodeIfPresent(Bool.self,forKey:.flockPasses) ?? true
        socialInteractions=try values.decodeIfPresent(Bool.self,forKey:.socialInteractions) ?? true
        perchActions=try values.decodeIfPresent(Bool.self,forKey:.perchActions) ?? true
        passiveAttentionEnabled=try values.decodeIfPresent(Bool.self,forKey:.passiveAttentionEnabled) ?? true
        sideHopEnabled=try values.decodeIfPresent(Bool.self,forKey:.sideHopEnabled) ?? true
        takeoffPreparationEnabled=try values.decodeIfPresent(Bool.self,forKey:.takeoffPreparationEnabled) ?? true
        edgePeekEnabled=try values.decodeIfPresent(Bool.self,forKey:.edgePeekEnabled) ?? true
        chaseEnabled=try values.decodeIfPresent(Bool.self,forKey:.chaseEnabled) ?? true
        travelTogetherEnabled=try values.decodeIfPresent(Bool.self,forKey:.travelTogetherEnabled) ?? true
        allopreeningEnabled=try values.decodeIfPresent(Bool.self,forKey:.allopreeningEnabled) ?? true
        leafPlayEnabled=try values.decodeIfPresent(Bool.self,forKey:.leafPlayEnabled) ?? true
        ambientLeafPlayEnabled=try values.decodeIfPresent(Bool.self,forKey:.ambientLeafPlayEnabled) ?? true
        visitorMemoryEnabled=try values.decodeIfPresent(Bool.self,forKey:.visitorMemoryEnabled) ?? true
        visitorGiftsEnabled=try values.decodeIfPresent(Bool.self,forKey:.visitorGiftsEnabled) ?? false
        courtshipEnabled=try values.decodeIfPresent(Bool.self,forKey:.courtshipEnabled) ?? true
        nestBuildingEnabled=try values.decodeIfPresent(Bool.self,forKey:.nestBuildingEnabled) ?? true
        fixedPerchesEnabled=try values.decodeIfPresent(Bool.self,forKey:.fixedPerchesEnabled) ?? true
        insectCatchEnabled=try values.decodeIfPresent(Bool.self,forKey:.insectCatchEnabled) ?? true
        leafCarryEnabled=try values.decodeIfPresent(Bool.self,forKey:.leafCarryEnabled) ?? true
        bathEnabled=try values.decodeIfPresent(Bool.self,forKey:.bathEnabled) ?? true
        foodTrayEnabled=try values.decodeIfPresent(Bool.self,forKey:.foodTrayEnabled) ?? true
        // Missing keys are legacy defaults; explicit null is malformed anchor data.
        if values.contains(.fixedPerches) {
            fixedPerches=try values.decode([FixedPerchAnchor].self,forKey:.fixedPerches)
        } else {fixedPerches=[]}
        guard fixedPerches.count<=FixedPerchLayout.maximumCount,
              Set(fixedPerches.map(\.slot)).count==fixedPerches.count,
              fixedPerches.allSatisfy(\.isValid) else {
            throw DecodingError.dataCorruptedError(forKey:.fixedPerches,in:values,
                debugDescription:"Fixed perches must contain at most three valid anchors with unique slots.")
        }
        ambientFrequency=try values.decodeIfPresent(AmbientFrequency.self,forKey:.ambientFrequency) ?? .low
        activityRhythm=try values.decodeIfPresent(ActivityRhythmMode.self,forKey:.activityRhythm) ?? .steady
        companion=try values.decodeIfPresent(CompanionPreferences.self,forKey:.companion)
        try companion?.validate()
        perchDefaultsVersion=try values.decodeIfPresent(Int.self,forKey:.perchDefaultsVersion)
        if sourceVersion<3 {companion=CompanionPreferences.migrate(self)}
        guard hoverDelay.isFinite,Self.hoverDelayRange.contains(hoverDelay) else {
            throw DecodingError.dataCorruptedError(forKey:.hoverDelay,in:values,debugDescription:"Hover delay must be between 0 and 10 seconds.")
        }
    }
    public static func decode(_ data:Data) throws -> BirdSettings {
        var value = try JSONDecoder().decode(Self.self,from:data)
        guard Set(value.catalog.species.map(\.id)).count == value.catalog.species.count else { throw NSError(domain:"BirdSettings",code:3) }
        let present = Set(value.catalog.species.map(\.id))
        let added=SpeciesCatalog.standard.species.filter { !present.contains($0.id) }
        // Upgrade only old default wingbeat values. User-adjusted rates survive.
        for i in value.catalog.species.indices {
            let id=value.catalog.species[i].id, current=SpeciesCatalog.standard.profile(value.catalog.species[i].id).flapFPS
            let old=current / FlightBehavior.motion(id).rate
            if abs(value.catalog.species[i].flapFPS-old) < 0.0001 { value.catalog.species[i].flapFPS=current }
        }
        if (value.perchDefaultsVersion ?? 0)<1 {
            for i in value.catalog.species.indices {
                let current=SpeciesCatalog.standard.profile(value.catalog.species[i].id)
                // Only migrate the complete former default range, never a custom endpoint.
                if value.catalog.species[i].perchMin == current.perchMin/2 && value.catalog.species[i].perchMax == current.perchMax/2 {
                    value.catalog.species[i].perchMin=current.perchMin
                    value.catalog.species[i].perchMax=current.perchMax
                }
            }
        }
        value.perchDefaultsVersion=1
        // Refresh descriptive metadata without replacing user size, speed,
        // animation timing. Probability defaults come exclusively from the current catalog.
        value.catalog.species=value.catalog.species.map { old in
            let current=SpeciesCatalog.standard.profile(old.id)
            return SpeciesProfile(id:old.id,name:current.name,englishName:current.englishName,
                scientificName:current.scientificName,appearanceNotes:current.appearanceNotes,
                adultLengthCM:old.adultLengthCM,weight:current.weight,flapFPS:old.flapFPS,
                speed:old.speed,perchMin:old.perchMin,perchMax:old.perchMax,weightBasis:current.weightBasis)
        }
        value.catalog.species += added
        _ = try SpeciesCatalog.decode(JSONEncoder().encode(value.catalog))
        guard value.probabilities.isValid else { throw NSError(domain:"BirdSettings",code:1) }
        return value
    }
    public func save(to url:URL) throws {
        let existing = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        var previousVersion: Int?
        if let existing {
            previousVersion = try JSONDecoder().decode(SchemaVersionHeader.self, from: existing).version
            // A failed load must never turn into an implicit destructive repair.
            _ = try Self.decode(existing)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let data = try encoder.encode(self)
        _ = try Self.decode(data)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if let existing, let previousVersion, previousVersion < Self.currentSchemaVersion {
            let backup = url.appendingPathExtension("pre-schema-\(previousVersion)-" + UUID().uuidString + ".bak")
            try existing.write(to: backup, options: .withoutOverwriting)
        }
        try data.write(to:url,options:.atomic)
    }
    public static func load(from url:URL, legacyURL:URL) throws -> BirdSettings {
        if FileManager.default.fileExists(atPath:url.path) { return try decode(Data(contentsOf:url)) }
        if FileManager.default.fileExists(atPath:legacyURL.path) {
            var catalog=try JSONDecoder().decode(SpeciesCatalog.self,from:Data(contentsOf:legacyURL))
            guard !catalog.species.isEmpty, Set(catalog.species.map(\.id)).count == catalog.species.count else {
                throw NSError(domain:"BirdSettings",code:3)
            }
            let ids=Set(catalog.species.map(\.id))
            catalog.species += SpeciesCatalog.standard.species.filter{!ids.contains($0.id)}
            var result=BirdSettings(catalog:try SpeciesCatalog.decode(JSONEncoder().encode(catalog)))
            result.migration = ProbabilityMigration(fromSchemaVersion: 0)
            result.perchDefaultsVersion=nil
            result.companion=CompanionPreferences.migrate(result)
            // The original legacy file remains intact as the rollback copy.
            return try decode(JSONEncoder().encode(result))
        }
        return BirdSettings.companionDefaults
    }
}
