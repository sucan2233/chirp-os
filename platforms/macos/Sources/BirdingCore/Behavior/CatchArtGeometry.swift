import Foundation
import CoreGraphics

/// M6f.1/f.2 editable art contract. Logical bird coordinates are right-facing and
/// top-down; the renderer keeps its existing (29,39) reference even in flight.
public enum CatchArtGeometry {
    public static let species:[SpeciesID]=[.barnSwallow,.yellowRumpedFlycatcher]
    public static let frameNames=["catchOpen","catchClose","catchRecover"]
    public static let footAnchor=CGPoint(x:29,y:39)
    // The accepted common-frame drawer reads these same anatomy values.
    public static let swallowHeadWidth:Double=7
    public static let swallowHeadHeight:Double=6
    public static let swallowHeadY:Double=17
    public static let flycatcherHeadWidth:Double=8
    public static let flycatcherHeadHeight:Double=7
    public static let flycatcherHeadY:Double=15

    public static let insectFrameNames=["insect0","insect1","insect2","insect3"]
    public static let insectLogicalSize=CGSize(width:16,height:16)
    public static let insectAnchor=CGPoint(x:8,y:8)
    public static let insectCollisionRadius:CGFloat=3
    public static let insectFrameDuration=1.0/12.0
    public static let insectLifetime=12.0

    public struct Pose {
        public let species:SpeciesID
        public let body:CGRect
        public let head:CGPoint
        public let pitch:Double
        public let tail:CGPoint
        public let farWing:[CGPoint]
        public let nearWing:[CGPoint]
        public let gape:Double
        public func headPoint(_ x:Double,_ y:Double)->CGPoint {
            CGPoint(x:Double(head.x)+x*cos(pitch)-y*sin(pitch),
                    y:Double(head.y)+x*sin(pitch)+y*cos(pitch))
        }
        public var headWidth:Double {species == .yellowRumpedFlycatcher ? CatchArtGeometry.flycatcherHeadWidth:CatchArtGeometry.swallowHeadWidth}
        public var headHeight:Double {species == .yellowRumpedFlycatcher ? CatchArtGeometry.flycatcherHeadHeight:CatchArtGeometry.swallowHeadHeight}
        public var billRoot:Double {headWidth/2-0.5}
        public var billLength:Double {TransportArtGeometry.ordinaryBillLength(species:species)}
        /// This is an actual upper-mandible vertex, including in the open pose.
        /// The capture sweep follows this point; it is not the mouth's void.
        public var billTip:CGPoint {headPoint(billRoot+billLength,0.5)}
        public var upperBill:[CGPoint] {
            [CGPoint(x:billRoot,y:-0.7),CGPoint(x:billRoot+billLength,y:0.5),
             CGPoint(x:billRoot+billLength-0.7,y:1),CGPoint(x:billRoot,y:0.9)]
        }
        public var lowerBill:[CGPoint] {
            [CGPoint(x:billRoot-0.15,y:1.1),CGPoint(x:billRoot+billLength-0.4,y:1.2+gape),
             CGPoint(x:billRoot+0.6,y:1.5+gape),CGPoint(x:billRoot-0.3,y:1.6)]
        }
    }

    public static func pose(species:SpeciesID,frame:String)->Pose? {
        if species == .yellowRumpedFlycatcher {return flycatcherPose(frame)}
        guard species == .barnSwallow else {return nil}
        func points(_ values:[(Double,Double)])->[CGPoint] {values.map{CGPoint(x:$0.0,y:$0.1)}}
        switch frame {
        case "catchOpen":
            return Pose(species:species,body:CGRect(x:16.5,y:20.5,width:19,height:7.8),
                head:CGPoint(x:36.6,y:18.8),pitch:-0.14,tail:CGPoint(x:3.8,y:27),
                farWing:points([(28,22),(29,15),(34,8),(37,5),(37,11),(33,20),(29,25)]),
                nearWing:points([(25,23),(20,17),(14,9),(8,5),(9,12),(13,23),(21,29),(27,26)]),gape:2.2)
        case "catchClose":
            return Pose(species:species,body:CGRect(x:17,y:21.2,width:18.5,height:8.5),
                head:CGPoint(x:36,y:19.9),pitch:0.06,tail:CGPoint(x:4.8,y:26.5),
                farWing:points([(28,23),(34,25),(38,31),(40,36),(35,33),(30,28),(27,25)]),
                nearWing:points([(25,24),(19,26),(13,33),(9,40),(14,37),(22,31),(28,26)]),gape:0)
        case "catchRecover":
            return Pose(species:species,body:CGRect(x:16.2,y:21.7,width:18,height:8.8),
                head:CGPoint(x:34.7,y:20.2),pitch:-0.05,tail:CGPoint(x:3.2,y:28.2),
                farWing:points([(29,23),(33,20),(39,18),(44,18),(41,22),(34,26),(28,26)]),
                nearWing:points([(25,24),(18,23),(10,22),(4.5,19),(7,24),(16,29),(24,28),(28,25)]),gape:0)
        default:return nil
        }
    }

    /// The flycatcher has a compact torso, rounded wings and a short fan tail;
    /// none of these silhouettes reuse the swallow's pointed wings/streamers.
    private static func flycatcherPose(_ frame:String)->Pose? {
        func points(_ values:[(Double,Double)])->[CGPoint] {values.map{CGPoint(x:$0.0,y:$0.1)}}
        switch frame {
        case "catchOpen":
            return Pose(species:.yellowRumpedFlycatcher,body:CGRect(x:18,y:21,width:16,height:8.6),
                head:CGPoint(x:35.7,y:18.7),pitch:-0.10,tail:CGPoint(x:10.3,y:28.4),
                farWing:points([(28.5,22),(29,16),(32,10),(35,8),(37,10.5),(35.5,16),(31,23),(28,25)]),
                nearWing:points([(25,23),(19,19),(14,12),(10.5,10),(8.5,12.5),(10,18),(16.5,25.5),(23,28),(27,26)]),gape:2.0)
        case "catchClose":
            return Pose(species:.yellowRumpedFlycatcher,body:CGRect(x:18.3,y:21.6,width:15.8,height:9.1),
                head:CGPoint(x:35.1,y:20),pitch:0.07,tail:CGPoint(x:11.4,y:29.3),
                farWing:points([(29,23),(33,25),(36.5,29),(38,34),(35.7,35),(31,31),(27,26)]),
                nearWing:points([(25,24),(20,27),(17,32),(16,37),(12.8,37.6),(11.5,34),(15,28),(22,24)]),gape:0)
        case "catchRecover":
            return Pose(species:.yellowRumpedFlycatcher,body:CGRect(x:17.8,y:22,width:16,height:9.2),
                head:CGPoint(x:33.9,y:20.5),pitch:-0.04,tail:CGPoint(x:12.5,y:31.1),
                farWing:points([(29,23),(33,19),(37,18),(40,19.8),(39,22.6),(34,25),(28,26)]),
                nearWing:points([(25,24),(21,22.4),(16,22),(12.2,24),(14.5,28),(20,30.6),(26,28),(28,25)]),gape:0)
        default:return nil
        }
    }

    /// Legacy transforms and bill vertices stay in TransportArtGeometry; these
    /// exact dimensions are also consumed by DetailedBirdArt's common drawer.
    public static func billAnchor(species:SpeciesID,frame:String)->CGPoint? {
        guard Self.species.contains(species) else {return nil}
        if let pose=pose(species:species,frame:frame) {return pose.billTip}
        if species == .yellowRumpedFlycatcher {
            return TransportArtGeometry.billAnchor(frame:frame,species:species,
                headWidth:flycatcherHeadWidth,headHeight:flycatcherHeadHeight,headY:flycatcherHeadY)
        }
        return TransportArtGeometry.billAnchor(frame:frame,species:species,
            headWidth:swallowHeadWidth,headHeight:swallowHeadHeight,headY:swallowHeadY)
    }

    public struct InsectPose {
        public let farWing:[CGPoint]
        public let nearWing:[CGPoint]
    }
    /// All four frames hold the thorax/collision center still. Wings alone
    /// articulate; neither their transparent margin nor phase changes the pivot.
    public static func insectPose(frame:String)->InsectPose? {
        func points(_ values:[(Double,Double)])->[CGPoint] {values.map{CGPoint(x:$0.0,y:$0.1)}}
        switch frame {
        case "insect0":return InsectPose(
            farWing:points([(7,7.5),(3,2.5),(7,3),(9,7)]),
            nearWing:points([(7.5,8.5),(4,13.5),(8,12),(9,8.4)]))
        case "insect1":return InsectPose(
            farWing:points([(7,7),(3,5),(2,7),(8,8)]),
            nearWing:points([(7,8.5),(2.5,10),(4,12),(8.5,9)]))
        case "insect2":return InsectPose(
            farWing:points([(7,7),(5,5.5),(4,6.5),(8.5,8)]),
            nearWing:points([(7,8.5),(4.3,9.5),(5.5,10.8),(9,9)]))
        case "insect3":return InsectPose(
            farWing:points([(7,7),(5,2.5),(8,4),(9,7.5)]),
            nearWing:points([(7.5,8.5),(5,13),(9,11.5),(9,8.5)]))
        default:return nil
        }
    }
}
