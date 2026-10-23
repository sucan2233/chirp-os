import Foundation
import CoreGraphics

final class RelocationExecution:BehaviorExecution {
    let kind:BehaviorKind = .relocate
    let occupiesEncounter=false, runsWhilePaused=true, timeout=45.0
    let id:BirdID,origin:CGPoint,plan:DestinationPlan
    private var revision:UInt64=0
    var participants:[BirdID] {[id]}
    init(id:BirdID,origin:CGPoint,plan:DestinationPlan) {self.id=id;self.origin=origin;self.plan=plan}
    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(id) else {return}
        plan.apply(to:bird,random:engine.random);revision=bird.motionRevision
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(id) else {return .failed(.missingBird)}
        if bird.state == .perched {return .completed}
        if bird.needsDestination || bird.motionRevision != revision {
            guard let plan=engine.plan(for:bird,avoiding:origin) else {return .failed(.noSpace)}
            plan.apply(to:bird,random:engine.random);revision=bird.motionRevision
        }
        return nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        // The current path remains a valid recovery motion; replacement commands
        // take ownership at the same position. Nothing teleports or disappears.
    }
}

final class PointerVisitExecution:BehaviorExecution {
    let kind:BehaviorKind = .pointerVisit
    let occupiesEncounter=true,runsWhilePaused=false
    let id:BirdID,center:CGPoint,host:Surface,screen:CGRect,orbit:PointerOrbit
    private var revision:UInt64=0
    private(set) var timeout=30.0
    var participants:[BirdID] {[id]}
    init(id:BirdID,center:CGPoint,host:Surface,screen:CGRect,orbit:PointerOrbit) {
        self.id=id;self.center=center;self.host=host;self.screen=screen;self.orbit=orbit
    }
    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(id) else {return}
        bird.fly(to:bird.position,host:host,airspace:screen,pointerOrbit:orbit,random:engine.random.unit)
        revision=bird.motionRevision;timeout=bird.flightDuration+2
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(id) else {return .failed(.missingBird)}
        if bird.motionRevision != revision || bird.needsDestination {return .failed(.targetInvalid)}
        if engine.world.buttonsDown {return .cancelled(.userInput)}
        if Geometry.distance(engine.world.pointer,center)>12 {return .cancelled(.pointerMoved)}
        if bird.state != .flying {return .completed}
        return nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard ![BehaviorReason.replaced,.removed,.shutdown].contains(reason),let bird=engine.bird(id),
              !bird.isDeparting,bird.motionRevision==revision,
              let plan=engine.plan(for:bird,avoiding:center) else {return}
        plan.apply(to:bird,random:engine.random)
    }
}

final class FlockPassExecution:BehaviorExecution {
    let kind:BehaviorKind = .flockPass
    let occupiesEncounter=true,runsWhilePaused=false
    let members:[(BirdID,FlockMemberPlan)]
    private var pending:[BirdID:Double]=[:]
    private(set) var timeout=60.0
    var participants:[BirdID] {members.map{$0.0}}
    init(members:[(BirdID,FlockMemberPlan)]) {self.members=members}
    func start(in engine:BehaviorEngine) {
        timeout=0
        for (id,plan) in members {
            guard let bird=engine.bird(id) else {continue}
            bird.passThrough(plan);pending[id]=plan.delay
            timeout=max(timeout,plan.delay+bird.flightDuration+3)
        }
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        for id in pending.keys.sorted() {
            guard engine.bird(id) != nil else {pending.removeValue(forKey:id);continue}
            let remaining=pending[id]!-dt
            if remaining<=0 {pending.removeValue(forKey:id);engine.show(id)}else{pending[id]=remaining}
        }
        return participants.allSatisfy{engine.bird($0)==nil} ? .completed:nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        pending.removeAll()
        for id in participants {engine.removeRecord(id)}
    }
}
