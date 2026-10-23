import Foundation
import CoreGraphics

/// A synchronous, single-owner simulation. Platform adapters serialize commands
/// and snapshots on their UI executor; no behavior installs its own timer.
public final class BehaviorEngine {
    struct Record {let bird:Bird;let role:BirdRole;var visible:Bool}
    private var records:[BirdID:Record]=[:]
    private var identities:[ObjectIdentifier:BirdID]=[:]
    private var order:[BirdID]=[]
    private var nextBirdID:UInt64=1
    let runtime=BehaviorRuntime()
    let poseMixer=PoseMixer()
    let random:EngineRandom
    let perchPlanner:PerchActivityPlanner
    var scheduler=AmbientScheduler()
    private var previewDelay:Double?
    private var accumulator=0.0
    public static let step=1.0/60
    public let seed:UInt64
    /// Fixed-step clock, including steps allowed for manual moves while paused.
    public private(set) var time=0.0
    public private(set) var paused=false
    public private(set) var settings:BirdSettings
    public private(set) var world=BehaviorWorld()
    public var population=Population()
    public var populationEnabled=true
    public var ambientEnabled=true
    public var autonomousRouting=true
    public private(set) var lastArrivalPosition:CGPoint?
    public private(set) var arrivalCount=0
    public private(set) var departureCount=0
    public private(set) var events:[BehaviorEvent]=[]
    private var nextEvent:UInt64=1

    public init(seed:UInt64=UInt64.random(in:0...UInt64.max),settings:BirdSettings=BirdSettings()) {
        self.seed=seed;self.random=EngineRandom(seed:seed);self.settings=settings
        self.perchPlanner=PerchActivityPlanner(seed:seed)
        scheduler.reset(settings.ambientFrequency)
    }
    public var birds:[Bird] {order.compactMap{records[$0].flatMap{$0.visible ? $0.bird:nil}}}
    public var residentCount:Int {records.values.filter{$0.visible && $0.role == .resident && !$0.bird.isDeparting}.count}
    public var passingCount:Int {records.values.filter{$0.visible && $0.role == .transient}.count}
    public var departingCount:Int {records.values.filter{$0.visible && $0.role == .resident && $0.bird.isDeparting}.count}
    public var pendingCount:Int {records.values.filter{!$0.visible}.count}
    public var activeRunCount:Int {runtime.runs.count}
    public var leasedBirdCount:Int {runtime.owners.count}
    public var ambientBusy:Bool {runtime.encounterBusy}
    public var hasPointerPreview:Bool {previewDelay != nil}
    public func id(of bird:Bird) -> BirdID? {identities[ObjectIdentifier(bird)]}
    public func bird(_ id:BirdID) -> Bird? {records[id]?.bird}
    public func role(of bird:Bird) -> BirdRole? {id(of:bird).flatMap{records[$0]?.role}}
    public func behavior(of bird:Bird) -> BehaviorKind? {id(of:bird).flatMap{runtime.kind(for:$0)}}
    public func isHoverable(_ bird:Bird) -> Bool {!bird.isDeparting && behavior(of:bird) != .relocate}
    public func spriteScale(for bird:Bird) -> CGFloat {world.scale*bird.profile.relativeScale}

    @discardableResult func register(_ bird:Bird,role:BirdRole = .resident,visible:Bool=true) -> BirdID {
        if let id=id(of:bird) {return id}
        let id=BirdID(nextBirdID);nextBirdID+=1
        records[id]=Record(bird:bird,role:role,visible:visible)
        identities[ObjectIdentifier(bird)]=id;order.append(id)
        if role == .resident {perchPlanner.register(id,bird:bird)}
        return id
    }
    // Fixture bridge for the existing desktop verifiers. Production spawning
    // goes through the engine's population or behavior commands.
    public func installFixtureBirds(_ values:[Bird]) {
        let keep=Set(values.map(ObjectIdentifier.init))
        for id in order where records[id].map({!keep.contains(ObjectIdentifier($0.bird))}) == true {
            runtime.cancel(bird:id,reason:.removed,in:self);removeRecord(id)
        }
        let newOrder=values.map{register($0)}
        var seen=Set<BirdID>()
        order=newOrder.filter{seen.insert($0).inserted}
    }
    func show(_ id:BirdID) {records[id]?.visible=true}
    func removeRecord(_ id:BirdID) {
        guard let record=records.removeValue(forKey:id) else {return}
        identities.removeValue(forKey:ObjectIdentifier(record.bird));order.removeAll{$0==id}
        perchPlanner.remove(id);poseMixer.remove(id)
        emit(.birdRemoved,participants:[id],reason:.removed)
    }
    func emit(_ type:BehaviorEventType,run:BehaviorRunID?=nil,kind:BehaviorKind?=nil,
              source:BehaviorSource = .automatic,participants:[BirdID]=[],reason:BehaviorReason?=nil) {
        events.append(BehaviorEvent(sequence:nextEvent,time:time,runID:run,kind:kind,source:source,type:type,participants:participants,reason:reason))
        nextEvent+=1
        if events.count>256 {events.removeFirst(events.count-256)}
    }
    public func updateWorld(_ value:BehaviorWorld,sampleDT:Double?=nil) {
        world=value
        if let sampleDT {for bird in birds {bird.updateHost(surfaces:world.surfaces,sampleDT:sampleDT,spriteScale:spriteScale(for:bird))}}
        runtime.validate(in:self)
    }
    public func applySettings(_ value:BirdSettings) {
        settings=value;scheduler.reset(value.ambientFrequency)
        if !value.perchActions {
            runtime.cancel(where:{$0.kind == .rest || $0.kind == .preen},reason:.settingsChanged,in:self)
            perchPlanner.suppressAll()
        }
        if !value.pointerVisits {
            cancelPreview(.settingsChanged)
            runtime.cancel(where:{$0.kind == .pointerVisit},reason:.settingsChanged,in:self)
        }
        if !value.flockPasses {
            // Already visible visitors finish naturally. Pending visitors vanish
            // from their run once the execution observes the disabled setting.
            for id in order where records[id].map({$0.role == .transient && !$0.visible}) == true {removeRecord(id)}
        }
    }
    @discardableResult public func handle(_ command:EngineCommand) -> BehaviorResult {
        switch command {
        case .relocate(let id): return relocate(id)
        case .pointerVisit(let source): return requestPointer(source)
        case .flockPass(let source): return requestFlock(source)
        case .perchAction(let kind,let source):return requestPerchAction(kind,source:source)
        case .previewPointerAfter(let delay):
            guard !paused else {return reject(.pointerVisit,.preview,.paused)}
            guard settings.pointerVisits else {return reject(.pointerVisit,.preview,.disabled)}
            guard !ambientBusy,previewDelay == nil else {return reject(.pointerVisit,.preview,.busy)}
            previewDelay=max(0,min(10,delay.isFinite ? delay:3));return .scheduled
        case .pointerClick:
            scheduler.suppress()
            runtime.cancel(where:{$0.kind == .pointerVisit || $0.kind == .rest || $0.kind == .preen},reason:.userInput,in:self)
            perchPlanner.suppressAll()
        case .pause(let value):
            guard paused != value else {return .accepted}
            paused=value;accumulator=0
            if value {
                cancelPreview(.paused);scheduler.suppress()
                runtime.cancel(where:{$0.kind == .pointerVisit},reason:.paused,in:self)
            }
        case .cancelAmbient(let reason):
            cancelPreview(reason);accumulator=0;scheduler.suppress();perchPlanner.suppressAll()
            let all:[BehaviorReason]=[.sleep,.screensChanged,.spaceChanged,.shutdown]
            runtime.cancel(where:{all.contains(reason) || $0.occupiesEncounter},reason:reason,in:self)
        case .scatter:
            cancelPreview(.userInput);perchPlanner.suppressAll()
            runtime.cancel(where:{!$0.occupiesEncounter || $0.kind == .pointerVisit},reason:.replaced,in:self)
            scheduler.suppress()
            for bird in birds where !bird.isDeparting {_=route(bird)}
        case .remove(let id):
            guard records[id] != nil else {return .rejected(.missingBird)}
            runtime.cancel(bird:id,reason:.removed,in:self);removeRecord(id)
        }
        return .accepted
    }
    private func cancelPreview(_ reason:BehaviorReason) {
        guard previewDelay != nil else {return}
        previewDelay=nil
        emit(.previewResult,kind:.pointerVisit,source:.preview,reason:reason)
    }
    private func reject(_ kind:BehaviorKind,_ source:BehaviorSource,_ reason:BehaviorReason) -> BehaviorResult {
        emit(.rejected,kind:kind,source:source,reason:reason);return .rejected(reason)
    }
    private func relocate(_ id:BirdID) -> BehaviorResult {
        guard let bird=bird(id) else {return reject(.relocate,.user,.missingBird)}
        guard !bird.isDeparting,records[id]?.role == .resident else {return reject(.relocate,.user,.unavailableBird)}
        guard runtime.kind(for:id) != .relocate else {return reject(.relocate,.user,.busy)}
        guard let plan=plan(for:bird,avoiding:bird.position) else {return reject(.relocate,.user,.noSpace)}
        runtime.cancel(bird:id,reason:.replaced,in:self)
        perchPlanner.suppress(id)
        scheduler.suppress()
        return runtime.start(RelocationExecution(id:id,origin:bird.position,plan:plan),source:.user,in:self)
    }
    private func requestPointer(_ source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(.pointerVisit,source,.paused)}
        guard settings.pointerVisits else {return reject(.pointerVisit,source,.disabled)}
        guard !ambientBusy,previewDelay == nil else {return reject(.pointerVisit,source,.busy)}
        guard !world.buttonsDown,let screen=world.screens.first(where:{$0.contains(world.pointer)}) else {return reject(.pointerVisit,source,.noSpace)}
        let candidates=birds.filter {bird in
            bird.state == .perched && bird.edge == .top && !bird.isDeparting && behavior(of:bird)==nil &&
                spriteScale(for:bird)<=1.8 && screen.contains(bird.position)
        }
        // Evaluate geometry without consuming RNG; select only from eligible birds.
        let eligible=candidates.compactMap {bird -> (Bird,Surface,PointerOrbit)? in
            guard let host=world.surfaces.first(where:{$0.id==bird.hostID}),
                  let orbit=PointerOrbit(center:world.pointer,origin:bird.position,area:screen,spriteScale:spriteScale(for:bird)) else {return nil}
            return (bird,host,orbit)
        }
        guard let (bird,host,orbit)=random.element(eligible),let id=id(of:bird) else {return reject(.pointerVisit,source,.noSpace)}
        scheduler.suppress()
        return runtime.start(PointerVisitExecution(id:id,center:world.pointer,host:host,screen:screen,orbit:orbit),source:source,in:self)
    }
    private func requestFlock(_ source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(.flockPass,source,.paused)}
        guard settings.flockPasses else {return reject(.flockPass,source,.disabled)}
        guard !ambientBusy,previewDelay == nil else {return reject(.flockPass,source,.busy)}
        guard let screen=random.element(world.displays) else {return reject(.flockPass,source,.noSpace)}
        let entries=settings.probabilities.entries.filter{$0.points>0 && AmbientFlock.species.contains($0.id)}
        let total=entries.reduce(0){$0+$1.points}
        guard total>0 else {return reject(.flockPass,source,.noSpecies)}
        var ticket=Int(random.unit()*Double(total))
        let species=entries.first {entry in
            if ticket<entry.points {return true};ticket-=entry.points;return false
        }!.id
        let profile=settings.catalog.profile(species),scale=world.scale*profile.relativeScale
        let left=world.displays.map(\.minX).min()!,right=world.displays.map(\.maxX).max()!
        let corridor=CGRect(x:left,y:screen.minY,width:right-left,height:screen.height)
        let plans=AmbientFlock.plan(screen:corridor,rightward:random.unit()<0.5,count:3+Int(random.unit()*3),spriteScale:scale,
                                    speed:FlightBehavior.cruiseSpeed(species,multiplier:profile.speed),random:random.unit)
        guard !plans.isEmpty else {return reject(.flockPass,source,.noSpace)}
        let members=plans.map {plan -> (BirdID,FlockMemberPlan) in
            let bird=Bird(position:plan.path.point(0),fraction:0.5,profile:profile,random:random.unit)
            return (register(bird,role:.transient,visible:false),plan)
        }
        scheduler.suppress()
        let result=runtime.start(FlockPassExecution(members:members),source:source,in:self)
        if !result.accepted {for (id,_) in members {removeRecord(id)}}
        return result
    }
    func supports(_ action:PerchActionKind,bird:Bird) -> Bool {
        action.requiredFrames.isSubset(of:world.availableFrames[bird.profile.id] ?? [])
    }
    func pointerNear(_ bird:Bird) -> Bool {
        Geometry.distance(world.pointer,bird.position)<max(100,72*spriteScale(for:bird))
    }
    func hasUsablePerch(_ bird:Bird) -> Bool {
        guard let hostID=bird.hostID,bird.edge == .top,
              world.surfaces.contains(where:{$0.id==hostID}) else {return false}
        let footprint=Geometry.landingFootprint(at:bird.position,scale:spriteScale(for:bird))
        return world.displays.contains(where:{$0.contains(footprint)}) &&
            Geometry.isLandingVisible(on:hostID,at:bird.position,surfaces:world.surfaces,scale:spriteScale(for:bird))
    }
    private func perchRejection(_ action:PerchActionKind,bird:Bird) -> BehaviorReason? {
        guard !bird.isDeparting,bird.state == .perched,bird.edge == .top,role(of:bird) == .resident,
              !bird.needsDestination,bird.perchDuration-bird.stateTime>7 else {return .unavailableBird}
        guard behavior(of:bird)==nil else {return .busy}
        guard supports(action,bird:bird) else {return .missingFrames}
        guard hasUsablePerch(bird) else {return .noSpace}
        guard !world.buttonsDown else {return .userInput}
        guard !pointerNear(bird) else {return .pointerNearby}
        return nil
    }
    private func requestPerchAction(_ action:PerchActionKind,source:BehaviorSource,target:BirdID?=nil) -> BehaviorResult {
        guard !paused else {return reject(action.behavior,source,.paused)}
        guard settings.perchActions else {return reject(action.behavior,source,.disabled)}
        let candidates=target.map{[$0]} ?? order
        var reasons:[BehaviorReason]=[]
        let eligible=candidates.filter {id in
            guard let record=records[id],record.visible else {return false}
            if let reason=perchRejection(action,bird:record.bird) {reasons.append(reason);return false}
            return true
        }
        guard let id=perchPlanner.select(eligible),let plan=perchPlanner.plan(action,for:id) else {
            let reason=([BehaviorReason.pointerNearby,.userInput,.missingFrames,.noSpace,.busy].first(where:{reasons.contains($0)})) ?? .unavailableBird
            return reject(action.behavior,source,reason)
        }
        perchPlanner.suppress(id)
        return runtime.start(PerchActivityExecution(id:id,plan:plan),source:source,in:self)
    }
    private func updatePerchActivities(_ dt:Double) {
        for id in order {
            guard let record=records[id],record.visible,record.role == .resident else {continue}
            let bird=record.bird
            let enabled=ambientEnabled && settings.perchActions && PerchActionKind.allCases.contains{supports($0,bird:bird)}
            if let action=perchPlanner.candidate(id,bird:bird,dt:dt,enabled:enabled,occupied:runtime.owners[id] != nil,
                quiet:!world.buttonsDown && !pointerNear(bird)),enabled {
                _=requestPerchAction(action,source:.automatic,target:id)
            }
        }
    }
    func plan(for bird:Bird,entering:Bool=false,avoiding:CGPoint?=nil) -> DestinationPlan? {
        DestinationPlanner.plan(for:bird,birds:birds,world:world,entering:entering,avoiding:avoiding,random:random)
    }
    @discardableResult public func route(_ bird:Bird,entering:Bool=false,avoiding:CGPoint?=nil) -> Bool {
        guard let plan=plan(for:bird,entering:entering,avoiding:avoiding) else {return false}
        if let id=id(of:bird) {runtime.cancel(bird:id,reason:.replaced,in:self)}
        plan.apply(to:bird,random:random);return true
    }
    public func bringInBird() {
        guard let point=Migration.outsidePoint(screens:world.displays,right:random.unit()<0.5,fraction:random.value(in:0.2...0.75),margin:80*world.scale*3+20) else {return}
        let bird=Bird(position:point,fraction:random.value(in:0.12...0.88),profile:settings.catalog.profile(settings.probabilities.choose(unit:random.unit())),random:random.unit)
        // Publish an arrival only after it has a continuous route from its real
        // offscreen origin. An incomplete display snapshot must not create an
        // unplanned bird that becomes visible before a later routing attempt.
        guard let plan=plan(for:bird,entering:true) else {return}
        plan.apply(to:bird,random:random)
        register(bird);lastArrivalPosition=point;arrivalCount+=1
    }
    public func sendAway(_ bird:Bird) {
        guard let point=Migration.outsidePoint(screens:world.displays,right:random.unit()<0.5,fraction:random.value(in:0.2...0.75),margin:80*world.scale*3+20) else {return}
        if let id=id(of:bird) {runtime.cancel(bird:id,reason:.replaced,in:self)}
        bird.depart(to:point,duration:max(2.8,Double(Geometry.distance(bird.position,point))/400*Bird.flightSpeedMultiplier))
    }
    public func reconcileLayout() {
        for bird in birds {
            if bird.isDeparting {sendAway(bird)}
            else if bird.state != .flying && world.surfaces.contains(where:{$0.isGround && $0.id==bird.hostID}) {
                bird.updateHost(surfaces:world.surfaces,sampleDT:1,spriteScale:spriteScale(for:bird))
            } else {_=route(bird)}
        }
    }
    public func advance(_ elapsed:Double) {
        guard elapsed.isFinite,elapsed>=0 else {return}
        accumulator+=min(0.05,elapsed)
        var steps=0
        while accumulator+1e-10>=Self.step && steps<3 {
            accumulator=max(0,accumulator-Self.step);steps+=1;step(Self.step)
        }
    }
    private func step(_ dt:Double) {
        time+=dt
        if !paused {
            poseMixer.advance(dt)
            if populationEnabled,let event=population.tick(dt,residents:residentCount,total:residentCount+departingCount,random:random.unit) {
                switch event {
                case .arrive:bringInBird()
                case .depart:if let bird=random.element(birds.filter{!$0.isDeparting && behavior(of:$0)==nil}) {sendAway(bird)}
                }
            }
            if let delay=previewDelay {
                previewDelay=delay-dt
                if delay<=dt {
                    previewDelay=nil
                    let result=requestPointer(.preview)
                    let reason:BehaviorReason?;if case .rejected(let why)=result {reason=why}else{reason=nil}
                    emit(.previewResult,kind:.pointerVisit,source:.preview,reason:reason)
                }
            }
        }
        // Resolve input cancellations and pending spawns before integrating motion.
        runtime.advance(dt,in:self)
        for id in order {
            guard let record=records[id],record.visible,runtime.canAdvance(id,paused:paused) else {continue}
            record.bird.tick(dt)
        }
        for id in order {
            guard let record=records[id],record.visible else {continue}
            let bird=record.bird
            if bird.departureFinished && !world.displays.contains(where:{$0.intersects(bounds(of:bird))}) {
                if record.role == .resident {departureCount+=1}
                removeRecord(id)
            } else if runtime.owners[id]==nil && !paused && autonomousRouting && bird.needsDestination {_=route(bird)}
        }
        if !paused {updatePerchActivities(dt)}
        if !paused && ambientEnabled,let event=scheduler.tick(dt,pointer:world.pointer,buttonsDown:world.buttonsDown,
            pointerEnabled:settings.pointerVisits,flockEnabled:settings.flockPasses,frequency:settings.ambientFrequency,
            busy:ambientBusy || previewDelay != nil,random:random.unit) {
            switch event {
            case .pointerVisit:_=requestPointer(.automatic)
            case .flockPass:_=requestFlock(.automatic)
            }
        }
    }
    func baseHop(for id:BirdID,bird:Bird) -> CGFloat {poseMixer.hop(for:id,bird:bird)}
    private func drawableFrame(_ requested:String,for bird:Bird) -> String {
        // A missing manifest preserves legacy adapters. An explicit partial
        // manifest must never hide a bird just because its idle frame is absent.
        guard let frames=world.availableFrames[bird.profile.id],!frames.isEmpty,
              !frames.contains(requested) else {return requested}
        return frames.contains("stand") ? "stand":frames.sorted().first!
    }
    public func bounds(of bird:Bird) -> CGRect {
        let scale=spriteScale(for:bird)
        let hop=id(of:bird).map{runtime.presentation(for:$0,in:self)?.hopOffset ?? baseHop(for:$0,bird:bird)} ?? bird.hopOffset
        return CGRect(x:bird.position.x-(bird.facingRight ? 29:19)*scale,y:bird.position.y+(hop-39)*scale,width:48*scale,height:48*scale).insetBy(dx:-2,dy:-2)
    }
    public func renderSnapshot() -> [BirdRenderState] {
        birds.compactMap {bird in
            guard let id=id(of:bird) else {return nil}
            let pose=runtime.presentation(for:id,in:self)
            return BirdRenderState(id:id,species:bird.profile.id,position:bird.position,facingRight:bird.facingRight,
                scale:spriteScale(for:bird),hopOffset:pose?.hopOffset ?? baseHop(for:id,bird:bird),frameName:drawableFrame(pose?.frameName ?? bird.frameName,for:bird),
                blockers:bird.blockers(in:world.surfaces),hoverable:isHoverable(bird))
        }
    }
}
