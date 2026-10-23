public enum ActivityRhythmMode:String,Codable,CaseIterable {
    case steady,localDayNight,quiet
}

/// A product rhythm for desktop activity, not a biological species model.
/// The caller supplies local minutes; this policy never reads a clock or RNG.
public enum ActivityRhythmPolicy {
    public static func ambientRate(mode:ActivityRhythmMode,minute:Int?) -> Double {
        switch mode {
        case .steady:return 1
        case .quiet:return 0
        case .localDayNight:
            guard let day=daytimeWeight(minute) else {return 1}
            return 0.35+0.65*day
        }
    }

    public static func restRate(mode:ActivityRhythmMode,minute:Int?,species:SpeciesID) -> Double {
        switch mode {
        case .steady:return 1
        case .quiet:return 1.6
        case .localDayNight:
            guard let day=daytimeWeight(minute) else {return 1}
            // Only these two species use the reversed product rest schedule.
            let resting:Double
            switch species {
            case .nightHeron,.collaredScopsOwl:resting=day
            default:resting=1-day
            }
            return 1+0.6*resting
        }
    }

    private static func daytimeWeight(_ minute:Int?) -> Double? {
        guard let minute,(0..<1440).contains(minute) else {return nil}
        switch minute {
        case 0..<360,1320..<1440:return 0
        case 360..<480:return smoothstep(Double(minute-360)/120)
        case 480..<1080:return 1
        default:return 1-smoothstep(Double(minute-1080)/240)
        }
    }

    private static func smoothstep(_ t:Double) -> Double {t*t*(3-2*t)}
}
