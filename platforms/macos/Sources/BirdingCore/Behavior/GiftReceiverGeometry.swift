import Foundation
import CoreGraphics

/// The branch's alpha rail and its ordinary visitor foot share this anchor.
/// Gifts reserve an object receiver, never a landing slot for the carrier.
public enum GiftReceiverGeometry {
    public static let releaseDuration=0.3
    public static let fallDuration=0.6
    public static let maximumFallDuration=0.8
    public static let displayLifetime=120.0
    public static let timeout=35.0

    public static func anchor(on perch:ResolvedFixedPerch) -> CGPoint {perch.foot}
    static func finalGrip(on perch:ResolvedFixedPerch,worldScale:CGFloat,facingRight:Bool) -> CGPoint {
        CGPoint(x:perch.foot.x+(facingRight ? -7:7)*worldScale,y:perch.foot.y)
    }
    static func leafRect(on perch:ResolvedFixedPerch,worldScale:CGFloat,facingRight:Bool) -> CGRect {
        CarriedObjectGeometry.bounds(position:anchor(on:perch),anchor:CarriedObjectGeometry.surface,
            worldScale:worldScale,facingRight:facingRight)
    }
    /// A monotone, controlled descent keeps rotation fixed. The endpoint hull
    /// exactly encloses every four-corner leaf rectangle between these pivots.
    static func descentRect(from grip:CGPoint,on perch:ResolvedFixedPerch,worldScale:CGFloat,facingRight:Bool) -> CGRect {
        CarriedObjectGeometry.bounds(position:grip,anchor:CarriedObjectGeometry.grip,
            worldScale:worldScale,facingRight:facingRight)
            .union(leafRect(on:perch,worldScale:worldScale,facingRight:facingRight))
    }
}

struct GiftReceiverReservation {
    let bird:BirdID
    let slot:Int
    let revision:UInt64
    let rect:CGRect
    let perch:ResolvedFixedPerch
    let worldScale:CGFloat

    init(bird:BirdID,perch:ResolvedFixedPerch,revision:UInt64,rect:CGRect,worldScale:CGFloat) {
        self.bird=bird;slot=perch.slot;self.revision=revision;self.rect=rect
        self.perch=perch;self.worldScale=worldScale
    }
    func isValid(in engine:BehaviorEngine,excluding:[BirdID]=[]) -> Bool {
        guard revision>0,worldScale==engine.world.scale,SurfaceAnchor.finite(rect),!rect.isEmpty,
              engine.giftReceiverRevision(slot:slot)==revision,
              let current=engine.fixedPerchSnapshot().first(where:{$0.slot==slot}),
              current.surface==perch.surface,current.foot==perch.foot,current.rect==perch.rect,
              engine.world.displays.contains(where:{$0.contains(rect)}),
              engine.world.screens.isEmpty || engine.world.screens.contains(where:{$0.contains(rect)}),
              !Geometry.blockers(on:current.surface,surfaces:engine.world.surfaces).contains(where:{$0.rect.intersects(rect)}) else {return false}
        let ignored=Set(excluding)
        for other in engine.birds where engine.id(of:other).map({!ignored.contains($0)}) ?? true {
            if engine.bounds(of:other).intersects(rect) {return false}
            if other.state == .flying {
                guard let path=other.plannedFlightFootprint(scale:engine.spriteScale(for:other)),!path.intersects(rect) else {return false}
            }
        }
        for other in engine.runtime.landingReservations where !ignored.contains(other.bird) {
            guard let area=other.footprint(in:engine),!area.intersects(rect) else {return false}
        }
        return true
    }
    func conflicts(with other:GiftReceiverReservation,in engine:BehaviorEngine) -> Bool {
        slot==other.slot || rect.intersects(other.rect)
    }
    func conflicts(with other:LandingReservation,in engine:BehaviorEngine) -> Bool {
        return other.footprint(in:engine).map{rect.intersects($0)} ?? true
    }
}
