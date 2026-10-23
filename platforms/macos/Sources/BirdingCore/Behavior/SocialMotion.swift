import Foundation
import CoreGraphics

public enum SocialMotionKind:String,CaseIterable {
    case sideBySide, giveWay, pairedTakeoff
    var behavior:BehaviorKind {
        switch self {
        case .sideBySide:return .sideBySide
        case .giveWay:return .giveWay
        case .pairedTakeoff:return .pairedTakeoff
        }
    }
}

struct SocialMotionPlan {
    static let requiredFrames=BehaviorDefinitions.definition(for:.sideBySide).requiredFrames
    let action:SocialMotionKind
    /// Host/leader first; visitor/follower second. Selection is deterministic.
    let participants:[BirdID]
    let destinations:[LandingReservation]
    let display:CGRect
}

/// Finite, geometry-only plans. Both future slots are checked before either bird
/// moves. The runtime owns the resulting reservations, including delayed starts.
enum SocialMotionPlanner {
    private final class Budget {var remaining=12}
    static func candidates(_ action:SocialMotionKind,ids:[BirdID],in engine:BehaviorEngine) -> [SocialMotionPlan] {
        var result:[SocialMotionPlan]=[]
        let budget=Budget()
        for first in ids {
            for second in ids where first != second {
                guard budget.remaining>0,result.count<8 else {return result}
                if let plan=make(action,first:first,second:second,budget:budget,in:engine) {result.append(plan)}
            }
        }
        return result
    }
    static func occupied(excluding ids:Set<BirdID>,in engine:BehaviorEngine) -> [CGRect] {
        let birds=engine.birds.compactMap {bird -> CGRect? in
            guard !bird.isDeparting,let id=engine.id(of:bird),!ids.contains(id),
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}) else {return nil}
            let scale=engine.spriteScale(for:bird)
            return Geometry.landingFootprint(at:Geometry.foot(on:host,fraction:bird.fraction,edge:bird.edge,scale:scale),scale:scale).insetBy(dx:-8,dy:-8)
        }
        return birds+engine.runtime.landingReservations.filter{!ids.contains($0.bird)}.compactMap{$0.footprint(in:engine)}
    }
    static func clear(_ slots:[LandingReservation],participants:[BirdID],display:CGRect,in engine:BehaviorEngine) -> Bool {
        let blocked=occupied(excluding:Set(participants),in:engine)
        for (index,slot) in slots.enumerated() {
            guard slot.isValid(in:engine),let point=slot.point(in:engine),let host=slot.host(in:engine),
                  let bird=engine.bird(slot.bird),let area=slot.footprint(in:engine),
                  display.contains(Geometry.landingFootprint(at:point,scale:engine.spriteScale(for:bird))),
                  !blocked.contains(where:{intersects(area,$0)}),
                  !slots.dropFirst(index+1).contains(where:{slot.conflicts(with:$0,in:engine)}),
                  Geometry.landingRanges(on:host,surfaces:engine.world.surfaces,screen:display,
                      scale:engine.spriteScale(for:bird),occupied:blocked).contains(where:{$0.contains(point.x)}) else {return false}
        }
        return true
    }
    static func intersects(_ a:CGRect,_ b:CGRect) -> Bool {
        let cut=a.intersection(b);return !cut.isNull && !cut.isEmpty
    }
    static func hopCorridorClear(origin:LandingReservation,destination:LandingReservation,participants:[BirdID],display:CGRect,in engine:BehaviorEngine) -> Bool {
        guard let a=origin.point(in:engine),let b=destination.point(in:engine),
              let host=origin.host(in:engine),let bird=engine.bird(origin.bird) else {return false}
        let scale=engine.spriteScale(for:bird)
        let swept=Geometry.landingFootprint(at:a,scale:scale).union(Geometry.landingFootprint(at:b,scale:scale))
        let corridor=CGRect(x:swept.minX,y:swept.minY-24*scale,width:swept.width,height:swept.height+24*scale)
        let blocked=occupied(excluding:Set(participants),in:engine)+Geometry.blockers(on:host,surfaces:engine.world.surfaces).map(\.rect)
        return display.contains(corridor) && !blocked.contains{intersects(corridor,$0)}
    }
    /// Use the same motion integrator on isolated models before acquiring a run.
    /// This is a bounded path check, not a second live animation loop. Inflated
    /// envelopes retain clearance between samples; incompatible pairs are skipped.
    static func flightIsClear(_ plan:SocialMotionPlan,in engine:BehaviorEngine) -> Bool {
        let models=plan.participants.compactMap {id -> Bird? in
            guard let bird=engine.bird(id),let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}) else {return nil}
            let copy=Bird(position:bird.position,fraction:bird.fraction,profile:bird.profile,random:{0.5})
            copy.perch(on:host,spriteScale:engine.spriteScale(for:bird));copy.perchDuration=600
            return copy
        }
        guard models.count==2 else {return false}
        var launched=[false,false]
        let movers=plan.action == .sideBySide ? [1]:[0,1]
        var age=0.0
        for _ in 0..<1800 {
            age+=BehaviorEngine.step
            for index in movers where !launched[index] {
                let ready:Bool
                if plan.action == .giveWay && index==1 {ready=launched[0] && models[0].state == .perched}
                else {ready=age+1e-9 >= (plan.action == .pairedTakeoff && index==1 ? 1.10:0.45)}
                if ready {
                    guard SocialMotionFlight.launch(models[index],index:index,plan:plan,in:engine,random:{0.5}) else {return false}
                    launched[index]=true
                }
            }
            for model in models {model.tick(BehaviorEngine.step)}
            let areas=models.map{Geometry.landingFootprint(at:$0.position,scale:engine.spriteScale(for:$0))}
            guard areas.allSatisfy({plan.display.contains($0)}),
                  !intersects(areas[0].insetBy(dx:-4,dy:-4),areas[1].insetBy(dx:-4,dy:-4)) else {return false}
            if movers.allSatisfy({launched[$0] && models[$0].state == .perched}) {return true}
        }
        return false
    }
    private static func make(_ action:SocialMotionKind,first:BirdID,second:BirdID,budget:Budget,in engine:BehaviorEngine) -> SocialMotionPlan? {
        guard let a=engine.bird(first),let b=engine.bird(second),
              let host=engine.world.surfaces.first(where:{$0.id==a.hostID}),
              !host.isFixedPerch,host.isGround || host.layer==0 else {return nil}
        let sa=engine.spriteScale(for:a),sb=engine.spriteScale(for:b)
        guard let display=engine.world.displays.first(where:{
            $0.contains(Geometry.landingFootprint(at:a.position,scale:sa)) &&
            $0.contains(Geometry.landingFootprint(at:b.position,scale:sb))
        }) else {return nil}
        let ids=[first,second],gap=29*(sa+sb)+24
        func slot(_ id:BirdID,_ host:Surface,_ x:CGFloat) -> LandingReservation? {
            let lo=Geometry.perchX(0,rect:host.rect),hi=Geometry.perchX(1,rect:host.rect)
            guard hi>lo,x>=lo,x<=hi else {return nil}
            return LandingReservation(bird:id,host:host,fraction:(x-lo)/(hi-lo))
        }
        func result(_ slots:[LandingReservation]) -> SocialMotionPlan? {
            guard clear(slots,participants:ids,display:display,in:engine),slots.allSatisfy({s in
                guard let p=s.point(in:engine),let model=engine.bird(s.bird) else {return false}
                return Geometry.distance(p,engine.world.pointer)>=max(100,72*engine.spriteScale(for:model))
            }) else {return nil}
            guard budget.remaining>0 else {return nil}
            budget.remaining-=1
            let plan=SocialMotionPlan(action:action,participants:ids,destinations:slots,display:display)
            return flightIsClear(plan,in:engine) ? plan:nil
        }
        switch action {
        case .sideBySide,.giveWay:
            guard Geometry.distance(a.position,b.position)>gap+100,
                  Geometry.distance(a.position,b.position)<1200*engine.world.scale else {return nil}
            let nearSide:CGFloat=b.position.x<a.position.x ? -1:1
            for direction in (action == .sideBySide ? [nearSide]:[nearSide,-nearSide]) {
                let x=a.position.x+direction*gap
                if action == .sideBySide {
                    guard let guest=slot(second,host,x),let p=guest.point(in:engine),
                          Geometry.distance(p,b.position)>120*engine.world.scale else {continue}
                    if let plan=result([LandingReservation(bird:first,host:host,fraction:a.fraction),guest]) {return plan}
                } else {
                    guard let moved=slot(first,host,x),let guest=slot(second,host,a.position.x),
                          moved.point(in:engine) != nil else {continue}
                    guard hopCorridorClear(origin:LandingReservation(bird:first,host:host,fraction:a.fraction),
                        destination:moved,participants:ids,display:display,in:engine) else {continue}
                    if let plan=result([moved,guest]) {return plan}
                }
            }
        case .pairedTakeoff:
            guard a.hostID==b.hostID,Geometry.distance(a.position,b.position)<=420*engine.world.scale,
                  abs(a.position.x-b.position.x)>=gap else {return nil}
            for destination in engine.world.surfaces where destination.isGround || destination.layer==0 {
                for fraction in [CGFloat(0.25),0.5,0.75] {
                    let midpoint=Geometry.perchX(fraction,rect:destination.rect),sign:CGFloat=a.position.x<b.position.x ? -1:1
                    guard let left=slot(first,destination,midpoint+sign*gap/2),
                          let right=slot(second,destination,midpoint-sign*gap/2),
                          let pa=left.point(in:engine),let pb=right.point(in:engine),
                          Geometry.distance(a.position,pa)>180*engine.world.scale,
                          Geometry.distance(b.position,pb)>180*engine.world.scale else {continue}
                    let dx=(pa.x+pb.x-a.position.x-b.position.x)/2
                    let dy=(pa.y+pb.y-a.position.y-b.position.y)/2
                    let ahead=(a.position.x-b.position.x)*dx+(a.position.y-b.position.y)*dy
                    guard ahead>0.001 || (abs(ahead)<=0.001 && first<second) else {continue}
                    if let plan=result([left,right]) {return plan}
                }
            }
        }
        return nil
    }
}

private enum SocialMotionFlight {
    @discardableResult static func launch(_ bird:Bird,index:Int,plan:SocialMotionPlan,in engine:BehaviorEngine,random:()->Double) -> Bool {
        let slot=plan.destinations[index]
        guard let host=slot.host(in:engine),let point=slot.point(in:engine) else {return false}
        let scale=engine.spriteScale(for:bird),hop=plan.action == .giveWay && index==0
        let distance=Geometry.distance(bird.position,point)
        let area=CGRect(x:plan.display.minX+29*scale,y:plan.display.minY+39*scale,
            width:plan.display.width-58*scale,height:plan.display.height-48*scale)
        bird.fraction=slot.fraction;bird.edge = .top
        bird.fly(to:point,host:host,duration:max(0.65,Double(distance)/190)*Bird.flightSpeedMultiplier*bird.profile.speed,
            arc:hop ? 18*scale:70*scale,airspace:area,urgent:hop,allowsOrbit:false,random:random)
        return true
    }
}

final class SocialMotionExecution:BehaviorExecution {
    let plan:SocialMotionPlan
    var kind:BehaviorKind {plan.action.behavior}
    var participants:[BirdID] {plan.participants}
    var landingReservations:[LandingReservation] {plan.destinations}
    let timeout=30.0
    private struct Actor {
        var revision:UInt64
        let origin:LandingReservation
        let scale:CGFloat
        let initialHop:CGFloat
        var launched=false
    }
    private var actors:[BirdID:Actor]=[:]
    private var age=0.0,settled=0.0
    init(plan:SocialMotionPlan) {self.plan=plan}
    func start(in engine:BehaviorEngine) {
        for id in participants {
            guard let bird=engine.bird(id),let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}) else {continue}
            actors[id]=Actor(revision:bird.motionRevision,origin:LandingReservation(bird:id,host:host,fraction:bird.fraction),
                scale:engine.spriteScale(for:bird),initialHop:engine.baseHop(for:id,bird:bird))
        }
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard engine.world.displays.contains(plan.display),
              SocialMotionPlanner.clear(plan.destinations,participants:participants,display:plan.display,in:engine) else {return .failed(.targetInvalid)}
        if plan.action == .giveWay,let actor=actors[participants[0]],
           !actor.launched || engine.bird(participants[0])?.state != .perched {
            guard SocialMotionPlanner.hopCorridorClear(origin:actor.origin,destination:plan.destinations[0],
                participants:participants,display:plan.display,in:engine) else {return .failed(.targetInvalid)}
        }
        for (index,id) in participants.enumerated() {
            guard let bird=engine.bird(id),let actor=actors[id],!bird.isDeparting,
                  bird.motionRevision==actor.revision,engine.spriteScale(for:bird)==actor.scale else {return .failed(.targetInvalid)}
            guard SocialMotionPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
            let slot=actor.launched ? plan.destinations[index]:actor.origin
            guard slot.isValid(in:engine),bird.hostID==slot.hostID,
                  (actor.launched ? (bird.state != .flying || !bird.needsDestination):bird.state == .perched) else {return .failed(.targetInvalid)}
            if bird.state != .flying {
                guard let point=slot.point(in:engine),Geometry.distance(point,bird.position)<0.00001 else {return .failed(.targetInvalid)}
            }
        }
        return nil
    }
    private func launch(_ index:Int,in engine:BehaviorEngine) {
        let id=participants[index]
        guard var actor=actors[id],!actor.launched,let bird=engine.bird(id),
              SocialMotionFlight.launch(bird,index:index,plan:plan,in:engine,random:engine.random.unit) else {return}
        actor.launched=true;actor.revision=bird.motionRevision;actors[id]=actor
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        if engine.world.buttonsDown {return .cancelled(.userInput)}
        if participants.contains(where:{engine.bird($0).map{engine.pointerNear($0)} ?? false}) {return .cancelled(.pointerNearby)}
        if actors.values.allSatisfy({!$0.launched}),age+dt+1e-9>=0.45,!SocialMotionPlanner.flightIsClear(plan,in:engine) {return .failed(.targetInvalid)}
        age+=dt
        switch plan.action {
        case .sideBySide:
            if age+1e-9>=0.45 {launch(1,in:engine)}
        case .giveWay:
            if age+1e-9>=0.45 {launch(0,in:engine)}
            if actors[participants[0]]?.launched == true,engine.bird(participants[0])?.state == .perched {launch(1,in:engine)}
        case .pairedTakeoff:
            if age+1e-9>=0.45 {launch(0,in:engine)}
            if age+1e-9>=1.10 {launch(1,in:engine)}
        }
        let movers=plan.action == .sideBySide ? [1]:[0,1]
        if movers.allSatisfy({actors[participants[$0]]?.launched == true && engine.bird(participants[$0])?.state == .perched}) {
            settled+=dt
            if settled+1e-9>=1.2 {
                // A completed encounter starts a fresh quiet stay. Pending actors
                // may have spent their previous dwell time waiting for a visitor.
                for slot in plan.destinations {
                    if let bird=engine.bird(slot.bird),let host=slot.host(in:engine) {bird.perch(on:host,spriteScale:engine.spriteScale(for:bird))}
                }
                return .completed
            }
        }
        return nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard reason != .shutdown else {return}
        let safe=SocialMotionPlanner.clear(plan.destinations,participants:participants,display:plan.display,in:engine)
        for (index,id) in participants.enumerated() {
            guard let actor=actors[id],actor.launched,let bird=engine.bird(id),
                  bird.motionRevision==actor.revision,!bird.isDeparting else {continue}
            let slot=plan.destinations[index]
            // Keep an already valid flight. If its endpoint disappeared, recover
            // from the current position after the runtime releases all slots.
            let misplaced=bird.state != .flying && slot.point(in:engine).map{Geometry.distance($0,bird.position)>0.00001} == true
            let unsafeHop=plan.action == .giveWay && index==0 && bird.state != .perched &&
                !SocialMotionPlanner.hopCorridorClear(origin:actor.origin,destination:slot,
                    participants:participants,display:plan.display,in:engine)
            if !safe || !slot.isValid(in:engine) || bird.needsDestination || misplaced || unsafeHop {
                if let recovery=engine.plan(for:bird,avoiding:unsafeHop ? bird.position:nil) {recovery.apply(to:bird,random:engine.random)}
                else {bird.fly(to:bird.position,host:nil,arc:0,urgent:true)}
            }
        }
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard let index=participants.firstIndex(of:id),let actor=actors[id],let bird=engine.bird(id),
              actor.revision==bird.motionRevision,bird.state == .perched else {return nil}
        let destination=plan.destinations[index].point(in:engine) ?? bird.position
        let other=engine.bird(participants[1-index])?.position ?? destination
        let target=actor.launched || (plan.action == .sideBySide && index==0) ? other:destination
        let facing=abs(target.x-bird.position.x)>1 ? target.x>bird.position.x:bird.facingRight
        let u=min(1,max(0,age/0.35)),hop=actor.launched ? 0:actor.initialHop*(1-u*u*(3-2*u))
        return BirdPose(frameName:age>0.22 && age<0.34 ? "blink":"stand",hopOffset:hop,facingRight:facing)
    }
}
