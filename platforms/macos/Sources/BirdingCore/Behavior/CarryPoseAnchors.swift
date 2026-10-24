import Foundation
import CoreGraphics

/// Right-facing, top-down 48-unit geometry; mirror with PoseClip.Anchor.
/// Both endpoints read the same editable source as DetailedBirdArt; there is
/// no hand-copied flight table and no prop/carrier scale baked into the anchor.
enum CarryPoseAnchors {
    static func anchor(species:SpeciesID,frame:String)->PoseClip.Anchor? {
        guard CarryArtGeometry.species.contains(species) else {return nil}
        let point:CGPoint
        if let pose=CarryArtGeometry.pose(species:species,frame:frame) {
            point=pose.billTip
        } else if let bill=CarryArtGeometry.transportBillAnchor(species:species,frame:frame) {
            point=bill
        } else {return nil}
        return PoseClip.Anchor(Double(point.x),Double(point.y))
    }
}
