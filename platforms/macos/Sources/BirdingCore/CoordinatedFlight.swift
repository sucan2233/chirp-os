import Foundation
import CoreGraphics

/// Immutable path and clock for one leg of a coordinated scene. Live models
/// only sample this through Bird.tick; planners may inspect it without RNG.
struct CoordinatedFlightLeg {
    let path:FlightPath
    let timing:FlightTiming
    init(path:FlightPath,timing:FlightTiming) {self.path=path;self.timing=timing}
}

struct CoordinatedFlightRoute {
    let legs:[CoordinatedFlightLeg]
    let duration:Double
    init?(legs:[CoordinatedFlightLeg]) {
        guard !legs.isEmpty,legs.count<=8 else {return nil}
        var duration=0.0
        for (index,leg) in legs.enumerated() {
            let timing=leg.timing
            guard leg.path.length.isFinite,leg.path.length>0.01,
                  timing.duration.isFinite,timing.duration>0,timing.peakSpeed.isFinite,timing.peakSpeed>0,
                  timing.acceleration.isFinite,timing.acceleration>=0,
                  timing.deceleration.isFinite,timing.deceleration>=0,
                  abs(timing.distance-leg.path.length)<0.001 else {return nil}
            for sample in 0...64 {
                let point=leg.path.point(Double(sample)/64)
                guard point.x.isFinite,point.y.isFinite else {return nil}
            }
            if index>0 {
                let previous=legs[index-1]
                guard Geometry.distance(previous.path.point(1),leg.path.point(0))<0.001,
                      abs(previous.timing.speed(at:previous.timing.duration)-timing.speed(at:0))<0.01 else {return nil}
            }
            duration+=timing.duration
        }
        guard duration<=30 else {return nil}
        self.legs=legs;self.duration=duration
    }
    private func segment(at age:Double) -> (CoordinatedFlightLeg,Double) {
        var remaining=max(0,age.isFinite ? age:0)
        for leg in legs {
            if remaining<leg.timing.duration {return (leg,remaining)}
            remaining-=leg.timing.duration
        }
        return (legs.last!,legs.last!.timing.duration)
    }
    func position(at age:Double) -> CGPoint {
        let (leg,time)=segment(at:age)
        return leg.path.point(leg.timing.progress(at:time))
    }
    func speed(at age:Double) -> Double {
        let (leg,time)=segment(at:age);return leg.timing.speed(at:time)
    }
    func isBraking(at age:Double) -> Bool {
        let (leg,time)=segment(at:age)
        return leg.timing.deceleration>0 && time>=leg.timing.brakeStart-0.12
    }
}
