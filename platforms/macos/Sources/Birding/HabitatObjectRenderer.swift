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
    static var bathArtAvailable:Bool {
        BathArt.image().width==128 && BathArt.image().height==40 &&
            BathGeometry.splashFrameNames.allSatisfy{BathArt.splashImage($0) != nil}
    }
    private var objects:[UInt64:CALayer]=[:]
    private var baths:[UInt64:(rear:CALayer,front:CALayer)]=[:]

    /// Preserve window occlusion in one renderable mask. A mask with its own
    /// mask can disappear during native layer composition; subtract both holes
    /// from the visible path instead, including their overlapping area once.
    static func applyImmersion(_ state:BathImmersionState?,to mask:CAShapeLayer,birdRect:CGRect) {
        mask.mask=nil;mask.fillRule = .nonZero
        guard let state,let visible=mask.path else {return}
        let water=state.waterRect.offsetBy(dx:-birdRect.minX,dy:-birdRect.minY)
        // The waterline itself is retained (strict y > line). A subpixel
        // epsilon excludes the contact boundary without raising a visible strip.
        let line=state.waterlineY-birdRect.minY+0.000001
        let waterHole=CGMutablePath()
        if water.width>0,water.height>0,line<water.maxY {
            if line<=water.minY {waterHole.addEllipse(in:water)}
            else {
                let angle=asin(min(1,max(-1,(line-water.midY)/(water.height/2))))
                let transform=CGAffineTransform(a:water.width/2,b:0,c:0,d:water.height/2,tx:water.midX,ty:water.midY)
                let lower=CGMutablePath()
                lower.addArc(center:.zero,radius:1,startAngle:angle,endAngle:.pi-angle,clockwise:false,transform:transform)
                lower.closeSubpath();waterHole.addPath(lower)
            }
        }
        let feetHole=CGPath(rect:state.feetRect.offsetBy(dx:-birdRect.minX,dy:-birdRect.minY),transform:nil)
        mask.path=visible.subtracting(waterHole).subtracting(feetHole)
    }

    func update(_ snapshot:[HabitatObjectRenderState],on root:CALayer,desktopRect:CGRect) {
        updateBaths(snapshot.filter{$0.kind == .bath},on:root,desktopRect:desktopRect)
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

    private func updateBaths(_ snapshot:[HabitatObjectRenderState],on root:CALayer,desktopRect:CGRect) {
        let live=Set(snapshot.map{$0.id.rawValue})
        for id in Array(baths.keys) where !live.contains(id) {
            let removed=baths.removeValue(forKey:id);removed?.rear.removeFromSuperlayer();removed?.front.removeFromSuperlayer()
        }
        for bath in snapshot {
            let layers:(rear:CALayer,front:CALayer)
            if let existing=baths[bath.id.rawValue] {layers=existing}
            else {
                func make(_ name:String,_ image:CGImage,_ z:CGFloat)->CALayer {
                    let layer=CALayer();layer.name="habitat-bath-\(name)-\(bath.id.rawValue)";layer.zPosition=z
                    let texture=CALayer();texture.contents=image
                    texture.magnificationFilter = .nearest;texture.minificationFilter = .nearest
                    layer.addSublayer(texture);layer.mask=CAShapeLayer();root.addSublayer(layer);return layer
                }
                layers=(make("rear",BathArt.image(layer:.rear),-0.5),make("front",BathArt.image(layer:.front),0.5))
                baths[bath.id.rawValue]=layers
            }
            let rect=bath.rect,pieces=Geometry.visiblePieces(rect,blockers:bath.blockers)
            for layer in [layers.rear,layers.front] {
                layer.isHidden = !Self.bathArtAvailable || !rect.intersects(desktopRect) || pieces.isEmpty
                guard !layer.isHidden else {continue}
                layer.frame=rect.offsetBy(dx:-desktopRect.minX,dy:-desktopRect.minY)
                layer.sublayers![0].frame=CGRect(origin:.zero,size:rect.size)
                let path=CGMutablePath()
                for piece in pieces {path.addRect(piece.offsetBy(dx:-rect.minX,dy:-rect.minY))}
                let mask=layer.mask as! CAShapeLayer;mask.frame=layer.bounds
                mask.path=path;mask.fillColor=NSColor.black.cgColor
            }
        }
    }
}
