import Foundation
import CoreGraphics

/// Runtime identities are never reused. A prop belongs to exactly one behavior
/// run, so clearing or ending that run also removes its presentation.
public struct ScenePropID:Hashable,Comparable {
    public let rawValue:UInt64
    public init(_ value:UInt64) {rawValue=value}
    public static func < (lhs:Self,rhs:Self) -> Bool {lhs.rawValue<rhs.rawValue}
}
public enum ScenePropKind:String {case leaf}

/// Quartz coordinates, like BirdRenderState. Props do not participate in mouse
/// hit testing; explicit commands control their lifetime.
public struct ScenePropRenderState {
    public let id:ScenePropID
    public let kind:ScenePropKind
    public let position:CGPoint
    public let size:CGFloat
    public let rotation:CGFloat
    public let opacity:Double
    public let blockers:[CGRect]
    public var rect:CGRect {CGRect(x:position.x-size/2,y:position.y-size/2,width:size,height:size)}
}

public enum ScenePropAssets {
    public static var fixedPerchURL:URL? {Bundle.module.url(forResource:"fixed-perch",withExtension:"png")}
    public static var leafURL:URL? {Bundle.module.url(forResource:"leaf",withExtension:"png")}
}
