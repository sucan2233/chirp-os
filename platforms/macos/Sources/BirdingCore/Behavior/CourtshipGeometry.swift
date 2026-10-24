import Foundation
import CoreGraphics

/// Full 48px canvases rotate about the shared (29,39) foot anchor. The
/// clearance is measured in desktop points; only pointer padding follows scale.
public enum CourtshipGeometry {
    public static let frameNames=CourtshipArtGeometry.frameNames
    public static let facingDuration=0.4
    public static let raisingDuration=0.5
    public static let bowingDuration=2.0
    public static let observingDuration=0.5
    public static let recoveryDuration=0.6
    public static let duration=4.0
    public static let timeout=6.0
    public static let quietDuration=10.0
    public static let minimumGap:CGFloat=12
    public static let pointerPadding:CGFloat=80

    public static func turningBounds(foot:CGPoint,scale:CGFloat) -> CGRect {
        Geometry.landingFootprint(at:foot,scale:scale)
    }
    public static func hasClearance(_ a:CGPoint,_ b:CGPoint,scale:CGFloat) -> Bool {
        guard scale.isFinite,scale>0,a.x.isFinite,a.y.isFinite,b.x.isFinite,b.y.isFinite else {return false}
        let left=turningBounds(foot:a.x<b.x ? a:b,scale:scale)
        let right=turningBounds(foot:a.x<b.x ? b:a,scale:scale)
        return right.minX-left.maxX>=minimumGap
    }
    public static func pointerIsClear(_ pointer:CGPoint,feet:[CGPoint],birdScale:CGFloat,worldScale:CGFloat) -> Bool {
        guard pointer.x.isFinite,pointer.y.isFinite,birdScale.isFinite,birdScale>0,
              worldScale.isFinite,worldScale>0 else {return false}
        let padding=pointerPadding*worldScale
        return feet.allSatisfy {
            !turningBounds(foot:$0,scale:birdScale).insetBy(dx:-padding,dy:-padding).contains(pointer)
        }
    }
}
