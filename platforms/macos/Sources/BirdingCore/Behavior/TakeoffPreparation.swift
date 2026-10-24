import Foundation
import CoreGraphics

extension BehaviorEngine {
    /// Explicit preview/manual entry. Natural routing passes its already chosen
    /// destination to prepareTakeoff instead, so it never draws a second plan.
    @discardableResult func requestTakeoffPreparation(source:BehaviorSource,target:BirdID?=nil) -> BehaviorResult {
        func reject(_ reason:BehaviorReason) -> BehaviorResult {
            emit(.rejected,kind:.takeoffPreparation,source:source,reason:reason)
            return .rejected(reason)
        }
        if let reason=takeoffPreparationGate() {return reject(reason)}
        let ids=target.map{[$0]} ?? birds.compactMap{id(of:$0)}.sorted()
        var reasons:[BehaviorReason]=[]
        let eligible=ids.filter {id in
            if let reason=takeoffPreparationRejection(id) {reasons.append(reason);return false}
            return true
        }
        guard let id=perchPlanner.select(eligible),let bird=bird(id) else {
            return reject([BehaviorReason.missingBird,.missingFrames,.busy,.noSpace,.unavailableBird]
                .first{reasons.contains($0)} ?? .unavailableBird)
        }
        guard let destination=plan(for:bird) else {return reject(.noSpace)}
        let result=prepareTakeoff(id:id,plan:destination,source:source)
        if case .rejected(let reason)=result {return reject(reason)}
        return result
    }

    /// Does not mutate motion, release an existing owner, consume flight RNG or
    /// emit rejection events. A caller can immediately apply this same plan if
    /// preparation is unavailable (including urgent, hostless or side routes).
    @discardableResult func prepareTakeoff(id:BirdID,plan:DestinationPlan,source:BehaviorSource) -> BehaviorResult {
        if let reason=takeoffPreparationGate() {return .rejected(reason)}
        if let reason=takeoffPreparationRejection(id) {return .rejected(reason)}
        guard !plan.urgent,plan.edge == .top,let host=plan.host,host.isGround || host.layer==0,
              plan.duration.isFinite,plan.duration>0,plan.arc.isFinite,plan.arc>=0,
              plan.point.x.isFinite,plan.point.y.isFinite else {return .rejected(.noSpace)}
        let execution=TakeoffPreparationExecution(id:id,plan:plan)
        // Check both anchors before acquiring anything; runtime.start repeats
        // the reservation conflict check atomically with lease acquisition.
        execution.start(in:self)
        if let invalid=execution.validate(in:self) {
            switch invalid {
            case .completed:return .rejected(.unavailableBird)
            case .cancelled(let reason),.failed(let reason):return .rejected(reason)
            }
        }
        let result=runtime.start(execution,source:source,in:self)
        if result.accepted {perchPlanner.suppress(id)}
        return result
    }

    private func takeoffPreparationGate() -> BehaviorReason? {
        guard !paused else {return .paused}
        guard settings.perchActions,settings.takeoffPreparationEnabled else {return .disabled}
        guard !world.buttonsDown else {return .userInput}
        return nil
    }

    private func takeoffPreparationRejection(_ id:BirdID) -> BehaviorReason? {
        guard let bird=bird(id) else {return .missingBird}
        guard birds.contains(where:{$0 === bird}),role(of:bird) == .resident,
              bird.state == .perched,bird.edge == .top,!bird.isDeparting else {return .unavailableBird}
        guard runtime.owners[id]==nil else {return .busy}
        guard TakeoffPreparationExecution.requiredFrames.isSubset(of:world.availableFrames[bird.profile.id] ?? []) else {
            return .missingFrames
        }
        guard let host=world.surfaces.first(where:{$0.id==bird.hostID}),host.isGround || host.layer==0,
              hasUsablePerch(bird) else {return .noSpace}
        // needsDestination is expected to be true at a natural dwell deadline.
        // The execution separately verifies the live source host and motion.
        return nil
    }
}

/// Only real stand/fly0 artwork is presented: planted orientation, then open
/// wings. This is a preparation pose, not a new crouch animation or a flight loop.
final class TakeoffPreparationExecution:BehaviorExecution {
    static let duration=0.45
    static let wingsOpenAt=0.30
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.takeoffPreparation).requiredFrames}

    let id:BirdID
    let plan:DestinationPlan
    let kind:BehaviorKind = .takeoffPreparation
    var participants:[BirdID] {[id]}
    var timeout:Double {Self.duration+0.5}
    var landingReservations:[LandingReservation] {
        plan.host.map{[LandingReservation(bird:id,host:$0,fraction:plan.fraction)]} ?? []
    }

    private struct Anchor {
        let revision:UInt64
        let source:LandingReservation
        let scale:CGFloat
        let initialHop:CGFloat
        let sourceDisplay:CGRect
        let targetDisplay:CGRect
        let workAreas:[CGRect]
    }
    private var anchor:Anchor?
    private var age=0.0
    private var facingRight=true

    init(id:BirdID,plan:DestinationPlan) {self.id=id;self.plan=plan}

    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(id),let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}),
              let destination=landingReservations.first,let point=destination.point(in:engine) else {return}
        let scale=engine.spriteScale(for:bird),hop=engine.baseHop(for:id,bird:bird)
        let planted=Geometry.landingFootprint(at:bird.position,scale:scale)
        let sourceArea=planted.union(planted.offsetBy(dx:0,dy:hop*scale))
        guard let sourceDisplay=engine.world.displays.first(where:{
            $0.contains(sourceArea)
        }),let targetDisplay=engine.world.displays.first(where:{
            $0.contains(Geometry.landingFootprint(at:point,scale:scale))
        }) else {return}
        anchor=Anchor(revision:bird.motionRevision,source:LandingReservation(bird:id,host:host,fraction:bird.fraction),
            scale:scale,initialHop:hop,sourceDisplay:sourceDisplay,targetDisplay:targetDisplay,workAreas:engine.world.screens)
        facingRight=abs(point.x-bird.position.x)>1 ? point.x>bird.position.x:bird.facingRight
    }

    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(id) else {return .failed(.missingBird)}
        guard engine.settings.perchActions,engine.settings.takeoffPreparationEnabled else {return .cancelled(.settingsChanged)}
        if engine.world.buttonsDown {return .cancelled(.userInput)}
        guard Self.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
        guard let anchor,let destination=landingReservations.first,
              bird.motionRevision==anchor.revision,bird.state == .perched,bird.edge == .top,!bird.isDeparting,
              bird.hostID==anchor.source.hostID,bird.fraction==anchor.source.fraction,
              anchor.scale.isFinite,anchor.scale>0,engine.spriteScale(for:bird)==anchor.scale,
              engine.world.screens==anchor.workAreas,
              engine.world.displays.contains(anchor.sourceDisplay),engine.world.displays.contains(anchor.targetDisplay),
              anchor.source.isValid(in:engine),destination.isValid(in:engine),
              let sourceHost=anchor.source.host(in:engine),sourceHost.isGround || sourceHost.layer==0,
              let targetHost=destination.host(in:engine),targetHost.isGround || targetHost.layer==0,
              let sourcePoint=anchor.source.point(in:engine),let targetPoint=destination.point(in:engine),
              Geometry.distance(sourcePoint,bird.position)<0.000001,
              anchor.sourceDisplay.contains(Geometry.landingFootprint(at:sourcePoint,scale:anchor.scale)),
              anchor.targetDisplay.contains(Geometry.landingFootprint(at:targetPoint,scale:anchor.scale)),
              targetIsClear(destination,display:anchor.targetDisplay,in:engine) else {return .failed(.targetInvalid)}
        let planted=Geometry.landingFootprint(at:sourcePoint,scale:anchor.scale)
        let sourceArea=planted.union(planted.offsetBy(dx:0,dy:hopOffset*anchor.scale))
        guard anchor.sourceDisplay.contains(sourceArea),
              !Geometry.blockers(on:sourceHost,surfaces:engine.world.surfaces).contains(where:{
                  let cut=$0.rect.intersection(sourceArea)
                  return !cut.isNull && !cut.isEmpty
              }) else {return .failed(.targetInvalid)}
        return nil
    }

    private func targetIsClear(_ destination:LandingReservation,display:CGRect,in engine:BehaviorEngine) -> Bool {
        guard let host=destination.host(in:engine),let point=destination.point(in:engine),let anchor else {return false}
        // Use the same inflated footprints as normal destination planning,
        // including birds already flying toward another host and foreign slots.
        let occupied=engine.birds.compactMap {other -> CGRect? in
            guard engine.id(of:other) != id,!other.isDeparting,
                  let host=engine.world.surfaces.first(where:{$0.id==other.hostID}) else {return nil}
            let scale=engine.spriteScale(for:other)
            let foot=Geometry.foot(on:host,fraction:other.fraction,edge:other.edge,scale:scale)
            return Geometry.landingFootprint(at:foot,scale:scale).insetBy(dx:-8,dy:-8)
        }+engine.runtime.landingReservations.filter{$0.bird != id}.compactMap{$0.footprint(in:engine)}
        return Geometry.landingRanges(on:host,surfaces:engine.world.surfaces,screen:display,
            scale:anchor.scale,occupied:occupied).contains{$0.contains(point.x)}
    }

    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        if let invalid=validate(in:engine) {return invalid}
        guard let bird=engine.bird(id),let destination=landingReservations.first,
              let host=destination.host(in:engine),let point=destination.point(in:engine) else {return .failed(.targetInvalid)}
        if abs(point.x-bird.position.x)>1 {facingRight=point.x>bird.position.x}
        age+=dt
        guard age+1e-9>=Self.duration else {return nil}
        // Host movement can invalidate plan.point without invalidating its
        // relative slot. Rebuild immediately before apply; fly reads the actual
        // current source position. The engine's ordinary Bird.tick runs once.
        let current=DestinationPlan(point:point,host:host,fraction:destination.fraction,edge:.top,
            duration:plan.duration,arc:plan.arc,airspace:plan.airspace,urgent:plan.urgent)
        current.apply(to:bird,random:engine.random)
        return .completed
    }

    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        // Runtime detaches the pose and reservation. Never restore coordinates,
        // replace a newer flight, reset dwell time or launch from cancellation.
    }

    func presentation(for birdID:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard birdID==id,let anchor,let bird=engine.bird(id),bird.motionRevision==anchor.revision,
              bird.state == .perched,!bird.isDeparting else {return nil}
        let clip=SpeciesBehaviorProfile.profile(for:bird.profile.id).poseClip(for:kind,duration:Self.duration)
        let frame=clip.flatMap { $0.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) ? $0.sample(at:age)?.name:nil }
        return BirdPose(frameName:frame ?? (age+1e-9>=Self.wingsOpenAt ? "fly0":"stand"),hopOffset:hopOffset,facingRight:facingRight)
    }

    private var hopOffset:CGFloat {
        guard let anchor else {return 0}
        let t=min(1,max(0,age/0.15)),blend=t*t*(3-2*t)
        return anchor.initialHop*CGFloat(1-blend)
    }
}
