import Foundation
import CoreGraphics

/// Source-derived swallow/flycatcher beak geometry. The caller mirrors x -> 48-x
/// through PoseClip.Anchor.world; no world/species scale is baked into this API.
enum CatchPoseAnchors {
    static func anchor(species:SpeciesID,frame:String)->PoseClip.Anchor? {
        guard let point=CatchArtGeometry.billAnchor(species:species,frame:frame) else {return nil}
        return PoseClip.Anchor(Double(point.x),Double(point.y))
    }
}
