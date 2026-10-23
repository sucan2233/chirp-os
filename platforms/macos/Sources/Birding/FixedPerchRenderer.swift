import AppKit
import BirdingCore

/// The source asset is kept unchanged. At load time, trim transparent padding
/// and locate the central rail from real alpha, so feet meet wood at every scale.
final class FixedPerchArt {
    static let shared=FixedPerchArt()
    let image:CGImage
    let railY:CGFloat
    private init?() {
        guard let url=ScenePropAssets.fixedPerchURL,
              let raw=NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let ctx=CGContext(data:nil,width:raw.width,height:raw.height,bitsPerComponent:8,bytesPerRow:raw.width*4,
                  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return nil}
        ctx.draw(raw,in:CGRect(x:0,y:0,width:raw.width,height:raw.height))
        guard let data=ctx.data else {return nil}
        let bytes=data.bindMemory(to:UInt8.self,capacity:raw.width*raw.height*4)
        var left=raw.width,right=0,top=raw.height,bottom=0
        for y in 0..<raw.height {for x in 0..<raw.width where bytes[(y*raw.width+x)*4+3]>=32 {
            left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)
        }}
        guard right>left,bottom>top else {return nil}
        let center=(left+right)/2
        guard let rail=(top...bottom).first(where:{bytes[($0*raw.width+center)*4+3]>=128}),
              let cropped=raw.cropping(to:CGRect(x:left,y:top,width:right-left+1,height:bottom-top+1)) else {return nil}
        image=cropped;railY=CGFloat(rail-top)
    }
    func rect(for perch:ResolvedFixedPerch)->CGRect {
        let ratio=perch.rect.width/CGFloat(image.width)
        return CGRect(x:perch.rect.minX,y:perch.foot.y-railY*ratio,
                      width:perch.rect.width,height:CGFloat(image.height)*ratio)
    }
}

final class FixedPerchRenderer {
    private var layers:[Int:CALayer]=[:]
    func update(_ perches:[ResolvedFixedPerch],world:BehaviorWorld,on root:CALayer,desktopRect:CGRect) {
        let live=Set(perches.map(\.slot))
        for slot in Array(layers.keys) where !live.contains(slot) {layers.removeValue(forKey:slot)?.removeFromSuperlayer()}
        guard let art=FixedPerchArt.shared else {
            for layer in layers.values {layer.isHidden=true};return
        }
        for perch in perches {
            let container:CALayer
            if let existing=layers[perch.slot] {container=existing}
            else {
                container=CALayer();container.name="fixed-perch-\(perch.slot)";container.zPosition = -1
                let texture=CALayer();texture.magnificationFilter = .nearest;texture.minificationFilter = .nearest
                texture.contents=art.image;texture.mask=CAShapeLayer();container.addSublayer(texture)
                root.addSublayer(container);layers[perch.slot]=container
            }
            let rect=art.rect(for:perch)
            let blockers=Geometry.blockers(on:perch.surface,surfaces:world.surfaces).map(\.rect)
            let pieces=Geometry.visiblePieces(rect,blockers:blockers)
            container.isHidden = !rect.intersects(desktopRect) || pieces.isEmpty
            guard !container.isHidden else {continue}
            container.frame=rect.offsetBy(dx:-desktopRect.minX,dy:-desktopRect.minY)
            let texture=container.sublayers![0];texture.frame=CGRect(origin:.zero,size:rect.size)
            let mask=texture.mask as! CAShapeLayer,path=CGMutablePath()
            for piece in pieces {path.addRect(piece.offsetBy(dx:-rect.minX,dy:-rect.minY))}
            mask.frame=texture.bounds;mask.path=path;mask.fillColor=NSColor.black.cgColor
        }
    }
}
