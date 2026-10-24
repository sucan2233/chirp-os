/// Capabilities describe complete groups of existing renderer frames.
public enum BirdCapability:String,CaseIterable,Codable {
    case standing, blinking, preening, greeting, flight, landing, allopreening, feeding
    case observationPose, alertPose, restPose, takeoffPose, edgePeekPose, bathing, carryingLeaf, insectCatching

    public var requiredFrames:Set<String> {
        switch self {
        case .observationPose:return ["lookNear","lookFar"]
        case .alertPose:return ["alertRise","alertHold","alertRelax"]
        case .restPose:return ["restLower","restTuck","restWake"]
        case .takeoffPose:return ["takeoffCrouch","takeoffPush"]
        case .edgePeekPose:return ["peekLower","peekLook","peekRecover"]
        case .standing:return ["stand"]
        case .blinking:return ["blink"]
        case .preening:return ["preen0","preen1"]
        case .greeting:return ["idle0","idle1","idle2"]
        case .flight:return ["fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7"]
        case .landing:return ["land0","land1","land2"]
        case .insectCatching:return Set(SpeciesBehaviorProfile.catchFrameNames)
        case .carryingLeaf:return Set(SpeciesBehaviorProfile.carryFrameNames)
        case .bathing:return Set(SpeciesBehaviorProfile.bathFrameNames).union(["shake"])
        case .feeding:return ["feedLook","feedDown0","feedDown1","feedLift"]
        case .allopreening:return ["allopreenGive0","allopreenGive1","allopreenGive2","allopreenReceive0","allopreenReceive1","allopreenReceive2"]
        }
    }
}

/// Immutable content and scheduling policy for one existing behavior.
/// Geometry, ownership and cooldown clocks remain the runtime's responsibility.
public struct BehaviorDefinition {
    public let kind:BehaviorKind
    public let requiredCapabilities:Set<BirdCapability>
    public let occupiesEncounter:Bool
    public let runsWhilePaused:Bool
    /// Scheduling rank alone never grants permission to interrupt another run.
    public let priority:Int
    /// Seconds of recovery after a run finishes, matching PerchActivityPlanner.
    public let cooldown:Double

    fileprivate init(kind:BehaviorKind,requiredCapabilities:Set<BirdCapability>,
                     occupiesEncounter:Bool,runsWhilePaused:Bool,priority:Int,cooldown:Double) {
        self.kind=kind;self.requiredCapabilities=requiredCapabilities
        self.occupiesEncounter=occupiesEncounter;self.runsWhilePaused=runsWhilePaused
        self.priority=priority;self.cooldown=cooldown
    }

    public var requiredFrames:Set<String> {
        requiredCapabilities.reduce(into:Set<String>()) {$0.formUnion($1.requiredFrames)}
    }

    /// Settings eligibility only; pause state and automatic scheduling eligibility
    /// (including ambientEnabled) are evaluated by the engine separately.
    public func isEnabled(settings:BirdSettings,source:BehaviorSource) -> Bool {
        if source == .automatic,settings.activityRhythm == .quiet,occupiesEncounter {return false}
        switch kind {
        case .relocate:return true
        case .visitorGift:return settings.visitorGiftsEnabled && settings.visitorMemoryEnabled && settings.fixedPerchesEnabled
        case .insectCatch:return settings.insectCatchEnabled
        case .leafCarry:return settings.leafCarryEnabled
        case .bathVisit:return settings.bathEnabled && (source != .automatic || settings.activityRhythm != .quiet)
        case .foodTrayVisit:return settings.foodTrayEnabled && (source != .automatic || settings.activityRhythm != .quiet)
        case .fixedPerchVisit:return settings.fixedPerchesEnabled && (source != .automatic || settings.activityRhythm != .quiet)
        case .pointerVisit:return settings.pointerVisits
        case .flockPass:return settings.flockPasses
        case .rest,.preen:return settings.perchActions
        case .watch,.alert:return settings.perchActions && settings.passiveAttentionEnabled
        case .sideHop:return settings.perchActions && settings.sideHopEnabled
        case .takeoffPreparation:return settings.perchActions && settings.takeoffPreparationEnabled
        case .edgePeek:return settings.perchActions && settings.edgePeekEnabled
        case .allopreening:return settings.socialInteractions && settings.allopreeningEnabled
        case .travelTogether:return settings.socialInteractions && settings.travelTogetherEnabled
        case .chase:return settings.socialInteractions && settings.chaseEnabled
        case .socialGreeting,.sideBySide,.giveWay,.pairedTakeoff:return settings.socialInteractions
        case .leafPlay:return settings.leafPlayEnabled && (source != .automatic || settings.ambientLeafPlayEnabled)
        }
    }

    public func missingFrames(in availableFrames:Set<String>) -> Set<String> {
        requiredFrames.subtracting(availableFrames)
    }
}

public enum BehaviorDefinitions {
    public static func definition(for kind:BehaviorKind) -> BehaviorDefinition {
        switch kind {
        // Core movement predates manifests. Legacy adapters provide sprite
        // fallback, so these actions must work even with no frame manifest.
        case .relocate:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[],occupiesEncounter:false,
                runsWhilePaused:true,priority:100,cooldown:0)
        case .pointerVisit,.flockPass:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[],occupiesEncounter:true,
                runsWhilePaused:false,priority:60,cooldown:0)
        case .rest:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.blinking],occupiesEncounter:false,
                runsWhilePaused:false,priority:10,cooldown:6)
        case .preen:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.preening],occupiesEncounter:false,
                runsWhilePaused:false,priority:10,cooldown:6)
        case .socialGreeting:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.blinking,.greeting],occupiesEncounter:true,
                runsWhilePaused:false,priority:60,cooldown:20)
        case .sideBySide,.giveWay,.pairedTakeoff:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.blinking,.flight,.landing],occupiesEncounter:true,
                runsWhilePaused:false,priority:60,cooldown:20)
        case .insectCatch:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.flight,.landing,.insectCatching],occupiesEncounter:true,
                runsWhilePaused:false,priority:60,cooldown:180)
        case .visitorGift:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.flight,.landing,.carryingLeaf],occupiesEncounter:true,
                runsWhilePaused:false,priority:60,cooldown:0)
        case .leafCarry:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.flight,.landing,.carryingLeaf],occupiesEncounter:true,
                runsWhilePaused:false,priority:60,cooldown:45)
        case .bathVisit:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.flight,.landing,.bathing],occupiesEncounter:true,
                runsWhilePaused:false,priority:30,cooldown:45)
        case .foodTrayVisit:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.flight,.landing,.feeding],occupiesEncounter:false,
                runsWhilePaused:false,priority:30,cooldown:75)
        case .fixedPerchVisit:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.flight,.landing],occupiesEncounter:false,
                runsWhilePaused:false,priority:30,cooldown:60)
        case .allopreening:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.landing,.allopreening],occupiesEncounter:true,
                runsWhilePaused:false,priority:60,cooldown:90)
        case .chase,.travelTogether:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.flight,.landing],occupiesEncounter:true,
                runsWhilePaused:false,priority:60,cooldown:60)
        case .leafPlay:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.flight,.landing],occupiesEncounter:true,
                runsWhilePaused:false,priority:60,cooldown:90)
        case .watch:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.blinking],occupiesEncounter:false,
                runsWhilePaused:false,priority:20,cooldown:8)
        case .sideHop:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.landing],occupiesEncounter:false,
                runsWhilePaused:false,priority:30,cooldown:24)
        case .edgePeek:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.greeting,.landing],occupiesEncounter:false,
                runsWhilePaused:false,priority:15,cooldown:45)
        case .takeoffPreparation:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing,.flight],occupiesEncounter:false,
                runsWhilePaused:false,priority:30,cooldown:4)
        case .alert:
            return BehaviorDefinition(kind:kind,requiredCapabilities:[.standing],occupiesEncounter:false,
                runsWhilePaused:false,priority:40,cooldown:12)
        }
    }

    /// Stable content order, independent of dictionary or Set iteration.
    public static var all:[BehaviorDefinition] {
        let kinds:[BehaviorKind] = [.relocate,.pointerVisit,.flockPass,.rest,.preen,.socialGreeting,
            .sideBySide,.giveWay,.pairedTakeoff,.leafPlay,.watch,.alert,.sideHop,.takeoffPreparation,.edgePeek,.chase,.travelTogether,.allopreening,.fixedPerchVisit,.foodTrayVisit,.bathVisit,.leafCarry,.insectCatch,.visitorGift]
        return kinds.map {definition(for:$0)}
    }

    public static func canPreempt(incoming:BehaviorKind,source:BehaviorSource,
                                  current:BehaviorKind,currentSource:BehaviorSource) -> Bool {
        switch incoming {
        case .relocate:return source == .user && current != .relocate
        case .alert:
            guard source == .automatic,currentSource == .automatic else {return false}
            switch current {
            case .rest,.preen,.watch:return true
            case .relocate,.pointerVisit,.flockPass,.socialGreeting,.sideBySide,.giveWay,
                 .pairedTakeoff,.leafPlay,.alert,.sideHop,.takeoffPreparation,.edgePeek,.chase,.travelTogether,.allopreening,.fixedPerchVisit,.foodTrayVisit,.bathVisit,.leafCarry,.insectCatch,.visitorGift:return false
            }
        case .pointerVisit,.flockPass,.rest,.preen,.socialGreeting,.sideBySide,.giveWay,
             .pairedTakeoff,.leafPlay,.watch,.sideHop,.takeoffPreparation,.edgePeek,.chase,.travelTogether,.allopreening,.fixedPerchVisit,.foodTrayVisit,.bathVisit,.leafCarry,.insectCatch,.visitorGift:return false
        }
    }
}
