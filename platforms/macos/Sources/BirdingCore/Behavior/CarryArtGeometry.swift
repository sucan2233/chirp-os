import Foundation
import CoreGraphics

/// Logical geometry shared by editable carry art, prop placement and anchors.
/// Props use world scale; these values never inherit a carrier's relative scale.
public enum CarryArtGeometry {
    public static let frameNames=["carryLook","carryLower","carryGrip","carryPlace"]
    public static let footAnchor=CGPoint(x:29,y:39)
    public static let sparrowHeadWidth:Double=9
    public static let sparrowHeadHeight:Double=8
    public static let sparrowHeadY:Double=16
    public static let contactBeak=CGPoint(x:40,y:39)
    public static let leafLogicalSize=CGSize(width:16,height:16)
    public static let leafGripAnchor=CGPoint(x:3,y:12)
    public static let leafSurfaceAnchor=CGPoint(x:10,y:12)
    // The complete dark border is filled geometry, not a centered stroke.
    // Both the square-cut stem and supporting blade end exactly at y12.
    public static let leafOutlineVertices:[CGPoint]=[
        CGPoint(x:2,y:12),CGPoint(x:2,y:11),CGPoint(x:5,y:8),CGPoint(x:5,y:6),
        CGPoint(x:7,y:3),CGPoint(x:10,y:2),CGPoint(x:14,y:2),CGPoint(x:14,y:6),
        CGPoint(x:13,y:9),CGPoint(x:11,y:11),CGPoint(x:10,y:12),
        CGPoint(x:8,y:11),CGPoint(x:6,y:10),CGPoint(x:4,y:12)
    ]

    public struct Pose {
        public let body:CGRect
        public let head:CGPoint
        public let pitch:Double
        public let tail:CGPoint
        public let release:Bool
        public func headPoint(_ x:Double,_ y:Double)->CGPoint {
            CGPoint(x:Double(head.x)+x*cos(pitch)-y*sin(pitch),
                    y:Double(head.y)+x*sin(pitch)+y*cos(pitch))
        }
        public var billTip:CGPoint {
            let length=TransportArtGeometry.ordinaryBillLength(species:.treeSparrow)
            return headPoint(CarryArtGeometry.sparrowHeadWidth/2-0.5+length,0.5)
        }
    }

    public static func pose(species:SpeciesID,frame:String)->Pose? {
        guard species == .treeSparrow else {return nil}
        let body:CGRect,head:CGPoint,pitch:Double,tail:CGPoint
        let target:CGPoint?
        switch frame {
        case "carryLook":
            body=CGRect(x:16.5,y:22,width:18,height:13)
            head=CGPoint(x:32,y:19);pitch=0.12;tail=CGPoint(x:11,y:36);target=nil
        case "carryLower":
            body=CGRect(x:17,y:24,width:19,height:11)
            head = .zero;pitch=0.72;tail=CGPoint(x:10.5,y:33)
            target=CGPoint(x:39.5,y:32.5)
        case "carryGrip":
            body=CGRect(x:17.5,y:25,width:19,height:11)
            head = .zero;pitch=0.95;tail=CGPoint(x:10,y:31)
            target=contactBeak
        case "carryPlace":
            body=CGRect(x:16.5,y:24.5,width:20,height:11.5)
            head = .zero;pitch=0.74;tail=CGPoint(x:9.5,y:32.5)
            target=contactBeak
        default:return nil
        }
        let center:CGPoint
        if let target=target {
            let tip=sparrowHeadWidth/2-0.5+TransportArtGeometry.ordinaryBillLength(species:species)
            center=CGPoint(x:Double(target.x)-tip*cos(pitch)+0.5*sin(pitch),
                           y:Double(target.y)-tip*sin(pitch)-0.5*cos(pitch))
        } else {center=head}
        return Pose(body:body,head:center,pitch:pitch,tail:tail,release:frame == "carryPlace")
    }

    /// Complete token canvas about its actual grip. This conservative envelope
    /// includes the transparent margin; using it never clips the leaf to 48x48.
    /// Reflect x before rotation. At contact use rotation=0 so grip and support
    /// stay at the same world y for every species and carrier scale.
    public static func leafBounds(grip:CGPoint,worldScale:CGFloat,facingRight:Bool,
                                  rotation:CGFloat=0)->CGRect? {
        guard grip.x.isFinite,grip.y.isFinite,worldScale.isFinite,worldScale>0,
              rotation.isFinite else {return nil}
        let corners=[CGPoint.zero,CGPoint(x:leafLogicalSize.width,y:0),
                     CGPoint(x:leafLogicalSize.width,y:leafLogicalSize.height),
                     CGPoint(x:0,y:leafLogicalSize.height)]
        let a=Double(rotation),co=cos(a),si=sin(a),direction=facingRight ? 1.0:-1.0
        let points=corners.map {p -> CGPoint in
            let x=Double(p.x-leafGripAnchor.x)*Double(worldScale)*direction
            let y=Double(p.y-leafGripAnchor.y)*Double(worldScale)
            return CGPoint(x:Double(grip.x)+x*co-y*si,y:Double(grip.y)+x*si+y*co)
        }
        guard points.allSatisfy({$0.x.isFinite && $0.y.isFinite}) else {return nil}
        let xs=points.map(\.x),ys=points.map(\.y)
        return CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
    }
}

/// Parameters of the accepted DetailedBirdArt common-frame drawing. Callers
/// supply that species' actual anatomy; no new species capability is implied.
/// Keeping the CGContext calls in their original order preserves legacy rasters.
public enum TransportArtGeometry {
    // Attached launch/landing-settle presentation can still sample stand.
    // It follows the same untransformed head/bill geometry as land0...2.
    public static let frameNames=(0..<8).map {"fly\($0)"} + (0..<3).map {"land\($0)"} +
        (0..<3).map {"glide\($0)"} + (0..<3).map {"bank\($0)"} + ["bound","stand"]

    public static func phase(_ frame:String)->Int {
        frame.hasPrefix("glide") ? 8+(Int(String(frame.last!)) ?? 1):
            (frame.hasPrefix("bank") ? 11+(Int(String(frame.last!)) ?? 1):
                (frame == "bound" ? 14:(Int(String(frame.last!)) ?? 0)))
    }
    public static func pitch(phase:Int)->Double {
        phase>=8 && phase<14 ? (phase == 11 ? -0.16:(phase == 13 ? -0.02:-0.09)):
            [0.03,0,-0.04,-0.06,-0.03,0.01,0.04,0.06][phase%8]
    }
    public static func bob(phase:Int)->Double {
        phase>=8 ? 0:[0,-0.3,-0.5,0,0.3,0.5,0,-0.2][phase%8]
    }
    public static func bodyScale(raptor:Bool)->CGSize {
        CGSize(width:raptor ? 0.74:0.9,height:raptor ? 0.80:0.94)
    }
    public struct HeadOrigin {
        public let x:Double,y:Double
    }
    public static func headOrigin(flying:Bool,headWidth:Double,headY:Double,bob:Double)->HeadOrigin {
        HeadOrigin(x:flying ? 33.0:37-headWidth,y:flying ? 18.0:headY+bob)
    }
    public struct BillOrigin {
        public let x:Double,y:Double
    }
    public static func billOrigin(headX:Double,headY:Double,headWidth:Double,headHeight:Double)->BillOrigin {
        BillOrigin(x:headX+headWidth-0.5,y:headY+headHeight*0.5)
    }
    public static func ordinaryBillLength(species:SpeciesID)->Double {
        species == .largeBilledCrow ? 7.0:(species == .barnSwallow || species == .swinhoesWhiteEye ? 2.2:4.0)
    }

    /// For common passerine/dove transport anatomy only, not owl/heron or
    /// hooked/curved bills. Later carrier batches can pass their own dimensions.
    public static func billAnchor(frame:String,species:SpeciesID,
                                  headWidth:Double,headHeight:Double,headY:Double)->CGPoint? {
        guard frameNames.contains(frame),[headWidth,headHeight,headY].allSatisfy(\.isFinite),
              headWidth>0,headHeight>0 else {return nil}
        let phase=Self.phase(frame),flying=frame.hasPrefix("fly") || phase>=8
        let h=headOrigin(flying:flying,headWidth:headWidth,headY:headY,bob:0)
        let bill=billOrigin(headX:h.x,headY:h.y,headWidth:headWidth,headHeight:headHeight)
        let point=CGPoint(x:bill.x+ordinaryBillLength(species:species),y:bill.y+0.5)
        guard flying else {return point}
        let scale=bodyScale(raptor:false)
        // Same logical matrix concatenation as DetailedBirdArt.make. Bob is
        // inside the outer rotation, and torso scaling does not affect wings.
        var t=CGAffineTransform.identity
        t=t.translatedBy(x:27,y:24)
        t=t.rotated(by:CGFloat(pitch(phase:phase)))
        t=t.translatedBy(x:-27,y:-24+CGFloat(bob(phase:phase)))
        t=t.translatedBy(x:27,y:24)
        t=t.scaledBy(x:scale.width,y:scale.height)
        t=t.translatedBy(x:-27,y:-24)
        return point.applying(t)
    }
}
