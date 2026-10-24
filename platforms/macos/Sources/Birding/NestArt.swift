import AppKit
import BirdingCore

/// Six delivered assets. Stock and loose delivered twigs are separate instances
/// of twigImage; neither is baked into the tray or any progress overlay.
enum NestArt {
    static func image()->CGImage {platform}
    static func trayImage()->CGImage {tray}
    static func twigImage()->CGImage {twig}
    static func overlayImage(progress:Int)->CGImage? {
        guard (1...3).contains(progress) else {return nil}
        return overlays[progress-1]
    }
    static var twigPath:CGPath {path(TwigGeometry.polygon)}
    private static func path(_ points:[CGPoint])->CGPath {
        let p=CGMutablePath();guard let first=points.first else {return p}
        p.move(to:first);for point in points.dropFirst() {p.addLine(to:point)};p.closeSubpath();return p
    }
    private static func context(_ size:CGSize)->CGContext {
        let width=Int(size.width),height=Int(size.height)
        let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setShouldAntialias(false);c.translateBy(x:0,y:CGFloat(height));c.scaleBy(x:1,y:-1)
        c.setLineCap(.butt);c.setLineJoin(.round);return c
    }
    private static func color(_ value:UInt32)->CGColor {
        CGColor(red:CGFloat((value>>16)&255)/255,green:CGFloat((value>>8)&255)/255,
                blue:CGFloat(value&255)/255,alpha:1)
    }
    private static func poly(_ c:CGContext,_ points:[CGPoint],_ value:UInt32) {
        c.addPath(path(points));c.setFillColor(color(value));c.fillPath()
    }
    private static func line(_ c:CGContext,_ points:[CGPoint],_ value:UInt32,width:CGFloat=1) {
        guard let first=points.first else {return}
        c.beginPath();c.move(to:first);for point in points.dropFirst() {c.addLine(to:point)}
        c.setStrokeColor(color(value));c.setLineWidth(width);c.strokePath()
    }
    private static let twig:CGImage = {
        let c=context(TwigGeometry.logicalSize)
        c.addPath(twigPath);c.setFillColor(color(0x574A40));c.fillPath()
        c.saveGState();c.addPath(twigPath);c.clip()
        line(c,[CGPoint(x:0,y:11),CGPoint(x:6,y:11),CGPoint(x:10,y:11),CGPoint(x:16,y:11)],0xAD8D66,width:0.8)
        line(c,[CGPoint(x:4,y:8),CGPoint(x:6,y:11)],0xAD8D66,width:0.7)
        line(c,[CGPoint(x:12,y:8),CGPoint(x:10,y:11)],0xAD8D66,width:0.7)
        line(c,[CGPoint(x:8,y:7),CGPoint(x:8,y:11)],0xAD8D66,width:0.8)
        c.restoreGState();return c.makeImage()!
    }()
    private static let platform:CGImage = {
        let c=context(NestArtGeometry.nestSize)
        // Flat y24 load-bearing top, backed by a shallow wooden support. The
        // underside reaches y48, so placement must check the complete canvas.
        poly(c,[CGPoint(x:8,y:24),CGPoint(x:136,y:24),CGPoint(x:141,y:28),CGPoint(x:136,y:33),
                CGPoint(x:8,y:33),CGPoint(x:3,y:28)],0x574A40)
        poly(c,[CGPoint(x:8,y:25),CGPoint(x:136,y:25),CGPoint(x:138,y:28),CGPoint(x:134,y:30),
                CGPoint(x:10,y:30),CGPoint(x:6,y:28)],0xAD8D66)
        line(c,[CGPoint(x:12,y:27),CGPoint(x:130,y:27)],0xD3B58A)
        line(c,[CGPoint(x:22,y:30),CGPoint(x:57,y:30),CGPoint(x:65,y:29)],0x806350)
        line(c,[CGPoint(x:83,y:29),CGPoint(x:121,y:29)],0x806350)
        for x:CGFloat in [30,110] {
            poly(c,[CGPoint(x:x-5,y:32),CGPoint(x:x+5,y:32),CGPoint(x:x+4,y:48),CGPoint(x:x-4,y:48)],0x574A40)
            poly(c,[CGPoint(x:x-3,y:33),CGPoint(x:x+2,y:33),CGPoint(x:x+2,y:48),CGPoint(x:x-2,y:48)],0x806350)
        }
        line(c,[CGPoint(x:40,y:33),CGPoint(x:48,y:43),CGPoint(x:97,y:43),CGPoint(x:104,y:33)],0x806350,width:2)
        return c.makeImage()!
    }()
    private static let tray:CGImage = {
        let c=context(NestArtGeometry.traySize)
        // Rim stays beneath the y12 contact plane. Empty tray remains empty
        // after the last atomic pickup; materials are always external tokens.
        poly(c,[CGPoint(x:2,y:12),CGPoint(x:30,y:12),CGPoint(x:32,y:14),CGPoint(x:29,y:16),
                CGPoint(x:3,y:16),CGPoint(x:0,y:14)],0x574A40)
        poly(c,[CGPoint(x:3,y:12),CGPoint(x:29,y:12),CGPoint(x:30,y:14),CGPoint(x:2,y:14)],0xAD8D66)
        line(c,[CGPoint(x:5,y:13),CGPoint(x:27,y:13)],0xD3B58A,width:0.7)
        return c.makeImage()!
    }()
    private static let overlays:[CGImage]=(1...3).map {progress in
        let c=context(NestArtGeometry.nestSize)
        // Compact shallow twig platform. Ink never rises above y14 and never
        // changes the y24 foot/contact plane. Each stage is a complete overlay,
        // not an accumulating set of old bitmaps or a count of loose materials.
        let sticks:[(CGPoint,CGPoint)]=[
            (CGPoint(x:50,y:23),CGPoint(x:84,y:21)),(CGPoint(x:60,y:20),CGPoint(x:96,y:23)),
            (CGPoint(x:55,y:18),CGPoint(x:88,y:23)),(CGPoint(x:47,y:22),CGPoint(x:76,y:18)),
            (CGPoint(x:66,y:23),CGPoint(x:101,y:19)),(CGPoint(x:58,y:16),CGPoint(x:91,y:22)),
            (CGPoint(x:43,y:21),CGPoint(x:81,y:16)),(CGPoint(x:70,y:19),CGPoint(x:104,y:23)),
            (CGPoint(x:49,y:23),CGPoint(x:72,y:15)),(CGPoint(x:78,y:15),CGPoint(x:98,y:23)),
            (CGPoint(x:55,y:19),CGPoint(x:92,y:18)),(CGPoint(x:62,y:22),CGPoint(x:86,y:15))]
        let count=progress == 1 ? 3:(progress == 2 ? 7:12)
        c.saveGState();c.clip(to:CGRect(x:40,y:14,width:66,height:10))
        for (index,stick) in sticks.prefix(count).enumerated() {
            line(c,[stick.0,stick.1],0x574A40,width:1.7)
            line(c,[CGPoint(x:stick.0.x,y:stick.0.y-0.35),CGPoint(x:stick.1.x,y:stick.1.y-0.35)],
                index%2 == 0 ? 0xAD8D66:0x806350,width:0.8)
        }
        c.restoreGState();return c.makeImage()!
    }
}
