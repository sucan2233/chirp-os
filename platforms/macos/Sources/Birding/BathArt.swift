import AppKit
import BirdingCore

/// Editable, top-down bath art. Every basin layer keeps the same 128x40
/// origin; rear/front partition the single authored whole image pixel for pixel.
/// Paths describe occlusion regions (pixels to remove), not visibility masks.
/// Apply water + local feet + front only while the bird is settled in this bath.
enum BathArt {
    enum Layer {case whole,rear,front}
    static let logicalSize=BathGeometry.basinSize
    static let waterlineY=BathGeometry.waterlineY
    static let birdWaterlineY=BathGeometry.birdWaterlineY
    static let footAnchor=BathGeometry.slotFoot
    static let splashLogicalSize=CGSize(width:24,height:24)
    static let splashAnchor=CGPoint(x:12,y:22)

    static var waterPath:CGPath {CGPath(ellipseIn:BathGeometry.waterEllipse,transform:nil)}

    /// Exactly the lower half of the water ellipse (y > 20). The line at y20
    /// is a boundary, not a one-pixel raised strip; retain the contact row when
    /// rasterizing a removal mask. Never apply this during approach/departure.
    static var immersionPath:CGPath {
        let e=BathGeometry.waterEllipse,y=waterlineY,k:CGFloat=0.5522847498307936
        let p=CGMutablePath()
        p.move(to:CGPoint(x:e.minX,y:y))
        p.addCurve(to:CGPoint(x:e.midX,y:e.maxY),
                   control1:CGPoint(x:e.minX,y:y+e.height/2*k),
                   control2:CGPoint(x:e.midX-e.width/2*k,y:e.maxY))
        p.addCurve(to:CGPoint(x:e.maxX,y:y),
                   control1:CGPoint(x:e.midX+e.width/2*k,y:e.maxY),
                   control2:CGPoint(x:e.maxX,y:y+e.height/2*k))
        p.closeSubpath();return p
    }

    static var frontOcclusionPath:CGPath {
        polygon([(8,18),(16,20),(24,26),(40,29),(64,30),(88,29),
                 (104,26),(112,20),(120,18),(116,30),(104,36),(24,36),(12,30)])
    }

    /// Bird-local coordinates; transform with the sprite, not with the basin.
    /// Only this local x24...35/y38...41 patch hides toes above the waterline.
    /// Left-facing uses x -> 48-x, so its patch becomes x13...24.
    static func birdFeetOcclusionPath(facingRight:Bool=true)->CGPath {
        let r=BathGeometry.birdFeetRect
        let rect=facingRight ? r:CGRect(x:48-r.maxX,y:r.minY,width:r.width,height:r.height)
        return CGPath(rect:rect,transform:nil)
    }

    static func image(layer:Layer = .whole)->CGImage {
        switch layer {
        case .whole:return basinWhole
        case .rear:return basinRear
        case .front:return basinFront
        }
    }

    static func splashImage(_ frame:String)->CGImage? {
        guard let i=BathGeometry.splashFrameNames.firstIndex(of:frame) else {return nil}
        return splashes[i]
    }

    private static func polygon(_ points:[(Double,Double)])->CGPath {
        let p=CGMutablePath()
        guard let first=points.first else {return p}
        p.move(to:CGPoint(x:first.0,y:first.1))
        for v in points.dropFirst() {p.addLine(to:CGPoint(x:v.0,y:v.1))}
        p.closeSubpath();return p
    }

    private static let basinWhole:CGImage = {
        let c=Painter(width:128,height:40)
        // Stoneware body, broad rim and a shallow blue-green well. The center
        // slot is water, not a visible perch or raised pedestal.
        c.poly([(8,18),(12,29),(24,36),(104,36),(116,29),(120,18)],0x8B7C69FF,outline:true)
        c.oval(CGRect(x:8,y:4,width:112,height:28),0xC5B89AFF,outline:true)
        c.oval(CGRect(x:13,y:8,width:102,height:24),0x716F64FF)
        c.oval(BathGeometry.waterEllipse,0x70ABB2FF)
        c.ctx.saveGState();c.ctx.addPath(waterPath);c.ctx.clip()
        c.oval(CGRect(x:19,y:12,width:89,height:17),0x8CBEC0FF)
        c.oval(CGRect(x:28,y:12,width:66,height:11),0xA6CFCAFF)
        // Sparse surface reflections avoid drawing a false hard ledge at y20.
        c.line([(29,16),(42,15),(52,15)],0xD1E6D5FF)
        c.line([(77,17),(91,17),(98,18)],0xC1DDD2FF)
        c.line([(23,23),(29,24),(36,24)],0x5F98A5FF)
        c.line([(91,25),(101,23)],0x5F98A5FF)
        c.ctx.restoreGState()
        c.poly([(8,18),(16,20),(24,26),(40,29),(64,30),(88,29),
                (104,26),(112,20),(120,18),(116,30),(104,36),(24,36),(12,30)],0xB4A284FF,outline:true)
        c.poly([(16,27),(26,32),(103,32),(113,27),(104,36),(24,36)],0x9A886FFF)
        c.line([(16,21),(25,27),(41,30),(64,31),(87,30),(103,27),(112,21)],0xDACBADFF)
        c.line([(27,34),(47,35),(81,35),(101,34)],0xC0AF91FF)
        // Fixed asymmetrical glaze flecks belong to the one whole source;
        // partitioning can never generate independently drifting rim details.
        for point in [(22.0,29.0),(37,32),(93,31),(108,28)] {
            c.line([point,(point.0+1,point.1)],0x7E7966FF)
        }
        return c.image
    }()

    private static let basinRear=partition(front:false)
    private static let basinFront=partition(front:true)

    private static func partition(front:Bool)->CGImage {
        let source=basinWhole,width=source.width,height=source.height,stride=source.bytesPerRow
        // Copy raw top-down image rows instead of redrawing/cropping CGImage:
        // this avoids a second interpolation pass or a front/rear y-flip.
        let data=source.dataProvider!.data!
        let raw=CFDataGetBytePtr(data)!
        var bytes=[UInt8](repeating:0,count:stride*height)
        let wall=frontOcclusionPath.copy(strokingWithWidth:1,lineCap:.round,lineJoin:.round,miterLimit:1)
        let fill=frontOcclusionPath
        for y in 0..<height {for x in 0..<width {
            let sample=CGPoint(x:Double(x)+0.5,y:Double(y)+0.5)
            let isFront=fill.contains(sample) || wall.contains(sample)
            if isFront == front {
                let offset=y*stride+x*4
                for c in 0..<4 {bytes[offset+c]=raw[offset+c]}
            }
        }}
        let provider=CGDataProvider(data:Data(bytes) as CFData)!
        return CGImage(width:width,height:height,bitsPerComponent:source.bitsPerComponent,
                       bitsPerPixel:source.bitsPerPixel,bytesPerRow:stride,space:source.colorSpace!,
                       bitmapInfo:source.bitmapInfo,provider:provider,decode:nil,
                       shouldInterpolate:false,intent:.defaultIntent)!
    }

    private static let splashes:[CGImage]=(0..<4).map { phase in
        let c=Painter(width:24,height:24)
        let water:UInt32=0x75B9C8FF,light:UInt32=0xD6EEDFFF,shadow:UInt32=0x4B8FADFF
        switch phase {
        case 0:
            c.poly([(4,21),(7,19),(7,16),(10,19),(12,13),(14,19),
                    (17,16),(17,19),(20,21),(15,22),(9,22)],water)
            c.line([(7,20),(10,21),(15,21),(18,20)],light)
            c.line([(11,18),(12,15),(13,18)],light)
            c.oval(CGRect(x:4,y:16,width:2,height:2),water)
            c.oval(CGRect(x:18,y:14,width:2,height:2),light)
        case 1:
            c.poly([(3,21),(7,17),(5,10),(7,9),(11,17),(12,8),(14,17),
                    (19,9),(20,11),(17,19),(21,21),(16,22),(8,22)],water)
            c.line([(7,12),(10,19),(12,20),(14,19),(18,12)],light)
            c.line([(5,22),(10,23),(15,23),(20,22)],shadow)
            c.oval(CGRect(x:2,y:6,width:2,height:3),water)
            c.oval(CGRect(x:10,y:3,width:2,height:3),light)
            c.oval(CGRect(x:20,y:5,width:2,height:3),water)
        case 2:
            for drop in [(3.0,12.0,2.0,3.0),(7,7,2,4),(12,10,2,3),(18,8,2,4),(20,15,2,2)] {
                c.oval(CGRect(x:drop.0,y:drop.1,width:drop.2,height:drop.3),water)
                c.line([(drop.0,drop.1),(drop.0,drop.1+1)],light)
            }
            c.line([(4,21),(8,20),(11,21),(14,20),(19,21)],light)
            c.line([(5,22),(10,23),(16,23),(20,22)],water)
        default:
            c.line([(3,20),(7,19),(10,19)],water)
            c.line([(15,19),(19,19),(22,20)],water)
            c.line([(3,22),(8,23),(16,23),(21,22)],shadow)
            c.line([(6,21),(10,22),(15,22),(18,21)],light)
            c.oval(CGRect(x:6,y:16,width:2,height:2),light)
            c.oval(CGRect(x:17,y:17,width:2,height:2),water)
        }
        return c.image
    }

    private final class Painter {
        let ctx:CGContext
        init(width:Int,height:Int) {
            ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                          space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setShouldAntialias(false);ctx.translateBy(x:0,y:CGFloat(height));ctx.scaleBy(x:1,y:-1)
            ctx.setLineJoin(.round);ctx.setLineCap(.round)
        }
        private func color(_ value:UInt32)->CGColor {
            CGColor(red:CGFloat((value>>24)&255)/255,green:CGFloat((value>>16)&255)/255,
                    blue:CGFloat((value>>8)&255)/255,alpha:CGFloat(value&255)/255)
        }
        func poly(_ points:[(Double,Double)],_ value:UInt32,outline:Bool=false) {
            ctx.addPath(BathArt.polygon(points));ctx.setFillColor(color(value))
            ctx.setStrokeColor(color(0x4B554EFF));ctx.setLineWidth(1)
            ctx.drawPath(using:outline ? .fillStroke:.fill)
        }
        func oval(_ rect:CGRect,_ value:UInt32,outline:Bool=false) {
            ctx.addEllipse(in:rect);ctx.setFillColor(color(value))
            ctx.setStrokeColor(color(0x4B554EFF));ctx.setLineWidth(1)
            ctx.drawPath(using:outline ? .fillStroke:.fill)
        }
        func line(_ points:[(Double,Double)],_ value:UInt32) {
            guard let first=points.first else {return}
            ctx.beginPath();ctx.move(to:CGPoint(x:first.0,y:first.1))
            for p in points.dropFirst() {ctx.addLine(to:CGPoint(x:p.0,y:p.1))}
            ctx.setStrokeColor(color(value));ctx.setLineWidth(1);ctx.strokePath()
        }
        var image:CGImage {ctx.makeImage()!}
    }
}
