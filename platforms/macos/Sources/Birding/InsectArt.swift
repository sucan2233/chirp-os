import AppKit
import BirdingCore

/// One independent world-scaled insect. Four wing phases share the actual
/// thorax center; collision radius is deliberately independent of wing extent.
enum InsectArt {
    static let frameNames=CatchArtGeometry.insectFrameNames
    static let logicalSize=CatchArtGeometry.insectLogicalSize
    static let anchor=CatchArtGeometry.insectAnchor
    static let collisionRadius=CatchArtGeometry.insectCollisionRadius
    static let frameDuration=CatchArtGeometry.insectFrameDuration
    static func image(_ frame:String)->CGImage? {images[frame]}

    private static let images:[String:CGImage]=Dictionary(uniqueKeysWithValues:frameNames.map {name in
        let pose=CatchArtGeometry.insectPose(frame:name)!
        let width=Int(logicalSize.width),height=Int(logicalSize.height)
        let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setShouldAntialias(false);c.translateBy(x:0,y:CGFloat(height));c.scaleBy(x:1,y:-1)
        c.setLineJoin(.round);c.setLineCap(.round)
        func color(_ value:UInt32)->CGColor {
            CGColor(red:CGFloat((value>>24)&255)/255,green:CGFloat((value>>16)&255)/255,
                blue:CGFloat((value>>8)&255)/255,alpha:CGFloat(value&255)/255)
        }
        func polygon(_ vertices:[CGPoint],fill:UInt32) {
            c.beginPath();c.move(to:vertices[0]);for p in vertices.dropFirst(){c.addLine(to:p)};c.closePath()
            c.setFillColor(color(fill));c.fillPath()
        }
        func line(_ vertices:[CGPoint],color value:UInt32,width:CGFloat=0.65) {
            c.beginPath();c.move(to:vertices[0]);for p in vertices.dropFirst(){c.addLine(to:p)}
            c.setStrokeColor(color(value));c.setLineWidth(width);c.strokePath()
        }
        // Muted blue-gray wings stay legible on both bright and dark windows.
        polygon(pose.farWing,fill:0x829A9DFF)
        polygon(pose.nearWing,fill:0xC8D8CEFF)
        line([CGPoint(x:8,y:8),pose.farWing[1]],color:0x597573FF,width:0.55)
        line([CGPoint(x:8,y:8),pose.nearWing[1]],color:0x829A87FF,width:0.55)
        line([CGPoint(x:7,y:8.7),CGPoint(x:5.2,y:10.8)],color:0x414E44FF)
        line([CGPoint(x:8.6,y:8.8),CGPoint(x:9.6,y:10.5)],color:0x414E44FF)
        c.setFillColor(color(0x414E44FF));c.fillEllipse(in:CGRect(x:6,y:6.5,width:4,height:3))
        c.setFillColor(color(0x8F9A56FF));c.fillEllipse(in:CGRect(x:6.8,y:7,width:2.6,height:1.5))
        c.setFillColor(color(0x303D39FF));c.fillEllipse(in:CGRect(x:9.3,y:7,width:1.5,height:2))
        c.setFillColor(color(0xE5D89DFF));c.fill(CGRect(x:9.8,y:7.2,width:0.6,height:0.6))
        line([CGPoint(x:10.4,y:7.3),CGPoint(x:11.6,y:6.2)],color:0x414E44FF,width:0.55)
        return (name,c.makeImage()!)
    })
}
