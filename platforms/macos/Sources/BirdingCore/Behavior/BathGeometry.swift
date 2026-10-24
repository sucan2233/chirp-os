import Foundation
import CoreGraphics

/// Frozen logical coordinates shared by simulation, editable art and masking.
/// Placement points are slot feet; changing bird size never changes the surface.
public enum BathGeometry {
    public static let basinSize=CGSize(width:128,height:40)
    public static let waterEllipse=CGRect(x:16,y:10,width:96,height:20)
    public static let waterlineY:CGFloat=20
    public static let slotFoot=CGPoint(x:64,y:20)
    public static let birdWaterlineY:CGFloat=39
    public static let birdFootAnchor=CGPoint(x:29,y:39)
    public static let rightBeak=CGPoint(x:40,y:39)
    public static let leftBeak=CGPoint(x:8,y:39)
    public static let birdFeetRect=CGRect(x:24,y:38,width:11,height:3)
    public static let frameNames=["bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise"]
    public static let splashFrameNames=["splash0","splash1","splash2","splash3"]
    public static let splashLifetime=0.4
    public static let maximumSplashes=6
    public static let visitDuration=5.2
    public static let visitTimeout=35.0

    public static func rect(foot:CGPoint,scale:CGFloat) -> CGRect {
        CGRect(x:foot.x-slotFoot.x*scale,y:foot.y-slotFoot.y*scale,
               width:basinSize.width*scale,height:basinSize.height*scale)
    }
    public static func foot(in rect:CGRect,scale:CGFloat) -> CGPoint {
        CGPoint(x:rect.minX+slotFoot.x*scale,y:rect.minY+slotFoot.y*scale)
    }
    public static func waterRect(in rect:CGRect,scale:CGFloat) -> CGRect {
        CGRect(x:rect.minX+waterEllipse.minX*scale,y:rect.minY+waterEllipse.minY*scale,
               width:waterEllipse.width*scale,height:waterEllipse.height*scale)
    }
    public static func touchPoint(foot:CGPoint,spriteScale:CGFloat,facingRight:Bool) -> CGPoint {
        let beak=facingRight ? rightBeak:leftBeak
        let anchorX=facingRight ? birdFootAnchor.x:48-birdFootAnchor.x
        return CGPoint(x:foot.x+(beak.x-anchorX)*spriteScale,
                       y:foot.y+(beak.y-birdFootAnchor.y)*spriteScale)
    }
    public static func containsContact(_ point:CGPoint,waterRect:CGRect) -> Bool {
        guard point.x.isFinite,point.y.isFinite,waterRect.width.isFinite,waterRect.height.isFinite,
              waterRect.width>0,waterRect.height>0 else {return false}
        let x=(point.x-waterRect.midX)/(waterRect.width/2)
        let y=(point.y-waterRect.midY)/(waterRect.height/2)
        return x*x+y*y<=1+0.000001
    }
    static func clearance(foot:CGPoint,worldScale:CGFloat,spriteScale:CGFloat) -> CGRect? {
        guard foot.x.isFinite,foot.y.isFinite,worldScale.isFinite,worldScale>0,
              spriteScale.isFinite,spriteScale>0 else {return nil}
        let basin=rect(foot:foot,scale:worldScale)
        let body=Geometry.landingFootprint(at:foot,scale:spriteScale)
        let area=basin.union(body).insetBy(dx:-8*worldScale,dy:-8*worldScale)
        guard [area.minX,area.minY,area.maxX,area.maxY].allSatisfy(\.isFinite) else {return nil}
        let water=waterRect(in:basin,scale:worldScale)
        guard [true,false].allSatisfy({containsContact(touchPoint(foot:foot,spriteScale:spriteScale,facingRight:$0),waterRect:water)}) else {return nil}
        return area
    }
}
