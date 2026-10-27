import Foundation
import CoreGraphics

public enum LeafCarryBehavior {
    public static var supportedSpecies:Set<SpeciesID> {Set(SpeciesBehaviorProfile.species(for:.leafCarry))}
}

/// Routes reuse ordinary habitat takeoff/landing timing. A moving-host handoff
/// uses the measured incoming velocity, then the same Bird.tick integrator.
struct LeafCarryJourney {
    let route:CoordinatedFlightRoute
    let envelope:FlightSceneEnvelope
    static func make(from start:CGPoint,to end:CGPoint,display:CGRect,worldScale:CGFloat,
                     bird:Bird,birdScale:CGFloat,localFootprint:CGRect,velocity:CGPoint?=nil) -> Self? {
        let route:CoordinatedFlightRoute
        let speed=FlightBehavior.cruiseSpeed(bird.profile.id,multiplier:bird.profile.speed)
        let incoming=velocity.map{Double(Geometry.distance(.zero,$0))} ?? 0
        if let velocity,incoming>0.001 {
            let distance=Double(Geometry.distance(start,end))
            guard distance>1 else {return nil}
            let handle=min(distance/3,max(8*Double(worldScale),incoming*0.2))
            let first=CGPoint(x:start.x+velocity.x/incoming*handle,y:start.y+velocity.y/incoming*handle)
            let last=CGPoint(x:start.x+(end.x-start.x)*0.7,y:start.y+(end.y-start.y)*0.7)
            let points: [CGPoint] = (0...512).map { index in
                let t: CGFloat = CGFloat(index) / 512
                let s: CGFloat = 1 - t
                let w0 = s * s * s
                let w1 = 3 * s * s * t
                let w2 = 3 * s * t * t
                let w3 = t * t * t
                let x = start.x * w0 + first.x * w1 + last.x * w2 + end.x * w3
                let y = start.y * w0 + first.y * w1 + last.y * w2 + end.y * w3
                return CGPoint(x: x, y: y)
            }
            let path = FlightPath(points: points)
            // A short carry cannot pay for accelerating back to full species
            // cruise. Size the peak from the remaining path, keeping the actual
            // incoming speed fixed. If its ramps consume the path, shorten the
            // ramps together; never discard velocity to make admission pass.
            let natural=FlightTiming(distance:path.length,speed:speed)
            let cruise=max(incoming,natural.peakSpeed)
            let rampDistance=(incoming+cruise)*0.15/2+cruise*0.35/2
            let fit=min(1,path.length/max(0.000001,rampDistance))
            guard let timing=FlightTiming(distance:path.length,cruiseSpeed:cruise,
                initialSpeed:incoming,finalSpeed:0,rampIn:0.15*fit,rampOut:0.35*fit),
                  let candidate=CoordinatedFlightRoute(legs:[CoordinatedFlightLeg(path:path,timing:timing)]) else {return nil}
            route=candidate
        } else {
            guard let journey=HabitatJourney.make(from:start,to:end,display:display,scale:birdScale,profile:bird.profile) else {return nil}
            route=journey.route
        }
        for leg in route.legs {
            let bounds=leg.path.bounds
            let full=CGRect(x:bounds.minX+localFootprint.minX,y:bounds.minY+localFootprint.minY,
                            width:bounds.width+localFootprint.width,height:bounds.height+localFootprint.height)
            guard display.contains(full) else {return nil}
        }
        guard let envelope=FlightSceneEnvelope(routes:[route],offsets:[0],scales:[birdScale],
            maximumDuration:CarriedObjectGeometry.timeout,localFootprints:[localFootprint]) else {return nil}
        return Self(route:route,envelope:envelope)
    }
    func safe(in engine:BehaviorEngine,bird:BirdID,display:CGRect,after age:Double=0) -> Bool {
        // make() already bounded the full real carrier footprint. The speed
        // inflation is for obstacle sweeps, not an invented screen-edge margin.
        envelope.isClear(in:engine,excluding:[bird],display:nil,after:age) && envelope.pointerIsClear(in:engine,after:age)
    }
}

struct LeafCarryPlan {
    struct Endpoints {
        let pickup:SurfaceAnchor
        let destination:SurfaceAnchor
        let pickupFoot:CGPoint
        let destinationFoot:CGPoint
        let pickupReservation:LandingReservation
        let destinationReservation:LandingReservation
    }
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.leafCarry).requiredFrames}
    let id:BirdID
    let object:CarriedObject
    let origin:CGPoint
    let initialRevision:UInt64
    let source:SurfaceAnchor
    let placement:SurfaceAnchor
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]
    let displayIDs:[String]
    let birdScale:CGFloat
    let localFootprint:CGRect
    let pickupClip:PoseClip
    let placeClip:PoseClip
    let approach:LeafCarryJourney
    let carrying:LeafCarryJourney
    let initialEndpoints:Endpoints
    var objectID:ScenePropID {object.id}
    var facingRight:Bool {object.facingRight}
    var maximumPlannedDuration:Double {approach.route.duration+carrying.route.duration+pickupClip.duration+placeClip.duration+1.2}

    func endpoints(in engine:BehaviorEngine) -> Endpoints? {
        guard let bird=engine.bird(id),engine.spriteScale(for:bird)==birdScale,
              let start=source.point(in:engine.world),let end=placement.point(in:engine.world),
              let startHost=source.host(in:engine.world),let endHost=placement.host(in:engine.world) else {return nil}
        let distance=Geometry.distance(start,end)/object.worldScale
        guard distance>=80-0.000001,distance<=240+0.000001,
              (facingRight ? end.x>start.x:end.x<start.x) else {return nil}
        let a=CarriedObjectGeometry.pickupFoot(surface:start,worldScale:object.worldScale,birdScale:birdScale,facingRight:facingRight)
        let b=CarriedObjectGeometry.pickupFoot(surface:end,worldScale:object.worldScale,birdScale:birdScale,facingRight:facingRight)
        guard let pickup=SurfaceAnchor.at(a,on:startHost,scale:birdScale),
              let destination=SurfaceAnchor.at(b,on:endHost,scale:birdScale) else {return nil}
        let first=LandingReservation(bird:id,host:startHost,fraction:pickup.fraction,localFootprint:localFootprint)
        let last=LandingReservation(bird:id,host:endHost,fraction:destination.fraction,localFootprint:localFootprint)
        guard first.isValid(in:engine),last.isValid(in:engine),!first.conflicts(with:last,in:engine),
              [a,b].allSatisfy({display.contains(localFootprint.offsetBy(dx:$0.x,dy:$0.y))}),
              !engine.runtime.landingReservations.contains(where:{$0.bird != id &&
                (first.conflicts(with:$0,in:engine) || last.conflicts(with:$0,in:engine))}) else {return nil}
        for other in engine.birds where engine.id(of:other) != id {
            let body=engine.bounds(of:other)
            guard !(first.footprint(in:engine)?.intersects(body) ?? true),
                  !(last.footprint(in:engine)?.intersects(body) ?? true) else {return nil}
        }
        return Endpoints(pickup:pickup,destination:destination,pickupFoot:a,destinationFoot:b,
            pickupReservation:first,destinationReservation:last)
    }
    func worldValid(in engine:BehaviorEngine) -> Bool {
        engine.world.leafCarryArtAvailable && engine.world.scale==object.worldScale &&
        engine.world.screens==screens && engine.world.displays==displays && engine.world.displayIDs==displayIDs
    }
    func canBegin(in engine:BehaviorEngine) -> Bool {
        guard worldValid(in:engine),let leaf=engine.carriedObjects.objects[objectID],leaf.state == .available,
              leaf.reservedByRun==nil,leaf.remainingLifetime>0,leaf.surfaceAnchor==source,
              let bird=engine.bird(id),bird.motionRevision==initialRevision,bird.position==origin,
              bird.state == .perched,bird.stateTime>=1,!bird.isDeparting,
              abs(engine.baseHop(for:id,bird:bird))<0.001,
              let slots=endpoints(in:engine),let host=slots.pickup.host(in:engine.world),
              Self.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return false}
        return bird.canBeginCoordinatedFlight(approach.route,on:host,fraction:slots.pickup.fraction,
            spriteScale:birdScale,allowExpiredPerch:true)
    }
    static func candidates(in engine:BehaviorEngine,source:BehaviorSource,target:BirdID?=nil) -> [Self] {
        guard !engine.paused,!engine.world.buttonsDown,!engine.ambientBusy,engine.settings.leafCarryEnabled,
              engine.world.leafCarryArtAvailable,
              BehaviorDefinitions.definition(for:.leafCarry).isEnabled(settings:engine.settings,source:source),
              source != .automatic || (engine.ambientEnabled && (engine.settings.companion != nil || engine.settings.activityRhythm != .quiet)) else {return []}
        let objects=engine.carriedObjects.objects.values.filter{$0.state == .available && (engine.sceneLeafCandidateID == nil || $0.id==engine.sceneLeafCandidateID) && $0.reservedByRun==nil && $0.remainingLifetime>0}.sorted{$0.id<$1.id}
        let birds=engine.birds.filter {bird in
            guard let id=engine.id(of:bird),target==nil || target==id,engine.role(of:bird) == .resident,
                  engine.runtime.owners[id]==nil,LeafCarryBehavior.supportedSpecies.contains(bird.profile.id),
                  bird.state == .perched,bird.edge == .top,bird.stateTime>=1,!bird.isDeparting,
                  !bird.isSideHopping,!bird.isCoordinatedFlying,abs(engine.baseHop(for:id,bird:bird))<0.001,
                  requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0,engine.hasUsablePerch(bird) else {return false}
            return source != .automatic || engine.perchPlanner.automaticWeight(id,kind:.leafCarry)>0
        }.sorted{engine.id(of:$0)!<engine.id(of:$1)!}.prefix(8)
        var result:[Self]=[]
        for bird in birds {
            guard let id=engine.id(of:bird),let pickup=PoseClip.leafCarryPickup(species:bird.profile.id),
                  let place=PoseClip.leafCarryPlace(species:bird.profile.id) else {continue}
            let scale=engine.spriteScale(for:bird)
            for object in objects {
                guard object.worldScale==engine.world.scale,let start=object.surfaceAnchor.point(in:engine.world),
                      let host=object.surfaceAnchor.host(in:engine.world),
                      let area=CarriedObjectGeometry.localFootprint(species:bird.profile.id,birdScale:scale,worldScale:object.worldScale),
                      let display=engine.world.displays.first(where:{$0.contains(area.offsetBy(dx:bird.position.x,dy:bird.position.y)) && $0.contains(start)}) else {continue}
                let foot=CarriedObjectGeometry.pickupFoot(surface:start,worldScale:object.worldScale,birdScale:scale,facingRight:object.facingRight)
                guard let approach=LeafCarryJourney.make(from:bird.position,to:foot,display:display,worldScale:object.worldScale,
                    bird:bird,birdScale:scale,localFootprint:area) else {continue}
                for distance in [CGFloat(120),160,200,240,80] {
                    let end=CGPoint(x:start.x+(object.facingRight ? distance:-distance)*object.worldScale,y:start.y)
                    guard let placement=SurfaceAnchor.at(end,on:host,scale:scale) else {continue}
                    let destination=CarriedObjectGeometry.pickupFoot(surface:end,worldScale:object.worldScale,birdScale:scale,facingRight:object.facingRight)
                    guard let carrying=LeafCarryJourney.make(from:foot,to:destination,display:display,worldScale:object.worldScale,
                        bird:bird,birdScale:scale,localFootprint:area),
                          let pickupAnchor=SurfaceAnchor.at(foot,on:host,scale:scale),
                          let destinationAnchor=SurfaceAnchor.at(destination,on:host,scale:scale) else {continue}
                    let slots=Endpoints(pickup:pickupAnchor,destination:destinationAnchor,pickupFoot:foot,destinationFoot:destination,
                        pickupReservation:LandingReservation(bird:id,host:host,fraction:pickupAnchor.fraction,localFootprint:area),
                        destinationReservation:LandingReservation(bird:id,host:host,fraction:destinationAnchor.fraction,localFootprint:area))
                    let plan=Self(id:id,object:object,origin:bird.position,initialRevision:bird.motionRevision,
                        source:object.surfaceAnchor,placement:placement,display:display,screens:engine.world.screens,
                        displays:engine.world.displays,displayIDs:engine.world.displayIDs,birdScale:scale,localFootprint:area,
                        pickupClip:pickup,placeClip:place,approach:approach,carrying:carrying,initialEndpoints:slots)
                    guard plan.maximumPlannedDuration<=CarriedObjectGeometry.timeout,plan.canBegin(in:engine),
                          approach.safe(in:engine,bird:id,display:display),carrying.safe(in:engine,bird:id,display:display) else {continue}
                    result.append(plan);break
                }
            }
        }
        return result
    }
}

final class LeafCarryExecution:BehaviorExecution {
    enum Phase:String {case approach,observe,lower,grip,lift,carry,place,recover}
    let kind:BehaviorKind = .leafCarry
    let occupiesEncounter=true
    let plan:LeafCarryPlan
    var participants:[BirdID] {[plan.id]}
    var propIDs:[ScenePropID] {[plan.objectID]}
    var plannedDuration:Double {plan.maximumPlannedDuration}
    var timeout:Double {CarriedObjectGeometry.timeout}
    var landingReservations:[LandingReservation] {
        guard let slots else {return []}
        return [slots.pickupReservation,slots.destinationReservation]
    }
    private(set) var phase:Phase = .approach
    private(set) var phaseAge=0.0
    private(set) var pickupAge=0.0
    private(set) var placeAge=0.0
    private(set) var pickedUp=false
    private(set) var placed=false
    private var age=0.0
    private var flightAge=0.0
    private var revision:UInt64?
    private var lease:BehaviorRunID?
    private var slots:LeafCarryPlan.Endpoints?
    private var activeJourney:LeafCarryJourney
    private var activeHost:Surface?
    private var activeFoot:CGPoint?
    private var sampledPickupHost:Surface?
    private var sampledDestinationHost:Surface?
    private var hostFailed=false
    /// Read-only guard evidence for failed reconciliation; no logging, RNG or
    /// separate timing. Retained on an execution even after runtime detaches it.
    private(set) var reconciliationFailure:String?
    private(set) var reconciliationFailurePhase:Phase?
    private func failHost(_ reason:String) {
        hostFailed=true;reconciliationFailure=reason;reconciliationFailurePhase=phase
    }

    init(plan:LeafCarryPlan) {
        self.plan=plan;activeJourney=plan.approach;slots=plan.initialEndpoints
    }
    func start(in engine:BehaviorEngine) {
        guard plan.canBegin(in:engine),let bird=engine.bird(plan.id),let run=engine.runtime.owners[plan.id],
              let endpoints=plan.endpoints(in:engine),let host=endpoints.pickup.host(in:engine.world),
              engine.carriedObjects.reserve(plan.objectID,run:run,bird:plan.id) else {hostFailed=true;return}
        lease=run;slots=endpoints
        guard bird.beginCoordinatedFlight(plan.approach.route,on:host,fraction:endpoints.pickup.fraction,
            spriteScale:plan.birdScale,allowExpiredPerch:true,tracksHost:true,localFootprint:plan.localFootprint)
        else {hostFailed=true;return}
        revision=bird.motionRevision;activeHost=host;activeFoot=endpoints.pickupFoot
        sampledPickupHost=host;sampledDestinationHost=endpoints.destination.host(in:engine.world)
    }
    private func at(_ point:CGPoint,bird:Bird) -> Bool {bird.state == .perched && Geometry.distance(bird.position,point)<0.001}
    private var isReturning:Bool {[Phase.carry,.place,.recover].contains(phase)}

    /// Checks the entire translation between old and new foot, including the
    /// token, before allowing a perched host-follow step in Bird.tick.
    private func staticClear(from start:CGPoint,to end:CGPoint,host:Surface,in engine:BehaviorEngine) -> Bool {
        let area=plan.localFootprint.offsetBy(dx:start.x,dy:start.y)
            .union(plan.localFootprint.offsetBy(dx:end.x,dy:end.y))
        guard plan.display.contains(area),
              !Geometry.blockers(on:host,surfaces:engine.world.surfaces).contains(where:{$0.rect.intersects(area)}),
              !engine.runtime.landingReservations.contains(where:{$0.bird != plan.id && ($0.footprint(in:engine)?.intersects(area) ?? true)}) else {return false}
        for bird in engine.birds where engine.id(of:bird) != plan.id {
            guard !engine.bounds(of:bird).intersects(area) else {return false}
            if bird.state == .flying {
                guard let path=bird.plannedFlightFootprint(scale:engine.spriteScale(for:bird)),!path.intersects(area) else {return false}
            }
        }
        let radius=max(100,72*plan.birdScale),p=engine.world.pointer
        guard p.x.isFinite,p.y.isFinite else {return false}
        return !CGRect(x:p.x-radius,y:p.y-radius,width:2*radius,height:2*radius).intersects(area)
    }
    /// The only world reconciliation entry. Engine calls this before generic
    /// updateHost. It changes neither feet nor run age, including while paused.
    func reconcileWorld(in engine:BehaviorEngine,sampleDT:Double?=nil) -> BehaviorCompletion? {
        synchronizeHosts(in:engine,sampleDT:sampleDT)
        return hostFailed ? .failed(.targetInvalid):nil
    }
    func synchronizeHosts(in engine:BehaviorEngine,sampleDT:Double?=nil) {
        guard !hostFailed else {return}
        guard plan.worldValid(in:engine),let bird=engine.bird(plan.id),let revision,
              bird.motionRevision==revision,!bird.isDeparting,bird.isCoordinatedFlying,
              let proposed=plan.endpoints(in:engine),let pickupHost=proposed.pickup.host(in:engine.world),
              let destinationHost=proposed.destination.host(in:engine.world) else {failHost("worldMotionOrEndpointsInvalid");return}
        if let old=sampledPickupHost,!SurfaceAnchor.acceptsChange(from:old,to:pickupHost,sampleDT:sampleDT) {failHost("pickupHostChangedAbruptly");return}
        if let old=sampledDestinationHost,!SurfaceAnchor.acceptsChange(from:old,to:destinationHost,sampleDT:sampleDT) {failHost("destinationHostChangedAbruptly");return}
        sampledPickupHost=pickupHost;sampledDestinationHost=destinationHost
        if engine.paused {slots=proposed;return}
        let target=isReturning ? proposed.destination:proposed.pickup
        let foot=isReturning ? proposed.destinationFoot:proposed.pickupFoot
        let host=isReturning ? destinationHost:pickupHost
        if host != activeHost || foot != activeFoot {
            if bird.state == .flying {
                guard let velocity=bird.coordinatedFlightVelocity,
                      let journey=LeafCarryJourney.make(from:bird.position,to:foot,display:plan.display,
                        worldScale:plan.object.worldScale,bird:bird,birdScale:plan.birdScale,
                        localFootprint:plan.localFootprint,velocity:velocity) else {failHost("replacementRouteUnavailable");return}
                guard age+journey.route.duration+(isReturning ? plan.placeClip.duration+0.6:plan.carrying.route.duration+plan.pickupClip.duration+plan.placeClip.duration+1.2)<=timeout
                else {failHost("replacementExceedsDeadline");return}
                guard journey.safe(in:engine,bird:plan.id,display:plan.display) else {failHost("replacementEnvelopeBlocked");return}
                guard bird.replanCoordinatedFlight(journey.route,on:host,fraction:target.fraction,
                    spriteScale:plan.birdScale,expectedRevision:revision,localFootprint:plan.localFootprint)
                else {failHost("replacementMotionHandoffRejected");return}
                activeJourney=journey;flightAge=0;self.revision=bird.motionRevision
            } else {
                guard staticClear(from:bird.position,to:foot,host:host,in:engine) else {failHost("perchedTranslationBlocked");return}
                guard bird.trackCoordinatedHost(host,fraction:target.fraction,spriteScale:plan.birdScale,expectedRevision:revision)
                else {failHost("perchedMotionHandoffRejected");return}
            }
            activeHost=host;activeFoot=foot
        }
        // No externally observable partial update: route/host/envelope are
        // installed only after the complete new pair of slots passes preflight.
        slots=proposed
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard engine.settings.leafCarryEnabled else {return .cancelled(.settingsChanged)}
        guard !engine.world.interruptingButtonsDown else {return .cancelled(.userInput)}
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard plan.worldValid(in:engine),LeafCarryPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
        guard !hostFailed,let revision,bird.motionRevision==revision,!bird.isDeparting,
              engine.role(of:bird) == .resident,bird.edge == .top,bird.isCoordinatedFlying,
              engine.spriteScale(for:bird)==plan.birdScale,let lease,engine.runtime.owners[plan.id]==lease,
              let object=engine.carriedObjects.objects[plan.objectID],object.reservedByRun==lease,
              object.state == (placed ? .placed:(pickedUp ? .attached:.available)),
              plan.endpoints(in:engine) != nil,let slots else {return .failed(.targetInvalid)}
        if engine.paused {return nil}
        let target=isReturning ? slots.destination:slots.pickup
        let point=isReturning ? slots.destinationFoot:slots.pickupFoot
        guard let host=target.host(in:engine.world),bird.hostID==host.id,bird.hostPID==host.pid,
              bird.fraction==target.fraction else {return .failed(.targetInvalid)}
        if bird.state == .flying {
            guard let actualAge=bird.coordinatedFlightAge,
                  abs(actualAge-min(flightAge,activeJourney.route.duration))<0.000001,
                  Geometry.distance(bird.position,activeJourney.route.position(at:actualAge))<0.001,
                  activeJourney.safe(in:engine,bird:plan.id,display:plan.display,after:actualAge) else {return .failed(.targetInvalid)}
        } else if !staticClear(from:bird.position,to:point,host:host,in:engine) {return .failed(.targetInvalid)}
        return nil
    }
    private func contactSnapshot(frame:String,in engine:BehaviorEngine) -> ScenePropRenderState? {
        guard let bird=engine.bird(plan.id) else {return nil}
        return CarriedObjectGeometry.attached(id:plan.objectID,bird:bird,
            pose:BirdPose(frameName:frame,hopOffset:0,facingRight:plan.facingRight),
            worldScale:plan.object.worldScale,birdScale:plan.birdScale,facingRight:plan.facingRight,
            blockers:bird.blockers(in:engine.world.surfaces))
    }
    private func beginCarry(in engine:BehaviorEngine,bird:Bird,slots:LeafCarryPlan.Endpoints) -> Bool {
        guard let host=slots.destination.host(in:engine.world),
              let journey=LeafCarryJourney.make(from:bird.position,to:slots.destinationFoot,display:plan.display,
                worldScale:plan.object.worldScale,bird:bird,birdScale:plan.birdScale,localFootprint:plan.localFootprint),
              age+journey.route.duration+plan.placeClip.duration+0.6<=timeout,
              journey.safe(in:engine,bird:plan.id,display:plan.display) else {return false}
        bird.finishCoordinatedFlight()
        guard bird.beginCoordinatedFlight(journey.route,on:host,fraction:slots.destination.fraction,
            spriteScale:plan.birdScale,allowExpiredPerch:true,tracksHost:true,localFootprint:plan.localFootprint) else {return false}
        revision=bird.motionRevision;activeJourney=journey;activeHost=host;activeFoot=slots.destinationFoot
        return true
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        age+=dt;phaseAge+=dt
        guard let bird=engine.bird(plan.id),let lease,let slots else {return .failed(.targetInvalid)}
        flightAge+=dt
        switch phase {
        case .approach:
            if at(slots.pickupFoot,bird:bird) {phase = .observe;phaseAge=0;pickupAge=0}
        case .observe,.lower,.grip,.lift:
            guard at(slots.pickupFoot,bird:bird) else {return nil}
            pickupAge+=dt
            let gripIndex=plan.pickupClip.frames.firstIndex(where:{$0.name=="carryGrip"}) ?? 2
            let gripStart=plan.pickupClip.frames.prefix(gripIndex).reduce(0){$0+$1.duration}
            let gripEnd=gripStart+plan.pickupClip.frames[gripIndex].duration
            if !pickedUp,pickupAge+1e-10>=gripStart {
                guard let contact=contactSnapshot(frame:"carryGrip",in:engine),
                      engine.carriedObjects.pickup(plan.objectID,run:lease,bird:plan.id,contact:contact) else {return .failed(.targetInvalid)}
                pickedUp=true
            }
            let next:Phase=pickupAge+1e-10<plan.pickupClip.frames[0].duration ? .observe:
                pickupAge+1e-10<gripStart ? .lower:pickupAge+1e-10<gripEnd ? .grip:.lift
            if next != phase {phase=next;phaseAge=0}
            if pickupAge+1e-10>=plan.pickupClip.duration {
                guard pickedUp,beginCarry(in:engine,bird:bird,slots:slots) else {return .failed(.targetInvalid)}
                phase = .carry;phaseAge=0;flightAge=dt
            }
        case .carry:
            if at(slots.destinationFoot,bird:bird) {phase = .place;phaseAge=0;placeAge=0}
        case .place,.recover:
            guard at(slots.destinationFoot,bird:bird) else {return nil}
            placeAge+=dt
            let commit=plan.placeClip.frames[0].duration
            if !placed,placeAge+1e-10>=commit {
                guard let contact=contactSnapshot(frame:"carryPlace",in:engine),
                      engine.carriedObjects.place(plan.objectID,run:lease,at:plan.placement,contact:contact,in:engine)
                else {return .failed(.targetInvalid)}
                placed=true;phase = .recover;phaseAge=0
            }
            if placeAge+1e-10>=plan.placeClip.duration {
                guard placed,bird.state == .perched else {return .failed(.targetInvalid)}
                engine.carriedObjects.releaseReservation(plan.objectID,run:lease)
                bird.finishCoordinatedFlight();return .completed
            }
        }
        return nil
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard id==plan.id,let bird=engine.bird(id),bird.motionRevision==revision else {return nil}
        let frame:String
        switch phase {
        case .approach,.carry:frame=bird.state == .perched ? "stand":bird.frameName
        case .observe,.lower,.grip,.lift:frame=plan.pickupClip.sample(at:pickupAge)?.name ?? "carryLook"
        case .place,.recover:frame=plan.placeClip.sample(at:placeAge)?.name ?? "carryLook"
        }
        return BirdPose(frameName:frame,hopOffset:0,facingRight:phase == .approach ? bird.facingRight:plan.facingRight)
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        let state=engine.carriedObjects.objects[plan.objectID]?.state
        if !placed,state != .placed {
            let frozen=presentation(for:plan.id,in:engine).flatMap {pose -> ScenePropRenderState? in
                guard let bird=engine.bird(plan.id) else {return nil}
                return CarriedObjectGeometry.attached(id:plan.objectID,bird:bird,pose:pose,
                    worldScale:plan.object.worldScale,birdScale:plan.birdScale,facingRight:plan.facingRight,
                    blockers:bird.blockers(in:engine.world.surfaces))
            }
            engine.carriedObjects.retire(plan.objectID,in:engine,
                immediate:reason == .sleep || reason == .shutdown ||
                    (engine.paused && [BehaviorReason.targetInvalid,.removed,.screensChanged,.spaceChanged,.settingsChanged,.missingBird,.missingFrames].contains(reason)),
                freezing:pickedUp ? frozen:nil)
            engine.scheduler.endFocus(matching:SceneFocus(leafID:plan.objectID),frequency:engine.settings.ambientFrequency)
        }
        if let lease {engine.carriedObjects.releaseReservation(plan.objectID,run:lease)}
        guard let bird=engine.bird(plan.id),let revision,bird.motionRevision==revision,!bird.isDeparting else {return}
        if reason == .replaced {bird.requestFlightRecovery();return}
        if bird.state == .perched,let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
           !host.isHabitat,Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,scale:plan.birdScale))<0.001 {
            bird.finishCoordinatedFlight()
        } else {engine.recoverFromCarriedObject(plan.id)}
    }
}
