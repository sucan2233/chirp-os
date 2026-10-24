import Foundation
import CoreGraphics

struct NestBuildPlan {
    let visit:NestVisitSchedule
    var id:BirdID {visit.id}
    var birdID:BirdID {id}
    var objectID:HabitatObjectID {visit.object.id}
    var nestID:HabitatObjectID {objectID}
    var materialID:ScenePropID {visit.materialID}
    var materialSlot:Int {visit.materialSlot}
    var approach:NestVisitJourney {visit.approach}
    var departure:NestVisitJourney {visit.departure}
    var destination:NestVisitLanding {visit.destination}
    var exit:NestVisitLanding {visit.exit}
    var maximumPlannedDuration:Double {visit.maximumPlannedDuration}
    func canBegin(in engine:BehaviorEngine)->Bool {visit.canBegin(in:engine)}
    func isSafe(in engine:BehaviorEngine)->Bool {
        visit.geometryValid(in:engine) && approach.safe(in:engine,bird:id) && departure.safe(in:engine,bird:id)
    }
    static func candidates(in engine:BehaviorEngine,source:BehaviorSource,target:HabitatObjectID?=nil)->[Self] {
        NestVisitSchedule.candidates(in:engine,source:source,kind:.nestBuild,target:target).map{Self(visit:$0)}
    }
}

final class NestBuildExecution:NestActivityExecution {
    let plan:NestBuildPlan
    init(plan:NestBuildPlan) {self.plan=plan;super.init(visit:plan.visit)}
}
