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
        if !names.isDisjoint(with:CourtshipArtGeometry.frameNames) {
            return names.union(CourtshipArtGeometry.frameNames)
        }
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
    /// Dedicated observation phase; approach and return remain owned by the
    /// existing ledge traversal. Sampling does not advance its clock.
    public static func edgePeek(species:SpeciesID) -> Self? {
        guard SpeciesBehaviorProfile.peekSpecies.contains(species) else {return nil}
        return Self(id:"\(species.rawValue).edgePeek",
            frames:zip(SpeciesBehaviorProfile.peekFrameNames,[0.32,0.96,0.32]).map {
                Frame(name:$0.0,duration:$0.1,beak:beakAnchor(species:species,frame:$0.0))
            })
    }
    /// Contact age starts only after the approach has landed. The final .8s
    /// shake uses existing art outside this seven-frame dedicated clip.
    public static func bath(species:SpeciesID) -> Self? {
        guard SpeciesBehaviorProfile.profile(for:species).allows(.bathVisit) else {return nil}
        var names=["bathInspect","bathTouch","bathLower"]
        var times=[0.6,0.6,0.4]
        for _ in 0..<3 {names += ["bath0","bath1","bath2"];times += [0.8/3,0.8/3,0.8/3]}
        names.append("bathRise");times.append(0.4)
        return Self(id:"\(species.rawValue).bathVisit",frames:zip(names,times).map {
            Frame(name:$0.0,duration:$0.1,beak:beakAnchor(species:species,frame:$0.0))
        })
    }
    public static func leafCarryPickup(species:SpeciesID) -> Self? {
        guard SpeciesBehaviorProfile.profile(for:species).allows(.leafCarry) else {return nil}
        return Self(id:"\(species.rawValue).leafCarry.pickup",
            frames:zip(["carryLook","carryLower","carryGrip","carryLook"],[0.4,0.3,0.2,0.3]).map {
                Frame(name:$0.0,duration:$0.1,beak:beakAnchor(species:species,frame:$0.0))
            })
    }
    public static func leafCarryPlace(species:SpeciesID) -> Self? {
        guard SpeciesBehaviorProfile.profile(for:species).allows(.leafCarry) else {return nil}
        return Self(id:"\(species.rawValue).leafCarry.place",
            frames:zip(["carryPlace","carryLook"],[0.4,0.3]).map {
                Frame(name:$0.0,duration:$0.1,beak:beakAnchor(species:species,frame:$0.0))
            })
    }
    /// Shares pickup timing with leafCarry without granting that behavior to a
    /// gift carrier. The execution performs the atomic grip at age 0.7s.
    public static func visitorGiftPickup(species:SpeciesID) -> Self? {
        guard SpeciesBehaviorProfile.profile(for:species).allows(.visitorGift),
              CarryArtGeometry.frameNames.allSatisfy({carryBeakAnchor(species:species,frame:$0) != nil}) else {return nil}
        return Self(id:"\(species.rawValue).visitorGift.pickup",
            frames:zip(["carryLook","carryLower","carryGrip","carryLook"],[0.4,0.3,0.2,0.3]).map {
                Frame(name:$0.0,duration:$0.1,beak:carryBeakAnchor(species:species,frame:$0.0)!)
            })
    }
    /// Aerial release only. The runtime keeps the real flight moving and owns
    /// the separate token/drop; no grounded look frame is appended here.
    public static func visitorGiftRelease(species:SpeciesID) -> Self? {
        guard SpeciesBehaviorProfile.profile(for:species).allows(.visitorGift),
              let anchor=carryBeakAnchor(species:species,frame:"carryPlace") else {return nil}
        return Self(id:"\(species.rawValue).visitorGift.release",
            frames:[Frame(name:"carryPlace",duration:GiftReceiverGeometry.releaseDuration,beak:anchor)])
    }
    /// A caught insect is already gone. The execution decides whether its
    /// recovery requires an ordinary flight handoff or an actual settled return.
    public static func insectCatchRecovery(species:SpeciesID) -> Self? {
        guard SpeciesBehaviorProfile.profile(for:species).allows(.insectCatch),
              let close=catchBeakAnchor(species:species,frame:"catchClose"),
              let recover=catchBeakAnchor(species:species,frame:"catchRecover") else {return nil}
        return Self(id:"\(species.rawValue).insectCatch.recovery",
            frames:[Frame(name:"catchClose",duration:0.18,beak:close),
                    Frame(name:"catchRecover",duration:0.30,beak:recover)])
    }
    /// Both roles sample the same owning-run age. Facing is owned by the
    /// execution; the observer turns only during 2.9...3.4s and then stands.
    /// Either role requires the complete five-frame species pack.
    public static func courtship(species:SpeciesID,role:CourtshipRole) -> Self? {
        guard CourtshipArtGeometry.species.contains(species),
              SpeciesBehaviorProfile.profile(for:species).allows(.courtshipDisplay) else {return nil}
        let names:[String],times:[Double],roleName:String
        switch role {
        case .initiator:
            names=["stand","courtRaise","courtBow0","courtBow1","courtBowRecover",
                   "courtBow0","courtBow1","courtBowRecover","courtBowRecover","courtBowRecover"]
            times=[0.4,0.5,0.35,0.40,0.25,0.35,0.40,0.25,0.5,0.6];roleName="initiator"
        case .observer:
            names=["stand","stand","stand","courtObserve","stand"]
            times=[0.4,0.5,2,0.5,0.6];roleName="observer"
        }
        var frames=[Frame]()
        for (name,time) in zip(names,times) {
            guard let beak=CourtshipPoseAnchors.anchor(species:species,frame:name) else {return nil}
            frames.append(Frame(name:name,duration:time,beak:beak))
        }
        return Self(id:"\(species.rawValue).courtshipDisplay.\(roleName)",frames:frames)
    }
    public static func catchBeakAnchor(species:SpeciesID,frame:String) -> Anchor? {
        CatchPoseAnchors.anchor(species:species,frame:frame)
    }
    /// Nest art has independent permission and anchors; providing the same four
    /// frame names never grants ordinary leafCarry to the dove.
    public static func nestBeakAnchor(species:SpeciesID,frame:String)->Anchor? {
        NestPoseAnchors.anchor(species:species,frame:frame)
    }
    public static func nestMaterialPickup(species:SpeciesID)->Self? {
        guard SpeciesBehaviorProfile.profile(for:species).allows(.nestMaterialCarry) else {return nil}
        return nestClip(species:species,id:"nestMaterialCarry.pickup",
            names:["carryLook","carryLower","carryGrip","carryLook"],times:[0.4,0.3,0.2,0.3])
    }
    public static func nestMaterialPlace(species:SpeciesID)->Self? {
        guard SpeciesBehaviorProfile.profile(for:species).allows(.nestMaterialCarry) else {return nil}
        return nestClip(species:species,id:"nestMaterialCarry.place",names:["carryPlace","carryLook"],times:[0.4,0.3])
    }
    /// One independent build visit. The executor consumes a delivered material
    /// after settle at age1.9, before the .3s raised empty-bill recovery.
    public static func nestBuild(species:SpeciesID)->Self? {
        guard SpeciesBehaviorProfile.profile(for:species).allows(.nestBuild) else {return nil}
        return nestClip(species:species,id:"nestBuild",
            names:["nestPlace","nestAdjust0","nestAdjust1","nestAdjust0","nestAdjust1","nestSettle","nestPlace"],
            times:[0.3,0.3,0.3,0.3,0.3,0.4,0.3])
    }
    private static func nestClip(species:SpeciesID,id:String,names:[String],times:[Double])->Self? {
        guard NestArtGeometry.species.contains(species),names.count==times.count else {return nil}
        var frames=[Frame]()
        for (name,time) in zip(names,times) {
            guard let anchor=nestBeakAnchor(species:species,frame:name) else {return nil}
            frames.append(Frame(name:name,duration:time,beak:anchor))
        }
        return Self(id:"\(species.rawValue).\(id)",frames:frames)
    }
    public static func carryBeakAnchor(species:SpeciesID,frame:String) -> Anchor? {
        CarryPoseAnchors.anchor(species:species,frame:frame)
    }
    public static func bathWaterContacts(species:SpeciesID,frame:String)->[Anchor] {
        BathPoseAnchors.waterContacts(species:species,frame:frame)
    }
    /// Logical canvas anchors track the editable species drawing, never bitmap size.
    public static func beakAnchor(species:SpeciesID,frame:String) -> Anchor {
        if let anchor=ExpansionArtCatalog.beakAnchor(species:species,frame:frame) {return anchor}
        if let anchor=M8ArtCatalog.beakAnchor(species:species,frame:frame) {return anchor}
        if let anchor=M8PilotArtGeometry.beakAnchor(species:species,frame:frame) {return anchor}
        if let anchor=ExpansionPilotArtGeometry.beakAnchor(species:species,frame:frame) {return anchor}
        if let anchor=NestPoseAnchors.anchor(species:species,frame:frame) {return anchor}
        if let anchor=CourtshipPoseAnchors.anchor(species:species,frame:frame) {return anchor}
        if let anchor=CatchPoseAnchors.anchor(species:species,frame:frame) {return anchor}
        if let anchor=CarryPoseAnchors.anchor(species:species,frame:frame) {return anchor}
        if let anchor=BathPoseAnchors.anchor(species:species,frame:frame) {return anchor}
        if let anchor=M6cPoseAnchors.anchor(species:species,frame:frame) {return anchor}
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
