import Foundation
import CoreGraphics

/// M7a editable Spotted Dove geometry. No sex, pair bond or breeding state is
/// represented. All points precede native rasterization and facing reflection.
public enum CourtshipArtGeometry {
    public static let species:[SpeciesID]=[.spottedDove]
    public static let frameNames=SpeciesBehaviorProfile.courtshipFrameNames
    public static let footAnchor=CGPoint(x:29,y:39)
    // Same-valued anatomy also feeds the untouched common-frame operations.
    public static let headWidth:Double=7
    public static let headHeight:Double=6
    public static let headY:Double=14

    public struct Pose {
        public let body:CGRect
        public let bodyPitch:Double
        public let head:CGPoint
        public let headPitch:Double
        public let headWidth:Double
        public let tail:CGPoint
        public let observing:Bool
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

        /// A continuous neck surface between the tilted shoulder/breast and the
        /// articulated nape/chin. Collar and every white spot use this mapping,
        /// so bowing does not leave a rigid spotted patch behind the head.
        public func neckPoint(_ t:Double,_ u:Double)->CGPoint {
            let shoulder=bodyPoint(Double(body.width)*0.57,1.3)
            let breast=bodyPoint(Double(body.width)-0.7,Double(body.height)*0.68)
            let nape=headPoint(-headWidth*0.40,1.1)
            let chin=headPoint(headWidth*0.28,CourtshipArtGeometry.headHeight*0.39)
            let a=CGPoint(x:shoulder.x+(nape.x-shoulder.x)*t,y:shoulder.y+(nape.y-shoulder.y)*t)
            let b=CGPoint(x:breast.x+(chin.x-breast.x)*t,y:breast.y+(chin.y-breast.y)*t)
            return CGPoint(x:a.x+(b.x-a.x)*u,y:a.y+(b.y-a.y)*u)
        }
        public var collar:[CGPoint] {
            [neckPoint(0.56,0),neckPoint(1,0),neckPoint(1,observing ? 0.34:0.46),neckPoint(0.56,0.43)]
        }
        public var collarSpots:[CGPoint] {
            [neckPoint(0.67,0.12),neckPoint(0.83,0.10),neckPoint(0.96,0.13),
             neckPoint(0.73,0.31),neckPoint(0.91,observing ? 0.26:0.32)]
        }
    }

    public static func pose(species:SpeciesID,frame:String)->Pose? {
        guard species == .spottedDove else {return nil}
        let body:CGRect,tilt:Double,pitch:Double,tip:CGPoint,tail:CGPoint
        let observing=frame == "courtObserve",width=observing ? 6.3:headWidth
        switch frame {
        case "courtRaise":
            body=CGRect(x:11,y:20,width:23,height:14);tilt = -0.08;pitch = -0.18
            tip=CGPoint(x:39.5,y:13);tail=CGPoint(x:6,y:43)
        case "courtBow0":
            body=CGRect(x:10.5,y:23.5,width:24,height:11);tilt=0.12;pitch=0.45
            tip=CGPoint(x:41,y:24);tail=CGPoint(x:4.5,y:37)
        case "courtBow1":
            body=CGRect(x:10,y:26,width:25,height:8.5);tilt=0.20;pitch=0.72
            tip=CGPoint(x:41.5,y:30);tail=CGPoint(x:3.5,y:33)
        case "courtBowRecover":
            body=CGRect(x:11,y:22.5,width:23,height:12);tilt=0.02;pitch=0.12
            tip=CGPoint(x:40,y:19);tail=CGPoint(x:5.5,y:40)
        case "courtObserve":
            body=CGRect(x:11,y:22,width:23,height:12.5);tilt = -0.025;pitch = -0.10
            tip=CGPoint(x:38.5,y:16);tail=CGPoint(x:6,y:42)
        default:return nil
        }
        let localX=width/2-0.5+TransportArtGeometry.ordinaryBillLength(species:species)
        let center=CGPoint(x:Double(tip.x)-localX*cos(pitch)+0.5*sin(pitch),
                           y:Double(tip.y)-localX*sin(pitch)-0.5*cos(pitch))
        return Pose(body:body,bodyPitch:tilt,head:center,headPitch:pitch,headWidth:width,tail:tail,observing:observing)
    }

    public static func billAnchor(species:SpeciesID,frame:String)->CGPoint? {
        guard species == .spottedDove else {return nil}
        if let pose=pose(species:species,frame:frame) {return pose.billTip}
        guard frame == "stand" else {return nil}
        return TransportArtGeometry.billAnchor(frame:frame,species:species,
            headWidth:headWidth,headHeight:headHeight,headY:headY)
    }
}
