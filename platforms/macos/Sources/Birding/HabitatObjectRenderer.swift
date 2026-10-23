import AppKit
import BirdingCore

/// Keep the source artwork intact and derive its visible crop from real alpha.
/// The seed plane is 36% down that crop, below the opaque rear rim.
final class FoodTrayArt {
    static let shared=FoodTrayArt()
    let image:CGImage
    let contactY:CGFloat
    let sourceAlphaBounds:CGRect
    let sourceSize:CGSize
    private init?() {
        guard let url=ScenePropAssets.foodTrayURL,
              let raw=NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let context=CGContext(data:nil,width:raw.width,height:raw.height,bitsPerComponent:8,bytesPerRow:raw.width*4,
                  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return nil}
        context.draw(raw,in:CGRect(x:0,y:0,width:raw.width,height:raw.height))
        guard let data=context.data else {return nil}
        let bytes=data.bindMemory(to:UInt8.self,capacity:raw.width*raw.height*4)
        var left=raw.width,right=0,top=raw.height,bottom=0
        for y in 0..<raw.height {for x in 0..<raw.width where bytes[(y*raw.width+x)*4+3]>=32 {
            left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)
        }}
        guard right>left,bottom>top else {return nil}
        let crop=CGRect(x:left,y:top,width:right-left+1,height:bottom-top+1)
        guard let cropped=raw.cropping(to:crop) else {return nil}
        image=cropped;sourceAlphaBounds=crop;sourceSize=CGSize(width:raw.width,height:raw.height)
        // For the approved 2167×726 sprite this is source y≈383, on the seeds.
        // The first opaque central pixel is the rear dish rim, not bird contact.
        contactY=(CGFloat(bottom-top)*0.36).rounded()
    }
    /// Engine rect is a logical 128×24 footprint. Its midX/minY is the foot
    /// anchor, not the top of the image's transparent canvas or raised rim.
    func rect(for footprint:CGRect) -> CGRect {
        let ratio=footprint.width/CGFloat(image.width)
        return CGRect(x:footprint.midX-footprint.width/2,y:footprint.minY-contactY*ratio,
                      width:footprint.width,height:CGFloat(image.height)*ratio)
    }
}

/// Presentation only: placement, portions, expiry and safe retirement belong
/// to the engine. Window occlusion comes from the same snapshot as the object.
final class HabitatObjectRenderer {
    static var foodTrayArtAvailable:Bool {FoodTrayArt.shared != nil}
    private var objects:[UInt64:CALayer]=[:]

    func update(_ snapshot:[HabitatObjectRenderState],on root:CALayer,desktopRect:CGRect) {
        let trays=snapshot.filter{$0.kind == .foodTray}
        let live=Set(trays.map{$0.id.rawValue})
        for id in Array(objects.keys) where !live.contains(id) {objects.removeValue(forKey:id)?.removeFromSuperlayer()}
        guard let art=FoodTrayArt.shared else {
            for layer in objects.values {layer.isHidden=true};return
        }
        for tray in trays {
            let container:CALayer
            if let existing=objects[tray.id.rawValue] {container=existing}
            else {
                container=CALayer();container.name="habitat-food-tray-\(tray.id.rawValue)"
                container.zPosition = -0.5
                let texture=CALayer();texture.contents=art.image
                texture.magnificationFilter = .nearest;texture.minificationFilter = .nearest
                container.addSublayer(texture);container.mask=CAShapeLayer()
                root.addSublayer(container);objects[tray.id.rawValue]=container
            }
            let rect=art.rect(for:tray.rect)
            let pieces=Geometry.visiblePieces(rect,blockers:tray.blockers)
            container.isHidden = !rect.intersects(desktopRect) || pieces.isEmpty
            guard !container.isHidden else {continue}
            container.frame=rect.offsetBy(dx:-desktopRect.minX,dy:-desktopRect.minY)
            container.sublayers![0].frame=CGRect(origin:.zero,size:rect.size)
            let path=CGMutablePath()
            for piece in pieces {path.addRect(piece.offsetBy(dx:-rect.minX,dy:-rect.minY))}
            let mask=container.mask as! CAShapeLayer
            mask.frame=container.bounds;mask.path=path;mask.fillColor=NSColor.black.cgColor
        }
    }
}
