import Foundation
import BirdingCore

/// Civil time is sampled only by the adapter. Monotonic time limits sampling;
/// neither clock advances the engine or catches up missed activity.
struct LocalActivityClock {
    private var lastSample:Double?
    private var minute:Int?
    mutating func sample(now:Double,date:()->Date={Date()},calendar:()->Calendar={Calendar.autoupdatingCurrent}) -> Int? {
        guard now.isFinite else {return minute}
        if let lastSample,now>=lastSample,now-lastSample<1 {return minute}
        lastSample=now
        let parts=calendar().dateComponents([.hour,.minute],from:date())
        if let hour=parts.hour,let value=parts.minute,(0..<24).contains(hour),(0..<60).contains(value) {
            minute=hour*60+value
        } else {minute=nil}
        return minute
    }
}

extension DesktopController {
    func activityMinuteOfDay() -> Int? {
        guard settings.activityRhythm == .localDayNight else {return nil}
        return activityClock.sample(now:ProcessInfo.processInfo.systemUptime)
    }
}
