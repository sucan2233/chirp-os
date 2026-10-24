import Foundation
import CoreGraphics

public enum HabitatSurfaceKind:String,Codable {case fixedPerch,foodTray,bath}

public struct Surface: Equatable {
    public let id: UInt32
    public let pid: Int32
    public var rect: CGRect // Quartz desktop coordinates: y grows downward.
    public let layer: Int
    public let isGround: Bool
    public let habitatKind:HabitatSurfaceKind?
    public var isFixedPerch:Bool {habitatKind == .fixedPerch}
    public var isHabitat:Bool {habitatKind != nil}
    public init(id: UInt32, pid: Int32 = 0, rect: CGRect, layer: Int = 0, isGround: Bool = false, isFixedPerch:Bool = false,habitatKind:HabitatSurfaceKind?=nil) {
        self.id = id; self.pid = pid; self.rect = rect; self.layer = layer; self.isGround = isGround; self.habitatKind=habitatKind ?? (isFixedPerch ? .fixedPerch:nil)
    }
}

public enum Geometry {
    /// A virtual ledge at the work-area bottom; rect.maxY is the physical screen
    /// bottom, used to keep tails visible when the Dock/taskbar is hidden or lateral.
    public static func ground(id:UInt32,display:CGRect,workArea:CGRect) -> Surface {
        let left=max(display.minX,workArea.minX),right=min(display.maxX,workArea.maxX)
        let y=min(display.maxY,max(display.minY,workArea.maxY))
        return Surface(id:id,rect:CGRect(x:left,y:y,width:max(0,right-left),height:display.maxY-y),isGround:true)
    }
    public static func blockers(on host:Surface,surfaces:[Surface]) -> [Surface] {
        // Ground birds share the floating overlay with birds in flight. Normal
        // windows cannot invalidate this last-resort ledge, but utility panels can.
        if host.isGround || host.isHabitat { return surfaces.filter { !$0.isGround && !$0.isHabitat && $0.layer>0 } }
        guard let depth=surfaces.firstIndex(where:{$0.id==host.id}) else { return [] }
        return surfaces.prefix(depth).filter { !$0.isGround && !$0.isHabitat }
    }
    // Sequential subtraction, not even-odd clipping: overlapping occluders stay opaque.
    public static func subtract(_ rect: CGRect, _ blocker: CGRect) -> [CGRect] {
        let cut = rect.intersection(blocker)
        guard !cut.isNull, !cut.isEmpty else { return [rect] }
        return [CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: cut.minY - rect.minY),
                CGRect(x: rect.minX, y: cut.maxY, width: rect.width, height: rect.maxY - cut.maxY),
                CGRect(x: rect.minX, y: cut.minY, width: cut.minX - rect.minX, height: cut.height),
                CGRect(x: cut.maxX, y: cut.minY, width: rect.maxX - cut.maxX, height: cut.height)]
            .filter { $0.width > 0 && $0.height > 0 }
    }
    public static func visiblePieces(_ rect: CGRect, blockers: [CGRect]) -> [CGRect] {
        blockers.reduce([rect]) { pieces, blocker in pieces.flatMap { subtract($0, blocker) } }
    }
    // Reserve the whole landing sprite, including tail below the feet and either
    // facing direction. A partly exposed head is not enough for a safe arrival.
    public static func landingFootprint(at foot: CGPoint, scale: CGFloat) -> CGRect {
        CGRect(x: foot.x - 29*scale, y: foot.y - 39*scale, width: 58*scale, height: 48*scale)
    }
    public static func isLandingVisible(on hostID: UInt32, at foot: CGPoint,
                                        surfaces: [Surface], scale: CGFloat) -> Bool {
        guard let host = surfaces.first(where: { $0.id == hostID }) else { return false }
        let area = landingFootprint(at: foot, scale: scale)
        return !blockers(on:host,surfaces:surfaces).contains {
            !$0.rect.intersection(area).isEmpty && !$0.rect.intersection(area).isNull
        }
    }
    // Continuous foot-position intervals, clipped by screens, occluders and reservations.
    public static func landingRanges(on host: Surface, surfaces: [Surface], screen: CGRect,
                                     scale: CGFloat, occupied: [CGRect] = []) -> [ClosedRange<CGFloat>] {
        guard surfaces.contains(where: { $0.id == host.id }) else { return [] }
        let y = foot(on:host,fraction:0.5,edge:.top,scale:scale).y, half = 29 * scale
        guard y - 39 * scale >= screen.minY, y + 9 * scale <= screen.maxY else { return [] }
        let lo = max(perchX(0, rect: host.rect), screen.minX + half)
        let hi = min(perchX(1, rect: host.rect), screen.maxX - half)
        guard hi > lo else { return [] }
        var ranges = [lo...hi]
        for rect in blockers(on:host,surfaces:surfaces).map(\.rect) + occupied {
            guard rect.maxY > y - 39 * scale, rect.minY < y + 9 * scale else { continue }
            let left = rect.minX - half, right = rect.maxX + half
            ranges = ranges.flatMap { range -> [ClosedRange<CGFloat>] in
                if right <= range.lowerBound || left >= range.upperBound { return [range] }
                var result: [ClosedRange<CGFloat>] = []
                if left > range.lowerBound { result.append(range.lowerBound...left) }
                if right < range.upperBound { result.append(right...range.upperBound) }
                return result
            }
        }
        return ranges.filter { $0.upperBound - $0.lowerBound > 0.01 }
    }
    public static func foot(on host:Surface, fraction:CGFloat, edge:PerchEdge, scale:CGFloat=1) -> CGPoint {
        if host.isGround { return CGPoint(x:perchX(fraction,rect:host.rect),y:min(host.rect.minY,host.rect.maxY-9*scale)) }
        if edge == .top { return CGPoint(x:perchX(fraction,rect:host.rect),y:host.rect.minY) }
        return CGPoint(x:edge == .left ? host.rect.minX:host.rect.maxX,
                       y:host.rect.minY+42+max(0,host.rect.height-84)*min(1,max(0,fraction)))
    }
    public static func sideRanges(on host:Surface, edge:PerchEdge, surfaces:[Surface], screen:CGRect,
                                  scale:CGFloat, occupied:[CGRect]) -> [ClosedRange<CGFloat>] {
        guard !host.isGround, surfaces.contains(where:{$0.id==host.id}) else { return [] }
        let x=edge == .left ? host.rect.minX:host.rect.maxX
        guard x-29*scale >= screen.minX, x+29*scale <= screen.maxX else { return [] }
        let lo=max(host.rect.minY+42,screen.minY+39*scale)
        let hi=min(host.rect.maxY-42,screen.maxY-9*scale)
        guard hi>lo else { return [] }
        var ranges=[lo...hi]
        for r in blockers(on:host,surfaces:surfaces).map(\.rect)+occupied {
            guard r.maxX>x-29*scale, r.minX<x+29*scale else {continue}
            let a=r.minY-9*scale,b=r.maxY+39*scale
            ranges=ranges.flatMap { q -> [ClosedRange<CGFloat>] in
                if b<=q.lowerBound || a>=q.upperBound {return [q]}
                var result:[ClosedRange<CGFloat>]=[]
                if a>q.lowerBound {result.append(q.lowerBound...a)}
                if b<q.upperBound {result.append(b...q.upperBound)}
                return result
            }
        }
        return ranges.filter{$0.upperBound-$0.lowerBound>0.01}
    }
    public static func quartz(_ cocoa: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX, y: primaryHeight - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }
    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x-b.x, a.y-b.y) }
    public static func perchX(_ fraction: CGFloat, rect: CGRect) -> CGFloat {
        let margin = min(42, rect.width / 3)
        return rect.minX + margin + max(0, rect.width - margin * 2) * min(1, max(0, fraction))
    }
}

public enum PerchEdge { case top, left, right }

public enum BirdState: String { case flying, landing, perched }
struct AirborneFlightSnapshot {
    let position,velocity,destination:CGPoint
    let revision:UInt64
}
public final class Bird {
    public static let flightSpeedMultiplier: Double = 2
    public private(set) var isDeparting = false
    /// Changes when a route is replaced, including host-driven startles.
    public private(set) var motionRevision: UInt64 = 0
    private var wingPhase = 0.0
    public var edge: PerchEdge = .top
    public let profile: SpeciesProfile
    public var position: CGPoint
    public var state: BirdState = .flying
    public var hostID: UInt32?
    private(set) var hostPID: Int32?
    public var depthID: UInt32?
    public var fraction: CGFloat
    public var facingRight = true
    public private(set) var stateTime: Double = 0
    public var flightDuration: Double = 1.5
    public var perchDuration: Double = 15
    public private(set) var startledCount = 0
    public private(set) var landedCount = 0
    public private(set) var followedDistance: CGFloat = 0
    private var previousHost: CGRect?
    private var origin: CGPoint
    private var target: CGPoint
    private var arc: CGFloat = 90
    private var flightAge: Double = 0
    private var destinationInvalidated = false
    /// A hop has its own short ballistic clock, never a flight acceleration path.
    private struct SideHopMotion {
        let startFraction:CGFloat, endFraction:CGFloat, scale:CGFloat
        let duration:Double
        var host:Surface
        var followedHost:Surface
        var age=0.0
    }
    private var sideHopMotion:SideHopMotion?
    private struct CoordinatedMotion {
        let route:CoordinatedFlightRoute
        let host:Surface
        let scale:CGFloat
        let delay:Double
        var age=0.0
    }
    private var coordinatedMotion:CoordinatedMotion?
    var isCoordinatedFlying:Bool {coordinatedMotion != nil}
    var coordinatedFlightAge:Double? {coordinatedMotion.map{max(0,$0.age-$0.delay)}}
    var isSideHopping:Bool {sideHopMotion != nil}
    static let sideHopDuration=0.36
    static func sideHopRise(scale:CGFloat) -> CGFloat {12*scale}
    public init(position: CGPoint, fraction: CGFloat, profile: SpeciesProfile = SpeciesCatalog.standard.profile(.redWhiskeredBulbul), random: () -> Double = { Double.random(in:0..<1) }) {
        self.profile = profile
        self.perchDuration = profile.perchMin + (profile.perchMax-profile.perchMin)*random()
        self.position = position; self.origin = position; self.target = position; self.plannedTarget = position; self.fraction = fraction
    }
    private var transitDuration: Double = 1
    private var orbitDuration: Double = 0
    private var orbitCenter: CGPoint = .zero
    private var orbitRadius: CGFloat = 100
    private var orbitHeight: CGFloat = 100
    private var orbitPath:FlightPath?
    /// Translation is deliberately slower than the bird's 160...240 pt/s orbit.
    public static let pointerFollowSpeed:CGFloat = 90
    private struct PointerFollowMotion {
        let area:CGRect, footArea:CGRect, centers:CGRect
        var target:CGPoint
        var velocity:CGPoint = .zero
        var exiting=false
    }
    private var pointerFollow:PointerFollowMotion?
    var pointerFollowCenter:CGPoint? {pointerFollow == nil ? nil:orbitCenter}
    private var urgentFlight = false
    private var entryDuration=0.0, exitDuration=0.0, orbitTurns=1.0
    private var approach:FlightPath?, exitPath:FlightPath?, transitPath:FlightPath?
    private var plannedTarget:CGPoint = .zero
    private var approachTiming:FlightTiming?, exitTiming:FlightTiming?, transitTiming:FlightTiming?
    private var cruiseSpeed=0.0
    public private(set) var flightSpeed=0.0
    private var flightVelocity:CGPoint = .zero
    /// Actual last-step velocity, never a guessed vector toward the destination.
    /// The snapshot does not advance simulation or consume randomness.
    var airborneFlight:AirborneFlightSnapshot? {
        guard state == .flying,stateTime>=0.3,!isDeparting,!needsDestination,!urgentFlight,
              coordinatedMotion==nil,sideHopMotion==nil,pointerFollow==nil,hostID != nil,
              flightDuration-flightAge>0.8,
              flightVelocity.x.isFinite,flightVelocity.y.isFinite,
              Geometry.distance(.zero,flightVelocity)>=60 else {return nil}
        return AirborneFlightSnapshot(position:position,velocity:flightVelocity,destination:target,revision:motionRevision)
    }
    public private(set) var isGliding=false
    public var isBraking:Bool {
        if let motion=coordinatedMotion {return motion.route.isBraking(at:max(0,motion.age-motion.delay))}
        if orbitDuration>0 {
            return flightAge>=entryDuration+orbitDuration && flightAge-entryDuration-orbitDuration >= (exitTiming?.brakeStart ?? .infinity)-0.12
        }
        return flightAge >= (transitTiming?.brakeStart ?? .infinity)-0.12
    }
    public var isCircling: Bool { orbitDuration > 0 && flightAge >= entryDuration && flightAge < entryDuration + orbitDuration }
    /// Read-only phase of the current orbit: negative on approach, 0...1 for
    /// one lap, and greater than one on exit. Retained during landing so scene
    /// props can join the exit continuously without advancing the bird's clock.
    var orbitProgress:Double? {
        guard orbitDuration>0,orbitTurns>0 else {return nil}
        return (flightAge-entryDuration)/orbitDuration*orbitTurns
    }
    private var orbitPoint:CGPoint {
        let turns=max(0,(flightAge-entryDuration)/max(0.001,orbitDuration))*orbitTurns
        return orbitPath!.point(turns.truncatingRemainder(dividingBy:1))
    }
    // Transit speed and time spent airborne are separate: soaring must not be
    // squeezed into the old window-to-window travel duration.

    public func fly(to point: CGPoint, host: Surface?, duration: Double = 3, arc: CGFloat = 90, airspace: CGRect? = nil, urgent: Bool = false, allowsOrbit:Bool = true, pointerOrbit: PointerOrbit? = nil, random: () -> Double = { Double.random(in:0...1) }) {
        flightVelocity = .zero
        coordinatedMotion=nil
        sideHopMotion=nil
        pointerFollow=nil
        isDeparting = false
        motionRevision &+= 1; wingPhase = 0
        if host?.isGround == true { edge = .top }
        origin = position; target = point; hostID = host?.id; hostPID = host?.pid; depthID = nil
        previousHost = nil
        let m = FlightBehavior.motion(profile.id)
        urgentFlight = urgent
        transitDuration = max(0.3, duration) / (Self.flightSpeedMultiplier * profile.speed)
        orbitDuration = urgent || !allowsOrbit ? 0 : m.orbit
        flightDuration = transitDuration + orbitDuration
        self.arc = arc
        let normalCruise=FlightBehavior.cruiseSpeed(profile.id,multiplier:profile.speed)*Self.flightSpeedMultiplier/2
        let cruise=pointerOrbit == nil ? normalCruise : min(240,max(160,normalCruise*0.7))
        if orbitDuration>0 {
            let radii=FlightBehavior.orbitRadii(width:Double(airspace?.width ?? max(800,Geometry.distance(origin,point)*1.5)),height:Double(airspace?.height ?? 800),widthSample:random(),heightSample:random())
            orbitRadius=radii.width;orbitHeight=radii.height
            orbitPath=FlightBehavior.orbitPath(horizontal:Double(orbitRadius),vertical:Double(orbitHeight))
            // Fractional laps preserve both chosen width and cruise speed. Exit
            // tangentially wherever the bird is when its circling time expires.
            orbitTurns=orbitDuration*cruise/max(1,orbitPath!.length)
        }
        orbitCenter = CGPoint(x: (origin.x + point.x) / 2, y: min(origin.y, point.y) - 40)
        if let area = airspace {
            orbitCenter.x = min(area.maxX - orbitRadius, max(area.minX + orbitRadius, orbitCenter.x))
            orbitCenter.y = min(area.maxY - orbitHeight, max(area.minY + orbitHeight, orbitCenter.y))
            // A transit arch must also fit above the destination screen's edge.
            self.arc = min(arc, max(0, min(origin.y, point.y) - area.minY))
        }
        if let pointerOrbit {
            orbitCenter=pointerOrbit.center;orbitRadius=pointerOrbit.radius;orbitHeight=pointerOrbit.radius
            orbitPath=pointerOrbit.path;orbitTurns=1;orbitDuration=pointerOrbit.path.length/cruise
        }
        if orbitRadius < 24 || orbitHeight < 12 { orbitDuration = 0 }
        plannedTarget=point
        cruiseSpeed=cruise;isGliding=false;flightSpeed=0;transitTiming=nil
        func inside(_ p:CGPoint) -> CGPoint {
            guard let area=airspace else { return p }
            return CGPoint(x:min(area.maxX,max(area.minX,p.x)),y:min(area.maxY,max(area.minY,p.y)))
        }
        if orbitDuration>0 {
            let first=orbitPath!.point(0),entryTangent=orbitPath!.loopTangent(0)
            let entry=CGPoint(x:orbitCenter.x+first.x,y:orbitCenter.y+first.y)
            let arriveBend=min(orbitHeight*0.8,Geometry.distance(origin,entry)*0.4)
            let last=orbitPath!.point(orbitTurns.truncatingRemainder(dividingBy:1))
            let exit=CGPoint(x:orbitCenter.x+last.x,y:orbitCenter.y+last.y)
            let tangent=orbitPath!.loopTangent(orbitTurns)
            var leaveBend=min(orbitHeight*0.8,Geometry.distance(exit,point)*0.4)
            // Shorten the tangent as a whole near screen edges; clamping its
            // coordinates independently would introduce a sudden heading change.
            if let area=airspace {
                if tangent.x>0.000001 { leaveBend=min(leaveBend,(area.maxX-exit.x)/tangent.x) }
                if tangent.x < -0.000001 { leaveBend=min(leaveBend,(area.minX-exit.x)/tangent.x) }
                if tangent.y>0.000001 { leaveBend=min(leaveBend,(area.maxY-exit.y)/tangent.y) }
                if tangent.y < -0.000001 { leaveBend=min(leaveBend,(area.minY-exit.y)/tangent.y) }
            }
            approach=FlightPath(origin,inside(CGPoint(x:origin.x+(entry.x-origin.x)*0.35,y:origin.y+(entry.y-origin.y)*0.35)),inside(CGPoint(x:entry.x-entryTangent.x*arriveBend,y:entry.y-entryTangent.y*arriveBend)),entry)
            let exitControl = pointerOrbit == nil ? CGPoint(x:point.x,y:point.y-min(self.arc,leaveBend)) : CGPoint(x:exit.x+(point.x-exit.x)*0.65,y:exit.y+(point.y-exit.y)*0.65)
            exitPath=FlightPath(exit,inside(CGPoint(x:exit.x+tangent.x*leaveBend,y:exit.y+tangent.y*leaveBend)),inside(exitControl),point)
            // Match the tangential speed on both sides of the orbit join.
            approachTiming=FlightTiming(distance:approach!.length,speed:cruiseSpeed,acceleration:min(0.65,1.8*approach!.length/cruiseSpeed),deceleration:0)
            exitTiming=FlightTiming(distance:exitPath!.length,speed:cruiseSpeed,acceleration:0,deceleration:min(0.85,1.8*exitPath!.length/cruiseSpeed))
            entryDuration=approachTiming!.duration;exitDuration=exitTiming!.duration
            transitDuration=entryDuration+exitDuration
        } else {
            transitPath=FlightPath(origin,CGPoint(x:origin.x+(point.x-origin.x)/3,y:origin.y+(point.y-origin.y)/3-self.arc*4/3),CGPoint(x:origin.x+(point.x-origin.x)*2/3,y:origin.y+(point.y-origin.y)*2/3-self.arc*4/3),point)
            if !urgent {
                transitTiming=FlightTiming(distance:transitPath!.length,speed:cruise)
                transitDuration=transitTiming!.duration;cruiseSpeed=transitTiming!.peakSpeed
            }
        }
        flightDuration=transitDuration+orbitDuration
        flightAge = 0; stateTime = 0; state = .flying; destinationInvalidated = false
    }
    /// Opt in immediately after planning a pointer orbit. The approach stays fixed;
    /// input collected during entry becomes the target when circling starts.
    /// Following never resets flightAge, motionRevision, or the one-lap deadline.
    @discardableResult
    public func enablePointerFollow(in area:CGRect,spriteScale:CGFloat) -> Bool {
        guard state == .flying,flightAge == 0,orbitDuration>0,
              spriteScale.isFinite,spriteScale>0,
              area.minX.isFinite,area.minY.isFinite,area.width.isFinite,area.height.isFinite else {return false}
        let margin=45*spriteScale
        guard area.width>2*(orbitRadius+margin),area.height>2*(orbitHeight+margin) else {return false}
        let centers=area.insetBy(dx:orbitRadius+margin,dy:orbitHeight+margin)
        guard centers.contains(orbitCenter) else {return false}
        pointerFollow=PointerFollowMotion(area:area,footArea:area.insetBy(dx:margin,dy:margin),
                                         centers:centers,target:orbitCenter)
        return true
    }
    /// Same-screen input is clamped to the safe circle-center rectangle. This
    /// changes only a target; tick integrates the center once per simulation step.
    @discardableResult
    public func updatePointerFollowTarget(_ point:CGPoint) -> Bool {
        guard var follow=pointerFollow,point.x.isFinite,point.y.isFinite,
              follow.area.contains(point) else {return false}
        follow.target=CGPoint(x:min(follow.centers.maxX,max(follow.centers.minX,point.x)),
                              y:min(follow.centers.maxY,max(follow.centers.minY,point.y)))
        pointerFollow=follow
        return true
    }
    private func advancePointerFollow(from oldAge:Double,to age:Double) {
        guard var follow=pointerFollow,!follow.exiting else {return}
        let end=entryDuration+orbitDuration
        let start=max(oldAge,entryDuration),stop=min(age,end)
        if stop>start {
            let dt=stop-start,mid=(start+stop)/2
            // Ease translation in and out without slowing the bird's orbit. The
            // center is stationary at both joins, preserving their tangents.
            let ramp=min(0.6,orbitDuration/2)
            let phase=min(1,max(0,min(mid-entryDuration,end-mid)/ramp))
            let envelope=phase*phase*(3-2*phase)
            let delta=CGPoint(x:follow.target.x-orbitCenter.x,y:follow.target.y-orbitCenter.y)
            let distance=Geometry.distance(.zero,delta)
            let speed=min(Self.pointerFollowSpeed,distance/0.35)
            let desired=distance>0 ? CGPoint(x:delta.x/distance*speed,y:delta.y/distance*speed):.zero
            let blend=1-exp(-dt/0.18)
            follow.velocity.x+=(desired.x-follow.velocity.x)*blend
            follow.velocity.y+=(desired.y-follow.velocity.y)*blend
            let candidate=CGPoint(x:orbitCenter.x+follow.velocity.x*dt*envelope,
                                  y:orbitCenter.y+follow.velocity.y*dt*envelope)
            orbitCenter=CGPoint(x:min(follow.centers.maxX,max(follow.centers.minX,candidate.x)),
                                y:min(follow.centers.maxY,max(follow.centers.minY,candidate.y)))
            if candidate.x != orbitCenter.x {follow.velocity.x=0}
            if candidate.y != orbitCenter.y {follow.velocity.y=0}
        }
        if age>=end {
            follow.exiting=true;follow.velocity = .zero
            // Plan exactly once from the translated ring, using the current host
            // target. Future pointer movement cannot extend or bend this exit.
            let p=orbitPath!.point(orbitTurns.truncatingRemainder(dividingBy:1))
            let exit=CGPoint(x:orbitCenter.x+p.x,y:orbitCenter.y+p.y)
            let tangent=orbitPath!.loopTangent(orbitTurns)
            var bend=min(orbitHeight*0.8,Geometry.distance(exit,target)*0.4)
            let area=follow.footArea
            if tangent.x>0.000001 {bend=min(bend,(area.maxX-exit.x)/tangent.x)}
            if tangent.x < -0.000001 {bend=min(bend,(area.minX-exit.x)/tangent.x)}
            if tangent.y>0.000001 {bend=min(bend,(area.maxY-exit.y)/tangent.y)}
            if tangent.y < -0.000001 {bend=min(bend,(area.minY-exit.y)/tangent.y)}
            bend=max(0,bend)
            exitPath=FlightPath(exit,CGPoint(x:exit.x+tangent.x*bend,y:exit.y+tangent.y*bend),
                                CGPoint(x:exit.x+(target.x-exit.x)*0.65,y:exit.y+(target.y-exit.y)*0.65),target)
            plannedTarget=target
            exitTiming=FlightTiming(distance:exitPath!.length,speed:cruiseSpeed,acceleration:0,
                                    deceleration:min(0.85,1.8*exitPath!.length/cruiseSpeed))
            exitDuration=exitTiming!.duration;transitDuration=entryDuration+exitDuration
            flightDuration=end+exitDuration
        }
        pointerFollow=follow
    }
    public func depart(to point: CGPoint, duration: Double) {
        fly(to: point, host: nil, duration: duration, arc: 30, urgent: true)
        isDeparting = true
    }
    /// A transient visitor cruises beyond the display edge without braking on
    /// screen. It never lands or enters the resident population.
    public func passThrough(_ plan: FlockMemberPlan) {
        fly(to:plan.path.point(1),host:nil,urgent:true)
        isDeparting=true;urgentFlight=false;wingPhase=plan.wingPhase
        transitPath=plan.path
        transitTiming=FlightTiming(distance:plan.path.length,speed:plan.speed,acceleration:0,deceleration:0)
        transitDuration=transitTiming!.duration;flightDuration=transitDuration;cruiseSpeed=plan.speed
    }
    public var departureFinished: Bool { isDeparting && flightAge >= flightDuration }
    public func perch(on host: Surface, spriteScale:CGFloat=1) {
        flightVelocity = .zero
        coordinatedMotion=nil
        sideHopMotion=nil
        pointerFollow=nil
        motionRevision &+= 1;isDeparting=false
        if host.isGround { edge = .top }
        hostID = host.id; hostPID = host.pid; depthID = host.id; previousHost = host.rect
        position = Geometry.foot(on:host,fraction:fraction,edge:edge,scale:spriteScale)
        state = .perched; stateTime = 0; destinationInvalidated = false;isGliding=false;flightSpeed=0
        if edge != .top { facingRight = edge == .left }
    }
    /// Installs motion without changing position. Only tick advances feet or age.
    @discardableResult
    func beginSideHop(on host:Surface,to endFraction:CGFloat,spriteScale:CGFloat) -> Bool {
        guard sideHopMotion == nil,coordinatedMotion == nil,state == .perched,edge == .top,!isDeparting,!needsDestination,
              host.id==hostID,host.pid==hostPID,spriteScale.isFinite,spriteScale>0,
              endFraction.isFinite,(0...1).contains(endFraction),fraction.isFinite,
              Geometry.distance(position,Geometry.foot(on:host,fraction:fraction,edge:.top,scale:spriteScale))<0.001 else {return false}
        let distance=abs(Geometry.perchX(endFraction,rect:host.rect)-position.x)/spriteScale
        guard distance>=60-0.001,distance<=110+0.001 else {return false}
        sideHopMotion=SideHopMotion(startFraction:fraction,endFraction:endFraction,scale:spriteScale,
            duration:Self.sideHopDuration,host:host,followedHost:host)
        pointerFollow=nil;orbitDuration=0;orbitPath=nil;transitPath=nil;transitTiming=nil
        approach=nil;exitPath=nil;approachTiming=nil;exitTiming=nil
        motionRevision &+= 1;flightAge=0;flightDuration=Self.sideHopDuration
        state = .flying;stateTime=0;destinationInvalidated=false;isGliding=false;flightSpeed=0
        depthID=host.id;previousHost=host.rect
        return true
    }
    /// Metadata changes only the pending host. Pause therefore freezes even a
    /// gently moving window until the next allowed simulation step.
    @discardableResult
    func updateSideHopHost(_ host:Surface,spriteScale:CGFloat) -> Bool {
        guard var hop=sideHopMotion,host.id==hostID,host.pid==hostPID,
              hop.host.isGround==host.isGround,host.rect.size==hop.host.rect.size,
              spriteScale==hop.scale else {return false}
        hop.host=host;sideHopMotion=hop
        return true
    }
    /// Preserve the actual airborne anchor. A future route starts here, and an
    /// absent route leaves a destination request rather than resuming stale flight.
    func cancelSideHop() {
        guard sideHopMotion != nil else {return}
        sideHopMotion=nil;motionRevision &+= 1
        hostID=nil;hostPID=nil;depthID=nil;previousHost=nil
        state = .flying;stateTime=0;destinationInvalidated=true;flightSpeed=0;isGliding=false
    }
    func finishSideHop() {
        guard state == .perched else {return}
        sideHopMotion=nil
    }
    private func advanceSideHop(_ dt:Double) {
        guard var hop=sideHopMotion else {return}
        let old=position
        let delta=CGPoint(x:hop.host.rect.minX-hop.followedHost.rect.minX,
                          y:hop.host.rect.minY-hop.followedHost.rect.minY)
        let distance=Geometry.distance(.zero,delta),limit=360*dt
        let amount=distance>0 ? min(1,limit/distance):1
        hop.followedHost.rect.origin.x+=delta.x*amount
        hop.followedHost.rect.origin.y+=delta.y*amount
        hop.age+=dt
        let t=min(1,hop.age/hop.duration),u=CGFloat(t*t*(3-2*t))
        fraction=hop.startFraction+(hop.endFraction-hop.startFraction)*u
        let foot=Geometry.foot(on:hop.followedHost,fraction:fraction,edge:.top,scale:hop.scale)
        position=CGPoint(x:foot.x,y:foot.y-Self.sideHopRise(scale:hop.scale)*CGFloat(sin(.pi*t)))
        facingRight=hop.endFraction>hop.startFraction
        flightSpeed=Double(Geometry.distance(old,position))/max(0.000001,dt)
        if t>=1,distance<=limit+0.000001 {
            position=foot
            if state == .flying {
                state = .landing;stateTime=0;landedCount+=1;flightSpeed=0
            } else if state == .landing,stateTime>0.42 {
                // Keep metadata queued until the execution observes completion.
                // A pause between this tick and runtime detachment must still
                // freeze the anchor, including on window metadata updates.
                state = .perched;stateTime=0;sideHopMotion=hop
                previousHost=hop.host.rect
                return
            }
        }
        sideHopMotion=hop
    }
    /// Reserve/plan first, then install without changing the current feet. Host
    /// geometry remains fixed for this route; changes request safe recovery.
    func canBeginCoordinatedFlight(_ route:CoordinatedFlightRoute,on host:Surface,fraction:CGFloat,spriteScale:CGFloat,delay:Double=0,airborne:Bool=false,allowExpiredPerch:Bool=false) -> Bool {
        let snapshot=airborneFlight
        guard coordinatedMotion==nil,sideHopMotion==nil,(airborne ? snapshot != nil:state == .perched),edge == .top,
              !isDeparting,(!needsDestination || (allowExpiredPerch && !airborne && state == .perched && !destinationInvalidated)),spriteScale.isFinite,spriteScale>0,
              fraction.isFinite,(0...1).contains(fraction),delay.isFinite,(0...5).contains(delay),
              delay==0 || (hostID==host.id && hostPID==host.pid),
              Geometry.distance(position,route.position(at:0))<0.001,
              Geometry.distance(Geometry.foot(on:host,fraction:fraction,edge:.top,scale:spriteScale),
                                route.position(at:route.duration))<0.001 else {return false}
        if airborne {
            guard let snapshot,delay==0,hostID==host.id,hostPID==host.pid,self.fraction==fraction,
                  Geometry.distance(snapshot.destination,route.position(at:route.duration))<0.001,
                  abs(route.speed(at:0)-Double(Geometry.distance(.zero,snapshot.velocity)))<0.1 else {return false}
            let step=route.position(at:0.001),dx=step.x-position.x,dy=step.y-position.y
            let length=hypot(dx,dy),speed=route.speed(at:0)
            guard length>0 else {return false}
            let incoming=CGPoint(x:dx/length*speed,y:dy/length*speed)
            // Permit only the small error introduced by polyline arc-length
            // lookup, never an otherwise visible turn at the handoff boundary.
            guard Geometry.distance(incoming,snapshot.velocity)<=max(2,speed*0.01) else {return false}
        }
        return true
    }
    @discardableResult
    func beginCoordinatedFlight(_ route:CoordinatedFlightRoute,on host:Surface,fraction:CGFloat,spriteScale:CGFloat,delay:Double=0,airborne:Bool=false,allowExpiredPerch:Bool=false) -> Bool {
        guard canBeginCoordinatedFlight(route,on:host,fraction:fraction,spriteScale:spriteScale,delay:delay,airborne:airborne,allowExpiredPerch:allowExpiredPerch) else {return false}
        let snapshot=airborneFlight
        let phase=flightAge+wingPhase
        fly(to:route.position(at:route.duration),host:host,arc:0,urgent:true,allowsOrbit:false,random:{0.5})
        if airborne,let snapshot {flightVelocity=snapshot.velocity;flightSpeed=Double(Geometry.distance(.zero,snapshot.velocity));wingPhase=phase}
        self.fraction=fraction
        coordinatedMotion=CoordinatedMotion(route:route,host:host,scale:spriteScale,delay:delay)
        if delay>0 {state = .perched;depthID=host.id;previousHost=host.rect}
        flightDuration=route.duration;cruiseSpeed=route.legs.map{$0.timing.peakSpeed}.max() ?? 1
        return true
    }
    func cancelCoordinatedFlight() {
        guard coordinatedMotion != nil else {return}
        requestFlightRecovery()
    }
    /// Release an interrupted scene at its actual feet. Ordinary routing can
    /// choose a fresh destination once simulation resumes.
    func requestFlightRecovery() {
        flightVelocity = .zero
        coordinatedMotion=nil;sideHopMotion=nil;pointerFollow=nil;motionRevision &+= 1
        hostID=nil;hostPID=nil;depthID=nil;previousHost=nil
        state = .flying;stateTime=0;destinationInvalidated=true;flightSpeed=0;isGliding=false
    }
    func finishCoordinatedFlight() {
        guard state == .perched else {return}
        coordinatedMotion=nil
    }
    private func advanceCoordinatedFlight(_ dt:Double) {
        guard var motion=coordinatedMotion else {return}
        let wasWaiting=motion.age<=motion.delay && state == .perched
        motion.age=min(motion.delay+motion.route.duration,motion.age+dt)
        if wasWaiting {
            guard motion.age>motion.delay else {coordinatedMotion=motion;return}
            state = .flying;stateTime=motion.age-motion.delay;depthID=nil
        }
        if state == .flying {
            let flightTime=max(0,motion.age-motion.delay)
            let next=motion.route.position(at:flightTime)
            if abs(next.x-position.x)>0.05 {facingRight=next.x>position.x}
            flightSpeed=Double(Geometry.distance(position,next))/max(0.000001,dt)
            position=next;flightAge=flightTime;isGliding=false
            if flightTime+1e-10>=motion.route.duration {
                position=motion.route.position(at:motion.route.duration)
                depthID=hostID;state = .landing;stateTime=0;landedCount+=1;flightSpeed=0
            }
        } else if state == .landing,stateTime>0.42 {
            state = .perched;stateTime=0;previousHost=motion.host.rect
        }
        coordinatedMotion=motion
    }
    public func flee() {
        startledCount += 1
        fly(to: CGPoint(x: position.x + (facingRight ? 210 : -210), y: position.y - 100), host: nil, duration: 1.25, arc: 45, urgent: true)
    }
    // Called at the actual metadata sampling interval, independent of animation frames.
    public func updateHost(surfaces: [Surface], sampleDT: Double, spriteScale: CGFloat = 1) {
        guard let id = hostID else { return }
        if let motion=coordinatedMotion {
            guard let host=surfaces.first(where:{$0.id==id && $0.pid==hostPID}),
                  host==motion.host,spriteScale==motion.scale else {cancelCoordinatedFlight();return}
            return
        }
        if let hop=sideHopMotion {
            guard let host=surfaces.first(where:{$0.id==id && $0.pid==hostPID}),
                  updateSideHopHost(host,spriteScale:spriteScale) else {cancelSideHop();return}
            let delta=Geometry.distance(host.rect.origin,hop.host.rect.origin)
            if !host.isGround,sampleDT<0.20,delta>8,delta/max(0.016,sampleDT)>950 {cancelSideHop()}
            return
        }
        // Window IDs can be reused between samples, including the first landing
        // frame. Reject a different owner before calculating or adopting its feet.
        guard let host = surfaces.first(where: { $0.id == id && $0.pid == hostPID }) else { flee(); return }
        let point = Geometry.foot(on:host,fraction:fraction,edge:edge,scale:spriteScale)
        if state == .flying && !Geometry.isLandingVisible(on: id, at: point, surfaces: surfaces, scale: spriteScale) {
            // Stay exactly where we are until the controller chooses a new route.
            // This is a blocked destination, not a startle or an instantaneous landing.
            hostID = nil; hostPID = nil; depthID = nil; previousHost = nil
            destinationInvalidated = true
            return
        }
        if state != .flying {
            if let old = previousHost {
                let delta = Geometry.distance(host.rect.origin, old.origin)
                // Ignore long sampling gaps (sleep/Space transitions) when estimating velocity.
                if !host.isGround && sampleDT < 0.20 && delta > 8 && delta / max(0.016, sampleDT) > 950 {
                    flee(); return
                }
                followedDistance += Geometry.distance(position, point)
            }
            position = point
        } else { target = point }
        previousHost = host.rect
    }
    public func tick(_ dt: Double) {
        guard !destinationInvalidated else { return }
        let previousPosition=position
        defer {
            if state == .flying,dt>0 {
                flightVelocity=CGPoint(x:(position.x-previousPosition.x)/dt,y:(position.y-previousPosition.y)/dt)
            } else {flightVelocity = .zero}
        }
        stateTime += dt
        if coordinatedMotion != nil {advanceCoordinatedFlight(dt);return}
        if sideHopMotion != nil {advanceSideHop(dt);return}
        if state == .flying {
            let oldAge=flightAge
            flightAge += dt
            advancePointerFollow(from:oldAge,to:flightAge)
            let t = min(1, flightAge / flightDuration)
            let m = FlightBehavior.motion(profile.id)
            let next: CGPoint
            if orbitDuration > 0 {
                if flightAge < entryDuration {
                    next=approach!.point(approachTiming!.progress(at:flightAge))
                } else if isCircling {
                    let p=orbitPoint
                    next=CGPoint(x:orbitCenter.x+p.x,y:orbitCenter.y+p.y)
                } else {
                    let u=exitTiming!.progress(at:flightAge-entryDuration-orbitDuration)
                    let p=exitPath!.point(u)
                    next=CGPoint(x:p.x+(target.x-plannedTarget.x)*u,y:p.y+(target.y-plannedTarget.y)*u)
                }
            } else {
                let u=transitTiming?.progress(at:flightAge) ?? FlightBehavior.travelProgress(t,duration:transitDuration),p=transitPath?.point(u) ?? origin
                let wave = urgentFlight ? 0 : m.wave * sin(2 * .pi * (flightAge+wingPhase) / m.cycle) * pow(sin(t * .pi), 2)
                next=CGPoint(x:p.x+(target.x-plannedTarget.x)*u,y:p.y+(target.y-plannedTarget.y)*u+wave)
            }
            if abs(next.x-position.x) > 0.05 { facingRight = next.x > position.x }
            let destination=t >= 1 ? target:next
            flightSpeed=Double(Geometry.distance(position,destination))/max(0.000001,dt)
            position=destination
            isGliding = !urgentFlight && t<1 && FlightBehavior.shouldGlide(profile.id,age:flightAge,fps:profile.flapFPS,speed:flightSpeed,cruise:cruiseSpeed,braking:isBraking,wasGliding:isGliding)
            if t >= 1 && hostID != nil {
                // Only adopt the host's depth once the feet have reached its top edge.
                depthID = hostID
                state = .landing; stateTime = 0; landedCount += 1
                if edge != .top { facingRight = edge == .left }
            }
        } else if state == .landing && stateTime > 0.42 {
            state = .perched; stateTime = 0
        }
    }
    public var needsDestination: Bool {
        !isDeparting && (destinationInvalidated || (state == .flying && flightAge >= flightDuration && hostID == nil) ||
        (state == .perched && stateTime >= perchDuration))
    }
    /// Conservative read-only envelope for a peer's already planned flight.
    /// Host correction can exceed last frame's velocity; include its entire
    /// translated path, not just a speed-based margin around the current feet.
    func plannedFlightFootprint(scale:CGFloat) -> CGRect? {
        guard state == .flying,scale.isFinite,scale>0 else {return nil}
        if destinationInvalidated {return Geometry.landingFootprint(at:position,scale:scale)}
        var area=CGRect(origin:position,size:.zero)
        func include(_ rect:CGRect) {if !rect.isNull {area=area.union(rect)}}
        if let motion=coordinatedMotion {
            for leg in motion.route.legs {include(leg.path.bounds)}
        } else if let hop=sideHopMotion {
            for host in [hop.host,hop.followedHost] {
                for fraction in [hop.startFraction,hop.endFraction] {
                    let foot=Geometry.foot(on:host,fraction:fraction,edge:.top,scale:hop.scale)
                    include(CGRect(origin:foot,size:.zero))
                    include(CGRect(x:foot.x,y:foot.y-Self.sideHopRise(scale:hop.scale),width:0,height:0))
                }
            }
        } else {
            let dx=target.x-plannedTarget.x,dy=target.y-plannedTarget.y
            for path in [transitPath,exitPath].compactMap({$0}) {
                include(path.bounds);include(path.bounds.offsetBy(dx:dx,dy:dy))
            }
            if let approach {include(approach.bounds)}
            if let orbitPath {include(orbitPath.bounds.offsetBy(dx:orbitCenter.x,dy:orbitCenter.y))}
            // Pointer following's future exit controls stay in the permitted
            // airspace or on the segment to its destination.
            if let follow=pointerFollow {include(follow.footArea)}
            include(CGRect(origin:target,size:.zero))
            let wave=urgentFlight ? 0:abs(FlightBehavior.motion(profile.id).wave)
            area=area.insetBy(dx:0,dy:-wave)
        }
        guard area.minX.isFinite,area.minY.isFinite,area.width.isFinite,area.height.isFinite else {return nil}
        return CGRect(x:area.minX-29*scale,y:area.minY-39*scale,width:area.width+58*scale,height:area.height+48*scale)
    }
    public func blockers(in surfaces: [Surface]) -> [CGRect] {
        if let depthID, let host = surfaces.first(where: { $0.id == depthID }) {
            return Geometry.blockers(on:host,surfaces:surfaces).map(\.rect)
        }
        // Every flight is above normal windows; menus / utility panels still cover it.
        return surfaces.filter { !$0.isGround && $0.layer > 0 }.map(\.rect)
    }
    public var hopOffset: CGFloat {
        guard state == .perched, edge == .top else { return 0 }
        return CGFloat(SpeciesBehavior.hop(profile.id, age: stateTime))
    }
    public var frameName: String {
        if sideHopMotion != nil,state == .perched {return "stand"}
        if let hop=sideHopMotion,state == .flying {
            // Use existing landing/standing artwork without assigning unverified
            // takeoff semantics to a frame or introducing a flap sequence.
            return hop.age<0.05 ? "land0":"stand"
        }
        switch state {
        case .flying:
            return FlightBehavior.frame(profile.id,age:flightAge+wingPhase,fps:profile.flapFPS,gliding:isGliding,banking:isCircling ? -orbitPoint.x/orbitRadius:0)
        case .landing: if edge != .top { return "cling0" }; return "land\(min(2, Int(stateTime / 0.14)))"
        case .perched:
            return SpeciesBehavior.frame(profile.id, age: stateTime, side: edge != .top) ?? "stand"
        }
    }
}
