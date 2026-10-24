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
    let habitatObjects=HabitatObjectStore()
    private var foodDepartureAttempts:[BirdID:UInt64]=[:]
    private var pendingBathPlacement:Double?
    private let bathRandom:EngineRandom
    private var recoveringHabitatBirds=Set<BirdID>()
    private var pendingFoodTrayPlacement:Double?
    private let foodRandom:EngineRandom
    private let inputRecorder:BehaviorInputRecorder?
    var eventObserver:((BehaviorEvent)->Void)?
    /// Outbound discovery values. Hosts serialize delivery with engine commands;
    /// observers must not issue simulation commands from inside this callback.
    public var observationObserver:((BehaviorObservation)->Void)?
    let poseMixer=PoseMixer()
    let random:EngineRandom
    let perchPlanner:PerchActivityPlanner
    let visitorMemory:VisitorMemory
    var visitorIDs:[BirdID:String]=[:]
    private let habitatRandom:EngineRandom
    private var fixedPerches:[ResolvedFixedPerch]=[]
    private var fixedPerchDepartureAttempts:[BirdID:UInt64]=[:]
    private let socialRandom:EngineRandom
    let ecologyRandom:EngineRandom
    var perception=PointerPerception()
    var attentionRanges:Set<BirdID>=[]
    var clickHandled=false
    var scheduler=AmbientScheduler()
    private struct ScheduledEncounter {let kind:BehaviorKind;var remaining:Double}
    private var scheduledEncounter:ScheduledEncounter?
    private var nextPropID:UInt64=1
    private var accumulator=0.0
    public static let step=1.0/60
    public let seed:UInt64
    /// Fixed-step clock, including steps allowed for manual moves while paused.
    public private(set) var time=0.0
    public private(set) var paused=false
    public private(set) var settings:BirdSettings
    public private(set) var world=BehaviorWorld()
    public var population=Population() {
        didSet {oldValue.stateObserver=nil;observePopulation();recordPopulation(population)}
    }
    public var populationEnabled=true
    public var ambientEnabled=true
    public var autonomousRouting=true
    public private(set) var lastArrivalPosition:CGPoint?
    public private(set) var arrivalCount=0
    public private(set) var departureCount=0
    public private(set) var events:[BehaviorEvent]=[]
    private var nextEvent:UInt64=1

    public init(seed:UInt64=UInt64.random(in:0...UInt64.max),settings:BirdSettings=BirdSettings(),recordInputs:Bool=false) {
        self.seed=seed;self.random=EngineRandom(seed:seed);self.settings=settings
        self.inputRecorder=recordInputs ? BehaviorInputRecorder(seed:seed,settings:settings):nil
        self.perchPlanner=PerchActivityPlanner(seed:seed)
        self.visitorMemory=VisitorMemory(seed:seed)
        self.bathRandom=EngineRandom(seed:seed ^ SceneRandomSalt.bath)
        self.foodRandom=EngineRandom(seed:seed ^ 0x464F4F4454524159)
        self.habitatRandom=EngineRandom(seed:seed ^ 0x5045524348524E47)
        self.socialRandom=EngineRandom(seed:seed ^ 0x534F4349414C524E)
        self.ecologyRandom=EngineRandom(seed:seed ^ 0x45434F5343484544)
        scheduler=AmbientScheduler(seed:seed)
        scheduler.reset(settings.ambientFrequency);observePopulation()
    }
    private func observePopulation() {
        population.stateObserver={ [weak self] value in self?.recordPopulation(value) }
    }
    private func recordPopulation(_ value:Population) {
        if let recorder=inputRecorder,recorder.depth==0 {recorder.append(.population(value))}
    }
    private func beginRecordingInput(_ value:@autoclosure ()->RecordedInput) {
        guard let recorder=inputRecorder else {return}
        if recorder.depth==0 {recorder.append(value())}
        recorder.depth+=1
    }
    private func endRecordingInput() {if let recorder=inputRecorder {recorder.depth-=1}}
    public func recordedInputs() throws -> BehaviorInputLog {
        guard let recorder=inputRecorder,recorder.depth==0 else {throw BehaviorRecordingError.invalid("recording is not enabled or an input is in progress")}
        var result=recorder.log
        result.expected=BehaviorReplayReport(engine:self,events:recorder.events)
        try result.validateEnvelope();return result
    }
    public func saveRecording(to url:URL) throws {try recordedInputs().save(to:url)}
    public var birds:[Bird] {order.compactMap{records[$0].flatMap{$0.visible ? $0.bird:nil}}}
    public var residentCount:Int {records.values.filter{$0.visible && $0.role == .resident && !$0.bird.isDeparting}.count}
    public var passingCount:Int {records.values.filter{$0.visible && $0.role == .transient}.count}
    public var departingCount:Int {records.values.filter{$0.visible && $0.role == .resident && $0.bird.isDeparting}.count}
    public var pendingCount:Int {records.values.filter{!$0.visible}.count}
    public var activeRunCount:Int {runtime.runs.count}
    public var leasedBirdCount:Int {runtime.owners.count}
    public var reservedLandingCount:Int {runtime.landingReservations.count}
    public var ambientBusy:Bool {runtime.encounterBusy}
    private var encounterUnavailable:Bool {
        ambientBusy || runtime.runs.values.contains{[BehaviorKind.foodTrayVisit,.fixedPerchVisit].contains($0.execution.kind)}
    }
    public var hasPointerPreview:Bool {scheduledEncounter?.kind == .pointerVisit}
    public var hasLeafPreview:Bool {scheduledEncounter?.kind == .leafPlay}
    public var sceneFocus:SceneFocus? {scheduler.sceneFocus}
    public var hasBathPlacement:Bool {pendingBathPlacement != nil}
    public var hasFoodTrayPlacement:Bool {pendingFoodTrayPlacement != nil}
    public var habitatReservationCount:Int {runtime.habitatReservations.count}
    public func habitatSnapshot()->[HabitatObjectRenderState] {habitatObjects.snapshot(in:self)}
    public var scenePropCount:Int {runtime.propIDs.count}
    public func propSnapshot() -> [ScenePropRenderState] {runtime.propSnapshots(in:self)}
    public func bathImmersionSnapshot() -> [BirdID:BathImmersionState] {
        var result:[BirdID:BathImmersionState]=[:]
        for run in runtime.runs.values {
            guard let bath=run.execution as? BathVisitExecution,bath.isImmersed,
                  let bird=bird(bath.plan.id) else {continue}
            let object=bath.plan.object,scale=spriteScale(for:bird)
            let facing=bath.presentation(for:bath.plan.id,in:self)?.facingRight ?? bird.facingRight
            let feet=BathGeometry.birdFeetRect
            let localX=facing ? feet.minX:48-feet.maxX,anchorX=facing ? BathGeometry.birdFootAnchor.x:48-BathGeometry.birdFootAnchor.x
            result[bath.plan.id]=BathImmersionState(
                waterRect:BathGeometry.waterRect(in:object.rect,scale:object.scale),
                waterlineY:object.foot.y,
                feetRect:CGRect(x:bird.position.x+(localX-anchorX)*scale,y:bird.position.y+(feet.minY-BathGeometry.birdFootAnchor.y)*scale,width:feet.width*scale,height:feet.height*scale))
        }
        return result
    }
    public func fixedPerchSnapshot() -> [ResolvedFixedPerch] {fixedPerches}
    public func id(of bird:Bird) -> BirdID? {identities[ObjectIdentifier(bird)]}
    public func ecology(of bird:Bird) -> BirdEcologySnapshot? {id(of:bird).flatMap{perchPlanner.ecology($0)}}
    public var visitorMemoryArchive:VisitorMemoryArchive {visitorMemory.archive}
    public var activeVisitorCount:Int {visitorMemory.activeCount}
    public var rememberedVisitorCount:Int {visitorMemory.profileCount}
    public func visitor(of bird:Bird) -> VisitorProfile? {
        id(of:bird).flatMap{visitorIDs[$0]}.flatMap{visitorMemory.profile($0)}
    }
    /// Bootstrap input, before any live identity is registered. Both persistence
    /// and replay use this boundary; an import never rewrites active birds.
    public func restoreVisitorMemory(_ archive:VisitorMemoryArchive) throws {
        guard order.isEmpty else {throw VisitorMemoryError.invalid("cannot restore visitor memory while birds are registered")}
        try visitorMemory.restore(archive)
        var input=RecordedInput(kind:"visitorMemory");input.visitorMemory=archive
        beginRecordingInput(input);endRecordingInput()
    }
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
        if role == .resident {
            let profile=settings.visitorMemoryEnabled ? visitorMemory.acquire(species:bird.profile.id):nil
            if let profile {visitorIDs[id]=profile.id}
            perchPlanner.register(id,bird:bird,temperament:profile?.temperament,familiarity:profile?.familiarity ?? 0)
        }
        return id
    }
    // Fixture bridge for the existing desktop verifiers. Production spawning
    // goes through the engine's population or behavior commands.
    public func installFixtureBirds(_ values:[Bird]) {
        inputRecorder?.log.failure="mutable fixture injection is not recordable; use initial fixtureBirds in a replay file"
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
        if let visitorID=visitorIDs.removeValue(forKey:id) {visitorMemory.release(visitorID)}
        fixedPerchDepartureAttempts.removeValue(forKey:id)
        foodDepartureAttempts.removeValue(forKey:id)
        recoveringHabitatBirds.remove(id)
        perchPlanner.remove(id);poseMixer.remove(id);attentionRanges.remove(id)
        emit(.birdRemoved,participants:[id],reason:.removed)
    }
    @discardableResult func emit(_ type:BehaviorEventType,run:BehaviorRunID?=nil,kind:BehaviorKind?=nil,
              source:BehaviorSource = .automatic,participants:[BirdID]=[],reason:BehaviorReason?=nil) -> BehaviorEvent {
        let event=BehaviorEvent(sequence:nextEvent,time:time,runID:run,kind:kind,source:source,type:type,participants:participants,reason:reason)
        if kind == .bathVisit,[BehaviorEventType.completed,.cancelled,.failed].contains(type) {scheduler.didFinishScene()}
        events.append(event)
        inputRecorder?.event(event);eventObserver?(event)
        nextEvent+=1
        if events.count>256 {events.removeFirst(events.count-256)}
        return event
    }
    public func updateWorld(_ value:BehaviorWorld,sampleDT:Double?=nil) {
        beginRecordingInput(.world(value,sampleDT:sampleDT));defer {endRecordingInput()}
        if world.screens != value.screens || world.displays != value.displays {resetPerception()}
        let previousPerches=world.surfaces.filter(\.isFixedPerch)
        world=value
        refreshFixedPerches(previous:previousPerches)
        refreshHabitatObjects()
        if !value.buttonsDown {clickHandled=false}
        // Contact scenes use fixed anchors. Release them against the new world
        // before host tracking can translate a perched partner or an active hop.
        runtime.validate(in:self,where:{$0.kind == .allopreening})
        if let sampleDT {for bird in birds {bird.updateHost(surfaces:world.surfaces,sampleDT:sampleDT,spriteScale:spriteScale(for:bird))}}
        runtime.validate(in:self)
    }
    public func applySettings(_ value:BirdSettings) {
        beginRecordingInput(.settings(value));defer {endRecordingInput()}
        if value.pointerFollowEnabled != settings.pointerFollowEnabled {
            runtime.cancel(where:{$0.kind == .pointerVisit},reason:.settingsChanged,in:self)
        }
        settings=value;scheduler.reset(value.ambientFrequency)
        if !value.foodTrayEnabled {pendingFoodTrayPlacement=nil;removeHabitatObjects(reason:.settingsChanged,ids:habitatIDs(.foodTray))}
        if !value.bathEnabled {pendingBathPlacement=nil;removeHabitatObjects(reason:.settingsChanged,ids:habitatIDs(.bath))}
        if !value.fixedPerchesEnabled {runtime.cancel(where:{$0.kind == .fixedPerchVisit},reason:.settingsChanged,in:self)}
        refreshFixedPerches(previous:world.surfaces.filter(\.isFixedPerch))
        refreshHabitatObjects()
        for id in visitorIDs.keys {
            let familiarity=value.visitorMemoryEnabled ? visitorIDs[id].flatMap{visitorMemory.profile($0)?.familiarity} ?? 0:0
            perchPlanner.setFamiliarity(familiarity,for:id)
        }
        if !value.leafPlayEnabled {
            if hasLeafPreview {cancelPreview(.settingsChanged)}
            runtime.cancel(where:{$0.kind == .leafPlay},reason:.settingsChanged,in:self)
        }
        if !value.ambientLeafPlayEnabled {
            for run in runtime.runs.values.filter({$0.source == .automatic && $0.execution.kind == .leafPlay}) {
                runtime.cancel(run.id,reason:.settingsChanged,in:self)
            }
        }
        if !value.travelTogetherEnabled {runtime.cancel(where:{$0.kind == .travelTogether},reason:.settingsChanged,in:self)}
        if !value.chaseEnabled {runtime.cancel(where:{$0.kind == .chase},reason:.settingsChanged,in:self)}
        if !value.edgePeekEnabled {
            runtime.cancel(where:{$0.kind == .edgePeek},reason:.settingsChanged,in:self)
            perchPlanner.resetEdgePeekOpportunities()
        }
        if !value.sideHopEnabled {runtime.cancel(where:{$0.kind == .sideHop},reason:.settingsChanged,in:self)}
        if !value.takeoffPreparationEnabled {runtime.cancel(where:{$0.kind == .takeoffPreparation},reason:.settingsChanged,in:self)}
        if !value.passiveAttentionEnabled {
            runtime.cancel(where:{$0.kind == .watch || $0.kind == .alert},reason:.settingsChanged,in:self)
            resetPerception()
        }
        if !value.allopreeningEnabled {runtime.cancel(where:{$0.kind == .allopreening},reason:.settingsChanged,in:self)}
        if !value.socialInteractions {
            runtime.cancel(where:{$0.kind.isSocial},reason:.settingsChanged,in:self)
        }
        if !value.perchActions {
            runtime.cancel(where:{$0.kind.isPerchActivity},reason:.settingsChanged,in:self)
            perchPlanner.suppressAll()
        }
        if !value.pointerVisits {
            if hasPointerPreview {cancelPreview(.settingsChanged)}
            runtime.cancel(where:{$0.kind == .pointerVisit},reason:.settingsChanged,in:self)
        }
        if !value.flockPasses {
            // Already visible visitors finish naturally. Pending visitors vanish
            // from their run once the execution observes the disabled setting.
            for id in order where records[id].map({$0.role == .transient && !$0.visible}) == true {removeRecord(id)}
        }
    }
    @discardableResult public func handle(_ command:EngineCommand) -> BehaviorResult {
        beginRecordingInput(.command(command));defer {endRecordingInput()}
        switch command {
        case .relocate(let id): return relocate(id)
        case .placeBath(let point):return placeBath(at:point)
        case .bathVisit(let source):return requestBathVisit(source:source)
        case .placeBathAfter(let delay):
            guard !paused else {return reject(.bathVisit,.user,.paused)}
            guard settings.bathEnabled else {return reject(.bathVisit,.user,.disabled)}
            guard world.bathArtAvailable else {return reject(.bathVisit,.user,.missingFrames)}
            guard habitatObjects.objects.isEmpty,scheduler.sceneFocus==nil,!hasBathPlacement,!hasFoodTrayPlacement else {return reject(.bathVisit,.user,.busy)}
            pendingBathPlacement=max(0,min(10,delay.isFinite ? delay:3));return .scheduled
        case .cancelBathPlacement:pendingBathPlacement=nil;return .accepted
        case .removeBath:
            pendingBathPlacement=nil;removeHabitatObjects(reason:.removed,ids:habitatIDs(.bath));return .accepted
        case .clearCurrentScene:
            pendingBathPlacement=nil;pendingFoodTrayPlacement=nil
            removeHabitatObjects(reason:.removed);return .accepted
        case .placeFoodTray(let point):return placeFoodTray(at:point)
        case .foodTrayVisit(let source):return requestFoodTrayVisit(source:source)
        case .placeFoodTrayAfter(let delay):
            guard !paused else {return reject(.foodTrayVisit,.user,.paused)}
            guard settings.foodTrayEnabled else {return reject(.foodTrayVisit,.user,.disabled)}
            guard habitatObjects.objects.isEmpty,!hasFoodTrayPlacement,!hasBathPlacement else {return reject(.foodTrayVisit,.user,.busy)}
            pendingFoodTrayPlacement=max(0,min(10,delay.isFinite ? delay:3));return .scheduled
        case .cancelFoodTrayPlacement:pendingFoodTrayPlacement=nil;return .accepted
        case .removeFoodTray:
            pendingFoodTrayPlacement=nil;removeHabitatObjects(reason:.removed,ids:habitatIDs(.foodTray));return .accepted
        case .fixedPerchVisit(let source):return requestFixedPerchVisit(source:source)
        case .allopreening(let source):return requestAllopreening(source:source)
        case .travelTogether(let source):return requestTravelTogether(source:source)
        case .chase(let source):return requestChase(source:source)
        case .edgePeek(let source):return requestEdgePeek(source:source)
        case .sideHop(let source):return requestSideHop(source:source)
        case .prepareTakeoff(let source):return requestTakeoffPreparation(source:source)
        case .pointerVisit(let source): return requestPointer(source)
        case .flockPass(let source): return requestFlock(source)
        case .socialGreeting(let source): return requestSocialGreeting(source)
        case .socialMotion(let kind,let source): return requestSocialMotion(kind,source:source)
        case .perchAction(let kind,let source):return requestPerchAction(kind,source:source)
        case .attention(let kind,let source):return requestAttention(kind,source:source)
        case .previewPointerAfter(let delay):
            guard !paused else {return reject(.pointerVisit,.preview,.paused)}
            guard settings.pointerVisits else {return reject(.pointerVisit,.preview,.disabled)}
            guard !encounterUnavailable,scheduledEncounter == nil else {return reject(.pointerVisit,.preview,.busy)}
            scheduledEncounter=ScheduledEncounter(kind:.pointerVisit,remaining:max(0,min(10,delay.isFinite ? delay:3)));return .scheduled
        case .leafPlay(let point,let source):return requestLeaf(at:point,source:source)
        case .releaseLeafAfter(let delay):
            guard !paused else {return reject(.leafPlay,.preview,.paused)}
            guard settings.leafPlayEnabled else {return reject(.leafPlay,.preview,.disabled)}
            guard !encounterUnavailable,scheduledEncounter == nil else {return reject(.leafPlay,.preview,.busy)}
            scheduledEncounter=ScheduledEncounter(kind:.leafPlay,remaining:max(0,min(10,delay.isFinite ? delay:3)))
            return .scheduled
        case .clearProps,.clearLeaf:
            if case .clearProps=command {pendingBathPlacement=nil;pendingFoodTrayPlacement=nil;removeHabitatObjects(reason:.userInput)}
            if hasLeafPreview {cancelPreview(.userInput)}
            runtime.cancel(where:{$0.kind == .leafPlay},reason:.userInput,in:self)
            scheduler.suppress();return .accepted
        case .removeProp(let id):
            runtime.cancel(where:{$0.propIDs.contains(id)},reason:.removed,in:self)
            return .accepted
        case .pointerClick:
            recordPointerClick(explicit:true)
            scheduler.suppress(reason:.userInput)
            runtime.cancel(where:{$0.kind == .pointerVisit || $0.kind.isPerchActivity || $0.kind.isSocial || $0.kind == .leafPlay || $0.kind == .fixedPerchVisit || $0.kind == .foodTrayVisit || $0.kind == .bathVisit},reason:.userInput,in:self)
            perchPlanner.suppressAll()
        case .pause(let value):
            guard paused != value else {return .accepted}
            paused=value;accumulator=0;resetPerception()
            if value {
                cancelPreview(.paused)
                runtime.cancel(where:{$0.kind == .pointerVisit},reason:.paused,in:self)
            }
        case .cancelAmbient(let reason):
            pendingBathPlacement=nil;pendingFoodTrayPlacement=nil
            if [.sleep,.screensChanged,.spaceChanged,.shutdown].contains(reason) {removeHabitatObjects(reason:reason)}
            cancelPreview(reason);accumulator=0;scheduler.suppress();perchPlanner.suppressAll();resetPerception()
            let all:[BehaviorReason]=[.sleep,.screensChanged,.spaceChanged,.shutdown]
            runtime.cancel(where:{all.contains(reason) || $0.occupiesEncounter},reason:reason,in:self)
        case .scatter:
            cancelPreview(.userInput);perchPlanner.suppressAll()
            runtime.cancel(where:{!$0.occupiesEncounter || $0.kind == .pointerVisit || $0.kind.isSocial || $0.kind == .leafPlay},reason:.replaced,in:self)
            scheduler.suppress(reason:.userInput)
            for bird in birds where !bird.isDeparting {_=route(bird)}
        case .remove(let id):
            guard records[id] != nil else {return .rejected(.missingBird)}
            runtime.cancel(bird:id,reason:.removed,in:self);removeRecord(id)
        }
        return .accepted
    }
    private func cancelPreview(_ reason:BehaviorReason) {
        guard let pending=scheduledEncounter else {return}
        scheduledEncounter=nil
        emit(.previewResult,kind:pending.kind,source:.preview,reason:reason)
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
        scheduler.suppress(reason:.userInput)
        return runtime.start(RelocationExecution(id:id,origin:bird.position,plan:plan),source:.user,in:self)
    }
    private func requestLeaf(at point:CGPoint,source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(.leafPlay,source,.paused)}
        guard BehaviorDefinitions.definition(for:.leafPlay).isEnabled(settings:settings,source:source) else {return reject(.leafPlay,source,.disabled)}
        guard !encounterUnavailable,scheduledEncounter == nil else {return reject(.leafPlay,source,.busy)}
        guard !world.buttonsDown else {return reject(.leafPlay,source,.userInput)}
        guard point.x.isFinite,point.y.isFinite else {return reject(.leafPlay,source,.noSpace)}
        let settled=order.filter {id in
            guard let record=records[id],record.visible,record.role == .resident else {return false}
            return record.bird.state == .perched && record.bird.edge == .top && !record.bird.isDeparting && !record.bird.needsDestination
        }
        guard !settled.isEmpty else {return reject(.leafPlay,source,.unavailableBird)}
        let free=settled.filter{runtime.owners[$0]==nil}
        guard !free.isEmpty else {return reject(.leafPlay,source,.busy)}
        let supported=free.filter {id in
            guard let bird=bird(id) else {return false}
            guard source != .automatic || perchPlanner.automaticWeight(id,kind:.leafPlay)>0 else {return false}
            return LeafPlayPlan.requiredFrames.isSubset(of:world.availableFrames[bird.profile.id] ?? [])
        }
        guard !supported.isEmpty else {return reject(.leafPlay,source,.missingFrames)}
        guard let screen=world.screens.first(where:{$0.contains(point)}) else {return reject(.leafPlay,source,.noSpace)}
        // Cheap geometric rejection precedes the eight expensive path probes.
        // Ineligible birds on another display must not exhaust that budget.
        let candidates=supported.filter {id in
            guard let bird=bird(id) else {return false}
            let scale=spriteScale(for:bird),position=bird.position
            return scale<=1.8 && position.x>=screen.minX && position.x<=screen.maxX &&
                position.y>=screen.minY && position.y<=screen.maxY &&
                PointerOrbit.isPossible(center:point,origin:position,area:screen,spriteScale:scale)
        }.sorted {
            let a=Geometry.distance(bird($0)!.position,point),b=Geometry.distance(bird($1)!.position,point)
            return a == b ? $0<$1:a<b
        }
        for id in candidates.prefix(8) {
            guard let plan=LeafPlayPlan.make(id:id,center:point,in:self) else {continue}
            return startLeaf(plan,source:source)
        }
        return reject(.leafPlay,source,.noSpace)
    }
    func startLeaf(_ plan:LeafPlayPlan,source:BehaviorSource) -> BehaviorResult {
        let prop=ScenePropID(nextPropID);nextPropID+=1
        let result=runtime.start(LeafPlayExecution(plan:plan,propID:prop),source:source,in:self)
        if result.accepted {scheduler.suppress();perchPlanner.suppress(plan.id)}
        return result
    }
    private func requestPointer(_ source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(.pointerVisit,source,.paused)}
        guard BehaviorDefinitions.definition(for:.pointerVisit).isEnabled(settings:settings,source:source) else {return reject(.pointerVisit,source,.disabled)}
        guard !encounterUnavailable,scheduledEncounter == nil else {return reject(.pointerVisit,source,.busy)}
        guard !world.buttonsDown,let screen=world.screens.first(where:{$0.contains(world.pointer)}) else {return reject(.pointerVisit,source,.noSpace)}
        let candidates=birds.filter {bird in
            bird.state == .perched && bird.edge == .top && !bird.isDeparting && behavior(of:bird)==nil &&
                spriteScale(for:bird)<=1.8 && bird.position.x>=screen.minX && bird.position.x<=screen.maxX &&
                bird.position.y>=screen.minY && bird.position.y<=screen.maxY
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
        guard BehaviorDefinitions.definition(for:.flockPass).isEnabled(settings:settings,source:source) else {return reject(.flockPass,source,.disabled)}
        guard !encounterUnavailable,scheduledEncounter == nil else {return reject(.flockPass,source,.busy)}
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
    private func requestSocialGreeting(_ source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(.socialGreeting,source,.paused)}
        guard BehaviorDefinitions.definition(for:.socialGreeting).isEnabled(settings:settings,source:source) else {return reject(.socialGreeting,source,.disabled)}
        guard !encounterUnavailable,scheduledEncounter == nil else {return reject(.socialGreeting,source,.busy)}
        guard !world.buttonsDown else {return reject(.socialGreeting,source,.userInput)}
        var reasons:[BehaviorReason]=[]
        let candidates=order.filter {id in
            guard let record=records[id],record.visible,record.role == .resident else {return false}
            let bird=record.bird
            guard bird.state == .perched,bird.edge == .top,!bird.isDeparting,
                  !bird.needsDestination,bird.perchDuration-bird.stateTime>6 else {return false}
            if runtime.owners[id] != nil {reasons.append(.busy);return false}
            if !SocialGreetingPlan.requiredFrames.isSubset(of:world.availableFrames[bird.profile.id] ?? []) {
                reasons.append(.missingFrames);return false
            }
            if !hasUsablePerch(bird) {reasons.append(.noSpace);return false}
            if pointerNear(bird) {reasons.append(.pointerNearby);return false}
            return true
        }
        var pairs:[(BirdID,BirdID)]=[]
        for (index,first) in candidates.enumerated() {
            for second in candidates.dropFirst(index+1) {
                if let a=bird(first),let b=bird(second),SocialGreetingPlan.eligiblePair(a,b,in:self,
                    hopA:baseHop(for:first,bird:a),hopB:baseHop(for:second,bird:b)) {
                    pairs.append((first,second))
                }
            }
        }
        guard let pair=(source == .automatic ? ecologicalChoice(pairs,weight:{
            self.perchPlanner.automaticWeight($0.0,kind:.socialGreeting)*self.perchPlanner.automaticWeight($0.1,kind:.socialGreeting)
        }):socialRandom.element(pairs)) else {
            let reason=([BehaviorReason.pointerNearby,.missingFrames,.busy,.noSpace].first{reasons.contains($0)}) ?? .noCompanion
            return reject(.socialGreeting,source,reason)
        }
        let reverse=socialRandom.unit()<0.5
        let plan=SocialGreetingPlan(initiator:reverse ? pair.1:pair.0,responder:reverse ? pair.0:pair.1)
        let result=runtime.start(SocialGreetingExecution(plan:plan),source:source,in:self)
        if result.accepted {
            scheduler.suppress()
            perchPlanner.suppress(pair.0);perchPlanner.suppress(pair.1)
        }
        return result
    }
    private func socialMotionCandidates() -> [BirdID] {
        order.filter {id in
            guard let record=records[id],record.visible,record.role == .resident else {return false}
            let bird=record.bird
            return bird.state == .perched && bird.edge == .top && !bird.isDeparting &&
                !bird.needsDestination && bird.perchDuration-bird.stateTime>3 &&
                runtime.owners[id]==nil && hasUsablePerch(bird) && !pointerNear(bird) &&
                SocialMotionPlan.requiredFrames.isSubset(of:world.availableFrames[bird.profile.id] ?? [])
        }
    }
    private func requestSocialMotion(_ action:SocialMotionKind,source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(action.behavior,source,.paused)}
        guard BehaviorDefinitions.definition(for:action.behavior).isEnabled(settings:settings,source:source) else {return reject(action.behavior,source,.disabled)}
        guard !encounterUnavailable,scheduledEncounter==nil else {return reject(action.behavior,source,.busy)}
        guard !world.buttonsDown else {return reject(action.behavior,source,.userInput)}
        let ids=socialMotionCandidates()
        guard ids.count>=2 else {
            let settled=birds.filter{role(of:$0) == .resident && !$0.isDeparting && $0.state == .perched && $0.edge == .top}
            let reason:BehaviorReason
            if settled.count<2 {reason = .noCompanion}
            else if settled.contains(where:{pointerNear($0)}) {reason = .pointerNearby}
            else if settled.contains(where:{!SocialMotionPlan.requiredFrames.isSubset(of:world.availableFrames[$0.profile.id] ?? [])}) {reason = .missingFrames}
            else if settled.contains(where:{behavior(of:$0) != nil}) {reason = .busy}
            else {reason = .noSpace}
            return reject(action.behavior,source,reason)
        }
        let plans=SocialMotionPlanner.candidates(action,ids:ids,in:self)
        guard let plan=(source == .automatic ? ecologicalChoice(plans,weight:{ plan in
            plan.participants.reduce(1){$0*self.perchPlanner.automaticWeight($1,kind:action.behavior)}
        }):socialRandom.element(plans)) else {
            return reject(action.behavior,source,.noSpace)
        }
        let result=runtime.start(SocialMotionExecution(plan:plan),source:source,in:self)
        if result.accepted {
            scheduler.suppress()
            for id in plan.participants {perchPlanner.suppress(id)}
        }
        return result
    }
    private func requestChase(source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(.chase,source,.paused)}
        guard BehaviorDefinitions.definition(for:.chase).isEnabled(settings:settings,source:source) else {return reject(.chase,source,.disabled)}
        guard !encounterUnavailable,scheduledEncounter==nil else {return reject(.chase,source,.busy)}
        guard !world.buttonsDown else {return reject(.chase,source,.userInput)}
        let candidates=ChasePlan.candidates(in:self,source:source)
        guard let plan=(source == .automatic ? ecologicalChoice(candidates,weight:{plan in
            plan.participants.reduce(1){$0*self.perchPlanner.automaticWeight($1,kind:.chase)}
        }):socialRandom.element(candidates)) else {
            let residents=birds.filter{role(of:$0) == .resident && !$0.isDeparting}
            let supported=residents.filter{ChaseBehavior.supportedSpecies.contains($0.profile.id)}
            let paired=supported.filter{bird in supported.contains{$0 !== bird && $0.profile.id==bird.profile.id}}
            let reason:BehaviorReason
            if residents.isEmpty {reason = .noCompanion}
            else if supported.isEmpty {reason = .noSpecies}
            else if paired.isEmpty {reason = .noCompanion}
            else if paired.contains(where:{pointerNear($0)}) {reason = .pointerNearby}
            else if paired.contains(where:{!BehaviorDefinitions.definition(for:.chase).requiredFrames.isSubset(of:world.availableFrames[$0.profile.id] ?? [])}) {reason = .missingFrames}
            else if paired.contains(where:{behavior(of:$0) != nil}) {reason = .busy}
            else {reason = .noSpace}
            return reject(.chase,source,reason)
        }
        let result=runtime.start(ChaseExecution(plan:plan,source:source),source:source,in:self)
        if result.accepted {
            scheduler.suppress()
            for id in plan.participants {perchPlanner.suppress(id)}
        } else if case .rejected(let reason)=result {return reject(.chase,source,reason)}
        return result
    }
    private func requestTravelTogether(source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(.travelTogether,source,.paused)}
        guard BehaviorDefinitions.definition(for:.travelTogether).isEnabled(settings:settings,source:source) else {return reject(.travelTogether,source,.disabled)}
        guard !encounterUnavailable,scheduledEncounter==nil else {return reject(.travelTogether,source,.busy)}
        guard !world.buttonsDown else {return reject(.travelTogether,source,.userInput)}
        let candidates=TravelTogetherPlan.candidates(in:self,source:source)
        guard let plan=(source == .automatic ? ecologicalChoice(candidates,weight:{plan in
            plan.participants.reduce(1){$0*self.perchPlanner.automaticWeight($1,kind:.travelTogether)}
        }):socialRandom.element(candidates)) else {
            let residents=birds.filter{role(of:$0) == .resident && !$0.isDeparting}
            let supported=residents.filter{TravelTogetherBehavior.supportedSpecies.contains($0.profile.id)}
            let paired=supported.filter{bird in supported.contains{$0 !== bird && $0.profile.id==bird.profile.id}}
            let reason:BehaviorReason
            if residents.isEmpty {reason = .noCompanion}
            else if supported.isEmpty {reason = .noSpecies}
            else if paired.isEmpty {reason = .noCompanion}
            else if paired.contains(where:{behavior(of:$0) != nil}) {reason = .busy}
            else if paired.filter({$0.airborneFlight != nil}).count<2 {reason = .unavailableBird}
            else if paired.contains(where:{pointerNear($0)}) {reason = .pointerNearby}
            else if paired.contains(where:{!BehaviorDefinitions.definition(for:.travelTogether).requiredFrames.isSubset(of:world.availableFrames[$0.profile.id] ?? [])}) {reason = .missingFrames}
            else {reason = .noSpace}
            return reject(.travelTogether,source,reason)
        }
        let result=runtime.start(TravelTogetherExecution(plan:plan,source:source),source:source,in:self)
        if result.accepted {
            scheduler.suppress()
            for id in plan.participants {perchPlanner.suppress(id)}
        } else if case .rejected(let reason)=result {return reject(.travelTogether,source,reason)}
        return result
    }
    /// Persistent habitat surfaces are derived from saved anchors, never from
    /// a behavior run. Re-layout releases birds before any host tracking occurs.
    private func refreshFixedPerches(previous:[Surface]) {
        world.surfaces.removeAll(where: \.isFixedPerch)
        fixedPerches=settings.fixedPerchesEnabled && world.fixedPerchArtAvailable ? FixedPerchLayout.resolve(anchors:settings.fixedPerches,world:world):[]
        world.surfaces.append(contentsOf:fixedPerches.map(\.surface))
        runtime.validate(in:self,where:{$0.kind == .fixedPerchVisit})
        for bird in birds {
            guard let old=previous.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  !world.surfaces.contains(old) else {continue}
            if let id=id(of:bird) {runtime.cancel(bird:id,reason:.targetInvalid,in:self)}
            if bird.hostID==old.id,bird.hostPID==old.pid,!bird.isDeparting {bird.requestFlightRecovery()}
        }
    }
    private func placeBath(at point:CGPoint)->BehaviorResult {
        guard !paused else {return reject(.bathVisit,.user,.paused)}
        guard settings.bathEnabled else {return reject(.bathVisit,.user,.disabled)}
        guard world.bathArtAvailable else {return reject(.bathVisit,.user,.missingFrames)}
        guard !world.buttonsDown else {return reject(.bathVisit,.user,.userInput)}
        guard habitatObjects.objects.isEmpty,scheduler.sceneFocus==nil,!hasFoodTrayPlacement else {return reject(.bathVisit,.user,.busy)}
        let placement=habitatObjects.placeBath(at:point,in:self)
        if case .rejected(let reason)=placement {return reject(.bathVisit,.user,reason)}
        guard let id=habitatIDs(.bath).first else {return reject(.bathVisit,.user,.noSpace)}
        guard scheduler.acquireFocus(SceneFocus(objectID:id),frequency:settings.ambientFrequency) else {
            habitatObjects.remove(id);return reject(.bathVisit,.user,.busy)
        }
        refreshHabitatObjects();return .accepted
    }
    private func requestBathVisit(source:BehaviorSource,target:BirdID?=nil)->BehaviorResult {
        guard !paused else {return reject(.bathVisit,source,.paused)}
        guard BehaviorDefinitions.definition(for:.bathVisit).isEnabled(settings:settings,source:source),
              source != .automatic || ambientEnabled else {return reject(.bathVisit,source,.disabled)}
        guard !world.buttonsDown else {return reject(.bathVisit,source,.userInput)}
        guard !ambientBusy,scheduledEncounter==nil,!hasFoodTrayPlacement,!hasBathPlacement,
              !runtime.runs.values.contains(where:{[BehaviorKind.fixedPerchVisit,.foodTrayVisit].contains($0.execution.kind)}) else {return reject(.bathVisit,source,.busy)}
        guard world.bathArtAvailable else {return reject(.bathVisit,source,.missingFrames)}
        guard let object=habitatIDs(.bath).first,habitatObjects.objects[object]?.retiring==false else {return reject(.bathVisit,source,.noSpace)}
        if source == .automatic,!scheduler.canAttemptScene(object) {return reject(.bathVisit,source,.busy)}
        let candidates=BathVisitPlan.candidates(in:self,source:source,target:target)
        guard let plan=bathRandom.element(candidates) else {
            let supported=birds.filter{role(of:$0) == .resident && SpeciesBehaviorProfile.profile(for:$0.profile.id).allows(.bathVisit)}
            let frames=BehaviorDefinitions.definition(for:.bathVisit).requiredFrames
            let reason:BehaviorReason = supported.isEmpty ? .noSpecies:
                supported.allSatisfy({!frames.isSubset(of:world.availableFrames[$0.profile.id] ?? [])}) ? .missingFrames:
                supported.allSatisfy({id(of:$0).map{runtime.owners[$0] != nil} ?? true}) ? .busy:
                supported.allSatisfy({bird in
                    guard bird.state == .perched,bird.stateTime>=1,let id=id(of:bird),
                          let ecology=ecology(of:bird) else {return true}
                    return ecology.quietTime<8 || ecology.disturbance>=0.35 || abs(baseHop(for:id,bird:bird))>=0.001
                }) ? .unavailableBird:
                supported.contains(where:{pointerNear($0)}) ? .pointerNearby:.noSpace
            return reject(.bathVisit,source,reason)
        }
        let splashIDs=(0..<BathGeometry.maximumSplashes).map { _ -> ScenePropID in
            let id=ScenePropID(nextPropID);nextPropID+=1;return id
        }
        let result=runtime.start(BathVisitExecution(plan:plan,splashIDs:splashIDs),source:source,in:self)
        if result.accepted {perchPlanner.suppress(plan.id);scheduler.suppress()}
        else if case .rejected(let reason)=result {return reject(.bathVisit,source,reason)}
        return result
    }
    private func placeFoodTray(at point:CGPoint)->BehaviorResult {
        guard !paused else {return reject(.foodTrayVisit,.user,.paused)}
        guard settings.foodTrayEnabled else {return reject(.foodTrayVisit,.user,.disabled)}
        guard world.foodTrayArtAvailable else {return reject(.foodTrayVisit,.user,.missingFrames)}
        guard !world.buttonsDown else {return reject(.foodTrayVisit,.user,.userInput)}
        guard habitatObjects.objects.isEmpty,!hasBathPlacement else {return reject(.foodTrayVisit,.user,.busy)}
        guard habitatObjects.placeFood(at:point,in:self) else {return reject(.foodTrayVisit,.user,.noSpace)}
        refreshHabitatObjects();return .accepted
    }
    private func requestFoodTrayVisit(source:BehaviorSource,target:BirdID?=nil)->BehaviorResult {
        guard !paused else {return reject(.foodTrayVisit,source,.paused)}
        guard BehaviorDefinitions.definition(for:.foodTrayVisit).isEnabled(settings:settings,source:source) else {return reject(.foodTrayVisit,source,.disabled)}
        guard !world.buttonsDown else {return reject(.foodTrayVisit,source,.userInput)}
        guard !ambientBusy,scheduledEncounter==nil,!hasFoodTrayPlacement,!hasBathPlacement,habitatReservationCount==0 else {return reject(.foodTrayVisit,source,.busy)}
        guard world.foodTrayArtAvailable else {return reject(.foodTrayVisit,source,.missingFrames)}
        guard !habitatIDs(.foodTray).isEmpty else {return reject(.foodTrayVisit,source,.noSpace)}
        let candidates=FoodTrayVisitPlan.candidates(in:self,source:source,target:target)
        guard let plan=(source == .automatic ? ecologicalChoice(candidates,weight:{self.perchPlanner.automaticWeight($0.id,kind:.foodTrayVisit)}):foodRandom.element(candidates)) else {
            let supported=birds.filter{FoodTrayBehavior.supportedSpecies.contains($0.profile.id)}
            let reason:BehaviorReason = supported.isEmpty ? .noSpecies:
                supported.allSatisfy({!FoodTrayVisitPlan.requiredFrames.isSubset(of:world.availableFrames[$0.profile.id] ?? [])}) ? .missingFrames:.noSpace
            return reject(.foodTrayVisit,source,reason)
        }
        let result=runtime.start(FoodTrayVisitExecution(plan:plan),source:source,in:self)
        if result.accepted {perchPlanner.suppress(plan.id)}
        return result
    }
    /// Called after runtime ownership is released. Keep paused birds at their actual
    /// feet, then recover on the first resumed step through the existing planner.
    func recoverFromHabitat(_ id:BirdID,excluding object:HabitatObjectID,immediate:Bool=false) {
        guard let bird=bird(id),!bird.isDeparting else {return}
        bird.requestFlightRecovery()
        recoveringHabitatBirds.insert(id)
        if !paused {resumeHabitatRecovery(id)}
    }
    private func resumeHabitatRecovery(_ id:BirdID) {
        guard !paused else {return}
        guard let bird=bird(id),runtime.owners[id]==nil,!bird.isDeparting else {recoveringHabitatBirds.remove(id);return}
        var recoveryWorld=world
        recoveryWorld.surfaces.removeAll{$0.isHabitat}
        let reserved=runtime.landingReservations.filter{$0.bird != id}.compactMap{$0.footprint(in:self)}
        if let destination=DestinationPlanner.plan(for:bird,birds:birds,world:recoveryWorld,reserved:reserved,random:random),
           destination.host != nil {
            destination.apply(to:bird,random:random)
        } else {
            sendAway(bird)
            // An empty display snapshot still needs a bounded offscreen route.
            if !bird.isDeparting {
                let point=CGPoint(x:bird.position.x+max(200,200*spriteScale(for:bird)),y:bird.position.y-100)
                bird.depart(to:point,duration:2.8)
            }
        }
        recoveringHabitatBirds.remove(id)
    }
    private func habitatIDs(_ kind:HabitatObjectKind)->[HabitatObjectID] {habitatObjects.objects.values.filter{$0.kind==kind}.map(\.id).sorted()}
    private func removeHabitatObjects(reason:BehaviorReason,ids:[HabitatObjectID]?=nil) {
        let targets=Set(ids ?? Array(habitatObjects.objects.keys))
        guard !targets.isEmpty else {return}
        for id in targets {habitatObjects.beginRetirement(id,reason:reason)}
        if let focus=scheduler.sceneFocus,targets.contains(focus.objectID) {scheduler.endFocus(frequency:settings.ambientFrequency)}
        // Detach owners before recovery. The retirement surface remains available
        // until every former resident has released it, for at most two live seconds.
        runtime.cancel(where:{!targets.isDisjoint(with:$0.habitatReservations)},reason:reason,in:self)
        let immediate=paused || [.sleep,.shutdown,.screensChanged,.spaceChanged].contains(reason)
        for id in targets.sorted() {
            guard let object=habitatObjects.objects[id] else {continue}
            for bird in birds where bird.hostID==object.surface.id && bird.hostPID==object.surface.pid && !bird.isDeparting {
                if let birdID=self.id(of:bird) {recoverFromHabitat(birdID,excluding:id,immediate:immediate)}
            }
            let referenced=birds.contains{$0.hostID==object.surface.id && $0.hostPID==object.surface.pid}
            if immediate || !referenced || habitatObjects.removalDueIDs.contains(id) {
                world.surfaces.removeAll{$0==object.surface};habitatObjects.remove(id)
            }
        }
    }
    private func collectRetiredHabitatObjects() {
        let retired=habitatObjects.objects.values.filter {
            $0.retiring && ($0.kind == .bath || !runtime.habitatReservations.contains($0.id))
        }.map(\.id)
        removeHabitatObjects(reason:.removed,ids:retired)
    }
    private func refreshHabitatObjects() {
        let invalid=habitatObjects.objects.values.filter {object in
            let enabled=object.kind == .bath ? settings.bathEnabled:settings.foodTrayEnabled
            let available=object.kind == .bath ? world.bathArtAvailable:world.foodTrayArtAvailable
            return !available || !enabled || world.scale != object.scale ||
                world.screens != object.screens || world.displays != object.displays ||
                world.surfaces.contains(where:{$0.id==object.surface.id && $0 != object.surface}) ||
                fixedPerches.contains(where:{$0.rect.insetBy(dx:-50*world.scale,dy:-80*world.scale).intersects(object.rect)})
        }.map(\.id)
        removeHabitatObjects(reason:.targetInvalid,ids:invalid)
        world.surfaces.removeAll{$0.habitatKind == .foodTray || $0.habitatKind == .bath}
        world.surfaces.append(contentsOf:habitatObjects.objects.keys.sorted().compactMap{habitatObjects.objects[$0]?.surface})
        runtime.validate(in:self,where:{$0.kind == .foodTrayVisit || $0.kind == .bathVisit})
        collectRetiredHabitatObjects()
    }
    private func requestFixedPerchVisit(source:BehaviorSource,target:BirdID?=nil) -> BehaviorResult {
        guard !paused else {return reject(.fixedPerchVisit,source,.paused)}
        guard BehaviorDefinitions.definition(for:.fixedPerchVisit).isEnabled(settings:settings,source:source)
        else {return reject(.fixedPerchVisit,source,.disabled)}
        guard !ambientBusy,scheduledEncounter==nil else {return reject(.fixedPerchVisit,source,.busy)}
        guard !world.buttonsDown else {return reject(.fixedPerchVisit,source,.userInput)}
        guard !fixedPerches.isEmpty else {return reject(.fixedPerchVisit,source,.noSpace)}
        var candidates=FixedPerchVisitPlan.candidates(in:self,source:source,target:target)
        if source == .preview {
            let arriving=candidates.filter{!$0.originHost.isFixedPerch}
            if !arriving.isEmpty {candidates=arriving}
            // Preview takes the nearest feasible journey. Random long crossings
            // can occupy a rail between other residents and their empty slots.
            candidates.sort {
                if $0.duration != $1.duration {return $0.duration<$1.duration}
                if $0.id != $1.id {return $0.id<$1.id}
                return $0.perch.slot<$1.perch.slot
            }
        }
        guard let plan=(source == .preview ? candidates.first:source == .automatic ? ecologicalChoice(candidates,weight:{self.perchPlanner.automaticWeight($0.id,kind:.fixedPerchVisit)}):habitatRandom.element(candidates)) else {
            let supported=birds.filter{role(of:$0) == .resident && FixedPerchVisitBehavior.supportedSpecies.contains($0.profile.id)}
            let settled=supported.filter{$0.state == .perched}
            let reason:BehaviorReason
            if supported.isEmpty {reason = .noSpecies}
            else if settled.isEmpty {reason = .unavailableBird}
            else if settled.allSatisfy({!FixedPerchVisitPlan.requiredFrames.isSubset(of:world.availableFrames[$0.profile.id] ?? [])}) {reason = .missingFrames}
            else if settled.contains(where:{pointerNear($0)}) {reason = .pointerNearby}
            else {reason = .noSpace}
            return reject(.fixedPerchVisit,source,reason)
        }
        let result=runtime.start(FixedPerchVisitExecution(plan:plan,source:source),source:source,in:self)
        if result.accepted {perchPlanner.suppress(plan.id)}
        else if case .rejected(let reason)=result {return reject(.fixedPerchVisit,source,reason)}
        return result
    }
    private func requestAllopreening(source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(.allopreening,source,.paused)}
        guard BehaviorDefinitions.definition(for:.allopreening).isEnabled(settings:settings,source:source) else {return reject(.allopreening,source,.disabled)}
        guard !encounterUnavailable,scheduledEncounter==nil else {return reject(.allopreening,source,.busy)}
        guard !world.buttonsDown else {return reject(.allopreening,source,.userInput)}
        let candidates=AllopreeningPlan.candidates(in:self,source:source)
        guard let plan=(source == .automatic ? ecologicalChoice(candidates,weight:{plan in
            plan.participants.reduce(1){$0*self.perchPlanner.automaticWeight($1,kind:.allopreening)}
        }):socialRandom.element(candidates)) else {
            let residents=birds.filter{role(of:$0) == .resident && !$0.isDeparting}
            let supported=residents.filter{AllopreeningBehavior.supportedSpecies.contains($0.profile.id)}
            let paired=supported.filter{bird in supported.contains{$0 !== bird && $0.profile.id==bird.profile.id}}
            let reason:BehaviorReason
            if residents.isEmpty {reason = .noCompanion}
            else if supported.isEmpty {reason = .noSpecies}
            else if paired.isEmpty {reason = .noCompanion}
            else if paired.contains(where:{behavior(of:$0) != nil}) {reason = .busy}
            else if paired.filter({$0.state == .perched && !$0.needsDestination}).count<2 {reason = .unavailableBird}
            else if paired.contains(where:{pointerNear($0)}) {reason = .pointerNearby}
            else if paired.contains(where:{!BehaviorDefinitions.definition(for:.allopreening).requiredFrames.isSubset(of:world.availableFrames[$0.profile.id] ?? [])}) {reason = .missingFrames}
            else {reason = .noSpace}
            return reject(.allopreening,source,reason)
        }
        let result=runtime.start(AllopreeningExecution(plan:plan,source:source),source:source,in:self)
        if result.accepted {
            scheduler.suppress()
            for id in plan.participants {perchPlanner.suppress(id)}
        } else if case .rejected(let reason)=result {return reject(.allopreening,source,reason)}
        return result
    }
    private func requestSocialEncounter() {
        // All social clips share this one opportunity; adding a clip does not
        // create another clock or make noticeable events more frequent.
        let ids=socialMotionCandidates()
        let available=SocialMotionKind.allCases.filter{!SocialMotionPlanner.candidates($0,ids:ids,in:self).isEmpty}
        let chase=BehaviorDefinitions.definition(for:.chase).isEnabled(settings:settings,source:.automatic) &&
            !ChasePlan.candidates(in:self).isEmpty
        let together=BehaviorDefinitions.definition(for:.travelTogether).isEnabled(settings:settings,source:.automatic) &&
            !TravelTogetherPlan.candidates(in:self).isEmpty
        let allopreening=BehaviorDefinitions.definition(for:.allopreening).isEnabled(settings:settings,source:.automatic) &&
            !AllopreeningPlan.candidates(in:self).isEmpty
        let choice=Int(socialRandom.unit()*Double(available.count+1+(chase ? 1:0)+(together ? 1:0)+(allopreening ? 1:0)))
        if choice<available.count {_=requestSocialMotion(available[choice],source:.automatic)}
        else if chase,choice==available.count {_=requestChase(source:.automatic)}
        else if together,choice==available.count+(chase ? 1:0) {_=requestTravelTogether(source:.automatic)}
        else if allopreening,choice==available.count+(chase ? 1:0)+(together ? 1:0) {_=requestAllopreening(source:.automatic)}
        else {_=requestSocialGreeting(.automatic)}
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
        guard BehaviorDefinitions.definition(for:action.behavior).isEnabled(settings:settings,source:source) else {return reject(action.behavior,source,.disabled)}
        let candidates=target.map{[$0]} ?? order
        var reasons:[BehaviorReason]=[]
        let eligible=candidates.filter {id in
            guard let record=records[id],record.visible else {return false}
            if let reason=perchRejection(action,bird:record.bird) {reasons.append(reason);return false}
            return source != .automatic || perchPlanner.automaticWeight(id,kind:action.behavior)>0
        }
        guard let id=perchPlanner.select(eligible),let plan=perchPlanner.plan(action,for:id) else {
            let reason=([BehaviorReason.pointerNearby,.userInput,.missingFrames,.noSpace,.busy].first(where:{reasons.contains($0)})) ?? .unavailableBird
            return reject(action.behavior,source,reason)
        }
        perchPlanner.suppress(id)
        return runtime.start(PerchActivityExecution(id:id,plan:plan),source:source,in:self)
    }
    private func updatePerchActivities(_ dt:Double) {
        var candidates:[(BirdID,PerchActionKind)]=[]
        for id in order {
            guard let record=records[id],record.visible,record.role == .resident else {continue}
            let bird=record.bird
            let enabled=ambientEnabled && settings.perchActions && PerchActionKind.allCases.contains{supports($0,bird:bird)}
            if let action=perchPlanner.candidate(id,bird:bird,dt:dt,enabled:enabled,occupied:runtime.owners[id] != nil,
                quiet:!world.buttonsDown && !pointerNear(bird),
                restRate:ActivityRhythmPolicy.restRate(mode:settings.activityRhythm,minute:world.localMinuteOfDay,species:bird.profile.id)),enabled,perchRejection(action,bird:bird)==nil {
                candidates.append((id,action))
            }
        }
        if let choice=ecologicalChoice(candidates,weight:{self.perchPlanner.automaticWeight($0.0,kind:$0.1.behavior)}) {
            _=requestPerchAction(choice.1,source:.automatic,target:choice.0)
        }
    }
    func plan(for bird:Bird,entering:Bool=false,avoiding:CGPoint?=nil) -> DestinationPlan? {
        DestinationPlanner.plan(for:bird,birds:birds,world:world,entering:entering,avoiding:avoiding,
            reserved:runtime.landingReservations.filter{$0.bird != id(of:bird)}.compactMap{$0.footprint(in:self)},random:random)
    }
    @discardableResult public func route(_ bird:Bird,entering:Bool=false,avoiding:CGPoint?=nil) -> Bool {
        var input=RecordedInput(kind:"route");input.bird=id(of:bird).map{String($0.rawValue)};input.entering=entering;input.avoiding=avoiding.map(RecordedPoint.init)
        beginRecordingInput(input);defer {endRecordingInput()}
        guard let plan=plan(for:bird,entering:entering,avoiding:avoiding) else {return false}
        if let id=id(of:bird) {runtime.cancel(bird:id,reason:.replaced,in:self)}
        plan.apply(to:bird,random:random);return true
    }
    private func routeAutonomously(_ bird:Bird,id:BirdID) {
        // One optional choice at the existing departure opportunity. No new
        // timer, resident, or forced takeoff is created by placing a perch.
        if ambientEnabled,!habitatIDs(.foodTray).isEmpty,bird.state == .perched,
           foodDepartureAttempts[id] != bird.motionRevision,
           BehaviorDefinitions.definition(for:.foodTrayVisit).isEnabled(settings:settings,source:.automatic) {
            foodDepartureAttempts[id]=bird.motionRevision
            if foodRandom.unit()<0.25,requestFoodTrayVisit(source:.automatic,target:id).accepted {return}
        }
        if ambientEnabled,!fixedPerches.isEmpty,bird.state == .perched,
           fixedPerchDepartureAttempts[id] != bird.motionRevision,
           BehaviorDefinitions.definition(for:.fixedPerchVisit).isEnabled(settings:settings,source:.automatic) {
            fixedPerchDepartureAttempts[id]=bird.motionRevision
            if habitatRandom.unit()<0.15,requestFixedPerchVisit(source:.automatic,target:id).accepted {return}
        }
        guard let destination=plan(for:bird) else {return}
        if settings.perchActions,settings.takeoffPreparationEnabled,
           bird.state == .perched,bird.stateTime>=bird.perchDuration,hasUsablePerch(bird),
           perchPlanner.automaticWeight(id,kind:.takeoffPreparation)>0,
           prepareTakeoff(id:id,plan:destination,source:.automatic).accepted {return}
        destination.apply(to:bird,random:random)
    }
    public func bringInBird() {
        beginRecordingInput(RecordedInput(kind:"arrive"));defer {endRecordingInput()}
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
        var input=RecordedInput(kind:"depart");input.bird=id(of:bird).map{String($0.rawValue)}
        beginRecordingInput(input);defer {endRecordingInput()}
        guard let point=Migration.outsidePoint(screens:world.displays,right:random.unit()<0.5,fraction:random.value(in:0.2...0.75),margin:80*world.scale*3+20) else {return}
        if let id=id(of:bird) {runtime.cancel(bird:id,reason:.replaced,in:self)}
        bird.depart(to:point,duration:max(2.8,Double(Geometry.distance(bird.position,point))/400*Bird.flightSpeedMultiplier))
    }
    public func reconcileLayout() {
        beginRecordingInput(RecordedInput(kind:"reconcileLayout"));defer {endRecordingInput()}
        for bird in birds {
            if bird.isDeparting {sendAway(bird)}
            else if bird.state != .flying && world.surfaces.contains(where:{$0.isGround && $0.id==bird.hostID}) {
                bird.updateHost(surfaces:world.surfaces,sampleDT:1,spriteScale:spriteScale(for:bird))
            } else {_=route(bird)}
        }
    }
    public func advance(_ elapsed:Double) {
        guard elapsed.isFinite,elapsed>=0 else {return}
        beginRecordingInput(.advance(elapsed,in:self));defer {endRecordingInput()}
        accumulator+=min(0.05,elapsed)
        var steps=0
        while accumulator+1e-10>=Self.step && steps<3 {
            accumulator=max(0,accumulator-Self.step);steps+=1;step(Self.step)
        }
    }
    private func step(_ dt:Double) {
        time+=dt
        if !paused {
            for id in recoveringHabitatBirds.sorted() {resumeHabitatRecovery(id)}
            habitatObjects.advance(dt)
            if let pending=pendingBathPlacement {
                let remaining=pending-dt;pendingBathPlacement=remaining
                if remaining<=1e-10 {
                    pendingBathPlacement=nil
                    let result=placeBath(at:world.pointer)
                    let reason:BehaviorReason?;if case .rejected(let why)=result {reason=why}else{reason=nil}
                    emit(.previewResult,kind:.bathVisit,source:.user,reason:reason)
                }
            }
            if let pending=pendingFoodTrayPlacement {
                let remaining=pending-dt;pendingFoodTrayPlacement=remaining
                if remaining<=1e-10 {
                    pendingFoodTrayPlacement=nil
                    let result=placeFoodTray(at:world.pointer)
                    let reason:BehaviorReason?;if case .rejected(let why)=result {reason=why}else{reason=nil}
                    emit(.previewResult,kind:.foodTrayVisit,source:.user,reason:reason)
                }
            }
            collectRetiredHabitatObjects()
            observeEnvironment(dt)
            poseMixer.advance(dt)
            if populationEnabled,let event=population.tick(dt,residents:residentCount,total:residentCount+departingCount,random:random.unit) {
                switch event {
                case .arrive:bringInBird()
                case .depart:if let bird=random.element(birds.filter{!$0.isDeparting && behavior(of:$0)==nil}) {sendAway(bird)}
                }
            }
            if var pending=scheduledEncounter {
                pending.remaining-=dt;scheduledEncounter=pending
                if pending.remaining<=1e-10 {
                    scheduledEncounter=nil
                    let result=pending.kind == .leafPlay ? requestLeaf(at:world.pointer,source:.preview):requestPointer(.preview)
                    let reason:BehaviorReason?;if case .rejected(let why)=result {reason=why}else{reason=nil}
                    emit(.previewResult,kind:pending.kind,source:.preview,reason:reason)
                }
            }
        }
        // Resolve input cancellations and pending spawns before integrating motion.
        runtime.advance(dt,in:self)
        collectRetiredHabitatObjects()
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
            } else if runtime.owners[id]==nil && !paused && autonomousRouting && bird.needsDestination {routeAutonomously(bird,id:id)}
        }
        if !paused {
            if !updateAttention(),!updateSideHops(),!updateEdgePeeks(dt) {updatePerchActivities(dt)}
        }
        let encounterRate=ActivityRhythmPolicy.ambientRate(mode:settings.activityRhythm,minute:world.localMinuteOfDay)
        if !paused,let event=scheduler.tick(dt,pointer:world.pointer,buttonsDown:world.buttonsDown,
            pointerEnabled:settings.pointerVisits,flockEnabled:settings.flockPasses,socialEnabled:settings.socialInteractions,leafEnabled:settings.leafPlayEnabled && settings.ambientLeafPlayEnabled,frequency:settings.ambientFrequency,
            busy:encounterUnavailable || scheduledEncounter != nil,cadenceRate:ambientEnabled ? encounterRate:0,leafRandom:ecologyRandom.unit,random:random.unit) {
            switch event {
            case .pointerVisit:_=requestPointer(.automatic)
            case .flockPass:_=requestFlock(.automatic)
            case .socialGreeting:requestSocialEncounter()
            case .leafPlay:requestAutomaticLeaf()
            case .bathVisit(let object):
                if scheduler.sceneFocus?.objectID==object {_=requestBathVisit(source:.automatic)}
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
        let pose=id(of:bird).flatMap{runtime.presentation(for:$0,in:self)}
        let hop=pose?.hopOffset ?? id(of:bird).map{baseHop(for:$0,bird:bird)} ?? bird.hopOffset
        let facing=pose?.facingRight ?? bird.facingRight
        return CGRect(x:bird.position.x-(facing ? 29:19)*scale,y:bird.position.y+(hop-39)*scale,width:48*scale,height:48*scale).insetBy(dx:-2,dy:-2)
    }
    public func renderSnapshot() -> [BirdRenderState] {
        birds.compactMap {bird in
            guard let id=id(of:bird) else {return nil}
            let pose=runtime.presentation(for:id,in:self)
            return BirdRenderState(id:id,species:bird.profile.id,position:bird.position,facingRight:pose?.facingRight ?? bird.facingRight,
                scale:spriteScale(for:bird),hopOffset:pose?.hopOffset ?? baseHop(for:id,bird:bird),frameName:drawableFrame(pose?.frameName ?? bird.frameName,for:bird),
                blockers:bird.blockers(in:world.surfaces),hoverable:isHoverable(bird))
        }
    }
}
