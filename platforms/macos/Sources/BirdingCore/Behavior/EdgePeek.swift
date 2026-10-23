import Foundation
import CoreGraphics

/// Only real window endpoints are eligible. Both legs use the same conservative
/// SideHopPlan geometry; no visible-piece boundary can become a pretend edge.
struct EdgePeekPlan {
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.edgePeek).requiredFrames}
    let approach:SideHopPlan
    let origin:LandingReservation
    var id:BirdID {approach.id}
    var returnPlan:SideHopPlan {
        SideHopPlan(id:id,host:approach.host,startFraction:approach.destination.fraction,
            destination:origin,scale:approach.scale,pointer:approach.pointer,display:approach.display,
            screens:approach.screens,displays:approach.displays)
    }
    func isSafe(in engine:BehaviorEngine) -> Bool {
        approach.isSafe(in:engine) && returnPlan.isSafe(in:engine)
    }
    func pointerIsClear(in engine:BehaviorEngine) -> Bool {
        let pointer=engine.world.pointer
        guard pointer.x.isFinite,pointer.y.isFinite,let area=approach.sweptFootprint(in:engine) else {return false}
        return !area.insetBy(dx:-48*approach.scale,dy:-48*approach.scale).contains(pointer)
    }
    static func make(id:BirdID,in engine:BehaviorEngine) -> EdgePeekPlan? {
        guard let bird=engine.bird(id),
              let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}),!host.isGround,!host.isHabitat else {return nil}
        let scale=engine.spriteScale(for:bird)
        guard scale.isFinite,scale>0,bird.fraction.isFinite,(0...1).contains(bird.fraction),
              let display=engine.world.displays.first(where:{$0.contains(Geometry.landingFootprint(at:bird.position,scale:scale))}),
              Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,scale:scale))<0.001 else {return nil}
        let origin=LandingReservation(bird:id,host:host,fraction:bird.fraction)
        let endpoints:[CGFloat]=bird.fraction<=0.5 ? [0,1]:[1,0]
        for fraction in endpoints {
            let distance=abs(Geometry.perchX(fraction,rect:host.rect)-bird.position.x)/scale
            guard distance>=80-0.001,distance<=110+0.001 else {continue}
            let hop=SideHopPlan(id:id,host:host,startFraction:bird.fraction,
                destination:LandingReservation(bird:id,host:host,fraction:fraction),scale:scale,
                pointer:engine.world.pointer,display:display,screens:engine.world.screens,displays:engine.world.displays)
            let plan=EdgePeekPlan(approach:hop,origin:origin)
            if !origin.conflicts(with:hop.destination,in:engine),
               plan.isSafe(in:engine),plan.pointerIsClear(in:engine) {return plan}
        }
        return nil
    }
}

public final class EdgePeekExecution:LedgeTraversalExecution {
    /// These species have downward head displacement in the renderer's idle
    /// peck/probe sequence. A matching frame name alone is insufficient evidence.
    public static let supportedSpecies:Set<SpeciesID> = [.treeSparrow,.chineseBlackbird,.hoopoe,.whimbrel]
    static let observationDuration=1.6
    enum Phase:String {case approach,observe,returning="return"}
    let plan:EdgePeekPlan
    let source:BehaviorSource
    let kind:BehaviorKind = .edgePeek
    var participants:[BirdID] {[plan.id]}
    var landingReservations:[LandingReservation] {[plan.origin,plan.approach.destination]}
    var timeout:Double {6}
    private(set) var phase:Phase = .approach
    private(set) var observationAge=0.0
    private var revision:UInt64?

    init(plan:EdgePeekPlan,source:BehaviorSource) {self.plan=plan;self.source=source}
    func sweptFootprint(in engine:BehaviorEngine) -> CGRect? {plan.approach.sweptFootprint(in:engine)}
    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),plan.isSafe(in:engine),plan.pointerIsClear(in:engine),
              bird.beginSideHop(on:plan.approach.host,to:plan.approach.destination.fraction,spriteScale:plan.approach.scale) else {return}
        revision=bird.motionRevision
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:source) else {return .cancelled(.settingsChanged)}
        guard Self.supportedSpecies.contains(bird.profile.id),
              EdgePeekPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
        guard !engine.world.buttonsDown else {return .cancelled(.userInput)}
        guard let revision,bird.motionRevision==revision,!bird.isDeparting,bird.edge == .top,
              bird.hostID==plan.approach.host.id,!bird.needsDestination,bird.isSideHopping,
              phase != .observe || bird.state == .perched,
              let host=plan.origin.host(in:engine),!host.isGround,!host.isHabitat,plan.isSafe(in:engine) else {return .failed(.targetInvalid)}
        guard plan.pointerIsClear(in:engine) else {return .cancelled(.pointerMoved)}
        // Keep the hop's metadata queue during observation too. Bird.updateHost
        // retains the actual sampling interval and detects fast host movement;
        // only Bird.tick follows a gentle host, including after a pause.
        guard bird.updateSideHopHost(host,spriteScale:plan.approach.scale) else {return .failed(.targetInvalid)}
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        switch phase {
        case .approach:
            if bird.state == .perched {phase = .observe;observationAge=0}
        case .observe:
            observationAge+=dt
            guard observationAge+1e-10>=Self.observationDuration,
                  let host=plan.origin.host(in:engine) else {return nil}
            // A queued window move must settle through tick, never a position
            // assignment or a fresh perch(on:) at the new coordinates.
            let anchor=Geometry.foot(on:host,fraction:bird.fraction,edge:.top,scale:plan.approach.scale)
            guard Geometry.distance(bird.position,anchor)<0.001 else {return nil}
            let back=plan.returnPlan
            guard back.isSafe(in:engine) else {return .failed(.targetInvalid)}
            bird.finishSideHop()
            guard bird.beginSideHop(on:host,to:back.destination.fraction,spriteScale:back.scale) else {return .failed(.targetInvalid)}
            revision=bird.motionRevision;phase = .returning
        case .returning:
            if bird.state == .perched,let anchor=plan.origin.point(in:engine),
               Geometry.distance(bird.position,anchor)<0.001 {
                bird.finishSideHop();return .completed
            }
        }
        return nil
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard id==plan.id,phase == .observe else {return nil}
        // One deliberate, brief bow: no looping peck animation and no invented
        // frame semantics for species outside supportedSpecies.
        let frame:String
        switch observationAge/Self.observationDuration {
        case ..<0.2:frame="idle0"
        case ..<0.4:frame="idle1"
        case ..<0.6:frame="idle2"
        case ..<0.8:frame="idle1"
        default:frame="idle0"
        }
        return BirdPose(frameName:frame,hopOffset:0,facingRight:plan.approach.destination.fraction==1)
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),bird.motionRevision==revision else {return}
        // A perched state can still have a pending host move or an occluded
        // endpoint. Keep it only if the actual feet are settled on a safe host;
        // otherwise recover from here without adopting queued coordinates.
        if bird.state == .perched,let host=plan.origin.host(in:engine),
           Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,
               edge:.top,scale:engine.spriteScale(for:bird)))<0.001,
           engine.hasUsablePerch(bird) {
            bird.finishSideHop()
        } else {bird.cancelSideHop()}
    }
}

extension BehaviorEngine {
    private func edgePeekRejection(_ id:BirdID,source:BehaviorSource) -> BehaviorReason? {
        guard let bird=bird(id) else {return .missingBird}
        guard birds.contains(where:{$0 === bird}),role(of:bird) == .resident,!bird.isDeparting else {return .unavailableBird}
        guard runtime.owners[id]==nil else {return .busy}
        guard EdgePeekExecution.supportedSpecies.contains(bird.profile.id) else {return .noSpecies}
        guard bird.state == .perched,bird.edge == .top,!bird.needsDestination,
              bird.stateTime>=0.45,bird.perchDuration-bird.stateTime>6,
              abs(baseHop(for:id,bird:bird))<0.001 else {return .unavailableBird}
        guard EdgePeekPlan.requiredFrames.isSubset(of:world.availableFrames[bird.profile.id] ?? []) else {return .missingFrames}
        guard !world.buttonsDown else {return .userInput}
        guard hasUsablePerch(bird) else {return .noSpace}
        if source == .automatic {
            guard let state=perchPlanner.ecology(id),state.quietTime>=8,state.disturbance<0.35,
                  perchPlanner.automaticWeight(id,kind:.edgePeek)>0 else {return .unavailableBird}
            guard !pointerNear(bird) else {return .pointerMoved}
        }
        return nil
    }
    func edgePeekCandidate(_ id:BirdID,source:BehaviorSource = .automatic) -> Bool {
        !paused && BehaviorDefinitions.definition(for:.edgePeek).isEnabled(settings:settings,source:source) &&
            edgePeekRejection(id,source:source)==nil && EdgePeekPlan.make(id:id,in:self) != nil
    }
    @discardableResult
    func requestEdgePeek(source:BehaviorSource,target:BirdID?=nil) -> BehaviorResult {
        func reject(_ reason:BehaviorReason) -> BehaviorResult {
            emit(.rejected,kind:.edgePeek,source:source,reason:reason);return .rejected(reason)
        }
        guard !paused else {return reject(.paused)}
        guard BehaviorDefinitions.definition(for:.edgePeek).isEnabled(settings:settings,source:source) else {return reject(.disabled)}
        guard !world.buttonsDown else {return reject(.userInput)}
        let ids=target.map{[$0]} ?? birds.compactMap{id(of:$0)}.sorted()
        var reasons:[BehaviorReason]=[],plans:[EdgePeekPlan]=[]
        for id in ids {
            if let reason=edgePeekRejection(id,source:source) {reasons.append(reason);continue}
            if let plan=EdgePeekPlan.make(id:id,in:self) {plans.append(plan)} else {reasons.append(.noSpace)}
        }
        guard let plan=ecologicalChoice(plans,weight:{source == .automatic ? self.perchPlanner.automaticWeight($0.id,kind:.edgePeek):1}) else {
            return reject([BehaviorReason.userInput,.missingFrames,.busy,.noSpecies,.noSpace,.pointerMoved,.missingBird].first{reasons.contains($0)} ?? .unavailableBird)
        }
        let result=runtime.start(EdgePeekExecution(plan:plan,source:source),source:source,in:self)
        if result.accepted {perchPlanner.suppress(plan.id)}
        else if case .rejected(let reason)=result {emit(.rejected,kind:.edgePeek,source:source,reason:reason)}
        return result
    }
}
