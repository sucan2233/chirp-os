import Foundation
import CoreGraphics

public enum CarriedObjectState:String {case available,attached,placed,retired}
public enum CarriedObjectKind:String {case leaf}

/// One identity survives every transition. Lease and lifecycle are distinct:
/// a run may reserve an available leaf before there is an attached owner.
public struct CarriedObject {
    public let id:ScenePropID
    public let kind:CarriedObjectKind
    public let worldScale:CGFloat
    public let facingRight:Bool
    public fileprivate(set) var state:CarriedObjectState
    public fileprivate(set) var owner:BirdID?
    public fileprivate(set) var reservedByRun:BehaviorRunID?
    public fileprivate(set) var surfaceAnchor:SurfaceAnchor
    public fileprivate(set) var remainingLifetime:Double
    fileprivate var reservedBird:BirdID?
    fileprivate var cachedSnapshot:ScenePropRenderState
    fileprivate var fadeRemaining=CarriedObjectGeometry.fadeDuration
    fileprivate var fadeOpacity=1.0
    fileprivate let screens:[CGRect]
    fileprivate let displays:[CGRect]
    fileprivate let displayIDs:[String]
}

/// Persistent scene entities only. Runtime borrows prop IDs as leases but does
/// not emit another copy. All transitions run on the engine's simulation thread.
final class CarriedObjectStore {
    private(set) var objects:[ScenePropID:CarriedObject]=[:]

    func placeLeaf(id:ScenePropID,at point:CGPoint,facingRight:Bool=true,in engine:BehaviorEngine) -> BehaviorResult {
        guard !engine.paused else {return .rejected(.paused)}
        guard engine.settings.leafCarryEnabled else {return .rejected(.disabled)}
        guard engine.world.leafCarryArtAvailable else {return .rejected(.missingFrames)}
        guard !engine.world.buttonsDown else {return .rejected(.userInput)}
        guard objects.isEmpty,!engine.runtime.propIDs.contains(id),id.rawValue>0 else {return .rejected(.busy)}
        let world=engine.world
        let scale=world.scale*CGFloat(engine.settings.catalog.profile(.treeSparrow).relativeScale)
        guard let anchor=SurfaceAnchor.placement(at:point,in:world,groundScale:scale),
              let host=anchor.host(in:world),let contact=anchor.point(in:world) else {return .rejected(.noSpace)}
        let snapshot=CarriedObjectGeometry.render(id:id,position:contact,anchor:CarriedObjectGeometry.surface,
            worldScale:world.scale,facingRight:facingRight,
            blockers:Geometry.blockers(on:host,surfaces:world.surfaces).map(\.rect))
        guard world.screens.contains(where:{$0.contains(snapshot.rect)}),world.displays.contains(where:{$0.contains(snapshot.rect)}),
              !snapshot.blockers.contains(where:{$0.intersects(snapshot.rect)}),
              !engine.birds.contains(where:{engine.bounds(of:$0).intersects(snapshot.rect)}),
              !engine.runtime.landingReservations.contains(where:{$0.footprint(in:engine)?.intersects(snapshot.rect) ?? true})
        else {return .rejected(.noSpace)}
        objects[id]=CarriedObject(id:id,kind:.leaf,worldScale:world.scale,facingRight:facingRight,
            state:.available,owner:nil,reservedByRun:nil,surfaceAnchor:anchor,
            remainingLifetime:CarriedObjectGeometry.availableLifetime,reservedBird:nil,cachedSnapshot:snapshot,
            screens:world.screens,displays:world.displays,displayIDs:world.displayIDs)
        return .accepted
    }
    @discardableResult func reserve(_ id:ScenePropID,run:BehaviorRunID,bird:BirdID) -> Bool {
        guard var object=objects[id],object.state == .available,object.remainingLifetime>0,
              object.reservedByRun==nil,object.owner==nil,
              !objects.values.contains(where:{$0.reservedBird==bird || $0.owner==bird}) else {return false}
        object.reservedByRun=run;object.reservedBird=bird;objects[id]=object;return true
    }
    @discardableResult func pickup(_ id:ScenePropID,run:BehaviorRunID,bird:BirdID,contact:ScenePropRenderState) -> Bool {
        guard var object=objects[id],object.state == .available,object.remainingLifetime>0,
              object.reservedByRun==run,object.reservedBird==bird,object.owner==nil,
              contact.id==id,Geometry.distance(contact.rect.origin,object.cachedSnapshot.rect.origin)<0.001,
              abs(contact.rect.width-object.cachedSnapshot.rect.width)<0.001,
              abs(contact.rect.height-object.cachedSnapshot.rect.height)<0.001 else {return false}
        object.state = .attached;object.owner=bird;object.remainingLifetime=0
        object.cachedSnapshot=contact;objects[id]=object;return true
    }
    @discardableResult func place(_ id:ScenePropID,run:BehaviorRunID,at anchor:SurfaceAnchor,
                                 contact:ScenePropRenderState,in engine:BehaviorEngine) -> Bool {
        guard var object=objects[id],object.state == .attached,object.reservedByRun==run,object.owner != nil,
              let host=anchor.host(in:engine.world),let point=anchor.point(in:engine.world) else {return false}
        let snapshot=CarriedObjectGeometry.render(id:id,position:point,anchor:CarriedObjectGeometry.surface,
            worldScale:object.worldScale,facingRight:object.facingRight,
            blockers:Geometry.blockers(on:host,surfaces:engine.world.surfaces).map(\.rect))
        guard contact.id==id,Geometry.distance(contact.rect.origin,snapshot.rect.origin)<0.001,
              abs(contact.rect.width-snapshot.rect.width)<0.001,abs(contact.rect.height-snapshot.rect.height)<0.001,
              engine.world.displays.contains(where:{$0.contains(snapshot.rect)}),
              !snapshot.blockers.contains(where:{$0.intersects(snapshot.rect)}) else {return false}
        object.state = .placed;object.owner=nil;object.surfaceAnchor=anchor
        object.remainingLifetime=CarriedObjectGeometry.placedLifetime;object.cachedSnapshot=snapshot
        objects[id]=object
        engine.scheduler.endFocus(matching:SceneFocus(leafID:id),frequency:engine.settings.ambientFrequency)
        return true
    }
    func releaseReservation(_ id:ScenePropID,run:BehaviorRunID) {
        guard var object=objects[id],object.reservedByRun==run else {return}
        object.reservedByRun=nil;object.reservedBird=nil;objects[id]=object
    }
    private func liveSnapshot(_ object:CarriedObject,in engine:BehaviorEngine) -> ScenePropRenderState? {
        switch object.state {
        case .available,.placed:
            guard let host=object.surfaceAnchor.host(in:engine.world),let point=object.surfaceAnchor.point(in:engine.world) else {return nil}
            // Paused metadata may invalidate a host, but may not translate props.
            if engine.paused {
                let cached=object.cachedSnapshot
                return CarriedObjectGeometry.render(id:object.id,position:cached.position,
                    anchor:CGPoint(x:cached.anchor.x*CarriedObjectGeometry.leafSize,y:cached.anchor.y*CarriedObjectGeometry.leafSize),
                    worldScale:object.worldScale,facingRight:object.facingRight,rotation:cached.rotation,
                    blockers:Geometry.blockers(on:host,surfaces:engine.world.surfaces).map(\.rect))
            }
            return CarriedObjectGeometry.render(id:object.id,position:point,anchor:CarriedObjectGeometry.surface,
                worldScale:object.worldScale,facingRight:object.facingRight,
                blockers:Geometry.blockers(on:host,surfaces:engine.world.surfaces).map(\.rect))
        case .attached:
            guard let birdID=object.owner,let bird=engine.bird(birdID),
                  let pose=engine.runtime.presentation(for:birdID,in:engine) else {return nil}
            return CarriedObjectGeometry.attached(id:object.id,bird:bird,pose:pose,worldScale:object.worldScale,
                birdScale:engine.spriteScale(for:bird),facingRight:object.facingRight,blockers:bird.blockers(in:engine.world.surfaces))
        case .retired:return object.cachedSnapshot
        }
    }
    /// Call after a new world sample, before generic host tracking. Invalid IDs
    /// are returned to the engine so runtime cancellation remains the sole owner.
    func synchronize(in engine:BehaviorEngine) -> [ScenePropID] {
        var invalid:[ScenePropID]=[]
        for id in objects.keys.sorted() {
            guard var object=objects[id],object.state != .retired else {continue}
            guard engine.settings.leafCarryEnabled,engine.world.leafCarryArtAvailable,
                  object.worldScale==engine.world.scale,object.screens==engine.world.screens,
                  object.displays==engine.world.displays,object.displayIDs==engine.world.displayIDs,
                  let value=liveSnapshot(object,in:engine),SurfaceAnchor.finite(value.rect),
                  engine.world.displays.contains(where:{$0.contains(value.rect)}),
                  !value.blockers.contains(where:{$0.intersects(value.rect)}) else {
                invalid.append(id)
                if engine.paused {retire(id,in:engine,immediate:true)}
                continue
            }
            if !engine.paused {object.cachedSnapshot=value;objects[id]=object}
        }
        return invalid
    }
    /// Engine invokes after Bird.tick, never from a render query. If a caller
    /// subsequently replaces motion/removes a bird before another world sample,
    /// retirement still freezes the last actual attached presentation.
    func captureAttachedSnapshots(in engine:BehaviorEngine) {
        guard !engine.paused else {return}
        for id in objects.keys.sorted() {
            guard var object=objects[id],object.state == .attached,
                  let value=liveSnapshot(object,in:engine) else {continue}
            object.cachedSnapshot=value;objects[id]=object
        }
    }
    /// Attached lifetime is exclusively bounded by the owning run, never by the
    /// old 180s or a second carried timer. Returns newly retired IDs once only.
    func advance(_ dt:Double,in engine:BehaviorEngine) -> [ScenePropID] {
        guard !engine.paused,dt.isFinite,dt>0 else {return []}
        var retired:[ScenePropID]=[]
        for id in objects.keys.sorted() {
            guard var object=objects[id] else {continue}
            if object.state == .retired {
                object.fadeRemaining=max(0,object.fadeRemaining-dt)
                if object.fadeRemaining<=1e-10 {objects.removeValue(forKey:id)} else {objects[id]=object}
            } else if object.state == .available || object.state == .placed {
                object.remainingLifetime=max(0,object.remainingLifetime-dt);objects[id]=object
                if object.remainingLifetime<=1e-10 {
                    // Placed presentation already faded during its final .2s.
                    // Do not restart an opaque retirement after the 8s deadline.
                    if object.state == .placed {
                        engine.scheduler.endFocus(matching:SceneFocus(leafID:id),frequency:engine.settings.ambientFrequency)
                        objects.removeValue(forKey:id)
                    } else {retire(id,in:engine)}
                    retired.append(id)
                }
            }
        }
        return retired
    }
    func retire(_ id:ScenePropID,in engine:BehaviorEngine,immediate:Bool=false,freezing:ScenePropRenderState?=nil) {
        guard var object=objects[id] else {return}
        engine.scheduler.endFocus(matching:SceneFocus(leafID:id),frequency:engine.settings.ambientFrequency)
        if immediate {objects.removeValue(forKey:id);return}
        guard object.state != .retired else {return}
        object.fadeOpacity=object.state == .placed ? min(1,object.remainingLifetime/CarriedObjectGeometry.fadeDuration):1
        object.cachedSnapshot=freezing ?? liveSnapshot(object,in:engine) ?? object.cachedSnapshot
        object.state = .retired;object.owner=nil;object.reservedByRun=nil;object.reservedBird=nil
        object.remainingLifetime=0;object.fadeRemaining=CarriedObjectGeometry.fadeDuration;objects[id]=object
    }
    func snapshot(in engine:BehaviorEngine) -> [ScenePropRenderState] {
        objects.keys.sorted().compactMap {id in
            guard let object=objects[id] else {return nil}
            let value=liveSnapshot(object,in:engine) ?? object.cachedSnapshot
            let opacity:Double
            if object.state == .retired {opacity=object.fadeOpacity*object.fadeRemaining/CarriedObjectGeometry.fadeDuration}
            else if object.state == .placed {opacity=min(1,object.remainingLifetime/CarriedObjectGeometry.fadeDuration)}
            else {opacity=1}
            return CarriedObjectGeometry.render(id:id,position:value.position,
                anchor:CGPoint(x:value.anchor.x*CarriedObjectGeometry.leafSize,y:value.anchor.y*CarriedObjectGeometry.leafSize),
                worldScale:object.worldScale,facingRight:!value.mirrored,rotation:value.rotation,opacity:opacity,blockers:value.blockers)
        }
    }
    func removeAll() {objects.removeAll()}
}
