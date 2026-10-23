import Foundation
import CoreGraphics

public enum FoodTrayBehavior {
    /// A deliberately narrow virtual seed-food policy, separate from motion/art.
    public static let supportedSpecies:Set<SpeciesID> = [.treeSparrow,.spottedDove]
}
struct FoodTrayVisitPlan {
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.foodTrayVisit).requiredFrames}
    let id:BirdID
    let object:HabitatObject
    let origin:Surface
    let fraction:CGFloat
    let originFoot:CGPoint
    let scale:CGFloat
    let initialRevision:UInt64
    let approach:HabitatJourney
    let departure:HabitatJourney
    var destination:LandingReservation {LandingReservation(bird:id,host:object.surface,fraction:0.5)}
    var home:LandingReservation {LandingReservation(bird:id,host:origin,fraction:fraction)}

    func geometryValid(in engine:BehaviorEngine)->Bool {
        guard let current=engine.habitatObjects.objects[object.id],current.surface==object.surface,
              engine.world.scale==object.scale,engine.world.screens==object.screens,engine.world.displays==object.displays,
              engine.world.surfaces.contains(origin),engine.world.surfaces.contains(object.surface),
              let bird=engine.bird(id),engine.spriteScale(for:bird)==scale,
              home.isValid(in:engine),destination.isValid(in:engine),
              !engine.birds.contains(where:{engine.id(of:$0) != id && $0.hostID==object.surface.id}) else {return false}
        return true
    }
    static func candidates(in engine:BehaviorEngine,source:BehaviorSource,target:BirdID?=nil)->[Self] {
        guard !engine.paused,!engine.world.buttonsDown,!engine.ambientBusy,
              BehaviorDefinitions.definition(for:.foodTrayVisit).isEnabled(settings:engine.settings,source:source),
              let object=engine.habitatObjects.objects.values.sorted(by:{$0.id<$1.id}).first,
              !object.retiring,!engine.runtime.habitatReservations.contains(object.id) else {return []}
        var result:[Self]=[]
        let candidates=engine.birds.filter {bird in
            guard let id=engine.id(of:bird),target==nil || target==id,
                  engine.role(of:bird) == .resident,engine.runtime.owners[id]==nil,
                  FoodTrayBehavior.supportedSpecies.contains(bird.profile.id),bird.state == .perched,bird.edge == .top,
                  bird.stateTime>=0.5,!bird.isDeparting,!bird.isCoordinatedFlying,!bird.isSideHopping,
                  requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  !host.isHabitat,engine.hasUsablePerch(bird),
                  Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,scale:engine.spriteScale(for:bird)))<0.001 else {return false}
            if source == .automatic {
                guard let ecology=engine.perchPlanner.ecology(id),ecology.quietTime>=8,ecology.disturbance<0.35,
                      engine.perchPlanner.automaticWeight(id,kind:.foodTrayVisit)>0 else {return false}
            }
            return true
        }.sorted{engine.id(of:$0)!<engine.id(of:$1)!}.prefix(8)
        for bird in candidates {
            guard let id=engine.id(of:bird),let origin=engine.world.surfaces.first(where:{$0.id==bird.hostID}) else {continue}
            let scale=engine.spriteScale(for:bird)
            guard let approach=HabitatJourney.make(from:bird.position,to:object.foot,display:object.display,scale:scale,profile:bird.profile),
                  let departure=HabitatJourney.make(from:object.foot,to:bird.position,display:object.display,scale:scale,profile:bird.profile),
                  bird.canBeginCoordinatedFlight(approach.route,on:object.surface,fraction:0.5,spriteScale:scale,allowExpiredPerch:true)
            else {continue}
            let plan=Self(id:id,object:object,origin:origin,fraction:bird.fraction,originFoot:bird.position,
                scale:scale,initialRevision:bird.motionRevision,approach:approach,departure:departure)
            guard plan.geometryValid(in:engine),approach.safe(in:engine,bird:id),departure.safe(in:engine,bird:id),
                  approach.pointerClear(in:engine),departure.pointerClear(in:engine) else {continue}
            result.append(plan)
        }
        return result
    }
}

final class FoodTrayVisitExecution:BehaviorExecution {
    enum Phase {case observe,approach,feed,departure,settle}
    let kind:BehaviorKind = .foodTrayVisit
    let plan:FoodTrayVisitPlan
    var participants:[BirdID] {[plan.id]}
    var habitatReservations:[HabitatObjectID] {[plan.object.id]}
    var landingReservations:[LandingReservation] {[plan.destination,plan.home]}
    var timeout:Double {plan.approach.route.duration+plan.departure.route.duration+12}
    private(set) var phase:Phase = .observe
    private(set) var phaseAge=0.0
    private var flightAge=0.0
    private var revision:UInt64
    init(plan:FoodTrayVisitPlan) {self.plan=plan;revision=plan.initialRevision}
    func start(in engine:BehaviorEngine) {}
    func validate(in engine:BehaviorEngine)->BehaviorCompletion? {
        guard engine.settings.foodTrayEnabled else {return .cancelled(.settingsChanged)}
        guard !engine.world.buttonsDown else {return .cancelled(.userInput)}
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard FoodTrayVisitPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
        guard plan.geometryValid(in:engine),bird.motionRevision==revision,!bird.isDeparting,
              bird.edge == .top,engine.role(of:bird) == .resident else {return .failed(.targetInvalid)}
        let journey:HabitatJourney,age:Double
        switch phase {
        case .observe:
            guard bird.state == .perched,bird.hostID==plan.origin.id,bird.fraction==plan.fraction,
                  Geometry.distance(bird.position,plan.originFoot)<0.001,!bird.isCoordinatedFlying else {return .failed(.targetInvalid)}
            journey=plan.approach;age=0
        case .approach,.feed:
            journey=plan.approach;age=flightAge
            guard bird.hostID==plan.object.surface.id,bird.fraction==0.5 else {return .failed(.targetInvalid)}
        case .departure,.settle:
            journey=plan.departure;age=flightAge
            guard bird.hostID==plan.origin.id,bird.fraction==plan.fraction else {return .failed(.targetInvalid)}
        }
        if phase != .observe {
            guard bird.isCoordinatedFlying,
                  let currentAge=bird.coordinatedFlightAge,abs(currentAge-min(age,journey.route.duration))<0.000001,
                  Geometry.distance(bird.position,journey.route.position(at:age))<0.01 else {return .failed(.targetInvalid)}
        }
        guard journey.safe(in:engine,bird:plan.id,after:age) else {return .failed(.targetInvalid)}
        guard journey.pointerClear(in:engine,after:age) else {return .cancelled(.pointerNearby)}
        // Before departing we also preserve a usable return corridor. Once on
        // the return flight, space behind the bird is no longer reserved.
        if phase == .observe || phase == .approach || phase == .feed {
            guard plan.departure.safe(in:engine,bird:plan.id),plan.departure.pointerClear(in:engine) else {return .cancelled(.targetInvalid)}
        }
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine)->BehaviorCompletion? {
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        phaseAge+=dt
        switch phase {
        case .observe:
            if phaseAge+1e-10>=0.8 {
                guard bird.beginCoordinatedFlight(plan.approach.route,on:plan.object.surface,fraction:0.5,spriteScale:plan.scale,allowExpiredPerch:true) else {return .failed(.targetInvalid)}
                revision=bird.motionRevision;phase = .approach;phaseAge=0;flightAge=dt
            }
        case .approach:
            flightAge+=dt
            if bird.state == .perched {phase = .feed;phaseAge=0}
        case .feed:
            flightAge+=dt
            if phaseAge+1e-10>=3.6 {
                // Consume once on finishing the feeding clip, never on approach
                // or again during cancellation/cleanup callbacks.
                engine.habitatObjects.consume(plan.object.id)
                bird.finishCoordinatedFlight()
                guard bird.beginCoordinatedFlight(plan.departure.route,on:plan.origin,fraction:plan.fraction,spriteScale:plan.scale,allowExpiredPerch:true) else {return .failed(.targetInvalid)}
                revision=bird.motionRevision;phase = .departure;phaseAge=0;flightAge=dt
            }
        case .departure:
            flightAge+=dt
            if bird.state == .perched {phase = .settle;phaseAge=0}
        case .settle:
            flightAge+=dt
            if phaseAge+1e-10>=0.6 {bird.finishCoordinatedFlight();return .completed}
        }
        return nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),bird.motionRevision==revision,!bird.isDeparting else {return}
        if phase == .observe {return}
        if bird.state == .perched,bird.hostID==plan.origin.id,engine.world.surfaces.contains(plan.origin),
           plan.home.isValid(in:engine),Geometry.distance(bird.position,plan.originFoot)<0.001 {
            bird.finishCoordinatedFlight()
        } else {bird.requestFlightRecovery()}
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine)->BirdPose? {
        guard id==plan.id,let bird=engine.bird(id),bird.motionRevision==revision,bird.state == .perched else {return nil}
        switch phase {
        case .observe:return BirdPose(frameName:"feedLook",hopOffset:0,facingRight:plan.object.foot.x>=bird.position.x)
        case .feed:
            let cycle=phaseAge.truncatingRemainder(dividingBy:1.2)
            let frame=cycle<0.25 ? "feedLook":cycle<0.5 ? "feedDown0":cycle<0.72 ? "feedDown1":"feedLift"
            return BirdPose(frameName:frame,hopOffset:0,facingRight:true)
        default:return BirdPose(frameName:"stand",hopOffset:0)
        }
    }
}
