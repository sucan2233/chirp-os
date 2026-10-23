import Foundation
import CoreGraphics

/// A bounded, immutable plan. Preflight uses an isolated Bird and constant
/// samples; neither selection nor rendering consumes the live flight RNG.
struct LeafPlayPlan {
    static let requiredFrames:Set<String> = Set(["stand"]+(0...7).map{"fly\($0)"}+(0...2).map{"land\($0)"})
    static let observeDuration=0.6,settleDuration=0.6,fadeDuration=1.5
    let id:BirdID
    let center:CGPoint
    let origin:CGPoint
    let host:Surface
    let returnSlot:LandingReservation
    let screen:CGRect,display:CGRect,airspace:CGRect
    let scale:CGFloat
    let orbit:PointerOrbit
    let cruise:Double
    let initialRevision:UInt64
    private let envelopes:[CGRect]
    private let envelopeBounds:CGRect
    var leafSize:CGFloat {36*max(0.8,scale)}
    var lead:Double {40/orbit.path.length}
    var orbitDuration:Double {orbit.path.length/cruise}

    static func make(id:BirdID,center:CGPoint,in engine:BehaviorEngine) -> LeafPlayPlan? {
        guard center.x.isFinite,center.y.isFinite,withinBudget(engine),
              let bird=engine.bird(id),engine.birds.contains(where:{$0 === bird}),
              engine.role(of:bird) == .resident,engine.behavior(of:bird)==nil,
              bird.state == .perched,bird.edge == .top,!bird.isDeparting,!bird.needsDestination,
              bird.perchDuration-bird.stateTime>observeDuration+BehaviorEngine.step,
              requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []),
              let host=engine.world.surfaces.first(where:{$0.id==bird.hostID}),
              host.isGround || host.layer==0 else {return nil}
        let scale=engine.spriteScale(for:bird)
        guard scale.isFinite,scale>0,scale<=1.8,finite(host.rect,allowFlat:host.isGround),
              let index=engine.world.screens.firstIndex(where:{$0.contains(center)}),
              engine.world.displays.indices.contains(index) else {return nil}
        let screen=engine.world.screens[index],display=engine.world.displays[index]
        let slot=LandingReservation(bird:id,host:host,fraction:bird.fraction)
        guard finite(screen),finite(display),containsInclusive(screen,bird.position),display.contains(center),
              let destination=slot.point(in:engine),Geometry.distance(destination,bird.position)<0.00001,
              slot.isValid(in:engine),returnIsClear(slot,display:display,in:engine),
              let orbit=PointerOrbit(center:center,origin:bird.position,area:screen,spriteScale:scale) else {return nil}
        let top=max(screen.minY,display.minY)+39*scale
        let bottom=min(screen.maxY,display.maxY-9*scale)
        let left=max(screen.minX,display.minX)+29*scale
        let right=min(screen.maxX,display.maxX)-29*scale
        let airspace=CGRect(x:left,y:top,width:right-left,height:bottom-top)
        guard finite(airspace),containsInclusive(airspace,bird.position) else {return nil}
        let cruise=min(240,max(160,FlightBehavior.cruiseSpeed(bird.profile.id,multiplier:bird.profile.speed)*Bird.flightSpeedMultiplier/2*0.7))
        // Normal species orbit selection is disabled before the explicit one-lap
        // pointer path is installed; no unused randomized orbit is generated.
        let probe=Bird(position:bird.position,fraction:bird.fraction,profile:bird.profile,random:{0.5})
        probe.fly(to:destination,host:host,airspace:airspace,allowsOrbit:false,pointerOrbit:orbit,random:{0.5})
        guard probe.flightDuration.isFinite,probe.flightDuration>0,probe.flightDuration<=30 else {return nil}
        var envelopes:[CGRect]=[]
        var previous=Geometry.landingFootprint(at:probe.position,scale:scale)
        let samples=Int(ceil(probe.flightDuration*30))
        guard samples<=900 else {return nil}
        for _ in 0..<samples {
            probe.tick(1.0/30)
            let next=Geometry.landingFootprint(at:probe.position,scale:scale)
            guard display.contains(next) else {return nil}
            // At <=240 pt/s a 1/30 s sample spans <=8 pt. Inflate the
            // endpoint union so curved segments cannot slip through a panel.
            envelopes.append(previous.union(next).insetBy(dx:-8,dy:-8))
            previous=next
        }
        guard probe.state == .landing,Geometry.distance(probe.position,destination)<0.00001 else {return nil}
        let provisional=LeafPlayPlan(id:id,center:center,origin:bird.position,host:host,returnSlot:slot,
            screen:screen,display:display,airspace:airspace,scale:scale,orbit:orbit,cruise:cruise,
            initialRevision:bird.motionRevision,envelopes:[],envelopeBounds:.null)
        // Check the complete leaf ring and its tangent-to-fall exit, including
        // the rotated sprite envelope. All loops have fixed upper bounds.
        let half=provisional.leafSize/sqrt(2)
        func envelope(_ point:CGPoint) -> CGRect {
            CGRect(x:point.x-half,y:point.y-half,width:half*2,height:half*2)
        }
        var last=envelope(provisional.leafPosition(progress:0))
        guard display.contains(last) else {return nil}
        for index in 1...256 {
            let next=envelope(provisional.leafPosition(progress:Double(index)/256))
            guard display.contains(next) else {return nil}
            envelopes.append(last.union(next).insetBy(dx:-5,dy:-5));last=next
        }
        for index in 1...90 {
            let next=envelope(provisional.fallPosition(age:Double(index)/60))
            guard display.contains(next) else {return nil}
            envelopes.append(last.union(next).insetBy(dx:-5,dy:-5));last=next
        }
        let bounds=envelopes.reduce(CGRect.null){$0.union($1)}
        guard panelsClear(envelopes,bounds:bounds,in:engine) else {return nil}
        return LeafPlayPlan(id:id,center:center,origin:bird.position,host:host,returnSlot:slot,
            screen:screen,display:display,airspace:airspace,scale:scale,orbit:orbit,cruise:cruise,
            initialRevision:bird.motionRevision,envelopes:envelopes,envelopeBounds:bounds)
    }

    private static func finite(_ rect:CGRect,allowFlat:Bool=false) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite && rect.maxX.isFinite && rect.maxY.isFinite && rect.width>0 && (allowFlat ? rect.height>=0:rect.height>0)
    }
    private static func containsInclusive(_ rect:CGRect,_ point:CGPoint) -> Bool {
        point.x>=rect.minX && point.x<=rect.maxX && point.y>=rect.minY && point.y<=rect.maxY
    }
    private static func withinBudget(_ engine:BehaviorEngine) -> Bool {
        engine.world.surfaces.count<=256 && engine.birds.count<=64 &&
            engine.world.screens.count<=16 && engine.world.displays.count<=16 &&
            engine.runtime.landingReservations.count<=64
    }
    private static func intersects(_ a:CGRect,_ b:CGRect) -> Bool {
        let overlap=a.intersection(b);return !overlap.isNull && !overlap.isEmpty
    }
    private static func panelsClear(_ envelopes:[CGRect],bounds:CGRect,in engine:BehaviorEngine) -> Bool {
        let panels=engine.world.surfaces.filter{!$0.isGround && $0.layer>0}
        guard panels.count<=64,panels.allSatisfy({finite($0.rect)}) else {return false}
        // Broad phase rejects distant panels in O(panel count). Narrow phase
        // is bounded by 64 panels x 1,246 envelopes and only reads frozen data.
        return !panels.contains {panel in intersects(bounds,panel.rect) && envelopes.contains{intersects($0,panel.rect)}}
    }
    private static func returnIsClear(_ slot:LandingReservation,display:CGRect,in engine:BehaviorEngine) -> Bool {
        guard let bird=engine.bird(slot.bird),let point=slot.point(in:engine),
              let footprint=slot.footprint(in:engine),let host=slot.host(in:engine),
              display.contains(Geometry.landingFootprint(at:point,scale:engine.spriteScale(for:bird))) else {return false}
        let occupied=engine.birds.compactMap {other -> CGRect? in
            guard other !== bird,!other.isDeparting,
                  let otherHost=engine.world.surfaces.first(where:{$0.id==other.hostID}) else {return nil}
            let scale=engine.spriteScale(for:other)
            return Geometry.landingFootprint(at:Geometry.foot(on:otherHost,fraction:other.fraction,edge:other.edge,scale:scale),scale:scale).insetBy(dx:-8,dy:-8)
        }+engine.runtime.landingReservations.filter{$0.bird != slot.bird}.compactMap{$0.footprint(in:engine)}
        return !occupied.contains{intersects(footprint,$0)} &&
            Geometry.landingRanges(on:host,surfaces:engine.world.surfaces,screen:display,
                scale:engine.spriteScale(for:bird),occupied:occupied).contains{$0.contains(point.x)}
    }
    func geometryIsValid(in engine:BehaviorEngine) -> Bool {
        guard Self.withinBudget(engine),let index=engine.world.screens.firstIndex(of:screen),
              engine.world.displays.indices.contains(index),engine.world.displays[index]==display,
              let currentHost=returnSlot.host(in:engine),currentHost==host,
              returnSlot.isValid(in:engine),Self.returnIsClear(returnSlot,display:display,in:engine) else {return false}
        // Moving a host invalidates the frozen exit corridor. Cancel/recover
        // instead of silently bending a preflighted route through new obstacles.
        return Self.panelsClear(envelopes,bounds:envelopeBounds,in:engine)
    }
    func leafPosition(progress:Double) -> CGPoint {
        let offset=orbit.path.point((min(1,max(0,progress))+lead).truncatingRemainder(dividingBy:1))
        return CGPoint(x:center.x+offset.x,y:center.y+offset.y)
    }
    func fallPosition(age:Double) -> CGPoint {
        let start=leafPosition(progress:1),t=min(Self.fadeDuration,max(0,age))
        let tangent=orbit.path.loopTangent(lead),distance=cruise*0.30*(1-exp(-t/0.30))
        return CGPoint(x:start.x+tangent.x*distance,y:start.y+tangent.y*distance+55*t*t)
    }
    func rotation(progress:Double,fallAge:Double) -> CGFloat {
        let tangent=orbit.path.loopTangent(lead)
        let base=atan2(tangent.y,tangent.x)
        let phase=min(1,max(0,progress))
        let tail=cruise/Double(orbit.radius)*0.30*(1-exp(-max(0,fallAge)/0.30))
        return base+CGFloat(phase*2*Double.pi+tail)
    }
}

final class LeafPlayExecution:BehaviorExecution {
    let kind:BehaviorKind = .leafPlay
    let occupiesEncounter=true,runsWhilePaused=false,timeout=35.0
    let plan:LeafPlayPlan
    let propID:ScenePropID
    var participants:[BirdID] {[plan.id]}
    var propIDs:[ScenePropID] {[propID]}
    var landingReservations:[LandingReservation] {[plan.returnSlot]}
    private var age=0.0,settled=0.0
    private var fallAge:Double?
    private var launched=false
    private var revision:UInt64
    private var initialHop:CGFloat=0

    init(plan:LeafPlayPlan,propID:ScenePropID) {
        self.plan=plan;self.propID=propID;revision=plan.initialRevision
    }
    func start(in engine:BehaviorEngine) {
        if let bird=engine.bird(plan.id) {initialHop=engine.baseHop(for:plan.id,bird:bird)}
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard engine.settings.leafPlayEnabled else {return .cancelled(.settingsChanged)}
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        guard LeafPlayPlan.requiredFrames.isSubset(of:engine.world.availableFrames[bird.profile.id] ?? []) else {return .failed(.missingFrames)}
        guard !bird.isDeparting,bird.motionRevision==revision,bird.edge == .top,
              bird.hostID==plan.host.id,bird.fraction==plan.returnSlot.fraction,
              engine.spriteScale(for:bird)==plan.scale,!bird.needsDestination,
              plan.geometryIsValid(in:engine) else {return .failed(.targetInvalid)}
        if !launched || bird.state != .flying {
            guard bird.state == .perched || (launched && bird.state == .landing),
                  Geometry.distance(bird.position,plan.origin)<0.00001 else {return .failed(.targetInvalid)}
        }
        if launched && bird.orbitProgress == nil {return .failed(.targetInvalid)}
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        // BehaviorRuntime validates immediately before advancing, including
        // while paused. Do not repeat the bounded corridor scan on this tick.
        guard let bird=engine.bird(plan.id) else {return .failed(.missingBird)}
        if engine.world.buttonsDown {return .cancelled(.userInput)}
        age+=dt
        if !launched,age+1e-9>=LeafPlayPlan.observeDuration {
            bird.fly(to:plan.origin,host:plan.host,airspace:plan.airspace,allowsOrbit:false,pointerOrbit:plan.orbit,random:{0.5})
            revision=bird.motionRevision;launched=true
        }
        if launched,let progress=bird.orbitProgress,progress>=1 {
            // Runtime advances before Bird.tick. Include this step only once;
            // snapshots also read Bird's current phase to cover the exit tick.
            fallAge=max(fallAge ?? 0,(progress-1)*plan.orbitDuration)+dt
        }
        if launched,bird.state == .perched {settled+=dt}
        if settled+1e-9>=LeafPlayPlan.settleDuration,(fallAge ?? 0)+1e-9>=LeafPlayPlan.fadeDuration {
            // Validation established that these are the same feet. Reset dwell
            // at completion without changing the landing location.
            bird.perch(on:plan.host,spriteScale:plan.scale);revision=bird.motionRevision
            return .completed
        }
        return nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard launched,![BehaviorReason.replaced,.shutdown].contains(reason),let bird=engine.bird(plan.id),
              !bird.isDeparting,bird.motionRevision==revision else {return}
        // .removed also means removing a prop. An intact finite return route
        // may finish after its prop disappears; removal of the bird needs no work.
        if reason == .removed,plan.geometryIsValid(in:engine),!bird.needsDestination {return}
        if let recovery=engine.plan(for:bird,avoiding:plan.center) {
            recovery.apply(to:bird,random:engine.random)
        } else {
            // No destination remains. Hold continuously until ordinary routing
            // can retry, rather than pursuing a released prop or teleporting.
            bird.fly(to:bird.position,host:nil,arc:0,urgent:true,allowsOrbit:false,random:{0.5})
        }
    }
    func presentation(for id:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard id==plan.id,let bird=engine.bird(id),bird.motionRevision==revision else {return nil}
        if bird.state == .perched {
            let u=min(1,max(0,age/0.35)),hop=launched ? 0:initialHop*(1-u*u*(3-2*u))
            let target=plan.leafPosition(progress:0)
            return BirdPose(frameName:"stand",hopOffset:hop,
                facingRight:launched ? bird.facingRight:target.x>bird.position.x)
        }
        // Leaf play requires actual fly frames, but not optional glide/bank
        // artwork. Keep soaring species airborne rather than falling back to stand.
        let frame=bird.state == .flying ? FlightBehavior.frame(bird.profile.id,age:bird.stateTime,fps:bird.profile.flapFPS):bird.frameName
        return BirdPose(frameName:frame,hopOffset:0,facingRight:bird.facingRight)
    }
    func propSnapshots(in engine:BehaviorEngine) -> [ScenePropRenderState] {
        guard let bird=engine.bird(plan.id),bird.motionRevision==revision else {return []}
        let progress=launched ? (bird.orbitProgress ?? 0):0
        let falling=progress>=1 || fallAge != nil
        let tail=falling ? max(fallAge ?? 0,max(0,progress-1)*plan.orbitDuration):0
        guard tail<LeafPlayPlan.fadeDuration else {return []}
        let t=tail/LeafPlayPlan.fadeDuration
        return [ScenePropRenderState(id:propID,kind:.leaf,
            position:falling ? plan.fallPosition(age:tail):plan.leafPosition(progress:progress),
            size:plan.leafSize,rotation:plan.rotation(progress:progress,fallAge:tail),opacity:1-t*t*(3-2*t),
            blockers:engine.world.surfaces.filter{!$0.isGround && $0.layer>0}.map(\.rect))]
    }
}
