import Foundation
import CoreGraphics

/// A visual exchange using each species' existing idle artwork, without audio.
struct SocialGreetingPlan {
    static let requiredFrames=BehaviorDefinitions.definition(for:.socialGreeting).requiredFrames
    let initiator:BirdID
    let responder:BirdID

    init(initiator:BirdID,responder:BirdID) {
        self.initiator=initiator;self.responder=responder
    }

    /// Geometry only: selection, capabilities and resource ownership belong to
    /// the engine. Neither checking eligibility nor turning changes a foot anchor.
    static func eligiblePair(_ a:Bird,_ b:Bird,in engine:BehaviorEngine,hopA:CGFloat?=nil,hopB:CGFloat?=nil) -> Bool {
        guard a !== b,engine.world.scale.isFinite,engine.world.scale>0,
              let aHost=engine.world.surfaces.first(where:{$0.id==a.hostID}),
              let bHost=engine.world.surfaces.first(where:{$0.id==b.hostID}),
              aHost.id==bHost.id,aHost.pid==bHost.pid,
              a.edge == .top,b.edge == .top,
              (aHost.isGround || abs(a.position.y-b.position.y)<0.000001),
              abs(a.position.y-Geometry.foot(on:aHost,fraction:a.fraction,edge:.top,scale:engine.spriteScale(for:a)).y)<0.000001,
              abs(b.position.y-Geometry.foot(on:bHost,fraction:b.fraction,edge:.top,scale:engine.spriteScale(for:b)).y)<0.000001,
              engine.hasUsablePerch(a),engine.hasUsablePerch(b),
              Geometry.distance(a.position,b.position)<=420*engine.world.scale else {return false}
        let left=a.position.x<b.position.x ? a:b
        let right=a.position.x<b.position.x ? b:a
        let leftRect=spriteRect(left,facingRight:true,hop:0,in:engine)
        let rightRect=spriteRect(right,facingRight:false,hop:0,in:engine)
        // The 12-point clearance is between the full, turned 48-pixel sprites.
        guard rightRect.minX-leftRect.maxX>=12 else {return false}
        let leftHop=left === a ? (hopA ?? a.hopOffset):(hopB ?? b.hopOffset)
        let rightHop=right === b ? (hopB ?? b.hopOffset):(hopA ?? a.hopOffset)
        let leftArea=leftRect.union(spriteRect(left,facingRight:true,hop:leftHop,in:engine))
        let rightArea=rightRect.union(spriteRect(right,facingRight:false,hop:rightHop,in:engine))
        // Ground tails may extend below the work area, but never past a display.
        guard engine.world.displays.contains(where:{$0.contains(leftArea) && $0.contains(rightArea)}) else {return false}
        return !Geometry.blockers(on:aHost,surfaces:engine.world.surfaces).contains { blocker in
            [leftArea,rightArea].contains { area in
                let cut=area.intersection(blocker.rect)
                return !cut.isNull && !cut.isEmpty
            }
        }
    }

    private static func spriteRect(_ bird:Bird,facingRight:Bool,hop:CGFloat,in engine:BehaviorEngine) -> CGRect {
        let scale=engine.spriteScale(for:bird)
        return CGRect(x:bird.position.x-(facingRight ? 29:19)*scale,
            y:bird.position.y+(hop-39)*scale,width:48*scale,height:48*scale)
    }
}

final class SocialGreetingExecution:BehaviorExecution {
    let plan:SocialGreetingPlan
    let kind:BehaviorKind = .socialGreeting
    private let duration=4.6
    var timeout:Double {duration+1}
    var participants:[BirdID] {[plan.initiator,plan.responder]}
    private var age=0.0
    private struct Actor {
        let revision:UInt64
        let hostID:UInt32
        let hostPID:Int32
        let initialHop:CGFloat
        let facingRight:Bool
    }
    private var actors:[BirdID:Actor]=[:]

    init(plan:SocialGreetingPlan) {self.plan=plan}

    func start(in engine:BehaviorEngine) {
        guard let initiator=engine.bird(plan.initiator),let responder=engine.bird(plan.responder) else {return}
        for (id,bird,other) in [(plan.initiator,initiator,responder),(plan.responder,responder,initiator)] {
            guard let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}) else {continue}
            actors[id]=Actor(revision:bird.motionRevision,hostID:host.id,hostPID:host.pid,
                initialHop:engine.baseHop(for:id,bird:bird),facingRight:bird.position.x<other.position.x)
        }
    }

    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        for id in participants {
            guard let bird=engine.bird(id) else {return .failed(.missingBird)}
            guard let actor=actors[id],bird.state == .perched,!bird.isDeparting,!bird.needsDestination,
                  bird.motionRevision==actor.revision,bird.hostID==actor.hostID,
                  engine.world.surfaces.contains(where:{$0.id==actor.hostID && $0.pid==actor.hostPID}),
                  engine.hasUsablePerch(bird) else {return .failed(.targetInvalid)}
            guard SocialGreetingPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {
                return .failed(.missingFrames)
            }
        }
        guard let a=engine.bird(plan.initiator),let b=engine.bird(plan.responder),
              let poseA=presentation(for:plan.initiator,in:engine),let poseB=presentation(for:plan.responder,in:engine),
              SocialGreetingPlan.eligiblePair(a,b,in:engine,hopA:poseA.hopOffset,hopB:poseB.hopOffset),
              actors[plan.initiator]?.facingRight == (a.position.x<b.position.x) else {return .failed(.targetInvalid)}
        return nil
    }

    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        if engine.world.interruptingButtonsDown {return .cancelled(.userInput)}
        for id in participants {
            guard let bird=engine.bird(id) else {return .failed(.missingBird)}
            if engine.pointerNear(bird) {return .cancelled(.pointerNearby)}
        }
        age+=dt
        return age+1e-9>=duration ? .completed:nil
    }

    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        // The runtime releases both poses and leases. Never restore old motion
        // over a relocation, host-driven flight, or removal.
    }

    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard let actor=actors[id],let bird=engine.bird(id),bird.motionRevision==actor.revision,
              bird.state == .perched,!bird.isDeparting else {return nil}
        func ease(_ value:Double) -> CGFloat {
            let t=min(1,max(0,value));return CGFloat(t*t*(3-2*t))
        }
        let hop=age<0.35 ? actor.initialHop*(1-ease(age/0.35)) : bird.hopOffset*ease((age-(duration-0.35))/0.35)
        let start=id==plan.initiator ? 0.4:1.9
        let end=id==plan.initiator ? 1.5:3.0
        let blinkStart=id==plan.initiator ? 3.3:3.7
        let frame:String
        if age>=start && age<end {
            frame="idle\([0,1,2,1][Int((age-start)*4)%4])"
        } else if age>=blinkStart && age<blinkStart+0.2 {frame="blink"}
        else {frame="stand"}
        return BirdPose(frameName:frame,hopOffset:hop,facingRight:actor.facingRight)
    }
}
