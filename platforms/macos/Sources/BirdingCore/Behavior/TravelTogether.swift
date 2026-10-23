import Foundation
import CoreGraphics

public enum TravelTogetherBehavior {
    public static let supportedSpecies:Set<SpeciesID> = [
        .treeSparrow,.barnSwallow,.spottedDove,.lightVentedBulbul,
        .azureWingedMagpie,.blackCollaredStarling
    ]
}

/// An encounter between two ordinary flights, preserving both original landings.
/// All three legs are installed immediately; neither bird waits for its partner.
struct TravelTogetherPlan {
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.travelTogether).requiredFrames}
    static var supportedSpecies:Set<SpeciesID> {TravelTogetherBehavior.supportedSpecies}
    let participants:[BirdID]
    let destinations:[LandingReservation]
    let hosts:[Surface]
    let scales:[CGFloat]
    let routes:[CoordinatedFlightRoute]
    let initialFlights:[AirborneFlightSnapshot]
    let commonPath:FlightPath
    let formationOffsets:[CGPoint]
    let commonDuration:Double
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]
    let worldScale:CGFloat
    private let envelope:FlightSceneEnvelope

    var duration:Double {routes.map(\.duration).max() ?? 0}
    var commonEntries:[Double] {routes.map{$0.legs[0].timing.duration}}
    var commonOverlap:Double {
        // Use the installed leg clocks, including polyline rounding, rather
        // than claiming overlap from the requested duration alone.
        (zip(commonEntries,routes).map{$0.0+$0.1.legs[1].timing.duration}.min() ?? 0)-(commonEntries.max() ?? 0)
    }
    func position(of index:Int,at age:Double) -> CGPoint {routes[index].position(at:age)}
    func pointerIsClear(in engine:BehaviorEngine,after age:Double=0) -> Bool {
        envelope.pointerIsClear(in:engine,after:age)
    }
    func isSafe(in engine:BehaviorEngine,after age:Double=0) -> Bool {
        guard engine.world.screens==screens,engine.world.displays==displays,
              engine.world.scale==worldScale,engine.world.displays.contains(display) else {return false}
        for index in participants.indices {
            guard let bird=engine.bird(participants[index]),engine.spriteScale(for:bird)==scales[index],
                  destinations[index].host(in:engine)==hosts[index],destinations[index].isValid(in:engine),
                  destinations[index].point(in:engine).map({Geometry.distance($0,initialFlights[index].destination)<0.001}) == true
            else {return false}
        }
        guard !destinations[0].conflicts(with:destinations[1],in:engine) else {return false}
        return envelope.isClear(in:engine,excluding:participants,display:display,after:age)
    }
    /// Check BOTH handoffs before installing either one. The snapshot revision
    /// also rejects plans retained across an intervening ordinary-flight tick.
    func canBegin(in engine:BehaviorEngine) -> Bool {
        participants.indices.allSatisfy {index in
            guard let bird=engine.bird(participants[index]),let flight=bird.airborneFlight else {return false}
            let expected=initialFlights[index]
            return flight.revision==expected.revision && flight.position==expected.position &&
                flight.velocity==expected.velocity && flight.destination==expected.destination &&
                bird.canBeginCoordinatedFlight(routes[index],on:hosts[index],fraction:destinations[index].fraction,
                    spriteScale:scales[index],delay:0,airborne:true)
        }
    }

    private static func plus(_ point:CGPoint,_ vector:CGPoint,_ distance:Double) -> CGPoint {
        CGPoint(x:point.x+vector.x*distance,y:point.y+vector.y*distance)
    }
    private static func minus(_ a:CGPoint,_ b:CGPoint) -> CGPoint {CGPoint(x:a.x-b.x,y:a.y-b.y)}
    private static func dot(_ a:CGPoint,_ b:CGPoint) -> Double {Double(a.x*b.x+a.y*b.y)}
    private static func unit(_ vector:CGPoint) -> CGPoint {
        let length=Geometry.distance(.zero,vector)
        return CGPoint(x:vector.x/length,y:vector.y/length)
    }
    private static func approachPath(_ a:CGPoint,_ b:CGPoint,_ c:CGPoint,_ d:CGPoint) -> FlightPath {
        // Only this handoff needs a finer polyline than the legacy 64-point
        // cubic: its first chord must preserve the measured velocity within 1%.
        FlightPath(points:(0...256).map {index in
            if index==0 {return a}
            if index==256 {return d}
            let t=Double(index)/256,s=1-t
            let w0=s*s*s,w1=3*s*s*t,w2=3*s*t*t,w3=t*t*t
            return CGPoint(x:a.x*w0+b.x*w1+c.x*w2+d.x*w3,y:a.y*w0+b.y*w1+c.y*w2+d.y*w3)
        })
    }

    static func candidates(in engine:BehaviorEngine,source:BehaviorSource = .automatic) -> [TravelTogetherPlan] {
        guard !engine.paused,!engine.world.buttonsDown,engine.world.scale.isFinite,engine.world.scale>0,
              BehaviorDefinitions.definition(for:.travelTogether).isEnabled(settings:engine.settings,source:source)
        else {return []}
        let ids=engine.birds.compactMap {bird -> BirdID? in
            guard let id=engine.id(of:bird),engine.role(of:bird) == .resident,
                  supportedSpecies.contains(bird.profile.id),engine.runtime.owners[id]==nil,
                  bird.edge == .top,!bird.isDeparting,!bird.needsDestination,!bird.isCoordinatedFlying,
                  let flight=bird.airborneFlight,
                  [flight.position.x,flight.position.y,flight.velocity.x,flight.velocity.y,
                   flight.destination.x,flight.destination.y].allSatisfy({$0.isFinite}),
                  Geometry.distance(.zero,flight.velocity)>0,
                  requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
                  !engine.pointerNear(bird),
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}),!host.isFixedPerch,host.isGround || host.layer==0
            else {return nil}
            // The existing ecology clock carries cooldowns even while airborne.
            // Perched dwell/quiet time has no bearing on this opportunity.
            if source == .automatic,engine.perchPlanner.automaticWeight(id,kind:.travelTogether)<=0 {return nil}
            return id
        }.sorted().prefix(16)
        var result:[TravelTogetherPlan]=[],pairs=0,probes=0
        for (offset,first) in ids.enumerated() {
            for second in ids.dropFirst(offset+1) {
                guard pairs<12,probes<24,result.count<4 else {return result}
                guard let a=engine.bird(first),let b=engine.bird(second),a.profile.id==b.profile.id,
                      let fa=a.airborneFlight,let fb=b.airborneFlight else {continue}
                pairs+=1
                let scales=[engine.spriteScale(for:a),engine.spriteScale(for:b)]
                guard scales.allSatisfy({$0.isFinite && $0>0}),
                      dot(unit(fa.velocity),unit(fb.velocity))>=0.85,
                      Geometry.distance(fa.position,fb.position)<=600*(scales.max() ?? 1),
                      let display=engine.world.displays.first(where:{
                          $0.contains(Geometry.landingFootprint(at:fa.position,scale:scales[0])) &&
                          $0.contains(Geometry.landingFootprint(at:fb.position,scale:scales[1]))
                      }) else {continue}
                // A slower common segment leaves room for a gentle split on
                // smaller displays. The one-second entry ramp keeps the
                // measured incoming velocity unchanged at the handoff.
                for speedFactor in [1.0,0.85,0.7] {
                    for approachFactor in [1.0,1.12] {
                        guard probes<24,result.count<4 else {return result}
                        probes+=1
                        if let plan=make(participants:[first,second],flights:[fa,fb],scales:scales,
                            display:display,speedFactor:speedFactor,approachFactor:approachFactor,in:engine) {
                            result.append(plan)
                        }
                    }
                }
            }
        }
        return result
    }

    /// Reject sharp bends using an upper speed bound, not render cadence. Every
    /// sampled tangent must continue forward; no U-turn or stationary rendezvous.
    private static func gentle(_ path:FlightPath,direction:CGPoint,peakSpeed:Double) -> Bool {
        guard path.length.isFinite,path.length>1,peakSpeed.isFinite,peakSpeed>0 else {return false}
        let count=128,spacing=path.length/Double(count)
        var previous:CGPoint?
        for index in 0..<count {
            let delta=minus(path.point(Double(index+1)/Double(count)),path.point(Double(index)/Double(count)))
            guard Geometry.distance(.zero,delta)>0.000001 else {return false}
            let tangent=unit(delta)
            guard dot(tangent,direction)>=0.35 else {return false}
            if let previous {
                let angle=acos(min(1,max(-1,dot(previous,tangent))))
                guard angle*peakSpeed/spacing<=2.4 else {return false}
            }
            previous=tangent
        }
        return true
    }

    private static func make(participants:[BirdID],flights:[AirborneFlightSnapshot],scales:[CGFloat],
                             display:CGRect,speedFactor:Double,approachFactor:Double,
                             in engine:BehaviorEngine) -> TravelTogetherPlan? {
        let birds=participants.compactMap{engine.bird($0)}
        let hosts=birds.compactMap{bird in engine.world.surfaces.first{$0.id==bird.hostID}}
        guard birds.count==2,hosts.count==2 else {return nil}
        let size=Double(scales.max() ?? 1)
        let velocities=flights.map{Double(Geometry.distance(.zero,$0.velocity))}
        let normalSpeed=FlightBehavior.cruiseSpeed(birds[0].profile.id,multiplier:birds[0].profile.speed)
        let speedLimit=min(900,normalSpeed*1.4)
        guard velocities.allSatisfy({$0>=60 && $0<=speedLimit}) else {return nil}
        let u=unit(flights[0].velocity),v=unit(flights[1].velocity)
        let direction=unit(CGPoint(x:u.x+v.x,y:u.y+v.y))
        let normal=CGPoint(x:-direction.y,y:direction.x)
        let delta=minus(flights[1].position,flights[0].position)
        let lateral=dot(delta,normal),gap=104*size
        guard abs(lateral)>=gap*1.3,abs(lateral)<=460*size,abs(dot(delta,direction))<=180*size else {return nil}
        let nominal=min(velocities.min() ?? 0,min(220*size,190*size*sqrt(birds[0].profile.speed)))*speedFactor
        guard nominal>=60 else {return nil}
        let commonDuration=2.2,chord=nominal*commonDuration
        // Two shallow cubics have matching forward tangents at both ends and at
        // the crest. Both birds traverse translated copies at the SAME phase.
        let zero=CGPoint.zero,end=plus(zero,direction,chord)
        let crest=plus(plus(zero,direction,chord/2),normal,6*size)
        let left=FlightPath(zero,plus(zero,direction,chord/6),plus(crest,direction,-chord/6),crest)
        let right=FlightPath(crest,plus(crest,direction,chord/6),plus(end,direction,-chord/6),end)
        let commonPath=FlightPath(points:(0...64).map{left.point(Double($0)/64)} +
            (1...64).map{right.point(Double($0)/64)})
        let speed=commonPath.length/commonDuration
        guard speed<=speedLimit,gentle(commonPath,direction:direction,peakSpeed:speed) else {return nil}
        let forward=max(230*size,(velocities.max()!+speed)/2+speed*0.6)*approachFactor
        let center=plus(CGPoint(x:(flights[0].position.x+flights[1].position.x)/2,
                                y:(flights[0].position.y+flights[1].position.y)/2),direction,forward)
        let side=lateral>0 ? 1.0:-1.0
        let targetDelta=minus(flights[1].destination,flights[0].destination)
        // When both destinations lie along one ledge, leave enough forward
        // stagger before the lateral gap closes during the split. Otherwise a
        // side-by-side pair would squeeze together on the final approach.
        let alongGap=abs(dot(targetDelta,normal))<gap*0.85 ?
            (dot(targetDelta,direction)>=0 ? 84.0:-84.0)*size:24*size
        let offsets=[plus(plus(.zero,normal,-side*gap/2),direction,-alongGap/2),
                     plus(plus(.zero,normal,side*gap/2),direction,alongGap/2)]
        var approaches:[FlightPath]=[],middles:[FlightPath]=[],exits:[FlightPath]=[],nominalTimings:[FlightTiming]=[]
        let rampIn=1.0,rampOut=0.25
        for index in 0..<2 {
            let flight=flights[index],entry=plus(center,offsets[index],1)
            let middle=FlightPath(points:(0...128).map{plus(entry,commonPath.point(Double($0)/128),1)})
            let leave=middle.point(1),remaining=dot(minus(flight.destination,leave),direction)
            guard dot(minus(flight.destination,flight.position),direction)>0,
                  remaining>=max(140*size,speed*0.8) else {return nil}
            let handle=Double(Geometry.distance(flight.position,entry))*0.34
            let approach=approachPath(flight.position,plus(flight.position,unit(flight.velocity),handle),
                plus(entry,direction,-handle),entry)
            let exit=FlightPath(leave,plus(leave,direction,remaining*0.4),
                plus(flight.destination,direction,-remaining*0.3),flight.destination)
            guard let timing=FlightTiming(distance:approach.length,cruiseSpeed:speed,initialSpeed:velocities[index],
                finalSpeed:speed,rampIn:rampIn,rampOut:rampOut) else {return nil}
            approaches.append(approach);middles.append(middle);exits.append(exit);nominalTimings.append(timing)
        }
        // Share the timing adjustment: the longer approach speeds up a little
        // while the shorter one slows down. Waiting for the slowest nominal
        // entry forces the rear bird below the minimum moving speed when the
        // formation needs forward stagger for two slots on the same ledge.
        let entryTime=max(rampIn+rampOut,nominalTimings.map(\.duration).reduce(0,+)/2)
        var routes:[CoordinatedFlightRoute]=[]
        for index in 0..<2 {
            // Solve the cosine-envelope integral for its plateau speed. A small
            // speed adjustment aligns entries without delays or stopping either
            // participant. Initial and final speeds remain fixed exactly.
            let plateau=(approaches[index].length-(velocities[index]*rampIn+speed*rampOut)/2) /
                (entryTime-(rampIn+rampOut)/2)
            guard plateau>=speed*0.65,plateau<=speedLimit,
                  let approachTiming=FlightTiming(distance:approaches[index].length,cruiseSpeed:plateau,
                    initialSpeed:velocities[index],finalSpeed:speed,rampIn:rampIn,rampOut:rampOut),
                  abs(approachTiming.duration-entryTime)<0.000001,
                  let middleTiming=FlightTiming(distance:middles[index].length,cruiseSpeed:speed,
                    initialSpeed:speed,finalSpeed:speed,rampIn:0,rampOut:0),
                  let exitTiming=FlightTiming(distance:exits[index].length,cruiseSpeed:speed,
                    initialSpeed:speed,finalSpeed:0,rampIn:0,rampOut:0.85),
                  gentle(approaches[index],direction:direction,peakSpeed:approachTiming.peakSpeed),
                  gentle(exits[index],direction:direction,peakSpeed:exitTiming.peakSpeed),
                  let route=CoordinatedFlightRoute(legs:[
                    CoordinatedFlightLeg(path:approaches[index],timing:approachTiming),
                    CoordinatedFlightLeg(path:middles[index],timing:middleTiming),
                    CoordinatedFlightLeg(path:exits[index],timing:exitTiming)
                  ]) else {return nil}
            routes.append(route)
        }
        guard let envelope=FlightSceneEnvelope(routes:routes,offsets:[0,0],scales:scales) else {return nil}
        let slots=participants.indices.map{LandingReservation(bird:participants[$0],host:hosts[$0],fraction:birds[$0].fraction)}
        let plan=TravelTogetherPlan(participants:participants,destinations:slots,hosts:hosts,scales:scales,
            routes:routes,initialFlights:flights,commonPath:commonPath,formationOffsets:offsets,
            commonDuration:commonDuration,display:display,screens:engine.world.screens,
            displays:engine.world.displays,worldScale:engine.world.scale,envelope:envelope)
        guard plan.commonOverlap>=1.8,plan.isSafe(in:engine),plan.pointerIsClear(in:engine),plan.canBegin(in:engine)
        else {return nil}
        return plan
    }
}

final class TravelTogetherExecution:BehaviorExecution {
    let plan:TravelTogetherPlan
    let source:BehaviorSource
    let kind:BehaviorKind = .travelTogether
    var participants:[BirdID] {plan.participants}
    var landingReservations:[LandingReservation] {plan.destinations}
    var timeout:Double {plan.duration+1.5}
    private var revisions:[BirdID:UInt64]=[:]
    private var age=0.0

    init(plan:TravelTogetherPlan,source:BehaviorSource) {self.plan=plan;self.source=source}
    func start(in engine:BehaviorEngine) {
        guard plan.isSafe(in:engine),plan.pointerIsClear(in:engine),plan.canBegin(in:engine) else {return}
        for (index,id) in participants.enumerated() {
            guard let bird=engine.bird(id),bird.beginCoordinatedFlight(plan.routes[index],on:plan.hosts[index],
                fraction:plan.destinations[index].fraction,spriteScale:plan.scales[index],delay:0,airborne:true)
            else {return}
            revisions[id]=bird.motionRevision
        }
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        // Quiet mode only closes the opportunity gate, never an active journey.
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:.preview)
        else {return .cancelled(.settingsChanged)}
        guard !engine.world.buttonsDown else {return .cancelled(.userInput)}
        for (index,id) in participants.enumerated() {
            guard let bird=engine.bird(id) else {return .failed(.missingBird)}
            guard TravelTogetherPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? [])
            else {return .failed(.missingFrames)}
            guard revisions[id]==bird.motionRevision,!bird.isDeparting,bird.edge == .top,
                  bird.hostID==plan.hosts[index].id,!bird.needsDestination,engine.role(of:bird) == .resident,
                  bird.isCoordinatedFlying,let flightAge=bird.coordinatedFlightAge,
                  abs(flightAge-min(age,plan.routes[index].duration))<0.000001,
                  Geometry.distance(bird.position,plan.position(of:index,at:age))<0.01
            else {return .failed(.targetInvalid)}
        }
        guard plan.isSafe(in:engine,after:age) else {return .failed(.targetInvalid)}
        guard plan.pointerIsClear(in:engine,after:age) else {return .cancelled(.pointerNearby)}
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        // Bird.tick integrates after runtime.advance; this age observes exactly
        // the previous tick, including the final landing animation of each bird.
        if participants.indices.allSatisfy({index in
            guard let bird=engine.bird(participants[index]) else {return false}
            return bird.state == .perched && (bird.coordinatedFlightAge ?? 0)+1e-9>=plan.routes[index].duration
        }) {
            for id in participants {engine.bird(id)?.finishCoordinatedFlight()}
            return .completed
        }
        age+=dt
        return nil
    }
    private func actualPerchIsValid(_ bird:Bird,in engine:BehaviorEngine) -> Bool {
        guard bird.state == .perched,bird.edge == .top,!bird.needsDestination,
              let id=engine.id(of:bird),let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}) else {return false}
        let slot=LandingReservation(bird:id,host:host,fraction:bird.fraction)
        return slot.isValid(in:engine) && slot.point(in:engine).map{Geometry.distance($0,bird.position)<0.001} == true
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        for id in participants {
            guard let revision=revisions[id],let bird=engine.bird(id),bird.motionRevision==revision,!bird.isDeparting
            else {continue}
            if actualPerchIsValid(bird,in:engine) {bird.finishCoordinatedFlight()}
            else {bird.requestFlightRecovery()}
        }
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard let revision=revisions[id],let bird=engine.bird(id),bird.motionRevision==revision,bird.state == .perched
        else {return nil}
        return BirdPose(frameName:"stand",hopOffset:0,facingRight:bird.facingRight)
    }
}
