import Foundation
import CoreGraphics

/// Continuous-space safety shared by coordinated flight scenes. Sampling is
/// conservative: a midpoint footprint grows by max speed * half the interval,
/// enclosing every position between samples, including leg/launch boundaries.
struct FlightSceneEnvelope {
    private struct Sweep {let end:Double;let areas:[CGRect]}
    private let sweeps:[Sweep]
    private let duration:Double
    private let pointerRadius:CGFloat

    init?(routes:[CoordinatedFlightRoute],offsets:[Double],scales:[CGFloat],maximumDuration:Double=20,localFootprints:[CGRect]?=nil) {
        guard (1...2).contains(routes.count),offsets.count==routes.count,scales.count==routes.count,
              localFootprints.map({$0.count==routes.count && $0.allSatisfy{SurfaceAnchor.finite($0) && $0.width>0 && $0.height>0}}) ?? true,
              offsets.allSatisfy({$0.isFinite && $0>=0}),scales.allSatisfy({$0.isFinite && $0>0}),
              maximumDuration.isFinite,maximumDuration>0,maximumDuration<=30 else {return nil}
        let duration=zip(offsets,routes).map{$0.0+$0.1.duration}.max() ?? 0
        guard duration.isFinite,duration>0,duration<=maximumDuration else {return nil}
        let count=Int(ceil(duration*30)),dt=duration/Double(count)
        let speeds=routes.map{$0.legs.map{$0.timing.peakSpeed}.max() ?? 0}
        var result:[Sweep]=[]
        for index in 0..<count {
            let mid=(Double(index)+0.5)*dt
            let areas=routes.indices.map {actor -> CGRect in
                let foot=routes[actor].position(at:max(0,mid-offsets[actor]))
                let margin=CGFloat(speeds[actor]*dt/2)+4
                var area=Geometry.landingFootprint(at:foot,scale:scales[actor])
                if let localFootprints {area=area.union(localFootprints[actor].offsetBy(dx:foot.x,dy:foot.y))}
                return area.insetBy(dx:-margin,dy:-margin)
            }
            if areas.count==2,Self.intersects(areas[0],areas[1]) {return nil}
            result.append(Sweep(end:Double(index+1)*dt,areas:areas))
        }
        self.sweeps=result;self.duration=duration;pointerRadius=max(100,72*(scales.max() ?? 1))
    }
    private static func intersects(_ a:CGRect,_ b:CGRect) -> Bool {
        let cut=a.intersection(b);return !cut.isNull && !cut.isEmpty
    }
    func pointerIsClear(in engine:BehaviorEngine,after age:Double=0) -> Bool {
        let pointer=engine.world.pointer
        guard pointer.x.isFinite,pointer.y.isFinite else {return false}
        let protected=CGRect(x:pointer.x-pointerRadius,y:pointer.y-pointerRadius,width:2*pointerRadius,height:2*pointerRadius)
        return !sweeps.contains{$0.end+1e-9>=min(age,duration) && $0.areas.contains{Self.intersects($0,protected)}}
    }
    /// A nil display requires the caller to have bounded the complete route
    /// footprint independently; obstacle padding is always retained.
    func isClear(in engine:BehaviorEngine,excluding participants:[BirdID],display:CGRect?,after age:Double=0) -> Bool {
        let ids=Set(participants)
        // Ordinary windows allow flight overhead. Utility/system panels block it.
        var obstacles=engine.world.surfaces.filter{!$0.isGround && $0.layer>0}.map(\.rect)
        obstacles.append(contentsOf:engine.giftObstacleRects(excluding:participants))
        for other in engine.birds where engine.id(of:other).map({!ids.contains($0)}) == true {
            let scale=engine.spriteScale(for:other)
            let speed=max(other.flightSpeed,FlightBehavior.cruiseSpeed(other.profile.id,multiplier:other.profile.speed))
            let margin:CGFloat=8+(other.state == .flying ? CGFloat(speed*BehaviorEngine.step):0)
            obstacles.append(Geometry.landingFootprint(at:other.position,scale:scale)
                .union(engine.bounds(of:other)).insetBy(dx:-margin,dy:-margin))
            if other.state == .flying {
                guard let planned=other.plannedFlightFootprint(scale:scale) else {return false}
                obstacles.append(planned.insetBy(dx:-8,dy:-8))
            }
            if let host=engine.world.surfaces.first(where:{$0.id==other.hostID}) {
                let foot=Geometry.foot(on:host,fraction:other.fraction,edge:other.edge,scale:scale)
                obstacles.append(Geometry.landingFootprint(at:foot,scale:scale).insetBy(dx:-8,dy:-8))
            }
        }
        for slot in engine.runtime.landingReservations where !ids.contains(slot.bird) {
            guard let area=slot.footprint(in:engine) else {return false}
            obstacles.append(area)
        }
        for sweep in sweeps where sweep.end+1e-9>=min(age,duration) {
            for area in sweep.areas {
                guard display.map({$0.contains(area)}) ?? true,!obstacles.contains(where:{Self.intersects(area,$0)}) else {return false}
            }
        }
        return true
    }
}
