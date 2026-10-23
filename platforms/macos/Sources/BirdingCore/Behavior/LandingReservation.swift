import Foundation
import CoreGraphics

/// A future foot anchor owned by a behavior run. Host identity and relative
/// placement survive gentle window movement; removing the run releases the slot.
struct LandingReservation {
    let bird:BirdID
    let hostID:UInt32
    let hostPID:Int32
    let fraction:CGFloat

    init(bird:BirdID,host:Surface,fraction:CGFloat) {
        self.bird=bird;hostID=host.id;hostPID=host.pid;self.fraction=fraction
    }
    func host(in engine:BehaviorEngine) -> Surface? {
        engine.world.surfaces.first{$0.id==hostID && $0.pid==hostPID}
    }
    func point(in engine:BehaviorEngine) -> CGPoint? {
        guard let host=host(in:engine),let model=engine.bird(bird) else {return nil}
        return Geometry.foot(on:host,fraction:fraction,edge:.top,scale:engine.spriteScale(for:model))
    }
    func footprint(in engine:BehaviorEngine) -> CGRect? {
        guard let point=point(in:engine),let model=engine.bird(bird) else {return nil}
        return Geometry.landingFootprint(at:point,scale:engine.spriteScale(for:model)).insetBy(dx:-8,dy:-8)
    }
    func isValid(in engine:BehaviorEngine) -> Bool {
        guard fraction.isFinite,(0...1).contains(fraction),let host=host(in:engine),
              let point=point(in:engine),let model=engine.bird(bird) else {return false}
        let scale=engine.spriteScale(for:model)
        guard scale.isFinite,scale>0 else {return false}
        let area=Geometry.landingFootprint(at:point,scale:scale)
        return engine.world.displays.contains{$0.contains(area)} &&
            Geometry.isLandingVisible(on:host.id,at:point,surfaces:engine.world.surfaces,scale:scale)
    }
    func conflicts(with other:LandingReservation,in engine:BehaviorEngine) -> Bool {
        guard let a=footprint(in:engine),let b=other.footprint(in:engine) else {return true}
        let cut=a.intersection(b)
        return !cut.isNull && !cut.isEmpty
    }
}
