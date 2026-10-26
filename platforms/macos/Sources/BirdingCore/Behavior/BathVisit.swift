import Foundation
import CoreGraphics

public enum BathVisitBehavior {
    public static var supportedSpecies:Set<SpeciesID> {Set(SpeciesBehaviorProfile.species(for:.bathVisit))}
}

/// Both ordinary flight legs are frozen before taking any lease. No bath code
/// integrates motion or changes the basin surface to fit an individual bird.
struct BathVisitPlan {
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.bathVisit).requiredFrames}
    let id:BirdID
    let object:HabitatObject
    let origin:Surface
    let fraction:CGFloat
    let originFoot:CGPoint
    let scale:CGFloat
    let initialRevision:UInt64
    let approach:HabitatJourney
    let departure:HabitatJourney
    let clip:PoseClip
    let facingRight:Bool
    var destination:LandingReservation {LandingReservation(bird:id,host:object.surface,fraction:0.5)}
    var home:LandingReservation {LandingReservation(bird:id,host:origin,fraction:fraction)}
    // Two real landing transitions, settling, and fixed-step phase boundaries
    // have budget as well as the authored bath and shake clips.
    var maximumPlannedDuration:Double {approach.route.duration+departure.route.duration+clip.duration+0.8+1.5}

    func geometryValid(in engine:BehaviorEngine) -> Bool {
        guard let current=engine.habitatObjects.objects[object.id],current.kind == .bath,!current.retiring,
              current.surface==object.surface,current.rect==object.rect,current.foot==object.foot,
              engine.world.bathArtAvailable,engine.world.scale==object.scale,
              engine.world.screens==object.screens,engine.world.displays==object.displays,
              engine.world.surfaces.contains(origin),engine.world.surfaces.contains(object.surface),
              let bird=engine.bird(id),engine.spriteScale(for:bird)==scale,
              home.isValid(in:engine),destination.isValid(in:engine),
              let clearance=BathGeometry.clearance(foot:object.foot,worldScale:object.scale,spriteScale:scale),
              object.display.contains(clearance),engine.world.screens.contains(where:{$0.contains(clearance)}),
              !Geometry.blockers(on:object.surface,surfaces:engine.world.surfaces).contains(where:{$0.rect.intersects(clearance)}),
              !engine.birds.contains(where:{engine.id(of:$0) != id && $0.hostID==object.surface.id}),
              !engine.runtime.landingReservations.contains(where:{$0.bird != id && $0.hostID==object.surface.id})
        else {return false}
        let point=clip.frames.first(where:{$0.name=="bathTouch"})?.beak.world(
            foot:object.foot,scale:scale,facingRight:facingRight)
        return point.map{BathGeometry.containsContact($0,waterRect:BathGeometry.waterRect(in:object.rect,scale:object.scale))} == true
    }
    func canBegin(in engine:BehaviorEngine) -> Bool {
        guard let bird=engine.bird(id),bird.motionRevision==initialRevision,
              engine.role(of:bird) == .resident,engine.birds.contains(where:{$0 === bird}),
              bird.state == .perched,bird.stateTime>=1,bird.hostID==origin.id,bird.hostPID==origin.pid,
              abs(engine.baseHop(for:id,bird:bird))<0.001,
              bird.fraction==fraction,Geometry.distance(bird.position,originFoot)<0.001,
              Self.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
              geometryValid(in:engine) else {return false}
        return bird.canBeginCoordinatedFlight(approach.route,on:object.surface,fraction:0.5,
            spriteScale:scale,allowExpiredPerch:true)
    }
    static func candidates(in engine:BehaviorEngine,source:BehaviorSource,target:BirdID?=nil) -> [Self] {
        guard !engine.paused,!engine.world.buttonsDown,!engine.ambientBusy,
              engine.settings.bathEnabled,engine.world.bathArtAvailable,
              BehaviorDefinitions.definition(for:.bathVisit).isEnabled(settings:engine.settings,source:source),
              source != .automatic || (engine.ambientEnabled && engine.settings.activityRhythm != .quiet)
        else {return []}
        let objects=engine.habitatObjects.objects.values.filter {
            $0.kind == .bath && !$0.retiring && !engine.runtime.habitatReservations.contains($0.id)
        }.sorted{$0.id<$1.id}
        let birds=engine.birds.filter {bird in
            guard let id=engine.id(of:bird),target==nil || target==id,
                  engine.role(of:bird) == .resident,engine.runtime.owners[id]==nil,
                  BathVisitBehavior.supportedSpecies.contains(bird.profile.id),bird.state == .perched,
                  bird.edge == .top,bird.stateTime>=1,!bird.isDeparting,!bird.isSideHopping,!bird.isCoordinatedFlying,
                  abs(engine.baseHop(for:id,bird:bird))<0.001,
                  let ecology=engine.ecology(of:bird),ecology.quietTime>=8,ecology.disturbance<0.35,
                  requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  !host.isHabitat,engine.hasUsablePerch(bird),
                  Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,
                    scale:engine.spriteScale(for:bird)))<0.001 else {return false}
            if source == .automatic {
                guard engine.perchPlanner.automaticWeight(id,kind:.bathVisit)>0 else {return false}
            }
            return true
        }.sorted{engine.id(of:$0)!<engine.id(of:$1)!}.prefix(8)
        var result:[Self]=[]
        for bird in birds {
            guard let id=engine.id(of:bird),let origin=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  let clip=PoseClip.bath(species:bird.profile.id) else {continue}
            let scale=engine.spriteScale(for:bird)
            for object in objects {
                guard let approach=HabitatJourney.make(from:bird.position,to:object.foot,display:object.display,scale:scale,profile:bird.profile),
                      let departure=HabitatJourney.make(from:object.foot,to:bird.position,display:object.display,scale:scale,profile:bird.profile)
                else {continue}
                let plan=Self(id:id,object:object,origin:origin,fraction:bird.fraction,originFoot:bird.position,
                    scale:scale,initialRevision:bird.motionRevision,approach:approach,departure:departure,
                    clip:clip,facingRight:object.foot.x>=bird.position.x)
                guard plan.maximumPlannedDuration<=BathGeometry.visitTimeout,plan.canBegin(in:engine),
                      approach.safe(in:engine,bird:id),departure.safe(in:engine,bird:id),
                      approach.pointerClear(in:engine),departure.pointerClear(in:engine) else {continue}
                result.append(plan)
            }
        }
        return result
    }
}

final class BathVisitExecution:BehaviorExecution {
    enum Phase:String {case approach,observe,touch,lower,bathe,rise,shake,departure,settle}
    let kind:BehaviorKind = .bathVisit
    let occupiesEncounter=true
    let plan:BathVisitPlan
    let propIDs:[ScenePropID]
    var participants:[BirdID] {[plan.id]}
    var habitatReservations:[HabitatObjectID] {[plan.object.id]}
    var landingReservations:[LandingReservation] {[plan.destination,plan.home]}
    var timeout:Double {BathGeometry.visitTimeout}
    private(set) var phase:Phase = .approach
    private(set) var phaseAge=0.0
    private(set) var bathAge=0.0
    private var flightAge=0.0
    private var revision:UInt64?
    private var bathFinished=false
    private var committed=false
    var isImmersed:Bool {
        switch phase {
        case .observe,.touch,.lower,.bathe,.rise,.shake:return true
        case .approach,.departure,.settle:return false
        }
    }
    init(plan:BathVisitPlan,splashIDs:[ScenePropID]=[]) {
        self.plan=plan
        // The engine allocates globally unique IDs. A fixture without IDs has
        // no particles rather than borrowing a persistent prop's identity.
        propIDs=Array(splashIDs.prefix(BathGeometry.maximumSplashes))
    }
    func start(in engine:BehaviorEngine) {
        guard plan.canBegin(in:engine),let bird=engine.bird(plan.id),
              bird.beginCoordinatedFlight(plan.approach.route,on:plan.object.surface,
                fraction:0.5,spriteScale:plan.scale,allowExpiredPerch:true) else {return}
        revision=bird.motionRevision
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard engine.settings.bathEnabled else {return .cancelled(.settingsChanged)}
        guard !engine.world.interruptingButtonsDown else {return .cancelled(.userInput)}
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard BathVisitPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
              engine.world.bathArtAvailable else {return .failed(.missingFrames)}
        guard let revision,bird.motionRevision==revision,!bird.isDeparting,bird.edge == .top,
              engine.role(of:bird) == .resident,plan.geometryValid(in:engine),bird.isCoordinatedFlying
        else {return .failed(.targetInvalid)}
        let returning=phase == .departure || phase == .settle
        let journey=returning ? plan.departure:plan.approach
        let host=returning ? plan.origin:plan.object.surface
        let fraction=returning ? plan.fraction:0.5
        guard bird.hostID==host.id,bird.hostPID==host.pid,bird.fraction==fraction,
              let actualAge=bird.coordinatedFlightAge,abs(actualAge-min(flightAge,journey.route.duration))<0.000001,
              Geometry.distance(bird.position,journey.route.position(at:flightAge))<0.01,
              !isImmersed || bird.state == .perched,
              journey.safe(in:engine,bird:plan.id,after:flightAge) else {return .failed(.targetInvalid)}
        guard journey.pointerClear(in:engine,after:flightAge) else {return .cancelled(.pointerNearby)}
        if !returning {
            guard plan.departure.safe(in:engine,bird:plan.id),plan.departure.pointerClear(in:engine) else {return .failed(.targetInvalid)}
        }
        return nil
    }
    private func selectPhase() {
        let next:Phase
        switch plan.clip.sample(at:bathAge)?.name {
        case "bathInspect":next = .observe
        case "bathTouch":next = .touch
        case "bathLower":next = .lower
        case "bath0","bath1","bath2":next = .bathe
        case "bathRise":next = .rise
        default:next = .shake
        }
        if next != phase {phase=next;phaseAge=0}
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        phaseAge+=dt
        switch phase {
        case .approach:
            flightAge+=dt
            if bird.state == .perched {phase = .observe;phaseAge=0;bathAge=0}
        case .observe,.touch,.lower,.bathe,.rise:
            flightAge+=dt;bathAge+=dt
            selectPhase()
        case .shake:
            flightAge+=dt
            if phaseAge+1e-10>=0.8 {
                bathFinished=true
                bird.finishCoordinatedFlight()
                guard bird.beginCoordinatedFlight(plan.departure.route,on:plan.origin,
                    fraction:plan.fraction,spriteScale:plan.scale,allowExpiredPerch:true) else {return .failed(.targetInvalid)}
                revision=bird.motionRevision;phase = .departure;phaseAge=0;flightAge=dt
            }
        case .departure:
            flightAge+=dt
            if bird.state == .perched {phase = .settle;phaseAge=0}
        case .settle:
            flightAge+=dt
            if phaseAge+1e-10>=0.2 {
                guard bathFinished,bird.state == .perched,plan.home.isValid(in:engine),
                      Geometry.distance(bird.position,plan.originFoot)<0.001,
                      let runID=engine.runtime.owners[plan.id] else {return .failed(.targetInvalid)}
                // No validation boundary between the third-use commit and the
                // sole completed terminal. Emergency recovery never comes here.
                if !committed {
                    guard engine.habitatObjects.completeVisit(plan.object.id,runID:runID) else {return .failed(.targetInvalid)}
                    committed=true
                }
                bird.finishCoordinatedFlight();return .completed
            }
        }
        return nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),let revision,bird.motionRevision==revision,!bird.isDeparting else {return}
        // Click relocation and route() have already chosen their successor.
        // Do not install a departure before that caller takes its new lease.
        if reason == .replaced {bird.requestFlightRecovery();return}
        if bird.state == .perched,bird.hostID==plan.origin.id,bird.hostPID==plan.origin.pid,
           plan.home.isValid(in:engine),Geometry.distance(bird.position,plan.originFoot)<0.001 {
            bird.finishCoordinatedFlight()
        } else {
            engine.recoverFromHabitat(plan.id,excluding:plan.object.id,
                immediate:engine.paused || reason == .sleep || reason == .shutdown || reason == .screensChanged)
        }
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard id==plan.id,let bird=engine.bird(id),bird.motionRevision==revision,bird.state == .perched else {return nil}
        if isImmersed {
            let frame=phase == .shake ? "shake":(plan.clip.sample(at:bathAge)?.name ?? "bathRise")
            return BirdPose(frameName:frame,hopOffset:0,facingRight:plan.facingRight)
        }
        return BirdPose(frameName:"stand",hopOffset:0)
    }
    func propSnapshots(in engine:BehaviorEngine) -> [ScenePropRenderState] {
        guard isImmersed,let bird=engine.bird(plan.id),bird.motionRevision==revision,
              bird.state == .perched else {return []}
        let start=plan.clip.frames.prefix(while:{$0.name != "bath0"}).reduce(0){$0+$1.duration}
        // Two distinct particles in each wash cycle, each alive for at most .4s.
        // An expired identity is never revived in the following cycle.
        let elapsed=bathAge-start
        guard elapsed>=0,elapsed<2.4 else {return []}
        let water=BathGeometry.waterRect(in:plan.object.rect,scale:plan.object.scale)
        return propIDs.enumerated().compactMap {index,id in
            let birth=Double(index/2)*0.8+Double(index%2)*0.12
            let age=elapsed-birth
            guard age>=0,age<BathGeometry.splashLifetime else {return nil}
            let frame=BathGeometry.splashFrameNames[min(3,Int(age/0.1))]
            let x=water.minX+water.width*CGFloat(index+1)/CGFloat(propIDs.count+1)
            return ScenePropRenderState(id:id,kind:.waterSplash,
                position:CGPoint(x:x,y:plan.object.foot.y),size:24*plan.object.scale,
                rotation:0,opacity:max(0,1-age/BathGeometry.splashLifetime),
                blockers:Geometry.blockers(on:plan.object.surface,surfaces:engine.world.surfaces).map(\.rect),
                frameName:frame,anchor:CGPoint(x:0.5,y:22.0/24.0))
        }
    }
}
