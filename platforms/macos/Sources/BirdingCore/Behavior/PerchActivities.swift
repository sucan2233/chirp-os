import Foundation
import CoreGraphics

public enum PerchActionKind:String,CaseIterable {
    case rest, preen
    var behavior:BehaviorKind {self == .rest ? .rest:.preen}
    var requiredFrames:Set<String> {
        BehaviorDefinitions.definition(for:behavior).requiredFrames
    }
}

/// A pose is a value layered over motion. It does not move the bird's foot anchor.
/// Releasing the owning run releases its presentation, including on cancellation.
struct BirdPose {
    let frameName:String
    let hopOffset:CGFloat
    var facingRight:Bool? = nil
}

struct PerchActionPlan {
    let kind:PerchActionKind
    let duration:Double
    let rate:Double
    func frame(at age:Double) -> String {
        guard age>=0.35,age<duration-0.35 else {return "stand"}
        switch kind {
        case .rest:return "blink"
        case .preen:return "preen\(Int((age-0.35)*rate)%2)"
        }
    }
}

/// Per-bird scheduling and variation live in the core, not the desktop adapter.
/// Separate deterministic streams keep optional poses from changing flight RNG.
final class PerchActivityPlanner {
    final class Rhythm {
        let random:EngineRandom
        let ecologyRandom:EngineRandom
        let temperament:BirdTemperament
        let cadence,restDuration,preenDuration,preenRate,landingDelay:Double
        var quiet=0.0,landingAge=0.0,nextRest:Double
        var pendingPreen=false
        var revision:UInt64
        var landings:Int
        var disturbance=0.0,quietTime=0.0
        var familiarity=0.0
        var cooldowns:[BehaviorKind:Double]=[:]
        var active:Set<BehaviorKind>=[]
        var previousNear=false,previousRange=false,previousFast=false,previousClick=false
        var pendingAttention:AttentionKind?
        var attentionRemaining=0.0
        var hopOpportunityRemaining=0.0
        var hasPerceptionBaseline=false
        init(seed:UInt64,bird:Bird,temperament:BirdTemperament?=nil) {
            random=EngineRandom(seed:seed)
            ecologyRandom=EngineRandom(seed:seed ^ 0x45434F4C4F475952)
            let traits=temperament ?? BirdTemperament(seed:seed,birdID:BirdID(0))
            self.temperament=traits
            cadence=(0.8+0.4*random.unit())*(1.2-0.4*traits.activity)
            restDuration=3+2*random.unit();preenDuration=1.7+1.1*random.unit()
            preenRate=2.2+1.1*random.unit();landingDelay=0.3+0.6*random.unit()
            nextRest=(12+14*random.unit())*cadence
            revision=bird.motionRevision;landings=bird.landedCount
        }
        func suppress() {
            quiet=0;pendingPreen=false;landingAge=0
            nextRest=(12+14*random.unit())*cadence
        }
    }
    let seed:UInt64
    private let selection:EngineRandom
    private(set) var rhythms:[BirdID:Rhythm]=[:]
    init(seed:UInt64) {self.seed=seed;selection=EngineRandom(seed:seed ^ 0x504552434853454C)}
    func register(_ id:BirdID,bird:Bird,temperament:BirdTemperament?=nil,familiarity:Double=0) {
        rhythms[id]=Rhythm(seed:seed ^ 0x5045524348524E47 ^ (id.rawValue &* 0x9E3779B97F4A7C15),bird:bird,
            temperament:temperament ?? BirdTemperament(seed:seed,birdID:id))
        setFamiliarity(familiarity,for:id)
    }
    func setFamiliarity(_ value:Double,for id:BirdID) {
        rhythms[id]?.familiarity=value.isFinite ? min(1,max(0,value)):0
    }
    func remove(_ id:BirdID) {rhythms.removeValue(forKey:id)}
    func suppress(_ id:BirdID) {rhythms[id]?.suppress()}
    func suppressAll() {for id in rhythms.keys.sorted() {suppress(id)}}
    func select(_ ids:[BirdID]) -> BirdID? {selection.element(ids)}
    func ecology(_ id:BirdID) -> BirdEcologySnapshot? {
        guard let rhythm=rhythms[id] else {return nil}
        return BirdEcologySnapshot(temperament:rhythm.temperament,disturbance:rhythm.disturbance,
            quietTime:rhythm.quietTime,familiarity:rhythm.familiarity,cooldowns:rhythm.cooldowns)
    }
    func observe(_ id:BirdID,stimulus:BirdStimulus,dt:Double) {
        guard let rhythm=rhythms[id],dt.isFinite,dt>=0 else {return}
        rhythm.disturbance *= pow(0.5,dt/6)
        for kind in Array(rhythm.cooldowns.keys) {
            let remaining=(rhythm.cooldowns[kind] ?? 0)-dt
            if remaining>0 {rhythm.cooldowns[kind]=remaining}
            else {rhythm.cooldowns.removeValue(forKey:kind)}
        }
        rhythm.attentionRemaining=max(0,rhythm.attentionRemaining-dt)
        rhythm.hopOpportunityRemaining=max(0,rhythm.hopOpportunityRemaining-dt)
        let approached=rhythm.hasPerceptionBaseline && stimulus.near && !rhythm.previousNear
        rhythm.hasPerceptionBaseline=true
        if rhythm.attentionRemaining==0 {rhythm.pendingAttention=nil}
        let entered=stimulus.inAttentionRange && !rhythm.previousRange
        let fast=stimulus.fastPass && !rhythm.previousFast
        let clicked=stimulus.click && !rhythm.previousClick
        rhythm.previousNear=stimulus.near;rhythm.previousRange=stimulus.inAttentionRange
        rhythm.previousFast=stimulus.fastPass;rhythm.previousClick=stimulus.click
        if approached,!stimulus.click,!stimulus.fastPass,rhythm.disturbance<0.6,
           automaticWeight(id,kind:.sideHop)>0,
           rhythm.ecologyRandom.unit()<(0.3+0.5*rhythm.temperament.boldness)*(1-0.35*rhythm.familiarity) {
            rhythm.hopOpportunityRemaining=0.5
        }
        if !stimulus.near || stimulus.click || stimulus.fastPass {rhythm.hopOpportunityRemaining=0}
        if clicked {noteClick(id)}
        else if fast && !stimulus.click {
            rhythm.disturbance=min(1,rhythm.disturbance+0.65*(1-rhythm.temperament.boldness)*(1-0.15*rhythm.familiarity))
            // A fast pass can replace a pending watch, but never retries while held.
            rhythm.pendingAttention=nil;rhythm.attentionRemaining=0
            if automaticWeight(id,kind:.alert)>0 {
                rhythm.pendingAttention = .alert;rhythm.attentionRemaining=0.5
            }
        } else if entered && !stimulus.click && !stimulus.fastPass && !stimulus.near,
                  automaticWeight(id,kind:.watch)>0,
                  rhythm.ecologyRandom.unit()<min(0.9,rhythm.temperament.curiosity+0.1*rhythm.familiarity) {
            rhythm.pendingAttention = .watch;rhythm.attentionRemaining=0.5
        }
        if !stimulus.inAttentionRange && rhythm.pendingAttention == .watch {
            rhythm.pendingAttention=nil;rhythm.attentionRemaining=0
        }
        if stimulus.near || stimulus.fastPass || stimulus.click || rhythm.disturbance>=0.35 {
            rhythm.quietTime=0;rhythm.quiet=0;rhythm.pendingPreen=false
        } else {rhythm.quietTime+=dt}
    }
    func noteClick(_ id:BirdID) {
        guard let rhythm=rhythms[id] else {return}
        // An explicit click command and the next held-button sample are one input.
        rhythm.previousClick=true;rhythm.hopOpportunityRemaining=0
        rhythm.disturbance=min(1,rhythm.disturbance+0.8*(1-rhythm.temperament.boldness))
        rhythm.quietTime=0;rhythm.quiet=0;rhythm.pendingPreen=false
        rhythm.pendingAttention=nil;rhythm.attentionRemaining=0
        for kind:BehaviorKind in [.watch,.alert] {rhythm.cooldowns[kind]=max(4,rhythm.cooldowns[kind] ?? 0)}
    }
    func resetPerception() {
        for rhythm in rhythms.values {
            rhythm.pendingAttention=nil;rhythm.attentionRemaining=0
            rhythm.hopOpportunityRemaining=0;rhythm.hasPerceptionBaseline=false
            rhythm.previousNear=false;rhythm.previousRange=false
            rhythm.previousFast=false;rhythm.previousClick=false
        }
    }
    /// Reading a candidate does not consume it; acceptance is acknowledged by didStart.
    func attentionCandidate(_ id:BirdID) -> AttentionKind? {
        guard let rhythm=rhythms[id],rhythm.attentionRemaining>0,
              let pending=rhythm.pendingAttention else {return nil}
        let kind:BehaviorKind=pending == .watch ? .watch:.alert
        return automaticWeight(id,kind:kind)>0 ? pending:nil
    }
    /// Consume the approach once, including when no safe hop can be planned.
    func consumeHopOpportunity(_ id:BirdID) -> Bool {
        guard let rhythm=rhythms[id],rhythm.hopOpportunityRemaining>0 else {return false}
        rhythm.hopOpportunityRemaining=0
        return automaticWeight(id,kind:.sideHop)>0
    }
    func automaticWeight(_ id:BirdID,kind:BehaviorKind) -> Double {
        guard let rhythm=rhythms[id],!rhythm.active.contains(kind),(rhythm.cooldowns[kind] ?? 0)<=0 else {return 0}
        let traits=rhythm.temperament
        if kind == .sideHop {return rhythm.disturbance<0.6 ? (0.5+traits.activity)*(1-0.2*rhythm.familiarity):0}
        if kind == .alert {
            return rhythm.disturbance>=0.2 ? (1.2-traits.boldness)*(0.8+0.4*traits.activity):0
        }
        if rhythm.disturbance>=0.35 && (kind == .rest || kind == .preen || kind.isSocial || kind == .leafPlay || kind == .watch) {return 0}
        if kind.isSocial {return (0.4+1.2*traits.sociability)*(0.8+0.4*traits.boldness)}
        switch kind {
        case .rest:return 1.2-0.4*traits.activity
        case .preen:return (0.6+0.8*traits.boldness)*(0.9+0.2*traits.curiosity)
        case .leafPlay:return (0.3+1.4*traits.curiosity)*(0.6+0.8*traits.activity)*(0.7+0.6*traits.boldness)
        case .watch:return (0.4+1.2*traits.curiosity)*(1+0.2*rhythm.familiarity)
        default:return 1
        }
    }
    func didStart(_ id:BirdID,kind:BehaviorKind) {
        guard let rhythm=rhythms[id] else {return}
        rhythm.active.insert(kind);rhythm.hopOpportunityRemaining=0
        rhythm.pendingAttention=nil;rhythm.attentionRemaining=0
        rhythm.quietTime=0;rhythm.quiet=0;rhythm.pendingPreen=false
    }
    func didFinish(_ id:BirdID,kind:BehaviorKind) {
        guard let rhythm=rhythms[id],rhythm.active.remove(kind) != nil else {return}
        let duration=BehaviorDefinitions.definition(for:kind).cooldown
        guard duration>0 else {return}
        // Social opportunities share one recovery period across all variants.
        let kinds:[BehaviorKind]=kind.isSocial ? [.socialGreeting,.sideBySide,.giveWay,.pairedTakeoff]:[kind]
        for cooled in kinds {rhythm.cooldowns[cooled]=max(duration,rhythm.cooldowns[cooled] ?? 0)}
    }
    func plan(_ kind:PerchActionKind,for id:BirdID) -> PerchActionPlan? {
        guard let rhythm=rhythms[id] else {return nil}
        let base=kind == .rest ? rhythm.restDuration:rhythm.preenDuration
        return PerchActionPlan(kind:kind,duration:base*(0.9+0.2*rhythm.random.unit()),rate:rhythm.preenRate)
    }
    func candidate(_ id:BirdID,bird:Bird,dt:Double,enabled:Bool,occupied:Bool,quiet:Bool,restRate:Double=1) -> PerchActionKind? {
        guard let rhythm=rhythms[id] else {return nil}
        if rhythm.revision != bird.motionRevision {
            rhythm.revision=bird.motionRevision;rhythm.quiet=0;rhythm.pendingPreen=false;rhythm.landingAge=0
        }
        if rhythm.landings != bird.landedCount {
            rhythm.landings=bird.landedCount;rhythm.landingAge=0
            rhythm.pendingPreen=rhythm.random.unit()<0.65
        }
        guard enabled else {rhythm.quiet=0;rhythm.pendingPreen=false;return nil}
        guard bird.state == .perched,!bird.isDeparting,bird.edge == .top else {rhythm.quiet=0;return nil}
        if rhythm.pendingPreen {
            rhythm.landingAge+=dt
            if rhythm.landingAge>2.5 {rhythm.pendingPreen=false}
        }
        guard quiet,rhythm.disturbance<0.35 else {rhythm.quiet=0;rhythm.pendingPreen=false;return nil}
        guard !occupied else {rhythm.quiet=0;return nil}
        if rhythm.pendingPreen,rhythm.landingAge>=rhythm.landingDelay,automaticWeight(id,kind:.preen)>0 {
            rhythm.pendingPreen=false;rhythm.quiet=0;return .preen
        }
        rhythm.quiet+=dt*restRate
        guard rhythm.quiet>=rhythm.nextRest,automaticWeight(id,kind:.rest)>0 else {return nil}
        rhythm.suppress();return .rest
    }
}

final class PerchActivityExecution:BehaviorExecution {
    let id:BirdID,plan:PerchActionPlan
    var kind:BehaviorKind {plan.kind.behavior}
    var participants:[BirdID] {[id]}
    var timeout:Double {plan.duration+1}
    private var age=0.0
    private var revision:UInt64=0
    private var initialHop:CGFloat=0
    init(id:BirdID,plan:PerchActionPlan) {self.id=id;self.plan=plan}
    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(id) else {return}
        revision=bird.motionRevision;initialHop=engine.baseHop(for:id,bird:bird)
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(id) else {return .failed(.missingBird)}
        guard bird.motionRevision==revision,bird.state == .perched,!bird.needsDestination,
              engine.hasUsablePerch(bird) else {return .failed(.targetInvalid)}
        guard engine.supports(plan.kind,bird:bird) else {return .failed(.missingFrames)}
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(id) else {return .failed(.missingBird)}
        if engine.world.buttonsDown {return .cancelled(.userInput)}
        if engine.pointerNear(bird) {return .cancelled(.pointerNearby)}
        age+=dt
        return age>=plan.duration ? .completed:nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        // Runtime removal removes the pose. No restore-to-old-frame mutation,
        // so a newly started flight cannot be overwritten by stale cleanup.
    }
    func presentation(for birdID:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        guard birdID==id,let bird=engine.bird(id),bird.motionRevision==revision,
              bird.state == .perched else {return nil}
        func ease(_ value:Double) -> CGFloat {let t=min(1,max(0,value));return t*t*(3-2*t)}
        // Blend out an existing hop and blend back to the live idle motion. The
        // anchor, orientation, occlusion and sprite geometry stay authoritative.
        let hop=age<0.35 ? initialHop*(1-ease(age/0.35)) : bird.hopOffset*ease((age-(plan.duration-0.35))/0.35)
        return BirdPose(frameName:plan.frame(at:age),hopOffset:hop)
    }
}
