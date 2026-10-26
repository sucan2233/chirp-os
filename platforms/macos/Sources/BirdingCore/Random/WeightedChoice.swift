import Foundation

public enum WeightedChoiceError: Error, Equatable {
    case invalidWeight
    case invalidUnit
}

/// A stable, scale-independent pool. Empty and all-zero pools never draw or invent a candidate.
public struct WeightedChoice<Value> {
    public static var algorithmVersion: Int { 2 }
    private let values: [Value]
    private let boundaries: [Double]
    private let total: Double

    public init(_ candidates: [Value], weight: (Value) -> Double) throws {
        let weights = candidates.map(weight)
        guard weights.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw WeightedChoiceError.invalidWeight }
        let maximum = weights.max() ?? 0
        var values: [Value] = [], boundaries: [Double] = []
        var sum = 0.0, compensation = 0.0
        if maximum > 0 {
            for (value, weight) in zip(candidates, weights) where weight > 0 {
                let corrected = weight / maximum - compensation
                let next = sum + corrected
                compensation = (next - sum) - corrected
                sum = next
                values.append(value); boundaries.append(sum)
            }
        }
        self.values = values; self.boundaries = boundaries; total = sum
    }

    public var isEmpty: Bool { values.isEmpty }
    public func choose(unit: Double) throws -> Value? {
        guard unit.isFinite && unit >= 0 && unit < 1 else { throw WeightedChoiceError.invalidUnit }
        guard !isEmpty else { return nil }
        let ticket = unit * total
        for (value, boundary) in zip(values, boundaries) where ticket < boundary { return value }
        // The last positive candidate absorbs floating-point tail rounding only.
        return values.last
    }
    public func choose(using random: () -> Double) throws -> Value? {
        guard !isEmpty else { return nil }
        return try choose(unit: random())
    }
}

/// Helpers for internal, validated probability constants and injected [0, 1) random streams.
public enum RandomChoice {
    public static func chance(_ probability: Double, using random: () -> Double) -> Bool {
        precondition(probability.isFinite && (0...1).contains(probability))
        let unit = random()
        precondition(unit.isFinite && unit >= 0 && unit < 1)
        return unit < probability
    }
    public static func odds(success: Double, failure: Double, using random: () -> Double) throws -> Bool? {
        try WeightedChoice([true, false], weight: { $0 ? success : failure }).choose(using: random)
    }
    public static func index(count: Int, using random: () -> Double) -> Int? {
        guard count > 0 else { return nil }
        let unit = random()
        precondition(unit.isFinite && unit >= 0 && unit < 1)
        return min(count - 1, Int(unit * Double(count)))
    }
    public static func value(in range: ClosedRange<Double>, using random: () -> Double) -> Double {
        precondition(range.lowerBound.isFinite && range.upperBound.isFinite)
        let unit = random()
        precondition(unit.isFinite && unit >= 0 && unit < 1)
        return (1 - unit) * range.lowerBound + unit * range.upperBound
    }
}
