import AppKit
import BirdingCore

/// Rendering-only adapter. Lifetime and motion are owned by BehaviorRuntime;
/// no mouse handlers or animation timers live in this layer.
final class ScenePropRenderer {
    static var leafCarryArtAvailable:Bool {CarryArt.leafImage().width==16 && CarryArt.leafImage().height==16}
    static var insectArtAvailable:Bool {InsectArt.frameNames.allSatisfy {
        guard let image=InsectArt.image($0) else {return false}
        return image.width==Int(InsectArt.logicalSize.width) && image.height==Int(InsectArt.logicalSize.height)
    }}
    private var props:[ScenePropID:CALayer]=[:]
    private lazy var leafTexture:CGImage? = ScenePropAssets.leafURL.flatMap {url in
        NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil)
    }
    func update(_ snapshot:[ScenePropRenderState],on root:CALayer,desktopRect:CGRect) {
        let live=Set(snapshot.map(\.id))
        for id in Array(props.keys) where !live.contains(id) {props.removeValue(forKey:id)?.removeFromSuperlayer()}
        for prop in snapshot {
            let container:CALayer
            if let existing=props[prop.id] {container=existing}
            else {
                container=CALayer();container.name="scene-prop-\(prop.id.rawValue)"
                let texture=CALayer();texture.magnificationFilter = .nearest;texture.minificationFilter = .nearest
                container.addSublayer(texture);container.mask=CAShapeLayer()
                root.addSublayer(container);props[prop.id]=container
            }
            // Carry leaves use the engine's exact transformed AABB and raw
            // grip anchor. The original moving leaf retains its old envelope.
            let splash=prop.kind == .waterSplash
            let carry=prop.kind == .leafToken
            let insect=prop.kind == .insect
            let anchored=splash || carry || insect
            let side=anchored ? prop.size:prop.size*sqrt(2.0)
            let rect=anchored ? prop.rect:CGRect(x:prop.position.x-side/2,y:prop.position.y-side/2,width:side,height:side)
            container.zPosition=anchored ? 1:0
            let pieces=Geometry.visiblePieces(rect,blockers:prop.blockers)
            container.isHidden = !rect.intersects(desktopRect) || pieces.isEmpty || prop.opacity<=0
            container.opacity=Float(min(1,max(0,prop.opacity)))
            guard !container.isHidden else {continue}
            container.frame=rect.offsetBy(dx:-desktopRect.minX,dy:-desktopRect.minY)
            let texture=container.sublayers![0]
            texture.bounds=CGRect(x:0,y:0,width:prop.size,height:prop.size)
            texture.anchorPoint=prop.anchor
            texture.position=anchored ? CGPoint(x:prop.position.x-rect.minX,y:prop.position.y-rect.minY):CGPoint(x:side/2,y:side/2)
            // Mirror in raw artwork coordinates about anchor, then rotate.
            let c=cos(prop.rotation),s=sin(prop.rotation),m:CGFloat=(carry || insect) && prop.mirrored ? -1:1
            texture.setAffineTransform(CGAffineTransform(a:c*m,b:s*m,c:-s,d:c,tx:0,ty:0))
            texture.contents=insect ? InsectArt.image(prop.frameName):(carry ? CarryArt.leafImage():(splash ? BathArt.splashImage(prop.frameName):leafTexture))
            container.isHidden = container.isHidden || texture.contents==nil
            let path=CGMutablePath()
            for piece in pieces {path.addRect(piece.offsetBy(dx:-rect.minX,dy:-rect.minY))}
            let mask=container.mask as! CAShapeLayer
            mask.frame=CGRect(origin:.zero,size:rect.size);mask.path=path;mask.fillColor=NSColor.black.cgColor
        }
    }
}
