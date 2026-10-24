import Foundation
import CoreGraphics

/// Editable filled silhouette, including its border. All object dimensions use
/// world scale, never the carrier's relative scale. The ink ends exactly at y12.
public enum TwigGeometry {
    public static let logicalSize=CGSize(width:16,height:16)
    public static let grip=CGPoint(x:3,y:12)
    public static let surface=CGPoint(x:8,y:12)
    /// Horizontal symmetry makes either real end grip usable without changing
    /// the laid twig's appearance at pickup. Forks stay ahead of either grip.
    // Trace the actual native pixel edges, rather than diagonals whose aliased
    // fill can cover cells with centers outside the analytic polygon. These
    // integer steps retain the first source raster's 56-cell silhouette, and
    // make that same closed outline valid for arbitrary rotated footprints.
    public static let polygon:[CGPoint]=[
        CGPoint(x:0,y:10),CGPoint(x:3,y:10),CGPoint(x:3,y:7),CGPoint(x:5,y:7),
        CGPoint(x:5,y:8),CGPoint(x:6,y:8),CGPoint(x:6,y:10),CGPoint(x:7,y:10),
        CGPoint(x:7,y:6),CGPoint(x:9,y:6),CGPoint(x:9,y:10),CGPoint(x:10,y:10),
        CGPoint(x:10,y:8),CGPoint(x:11,y:8),CGPoint(x:11,y:7),CGPoint(x:13,y:7),
        CGPoint(x:13,y:10),CGPoint(x:16,y:10),CGPoint(x:16,y:12),CGPoint(x:0,y:12)
    ]
    public static let canvas:[CGPoint]=[.zero,CGPoint(x:16,y:0),CGPoint(x:16,y:16),CGPoint(x:0,y:16)]

    /// Position denotes the selected RAW anchor's world location. Reflect the
    /// displacement about that anchor first, then apply the desktop rotation.
    public static func transformedPolygon(position:CGPoint,anchor:CGPoint=grip,worldScale:CGFloat,
                                           facingRight:Bool,rotation:CGFloat=0)->[CGPoint]? {
        transform(polygon,position:position,anchor:anchor,worldScale:worldScale,
                  facingRight:facingRight,rotation:rotation)
    }
    public static func bounds(position:CGPoint,anchor:CGPoint=grip,worldScale:CGFloat,
                              facingRight:Bool,rotation:CGFloat=0)->CGRect? {
        guard let points=transformedPolygon(position:position,anchor:anchor,worldScale:worldScale,
            facingRight:facingRight,rotation:rotation) else {return nil}
        return enclosing(points)
    }
    public static func canvasBounds(position:CGPoint,anchor:CGPoint=grip,worldScale:CGFloat,
                                    facingRight:Bool,rotation:CGFloat=0)->CGRect? {
        guard let points=transform(canvas,position:position,anchor:anchor,worldScale:worldScale,
            facingRight:facingRight,rotation:rotation) else {return nil}
        return enclosing(points)
    }
    /// Exact coordinate extrema over every polygon vertex and the whole angular
    /// interval, including interior extrema between endpoint poses. No sampling.
    public static func sweptBounds(position:CGPoint,anchor:CGPoint=grip,worldScale:CGFloat,
                                   facingRight:Bool,rotationRange:ClosedRange<CGFloat>)->CGRect? {
        swept(polygon,position:position,anchor:anchor,worldScale:worldScale,
              facingRight:facingRight,rotationRange:rotationRange)
    }
    public static func sweptCanvasBounds(position:CGPoint,anchor:CGPoint=grip,worldScale:CGFloat,
                                         facingRight:Bool,rotationRange:ClosedRange<CGFloat>)->CGRect? {
        swept(canvas,position:position,anchor:anchor,worldScale:worldScale,
              facingRight:facingRight,rotationRange:rotationRange)
    }
    /// Contact orientation is zero. The same laid twig is gripped at raw x3
    /// from the left or raw x13 from the right; its central support stays put.
    public static func gripPoint(surfacePoint:CGPoint,worldScale:CGFloat,facingRight:Bool)->CGPoint? {
        guard valid(position:surfacePoint,anchor:surface,scale:worldScale),worldScale>0 else {return nil}
        let direction:CGFloat=facingRight ? 1:-1
        return CGPoint(x:surfacePoint.x+(grip.x-surface.x)*worldScale*direction,y:surfacePoint.y)
    }

    private static func valid(position:CGPoint,anchor:CGPoint,scale:CGFloat)->Bool {
        [position.x,position.y,anchor.x,anchor.y,scale].allSatisfy(\.isFinite) && scale>0
    }
    private static func transform(_ vertices:[CGPoint],position:CGPoint,anchor:CGPoint,worldScale:CGFloat,
                                  facingRight:Bool,rotation:CGFloat)->[CGPoint]? {
        guard valid(position:position,anchor:anchor,scale:worldScale),rotation.isFinite else {return nil}
        let direction:CGFloat=facingRight ? 1:-1,co=cos(rotation),si=sin(rotation)
        let points=vertices.map {p -> CGPoint in
            let x=(p.x-anchor.x)*worldScale*direction,y=(p.y-anchor.y)*worldScale
            return CGPoint(x:position.x+x*co-y*si,y:position.y+x*si+y*co)
        }
        return points.allSatisfy{$0.x.isFinite && $0.y.isFinite} ? points:nil
    }
    private static func enclosing(_ points:[CGPoint])->CGRect? {
        guard !points.isEmpty else {return nil}
        let xs=points.map(\.x),ys=points.map(\.y)
        let rect=CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
        return [rect.minX,rect.minY,rect.maxX,rect.maxY,rect.width,rect.height].allSatisfy(\.isFinite) ? rect:nil
    }
    private static func swept(_ vertices:[CGPoint],position:CGPoint,anchor:CGPoint,worldScale:CGFloat,
                              facingRight:Bool,rotationRange:ClosedRange<CGFloat>)->CGRect? {
        guard valid(position:position,anchor:anchor,scale:worldScale),
              rotationRange.lowerBound.isFinite,rotationRange.upperBound.isFinite else {return nil}
        let direction:CGFloat=facingRight ? 1:-1
        var minX=CGFloat.infinity,minY=CGFloat.infinity,maxX = -CGFloat.infinity,maxY = -CGFloat.infinity
        for point in vertices {
            let x=(point.x-anchor.x)*worldScale*direction,y=(point.y-anchor.y)*worldScale
            guard x.isFinite,y.isFinite else {return nil}
            let ex=extrema(x,-y,over:rotationRange),ey=extrema(y,x,over:rotationRange)
            minX=min(minX,ex.0);maxX=max(maxX,ex.1);minY=min(minY,ey.0);maxY=max(maxY,ey.1)
        }
        return enclosing([CGPoint(x:position.x+minX,y:position.y+minY),
                          CGPoint(x:position.x+maxX,y:position.y+maxY)])
    }
    /// Extrema of a*cos(theta)+b*sin(theta). Reduce the interval's start to
    /// avoid integer conversion/overflow, then inspect at most two extrema.
    private static func extrema(_ a:CGFloat,_ b:CGFloat,over range:ClosedRange<CGFloat>)->(CGFloat,CGFloat) {
        let tau=2*CGFloat.pi,radius=hypot(a,b),span=range.upperBound-range.lowerBound
        if !span.isFinite || span>=tau {return (-radius,radius)}
        let lower=range.lowerBound.truncatingRemainder(dividingBy:tau),upper=lower+span
        var low=min(a*cos(lower)+b*sin(lower),a*cos(upper)+b*sin(upper))
        var high=max(a*cos(lower)+b*sin(lower),a*cos(upper)+b*sin(upper))
        let phase=atan2(b,a)
        for (angle,value) in [(phase,radius),(phase+CGFloat.pi,-radius)] {
            let candidate=angle+ceil((lower-angle)/tau)*tau
            if candidate>=lower && candidate<=upper {low=min(low,value);high=max(high,value)}
        }
        return (low,high)
    }
}
