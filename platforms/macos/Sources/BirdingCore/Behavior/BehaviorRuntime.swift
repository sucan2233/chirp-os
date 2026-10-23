import Foundation

enum BehaviorCompletion {case completed, cancelled(BehaviorReason), failed(BehaviorReason)}

// New executions implement this lifecycle. They do not install timers or modify
// the desktop controller. The runtime owns all leases and terminal events.
protocol BehaviorExecution: AnyObject {
    var kind: BehaviorKind {get}
    var participants: [BirdID] {get}
    var occupiesEncounter: Bool {get}
    var runsWhilePaused: Bool {get}
    var timeout: Double {get}
    var landingReservations: [LandingReservation] {get}
    var propIDs:[ScenePropID] {get}
    func propSnapshots(in engine:BehaviorEngine) -> [ScenePropRenderState]
    func start(in engine:BehaviorEngine)
    /// Pure validity checks also run while animation time is paused.
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion?
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion?
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine)
    func presentation(for bird:BirdID,in engine:BehaviorEngine) -> BirdPose?
}

extension BehaviorExecution {
    var propIDs:[ScenePropID] {[]}
    func propSnapshots(in engine:BehaviorEngine) -> [ScenePropRenderState] {[]}
    var landingReservations: [LandingReservation] {[]}
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
    func presentation(for bird:BirdID,in engine:BehaviorEngine) -> BirdPose? {nil}
}

final class BehaviorRuntime {
    struct Run {
        let id: BehaviorRunID
        let source: BehaviorSource
        let execution: BehaviorExecution
        var age: Double = 0
    }
    private(set) var runs: [BehaviorRunID:Run] = [:]
    private(set) var owners: [BirdID:BehaviorRunID] = [:]
    private var nextID: UInt64 = 1
    var encounterBusy: Bool {runs.values.contains{$0.execution.occupiesEncounter}}
    var propIDs:Set<ScenePropID> {Set(runs.values.flatMap{$0.execution.propIDs})}
    func propSnapshots(in engine:BehaviorEngine) -> [ScenePropRenderState] {
        runs.keys.sorted().flatMap{runs[$0]?.execution.propSnapshots(in:engine) ?? []}
    }
    var landingReservations:[LandingReservation] {
        runs.keys.sorted().flatMap {runs[$0]?.execution.landingReservations ?? []}
    }
    func kind(for bird:BirdID) -> BehaviorKind? {owners[bird].flatMap{runs[$0]?.execution.kind}}
    func canAdvance(_ bird:BirdID,paused:Bool) -> Bool {
        !paused || owners[bird].flatMap{runs[$0]?.execution.runsWhilePaused} == true
    }
    func presentation(for bird:BirdID,in engine:BehaviorEngine) -> BirdPose? {
        owners[bird].flatMap{runs[$0]?.execution.presentation(for:bird,in:engine)}
    }
    func start(_ execution:BehaviorExecution,source:BehaviorSource,in engine:BehaviorEngine) -> BehaviorResult {
        guard !execution.participants.contains(where:{owners[$0] != nil}),
              Set(execution.propIDs).count==execution.propIDs.count,
              propIDs.isDisjoint(with:execution.propIDs),
              !execution.occupiesEncounter || !encounterBusy else {return .rejected(.busy)}
        let requested=execution.landingReservations
        guard requested.allSatisfy({execution.participants.contains($0.bird) && $0.isValid(in:engine)}),
              !requested.enumerated().contains(where:{index,slot in
                  requested.dropFirst(index+1).contains{slot.conflicts(with:$0,in:engine)} ||
                  landingReservations.contains{slot.conflicts(with:$0,in:engine)}
              }) else {return .rejected(.noSpace)}
        let id=BehaviorRunID(rawValue:nextID);nextID+=1
        runs[id]=Run(id:id,source:source,execution:execution)
        for bird in execution.participants {
            owners[bird]=id;engine.perchPlanner.didStart(bird,kind:execution.kind)
        }
        execution.start(in:engine)
        engine.emit(.started,run:id,kind:execution.kind,source:source,participants:execution.participants)
        return .started(id)
    }
    func validate(in engine:BehaviorEngine) {
        for id in runs.keys.sorted() {
            guard let run=runs[id] else {continue}
            let slots=run.execution.landingReservations
            let foreign=runs.keys.sorted().filter{$0 != id}.flatMap{runs[$0]?.execution.landingReservations ?? []}
            if slots.contains(where:{!$0.isValid(in:engine)}) || slots.enumerated().contains(where:{index,slot in
                slots.dropFirst(index+1).contains{slot.conflicts(with:$0,in:engine)} ||
                    foreign.contains{slot.conflicts(with:$0,in:engine)}
            }) {
                finish(id,result:.failed(.targetInvalid),in:engine);continue
            }
            if let result=runs[id]?.execution.validate(in:engine) {finish(id,result:result,in:engine)}
        }
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) {
        validate(in:engine)
        for id in runs.keys.sorted() {
            guard var run=runs[id],!engine.paused || run.execution.runsWhilePaused else {continue}
            run.age+=dt;runs[id]=run
            if run.age>run.execution.timeout {
                finish(id,result:.failed(.timedOut),in:engine);continue
            }
            if let result=run.execution.advance(dt,in:engine) {finish(id,result:result,in:engine)}
        }
    }
    // Remove ownership before callbacks so cleanup/recovery cannot double-end a run.
    private func detach(_ id:BehaviorRunID,in engine:BehaviorEngine) -> Run? {
        guard let run=runs[id] else {return nil}
        for bird in run.execution.participants {
            if let pose=run.execution.presentation(for:bird,in:engine),let model=engine.bird(bird) {
                engine.poseMixer.release(pose,for:bird,bird:model)
            }
        }
        runs.removeValue(forKey:id)
        for bird in run.execution.participants where owners[bird]==id {owners.removeValue(forKey:bird)}
        for bird in run.execution.participants {engine.perchPlanner.didFinish(bird,kind:run.execution.kind)}
        return run
    }
    private func finish(_ id:BehaviorRunID,result:BehaviorCompletion,in engine:BehaviorEngine) {
        guard let run=detach(id,in:engine) else {return}
        switch result {
        case .completed:
            engine.emit(.completed,run:id,kind:run.execution.kind,source:run.source,participants:run.execution.participants)
        case .cancelled(let reason):
            run.execution.cancel(reason,in:engine)
            engine.emit(.cancelled,run:id,kind:run.execution.kind,source:run.source,participants:run.execution.participants,reason:reason)
        case .failed(let reason):
            run.execution.cancel(reason,in:engine)
            engine.emit(.failed,run:id,kind:run.execution.kind,source:run.source,participants:run.execution.participants,reason:reason)
        }
    }
    func cancel(_ id:BehaviorRunID,reason:BehaviorReason,in engine:BehaviorEngine) {
        guard let run=detach(id,in:engine) else {return}
        run.execution.cancel(reason,in:engine)
        engine.emit(.cancelled,run:id,kind:run.execution.kind,source:run.source,participants:run.execution.participants,reason:reason)
    }
    func cancel(bird:BirdID,reason:BehaviorReason,in engine:BehaviorEngine) {
        if let id=owners[bird] {cancel(id,reason:reason,in:engine)}
    }
    func cancel(where matches:(BehaviorExecution)->Bool,reason:BehaviorReason,in engine:BehaviorEngine) {
        for id in runs.keys.sorted() where runs[id].map({matches($0.execution)}) == true {cancel(id,reason:reason,in:engine)}
    }
}
