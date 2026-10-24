import Foundation
import CoreGraphics

/// Engine validates before host tracking and resolves after the one Bird.tick.
/// Run age, deadline clipping and terminal events stay owned by Runtime.
protocol NestMotionExecution:BehaviorExecution {
    func reconcileWorld(in engine:BehaviorEngine,sampleDT:Double?) -> BehaviorCompletion?
    func resolveMotion(in engine:BehaviorEngine) -> BehaviorCompletion?
}

/// Uses the existing habitat route and timing, with an optional complete
/// bird/material footprint. There is no additional motion integrator.
struct NestVisitJourney {
    let route:CoordinatedFlightRoute
    let envelope:FlightSceneEnvelope

    static func make(from start:CGPoint,to end:CGPoint,display:CGRect,bird:Bird,
                     scale:CGFloat,localFootprint:CGRect) -> Self? {
        guard SurfaceAnchor.finite(localFootprint),
              let journey=HabitatJourney.make(from:start,to:end,display:display,scale:scale,profile:bird.profile),
              journey.route.legs.allSatisfy({leg in
                  let path=leg.path.bounds
                  return display.contains(CGRect(x:path.minX+localFootprint.minX,y:path.minY+localFootprint.minY,
                      width:path.width+localFootprint.width,height:path.height+localFootprint.height))
              }),let envelope=FlightSceneEnvelope(routes:[journey.route],offsets:[0],scales:[scale],
                  maximumDuration:30,localFootprints:[localFootprint]) else {return nil}
        return Self(route:journey.route,envelope:envelope)
    }
    func safe(in engine:BehaviorEngine,bird:BirdID,after age:Double=0) -> Bool {
        // Geometry above bounds actual content. Speed inflation protects
        // obstacles, and must not invent a second screen-bottom clearance.
        envelope.isClear(in:engine,excluding:[bird],display:nil,after:age) &&
            envelope.pointerIsClear(in:engine,after:age)
    }
}

struct NestVisitLanding {
    let host:Surface
    let fraction:CGFloat
    let foot:CGPoint
    let reservation:LandingReservation

    init?(bird:BirdID,foot:CGPoint,host:Surface,scale:CGFloat,localFootprint:CGRect?=nil) {
        let low=Geometry.perchX(0,rect:host.rect),high=Geometry.perchX(1,rect:host.rect)
        guard high>low,foot.x.isFinite,foot.y.isFinite,
              foot.x>=low-1e-6,foot.x<=high+1e-6 else {return nil}
        let fraction=min(1,max(0,(foot.x-low)/(high-low)))
        guard Geometry.distance(Geometry.foot(on:host,fraction:fraction,edge:.top,scale:scale),foot)<0.001 else {return nil}
        self.host=host;self.fraction=fraction;self.foot=foot
        reservation=LandingReservation(bird:bird,host:host,fraction:fraction,localFootprint:localFootprint)
    }
    func valid(in engine:BehaviorEngine) -> Bool {
        engine.world.surfaces.contains(host) && reservation.isValid(in:engine) &&
            reservation.point(in:engine).map{Geometry.distance($0,foot)<0.001} == true
    }
}

enum NestVisitGeometry {
    static let carryTimeout=35.0
    static let buildTimeout=30.0
    static let landingBudget=0.5
    static let exitSettle=0.2

    static func ordinaryResident(_ bird:Bird,in engine:BehaviorEngine) -> Surface? {
        guard bird.profile.id == .spottedDove,engine.role(of:bird) == .resident,
              engine.birds.contains(where:{$0 === bird}),bird.state == .perched,bird.edge == .top,
              bird.stateTime+1e-9>=exitSettle,!bird.isDeparting,!bird.needsDestination,
              !bird.isSideHopping,!bird.isCoordinatedFlying,
              bird.fraction.isFinite,(0...1).contains(bird.fraction),
              let id=engine.id(of:bird),abs(engine.baseHop(for:id,bird:bird))<0.001,
              let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
              !host.isHabitat,host.isGround || host.layer==0,engine.hasUsablePerch(bird),
              Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,
                  scale:engine.spriteScale(for:bird)))<0.001 else {return nil}
        return host
    }
    static func slotsClear(_ slots:[LandingReservation],in engine:BehaviorEngine,bird:BirdID) -> Bool {
        guard slots.allSatisfy({$0.isValid(in:engine)}) else {return false}
        for (index,slot) in slots.enumerated() {
            guard let area=slot.footprint(in:engine),
                  !slots.dropFirst(index+1).contains(where:{slot.conflicts(with:$0,in:engine)}),
                  !engine.runtime.landingReservations.contains(where:{$0.bird != bird && slot.conflicts(with:$0,in:engine)}),
                  !engine.birds.contains(where:{engine.id(of:$0) != bird && engine.bounds(of:$0).intersects(area)}) else {return false}
        }
        return true
    }
    static func stationaryClear(_ landing:NestVisitLanding,localFootprint:CGRect,
                                in engine:BehaviorEngine,bird:BirdID,display:CGRect) -> Bool {
        let body=localFootprint.offsetBy(dx:landing.foot.x,dy:landing.foot.y)
        let blockerHost:Surface
        if landing.host.habitatKind == .nest {
            // Habitat ledges alone only see utility panels. The real parent
            // also supplies ordinary foreground windows, including ones that
            // cover a future head/twig without intersecting the platform art.
            guard let object=engine.habitatObjects.objects.values.first(where:{$0.kind == .nest && $0.surface==landing.host}),
                  let parent=object.nest?.parentAnchor.host(in:engine.world) else {return false}
            blockerHost=parent
        } else {blockerHost=landing.host}
        guard landing.valid(in:engine),display.contains(body),
              !Geometry.blockers(on:blockerHost,surfaces:engine.world.surfaces).contains(where:{$0.rect.intersects(body)}),
              !engine.giftObstacleRects(excluding:[bird]).contains(where:{$0.intersects(body)}) else {return false}
        for other in engine.birds where engine.id(of:other) != bird {
            if engine.bounds(of:other).intersects(body) {return false}
            if other.state == .flying {
                guard let area=other.plannedFlightFootprint(scale:engine.spriteScale(for:other)),!area.intersects(body) else {return false}
            }
        }
        guard let model=engine.bird(bird) else {return false}
        let radius=max(100,72*engine.spriteScale(for:model)),p=engine.world.pointer
        return p.x.isFinite && p.y.isFinite &&
            !body.intersects(CGRect(x:p.x-radius,y:p.y-radius,width:2*radius,height:2*radius))
    }
    /// Prefer the actual starting slot, then a finite stable set of ordinary
    /// destinations. A return candidate never includes another scene host.
    static func exits(for bird:Bird,origin:Surface,in engine:BehaviorEngine) -> [NestVisitLanding] {
        guard let id=engine.id(of:bird) else {return []}
        let scale=engine.spriteScale(for:bird)
        let hosts=engine.world.surfaces.filter{!$0.isHabitat && ($0.isGround || $0.layer==0)}.sorted {
            if ($0.id==origin.id && $0.pid==origin.pid) != ($1.id==origin.id && $1.pid==origin.pid) {
                return $0.id==origin.id && $0.pid==origin.pid
            }
            return $0.id==$1.id ? $0.pid<$1.pid:$0.id<$1.id
        }
        var result:[NestVisitLanding]=[]
        for host in hosts.prefix(16) {
            var fractions:[CGFloat]=host==origin ? [bird.fraction]:[]
            for value in [CGFloat(0.25),0.5,0.75] where !fractions.contains(value) {fractions.append(value)}
            for fraction in fractions {
                let foot=Geometry.foot(on:host,fraction:fraction,edge:.top,scale:scale)
                if let slot=NestVisitLanding(bird:id,foot:foot,host:host,scale:scale) {result.append(slot)}
            }
        }
        return result
    }
}

/// One frozen, preflighted visit. Ledger mutations never change these endpoints.
/// A moved/reused host cancels before updateHost can translate the bird's foot.
struct NestVisitSchedule {
    let id:BirdID
    let kind:BehaviorKind
    let object:HabitatObject
    let materialID:ScenePropID
    let materialSlot:Int
    let origin:Surface
    let originFoot:CGPoint
    let initialRevision:UInt64
    let scale:CGFloat
    let localFootprint:CGRect
    let facingRight:Bool
    let first:NestVisitLanding
    let destination:NestVisitLanding
    let exit:NestVisitLanding
    let approach:NestVisitJourney
    let carrying:NestVisitJourney?
    let departure:NestVisitJourney
    let pickupClip:PoseClip?
    let workClip:PoseClip
    let displayIDs:[String]
    var isCarry:Bool {kind == .nestMaterialCarry}
    var timeout:Double {isCarry ? NestVisitGeometry.carryTimeout:NestVisitGeometry.buildTimeout}
    var slots:[LandingReservation] {
        isCarry ? [first.reservation,destination.reservation,exit.reservation]:[destination.reservation,exit.reservation]
    }
    var maximumPlannedDuration:Double {
        approach.route.duration+(carrying?.route.duration ?? 0)+departure.route.duration +
            (pickupClip?.duration ?? 0)+workClip.duration+(isCarry ? 3.0:2.0)*NestVisitGeometry.landingBudget+0.5
    }
    var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:kind).requiredFrames}

    func geometryValid(in engine:BehaviorEngine) -> Bool {
        guard let current=engine.habitatObjects.objects[object.id],let oldNest=object.nest,let nest=current.nest,
              current.kind == .nest,!current.retiring,current.remainingLifetime>0,
              current.rect==object.rect,current.surface==object.surface,nest.host==oldNest.host,
              nest.trayRect==oldNest.trayRect,nest.parentAnchor==oldNest.parentAnchor,
              engine.world.scale==object.scale,engine.world.screens==object.screens,
              engine.world.displays==object.displays,engine.world.displayIDs==displayIDs,
              engine.world.surfaces.contains(oldNest.host),engine.world.surfaces.contains(origin),
              engine.habitatObjects.isNestValid(current,in:engine),
              let bird=engine.bird(id),engine.spriteScale(for:bird)==scale,
              NestVisitGeometry.slotsClear(slots,in:engine,bird:id),
              NestVisitGeometry.stationaryClear(destination,localFootprint:localFootprint,
                  in:engine,bird:id,display:object.display),
              NestVisitGeometry.stationaryClear(exit,localFootprint:Geometry.landingFootprint(at:.zero,scale:scale),
                  in:engine,bird:id,display:object.display) else {return false}
        return !isCarry || NestVisitGeometry.stationaryClear(first,localFootprint:localFootprint,
            in:engine,bird:id,display:object.display)
    }
    /// Runtime has already registered this run's leases when start calls here.
    /// Do not repeat owner/cooldown/quiet admission checks inside this function.
    func canBegin(in engine:BehaviorEngine) -> Bool {
        guard engine.settings.nestBuildingEnabled,engine.world.nestArtAvailable,
              engine.settings.probabilities.entries.contains(where:{$0.id == .spottedDove && $0.points>0}),
              let bird=engine.bird(id),bird.motionRevision==initialRevision,
              engine.runtime.owners[id]==nil || engine.runtime.kind(for:id)==kind,
              NestVisitGeometry.ordinaryResident(bird,in:engine)==origin,bird.position==originFoot,
              requiredFrames.isSubset(of:engine.world.availableFrames[.spottedDove] ?? []),
              let current=engine.habitatObjects.objects[object.id],let nest=current.nest,
              nest.reservation==nil,let material=nest.materials.first(where:{$0.id==materialID}),
              material.state == (isCarry ? .available:.delivered),
              current.remainingLifetime+1e-9>=maximumPlannedDuration,
              maximumPlannedDuration<=timeout,geometryValid(in:engine),
              approach.safe(in:engine,bird:id),carrying?.safe(in:engine,bird:id) ?? true,
              departure.safe(in:engine,bird:id) else {return false}
        return bird.canBeginCoordinatedFlight(approach.route,on:first.host,fraction:first.fraction,
            spriteScale:scale,allowExpiredPerch:true)
    }

    static func candidates(in engine:BehaviorEngine,source:BehaviorSource,kind:BehaviorKind,
                           target:HabitatObjectID?) -> [Self] {
        guard !engine.paused,!engine.world.buttonsDown,!engine.ambientBusy,
              engine.settings.nestBuildingEnabled,engine.world.nestArtAvailable,
              engine.settings.probabilities.entries.contains(where:{$0.id == .spottedDove && $0.points>0}),
              BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:source),
              source != .automatic || (engine.ambientEnabled && engine.settings.activityRhythm != .quiet)
        else {return []}
        let isCarry=kind == .nestMaterialCarry
        let objects=engine.habitatObjects.objects.values.filter {
            $0.kind == .nest && !$0.retiring && (target==nil || target==$0.id) &&
                $0.nest?.reservation==nil && !engine.runtime.habitatReservations.contains($0.id)
        }.sorted{$0.id<$1.id}
        let required=BehaviorDefinitions.definition(for:kind).requiredFrames
        let birds=engine.birds.filter {bird in
            guard let id=engine.id(of:bird),engine.runtime.owners[id]==nil,
                  ordinaryOrigin(bird,in:engine) != nil,
                  required.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return false}
            return source != .automatic || engine.perchPlanner.automaticWeight(id,kind:kind)>0
        }.sorted{(engine.id(of:$0)?.rawValue ?? 0)<(engine.id(of:$1)?.rawValue ?? 0)}
        var result:[Self]=[]
        for bird in birds {
            guard let id=engine.id(of:bird),let origin=ordinaryOrigin(bird,in:engine),
                  let work=isCarry ? PoseClip.nestMaterialPlace(species:.spottedDove):PoseClip.nestBuild(species:.spottedDove)
            else {continue}
            let pickup=isCarry ? PoseClip.nestMaterialPickup(species:.spottedDove):nil
            if isCarry && pickup==nil {continue}
            let scale=engine.spriteScale(for:bird),body=Geometry.landingFootprint(at:.zero,scale:scale)
            guard let union=materialFootprint(birdScale:scale,worldScale:engine.world.scale) else {continue}
            let local=isCarry ? union:body
            for object in objects {
                guard let nest=object.nest,engine.habitatObjects.isNestValid(object,in:engine) else {continue}
                let facing=isCarry ? nest.traySide<0:object.foot.x>=bird.position.x
                for material in nest.materials.sorted(by:{$0.id<$1.id}) where material.state == (isCarry ? .available:.delivered) {
                    guard let endPoint=NestGeometry.materialPoint(slot:material.slot,rect:object.rect,scale:object.scale),
                          let end=contactFoot(point:endPoint,birdScale:scale,worldScale:object.scale,facingRight:facing,
                              frame:isCarry ? "carryPlace":"nestSettle"),
                          let destination=NestVisitLanding(bird:id,foot:end,host:object.surface,scale:scale,localFootprint:local),
                          let startPoint=NestGeometry.trayMaterialPoint(slot:material.slot,rect:nest.trayRect,scale:object.scale),
                          let start=contactFoot(point:startPoint,birdScale:scale,worldScale:object.scale,facingRight:facing),
                          let first=isCarry ? NestVisitLanding(bird:id,foot:start,host:object.surface,scale:scale,localFootprint:local):destination,
                          let approach=NestVisitJourney.make(from:bird.position,to:first.foot,display:object.display,
                              bird:bird,scale:scale,localFootprint:local) else {continue}
                    let carrying=isCarry ? NestVisitJourney.make(from:first.foot,to:destination.foot,display:object.display,
                        bird:bird,scale:scale,localFootprint:local):nil
                    if isCarry && carrying==nil {continue}
                    for exit in NestVisitGeometry.exits(for:bird,origin:origin,in:engine) {
                        guard let departure=NestVisitJourney.make(from:destination.foot,to:exit.foot,display:object.display,
                            bird:bird,scale:scale,localFootprint:body) else {continue}
                        let visit=Self(id:id,kind:kind,object:object,materialID:material.id,materialSlot:material.slot,
                            origin:origin,originFoot:bird.position,initialRevision:bird.motionRevision,scale:scale,
                            localFootprint:local,facingRight:facing,first:first,destination:destination,exit:exit,
                            approach:approach,carrying:carrying,departure:departure,pickupClip:pickup,workClip:work,
                            displayIDs:engine.world.displayIDs)
                        if visit.canBegin(in:engine) {result.append(visit);break}
                    }
                }
            }
        }
        return result
    }
    private static func ordinaryOrigin(_ bird:Bird,in engine:BehaviorEngine)->Surface? {
        NestVisitGeometry.ordinaryResident(bird,in:engine)
    }
    static func contactFoot(point:CGPoint,birdScale:CGFloat,worldScale:CGFloat,facingRight:Bool,
                            frame:String="carryGrip")->CGPoint? {
        guard let grip=TwigGeometry.gripPoint(surfacePoint:point,worldScale:worldScale,facingRight:facingRight),
              let anchor=PoseClip.nestBeakAnchor(species:.spottedDove,frame:frame) else {return nil}
        let offset=anchor.world(foot:.zero,scale:birdScale,facingRight:facingRight)
        return CGPoint(x:grip.x-offset.x,y:grip.y-offset.y)
    }
    /// Includes authored ordinary flight/landing frames and both actual headings.
    /// The twig is currently held at zero angle; enumerate exact rotated corner
    /// extrema rather than replacing the eccentric grip by a 48px bird box.
    static func materialFootprint(birdScale:CGFloat,worldScale:CGFloat)->CGRect? {
        let frames=NestArtGeometry.carryFrameNames+NestArtGeometry.transportFrameNames
        var result=Geometry.landingFootprint(at:.zero,scale:birdScale)
        for frame in frames {
            guard let anchor=PoseClip.nestBeakAnchor(species:.spottedDove,frame:frame) else {return nil}
            for facing in [true,false] {
                let point=anchor.world(foot:.zero,scale:birdScale,facingRight:facing)
                guard let area=TwigGeometry.sweptCanvasBounds(position:point,worldScale:worldScale,
                    facingRight:facing,rotationRange:0...0) else {return nil}
                result=result.union(area)
            }
        }
        return SurfaceAnchor.finite(result) ? result:nil
    }
}
