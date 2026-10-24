import Foundation

enum NestPoseAnchors {
    static func anchor(species:SpeciesID,frame:String)->PoseClip.Anchor? {
        guard let point=NestArtGeometry.billAnchor(species:species,frame:frame) else {return nil}
        return PoseClip.Anchor(Double(point.x),Double(point.y))
    }
}
