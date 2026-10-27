import Foundation
import CoreGraphics

/// A single sally from a real ordinary perch. The insect and the entire return
/// are frozen before admission; neither actor is moved by the planner.
struct FlycatcherInsectCatchPlan {
    static var requiredFrames:Set<String> {
        SpeciesBehaviorProfile.profile(for:.yellowRumpedFlycatcher).requiredFrames(for:.insectCatch)
    }
    let id:BirdID
    let species:SpeciesID
    let source:BehaviorSource
    let originalHost:Surface
    let originalFoot:CGPoint
    let originalDestination:LandingReservation
    let initialRevision:UInt64
    let spriteScale:CGFloat
    let facingRight:Bool
    let route:CoordinatedFlightRoute
    let trajectory:InsectTrajectory
    let interceptionWindow:Range<Double>
    let nominalInterceptAge:Double
    fileprivate let envelope:FlightSceneEnvelope
    var originalReservation:LandingReservation {originalDestination}

    func canBegin(in engine:BehaviorEngine) -> Bool {
        guard let bird=engine.bird(id),bird.state == .perched,bird.edge == .top,
              bird.motionRevision==initialRevision,bird.facingRight==facingRight,
              bird.hostID==originalHost.id,bird.hostPID==originalHost.pid,
              Geometry.distance(bird.position,originalFoot)<0.001,
              abs(engine.baseHop(for:id,bird:bird))<0.001 else {return false}
        return bird.canBeginCoordinatedFlight(route,on:originalHost,fraction:originalDestination.fraction,
            spriteScale:spriteScale,allowExpiredPerch:true)
    }
    func isSafe(in engine:BehaviorEngine) -> Bool {
        originalDestination.host(in:engine)==originalHost && originalDestination.isValid(in:engine) &&
            envelope.isClear(in:engine,excluding:[id],display:nil) && envelope.pointerIsClear(in:engine)
    }
    /// Physical miss fixture seam, identical to the swallow's: only the insect
    /// trajectory changes. The real run, flight and resolver still execute.
    func replacingTrajectory(_ value:InsectTrajectory) -> Self? {
        guard value.worldScale==trajectory.worldScale,value.display==trajectory.display,
              value.screens==trajectory.screens,value.displays==trajectory.displays,
              value.displayIDs==trajectory.displayIDs else {return nil}
        return Self(id:id,species:species,source:source,originalHost:originalHost,originalFoot:originalFoot,
            originalDestination:originalDestination,initialRevision:initialRevision,spriteScale:spriteScale,
            facingRight:facingRight,route:route,trajectory:value,interceptionWindow:interceptionWindow,
            nominalInterceptAge:nominalInterceptAge,envelope:envelope)
    }
    static func candidates(in engine:BehaviorEngine,species:SpeciesID,source:BehaviorSource) -> [Self] {
        guard species == .yellowRumpedFlycatcher,!engine.paused,!engine.world.buttonsDown,
              source != .automatic || engine.ambientEnabled,
              engine.settings.probabilities.participates(species),
              BehaviorDefinitions.definition(for:.insectCatch).isEnabled(settings:engine.settings,source:source),
              engine.world.insectArtAvailable,engine.insects.current==nil,
              engine.world.scale.isFinite,engine.world.scale>0,
              PoseClip.insectCatchRecovery(species:species) != nil,
              requiredFrames.allSatisfy({PoseClip.catchBeakAnchor(species:species,frame:$0) != nil}) else {return []}
        let w=engine.world.scale
        var result:[Self]=[]
        let birds=engine.birds.filter{$0.profile.id==species}.sorted{(engine.id(of:$0) ?? BirdID(0))<(engine.id(of:$1) ?? BirdID(0))}
        for bird in birds.prefix(16) {
            guard let id=engine.id(of:bird),engine.role(of:bird) == .resident,engine.runtime.owners[id]==nil,
                  bird.state == .perched,bird.edge == .top,!bird.isDeparting,
                  !bird.isCoordinatedFlying,!bird.isSideHopping,!engine.pointerNear(bird),
                  abs(engine.baseHop(for:id,bird:bird))<0.001,
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0,
                  requiredFrames.isSubset(of:engine.world.availableFrames[species] ?? []),
                  source != .automatic || engine.perchPlanner.automaticWeight(id,kind:.insectCatch)>0 else {continue}
            let scale=engine.spriteScale(for:bird),slot=LandingReservation(bird:id,host:host,fraction:bird.fraction)
            let foot=Geometry.foot(on:host,fraction:bird.fraction,edge:.top,scale:scale)
            guard scale.isFinite,scale>0,slot.isValid(in:engine),Geometry.distance(foot,bird.position)<0.001,
                  let display=engine.world.displays.first(where:{$0.contains(Geometry.landingFootprint(at:foot,scale:scale))}),
                  let anchor=PoseClip.catchBeakAnchor(species:species,frame:"catchOpen") else {continue}
            let sign:CGFloat=bird.facingRight ? 1:-1
            for intercept in [1.6,2.2,2.8] {
                for radius:CGFloat in [120,180,100] {
                    for slope:CGFloat in [0.65,1.0,0.25] {
                        guard result.count<8 else {return result}
                        let length=Double(radius*w),norm=sqrt(1+slope*slope)
                        let direction=CGPoint(x:sign/norm,y:-slope/norm)
                        let end=CGPoint(x:foot.x+direction.x*length,y:foot.y+direction.y*length)
                        let duration=intercept+0.15,ramp=0.30,cruise=length/(duration-ramp/2)
                        let path=FlightPath(points:[foot,end])
                        guard let timing=FlightTiming(distance:length,cruiseSpeed:cruise,initialSpeed:0,
                            finalSpeed:cruise,rampIn:ramp,rampOut:0),timing.duration<=3,
                              let exit=InsectCatchJourney.leg(from:end,
                                velocity:CGPoint(x:direction.x*cruise,y:direction.y*cruise),to:foot,scale:scale,
                                preferredCruise:min(280*Double(w),FlightBehavior.cruiseSpeed(species,multiplier:bird.profile.speed))),
                              InsectCatchJourney.continuous(CoordinatedFlightLeg(path:path,timing:timing),exit),
                              let route=CoordinatedFlightRoute(legs:[CoordinatedFlightLeg(path:path,timing:timing),exit]),
                              route.duration+0.5<25,InsectCatchJourney.fits(route,scale:scale,display:display),
                              FlycatcherInsectJourney.withinSallyRadius(route,origin:foot,worldScale:w),
                              let envelope=FlightSceneEnvelope(routes:[route],offsets:[0],scales:[scale],maximumDuration:25)
                        else {continue}
                        let catchFoot=route.position(at:intercept),distance=Geometry.distance(foot,catchFoot)/w
                        guard distance>=80,distance<=220 else {continue}
                        let beak=anchor.world(foot:catchFoot,scale:scale,facingRight:bird.facingRight)
                        guard let target=FlycatcherInsectJourney.trajectory(beak:beak,intercept:intercept,
                            route:route,display:display,bird:bird,birdID:id,birdScale:scale,in:engine) else {continue}
                        let plan=Self(id:id,species:species,source:source,originalHost:host,originalFoot:foot,
                            originalDestination:slot,initialRevision:bird.motionRevision,spriteScale:scale,
                            facingRight:bird.facingRight,route:route,trajectory:target,
                            interceptionWindow:(intercept-0.2)..<timing.duration,
                            nominalInterceptAge:intercept,envelope:envelope)
                        if plan.canBegin(in:engine),plan.isSafe(in:engine) {result.append(plan)}
                    }
                }
            }
        }
        return result
    }
}

/// Bounded geometry queries only; all actual motion remains in Bird.tick.
private enum FlycatcherInsectJourney {
    static func withinSallyRadius(_ route:CoordinatedFlightRoute,origin:CGPoint,worldScale:CGFloat) -> Bool {
        // Every segment is inside its rectangle, and the disk is convex. Testing
        // its four corners bounds the whole outbound/return, not just rendezvous.
        route.legs.allSatisfy {leg in
            let b=leg.path.bounds
            return [CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.minX,y:b.maxY),
                    CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY)]
                .allSatisfy{Geometry.distance(origin,$0)<=220*worldScale}
        }
    }
    static func clip(from a:CGPoint,to b:CGPoint,rect:CGRect) -> ClosedRange<Double>? {
        var lo=0.0,hi=1.0
        for (p,d,mn,mx) in [(a.x,b.x-a.x,rect.minX,rect.maxX),(a.y,b.y-a.y,rect.minY,rect.maxY)] {
            if abs(d)<1e-12 {if p<mn || p>mx {return nil};continue}
            let x=Double((mn-p)/d),y=Double((mx-p)/d)
            lo=max(lo,min(x,y));hi=min(hi,max(x,y))
            if hi<lo {return nil}
        }
        return lo...hi
    }
    static func trajectory(beak:CGPoint,intercept:Double,route:CoordinatedFlightRoute,display:CGRect,
                           bird:Bird,birdID:BirdID,birdScale:CGFloat,in engine:BehaviorEngine) -> InsectTrajectory? {
        let w=engine.world.scale,half=InsectTrajectory.logicalSize*w/2,gap=w
        let whole=display.insetBy(dx:half,dy:half),sign:CGFloat=bird.facingRight ? 1:-1
        guard !whole.isEmpty,whole.contains(beak) else {return nil}
        var entries:[CGPoint]=[]
        for slope:CGFloat in [1.2,0.6] {
            entries += [display.minY-half-gap,display.maxY+half+gap].map {y in
                CGPoint(x:min(whole.maxX,max(whole.minX,beak.x+sign*max(64*w,abs(beak.y-y)*slope))),y:y)
            }.sorted{Geometry.distance($0,beak)<Geometry.distance($1,beak)}
        }
        entries.append(CGPoint(x:bird.facingRight ? display.maxX+half+gap:display.minX-half-gap,y:beak.y))
        for start in entries {
            guard (start.x-beak.x)*sign>0 else {continue}
            let velocity=CGPoint(x:(beak.x-start.x)/intercept,y:(beak.y-start.y)/intercept)
            let speed=Double(Geometry.distance(.zero,velocity))
            guard speed.isFinite,speed>0,speed<=InsectCatchPlan.maximumInsectSpeedPerScale*Double(w),
                  let full=clip(from:start,to:beak,rect:whole) else {continue}
            let fullyEntered=full.lowerBound*intercept
            guard intercept-0.2-fullyEntered>=InsectCatchPlan.minimumFullyVisibleLead else {continue}
            let outer=display.insetBy(dx:-half-gap,dy:-half-gap)
            var exit=Double.infinity
            if velocity.x>0 {exit=min(exit,Double((outer.maxX-beak.x)/velocity.x))}
            if velocity.x<0 {exit=min(exit,Double((outer.minX-beak.x)/velocity.x))}
            if velocity.y>0 {exit=min(exit,Double((outer.maxY-beak.y)/velocity.y))}
            if velocity.y<0 {exit=min(exit,Double((outer.minY-beak.y)/velocity.y))}
            let duration=intercept+exit+Double(gap)/speed
            guard exit.isFinite,exit>0,duration.isFinite,duration<=60 else {continue}
            let finish=CGPoint(x:start.x+velocity.x*duration,y:start.y+velocity.y*duration)
            guard let target=InsectTrajectory(waypoints:[.init(time:0,position:start),.init(time:duration,position:finish)],
                display:display,worldScale:w,screens:engine.world.screens,displays:engine.world.displays,displayIDs:engine.world.displayIDs),
                  avoidsBody(target,route:route,intercept:intercept,birdScale:birdScale,facingRight:bird.facingRight) else {continue}
            let a=target.position(at:fullyEntered),b=target.position(at:intercept)
            let sweep=CGRect(x:min(a.x,b.x)-half,y:min(a.y,b.y)-half,width:abs(a.x-b.x)+2*half,height:abs(a.y-b.y)+2*half)
            var obstacles=engine.world.surfaces.filter{!$0.isGround && $0.layer>0}.map(\.rect)
            for peer in engine.birds where engine.id(of:peer) != birdID {
                obstacles.append(engine.bounds(of:peer))
                if peer.state == .flying {
                    guard let full=peer.plannedFlightFootprint(scale:engine.spriteScale(for:peer)) else {return nil}
                    obstacles.append(full)
                }
            }
            if !obstacles.contains(where:{$0.intersects(sweep)}) {return target}
        }
        return nil
    }
    private static func avoidsBody(_ target:InsectTrajectory,route:CoordinatedFlightRoute,
                                   intercept:Double,birdScale:CGFloat,facingRight:Bool) -> Bool {
        guard let pose=CatchArtGeometry.pose(species:.yellowRumpedFlycatcher,frame:"catchOpen") else {return false}
        let first=route.legs[0],open=intercept-0.2,sign:CGFloat=facingRight ? 1:-1
        let start=target.waypoints[0],end=target.waypoints[1]
        let v=CGPoint(x:(end.position.x-start.position.x)/(end.time-start.time),y:(end.position.y-start.position.y)/(end.time-start.time))
        let d=CGPoint(x:(first.path.point(1).x-first.path.point(0).x)/first.path.length,
                      y:(first.path.point(1).y-first.path.point(0).y)/first.path.length)
        let cruise=first.timing.speed(at:intercept)
        let relative=CGPoint(x:v.x-d.x*cruise,y:v.y-d.y*cruise)
        let speed=Double(Geometry.distance(.zero,relative))
        guard speed>0 else {return false}
        let contact=max(open,intercept-Double(target.collisionRadius)/speed)
        func local(_ t:Double) -> CGPoint {
            let p=target.position(at:t),foot=route.position(at:t)
            return CGPoint(x:29+sign*(p.x-foot.x)/birdScale,y:39+(p.y-foot.y)/birdScale)
        }
        let bound=first.timing.peakSpeed+Double(Geometry.distance(.zero,v))
        for index in 0..<64 {
            let dt=open/64,mid=(Double(index)+0.5)*dt
            let margin=(target.collisionRadius+CGFloat(bound*dt/2))/birdScale
            if CGRect(x:0,y:0,width:48,height:48).insetBy(dx:-margin,dy:-margin).contains(local(mid)) {return false}
        }
        let head=[pose.headPoint(-pose.headWidth/2,-pose.headHeight/2),pose.headPoint(pose.headWidth/2,-pose.headHeight/2),
                  pose.headPoint(-pose.headWidth/2,pose.headHeight/2),pose.headPoint(pose.headWidth/2,pose.headHeight/2)]
        let front=([pose.body.maxX,pose.tail.x]+head.map(\.x)+pose.nearWing.map(\.x)+pose.farWing.map(\.x)).max()!
        let radius=target.collisionRadius/birdScale
        return clip(from:local(open),to:local(contact),rect:CGRect(x:0,y:0,width:front,height:48).insetBy(dx:-radius,dy:-radius))==nil
    }
    static func returnRoute(from start:CGPoint,velocity:CGPoint,to end:CGPoint,display:CGRect,
                            bird:Bird,scale:CGFloat,worldScale:CGFloat) -> CoordinatedFlightRoute? {
        if Geometry.distance(.zero,velocity)>0.001 {
            guard let leg=InsectCatchJourney.leg(from:start,velocity:velocity,to:end,scale:scale,
                preferredCruise:min(280*Double(worldScale),FlightBehavior.cruiseSpeed(bird.profile.id,multiplier:bird.profile.speed))),
                  let route=CoordinatedFlightRoute(legs:[leg]),InsectCatchJourney.fits(route,scale:scale,display:display) else {return nil}
            return route
        }
        // A sub-point host movement during landing still needs a continuous
        // handoff. HabitatJourney deliberately rejects distances <=1, so retain
        // the same native timing/sampler for this small, checked straight.
        let distance=Double(Geometry.distance(start,end))
        if distance>0.001,distance<=1 {
            let path=FlightPath(points:[start,end])
            guard let route=CoordinatedFlightRoute(legs:[CoordinatedFlightLeg(path:path,
                timing:FlightTiming(distance:path.length,speed:120*Double(worldScale)))]),
                  InsectCatchJourney.fits(route,scale:scale,display:display) else {return nil}
            return route
        }
        return HabitatJourney.make(from:start,to:end,display:display,scale:scale,profile:bird.profile)?.route
    }
}

final class FlycatcherInsectCatchExecution:InsectCatchMotionExecution {
    let plan:FlycatcherInsectCatchPlan
    let insectID:ScenePropID
    let kind:BehaviorKind = .insectCatch
    var source:BehaviorSource {plan.source}
    var participants:[BirdID] {[plan.id]}
    var propIDs:[ScenePropID] {[insectID]}
    func estimatedDuration(in engine:BehaviorEngine)->Double {
        guard let target=plan.originalDestination.point(in:engine) else {return .infinity}
        let end=plan.route.position(at:plan.route.duration)
        let previous=plan.route.position(at:max(0,plan.route.duration-0.01))
        let velocity=CGPoint(x:(end.x-previous.x)/0.01,y:(end.y-previous.y)/0.01)
        guard let leg=InsectCatchJourney.leg(from:end,velocity:velocity,to:target,scale:plan.spriteScale) else {return .infinity}
        return plan.route.duration+leg.timing.duration+(PoseClip.insectCatchRecovery(species:plan.species)?.duration ?? 0)+0.6
    }
    var timeout:Double {25}
    var landingReservations:[LandingReservation] {[reservation]}
    private var reservation:LandingReservation
    private var activeHost:Surface
    private var activeRoute:CoordinatedFlightRoute
    private var activeEnvelope:FlightSceneEnvelope
    private var routeStartedAt=0.0
    private var revision:UInt64?
    private var runID:BehaviorRunID?
    private var age=0.0
    private var resolvedAge=0.0
    private var attemptEnded=false
    private var interrupted=false
    private var recoveryStartedAt:Double?
    private var startFailed=false
    private(set) var captured=false
    private(set) var minimumBeakDistance:CGFloat?
    private struct MotionStart {let foot:CGPoint;let frame:String;let facing:Bool;let beak:CGPoint}
    private var motionStart:MotionStart?

    init(plan:FlycatcherInsectCatchPlan,insectID:ScenePropID) {
        self.plan=plan;self.insectID=insectID;reservation=plan.originalDestination
        activeHost=plan.originalHost;activeRoute=plan.route;activeEnvelope=plan.envelope
    }
    func start(in engine:BehaviorEngine) {
        guard engine.insects.current==nil,let bird=engine.bird(plan.id),let owner=engine.runtime.owners[plan.id],
              plan.canBegin(in:engine),plan.isSafe(in:engine),
              bird.beginCoordinatedFlight(plan.route,on:plan.originalHost,fraction:plan.originalDestination.fraction,
                spriteScale:plan.spriteScale,allowExpiredPerch:true,tracksHost:true) else {startFailed=true;return}
        revision=bird.motionRevision;runID=owner
        if !engine.insects.install(id:insectID,trajectory:plan.trajectory) {startFailed=true}
    }
    private func worldMatches(_ engine:BehaviorEngine) -> Bool {
        let t=plan.trajectory,w=engine.world
        return w.scale==t.worldScale && w.screens==t.screens && w.displays==t.displays && w.displayIDs==t.displayIDs
    }
    private func routeIsSafe(in engine:BehaviorEngine) -> Bool {
        guard reservation.isValid(in:engine),reservation.host(in:engine)==activeHost,
              let point=reservation.point(in:engine),Geometry.distance(point,activeRoute.position(at:activeRoute.duration))<0.001 else {return false}
        return activeEnvelope.isClear(in:engine,excluding:participants,display:nil,after:resolvedAge-routeStartedAt)
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard !startFailed else {return .failed(.targetInvalid)}
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:.preview),
              engine.settings.probabilities.participates(plan.species) else {return .cancelled(.settingsChanged)}
        guard engine.world.insectArtAvailable,
              FlycatcherInsectCatchPlan.requiredFrames.isSubset(of:engine.world.availableFrames[plan.species] ?? []),
              PoseClip.insectCatchRecovery(species:plan.species) != nil,
              FlycatcherInsectCatchPlan.requiredFrames.allSatisfy({PoseClip.catchBeakAnchor(species:plan.species,frame:$0) != nil}) else {return .failed(.missingFrames)}
        guard worldMatches(engine),engine.spriteScale(for:bird)==plan.spriteScale else {return .cancelled(.screensChanged)}
        guard let revision,bird.motionRevision==revision,!bird.isDeparting,bird.edge == .top,
              engine.role(of:bird) == .resident,let runID,engine.runtime.owners[plan.id]==runID,
              bird.isCoordinatedFlying,bird.hostID==activeHost.id,bird.hostPID==activeHost.pid,
              bird.fraction==reservation.fraction,routeIsSafe(in:engine),
              let t=bird.coordinatedFlightAge,abs(t-min(max(0,resolvedAge-routeStartedAt),activeRoute.duration))<1e-6,
              Geometry.distance(bird.position,activeRoute.position(at:t))<0.01 else {return .failed(.targetInvalid)}
        return nil
    }
    /// Called before host tracking, even while paused. Route installation is
    /// metadata-only and cannot reset the run/insect clock or create a capture.
    func reconcileWorld(in engine:BehaviorEngine,sampleDT:Double?=nil) -> BehaviorCompletion? {
        guard !startFailed,let bird=engine.bird(plan.id) else {return .failed(.targetInvalid)}
        guard worldMatches(engine),engine.spriteScale(for:bird)==plan.spriteScale else {return .cancelled(.screensChanged)}
        guard let revision,bird.motionRevision==revision,let runID,engine.runtime.owners[plan.id]==runID,
              bird.isCoordinatedFlying,!bird.isDeparting else {return .failed(.targetInvalid)}
        if routeIsSafe(in:engine) {return nil}
        if bird.state != .flying,let host=reservation.host(in:engine),host.id==activeHost.id,
           host.pid==activeHost.pid,reservation.isValid(in:engine),let point=reservation.point(in:engine),
           Geometry.distance(point,bird.position)<0.001,
           Geometry.distance(point,activeRoute.position(at:activeRoute.duration))<0.001,
           activeEnvelope.isClear(in:engine,excluding:participants,display:nil,after:resolvedAge-routeStartedAt),
           bird.trackCoordinatedHost(host,fraction:reservation.fraction,spriteScale:plan.spriteScale,expectedRevision:revision) {
            activeHost=host;return nil
        }
        return replanReturn(in:engine,bird:bird,revision:revision) ? nil:.failed(.targetInvalid)
    }
    private func replanReturn(in engine:BehaviorEngine,bird:Bird,revision:UInt64) -> Bool {
        let velocity=bird.coordinatedFlightVelocity ?? .zero
        var targets:[LandingReservation]=[]
        if let host=plan.originalDestination.host(in:engine),host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0 {
            targets.append(LandingReservation(bird:plan.id,host:host,fraction:plan.originalDestination.fraction))
        }
        if let host=reservation.host(in:engine),host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0 {
            targets.append(LandingReservation(bird:plan.id,host:host,fraction:reservation.fraction))
        }
        for host in engine.world.surfaces.filter({$0.canHostBirds && !$0.isHabitat && ($0.isGround || $0.layer==0)}).sorted(by:{$0.id<$1.id}).prefix(32) {
            for fraction:CGFloat in [0.5,0.25,0.75] {targets.append(LandingReservation(bird:plan.id,host:host,fraction:fraction))}
        }
        for slot in targets {
            guard slot.isValid(in:engine),let host=slot.host(in:engine),let point=slot.point(in:engine),
                  !engine.runtime.landingReservations.contains(where:{$0.bird != plan.id && slot.conflicts(with:$0,in:engine)}) else {continue}
            for display in engine.world.displays {
                guard let route=FlycatcherInsectJourney.returnRoute(from:bird.position,velocity:velocity,to:point,
                    display:display,bird:bird,scale:plan.spriteScale,worldScale:engine.world.scale),
                      age+route.duration+0.5<timeout,
                      let envelope=FlightSceneEnvelope(routes:[route],offsets:[0],scales:[plan.spriteScale],maximumDuration:25),
                      envelope.isClear(in:engine,excluding:participants,display:nil),
                      engine.runtime.owners[plan.id]==runID,
                      bird.replaceCoordinatedFlight(route,on:host,fraction:slot.fraction,
                        spriteScale:plan.spriteScale,expectedRevision:revision) else {continue}
                // All preflights precede this synchronous commit. Runtime reads
                // this updated reservation before its next validation pass.
                reservation=slot;activeHost=host;activeRoute=route;activeEnvelope=envelope
                routeStartedAt=resolvedAge;self.revision=bird.motionRevision
                interrupted=true;attemptEnded=true;recoveryStartedAt=recoveryStartedAt ?? age
                return true
            }
        }
        return false
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        if let bird=engine.bird(plan.id) {
            let pose=presentation(for:plan.id,in:engine),frame=pose?.frameName ?? bird.frameName
            let facing=pose?.facingRight ?? bird.facingRight
            if let anchor=PoseClip.catchBeakAnchor(species:plan.species,frame:frame) {
                motionStart=MotionStart(foot:bird.position,frame:frame,facing:facing,
                    beak:anchor.world(foot:bird.position,scale:plan.spriteScale,facingRight:facing))
            } else {motionStart=nil}
        }
        if dt.isFinite,dt>0 {age+=dt}
        return nil
    }
    func resolveMotion(_ step:InsectStep?,in engine:BehaviorEngine) -> InsectResolution {
        guard let bird=engine.bird(plan.id),let revision,bird.motionRevision==revision,
              let runID,engine.runtime.owners[plan.id]==runID else {return InsectResolution(completion:.failed(.targetInvalid))}
        let from=resolvedAge,to=age
        defer {resolvedAge=age}
        guard let motionStart,Geometry.distance(motionStart.foot,activeRoute.position(at:from-routeStartedAt))<0.01,
              let actual=bird.coordinatedFlightAge,abs(actual-min(max(0,to-routeStartedAt),activeRoute.duration))<1e-6,
              Geometry.distance(bird.position,activeRoute.position(at:actual))<0.01 else {
            return InsectResolution(completion:.failed(.targetInvalid))
        }
        var contact:InsectContact?
        if !attemptEnded,!interrupted {
            if plan.interceptionWindow.contains(from),
               let anchor=PoseClip.catchBeakAnchor(species:plan.species,frame:"catchOpen") {
                guard motionStart.frame=="catchOpen",motionStart.facing==plan.facingRight,
                      Geometry.distance(motionStart.beak,anchor.world(foot:plan.route.position(at:from),
                        scale:plan.spriteScale,facingRight:plan.facingRight))<1e-6 else {
                    return InsectResolution(completion:.failed(.targetInvalid))
                }
            }
            if let step,step.insectID==insectID,abs(step.startAge-from)<1e-6,
               let anchor=PoseClip.catchBeakAnchor(species:plan.species,frame:"catchOpen") {
                let result=InsectContactResolver.resolve(step,runID:runID,birdID:plan.id,
                    simulationStart:engine.time-(step.endAge-step.startAge),motionInterval:from...to,
                    openInterval:plan.interceptionWindow,beakAt:{t in
                        anchor.world(foot:self.plan.route.position(at:t),scale:self.plan.spriteScale,facingRight:self.plan.facingRight)
                    })
                if let distance=result.minimumDistance {minimumBeakDistance=min(minimumBeakDistance ?? distance,distance)}
                if let hit=result.contact {contact=hit;captured=true;attemptEnded=true;recoveryStartedAt=hit.insectAge}
                else if to>=min(plan.interceptionWindow.upperBound,step.trajectory.terminalAge) {
                    attemptEnded=true;recoveryStartedAt=min(plan.interceptionWindow.upperBound,step.trajectory.terminalAge)
                }
            } else {attemptEnded=true;recoveryStartedAt=from}
            if !attemptEnded,to>=plan.interceptionWindow.upperBound {
                attemptEnded=true;recoveryStartedAt=plan.interceptionWindow.upperBound
            }
        }
        if attemptEnded,bird.state == .perched,let point=reservation.point(in:engine),
           reservation.isValid(in:engine),Geometry.distance(bird.position,point)<0.001,
           let clip=PoseClip.insectCatchRecovery(species:plan.species),
           to-(recoveryStartedAt ?? to)+1e-9>=(captured ? clip.duration:(clip.frames.last?.duration ?? clip.duration)) {
            bird.finishCoordinatedFlight()
            return InsectResolution(contact:contact,completion:captured ? .completed:.failed(.missedTarget))
        }
        return InsectResolution(contact:contact)
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),let revision,bird.motionRevision==revision,!bird.isDeparting,
              engine.runtime.owners[plan.id]==nil else {return}
        if bird.state == .perched,reservation.isValid(in:engine),
           let point=reservation.point(in:engine),Geometry.distance(point,bird.position)<0.001 {
            bird.finishCoordinatedFlight();return
        }
        if reason == .replaced {bird.requestFlightRecovery();return}
        engine.recoverFromInsectCatch(plan.id)
        // The independently committed insect continues its remaining route.
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard id==plan.id,let bird=engine.bird(id),bird.motionRevision==revision else {return nil}
        if let began=recoveryStartedAt,let clip=PoseClip.insectCatchRecovery(species:plan.species) {
            let t=max(0,age-began),duration=captured ? clip.duration:(clip.frames.last?.duration ?? clip.duration)
            if t<duration {
                let frame=captured ? clip.sample(at:t):clip.frames.last
                if let frame {return BirdPose(frameName:frame.name,hopOffset:0,facingRight:bird.facingRight)}
            }
        }
        if !attemptEnded,!interrupted,plan.interceptionWindow.contains(age) {
            return BirdPose(frameName:"catchOpen",hopOffset:0,facingRight:plan.facingRight)
        }
        if bird.state == .perched {return BirdPose(frameName:"stand",hopOffset:0,facingRight:bird.facingRight)}
        return nil
    }
}
