import Foundation

extension ObservationArchive {
    /// Pure delta merge. The caller owns the sidecar lock and a stable pending
    /// batch identity. Disk is authoritative; no stale snapshot replaces it.
    public static func merging(local:Self,baseline:Self,disk:Self?) throws -> Self {
        try local.validate();try baseline.validate()
        guard let disk else {return local}
        try disk.validate()
        func key(_ entry:ObservationEntry)->String {entry.species.rawValue+":"+entry.behavior}
        let old=Dictionary(uniqueKeysWithValues:baseline.entries.map{(key($0),$0)})
        var merged=Dictionary(uniqueKeysWithValues:disk.entries.map{(key($0),$0)})
        for entry in local.entries {
            let previous=old[key(entry)]
            guard entry != previous else {continue}
            let increments=[entry.automaticCount-(previous?.automaticCount ?? 0),
                            entry.previewCount-(previous?.previewCount ?? 0),entry.userCount-(previous?.userCount ?? 0)]
            guard increments.allSatisfy({$0>=0}) else {throw ObservationJournalError.invalid("local counters moved backwards")}
            let existing=merged[key(entry)]
            let counts=[existing?.automaticCount ?? 0,existing?.previewCount ?? 0,existing?.userCount ?? 0]
            let totals=zip(counts,increments).map{min(Self.maximumCount,$0+$1)}
            guard totals.reduce(0,+)>0 else {continue}
            merged[key(entry)]=ObservationEntry(species:entry.species,behavior:entry.behavior,
                firstSeen:min(existing?.firstSeen ?? entry.firstSeen,entry.firstSeen),
                lastSeen:max(existing?.lastSeen ?? entry.lastSeen,entry.lastSeen),
                automaticCount:totals[0],previewCount:totals[1],userCount:totals[2])
        }
        let oldSpecies=Dictionary(uniqueKeysWithValues:baseline.speciesRecords.map{($0.species,$0)})
        var records=Dictionary(uniqueKeysWithValues:disk.speciesRecords.map{($0.species,$0)})
        for record in local.speciesRecords where record != oldSpecies[record.species] {
            let increment=record.manualCount-(oldSpecies[record.species]?.manualCount ?? 0)
            guard increment>=0 else {throw ObservationJournalError.invalid("manual count moved backwards")}
            var combined=records[record.species] ?? ObservationSpeciesRecord(species:record.species)
            combined.manualCount=min(Self.maximumCount,combined.manualCount+increment)
            combined.manualFirstRecordedAt=earliest(combined.manualFirstRecordedAt,record.manualFirstRecordedAt)
            combined.manualLastRecordedAt=latest(combined.manualLastRecordedAt,record.manualLastRecordedAt)
            combined.firstDiscoveredAt=earliest(combined.firstDiscoveredAt,record.firstDiscoveredAt)
            combined.lastDiscoveredAt=latest(combined.lastDiscoveredAt,record.lastDiscoveredAt)
            combined.historicalFirstSeen=earliest(combined.historicalFirstSeen,record.historicalFirstSeen)
            for source in record.discoverySources {combined.discover(source:source,at:nil)}
            records[record.species]=combined
        }
        // Imports are committed independently under the same disk lock before
        // restoring a journal, never represented as retryable manual deltas.
        guard local.migration.lifeList==baseline.migration.lifeList else {
            throw ObservationJournalError.invalid("Life List import must use the migration transaction")
        }
        var migration=disk.migration
        migration.convertedVersions=Array(Set(migration.convertedVersions+local.migration.convertedVersions)).sorted()
        let result=Self(entries:merged.values.sorted{
            $0.species == $1.species ? $0.behavior<$1.behavior:$0.species.rawValue<$1.species.rawValue
        },speciesRecords:records.values.sorted{$0.species.rawValue<$1.species.rawValue},
        migration:migration,writerProgress:disk.writerProgress)
        try result.validate();return result
    }
    private static func earliest(_ a:Date?,_ b:Date?)->Date? {
        guard let a else {return b};guard let b else {return a};return min(a,b)
    }
    private static func latest(_ a:Date?,_ b:Date?)->Date? {
        guard let a else {return b};guard let b else {return a};return max(a,b)
    }
    public func importing(_ legacy:ObservationLegacyLifeList,fingerprint:String) throws -> Self {
        guard migration.lifeList==nil else {return self}
        var result=self
        for species in legacy.records.keys.sorted(by:{$0.rawValue<$1.rawValue}) {
            let old=legacy.records[species]!
            var record=result.speciesRecord(for:species) ?? ObservationSpeciesRecord(species:species)
            record.manualCount=min(Self.maximumCount,record.manualCount+old.count)
            record.manualFirstRecordedAt=Self.earliest(record.manualFirstRecordedAt,old.firstRecordedAt)
            // No legacy last date exists. Keep nil unless a newer local record supplies it.
            record.discover(source:.lifeList,at:nil)
            record.firstDiscoveredAt=Self.earliest(record.firstDiscoveredAt,old.firstRecordedAt)
            result.speciesRecords.removeAll{$0.species==species};result.speciesRecords.append(record)
        }
        result.speciesRecords.sort{$0.species.rawValue<$1.species.rawValue}
        result.migration.lifeList=ObservationLifeListImport(fingerprint:fingerprint,enabled:legacy.enabled)
        try result.validate();return result
    }
}
