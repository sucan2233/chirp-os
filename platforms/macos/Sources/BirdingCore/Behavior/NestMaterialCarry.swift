import Foundation
import CoreGraphics

struct NestMaterialCarryPlan {
    let visit:NestVisitSchedule
    let carrying:NestVisitJourney
    private init?(visit:NestVisitSchedule) {
        guard visit.isCarry,let carrying=visit.carrying else {return nil}
        self.visit=visit;self.carrying=carrying
    }
    var id:BirdID {visit.id}
    var birdID:BirdID {id}
    var objectID:HabitatObjectID {visit.object.id}
    var nestID:HabitatObjectID {objectID}
    var materialID:ScenePropID {visit.materialID}
    var materialSlot:Int {visit.materialSlot}
    var approach:NestVisitJourney {visit.approach}
    var departure:NestVisitJourney {visit.departure}
    var localFootprint:CGRect {visit.localFootprint}
    var pickup:NestVisitLanding {visit.first}
    var destination:NestVisitLanding {visit.destination}
    var exit:NestVisitLanding {visit.exit}
    var facingRight:Bool {visit.facingRight}
    var maximumPlannedDuration:Double {visit.maximumPlannedDuration}
    func canBegin(in engine:BehaviorEngine)->Bool {visit.canBegin(in:engine)}
    func isSafe(in engine:BehaviorEngine)->Bool {
        visit.geometryValid(in:engine) && approach.safe(in:engine,bird:id) &&
            carrying.safe(in:engine,bird:id) && departure.safe(in:engine,bird:id)
    }
    static func candidates(in engine:BehaviorEngine,source:BehaviorSource,target:HabitatObjectID?=nil)->[Self] {
        NestVisitSchedule.candidates(in:engine,source:source,kind:.nestMaterialCarry,target:target).compactMap{Self(visit:$0)}
    }
}

final class NestMaterialCarryExecution:NestActivityExecution {
    let plan:NestMaterialCarryPlan
    init(plan:NestMaterialCarryPlan) {self.plan=plan;super.init(visit:plan.visit)}
}

/// Shared lifecycle, not a movement system: Runtime supplies the sole elapsed
/// time and Bird.tick supplies all foot positions. Transactions run afterwards.
class NestActivityExecution:NestMotionExecution {
    enum Phase:String {case approach,pickup,carry,place,build,departure,settle}
    let visit:NestVisitSchedule
    var kind:BehaviorKind {visit.kind}
    var participants:[BirdID] {[visit.id]}
    let occupiesEncounter=true
    var timeout:Double {visit.timeout}
    var habitatReservations:[HabitatObjectID] {[visit.object.id]}
    var landingReservations:[LandingReservation] {visit.slots}
    // The store renders the three globally allocated material identities.
    // Borrowing a material never introduces a second run-owned prop snapshot.
    var propIDs:[ScenePropID] {[]}
    private(set) var phase:Phase = .approach
    private(set) var phaseAge=0.0
    private(set) var age=0.0
    private(set) var pickupAge=0.0
    private(set) var placeAge=0.0
    private(set) var buildAge=0.0
    private(set) var pickedUp=false
    private(set) var delivered=false
    private(set) var arranged=false
    private var flightAge=0.0
    private var revision:UInt64?
    private var runID:BehaviorRunID?
    private var finished=false

    init(visit:NestVisitSchedule) {self.visit=visit}
    private var journey:NestVisitJourney {
        switch phase {
        case .approach,.pickup:return visit.approach
        case .carry,.place:return visit.carrying ?? visit.approach
        case .build:return visit.approach
        case .departure,.settle:return visit.departure
        }
    }
    private var landing:NestVisitLanding {
        switch phase {
        case .approach,.pickup:return visit.first
        case .carry,.place,.build:return visit.destination
        case .departure,.settle:return visit.exit
        }
    }
    private var stationary:Bool {
        switch phase {
        case .pickup,.place,.build,.settle:return true
        case .approach,.carry,.departure:return false
        }
    }

    func start(in engine:BehaviorEngine) {
        guard visit.canBegin(in:engine),let run=engine.runtime.owners[visit.id],let bird=engine.bird(visit.id),
              engine.habitatObjects.reserveNestMaterial(visit.object.id,materialID:visit.materialID,
                  runID:run,birdID:visit.id,purpose:visit.isCarry ? .carry:.build) else {return}
        runID=run
        guard bird.beginCoordinatedFlight(visit.approach.route,on:visit.first.host,fraction:visit.first.fraction,
            spriteScale:visit.scale,allowExpiredPerch:true,localFootprint:visit.localFootprint) else {
            release(in:engine);return
        }
        revision=bird.motionRevision
    }
    func validate(in engine:BehaviorEngine)->BehaviorCompletion? {
        guard engine.settings.nestBuildingEnabled,
              engine.settings.probabilities.entries.contains(where:{$0.id == .spottedDove && $0.points>0})
        else {return .cancelled(.settingsChanged)}
        guard !engine.world.interruptingButtonsDown else {return .cancelled(.userInput)}
        guard engine.world.nestArtAvailable,
              visit.requiredFrames.isSubset(of:engine.world.availableFrames[.spottedDove] ?? [])
        else {return .failed(.missingFrames)}
        guard let bird=engine.bird(visit.id) else {return .failed(.missingBird)}
        guard let runID,engine.runtime.owners[visit.id]==runID,let revision,bird.motionRevision==revision,
              !bird.isDeparting,engine.role(of:bird) == .resident,bird.profile.id == .spottedDove,
              bird.edge == .top,bird.isCoordinatedFlying,
              let current=engine.habitatObjects.objects[visit.object.id],let nest=current.nest,
              nest.reservation==NestMaterialReservation(materialID:visit.materialID,runID:runID,
                  birdID:visit.id,purpose:visit.isCarry ? .carry:.build),
              let material=nest.materials.first(where:{$0.id==visit.materialID}),
              visit.geometryValid(in:engine) else {return .failed(.targetInvalid)}
        let state:NestMaterialState=visit.isCarry ? (delivered ? .delivered:pickedUp ? .attached:.available):
            (arranged ? .arranged:.delivered)
        guard material.state==state,material.owner==(state == .attached ? visit.id:nil),
              state != .attached || abs(material.cached.rotation)<1e-9,
              bird.hostID==landing.host.id,bird.hostPID==landing.host.pid,bird.fraction==landing.fraction,
              let actual=bird.coordinatedFlightAge,abs(actual-flightAge)<0.000001,
              Geometry.distance(bird.position,journey.route.position(at:flightAge))<0.01,
              !stationary || bird.state == .perched,
              journey.safe(in:engine,bird:visit.id,after:flightAge),
              visit.departure.safe(in:engine,bird:visit.id,after:phase == .departure || phase == .settle ? flightAge:0)
        else {return .failed(.targetInvalid)}
        if (phase == .approach || phase == .pickup),let carrying=visit.carrying,
           !carrying.safe(in:engine,bird:visit.id) {return .failed(.targetInvalid)}
        if let pose=presentation(for:visit.id,in:engine),
           PoseClip.nestBeakAnchor(species:.spottedDove,frame:pose.frameName)==nil {return .failed(.missingFrames)}
        return nil
    }

    func reconcileWorld(in engine:BehaviorEngine,sampleDT:Double?=nil)->BehaviorCompletion? {
        // Exact frozen host identity/geometry is intentional. Recovery starts at
        // actual feet; neither paused samples nor a small move slide the carrier.
        validate(in:engine)
    }
    func advance(_ dt:Double,in engine:BehaviorEngine)->BehaviorCompletion? {
        guard dt.isFinite,dt>=0,!engine.paused else {return nil}
        age+=dt;phaseAge+=dt
        flightAge=min(journey.route.duration,flightAge+dt)
        switch phase {
        case .pickup:pickupAge+=dt
        case .place:placeAge+=dt
        case .build:buildAge+=dt
        default:break
        }
        // Never decide contact, landing or timeout before this step's Bird.tick.
        return nil
    }

    func resolveMotion(in engine:BehaviorEngine)->BehaviorCompletion? {
        guard !finished,!engine.paused else {return nil}
        if let invalid=validate(in:engine) {return invalid}
        guard let bird=engine.bird(visit.id),let runID else {return .failed(.targetInvalid)}
        switch phase {
        case .approach:
            if landed(bird,on:visit.first) {
                transition(to:visit.isCarry ? .pickup:.build)
            }
        case .pickup:
            if !pickedUp,pickupAge+1e-10>=0.7 {
                guard landed(bird,on:visit.first),let contact=contact(frame:"carryGrip",bird:bird,in:engine),
                      engine.habitatObjects.pickupNestMaterial(visit.object.id,materialID:visit.materialID,
                          runID:runID,birdID:visit.id,contact:contact) else {return .failed(.targetInvalid)}
                pickedUp=true
            }
            if pickupAge+1e-10>=(visit.pickupClip?.duration ?? .infinity) {
                guard pickedUp,let route=visit.carrying,
                      begin(route,to:visit.destination,phase:.carry,bird:bird,in:engine)
                else {return .failed(.targetInvalid)}
            }
        case .carry:
            if landed(bird,on:visit.destination) {transition(to:.place)}
        case .place:
            if !delivered,placeAge+1e-10>=0.4 {
                guard landed(bird,on:visit.destination),let contact=contact(frame:"carryPlace",bird:bird,in:engine),
                      engine.habitatObjects.deliverNestMaterial(visit.object.id,materialID:visit.materialID,
                          runID:runID,birdID:visit.id,contact:contact) else {return .failed(.targetInvalid)}
                delivered=true
            }
            if placeAge+1e-10>=visit.workClip.duration {
                guard delivered,begin(visit.departure,to:visit.exit,phase:.departure,bird:bird,in:engine)
                else {return .failed(.targetInvalid)}
            }
        case .build:
            if !arranged,buildAge+1e-10>=1.9 {
                guard landed(bird,on:visit.destination),
                      buildContactIsReal(bird,in:engine),
                      engine.habitatObjects.arrangeNestMaterial(visit.object.id,materialID:visit.materialID,
                          runID:runID,birdID:visit.id) else {return .failed(.targetInvalid)}
                arranged=true
            }
            if buildAge+1e-10>=visit.workClip.duration {
                guard arranged,begin(visit.departure,to:visit.exit,phase:.departure,bird:bird,in:engine)
                else {return .failed(.targetInvalid)}
            }
        case .departure:
            if landed(bird,on:visit.exit) {transition(to:.settle)}
        case .settle:
            if phaseAge+1e-10>=NestVisitGeometry.exitSettle {
                guard landed(bird,on:visit.exit),visit.isCarry ? delivered:arranged else {return .failed(.targetInvalid)}
                release(in:engine);bird.finishCoordinatedFlight();finished=true
                return .completed
            }
        }
        if pickedUp && !delivered,let pose=presentation(for:visit.id,in:engine),
           let value=contact(frame:pose.frameName,bird:bird,in:engine,facingRight:pose.facingRight ?? bird.facingRight) {
            guard engine.habitatObjects.updateNestAttachment(visit.object.id,materialID:visit.materialID,
                runID:runID,birdID:visit.id,contact:value) else {return .failed(.targetInvalid)}
        }
        return nil
    }
    private func transition(to next:Phase) {phase=next;phaseAge=0}
    private func landed(_ bird:Bird,on slot:NestVisitLanding)->Bool {
        bird.state == .perched && bird.hostID==slot.host.id && bird.hostPID==slot.host.pid &&
            bird.fraction==slot.fraction && Geometry.distance(bird.position,slot.foot)<0.001
    }
    private func begin(_ journey:NestVisitJourney,to slot:NestVisitLanding,phase next:Phase,
                       bird:Bird,in engine:BehaviorEngine)->Bool {
        guard bird.state == .perched,Geometry.distance(bird.position,journey.route.position(at:0))<0.001,
              slot.valid(in:engine),journey.safe(in:engine,bird:visit.id) else {return false}
        bird.finishCoordinatedFlight()
        guard bird.beginCoordinatedFlight(journey.route,on:slot.host,fraction:slot.fraction,
            spriteScale:visit.scale,allowExpiredPerch:true,
            localFootprint:next == .carry ? visit.localFootprint:Geometry.landingFootprint(at:.zero,scale:visit.scale))
        else {return false}
        revision=bird.motionRevision;flightAge=0;transition(to:next);return true
    }
    private func contact(frame:String,bird:Bird,in engine:BehaviorEngine,facingRight:Bool?=nil)->ScenePropRenderState? {
        guard let anchor=PoseClip.nestBeakAnchor(species:.spottedDove,frame:frame) else {return nil}
        let facing=facingRight ?? visit.facingRight
        return NestGeometry.render(id:visit.materialID,
            position:anchor.world(foot:bird.position,scale:visit.scale,facingRight:facing),
            worldScale:visit.object.scale,facingRight:facing,rotation:0,
            blockers:bird.blockers(in:engine.world.surfaces))
    }
    private func buildContactIsReal(_ bird:Bird,in engine:BehaviorEngine)->Bool {
        guard let point=NestGeometry.materialPoint(slot:visit.materialSlot,rect:visit.object.rect,scale:visit.object.scale),
              let contact=contact(frame:"nestSettle",bird:bird,in:engine) else {return false}
        let resting=NestGeometry.render(id:visit.materialID,position:point,worldScale:visit.object.scale,anchor:TwigGeometry.surface)
        return NestGeometry.contactMatches(contact,resting,scale:visit.object.scale)
    }
    private func release(in engine:BehaviorEngine) {
        if let runID {
            engine.habitatObjects.releaseNestMaterial(visit.object.id,materialID:visit.materialID,
                runID:runID,birdID:visit.id)
        }
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        // detach has removed Runtime's presentation already. Use this execution's
        // actual current pose to freeze the same material before its .2s fade.
        if pickedUp && !delivered,let runID,let bird=engine.bird(visit.id),
           let pose=presentation(for:visit.id,in:engine),
           let value=contact(frame:pose.frameName,bird:bird,in:engine,facingRight:pose.facingRight ?? bird.facingRight) {
            engine.habitatObjects.updateNestAttachment(visit.object.id,materialID:visit.materialID,
                runID:runID,birdID:visit.id,contact:value)
        }
        release(in:engine)
        guard let bird=engine.bird(visit.id),let revision,bird.motionRevision==revision,!bird.isDeparting,
              engine.runtime.owners[visit.id]==nil || engine.runtime.owners[visit.id]==runID else {return}
        if reason == .replaced {bird.requestFlightRecovery();return}
        if landed(bird,on:visit.exit),
           NestVisitGeometry.slotsClear([visit.exit.reservation],in:engine,bird:visit.id),
           NestVisitGeometry.stationaryClear(visit.exit,localFootprint:Geometry.landingFootprint(at:.zero,scale:visit.scale),
               in:engine,bird:visit.id,display:visit.object.display) {bird.finishCoordinatedFlight()}
        else {engine.recoverFromNest(visit.id,excluding:visit.object.id)}
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine)->BirdPose? {
        guard id==visit.id,let bird=engine.bird(id),let revision,bird.motionRevision==revision else {return nil}
        let frame:String
        if bird.state == .perched {
            switch phase {
            case .pickup:frame=visit.pickupClip?.sample(at:min(pickupAge,max(0,(visit.pickupClip?.duration ?? 0)-1e-9)))?.name ?? "carryLook"
            case .place:frame=visit.workClip.sample(at:min(placeAge,visit.workClip.duration-1e-9))?.name ?? "carryPlace"
            case .build:frame=visit.workClip.sample(at:min(buildAge,visit.workClip.duration-1e-9))?.name ?? "nestPlace"
            default:frame="stand"
            }
        } else {frame=bird.frameName}
        let facing=phase == .pickup || phase == .carry || phase == .place || phase == .build
            ? visit.facingRight:bird.facingRight
        return BirdPose(frameName:frame,hopOffset:0,facingRight:facing)
    }
}
