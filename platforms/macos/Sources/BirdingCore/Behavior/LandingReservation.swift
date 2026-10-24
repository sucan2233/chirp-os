import Foundation
import CoreGraphics

/// A future foot anchor owned by a behavior run. Host identity and relative
/// placement survive gentle window movement; removing the run releases the slot.
struct LandingReservation {
    let bird:BirdID
    let hostID:UInt32
    let hostPID:Int32
    let fraction:CGFloat
    /// A shared ledge scene may reserve one continuous span for its leased
    /// participants. Internal contact does not relax conflicts with other runs.
    let span:ClosedRange<CGFloat>?
    let headroom:CGFloat
    /// Optional carrier/object union relative to the live foot, in world units.
    /// Defaults preserve all existing reservations and their conflict geometry.
    let localFootprint:CGRect?

    init(bird:BirdID,host:Surface,fraction:CGFloat,span:ClosedRange<CGFloat>?=nil,headroom:CGFloat=0,localFootprint:CGRect?=nil) {
        self.bird=bird;hostID=host.id;hostPID=host.pid;self.fraction=fraction
        self.span=span;self.headroom=headroom;self.localFootprint=localFootprint
    }
    func host(in engine:BehaviorEngine) -> Surface? {
        engine.world.surfaces.first{$0.id==hostID && $0.pid==hostPID}
    }
    func point(in engine:BehaviorEngine) -> CGPoint? {
        guard let host=host(in:engine),let model=engine.bird(bird) else {return nil}
        return Geometry.foot(on:host,fraction:fraction,edge:.top,scale:engine.spriteScale(for:model))
    }
    private func bodyFootprint(in engine:BehaviorEngine) -> CGRect? {
        guard let point=point(in:engine),let model=engine.bird(bird) else {return nil}
        guard headroom.isFinite,headroom>=0 else {return nil}
        let scale=engine.spriteScale(for:model)
        var area=Geometry.landingFootprint(at:point,scale:scale)
        if let localFootprint {
            guard SurfaceAnchor.finite(localFootprint),localFootprint.width>0,localFootprint.height>0 else {return nil}
            area=area.union(localFootprint.offsetBy(dx:point.x,dy:point.y))
        }
        if let span {
            guard span.lowerBound.isFinite,span.upperBound.isFinite,
                  span.lowerBound>=0,span.upperBound<=1,span.contains(fraction),let host=host(in:engine) else {return nil}
            for end in [span.lowerBound,span.upperBound] {
                let foot=Geometry.foot(on:host,fraction:end,edge:.top,scale:scale)
                area=area.union(Geometry.landingFootprint(at:foot,scale:scale))
                if let localFootprint {area=area.union(localFootprint.offsetBy(dx:foot.x,dy:foot.y))}
            }
        }
        return area.union(area.offsetBy(dx:0,dy:-headroom))
    }
    func footprint(in engine:BehaviorEngine) -> CGRect? {
        bodyFootprint(in:engine)?.insetBy(dx:-8,dy:-8)
    }
    func isValid(in engine:BehaviorEngine) -> Bool {
        guard fraction.isFinite,(0...1).contains(fraction),let host=host(in:engine),
              let model=engine.bird(bird),let area=bodyFootprint(in:engine) else {return false}
        let scale=engine.spriteScale(for:model)
        guard scale.isFinite,scale>0 else {return false}
        return engine.world.displays.contains{$0.contains(area)} &&
            !Geometry.blockers(on:host,surfaces:engine.world.surfaces).contains {
                let overlap=area.intersection($0.rect)
                return !overlap.isNull && !overlap.isEmpty
            }
    }
    func conflicts(with other:LandingReservation,in engine:BehaviorEngine) -> Bool {
        guard let a=footprint(in:engine),let b=other.footprint(in:engine) else {return true}
        let cut=a.intersection(b)
        return !cut.isNull && !cut.isEmpty
    }
}
