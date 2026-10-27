import Foundation
import CoreGraphics

public enum CarriedObjectState:String {case available,attached,placed,retired}
public enum CarriedObjectKind:String {case leaf}

/// Delivery belongs to the persistent entity, so cancelling the bird after
/// release cannot undo the descent or create another leaf.
public struct GiftDelivery:Codable,Equatable {
    public let carrier:BirdID
    public let receiverSlot:Int
    public let receiverRevision:UInt64
    public let receiverFoot:CGPoint
    public let releaseGrip:CGPoint
    public let duration:Double
    public fileprivate(set) var age:Double
    public var arrived:Bool {age+1e-10>=duration}
}

/// One identity survives every transition. Lease and lifecycle are distinct:
/// a run may reserve an available leaf before there is an attached owner.
public struct CarriedObject {
    public let id:ScenePropID
    public let kind:CarriedObjectKind
    public let worldScale:CGFloat
    public let facingRight:Bool
    var persistentID:UUID?=nil
    public fileprivate(set) var state:CarriedObjectState
    public fileprivate(set) var owner:BirdID?
    public fileprivate(set) var reservedByRun:BehaviorRunID?
    public fileprivate(set) var surfaceAnchor:SurfaceAnchor
    public fileprivate(set) var remainingLifetime:Double
    public fileprivate(set) var isVisitorGift=false
    public fileprivate(set) var giftDelivery:GiftDelivery?
    public var giftReceiverSlot:Int? {giftDelivery?.receiverSlot}
    public var giftReceiverRevision:UInt64? {giftDelivery?.receiverRevision}
    fileprivate var reservedBird:BirdID?
    fileprivate var cachedSnapshot:ScenePropRenderState
    fileprivate var effect:SceneLeafEffect?
    fileprivate var effectAllowance:Double=0
    fileprivate var fadeRemaining=CarriedObjectGeometry.fadeDuration
    fileprivate var fadeOpacity=1.0
    fileprivate let screens:[CGRect]
    fileprivate let displays:[CGRect]
    fileprivate let displayIDs:[String]
}

/// Persistent scene entities only. Runtime borrows prop IDs as leases but does
/// not emit another copy. All transitions run on the engine's simulation thread.
final class CarriedObjectStore {
    var objects:[ScenePropID:CarriedObject]=[:]

    var commitResource:((UUID,SceneResource)->Bool)?
    func makePersistent(_ id:ScenePropID,instance:UUID) {
        guard var object=objects[id] else {return}
        object.persistentID=instance;object.remainingLifetime=1e12;objects[id]=object
    }
    @discardableResult func restoreEffect(id:ScenePropID,instance:UUID,effect:SceneLeafEffect,in engine:BehaviorEngine)->Bool {
        let item=SceneInstance(id:instance,kind:.leaf,anchor:effect.anchor)
        guard effect.support == .ground,effect.remaining>0,let point=item.point(in:engine.world),
              placeLeaf(id:id,at:point,facingRight:effect.facingRight,in:engine).accepted,var object=objects[id],object.surfaceAnchor.isGround else {return false}
        object.persistentID=instance;object.state = .placed;object.remainingLifetime=effect.remaining
        object.effect=effect;object.effectAllowance=0;objects[id]=object;return true
    }
    private func reserveEffectTime(_ object:inout CarriedObject)->Bool {
        guard let id=object.persistentID,var effect=object.effect,effect.remaining>0 else {return false}
        let allowance=min(2,effect.remaining);effect.remaining-=allowance
        var resource=SceneResource(kind:.leaf);resource.leafConsumed=true;resource.leafEffect=effect
        guard commitResource?(id,resource) == true else {return false}
        object.effect=effect;object.effectAllowance=allowance;return true
    }
    func placeLeaf(id:ScenePropID,at point:CGPoint,facingRight:Bool=true,in engine:BehaviorEngine) -> BehaviorResult {
        guard !engine.paused else {return .rejected(.paused)}
        guard engine.settings.leafCarryEnabled else {return .rejected(.disabled)}
        guard engine.world.leafCarryArtAvailable else {return .rejected(.missingFrames)}
        guard !engine.world.buttonsDown else {return .rejected(.userInput)}
        guard (engine.settings.companion != nil ? objects.count<3:objects.isEmpty),!engine.runtime.propIDs.contains(id),id.rawValue>0 else {return .rejected(.busy)}
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
        guard var object=objects[id],!object.isVisitorGift,object.state == .available,object.remainingLifetime>0,
              object.reservedByRun==nil,object.owner==nil,
              !objects.values.contains(where:{$0.reservedBird==bird || $0.owner==bird}) else {return false}
        object.reservedByRun=run;object.reservedBird=bird;objects[id]=object;return true
    }
    @discardableResult func pickup(_ id:ScenePropID,run:BehaviorRunID,bird:BirdID,contact:ScenePropRenderState) -> Bool {
        guard var object=objects[id],(object.state == .available || (object.isVisitorGift && object.state == .placed)),object.remainingLifetime>0,
              object.reservedByRun==run,object.reservedBird==bird,object.owner==nil,
              contact.id==id,Geometry.distance(contact.rect.origin,object.cachedSnapshot.rect.origin)<0.001,
              abs(contact.rect.width-object.cachedSnapshot.rect.width)<0.001,
              abs(contact.rect.height-object.cachedSnapshot.rect.height)<0.001 else {return false}
        if let instance=object.persistentID {
            var resource=SceneResource(kind:.leaf);resource.leafConsumed=true
            guard commitResource?(instance,resource) == true else {return false}
        }
        object.effect=nil;object.effectAllowance=0
        object.state = .attached;object.owner=bird;object.remainingLifetime=0
        object.cachedSnapshot=contact;objects[id]=object;return true
    }
    @discardableResult func place(_ id:ScenePropID,run:BehaviorRunID,at anchor:SurfaceAnchor,
                                 contact:ScenePropRenderState,in engine:BehaviorEngine) -> Bool {
        guard var object=objects[id],!object.isVisitorGift,object.state == .attached,object.reservedByRun==run,object.owner != nil,
              let host=anchor.host(in:engine.world),let point=anchor.point(in:engine.world) else {return false}
        let snapshot=CarriedObjectGeometry.render(id:id,position:point,anchor:CarriedObjectGeometry.surface,
            worldScale:object.worldScale,facingRight:object.facingRight,
            blockers:Geometry.blockers(on:host,surfaces:engine.world.surfaces).map(\.rect))
        guard contact.id==id,Geometry.distance(contact.rect.origin,snapshot.rect.origin)<0.001,
              abs(contact.rect.width-snapshot.rect.width)<0.001,abs(contact.rect.height-snapshot.rect.height)<0.001,
              engine.world.displays.contains(where:{$0.contains(snapshot.rect)}),
              !snapshot.blockers.contains(where:{$0.intersects(snapshot.rect)}) else {return false}
        object.state = .placed;object.owner=nil;object.surfaceAnchor=anchor
        object.remainingLifetime=engine.settings.visitorGiftsEnabled ? CarriedObjectGeometry.giftMaterialLifetime:CarriedObjectGeometry.placedLifetime
        object.cachedSnapshot=snapshot
        if object.persistentID != nil {
            guard let saved=FixedPerchAnchor.capture(slot:1,point:point,displayIDs:engine.world.displayIDs,displays:engine.world.displays) else {return false}
            object.effect=SceneLeafEffect(anchor:saved,support:anchor.isGround ? .ground:.window,
                remaining:object.remainingLifetime,facingRight:object.facingRight)
            guard reserveEffectTime(&object) else {return false}
        }
        objects[id]=object
        engine.scheduler.endFocus(matching:SceneFocus(leafID:id),frequency:engine.settings.ambientFrequency)
        return true
    }
    func releaseReservation(_ id:ScenePropID,run:BehaviorRunID) {
        guard var object=objects[id],object.reservedByRun==run else {return}
        object.reservedByRun=nil;object.reservedBird=nil;objects[id]=object
    }
    private func liveSnapshot(_ object:CarriedObject,in engine:BehaviorEngine) -> ScenePropRenderState? {
        if let delivery=object.giftDelivery,object.state != .retired {
            guard delivery.duration==GiftReceiverGeometry.fallDuration,
                  delivery.duration>0,delivery.duration<=GiftReceiverGeometry.maximumFallDuration,
                  delivery.age.isFinite,delivery.age>=0,delivery.age<=delivery.duration,
                  engine.giftReceiverRevision(slot:delivery.receiverSlot)==delivery.receiverRevision,
                  let perch=engine.fixedPerchSnapshot().first(where:{$0.slot==delivery.receiverSlot}),
                  perch.foot==delivery.receiverFoot else {return nil}
            let value=giftSnapshot(object,delivery:delivery,perch:perch,in:engine)
            let remaining=delivery.arrived ? value.rect:GiftReceiverGeometry.descentRect(from:value.position,
                on:perch,worldScale:object.worldScale,facingRight:object.facingRight)
            // Release begins at the real bill, inside the conservative bird
            // canvas. The original carrier may separate for this existing .6s
            // simulated descent even after cancellation releases its run lease.
            // Pausing freezes delivery.age; arrived ends the exemption even if
            // the run still exists. No destination reservation is exempted.
            let carrierIsSeparating = !delivery.arrived
            guard !value.blockers.contains(where:{$0.intersects(remaining)}),
                  !engine.birds.contains(where:{(!carrierIsSeparating || engine.id(of:$0) != delivery.carrier) && engine.bounds(of:$0).intersects(remaining)}),
                  !engine.runtime.landingReservations.contains(where:{$0.footprint(in:engine)?.intersects(remaining) ?? true}) else {return nil}
            return value
        }
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
        synchronize(in:engine,visitorGiftsOnly:false)
    }
    /// Settings changes can invalidate receivers without changing ordinary leaf
    /// hosts. Filter before validation, including its immediate paused removal.
    func synchronizeVisitorGifts(in engine:BehaviorEngine) -> [ScenePropID] {
        synchronize(in:engine,visitorGiftsOnly:true)
    }
    private func synchronize(in engine:BehaviorEngine,visitorGiftsOnly:Bool) -> [ScenePropID] {
        var invalid:[ScenePropID]=[]
        for id in objects.keys.sorted() {
            guard var object=objects[id],object.state != .retired,
                  !visitorGiftsOnly || object.isVisitorGift else {continue}
            guard (object.isVisitorGift ? engine.settings.visitorGiftsEnabled:engine.settings.leafCarryEnabled),engine.world.leafCarryArtAvailable,
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
            } else if var delivery=object.giftDelivery,!delivery.arrived {
                let used=min(dt,max(0,delivery.duration-delivery.age))
                delivery.age=min(delivery.duration,delivery.age+used);object.giftDelivery=delivery
                if delivery.arrived {object.remainingLifetime=max(0,GiftReceiverGeometry.displayLifetime-(dt-used))}
                if let perch=engine.fixedPerchSnapshot().first(where:{$0.slot==delivery.receiverSlot}) {
                    object.cachedSnapshot=giftSnapshot(object,delivery:delivery,perch:perch,in:engine)
                }
                objects[id]=object
            } else if object.state == .available || object.state == .placed {
                if object.persistentID != nil,object.state == .placed,!object.isVisitorGift {
                    if object.effectAllowance+1e-10<dt {
                        guard reserveEffectTime(&object) else {retire(id,in:engine);retired.append(id);continue}
                    }
                    object.effectAllowance=max(0,object.effectAllowance-dt)
                }
                if object.persistentID == nil || object.state != .available {object.remainingLifetime=max(0,object.remainingLifetime-dt)};objects[id]=object
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
            if object.persistentID != nil,object.state == .placed,!object.isVisitorGift,object.effectAllowance<=0 {opacity=0}
            else if object.state == .retired {opacity=object.fadeOpacity*object.fadeRemaining/CarriedObjectGeometry.fadeDuration}
            else if object.state == .placed,object.giftDelivery?.arrived != false {opacity=min(1,object.remainingLifetime/CarriedObjectGeometry.fadeDuration)}
            else {opacity=1}
            return CarriedObjectGeometry.render(id:id,position:value.position,
                anchor:CGPoint(x:value.anchor.x*CarriedObjectGeometry.leafSize,y:value.anchor.y*CarriedObjectGeometry.leafSize),
                worldScale:object.worldScale,facingRight:!value.mirrored,rotation:value.rotation,opacity:opacity,blockers:value.blockers)
        }
    }
    /// Pure admission: a rejected request leaves identity, lifetime and leases
    /// untouched. Delivered gifts can never be recycled into another gift.
    func giftIsAvailable(_ id:ScenePropID,in engine:BehaviorEngine) -> Bool {
        guard let object=objects[id],!object.isVisitorGift,
              object.state == .available || object.state == .placed,
              object.reservedByRun==nil,object.owner==nil,object.remainingLifetime>0,
              object.worldScale==engine.world.scale,object.screens==engine.world.screens,
              object.displays==engine.world.displays,object.displayIDs==engine.world.displayIDs,
              let value=liveSnapshot(object,in:engine),engine.world.displays.contains(where:{$0.contains(value.rect)}),
              !value.blockers.contains(where:{$0.intersects(value.rect)}) else {return false}
        return true
    }
    @discardableResult func reserveGift(_ id:ScenePropID,run:BehaviorRunID,bird:BirdID,in engine:BehaviorEngine) -> Bool {
        guard giftIsAvailable(id,in:engine),var object=objects[id],
              !objects.values.contains(where:{$0.isVisitorGift && $0.state != .retired || $0.reservedBird==bird || $0.owner==bird}) else {return false}
        if let instance=object.persistentID {
            // Claim once before changing lifecycle. A crash cannot restore the old
            // placed effect while a gift has already claimed the same material.
            var resource=SceneResource(kind:.leaf);resource.leafConsumed=true
            guard commitResource?(instance,resource) == true else {return false}
            object.effect=nil;object.effectAllowance=0
        }
        object.isVisitorGift=true;object.reservedByRun=run;object.reservedBird=bird;objects[id]=object
        engine.scheduler.endFocus(matching:SceneFocus(leafID:id),frequency:engine.settings.ambientFrequency)
        return true
    }
    struct PreparedGiftRelease {
        fileprivate let object:CarriedObject
    }
    /// No mutation, token use, RNG or time advancement is permitted here. The
    /// returned value is the entire committed entity, not a fallible recipe.
    func prepareGiftRelease(_ id:ScenePropID,run:BehaviorRunID,bird:BirdID,
                            receiver:GiftReceiverReservation,contact:ScenePropRenderState,
                            in engine:BehaviorEngine) -> PreparedGiftRelease? {
        guard var object=objects[id],object.isVisitorGift,object.state == .attached,
              object.owner==bird,object.reservedByRun==run,object.reservedBird==bird,
              object.worldScale==engine.world.scale,object.screens==engine.world.screens,
              object.displays==engine.world.displays,object.displayIDs==engine.world.displayIDs,
              contact.id==id,SurfaceAnchor.finite(contact.rect),contact.rotation==0,
              engine.settings.visitorGiftsEnabled,receiver.bird==bird,
              receiver.isValid(in:engine,excluding:[bird]),
              let actual=liveSnapshot(object,in:engine),actual.mirrored==contact.mirrored,
              Geometry.distance(actual.position,contact.position)<0.001,actual.anchor==contact.anchor,
              abs(actual.size-contact.size)<0.001,abs(actual.rotation-contact.rotation)<0.001,
              let perch=engine.fixedPerchSnapshot().first(where:{$0.slot==receiver.slot}) else {return nil}
        let finalGrip=GiftReceiverGeometry.finalGrip(on:perch,worldScale:object.worldScale,facingRight:object.facingRight)
        let area=GiftReceiverGeometry.descentRect(from:contact.position,on:perch,
            worldScale:object.worldScale,facingRight:object.facingRight)
        guard contact.position.y<=finalGrip.y,finalGrip.y-contact.position.y<=100*object.worldScale,
              receiver.rect.contains(area),engine.world.displays.contains(where:{$0.contains(area)}),
              !Geometry.blockers(on:perch.surface,surfaces:engine.world.surfaces).contains(where:{$0.rect.intersects(area)}),
              !engine.birds.contains(where:{engine.id(of:$0) != bird && engine.bounds(of:$0).intersects(area)}),
              !engine.runtime.landingReservations.contains(where:{$0.bird != bird && ($0.footprint(in:engine)?.intersects(area) ?? true)}) else {return nil}
        object.state = .placed;object.owner=nil;object.remainingLifetime=GiftReceiverGeometry.displayLifetime
        object.cachedSnapshot=contact
        object.giftDelivery=GiftDelivery(carrier:bird,receiverSlot:receiver.slot,receiverRevision:receiver.revision,
            receiverFoot:perch.foot,releaseGrip:contact.position,duration:GiftReceiverGeometry.fallDuration,age:0)
        return PreparedGiftRelease(object:object)
    }
    /// Call immediately after the token is consumed, with no callbacks between
    /// the two statements. This assignment is deliberately nonfailable.
    func commitGiftRelease(_ prepared:PreparedGiftRelease) {objects[prepared.object.id]=prepared.object}
    func giftHasArrived(_ id:ScenePropID,in engine:BehaviorEngine) -> Bool {
        guard let object=objects[id],object.isVisitorGift,object.state == .placed,
              object.giftDelivery?.arrived==true,object.remainingLifetime>0,
              let snapshot=liveSnapshot(object,in:engine),engine.world.displays.contains(where:{$0.contains(snapshot.rect)}),
              !snapshot.blockers.contains(where:{$0.intersects(snapshot.rect)}) else {return false}
        return true
    }
    /// Persists beyond the run/visitor. Slot/revision retain receiver identity;
    /// actual remaining descent/leaf geometry blocks ordinary landings.
    func giftReceiverReservations(in engine:BehaviorEngine) -> [GiftReceiverReservation] {
        objects.keys.sorted().compactMap {id in
            guard let object=objects[id],object.isVisitorGift,object.state == .placed,
                  let delivery=object.giftDelivery,
                  engine.giftReceiverRevision(slot:delivery.receiverSlot)==delivery.receiverRevision,
                  let perch=engine.fixedPerchSnapshot().first(where:{$0.slot==delivery.receiverSlot}),
                  perch.foot==delivery.receiverFoot else {return nil}
            let value=giftSnapshot(object,delivery:delivery,perch:perch,in:engine)
            let rect=delivery.arrived ? value.rect:GiftReceiverGeometry.descentRect(from:value.position,
                on:perch,worldScale:object.worldScale,facingRight:object.facingRight)
            return GiftReceiverReservation(bird:delivery.carrier,perch:perch,revision:delivery.receiverRevision,
                rect:rect,worldScale:object.worldScale)
        }
    }
    private func giftSnapshot(_ object:CarriedObject,delivery:GiftDelivery,perch:ResolvedFixedPerch,
                              in engine:BehaviorEngine) -> ScenePropRenderState {
        let end=GiftReceiverGeometry.finalGrip(on:perch,worldScale:object.worldScale,facingRight:object.facingRight)
        let t=min(1,max(0,delivery.age/delivery.duration)),u=t*t*(3-2*t)
        let point=CGPoint(x:delivery.releaseGrip.x+(end.x-delivery.releaseGrip.x)*t,
            y:delivery.releaseGrip.y+(end.y-delivery.releaseGrip.y)*u)
        return CarriedObjectGeometry.render(id:object.id,position:point,anchor:CarriedObjectGeometry.grip,
            worldScale:object.worldScale,facingRight:object.facingRight,
            blockers:Geometry.blockers(on:perch.surface,surfaces:engine.world.surfaces).map(\.rect))
    }
    func clearVisitorGifts(in engine:BehaviorEngine,immediate:Bool=true) {
        for id in objects.keys.sorted() where objects[id]?.isVisitorGift==true {retire(id,in:engine,immediate:immediate)}
    }
    func clearOrdinaryLeaves(in engine:BehaviorEngine,immediate:Bool=true) {
        for id in objects.keys.sorted() where objects[id]?.isVisitorGift==false {retire(id,in:engine,immediate:immediate)}
    }
    func removeAll() {objects.removeAll()}
}
