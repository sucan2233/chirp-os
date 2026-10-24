import Foundation
import CoreGraphics

/// 放置与材料几何共用素材坐标；尺寸只乘world scale，不乘携带鸟的相对大小。
public enum NestGeometry {
    public static let size=NestArtGeometry.nestSize
    public static let contactY=NestArtGeometry.nestContactY
    public static let traySize=NestArtGeometry.traySize
    public static let trayContactY=NestArtGeometry.trayContactY
    public static let trayOffset=NestArtGeometry.trayOffset
    public static let fadeDuration=0.2
    public static let lifetime=900.0

    public static func rect(foot:CGPoint,scale:CGFloat)->CGRect {
        CGRect(x:foot.x-NestArtGeometry.nestAnchor.x*scale,y:foot.y-contactY*scale,
               width:size.width*scale,height:size.height*scale)
    }
    public static func trayRect(foot:CGPoint,scale:CGFloat,side:Int)->CGRect {
        CGRect(x:foot.x+CGFloat(side)*trayOffset*scale-NestArtGeometry.trayAnchor.x*scale,
               y:foot.y-trayContactY*scale,width:traySize.width*scale,height:traySize.height*scale)
    }
    public static func materialPoint(slot:Int,rect:CGRect,scale:CGFloat)->CGPoint? {
        guard NestArtGeometry.materialPoints.indices.contains(slot) else {return nil}
        let p=NestArtGeometry.materialPoints[slot]
        return CGPoint(x:rect.minX+p.x*scale,y:rect.minY+p.y*scale)
    }
    public static func trayMaterialPoint(slot:Int,rect:CGRect,scale:CGFloat)->CGPoint? {
        guard NestArtGeometry.trayMaterialPoints.indices.contains(slot) else {return nil}
        let p=NestArtGeometry.trayMaterialPoints[slot]
        return CGPoint(x:rect.minX+p.x*scale,y:rect.minY+p.y*scale)
    }
    public static func render(id:ScenePropID,position:CGPoint,worldScale:CGFloat,
                              anchor:CGPoint=TwigGeometry.grip,facingRight:Bool=true,
                              rotation:CGFloat=0,opacity:Double=1,blockers:[CGRect]=[]) -> ScenePropRenderState {
        var value=ScenePropRenderState(id:id,kind:.twigToken,position:position,
            size:TwigGeometry.logicalSize.width*worldScale,rotation:rotation,opacity:opacity,
            blockers:blockers,frameName:"twigToken",
            anchor:CGPoint(x:anchor.x/TwigGeometry.logicalSize.width,y:anchor.y/TwigGeometry.logicalSize.height))
        value.mirrored = !facingRight;return value
    }
    static func supported(foot:CGPoint,nest:CGRect,tray:CGRect,host:Surface,world:BehaviorWorld,
                          display:CGRect) -> Bool {
        let group=nest.union(tray)
        guard SurfaceAnchor.finite(group),display.contains(group),
              host.rect.minX<=group.minX,host.rect.maxX>=group.maxX else {return false}
        // ground允许画布尾部越过Dock工作区下沿，但必须完整落在同一物理屏内。
        let workArea=world.screens.contains {screen in
            guard screen.minX>=display.minX-0.001,screen.maxX<=display.maxX+0.001,
                  screen.minY>=display.minY-0.001,screen.maxY<=display.maxY+0.001 else {return false}
            return host.isGround ? group.minX>=screen.minX && group.maxX<=screen.maxX && group.minY>=screen.minY:
                screen.contains(group)
        }
        return workArea && !Geometry.blockers(on:host,surfaces:world.surfaces).contains{$0.rect.intersects(group)}
    }
    /// 两个朝向及三个接触点的完整落稳鸟体。用于放置时预留空间，访问仍需实际路线复核。
    static func clearance(nest:CGRect,tray:CGRect,worldScale:CGFloat,birdScale:CGFloat) -> CGRect {
        var area=nest.union(tray)
        for slot in 0..<3 {
            for point in [materialPoint(slot:slot,rect:nest,scale:worldScale)!,
                          trayMaterialPoint(slot:slot,rect:tray,scale:worldScale)!] {
                for facing in [true,false] {
                    let grip=TwigGeometry.gripPoint(surfacePoint:point,worldScale:worldScale,facingRight:facing)!
                    let foot=CGPoint(x:grip.x+(facing ? -11:11)*birdScale,y:point.y)
                    area=area.union(Geometry.landingFootprint(at:foot,scale:birdScale))
                }
            }
        }
        return area
    }
    /// 虚拟边缘补足perchX的42点内缩，但绝不越过真实parent左右边界。
    /// 每根枝条两端至少有一端可落稳；具体朝向由执行器逐候选复核。
    static func supportSurfaceRect(foot:CGPoint,nest:CGRect,tray:CGRect,host:Surface,
                                   worldScale:CGFloat,birdScale:CGFloat)->CGRect? {
        let contacts=(0..<3).flatMap {slot in
            [materialPoint(slot:slot,rect:nest,scale:worldScale)!,
             trayMaterialPoint(slot:slot,rect:tray,scale:worldScale)!]
        }
        let offset=5*worldScale+11*birdScale
        let lo=max(host.rect.minX,contacts.map(\.x).min()!-offset-42)
        let hi=min(host.rect.maxX,contacts.map(\.x).max()!+offset+42)
        guard hi>lo else {return nil}
        let rect=CGRect(x:lo,y:foot.y,width:hi-lo,height:1)
        let low=Geometry.perchX(0,rect:rect),high=Geometry.perchX(1,rect:rect)
        guard high>low,contacts.allSatisfy({p in
            [p.x-offset,p.x+offset].contains{$0>=low-0.000001 && $0<=high+0.000001}
        }) else {return nil}
        return rect
    }
    static func contactMatches(_ contact:ScenePropRenderState,_ resting:ScenePropRenderState,scale:CGFloat)->Bool {
        guard contact.id==resting.id,contact.kind == .twigToken,contact.frameName=="twigToken",
              abs(contact.size-16*scale)<0.000001,contact.rotation.isFinite,
              abs(contact.rotation)<0.000001,contact.opacity==1,
              contact.anchor==CGPoint(x:TwigGeometry.grip.x/16,y:TwigGeometry.grip.y/16),
              SurfaceAnchor.finite(contact.rect),SurfaceAnchor.finite(resting.rect) else {return false}
        // 左右两端夹持同一对称轮廓；不能要求夹持点等于中心承载点。
        let a=contact.rect,b=resting.rect
        return abs(a.minX-b.minX)<0.001 && abs(a.minY-b.minY)<0.001 &&
            abs(a.maxX-b.maxX)<0.001 && abs(a.maxY-b.maxY)<0.001
    }
    static func validAttachment(_ value:ScenePropRenderState,id:ScenePropID,scale:CGFloat)->Bool {
        value.id==id && value.kind == .twigToken && value.frameName=="twigToken" &&
            value.anchor==CGPoint(x:TwigGeometry.grip.x/16,y:TwigGeometry.grip.y/16) &&
            value.opacity==1 && abs(value.size-16*scale)<0.000001 &&
            value.rotation.isFinite && SurfaceAnchor.finite(value.rect) && value.rect.width>0 && value.rect.height>0
    }
    static func attached(_ material:NestMaterial,scale:CGFloat,in engine:BehaviorEngine)->ScenePropRenderState? {
        guard let owner=material.owner,let bird=engine.bird(owner),
              let pose=engine.runtime.presentation(for:owner,in:engine),
              let anchor=PoseClip.nestBeakAnchor(species:bird.profile.id,frame:pose.frameName) else {return nil}
        let birdScale=engine.spriteScale(for:bird)
        let foot=CGPoint(x:bird.position.x,y:bird.position.y+pose.hopOffset*birdScale)
        let facing=pose.facingRight ?? bird.facingRight
        return render(id:material.id,position:anchor.world(foot:foot,scale:birdScale,facingRight:facing),
            worldScale:scale,facingRight:facing,rotation:material.cached.rotation,
            blockers:bird.blockers(in:engine.world.surfaces))
    }
}
