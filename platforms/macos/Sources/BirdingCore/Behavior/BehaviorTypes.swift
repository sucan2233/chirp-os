import Foundation
import CoreGraphics

public struct BirdID: Hashable, Codable, Comparable {
    public let rawValue: UInt64
    public init(_ value: UInt64) {rawValue=value}
    public static func < (lhs:Self,rhs:Self) -> Bool {lhs.rawValue<rhs.rawValue}
}
public struct BehaviorRunID: Hashable, Codable, Comparable {
    public let rawValue: UInt64
    public static func < (lhs:Self,rhs:Self) -> Bool {lhs.rawValue<rhs.rawValue}
}
public enum BirdRole: String {case resident, transient}
/// Animation roles only; these do not encode sex or a persistent pair.
public enum CourtshipRole:String,CaseIterable {case initiator,observer}
public enum BehaviorKind: String, Codable {
    case relocate, pointerVisit, flockPass, rest, preen, socialGreeting, sideBySide, giveWay, pairedTakeoff, leafPlay, watch, alert, sideHop, takeoffPreparation, edgePeek, chase, travelTogether, allopreening, fixedPerchVisit, foodTrayVisit, bathVisit, leafCarry, insectCatch, visitorGift, courtshipDisplay, nestMaterialCarry, nestBuild
    var isNestActivity:Bool {self == .nestMaterialCarry || self == .nestBuild}
    var isPerchActivity:Bool {[Self.rest,.preen,.watch,.alert,.sideHop,.takeoffPreparation,.edgePeek].contains(self)}
    var isSocial:Bool {[Self.socialGreeting,.sideBySide,.giveWay,.pairedTakeoff,.chase,.travelTogether,.allopreening,.courtshipDisplay].contains(self)}
}
public enum BehaviorSource: String, Codable {case user, preview, automatic}
public enum BehaviorReason: String {
    case notFamiliar, authorizationDenied
    case paused, disabled, busy, missingBird, unavailableBird, noSpace, noSpecies, missingFrames, pointerNearby, noCompanion
    case userInput, pointerMoved, targetInvalid, replaced, timedOut, removed, missedTarget
    case sleep, screensChanged, spaceChanged, shutdown, settingsChanged
}
public enum BehaviorEventType: String {case started, completed, cancelled, failed, rejected, birdRemoved, previewResult}
public struct BehaviorEvent {
    public let sequence: UInt64
    public let time: Double
    public let runID: BehaviorRunID?
    public let kind: BehaviorKind?
    public let source: BehaviorSource
    public let type: BehaviorEventType
    public let participants: [BirdID]
    public let reason: BehaviorReason?
}
public enum BehaviorResult: Equatable {
    case started(BehaviorRunID), scheduled, accepted, rejected(BehaviorReason)
    public var accepted: Bool {if case .rejected = self {return false};return true}
}
public enum EngineCommand {
    case placeNest(at:CGPoint)
    case placeNestAfter(Double)
    case cancelNestPlacement
    case removeNest
    case nestMaterialCarry(BehaviorSource)
    case nestBuild(BehaviorSource)
    case courtshipDisplay(BehaviorSource)
    case visitorGift(BehaviorSource)
    case cancelVisitorGiftRequest
    case clearVisitorGift
    case relocate(BirdID)
    case pointerVisit(BehaviorSource)
    case flockPass(BehaviorSource)
    case socialGreeting(BehaviorSource)
    case socialMotion(SocialMotionKind,BehaviorSource)
    case perchAction(PerchActionKind,BehaviorSource)
    case attention(AttentionKind,BehaviorSource)
    case insectCatch(species:SpeciesID,source:BehaviorSource)
    case cancelInsectCatchPreview
    case clearInsect
    case placeCarryLeaf(at:CGPoint)
    case placeCarryLeafAfter(Double)
    case cancelCarryLeafPlacement
    case removeCarryLeaf
    case leafCarry(BehaviorSource)
    case placeBath(at:CGPoint)
    case placeBathAfter(Double)
    case cancelBathPlacement
    case removeBath
    case clearCurrentScene
    case bathVisit(BehaviorSource)
    case placeFoodTray(at:CGPoint)
    case placeFoodTrayAfter(Double)
    case cancelFoodTrayPlacement
    case removeFoodTray
    case foodTrayVisit(BehaviorSource)
    case fixedPerchVisit(BehaviorSource)
    case allopreening(BehaviorSource)
    case travelTogether(BehaviorSource)
    case chase(BehaviorSource)
    case edgePeek(BehaviorSource)
    case sideHop(BehaviorSource)
    case prepareTakeoff(BehaviorSource)
    case previewPointerAfter(Double)
    case leafPlay(at:CGPoint,source:BehaviorSource)
    case releaseLeafAfter(Double)
    case clearLeaf
    case clearProps
    case removeProp(ScenePropID)
    case pointerClick
    case pause(Bool)
    case cancelAmbient(BehaviorReason)
    case scatter
    case remove(BirdID)
}

/// Platform snapshots use Quartz-style desktop coordinates, including negatives.
public struct BehaviorWorld {
    public var screens: [CGRect]
    public var displays: [CGRect]
    /// Stable display identifiers, in the same order as displays; empty for legacy fixtures.
    public var displayIDs:[String]
    /// Platforms opt out when the real perch sprite cannot be loaded.
    public var fixedPerchArtAvailable:Bool
    public var nestArtAvailable:Bool
    public var insectArtAvailable:Bool
    public var leafCarryArtAvailable:Bool
    public var bathArtAvailable:Bool
    public var foodTrayArtAvailable:Bool
    public var surfaces: [Surface]
    public var scale: CGFloat
    public var pointer: CGPoint
    public var buttonsDown: Bool
    /// A classified handbook click suppresses new encounters without cancelling
    /// an encounter already in progress. Ordinary clicks keep their old contract.
    public var observationClick:Bool=false
    public var interruptingButtonsDown:Bool {buttonsDown && !observationClick}
    /// Local civil minute supplied by the platform; nil keeps clock-free simulations neutral.
    public var localMinuteOfDay: Int?
    /// Optional poses require real renderer frames; an empty manifest opts out.
    public var availableFrames: [SpeciesID:Set<String>]
    public init(screens:[CGRect]=[],displays:[CGRect]=[],surfaces:[Surface]=[],scale:CGFloat=1,
                pointer:CGPoint = .zero,buttonsDown:Bool=false,availableFrames:[SpeciesID:Set<String>]=[:],localMinuteOfDay:Int?=nil,displayIDs:[String]=[],fixedPerchArtAvailable:Bool=true,foodTrayArtAvailable:Bool=true,bathArtAvailable:Bool=true,leafCarryArtAvailable:Bool=true,insectArtAvailable:Bool=true,nestArtAvailable:Bool=true) {
        self.screens=screens;self.displays=displays;self.surfaces=surfaces;self.displayIDs=displayIDs;self.fixedPerchArtAvailable=fixedPerchArtAvailable;self.foodTrayArtAvailable=foodTrayArtAvailable;self.bathArtAvailable=bathArtAvailable;self.leafCarryArtAvailable=leafCarryArtAvailable;self.insectArtAvailable=insectArtAvailable
        self.nestArtAvailable=nestArtAvailable
        self.scale=scale;self.pointer=pointer;self.buttonsDown=buttonsDown;self.availableFrames=availableFrames
        self.localMinuteOfDay=localMinuteOfDay.flatMap{(0..<1440).contains($0) ? $0:nil}
    }
}

/// SplitMix64, version 1. Integer state and a fixed 53-bit conversion make runs
/// reproducible without relying on Swift's process-randomized hashing or RNG.
public final class EngineRandom {
    private var state: UInt64
    public init(seed:UInt64) {state=seed}
    public func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value=state
        value=(value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value=(value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9007199254740992
    }
    func value(in range:ClosedRange<Double>) -> Double {range.lowerBound+(range.upperBound-range.lowerBound)*unit()}
    func element<T>(_ values:[T]) -> T? {
        values.isEmpty ? nil:values[min(values.count-1,Int(unit()*Double(values.count)))]
    }
}

/// Value output: rendering and hit-testing cannot mutate the simulated bird.
public struct BirdRenderState {
    public let id: BirdID
    public let species: SpeciesID
    public let position: CGPoint
    public let facingRight: Bool
    public let scale: CGFloat
    public let hopOffset: CGFloat
    public let frameName: String
    public let blockers: [CGRect]
    public let hoverable: Bool
    public var rect: CGRect {
        CGRect(x:position.x-(facingRight ? 29:19)*scale,y:position.y+(hopOffset-39)*scale,width:48*scale,height:48*scale)
    }
}

/// World-space immersion geometry, emitted only while a bath visitor is settled.
public struct BathImmersionState {
    public let waterRect:CGRect
    public let waterlineY:CGFloat
    public let feetRect:CGRect
}
