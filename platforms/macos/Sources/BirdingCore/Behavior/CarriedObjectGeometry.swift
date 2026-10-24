import Foundation
import CoreGraphics

/// Authored leaf coordinates shared with art. Object scale belongs to the world,
/// not the carrier; changing species never changes the same object's size.
public enum CarriedObjectGeometry {
    public static let leafSize:CGFloat=16
    public static let grip=CGPoint(x:3,y:12)
    public static let surface=CGPoint(x:10,y:12)
    public static let contactBeak=PoseClip.Anchor(40,39)
    public static let frameNames=["carryLook","carryLower","carryGrip","carryPlace"]
    public static let availableLifetime=180.0
    public static let placedLifetime=8.0
    public static let fadeDuration=0.2
    public static let timeout=25.0

    public static func pickupFoot(surface point:CGPoint,worldScale:CGFloat,birdScale:CGFloat,facingRight:Bool) -> CGPoint {
        let offset=7*worldScale+11*birdScale
        return CGPoint(x:point.x+(facingRight ? -offset:offset),y:point.y)
    }
    public static func surfacePoint(foot:CGPoint,worldScale:CGFloat,birdScale:CGFloat,facingRight:Bool) -> CGPoint {
        let offset=7*worldScale+11*birdScale
        return CGPoint(x:foot.x+(facingRight ? offset:-offset),y:foot.y)
    }
    /// Raw (unmirrored) anchor coordinates; renderer mirrors around the anchor.
    static func render(id:ScenePropID,position:CGPoint,anchor:CGPoint,worldScale:CGFloat,
                       facingRight:Bool,rotation:CGFloat=0,opacity:Double=1,blockers:[CGRect]=[]) -> ScenePropRenderState {
        var value=ScenePropRenderState(id:id,kind:.leafToken,position:position,size:leafSize*worldScale,
            rotation:rotation,opacity:opacity,blockers:blockers,frameName:"leafToken",
            anchor:CGPoint(x:anchor.x/leafSize,y:anchor.y/leafSize))
        value.mirrored = !facingRight
        return value
    }
    /// Exact four-corner AABB for the same biased pivot/mirror/rotation transform
    /// used by ScenePropRenderState.rect. Public for exported geometric evidence.
    public static func bounds(position:CGPoint,anchor:CGPoint,worldScale:CGFloat,
                              facingRight:Bool,rotation:CGFloat=0) -> CGRect {
        render(id:ScenePropID(0),position:position,anchor:anchor,worldScale:worldScale,
               facingRight:facingRight,rotation:rotation).rect
    }
    /// Covers every authored beak frame and either heading. A nonconstant angular
    /// range uses the corners' maximum radius, enclosing extrema between samples.
    /// M6e leaves retain zero rotation; do not reject ground by inventing spins.
    static func localFootprint(species:SpeciesID,birdScale:CGFloat,worldScale:CGFloat,
                               rotationRange:ClosedRange<CGFloat> = 0...0) -> CGRect? {
        guard birdScale.isFinite,birdScale>0,worldScale.isFinite,worldScale>0 else {return nil}
        let names=frameNames+["stand","land0","land1","land2"]+(0...7).map{"fly\($0)"}
        var area=Geometry.landingFootprint(at:.zero,scale:birdScale)
        let radius=hypot(max(grip.x,leafSize-grip.x),max(grip.y,leafSize-grip.y))*worldScale
        for name in names {
            guard let anchor=PoseClip.carryBeakAnchor(species:species,frame:name) else {return nil}
            for facing in [true,false] {
                let beak=anchor.world(foot:.zero,scale:birdScale,facingRight:facing)
                if rotationRange.lowerBound==rotationRange.upperBound {
                    for leafFacing in [true,false] {
                        area=area.union(bounds(position:beak,anchor:grip,worldScale:worldScale,
                            facingRight:leafFacing,rotation:rotationRange.lowerBound))
                    }
                } else {
                    area=area.union(CGRect(x:beak.x-radius,y:beak.y-radius,width:2*radius,height:2*radius))
                }
            }
        }
        return SurfaceAnchor.finite(area) ? area:nil
    }
    static func attached(id:ScenePropID,bird:Bird,pose:BirdPose,worldScale:CGFloat,birdScale:CGFloat,
                         facingRight:Bool,blockers:[CGRect]) -> ScenePropRenderState? {
        guard let anchor=PoseClip.carryBeakAnchor(species:bird.profile.id,frame:pose.frameName) else {return nil}
        let foot=CGPoint(x:bird.position.x,y:bird.position.y+pose.hopOffset*birdScale)
        let beak=anchor.world(foot:foot,scale:birdScale,facingRight:pose.facingRight ?? bird.facingRight)
        return render(id:id,position:beak,anchor:grip,worldScale:worldScale,
                      facingRight:facingRight,blockers:blockers)
    }
}
