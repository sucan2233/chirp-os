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
    var habitatReservations:[HabitatObjectID] {get}
    func propSnapshots(in engine:BehaviorEngine) -> [ScenePropRenderState]
    func start(in engine:BehaviorEngine)
    /// Pure validity checks also run while animation time is paused.
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion?
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion?
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine)
    func presentation(for bird:BirdID,in engine:BehaviorEngine) -> BirdPose?
}

extension BehaviorExecution {
    var occupiesEncounter:Bool {BehaviorDefinitions.definition(for:kind).occupiesEncounter}
    var runsWhilePaused:Bool {BehaviorDefinitions.definition(for:kind).runsWhilePaused}
    var propIDs:[ScenePropID] {[]}
    var habitatReservations:[HabitatObjectID] {[]}
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
        // Retain only species that were renderable on a display during this run;
        // transient participants may already be gone when completion is emitted.
        var observationSpecies=Set<SpeciesID>()
        var age: Double = 0
    }
    private(set) var runs: [BehaviorRunID:Run] = [:]
    private(set) var owners: [BirdID:BehaviorRunID] = [:]
    private var nextID: UInt64 = 1
    var habitatReservations:Set<HabitatObjectID> {Set(runs.values.flatMap{$0.execution.habitatReservations})}
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
    private func captureObservationSpecies(_ id:BehaviorRunID,in engine:BehaviorEngine) {
        guard var run=runs[id],run.execution.kind != .relocate else {return}
        let participants=Set(run.execution.participants)
        // engine.birds excludes hidden records. A shown offscreen arrival still
        // needs to enter a display before its species qualifies as a discovery.
        for bird in engine.birds where !run.observationSpecies.contains(bird.profile.id) {
            guard let birdID=engine.id(of:bird),participants.contains(birdID),
                  engine.world.displays.contains(where:{$0.intersects(engine.bounds(of:bird))}) else {continue}
            run.observationSpecies.insert(bird.profile.id)
        }
        runs[id]=run
    }
    func start(_ execution:BehaviorExecution,source:BehaviorSource,in engine:BehaviorEngine) -> BehaviorResult {
        guard !execution.participants.contains(where:{owners[$0] != nil}),
              Set(execution.habitatReservations).count==execution.habitatReservations.count,
              habitatReservations.isDisjoint(with:execution.habitatReservations),
              execution.habitatReservations.allSatisfy({engine.habitatObjects.objects[$0].map{!$0.retiring} ?? false}),
              Set(execution.propIDs).count==execution.propIDs.count,
              propIDs.isDisjoint(with:execution.propIDs),
              !execution.occupiesEncounter || (!encounterBusy && !runs.values.contains(where:{ [BehaviorKind.foodTrayVisit,.fixedPerchVisit].contains($0.execution.kind) })),
              ![BehaviorKind.foodTrayVisit,.fixedPerchVisit].contains(execution.kind) || !encounterBusy else {return .rejected(.busy)}
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
        captureObservationSpecies(id,in:engine)
        engine.emit(.started,run:id,kind:execution.kind,source:source,participants:execution.participants)
        return .started(id)
    }
    func validate(in engine:BehaviorEngine,where matches:(BehaviorExecution)->Bool = {_ in true}) {
        for id in runs.keys.sorted() {
            guard let run=runs[id],matches(run.execution) else {continue}
            captureObservationSpecies(id,in:engine)
            guard run.execution.habitatReservations.allSatisfy({engine.habitatObjects.objects[$0] != nil}) else {
                finish(id,result:.failed(.targetInvalid),in:engine);continue
            }
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
            captureObservationSpecies(id,in:engine)
            let result=run.execution.advance(dt,in:engine)
            captureObservationSpecies(id,in:engine)
            if let result {finish(id,result:result,in:engine)}
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
            let event=engine.emit(.completed,run:id,kind:run.execution.kind,source:run.source,participants:run.execution.participants)
            if run.execution.kind != .relocate,!run.observationSpecies.isEmpty {
                engine.observationObserver?(BehaviorObservation(sequence:event.sequence,simulationTime:event.time,
                    kind:run.execution.kind,source:run.source,
                    species:run.observationSpecies.sorted{$0.rawValue<$1.rawValue},runID:id.rawValue))
            }
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
