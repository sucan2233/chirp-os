import Foundation
import CoreGraphics

/// One ordinary airborne resident, one frozen target route, one open-beak
/// window. A plan never changes the insect path to guarantee a contact.
struct InsectCatchPlan {
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.insectCatch).requiredFrames}
    static let contactAges=[1.2,2.0,2.8,3.6]
    static let maximumInsectSpeedPerScale=480.0
    static let minimumFullyVisibleLead=0.8
    let id:BirdID
    let species:SpeciesID
    let source:BehaviorSource
    let initialFlight:AirborneFlightSnapshot
    let originalHost:Surface
    let originalDestination:LandingReservation
    let spriteScale:CGFloat
    let facingRight:Bool
    let route:CoordinatedFlightRoute
    let trajectory:InsectTrajectory
    let interceptionWindow:Range<Double>
    let nominalInterceptAge:Double
    fileprivate let envelope:FlightSceneEnvelope

    func canBegin(in engine:BehaviorEngine) -> Bool {
        guard let bird=engine.bird(id),let flight=bird.airborneFlight,
              flight.revision==initialFlight.revision,flight.position==initialFlight.position,
              flight.velocity==initialFlight.velocity,flight.destination==initialFlight.destination,
              bird.facingRight==facingRight else {return false}
        return bird.canBeginCoordinatedFlight(route,on:originalHost,fraction:originalDestination.fraction,
            spriteScale:spriteScale,airborne:true)
    }
    func isSafe(in engine:BehaviorEngine,after age:Double=0) -> Bool {
        originalDestination.host(in:engine)==originalHost && originalDestination.isValid(in:engine) &&
            envelope.isClear(in:engine,excluding:[id],display:nil,after:age) && envelope.pointerIsClear(in:engine,after:age)
    }
    /// Internal evidence/fixture seam: replace only the frozen physical target
    /// trajectory. Production commands do not expose a success/miss switch.
    func replacingTrajectory(_ value:InsectTrajectory) -> InsectCatchPlan? {
        guard value.worldScale==trajectory.worldScale,value.display==trajectory.display,
              value.screens==trajectory.screens,value.displays==trajectory.displays,value.displayIDs==trajectory.displayIDs else {return nil}
        return InsectCatchPlan(id:id,species:species,source:source,initialFlight:initialFlight,
            originalHost:originalHost,originalDestination:originalDestination,spriteScale:spriteScale,
            facingRight:facingRight,route:route,trajectory:value,interceptionWindow:interceptionWindow,
            nominalInterceptAge:nominalInterceptAge,envelope:envelope)
    }
    static func candidates(in engine:BehaviorEngine,species:SpeciesID,source:BehaviorSource) -> [InsectCatchPlan] {
        guard species == .barnSwallow,!engine.paused,!engine.world.buttonsDown,
              source != .automatic || engine.ambientEnabled,
              engine.settings.probabilities.entries.contains(where:{$0.id==species && $0.points>0}),
              engine.world.insectArtAvailable,engine.insects.current==nil,
              BehaviorDefinitions.definition(for:.insectCatch).isEnabled(settings:engine.settings,source:source),
              engine.world.scale.isFinite,engine.world.scale>0,
              PoseClip.insectCatchRecovery(species:species) != nil,
              requiredFrames.allSatisfy({PoseClip.catchBeakAnchor(species:species,frame:$0) != nil}) else {return []}
        var result:[InsectCatchPlan]=[]
        let birds=engine.birds.filter{$0.profile.id==species}.sorted{(engine.id(of:$0) ?? BirdID(0))<(engine.id(of:$1) ?? BirdID(0))}
        for bird in birds.prefix(16) {
            guard let id=engine.id(of:bird),engine.role(of:bird) == .resident,engine.runtime.owners[id]==nil,
                  !bird.isDeparting,bird.edge == .top,let flight=bird.airborneFlight,
                  requiredFrames.isSubset(of:engine.world.availableFrames[species] ?? []),!engine.pointerNear(bird),
                  PoseClip.catchBeakAnchor(species:species,frame:bird.frameName) != nil,
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  !host.isHabitat,host.isGround || host.layer==0,
                  source != .automatic || engine.perchPlanner.automaticWeight(id,kind:.insectCatch)>0 else {continue}
            let scale=engine.spriteScale(for:bird),speed=Double(Geometry.distance(.zero,flight.velocity))
            guard scale.isFinite,scale>0,speed.isFinite,speed>=60,
                  abs(Double(flight.velocity.x))/speed>=0.25,bird.facingRight==(flight.velocity.x>0),
                  let display=engine.world.displays.first(where:{$0.contains(Geometry.landingFootprint(at:flight.position,scale:scale))}) else {continue}
            for intercept in contactAges {
                guard result.count<8 else {return result}
                let direction=CGPoint(x:flight.velocity.x/speed,y:flight.velocity.y/speed)
                let cruise=min(speed,max(100,150*Double(engine.world.scale)))
                let duration=intercept+0.25,rampIn=0.12
                // Integral of the existing cosine speed ramp, followed by a
                // constant-speed straight. Initial velocity is never scaled.
                let length=cruise*duration+(speed-cruise)*rampIn/2
                let end=CGPoint(x:flight.position.x+direction.x*length,y:flight.position.y+direction.y*length)
                let path=FlightPath(points:[flight.position,end])
                guard let timing=FlightTiming(distance:length,cruiseSpeed:cruise,initialSpeed:speed,
                    finalSpeed:cruise,rampIn:rampIn,rampOut:0),abs(timing.duration-duration)<1e-6,timing.duration<=4,
                      let exit=InsectCatchJourney.leg(from:end,velocity:CGPoint(x:direction.x*cruise,y:direction.y*cruise),
                        to:flight.destination,scale:scale,preferredCruise:min(300*Double(engine.world.scale),
                            FlightBehavior.cruiseSpeed(species,multiplier:bird.profile.speed))),
                      InsectCatchJourney.continuous(CoordinatedFlightLeg(path:path,timing:timing),exit),
                      let route=CoordinatedFlightRoute(legs:[CoordinatedFlightLeg(path:path,timing:timing),exit]),
                      InsectCatchJourney.fits(route,scale:scale,display:display),
                      let envelope=FlightSceneEnvelope(routes:[route],offsets:[0],scales:[scale],maximumDuration:30),
                      let anchor=PoseClip.catchBeakAnchor(species:species,frame:"catchOpen") else {continue}
                let beak=anchor.world(foot:route.position(at:intercept),scale:scale,facingRight:bird.facingRight)
                guard let trajectory=readableTrajectory(beak:beak,intercept:intercept,route:route,
                    display:display,bird:bird,birdID:id,birdScale:scale,in:engine) else {continue}
                let slot=LandingReservation(bird:id,host:host,fraction:bird.fraction)
                let plan=InsectCatchPlan(id:id,species:species,source:source,initialFlight:flight,
                    originalHost:host,originalDestination:slot,spriteScale:scale,facingRight:bird.facingRight,
                    route:route,trajectory:trajectory,interceptionWindow:(intercept-0.2)..<timing.duration,
                    nominalInterceptAge:intercept,envelope:envelope)
                if plan.canBegin(in:engine),plan.isSafe(in:engine) {result.append(plan)}
            }
        }
        return result
    }

    /// At most five entry rays per time probe: front-side diagonals first,
    /// followed by the forward horizontal edge. Every ray has constant velocity
    /// through and beyond the rendezvous; it is never steered onto a live beak.
    private static func readableTrajectory(beak:CGPoint,intercept:Double,route:CoordinatedFlightRoute,
        display:CGRect,bird:Bird,birdID:BirdID,birdScale:CGFloat,in engine:BehaviorEngine) -> InsectTrajectory? {
        let w=engine.world.scale,half=InsectTrajectory.logicalSize*w/2,gap=w
        let whole=display.insetBy(dx:half,dy:half)
        guard !whole.isEmpty,whole.contains(beak) else {return nil}
        let sign:CGFloat=bird.facingRight ? 1:-1
        var entries:[CGPoint]=[]
        for slope in [1.2,0.6] {
            let pair=[display.minY-half-gap,display.maxY+half+gap].map {y -> CGPoint in
                let ahead=max(64*w,abs(beak.y-y)*slope)
                let x=min(whole.maxX,max(whole.minX,beak.x+sign*ahead))
                return CGPoint(x:x,y:y)
            }.sorted {Geometry.distance($0,beak)<Geometry.distance($1,beak)}
            entries += pair
        }
        entries.append(CGPoint(x:bird.facingRight ? display.maxX+half+gap:display.minX-half-gap,y:beak.y))
        for start in entries {
            guard (start.x-beak.x)*sign>0 else {continue}
            let velocity=CGPoint(x:(beak.x-start.x)/intercept,y:(beak.y-start.y)/intercept)
            let speed=Double(Geometry.distance(.zero,velocity))
            guard speed.isFinite,speed>0,speed<=maximumInsectSpeedPerScale*Double(w),
                  let full=clip(from:start,to:beak,rect:whole) else {continue}
            let fullyEntered=full.lowerBound*intercept,open=intercept-0.2
            guard open-fullyEntered>=minimumFullyVisibleLead else {continue}
            let outer=display.insetBy(dx:-half-gap,dy:-half-gap)
            var exit=Double.infinity
            if velocity.x>0 {exit=min(exit,Double((outer.maxX-beak.x)/velocity.x))}
            if velocity.x<0 {exit=min(exit,Double((outer.minX-beak.x)/velocity.x))}
            if velocity.y>0 {exit=min(exit,Double((outer.maxY-beak.y)/velocity.y))}
            if velocity.y<0 {exit=min(exit,Double((outer.minY-beak.y)/velocity.y))}
            let duration=intercept+exit+Double(gap)/speed
            guard exit.isFinite,exit>0,duration.isFinite,duration<=60 else {continue}
            let finish=CGPoint(x:start.x+velocity.x*duration,y:start.y+velocity.y*duration)
            guard let target=InsectTrajectory(waypoints:[InsectWaypoint(time:0,position:start),InsectWaypoint(time:duration,position:finish)],
                display:display,worldScale:w,screens:engine.world.screens,displays:engine.world.displays,displayIDs:engine.world.displayIDs),
                  avoidsBody(target,route:route,intercept:intercept,birdScale:birdScale,facingRight:bird.facingRight) else {continue}
            // Full sprite visibility includes system panels and other birds,
            // not merely an in-screen collision center.
            let a=target.position(at:fullyEntered),b=target.position(at:intercept)
            let sweep=CGRect(x:min(a.x,b.x)-half,y:min(a.y,b.y)-half,
                width:abs(a.x-b.x)+2*half,height:abs(a.y-b.y)+2*half)
            var blockers=engine.world.surfaces.filter{!$0.isGround && $0.layer>0}.map(\.rect)
            for peer in engine.birds where engine.id(of:peer) != birdID {
                blockers.append(engine.bounds(of:peer))
                if peer.state == .flying,let area=peer.plannedFlightFootprint(scale:engine.spriteScale(for:peer)) {blockers.append(area)}
            }
            guard !blockers.contains(where:{$0.intersects(sweep)}) else {continue}
            return target
        }
        return nil
    }
    private static func clip(from a:CGPoint,to b:CGPoint,rect:CGRect) -> ClosedRange<Double>? {
        var lo=0.0,hi=1.0
        for (p,d,mn,mx) in [(a.x,b.x-a.x,rect.minX,rect.maxX),(a.y,b.y-a.y,rect.minY,rect.maxY)] {
            if abs(d)<1e-12 {if p<mn || p>mx {return nil};continue}
            let x=Double((mn-p)/d),y=Double((mx-p)/d)
            lo=max(lo,min(x,y));hi=min(hi,max(x,y))
            if hi<lo {return nil}
        }
        return lo...hi
    }
    /// Before the open pose, enclose every ordinary frame in its entire canvas
    /// and bound motion between samples. During open, both actors are linear;
    /// check the exact relative segment against the authored body's padded AABB
    /// up to the first possible beak contact. This never declares a capture.
    private static func avoidsBody(_ target:InsectTrajectory,route:CoordinatedFlightRoute,
        intercept:Double,birdScale:CGFloat,facingRight:Bool) -> Bool {
        guard let pose=CatchArtGeometry.pose(species:.barnSwallow,frame:"catchOpen") else {return false}
        let open=intercept-0.2,sign:CGFloat=facingRight ? 1:-1
        let first=route.legs[0],direction=CGPoint(x:(first.path.point(1).x-first.path.point(0).x)/first.path.length,
            y:(first.path.point(1).y-first.path.point(0).y)/first.path.length)
        let start=target.waypoints[0],end=target.waypoints[1]
        let insectVelocity=CGPoint(x:(end.position.x-start.position.x)/(end.time-start.time),y:(end.position.y-start.position.y)/(end.time-start.time))
        let cruise=first.timing.speed(at:intercept)
        let relative=CGPoint(x:insectVelocity.x-direction.x*cruise,y:insectVelocity.y-direction.y*cruise)
        let relativeSpeed=Double(Geometry.distance(.zero,relative))
        guard relativeSpeed>0 else {return false}
        let contact=max(open,intercept-Double(target.collisionRadius)/relativeSpeed)
        func local(_ t:Double) -> CGPoint {
            let p=target.position(at:t),foot=route.position(at:t)
            return CGPoint(x:29+sign*(p.x-foot.x)/birdScale,y:39+(p.y-foot.y)/birdScale)
        }
        let bound=first.timing.peakSpeed+Double(Geometry.distance(.zero,insectVelocity))
        for index in 0..<64 {
            let dt=open/64,mid=(Double(index)+0.5)*dt
            let margin=(target.collisionRadius+CGFloat(bound*dt/2))/birdScale
            if CGRect(x:0,y:0,width:48,height:48).insetBy(dx:-margin,dy:-margin).contains(local(mid)) {return false}
        }
        let head=[pose.headPoint(-CatchArtGeometry.swallowHeadWidth/2,-CatchArtGeometry.swallowHeadHeight/2),
                  pose.headPoint(CatchArtGeometry.swallowHeadWidth/2,-CatchArtGeometry.swallowHeadHeight/2),
                  pose.headPoint(-CatchArtGeometry.swallowHeadWidth/2,CatchArtGeometry.swallowHeadHeight/2),
                  pose.headPoint(CatchArtGeometry.swallowHeadWidth/2,CatchArtGeometry.swallowHeadHeight/2)]
        let front=([pose.body.maxX,pose.tail.x]+head.map(\.x)+pose.nearWing.map(\.x)+pose.farWing.map(\.x)).max()!
        let radius=target.collisionRadius/birdScale
        let body=CGRect(x:0,y:0,width:front,height:48).insetBy(dx:-radius,dy:-radius)
        return clip(from:local(open),to:local(contact),rect:body)==nil
    }
}

/// Shared path construction for interception exits and actual-state recovery.
/// Fine polyline endpoints preserve tangent vectors, not just scalar speeds.
enum InsectCatchJourney {
    static func leg(from start:CGPoint,velocity:CGPoint,to end:CGPoint,scale:CGFloat,preferredCruise:Double?=nil) -> CoordinatedFlightLeg? {
        let speed=Double(Geometry.distance(.zero,velocity)),distance=Double(Geometry.distance(start,end))
        guard distance>max(4,8*Double(scale)),speed.isFinite,speed>0.001 else {return nil}
        let direction=CGPoint(x:velocity.x/speed,y:velocity.y/speed)
        let handle=min(distance*0.32,max(distance*0.08,speed*0.16))
        // A short exact tangent lead makes the .001s handoff probe independent
        // of how far away the destination controls are. It is part of FlightPath,
        // not a separate integrator or a position correction at installation.
        let lead=min(distance*0.10,max(2,speed*0.01))
        let a=CGPoint(x:start.x+direction.x*lead,y:start.y+direction.y*lead)
        let b=CGPoint(x:a.x+direction.x*handle,y:a.y+direction.y*handle)
        let c=CGPoint(x:end.x,y:end.y-min(distance*0.30,80*Double(scale)))
        let path=FlightPath(points:[start]+(0...512).map {index in
            let t=Double(index)/512,s=1-t
            let w0=s*s*s,w1=3*s*s*t,w2=3*s*t*t,w3=t*t*t
            return CGPoint(x:a.x*w0+b.x*w1+c.x*w2+end.x*w3,
                           y:a.y*w0+b.y*w1+c.y*w2+end.y*w3)
        })
        let cruise=preferredCruise ?? max(80*Double(scale),min(speed,300*Double(scale)))
        let ramps=(speed+cruise)*0.15/2+cruise*0.35/2
        let fit=min(1,path.length/max(1,ramps))
        guard let timing=FlightTiming(distance:path.length,cruiseSpeed:cruise,initialSpeed:speed,finalSpeed:0,
                                     rampIn:0.15*fit,rampOut:0.35*fit) else {return nil}
        return CoordinatedFlightLeg(path:path,timing:timing)
    }
    static func continuous(_ a:CoordinatedFlightLeg,_ b:CoordinatedFlightLeg) -> Bool {
        guard Geometry.distance(a.path.point(1),b.path.point(0))<0.001 else {return false}
        let v=a.timing.speed(at:a.timing.duration),w=b.timing.speed(at:0)
        let aa=a.path.point(0.999999),ab=a.path.point(1),ba=b.path.point(0),bb=b.path.point(0.000001)
        let al=Geometry.distance(aa,ab),bl=Geometry.distance(ba,bb)
        guard al>0,bl>0,abs(v-w)<0.01 else {return false}
        return Geometry.distance(CGPoint(x:(ab.x-aa.x)/al*v,y:(ab.y-aa.y)/al*v),
                                 CGPoint(x:(bb.x-ba.x)/bl*w,y:(bb.y-ba.y)/bl*w))<=max(2,v*0.01)
    }
    static func fits(_ route:CoordinatedFlightRoute,scale:CGFloat,display:CGRect) -> Bool {
        route.legs.allSatisfy {leg in
            let r=leg.path.bounds
            return display.contains(CGRect(x:r.minX-29*scale,y:r.minY-39*scale,width:r.width+58*scale,height:r.height+48*scale))
        }
    }
}

final class InsectCatchExecution:InsectCatchMotionExecution {
    let plan:InsectCatchPlan
    let insectID:ScenePropID
    let kind:BehaviorKind = .insectCatch
    var source:BehaviorSource {plan.source}
    var participants:[BirdID] {[plan.id]}
    var propIDs:[ScenePropID] {[insectID]}
    var timeout:Double {35}
    var landingReservations:[LandingReservation] {reservation.map{[$0]} ?? []}
    private var reservation:LandingReservation?
    private var revision:UInt64?
    private var runID:BehaviorRunID?
    private var age=0.0
    private var resolvedAge=0.0
    private var recoveryStartedAt:Double?
    private var recovered=false
    private var startFailed=false
    private(set) var captured=false
    private(set) var minimumBeakDistance:CGFloat?
    private var returnEnvelope:FlightSceneEnvelope?
    private var returnHost:Surface?
    private var returnStartedAt=0.0
    private struct MotionStart {
        let foot:CGPoint
        let frame:String
        let facingRight:Bool
        let beak:CGPoint
    }
    private var motionStart:MotionStart?
    init(plan:InsectCatchPlan,insectID:ScenePropID) {
        self.plan=plan;self.insectID=insectID;reservation=plan.originalDestination
    }
    func start(in engine:BehaviorEngine) {
        guard engine.insects.current==nil,let bird=engine.bird(plan.id),let owner=engine.runtime.owners[plan.id],
              plan.canBegin(in:engine),plan.isSafe(in:engine),
              bird.beginCoordinatedFlight(plan.route,on:plan.originalHost,fraction:plan.originalDestination.fraction,
                  spriteScale:plan.spriteScale,airborne:true) else {startFailed=true;return}
        revision=bird.motionRevision;runID=owner
        if !engine.insects.install(id:insectID,trajectory:plan.trajectory) {startFailed=true}
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard !startFailed else {return .failed(.targetInvalid)}
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:.preview),
              engine.settings.probabilities.entries.contains(where:{$0.id==plan.species && $0.points>0}) else {return .cancelled(.settingsChanged)}
        guard engine.world.insectArtAvailable,InsectCatchPlan.requiredFrames.isSubset(of:engine.world.availableFrames[plan.species] ?? []),
              PoseClip.insectCatchRecovery(species:plan.species) != nil,
              InsectCatchPlan.requiredFrames.allSatisfy({PoseClip.catchBeakAnchor(species:plan.species,frame:$0) != nil}) else {return .failed(.missingFrames)}
        guard worldMatches(engine),engine.spriteScale(for:bird)==plan.spriteScale else {return .cancelled(.screensChanged)}
        guard revision==bird.motionRevision,!bird.isDeparting,engine.role(of:bird) == .resident else {return .failed(.targetInvalid)}
        if !recovered {
            guard bird.isCoordinatedFlying,let t=bird.coordinatedFlightAge,
                  abs(t-min(resolvedAge,plan.route.duration))<1e-6,
                  Geometry.distance(bird.position,plan.route.position(at:resolvedAge))<0.01 else {return .failed(.targetInvalid)}
            guard plan.isSafe(in:engine,after:resolvedAge) else {return .failed(.targetInvalid)}
        } else if !ordinaryReturnIsSafe(in:engine) {
            return .failed(.targetInvalid)
        }
        return nil
    }
    private func worldMatches(_ engine:BehaviorEngine) -> Bool {
        let t=plan.trajectory,w=engine.world
        return w.scale==t.worldScale && w.screens==t.screens && w.displays==t.displays && w.displayIDs==t.displayIDs
    }
    /// Engine calls before generic host tracking, including paused world updates.
    /// Original-target loss ends interception and restores a safe ordinary target;
    /// it never chases a reused PID or translates the bird with a moved window.
    func reconcileWorld(in engine:BehaviorEngine,sampleDT:Double?=nil) -> BehaviorCompletion? {
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard worldMatches(engine),engine.spriteScale(for:bird)==plan.spriteScale else {return .cancelled(.screensChanged)}
        guard revision==bird.motionRevision else {return .failed(.targetInvalid)}
        if recovered {
            if !ordinaryReturnIsSafe(in:engine),!restoreOrdinaryFlight(in:engine) {
                return .failed(.targetInvalid)
            }
            return nil
        }
        if !plan.isSafe(in:engine,after:resolvedAge) {
            recoveryStartedAt=recoveryStartedAt ?? age
            guard restoreOrdinaryFlight(in:engine) else {return .failed(.targetInvalid)}
        }
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        // Includes Runtime's clipped final step. Contact/deadline decisions are
        // exclusively after Bird.tick; insects still receive the full world dt.
        if let bird=engine.bird(plan.id) {
            let pose=presentation(for:plan.id,in:engine)
            let frame=pose?.frameName ?? bird.frameName,facing=pose?.facingRight ?? bird.facingRight
            if let anchor=PoseClip.catchBeakAnchor(species:plan.species,frame:frame) {
                motionStart=MotionStart(foot:bird.position,frame:frame,facingRight:facing,
                    beak:anchor.world(foot:bird.position,scale:plan.spriteScale,facingRight:facing))
            } else {motionStart=nil}
        }
        if dt.isFinite,dt>0 {age+=dt}
        return nil
    }
    func resolveMotion(_ step:InsectStep?,in engine:BehaviorEngine) -> InsectResolution {
        guard let bird=engine.bird(plan.id),let revision,revision==bird.motionRevision,let runID else {
            return InsectResolution(completion:.failed(.targetInvalid))
        }
        let from=resolvedAge,to=age
        defer {resolvedAge=age}
        if !recovered {
            guard let motionStart,Geometry.distance(motionStart.foot,plan.route.position(at:from))<0.01,
                  let actualAge=bird.coordinatedFlightAge,abs(actualAge-min(to,plan.route.duration))<1e-6,
                  Geometry.distance(bird.position,plan.route.position(at:to))<0.01 else {
                return InsectResolution(completion:.failed(.targetInvalid))
            }
            if plan.interceptionWindow.contains(from),recoveryStartedAt==nil,
               (motionStart.frame != "catchOpen" || motionStart.facingRight != plan.facingRight) {
                return InsectResolution(completion:.failed(.targetInvalid))
            }
            if plan.interceptionWindow.contains(from),recoveryStartedAt==nil,
               let anchor=PoseClip.catchBeakAnchor(species:plan.species,frame:"catchOpen"),
               Geometry.distance(motionStart.beak,anchor.world(foot:plan.route.position(at:from),
                    scale:plan.spriteScale,facingRight:plan.facingRight))>1e-6 {
                return InsectResolution(completion:.failed(.targetInvalid))
            }
        }
        var contact:InsectContact?
        if recoveryStartedAt==nil {
            if let step,step.insectID==insectID,abs(step.startAge-from)<1e-6,
               let anchor=PoseClip.catchBeakAnchor(species:plan.species,frame:"catchOpen") {
                // The entire open window lies on the first straight route leg.
                // Facing is stable there; the flight/open and open/close changes
                // are half-open boundaries, never interpolated anchor jumps.
                let result=InsectContactResolver.resolve(step,runID:runID,birdID:plan.id,
                    simulationStart:engine.time-(step.endAge-step.startAge),motionInterval:from...to,
                    openInterval:plan.interceptionWindow,beakAt:{t in
                        anchor.world(foot:self.plan.route.position(at:t),scale:self.plan.spriteScale,facingRight:self.plan.facingRight)
                    })
                if let d=result.minimumDistance {minimumBeakDistance=min(minimumBeakDistance ?? d,d)}
                if let hit=result.contact {contact=hit;captured=true;recoveryStartedAt=hit.insectAge}
                else if to>=min(plan.interceptionWindow.upperBound,step.trajectory.terminalAge) {
                    recoveryStartedAt=min(plan.interceptionWindow.upperBound,step.trajectory.terminalAge)
                }
            } else if step==nil || step?.insectID != insectID {
                recoveryStartedAt=from
            }
            if recoveryStartedAt==nil,to>=plan.interceptionWindow.upperBound {recoveryStartedAt=plan.interceptionWindow.upperBound}
        }
        if let began=recoveryStartedAt,let clip=PoseClip.insectCatchRecovery(species:plan.species) {
            let duration=captured ? clip.duration:(clip.frames.last?.duration ?? clip.duration)
            if to-began+1e-9>=duration {
                if !recovered,!restoreOrdinaryFlight(in:engine) {
                    // A very short legal journey can already be landing. Wait
                    // for its actual perch, rather than calling that recovery a
                    // failure or forcing another airborne transition.
                    if bird.state == .landing,reservation?.isValid(in:engine)==true {
                        return InsectResolution(contact:contact)
                    }
                    return InsectResolution(contact:contact,completion:.failed(.targetInvalid))
                }
                return InsectResolution(contact:contact,completion:captured ? .completed:.failed(.missedTarget))
            }
        }
        return InsectResolution(contact:contact)
    }
    private func restoreOrdinaryFlight(in engine:BehaviorEngine) -> Bool {
        guard let bird=engine.bird(plan.id),let revision,revision==bird.motionRevision else {return false}
        if bird.state == .perched,let slot=reservation,slot.isValid(in:engine),
           let point=slot.point(in:engine),Geometry.distance(point,bird.position)<0.001 {
            bird.finishCoordinatedFlight();recovered=true;returnHost=slot.host(in:engine);return true
        }
        guard bird.state == .flying else {return false}
        let velocity=bird.ordinaryFlightVelocity
        var targets:[LandingReservation]=[]
        if let host=plan.originalDestination.host(in:engine),!host.isHabitat {
            targets.append(LandingReservation(bird:plan.id,host:host,fraction:plan.originalDestination.fraction))
        }
        for host in engine.world.surfaces.filter({!$0.isHabitat && ($0.isGround || $0.layer==0)}).sorted(by:{$0.id<$1.id}).prefix(32) {
            for fraction in [CGFloat(0.5),CGFloat(0.25),CGFloat(0.75)] {targets.append(LandingReservation(bird:plan.id,host:host,fraction:fraction))}
        }
        for slot in targets {
            guard slot.isValid(in:engine),let host=slot.host(in:engine),let target=slot.point(in:engine),
                  !engine.runtime.landingReservations.contains(where:{$0.bird != plan.id && slot.conflicts(with:$0,in:engine)}),
                  let leg=InsectCatchJourney.leg(from:bird.position,velocity:velocity,to:target,scale:plan.spriteScale),
                  let route=CoordinatedFlightRoute(legs:[leg]),
                  engine.world.displays.contains(where:{InsectCatchJourney.fits(route,scale:plan.spriteScale,display:$0)}),
                  let envelope=FlightSceneEnvelope(routes:[route],offsets:[0],scales:[plan.spriteScale],maximumDuration:30),
                  envelope.isClear(in:engine,excluding:participants,display:nil),
                  bird.resumeOrdinaryFlight(leg,on:host,fraction:slot.fraction,spriteScale:plan.spriteScale,expectedRevision:revision)
            else {continue}
            self.revision=bird.motionRevision;reservation=slot;recovered=true
            returnEnvelope=envelope;returnHost=host;returnStartedAt=age
            return true
        }
        return false
    }
    private func ordinaryReturnIsSafe(in engine:BehaviorEngine) -> Bool {
        guard worldMatches(engine),let bird=engine.bird(plan.id),engine.spriteScale(for:bird)==plan.spriteScale,
              let slot=reservation,slot.isValid(in:engine),slot.host(in:engine)==returnHost else {return false}
        return returnEnvelope?.isClear(in:engine,excluding:participants,display:nil,after:age-returnStartedAt) ?? true
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard let bird=engine.bird(plan.id),let revision,revision==bird.motionRevision,!bird.isDeparting,
              engine.runtime.owners[plan.id]==nil else {return}
        // The clicked bird's next owner is about to install its own route. No
        // eager engine routing/sendAway may take that ownership away.
        if reason == .replaced {bird.requestFlightRecovery();return}
        if !worldMatches(engine) || engine.spriteScale(for:bird) != plan.spriteScale {
            engine.recoverFromInsectCatch(plan.id);return
        }
        if recovered,ordinaryReturnIsSafe(in:engine) {return}
        if !restoreOrdinaryFlight(in:engine) {engine.recoverFromInsectCatch(plan.id)}
        // The independent insect is deliberately untouched by run cancellation.
    }
    func presentation(for birdID:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard birdID==plan.id,let bird=engine.bird(birdID),revision==bird.motionRevision else {return nil}
        if let began=recoveryStartedAt,let clip=PoseClip.insectCatchRecovery(species:plan.species) {
            let t=max(0,age-began)
            let frame=captured ? clip.sample(at:min(t,clip.duration.nextDown)):clip.frames.last
            if let frame {return BirdPose(frameName:frame.name,hopOffset:0,facingRight:bird.facingRight)}
        }
        if plan.interceptionWindow.contains(age) {
            return BirdPose(frameName:"catchOpen",hopOffset:0,facingRight:plan.facingRight)
        }
        return nil
    }
}
