import Foundation
import CoreGraphics

public struct InsectContact:Equatable {
    public let runID:BehaviorRunID
    public let birdID:BirdID
    public let insectID:ScenePropID
    public let time:Double
    public let insectAge:Double
    public let beakPosition:CGPoint
    public let insectPosition:CGPoint
    public init(runID:BehaviorRunID,birdID:BirdID,insectID:ScenePropID,time:Double,insectAge:Double,
                beakPosition:CGPoint,insectPosition:CGPoint) {
        self.runID=runID;self.birdID=birdID;self.insectID=insectID;self.time=time;self.insectAge=insectAge
        self.beakPosition=beakPosition;self.insectPosition=insectPosition
    }
}

struct InsectResolution {
    let contact:InsectContact?
    let completion:BehaviorCompletion?
    init(contact:InsectContact?=nil,completion:BehaviorCompletion?=nil) {self.contact=contact;self.completion=completion}
}

struct InsectSweepResult {
    let contact:InsectContact?
    let minimumDistance:CGFloat?
    let segments:Int
}

/// Contact is verified against the original time-parametrized motion, never a
/// chord between two differently posed beaks. A caller supplies discontinuity
/// boundaries and a half-open interval during which the open beak really exists.
/// Finite search may conservatively miss a numerical tangency, but cannot turn
/// an approximate sweep/box overlap into a successful capture.
enum InsectContactResolver {
    static let maximumSegments=128
    static func resolve(_ step:InsectStep,runID:BehaviorRunID,birdID:BirdID,
                        simulationStart:Double,motionInterval:ClosedRange<Double>,
                        openInterval:Range<Double>,boundaries:[Double]=[],
                        beakAt:(Double)->CGPoint?) -> InsectSweepResult {
        let lo=max(step.startAge,max(motionInterval.lowerBound,max(openInterval.lowerBound,step.trajectory.visibleFrom.nextUp)))
        let hi=min(step.endAge,min(motionInterval.upperBound,min(openInterval.upperBound.nextDown,step.trajectory.terminalAge.nextDown)))
        guard lo.isFinite,hi.isFinite,hi>=lo else {return InsectSweepResult(contact:nil,minimumDistance:nil,segments:0)}
        var cuts=[lo,hi]
        cuts += boundaries.filter{$0>lo && $0<hi}
        cuts += step.trajectory.waypoints.map(\.time).filter{$0>lo && $0<hi}
        // Fixed temporal partitions keep the budget bounded independently of
        // frame rate. Each minimum/root query samples actual motion again.
        cuts += (1..<32).map{lo+(hi-lo)*Double($0)/32}
        cuts=Array(Set(cuts)).sorted()
        guard cuts.count<=maximumSegments+1 else {return InsectSweepResult(contact:nil,minimumDistance:nil,segments:0)}
        let radius=step.trajectory.collisionRadius
        var minimum:CGFloat?,segments=0
        func distance(_ t:Double) -> CGFloat {
            guard let p=beakAt(t),p.x.isFinite,p.y.isFinite else {return .infinity}
            let d=Geometry.distance(p,step.trajectory.position(at:t))
            minimum=min(minimum ?? d,d);return d
        }
        func contact(_ t:Double) -> InsectContact? {
            guard let beak=beakAt(t),step.trajectory.isVisible(at:t),
                  Geometry.distance(beak,step.trajectory.position(at:t))<=radius else {return nil}
            return InsectContact(runID:runID,birdID:birdID,insectID:step.insectID,
                time:simulationStart+t-step.startAge,insectAge:t,beakPosition:beak,
                insectPosition:step.trajectory.position(at:t))
        }
        if let hit=contact(lo) {return InsectSweepResult(contact:hit,minimumDistance:distance(lo),segments:0)}
        for index in 0..<(cuts.count-1) {
            let a=cuts[index],b=cuts[index+1]
            // A discontinuity starts a new interval. No segment ever connects
            // the old anchor at a boundary to the new anchor after it.
            let left=a,right=index==cuts.count-2 ? b:b.nextDown
            guard right>=left else {continue}
            segments+=1
            if let hit=contact(left) {return InsectSweepResult(contact:hit,minimumDistance:distance(left),segments:segments)}
            var l=left,r=right
            for _ in 0..<24 {
                let x=l+(r-l)/3,y=r-(r-l)/3
                if distance(x)<=distance(y) {r=y} else {l=x}
            }
            let middle=(l+r)/2
            let choices=[left,middle,right].map{($0,distance($0))}
            guard let best=choices.min(by:{$0.1<$1.1}),best.1<=radius else {continue}
            // Find the first entry within this piece, then recheck the exact
            // sample. Equality at expiry/exit has already been excluded above.
            var before=left,inside=best.0
            for _ in 0..<36 {
                let t=(before+inside)/2
                if distance(t)<=radius {inside=t} else {before=t}
            }
            if let hit=contact(inside) {return InsectSweepResult(contact:hit,minimumDistance:minimum,segments:segments)}
        }
        return InsectSweepResult(contact:nil,minimumDistance:minimum,segments:segments)
    }
}
