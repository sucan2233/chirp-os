import Foundation
import CoreGraphics

/// Brief visual recovery after a pose ends. This owns no behavior resource and
/// cannot override a new motion revision or keep a removed bird alive.
final class PoseMixer {
    private struct Recovery {
        let revision:UInt64
        let hop:CGFloat
        var age=0.0
    }
    private var recoveries:[BirdID:Recovery]=[:]
    func release(_ pose:BirdPose,for id:BirdID,bird:Bird) {
        guard bird.state == .perched,!bird.isDeparting else {return}
        recoveries[id]=Recovery(revision:bird.motionRevision,hop:pose.hopOffset)
    }
    func remove(_ id:BirdID) {recoveries.removeValue(forKey:id)}
    func advance(_ dt:Double) {
        for id in recoveries.keys.sorted() {
            recoveries[id]!.age+=dt
            if recoveries[id]!.age>=0.2 {recoveries.removeValue(forKey:id)}
        }
    }
    func hop(for id:BirdID,bird:Bird) -> CGFloat {
        guard let recovery=recoveries[id] else {return bird.hopOffset}
        guard bird.state == .perched,!bird.isDeparting,bird.motionRevision==recovery.revision else {
            recoveries.removeValue(forKey:id);return bird.hopOffset
        }
        let t=min(1,recovery.age/0.2),blend=t*t*(3-2*t)
        return recovery.hop*(1-blend)+bird.hopOffset*blend
    }
}
