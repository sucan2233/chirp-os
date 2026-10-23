import Foundation
import CoreGraphics

/// A single, finite same-ledge move. Pointer position chooses the direction once;
/// neither motion nor validation follows the pointer after acceptance.
struct SideHopPlan {
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.sideHop).requiredFrames}
    let id:BirdID
    let host:Surface
    let startFraction:CGFloat
    let destination:LandingReservation
    let scale:CGFloat
    let pointer:CGPoint
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]

    /// Conservative continuous swept volume, including both facings, tail and
    /// the full low arch. This cannot miss a thin blocker between sample points.
    private func corridor(on host:Surface) -> CGRect {
        let a=Geometry.foot(on:host,fraction:startFraction,edge:.top,scale:scale)
        let b=Geometry.foot(on:host,fraction:destination.fraction,edge:.top,scale:scale)
        let area=Geometry.landingFootprint(at:a,scale:scale).union(Geometry.landingFootprint(at:b,scale:scale))
        return area.union(area.offsetBy(dx:0,dy:-Bird.sideHopRise(scale:scale)))
    }
    func sweptFootprint(in engine:BehaviorEngine) -> CGRect? {
        guard let current=destination.host(in:engine),let bird=engine.bird(id) else {return nil}
        let actual=Geometry.landingFootprint(at:bird.position,scale:scale)
        return corridor(on:host).union(corridor(on:current)).union(actual)
    }
    func isSafe(in engine:BehaviorEngine) -> Bool {
        guard let current=destination.host(in:engine),current.isGround==host.isGround,
              current.rect.size==host.rect.size,let bird=engine.bird(id),
              engine.spriteScale(for:bird)==scale,scale.isFinite,scale>0,
              engine.world.screens==screens,engine.world.displays==displays,
              let area=sweptFootprint(in:engine),display.contains(area),destination.isValid(in:engine) else {return false}
        func intersects(_ other:CGRect) -> Bool {
            let cut=area.intersection(other)
            return !cut.isNull && !cut.isEmpty
        }
        guard !Geometry.blockers(on:current,surfaces:engine.world.surfaces).contains(where:{intersects($0.rect)}) else {return false}
        for other in engine.birds where engine.id(of:other) != id {
            let otherScale=engine.spriteScale(for:other)
            let footprint=Geometry.landingFootprint(at:other.position,scale:otherScale)
                .union(engine.bounds(of:other)).insetBy(dx:-8,dy:-8)
            if intersects(footprint) {return false}
            // Ordinary routed arrivals have a destination but no runtime slot.
            if let host=engine.world.surfaces.first(where:{$0.id==other.hostID}) {
                let foot=Geometry.foot(on:host,fraction:other.fraction,edge:other.edge,scale:otherScale)
                if intersects(Geometry.landingFootprint(at:foot,scale:otherScale).insetBy(dx:-8,dy:-8)) {return false}
            }
        }
        for slot in engine.runtime.landingReservations where slot.bird != id {
            guard let footprint=slot.footprint(in:engine),!intersects(footprint) else {return false}
        }
        // Destination slots alone do not protect two crossing hop trajectories.
        for run in engine.runtime.runs.values {
            guard let other=run.execution as? SideHopExecution,other.plan.id != id else {continue}
            guard let footprint=other.plan.sweptFootprint(in:engine),
                  !intersects(footprint.insetBy(dx:-8,dy:-8)) else {return false}
        }
        return true
    }

    static func make(id:BirdID,in engine:BehaviorEngine) -> SideHopPlan? {
        guard let bird=engine.bird(id),let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}) else {return nil}
        let scale=engine.spriteScale(for:bird),start=bird.position,pointer=engine.world.pointer
        guard scale.isFinite,scale>0,pointer.x.isFinite,pointer.y.isFinite,
              let display=engine.world.displays.first(where:{$0.contains(Geometry.landingFootprint(at:start,scale:scale))}),
              Geometry.distance(start,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,scale:scale))<0.001 else {return nil}
        let left=Geometry.perchX(0,rect:host.rect),right=Geometry.perchX(1,rect:host.rect)
        guard right>left else {return nil}
        let direction:CGFloat=pointer.x<start.x ? 1:(pointer.x>start.x ? -1:(bird.facingRight ? 1:-1))
        // Three bounded probes, with a natural medium jump preferred. Never
        // clamp onto an undersized edge or reverse toward the pointer to fit.
        for distance:CGFloat in [85,110,60] {
            let x=start.x+direction*distance*scale
            guard x>=left,x<=right else {continue}
            let fraction=(x-left)/(right-left)
            let slot=LandingReservation(bird:id,host:host,fraction:fraction)
            guard let end=slot.point(in:engine),
                  Geometry.distance(end,pointer)>Geometry.distance(start,pointer)+0.001 else {continue}
            let plan=SideHopPlan(id:id,host:host,startFraction:bird.fraction,destination:slot,
                scale:scale,pointer:pointer,display:display,screens:engine.world.screens,displays:engine.world.displays)
            if plan.isSafe(in:engine) {return plan}
        }
        return nil
    }
}

final class SideHopExecution:BehaviorExecution {
    let plan:SideHopPlan
    let source:BehaviorSource
    let kind:BehaviorKind = .sideHop
    var participants:[BirdID] {[plan.id]}
    var landingReservations:[LandingReservation] {[plan.destination]}
    var timeout:Double {Bird.sideHopDuration+1.1}
    private var revision:UInt64?

    init(plan:SideHopPlan,source:BehaviorSource) {
        self.plan=plan;self.source=source
    }
    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),bird.beginSideHop(on:plan.host,to:plan.destination.fraction,spriteScale:plan.scale) else {return}
        revision=bird.motionRevision
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:source) else {return .cancelled(.settingsChanged)}
        guard SideHopPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
        if engine.world.buttonsDown {return .cancelled(.userInput)}
        guard let revision,bird.motionRevision==revision,!bird.isDeparting,bird.edge == .top,
              bird.hostID==plan.host.id,!bird.needsDestination,
              bird.isSideHopping || bird.state == .perched,
              let host=plan.destination.host(in:engine),plan.isSafe(in:engine) else {return .failed(.targetInvalid)}
        let pointer=engine.world.pointer
        if bird.state == .flying,Geometry.distance(pointer,plan.pointer)>24*plan.scale,
           let end=plan.destination.point(in:engine),
           Geometry.distance(end,pointer)+0.001<Geometry.distance(bird.position,pointer) {
            return .cancelled(.pointerMoved)
        }
        // The actual metadata interval belongs to Bird.updateHost; estimating
        // velocity from validation frequency would mistake gentle 10 Hz samples
        // for fast 60 Hz motion. This only queues a host for Bird.tick to follow.
        if bird.isSideHopping,!bird.updateSideHopHost(host,spriteScale:plan.scale) {return .failed(.targetInvalid)}
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        // Runtime validates before advancing. The motion clock lives solely in
        // Bird.tick; this observes the touchdown/settling result from that tick.
        if bird.state == .perched {bird.finishSideHop();return .completed}
        return nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),bird.motionRevision==revision else {return}
        bird.cancelSideHop()
    }
}

extension BehaviorEngine {
    private func sideHopRejection(_ id:BirdID,source:BehaviorSource) -> BehaviorReason? {
        guard let bird=bird(id) else {return .missingBird}
        guard birds.contains(where:{$0 === bird}),role(of:bird) == .resident,!bird.isDeparting else {return .unavailableBird}
        guard runtime.owners[id]==nil else {return .busy}
        guard bird.state == .perched,bird.edge == .top,!bird.needsDestination,
              bird.stateTime>=0.45,bird.perchDuration-bird.stateTime>1.5,
              abs(baseHop(for:id,bird:bird))<0.001 else {return .unavailableBird}
        guard SideHopPlan.requiredFrames.isSubset(of:world.availableFrames[bird.profile.id] ?? []) else {return .missingFrames}
        guard !world.buttonsDown else {return .userInput}
        guard hasUsablePerch(bird) else {return .noSpace}
        if source == .automatic {
            guard let state=perchPlanner.ecology(id),state.disturbance<0.6,
                  perchPlanner.automaticWeight(id,kind:.sideHop)>0 else {return .unavailableBird}
            guard world.displays.contains(where:{$0.contains(world.pointer) && $0.contains(bird.position)}),
                  pointerNear(bird) else {return .pointerMoved}
        }
        return nil
    }
    /// Geometry-only eligibility for the scheduler's bounded entry opportunity.
    /// Does not consume randomness, lease a bird, or acknowledge an entry.
    func sideHopCandidate(_ id:BirdID,source:BehaviorSource = .automatic) -> Bool {
        !paused && BehaviorDefinitions.definition(for:.sideHop).isEnabled(settings:settings,source:source) &&
            sideHopRejection(id,source:source)==nil && SideHopPlan.make(id:id,in:self) != nil
    }
    @discardableResult
    func requestSideHop(source:BehaviorSource,target:BirdID?=nil) -> BehaviorResult {
        func reject(_ reason:BehaviorReason) -> BehaviorResult {
            emit(.rejected,kind:.sideHop,source:source,reason:reason);return .rejected(reason)
        }
        guard !paused else {return reject(.paused)}
        guard BehaviorDefinitions.definition(for:.sideHop).isEnabled(settings:settings,source:source) else {return reject(.disabled)}
        guard !world.buttonsDown else {return reject(.userInput)}
        let ids=target.map{[$0]} ?? birds.compactMap{id(of:$0)}.sorted()
        var reasons:[BehaviorReason]=[],plans:[SideHopPlan]=[]
        for id in ids {
            if let reason=sideHopRejection(id,source:source) {reasons.append(reason);continue}
            if let plan=SideHopPlan.make(id:id,in:self) {plans.append(plan)} else {reasons.append(.noSpace)}
        }
        guard let plan=ecologicalChoice(plans,weight:{source == .automatic ? self.perchPlanner.automaticWeight($0.id,kind:.sideHop):1}) else {
            return reject([BehaviorReason.userInput,.missingFrames,.busy,.noSpace,.pointerMoved,.missingBird].first{reasons.contains($0)} ?? .unavailableBird)
        }
        let result=runtime.start(SideHopExecution(plan:plan,source:source),source:source,in:self)
        if result.accepted {perchPlanner.suppress(plan.id)}
        else if case .rejected(let reason)=result {emit(.rejected,kind:.sideHop,source:source,reason:reason)}
        return result
    }
}
