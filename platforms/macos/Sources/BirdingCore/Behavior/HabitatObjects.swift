import Foundation
import CoreGraphics

/// Objects outlive individual visits. The runtime leases their slots; the store
/// only owns placement, remaining resources and the simulation-time lifetime.
public struct HabitatObjectID:Hashable,Codable,Comparable {
    public let rawValue:UInt64
    public init(_ value:UInt64) {rawValue=value}
    public static func < (a:Self,b:Self)->Bool {a.rawValue<b.rawValue}
}
public enum HabitatObjectKind:String,Codable {case foodTray}
public struct HabitatObjectRenderState {
    public let id:HabitatObjectID
    public let kind:HabitatObjectKind
    /// The center of the upper edge is the foot/seed contact anchor.
    public let rect:CGRect
    public let blockers:[CGRect]
    public let remainingUses:Int
    public let retiring:Bool
    public let remainingLifetime:Double
}
struct HabitatObject {
    let id:HabitatObjectID
    let kind:HabitatObjectKind
    let rect:CGRect
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]
    let scale:CGFloat
    let surface:Surface
    var remainingUses:Int
    var remainingLifetime:Double
    var retiring:Bool {remainingUses<=0 || remainingLifetime<=0}
    var foot:CGPoint {CGPoint(x:rect.midX,y:rect.minY)}
}
final class HabitatObjectStore {
    private(set) var objects:[HabitatObjectID:HabitatObject]=[:]
    private var nextID:UInt64=1
    static let foodLifetime=180.0
    static let foodPortions=3

    func placeFood(at point:CGPoint,in engine:BehaviorEngine)->Bool {
        let world=engine.world,scale=world.scale
        guard objects.isEmpty,scale.isFinite,scale>0,point.x.isFinite,point.y.isFinite,
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
              !world.surfaces.contains(where:{$0.id==Self.surfaceID}) else {return false}
        let id=HabitatObjectID(nextID);nextID+=1
        let surface=Surface(id:Self.surfaceID,pid:Int32.min+19,
            rect:CGRect(x:point.x-64*scale,y:point.y,width:128*scale,height:1),habitatKind:.foodTray)
        objects[id]=HabitatObject(id:id,kind:.foodTray,rect:rect,display:display,screens:world.screens,
            displays:world.displays,scale:scale,surface:surface,remainingUses:Self.foodPortions,remainingLifetime:Self.foodLifetime)
        return true
    }
    static let surfaceID:UInt32=0xFE000001
    func consume(_ id:HabitatObjectID) {
        guard var object=objects[id],object.remainingUses>0 else {return}
        object.remainingUses-=1;objects[id]=object
    }
    func advance(_ dt:Double) {
        for id in objects.keys.sorted() {
            guard var object=objects[id] else {continue}
            object.remainingLifetime=max(0,object.remainingLifetime-dt);objects[id]=object
        }
    }
    func remove(_ id:HabitatObjectID) {objects.removeValue(forKey:id)}
    func snapshot(in engine:BehaviorEngine)->[HabitatObjectRenderState] {
        objects.keys.sorted().compactMap {id in
            guard let object=objects[id] else {return nil}
            return HabitatObjectRenderState(id:id,kind:object.kind,rect:object.rect,
                blockers:Geometry.blockers(on:object.surface,surfaces:engine.world.surfaces).map(\.rect),
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
