import Foundation

public enum VisitorMemoryError:Error,LocalizedError {
    case invalid(String)
    public var errorDescription:String? {
        if case let .invalid(reason)=self {return "Invalid visitor memory: \(reason)"}
        return nil
    }
}

/// Decimal strings preserve all 64 bits in JSON and have one canonical spelling.
private func visitorInteger(_ text:String,field:String,allowZero:Bool=true) throws -> UInt64 {
    guard text.utf8.count<=20,let value=UInt64(text),String(value)==text,
          allowZero || value>0 else {throw VisitorMemoryError.invalid("invalid \(field)")}
    return value
}

public struct VisitorProfile:Codable,Equatable {
    public let id:String
    public let species:SpeciesID
    public let seed:String
    public fileprivate(set) var calmSeconds:Double
    public fileprivate(set) var visits:Int
    public fileprivate(set) var lastVisitOrdinal:String

    public var temperament:BirdTemperament {
        BirdTemperament(seed:UInt64(seed)!,birdID:BirdID(UInt64(id)!))
    }
    public var familiarity:Double {calmSeconds/300}

    fileprivate static let maximumVisits=1_000_000_000
    private enum CodingKeys:String,CodingKey {case id,species,seed,calmSeconds,visits,lastVisitOrdinal}

    fileprivate init(id:UInt64,species:SpeciesID,seed:String,ordinal:UInt64) {
        self.id=String(id);self.species=species;self.seed=seed
        calmSeconds=0;visits=1;lastVisitOrdinal=String(ordinal)
    }
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        id=try values.decode(String.self,forKey:.id)
        species=try values.decode(SpeciesID.self,forKey:.species)
        seed=try values.decode(String.self,forKey:.seed)
        calmSeconds=try values.decode(Double.self,forKey:.calmSeconds)
        visits=try values.decode(Int.self,forKey:.visits)
        lastVisitOrdinal=try values.decode(String.self,forKey:.lastVisitOrdinal)
        try validate()
    }
    fileprivate func validate() throws {
        let number=try visitorInteger(id,field:"profile ID",allowZero:false)
        _=try visitorInteger(seed,field:"profile seed")
        let ordinal=try visitorInteger(lastVisitOrdinal,field:"profile visit ordinal",allowZero:false)
        guard calmSeconds.isFinite,(0...300).contains(calmSeconds),
              (1...Self.maximumVisits).contains(visits),ordinal>=number,
              UInt64(visits)<=ordinal-number+1 else {
            throw VisitorMemoryError.invalid("invalid profile bounds or visit order")
        }
    }
}

/// Version 1 contains only persistent profiles and logical counters, never leases.
public struct VisitorMemoryArchive:Codable,Equatable {
    public static let maximumProfiles=128
    public static let maximumBytes=262_144
    public static let currentVersion=1

    public let version:Int
    public let seed:String
    public fileprivate(set) var nextID:String
    public fileprivate(set) var visitOrdinal:String
    public fileprivate(set) var profiles:[VisitorProfile]

    private enum CodingKeys:String,CodingKey {case version,seed,nextID,visitOrdinal,profiles}

    fileprivate init(seed:UInt64) {
        version=Self.currentVersion;self.seed=String(seed)
        nextID="1";visitOrdinal="0";profiles=[]
    }
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        version=try values.decode(Int.self,forKey:.version)
        // Check the envelope before attempting to interpret a future nested schema.
        guard version==Self.currentVersion else {throw VisitorMemoryError.invalid("unsupported version \(version)")}
        seed=try values.decode(String.self,forKey:.seed)
        nextID=try values.decode(String.self,forKey:.nextID)
        visitOrdinal=try values.decode(String.self,forKey:.visitOrdinal)
        var nested=try values.nestedUnkeyedContainer(forKey:.profiles)
        var decoded:[VisitorProfile]=[]
        while !nested.isAtEnd {
            guard decoded.count<Self.maximumProfiles else {throw VisitorMemoryError.invalid("too many profiles")}
            decoded.append(try nested.decode(VisitorProfile.self))
        }
        profiles=decoded
        try validate()
    }
    public func validate() throws {
        guard version==Self.currentVersion,profiles.count<=Self.maximumProfiles else {
            throw VisitorMemoryError.invalid("unsupported version or too many profiles")
        }
        _=try visitorInteger(seed,field:"archive seed")
        let next=try visitorInteger(nextID,field:"next ID",allowZero:false)
        let ordinal=try visitorInteger(visitOrdinal,field:"visit ordinal")
        guard ordinal>=next-1,UInt64(profiles.count)<=next-1 else {
            throw VisitorMemoryError.invalid("allocation counters precede profiles")
        }
        var ids=Set<String>(),ordinals=Set<UInt64>(),totalVisits:UInt64=0,latest:UInt64=0
        for profile in profiles {
            try profile.validate()
            let number=try visitorInteger(profile.id,field:"profile ID",allowZero:false)
            let last=try visitorInteger(profile.lastVisitOrdinal,field:"profile visit ordinal",allowZero:false)
            guard number<next,last<=ordinal,ids.insert(profile.id).inserted,ordinals.insert(last).inserted else {
                throw VisitorMemoryError.invalid("duplicate profile or inconsistent visit order")
            }
            totalVisits+=UInt64(profile.visits)
            latest=max(latest,last)
        }
        guard totalVisits<=ordinal,latest==ordinal,
              !profiles.isEmpty || next==1 else {throw VisitorMemoryError.invalid("inconsistent visit counters")}
    }
    public static func decode(_ data:Data) throws -> Self {
        guard data.count<=maximumBytes else {throw VisitorMemoryError.invalid("file exceeds 256 KiB")}
        do {return try JSONDecoder().decode(Self.self,from:data)}
        catch let error as VisitorMemoryError {throw error}
        catch {throw VisitorMemoryError.invalid("malformed archive: \(error.localizedDescription)")}
    }
    public static func load(from url:URL) throws -> Self {
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size<=maximumBytes else {throw VisitorMemoryError.invalid("file exceeds 256 KiB")}
        let handle=try FileHandle(forReadingFrom:url)
        defer {try? handle.close()}
        var data=Data()
        // Also bound the actual read if the file changes after the metadata check.
        while let chunk=try handle.read(upToCount:maximumBytes+1-data.count),!chunk.isEmpty {
            data.append(chunk)
            guard data.count<=maximumBytes else {throw VisitorMemoryError.invalid("file exceeds 256 KiB")}
        }
        return try decode(data)
    }
    public func save(to url:URL) throws {
        try validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(self)
        guard data.count<=Self.maximumBytes else {throw VisitorMemoryError.invalid("file exceeds 256 KiB")}
        let files=FileManager.default
        let exists:Bool
        do {_=try files.attributesOfItem(atPath:url.path);exists=true}
        catch {
            let failure=error as NSError
            guard failure.domain==NSCocoaErrorDomain,
                  [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(failure.code) else {throw error}
            exists=false
        }
        // Even an unreadable, corrupt, or newer existing archive must survive.
        if exists {_=try Self.load(from:url)}
        try files.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
    }
}

/// The engine owns calm eligibility and serializes access to this session store.
public final class VisitorMemory {
    private var stored:VisitorMemoryArchive
    private var active=Set<String>()

    public init(seed:UInt64) {stored=VisitorMemoryArchive(seed:seed)}
    public var archive:VisitorMemoryArchive {stored}
    public var activeCount:Int {active.count}
    public var profileCount:Int {stored.profiles.count}

    public func restore(_ archive:VisitorMemoryArchive) throws {
        guard active.isEmpty else {throw VisitorMemoryError.invalid("cannot restore while visitors are active")}
        try archive.validate()
        stored=archive
    }
    public func acquire(species:SpeciesID) -> VisitorProfile? {
        let ordinal=UInt64(stored.visitOrdinal)!
        guard ordinal<UInt64.max else {return nil}
        let inactive=stored.profiles.indices.filter{!active.contains(stored.profiles[$0].id)}
        func older(_ a:Int,_ b:Int) -> Bool {
            UInt64(stored.profiles[a].lastVisitOrdinal)! < UInt64(stored.profiles[b].lastVisitOrdinal)!
        }
        let index:Int
        if let match=inactive.filter({stored.profiles[$0].species==species}).min(by:older) {
            index=match
            stored.profiles[index].visits=min(VisitorProfile.maximumVisits,stored.profiles[index].visits+1)
            stored.profiles[index].lastVisitOrdinal=String(ordinal+1)
        } else {
            let next=UInt64(stored.nextID)!
            guard next<UInt64.max else {return nil}
            let new=VisitorProfile(id:next,species:species,seed:stored.seed,ordinal:ordinal+1)
            if stored.profiles.count<VisitorMemoryArchive.maximumProfiles {
                index=stored.profiles.count;stored.profiles.append(new)
            } else {
                guard let victim=inactive.min(by:older) else {return nil}
                index=victim;stored.profiles[index]=new
            }
            stored.nextID=String(next+1)
        }
        stored.visitOrdinal=String(ordinal+1)
        let result=stored.profiles[index]
        active.insert(result.id)
        return result
    }
    public func release(_ id:String) {active.remove(id)}
    public func learn(_ id:String,elapsed:Double) {
        guard active.contains(id),elapsed.isFinite,elapsed>0,
              let index=stored.profiles.firstIndex(where:{$0.id==id}) else {return}
        stored.profiles[index].calmSeconds=min(300,stored.profiles[index].calmSeconds+min(0.05,elapsed))
    }
    public func profile(_ id:String) -> VisitorProfile? {stored.profiles.first{$0.id==id}}
}
