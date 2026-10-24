import Foundation
import CoreGraphics

/// Runtime identities are never reused. Ephemeral props belong to a run;
/// persistent carried objects retain this identity across reservation, attachment
/// and placement, with at most one run holding their lease at a time.
public struct ScenePropID:Hashable,Comparable {
    public let rawValue:UInt64
    public init(_ value:UInt64) {rawValue=value}
    public static func < (lhs:Self,rhs:Self) -> Bool {lhs.rawValue<rhs.rawValue}
}
public enum ScenePropKind:String {case leaf,waterSplash,leafToken,insect}

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
    public var frameName:String = "leaf"
    public var anchor:CGPoint = CGPoint(x:0.5,y:0.5)
    public var mirrored:Bool = false
    public var rect:CGRect {
        guard kind == .leafToken else {return CGRect(x:position.x-size*anchor.x,y:position.y-size*anchor.y,width:size,height:size)}
        let points=[CGPoint.zero,CGPoint(x:size,y:0),CGPoint(x:size,y:size),CGPoint(x:0,y:size)].map {point -> CGPoint in
            let x=(point.x-size*anchor.x)*(mirrored ? -1:1),y=point.y-size*anchor.y
            return CGPoint(x:position.x+x*cos(rotation)-y*sin(rotation),y:position.y+x*sin(rotation)+y*cos(rotation))
        }
        let xs=points.map(\.x),ys=points.map(\.y)
        return CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
    }
}

public enum ScenePropAssets {
    public static var foodTrayURL:URL? {Bundle.module.url(forResource:"food-tray",withExtension:"png")}
    public static var fixedPerchURL:URL? {Bundle.module.url(forResource:"fixed-perch",withExtension:"png")}
    public static var leafURL:URL? {Bundle.module.url(forResource:"leaf",withExtension:"png")}
}
