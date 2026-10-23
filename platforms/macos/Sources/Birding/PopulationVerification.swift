import AppKit
import BirdingCore

final class PopulationVerification {
    unowned let desktop: DesktopController
    let path: String
    var checks: [String:Bool] = [:]
    init(desktop: DesktopController,path:String) { self.desktop = desktop; self.path = path }
    func start() {
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) {
            let d = self.desktop
            // Own the verification clock so the first rendered state is observed
            // before a wall-clock delay can skip the entire screen-edge crossing.
            d.timer?.invalidate()
            self.checks["startsWithNoBirds"] = d.birds.isEmpty
            for _ in 0..<120 {
                d.advanceBirds(BehaviorEngine.step)
                if !d.birds.isEmpty {break}
            }
            self.checks["firstArrivalIsOneBird"] = d.birds.count == 1 && d.arrivalCount == 1
            d.automaticPopulation = false
            if let bird = d.birds.first {
                self.traceArrival(bird,prefix:"arrival")
                let current = bird.position
                d.sendAway(bird)
                self.checks["departureStartsWithoutTeleporting"] = bird.position == current && bird.isDeparting && bird.hostID == nil
                bird.tick(bird.flightDuration/2)
                self.checks["departingBirdRetainedDuringFlight"] = d.birds.contains{$0 === bird} && !bird.departureFinished && !bird.needsDestination
                bird.tick(bird.flightDuration)
                d.advanceBirds(1.0/60)
                self.checks["removedOnlyAfterFlyingOffscreen"] = !d.birds.contains{$0 === bird} && !d.displayRects.contains{$0.intersects(d.bounds(of:bird))}
            }
            d.bringInBird()
            if let bird=d.birds.last {self.traceArrival(bird,prefix:"subsequentArrival")}
            let previous = d.birds.count
            d.population.setRange(PopulationRange(lower:8,upper:12)!)
            self.checks["changingRangeDoesNotSpawnABatch"] = d.birds.count == previous
            let passed=self.checks.count == 12 && self.checks.values.allSatisfy{$0}
            saveJSON(["passed":passed,"checks":self.checks],to:URL(fileURLWithPath:self.path))
            exit(passed ? 0 : 1)
        }
    }

    private func traceArrival(_ bird:Bird,prefix:String) {
        let d=desktop,displays=d.displayRects
        guard let id=d.engine.id(of:bird),let origin=d.lastArrivalPosition,
              let initial=d.engine.renderSnapshot().first(where:{$0.id == id}) else {return}
        // Check the published sprite, including species size and global zoom,
        // rather than trusting the separately recorded spawn coordinate.
        checks[prefix+"StartsOutsideAllDisplays"] = !displays.contains{$0.intersects(initial.rect)} &&
            !displays.contains{$0.intersects(Geometry.landingFootprint(at:origin,scale:d.spriteScale(for:bird)))}
        let motion=FlightBehavior.motion(bird.profile.id)
        let cruise=FlightBehavior.cruiseSpeed(bird.profile.id,multiplier:bird.profile.speed)
        let waveSpeed=motion.wave*(2 * .pi/motion.cycle + .pi/max(0.001,bird.flightDuration))
        let limit=CGFloat((cruise+waveSpeed)*BehaviorEngine.step)+0.1
        var previous=initial.position
        var continuous=Geometry.distance(origin,previous)<=limit
        var crossed=false
        for _ in 0...Int(ceil(bird.flightDuration/BehaviorEngine.step)) {
            d.advanceBirds(BehaviorEngine.step)
            guard let snapshot=d.engine.renderSnapshot().first(where:{$0.id == id}) else {continuous=false;break}
            continuous = continuous && Geometry.distance(previous,snapshot.position)<=limit
            previous=snapshot.position
            if displays.contains(where:{$0.intersects(snapshot.rect)}) {crossed=true;break}
        }
        checks[prefix+"MovesContinuously"]=continuous
        checks[prefix+"ReachesDisplay"]=crossed
    }
}
