import Foundation

/// A typed reference to an existing scene entity, never another clock.
public struct SceneFocus:Equatable {
    public enum Target:Equatable {case bath(HabitatObjectID),leaf(ScenePropID)}
    public let target:Target
    public init(target:Target) {self.target=target}
    public init(objectID:HabitatObjectID) {target = .bath(objectID)}
    public init(leafID:ScenePropID) {target = .leaf(leafID)}
    public var objectID:HabitatObjectID? {if case .bath(let id)=target {return id};return nil}
    public var leafID:ScenePropID? {if case .leaf(let id)=target {return id};return nil}
}

public enum AmbientSuppressionReason {case interaction,userInput}

public enum SceneRandomSalt {
    public static let scheduler:UInt64=0x5343454E45464F43
    public static let bath:UInt64=0x4241544856495349
    public static let insectCatch:UInt64=0x494E534543544354
    public static let leafCarry:UInt64=0x4C45414643415252
}

extension AmbientFrequency {
    public var sceneInterval:ClosedRange<Double> {
        switch self {
        case .low:return 30...45
        case .medium:return 20...35
        case .high:return 15...25
        }
    }
}
