import Foundation
import CoreGraphics

/// Seven positions span six simulation intervals, smoothing duplicate 30 Hz and
/// the smaller displacements at 120 Hz. Display crossings reset velocity.
struct PointerPerception {
    private var samples:[CGPoint]=[]
    private var screen:CGRect?
    private(set) var from:CGPoint?
    private(set) var to:CGPoint?
    private(set) var fast=false
    mutating func reset() {samples=[];screen=nil;from=nil;to=nil;fast=false}
    mutating func sample(_ point:CGPoint,screens:[CGRect],dt:Double) {
        guard point.x.isFinite,point.y.isFinite,dt>0,
              let current=screens.first(where:{$0.contains(point)}) else {reset();return}
        guard screen==current,let last=samples.last else {
            reset();screen=current;samples=[point];to=point;return
        }
        // Treat pointer warps as a new baseline rather than a desktop-wide scare.
        guard Geometry.distance(last,point)<max(400,current.width*0.4) else {
            reset();screen=current;samples=[point];to=point;return
        }
        from=last;to=point;samples.append(point)
        if samples.count>7 {samples.removeFirst(samples.count-7)}
        let duration=Double(samples.count-1)*dt
        fast=samples.count==7 && Double(Geometry.distance(samples[0],point))/duration >= (fast ? 480:600)
    }
    func passesNear(_ point:CGPoint,radius:CGFloat) -> Bool {
        guard fast,let from,let to else {return false}
        let dx=to.x-from.x,dy=to.y-from.y,length=dx*dx+dy*dy
        let t=length>0 ? max(0,min(1,((point.x-from.x)*dx+(point.y-from.y)*dy)/length)):0
        return Geometry.distance(point,CGPoint(x:from.x+t*dx,y:from.y+t*dy))<radius
    }
}

extension BehaviorEngine {
    func resetPerception() {
        perception.reset();attentionRanges=[]
        perchPlanner.resetPerception()
    }
    func recordPointerClick(explicit:Bool=false) {
        // Mouse-up snapshots release the latch even while paused. A sampled
        // down and its native event represent one click in either arrival order.
        guard !clickHandled || (explicit && !world.buttonsDown) else {return}
        clickHandled=true;perchPlanner.resetPerception()
        for bird in birds where role(of:bird) == .resident {
            let radius=max(200,144*spriteScale(for:bird))*1.2
            if let id=id(of:bird),Geometry.distance(world.pointer,bird.position)<=radius,
               world.displays.contains(where:{$0.contains(world.pointer) && $0.contains(bird.position)}) {
                perchPlanner.noteClick(id)
            }
        }
    }
    func observeEnvironment(_ dt:Double) {
        perception.sample(world.pointer,screens:world.displays,dt:dt)
        if world.buttonsDown {recordPointerClick()}
        else {clickHandled=false}
        for bird in birds where role(of:bird) == .resident {
            guard let id=id(of:bird) else {continue}
            let near=max(100,72*spriteScale(for:bird))
            let onDisplay=world.displays.contains{$0.contains(world.pointer) && $0.contains(bird.position)}
            let distance=Geometry.distance(world.pointer,bird.position)
            let inRange=onDisplay && distance<near*2*(attentionRanges.contains(id) ? 1.2:1)
            if inRange {attentionRanges.insert(id)} else {attentionRanges.remove(id)}
            perchPlanner.observe(id,stimulus:BirdStimulus(near:onDisplay && distance<near,
                inAttentionRange:inRange,fastPass:!world.buttonsDown && onDisplay && perception.passesNear(bird.position,radius:near),click:false),dt:dt)
        }
    }
    /// Stable traversal and a separate stream keep optional ecology out of the
    /// population/flight RNG, and prevent the first registered bird monopolizing it.
    func ecologicalChoice<T>(_ values:[T],weight:(T)->Double) -> T? {
        let weighted=values.map{($0,max(0,weight($0)))}.filter{$0.1.isFinite && $0.1>0}
        let total=weighted.reduce(0){$0+$1.1}
        guard total>0 else {return nil}
        var ticket=ecologyRandom.unit()*total
        for (value,weight) in weighted {ticket-=weight;if ticket<0 {return value}}
        return weighted.last?.0
    }
    private func attentionRejection(_ action:AttentionKind,id:BirdID,source:BehaviorSource) -> BehaviorReason? {
        guard let bird=bird(id),role(of:bird) == .resident,bird.state == .perched,bird.edge == .top,
              !bird.isDeparting,!bird.needsDestination,bird.perchDuration-bird.stateTime>3 else {return .unavailableBird}
        if let owner=runtime.owners[id],let run=runtime.runs[owner] {
            let canInterrupt=BehaviorDefinitions.canPreempt(incoming:action.behavior,source:source,
                current:run.execution.kind,currentSource:run.source)
            if !canInterrupt {return .busy}
        }
        guard action.requiredFrames.isSubset(of:world.availableFrames[bird.profile.id] ?? []) else {return .missingFrames}
        guard hasUsablePerch(bird) else {return .noSpace}
        guard !world.buttonsDown else {return .userInput}
        if source == .automatic {
            guard perchPlanner.automaticWeight(id,kind:action.behavior)>0 else {return .unavailableBird}
            if action == .watch {
                let radius=max(200,144*spriteScale(for:bird))*(attentionRanges.contains(id) ? 1.2:1)
                guard world.displays.contains(where:{$0.contains(world.pointer) && $0.contains(bird.position)}),
                      Geometry.distance(world.pointer,bird.position)<=radius else {return .pointerMoved}
            }
        }
        return nil
    }
    @discardableResult func requestAttention(_ action:AttentionKind,source:BehaviorSource,target:BirdID?=nil) -> BehaviorResult {
        func reject(_ reason:BehaviorReason) -> BehaviorResult {
            emit(.rejected,kind:action.behavior,source:source,reason:reason);return .rejected(reason)
        }
        guard !paused else {return reject(.paused)}
        guard BehaviorDefinitions.definition(for:action.behavior).isEnabled(settings:settings,source:source) else {return reject(.disabled)}
        let ids=target.map{[$0]} ?? birds.compactMap{id(of:$0)}
        var reasons:[BehaviorReason]=[]
        let candidates=ids.filter {id in
            if let reason=attentionRejection(action,id:id,source:source) {reasons.append(reason);return false}
            return true
        }
        guard let id=ecologicalChoice(candidates,weight:{source == .automatic ? self.perchPlanner.automaticWeight($0,kind:action.behavior):1}),
              let state=perchPlanner.ecology(id) else {
            return reject([BehaviorReason.userInput,.missingFrames,.busy,.noSpace,.pointerMoved].first{reasons.contains($0)} ?? .unavailableBird)
        }
        let duration=action == .watch ? 1.5+state.temperament.curiosity:0.8+0.6*state.disturbance
        let execution=AttentionExecution(id:id,kind:action,duration:duration,requiresNearbyPointer:source == .automatic)
        // Validate the full prospective pose before releasing a lower priority run.
        execution.start(in:self)
        if let invalid=execution.validate(in:self) {
            switch invalid {
            case .completed:return reject(.unavailableBird)
            case .cancelled(let why),.failed(let why):return reject(why)
            }
        }
        runtime.cancel(bird:id,reason:.replaced,in:self)
        perchPlanner.suppress(id)
        return runtime.start(execution,source:source,in:self)
    }
    @discardableResult func updateAttention() -> Bool {
        guard ambientEnabled,settings.perchActions,settings.passiveAttentionEnabled,!world.buttonsDown else {return false}
        let candidates=birds.compactMap {bird -> (BirdID,AttentionKind)? in
            guard let id=id(of:bird),let action=perchPlanner.attentionCandidate(id),
                  attentionRejection(action,id:id,source:.automatic)==nil else {return nil}
            return (id,action)
        }
        let alerts=candidates.filter{$0.1 == .alert}
        guard let selected=ecologicalChoice(alerts.isEmpty ? candidates:alerts,weight:{self.perchPlanner.automaticWeight($0.0,kind:$0.1.behavior)}) else {return false}
        return requestAttention(selected.1,source:.automatic,target:selected.0).accepted
    }
    func requestAutomaticLeaf() {
        guard !paused,ambientEnabled,settings.leafPlayEnabled,settings.ambientLeafPlayEnabled,
              !ambientBusy,!hasPointerPreview,!hasLeafPreview,!world.buttonsDown else {return}
        var candidates=birds.compactMap {bird -> BirdID? in
            guard let id=id(of:bird),role(of:bird) == .resident,behavior(of:bird)==nil,
                  bird.state == .perched,bird.edge == .top,!bird.needsDestination,!bird.isDeparting,
                  bird.perchDuration-bird.stateTime>LeafPlayPlan.observeDuration+BehaviorEngine.step,
                  spriteScale(for:bird)<=1.8,!pointerNear(bird),
                  LeafPlayPlan.requiredFrames.isSubset(of:world.availableFrames[bird.profile.id] ?? []),
                  perchPlanner.automaticWeight(id,kind:.leafPlay)>0 else {return nil}
            return id
        }
        var probes=0
        // At most eight complete trajectory preflights across all candidates.
        while probes<8,let id=ecologicalChoice(candidates,weight:{self.perchPlanner.automaticWeight($0,kind:.leafPlay)}) {
            candidates.removeAll{$0==id}
            guard let bird=bird(id),let screen=world.screens.first(where:{
                bird.position.x >= $0.minX && bird.position.x <= $0.maxX && bird.position.y >= $0.minY && bird.position.y <= $0.maxY
            }) else {continue}
            let scale=spriteScale(for:bird),margin=140+80*scale
            let area=screen.insetBy(dx:margin,dy:margin+55)
            guard area.width>0,area.height>0 else {continue}
            for _ in 0..<4 where probes<8 {
                let point=CGPoint(x:area.minX+area.width*ecologyRandom.unit(),y:area.minY+area.height*ecologyRandom.unit())
                guard Geometry.distance(point,world.pointer)>margin+100,
                      PointerOrbit.isPossible(center:point,origin:bird.position,area:screen,spriteScale:scale) else {continue}
                probes+=1
                guard let plan=LeafPlayPlan.make(id:id,center:point,in:self) else {continue}
                _=startLeaf(plan,source:.automatic);return
            }
        }
    }
}
