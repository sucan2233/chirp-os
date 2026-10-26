import Foundation
import CoreGraphics

/// An ordered pair is one candidate: the engine samples the pair and its roles
/// once. No flight, new bird, persistent pair or familiarity mutation is needed.
struct CourtshipDisplayPlan {
    static var requiredFrames:Set<String> {
        SpeciesBehaviorProfile.profile(for:.spottedDove).requiredFrames(for:.courtshipDisplay)
            .union(CourtshipGeometry.frameNames)
    }
    let initiator:BirdID
    let observer:BirdID
    let source:BehaviorSource
    let host:Surface
    let scale:CGFloat
    let originalFractions:[CGFloat]
    let originalPositions:[CGPoint]
    let initialRevisions:[UInt64]
    let reservation:LandingReservation
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]
    let displayIDs:[String]
    let worldScale:CGFloat
    let initiatorClip:PoseClip
    let observerClip:PoseClip

    var participants:[BirdID] {[initiator,observer]}
    var duration:Double {CourtshipGeometry.duration}
    func role(for id:BirdID) -> CourtshipRole? {
        id==initiator ? .initiator:id==observer ? .observer:nil
    }
    func clip(for id:BirdID) -> PoseClip? {
        id==initiator ? initiatorClip:id==observer ? observerClip:nil
    }
    func facingRight(for id:BirdID) -> Bool? {
        guard let index=participants.firstIndex(of:id) else {return nil}
        return originalPositions[index].x<originalPositions[1-index].x
    }
    func sweptFootprint(in engine:BehaviorEngine) -> CGRect? {
        guard reservation.host(in:engine)==host else {return nil}
        return reservation.footprint(in:engine)
    }
    func pointerIsClear(in engine:BehaviorEngine) -> Bool {
        CourtshipGeometry.pointerIsClear(engine.world.pointer,feet:originalPositions,
            birdScale:scale,worldScale:worldScale)
    }
    /// Frozen identity/feet reject host movement before generic host tracking.
    /// Quiet time and cooldowns are intentionally absent: Runtime resets them
    /// after selection, before calling execution.start.
    func canBegin(in engine:BehaviorEngine) -> Bool {
        guard !engine.paused,!engine.world.buttonsDown,
              BehaviorDefinitions.definition(for:.courtshipDisplay).isEnabled(settings:engine.settings,source:source),
              Self.speciesEnabled(in:engine),Self.clipsValid(initiatorClip,observerClip),
              participants.indices.allSatisfy({index in
                  guard let bird=engine.bird(participants[index]) else {return false}
                  return bird.motionRevision==initialRevisions[index] &&
                      bird.position==originalPositions[index] && bird.fraction==originalFractions[index] &&
                      Self.standing(bird,on:host,in:engine) &&
                      bird.perchDuration-bird.stateTime>duration+BehaviorEngine.step &&
                      abs(engine.baseHop(for:participants[index],bird:bird))<0.001 &&
                      Self.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? [])
              }),isSafe(in:engine),pointerIsClear(in:engine) else {return false}
        return true
    }
    private static func speciesEnabled(in engine:BehaviorEngine) -> Bool {
        SpeciesBehaviorProfile.profile(for:.spottedDove).allows(.courtshipDisplay) &&
            engine.settings.probabilities.participates(.spottedDove)
    }
    private static func clipsValid(_ a:PoseClip,_ b:PoseClip) -> Bool {
        let initiatorFrames=Set(a.frames.filter{$0.duration>0}.map(\.name))
        let observerFrames=Set(b.frames.filter{$0.duration>0}.map(\.name))
        return Set(["courtRaise","courtBow0","courtBow1","courtBowRecover"]).isSubset(of:initiatorFrames) &&
            observerFrames.contains("courtObserve") && [a,b].allSatisfy {
            abs($0.duration-CourtshipGeometry.duration)<1e-9 && $0.maximumLoops==1 &&
                $0.foot==PoseClip.footAnchor && Set($0.frames.map(\.name)).isSubset(of:Set(CourtshipGeometry.frameNames).union(["stand"]))
        }
    }
    private static func standing(_ bird:Bird,on host:Surface,in engine:BehaviorEngine) -> Bool {
        guard bird.profile.id == .spottedDove,engine.role(of:bird) == .resident,
              engine.birds.contains(where:{$0 === bird}),bird.state == .perched,bird.edge == .top,
              bird.stateTime>=0.5,!bird.isDeparting,!bird.needsDestination,
              !bird.isSideHopping,!bird.isCoordinatedFlying,bird.hostID==host.id,bird.hostPID==host.pid,
              host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0,
              bird.fraction.isFinite,(0...1).contains(bird.fraction),
              engine.world.surfaces.contains(host),engine.hasUsablePerch(bird) else {return false}
        return Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,
            scale:engine.spriteScale(for:bird)))<0.001
    }
    /// Protect the continuous span as well as each turned canvas. The span is
    /// one reservation, so its internal 12pt gap never self-conflicts with two
    /// separately padded landing slots.
    func isSafe(in engine:BehaviorEngine) -> Bool {
        guard worldScale.isFinite,worldScale>0,scale.isFinite,scale>0,
              engine.world.scale==worldScale,engine.world.screens==screens,
              engine.world.displays==displays,engine.world.displayIDs==displayIDs,
              engine.world.surfaces.contains(host),host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0,
              participants.indices.allSatisfy({index in
                  guard let bird=engine.bird(participants[index]) else {return false}
                  return engine.spriteScale(for:bird)==scale && bird.position==originalPositions[index] &&
                      bird.fraction==originalFractions[index] && bird.hostID==host.id && bird.hostPID==host.pid
              }),CourtshipGeometry.hasClearance(originalPositions[0],originalPositions[1],scale:scale),
              reservation.isValid(in:engine),let area=sweptFootprint(in:engine) else {return false}
        let bodies=originalPositions.map{CourtshipGeometry.turningBounds(foot:$0,scale:scale)}
        // A ground bird's tail may extend past visibleFrame while remaining
        // inside the physical display. Neither the work area nor external
        // safety padding may become an additional screen-bottom inset.
        let bodySpan=bodies[0].union(bodies[1])
        guard display.contains(bodySpan),
              host.isGround || screens.isEmpty || screens.contains(where:{$0.contains(bodySpan)}),
              !Geometry.blockers(on:host,surfaces:engine.world.surfaces).contains(where:{area.intersects($0.rect)}),
              !engine.giftObstacleRects(excluding:participants).contains(where:{area.intersects($0)}) else {return false}
        let ids=Set(participants)
        for bird in engine.birds where engine.id(of:bird).map({!ids.contains($0)}) ?? true {
            let size=engine.spriteScale(for:bird)
            guard size.isFinite,size>0 else {return false}
            let body=Geometry.landingFootprint(at:bird.position,scale:size).union(engine.bounds(of:bird))
            if area.intersects(body.insetBy(dx:-8,dy:-8)) {return false}
            if bird.state == .flying {
                guard let flight=bird.plannedFlightFootprint(scale:size),
                      !area.intersects(flight.insetBy(dx:-8,dy:-8)) else {return false}
            }
            if let target=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}) {
                let foot=Geometry.foot(on:target,fraction:bird.fraction,edge:bird.edge,scale:size)
                if area.intersects(Geometry.landingFootprint(at:foot,scale:size).insetBy(dx:-8,dy:-8)) {return false}
            }
        }
        for slot in engine.runtime.landingReservations where !ids.contains(slot.bird) {
            guard let other=slot.footprint(in:engine),!area.intersects(other) else {return false}
        }
        for run in engine.runtime.runs.values {
            guard let traversal=run.execution as? LedgeTraversalExecution,
                  Set(traversal.participants).isDisjoint(with:ids) else {continue}
            guard let other=traversal.sweptFootprint(in:engine),!area.intersects(other) else {return false}
        }
        return true
    }
    static func candidates(in engine:BehaviorEngine,source:BehaviorSource = .automatic) -> [Self] {
        guard !engine.paused,!engine.world.buttonsDown,!engine.ambientBusy,
              engine.world.scale.isFinite,engine.world.scale>0,
              BehaviorDefinitions.definition(for:.courtshipDisplay).isEnabled(settings:engine.settings,source:source),
              speciesEnabled(in:engine),source != .automatic || engine.ambientEnabled,
              let initiatorClip=PoseClip.courtship(species:.spottedDove,role:.initiator),
              let observerClip=PoseClip.courtship(species:.spottedDove,role:.observer),
              clipsValid(initiatorClip,observerClip) else {return []}
        let ids=engine.birds.compactMap {bird -> BirdID? in
            guard let id=engine.id(of:bird),engine.runtime.owners[id]==nil,
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  standing(bird,on:host,in:engine),abs(engine.baseHop(for:id,bird:bird))<0.001,
                  bird.perchDuration-bird.stateTime>CourtshipGeometry.duration+BehaviorEngine.step,
                  requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
                  let ecology=engine.perchPlanner.ecology(id),ecology.quietTime+1e-9>=CourtshipGeometry.quietDuration,
                  ecology.disturbance<0.35 else {return nil}
            return source != .automatic || engine.perchPlanner.automaticWeight(id,kind:.courtshipDisplay)>0 ? id:nil
        }.sorted()
        var plans:[Self]=[]
        for (offset,first) in ids.enumerated() {
            for second in ids.dropFirst(offset+1) {
                guard let a=engine.bird(first),let b=engine.bird(second),
                      a.hostID==b.hostID,a.hostPID==b.hostPID,
                      let host=engine.world.surfaces.first(where:{$0.id==a.hostID && $0.pid==a.hostPID}) else {continue}
                let scale=engine.spriteScale(for:a)
                guard scale==engine.spriteScale(for:b),
                      CourtshipGeometry.hasClearance(a.position,b.position,scale:scale) else {continue}
                let bodySpan=CourtshipGeometry.turningBounds(foot:a.position,scale:scale)
                    .union(CourtshipGeometry.turningBounds(foot:b.position,scale:scale))
                guard let display=engine.world.displays.first(where:{$0.contains(bodySpan)}) else {continue}
                let span=min(a.fraction,b.fraction)...max(a.fraction,b.fraction)
                // Both roles have the same scale, required frames, feet and
                // span. Only the reservation owner and sampled clip change.
                // Reuse this call-local result; start still fully revalidates
                // the selected plan against the live world and its leases.
                var pairCanBegin:Bool?
                for (initiator,observer) in [(first,second),(second,first)] {
                    guard let one=engine.bird(initiator),let two=engine.bird(observer) else {continue}
                    let plan=Self(initiator:initiator,observer:observer,source:source,host:host,scale:scale,
                        originalFractions:[one.fraction,two.fraction],originalPositions:[one.position,two.position],
                        initialRevisions:[one.motionRevision,two.motionRevision],
                        reservation:LandingReservation(bird:initiator,host:host,fraction:one.fraction,span:span),
                        display:display,screens:engine.world.screens,displays:engine.world.displays,
                        displayIDs:engine.world.displayIDs,worldScale:engine.world.scale,
                        initiatorClip:initiatorClip,observerClip:observerClip)
                    let accepted:Bool
                    if let cached=pairCanBegin {accepted=cached}
                    else {accepted=plan.canBegin(in:engine);pairCanBegin=accepted}
                    if accepted {plans.append(plan)}
                }
            }
        }
        return plans.sorted{$0.initiator==$1.initiator ? $0.observer<$1.observer:$0.initiator<$1.initiator}
    }
}

/// Presentation only. Bird.tick keeps the real standing state and Runtime owns
/// both leases, one reservation and the sole terminal/journal event.
final class CourtshipDisplayExecution:LedgeTraversalExecution {
    let plan:CourtshipDisplayPlan
    let kind:BehaviorKind = .courtshipDisplay
    let occupiesEncounter=true
    var participants:[BirdID] {plan.participants}
    var landingReservations:[LandingReservation] {[plan.reservation]}
    var timeout:Double {CourtshipGeometry.timeout}
    private(set) var age=0.0
    private var runID:BehaviorRunID?
    private var started=false
    private var ended=false

    init(plan:CourtshipDisplayPlan) {self.plan=plan}
    func sweptFootprint(in engine:BehaviorEngine) -> CGRect? {plan.sweptFootprint(in:engine)}
    func start(in engine:BehaviorEngine) {
        guard !started,!ended,plan.canBegin(in:engine),
              let run=engine.runtime.owners[plan.initiator],
              participants.allSatisfy({engine.runtime.owners[$0]==run}) else {return}
        runID=run;started=true
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard started,!ended,let runID else {return .failed(.targetInvalid)}
        // Switching to quiet stops new automatic opportunities; an accepted
        // display can finish. Feature/species disabling still cancels now.
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:.preview),
              engine.settings.probabilities.participates(.spottedDove)
        else {return .cancelled(.settingsChanged)}
        guard !engine.world.interruptingButtonsDown else {return .cancelled(.userInput)}
        for (index,id) in participants.enumerated() {
            guard let bird=engine.bird(id),engine.birds.contains(where:{$0 === bird}) else {return .failed(.missingBird)}
            guard CourtshipDisplayPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? [])
            else {return .failed(.missingFrames)}
            guard engine.runtime.owners[id]==runID,bird.motionRevision==plan.initialRevisions[index],
                  bird.profile.id == .spottedDove,engine.role(of:bird) == .resident,
                  bird.state == .perched,bird.edge == .top,!bird.isDeparting,!bird.needsDestination,
                  !bird.isSideHopping,!bird.isCoordinatedFlying,
                  bird.position==plan.originalPositions[index],bird.fraction==plan.originalFractions[index]
            else {return .failed(.targetInvalid)}
        }
        guard plan.isSafe(in:engine) else {return .failed(.targetInvalid)}
        return plan.pointerIsClear(in:engine) ? nil:.cancelled(.pointerNearby)
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard started,!ended,dt.isFinite,dt>=0 else {return .failed(.targetInvalid)}
        guard !engine.paused else {return nil}
        age+=dt
        if age+1e-9>=plan.duration {ended=true;return .completed}
        return nil
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard started,!ended,let runID,let index=participants.firstIndex(of:id),let bird=engine.bird(id),
              engine.runtime.owners[id]==runID,bird.motionRevision==plan.initialRevisions[index],
              bird.state == .perched,!bird.isDeparting,let clip=plan.clip(for:id),
              let frame=clip.sample(at:age),let facing=plan.facingRight(for:id) else {return nil}
        return BirdPose(frameName:frame.name,hopOffset:0,facingRight:facing)
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard !ended else {return}
        ended=true
        // Runtime detaches both participants first. Never restore a prior pose
        // or replace a new owner/revision installed by a click or relocation.
        for (index,id) in participants.enumerated() {
            guard let bird=engine.bird(id),engine.runtime.owners[id]==nil,
                  bird.motionRevision==plan.initialRevisions[index],!bird.isDeparting else {continue}
            if bird.state == .perched,bird.edge == .top,!bird.needsDestination,
               !bird.isSideHopping,!bird.isCoordinatedFlying,
               let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
               host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0,
               engine.hasUsablePerch(bird),Geometry.distance(bird.position,Geometry.foot(on:host,
                   fraction:bird.fraction,edge:.top,scale:engine.spriteScale(for:bird)))<0.001 {continue}
            engine.recoverFromCourtship(id)
        }
    }
}
