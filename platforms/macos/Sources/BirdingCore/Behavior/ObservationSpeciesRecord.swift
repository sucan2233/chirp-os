import Foundation

public enum ObservationDiscoverySource:String,Codable,CaseIterable {
    case manual,automatic,user,historicalBehavior,lifeList
}

/// Dates from old mixed-source aggregates are deliberately kept separate from
/// dates whose discovery source is known. Life List has no last-recorded date.
public struct ObservationSpeciesRecord:Codable,Equatable {
    public let species:SpeciesID
    public internal(set) var manualCount:Int=0
    public internal(set) var manualFirstRecordedAt:Date?
    public internal(set) var manualLastRecordedAt:Date?
    public internal(set) var firstDiscoveredAt:Date?
    public internal(set) var lastDiscoveredAt:Date?
    public internal(set) var historicalFirstSeen:Date?
    public internal(set) var discoverySources:[ObservationDiscoverySource]=[]

    public init(species:SpeciesID) {self.species=species}
    mutating func discover(source:ObservationDiscoverySource,at date:Date?) {
        if !discoverySources.contains(source) {
            discoverySources.append(source);discoverySources.sort{$0.rawValue<$1.rawValue}
        }
        if let date {
            firstDiscoveredAt=min(firstDiscoveredAt ?? date,date)
            lastDiscoveredAt=max(lastDiscoveredAt ?? date,date)
        }
    }
    func validate() throws {
        let dates=[manualFirstRecordedAt,manualLastRecordedAt,firstDiscoveredAt,lastDiscoveredAt,historicalFirstSeen].compactMap{$0}
        guard (0...ObservationArchive.maximumCount).contains(manualCount),
              dates.allSatisfy(ObservationArchive.validDate),
              !discoverySources.isEmpty,Set(discoverySources).count==discoverySources.count,
              manualCount==0 || manualFirstRecordedAt != nil,
              manualLastRecordedAt==nil || manualFirstRecordedAt != nil,
              lastDiscoveredAt==nil || firstDiscoveredAt != nil,
              manualCount==0 || discoverySources.contains(.manual) || discoverySources.contains(.lifeList) else {
            throw ObservationJournalError.invalid("invalid species discovery record")
        }
        if let first=manualFirstRecordedAt,let last=manualLastRecordedAt,first>last {
            throw ObservationJournalError.invalid("manual date range moved backwards")
        }
        if let first=firstDiscoveredAt,let last=lastDiscoveredAt,first>last {
            throw ObservationJournalError.invalid("discovery date range moved backwards")
        }
    }
}

public struct ObservationMigration:Codable,Equatable {
    public internal(set) var convertedVersions:[Int]=[]
    /// A fixed source slot, independent of file fingerprint: changed old files
    /// must never be added again after a successful one-time import.
    public internal(set) var lifeList:ObservationLifeListImport?
    public init() {}
}
public struct ObservationLifeListImport:Codable,Equatable {
    public let sourceSlot:String
    public let fingerprint:String
    public let enabled:Bool
    public init(fingerprint:String,enabled:Bool) {
        sourceSlot="upstream-life-list";self.fingerprint=fingerprint;self.enabled=enabled
    }
}
public struct ObservationWriterProgress:Codable,Equatable {
    public let writerID:UUID
    public let slot:Int
    public let sequence:UInt64
    public init(writerID:UUID,slot:Int,sequence:UInt64) {
        self.writerID=writerID;self.slot=slot;self.sequence=sequence
    }
}

/// Strictly recognizes only the shipped upstream schema, including ISO dates.
/// Extra keys are rejected so importing cannot silently lose future semantics.
public struct ObservationLegacyLifeList {
    public let records:[SpeciesID:LifeRecord]
    public let enabled:Bool
    public static func decode(_ data:Data) throws -> Self {
        guard data.count<=ObservationArchive.maximumBytes,
              let raw=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(raw.keys).isSubset(of:["enabled","introductionVersion","records"]),
              let entries=raw["records"] as? [String:Any],entries.count<=SpeciesID.allCases.count else {
            throw ObservationJournalError.invalid("unsupported Life List structure")
        }
        for (key,value) in entries {
            guard SpeciesID(rawValue:key) != nil,let record=value as? [String:Any],
                  Set(record.keys)==["count","firstRecordedAt"] else {
                throw ObservationJournalError.invalid("unknown Life List species or record fields")
            }
        }
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let list=try decoder.decode(LifeList.self,from:data)
        guard list.introductionVersion==nil || list.introductionVersion==1,
              list.records.values.allSatisfy({(1...ObservationArchive.maximumCount).contains($0.count) && ObservationArchive.validDate($0.firstRecordedAt)}) else {
            throw ObservationJournalError.invalid("unsupported Life List version, date or count")
        }
        return Self(records:Dictionary(uniqueKeysWithValues:list.records.map{(SpeciesID(rawValue:$0.key)!,$0.value)}),enabled:list.enabled)
    }
}
