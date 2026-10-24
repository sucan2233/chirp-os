import Foundation
import CoreGraphics

/// Output-only evidence captured before cancellation destroys the motion state.
/// A safety exit describes the guard that fired, not a proof that every upstream
/// planner was correct. Unexplained motion changes must remain unresolved.
public struct SideHopDiagnostic:Codable,Equatable {
    public enum Classification:String,Codable {case safetyExit,invariantViolation,unresolved}
    public enum Cause:String,Codable {
        case hostMissingOrReplaced,hostGeometryChanged,scaleChanged,displayLayoutChanged
        case corridorOutsideDisplay,destinationInvalid,surfaceObstruction
        case birdIntrusion,arrivalConflict,reservationConflict,traversalConflict
        case startRejected,motionRevisionChanged,motionStateChanged,hostTrackingRejected,unattributed
        public var classification:Classification {
            switch self {
            case .startRejected,.hostTrackingRejected:return .invariantViolation
            case .motionRevisionChanged,.motionStateChanged,.unattributed:return .unresolved
            default:return .safetyExit
            }
        }
    }
    public struct SafetyEvidence:Codable,Equatable {
        public let cause:Cause
        public let conflictingBird:UInt64?
        public let conflictingSurface:UInt32?
        public let conflictingRun:UInt64?
        public let conflictingFootprint:CGRect?
    }
    /// The guard that actually failed determines cause and classification.
    /// Concurrent geometry is evidence, never a replacement for that guard.
    public let cause:Cause
    public let classification:Classification
    public let accompanyingSafety:SafetyEvidence?
    public let stage:String
    public let simulationTime:Double
    public let birdID:UInt64
    public let birdState:String?
    public let position:CGPoint?
    public let isSideHopping:Bool
    public let needsDestination:Bool
    public let expectedMotionRevision:UInt64?
    public let actualMotionRevision:UInt64?
    public let hostID:UInt32
    public let hostPID:Int32
    public let originalHost:CGRect
    public let currentHost:CGRect?
    public let startFraction:CGFloat
    public let destinationFraction:CGFloat
    public let destination:CGPoint?
    public let plannedScale:CGFloat
    public let currentScale:CGFloat?
    public let corridor:CGRect?
    public let conflictingBird:UInt64?
    public let conflictingSurface:UInt32?
    public let conflictingRun:UInt64?
    public let conflictingFootprint:CGRect?
}

/// Same-ledge executions protect their continuous path as well as their slots.
protocol LedgeTraversalExecution:BehaviorExecution {
    func sweptFootprint(in engine:BehaviorEngine) -> CGRect?
}

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
    struct SafetyIssue {
        let cause:SideHopDiagnostic.Cause
        var bird:UInt64?=nil
        var surface:UInt32?=nil
        var run:UInt64?=nil
        var footprint:CGRect?=nil
    }
    /// Runtime pads both slots; it can reject a margin-only overlap before the
    /// unpadded traversal corridor reaches the foreign slot's padded footprint.
    /// Used only to explain an already failed run, never to change admission.
    func runtimeReservationIssue(in engine:BehaviorEngine) -> SafetyIssue? {
        for slot in engine.runtime.landingReservations where slot.bird != id {
            if destination.conflicts(with:slot,in:engine) {
                return SafetyIssue(cause:.reservationConflict,bird:slot.bird.rawValue,
                    run:engine.runtime.owners[slot.bird]?.rawValue,footprint:slot.footprint(in:engine))
            }
        }
        return nil
    }
    func isSafe(in engine:BehaviorEngine) -> Bool {safetyIssue(in:engine)==nil}
    /// The same predicates and order as admission/validation, with no RNG or
    /// simulation mutation. Report the first concrete obstruction, not a guess.
    func safetyIssue(in engine:BehaviorEngine) -> SafetyIssue? {
        guard let current=destination.host(in:engine) else {return SafetyIssue(cause:.hostMissingOrReplaced)}
        guard current.isGround==host.isGround,current.rect.size==host.rect.size else {return SafetyIssue(cause:.hostGeometryChanged)}
        guard let bird=engine.bird(id) else {return SafetyIssue(cause:.unattributed)}
        guard engine.spriteScale(for:bird)==scale,scale.isFinite,scale>0 else {return SafetyIssue(cause:.scaleChanged)}
        guard engine.world.screens==screens,engine.world.displays==displays else {return SafetyIssue(cause:.displayLayoutChanged)}
        guard let area=sweptFootprint(in:engine),display.contains(area) else {return SafetyIssue(cause:.corridorOutsideDisplay)}
        guard destination.isValid(in:engine) else {
            let target=destination.point(in:engine).map{Geometry.landingFootprint(at:$0,scale:scale)}
            let blocker=target.flatMap {area in
                Geometry.blockers(on:current,surfaces:engine.world.surfaces).first {
                    let cut=area.intersection($0.rect);return !cut.isNull && !cut.isEmpty
                }
            }
            return SafetyIssue(cause:.destinationInvalid,surface:blocker?.id,footprint:blocker?.rect)
        }
        func intersects(_ other:CGRect) -> Bool {
            let cut=area.intersection(other)
            return !cut.isNull && !cut.isEmpty
        }
        if let blocker=Geometry.blockers(on:current,surfaces:engine.world.surfaces).first(where:{intersects($0.rect)}) {
            return SafetyIssue(cause:.surfaceObstruction,surface:blocker.id,footprint:blocker.rect)
        }
        for other in engine.birds where engine.id(of:other) != id {
            let otherScale=engine.spriteScale(for:other)
            let footprint=Geometry.landingFootprint(at:other.position,scale:otherScale)
                .union(engine.bounds(of:other)).insetBy(dx:-8,dy:-8)
            if intersects(footprint) {return SafetyIssue(cause:.birdIntrusion,bird:engine.id(of:other)?.rawValue,footprint:footprint)}
            // Ordinary routed arrivals have a destination but no runtime slot.
            if let host=engine.world.surfaces.first(where:{$0.id==other.hostID}) {
                let foot=Geometry.foot(on:host,fraction:other.fraction,edge:other.edge,scale:otherScale)
                let footprint=Geometry.landingFootprint(at:foot,scale:otherScale).insetBy(dx:-8,dy:-8)
                if intersects(footprint) {return SafetyIssue(cause:.arrivalConflict,bird:engine.id(of:other)?.rawValue,surface:host.id,footprint:footprint)}
            }
        }
        for slot in engine.runtime.landingReservations where slot.bird != id {
            guard let footprint=slot.footprint(in:engine) else {
                return SafetyIssue(cause:.reservationConflict,bird:slot.bird.rawValue,run:engine.runtime.owners[slot.bird]?.rawValue)
            }
            if intersects(footprint) {
                return SafetyIssue(cause:.reservationConflict,bird:slot.bird.rawValue,
                    run:engine.runtime.owners[slot.bird]?.rawValue,footprint:footprint)
            }
        }
        // Destination slots alone do not protect two crossing hop trajectories.
        for run in engine.runtime.runs.values {
            guard let other=run.execution as? LedgeTraversalExecution,!other.participants.contains(id) else {continue}
            guard let footprint=other.sweptFootprint(in:engine) else {return SafetyIssue(cause:.traversalConflict,run:run.id.rawValue)}
            let padded=footprint.insetBy(dx:-8,dy:-8)
            if intersects(padded) {return SafetyIssue(cause:.traversalConflict,run:run.id.rawValue,footprint:padded)}
        }
        return nil
    }

    static func make(id:BirdID,in engine:BehaviorEngine) -> SideHopPlan? {
        guard let bird=engine.bird(id),let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}),!host.isHabitat else {return nil}
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

final class SideHopExecution:LedgeTraversalExecution {
    let plan:SideHopPlan
    let source:BehaviorSource
    let kind:BehaviorKind = .sideHop
    var participants:[BirdID] {[plan.id]}
    var landingReservations:[LandingReservation] {[plan.destination]}
    var timeout:Double {Bird.sideHopDuration+1.1}
    private var revision:UInt64?
    private(set) var diagnostic:SideHopDiagnostic?

    init(plan:SideHopPlan,source:BehaviorSource) {
        self.plan=plan;self.source=source
    }
    func sweptFootprint(in engine:BehaviorEngine) -> CGRect? {plan.sweptFootprint(in:engine)}
    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),bird.beginSideHop(on:plan.host,to:plan.destination.fraction,spriteScale:plan.scale) else {
            capture(.init(cause:.startRejected),stage:"start",in:engine);return
        }
        revision=bird.motionRevision
    }
    private func capture(_ issue:SideHopPlan.SafetyIssue,accompanyingSafety:SideHopPlan.SafetyIssue?=nil,
                         stage:String,in engine:BehaviorEngine) {
        guard diagnostic==nil else {return}
        let bird=engine.bird(plan.id)
        func point(_ value:CGPoint?) -> CGPoint? {
            guard let value,value.x.isFinite,value.y.isFinite else {return nil};return value
        }
        func rect(_ value:CGRect?) -> CGRect? {
            guard let value,value.origin.x.isFinite,value.origin.y.isFinite,
                  value.width.isFinite,value.height.isFinite else {return nil};return value
        }
        let currentScale=bird.map{engine.spriteScale(for:$0)}
        let safety=accompanyingSafety.map {
            SideHopDiagnostic.SafetyEvidence(cause:$0.cause,conflictingBird:$0.bird,conflictingSurface:$0.surface,
                conflictingRun:$0.run,conflictingFootprint:rect($0.footprint))
        }
        diagnostic=SideHopDiagnostic(cause:issue.cause,classification:issue.cause.classification,accompanyingSafety:safety,stage:stage,
            simulationTime:engine.time,birdID:plan.id.rawValue,birdState:bird?.state.rawValue,position:point(bird?.position),
            isSideHopping:bird?.isSideHopping ?? false,needsDestination:bird?.needsDestination ?? false,
            expectedMotionRevision:revision,actualMotionRevision:bird?.motionRevision,hostID:plan.host.id,hostPID:plan.host.pid,
            originalHost:plan.host.rect,currentHost:rect(plan.destination.host(in:engine)?.rect),startFraction:plan.startFraction,
            destinationFraction:plan.destination.fraction,destination:point(plan.destination.point(in:engine)),plannedScale:plan.scale,
            currentScale:currentScale.flatMap{$0.isFinite ? $0:nil},corridor:rect(plan.sweptFootprint(in:engine)),
            conflictingBird:issue.bird,conflictingSurface:issue.surface,conflictingRun:issue.run,conflictingFootprint:rect(issue.footprint))
    }
    private func invalid(_ cause:SideHopDiagnostic.Cause,in engine:BehaviorEngine) -> BehaviorCompletion {
        capture(.init(cause:cause),accompanyingSafety:plan.safetyIssue(in:engine),stage:"executionValidation",in:engine)
        return .failed(.targetInvalid)
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:source) else {return .cancelled(.settingsChanged)}
        guard SideHopPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
        if engine.world.buttonsDown {return .cancelled(.userInput)}
        guard let revision else {return invalid(.startRejected,in:engine)}
        guard bird.motionRevision==revision else {return invalid(.motionRevisionChanged,in:engine)}
        guard !bird.isDeparting,bird.edge == .top,bird.hostID==plan.host.id,!bird.needsDestination,
              bird.isSideHopping || bird.state == .perched else {return invalid(.motionStateChanged,in:engine)}
        guard let host=plan.destination.host(in:engine) else {return invalid(.hostMissingOrReplaced,in:engine)}
        if let issue=plan.safetyIssue(in:engine) {
            capture(issue,stage:"executionValidation",in:engine);return .failed(.targetInvalid)
        }
        let pointer=engine.world.pointer
        if bird.state == .flying,Geometry.distance(pointer,plan.pointer)>24*plan.scale,
           let end=plan.destination.point(in:engine),
           Geometry.distance(end,pointer)+0.001<Geometry.distance(bird.position,pointer) {
            return .cancelled(.pointerMoved)
        }
        // The actual metadata interval belongs to Bird.updateHost; estimating
        // velocity from validation frequency would mistake gentle 10 Hz samples
        // for fast 60 Hz motion. This only queues a host for Bird.tick to follow.
        if bird.isSideHopping,!bird.updateSideHopHost(host,spriteScale:plan.scale) {return invalid(.hostTrackingRejected,in:engine)}
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
        // Runtime can reject a landing slot before calling execution.validate.
        // It detaches first, but foreign runs and the pre-cancel bird still exist.
        if reason == .targetInvalid {
            capture(plan.safetyIssue(in:engine) ?? plan.runtimeReservationIssue(in:engine) ?? .init(cause:.unattributed),
                stage:"runtimeValidation",in:engine)
        }
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
