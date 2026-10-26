import Foundation
import CoreGraphics

/// Gift routes use the existing coordinated-flight sampler. The branch is
/// solely an object receiver; both bird destinations remain ordinary hosts.
struct VisitorGiftPlan {
    static var requiredFrames:Set<String> {SpeciesBehaviorProfile.profile(for:.azureWingedMagpie).requiredFrames(for:.visitorGift)}
    let id:BirdID
    let leafID:ScenePropID
    let receiverSlot:Int
    let receiverRevision:UInt64
    let source:BehaviorSource
    let visitorID:String
    let visitorArchiveSeed:String
    let object:CarriedObject
    let origin:CGPoint
    let initialRevision:UInt64
    let pickup:SurfaceAnchor
    let destination:SurfaceAnchor
    let pickupFoot:CGPoint
    let destinationFoot:CGPoint
    let pickupReservation:LandingReservation
    let destinationReservation:LandingReservation
    let receiverReservation:GiftReceiverReservation
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]
    let displayIDs:[String]
    let birdScale:CGFloat
    let localFootprint:CGRect
    let pickupClip:PoseClip
    let releaseClip:PoseClip
    let approach:LeafCarryJourney
    let carrying:CoordinatedFlightRoute
    let releaseWindow:Range<Double>
    private let carryingEnvelope:FlightSceneEnvelope

    var facingRight:Bool {object.facingRight}
    var maximumPlannedDuration:Double {approach.route.duration+pickupClip.duration+carrying.duration+1.5}
    func worldValid(in engine:BehaviorEngine) -> Bool {
        engine.world.scale==object.worldScale && engine.world.screens==screens &&
            engine.world.displays==displays && engine.world.displayIDs==displayIDs &&
            engine.world.leafCarryArtAvailable && engine.world.fixedPerchArtAvailable
    }
    func receiverValid(in engine:BehaviorEngine) -> Bool {
        receiverReservation.isValid(in:engine,excluding:[id]) &&
            !engine.runtime.giftReceiverReservations.contains(where:{$0.bird != id && receiverReservation.conflicts(with:$0,in:engine)})
    }
    func carryingIsSafe(in engine:BehaviorEngine,after age:Double=0) -> Bool {
        carryingEnvelope.isClear(in:engine,excluding:[id],display:nil,after:age) &&
            carryingEnvelope.pointerIsClear(in:engine,after:age)
    }
    func canBegin(in engine:BehaviorEngine) -> Bool {
        guard engine.settings.visitorGiftsEnabled,engine.settings.visitorMemoryEnabled,engine.settings.fixedPerchesEnabled,
              !engine.paused,!engine.world.buttonsDown,
              engine.settings.probabilities.entries.contains(where:{$0.id == .azureWingedMagpie && $0.points>0}),
              worldValid(in:engine),let bird=engine.bird(id),bird.profile.id == .azureWingedMagpie,
              bird.motionRevision==initialRevision,bird.position==origin,bird.state == .perched,
              bird.stateTime>=1,!bird.isDeparting,bird.edge == .top,
              abs(engine.baseHop(for:id,bird:bird))<0.001,engine.role(of:bird) == .resident,
              engine.spriteScale(for:bird)==birdScale,let visitor=engine.visitor(of:bird),
              visitor.id==visitorID,visitor.visits>=3,visitor.familiarity>=0.6,
              engine.visitorMemoryArchive.seed==visitorArchiveSeed,
              engine.carriedObjects.giftIsAvailable(leafID,in:engine),
              engine.carriedObjects.objects[leafID]?.surfaceAnchor==object.surfaceAnchor,
              Self.requiredFrames.isSubset(of:engine.world.availableFrames[.azureWingedMagpie] ?? []),
              let host=pickup.host(in:engine.world),pickupReservation.isValid(in:engine),
              destinationReservation.isValid(in:engine),receiverValid(in:engine),
              approach.safe(in:engine,bird:id,display:display),carryingIsSafe(in:engine) else {return false}
        return bird.canBeginCoordinatedFlight(approach.route,on:host,fraction:pickup.fraction,
            spriteScale:birdScale,allowExpiredPerch:true)
    }
    /// Authorization may take time. Rebuild only this identity tuple, with no
    /// random draw, no lease and no mutation of the available object's lifetime.
    func revalidate(in engine:BehaviorEngine) -> Self? {
        Self.candidates(in:engine,source:source).first {
            $0.id==id && $0.leafID==leafID && $0.receiverSlot==receiverSlot &&
                $0.receiverRevision==receiverRevision && $0.visitorID==visitorID &&
                $0.visitorArchiveSeed==visitorArchiveSeed
        }
    }
    static func candidates(in engine:BehaviorEngine,source:BehaviorSource) -> [Self] {
        guard !engine.paused,!engine.world.buttonsDown,!engine.ambientBusy,
              source == .automatic || source == .preview,
              engine.settings.visitorGiftsEnabled,engine.settings.visitorMemoryEnabled,
              engine.settings.fixedPerchesEnabled,engine.world.fixedPerchArtAvailable,engine.world.leafCarryArtAvailable,
              engine.settings.probabilities.entries.contains(where:{$0.id == .azureWingedMagpie && $0.points>0}),
              BehaviorDefinitions.definition(for:.visitorGift).isEnabled(settings:engine.settings,source:source),
              source != .automatic || (engine.ambientEnabled && engine.settings.activityRhythm != .quiet),
              !engine.carriedObjects.objects.values.contains(where:{$0.isVisitorGift && $0.state != .retired}),
              let pickupClip=PoseClip.visitorGiftPickup(species:.azureWingedMagpie),
              let releaseClip=PoseClip.visitorGiftRelease(species:.azureWingedMagpie) else {return []}
        let objects=engine.carriedObjects.objects.values.filter{engine.carriedObjects.giftIsAvailable($0.id,in:engine)}.sorted{$0.id<$1.id}
        let birds=engine.birds.filter {bird in
            guard bird.profile.id == .azureWingedMagpie,let id=engine.id(of:bird),
                  engine.runtime.owners[id]==nil,engine.role(of:bird) == .resident,
                  bird.state == .perched,bird.edge == .top,bird.stateTime>=1,!bird.isDeparting,
                  !bird.isSideHopping,!bird.isCoordinatedFlying,engine.hasUsablePerch(bird),
                  abs(engine.baseHop(for:id,bird:bird))<0.001,
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  host.canHostBirds,!host.isHabitat,host.isGround || host.layer==0,
                  let visitor=engine.visitor(of:bird),visitor.visits>=3,visitor.familiarity>=0.6,
                  requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return false}
            return source != .automatic || engine.perchPlanner.automaticWeight(id,kind:.visitorGift)>0
        }.sorted{engine.id(of:$0)!<engine.id(of:$1)!}.prefix(8)
        let perches=engine.fixedPerchSnapshot().sorted{$0.slot<$1.slot}
        var result:[Self]=[]
        for bird in birds {
            guard let id=engine.id(of:bird),let visitor=engine.visitor(of:bird) else {continue}
            let scale=engine.spriteScale(for:bird),worldScale=engine.world.scale
            guard let area=CarriedObjectGeometry.localFootprint(species:bird.profile.id,birdScale:scale,worldScale:worldScale),
                  let releaseAnchor=PoseClip.carryBeakAnchor(species:bird.profile.id,frame:"carryPlace") else {continue}
            for object in objects {
                guard let surface=object.surfaceAnchor.point(in:engine.world),let host=object.surfaceAnchor.host(in:engine.world) else {continue}
                let foot=CarriedObjectGeometry.pickupFoot(surface:surface,worldScale:worldScale,birdScale:scale,facingRight:object.facingRight)
                guard let pickup=SurfaceAnchor.at(foot,on:host,scale:scale),
                      let display=engine.world.displays.first(where:{$0.contains(area.offsetBy(dx:bird.position.x,dy:bird.position.y)) && $0.contains(area.offsetBy(dx:foot.x,dy:foot.y))}),
                      let approach=LeafCarryJourney.make(from:bird.position,to:foot,display:display,
                        worldScale:worldScale,bird:bird,birdScale:scale,localFootprint:area),
                      approach.safe(in:engine,bird:id,display:display),
                      object.remainingLifetime>approach.route.duration+1.5 else {continue}
                let pickupSlot=LandingReservation(bird:id,host:host,fraction:pickup.fraction,localFootprint:area)
                for perch in perches {
                    guard let revision=engine.giftReceiverRevision(slot:perch.slot),display.contains(perch.rect),
                          !engine.birds.contains(where:{$0.hostID==perch.surface.id && $0.hostPID==perch.surface.pid}),
                          !engine.runtime.landingReservations.contains(where:{$0.hostID==perch.surface.id && $0.hostPID==perch.surface.pid}) else {continue}
                    let direction:CGFloat=object.facingRight ? 1:-1
                    // Forward travel and descent are both preflighted. Relative
                    // initial speeds alone do not prove separation throughout
                    // the descent and the bird's turning return leg.
                    let grip=CGPoint(x:perch.foot.x-direction*71*worldScale,y:perch.foot.y-48*worldScale)
                    let beakOffset=releaseAnchor.world(foot:.zero,scale:scale,facingRight:object.facingRight)
                    let releaseEnd=CGPoint(x:grip.x-beakOffset.x,y:grip.y-beakOffset.y)
                    let releaseStart=CGPoint(x:releaseEnd.x-direction*24*worldScale,y:releaseEnd.y)
                    // Facing is persistent object metadata. Do not turn a leaf
                    // around by silently reflecting it during this flight.
                    guard direction*(releaseStart.x-foot.x)>40*worldScale else {continue}
                    let receiverRect=GiftReceiverGeometry.descentRect(from:grip,on:perch,worldScale:worldScale,
                        facingRight:object.facingRight).insetBy(dx:-4*worldScale,dy:-4*worldScale)
                    let receiver=GiftReceiverReservation(bird:id,perch:perch,revision:revision,rect:receiverRect,worldScale:worldScale)
                    guard receiver.isValid(in:engine,excluding:[id]),
                          !engine.runtime.giftReceiverReservations.contains(where:{receiver.conflicts(with:$0,in:engine)}) else {continue}
                    let ordinary=engine.world.surfaces.filter{$0.canHostBirds && !$0.isHabitat && ($0.isGround || $0.layer==0)}.sorted {
                        if ($0.id==host.id) != ($1.id==host.id) {return $0.id==host.id}
                        return $0.id==$1.id ? $0.pid<$1.pid:$0.id<$1.id
                    }
                    var made:Self?
                    for landingHost in ordinary.prefix(16) {
                        for fraction in [CGFloat(0.25),0.5,0.75] {
                            let end=Geometry.foot(on:landingHost,fraction:fraction,edge:.top,scale:scale)
                            guard let destination=SurfaceAnchor.at(end,on:landingHost,scale:scale) else {continue}
                            let landing=LandingReservation(bird:id,host:landingHost,fraction:fraction,localFootprint:area)
                            guard pickupSlot.isValid(in:engine),landing.isValid(in:engine),
                                  !pickupSlot.conflicts(with:landing,in:engine),!receiver.conflicts(with:landing,in:engine),
                                  !engine.runtime.landingReservations.contains(where:{pickupSlot.conflicts(with:$0,in:engine) || landing.conflicts(with:$0,in:engine)}),
                                  let route=makeCarrying(from:foot,releaseStart:releaseStart,releaseEnd:releaseEnd,to:end,
                                    facingRight:object.facingRight,worldScale:worldScale,birdScale:scale),
                                  fits(route,area:area,display:display),
                                  let envelope=FlightSceneEnvelope(routes:[route],offsets:[0],scales:[scale],maximumDuration:30,localFootprints:[area]) else {continue}
                            let startAge=route.legs[0].timing.duration
                            let plan=Self(id:id,leafID:object.id,receiverSlot:perch.slot,receiverRevision:revision,source:source,
                                visitorID:visitor.id,visitorArchiveSeed:engine.visitorMemoryArchive.seed,object:object,
                                origin:bird.position,initialRevision:bird.motionRevision,pickup:pickup,destination:destination,
                                pickupFoot:foot,destinationFoot:end,pickupReservation:pickupSlot,destinationReservation:landing,
                                receiverReservation:receiver,display:display,screens:engine.world.screens,displays:engine.world.displays,
                                displayIDs:engine.world.displayIDs,birdScale:scale,localFootprint:area,pickupClip:pickupClip,
                                releaseClip:releaseClip,approach:approach,carrying:route,
                                releaseWindow:startAge..<(startAge+releaseClip.duration),carryingEnvelope:envelope)
                            guard plan.maximumPlannedDuration<=GiftReceiverGeometry.timeout,plan.canBegin(in:engine),
                                  endClear(pickupSlot,landing,in:engine,excluding:id) else {continue}
                            made=plan;break
                        }
                        if made != nil {break}
                    }
                    if let made {result.append(made)}
                }
            }
        }
        return result
    }
    private static func endClear(_ a:LandingReservation,_ b:LandingReservation,in engine:BehaviorEngine,excluding id:BirdID) -> Bool {
        guard let first=a.footprint(in:engine),let last=b.footprint(in:engine) else {return false}
        return !engine.birds.contains{engine.id(of:$0) != id && (first.intersects(engine.bounds(of:$0)) || last.intersects(engine.bounds(of:$0)))}
    }
    private static func fits(_ route:CoordinatedFlightRoute,area:CGRect,display:CGRect) -> Bool {
        route.legs.allSatisfy {leg in
            let r=leg.path.bounds
            return display.contains(CGRect(x:r.minX+area.minX,y:r.minY+area.minY,
                width:r.width+area.width,height:r.height+area.height))
        }
    }
    private static func makeCarrying(from start:CGPoint,releaseStart:CGPoint,releaseEnd:CGPoint,to end:CGPoint,
                                     facingRight:Bool,worldScale:CGFloat,birdScale:CGFloat) -> CoordinatedFlightRoute? {
        let sign:CGFloat=facingRight ? 1:-1,speed=80*Double(worldScale)
        let distance=Geometry.distance(start,releaseStart)
        let forward=sign*(releaseStart.x-start.x)
        guard forward>0 else {return nil}
        // Preserve the old handle except on near-vertical approaches. Ordered
        // x control points prohibit an initial backwards leg under a fixed pose.
        let handle=min(max(24*worldScale,min(distance*0.3,100*worldScale)),forward*0.75)
        let p=CGPoint(x:start.x,y:start.y-min(80*worldScale,distance*0.35))
        let q=CGPoint(x:releaseStart.x-sign*handle,y:releaseStart.y)
        let path=FlightPath(points:(0...512).map {i in
            let t=Double(i)/512,u=1-t
            return CGPoint(x:start.x*u*u*u+p.x*3*u*u*t+q.x*3*u*t*t+releaseStart.x*t*t*t,
                y:start.y*u*u*u+p.y*3*u*u*t+q.y*3*u*t*t+releaseStart.y*t*t*t)
        })
        let cruise=160*Double(worldScale),ramps=cruise*0.4/2+(cruise+speed)*0.3/2
        let fit=min(1,path.length/max(1,ramps))
        guard let entryTiming=FlightTiming(distance:path.length,cruiseSpeed:cruise,initialSpeed:0,finalSpeed:speed,
            rampIn:0.4*fit,rampOut:0.3*fit),
              let releaseTiming=FlightTiming(distance:Double(Geometry.distance(releaseStart,releaseEnd)),cruiseSpeed:speed,
                initialSpeed:speed,finalSpeed:speed,rampIn:0,rampOut:0),
              abs(releaseTiming.duration-GiftReceiverGeometry.releaseDuration)<1e-6,
              let exit=InsectCatchJourney.leg(from:releaseEnd,velocity:CGPoint(x:sign*speed,y:0),to:end,
                scale:birdScale,preferredCruise:160*Double(worldScale)) else {return nil}
        let entry=CoordinatedFlightLeg(path:path,timing:entryTiming)
        let release=CoordinatedFlightLeg(path:FlightPath(points:[releaseStart,releaseEnd]),timing:releaseTiming)
        guard InsectCatchJourney.continuous(entry,release),InsectCatchJourney.continuous(release,exit) else {return nil}
        return CoordinatedFlightRoute(legs:[entry,release,exit])
    }
}

final class VisitorGiftExecution:BehaviorExecution {
    enum Phase:String {case approach,pickup,carrying,releasing,returning}
    let kind:BehaviorKind = .visitorGift
    let occupiesEncounter=true
    let plan:VisitorGiftPlan
    let token:GiftAuthorizationToken
    var participants:[BirdID] {[plan.id]}
    var propIDs:[ScenePropID] {[plan.leafID]}
    var timeout:Double {GiftReceiverGeometry.timeout}
    var landingReservations:[LandingReservation] {phase == .approach || phase == .pickup ? [plan.pickupReservation,plan.destinationReservation]:[plan.destinationReservation]}
    var giftReceiverReservations:[GiftReceiverReservation] {[plan.receiverReservation]}
    private(set) var phase:Phase = .approach
    private(set) var pickedUp=false
    private(set) var released=false
    private(set) var delivered=false
    private var age=0.0
    private var pickupAge=0.0
    private var revision:UInt64?
    private var runID:BehaviorRunID?
    private var failedStart=false

    init(plan:VisitorGiftPlan,token:GiftAuthorizationToken) {self.plan=plan;self.token=token}
    func start(in engine:BehaviorEngine) {
        guard let run=engine.runtime.owners[plan.id] else {failedStart=true;return}
        runID=run
        let binding=token.binding
        guard binding.isValid,binding.birdID==plan.id,binding.species == .azureWingedMagpie,
              binding.source==plan.source,binding.leafID==plan.leafID,binding.receiverSlot==plan.receiverSlot,
              binding.receiverRevision==plan.receiverRevision,binding.visitorID==plan.visitorID,
              binding.visitorArchiveSeed==plan.visitorArchiveSeed,plan.canBegin(in:engine),
              let bird=engine.bird(plan.id),let host=plan.pickup.host(in:engine.world),
              engine.bindGiftAuthorization(token,run:run),
              engine.carriedObjects.reserveGift(plan.leafID,run:run,bird:plan.id,in:engine),
              bird.beginCoordinatedFlight(plan.approach.route,on:host,fraction:plan.pickup.fraction,
                spriteScale:plan.birdScale,allowExpiredPerch:true,tracksHost:true,localFootprint:plan.localFootprint)
        else {failedStart=true;return}
        revision=bird.motionRevision
    }
    private func motionValid(in engine:BehaviorEngine) -> Bool {
        guard !failedStart,let runID,engine.runtime.owners[plan.id]==runID,
              let bird=engine.bird(plan.id),let revision,bird.motionRevision==revision,
              !bird.isDeparting,bird.isCoordinatedFlying,engine.role(of:bird) == .resident,
              engine.spriteScale(for:bird)==plan.birdScale,plan.worldValid(in:engine) else {return false}
        return true
    }
    func reconcileWorld(in engine:BehaviorEngine,sampleDT:Double?=nil) -> BehaviorCompletion? {
        // Frozen routes reject changed hosts before updateHost can translate the
        // carrier. Cancellation then uses the engine's existing safe recovery.
        guard motionValid(in:engine),plan.receiverValid(in:engine),
              let pickupHost=plan.pickup.host(in:engine.world),let destinationHost=plan.destination.host(in:engine.world),
              plan.pickupReservation.point(in:engine)==plan.pickupFoot,
              plan.destinationReservation.point(in:engine)==plan.destinationFoot,
              let bird=engine.bird(plan.id) else {return .failed(.targetInvalid)}
        let expected=phase == .approach || phase == .pickup ? pickupHost:destinationHost
        guard bird.hostID==expected.id,bird.hostPID==expected.pid else {return .failed(.targetInvalid)}
        let flightAge=bird.coordinatedFlightAge ?? 0
        let route=phase == .approach || phase == .pickup ? plan.approach.route:plan.carrying
        guard Geometry.distance(bird.position,route.position(at:flightAge))<0.01 else {return .failed(.targetInvalid)}
        let safe=phase == .approach || phase == .pickup ?
            plan.approach.safe(in:engine,bird:plan.id,display:plan.display,after:flightAge):plan.carryingIsSafe(in:engine,after:flightAge)
        return safe ? nil:.failed(.targetInvalid)
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard engine.settings.visitorGiftsEnabled,engine.settings.visitorMemoryEnabled,engine.settings.fixedPerchesEnabled,
              engine.settings.probabilities.entries.contains(where:{$0.id == .azureWingedMagpie && $0.points>0}) else {return .cancelled(.settingsChanged)}
        guard !engine.world.interruptingButtonsDown else {return .cancelled(.userInput)}
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard VisitorGiftPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
        guard let visitor=engine.visitor(of:bird),visitor.id==plan.visitorID,visitor.visits>=3,visitor.familiarity>=0.6,
              engine.visitorMemoryArchive.seed==plan.visitorArchiveSeed,motionValid(in:engine),
              let object=engine.carriedObjects.objects[plan.leafID],object.isVisitorGift,
              object.reservedByRun==runID,object.state != .retired,
              (released ? object.giftDelivery != nil:(pickedUp ? object.state == .attached:(object.state == .available || object.state == .placed)))
        else {return .failed(.targetInvalid)}
        return reconcileWorld(in:engine)
    }
    private func contact(frame:String,in engine:BehaviorEngine) -> ScenePropRenderState? {
        guard let bird=engine.bird(plan.id) else {return nil}
        return CarriedObjectGeometry.attached(id:plan.leafID,bird:bird,
            pose:BirdPose(frameName:frame,hopOffset:0,facingRight:plan.facingRight),worldScale:plan.object.worldScale,
            birdScale:plan.birdScale,facingRight:plan.facingRight,blockers:bird.blockers(in:engine.world.surfaces))
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        age+=dt
        guard let bird=engine.bird(plan.id),let runID else {return .failed(.targetInvalid)}
        switch phase {
        case .approach:
            if bird.state == .perched,Geometry.distance(bird.position,plan.pickupFoot)<0.001 {phase = .pickup;pickupAge=0}
        case .pickup:
            guard bird.state == .perched,Geometry.distance(bird.position,plan.pickupFoot)<0.001 else {return .failed(.targetInvalid)}
            pickupAge+=dt
            let gripIndex=plan.pickupClip.frames.firstIndex(where:{$0.name=="carryGrip"}) ?? 2
            let gripStart=plan.pickupClip.frames.prefix(gripIndex).reduce(0){$0+$1.duration}
            if !pickedUp,pickupAge+1e-10>=gripStart {
                guard let value=contact(frame:"carryGrip",in:engine),
                      engine.carriedObjects.pickup(plan.leafID,run:runID,bird:plan.id,contact:value) else {return .failed(.targetInvalid)}
                pickedUp=true
            }
            if pickupAge+1e-10>=plan.pickupClip.duration {
                guard pickedUp,plan.carryingIsSafe(in:engine),let host=plan.destination.host(in:engine.world),
                      age+plan.carrying.duration+1.5<=timeout else {return .failed(.targetInvalid)}
                bird.finishCoordinatedFlight()
                guard bird.beginCoordinatedFlight(plan.carrying,on:host,fraction:plan.destination.fraction,
                    spriteScale:plan.birdScale,allowExpiredPerch:true,tracksHost:true,localFootprint:plan.localFootprint) else {return .failed(.targetInvalid)}
                revision=bird.motionRevision;phase = .carrying
            }
        case .carrying,.releasing,.returning:break
        }
        return nil
    }
    /// Called after the real Bird.tick. A clip boundary is never a guessed foot
    /// position, and a consumed grant has no subsequent fallible store operation.
    func resolveMotion(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard !engine.paused,motionValid(in:engine),let bird=engine.bird(plan.id),let runID else {return .failed(.targetInvalid)}
        guard phase == .carrying || phase == .releasing || phase == .returning else {return nil}
        let flightAge=bird.coordinatedFlightAge ?? 0
        if !released,flightAge+1e-10>=plan.releaseWindow.lowerBound {phase = .releasing}
        if !released,flightAge+1e-10>=plan.releaseWindow.upperBound {
            guard plan.receiverValid(in:engine),plan.carryingIsSafe(in:engine,after:flightAge),
                  let value=contact(frame:"carryPlace",in:engine),
                  let prepared=engine.carriedObjects.prepareGiftRelease(plan.leafID,run:runID,bird:plan.id,
                    receiver:plan.receiverReservation,contact:value,in:engine),
                  engine.consumeGiftAuthorization(token.id,run:runID) else {return .failed(.targetInvalid)}
            engine.carriedObjects.commitGiftRelease(prepared)
            released=true;phase = .returning
        }
        if released {delivered=engine.carriedObjects.giftHasArrived(plan.leafID,in:engine)}
        if delivered,bird.state == .perched,Geometry.distance(bird.position,plan.destinationFoot)<0.001,
           plan.destinationReservation.isValid(in:engine) {
            engine.carriedObjects.releaseReservation(plan.leafID,run:runID)
            engine.invalidateGiftAuthorization(token.id,run:runID)
            bird.finishCoordinatedFlight();return .completed
        }
        return nil
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard id==plan.id,let bird=engine.bird(id),bird.motionRevision==revision else {return nil}
        let frame:String
        if phase == .pickup {frame=plan.pickupClip.sample(at:pickupAge)?.name ?? "carryLook"}
        else if pickedUp,!released,(bird.coordinatedFlightAge ?? 0)+1e-10>=plan.releaseWindow.lowerBound {frame="carryPlace"}
        else {frame=bird.state == .perched ? "stand":bird.frameName}
        return BirdPose(frameName:frame,hopOffset:0,facingRight:phase == .approach || released ? bird.facingRight:plan.facingRight)
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        if let runID {
            engine.invalidateGiftAuthorization(token.id,run:runID)
            if !released,engine.carriedObjects.objects[plan.leafID]?.reservedByRun==runID {
                let frozen=pickedUp ? presentation(for:plan.id,in:engine).flatMap{contact(frame:$0.frameName,in:engine)}:nil
                engine.carriedObjects.retire(plan.leafID,in:engine,
                    immediate:reason == .sleep || reason == .shutdown ||
                        (engine.paused && [BehaviorReason.targetInvalid,.removed,.screensChanged,.spaceChanged,.settingsChanged,.missingBird,.missingFrames].contains(reason)),
                    freezing:frozen)
            }
            engine.carriedObjects.releaseReservation(plan.leafID,run:runID)
        }
        guard let bird=engine.bird(plan.id),let revision,bird.motionRevision==revision,
              !bird.isDeparting,engine.runtime.owners[plan.id]==nil else {return}
        if reason == .replaced {bird.requestFlightRecovery();return}
        if bird.state == .perched,let host=engine.world.surfaces.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
           !host.isHabitat,Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,scale:plan.birdScale))<0.001,
           Geometry.isLandingVisible(on:host.id,at:bird.position,surfaces:engine.world.surfaces,scale:plan.birdScale) {
            bird.finishCoordinatedFlight()
        } else {engine.recoverFromVisitorGift(plan.id)}
    }
}
