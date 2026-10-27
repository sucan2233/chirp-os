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
    let carriedObjects=CarriedObjectStore()
    let insects=InsectStore()
    private var pendingNestPlacement:Double?
    private let nestRandom:EngineRandom
    private let courtshipRandom:EngineRandom
    private let giftRandom:EngineRandom
    private struct PendingGift {
        let request:GiftAuthorizationRequest
        let plan:VisitorGiftPlan
        let motionRevision:UInt64
    }
    private var pendingGift:PendingGift?
    private var nextGiftRequestID:UInt64=1
    private struct RegisteredGiftToken {
        let token:GiftAuthorizationToken
        var run:BehaviorRunID?
        var consumed=false
    }
    private var registeredGiftToken:RegisteredGiftToken?
    private var giftReceiverRevisions:[Int:UInt64]=[:]
    private var giftReceiverAnchors:[FixedPerchAnchor]=[]
    private var giftReceiverDisplayIDs:[String]=[]
    private var nextGiftReceiverRevision:UInt64=1
    /// The platform must return results on the simulation executor. In
    /// production it schedules IO asynchronously, including preview grants.
    public var giftAuthorizationObserver:((GiftAuthorizationRequest)->Void)?
    public var giftAuthorizationRequest:GiftAuthorizationRequest? {pendingGift?.request}
    public private(set) var lastGiftAuthorizationDenial:GiftAuthorizationDenial?
    public var activeGiftAuthorizationCount:Int {registeredGiftToken == nil ? 0:1}
    var giftAuthorizationForReplay:(token:GiftAuthorizationToken,run:BehaviorRunID?,consumed:Bool)? {
        registeredGiftToken.map{($0.token,$0.run,$0.consumed)}
    }
    private let insectRandom:EngineRandom
    private struct PendingInsectPreview {let species:SpeciesID;var remaining:Double}
    private var pendingInsectPreview:PendingInsectPreview?
    public var lastInsectContact:InsectContact? {insects.lastContact}
    public private(set) var insectMissedTargetCount=0
    private var pendingCarryLeafPlacement:Double?
    private let leafCarryRandom:EngineRandom
    private var foodDepartureAttempts:[BirdID:UInt64]=[:]
    private var pendingBathPlacement:Double?
    private let bathRandom:EngineRandom
    private var recoveringHabitatBirds=Set<BirdID>()
    private var pendingFoodTrayPlacement:Double?
    private let foodRandom:EngineRandom
    private let inputRecorder:BehaviorInputRecorder?
    /// Synchronous event stream for bounded telemetry; observers must not issue
    /// engine commands or advance simulation from inside this callback.
    public var eventObserver:((BehaviorEvent)->Void)?
    /// Outbound discovery values. Hosts serialize delivery with engine commands;
    /// observers must not issue simulation commands from inside this callback.
    public var observationObserver:((BehaviorObservation)->Void)?
    let poseMixer=PoseMixer()
    let livelyMotion=LivelyMotionScheduler()
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
    let companionScheduler:CompanionOpportunityScheduler
    let companionRandom:EngineRandom
    var companionRecovering=Set<BirdID>()
    var companionOrbit:BirdID?
    var companionEscapeStarted:[BirdID:Double]=[:]
    var companionMicroNext:[BirdID:Double]=[:]
    var companionFlightAges:[BirdID:Double]=[:]
    var sceneCandidateID:HabitatObjectID?
    var sceneLeafCandidateID:ScenePropID?
    var scenePerchCandidateSlot:Int?
    var sceneLastVisit:[String:Double]=[:]
    public var companionDiagnostics:[OpportunityDiagnostic] {companionScheduler.diagnostics}
    public private(set) var companionMetrics=CompanionMetrics()
    public var companionOpportunityCounts:[String:Int] {companionScheduler.counts}
    public var companionDueCounts:[String:Int] {["flock":companionScheduler.flockDueCount,"encounter":companionScheduler.encounterDueCount]}
    public var companionMaximumFlockWait:Double {companionScheduler.maximumFlockWait}
    private var companionRunStarts:[BehaviorRunID:(Double,Double)]=[:]
    private var companionMotionRevisions:[BirdID:UInt64]=[:]


    public private(set) var sceneArchive=SceneArchive()
    public private(set) var sceneEditPhase:SceneEditPhase = .idle
    public private(set) var sceneError:String?
    public var sceneWriter:((SceneArchive)throws->Void)?
    private var sceneEnabled=false
    public private(set) var sceneNeedsPlacement=Set<UUID>()
    private var sceneProposed:SceneLayout?
    private var sceneAffected=Set<UUID>()
    private var sceneRecovery=Set<BirdID>()
    private var sceneRecoveryAge=0.0
    private var sceneExcludedSurfaces=Set<UInt32>()
    private var sceneLastWorld:BehaviorWorld?
    private var sceneRetryRemaining=0.0
    public var sceneEditing:Bool {[SceneEditPhase.editing,.applying,.failed].contains(sceneEditPhase)}

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
        companionScheduler=CompanionOpportunityScheduler(seed:seed)
        companionRandom=EngineRandom(seed:seed ^ 0x434F4D5043484F49)
        self.inputRecorder=recordInputs ? BehaviorInputRecorder(seed:seed,settings:settings):nil
        self.perchPlanner=PerchActivityPlanner(seed:seed)
        self.visitorMemory=VisitorMemory(seed:seed)
        self.bathRandom=EngineRandom(seed:seed ^ SceneRandomSalt.bath)
        self.insectRandom=EngineRandom(seed:seed ^ SceneRandomSalt.insectCatch)
        self.leafCarryRandom=EngineRandom(seed:seed ^ SceneRandomSalt.leafCarry)
        self.giftRandom=EngineRandom(seed:seed ^ SceneRandomSalt.visitorGift)
        self.nestRandom=EngineRandom(seed:seed ^ SceneRandomSalt.nest)
        self.courtshipRandom=EngineRandom(seed:seed ^ SceneRandomSalt.courtship)
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
    public var ambientBusy:Bool {pendingGift != nil || runtime.encounterBusy}
    private var encounterUnavailable:Bool {
        pendingGift != nil || ambientBusy || runtime.runs.values.contains{[BehaviorKind.foodTrayVisit,.fixedPerchVisit].contains($0.execution.kind)}
    }
    public var hasPointerPreview:Bool {scheduledEncounter?.kind == .pointerVisit}
    public var hasLeafPreview:Bool {scheduledEncounter?.kind == .leafPlay}
    public var sceneFocus:SceneFocus? {scheduler.sceneFocus}
    public func insectSnapshot() -> Insect? {insects.current}
    public var hasInsectCatchPreview:Bool {pendingInsectPreview != nil}
    public var insectPreviewRemaining:Double? {pendingInsectPreview?.remaining}
    public var insectPreviewSpecies:SpeciesID? {pendingInsectPreview?.species}
    public var hasNestPlacement:Bool {pendingNestPlacement != nil}
    public func nestSnapshot()->[NestSnapshot] {habitatObjects.nestSnapshot(in:self)}
    public var hasCarryLeafPlacement:Bool {pendingCarryLeafPlacement != nil}
    public func carriedObjectSnapshot()->[CarriedObject] {carriedObjects.objects.keys.sorted().compactMap{carriedObjects.objects[$0]}}
    /// Receiver geometry remains an obstacle for the full object lifetime.
    /// Only its active delivery run may pass through its own release corridor.
    func giftObstacleRects(excluding participants:[BirdID]=[]) -> [CGRect] {
        guard settings.visitorGiftsEnabled else {return []}
        let ignored=Set(participants)
        let active=Set(runtime.runs.values.filter{$0.execution.kind == .visitorGift}.flatMap{$0.execution.participants})
        return runtime.giftReceiverReservations.filter{!ignored.contains($0.bird)}.map(\.rect) +
            carriedObjects.giftReceiverReservations(in:self).filter{!ignored.contains($0.bird) || !active.contains($0.bird)}.map(\.rect)
    }
    public var hasBathPlacement:Bool {pendingBathPlacement != nil}
    public var hasFoodTrayPlacement:Bool {pendingFoodTrayPlacement != nil}
    public var habitatReservationCount:Int {runtime.habitatReservations.count}
    public func habitatSnapshot()->[HabitatObjectRenderState] {habitatObjects.snapshot(in:self)}
    public var giftReceiverReservationCount:Int {runtime.giftReceiverReservations.count}
    public var scenePropCount:Int {runtime.propIDs.union(carriedObjects.objects.keys).union(insects.current.map{[$0.id]} ?? []).union(habitatObjects.objects.values.flatMap{$0.nest?.materials.map(\.id) ?? []}).count}
    public func propSnapshot() -> [ScenePropRenderState] {
        (runtime.propSnapshots(in:self)+carriedObjects.snapshot(in:self)+insects.snapshot(in:self)+habitatObjects.propSnapshots(in:self)).sorted{$0.id<$1.id}
    }
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
        if let p=settings.companion {bird.ordinaryOrbitLimit=0;bird.preferNearbyDestinations=p.mode != .lively}
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
        if pendingGift?.request.binding.birdID==id {cancelGiftRequest(.removed)}
        guard let record=records.removeValue(forKey:id) else {return}
        identities.removeValue(forKey:ObjectIdentifier(record.bird));order.removeAll{$0==id}
        if let visitorID=visitorIDs.removeValue(forKey:id) {visitorMemory.release(visitorID)}
        companionMicroNext.removeValue(forKey:id);companionFlightAges.removeValue(forKey:id);companionEscapeStarted.removeValue(forKey:id)
        companionMotionRevisions.removeValue(forKey:id)
        fixedPerchDepartureAttempts.removeValue(forKey:id)
        foodDepartureAttempts.removeValue(forKey:id)
        recoveringHabitatBirds.remove(id)
        perchPlanner.remove(id);poseMixer.remove(id);livelyMotion.remove(id);attentionRanges.remove(id)
        if let pending=pendingInsectPreview,!birds.contains(where:{role(of:$0) == .resident && !$0.isDeparting && $0.profile.id==pending.species}) {
            cancelInsectPreview(.removed)
        }
        emit(.birdRemoved,participants:[id],reason:.removed)
    }
    @discardableResult func emit(_ type:BehaviorEventType,run:BehaviorRunID?=nil,kind:BehaviorKind?=nil,
              source:BehaviorSource = .automatic,participants:[BirdID]=[],reason:BehaviorReason?=nil) -> BehaviorEvent {
        let event=BehaviorEvent(sequence:nextEvent,time:time,runID:run,kind:kind,source:source,type:type,participants:participants,reason:reason)
        if settings.companion != nil,let run {
            if type == .started {
                companionRunStarts[run]=(companionMetrics.simulatedElapsed,companionMetrics.unpausedElapsed)
                companionScheduler.record(time:time,kind:kind,state:.started,reason:source.rawValue,run:run.rawValue)
            } else if [.completed,.cancelled,.failed].contains(type) {
                let start=companionRunStarts.removeValue(forKey:run)
                companionScheduler.record(time:time,kind:kind,state:type == .completed ? .completed:type == .cancelled ? .cancelled:.failed,reason:reason?.rawValue ?? "finished",run:run.rawValue,
                    elapsed:start.map{companionMetrics.simulatedElapsed-$0.0},wallElapsed:start.map{companionMetrics.unpausedElapsed-$0.1})
            }
        }
        if (kind == .bathVisit || kind == .leafCarry),[BehaviorEventType.completed,.cancelled,.failed].contains(type) {scheduler.didFinishScene()}
        if kind == .insectCatch,[BehaviorEventType.completed,.cancelled,.failed].contains(type) {
            scheduler.didFinishInsectCatch()
            if type == .failed,reason == .missedTarget {insectMissedTargetCount+=1}
        }
        events.append(event)
        inputRecorder?.event(event);eventObserver?(event)
        nextEvent+=1
        if events.count>256 {events.removeFirst(events.count-256)}
        return event
    }
    public func updateWorld(_ value:BehaviorWorld,sampleDT:Double?=nil) {
        beginRecordingInput(.world(value,sampleDT:sampleDT));defer {endRecordingInput()}
        if world.screens != value.screens || world.displays != value.displays {resetPerception();pendingCarryLeafPlacement=nil;pendingNestPlacement=nil}
        if world.screens != value.screens || world.displays != value.displays || world.displayIDs != value.displayIDs || world.scale != value.scale {
            pendingNestPlacement=nil
            cancelInsectPreview(.screensChanged)
        }
        let previousPerches=world.surfaces.filter(\.isFixedPerch)
        if sceneEditing {
            sceneLastWorld=value
            if world.displays != value.displays || world.displayIDs != value.displayIDs || world.scale != value.scale {cancelSceneEditing()}
            else {return}
        }
        world=value
        refreshFixedPerches(previous:previousPerches)
        refreshHabitatObjects(sampleDT:sampleDT)
        refreshNestMotion(sampleDT:sampleDT)
        // Release obsolete gift-route reservations before the independent
        // falling leaf checks the new world's obstacles and reservations.
        if settings.visitorGiftsEnabled {runtime.validate(in:self,where:{$0.kind == .visitorGift})}
        refreshCarriedObjects(sampleDT:sampleDT)
        refreshInsects(sampleDT:sampleDT)
        refreshGiftRequest()
        if !value.leafCarryArtAvailable {pendingCarryLeafPlacement=nil}
        if !value.nestArtAvailable {pendingNestPlacement=nil}
        if !value.buttonsDown {clickHandled=false}
        // Contact scenes use fixed anchors. Release them against the new world
        // before host tracking can translate a perched partner or an active hop.
        runtime.validate(in:self,where:{$0.kind == .allopreening || $0.kind == .courtshipDisplay})
        if let sampleDT {for bird in birds {bird.updateHost(surfaces:world.surfaces,sampleDT:sampleDT,spriteScale:spriteScale(for:bird))}}
        runtime.validate(in:self)
        cancelIneligibleLivelyMotion()
    }
    public func applySettings(_ value:BirdSettings) {
        beginRecordingInput(.settings(value));defer {endRecordingInput()}
        if value.pointerFollowEnabled != settings.pointerFollowEnabled {
            runtime.cancel(where:{$0.kind == .pointerVisit},reason:.settingsChanged,in:self)
        }
        let previousCompanion=settings.companion
        settings=value
        if value.companion == nil {scheduler.reset(value.ambientFrequency)}
        configureCompanion(previous:previousCompanion)
        cancelIneligibleLivelyMotion()
        if !value.insectCatchEnabled {clearInsects(reason:.settingsChanged)}
        if let pending=pendingInsectPreview,!insectSpeciesEnabled(pending.species) {cancelInsectPreview(.settingsChanged)}
        runtime.cancel(where:{$0.kind == .insectCatch && $0.participants.contains {id in
            self.bird(id).map{!self.insectSpeciesEnabled($0.profile.id)} ?? true
        }},reason:.settingsChanged,in:self)
        if !value.foodTrayEnabled {pendingFoodTrayPlacement=nil;removeHabitatObjects(reason:.settingsChanged,ids:habitatIDs(.foodTray))}
        if !value.bathEnabled {pendingBathPlacement=nil;removeHabitatObjects(reason:.settingsChanged,ids:habitatIDs(.bath))}
        if !value.nestBuildingEnabled {pendingNestPlacement=nil;removeHabitatObjects(reason:.settingsChanged,ids:habitatIDs(.nest))}
        if !value.probabilities.participates(.spottedDove) {
            runtime.cancel(where:{$0.kind.isNestActivity},reason:.settingsChanged,in:self)
        }
        if !value.leafCarryEnabled {
            pendingCarryLeafPlacement=nil
            removeCarriedObjects(reason:.settingsChanged,ids:carriedObjects.objects.values.filter{!$0.isVisitorGift}.map(\.id))
        }
        if !value.visitorGiftsEnabled || !value.visitorMemoryEnabled || !value.fixedPerchesEnabled ||
            !value.probabilities.participates(.azureWingedMagpie) {clearVisitorGifts(reason:.settingsChanged)}
        if !value.fixedPerchesEnabled {runtime.cancel(where:{$0.kind == .fixedPerchVisit},reason:.settingsChanged,in:self)}
        refreshFixedPerches(previous:world.surfaces.filter(\.isFixedPerch))
        refreshHabitatObjects()
        refreshGiftRequest()
        // Saved receiving branches can disappear while paused. Cancel their
        // runs and retire invalid gift entities in this settings transaction.
        if carriedObjects.objects.values.contains(where:{$0.isVisitorGift}) {
            runtime.validate(in:self,where:{$0.kind == .visitorGift})
            let identities=carriedObjects.objects.mapValues(\.persistentID)
            let invalid=carriedObjects.synchronizeVisitorGifts(in:self)
            if !invalid.isEmpty {
                markInvalidSceneSupports(invalid,identities:identities)
                removeCarriedObjects(reason:.targetInvalid,ids:invalid)
            }
        }
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
        if !value.courtshipEnabled || !value.probabilities.participates(.spottedDove) {
            runtime.cancel(where:{$0.kind == .courtshipDisplay},reason:.settingsChanged,in:self)
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
        if sceneEditing {
            switch command {case .pause:break;case .cancelAmbient:cancelSceneEditing();default:return .rejected(.busy)}
        }
        beginRecordingInput(.command(command));defer {endRecordingInput()}
        switch command {
        case .placeNest(let point):return placeNest(at:point)
        case .nestMaterialCarry(let source):return requestNest(kind:.nestMaterialCarry,source:source)
        case .nestBuild(let source):return requestNest(kind:.nestBuild,source:source)
        case .placeNestAfter(let delay):
            guard !paused else {return reject(.nestMaterialCarry,.user,.paused)}
            guard settings.nestBuildingEnabled else {return reject(.nestMaterialCarry,.user,.disabled)}
            guard world.nestArtAvailable else {return reject(.nestMaterialCarry,.user,.missingFrames)}
            guard habitatObjects.objects.isEmpty,scheduler.sceneFocus==nil,!hasFoodTrayPlacement,
                  !hasBathPlacement,!hasCarryLeafPlacement,!hasNestPlacement else {return reject(.nestMaterialCarry,.user,.busy)}
            pendingNestPlacement=max(0,min(10,delay.isFinite ? delay:3));return .scheduled
        case .cancelNestPlacement:pendingNestPlacement=nil;return .accepted
        case .removeNest:
            pendingNestPlacement=nil;removeHabitatObjects(reason:.removed,ids:habitatIDs(.nest));return .accepted
        case .visitorGift(let source):return requestVisitorGift(source:source)
        case .cancelVisitorGiftRequest:cancelGiftRequest(.userInput);return .accepted
        case .clearVisitorGift:clearVisitorGifts(reason:.removed);return .accepted
        case .relocate(let id):
            if pendingGift?.request.binding.birdID==id {cancelGiftRequest(.replaced)}
            return relocate(id)
        case .insectCatch(let species,let source):return requestInsectCatch(species:species,source:source)
        case .cancelInsectCatchPreview:cancelInsectPreview(.userInput);return .accepted
        case .clearInsect:clearInsects(reason:.removed);return .accepted
        case .placeCarryLeaf(let point):return placeCarryLeaf(at:point)
        case .leafCarry(let source):return requestLeafCarry(source:source)
        case .placeCarryLeafAfter(let delay):
            guard !paused else {return reject(.leafCarry,.user,.paused)}
            guard settings.leafCarryEnabled else {return reject(.leafCarry,.user,.disabled)}
            guard world.leafCarryArtAvailable else {return reject(.leafCarry,.user,.missingFrames)}
            guard carriedObjects.objects.isEmpty,scheduler.sceneFocus==nil,
                  !hasCarryLeafPlacement,!hasBathPlacement,!hasNestPlacement else {return reject(.leafCarry,.user,.busy)}
            pendingCarryLeafPlacement=max(0,min(10,delay.isFinite ? delay:3));return .scheduled
        case .cancelCarryLeafPlacement:pendingCarryLeafPlacement=nil;return .accepted
        case .removeCarryLeaf:
            pendingCarryLeafPlacement=nil
            removeCarriedObjects(reason:.removed,ids:carriedObjects.objects.values.filter{!$0.isVisitorGift}.map(\.id))
            return .accepted
        case .placeBath(let point):return placeBath(at:point)
        case .bathVisit(let source):return requestBathVisit(source:source)
        case .placeBathAfter(let delay):
            guard !paused else {return reject(.bathVisit,.user,.paused)}
            guard settings.bathEnabled else {return reject(.bathVisit,.user,.disabled)}
            guard world.bathArtAvailable else {return reject(.bathVisit,.user,.missingFrames)}
            guard habitatObjects.objects.isEmpty,scheduler.sceneFocus==nil,!hasBathPlacement,!hasFoodTrayPlacement,!hasCarryLeafPlacement,!hasNestPlacement else {return reject(.bathVisit,.user,.busy)}
            pendingBathPlacement=max(0,min(10,delay.isFinite ? delay:3));return .scheduled
        case .cancelBathPlacement:pendingBathPlacement=nil;return .accepted
        case .removeBath:
            pendingBathPlacement=nil;removeHabitatObjects(reason:.removed,ids:habitatIDs(.bath));return .accepted
        case .clearCurrentScene:
            pendingBathPlacement=nil;pendingFoodTrayPlacement=nil;pendingCarryLeafPlacement=nil;pendingNestPlacement=nil
            removeHabitatObjects(reason:.removed);removeCarriedObjects(reason:.removed);clearInsects(reason:.removed);return .accepted
        case .placeFoodTray(let point):return placeFoodTray(at:point)
        case .foodTrayVisit(let source):return requestFoodTrayVisit(source:source)
        case .placeFoodTrayAfter(let delay):
            guard !paused else {return reject(.foodTrayVisit,.user,.paused)}
            guard settings.foodTrayEnabled else {return reject(.foodTrayVisit,.user,.disabled)}
            guard habitatObjects.objects.isEmpty,!hasFoodTrayPlacement,!hasBathPlacement,!hasNestPlacement else {return reject(.foodTrayVisit,.user,.busy)}
            pendingFoodTrayPlacement=max(0,min(10,delay.isFinite ? delay:3));return .scheduled
        case .cancelFoodTrayPlacement:pendingFoodTrayPlacement=nil;return .accepted
        case .removeFoodTray:
            pendingFoodTrayPlacement=nil;removeHabitatObjects(reason:.removed,ids:habitatIDs(.foodTray));return .accepted
        case .fixedPerchVisit(let source):return requestFixedPerchVisit(source:source)
        case .courtshipDisplay(let source):return requestCourtship(source:source)
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
            if case .clearProps=command {pendingBathPlacement=nil;pendingFoodTrayPlacement=nil;pendingCarryLeafPlacement=nil;pendingNestPlacement=nil;removeHabitatObjects(reason:.userInput);removeCarriedObjects(reason:.userInput);clearInsects(reason:.userInput)}
            if hasLeafPreview {cancelPreview(.userInput)}
            runtime.cancel(where:{$0.kind == .leafPlay},reason:.userInput,in:self)
            scheduler.suppress();return .accepted
        case .removeProp(let id):
            runtime.cancel(where:{$0.propIDs.contains(id)},reason:.removed,in:self)
            removeCarriedObjects(reason:.removed,ids:[id])
            if insects.current?.id==id {clearInsects(reason:.removed)}
            let nests=habitatObjects.objects.values.filter{$0.nest?.materials.contains(where:{$0.id==id}) == true}.map(\.id)
            if !nests.isEmpty {removeHabitatObjects(reason:.removed,ids:nests)}
            return .accepted
        case .pointerClick:
            companionScheduler.clicked()
            livelyMotion.cancelAll()
            cancelGiftRequest(.userInput)
            cancelInsectPreview(.userInput)
            recordPointerClick(explicit:true)
            scheduler.suppress(reason:.userInput)
            runtime.cancel(where:{$0.kind == .pointerVisit || $0.kind.isPerchActivity || $0.kind.isSocial || $0.kind == .leafPlay || $0.kind == .fixedPerchVisit || $0.kind == .foodTrayVisit || $0.kind == .bathVisit || $0.kind == .leafCarry || $0.kind == .insectCatch || $0.kind == .visitorGift || $0.kind.isNestActivity},reason:.userInput,in:self)
            perchPlanner.suppressAll()
        case .pause(let value):
            guard paused != value else {return .accepted}
            paused=value;accumulator=0;resetPerception()
            if value {
                companionScheduler.discardPending()
                cancelGiftRequest(.paused)
                cancelPreview(.paused)
                runtime.cancel(where:{$0.kind == .pointerVisit},reason:.paused,in:self)
            }
        case .cancelAmbient(let reason):
            companionScheduler.discardPending()
            livelyMotion.cancelAll()
            cancelGiftRequest(reason)
            cancelInsectPreview(reason)
            if [.sleep,.screensChanged,.spaceChanged,.shutdown].contains(reason) {clearInsects(reason:reason)}
            pendingBathPlacement=nil;pendingFoodTrayPlacement=nil;pendingCarryLeafPlacement=nil;pendingNestPlacement=nil
            if [.sleep,.screensChanged,.spaceChanged,.shutdown].contains(reason) {removeHabitatObjects(reason:reason);removeCarriedObjects(reason:reason)}
            cancelPreview(reason);accumulator=0;scheduler.suppress();perchPlanner.suppressAll();resetPerception()
            let all:[BehaviorReason]=[.sleep,.screensChanged,.spaceChanged,.shutdown]
            runtime.cancel(where:{all.contains(reason) || $0.occupiesEncounter},reason:reason,in:self)
        case .scatter:
            livelyMotion.cancelAll()
            cancelGiftRequest(.userInput)
            cancelInsectPreview(.userInput)
            cancelPreview(.userInput);perchPlanner.suppressAll()
            runtime.cancel(where:{!$0.occupiesEncounter || $0.kind == .pointerVisit || $0.kind.isSocial || $0.kind == .leafPlay || $0.kind == .insectCatch || $0.kind == .visitorGift || $0.kind.isNestActivity},reason:.replaced,in:self)
            scheduler.suppress(reason:.userInput)
            for bird in birds where !bird.isDeparting {_=route(bird)}
        case .remove(let id):
            if pendingGift?.request.binding.birdID==id {cancelGiftRequest(.removed)}
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
        cancelInsectPreview(.userInput)
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
            guard supportsBehavior(.leafPlay,bird:bird) else {return false}
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
            supportsBehavior(.pointerVisit,bird:bird) &&
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
        if source == .automatic,settings.companion != nil,companionScheduler.permit != .flockPass {return .rejected(.busy)}
        guard BehaviorDefinitions.definition(for:.flockPass).isEnabled(settings:settings,source:source) else {return reject(.flockPass,source,.disabled)}
        guard !encounterUnavailable,scheduledEncounter == nil else {return reject(.flockPass,source,.busy)}
        guard let screen=random.element(world.displays) else {return reject(.flockPass,source,.noSpace)}
        let entries=settings.probabilities.entries.filter { AmbientFlock.species.contains($0.id) }
        guard let selected = try? WeightedChoice(entries, weight: { $0.weight }).choose(using: random.unit) else {
            return reject(.flockPass,source,.noSpecies)
        }
        let species = selected.id
        let profile=settings.catalog.profile(species),scale=world.scale*profile.relativeScale
        let left=world.displays.map(\.minX).min()!,right=world.displays.map(\.maxX).max()!
        let corridor=settings.companion == nil ? CGRect(x:left,y:screen.minY,width:right-left,height:screen.height):screen
        let plans=settings.companion != nil ? companionFlockPlans(screen:screen,profile:profile,scale:scale) : AmbientFlock.plan(screen:corridor,rightward:RandomChoice.chance(0.5, using: random.unit),count:3+Int(random.unit()*3),spriteScale:scale,
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
            guard supportsBehavior(.socialGreeting,bird:bird) else {return false}
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
        let reverse=RandomChoice.chance(0.5, using: socialRandom.unit)
        let plan=SocialGreetingPlan(initiator:reverse ? pair.1:pair.0,responder:reverse ? pair.0:pair.1)
        let result=runtime.start(SocialGreetingExecution(plan:plan),source:source,in:self)
        if result.accepted {
            scheduler.suppress()
            perchPlanner.suppress(pair.0);perchPlanner.suppress(pair.1)
        }
        return result
    }
    private func socialMotionCandidates(_ kind:BehaviorKind) -> [BirdID] {
        order.filter {id in
            guard let record=records[id],record.visible,record.role == .resident else {return false}
            let bird=record.bird
            return supportsBehavior(kind,bird:bird) &&
                bird.state == .perched && bird.edge == .top && !bird.isDeparting &&
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
        let ids=socialMotionCandidates(action.behavior)
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
        let old=fixedPerches
        world.surfaces.removeAll(where: \.isFixedPerch)
        fixedPerches=settings.fixedPerchesEnabled && world.fixedPerchArtAvailable ? FixedPerchLayout.resolve(anchors:sceneEnabled ? settings.fixedPerches.filter{anchor in SceneInstance(kind:.perch,anchor:anchor).point(in:world) != nil}:settings.fixedPerches,world:world):[]
        let live=Set(fixedPerches.map(\.slot))
        giftReceiverRevisions=giftReceiverRevisions.filter{live.contains($0.key)}
        for perch in fixedPerches {
            let unchanged=giftReceiverDisplayIDs==world.displayIDs &&
                giftReceiverAnchors.first(where:{$0.slot==perch.slot})==settings.fixedPerches.first(where:{$0.slot==perch.slot}) &&
                old.contains{$0.slot==perch.slot && $0.surface==perch.surface && $0.foot==perch.foot && $0.rect==perch.rect}
            if !unchanged || giftReceiverRevisions[perch.slot]==nil {
                guard nextGiftReceiverRevision<UInt64.max else {giftReceiverRevisions.removeValue(forKey:perch.slot);continue}
                giftReceiverRevisions[perch.slot]=nextGiftReceiverRevision;nextGiftReceiverRevision+=1
            }
        }
        giftReceiverAnchors=settings.fixedPerches;giftReceiverDisplayIDs=world.displayIDs
        world.surfaces.append(contentsOf:fixedPerches.map(\.surface))
        runtime.validate(in:self,where:{$0.kind == .fixedPerchVisit})
        for bird in birds {
            guard let old=previous.first(where:{$0.id==bird.hostID && $0.pid==bird.hostPID}),
                  !world.surfaces.contains(old) else {continue}
            if let id=id(of:bird) {runtime.cancel(bird:id,reason:.targetInvalid,in:self)}
            if bird.hostID==old.id,bird.hostPID==old.pid,!bird.isDeparting {bird.requestFlightRecovery()}
        }
    }
    func giftReceiverRevision(slot:Int) -> UInt64? {giftReceiverRevisions[slot]}
    private func giftEnabled(source:BehaviorSource) -> Bool {
        (source == .automatic || source == .preview) &&
            BehaviorDefinitions.definition(for:.visitorGift).isEnabled(settings:settings,source:source) &&
            (source != .automatic || ambientEnabled) &&
            settings.probabilities.participates(.azureWingedMagpie)
    }
    private func giftAdmissionReason(source:BehaviorSource) -> BehaviorReason? {
        if paused {return .paused}
        if !giftEnabled(source:source) {return .disabled}
        if world.buttonsDown {return .userInput}
        if encounterUnavailable || scheduledEncounter != nil || registeredGiftToken != nil {return .busy}
        if !world.fixedPerchArtAvailable || !world.leafCarryArtAvailable {return .missingFrames}
        let required=SpeciesBehaviorProfile.profile(for:.azureWingedMagpie).requiredFrames(for:.visitorGift)
        if !required.isSubset(of:world.availableFrames[.azureWingedMagpie] ?? []) {return .missingFrames}
        let residents=birds.filter{$0.profile.id == .azureWingedMagpie && role(of:$0) == .resident && !$0.isDeparting}
        if residents.isEmpty {return .noSpecies}
        if !residents.contains(where:{visitor(of:$0).map{$0.visits>=3 && $0.familiarity>=0.6} ?? false}) {return .notFamiliar}
        return nil
    }
    private func requestVisitorGift(source:BehaviorSource) -> BehaviorResult {
        if let reason=giftAdmissionReason(source:source) {return reject(.visitorGift,source,reason)}
        guard let plan=giftRandom.element(VisitorGiftPlan.candidates(in:self,source:source)),
              let bird=bird(plan.id),let visitor=visitor(of:bird) else {return reject(.visitorGift,source,.noSpace)}
        guard nextGiftRequestID<UInt64.max else {return reject(.visitorGift,source,.authorizationDenied)}
        let binding=GiftBinding(requestID:String(nextGiftRequestID),visitorArchiveSeed:visitorMemoryArchive.seed,
            visitorID:visitor.id,birdID:plan.id,species:bird.profile.id,source:source,leafID:plan.leafID,
            receiverSlot:plan.receiverSlot,receiverRevision:plan.receiverRevision)
        guard binding.isValid else {return reject(.visitorGift,source,.authorizationDenied)}
        nextGiftRequestID+=1
        let request=GiftAuthorizationRequest(binding:binding)
        pendingGift=PendingGift(request:request,plan:plan,motionRevision:bird.motionRevision)
        lastGiftAuthorizationDenial=nil;scheduler.suppress()
        giftAuthorizationObserver?(request)
        return .scheduled
    }
    /// Even a late/repeated result is an external input. Recording it does not
    /// revive a cancelled request, issue another grant, or read the real ledger.
    public func receiveGiftAuthorization(_ result:GiftAuthorizationResult) {
        guard result.isValid else {return}
        var input=RecordedInput(kind:"giftAuthorization");input.giftAuthorization=result
        if let recorder=inputRecorder {recorder.append(input);recorder.depth+=1}
        defer {if let recorder=inputRecorder {recorder.depth-=1}}
        guard let pending=pendingGift,pending.request.binding==result.binding else {return}
        pendingGift=nil
        if let denial=result.denial {
            lastGiftAuthorizationDenial=denial
            _=reject(.visitorGift,result.binding.source,denial == .timedOut ? .timedOut:.authorizationDenied)
            return
        }
        guard let token=result.token,token.binding==pending.request.binding else {return}
        if let reason=giftAdmissionReason(source:result.binding.source) {_=reject(.visitorGift,result.binding.source,reason);return}
        guard let bird=bird(result.binding.birdID),bird.motionRevision==pending.motionRevision,
              visitorMemoryArchive.seed==result.binding.visitorArchiveSeed,
              visitor(of:bird)?.id==result.binding.visitorID,
              giftReceiverRevision(slot:result.binding.receiverSlot)==result.binding.receiverRevision,
              let plan=pending.plan.revalidate(in:self),plan.id==result.binding.birdID,
              plan.leafID==result.binding.leafID,plan.receiverSlot==result.binding.receiverSlot,
              plan.receiverRevision==result.binding.receiverRevision else {
            _=reject(.visitorGift,result.binding.source,.targetInvalid);return
        }
        registeredGiftToken=RegisteredGiftToken(token:token)
        let started=runtime.start(VisitorGiftExecution(plan:plan,token:token),source:result.binding.source,in:self)
        if case .rejected(let reason)=started {
            registeredGiftToken=nil;_=reject(.visitorGift,result.binding.source,reason)
        } else {scheduler.suppress();perchPlanner.suppress(plan.id)}
    }
    func bindGiftAuthorization(_ token:GiftAuthorizationToken,run:BehaviorRunID) -> Bool {
        guard var grant=registeredGiftToken,grant.token==token,grant.run==nil,!grant.consumed,
              runtime.owners[token.binding.birdID]==run,
              runtime.runs[run]?.execution.kind == .visitorGift,
              runtime.runs[run]?.source==token.binding.source else {return false}
        grant.run=run;registeredGiftToken=grant;return true
    }
    func consumeGiftAuthorization(_ tokenID:UUID,run:BehaviorRunID) -> Bool {
        guard var grant=registeredGiftToken,grant.token.id==tokenID,grant.run==run,!grant.consumed,
              runtime.owners[grant.token.binding.birdID]==run else {return false}
        grant.consumed=true;registeredGiftToken=grant;return true
    }
    func invalidateGiftAuthorization(_ tokenID:UUID,run:BehaviorRunID) {
        guard let grant=registeredGiftToken,grant.token.id==tokenID,grant.run==run else {return}
        registeredGiftToken=nil
    }
    func releaseGiftAuthorization(run:BehaviorRunID) {
        guard let grant=registeredGiftToken else {return}
        if grant.run==run || (grant.run==nil && runtime.runs[run]?.execution.kind == .visitorGift &&
            runtime.owners[grant.token.binding.birdID]==run) {registeredGiftToken=nil}
    }
    private func cancelGiftRequest(_ reason:BehaviorReason) {
        guard let pending=pendingGift else {return}
        pendingGift=nil
        emit(pending.request.binding.source == .preview ? .previewResult:.rejected,
            kind:.visitorGift,source:pending.request.binding.source,reason:reason)
    }
    private func refreshGiftRequest() {
        guard let pending=pendingGift else {return}
        let b=pending.request.binding
        guard !paused,giftEnabled(source:b.source) else {cancelGiftRequest(paused ? .paused:.settingsChanged);return}
        guard !world.buttonsDown else {cancelGiftRequest(.userInput);return}
        guard let bird=bird(b.birdID),role(of:bird) == .resident,!bird.isDeparting,
              bird.motionRevision==pending.motionRevision,runtime.owners[b.birdID]==nil,
              visitorMemoryArchive.seed==b.visitorArchiveSeed,visitor(of:bird)?.id==b.visitorID,
              giftReceiverRevision(slot:b.receiverSlot)==b.receiverRevision,
              let leaf=carriedObjects.objects[b.leafID],!leaf.isVisitorGift,
              leaf.state == .available || leaf.state == .placed,leaf.owner==nil,leaf.reservedByRun==nil else {
            cancelGiftRequest(.targetInvalid);return
        }
        let frames=SpeciesBehaviorProfile.profile(for:b.species).requiredFrames(for:.visitorGift)
        if !world.leafCarryArtAvailable || !world.fixedPerchArtAvailable ||
            !frames.isSubset(of:world.availableFrames[b.species] ?? []) {cancelGiftRequest(.missingFrames)}
    }
    private func clearVisitorGifts(reason:BehaviorReason) {
        cancelGiftRequest(reason)
        runtime.cancel(where:{$0.kind == .visitorGift},reason:reason,in:self)
        carriedObjects.clearVisitorGifts(in:self,immediate:true)
        registeredGiftToken=nil
    }
    func recoverFromCourtship(_ id:BirdID) {recoverFromInsectCatch(id)}
    func recoverFromVisitorGift(_ id:BirdID) {recoverFromInsectCatch(id)}
    private func insectSpeciesEnabled(_ species:SpeciesID) -> Bool {
        SpeciesBehaviorProfile.profile(for:species).allows(.insectCatch) &&
            settings.probabilities.participates(species)
    }
    /// Species share one entity, opportunity and resolver pipeline, while each
    /// plan retains its own admission, flight and completion contract.
    private enum InsectCandidate {
        case swallow(InsectCatchPlan)
        case flycatcher(FlycatcherInsectCatchPlan)
        var birdID:BirdID {
            switch self {
            case .swallow(let plan):return plan.id
            case .flycatcher(let plan):return plan.id
            }
        }
        func execution(insectID:ScenePropID) -> BehaviorExecution {
            switch self {
            case .swallow(let plan):return InsectCatchExecution(plan:plan,insectID:insectID)
            case .flycatcher(let plan):return FlycatcherInsectCatchExecution(plan:plan,insectID:insectID)
            }
        }
        func replacingTrajectory(_ value:InsectTrajectory) -> Self? {
            switch self {
            case .swallow(let plan):return plan.replacingTrajectory(value).map(Self.swallow)
            case .flycatcher(let plan):return plan.replacingTrajectory(value).map(Self.flycatcher)
            }
        }
    }
    private func insectCandidates(species:SpeciesID,source:BehaviorSource) -> [InsectCandidate] {
        switch species {
        case .barnSwallow:return InsectCatchPlan.candidates(in:self,species:species,source:source).map(InsectCandidate.swallow)
        case .yellowRumpedFlycatcher:return FlycatcherInsectCatchPlan.candidates(in:self,species:species,source:source).map(InsectCandidate.flycatcher)
        default:return []
        }
    }
    private func canAwaitInsectFlight(_ bird:Bird) -> Bool {
        guard let id=id(of:bird),let owner=runtime.owners[id] else {return true}
        guard bird.profile.id == .barnSwallow else {return false}
        // Natural takeoff preparation is part of the departure being awaited.
        // Keep its lease intact; candidate selection still requires no owner.
        return runtime.runs[owner].map{$0.source == .automatic && $0.execution.kind == .takeoffPreparation} ?? false
    }
    private func insectAdmissionReason(species:SpeciesID,source:BehaviorSource) -> BehaviorReason? {
        if paused {return .paused}
        if !BehaviorDefinitions.definition(for:.insectCatch).isEnabled(settings:settings,source:source) ||
            (source == .automatic && !ambientEnabled) {return .disabled}
        if !insectSpeciesEnabled(species) {return .noSpecies}
        if world.buttonsDown {return .userInput}
        if encounterUnavailable || scheduledEncounter != nil || insects.current != nil ||
            hasCarryLeafPlacement || hasBathPlacement || hasFoodTrayPlacement {return .busy}
        if !world.insectArtAvailable {return .missingFrames}
        let residents=birds.filter{role(of:$0) == .resident && !$0.isDeparting && $0.profile.id==species}
        if residents.isEmpty {return .noSpecies}
        let required=SpeciesBehaviorProfile.profile(for:species).requiredFrames(for:.insectCatch)
        if !required.isSubset(of:world.availableFrames[species] ?? []) {return .missingFrames}
        if residents.allSatisfy({!canAwaitInsectFlight($0)}) {return .busy}
        return nil
    }
    private func startInsectCatch(_ plan:InsectCandidate,source:BehaviorSource) -> BehaviorResult {
        let insectID=ScenePropID(nextPropID)
        let result=runtime.start(plan.execution(insectID:insectID),source:source,in:self)
        if case .started=result {nextPropID+=1;scheduler.suppress()}
        return result
    }
    private func requestInsectCatch(species:SpeciesID,source:BehaviorSource) -> BehaviorResult {
        guard pendingInsectPreview==nil else {return reject(.insectCatch,source,.busy)}
        if let reason=insectAdmissionReason(species:species,source:source) {return reject(.insectCatch,source,reason)}
        if source == .automatic,settings.companion == nil,!scheduler.canAttemptInsectCatch {return reject(.insectCatch,source,.busy)}
        let candidates=insectCandidates(species:species,source:source)
        if let plan=insectRandom.element(candidates) {
            let result=startInsectCatch(plan,source:source)
            if case .rejected(let reason)=result {return reject(.insectCatch,source,reason)}
            return result
        }
        let available=birds.filter{$0.profile.id==species && role(of:$0) == .resident && !$0.isDeparting && canAwaitInsectFlight($0)}
        if species == .barnSwallow,source == .preview,available.contains(where:{$0.airborneFlight==nil}) {
            pendingInsectPreview=PendingInsectPreview(species:species,remaining:10)
            return .scheduled
        }
        if species == .yellowRumpedFlycatcher {
            let settled=available.contains {bird in
                bird.state == .perched && bird.edge == .top && !bird.needsDestination &&
                    world.surfaces.contains {$0.id==bird.hostID && $0.pid==bird.hostPID &&
                        $0.canHostBirds && !$0.isHabitat && ($0.isGround || $0.layer==0)}
            }
            return reject(.insectCatch,source,settled ? .noSpace:.unavailableBird)
        }
        return reject(.insectCatch,source,available.contains(where:{$0.airborneFlight != nil}) ? .noSpace:.unavailableBird)
    }
    /// Native acceptance bridge, like installFixtureBirds. Only an immutable,
    /// physically valid target route may be replaced; flight admission, leases,
    /// motion, sweep detection and recovery remain the production pipeline.
    /// This is deliberately absent from EngineCommand and live recordings.
    @discardableResult public func startInsectCatchFixture(species:SpeciesID,trajectory:InsectTrajectory) -> BehaviorResult {
        inputRecorder?.log.failure="immutable insect trajectory fixture is not a recordable production command"
        guard pendingInsectPreview==nil else {return reject(.insectCatch,.preview,.busy)}
        if let reason=insectAdmissionReason(species:species,source:.preview) {return reject(.insectCatch,.preview,reason)}
        guard let original=insectRandom.element(insectCandidates(species:species,source:.preview)),
              let plan=original.replacingTrajectory(trajectory) else {return reject(.insectCatch,.preview,.noSpace)}
        let result=startInsectCatch(plan,source:.preview)
        if case .rejected(let reason)=result {return reject(.insectCatch,.preview,reason)}
        return result
    }
    private func advanceInsectPreview(_ dt:Double) {
        guard var pending=pendingInsectPreview else {return}
        if let reason=insectAdmissionReason(species:pending.species,source:.preview) {cancelInsectPreview(reason);return}
        // No random draw, lease, entity or forced takeoff while waiting.
        let candidates=insectCandidates(species:pending.species,source:.preview)
        if let plan=insectRandom.element(candidates) {
            pendingInsectPreview=nil
            let result=startInsectCatch(plan,source:.preview)
            let reason:BehaviorReason?;if case .rejected(let value)=result {reason=value}else{reason=nil}
            emit(.previewResult,kind:.insectCatch,source:.preview,reason:reason)
            return
        }
        pending.remaining=max(0,pending.remaining-dt);pendingInsectPreview=pending
        if pending.remaining<=1e-10 {cancelInsectPreview(.timedOut)}
    }
    private func requestAutomaticInsectCatch() {
        guard pendingInsectPreview==nil,(settings.companion != nil || scheduler.sceneFocus==nil),(settings.companion != nil || scheduler.canAttemptInsectCatch) else {return}
        // A disabled or unqualified fixed 8% opportunity remains empty.
        let candidates=SpeciesBehaviorProfile.species(for:.insectCatch).flatMap {species -> [InsectCandidate] in
            guard insectAdmissionReason(species:species,source:.automatic)==nil else {return []}
            return insectCandidates(species:species,source:.automatic)
        }.enumerated().sorted {a,b in
            a.element.birdID==b.element.birdID ? a.offset<b.offset:a.element.birdID<b.element.birdID
        }.map(\.element)
        if let plan=insectRandom.element(candidates) {_=startInsectCatch(plan,source:.automatic)}
    }
    private func cancelInsectPreview(_ reason:BehaviorReason) {
        guard pendingInsectPreview != nil else {return}
        pendingInsectPreview=nil
        emit(.previewResult,kind:.insectCatch,source:.preview,reason:reason)
    }
    private func clearInsects(reason:BehaviorReason) {
        cancelInsectPreview(reason)
        runtime.cancel(where:{$0.kind == .insectCatch},reason:reason,in:self)
        insects.clear()
    }
    private func refreshInsects(sampleDT:Double?=nil) {
        if !insects.synchronize(in:self) {
            runtime.cancel(where:{$0.kind == .insectCatch},reason:.targetInvalid,in:self)
        }
        if !world.insectArtAvailable {cancelInsectPreview(.missingFrames)}
        if let pending=pendingInsectPreview,!SpeciesBehaviorProfile.profile(for:pending.species).requiredFrames(for:.insectCatch).isSubset(of:world.availableFrames[pending.species] ?? []) {
            cancelInsectPreview(.missingFrames)
        }
        for runID in runtime.runs.keys.sorted() {
            guard let execution=runtime.runs[runID]?.execution as? InsectCatchMotionExecution else {continue}
            if let result=execution.reconcileWorld(in:self,sampleDT:sampleDT) {runtime.finish(runID,result:result,in:self)}
        }
    }
    private func refreshNestMotion(sampleDT:Double?=nil) {
        for id in runtime.runs.keys.sorted() {
            guard let execution=runtime.runs[id]?.execution as? NestMotionExecution else {continue}
            if let result=execution.reconcileWorld(in:self,sampleDT:sampleDT) {runtime.finish(id,result:result,in:self)}
        }
    }
    private func placeNest(at point:CGPoint)->BehaviorResult {
        guard !paused else {return reject(.nestMaterialCarry,.user,.paused)}
        guard settings.nestBuildingEnabled else {return reject(.nestMaterialCarry,.user,.disabled)}
        guard world.nestArtAvailable else {return reject(.nestMaterialCarry,.user,.missingFrames)}
        guard !world.buttonsDown else {return reject(.nestMaterialCarry,.user,.userInput)}
        guard habitatObjects.objects.isEmpty,scheduler.sceneFocus==nil,!hasFoodTrayPlacement,
              !hasBathPlacement,!hasCarryLeafPlacement else {return reject(.nestMaterialCarry,.user,.busy)}
        guard nextPropID<UInt64.max-3 else {return reject(.nestMaterialCarry,.user,.noSpace)}
        let materials=(0..<3).map{ScenePropID(nextPropID+UInt64($0))}
        let result=habitatObjects.placeNest(at:point,materialIDs:materials,in:self)
        if case .rejected(let reason)=result {return reject(.nestMaterialCarry,.user,reason)}
        guard let id=habitatIDs(.nest).first else {return reject(.nestMaterialCarry,.user,.noSpace)}
        guard scheduler.acquireFocus(SceneFocus(nestID:id),frequency:settings.ambientFrequency) else {
            habitatObjects.remove(id);return reject(.nestMaterialCarry,.user,.busy)
        }
        nextPropID+=3;pendingNestPlacement=nil;refreshHabitatObjects();return .accepted
    }
    private func requestNest(kind:BehaviorKind,source:BehaviorSource)->BehaviorResult {
        guard !paused else {return reject(kind,source,.paused)}
        guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:settings,source:source),
              source != .automatic || ambientEnabled else {return reject(kind,source,.disabled)}
        guard settings.probabilities.participates(.spottedDove) else {return reject(kind,source,.noSpecies)}
        guard !world.buttonsDown else {return reject(kind,source,.userInput)}
        guard !encounterUnavailable,scheduledEncounter==nil,!hasNestPlacement,!hasInsectCatchPreview else {return reject(kind,source,.busy)}
        guard world.nestArtAvailable else {return reject(kind,source,.missingFrames)}
        guard let nest=nestSnapshot().first(where:{!$0.retiring && (sceneCandidateID == nil || $0.id==sceneCandidateID)}) else {return reject(kind,source,.noSpace)}
        guard source != .automatic || settings.companion != nil || scheduler.canAttemptScene(SceneFocus(nestID:nest.id)) else {return reject(kind,source,.busy)}
        guard birds.contains(where:{role(of:$0) == .resident && $0.profile.id == .spottedDove}) else {return reject(kind,source,.noSpecies)}
        guard BehaviorDefinitions.definition(for:kind).requiredFrames.isSubset(of:world.availableFrames[.spottedDove] ?? []) else {return reject(kind,source,.missingFrames)}
        let result:BehaviorResult
        if kind == .nestBuild {
            guard nest.delivered>0,let plan=nestRandom.element(NestBuildPlan.candidates(in:self,source:source,target:sceneCandidateID)),plan.canBegin(in:self)
            else {return reject(kind,source,.noSpace)}
            result=runtime.start(NestBuildExecution(plan:plan),source:source,in:self)
        } else {
            guard nest.available>0,let plan=nestRandom.element(NestMaterialCarryPlan.candidates(in:self,source:source,target:sceneCandidateID)),plan.canBegin(in:self)
            else {return reject(kind,source,.noSpace)}
            result=runtime.start(NestMaterialCarryExecution(plan:plan),source:source,in:self)
        }
        if result.accepted {scheduler.suppress()}
        else if case .rejected(let reason)=result {return reject(kind,source,reason)}
        return result
    }
    func recoverFromNest(_ id:BirdID,excluding object:HabitatObjectID?=nil) {
        if let object {recoverFromHabitat(id,excluding:object,immediate:paused)}
        else {recoverFromInsectCatch(id)}
    }
    private func reconcileNestFocus() {
        guard let id=scheduler.sceneFocus?.nestID else {return}
        guard let nest=nestSnapshot().first(where:{$0.id==id}),nest.canContinue else {
            scheduler.endFocus(matching:SceneFocus(nestID:id),frequency:settings.ambientFrequency);return
        }
    }
    private func placeCarryLeaf(at point:CGPoint)->BehaviorResult {
        guard !paused else {return reject(.leafCarry,.user,.paused)}
        guard settings.leafCarryEnabled else {return reject(.leafCarry,.user,.disabled)}
        guard world.leafCarryArtAvailable else {return reject(.leafCarry,.user,.missingFrames)}
        guard !world.buttonsDown else {return reject(.leafCarry,.user,.userInput)}
        guard carriedObjects.objects.isEmpty,scheduler.sceneFocus==nil,
              !hasBathPlacement,!hasNestPlacement else {return reject(.leafCarry,.user,.busy)}
        let id=ScenePropID(nextPropID)
        let nearest=birds.filter{role(of:$0) == .resident && SpeciesBehaviorProfile.profile(for:$0.profile.id).allows(.leafCarry)}.sorted {
            let a=Geometry.distance($0.position,point),b=Geometry.distance($1.position,point)
            return a==b ? self.id(of:$0)!<self.id(of:$1)!:a<b
        }.first
        let facingRight=nearest.map{$0.position.x<=point.x} ?? true
        let result=carriedObjects.placeLeaf(id:id,at:point,facingRight:facingRight,in:self)
        if case .rejected(let reason)=result {return reject(.leafCarry,.user,reason)}
        guard scheduler.acquireFocus(SceneFocus(leafID:id),frequency:settings.ambientFrequency) else {
            carriedObjects.retire(id,in:self,immediate:true);return reject(.leafCarry,.user,.busy)
        }
        nextPropID+=1;pendingCarryLeafPlacement=nil;return .accepted
    }
    private func requestLeafCarry(source:BehaviorSource)->BehaviorResult {
        guard !paused else {return reject(.leafCarry,source,.paused)}
        guard BehaviorDefinitions.definition(for:.leafCarry).isEnabled(settings:settings,source:source),
              source != .automatic || ambientEnabled else {return reject(.leafCarry,source,.disabled)}
        guard !world.buttonsDown else {return reject(.leafCarry,source,.userInput)}
        guard !encounterUnavailable,scheduledEncounter==nil,!hasCarryLeafPlacement,!hasBathPlacement,!hasFoodTrayPlacement
        else {return reject(.leafCarry,source,.busy)}
        guard world.leafCarryArtAvailable else {return reject(.leafCarry,source,.missingFrames)}
        guard let object=carriedObjects.objects.values.filter({$0.state == .available && $0.reservedByRun==nil}).sorted(by:{$0.id<$1.id}).first
        else {return reject(.leafCarry,source,.noSpace)}
        if source == .automatic,settings.companion == nil,!scheduler.canAttemptScene(SceneFocus(leafID:object.id)) {return reject(.leafCarry,source,.busy)}
        let candidates=LeafCarryPlan.candidates(in:self,source:source)
        guard let plan=leafCarryRandom.element(candidates) else {
            let supported=birds.filter{role(of:$0) == .resident && SpeciesBehaviorProfile.profile(for:$0.profile.id).allows(.leafCarry)}
            let frames=BehaviorDefinitions.definition(for:.leafCarry).requiredFrames
            let reason:BehaviorReason = supported.isEmpty ? .noSpecies:
                supported.allSatisfy({!frames.isSubset(of:world.availableFrames[$0.profile.id] ?? [])}) ? .missingFrames:
                supported.allSatisfy({id(of:$0).map{runtime.owners[$0] != nil} ?? true}) ? .busy:
                supported.contains(where:{pointerNear($0)}) ? .pointerNearby:.noSpace
            return reject(.leafCarry,source,reason)
        }
        let result=runtime.start(LeafCarryExecution(plan:plan),source:source,in:self)
        if result.accepted {perchPlanner.suppress(plan.id);scheduler.suppress()}
        else if case .rejected(let reason)=result {return reject(.leafCarry,source,reason)}
        return result
    }
    private func refreshCarriedObjects(sampleDT:Double?=nil) {
        for runID in runtime.runs.keys.sorted() {
            guard let execution=runtime.runs[runID]?.execution as? LeafCarryExecution else {continue}
            if let result=execution.reconcileWorld(in:self,sampleDT:sampleDT) {runtime.finish(runID,result:result,in:self)}
        }
        let identities=carriedObjects.objects.mapValues(\.persistentID)
        let invalid=carriedObjects.synchronize(in:self)
        if !invalid.isEmpty {
            markInvalidSceneSupports(invalid,identities:identities)
            removeCarriedObjects(reason:.targetInvalid,ids:invalid)
        }
    }
    private func markInvalidSceneSupports(_ ids:[ScenePropID],identities:[ScenePropID:UUID?]) {
        // Synchronization can remove a paused object immediately; capture identity
        // before that call so an unrelated window at the same position cannot claim it.
        for id in ids {
            if let uuid=identities[id] ?? nil,sceneArchive.layout.instances.first(where:{$0.id==uuid})?.requiresWindowPlacement == true {sceneNeedsPlacement.insert(uuid)}
        }
    }
    private func removeCarriedObjects(reason:BehaviorReason,ids:[ScenePropID]?=nil) {
        let targets=Set(ids ?? Array(carriedObjects.objects.keys))
        if let leaf=pendingGift?.request.binding.leafID,targets.contains(leaf) {cancelGiftRequest(reason)}
        runtime.cancel(where:{!targets.isDisjoint(with:$0.propIDs)},reason:reason,in:self)
        let immediate=paused || [.sleep,.shutdown,.screensChanged,.spaceChanged].contains(reason)
        for id in targets.sorted() {carriedObjects.retire(id,in:self,immediate:immediate)}
    }
    /// Emergency exit after the catch run has released its lease. Reuse the
    /// bounded ordinary-surface recovery queue, including pause semantics.
    func recoverFromInsectCatch(_ id:BirdID) {
        guard runtime.owners[id]==nil,let bird=bird(id),!bird.isDeparting else {return}
        bird.requestFlightRecovery();recoveringHabitatBirds.insert(id)
        if !paused {resumeHabitatRecovery(id)}
    }
    /// Shared ordinary-surface recovery; caller has already released ownership.
    func recoverFromCarriedObject(_ id:BirdID) {
        guard let bird=bird(id),!bird.isDeparting else {return}
        bird.requestFlightRecovery();recoveringHabitatBirds.insert(id)
        if !paused {resumeHabitatRecovery(id)}
    }
    private func placeBath(at point:CGPoint)->BehaviorResult {
        guard !paused else {return reject(.bathVisit,.user,.paused)}
        guard settings.bathEnabled else {return reject(.bathVisit,.user,.disabled)}
        guard world.bathArtAvailable else {return reject(.bathVisit,.user,.missingFrames)}
        guard !world.buttonsDown else {return reject(.bathVisit,.user,.userInput)}
        guard habitatObjects.objects.isEmpty,scheduler.sceneFocus==nil,!hasFoodTrayPlacement,!hasCarryLeafPlacement,!hasNestPlacement else {return reject(.bathVisit,.user,.busy)}
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
        if source == .automatic,settings.companion == nil,!scheduler.canAttemptScene(object) {return reject(.bathVisit,source,.busy)}
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
        guard habitatObjects.objects.isEmpty,!hasBathPlacement,!hasNestPlacement else {return reject(.foodTrayVisit,.user,.busy)}
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
        recoveryWorld.surfaces.removeAll{$0.isHabitat || sceneExcludedSurfaces.contains($0.id)}
        let reserved=runtime.landingReservations.filter{$0.bird != id}.compactMap{$0.footprint(in:self)}+giftObstacleRects(excluding:[id])
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
        habitatObjects.captureAttachedSnapshots(in:self)
        for id in targets {habitatObjects.beginRetirement(id,reason:reason)}
        if let focus=scheduler.sceneFocus,let id=focus.objectID,targets.contains(id) {scheduler.endFocus(matching:focus,frequency:settings.ambientFrequency)}
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
            $0.retiring && ($0.kind == .bath || $0.kind == .nest || !runtime.habitatReservations.contains($0.id))
        }.map(\.id)
        removeHabitatObjects(reason:.removed,ids:retired)
    }
    private func refreshHabitatObjects(sampleDT:Double?=nil) {
        let invalidNests=Set(habitatObjects.invalidNestIDs(in:self,sampleDT:sampleDT))
        let invalid=habitatObjects.objects.values.filter {object in
            if object.kind == .nest {return invalidNests.contains(object.id)}
            let enabled=object.kind == .bath ? settings.bathEnabled:settings.foodTrayEnabled
            let available=object.kind == .bath ? world.bathArtAvailable:world.foodTrayArtAvailable
            return !available || !enabled || world.scale != object.scale ||
                world.screens != object.screens || world.displays != object.displays ||
                world.surfaces.contains(where:{$0.id==object.surface.id && $0 != object.surface}) ||
                fixedPerches.contains(where:{$0.rect.insetBy(dx:-50*world.scale,dy:-80*world.scale).intersects(object.rect)})
        }.map(\.id)
        for id in invalid {if let uuid=habitatObjects.objects[id]?.persistentID,sceneArchive.layout.instances.first(where:{$0.id==uuid})?.requiresWindowPlacement == true {sceneNeedsPlacement.insert(uuid)}}
        removeHabitatObjects(reason:.targetInvalid,ids:invalid)
        world.surfaces.removeAll{$0.habitatKind == .foodTray || $0.habitatKind == .bath || $0.habitatKind == .nest}
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
    private func startCourtship(_ plan:CourtshipDisplayPlan,source:BehaviorSource) -> BehaviorResult {
        let result=runtime.start(CourtshipDisplayExecution(plan:plan),source:source,in:self)
        if result.accepted {
            scheduler.suppress()
            for id in plan.participants {perchPlanner.suppress(id)}
        }
        return result
    }
    private func requestCourtship(source:BehaviorSource) -> BehaviorResult {
        guard !paused else {return reject(.courtshipDisplay,source,.paused)}
        guard BehaviorDefinitions.definition(for:.courtshipDisplay).isEnabled(settings:settings,source:source) else {return reject(.courtshipDisplay,source,.disabled)}
        guard settings.probabilities.participates(.spottedDove) else {return reject(.courtshipDisplay,source,.noSpecies)}
        guard !encounterUnavailable,scheduledEncounter==nil else {return reject(.courtshipDisplay,source,.busy)}
        guard !world.buttonsDown else {return reject(.courtshipDisplay,source,.userInput)}
        guard source != .automatic || settings.companion != nil || scheduler.canAttemptCourtship else {return reject(.courtshipDisplay,source,.busy)}
        let residents=birds.filter{role(of:$0) == .resident && !$0.isDeparting && $0.profile.id == .spottedDove}
        guard residents.count>=2 else {return reject(.courtshipDisplay,source,.noCompanion)}
        guard CourtshipDisplayPlan.requiredFrames.isSubset(of:world.availableFrames[.spottedDove] ?? []) else {return reject(.courtshipDisplay,source,.missingFrames)}
        guard let plan=courtshipRandom.element(CourtshipDisplayPlan.candidates(in:self,source:source)) else {
            return reject(.courtshipDisplay,source,.noSpace)
        }
        let result=startCourtship(plan,source:source)
        if case .rejected(let reason)=result {return reject(.courtshipDisplay,source,reason)}
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
        let available=SocialMotionKind.allCases.filter{
            !SocialMotionPlanner.candidates($0,ids:socialMotionCandidates($0.behavior),in:self).isEmpty
        }
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
    /// Product/content approval is separate from actual frames and live geometry.
    func supportsBehavior(_ kind:BehaviorKind,bird:Bird) -> Bool {
        let profile=SpeciesBehaviorProfile.profile(for:bird.profile.id)
        return profile.allows(kind) && profile.hasReviewedContent(for:kind)
    }
    func supports(_ action:PerchActionKind,bird:Bird) -> Bool {
        supportsBehavior(action.behavior,bird:bird) &&
            SpeciesBehaviorProfile.profile(for:bird.profile.id).requiredFrames(for:action.behavior).isSubset(of:world.availableFrames[bird.profile.id] ?? [])
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
        guard supportsBehavior(action.behavior,bird:bird) else {return .unavailableBird}
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
            if let action=perchPlanner.candidate(id,bird:bird,dt:dt*(settings.companion.map{$0.mode == .focus ? 0.5:$0.mode == .natural ? 0.8:1} ?? 1),enabled:enabled,occupied:runtime.owners[id] != nil,
                quiet:!world.buttonsDown && !pointerNear(bird),
                restRate:ActivityRhythmPolicy.restRate(mode:settings.companion.map{$0.followLocalDayNight ? .localDayNight:.steady} ?? settings.activityRhythm,minute:world.localMinuteOfDay,species:bird.profile.id)),enabled,perchRejection(action,bird:bird)==nil {
                candidates.append((id,action))
            }
        }
        if let choice=ecologicalChoice(candidates,weight:{self.perchPlanner.automaticWeight($0.0,kind:$0.1.behavior)}) {
            _=requestPerchAction(choice.1,source:.automatic,target:choice.0)
        }
    }
    func plan(for bird:Bird,entering:Bool=false,avoiding:CGPoint?=nil) -> DestinationPlan? {
        DestinationPlanner.plan(for:bird,birds:birds,world:world,entering:entering,avoiding:avoiding,
            reserved:runtime.landingReservations.filter{$0.bird != id(of:bird)}.compactMap{$0.footprint(in:self)} +
                giftObstacleRects(excluding:id(of:bird).map{[$0]} ?? []),random:random)
    }
    @discardableResult public func route(_ bird:Bird,entering:Bool=false,avoiding:CGPoint?=nil) -> Bool {
        var input=RecordedInput(kind:"route");input.bird=id(of:bird).map{String($0.rawValue)};input.entering=entering;input.avoiding=avoiding.map(RecordedPoint.init)
        beginRecordingInput(input);defer {endRecordingInput()}
        guard let plan=plan(for:bird,entering:entering,avoiding:avoiding) else {return false}
        if let id=id(of:bird) {
            if pendingGift?.request.binding.birdID==id {cancelGiftRequest(.replaced)}
            runtime.cancel(bird:id,reason:.replaced,in:self)
        }
        plan.apply(to:bird,random:random);return true
    }
    private func routeAutonomously(_ bird:Bird,id:BirdID) {
        // One optional choice at the existing departure opportunity. No new
        // timer, resident, or forced takeoff is created by placing a perch.
        if settings.companion == nil,ambientEnabled,!habitatIDs(.foodTray).isEmpty,bird.state == .perched,
           foodDepartureAttempts[id] != bird.motionRevision,
           BehaviorDefinitions.definition(for:.foodTrayVisit).isEnabled(settings:settings,source:.automatic) {
            foodDepartureAttempts[id]=bird.motionRevision
            if RandomChoice.chance(0.25, using: foodRandom.unit),requestFoodTrayVisit(source:.automatic,target:id).accepted {return}
        }
        if settings.companion == nil,ambientEnabled,!fixedPerches.isEmpty,bird.state == .perched,
           fixedPerchDepartureAttempts[id] != bird.motionRevision,
           BehaviorDefinitions.definition(for:.fixedPerchVisit).isEnabled(settings:settings,source:.automatic) {
            fixedPerchDepartureAttempts[id]=bird.motionRevision
            if RandomChoice.chance(0.15, using: habitatRandom.unit),requestFixedPerchVisit(source:.automatic,target:id).accepted {return}
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
        guard settings.probabilities.totalWeight > 0 else { return }
        guard let point=Migration.outsidePoint(screens:world.displays,right:RandomChoice.chance(0.5, using: random.unit),fraction:random.value(in:0.2...0.75),margin:80*world.scale*3+20) else {return}
        guard let species = settings.probabilities.choose(using: random.unit) else { return }
        let bird=Bird(position:point,fraction:random.value(in:0.12...0.88),profile:settings.catalog.profile(species),random:random.unit)
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
        guard let point=Migration.outsidePoint(screens:world.displays,right:RandomChoice.chance(0.5, using: random.unit),fraction:random.value(in:0.2...0.75),margin:80*world.scale*3+20) else {return}
        if let id=id(of:bird) {
            if pendingGift?.request.binding.birdID==id {cancelGiftRequest(.replaced)}
            runtime.cancel(bird:id,reason:.replaced,in:self)
        }
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
        if settings.companion != nil,!paused,!sceneEditing {companionMetrics.unpausedElapsed+=elapsed}
        accumulator+=min(0.05,elapsed)
        var steps=0
        while accumulator+1e-10>=Self.step && steps<3 {
            accumulator=max(0,accumulator-Self.step);steps+=1;step(Self.step)
        }
    }
    private func step(_ dt:Double) {
        if sceneEditing {advanceSceneEditing(dt);return}
        time+=dt
        if sceneEnabled {sceneRetryRemaining-=dt;if sceneRetryRemaining<=0 {sceneRetryRemaining=2;restoreMissingSceneObjects()}}
        if !paused {advanceCompanionEpisodes(dt)}
        if !paused {
            for id in recoveringHabitatBirds.sorted() {resumeHabitatRecovery(id)}
            habitatObjects.advance(dt)
            if !carriedObjects.objects.isEmpty {refreshCarriedObjects()}
            let expired=carriedObjects.advance(dt,in:self)
            if !expired.isEmpty {runtime.cancel(where:{!Set(expired).isDisjoint(with:$0.propIDs)},reason:.targetInvalid,in:self)}
            if let pending=pendingNestPlacement {
                let remaining=pending-dt;pendingNestPlacement=remaining
                if remaining<=1e-10 {
                    pendingNestPlacement=nil
                    let result=placeNest(at:world.pointer)
                    let reason:BehaviorReason?;if case .rejected(let why)=result {reason=why}else{reason=nil}
                    emit(.previewResult,kind:.nestMaterialCarry,source:.user,reason:reason)
                }
            }
            if let pending=pendingCarryLeafPlacement {
                let remaining=pending-dt;pendingCarryLeafPlacement=remaining
                if remaining<=1e-10 {
                    pendingCarryLeafPlacement=nil
                    let result=placeCarryLeaf(at:world.pointer)
                    let reason:BehaviorReason?;if case .rejected(let why)=result {reason=why}else{reason=nil}
                    emit(.previewResult,kind:.leafCarry,source:.user,reason:reason)
                }
            }
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
        refreshGiftRequest()
        if !paused {
            advanceInsectPreview(dt)
            // Other birds can invalidate a return between world samples.
            // Give the scene its safe replan before generic lease validation.
            if runtime.runs.values.contains(where:{$0.execution.kind == .insectCatch}) {refreshInsects()}
            if runtime.runs.values.contains(where:{$0.execution.kind.isNestActivity}) {refreshNestMotion()}
        }
        let insectStep=paused ? nil:insects.makeStep(dt)
        // Resolve input cancellations and pending spawns before integrating motion.
        runtime.advance(dt,in:self)
        collectRetiredHabitatObjects()
        // These single-bird scenes share the exclusive encounter lease.
        let motionRun=runtime.runs.values.first{$0.execution.kind == .insectCatch || $0.execution.kind == .visitorGift || $0.execution.kind.isNestActivity}
        let insectRun=motionRun?.execution.kind == .insectCatch ? motionRun:nil
        let motionBird=motionRun?.execution.participants.first
        let sceneMotionDT=motionRun?.motionDT ?? dt
        for id in order {
            guard let record=records[id],record.visible,runtime.canAdvance(id,paused:paused) else {continue}
            let motionDT=motionBird==id ? sceneMotionDT:dt
            if motionDT>0 {record.bird.tick(motionDT)}
        }
        if !paused {
            var contact:InsectContact?
            var completions:[(BehaviorRunID,BehaviorCompletion)]=[]
            if let run=insectRun,let execution=run.execution as? InsectCatchMotionExecution {
                let result=execution.resolveMotion(insectStep,in:self)
                contact=result.contact
                if let completion=result.completion {completions.append((run.id,completion))}
                else if run.age+1e-10>=run.execution.timeout {completions.append((run.id,.failed(.timedOut)))}
            }
            if let insectStep,!insects.commit(insectStep,capture:contact) {
                // Never report capture/recovery success after a stale or
                // invalid entity commit. This branch is an integrity failure.
                insects.clear()
                completions=runtime.runs.keys.sorted().compactMap {id in
                    runtime.runs[id]?.execution.kind == .insectCatch ? (id,.failed(.targetInvalid)):nil
                }
            }
            for (runID,result) in completions {runtime.finish(runID,result:result,in:self)}
            for id in runtime.runs.keys.sorted() {
                guard let run=runtime.runs[id],let gift=run.execution as? VisitorGiftExecution else {continue}
                if let result=gift.resolveMotion(in:self) {runtime.finish(id,result:result,in:self)}
                else if run.age+1e-10>=run.execution.timeout {runtime.finish(id,result:.failed(.timedOut),in:self)}
            }
            for id in runtime.runs.keys.sorted() {
                guard let run=runtime.runs[id],let execution=run.execution as? NestMotionExecution else {continue}
                if let result=execution.resolveMotion(in:self) {runtime.finish(id,result:result,in:self)}
                else if run.age+1e-10>=run.execution.timeout {runtime.finish(id,result:.failed(.timedOut),in:self)}
            }
            carriedObjects.captureAttachedSnapshots(in:self)
            habitatObjects.captureAttachedSnapshots(in:self)
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
        if !paused {
            for id in order {
                guard let bird=records[id]?.bird else {continue}
                livelyMotion.update(id:id,bird:bird,eligible:livelyEligible(id,bird:bird))
            }
        }
        reconcileNestFocus()
        let encounterRate=ActivityRhythmPolicy.ambientRate(mode:settings.activityRhythm,minute:world.localMinuteOfDay)
        if !paused,settings.companion != nil {advanceCompanionOpportunities(dt)}
        if !paused,settings.companion == nil,let event=scheduler.tick(dt,pointer:world.pointer,buttonsDown:world.buttonsDown,
            pointerEnabled:settings.pointerVisits,flockEnabled:settings.flockPasses,socialEnabled:settings.socialInteractions,leafEnabled:settings.leafPlayEnabled && settings.ambientLeafPlayEnabled,insectEnabled:settings.insectCatchEnabled,giftEnabled:settings.visitorGiftsEnabled && settings.visitorMemoryEnabled,courtshipEnabled:settings.courtshipEnabled,frequency:settings.ambientFrequency,
            busy:encounterUnavailable || scheduledEncounter != nil || hasInsectCatchPreview,cadenceRate:ambientEnabled ? encounterRate:0,leafRandom:ecologyRandom.unit,random:random.unit) {
            switch event {
            case .pointerVisit:_=requestPointer(.automatic)
            case .flockPass:_=requestFlock(.automatic)
            case .socialGreeting:requestSocialEncounter()
            case .leafPlay:requestAutomaticLeaf()
            case .visitorGift:_=requestVisitorGift(source:.automatic)
            case .insectCatch:requestAutomaticInsectCatch()
            case .courtshipDisplay:
                // No eligible pair discards this one opportunity without consuming
                // existing random streams or emitting a rejected ambient command.
                if scheduler.canAttemptCourtship,let plan=courtshipRandom.element(CourtshipDisplayPlan.candidates(in:self)) {
                    _=startCourtship(plan,source:.automatic)
                }
            case .nestVisit(let object):
                if scheduler.sceneFocus?.nestID==object,let nest=nestSnapshot().first(where:{$0.id==object}),nest.canContinue {
                    // The scheduler has already selected this scene's one chance.
                    // An unavailable participant discards it without a rejected
                    // user command or a second probability draw.
                    let execution:BehaviorExecution?
                    if nest.delivered>0 {
                        execution=nestRandom.element(NestBuildPlan.candidates(in:self,source:.automatic,target:object))
                            .map{NestBuildExecution(plan:$0)}
                    } else {
                        execution=nestRandom.element(NestMaterialCarryPlan.candidates(in:self,source:.automatic,target:object))
                            .map{NestMaterialCarryExecution(plan:$0)}
                    }
                    if let execution,runtime.start(execution,source:.automatic,in:self).accepted {scheduler.suppress()}
                }
            case .leafCarry(let object):
                if scheduler.sceneFocus?.leafID==object {_=requestLeafCarry(source:.automatic)}
            case .bathVisit(let object):
                if scheduler.sceneFocus?.objectID==object {_=requestBathVisit(source:.automatic)}
            }
        }
    }
    func prepareLivelyHandoff(_ id:BirdID) {
        if let bird=bird(id),let frame=livelyFrame(id,bird:bird) {
            poseMixer.release(BirdPose(frameName:frame,hopOffset:0),for:id,bird:bird)
        }
        livelyMotion.cancel(id)
    }
    private func cancelIneligibleLivelyMotion() {
        for id in order {
            if let bird=records[id]?.bird,!livelyEligible(id,bird:bird) {livelyMotion.cancel(id)}
        }
    }
    private func livelyEligible(_ id:BirdID,bird:Bird) -> Bool {
        let names=LivelyMotion.frameNames(for:bird.profile.id)
        guard let rhythm=perchPlanner.rhythms[id],rhythm.quietTime>=0.5,rhythm.disturbance<0.35,
              [BehaviorKind.watch,.alert,.rest,.preen].allSatisfy({(rhythm.cooldowns[$0] ?? 0)<=0}) else {return false}
        if let p=settings.companion {
            guard p.allows(.preen,source:.automatic) else {return false}
            let cycle=Int(bird.stateTime/max(1,LivelyMotion.window(bird.profile.id).cycle))
            if p.mode == .natural && (cycle+Int(id.rawValue%3))%3 != 0 {return false}
            let active=birds.filter {other in
                guard other !== bird,let otherID=self.id(of:other) else {return false}
                return livelyMotion.frame(id:otherID,bird:other,seed:seed,eligible:true) != nil
            }.count
            if active >= (p.mode == .lively ? 3:1),livelyMotion.frame(id:id,bird:bird,seed:seed,eligible:true)==nil {return false}
        }
        return !names.isEmpty && bird.state == .perched && !bird.isDeparting && !bird.needsDestination &&
            !bird.isSideHopping && runtime.owners[id]==nil && role(of:bird) == .resident &&
            world.surfaces.contains(where:{$0.id==bird.hostID}) &&
            LivelyMotion.isSideMotion(bird.profile.id) == (bird.edge != .top) &&
            settings.perchActions && (settings.companion?.mode != .focus) && (settings.companion != nil || settings.activityRhythm != .quiet) && !world.buttonsDown && !pointerNear(bird) &&
            Set(names).isSubset(of:world.availableFrames[bird.profile.id] ?? [])
    }
    private func livelyFrame(_ id:BirdID,bird:Bird) -> String? {
        livelyMotion.frame(id:id,bird:bird,seed:seed,eligible:livelyEligible(id,bird:bird))
    }
    func baseHop(for id:BirdID,bird:Bird) -> CGFloat {
        livelyFrame(id,bird:bird) == nil ? poseMixer.hop(for:id,bird:bird):0
    }
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
        var area=CGRect(x:bird.position.x-(facing ? 29:19)*scale,y:bird.position.y+(hop-39)*scale,width:48*scale,height:48*scale).insetBy(dx:-2,dy:-2)
        if let id=id(of:bird),carriedObjects.objects.values.contains(where:{$0.owner==id}) {
            let owned=Set(carriedObjects.objects.values.filter{$0.owner==id}.map(\.id))
            for prop in carriedObjects.snapshot(in:self) where owned.contains(prop.id) {area=area.union(prop.rect)}
        }
        if let id=id(of:bird) {
            let owned=Set(habitatObjects.objects.values.flatMap{$0.nest?.materials.filter{$0.owner==id}.map(\.id) ?? []})
            if !owned.isEmpty {
                for prop in habitatObjects.propSnapshots(in:self) where owned.contains(prop.id) {area=area.union(prop.rect)}
            }
        }
        return area
    }
    public func renderSnapshot() -> [BirdRenderState] {
        birds.compactMap {bird in
            guard let id=id(of:bird) else {return nil}
            let pose=runtime.presentation(for:id,in:self)
            return BirdRenderState(id:id,species:bird.profile.id,position:bird.position,facingRight:pose?.facingRight ?? bird.facingRight,
                scale:spriteScale(for:bird),hopOffset:pose?.hopOffset ?? baseHop(for:id,bird:bird),frameName:drawableFrame(pose?.frameName ?? livelyFrame(id,bird:bird) ?? bird.frameName,for:bird),
                blockers:bird.blockers(in:world.surfaces),hoverable:isHoverable(bird),opacity:companionEscapeStarted[id].map{max(0,min(1,16-(time-$0)))} ?? 1)
        }
    }
}

// Companion orchestration lives on the simulation owner, including every legacy entry point.
extension BehaviorEngine {
    func configureCompanion(previous:CompanionPreferences?) {
        guard let p=settings.companion else {return}
        companionScheduler.configure(p.policy,flockEnabled:settings.flockPasses && p.allows(.flockPass,source:.automatic))
        for bird in birds {bird.ordinaryOrbitLimit=0;bird.preferNearbyDestinations=p.mode != .lively}
        if previous?.mode != p.mode,p.mode != .lively {
            if let id=companionOrbit,let bird=bird(id) {bird.requestFlightRecovery();_=route(bird);companionOrbit=nil}
            for id in runtime.runs.keys.sorted() {
                guard let run=runtime.runs[id],run.source == .automatic,run.execution.kind.isSignificant else {continue}
                if !p.allows(run.execution.kind,source:.automatic) || run.execution.estimatedDuration(in:self)>p.policy.target(for:run.execution.kind) {
                    runtime.cancel(id,reason:.settingsChanged,in:self)
                }
            }
        }
    }
    func companionAdmission(_ execution:BehaviorExecution,source:BehaviorSource)->BehaviorReason? {
        guard let p=settings.companion else {return nil}
        guard p.allows(execution.kind,source:source) else {return .disabled}
        guard source == .automatic else {return nil}
        if execution.kind.isSignificant {
            guard !runtime.runs.values.contains(where:{$0.execution.kind.isSignificant}),companionScheduler.permit==execution.kind,companionRecovering.isEmpty,companionOrbit==nil else {return .busy}
            if execution.kind != .flockPass,execution.estimatedDuration(in:self)+(execution.participants.compactMap{bird($0)?.continuousFlightAge}.max() ?? 0)>p.policy.target(for:execution.kind) {return .unavailableBird}
        } else if execution.kind != .relocate {
            if execution.participants.contains(where:{(companionMicroNext[$0] ?? 0)>time}) {return .busy}
            let count=runtime.runs.values.filter{!$0.execution.kind.isSignificant && $0.source == .automatic}.count
            if count >= (p.mode == .lively ? 3:p.mode == .natural ? 2:1) {return .busy}
        }
        return nil
    }
    func companionDidStart(_ execution:BehaviorExecution,source:BehaviorSource) {
        guard let p=settings.companion else {return}
        if !execution.kind.isSignificant {
            if source == .automatic {for id in execution.participants {companionMicroNext[id]=time+(p.mode == .focus ? 24:p.mode == .natural ? 12:4)/p.policy.weight(for:execution.kind)}}
            return
        }
        for id in execution.participants {bird(id)?.episodeRetainsFlightClock=true}
        if source == .automatic {companionScheduler.didStart(execution.kind)}
        let habitatIDs=execution.habitatReservations.compactMap{habitatObjects.objects[$0]?.persistentID}
        let leafIDs=execution.propIDs.compactMap{carriedObjects.objects[$0]?.persistentID}
        for id in Set(habitatIDs+leafIDs) {companionMetrics.sceneVisits[id.uuidString,default:0]+=1}
    }
    func companionDidFinish(_ execution:BehaviorExecution,source:BehaviorSource) {
        guard settings.companion != nil,execution.kind.isSignificant else {return}
        for id in execution.participants {bird(id)?.episodeRetainsFlightClock=false;companionRecovering.insert(id)}
        // The recovery set is resolved on the next step, after execution.cancel().
        companionScheduler.didSettle()
    }
    private func advanceCompanionEpisodes(_ dt:Double) {
        guard let p=settings.companion else {return}
        companionMetrics.simulatedElapsed+=dt
        var visibleMotion=false,nearPointer=false
        for id in order {
            guard let bird=bird(id) else {continue}
            if bird.continuousFlightAge>0,let previous=companionMotionRevisions[id],previous != bird.motionRevision {companionMetrics.replans+=1}
            companionMotionRevisions[id]=bird.motionRevision
            bird.advanceEpisodeClock(dt)
            companionMetrics.maximumContinuousFlight=max(companionMetrics.maximumContinuousFlight,bird.continuousFlightAge)
            if bird.state != .perched,records[id]?.visible == true,world.displays.contains(where:{$0.intersects(bounds(of:bird))}) {
                visibleMotion=true
                if bounds(of:bird).insetBy(dx:-90,dy:-90).contains(world.pointer) {nearPointer=true}
            }
            companionFlightAges[id]=max(companionFlightAges[id] ?? 0,bird.continuousFlightAge)
            if bird.continuousFlightAge>=90,companionEscapeStarted[id]==nil {
                runtime.cancel(bird:id,reason:.timedOut,in:self)
                bird.ordinaryOrbitLimit=0;sendAway(bird);companionEscapeStarted[id]=time
                companionScheduler.record(time:time,kind:nil,state:.failed,reason:"continuousFlightLimit")
            }
            if let began=companionEscapeStarted[id],time-began>=16 {removeRecord(id);companionEscapeStarted.removeValue(forKey:id)}
        }
        if visibleMotion {companionMetrics.visibleMotionTime+=dt}
        if nearPointer {companionMetrics.pointerNearbyMotionTime+=dt}
        let settled=companionRecovering.filter {id in
            guard let b=bird(id) else {return true}
            return b.state == .perched && b.stateTime>=0.5
        }
        if !settled.isEmpty {companionRecovering.subtract(settled);if companionRecovering.isEmpty {companionScheduler.didSettle()}}
        if let id=companionOrbit {
            if bird(id)==nil || bird(id).map({$0.state == .perched && $0.stateTime>=0.5}) == true {
                companionOrbit=nil;companionScheduler.didSettle()
            }
        }
        companionScheduler.configure(p.policy,flockEnabled:settings.flockPasses && p.allows(.flockPass,source:.automatic))
    }
    private func advanceCompanionOpportunities(_ dt:Double) {
        guard let p=settings.companion,ambientEnabled else {return}
        let due=companionScheduler.advance(dt,pointer:world.pointer,buttonsDown:world.buttonsDown,
            cadence:p.policy.cadence(minute:world.localMinuteOfDay),flockEnabled:settings.flockPasses && p.allows(.flockPass,source:.automatic))
        guard !encounterUnavailable,scheduledEncounter==nil,companionRecovering.isEmpty,companionOrbit==nil,!world.buttonsDown else {
            if due.flock {companionScheduler.record(time:time,kind:.flockPass,state:.deferred,reason:"busy")};return
        }
        if due.flock {attemptCompanion(.flockPass);return}
        guard due.encounter else {return}
        var kinds:[BehaviorKind]=[.pointerVisit,.socialGreeting,.sideBySide,.giveWay,.pairedTakeoff,.chase,.travelTogether,.allopreening,.courtshipDisplay,.leafPlay,.insectCatch,.visitorGift]
        if !fixedPerches.isEmpty {kinds.append(.fixedPerchVisit)}
        let scenes=habitatObjects.objects.values.filter{!$0.retiring && $0.remainingUses>0 || $0.kind == .nest && !$0.retiring && ($0.nest?.materials.contains{[NestMaterialState.available,.delivered].contains($0.state)} ?? false)}.sorted {
            let a=sceneLastVisit["h\($0.id.rawValue)"] ?? -1,b=sceneLastVisit["h\($1.id.rawValue)"] ?? -1
            return a==b ? $0.id<$1.id:a<b
        }
        let leaves=carriedObjects.objects.values.filter {object in
            guard !object.isVisitorGift,object.state == .available else {return false}
            sceneLeafCandidateID=object.id;defer {sceneLeafCandidateID=nil}
            return !LeafCarryPlan.candidates(in:self,source:.automatic).isEmpty
        }.sorted{$0.id<$1.id}
        // One scene slot irrespective of object count; select its oldest eligible instance afterwards.
        let availableScenes=scenes.filter {obj in
            let kind:BehaviorKind=obj.kind == .bath ? .bathVisit:obj.kind == .foodTray ? .foodTrayVisit:obj.nest?.materials.contains{$0.state == .delivered} == true ? .nestBuild:.nestMaterialCarry
            guard BehaviorDefinitions.definition(for:kind).isEnabled(settings:settings,source:.automatic) else {return false}
            sceneCandidateID=obj.id;defer {sceneCandidateID=nil}
            switch kind {
            case .foodTrayVisit:return !FoodTrayVisitPlan.candidates(in:self,source:.automatic).isEmpty
            case .bathVisit:return !BathVisitPlan.candidates(in:self,source:.automatic).isEmpty
            case .nestBuild:return !NestBuildPlan.candidates(in:self,source:.automatic,target:obj.id).isEmpty
            default:return !NestMaterialCarryPlan.candidates(in:self,source:.automatic,target:obj.id).isEmpty
            }
        }
        kinds=kinds.filter {BehaviorDefinitions.definition(for:$0).isEnabled(settings:settings,source:.automatic)}
        if companionScheduler.pointerStill<p.policy.pointerQuiet {kinds.removeAll{$0 == .pointerVisit}}
        let hasScene = !availableScenes.isEmpty || (!leaves.isEmpty && p.allows(.leafCarry,source:.automatic))
        let canOrbit=p.mode != .focus && p.allows(.pointerVisit,source:.automatic) && settings.pointerVisits && birds.contains{$0.state == .perched && FlightBehavior.motion($0.profile.id).orbit>0 && id(of:$0).map{runtime.owners[$0]==nil} == true}
        let count=kinds.count+(hasScene ? 1:0)+(canOrbit ? 1:0)
        guard count>0 else {return}
        let weights=kinds.map{p.policy.weight(for:$0)}+(hasScene ? [p.policy.weight(for:.bathVisit)]:[])+(canOrbit ? [p.policy.weight(for:.pointerVisit)]:[])
        var ticket=companionRandom.unit()*weights.reduce(0,+),choice=weights.count-1
        for index in weights.indices {ticket-=weights[index];if ticket<0 {choice=index;break}}
        if choice<kinds.count {attemptCompanion(kinds[choice]);return}
        if hasScene,choice==kinds.count {
            let oldestLeaf=leaves.filter{_ in p.allows(.leafCarry,source:.automatic)}.min {
                let a=sceneLastVisit["l\($0.id.rawValue)"] ?? -1,b=sceneLastVisit["l\($1.id.rawValue)"] ?? -1
                return a==b ? $0.id<$1.id:a<b
            }
            let leafFirst=oldestLeaf.map {leaf in availableScenes.first.map{(sceneLastVisit["l\(leaf.id.rawValue)"] ?? -1)<(sceneLastVisit["h\($0.id.rawValue)"] ?? -1)} ?? true} ?? false
            if !leafFirst,let object=availableScenes.first {
                sceneCandidateID=object.id
                let kind:BehaviorKind=object.kind == .bath ? .bathVisit:object.kind == .foodTray ? .foodTrayVisit:object.nest?.materials.contains{$0.state == .delivered} == true ? .nestBuild:.nestMaterialCarry
                attemptCompanion(kind);sceneLastVisit["h\(object.id.rawValue)"]=time;sceneCandidateID=nil
            } else if let leaf=oldestLeaf {
                sceneLeafCandidateID=leaf.id;attemptCompanion(.leafCarry);sceneLastVisit["l\(leaf.id.rawValue)"]=time;sceneLeafCandidateID=nil
            }
        } else if canOrbit,let bird=birds.first(where:{$0.state == .perched && FlightBehavior.motion($0.profile.id).orbit>0 && id(of:$0).map{runtime.owners[$0]==nil} == true}),let id=id(of:bird) {
            bird.ordinaryOrbitLimit=p.policy.orbitDuration
            if route(bird) {companionOrbit=id;companionScheduler.record(time:time,kind:nil,state:.started,reason:"decorativeOrbit")}
            bird.ordinaryOrbitLimit=0
        }
    }
    private func attemptCompanion(_ kind:BehaviorKind) {
        companionScheduler.permit=kind
        companionScheduler.record(time:time,kind:kind,state:.candidate,reason:"opportunityDue")
        let result:BehaviorResult
        switch kind {
        case .flockPass:result=requestFlock(.automatic)
        case .pointerVisit:result=requestPointer(.automatic)
        case .socialGreeting:result=requestSocialGreeting(.automatic)
        case .sideBySide:result=requestSocialMotion(.sideBySide,source:.automatic)
        case .giveWay:result=requestSocialMotion(.giveWay,source:.automatic)
        case .pairedTakeoff:result=requestSocialMotion(.pairedTakeoff,source:.automatic)
        case .chase:result=requestChase(source:.automatic)
        case .travelTogether:result=requestTravelTogether(source:.automatic)
        case .allopreening:result=requestAllopreening(source:.automatic)
        case .courtshipDisplay:result=requestCourtship(source:.automatic)
        case .foodTrayVisit:result=requestFoodTrayVisit(source:.automatic)
        case .fixedPerchVisit:result=requestFixedPerchVisit(source:.automatic)
        case .bathVisit:result=requestBathVisit(source:.automatic)
        case .leafCarry:result=requestLeafCarry(source:.automatic)
        case .nestMaterialCarry,.nestBuild:result=requestNest(kind:kind,source:.automatic)
        case .visitorGift:result=requestVisitorGift(source:.automatic)
        case .insectCatch:requestAutomaticInsectCatch();result = .accepted
        case .leafPlay:requestAutomaticLeaf();result = .accepted
        default:result = .rejected(.disabled)
        }
        if case .rejected(let reason)=result {companionScheduler.record(time:time,kind:kind,state:.suppressed,reason:reason.rawValue)}
        if !(kind == .visitorGift && pendingGift != nil) {companionScheduler.permit=nil}
    }
    private func companionFlockPlans(screen:CGRect,profile:SpeciesProfile,scale:CGFloat)->[FlockMemberPlan] {
        guard let p=settings.companion,screen.width>200,screen.height>200 else {return []}
        let speed=FlightBehavior.cruiseSpeed(profile.id,multiplier:profile.speed)
        let desired=companionRandom.value(in:p.policy.flockDuration)
        let sampledCount=3+Int(companionRandom.unit()*3)
        let count=Double(screen.width)/speed<4 ? 5:sampledCount
        let margin=max(80,80*scale),right=companionRandom.unit()<0.5
        let phases=(0..<count).map{_ in companionRandom.unit()*3}
        var spacing=0.25
        func plans(_ extent:Double)->[FlockMemberPlan] {
            (0..<count).map {index in
                let y=screen.minY+margin+CGFloat(index%3)*12*scale
                let start=CGPoint(x:right ? screen.minX-margin:screen.maxX+margin,y:y)
                let end=CGPoint(x:start.x+(right ? extent:-extent),y:screen.minY-margin)
                let path=FlightPath(start,CGPoint(x:start.x+(end.x-start.x)*0.3,y:y),CGPoint(x:end.x,y:y),end)
                return FlockMemberPlan(delay:Double(index)*spacing,path:path,speed:speed,wingPhase:phases[index])
            }
        }
        // Measure the complete visible group at the real cruise speed. Offscreen
        // approach and exit must not count toward the mode's presentation target.
        func visibleDuration(_ values:[FlockMemberPlan])->Double {
            var first=Double.infinity,last=0.0
            for value in values {
                for sample in 0...256 {
                    let progress=Double(sample)/256,point=value.path.point(progress)
                    let rect=CGRect(x:point.x-(right ? 29:19)*scale,y:point.y-39*scale,width:48*scale,height:48*scale)
                    if screen.intersects(rect) {
                        let time=value.delay+progress*value.path.length/speed
                        first=min(first,time);last=max(last,time)
                    }
                }
            }
            return first.isFinite ? last-first:0
        }
        var low=Double(margin),high=Double(screen.width+margin*0.7)
        let baseMaximum=visibleDuration(plans(high))
        if baseMaximum<desired {
            // Longer formations on a small display keep cruise speed unchanged.
            // Bound spacing below each member's visible span to avoid empty gaps.
            spacing=0
            let span=visibleDuration(plans(high))
            spacing=max(0.25,min(span*0.8,(desired-span)/Double(count-1)))
        }
        let maximum=visibleDuration(plans(high)),minimum=visibleDuration(plans(low))
        guard maximum>=p.policy.flockDuration.lowerBound,minimum<=p.policy.flockDuration.upperBound else {return []}
        let target=min(maximum-0.05,max(minimum,desired))
        for _ in 0..<20 {
            let mid=(low+high)/2
            if visibleDuration(plans(mid))<target {low=mid}else{high=mid}
        }
        return plans((low+high)/2)
    }
}

// Scene transactions stay on the simulation executor. The tiny atomic ledger
// write acknowledges a transition before an executor can report its success.
extension BehaviorEngine {
    public func restoreScene(_ archive:SceneArchive) throws {
        try archive.validate()
        var input=RecordedInput(kind:"sceneRestore");input.sceneArchive=archive
        beginRecordingInput(input);defer {endRecordingInput()}
        sceneArchive=archive;sceneEnabled=true
        sceneNeedsPlacement=Set(archive.layout.instances.filter{$0.requiresWindowPlacement}.map(\.id))
        for id in archive.resources.keys.sorted(by:{$0.uuidString<$1.uuidString}) {
            guard let resource=archive.resources[id],resource.recovered != resource else {continue}
            guard commitSceneResource(id,resource.recovered) else {throw SceneError.invalid(sceneError ?? "无法恢复资源账本")}
        }
        habitatObjects.commitResource={ [weak self] id,value in self?.commitSceneResource(id,value) ?? false }
        carriedObjects.commitResource={ [weak self] id,value in self?.commitSceneResource(id,value) ?? false }
        restoreMissingSceneObjects()
    }
    private func persistScene(_ value:SceneArchive)->Bool {
        do {
            try value.validate();try sceneWriter?(value)
            inputRecorder?.sceneWrite(SceneWriteDecision(archive:value,accepted:true))
            sceneArchive=value;sceneError=nil;return true
        } catch {
            inputRecorder?.sceneWrite(SceneWriteDecision(archive:value,accepted:false))
            sceneError=error.localizedDescription;return false
        }
    }
    private func commitSceneResource(_ id:UUID,_ value:SceneResource)->Bool {
        guard let old=sceneArchive.resources[id] else {return false}
        var resource=value;resource.revision=old.revision
        if resource==old {return true}
        // There is no refund API here. Replenishment is an explicit editor operation.
        guard resource.remainingUses<=old.remainingUses,!old.leafConsumed || resource.leafConsumed,
              old.materials.count==resource.materials.count,
              (resource.leafEffect?.remaining ?? 0)<=(old.leafEffect?.remaining ?? 120),
              zip(old.materials,resource.materials).allSatisfy({a,b in
                  a==b || (a == .available && b == .attached) || (a == .attached && [.delivered,.spent].contains(b)) || (a == .delivered && b == .arranged)
              }) else {return false}
        guard resource.revision<UInt64.max-1 else {return false}
        resource.revision+=1
        var archive=sceneArchive;archive.resources[id]=resource;archive.ledgerRevision+=1
        return persistScene(archive)
    }
    /// Preview the selected committed instance through the normal executor and gates.
    @discardableResult public func previewSceneInstance(_ id:UUID)->BehaviorResult {
        var input=RecordedInput(kind:"scenePreview");input.sceneInstance=id
        beginRecordingInput(input);defer {endRecordingInput()}
        guard !sceneEditing else {return .rejected(.busy)}
        guard !paused else {return .rejected(.paused)}
        guard let item=sceneArchive.layout.instances.first(where:{$0.id==id}),
              item.point(in:world) != nil,!sceneNeedsPlacement.contains(id) else {return .rejected(.noSpace)}
        defer {sceneCandidateID=nil;sceneLeafCandidateID=nil;scenePerchCandidateSlot=nil}
        switch item.kind {
        case .perch:
            scenePerchCandidateSlot=item.anchor.slot
            return requestFixedPerchVisit(source:.preview)
        case .leaf:
            guard let prop=carriedObjects.objects.values.first(where:{$0.persistentID==id}) else {return .rejected(.noSpace)}
            sceneLeafCandidateID=prop.id
            return requestLeafCarry(source:.preview)
        case .foodTray,.bath,.nest:
            guard let object=habitatObjects.objects.values.first(where:{$0.persistentID==id}) else {return .rejected(.noSpace)}
            sceneCandidateID=object.id
            if item.kind == .foodTray {return requestFoodTrayVisit(source:.preview)}
            if item.kind == .bath {return requestBathVisit(source:.preview)}
            return requestNest(kind:sceneArchive.resources[id]?.materials.contains(.delivered) == true ? .nestBuild:.nestMaterialCarry,source:.preview)
        }
    }
    public func beginSceneEditing()->SceneDraft {
        if !sceneEnabled {
            sceneArchive.layout = .migrate(anchors:settings.fixedPerches)
            for item in sceneArchive.layout.instances {sceneArchive.resources[item.id]=SceneResource(kind:item.kind)}
            sceneEnabled=true
            habitatObjects.commitResource={ [weak self] id,value in self?.commitSceneResource(id,value) ?? false }
            carriedObjects.commitResource={ [weak self] id,value in self?.commitSceneResource(id,value) ?? false }
        }
        beginRecordingInput(RecordedInput(kind:"sceneBegin"));defer {endRecordingInput()}
        sceneEditPhase = .editing;sceneError=nil;companionScheduler.discardPending()
        return SceneDraft(sceneArchive.layout)
    }
    public func cancelSceneEditing() {
        guard sceneEditing else {return}
        beginRecordingInput(RecordedInput(kind:"sceneCancel"));defer {endRecordingInput()}
        sceneEditPhase = .cancelled;sceneProposed=nil;sceneAffected=[];sceneRecovery=[]
        sceneExcludedSurfaces=[];companionScheduler.didSettle()
        if let latest=sceneLastWorld {sceneLastWorld=nil;updateWorld(latest)}
    }
    public func scenePlacementError(_ layout:SceneLayout)->String? {
        do {_=try sceneProjection(layout);return nil} catch {return error.localizedDescription}
    }
    public func applySceneLayout(_ layout:SceneLayout,baseRevision:UInt64)->Bool {
        var input=RecordedInput(kind:"sceneApply");input.sceneLayout=layout;input.sceneBaseRevision=baseRevision
        beginRecordingInput(input);defer {endRecordingInput()}
        if let latest=sceneLastWorld,latest.surfaces.filter({!$0.isHabitat && !$0.isFixedPerch}) != world.surfaces.filter({!$0.isHabitat && !$0.isFixedPerch}) {
            sceneError="窗口位置已变化，请取消后重新打开布置桌面。";return false
        }
        guard sceneEditing,sceneEditPhase != .applying,baseRevision==sceneArchive.layout.revision else {
            sceneError="布局已变化，请重新打开编辑器。";return false
        }
        do {
            try layout.validate()
            let previous=Dictionary(uniqueKeysWithValues:sceneArchive.layout.instances.map{($0.id,$0)})
            let proposed=Dictionary(uniqueKeysWithValues:layout.instances.map{($0.id,$0)})
            guard !previous.contains(where:{id,item in proposed[id].map{$0.kind != item.kind} ?? false}) else {throw SceneError.invalid("已有物件不能更改类型，请收回后重新放置。")}
            sceneAffected=Set(previous.keys).union(proposed.keys).filter{previous[$0] != proposed[$0]}
            sceneExcludedSurfaces=Set(habitatObjects.objects.values.filter{$0.persistentID.map{sceneAffected.contains($0)} ?? false}.map{$0.surface.id})
            for item in sceneArchive.layout.instances where item.kind == .perch && sceneAffected.contains(item.id) {
                sceneExcludedSurfaces.insert(0xFF000000+UInt32(item.anchor.slot))
            }
            let props=Set(carriedObjects.objects.values.filter{$0.persistentID.map{sceneAffected.contains($0)} ?? false}.map(\.id))
            let habitats=Set(habitatObjects.objects.values.filter{$0.persistentID.map{sceneAffected.contains($0)} ?? false}.map(\.id))
            let runs=runtime.runs.values.filter {run in
                !Set(run.execution.habitatReservations).isDisjoint(with:habitats) || !Set(run.execution.propIDs).isDisjoint(with:props) ||
                run.execution.landingReservations.contains{sceneExcludedSurfaces.contains($0.hostID)} ||
                run.execution.giftReceiverReservations.contains{reservation in
                    sceneArchive.layout.instances.contains{$0.kind == .perch && sceneAffected.contains($0.id) && $0.anchor.slot==reservation.slot}
                }
            }.map(\.id).sorted()
            sceneRecovery=Set(runs.flatMap{runtime.runs[$0]?.execution.participants ?? []})
            sceneRecovery.formUnion(birds.filter{$0.hostID.map{sceneExcludedSurfaces.contains($0)} == true}.compactMap{id(of:$0)})
            if paused && !sceneRecovery.isEmpty {throw SceneError.invalid("物件正在使用中，请先继续动画，再应用布局。草稿已保留。")}
            _=try sceneProjection(layout)
            sceneProposed=layout;sceneEditPhase = .applying;sceneRecoveryAge=0
            if let slot=pendingGift?.request.binding.receiverSlot,
               sceneArchive.layout.instances.contains(where:{$0.kind == .perch && sceneAffected.contains($0.id) && $0.anchor.slot==slot}) {
                cancelGiftRequest(.settingsChanged)
            }
            for id in runs {runtime.cancel(id,reason:.settingsChanged,in:self)}
            for id in sceneRecovery.sorted() {
                guard let bird=bird(id) else {continue}
                bird.requestFlightRecovery();recoveringHabitatBirds.insert(id);resumeHabitatRecovery(id)
            }
            if sceneRecovery.isEmpty {finishSceneApply()}
            return sceneEditPhase == .applying || sceneEditPhase == .committed
        } catch {sceneError=error.localizedDescription;sceneEditPhase = .failed;sceneExcludedSurfaces=[];return false}
    }
    private struct SceneProjection {
        var habitats:[HabitatObjectID:HabitatObject]
        var leaves:[ScenePropID:CarriedObject]
        var nextHabitat:UInt64
        var nextProp:UInt64
        var anchors:[FixedPerchAnchor]
    }
    private func sceneProjection(_ layout:SceneLayout,restoring:Bool=false) throws -> SceneProjection {
        try layout.validate()
        let sandbox=BehaviorEngine(seed:seed,settings:settings)
        sandbox.settings.companion=sandbox.settings.companion ?? CompanionPreferences()
        sandbox.settings.fixedPerches=layout.instances.filter{$0.kind == .perch && $0.point(in:world) != nil}.map(\.anchor)
        var sceneWorld=world;sceneWorld.buttonsDown=false
        sceneWorld.surfaces.removeAll{$0.isHabitat || $0.isFixedPerch}
        sandbox.updateWorld(sceneWorld)
        sandbox.habitatObjects.nextID=habitatObjects.nextID
        var prop=nextPropID
        // Preserve the actual runtime identity of every unchanged object.
        let old=Dictionary(uniqueKeysWithValues:sceneArchive.layout.instances.map{($0.id,$0)})
        for item in layout.instances.filter({$0.kind != .perch}).sorted(by:{$0.id.uuidString<$1.id.uuidString}) {
            guard let point=item.point(in:world),!sceneNeedsPlacement.contains(item.id) || item != old[item.id] else {continue} // parked until explicitly repositioned
            if item==old[item.id],let object=habitatObjects.objects.values.first(where:{$0.persistentID==item.id && !$0.retiring}) {
                sandbox.habitatObjects.objects[object.id]=object;sandbox.world.surfaces.append(object.surface);continue
            }
            if item==old[item.id],let object=carriedObjects.objects.values.first(where:{$0.persistentID==item.id}) {
                sandbox.carriedObjects.objects[object.id]=object;continue
            }
            let resource=(sceneArchive.resources[item.id] ?? SceneResource(kind:item.kind)).recovered
            if item.kind == .leaf && resource.leafConsumed {
                if let effect=resource.leafEffect,effect.remaining>0,effect.support == .ground {
                    let id=ScenePropID(prop);prop+=1
                    _=sandbox.carriedObjects.restoreEffect(id:id,instance:item.id,effect:effect,in:sandbox)
                }
                continue
            }
            let before=Set(sandbox.habitatObjects.objects.keys)
            let result:BehaviorResult
            switch item.kind {
            case .foodTray:result=sandbox.habitatObjects.placeFood(at:point,in:sandbox) ? .accepted:.rejected(.noSpace)
            case .bath:result=sandbox.habitatObjects.placeBath(at:point,in:sandbox)
            case .nest:
                let ids=(0..<3).map{ScenePropID(prop+UInt64($0))};prop+=3
                result=sandbox.habitatObjects.placeNest(at:point,materialIDs:ids,in:sandbox)
            case .leaf:
                let id=ScenePropID(prop);prop+=1
                result=sandbox.carriedObjects.placeLeaf(id:id,at:point,in:sandbox)
                if result.accepted {sandbox.carriedObjects.makePersistent(id,instance:item.id)}
            case .perch:continue
            }
            if !result.accepted {
                if restoring {continue}
                throw SceneError.invalid("\(item.kind.rawValue)：位置被遮挡、空间不足或对应行为尚未开启。叶片与巢台请靠近窗口顶部或地面边缘。")
            }
            if let id=Set(sandbox.habitatObjects.objects.keys).subtracting(before).first,var object=sandbox.habitatObjects.objects[id] {
                object.persistentID=item.id;object.remainingLifetime=1e12;object.remainingUses=resource.remainingUses
                if var nest=object.nest {
                    for i in nest.materials.indices {nest.materials[i].state=resource.materials[i]}
                    object.nest=nest;object.remainingUses=nest.available
                }
                sandbox.habitatObjects.objects[id]=object;sandbox.world.surfaces.append(object.surface)
            }
        }
        let rectangles=sandbox.habitatObjects.objects.values.map{$0.rect.union($0.nest?.trayRect ?? $0.rect)} +
            sandbox.carriedObjects.snapshot(in:sandbox).map(\.rect)+sandbox.fixedPerchSnapshot().map(\.rect)
        if !restoring {
            for i in rectangles.indices {
                if rectangles.indices.contains(where:{$0 != i && rectangles[$0].insetBy(dx:-8,dy:-8).intersects(rectangles[i])}) {
                    throw SceneError.invalid("物件间需要留出安全间距。")
                }
                let unchanged=habitatObjects.objects.values.contains{object in object.rect.union(object.nest?.trayRect ?? object.rect)==rectangles[i] && object.persistentID.flatMap{old[$0]} .map{layout.instances.contains($0)} == true} ||
                    fixedPerches.contains{perch in perch.rect==rectangles[i] && layout.instances.contains{old[$0.id]==$0 && $0.kind == .perch && $0.anchor.slot==perch.slot}}
                if !unchanged && birds.contains(where:{id(of:$0).map{!sceneRecovery.contains($0)} == true && bounds(of:$0).intersects(rectangles[i])}) {
                    throw SceneError.invalid("此位置有小鸟，请选择空位或等待它离开。")
                }
            }
            if sandbox.fixedPerchSnapshot().count != sandbox.settings.fixedPerches.count {throw SceneError.invalid("栖木间距或屏幕可用空间不足。")}
        }
        return SceneProjection(habitats:sandbox.habitatObjects.objects,leaves:sandbox.carriedObjects.objects,
            nextHabitat:sandbox.habitatObjects.nextID,nextProp:prop,anchors:layout.instances.filter{$0.kind == .perch}.map(\.anchor))
    }
    private func installSceneProjection(_ projection:SceneProjection) {
        let transientHabitat=habitatObjects.objects.filter{$0.value.persistentID==nil}
        let transientLeaves=carriedObjects.objects.filter{$0.value.persistentID==nil || ($0.value.state != .available && $0.value.state != .retired)}
        habitatObjects.objects=projection.habitats.merging(transientHabitat,uniquingKeysWith:{a,_ in a})
        carriedObjects.objects=projection.leaves.merging(transientLeaves,uniquingKeysWith:{a,_ in a})
        habitatObjects.nextID=max(habitatObjects.nextID,projection.nextHabitat);nextPropID=max(nextPropID,projection.nextProp)
        settings.fixedPerches=projection.anchors
        refreshFixedPerches(previous:world.surfaces.filter(\.isFixedPerch));refreshHabitatObjects()
    }
    private func finishSceneApply() {
        guard var proposed=sceneProposed else {return}
        do {
            let projection=try sceneProjection(proposed)
            var archive=sceneArchive;proposed.revision=archive.layout.revision+1;archive.layout=proposed
            archive.resources=archive.resources.filter {id,_ in proposed.instances.contains{$0.id==id}}
            for item in proposed.instances where archive.resources[item.id]==nil {archive.resources[item.id]=SceneResource(kind:item.kind)}
            guard persistScene(archive) else {sceneEditPhase = .failed;return}
            sceneNeedsPlacement.subtract(sceneAffected)
            installSceneProjection(projection);sceneEditPhase = .committed;sceneProposed=nil
            sceneRecovery=[];sceneAffected=[];sceneExcludedSurfaces=[];companionScheduler.didSettle()
            if let latest=sceneLastWorld {sceneLastWorld=nil;updateWorld(latest)}
        } catch {sceneError=error.localizedDescription;sceneEditPhase = .failed}
    }
    private func advanceSceneEditing(_ dt:Double) {
        guard sceneEditPhase == .applying,!paused else {return}
        if let latest=sceneLastWorld,latest.surfaces.filter({!$0.isHabitat && !$0.isFixedPerch}) != world.surfaces.filter({!$0.isHabitat && !$0.isFixedPerch}) {
            sceneError="恢复期间窗口位置变化，布局未提交。请取消后重试。";sceneEditPhase = .failed;return
        }
        sceneRecoveryAge+=dt
        for id in sceneRecovery.sorted() {
            guard let bird=bird(id) else {continue}
            bird.tick(dt)
            if bird.departureFinished && !world.displays.contains(where:{$0.intersects(bounds(of:bird))}) {removeRecord(id)}
        }
        sceneRecovery=sceneRecovery.filter {id in
            guard let bird=bird(id) else {return false}
            return bird.state != .perched || bird.stateTime<0.5 || bird.hostID.map{sceneExcludedSurfaces.contains($0)} == true
        }
        if sceneRecovery.isEmpty {finishSceneApply()}
        else if sceneRecoveryAge>=20 {
            sceneError="小鸟尚未安全离开，布局没有改变。请取消编辑，让动画继续后重试。";sceneEditPhase = .failed
        }
    }
    private func restoreMissingSceneObjects() {
        guard sceneEnabled,!sceneEditing,!world.displays.isEmpty else {return}
        let missing=sceneArchive.layout.instances.contains {item in
            guard item.point(in:world) != nil,!sceneNeedsPlacement.contains(item.id) else {return false}
            if item.kind == .perch {return settings.fixedPerches != sceneArchive.layout.instances.filter{$0.kind == .perch}.map(\.anchor)}
            if item.kind == .leaf {
                let r=sceneArchive.resources[item.id]
                let remaining=r?.leafEffect.map{$0.support == .ground && $0.remaining>0} ?? false
                return (r?.leafConsumed != true || remaining) && !carriedObjects.objects.values.contains{$0.persistentID==item.id}
            }
            return !habitatObjects.objects.values.contains{$0.persistentID==item.id}
        }
        guard missing else {return}
        if let projection=try? sceneProjection(sceneArchive.layout,restoring:true) {installSceneProjection(projection)}
    }
    public func replenishSceneInstance(_ id:UUID)->Bool {
        guard sceneEditPhase != .applying,let item=sceneArchive.layout.instances.first(where:{$0.id==id}),item.kind != .perch,
              !habitatObjects.objects.values.contains(where:{$0.persistentID==id && runtime.habitatReservations.contains($0.id)}),
              !carriedObjects.objects.values.contains(where:{$0.persistentID==id && $0.reservedByRun != nil}),
              !habitatObjects.objects.values.contains(where:{object in object.persistentID==id && birds.contains{$0.hostID==object.surface.id}}) else {return false}
        var input=RecordedInput(kind:"sceneReplenish");input.sceneInstance=id
        beginRecordingInput(input);defer {endRecordingInput()}
        var archive=sceneArchive;var resource=SceneResource(kind:item.kind)
        resource.revision=(archive.resources[id]?.revision ?? 0)+1;archive.resources[id]=resource;archive.ledgerRevision+=1
        guard persistScene(archive) else {return false}
        habitatObjects.objects=habitatObjects.objects.filter{$0.value.persistentID != id}
        carriedObjects.objects=carriedObjects.objects.filter{$0.value.persistentID != id}
        // The editor displays refreshed inventory immediately; geometry is restored on exit.
        return true
    }
}
