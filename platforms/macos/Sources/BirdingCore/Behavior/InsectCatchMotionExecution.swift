import CoreGraphics

/// One after-motion contract for both airborne interception and perch sallies.
/// The engine commits the independent insect once, before any terminal event.
protocol InsectCatchMotionExecution:BehaviorExecution {
    var captured:Bool {get}
    var minimumBeakDistance:CGFloat? {get}
    func resolveMotion(_ step:InsectStep?,in engine:BehaviorEngine) -> InsectResolution
    func reconcileWorld(in engine:BehaviorEngine,sampleDT:Double?) -> BehaviorCompletion?
}

extension InsectCatchMotionExecution {
    func reconcileWorld(in engine:BehaviorEngine) -> BehaviorCompletion? {
        reconcileWorld(in:engine,sampleDT:nil)
    }
}
