import Foundation
import CoreGraphics

public enum AttentionKind:String,CaseIterable {
    case watch, alert
    public var behavior:BehaviorKind {self == .watch ? .watch:.alert}
    public var requiredFrames:Set<String> {self == .watch ? ["stand","blink"]:["stand"]}
}

struct AttentionPlan {
    let kind:AttentionKind
    let duration:Double

    func frame(at age:Double,hasBlink:Bool) -> String {
        guard hasBlink else {return "stand"}
        let blinkStart=duration*(kind == .watch ? 0.45:0.78)
        let blinkDuration=min(0.16,duration*0.12)
        return age>=blinkStart && age<blinkStart+blinkDuration ? "blink":"stand"
    }
}

/// A short full-body reaction using real stand/blink frames. Turning is a pose
/// override, not head-turn artwork or a mutation of the bird's motion direction.
public final class AttentionExecution:BehaviorExecution {
    let id:BirdID,plan:AttentionPlan
    let requiresNearbyPointer:Bool
    let occupiesEncounter=false,runsWhilePaused=false
    var kind:BehaviorKind {plan.kind.behavior}
    var participants:[BirdID] {[id]}
    var timeout:Double {plan.duration+0.5}

    private struct Anchor {
        let revision:UInt64
        let hostID:UInt32
        let hostPID:Int32
        let scale:CGFloat
        let screen:CGRect
        let initialHop:CGFloat
    }
    private var anchor:Anchor?
    private var age=0.0
    private var facingRight=true

    public init(id:BirdID,kind:AttentionKind,duration:Double,requiresNearbyPointer:Bool=true) {
        self.id=id;self.plan=AttentionPlan(kind:kind,duration:duration)
        self.requiresNearbyPointer=requiresNearbyPointer
    }

    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(id),let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}) else {return}
        let scale=engine.spriteScale(for:bird),hop=engine.baseHop(for:id,bird:bird)
        let footprint=Self.footprint(bird,scale:scale,hop:hop)
        guard let screen=engine.world.displays.first(where:{$0.contains(footprint)}) else {return}
        anchor=Anchor(revision:bird.motionRevision,hostID:host.id,hostPID:host.pid,
            scale:scale,screen:screen,initialHop:hop)
        facingRight=bird.facingRight
    }

    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(id) else {return .failed(.missingBird)}
        guard engine.settings.perchActions,engine.settings.passiveAttentionEnabled else {
            return .cancelled(.settingsChanged)
        }
        guard plan.duration.isFinite,plan.duration>0,let anchor,
              bird.motionRevision==anchor.revision,bird.state == .perched,
              !bird.isDeparting,!bird.needsDestination,bird.edge == .top,
              bird.hostID==anchor.hostID,
              let host=engine.world.surfaces.first(where:{$0.id==anchor.hostID && $0.pid==anchor.hostPID}),
              anchor.scale.isFinite,anchor.scale>0,engine.spriteScale(for:bird)==anchor.scale,
              engine.world.displays.contains(anchor.screen),engine.hasUsablePerch(bird) else {
            return .failed(.targetInvalid)
        }
        let expected=Geometry.foot(on:host,fraction:bird.fraction,edge:.top,scale:anchor.scale)
        let area=Self.footprint(bird,scale:anchor.scale,hop:hopOffset)
        guard Geometry.distance(expected,bird.position)<0.000001,anchor.screen.contains(area),
              !Geometry.blockers(on:host,surfaces:engine.world.surfaces).contains(where:{
                  let cut=$0.rect.intersection(area)
                  return !cut.isNull && !cut.isEmpty
              }) else {return .failed(.targetInvalid)}
        guard plan.kind.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {
            return .failed(.missingFrames)
        }
        // Input remains actionable while animation is paused, just like invalid
        // hosts and frame manifests. Validation never advances age or facing.
        if engine.world.buttonsDown {return .cancelled(.userInput)}
        return nil
    }

    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        if let result=validate(in:engine) {return result}
        guard let bird=engine.bird(id),let anchor else {return .failed(.targetInvalid)}
        let pointer=engine.world.pointer
        if plan.kind == .watch && requiresNearbyPointer {
            let exitRadius=max(200,144*anchor.scale)*1.2
            guard anchor.screen.contains(pointer),Geometry.distance(pointer,bird.position)<=exitRadius else {
                return .cancelled(.pointerMoved)
            }
        }
        // A dead band around the feet prevents tiny pointer crossings from
        // flipping the sprite. Only simulation steps may update this state.
        if anchor.screen.contains(pointer) {
            let dx=pointer.x-bird.position.x,threshold=24*anchor.scale
            if dx>threshold {facingRight=true}
            else if dx < -threshold {facingRight=false}
        }
        age+=dt
        return age+1e-9>=plan.duration ? .completed:nil
    }

    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        // Runtime detach hands the last hop to PoseMixer. Never restore stale
        // orientation, position or frames over a newer route.
    }

    func presentation(for birdID:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard birdID==id,let bird=engine.bird(id),let anchor,
              bird.motionRevision==anchor.revision,bird.state == .perched,!bird.isDeparting else {return nil}
        let hasBlink=engine.world.availableFrames[bird.profile.id]?.contains("blink") == true
        return BirdPose(frameName:plan.frame(at:age,hasBlink:hasBlink),hopOffset:hopOffset,facingRight:facingRight)
    }

    private var hopOffset:CGFloat {
        guard let anchor else {return 0}
        let t=min(1,max(0,age/0.35)),blend=t*t*(3-2*t)
        return anchor.initialHop*CGFloat(1-blend)
    }

    private static func footprint(_ bird:Bird,scale:CGFloat,hop:CGFloat) -> CGRect {
        let planted=Geometry.landingFootprint(at:bird.position,scale:scale)
        return planted.union(planted.offsetBy(dx:0,dy:hop*scale))
    }
}
