import Foundation

/// A request names immutable identities, not merely the current screen positions.
public struct GiftBinding: Codable, Equatable {
    public let requestID: String
    public let visitorArchiveSeed: String
    public let visitorID: String
    public let birdID: BirdID
    public let species: SpeciesID
    public let source: BehaviorSource
    public let leafID: ScenePropID
    public let receiverSlot: Int
    public let receiverRevision: UInt64

    public init(requestID: String, visitorArchiveSeed: String, visitorID: String,
                birdID: BirdID, species: SpeciesID, source: BehaviorSource,
                leafID: ScenePropID, receiverSlot: Int, receiverRevision: UInt64) {
        self.requestID=requestID; self.visitorArchiveSeed=visitorArchiveSeed
        self.visitorID=visitorID; self.birdID=birdID; self.species=species
        self.source=source; self.leafID=leafID; self.receiverSlot=receiverSlot
        self.receiverRevision=receiverRevision
    }
    public var isValid: Bool {
        func canonical(_ text: String, zero: Bool=false) -> Bool {
            guard text.utf8.count<=20,let value=UInt64(text),String(value)==text else {return false}
            return zero || value>0
        }
        return canonical(requestID) && canonical(visitorArchiveSeed,zero:true) &&
            canonical(visitorID) && birdID.rawValue>0 && leafID.rawValue>0 &&
            species == .azureWingedMagpie && (source == .automatic || source == .preview) &&
            (1...FixedPerchLayout.maximumCount).contains(receiverSlot) && receiverRevision>0
    }
    private enum CodingKeys: String, CodingKey {
        case requestID,visitorArchiveSeed,visitorID,birdID,species,source,leafID,receiverSlot,receiverRevision
    }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        self.init(requestID:try c.decode(String.self,forKey:.requestID),
            visitorArchiveSeed:try c.decode(String.self,forKey:.visitorArchiveSeed),
            visitorID:try c.decode(String.self,forKey:.visitorID),
            birdID:try c.decode(BirdID.self,forKey:.birdID),species:try c.decode(SpeciesID.self,forKey:.species),
            source:try c.decode(BehaviorSource.self,forKey:.source),leafID:try c.decode(ScenePropID.self,forKey:.leafID),
            receiverSlot:try c.decode(Int.self,forKey:.receiverSlot),receiverRevision:try c.decode(UInt64.self,forKey:.receiverRevision))
        guard isValid else {throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid gift binding"))}
    }
}

public struct GiftAuthorizationRequest: Codable, Equatable {
    public let binding: GiftBinding
    public init(binding: GiftBinding) {self.binding=binding}
}

public struct GiftAuthorizationToken: Codable, Equatable {
    public let id: UUID
    public let binding: GiftBinding
    public init(id: UUID, binding: GiftBinding) {self.id=id;self.binding=binding}
}

public enum GiftAuthorizationDenial: String, Codable {
    case invalidRequest,namespaceUnavailable,notEligible,alreadyGranted,globalCooldown
    case clockRollback,storageUnavailable,unsupportedVersion,invalidLedger,ledgerFull,busy,timedOut
}

/// External input: the simulation never asks the wall clock or reads a ledger.
public struct GiftAuthorizationResult: Codable, Equatable {
    public let binding: GiftBinding
    public let token: GiftAuthorizationToken?
    public let denial: GiftAuthorizationDenial?
    public init(granted token: GiftAuthorizationToken) {binding=token.binding;self.token=token;denial=nil}
    public init(denied binding: GiftBinding, reason: GiftAuthorizationDenial) {self.binding=binding;token=nil;denial=reason}
    public var isValid: Bool {
        binding.isValid && ((token != nil) != (denial != nil)) && (token.map{$0.binding==binding} ?? true)
    }
    private enum CodingKeys: String, CodingKey {case binding,token,denial}
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        binding=try c.decode(GiftBinding.self,forKey:.binding)
        token=try c.decodeIfPresent(GiftAuthorizationToken.self,forKey:.token)
        denial=try c.decodeIfPresent(GiftAuthorizationDenial.self,forKey:.denial)
        guard isValid else {throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Gift result requires exactly one matching token or denial"))}
    }
}
