import AppKit
import BirdingCore

/// Rendering-only adapter. Lifetime and motion are owned by BehaviorRuntime;
/// no mouse handlers or animation timers live in this layer.
final class ScenePropRenderer {
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
            // The unrotated clipping envelope accommodates every leaf angle.
            let side=prop.size*sqrt(2.0)
            let rect=CGRect(x:prop.position.x-side/2,y:prop.position.y-side/2,width:side,height:side)
            let pieces=Geometry.visiblePieces(rect,blockers:prop.blockers)
            container.isHidden = !rect.intersects(desktopRect) || pieces.isEmpty || prop.opacity<=0
            container.opacity=Float(min(1,max(0,prop.opacity)))
            guard !container.isHidden else {continue}
            container.frame=rect.offsetBy(dx:-desktopRect.minX,dy:-desktopRect.minY)
            let texture=container.sublayers![0]
            texture.bounds=CGRect(x:0,y:0,width:prop.size,height:prop.size)
            texture.position=CGPoint(x:side/2,y:side/2)
            texture.setAffineTransform(CGAffineTransform(rotationAngle:prop.rotation))
            texture.contents=leafTexture
            let path=CGMutablePath()
            for piece in pieces {path.addRect(piece.offsetBy(dx:-rect.minX,dy:-rect.minY))}
            let mask=container.mask as! CAShapeLayer
            mask.frame=CGRect(origin:.zero,size:rect.size);mask.path=path;mask.fillColor=NSColor.black.cgColor
        }
    }
}
