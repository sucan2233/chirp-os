import Foundation
import CoreGraphics

public struct InsectWaypoint:Equatable {
    public let time:Double
    public let position:CGPoint
    public init(time:Double,position:CGPoint) {self.time=time;self.position=position}
}

/// A frozen, piecewise linear flight in simulation time. Neither a chase nor
/// rendering may move this target to the bird. All entry/exit times are exact
/// slab intersections with the sprite's visible screen area.
public struct InsectTrajectory:Equatable {
    public static let lifetime=CatchArtGeometry.insectLifetime
    public static let logicalSize:CGFloat=CatchArtGeometry.insectLogicalSize.width
    public let waypoints:[InsectWaypoint]
    public let display:CGRect
    public let worldScale:CGFloat
    public let screens:[CGRect]
    public let displays:[CGRect]
    public let displayIDs:[String]
    public let visibleFrom:Double
    public let visibleUntil:Double
    public var duration:Double {waypoints.last!.time}
    public var terminalAge:Double {min(Self.lifetime,min(duration,visibleUntil))}
    public var collisionRadius:CGFloat {CatchArtGeometry.insectCollisionRadius*worldScale}

    public init?(waypoints:[InsectWaypoint],display:CGRect,worldScale:CGFloat,
                 screens:[CGRect]=[],displays:[CGRect]=[],displayIDs:[String]=[]) {
        guard (2...32).contains(waypoints.count),waypoints[0].time==0,
              worldScale.isFinite,worldScale>0,SurfaceAnchor.finite(display),
              display.width>0,display.height>0,
              waypoints.allSatisfy({$0.time.isFinite && $0.time>=0 && $0.position.x.isFinite && $0.position.y.isFinite}),
              zip(waypoints,waypoints.dropFirst()).allSatisfy({$0.1.time>$0.0.time}),
              waypoints.last!.time<=60 else {return nil}
        let half=Self.logicalSize*worldScale/2
        let visible=display.insetBy(dx:-half,dy:-half)
        func strictlyInside(_ p:CGPoint) -> Bool {p.x>visible.minX && p.x<visible.maxX && p.y>visible.minY && p.y<visible.maxY}
        guard !strictlyInside(waypoints[0].position),!strictlyInside(waypoints.last!.position) else {return nil}
        var intervals:[ClosedRange<Double>]=[]
        for (a,b) in zip(waypoints,waypoints.dropFirst()) {
            guard let range=Self.clip(from:a.position,to:b.position,rect:visible) else {continue}
            let lo=a.time+(b.time-a.time)*range.lowerBound,hi=a.time+(b.time-a.time)*range.upperBound
            guard hi>lo else {continue}
            if let last=intervals.last,lo<=last.upperBound+1e-9 {
                intervals[intervals.count-1]=last.lowerBound...max(last.upperBound,hi)
            } else {intervals.append(lo...hi)}
        }
        // One entry and one exit. Reentry cannot create a second interception.
        guard intervals.count==1,let interval=intervals.first,
              interval.lowerBound>0,interval.lowerBound<Self.lifetime else {return nil}
        self.waypoints=waypoints;self.display=display;self.worldScale=worldScale
        self.screens=screens;self.displays=displays;self.displayIDs=displayIDs
        visibleFrom=interval.lowerBound;visibleUntil=interval.upperBound
    }
    private static func clip(from a:CGPoint,to b:CGPoint,rect:CGRect) -> ClosedRange<Double>? {
        var lo=0.0,hi=1.0
        for (p,d,mn,mx) in [(a.x,b.x-a.x,rect.minX,rect.maxX),(a.y,b.y-a.y,rect.minY,rect.maxY)] {
            if abs(d)<1e-12 {if p<=mn || p>=mx {return nil};continue}
            let x=Double((mn-p)/d),y=Double((mx-p)/d)
            lo=max(lo,min(x,y));hi=min(hi,max(x,y))
            if hi<=lo {return nil}
        }
        return lo...hi
    }
    public func position(at age:Double) -> CGPoint {
        let t=min(duration,max(0,age))
        for (a,b) in zip(waypoints,waypoints.dropFirst()) where t<=b.time {
            let u=CGFloat((t-a.time)/(b.time-a.time))
            return CGPoint(x:a.position.x+(b.position.x-a.position.x)*u,y:a.position.y+(b.position.y-a.position.y)*u)
        }
        return waypoints.last!.position
    }
    public func isVisible(at age:Double) -> Bool {age>visibleFrom && age<terminalAge}
    public func facingRight(at age:Double) -> Bool {
        var right=true
        for (a,b) in zip(waypoints,waypoints.dropFirst()) {
            if b.position.x != a.position.x {right=b.position.x>a.position.x}
            if age<b.time {return right}
        }
        return right
    }
}

public struct Insect:Equatable {
    public let id:ScenePropID
    public let trajectory:InsectTrajectory
    public fileprivate(set) var age:Double
    public var position:CGPoint {trajectory.position(at:age)}
    public var remainingLifetime:Double {max(0,InsectTrajectory.lifetime-age)}
}

public struct InsectStep {
    public let insectID:ScenePropID
    public let startAge:Double
    public let endAge:Double
    public let trajectory:InsectTrajectory
    fileprivate let revision:UInt64
}

/// The entity outlives its borrowed run lease. makeStep is pure; even an expired
/// step stays available until post-motion contact has been resolved and commit
/// is called exactly once. Reads never advance age or mutate lastContact.
final class InsectStore {
    private(set) var current:Insect?
    private(set) var lastContact:InsectContact?
    private var revision:UInt64=0
    @discardableResult func install(id:ScenePropID,trajectory:InsectTrajectory) -> Bool {
        guard current==nil,id.rawValue>0 else {return false}
        current=Insect(id:id,trajectory:trajectory,age:0);revision &+= 1;return true
    }
    func makeStep(_ dt:Double) -> InsectStep? {
        guard let insect=current,dt.isFinite,dt>0 else {return nil}
        return InsectStep(insectID:insect.id,startAge:insect.age,endAge:insect.age+dt,
            trajectory:insect.trajectory,revision:revision)
    }
    @discardableResult func commit(_ step:InsectStep,capture:InsectContact?) -> Bool {
        guard var insect=current,insect.id==step.insectID,revision==step.revision,
              insect.age==step.startAge,insect.trajectory==step.trajectory else {return false}
        if let contact=capture {
            guard contact.insectID==insect.id,contact.insectAge>=step.startAge,contact.insectAge<=step.endAge,
                  contact.time.isFinite,
                  insect.trajectory.isVisible(at:contact.insectAge),
                  Geometry.distance(contact.insectPosition,insect.trajectory.position(at:contact.insectAge))<1e-6,
                  Geometry.distance(contact.beakPosition,contact.insectPosition)<=insect.trajectory.collisionRadius
            else {return false}
            lastContact=contact;current=nil
        } else if step.endAge>=insect.trajectory.terminalAge {current=nil}
        else {insect.age=step.endAge;current=insect}
        revision &+= 1;return true
    }
    func snapshot(in engine:BehaviorEngine) -> [ScenePropRenderState] {
        guard let insect=current else {return []}
        let blockers=engine.world.surfaces.filter{!$0.isGround && $0.layer>0}.map(\.rect)
        return [ScenePropRenderState(id:insect.id,kind:.insect,position:insect.position,
            size:InsectTrajectory.logicalSize*insect.trajectory.worldScale,rotation:0,opacity:1,blockers:blockers,
            frameName:CatchArtGeometry.insectFrameNames[Int(insect.age/CatchArtGeometry.insectFrameDuration)%CatchArtGeometry.insectFrameNames.count],
            anchor:CGPoint(x:CatchArtGeometry.insectAnchor.x/CatchArtGeometry.insectLogicalSize.width,
                           y:CatchArtGeometry.insectAnchor.y/CatchArtGeometry.insectLogicalSize.height),
            mirrored:!insect.trajectory.facingRight(at:insect.age))]
    }
    /// Invalid worlds clear the independent entity even while paused. Cancelling
    /// its owner remains the engine/runtime's responsibility.
    @discardableResult func synchronize(in engine:BehaviorEngine) -> Bool {
        guard let insect=current else {return true}
        let t=insect.trajectory,w=engine.world
        guard engine.settings.insectCatchEnabled,w.insectArtAvailable,w.scale==t.worldScale,
              w.displays.contains(t.display),(t.screens.isEmpty || t.screens==w.screens),
              (t.displays.isEmpty || t.displays==w.displays),(t.displayIDs.isEmpty || t.displayIDs==w.displayIDs)
        else {clear();return false}
        return true
    }
    func clear() {current=nil;revision &+= 1}
}
