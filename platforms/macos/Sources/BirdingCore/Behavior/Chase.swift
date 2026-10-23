import Foundation
import CoreGraphics

public enum ChaseBehavior {
    public static let supportedSpecies:Set<SpeciesID> = [
        .treeSparrow,.barnSwallow,.swinhoesWhiteEye,.lightVentedBulbul,
        .azureWingedMagpie,.blackCollaredStarling
    ]
}

/// Two existing residents use the SAME closed path and speed. Their different
/// entry times provide the phase offset; the paths are never translated copies.
struct ChasePlan {
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.chase).requiredFrames}
    static var supportedSpecies:Set<SpeciesID> {ChaseBehavior.supportedSpecies}
    let participants:[BirdID]
    let destinations:[LandingReservation]
    let hosts:[Surface]
    let scales:[CGFloat]
    let routes:[CoordinatedFlightRoute]
    let launchOffsets:[Double]
    let loop:FlightPath
    let loopDuration:Double
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]
    let worldScale:CGFloat
    private let sweeps:[Sweep]

    private struct Sweep {
        let end:Double
        let areas:[CGRect]
    }
    var duration:Double {zip(launchOffsets,routes).map{$0.0+$0.1.duration}.max() ?? 0}
    var loopEntries:[Double] {
        routes.indices.map{launchOffsets[$0]+routes[$0].legs[0].timing.duration}
    }
    func position(of index:Int,at age:Double) -> CGPoint {
        routes[index].position(at:max(0,age-launchOffsets[index]))
    }
    private static func intersects(_ a:CGRect,_ b:CGRect) -> Bool {
        let cut=a.intersection(b);return !cut.isNull && !cut.isEmpty
    }

    /// Every midpoint envelope contains ALL positions in its time interval:
    /// arc-length speed is bounded by peakSpeed, so speed * halfInterval is a
    /// conservative displacement bound even across a curve/leg/launch boundary.
    private static func makeSweeps(routes:[CoordinatedFlightRoute],offsets:[Double],scales:[CGFloat]) -> [Sweep]? {
        let duration=zip(offsets,routes).map{$0.0+$0.1.duration}.max() ?? 0
        guard duration.isFinite,duration>0,duration<=20 else {return nil}
        let count=Int(ceil(duration*30)),dt=duration/Double(count)
        let speeds=routes.map{$0.legs.map{$0.timing.peakSpeed}.max() ?? 0}
        var result:[Sweep]=[]
        for index in 0..<count {
            let mid=(Double(index)+0.5)*dt
            let areas=routes.indices.map {actor -> CGRect in
                let foot=routes[actor].position(at:max(0,mid-offsets[actor]))
                let margin=CGFloat(speeds[actor]*dt/2)+4
                return Geometry.landingFootprint(at:foot,scale:scales[actor]).insetBy(dx:-margin,dy:-margin)
            }
            guard !intersects(areas[0],areas[1]) else {return nil}
            result.append(Sweep(end:Double(index+1)*dt,areas:areas))
        }
        return result
    }

    func pointerIsClear(in engine:BehaviorEngine,after age:Double=0) -> Bool {
        let pointer=engine.world.pointer
        guard pointer.x.isFinite,pointer.y.isFinite else {return false}
        let radius=max(100,72*(scales.max() ?? 1))
        let protected=CGRect(x:pointer.x-radius,y:pointer.y-radius,width:2*radius,height:2*radius)
        let from=min(age,duration)
        return !sweeps.contains{$0.end+1e-9>=from && $0.areas.contains{Self.intersects($0,protected)}}
    }

    func isSafe(in engine:BehaviorEngine,after age:Double=0) -> Bool {
        guard engine.world.screens==screens,engine.world.displays==displays,
              engine.world.scale==worldScale,engine.world.displays.contains(display) else {return false}
        for index in participants.indices {
            guard let bird=engine.bird(participants[index]),engine.spriteScale(for:bird)==scales[index],
                  destinations[index].host(in:engine)==hosts[index],destinations[index].isValid(in:engine) else {return false}
        }
        guard !destinations[0].conflicts(with:destinations[1],in:engine) else {return false}
        let ids=Set(participants)
        // Flying overlays pass over ordinary windows; utility panels still block.
        var obstacles=engine.world.surfaces.filter{!$0.isGround && $0.layer>0}.map(\.rect)
        for other in engine.birds where engine.id(of:other).map({!ids.contains($0)}) == true {
            let scale=engine.spriteScale(for:other)
            let speed=max(other.flightSpeed,FlightBehavior.cruiseSpeed(other.profile.id,multiplier:other.profile.speed))
            let margin:CGFloat=8+(other.state == .flying ? CGFloat(speed*BehaviorEngine.step):0)
            obstacles.append(Geometry.landingFootprint(at:other.position,scale:scale)
                .union(engine.bounds(of:other)).insetBy(dx:-margin,dy:-margin))
            if other.state == .flying {
                guard let planned=other.plannedFlightFootprint(scale:scale) else {return false}
                obstacles.append(planned.insetBy(dx:-8,dy:-8))
            }
            if let host=engine.world.surfaces.first(where:{$0.id==other.hostID}) {
                let foot=Geometry.foot(on:host,fraction:other.fraction,edge:other.edge,scale:scale)
                obstacles.append(Geometry.landingFootprint(at:foot,scale:scale).insetBy(dx:-8,dy:-8))
            }
        }
        for slot in engine.runtime.landingReservations where !ids.contains(slot.bird) {
            guard let area=slot.footprint(in:engine) else {return false}
            obstacles.append(area)
        }
        for sweep in sweeps where sweep.end+1e-9>=min(age,duration) {
            for area in sweep.areas {
                guard display.contains(area),!obstacles.contains(where:{Self.intersects(area,$0)}) else {return false}
            }
        }
        return true
    }

    static func candidates(in engine:BehaviorEngine,source:BehaviorSource = .automatic) -> [ChasePlan] {
        guard !engine.paused,!engine.world.buttonsDown,engine.world.scale.isFinite,engine.world.scale>0,
              BehaviorDefinitions.definition(for:.chase).isEnabled(settings:engine.settings,source:source) else {return []}
        // Bound both enumeration and expensive continuous path probes. No RNG,
        // leases, allocations of birds, or input mutation during planning.
        let ids=engine.birds.compactMap {bird -> BirdID? in
            guard let id=engine.id(of:bird),engine.role(of:bird) == .resident,
                  supportedSpecies.contains(bird.profile.id),engine.runtime.owners[id]==nil,
                  bird.state == .perched,bird.edge == .top,bird.stateTime+1e-9>=0.5,
                  !bird.isDeparting,!bird.needsDestination,bird.perchDuration-bird.stateTime>8,
                  abs(engine.baseHop(for:id,bird:bird))<0.001,
                  requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
                  engine.hasUsablePerch(bird),!engine.pointerNear(bird),
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}),
                  host.isGround || host.layer==0,
                  Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,
                      scale:engine.spriteScale(for:bird)))<0.001 else {return nil}
            if source == .automatic {
                guard let ecology=engine.perchPlanner.ecology(id),ecology.disturbance<0.35,ecology.quietTime>=4,
                      engine.perchPlanner.automaticWeight(id,kind:.chase)>0 else {return nil}
            }
            return id
        }.sorted().prefix(16)
        var result:[ChasePlan]=[],pairs=0,probes=0
        for (offset,first) in ids.enumerated() {
            for second in ids.dropFirst(offset+1) {
                guard pairs<12,probes<24,result.count<4 else {return result}
                guard let a=engine.bird(first),let b=engine.bird(second),a.profile.id==b.profile.id else {continue}
                pairs+=1
                let scales=[engine.spriteScale(for:a),engine.spriteScale(for:b)]
                guard scales.allSatisfy({$0.isFinite && $0>0}),
                      Geometry.distance(a.position,b.position)<=700*(scales.max() ?? 1),
                      let display=engine.world.displays.first(where:{rect in
                          rect.contains(Geometry.landingFootprint(at:a.position,scale:scales[0])) &&
                          rect.contains(Geometry.landingFootprint(at:b.position,scale:scales[1]))
                      }) else {continue}
                // Species sizes, screen offsets, and both turning directions use
                // the same planner. Smaller loops are preferred, never clamped.
                for size:CGFloat in [180,220,270] {
                    for direction:CGFloat in [1,-1] {
                        for lag in [0.65,0.9] {
                            guard probes<24,result.count<4 else {return result}
                            probes+=1
                            if let plan=make(participants:[first,second],scales:scales,display:display,
                                radius:size,direction:direction,lag:lag,in:engine) {result.append(plan)}
                        }
                    }
                }
            }
        }
        return result
    }

    private static func make(participants:[BirdID],scales:[CGFloat],display:CGRect,
                             radius:CGFloat,direction:CGFloat,lag:Double,in engine:BehaviorEngine) -> ChasePlan? {
        let birds=participants.compactMap{engine.bird($0)}
        let hosts=birds.compactMap{bird in engine.world.surfaces.first{$0.id==bird.hostID}}
        guard birds.count==2,hosts.count==2 else {return nil}
        let size=scales.max() ?? 1,rx=radius*size,ry=radius*0.55*size
        let center=CGPoint(x:(birds[0].position.x+birds[1].position.x)/2,
                           y:min(birds[0].position.y,birds[1].position.y)-110*size-ry)
        let entry=CGPoint(x:center.x,y:center.y+ry)
        var points=(0..<512).map {index -> CGPoint in
            let theta=Double.pi/2-Double(direction)*2*Double.pi*Double(index)/512
            return CGPoint(x:center.x+rx*CGFloat(cos(theta)),y:center.y+ry*CGFloat(sin(theta)))
        }
        points[0]=entry;points.append(entry)
        let loop=FlightPath(points:points),loopDuration=4.2,speed=loop.length/loopDuration
        let ring=CoordinatedFlightLeg(path:loop,timing:FlightTiming(distance:loop.length,speed:speed,acceleration:0,deceleration:0))
        var routes:[CoordinatedFlightRoute]=[]
        for bird in birds {
            let foot=bird.position,bend=ry*0.8
            let perchControl=CGPoint(x:foot.x,y:foot.y-max(40*size,(foot.y-entry.y)*0.55))
            let approach=FlightPath(foot,perchControl,CGPoint(x:entry.x-direction*bend,y:entry.y),entry)
            let exit=FlightPath(entry,CGPoint(x:entry.x+direction*bend,y:entry.y),perchControl,foot)
            let approachTiming=FlightTiming(distance:approach.length,speed:speed,
                acceleration:min(0.45,1.8*approach.length/speed),deceleration:0)
            let exitTiming=FlightTiming(distance:exit.length,speed:speed,
                acceleration:0,deceleration:min(0.55,1.8*exit.length/speed))
            guard let route=CoordinatedFlightRoute(legs:[
                CoordinatedFlightLeg(path:approach,timing:approachTiming),ring,
                CoordinatedFlightLeg(path:exit,timing:exitTiming)
            ]) else {return nil}
            routes.append(route)
        }
        let delay=lag+routes[0].legs[0].timing.duration-routes[1].legs[0].timing.duration
        // Align starts to the engine's fixed clock, never advance a second clock
        // inside Bird or lose dt when the runtime installs a route before tick.
        let stagger=(delay/BehaviorEngine.step).rounded()*BehaviorEngine.step
        guard stagger>=0.2,stagger<=1.5 else {return nil}
        let offsets=[0.3,0.3+stagger]
        let actualLag=offsets[1]+routes[1].legs[0].timing.duration-offsets[0]-routes[0].legs[0].timing.duration
        guard actualLag>0,loopDuration-actualLag>=3,
              let sweeps=makeSweeps(routes:routes,offsets:offsets,scales:scales) else {return nil}
        let slots=zip(participants,zip(hosts,birds)).map {
            LandingReservation(bird:$0.0,host:$0.1.0,fraction:$0.1.1.fraction)
        }
        let plan=ChasePlan(participants:participants,destinations:slots,hosts:hosts,scales:scales,
            routes:routes,launchOffsets:offsets,loop:loop,loopDuration:loopDuration,display:display,
            screens:engine.world.screens,displays:engine.world.displays,worldScale:engine.world.scale,sweeps:sweeps)
        return plan.isSafe(in:engine) && plan.pointerIsClear(in:engine) ? plan:nil
    }
}

final class ChaseExecution:BehaviorExecution {
    let plan:ChasePlan
    let source:BehaviorSource
    let kind:BehaviorKind = .chase
    var participants:[BirdID] {plan.participants}
    var landingReservations:[LandingReservation] {plan.destinations}
    var timeout:Double {plan.duration+1.5}
    private struct Actor {let revision:UInt64}
    private var actors:[BirdID:Actor]=[:]
    private var age=0.0

    init(plan:ChasePlan,source:BehaviorSource) {self.plan=plan;self.source=source}
    func start(in engine:BehaviorEngine) {
        for (index,id) in participants.enumerated() {
            guard let bird=engine.bird(id),
                  bird.beginCoordinatedFlight(plan.routes[index],on:plan.hosts[index],
                      fraction:plan.destinations[index].fraction,spriteScale:plan.scales[index],
                      delay:plan.launchOffsets[index]) else {continue}
            actors[id]=Actor(revision:bird.motionRevision)
        }
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        // Quiet rhythm stops new automatic opportunities, not a scene in flight.
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:.preview) else {return .cancelled(.settingsChanged)}
        guard !engine.world.buttonsDown else {return .cancelled(.userInput)}
        for (index,id) in participants.enumerated() {
            guard let bird=engine.bird(id) else {return .failed(.missingBird)}
            guard ChasePlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
            guard let actor=actors[id],actor.revision==bird.motionRevision,!bird.isDeparting,
                  bird.edge == .top,bird.hostID==plan.hosts[index].id,!bird.needsDestination,
                  engine.role(of:bird) == .resident,
                  Geometry.distance(bird.position,plan.position(of:index,at:age))<0.01,
                  bird.isCoordinatedFlying else {return .failed(.targetInvalid)}
        }
        guard plan.isSafe(in:engine,after:age) else {return .failed(.targetInvalid)}
        guard plan.pointerIsClear(in:engine,after:age) else {return .cancelled(.pointerNearby)}
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        // Both delayed routes are already armed. Bird.tick owns the complete
        // wait/flight/landing clock; this age observes the previous integrated tick.
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
            guard let actor=actors[id],let bird=engine.bird(id),bird.motionRevision==actor.revision,!bird.isDeparting else {continue}
            if actualPerchIsValid(bird,in:engine) {bird.finishCoordinatedFlight();continue}
            bird.requestFlightRecovery()
        }
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard let actor=actors[id],let bird=engine.bird(id),bird.motionRevision==actor.revision,
              bird.state == .perched else {return nil}
        return BirdPose(frameName:"stand",hopOffset:0,facingRight:bird.facingRight)
    }
}
