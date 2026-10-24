import Foundation
import CoreGraphics

public enum AmbientFrequency: String, Codable, CaseIterable {
    case low, medium, high
    public var interval: ClosedRange<Double> {
        switch self {
        case .low: return 180...360
        case .medium: return 90...180
        case .high: return 45...90
        }
    }
}

public enum AmbientEvent: Equatable { case pointerVisit, flockPass, socialGreeting, leafPlay }

/// One simulation clock for encounters. Missed opportunities are discarded,
/// so busy periods, sleep and pause never build up a queue of animations.
public struct AmbientScheduler {
    public private(set) var remaining: Double = 180
    public private(set) var stationaryTime: Double = 0
    private var pointerAnchor: CGPoint?
    public init() {}
    public mutating func reset(_ frequency: AmbientFrequency) {
        remaining = frequency.interval.lowerBound
        stationaryTime = 0; pointerAnchor = nil
    }
    public mutating func suppress() {
        remaining = max(remaining, 60)
        stationaryTime = 0; pointerAnchor = nil
    }
    public mutating func tick(_ dt: Double, pointer: CGPoint, buttonsDown: Bool,
                              pointerEnabled: Bool, flockEnabled: Bool, socialEnabled: Bool = false, leafEnabled: Bool = false,
                              frequency: AmbientFrequency, busy: Bool, cadenceRate:Double=1, leafRandom: (() -> Double)? = nil,
                              random: () -> Double = { Double.random(in: 0..<1) }) -> AmbientEvent? {
        let step = min(0.1, max(0, dt))
        if buttonsDown || pointerAnchor == nil || Geometry.distance(pointer, pointerAnchor!) > 6 {
            pointerAnchor = pointer; stationaryTime = 0
        } else { stationaryTime += step }
        // Only opportunity cadence changes; pointer dwell and motion use real simulation time.
        let rate=cadenceRate.isFinite ? min(1,max(0,cadenceRate)):1
        remaining -= step*rate
        guard rate>0 else {return nil}
        guard remaining <= 0 else { return nil }
        let interval = frequency.interval
        remaining = interval.lowerBound + (interval.upperBound - interval.lowerBound) * random()
        guard !busy, !buttonsDown else { return nil }
        // Reserve a small share of existing opportunities, never a second timer.
        // Failed leaf plans are discarded instead of falling through to another event.
        if leafEnabled && (leafRandom.map{$0()} ?? random())<0.1 {return .leafPlay}
        var choices: [AmbientEvent] = []
        if pointerEnabled && stationaryTime >= 3 { choices.append(.pointerVisit) }
        if flockEnabled { choices.append(.flockPass) }
        if socialEnabled { choices.append(.socialGreeting) }
        guard !choices.isEmpty else { return nil }
        return choices[min(choices.count - 1, Int(random() * Double(choices.count)))]
    }
}

/// Initial orbit geometry. Optional pointer following translates the center in
/// Bird's motion integrator; entry and exit retain their tangential joins.
public struct PointerOrbit {
    public let center: CGPoint
    public let radius: CGFloat
    public let path: FlightPath
    static func isPossible(center:CGPoint,origin:CGPoint,area:CGRect,spriteScale:CGFloat) -> Bool {
        let radius = 140 + 35 * spriteScale
        let margin = 45 * spriteScale
        return spriteScale.isFinite && spriteScale>0 &&
            area.width > 2*(radius+margin) && area.height > 2*(radius+margin) &&
            area.insetBy(dx:radius+margin,dy:radius+margin).contains(center) &&
            Geometry.distance(origin,center)>radius+margin
    }
    public init?(center: CGPoint, origin: CGPoint, area: CGRect, spriteScale: CGFloat) {
        guard Self.isPossible(center:center,origin:origin,area:area,spriteScale:spriteScale) else {return nil}
        let radius = 140 + 35 * spriteScale
        self.center = center; self.radius = radius
        let angle = atan2(origin.y - center.y, origin.x - center.x)
        path = FlightPath(points: (0...512).map { i in
            let phase = angle + CGFloat(i) * 2 * .pi / 512
            return CGPoint(x: radius * cos(phase), y: radius * sin(phase))
        })
    }
}

public struct FlockMemberPlan {
    public let delay: Double
    public let path: FlightPath
    public let speed: Double
    public let wingPhase: Double
}

public enum AmbientFlock {
    // Respect enabled species. Avoid turning solitary raptors into arbitrary flocks.
    public static let species: Set<SpeciesID> = Set(SpeciesBehaviorProfile.ambientFlockSpecies)

    /// Use one display, including its actual offscreen edges. Staggered entry and
    /// shallow curves make a loose formation without a per-frame random jitter.
    public static func plan(screen: CGRect, rightward: Bool, count: Int, spriteScale: CGFloat,
                            speed: Double, random: () -> Double = { Double.random(in: 0..<1) }) -> [FlockMemberPlan] {
        guard screen.width > 200, screen.height > 200 else { return [] }
        let margin = 80 * spriteScale + 40
        guard screen.height > 2*margin+50 else {return []}
        let startX = rightward ? screen.minX - margin : screen.maxX + margin
        let endX = rightward ? screen.maxX + margin : screen.minX - margin
        let baseline = screen.minY + screen.height * (0.18 + random() * 0.10)
        return (0..<min(5, max(0, count))).map { index in
            let offset = CGFloat(index % 3 - 1) * 28 * spriteScale + CGFloat(random() * 16 - 8)
            let y = min(screen.maxY - margin, max(screen.minY + margin, baseline + offset))
            let rise = CGFloat(18 + random() * 24)
            let a = CGPoint(x: startX, y: y)
            let d = CGPoint(x: endX, y: y + CGFloat(random() * 26 - 13))
            let path = FlightPath(a, CGPoint(x: startX + (endX-startX)/3, y: y-rise),
                                  CGPoint(x: startX + (endX-startX)*2/3, y: d.y+rise), d)
            return FlockMemberPlan(delay: Double(index) * 0.45 + random() * 0.12,
                                   path: path, speed: speed * (0.96 + random() * 0.08),
                                   wingPhase: random() * 3)
        }
    }
}
