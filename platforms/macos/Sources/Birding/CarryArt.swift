import AppKit
import BirdingCore

/// One independent 16x16 leaf token. Draw at 16*worldScale, including while
/// attached; switching carrier never changes its physical size. Grip and ground
/// support both use y12. Keep rotation=0 during pickup/place, mirror horizontally
/// for a left-facing carrier, and preserve the world transform on detach.
enum CarryArt {
    static let leafLogicalSize=CarryArtGeometry.leafLogicalSize
    static let leafGripAnchor=CarryArtGeometry.leafGripAnchor
    static let leafSurfaceAnchor=CarryArtGeometry.leafSurfaceAnchor

    /// Complete silhouette including the dark border. No centered outline
    /// stroke extends the square-cut stem or the blade's support below y12.
    static var leafOutlinePath:CGPath {
        let p=CGMutablePath(),vertices=CarryArtGeometry.leafOutlineVertices
        p.move(to:vertices[0])
        for v in vertices.dropFirst() {p.addLine(to:v)}
        p.closeSubpath();return p
    }
    static func leafImage()->CGImage {leaf}

    private static let leaf:CGImage = {
        let width=Int(leafLogicalSize.width),height=Int(leafLogicalSize.height)
        let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setShouldAntialias(false);c.translateBy(x:0,y:CGFloat(height));c.scaleBy(x:1,y:-1)
        c.setLineJoin(.round);c.setLineCap(.round)
        func color(_ v:UInt32)->CGColor {
            CGColor(red:CGFloat((v>>24)&255)/255,green:CGFloat((v>>16)&255)/255,
                    blue:CGFloat((v>>8)&255)/255,alpha:1)
        }
        func poly(_ points:[(Double,Double)],_ fill:UInt32) {
            c.beginPath();c.move(to:CGPoint(x:points[0].0,y:points[0].1))
            for p in points.dropFirst() {c.addLine(to:CGPoint(x:p.0,y:p.1))}
            c.closePath();c.setFillColor(color(fill));c.fillPath()
        }
        func line(_ points:[(Double,Double)],_ fill:UInt32,width:CGFloat=1) {
            c.beginPath();c.move(to:CGPoint(x:points[0].0,y:points[0].1))
            for p in points.dropFirst() {c.addLine(to:CGPoint(x:p.0,y:p.1))}
            c.setStrokeColor(color(fill));c.setLineWidth(width);c.strokePath()
        }
        c.addPath(leafOutlinePath);c.setFillColor(color(0x4C6047FF));c.fillPath()
        // All detail is clipped to the filled border. Even round vein caps
        // cannot add a pixel below either of the two y12 contact anchors.
        c.saveGState();c.addPath(leafOutlinePath);c.clip()
        poly([(6,8),(6,6),(8,4),(10,3),(13,3),(13,6),(12,8),
              (10,10.5),(8,9.8)],0x89975DFF)
        poly([(7,6),(9,4),(12,3),(12,5),(10,7),(8,9)],0xB6BB70FF)
        poly([(9,9),(12,6),(13,4),(12,8),(10,11)],0x6D824CFF)
        // The blunt stem's lower edge is y12 across x2...4; grip(3,12)
        // is an actual painted boundary, rather than an invisible offset.
        poly([(2,11),(5.5,8),(6.5,8.8),(4,12),(2,12)],0x9B8353FF)
        line([(3,11.4),(7,8),(10,5.5),(12,3.8)],0xD0CA82FF,width:0.7)
        line([(7,8),(7,5.7)],0x6B7F4BFF,width:0.6)
        line([(8.5,6.8),(11.5,7.1)],0x6B7F4BFF,width:0.6)
        line([(10,5.5),(10,3.5)],0xE0D68DFF,width:0.6)
        c.restoreGState()
        return c.makeImage()!
    }()
}
