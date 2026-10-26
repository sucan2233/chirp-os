import Foundation
import CoreGraphics

/// A point on an existing ordinary ledge. Identity includes PID so a reused
/// window number can never adopt an old object. No absolute airborne fallback.
public struct SurfaceAnchor:Equatable {
    public let hostID:UInt32
    public let hostPID:Int32
    public let fraction:CGFloat
    public let isGround:Bool
    /// Ground's existing tail-clearance rule is frozen when the point is made.
    public let groundScale:CGFloat
    public init(host:Surface,fraction:CGFloat,groundScale:CGFloat=1) {
        hostID=host.id;hostPID=host.pid;self.fraction=fraction
        isGround=host.isGround;self.groundScale=groundScale
    }
    public func host(in world:BehaviorWorld) -> Surface? {
        guard fraction.isFinite,(0...1).contains(fraction),groundScale.isFinite,groundScale>0 else {return nil}
        return world.surfaces.first {
            $0.canHostBirds && $0.id==hostID && $0.pid==hostPID && $0.isGround==isGround && !$0.isHabitat &&
            ($0.isGround || $0.layer==0) && Self.finite($0.rect) && $0.rect.width>0
        }
    }
    public func point(in world:BehaviorWorld) -> CGPoint? {
        host(in:world).map{Geometry.foot(on:$0,fraction:fraction,edge:.top,scale:groundScale)}
    }
    static func at(_ point:CGPoint,on host:Surface,scale:CGFloat) -> Self? {
        guard point.x.isFinite,point.y.isFinite,scale.isFinite,scale>0,
              host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0,finite(host.rect) else {return nil}
        let low=Geometry.perchX(0,rect:host.rect),high=Geometry.perchX(1,rect:host.rect)
        guard high>low,point.x>=low-0.000001,point.x<=high+0.000001 else {return nil}
        let fraction=min(1,max(0,(point.x-low)/(high-low)))
        let foot=Geometry.foot(on:host,fraction:fraction,edge:.top,scale:scale)
        guard abs(foot.y-point.y)<0.001 else {return nil}
        return Self(host:host,fraction:fraction,groundScale:scale)
    }
    /// Resolve a click near a real top edge; never clamp an arbitrary air point
    /// onto a surface. Occlusion and complete object bounds are checked by store.
    static func placement(at point:CGPoint,in world:BehaviorWorld,groundScale:CGFloat) -> Self? {
        guard point.x.isFinite,point.y.isFinite,world.scale.isFinite,world.scale>0 else {return nil}
        let candidates=world.surfaces.enumerated().compactMap {index,host -> (Int,CGFloat,Self)? in
            guard host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0 else {return nil}
            let y=Geometry.foot(on:host,fraction:0.5,edge:.top,scale:groundScale).y
            guard abs(point.y-y)<=16*world.scale,
                  let anchor=at(CGPoint(x:point.x,y:y),on:host,scale:groundScale) else {return nil}
            return (index,abs(point.y-y),anchor)
        }.sorted {a,b in a.1==b.1 ? a.0<b.0:a.1<b.1}
        return candidates.first?.2
    }
    static func acceptsChange(from old:Surface,to new:Surface,sampleDT:Double?) -> Bool {
        guard old.id==new.id,old.pid==new.pid,old.isGround==new.isGround,
              new.canHostBirds,!new.isHabitat,new.isGround || new.layer==0,finite(new.rect) else {return false}
        let distance=Geometry.distance(old.rect.origin,new.rect.origin)
        if !new.isGround,let dt=sampleDT,dt.isFinite,dt>0,dt<0.2,distance>8,
           distance/CGFloat(max(0.016,dt))>950 {return false}
        return true
    }
    static func finite(_ rect:CGRect) -> Bool {
        !rect.isNull && [rect.minX,rect.minY,rect.width,rect.height].allSatisfy(\.isFinite) && rect.width>=0 && rect.height>=0
    }
}
