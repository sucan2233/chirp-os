import Foundation
import CoreGraphics

public enum FixedPerchVisitBehavior {
    public static let supportedSpecies:Set<SpeciesID> = Set(SpeciesBehaviorProfile.species(for:.fixedPerchVisit))
}

/// The branch uses world scale; the visiting bird uses its live profile scale.
/// Keep these separate so a catalog size change cannot silently shrink margins.
enum FixedPerchVisitGeometry {
    static func landingClearance(perch:ResolvedFixedPerch,spriteScale:CGFloat) -> CGRect? {
        guard spriteScale.isFinite,spriteScale>0 else {return nil}
        let bird=Geometry.landingFootprint(at:perch.foot,scale:spriteScale)
            .insetBy(dx:-8*spriteScale,dy:-8*spriteScale)
        let area=bird.union(perch.rect)
        guard [area.minX,area.minY,area.maxX,area.maxY].allSatisfy(\.isFinite) else {return nil}
        return area
    }
    static func isSafe(perch:ResolvedFixedPerch,bird:Bird,in engine:BehaviorEngine) -> Bool {
        // Existing species retain their established journey policy. The new
        // bulbul additionally proves that its full, padded body and the branch
        // fit together in a work area using the actual relativeScale.
        guard bird.profile.id == .lightVentedBulbul else {return true}
        guard let area=landingClearance(perch:perch,spriteScale:engine.spriteScale(for:bird)),
              engine.world.displays.contains(where:{display in
                  guard display.contains(area) else {return false}
                  return engine.world.screens.isEmpty || engine.world.screens.contains {
                      let work=display.intersection($0)
                      return !work.isNull && !work.isEmpty && work.contains(area)
                  }
              }) else {return false}
        return !Geometry.blockers(on:perch.surface,surfaces:engine.world.surfaces).contains {
            let overlap=area.intersection($0.rect)
            return !overlap.isNull && !overlap.isEmpty
        }
    }
}

/// A frozen, single-bird journey. Only Bird.tick changes the foot anchor.
struct FixedPerchVisitPlan {
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.fixedPerchVisit).requiredFrames}
    let id:BirdID
    let perch:ResolvedFixedPerch
    let destination:LandingReservation
    let route:CoordinatedFlightRoute
    let scale:CGFloat
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]
    let worldScale:CGFloat
    let initialRevision:UInt64
    let originHost:Surface
    let originFraction:CGFloat
    private let envelope:FlightSceneEnvelope

    var duration:Double {route.duration}
    func pointerIsClear(in engine:BehaviorEngine,after age:Double=0) -> Bool {
        envelope.pointerIsClear(in:engine,after:age)
    }
    func isSafe(in engine:BehaviorEngine,after age:Double=0) -> Bool {
        guard engine.world.screens==screens,engine.world.displays==displays,engine.world.scale==worldScale,
              let bird=engine.bird(id),engine.spriteScale(for:bird)==scale,
              let current=engine.fixedPerchSnapshot().first(where:{$0.slot==perch.slot}),
              current.surface==perch.surface,current.foot==perch.foot,current.rect==perch.rect,
              FixedPerchVisitGeometry.isSafe(perch:current,bird:bird,in:engine),
              destination.host(in:engine)==perch.surface,destination.isValid(in:engine),
              destination.point(in:engine).map({Geometry.distance($0,perch.foot)<0.001}) == true
        else {return false}
        // The whole rail is one slot, even if two sprite rectangles would fit.
        guard !engine.birds.contains(where:{engine.id(of:$0) != id && $0.hostID==perch.surface.id}),
              !engine.runtime.landingReservations.contains(where:{
                  $0.bird != id && $0.hostID==perch.surface.id && $0.hostPID==perch.surface.pid
              }) else {return false}
        // The entire cubic footprint was bounded to this frozen display when
        // planned. Collision padding may extend below a valid ground takeoff;
        // retain that padding for obstacles without treating it as actual art.
        return envelope.isClear(in:engine,excluding:[id],display:nil,after:age)
    }
    func canBegin(in engine:BehaviorEngine) -> Bool {
        guard let bird=engine.bird(id),bird.motionRevision==initialRevision,
              bird.stateTime>=0.5,engine.role(of:bird) == .resident,
              bird.hostID==originHost.id,bird.hostPID==originHost.pid,bird.fraction==originFraction,engine.world.surfaces.contains(originHost),
              engine.hasUsablePerch(bird),
              Self.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? [])
        else {return false}
        return bird.canBeginCoordinatedFlight(route,on:perch.surface,fraction:0.5,spriteScale:scale,allowExpiredPerch:true)
    }

    static func candidates(in engine:BehaviorEngine,source:BehaviorSource = .automatic,target:BirdID?=nil) -> [Self] {
        guard !engine.paused,!engine.world.buttonsDown,!engine.ambientBusy,
              engine.world.scale.isFinite,engine.world.scale>0,
              BehaviorDefinitions.definition(for:.fixedPerchVisit).isEnabled(settings:engine.settings,source:source),
              source != .automatic || engine.settings.activityRhythm != .quiet else {return []}
        let birds=engine.birds.filter {bird in
            guard let id=engine.id(of:bird),target==nil || target==id,engine.role(of:bird) == .resident,
                  engine.runtime.owners[id]==nil,FixedPerchVisitBehavior.supportedSpecies.contains(bird.profile.id),
                  bird.state == .perched,bird.edge == .top,bird.stateTime>=0.5,!bird.isDeparting,
                  !bird.isSideHopping,!bird.isCoordinatedFlying,
                  bird.position.x.isFinite,bird.position.y.isFinite,
                  requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
                  engine.hasUsablePerch(bird),
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}),
                  Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,
                    edge:.top,scale:engine.spriteScale(for:bird)))<0.001 else {return false}
            if source == .automatic {
                guard let ecology=engine.perchPlanner.ecology(id),ecology.quietTime>=8,ecology.disturbance<0.35,
                      engine.perchPlanner.automaticWeight(id,kind:.fixedPerchVisit)>0 else {return false}
            }
            return true
        }.sorted{engine.id(of:$0)!<engine.id(of:$1)!}.prefix(8)
        let perches=engine.fixedPerchSnapshot().sorted{$0.slot<$1.slot}.prefix(3)
        var result:[Self]=[]
        for bird in birds {
            guard let id=engine.id(of:bird),let originHost=engine.world.surfaces.first(where:{$0.id==bird.hostID}) else {continue}
            let scale=engine.spriteScale(for:bird)
            guard scale.isFinite,scale>0 else {continue}
            for perch in perches where bird.hostID != perch.surface.id {
                guard FixedPerchVisitGeometry.isSafe(perch:perch,bird:bird,in:engine) else {continue}
                guard let display=engine.world.displays.first(where:{
                    $0.contains(Geometry.landingFootprint(at:bird.position,scale:scale)) &&
                    $0.contains(Geometry.landingFootprint(at:perch.foot,scale:scale))
                }) else {continue}
                guard let journey=HabitatJourney.make(from:bird.position,to:perch.foot,display:display,scale:scale,profile:bird.profile) else {continue}
                let route=journey.route,envelope=journey.envelope
                let plan=Self(id:id,perch:perch,destination:LandingReservation(bird:id,host:perch.surface,fraction:0.5),
                    route:route,scale:scale,display:display,screens:engine.world.screens,displays:engine.world.displays,
                    worldScale:engine.world.scale,initialRevision:bird.motionRevision,
                    originHost:originHost,originFraction:bird.fraction,envelope:envelope)
                if plan.isSafe(in:engine),plan.pointerIsClear(in:engine),plan.canBegin(in:engine) {result.append(plan)}
            }
        }
        return result
    }
}

final class FixedPerchVisitExecution:BehaviorExecution {
    enum Phase {case approach,landing,rest}
    static let restDuration=3.0
    let plan:FixedPerchVisitPlan
    let source:BehaviorSource
    let kind:BehaviorKind = .fixedPerchVisit
    let occupiesEncounter=false
    var participants:[BirdID] {[plan.id]}
    var landingReservations:[LandingReservation] {[plan.destination]}
    var timeout:Double {plan.duration+Self.restDuration+2}
    private(set) var phase:Phase = .approach
    private var revision:UInt64?
    private var age=0.0
    private(set) var restAge=0.0

    init(plan:FixedPerchVisitPlan,source:BehaviorSource) {self.plan=plan;self.source=source}
    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),plan.isSafe(in:engine),plan.pointerIsClear(in:engine),
              plan.canBegin(in:engine),bird.beginCoordinatedFlight(plan.route,on:plan.perch.surface,
                fraction:0.5,spriteScale:plan.scale,allowExpiredPerch:true) else {return}
        revision=bird.motionRevision
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard engine.settings.fixedPerchesEnabled else {return .cancelled(.settingsChanged)}
        guard !engine.world.interruptingButtonsDown else {return .cancelled(.userInput)}
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard FixedPerchVisitPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? [])
        else {return .failed(.missingFrames)}
        guard let revision,bird.motionRevision==revision,!bird.isDeparting,bird.edge == .top,
              bird.hostID==plan.perch.surface.id,bird.fraction==0.5,!bird.needsDestination,
              engine.role(of:bird) == .resident,bird.isCoordinatedFlying,
              let flightAge=bird.coordinatedFlightAge,abs(flightAge-min(age,plan.duration))<0.000001,
              Geometry.distance(bird.position,plan.route.position(at:age))<0.01,
              plan.isSafe(in:engine,after:age) else {return .failed(.targetInvalid)}
        guard plan.pointerIsClear(in:engine,after:age) else {return .cancelled(.pointerNearby)}
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        // Runtime runs before Bird.tick: measure rest from the observed, real
        // perched state, never from a guessed flight or landing deadline.
        if bird.state == .perched {
            if phase != .rest {phase = .rest;restAge=0}
            else {restAge+=dt}
            if restAge+1e-10>=Self.restDuration {
                bird.finishCoordinatedFlight();return .completed
            }
        } else if bird.state == .landing {phase = .landing}
        age+=dt
        return nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard let revision,let bird=engine.bird(plan.id),bird.motionRevision==revision,!bird.isDeparting else {return}
        if bird.state == .perched,plan.isSafe(in:engine,after:age),
           plan.destination.point(in:engine).map({Geometry.distance($0,bird.position)<0.001}) == true {
            bird.finishCoordinatedFlight()
        } else {bird.requestFlightRecovery()}
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard id==plan.id,let bird=engine.bird(id),bird.motionRevision==revision,bird.state == .perched else {return nil}
        return BirdPose(frameName:"stand",hopOffset:0)
    }
}
