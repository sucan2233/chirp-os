import Foundation
import CoreGraphics

public enum CompanionMode:String,Codable,CaseIterable {case focus,natural,lively}
public enum BehaviorCategory:String,Codable,CaseIterable {case flight,perch,social,scene}
public enum DurationStyle:String,Codable,CaseIterable {case short,balanced,full}
public struct BehaviorCategoryOverride:Codable,Equatable {
    public var enabled:Bool=true
    public var frequency:AmbientFrequency?
    public var duration:DurationStyle?
    public init() {}
}

/// Preferences are intent; all entry points use the same resolved policy.
public struct CompanionPreferences:Codable,Equatable {
    public var mode:CompanionMode = .natural
    public var followLocalDayNight=false
    public var manualAdjustmentEnabled=false
    public var categoryOverrides:[BehaviorCategory:BehaviorCategoryOverride]=[:]
    public var behaviorDisables:Set<BehaviorKind>=[]
    public var automaticRestrictions:Set<BehaviorKind>=[]
    public var legacyCadence:AmbientFrequency?
    public let migrationVersion:Int
    public init(mode:CompanionMode = .natural) {self.mode=mode;migrationVersion=1}
    public mutating func restoreModeDefaults() {
        categoryOverrides=[:];behaviorDisables=[];automaticRestrictions=[]
        legacyCadence=nil;manualAdjustmentEnabled=false
    }
    public static func migrate(_ settings:BirdSettings)->Self {
        var p=Self(mode:settings.activityRhythm == .quiet ? .focus:.lively)
        p.followLocalDayNight=settings.activityRhythm == .localDayNight
        if settings.activityRhythm == .quiet {
            p.automaticRestrictions=Set(BehaviorDefinitions.all.filter {
                $0.occupiesEncounter || [.fixedPerchVisit,.foodTrayVisit,.bathVisit].contains($0.kind)
            }.map(\.kind))
        }
        if !settings.ambientLeafPlayEnabled {p.automaticRestrictions.insert(.leafPlay)}
        // The existing independent switches continue to gate previews as well.
        if settings.ambientFrequency != .low {p.legacyCadence=settings.ambientFrequency;p.manualAdjustmentEnabled=true}
        return p
    }
    public func validate() throws {
        guard migrationVersion==1,categoryOverrides.count<=BehaviorCategory.allCases.count else {throw SceneError.invalid("不支持的陪伴偏好版本")}
    }
    public func allows(_ kind:BehaviorKind,source:BehaviorSource)->Bool {
        if kind == .relocate {return true}
        if behaviorDisables.contains(kind) {return false}
        guard source == .automatic else {return true}
        if automaticRestrictions.contains(kind) {return false}
        if manualAdjustmentEnabled,categoryOverrides[kind.category]?.enabled == false {return false}
        if mode == .focus,kind == .pointerVisit {return false}
        return true
    }
    public var policy:CompanionPolicy {CompanionPolicy(preferences:self)}
}

public struct CompanionPolicy:Equatable {
    public static let presetVersion=1
    public let preferences:CompanionPreferences
    public var mode:CompanionMode {preferences.mode}
    public var flockInterval:ClosedRange<Double> {
        let base:ClosedRange<Double>
        switch mode {case .focus:base=480...720;case .natural:base=240...420;case .lively:base=120...240}
        let factor=weight(for:.flockPass);return base.lowerBound/factor...base.upperBound/factor
    }
    public var encounterInterval:ClosedRange<Double> {
        if preferences.manualAdjustmentEnabled,let f=preferences.legacyCadence {return f.interval}
        switch mode {case .focus:return 360...600;case .natural,.lively:return 180...360}
    }
    public var quietGap:Double {switch mode {case .focus:return 90;case .natural:return 45;case .lively:return 20}}
    public var pointerQuiet:Double {mode == .lively ? 5:10}
    public var orbitDuration:Double? {switch mode {case .focus:return 0;case .natural:return 6;case .lively:return nil}}
    public var flockDuration:ClosedRange<Double> {switch mode {case .focus:return 3...5;case .natural:return 4...7;case .lively:return 5...9}}
    public func style(for kind:BehaviorKind)->DurationStyle {
        if preferences.manualAdjustmentEnabled,let style=preferences.categoryOverrides[kind.category]?.duration {return style}
        switch mode {case .focus:return .short;case .natural:return .balanced;case .lively:return .full}
    }
    public func target(for kind:BehaviorKind)->Double {
        switch style(for:kind) {case .short:return 8;case .balanced:return 12;case .full:return .infinity}
    }
    public func cadence(minute:Int?)->Double {
        preferences.followLocalDayNight ? ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute):1
    }
    public func weight(for kind:BehaviorKind)->Double {
        guard preferences.manualAdjustmentEnabled,let f=preferences.categoryOverrides[kind.category]?.frequency else {return 1}
        switch f {case .low:return 0.5;case .medium:return 1;case .high:return 2}
    }
}

extension BehaviorKind {
    public var category:BehaviorCategory {
        if isSocial {return .social}
        if isPerchActivity {return .perch}
        switch self {case .relocate,.pointerVisit,.flockPass:return .flight;default:return .scene}
    }
    public var isSignificant:Bool {
        self != .relocate && !isPerchActivity
    }
}

/// Bounded aggregate telemetry; wall time never changes collision integration.
public struct CompanionMetrics:Codable,Equatable {
    public var unpausedElapsed:Double=0
    public var simulatedElapsed:Double=0
    public var visibleMotionTime:Double=0
    public var pointerNearbyMotionTime:Double=0
    public var maximumContinuousFlight:Double=0
    public var replans:Int=0
    public var sceneVisits:[String:Int]=[:]
}

public enum OpportunityState:String,Codable {case candidate,suppressed,deferred,started,completed,cancelled,failed}
public struct OpportunityDiagnostic:Codable,Equatable {
    public let time:Double
    public let kind:BehaviorKind?
    public let state:OpportunityState
    public let reason:String
    public var runID:UInt64?=nil
    public var elapsed:Double?=nil
    public var wallElapsed:Double?=nil
}

/// Independent streams and one bounded pending flock, never a backlog of events.
final class CompanionOpportunityScheduler {
    private let random:EngineRandom
    private(set) var flockRemaining:Double=0
    private(set) var encounterRemaining:Double=0
    private(set) var pendingFlockAge:Double?
    private(set) var quietRemaining:Double=0
    private(set) var inputQuiet:Double=0
    private(set) var pointerStill:Double=0
    private var anchor:CGPoint?
    private var retryRemaining=0.0
    private var policy:CompanionPolicy?
    var permit:BehaviorKind?
    private(set) var diagnostics:[OpportunityDiagnostic]=[]
    private(set) var counts:[String:Int]=[:]
    private(set) var flockDueCount=0
    private(set) var encounterDueCount=0
    private(set) var maximumFlockWait:Double=0
    init(seed:UInt64) {random=EngineRandom(seed:seed ^ 0x434F4D50414E494F)}
    func configure(_ p:CompanionPolicy,flockEnabled:Bool) {
        if policy != p {
            flockRemaining=random.value(in:p.flockInterval)
            encounterRemaining=random.value(in:p.encounterInterval)
            quietRemaining=max(quietRemaining,p.quietGap)
            policy=p
        }
        if !flockEnabled {pendingFlockAge=nil}
    }
    func record(time:Double,kind:BehaviorKind?,state:OpportunityState,reason:String,run:UInt64?=nil,elapsed:Double?=nil,wallElapsed:Double?=nil) {
        counts[(kind?.rawValue ?? "ordinary")+"."+state.rawValue+"."+reason,default:0]+=1
        diagnostics.append(.init(time:time,kind:kind,state:state,reason:reason,runID:run,elapsed:elapsed,wallElapsed:wallElapsed))
        if diagnostics.count>256 {diagnostics.removeFirst(diagnostics.count-256)}
    }
    func advance(_ dt:Double,pointer:CGPoint,buttonsDown:Bool,cadence:Double,flockEnabled:Bool) -> (flock:Bool,encounter:Bool) {
        guard let policy else {return (false,false)}
        quietRemaining=max(0,quietRemaining-dt)
        retryRemaining=max(0,retryRemaining-dt)
        inputQuiet=buttonsDown ? 0:inputQuiet+dt
        if let anchor,Geometry.distance(anchor,pointer)<=6 {pointerStill+=dt}
        else {anchor=pointer;pointerStill=0}
        if buttonsDown {pointerStill=0}
        flockRemaining-=dt*cadence;encounterRemaining-=dt*cadence
        if flockEnabled,flockRemaining<=0,pendingFlockAge==nil {
            flockDueCount+=1
            pendingFlockAge=0
            flockRemaining=random.value(in:policy.flockInterval)
        }
        if let age=pendingFlockAge {
            pendingFlockAge=age+dt
            maximumFlockWait=max(maximumFlockWait,min(120,age+dt))
            if age+dt>=120 {pendingFlockAge=nil;flockRemaining=random.value(in:policy.flockInterval)}
        }
        let due=encounterRemaining<=0
        if due {encounterDueCount+=1;encounterRemaining=random.value(in:policy.encounterInterval)}
        let flockDue=flockEnabled && pendingFlockAge != nil && inputQuiet>=3 && quietRemaining<=0 && retryRemaining<=0
        if flockDue {retryRemaining=1}
        return (flockDue,
                due && inputQuiet>=policy.pointerQuiet && quietRemaining<=0)
    }
    func didStart(_ kind:BehaviorKind) {permit=nil;if kind == .flockPass {pendingFlockAge=nil}}
    func didSettle() {quietRemaining=max(quietRemaining,policy?.quietGap ?? 0)}
    func clicked() {inputQuiet=0;pointerStill=0}
    func discardPending() {pendingFlockAge=nil;permit=nil}
}
