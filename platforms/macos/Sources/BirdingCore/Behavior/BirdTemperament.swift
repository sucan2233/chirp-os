import Foundation

/// Stable individual variation, independent of species and the flight/pose RNGs.
public struct BirdTemperament:Equatable {
    public let boldness,curiosity,sociability,activity:Double

    public init(boldness:Double,curiosity:Double,sociability:Double,activity:Double) {
        func bounded(_ value:Double) -> Double {value.isFinite ? min(0.8,max(0.2,value)):0.5}
        self.boldness=bounded(boldness);self.curiosity=bounded(curiosity)
        self.sociability=bounded(sociability);self.activity=bounded(activity)
    }

    public init(seed:UInt64,birdID:BirdID) {
        let random=EngineRandom(seed:seed ^ 0x54454D504552414D ^ (birdID.rawValue &* 0x9E3779B97F4A7C15))
        self.init(boldness:0.2+0.6*random.unit(),curiosity:0.2+0.6*random.unit(),
            sociability:0.2+0.6*random.unit(),activity:0.2+0.6*random.unit())
    }
}

/// Remaining cooldowns and quiet time advance only on unpaused observations.
public struct BirdEcologySnapshot:Equatable {
    public let temperament:BirdTemperament
    public let disturbance:Double
    public let quietTime:Double
    public let cooldowns:[BehaviorKind:Double]
}

/// Range hysteresis belongs to the caller; the planner detects rising edges.
struct BirdStimulus {
    let near:Bool
    let inAttentionRange:Bool
    let fastPass:Bool
    let click:Bool
}
