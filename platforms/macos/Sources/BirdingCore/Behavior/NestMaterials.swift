import Foundation
import CoreGraphics

public enum NestMaterialState:String,Codable {case available,attached,delivered,arranged,spent}
public enum NestMaterialPurpose:String,Codable {case carry,build}

/// 预约与材料状态分开；同一次访问同时持有巢台单槽和一根材料。
public struct NestMaterialReservation:Equatable,Codable {
    public let materialID:ScenePropID
    public let runID:BehaviorRunID
    public let birdID:BirdID
    public let purpose:NestMaterialPurpose
}

public struct NestMaterialSnapshot:Equatable,Codable {
    public let id:ScenePropID
    public let slot:Int
    public let state:NestMaterialState
    public let owner:BirdID?
    public let reservedByRun:BehaviorRunID?
    public let reservedBird:BirdID?
    /// 当前同一实体的夹持点；available/delivered随父宿主定位，spent冻结最后位置。
    public let position:CGPoint
    public let rotation:CGFloat
    public let mirrored:Bool
    public let opacity:Double
    public let fadeRemaining:Double
    public let pickupRunID:BehaviorRunID?
    public let deliveryRunID:BehaviorRunID?
    public let arrangementRunID:BehaviorRunID?
}

public struct NestSnapshot:Equatable {
    public let id:HabitatObjectID
    public let surfaceID:UInt32
    public let parentAnchor:SurfaceAnchor
    public let rect:CGRect
    public let trayRect:CGRect
    public let foot:CGPoint
    public let trayFoot:CGPoint
    public let scale:CGFloat
    public let blockers:[CGRect]
    public let remainingLifetime:Double
    public let retiring:Bool
    public let retirementAge:Double?
    public let reservation:NestMaterialReservation?
    public let materials:[NestMaterialSnapshot]
    public var available:Int {materials.filter{$0.state == .available}.count}
    public var attached:Int {materials.filter{$0.state == .attached}.count}
    public var delivered:Int {materials.filter{$0.state == .delivered}.count}
    public var arranged:Int {materials.filter{$0.state == .arranged}.count}
    public var spent:Int {materials.filter{$0.state == .spent}.count}
    public var remainingUses:Int {available}
    public var progress:Int {arranged}
    public var completed:Bool {progress==3}
    public var canContinue:Bool {!retiring && remainingLifetime>0 && available+attached+delivered>0}
}

/// 这三条记录是唯一材料账本。不会另建CarriedObject或run道具副本。
struct NestMaterial {
    let id:ScenePropID
    let slot:Int
    var state:NestMaterialState = .available
    var owner:BirdID?
    var cached:ScenePropRenderState
    var fadeRemaining:Double=0
    var pickupRunID:BehaviorRunID?
    var pickupBirdID:BirdID?
    var deliveryRunID:BehaviorRunID?
    var arrangementRunID:BehaviorRunID?
    var arrangementBirdID:BirdID?
}

struct NestState {
    let parentAnchor:SurfaceAnchor
    let traySide:Int
    let displayIDs:[String]
    var host:Surface
    var trayRect:CGRect
    var materials:[NestMaterial]
    var reservation:NestMaterialReservation?
    var progress:Int {materials.filter{$0.state == .arranged}.count}
    var available:Int {materials.filter{$0.state == .available}.count}
    var canContinue:Bool {materials.contains{[NestMaterialState.available,.attached,.delivered].contains($0.state)}}

    mutating func advance(_ dt:Double) {
        for index in materials.indices where materials[index].state == .spent {
            materials[index].fadeRemaining=max(0,materials[index].fadeRemaining-dt)
        }
    }
    mutating func retire(elapsed:Double=0) {
        // 承载面可暂留给恢复飞行；未完成库存不再可访问，不增补第二根。
        for index in materials.indices {
            switch materials[index].state {
            case .attached:
                materials[index].state = .spent;materials[index].owner=nil
                materials[index].fadeRemaining=max(0,NestGeometry.fadeDuration-elapsed)
            case .available,.delivered:
                materials[index].state = .spent;materials[index].owner=nil
                materials[index].fadeRemaining=0
            case .arranged,.spent:break
            }
        }
        reservation=nil
    }
}

extension HabitatObjectStore {
    @discardableResult func reserveNestMaterial(_ id:HabitatObjectID,materialID:ScenePropID,
                                                runID:BehaviorRunID,birdID:BirdID,purpose:NestMaterialPurpose)->Bool {
        guard runID.rawValue>0,birdID.rawValue>0 else {return false}
        let requested=NestMaterialReservation(materialID:materialID,runID:runID,birdID:birdID,purpose:purpose)
        return withNest(id) {object,nest in
            guard !object.retiring,let index=nest.materials.firstIndex(where:{$0.id==materialID}) else {return false}
            if let existing=nest.reservation {return existing==requested}
            // 一次run只可提交一根、一个行为；旧运输不能再预约整理。
            guard !nest.materials.contains(where:{$0.pickupRunID==runID || $0.arrangementRunID==runID}),
                  !nest.materials.contains(where:{$0.owner==birdID}),
                  nest.materials[index].state == (purpose == .carry ? .available:.delivered) else {return false}
            nest.reservation=requested;return true
        }
    }

    @discardableResult func pickupNestMaterial(_ id:HabitatObjectID,materialID:ScenePropID,
                                               runID:BehaviorRunID,birdID:BirdID,contact:ScenePropRenderState)->Bool {
        withNest(id) {object,nest in
            guard !object.retiring,let index=nest.materials.firstIndex(where:{$0.id==materialID}),
                  NestGeometry.validAttachment(contact,id:materialID,scale:object.scale) else {return false}
            let material=nest.materials[index]
            if material.pickupRunID==runID,material.pickupBirdID==birdID,
               [.attached,.delivered,.arranged].contains(material.state) {return true}
            guard nest.reservation==NestMaterialReservation(materialID:materialID,runID:runID,birdID:birdID,purpose:.carry),
                  material.state == .available,material.owner==nil,
                  NestGeometry.contactMatches(contact,material.cached,scale:object.scale) else {return false}
            nest.materials[index].state = .attached;nest.materials[index].owner=birdID
            nest.materials[index].pickupRunID=runID;nest.materials[index].pickupBirdID=birdID
            nest.materials[index].cached=contact
            return true
        }
    }

    @discardableResult func updateNestAttachment(_ id:HabitatObjectID,materialID:ScenePropID,
                                                 runID:BehaviorRunID,birdID:BirdID,contact:ScenePropRenderState)->Bool {
        withNest(id) {object,nest in
            guard !object.retiring,
                  nest.reservation==NestMaterialReservation(materialID:materialID,runID:runID,birdID:birdID,purpose:.carry),
                  let index=nest.materials.firstIndex(where:{$0.id==materialID}),
                  nest.materials[index].state == .attached,nest.materials[index].owner==birdID,
                  NestGeometry.validAttachment(contact,id:materialID,scale:object.scale) else {return false}
            nest.materials[index].cached=contact;return true
        }
    }

    @discardableResult func deliverNestMaterial(_ id:HabitatObjectID,materialID:ScenePropID,
                                                runID:BehaviorRunID,birdID:BirdID,contact:ScenePropRenderState)->Bool {
        withNest(id) {object,nest in
            guard !object.retiring,let index=nest.materials.firstIndex(where:{$0.id==materialID}),
                  NestGeometry.validAttachment(contact,id:materialID,scale:object.scale) else {return false}
            let material=nest.materials[index]
            if material.deliveryRunID==runID,material.pickupBirdID==birdID,
               [.delivered,.arranged].contains(material.state) {return true}
            guard nest.reservation==NestMaterialReservation(materialID:materialID,runID:runID,birdID:birdID,purpose:.carry),
                  material.state == .attached,material.owner==birdID,material.pickupRunID==runID,
                  let point=NestGeometry.materialPoint(slot:material.slot,rect:object.rect,scale:object.scale) else {return false}
            let resting=NestGeometry.render(id:material.id,position:point,worldScale:object.scale,
                anchor:TwigGeometry.surface,blockers:contact.blockers)
            guard NestGeometry.contactMatches(contact,resting,scale:object.scale) else {return false}
            nest.materials[index].state = .delivered;nest.materials[index].owner=nil
            nest.materials[index].deliveryRunID=runID;nest.materials[index].cached=resting
            return true
        }
    }

    @discardableResult func arrangeNestMaterial(_ id:HabitatObjectID,materialID:ScenePropID,
                                                runID:BehaviorRunID,birdID:BirdID)->Bool {
        withNest(id) {object,nest in
            guard !object.retiring,let index=nest.materials.firstIndex(where:{$0.id==materialID}) else {return false}
            let material=nest.materials[index]
            if material.state == .arranged,material.arrangementRunID==runID,material.arrangementBirdID==birdID {return true}
            guard nest.reservation==NestMaterialReservation(materialID:materialID,runID:runID,birdID:birdID,purpose:.build),
                  material.state == .delivered,material.owner==nil,material.deliveryRunID != runID else {return false}
            nest.materials[index].state = .arranged
            nest.materials[index].arrangementRunID=runID;nest.materials[index].arrangementBirdID=birdID
            return true
        }
    }

    /// 先由执行器/Engine缓存真实after-motion喙，再释放；取消不退库存，送达/整理不回滚。
    @discardableResult func releaseNestMaterial(_ id:HabitatObjectID,materialID:ScenePropID,
                                                runID:BehaviorRunID,birdID:BirdID)->Bool {
        withNest(id) {_,nest in
            guard let index=nest.materials.firstIndex(where:{$0.id==materialID}),
                  let lease=nest.reservation,lease.materialID==materialID,lease.runID==runID,lease.birdID==birdID else {return false}
            if nest.materials[index].state == .attached {
                guard nest.materials[index].owner==birdID else {return false}
                nest.materials[index].state = .spent;nest.materials[index].owner=nil
                nest.materials[index].fadeRemaining=NestGeometry.fadeDuration
            }
            nest.reservation=nil;return true
        }
    }

    /// 每次world sample先调用。非暂停的轻微宿主移动保持fraction；失效由Engine统一取消恢复。
    func invalidNestIDs(in engine:BehaviorEngine,sampleDT:Double?=nil)->[HabitatObjectID] {
        var invalid:[HabitatObjectID]=[]
        for id in objects.keys.sorted() {
            guard let object=objects[id],let nest=object.nest,!object.retiring else {continue}
            guard isNestValid(object,in:engine),let host=nest.parentAnchor.host(in:engine.world),
                  SurfaceAnchor.acceptsChange(from:nest.host,to:host,sampleDT:sampleDT),
                  let point=nest.parentAnchor.point(in:engine.world) else {invalid.append(id);continue}
            guard !engine.paused else {continue}
            withNest(id) {object,nest in
                object.rect=NestGeometry.rect(foot:point,scale:object.scale)
                nest.trayRect=NestGeometry.trayRect(foot:point,scale:object.scale,side:nest.traySide)
                nest.host=host
                guard let support=NestGeometry.supportSurfaceRect(foot:point,nest:object.rect,tray:nest.trayRect,
                    host:host,worldScale:object.scale,birdScale:object.scale*CGFloat(engine.settings.catalog.profile(.spottedDove).relativeScale)) else {return false}
                object.surface.rect=support
                let blockers=Geometry.blockers(on:host,surfaces:engine.world.surfaces).map(\.rect)
                for index in nest.materials.indices {
                    let material=nest.materials[index],location:CGPoint?
                    switch material.state {
                    case .available:location=NestGeometry.trayMaterialPoint(slot:material.slot,rect:nest.trayRect,scale:object.scale)
                    case .delivered,.arranged:location=NestGeometry.materialPoint(slot:material.slot,rect:object.rect,scale:object.scale)
                    case .attached,.spent:location=nil
                    }
                    if let location {
                        nest.materials[index].cached=NestGeometry.render(id:material.id,position:location,worldScale:object.scale,
                            anchor:TwigGeometry.surface,blockers:blockers)
                    }
                }
                return true
            }
        }
        return invalid
    }

    func isNestValid(_ object:HabitatObject,in engine:BehaviorEngine)->Bool {
        let world=engine.world
        guard object.kind == .nest,let nest=object.nest,world.nestArtAvailable,engine.settings.nestBuildingEnabled,
              world.scale==object.scale,world.screens==object.screens,world.displays==object.displays,
              world.displayIDs==nest.displayIDs,let host=nest.parentAnchor.host(in:world),
              let foot=nest.parentAnchor.point(in:world),
              !world.surfaces.contains(where:{$0.id==object.surface.id &&
                  ($0.pid != object.surface.pid || $0.habitatKind != .nest)}) else {return false}
        let rect=NestGeometry.rect(foot:foot,scale:object.scale)
        let tray=NestGeometry.trayRect(foot:foot,scale:object.scale,side:nest.traySide)
        guard NestGeometry.supported(foot:foot,nest:rect,tray:tray,host:host,world:world,display:object.display),
              NestGeometry.supportSurfaceRect(foot:foot,nest:rect,tray:tray,host:host,worldScale:object.scale,
                birdScale:object.scale*CGFloat(engine.settings.catalog.profile(.spottedDove).relativeScale)) != nil,
              !engine.fixedPerchSnapshot().contains(where:{$0.rect.insetBy(dx:-50*object.scale,dy:-80*object.scale).intersects(rect.union(tray))})
        else {return false}
        // 暂停不移动道具；新遮挡既检查未来承载区，也检查仍显示的冻结位置。
        if engine.paused && !NestGeometry.supported(foot:object.foot,nest:object.rect,tray:nest.trayRect,
            host:host,world:world,display:object.display) {return false}
        let parentBlockers=Geometry.blockers(on:host,surfaces:world.surfaces).map(\.rect)
        if let lease=nest.reservation,let bird=engine.bird(lease.birdID),bird.state != .flying,
           bird.hostID==object.surface.id,bird.hostPID==object.surface.pid,
           parentBlockers.contains(where:{$0.intersects(engine.bounds(of:bird))}) {return false}
        for material in nest.materials where material.state == .attached {
            guard let value=NestGeometry.attached(material,scale:object.scale,in:engine),
                  world.displays.contains(where:{$0.contains(value.rect)}),
                  !value.blockers.contains(where:{$0.intersects(value.rect)}) else {return false}
            if let owner=material.owner,let bird=engine.bird(owner),bird.state != .flying,
               bird.hostID==object.surface.id,parentBlockers.contains(where:{$0.intersects(value.rect)}) {return false}
        }
        return true
    }

    func captureAttachedSnapshots(in engine:BehaviorEngine) {
        guard !engine.paused else {return}
        for id in objects.keys.sorted() {
            guard objects[id]?.nest != nil else {continue}
            withNest(id) {object,nest in
                for index in nest.materials.indices where nest.materials[index].state == .attached {
                    if let value=nestMaterialRender(nest.materials[index],object:object,in:engine) {
                        nest.materials[index].cached=value
                    }
                }
                return true
            }
        }
    }
    func captureNestAttachments(in engine:BehaviorEngine) {captureAttachedSnapshots(in:engine)}

    private func nestMaterialRender(_ material:NestMaterial,object:HabitatObject,in engine:BehaviorEngine)->ScenePropRenderState? {
        switch material.state {
        case .arranged:return nil
        case .attached:
            guard let value=engine.paused ? material.cached:NestGeometry.attached(material,scale:object.scale,in:engine) else {return nil}
            guard let owner=material.owner,let bird=engine.bird(owner),bird.state != .flying,
                  bird.hostID==object.surface.id,let host=object.nest?.parentAnchor.host(in:engine.world) else {return value}
            return NestGeometry.render(id:material.id,position:value.position,worldScale:object.scale,
                facingRight:!value.mirrored,rotation:value.rotation,
                blockers:Geometry.blockers(on:host,surfaces:engine.world.surfaces).map(\.rect))
        case .spent:
            guard material.fadeRemaining>0 else {return nil}
            let old=material.cached
            return NestGeometry.render(id:material.id,position:old.position,worldScale:object.scale,
                anchor:CGPoint(x:old.anchor.x*16,y:old.anchor.y*16),facingRight:!old.mirrored,
                rotation:old.rotation,opacity:material.fadeRemaining/NestGeometry.fadeDuration,
                blockers:old.blockers+engine.world.surfaces.filter{!$0.isGround && !$0.isHabitat && $0.layer>0}.map(\.rect))
        case .available,.delivered:
            guard let nest=object.nest,let host=nest.parentAnchor.host(in:engine.world) else {return nil}
            let old=material.cached
            return NestGeometry.render(id:material.id,position:old.position,worldScale:object.scale,
                anchor:TwigGeometry.surface,facingRight:!old.mirrored,rotation:old.rotation,
                blockers:Geometry.blockers(on:host,surfaces:engine.world.surfaces).map(\.rect))
        }
    }
    func propSnapshots(in engine:BehaviorEngine)->[ScenePropRenderState] {
        objects.keys.sorted().flatMap {id -> [ScenePropRenderState] in
            guard let object=objects[id],let nest=object.nest else {return []}
            return nest.materials.sorted{$0.id<$1.id}.compactMap{nestMaterialRender($0,object:object,in:engine)}
        }.sorted{$0.id<$1.id}
    }
    func nestSnapshot(in engine:BehaviorEngine)->[NestSnapshot] {
        objects.keys.sorted().compactMap {id in
            guard let object=objects[id],let nest=object.nest else {return nil}
            let materials=nest.materials.sorted{$0.id<$1.id}.map {material in
                let value=nestMaterialRender(material,object:object,in:engine) ?? material.cached
                let lease=nest.reservation.flatMap{$0.materialID==material.id ? $0:nil}
                return NestMaterialSnapshot(id:material.id,slot:material.slot,state:material.state,owner:material.owner,
                    reservedByRun:lease?.runID,reservedBird:lease?.birdID,position:value.position,
                    rotation:value.rotation,mirrored:value.mirrored,
                    opacity:material.state == .arranged || (material.state == .spent && material.fadeRemaining<=0) ? 0:value.opacity,
                    fadeRemaining:material.fadeRemaining,pickupRunID:material.pickupRunID,
                    deliveryRunID:material.deliveryRunID,arrangementRunID:material.arrangementRunID)
            }
            let host=nest.parentAnchor.host(in:engine.world) ?? nest.host
            return NestSnapshot(id:id,surfaceID:object.surface.id,parentAnchor:nest.parentAnchor,
                rect:object.rect,trayRect:nest.trayRect,foot:object.foot,
                trayFoot:CGPoint(x:nest.trayRect.midX,y:nest.trayRect.minY+NestGeometry.trayContactY*object.scale),
                scale:object.scale,blockers:Geometry.blockers(on:host,surfaces:engine.world.surfaces).map(\.rect),
                remainingLifetime:object.remainingLifetime,retiring:object.retiring,retirementAge:object.retirementAge,
                reservation:nest.reservation,materials:materials)
        }
    }
}
