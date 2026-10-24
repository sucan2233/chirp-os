import Foundation

/// A focus names an existing object; it never owns another opportunity clock.
/// Add later scene kinds only when their individual implementation starts.
public struct SceneFocus:Equatable {
    public let objectID:HabitatObjectID
    public init(objectID:HabitatObjectID) {self.objectID=objectID}
}

public enum AmbientSuppressionReason {case interaction,userInput}

public enum SceneRandomSalt {
    public static let scheduler:UInt64=0x5343454E45464F43
    public static let bath:UInt64=0x4241544856495349
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
