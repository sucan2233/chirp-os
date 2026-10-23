import Foundation
import CoreGraphics

public enum PerchActionKind:String,CaseIterable {
    case rest, preen
    var behavior:BehaviorKind {self == .rest ? .rest:.preen}
    var requiredFrames:Set<String> {
        self == .rest ? ["stand","blink"]:["stand","preen0","preen1"]
    }
}

/// A pose is a value layered over motion. It does not move the bird's foot anchor.
/// Releasing the owning run releases its presentation, including on cancellation.
struct BirdPose {
    let frameName:String
    let hopOffset:CGFloat
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
        let cadence,restDuration,preenDuration,preenRate,landingDelay:Double
        var quiet=0.0,landingAge=0.0,nextRest:Double
        var pendingPreen=false
        var revision:UInt64
        var landings:Int
        init(seed:UInt64,bird:Bird) {
            random=EngineRandom(seed:seed)
            cadence=0.8+0.4*random.unit()
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
    func register(_ id:BirdID,bird:Bird) {
        rhythms[id]=Rhythm(seed:seed ^ 0x5045524348524E47 ^ (id.rawValue &* 0x9E3779B97F4A7C15),bird:bird)
    }
    func remove(_ id:BirdID) {rhythms.removeValue(forKey:id)}
    func suppress(_ id:BirdID) {rhythms[id]?.suppress()}
    func suppressAll() {for id in rhythms.keys.sorted() {suppress(id)}}
    func select(_ ids:[BirdID]) -> BirdID? {selection.element(ids)}
    func plan(_ kind:PerchActionKind,for id:BirdID) -> PerchActionPlan? {
        guard let rhythm=rhythms[id] else {return nil}
        let base=kind == .rest ? rhythm.restDuration:rhythm.preenDuration
        return PerchActionPlan(kind:kind,duration:base*(0.9+0.2*rhythm.random.unit()),rate:rhythm.preenRate)
    }
    func candidate(_ id:BirdID,bird:Bird,dt:Double,enabled:Bool,occupied:Bool,quiet:Bool) -> PerchActionKind? {
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
        guard quiet else {rhythm.quiet=0;rhythm.pendingPreen=false;return nil}
        guard !occupied else {rhythm.quiet=0;return nil}
        if rhythm.pendingPreen,rhythm.landingAge>=rhythm.landingDelay {
            rhythm.pendingPreen=false;rhythm.quiet=0;return .preen
        }
        rhythm.quiet+=dt
        guard rhythm.quiet>=rhythm.nextRest else {return nil}
        rhythm.suppress();return .rest
    }
}

final class PerchActivityExecution:BehaviorExecution {
    let id:BirdID,plan:PerchActionPlan
    let occupiesEncounter=false,runsWhilePaused=false
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
