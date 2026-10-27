import Foundation
import CoreGraphics

/// Objects outlive individual visits. The runtime leases their slots; the store
/// only owns placement, remaining resources and the simulation-time lifetime.
public struct HabitatObjectID:Hashable,Codable,Comparable {
    public let rawValue:UInt64
    public init(_ value:UInt64) {rawValue=value}
    public static func < (a:Self,b:Self)->Bool {a.rawValue<b.rawValue}
}
public enum HabitatObjectKind:String,Codable {case foodTray,bath,nest}
public struct HabitatObjectRenderState {
    public let id:HabitatObjectID
    public let kind:HabitatObjectKind
    /// Asset bounds; the bath's fixed foot is on its internal waterline.
    public let rect:CGRect
    public let blockers:[CGRect]
    public let remainingUses:Int
    public let retiring:Bool
    public let remainingLifetime:Double
}
struct HabitatObject {
    let id:HabitatObjectID
    let kind:HabitatObjectKind
    var rect:CGRect
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]
    let scale:CGFloat
    var surface:Surface
    var remainingUses:Int
    var remainingLifetime:Double
    var retirementAge:Double?=nil
    var retirementReason:BehaviorReason?=nil
    var completedVisitRuns:Set<UInt64>=[]
    var persistentID:UUID?=nil
    var nest:NestState?=nil
    var retiring:Bool {retirementReason != nil || (persistentID == nil && kind != .nest && remainingUses<=0) || remainingLifetime<=0}
    var foot:CGPoint {
        if kind == .nest {return CGPoint(x:rect.midX,y:rect.minY+NestGeometry.contactY*scale)}
        return kind == .bath ? BathGeometry.foot(in:rect,scale:scale):CGPoint(x:rect.midX,y:rect.minY)
    }
}
final class HabitatObjectStore {
    var objects:[HabitatObjectID:HabitatObject]=[:]
    var nextID:UInt64=1
    var commitResource:((UUID,SceneResource)->Bool)?
    private func authorize(_ object:HabitatObject)->Bool {
        guard let id=object.persistentID else {return true}
        var resource=SceneResource(kind:object.kind == .nest ? .nest:object.kind == .bath ? .bath:.foodTray)
        resource.remainingUses=object.remainingUses;resource.materials=object.nest?.materials.map(\.state) ?? []
        return commitResource?(id,resource) ?? false
    }
    static let foodLifetime=180.0
    static let foodPortions=3
    static let bathLifetime=300.0
    static let bathVisits=3
    static let nestLifetime=900.0
    static let nestSurfaceID:UInt32=0xFE000003
    static let retirementLimit=2.0
    var retiringIDs:[HabitatObjectID] {objects.keys.sorted().filter{objects[$0]?.retiring == true}}
    var removalDueIDs:[HabitatObjectID] {
        retiringIDs.filter{(objects[$0]?.retirementAge ?? 0)+1e-10>=Self.retirementLimit}
    }

    func placeFood(at point:CGPoint,in engine:BehaviorEngine)->Bool {
        let world=engine.world,scale=world.scale
        guard (engine.settings.companion != nil ? objects.count<3:objects.isEmpty),scale.isFinite,scale>0,point.x.isFinite,point.y.isFinite,
              world.foodTrayArtAvailable,engine.settings.foodTrayEnabled,
              let display=world.displays.first(where:{$0.contains(point)}) else {return false}
        let rect=CGRect(x:point.x-64*scale,y:point.y,width:128*scale,height:24*scale)
        let maxBirdScale=FoodTrayBehavior.supportedSpecies.map{engine.settings.catalog.profile($0).relativeScale}.max() ?? 1
        let clearance=rect.union(Geometry.landingFootprint(at:point,scale:scale*maxBirdScale)).insetBy(dx:-8,dy:-8)
        guard display.contains(clearance),world.screens.contains(where:{$0.contains(clearance)}),
              !world.surfaces.contains(where:{$0.layer>0 && $0.rect.intersects(clearance)}),
              !engine.fixedPerchSnapshot().contains(where:{$0.rect.insetBy(dx:-50*scale,dy:-80*scale).intersects(clearance)}),
              !engine.birds.contains(where:{engine.bounds(of:$0).intersects(clearance)}),
              !engine.runtime.landingReservations.contains(where:{$0.footprint(in:engine)?.intersects(clearance) ?? true}),
              !objects.values.contains(where:{$0.rect.insetBy(dx:-16,dy:-48).intersects(clearance)}) else {return false}
        let id=HabitatObjectID(nextID);nextID+=1
        let surface=Surface(id:engine.settings.companion == nil ? Self.surfaceID:0xFE100000+UInt32(id.rawValue),pid:Int32.min+19,
            rect:CGRect(x:point.x-64*scale,y:point.y,width:128*scale,height:1),habitatKind:.foodTray)
        objects[id]=HabitatObject(id:id,kind:.foodTray,rect:rect,display:display,screens:world.screens,
            displays:world.displays,scale:scale,surface:surface,remainingUses:Self.foodPortions,remainingLifetime:Self.foodLifetime)
        return true
    }
    static let surfaceID:UInt32=0xFE000001
    static let bathSurfaceID:UInt32=0xFE000002
    func placeNest(at point:CGPoint,materialIDs:[ScenePropID],in engine:BehaviorEngine)->BehaviorResult {
        let world=engine.world,scale=world.scale
        guard !engine.paused else {return .rejected(.paused)}
        guard engine.settings.nestBuildingEnabled else {return .rejected(.disabled)}
        guard world.nestArtAvailable else {return .rejected(.missingFrames)}
        guard !world.buttonsDown else {return .rejected(.userInput)}
        guard (engine.settings.companion != nil ? objects.count<3:objects.isEmpty) else {return .rejected(.busy)}
        guard materialIDs.count==3,Set(materialIDs).count==3,materialIDs.allSatisfy({$0.rawValue>0}),
              !materialIDs.contains(where:{engine.runtime.propIDs.contains($0) || engine.carriedObjects.objects[$0] != nil}),
              !engine.propSnapshot().contains(where:{materialIDs.contains($0.id)}),
              (engine.settings.companion != nil || !world.surfaces.contains(where:{$0.id==Self.nestSurfaceID})) else {return .rejected(.busy)}
        guard scale.isFinite,scale>0 else {return .rejected(.noSpace)}
        let birdScale=scale*CGFloat(engine.settings.catalog.profile(.spottedDove).relativeScale)
        let groundScale=max(birdScale,(NestGeometry.size.height-NestGeometry.contactY)*scale/9)
        guard let anchor=SurfaceAnchor.placement(at:point,in:world,groundScale:groundScale),
              let host=anchor.host(in:world),let foot=anchor.point(in:world) else {return .rejected(.noSpace)}
        let rect=NestGeometry.rect(foot:foot,scale:scale)
        for side in [-1,1] {
            let tray=NestGeometry.trayRect(foot:foot,scale:scale,side:side)
            let area=NestGeometry.clearance(nest:rect,tray:tray,worldScale:scale,birdScale:birdScale)
            guard let display=world.displays.first(where:{$0.contains(area)}),
                  NestGeometry.supported(foot:foot,nest:rect,tray:tray,host:host,world:world,display:display),
                  let support=NestGeometry.supportSurfaceRect(foot:foot,nest:rect,tray:tray,host:host,
                      worldScale:scale,birdScale:birdScale),
                  !Geometry.blockers(on:host,surfaces:world.surfaces).contains(where:{$0.rect.intersects(area)}),
                  !engine.fixedPerchSnapshot().contains(where:{$0.rect.insetBy(dx:-50*scale,dy:-80*scale).intersects(area)}),
                  !engine.birds.contains(where:{engine.bounds(of:$0).intersects(area)}),
                  !engine.runtime.landingReservations.contains(where:{$0.footprint(in:engine)?.intersects(area) ?? true}),
                  !engine.propSnapshot().contains(where:{$0.opacity>0 && $0.rect.intersects(area)}),
                  !objects.values.contains(where:{$0.rect.union($0.nest?.trayRect ?? $0.rect).insetBy(dx:-16,dy:-48).intersects(area)}) else {continue}
            // 材料盘与巢台共用接触线、同一个habitat单鸟预约；不是额外场景或普通落点。
            let surface=Surface(id:engine.settings.companion == nil ? Self.nestSurfaceID:0xFE100000+UInt32(nextID),pid:Int32.min+21,
                rect:support,habitatKind:.nest)
            let blockers=Geometry.blockers(on:host,surfaces:world.surfaces).map(\.rect)
            let materials=materialIDs.sorted().enumerated().map {slot,id in
                NestMaterial(id:id,slot:slot,cached:NestGeometry.render(id:id,
                    position:NestGeometry.trayMaterialPoint(slot:slot,rect:tray,scale:scale)!,worldScale:scale,
                    anchor:TwigGeometry.surface,blockers:blockers))
            }
            let id=HabitatObjectID(nextID);nextID+=1
            let nest=NestState(parentAnchor:anchor,traySide:side,displayIDs:world.displayIDs,
                host:host,trayRect:tray,materials:materials)
            objects[id]=HabitatObject(id:id,kind:.nest,rect:rect,display:display,screens:world.screens,
                displays:world.displays,scale:scale,surface:surface,remainingUses:3,
                remainingLifetime:Self.nestLifetime,nest:nest)
            return .accepted
        }
        return .rejected(.noSpace)
    }
    /// The supplied point is the stable slot foot, not the asset's top edge.
    func placeBath(at point:CGPoint,in engine:BehaviorEngine) -> BehaviorResult {
        let world=engine.world,scale=world.scale
        guard !engine.paused else {return .rejected(.paused)}
        guard engine.settings.bathEnabled else {return .rejected(.disabled)}
        guard world.bathArtAvailable else {return .rejected(.missingFrames)}
        guard !world.buttonsDown else {return .rejected(.userInput)}
        // Retiring objects continue to own capacity until their surface is gone.
        guard (engine.settings.companion != nil ? objects.count<3:objects.isEmpty) else {return .rejected(.busy)}
        let maxScale=BathVisitBehavior.supportedSpecies.map{engine.settings.catalog.profile($0).relativeScale}.max() ?? 1
        guard let area=BathGeometry.clearance(foot:point,worldScale:scale,spriteScale:scale*maxScale),
              let display=world.displays.first(where:{$0.contains(area)}),
              world.screens.contains(where:{$0.contains(area)}),
              !world.surfaces.contains(where:{$0.layer>0 && $0.rect.intersects(area)}),
              !engine.fixedPerchSnapshot().contains(where:{$0.rect.insetBy(dx:-50*scale,dy:-80*scale).intersects(area)}),
              !engine.birds.contains(where:{engine.bounds(of:$0).intersects(area)}),
              !engine.runtime.landingReservations.contains(where:{$0.footprint(in:engine)?.intersects(area) ?? true}),
              !objects.values.contains(where:{$0.rect.insetBy(dx:-16,dy:-48).intersects(area)}) else {return .rejected(.noSpace)}
        let id=HabitatObjectID(nextID);nextID+=1
        let rect=BathGeometry.rect(foot:point,scale:scale)
        let surface=Surface(id:engine.settings.companion == nil ? Self.bathSurfaceID:0xFE100000+UInt32(id.rawValue),pid:Int32.min+20,
            rect:CGRect(x:rect.minX,y:point.y,width:rect.width,height:1),habitatKind:.bath)
        objects[id]=HabitatObject(id:id,kind:.bath,rect:rect,display:display,screens:world.screens,
            displays:world.displays,scale:scale,surface:surface,remainingUses:Self.bathVisits,remainingLifetime:Self.bathLifetime)
        return .accepted
    }
    func beginRetirement(_ id:HabitatObjectID,reason:BehaviorReason) {
        guard var object=objects[id] else {return}
        if object.retirementReason==nil {
            object.retirementReason=reason
            object.nest?.retire()
            if let nest=object.nest {object.remainingUses=nest.available}
        }
        if object.retirementAge==nil {object.retirementAge=0}
        objects[id]=object
    }
    /// Commit only after the complete bath and an actual safe return landing.
    /// Per-object successful run IDs are bounded by the three-visit capacity.
    @discardableResult func completeVisit(_ id:HabitatObjectID,runID:BehaviorRunID) -> Bool {
        guard var object=objects[id],object.kind == .bath,!object.retiring,
              runID.rawValue>0,!object.completedVisitRuns.contains(runID.rawValue) else {return false}
        object.completedVisitRuns.insert(runID.rawValue);object.remainingUses-=1
        guard authorize(object) else {return false}
        objects[id]=object
        if object.remainingUses==0 && object.persistentID == nil {beginRetirement(id,reason:.removed)}
        return true
    }
    @discardableResult func consume(_ id:HabitatObjectID)->Bool {
        guard var object=objects[id],object.kind == .foodTray,object.remainingUses>0 else {return false}
        object.remainingUses-=1
        guard authorize(object) else {return false}
        objects[id]=object;return true
    }
    func advance(_ dt:Double) {
        guard dt.isFinite,dt>0 else {return}
        for id in objects.keys.sorted() {
            guard var object=objects[id] else {continue}
            object.nest?.advance(dt)
            let previousLifetime=object.remainingLifetime
            if object.persistentID == nil {object.remainingLifetime=max(0,previousLifetime-dt)}
            if object.retiring {
                // A newly expired lifetime contributes only the portion of this
                // step after expiry; an already-retiring object uses all of dt.
                let elapsed=object.retirementAge==nil && previousLifetime>0 && (object.kind == .nest || object.remainingUses>0)
                    ? max(0,dt-previousLifetime):dt
                object.retirementAge=(object.retirementAge ?? 0)+elapsed
                if object.retirementReason==nil {
                    object.retirementReason = .removed
                    object.nest?.retire(elapsed:elapsed)
                    if let nest=object.nest {object.remainingUses=nest.available}
                }
            }
            objects[id]=object
        }
    }
    func remove(_ id:HabitatObjectID) {objects.removeValue(forKey:id)}
    /// 新巢事务用局部副本校验，只有整个四元身份与提交条件成立才写回。
    @discardableResult func withNest(_ id:HabitatObjectID,_ body:(inout HabitatObject,inout NestState)->Bool) -> Bool {
        guard var object=objects[id],object.kind == .nest,var nest=object.nest else {return false}
        guard body(&object,&nest) else {return false}
        object.nest=nest;object.remainingUses=nest.available
        if let old=objects[id]?.nest?.materials.map(\.state),old != nest.materials.map(\.state),!authorize(object) {
            // Failed cleanup writes may release an attached token locally. The durable
            // attached state recovers as spent; delivery/arrangement never gets this exception.
            guard zip(old,nest.materials.map(\.state)).allSatisfy({$0 == $1 || ($0 == .attached && $1 == .spent)}) else {return false}
        }
        objects[id]=object;return true
    }
    func snapshot(in engine:BehaviorEngine)->[HabitatObjectRenderState] {
        objects.keys.sorted().compactMap {id in
            guard let object=objects[id] else {return nil}
            return HabitatObjectRenderState(id:id,kind:object.kind,rect:object.rect,
                blockers:Geometry.blockers(on:object.nest?.host ?? object.surface,surfaces:engine.world.surfaces).map(\.rect),
                remainingUses:object.remainingUses,retiring:object.retiring,remainingLifetime:object.remainingLifetime)
        }
    }
}

/// Shared bounded point-to-point route for habitat visits. Native flight timing
/// supplies acceleration and braking; Bird.tick remains the only integrator.
struct HabitatJourney {
    let route:CoordinatedFlightRoute
    let envelope:FlightSceneEnvelope
    static func make(from a:CGPoint,to d:CGPoint,display:CGRect,scale:CGFloat,profile:SpeciesProfile)->Self? {
        let distance=Geometry.distance(a,d)
        guard distance>1,scale.isFinite,scale>0 else {return nil}
        let arc=min(90*scale,distance*0.2,max(0,min(a.y,d.y)-display.minY-39*scale)*0.7)
        let path=FlightPath(a,CGPoint(x:a.x+(d.x-a.x)/3,y:a.y+(d.y-a.y)/3-arc*4/3),
            CGPoint(x:a.x+(d.x-a.x)*2/3,y:a.y+(d.y-a.y)*2/3-arc*4/3),d)
        let bounds=path.bounds
        let footprint=CGRect(x:bounds.minX-29*scale,y:bounds.minY-39*scale,
            width:bounds.width+58*scale,height:bounds.height+48*scale)
        guard display.contains(footprint),
              let route=CoordinatedFlightRoute(legs:[CoordinatedFlightLeg(path:path,
                timing:FlightTiming(distance:path.length,speed:FlightBehavior.cruiseSpeed(profile.id,multiplier:profile.speed)))]),
              let envelope=FlightSceneEnvelope(routes:[route],offsets:[0],scales:[scale],maximumDuration:30) else {return nil}
        return Self(route:route,envelope:envelope)
    }
    func safe(in engine:BehaviorEngine,bird:BirdID,after age:Double=0)->Bool {
        envelope.isClear(in:engine,excluding:[bird],display:nil,after:age)
    }
    func pointerClear(in engine:BehaviorEngine,after age:Double=0)->Bool {envelope.pointerIsClear(in:engine,after:age)}
}
