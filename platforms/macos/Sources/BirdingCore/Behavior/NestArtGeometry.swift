import Foundation
import CoreGraphics

/// M7b/c source-art contract. Layout and bill geometry precede rasterization;
/// runtime stock, leases, material identities and progress belong to the core.
public enum NestArtGeometry {
    public static let species:[SpeciesID]=[.spottedDove]
    public static let carryFrameNames=SpeciesBehaviorProfile.nestCarryFrameNames
    public static let buildFrameNames=SpeciesBehaviorProfile.nestBuildFrameNames
    public static let frameNames=carryFrameNames+buildFrameNames
    public static let transportFrameNames=TransportArtGeometry.frameNames
    public static let birdFootAnchor=CGPoint(x:29,y:39)
    public static let nativeFrameSize=max(48,Int((48*SpeciesCatalog.standard.profile(.spottedDove).relativeScale).rounded()))
    public static let nestSize=CGSize(width:144,height:48)
    public static let nestAnchor=CGPoint(x:72,y:24)
    public static let nestContactY:CGFloat=24
    public static let materialPoints=[CGPoint(x:60,y:24),CGPoint(x:72,y:24),CGPoint(x:84,y:24)]
    public static let traySize=CGSize(width:32,height:16)
    public static let trayAnchor=CGPoint(x:16,y:12)
    public static let trayContactY:CGFloat=12
    public static let trayMaterialPoints=[CGPoint(x:8,y:12),CGPoint(x:16,y:12),CGPoint(x:24,y:12)]
    public static let trayOffset:CGFloat=120
    public static let assetNames=["twigToken","nestPlatform","nestMaterialTray","nestOverlay1","nestOverlay2","nestOverlay3"]

    public struct Pose {
        public let body:CGRect
        public let bodyPitch:Double
        public let head:CGPoint
        public let headPitch:Double
        public let tail:CGPoint
        public let pressing:Bool
        public let adjusting:Bool
        public var headWidth:Double {CourtshipArtGeometry.headWidth}
        public var headHeight:Double {CourtshipArtGeometry.headHeight}
        public var billRoot:Double {headWidth/2-0.5}
        public var billLength:Double {TransportArtGeometry.ordinaryBillLength(species:.spottedDove)}
        public func bodyPoint(_ x:Double,_ y:Double)->CGPoint {
            let dx=x-Double(body.width)/2,dy=y-Double(body.height)/2
            return CGPoint(x:Double(body.midX)+dx*cos(bodyPitch)-dy*sin(bodyPitch),
                           y:Double(body.midY)+dx*sin(bodyPitch)+dy*cos(bodyPitch))
        }
        public func headPoint(_ x:Double,_ y:Double)->CGPoint {
            CGPoint(x:Double(head.x)+x*cos(headPitch)-y*sin(headPitch),
                    y:Double(head.y)+x*sin(headPitch)+y*cos(headPitch))
        }
        public var billTip:CGPoint {headPoint(billRoot+billLength,0.5)}
        public func neckPoint(_ t:Double,_ u:Double)->CGPoint {
            let a=bodyPoint(Double(body.width)*0.57,1.8),b=bodyPoint(Double(body.width)-0.6,Double(body.height)*0.70)
            let n=headPoint(-headWidth*0.40,0.8),c=headPoint(headWidth*0.25,headHeight*0.35)
            let left=CGPoint(x:a.x+(n.x-a.x)*t,y:a.y+(n.y-a.y)*t)
            let right=CGPoint(x:b.x+(c.x-b.x)*t,y:b.y+(c.y-b.y)*t)
            return CGPoint(x:left.x+(right.x-left.x)*u,y:left.y+(right.y-left.y)*u)
        }
        public var collar:[CGPoint] {
            [neckPoint(0.42,0),neckPoint(1,0),neckPoint(1,0.66),neckPoint(0.42,0.60)]
        }
        public var collarSpots:[CGPoint] {
            // Five separately authored native pixels, still selected through
            // the continuous neck mapping. Small aliased ellipses can cover
            // several cells each and erase the entire black field when bowed.
            // Pick distinct in-patch centers instead of weakening the checker.
            let outline=collar,path=CGMutablePath()
            path.move(to:outline[0]);for point in outline.dropFirst() {path.addLine(to:point)};path.closeSubpath()
            let count=NestArtGeometry.nativeFrameSize,unit=48/CGFloat(count)
            var candidates=[CGPoint]()
            for y in 0..<count {for x in 0..<count {
                let point=CGPoint(x:(CGFloat(x)+0.5)*unit,y:(CGFloat(y)+0.5)*unit)
                if path.contains(point) {candidates.append(point)}
            }}
            guard candidates.count>5 else {return []}
            let targets=[neckPoint(0.52,0.16),neckPoint(0.74,0.16),neckPoint(0.94,0.16),
                         neckPoint(0.64,0.48),neckPoint(0.86,0.48)]
            var result=[CGPoint]()
            for target in targets {
                let index=candidates.indices.min {a,b in
                    hypot(candidates[a].x-target.x,candidates[a].y-target.y) <
                        hypot(candidates[b].x-target.x,candidates[b].y-target.y)
                }!
                result.append(candidates.remove(at:index))
            }
            return result
        }
    }

    public static func pose(species:SpeciesID,frame:String)->Pose? {
        guard species == .spottedDove else {return nil}
        let body:CGRect,tilt:Double,pitch:Double,tip:CGPoint,tail:CGPoint
        switch frame {
        case "carryLook":
            body=CGRect(x:11,y:22.5,width:23,height:12.5);tilt = -0.02;pitch = -0.06
            tip=CGPoint(x:40,y:19);tail=CGPoint(x:6,y:42)
        case "carryLower":
            body=CGRect(x:11.5,y:24,width:24,height:11);tilt=0.07;pitch=0.48
            tip=CGPoint(x:40,y:31);tail=CGPoint(x:5.5,y:38)
        case "carryGrip":
            body=CGRect(x:12,y:25,width:24,height:10);tilt=0.10;pitch=0.95
            tip=CGPoint(x:40,y:39);tail=CGPoint(x:5,y:34)
        case "carryPlace":
            // Open the side-neck surface while the real tip stays at (40,39).
            // At .82 the long, shallow torso and nape made the mapped collar
            // pinch to too few native cells for five spots plus black field.
            // A steeper emptying bill keeps this grounded release independent
            // of carryGrip's .95 head pitch and its different torso/tail.
            body=CGRect(x:10.5,y:24,width:25,height:11);tilt=0.04;pitch=1.04
            tip=CGPoint(x:40,y:39);tail=CGPoint(x:4.5,y:36)
        case "nestPlace":
            body=CGRect(x:11.25,y:23,width:23.5,height:12);tilt=0.04;pitch=0.24
            tip=CGPoint(x:40,y:26);tail=CGPoint(x:6,y:41)
        case "nestAdjust0":
            body=CGRect(x:12,y:25.2,width:23.5,height:10.3);tilt=0.13;pitch=0.86
            tip=CGPoint(x:40,y:39);tail=CGPoint(x:5.5,y:34.5)
        case "nestAdjust1":
            body=CGRect(x:11,y:26,width:25,height:9.5);tilt=0.20;pitch=1.02
            tip=CGPoint(x:41,y:39);tail=CGPoint(x:4.5,y:32)
        case "nestSettle":
            body=CGRect(x:12.5,y:25.2,width:23,height:10.2);tilt=0.08;pitch=0.92
            tip=CGPoint(x:40,y:39);tail=CGPoint(x:5,y:35.5)
        default:return nil
        }
        let local=CourtshipArtGeometry.headWidth/2-0.5+TransportArtGeometry.ordinaryBillLength(species:species)
        let head=CGPoint(x:Double(tip.x)-local*cos(pitch)+0.5*sin(pitch),
                         y:Double(tip.y)-local*sin(pitch)-0.5*cos(pitch))
        return Pose(body:body,bodyPitch:tilt,head:head,headPitch:pitch,tail:tail,
                    pressing:frame == "nestSettle",adjusting:frame == "nestAdjust0" || frame == "nestAdjust1")
    }
    public static func billAnchor(species:SpeciesID,frame:String)->CGPoint? {
        guard species == .spottedDove else {return nil}
        if let pose=pose(species:species,frame:frame) {return pose.billTip}
        return TransportArtGeometry.billAnchor(frame:frame,species:species,
            headWidth:CourtshipArtGeometry.headWidth,headHeight:CourtshipArtGeometry.headHeight,
            headY:CourtshipArtGeometry.headY)
    }
}
