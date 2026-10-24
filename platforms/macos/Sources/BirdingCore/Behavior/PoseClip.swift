import Foundation
import CoreGraphics

/// Immutable presentation data. Sampling never advances a clock or mutates a bird.
public struct PoseClip:Codable,Equatable {
    public struct Anchor:Codable,Equatable {
        public let x:Double,y:Double
        public init(_ x:Double,_ y:Double) {self.x=x;self.y=y}
        public func mirrored(facingRight:Bool) -> Anchor {facingRight ? self:Anchor(48-x,y)}
        public func world(foot:CGPoint,scale:CGFloat,facingRight:Bool) -> CGPoint {
            let point=mirrored(facingRight:facingRight),origin=PoseClip.footAnchor.mirrored(facingRight:facingRight)
            return CGPoint(x:foot.x+CGFloat(point.x-origin.x)*scale,y:foot.y+CGFloat(point.y-origin.y)*scale)
        }
    }
    public struct Frame:Codable,Equatable {
        public let name:String
        public let duration:Double
        public let beak:Anchor
        public init(name:String,duration:Double,beak:Anchor) {self.name=name;self.duration=duration;self.beak=beak}
    }
    public enum Recovery:String,Codable {case currentEngineState}
    public let id:String
    public let frames:[Frame]
    public let maximumLoops:Int
    public let foot:Anchor
    public let recovery:Recovery
    public static let footAnchor=Anchor(29,39)
    public static let frameNames=["lookNear","lookFar","alertRise","alertHold","alertRelax","restLower","restTuck","restWake","takeoffCrouch","takeoffPush"]
    public init?(id:String,frames:[Frame],maximumLoops:Int=1,foot:Anchor=PoseClip.footAnchor,recovery:Recovery = .currentEngineState) {
        guard !id.isEmpty,!frames.isEmpty,maximumLoops>0,foot == Self.footAnchor,
              frames.allSatisfy({!$0.name.isEmpty && $0.duration.isFinite && $0.duration>=0 &&
                  $0.beak.x.isFinite && $0.beak.y.isFinite && (0...48).contains($0.beak.x) && (0...48).contains($0.beak.y)}),
              frames.reduce(0,{$0+$1.duration})>0,
              (frames.reduce(0,{$0+$1.duration})*Double(maximumLoops)).isFinite else {return nil}
        self.id=id;self.frames=frames;self.maximumLoops=maximumLoops;self.foot=foot;self.recovery=recovery
    }
    private enum CodingKeys:String,CodingKey {case id,frames,maximumLoops,foot,recovery}
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        guard let value=Self(id:try c.decode(String.self,forKey:.id),frames:try c.decode([Frame].self,forKey:.frames),
            maximumLoops:try c.decode(Int.self,forKey:.maximumLoops),foot:try c.decode(Anchor.self,forKey:.foot),
            recovery:try c.decode(Recovery.self,forKey:.recovery)) else {
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid pose clip"))
        }
        self=value
    }
    public var duration:Double {frames.reduce(0){$0+$1.duration}}
    public var requiredFrames:Set<String> {
        let names=Set(frames.map(\.name))
        return names.contains("lookNear") || names.contains("lookFar") ? names.union(BirdCapability.observationPose.requiredFrames):names
    }
    public func sample(at age:Double) -> Frame? {
        guard age.isFinite,age>=0,age<duration*Double(maximumLoops) else {return nil}
        var remainder=age.truncatingRemainder(dividingBy:duration)
        for frame in frames {
            if remainder+1e-9<frame.duration {return frame}
            remainder-=frame.duration
        }
        return frames.last(where:{$0.duration>0})
    }
    static func enhancement(species:SpeciesID,kind:BehaviorKind,duration:Double,lookingFar:Bool) -> Self? {
        guard duration.isFinite,duration>0 else {return nil}
        let names:[String],times:[Double]
        func transitions(_ enter:Double,_ exit:Double) -> [Double] {
            let ratio=min(1,duration/(enter+exit))
            return [enter*ratio,max(0,duration-(enter+exit)*ratio),exit*ratio]
        }
        switch kind {
        case .watch:names=["lookNear",lookingFar ? "lookFar":"lookNear","lookNear"];times=transitions(0.15,0.15)
        case .alert:names=["alertRise","alertHold","alertRelax"];times=transitions(0.12,0.25)
        case .rest:names=["restLower","restTuck","restWake"];times=transitions(0.25,0.25)
        case .takeoffPreparation:names=["takeoffCrouch","takeoffPush"];times=[duration*0.25/0.45,duration*0.20/0.45]
        default:return nil
        }
        return Self(id:"\(species.rawValue).\(kind.rawValue)\(kind == .watch && lookingFar ? ".far":"")",
            frames:zip(names,times).map {Frame(name:$0.0,duration:$0.1,beak:beakAnchor(species:species,frame:$0.0))})
    }
    /// Logical canvas anchors track the editable species drawing, never bitmap size.
    public static func beakAnchor(species:SpeciesID,frame:String) -> Anchor {
        let anchors:[Anchor]
        switch species {
        case .treeSparrow:anchors=[Anchor(40.436600,24.991150),Anchor(39.960264,17.559685),Anchor(40.389555,15.584048),Anchor(41.002325,15.038707),Anchor(39.513596,20.179685),Anchor(38.781235,24.924158),Anchor(19.380695,29.520487),Anchor(38.751167,17.458085),Anchor(41.818159,26.768159),Anchor(42.889555,16.084048)]
        case .spottedDove:anchors=[Anchor(41.589210,23.415017),Anchor(40.490250,14.378386),Anchor(40.959801,12.599348),Anchor(41.514946,11.298668),Anchor(39.457422,18.418848),Anchor(38.261131,23.880719),Anchor(18.509903,27.169950),Anchor(38.879762,14.614765),Anchor(41.889804,23.834390),Anchor(42.418217,12.821751)]
        case .barnSwallow:anchors=[Anchor(38.819990,24.014373),Anchor(38.183782,17.353155),Anchor(38.653768,15.646376),Anchor(39.218895,14.769484),Anchor(37.675846,20.707545),Anchor(36.553923,25.322068),Anchor(22.332411,28.345977),Anchor(37.115510,17.940963),Anchor(39.624105,26.516636),Anchor(40.683782,16.353155)]
        case .nightHeron:anchors=[Anchor(45.688431,24.515670),Anchor(45.193040,13.851799),Anchor(45.104047,9.682686),Anchor(45.230002,7.800320),Anchor(44.198036,18.098401),Anchor(43.032436,25.210851),Anchor(16.653226,29.421172),Anchor(43.475093,12.520113),Anchor(46.145155,25.545324),Anchor(46.022492,12.740096)]
        default:preconditionFailure("No enhanced pose anchor for unsupported species")
        }
        guard let index=frameNames.firstIndex(of:frame) else {preconditionFailure("Unknown enhanced pose frame")}
        return anchors[index]
    }
}
