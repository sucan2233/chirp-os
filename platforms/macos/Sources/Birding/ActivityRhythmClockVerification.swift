import Foundation
import BirdingCore

enum ActivityRhythmClockVerification {
    static func run(into checks:inout [String:Bool]) {
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let midnight=Date(timeIntervalSince1970:0)
        var clock=LocalActivityClock(),reads=0
        func sample(_ now:Double,_ minute:Int) -> Int? {
            clock.sample(now:now,date:{reads+=1;return midnight.addingTimeInterval(Double(minute*60))},calendar:{calendar})
        }
        checks["activityClockInitialCivilMinute"]=sample(100,1439)==1439 && reads==1
        checks["activityClockCachesRepeatedWorldReads"]=sample(100.5,0)==1439 && reads==1
        checks["activityClockCrossesMidnight"]=sample(101,1440)==0 && reads==2
        checks["activityClockSleepUsesCurrentTime"]=sample(50_000,480)==480 && reads==3
        checks["activityClockBackwardsMonotonicResamples"]=sample(10,600)==600 && reads==4
        checks["activityClockInvalidMonotonicDoesNotRead"]=sample(.nan,0)==600 && reads==4
        calendar.timeZone=TimeZone(secondsFromGMT:8*3600)!
        checks["activityClockTimezoneChangeResamples"]=sample(11,600)==1080 && reads==5
        let desktop=DesktopController()
        desktop.settings.activityRhythm = .steady
        checks["activityClockSteadyNeedsNoCivilTime"]=desktop.activityMinuteOfDay()==nil
        desktop.settings.activityRhythm = .quiet
        checks["activityClockQuietNeedsNoCivilTime"]=desktop.activityMinuteOfDay()==nil
        desktop.settings.activityRhythm = .localDayNight
        checks["activityClockLocalModeSuppliesBoundedMinute"]=desktop.activityMinuteOfDay().map{(0..<1440).contains($0)} ?? false
        checks["activityClockDoesNotStartDesktop"]=desktop.timer==nil && desktop.panels.isEmpty && desktop.birds.isEmpty && desktop.visitorMemoryPersistence==nil
    }
}
