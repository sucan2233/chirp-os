import Foundation
import CoreGraphics

/// Source-derived beak geometry for M6f.1. The caller mirrors with x -> 48-x
/// through PoseClip.Anchor.world; no world/species scale is baked into this API.
enum CatchPoseAnchors {
    static func anchor(species:SpeciesID,frame:String)->PoseClip.Anchor? {
        guard let point=CatchArtGeometry.billAnchor(species:species,frame:frame) else {return nil}
        return PoseClip.Anchor(Double(point.x),Double(point.y))
    }
}
