import AppKit
import BirdingCore

final class PopulationVerification {
    unowned let desktop: DesktopController
    let path: String
    var checks: [String:Bool] = [:]
    init(desktop: DesktopController,path:String) { self.desktop = desktop; self.path = path }
    func start() {
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) {
            self.checks["startsWithNoBirds"] = self.desktop.birds.isEmpty
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+1.25) {
            let d = self.desktop
            self.checks["firstArrivalIsOneBird"] = d.birds.count == 1 && d.arrivalCount == 1
            self.checks["arrivalStartsOutsideAllDisplays"] = d.lastArrivalPosition.map { p in
                !d.displayRects.contains { $0.intersects(Geometry.landingFootprint(at:p,scale:d.scale)) }
            } ?? false
            d.automaticPopulation = false
            if let bird = d.birds.first {
                let current = bird.position
                d.sendAway(bird)
                self.checks["departureStartsWithoutTeleporting"] = bird.position == current && bird.isDeparting && bird.hostID == nil
                bird.tick(bird.flightDuration/2)
                self.checks["departingBirdRetainedDuringFlight"] = d.birds.contains{$0 === bird} && !bird.departureFinished && !bird.needsDestination
                bird.tick(bird.flightDuration)
                d.advanceBirds(1.0/60)
                self.checks["removedOnlyAfterFlyingOffscreen"] = !d.birds.contains{$0 === bird} && !d.displayRects.contains{$0.intersects(d.bounds(of:bird))}
            }
            let previous = d.birds.count
            d.population.setRange(PopulationRange(lower:8,upper:12)!)
            self.checks["changingRangeDoesNotSpawnABatch"] = d.birds.count == previous
            saveJSON(["passed":self.checks.count == 7 && self.checks.values.allSatisfy{$0},"checks":self.checks],to:URL(fileURLWithPath:self.path))
            exit(self.checks.count == 7 && self.checks.values.allSatisfy{$0} ? 0 : 1)
        }
    }
}
