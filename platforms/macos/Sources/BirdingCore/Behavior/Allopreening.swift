import Foundation
import CoreGraphics

public enum AllopreeningBehavior {
    public static let supportedSpecies:Set<SpeciesID> = Set(SpeciesBehaviorProfile.species(for:.allopreening))
    public static let contactSeparation:CGFloat = 24
}

/// One helper visits a stationary partner and returns to its original anchor.
/// The single reservation protects both bodies and the whole raised hop corridor.
struct AllopreeningPlan {
    static var requiredFrames:Set<String> {BehaviorDefinitions.definition(for:.allopreening).requiredFrames}
    static let groomingDuration=3.6
    static let settlingDuration=0.2
    // Each hop includes Bird's landing settle and one observation step.
    static var duration:Double {2*(Bird.sideHopDuration+0.45+BehaviorEngine.step)+settlingDuration+groomingDuration}

    /// Helper first, recipient second. Order also fixes their facing throughout.
    let participants:[BirdID]
    let host:Surface
    let scale:CGFloat
    let originalFractions:[CGFloat]
    let originalPositions:[CGPoint]
    let initialRevisions:[UInt64]
    let contactFraction:CGFloat
    let reservation:LandingReservation
    let display:CGRect
    let screens:[CGRect]
    let displays:[CGRect]
    let worldScale:CGFloat

    var duration:Double {Self.duration}
    var contactPoint:CGPoint {Geometry.foot(on:host,fraction:contactFraction,edge:.top,scale:scale)}

    func sweptFootprint(in engine:BehaviorEngine) -> CGRect? {
        guard reservation.host(in:engine)==host else {return nil}
        // LandingReservation includes full sprites at both ends and headroom.
        return reservation.footprint(in:engine)
    }

    private static func intersects(_ a:CGRect,_ b:CGRect) -> Bool {
        let cut=a.intersection(b);return !cut.isNull && !cut.isEmpty
    }

    func pointerIsClear(in engine:BehaviorEngine) -> Bool {
        let pointer=engine.world.pointer,radius=max(100,90*scale)
        guard pointer.x.isFinite,pointer.y.isFinite,let area=sweptFootprint(in:engine) else {return false}
        return !Self.intersects(area,CGRect(x:pointer.x-radius,y:pointer.y-radius,width:2*radius,height:2*radius))
    }

    func isSafe(in engine:BehaviorEngine) -> Bool {
        guard engine.world.screens==screens,engine.world.displays==displays,engine.world.scale==worldScale,
              reservation.host(in:engine)==host,reservation.isValid(in:engine),
              let area=sweptFootprint(in:engine),display.contains(area),
              participants.allSatisfy({id in
                  guard let bird=engine.bird(id) else {return false}
                  return engine.spriteScale(for:bird)==scale
              }) else {return false}
        guard !Geometry.blockers(on:host,surfaces:engine.world.surfaces).contains(where:{Self.intersects(area,$0.rect)})
        else {return false}
        let ids=Set(participants)
        // Internal beak contact is intentional. Every other body, destination,
        // and complete planned path remains an obstacle, even when far away now.
        for bird in engine.birds where engine.id(of:bird).map({!ids.contains($0)}) == true {
            let size=engine.spriteScale(for:bird)
            guard size.isFinite,size>0 else {return false}
            let actual=Geometry.landingFootprint(at:bird.position,scale:size)
                .union(engine.bounds(of:bird)).insetBy(dx:-8,dy:-8)
            if Self.intersects(area,actual) {return false}
            if bird.state == .flying {
                guard let flight=bird.plannedFlightFootprint(scale:size),
                      !Self.intersects(area,flight.insetBy(dx:-8,dy:-8)) else {return false}
            }
            if let target=engine.world.surfaces.first(where:{$0.id==bird.hostID}) {
                let foot=Geometry.foot(on:target,fraction:bird.fraction,edge:bird.edge,scale:size)
                if Self.intersects(area,Geometry.landingFootprint(at:foot,scale:size).insetBy(dx:-8,dy:-8)) {return false}
            }
        }
        for slot in engine.runtime.landingReservations where !ids.contains(slot.bird) {
            guard let occupied=slot.footprint(in:engine),!Self.intersects(area,occupied) else {return false}
        }
        for run in engine.runtime.runs.values {
            guard let traversal=run.execution as? LedgeTraversalExecution,
                  Set(traversal.participants).isDisjoint(with:ids) else {continue}
            guard let occupied=traversal.sweptFootprint(in:engine),!Self.intersects(area,occupied) else {return false}
        }
        return true
    }

    /// Both anchors must still match before installing the first and only move.
    /// Ownership/ecology checks belong to selection: runtime has leased both and
    /// reset their quiet clocks by the time execution.start is called.
    func canBegin(in engine:BehaviorEngine) -> Bool {
        participants.indices.allSatisfy {index in
            guard let bird=engine.bird(participants[index]) else {return false}
            return bird.motionRevision==initialRevisions[index] && bird.position==originalPositions[index] &&
                bird.fraction==originalFractions[index] && bird.hostID==host.id && bird.edge == .top &&
                bird.state == .perched && bird.stateTime>=0.5 && !bird.isDeparting && !bird.needsDestination &&
                !bird.isSideHopping && !bird.isCoordinatedFlying && abs(bird.hopOffset)<0.001 && engine.role(of:bird) == .resident &&
                bird.perchDuration-bird.stateTime>duration+1 &&
                Self.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? [])
        }
    }

    static func candidates(in engine:BehaviorEngine,source:BehaviorSource = .automatic) -> [Self] {
        guard !engine.paused,!engine.world.buttonsDown,engine.world.scale.isFinite,engine.world.scale>0,
              BehaviorDefinitions.definition(for:.allopreening).isEnabled(settings:engine.settings,source:source)
        else {return []}
        let ids=engine.birds.compactMap {bird -> BirdID? in
            guard let id=engine.id(of:bird),engine.role(of:bird) == .resident,engine.runtime.owners[id]==nil,
                  AllopreeningBehavior.supportedSpecies.contains(bird.profile.id),
                  bird.state == .perched,bird.edge == .top,bird.stateTime>=0.5,
                  !bird.isDeparting,!bird.needsDestination,!bird.isSideHopping,!bird.isCoordinatedFlying,
                  bird.perchDuration-bird.stateTime>duration+1,abs(bird.hopOffset)<0.001,
                  requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
                  let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}),host.canHostBirds,!host.isGround,!host.isHabitat,host.layer==0,
                  engine.hasUsablePerch(bird),bird.fraction.isFinite,(0...1).contains(bird.fraction),
                  Geometry.distance(bird.position,Geometry.foot(on:host,fraction:bird.fraction,edge:.top,
                      scale:engine.spriteScale(for:bird)))<0.001 else {return nil}
            if source == .automatic {
                guard let ecology=engine.perchPlanner.ecology(id),ecology.disturbance<0.35,ecology.quietTime>=8,
                      engine.perchPlanner.automaticWeight(id,kind:.allopreening)>0 else {return nil}
            }
            return id
        }.sorted().prefix(16)
        var result:[Self]=[],pairs=0
        for (offset,first) in ids.enumerated() {
            for second in ids.dropFirst(offset+1) {
                guard pairs<12,result.count<4 else {return result}
                pairs+=1
                guard let a=engine.bird(first),let b=engine.bird(second),a.profile.id==b.profile.id,
                      a.hostID==b.hostID,let host=engine.world.surfaces.first(where:{$0.id==a.hostID}),
                      engine.spriteScale(for:a)==engine.spriteScale(for:b) else {continue}
                let scale=engine.spriteScale(for:a),left=Geometry.perchX(0,rect:host.rect),right=Geometry.perchX(1,rect:host.rect)
                guard scale.isFinite,scale>0,right>left else {continue}
                let gap=abs(a.position.x-b.position.x)/scale
                // beginSideHop accepts 60...110 points. Within the requested
                // approximate 95...145 separation, 95...134 reaches contact in
                // one real hop, without clamping the landing or changing Bird.
                guard gap>=95,gap<=145,gap-AllopreeningBehavior.contactSeparation<=110 else {continue}
                for ordered in [[first,second],[second,first]] {
                    guard result.count<4 else {return result}
                    guard let helper=engine.bird(ordered[0]),let recipient=engine.bird(ordered[1]) else {continue}
                    let direction:CGFloat=helper.position.x<recipient.position.x ? 1:-1
                    let x=recipient.position.x-direction*AllopreeningBehavior.contactSeparation*scale
                    let fraction=(x-left)/(right-left)
                    guard fraction.isFinite,(0...1).contains(fraction) else {continue}
                    let span=min(helper.fraction,recipient.fraction)...max(helper.fraction,recipient.fraction)
                    let reservation=LandingReservation(bird:ordered[0],host:host,fraction:helper.fraction,
                        span:span,headroom:Bird.sideHopRise(scale:scale))
                    guard let area=reservation.footprint(in:engine),let display=engine.world.displays.first(where:{$0.contains(area)})
                    else {continue}
                    let plan=Self(participants:ordered,host:host,scale:scale,
                        originalFractions:[helper.fraction,recipient.fraction],originalPositions:[helper.position,recipient.position],
                        initialRevisions:[helper.motionRevision,recipient.motionRevision],contactFraction:fraction,
                        reservation:reservation,display:display,screens:engine.world.screens,displays:engine.world.displays,
                        worldScale:engine.world.scale)
                    if plan.canBegin(in:engine),plan.isSafe(in:engine),plan.pointerIsClear(in:engine) {result.append(plan)}
                }
            }
        }
        return result
    }
}

final class AllopreeningExecution:LedgeTraversalExecution {
    let plan:AllopreeningPlan
    let source:BehaviorSource
    let kind:BehaviorKind = .allopreening
    var participants:[BirdID] {plan.participants}
    var landingReservations:[LandingReservation] {[plan.reservation]}
    var plannedDuration:Double {plan.duration}
    var timeout:Double {plan.duration+1}
    private enum Phase {case approaching,settling,grooming,retreating,finished}
    private var phase:Phase = .approaching
    private var phaseAge=0.0
    private var motionAge=0.0
    private var revisions:[BirdID:UInt64]=[:]
    private var started=false,ended=false

    init(plan:AllopreeningPlan,source:BehaviorSource) {self.plan=plan;self.source=source}
    func sweptFootprint(in engine:BehaviorEngine) -> CGRect? {plan.sweptFootprint(in:engine)}

    func start(in engine:BehaviorEngine) {
        guard !started,!ended else {return}
        started=true
        guard !engine.paused,!engine.world.buttonsDown,
              BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:source),
              plan.canBegin(in:engine),plan.isSafe(in:engine),plan.pointerIsClear(in:engine),
              let helper=engine.bird(participants[0]),let recipient=engine.bird(participants[1]),
              helper.beginSideHop(on:plan.host,to:plan.contactFraction,spriteScale:plan.scale) else {return}
        revisions[participants[0]]=helper.motionRevision
        revisions[participants[1]]=recipient.motionRevision
    }

    private func expectedHelperPosition() -> CGPoint {
        guard phase == .approaching || phase == .retreating else {
            return phase == .finished ? plan.originalPositions[0]:plan.contactPoint
        }
        let t=min(1,motionAge/Bird.sideHopDuration),u=CGFloat(t*t*(3-2*t))
        let start=phase == .approaching ? plan.originalFractions[0]:plan.contactFraction
        let end=phase == .approaching ? plan.contactFraction:plan.originalFractions[0]
        let foot=Geometry.foot(on:plan.host,fraction:start+(end-start)*u,edge:.top,scale:plan.scale)
        return CGPoint(x:foot.x,y:foot.y-Bird.sideHopRise(scale:plan.scale)*CGFloat(sin(.pi*t)))
    }

    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard !ended else {return .failed(.targetInvalid)}
        // Quiet closes new automatic opportunities, but lets an accepted visit finish.
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:engine.settings,source:.preview)
        else {return .cancelled(.settingsChanged)}
        guard !engine.world.interruptingButtonsDown else {return .cancelled(.userInput)}
        for (index,id) in participants.enumerated() {
            guard let bird=engine.bird(id),engine.birds.contains(where:{$0 === bird}) else {return .failed(.missingBird)}
            guard AllopreeningPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? [])
            else {return .failed(.missingFrames)}
            guard revisions[id]==bird.motionRevision,!bird.isDeparting,!bird.needsDestination,bird.edge == .top,
                  bird.hostID==plan.host.id,engine.role(of:bird) == .resident,
                  Geometry.distance(bird.position,index==0 ? expectedHelperPosition():plan.originalPositions[1])<0.01
            else {return .failed(.targetInvalid)}
            if index==1 {
                guard bird.state == .perched,bird.fraction==plan.originalFractions[1],!bird.isSideHopping,!bird.isCoordinatedFlying
                else {return .failed(.targetInvalid)}
            } else if phase == .approaching || phase == .retreating {
                guard bird.isSideHopping,[BirdState.flying,.landing,.perched].contains(bird.state) else {return .failed(.targetInvalid)}
            } else {
                guard bird.state == .perched,!bird.isSideHopping else {return .failed(.targetInvalid)}
            }
        }
        guard plan.isSafe(in:engine) else {return .failed(.targetInvalid)}
        guard plan.pointerIsClear(in:engine) else {return .cancelled(.pointerNearby)}
        return nil
    }

    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard !ended else {return nil}
        guard let helper=engine.bird(participants[0]),revisions[participants[0]]==helper.motionRevision else {return .failed(.targetInvalid)}
        switch phase {
        case .approaching:
            if helper.state == .perched {
                helper.finishSideHop();phase = .settling;phaseAge=0
            } else {motionAge+=dt}
        case .settling:
            phaseAge+=dt
            if phaseAge+1e-9>=AllopreeningPlan.settlingDuration {phase = .grooming;phaseAge=0}
        case .grooming:
            phaseAge+=dt
            if phaseAge+1e-9>=AllopreeningPlan.groomingDuration {
                guard helper.beginSideHop(on:plan.host,to:plan.originalFractions[0],spriteScale:plan.scale)
                else {return .failed(.targetInvalid)}
                revisions[participants[0]]=helper.motionRevision
                phase = .retreating;phaseAge=0
                // This move is installed before the current step's Bird.tick.
                motionAge=dt
            }
        case .retreating:
            if helper.state == .perched {
                helper.finishSideHop();phase = .finished;ended=true;return .completed
            }
            motionAge+=dt
        case .finished:return nil
        }
        return nil
    }

    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard !ended else {return}
        ended=true
        // A contact perch is unsafe for normal stand artwork. Always recover the
        // owned helper, preserving its actual anchor, even after finishSideHop.
        if let helper=engine.bird(participants[0]),revisions[participants[0]]==helper.motionRevision,!helper.isDeparting {
            helper.requestFlightRecovery()
        }
        if let recipient=engine.bird(participants[1]),revisions[participants[1]]==recipient.motionRevision,!recipient.isDeparting {
            let foot=Geometry.foot(on:plan.host,fraction:plan.originalFractions[1],edge:.top,scale:plan.scale)
            if plan.reservation.host(in:engine) != plan.host || !engine.hasUsablePerch(recipient) ||
                Geometry.distance(recipient.position,foot)>=0.001 {recipient.requestFlightRecovery()}
        }
    }

    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard let index=participants.firstIndex(of:id),let bird=engine.bird(id),
              revisions[id]==bird.motionRevision,!bird.isDeparting else {return nil}
        let frame=phase == .grooming ? [0,1,2,1,0,0][Int(phaseAge/0.2)%6]:0
        return BirdPose(frameName:"allopreen\(index==0 ? "Give":"Receive")\(frame)",hopOffset:0,
            facingRight:index==0 ? plan.originalPositions[0].x<plan.originalPositions[1].x:
                plan.originalPositions[1].x<plan.originalPositions[0].x)
    }
}
