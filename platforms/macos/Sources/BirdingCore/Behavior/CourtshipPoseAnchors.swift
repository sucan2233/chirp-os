import Foundation

/// Five dedicated bills and the real common stand used by both role clips.
/// Unsupported species/frames return nil; mirroring belongs to Anchor.world.
enum CourtshipPoseAnchors {
    static func anchor(species:SpeciesID,frame:String)->PoseClip.Anchor? {
        guard let point=CourtshipArtGeometry.billAnchor(species:species,frame:frame) else {return nil}
        return PoseClip.Anchor(Double(point.x),Double(point.y))
    }
}
