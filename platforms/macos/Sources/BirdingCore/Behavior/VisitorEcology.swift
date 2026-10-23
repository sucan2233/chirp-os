import Foundation
import CoreGraphics

extension BehaviorEngine {
    /// Learn only from an observable, settled, calm encounter on this display.
    /// The caller runs once per unpaused simulation step. Neither snapshots nor
    /// host validation nor wall-clock time can grow familiarity.
    func observeVisitor(_ id:BirdID,bird:Bird,inAttentionRange:Bool,distance:CGFloat,dt:Double) {
        guard let visitorID=visitorIDs[id] else {return}
        guard settings.visitorMemoryEnabled else {perchPlanner.setFamiliarity(0,for:id);return}
        let current=behavior(of:bird)
        let calmPose=current == nil || current == .watch || current == .rest || current == .preen
        if inAttentionRange,!world.buttonsDown,!perception.fast,
           distance>=max(30,24*spriteScale(for:bird)),bird.state == .perched,
           bird.edge == .top,bird.stateTime>=0.45,!bird.needsDestination,!bird.isDeparting,
           calmPose,(perchPlanner.ecology(id)?.disturbance ?? 1)<0.2,
           hasUsablePerch(bird) {
            visitorMemory.learn(visitorID,elapsed:dt)
        }
        perchPlanner.setFamiliarity(visitorMemory.profile(visitorID)?.familiarity ?? 0,for:id)
    }
}
