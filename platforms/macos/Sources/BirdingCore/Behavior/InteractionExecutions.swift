import Foundation
import CoreGraphics

final class RelocationExecution:BehaviorExecution {
    let kind:BehaviorKind = .relocate
    let timeout=45.0
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
    let id:BirdID,center:CGPoint,host:Surface,screen:CGRect,orbit:PointerOrbit
    private var revision:UInt64=0
    // Frozen for this run. BehaviorEngine cancels the run when the setting changes.
    func estimatedDuration(in engine:BehaviorEngine)->Double {
        guard let bird=engine.bird(id) else {return .infinity}
        let probe=Bird(position:bird.position,fraction:bird.fraction,profile:bird.profile,random:{0.5})
        probe.fly(to:bird.position,host:host,airspace:screen,allowsOrbit:false,pointerOrbit:orbit,random:{0.5})
        return probe.flightDuration+0.6
    }
    private var followsPointer=false
    private var followScale:CGFloat=1
    private var followReady=true
    private(set) var timeout=30.0
    var participants:[BirdID] {[id]}
    init(id:BirdID,center:CGPoint,host:Surface,screen:CGRect,orbit:PointerOrbit) {
        self.id=id;self.center=center;self.host=host;self.screen=screen;self.orbit=orbit
    }
    func start(in engine:BehaviorEngine) {
        guard let bird=engine.bird(id) else {return}
        followsPointer=engine.settings.pointerFollowEnabled && (engine.settings.companion?.policy.style(for:kind) ?? .full) == .full
        followScale=engine.spriteScale(for:bird)
        bird.fly(to:bird.position,host:host,airspace:screen,pointerOrbit:orbit,random:engine.random.unit)
        revision=bird.motionRevision;timeout=bird.flightDuration+2
        if followsPointer {
            followReady=bird.enablePointerFollow(in:screen,spriteScale:followScale)
            // A cubic contained in one display is no longer than three display
            // diagonals. Reserve that finite exit budget once, never per input.
            timeout+=3*Double(hypot(screen.width,screen.height))/160+0.85
        }
    }
    func validate(in engine:BehaviorEngine) -> BehaviorCompletion? {
        guard let bird=engine.bird(id) else {return .failed(.missingBird)}
        if bird.motionRevision != revision || bird.needsDestination {return .failed(.targetInvalid)}
        if followsPointer {
            guard followReady,engine.world.screens.contains(screen) else {return .cancelled(.noSpace)}
            guard engine.spriteScale(for:bird)==followScale,
                  bird.hostID==host.id,
                  let currentHost=engine.world.surfaces.first(where:{$0.id==host.id && $0.pid==host.pid}) else {return .failed(.targetInvalid)}
            let foot=Geometry.foot(on:currentHost,fraction:bird.fraction,edge:bird.edge,scale:followScale)
            // Ground feet may sit at the work-area bottom, with their tail in
            // the reserved Dock strip. Test the full sprite against the display.
            let index=engine.world.screens.firstIndex(of:screen)!
            let display=engine.world.displays.indices.contains(index) ? engine.world.displays[index]:screen
            guard display.contains(Geometry.landingFootprint(at:foot,scale:followScale)),
                  Geometry.isLandingVisible(on:host.id,at:foot,surfaces:engine.world.surfaces,scale:followScale) else {return .failed(.targetInvalid)}
        }
        return nil
    }
    func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {
        if let result=validate(in:engine) {return result}
        guard let bird=engine.bird(id) else {return .failed(.missingBird)}
        // World synchronization also precedes commands and render snapshots.
        // Consume sampled input only on a simulation step, preserving the
        // encounter lease and explicit-click priority between steps.
        if engine.world.interruptingButtonsDown {return .cancelled(.userInput)}
        if followsPointer {
            guard engine.world.pointer.x.isFinite,engine.world.pointer.y.isFinite,
                  screen.contains(engine.world.pointer) else {return .cancelled(.noSpace)}
        } else if Geometry.distance(engine.world.pointer,center)>12 {return .cancelled(.pointerMoved)}
        if bird.state != .flying {return .completed}
        if followsPointer {
            guard bird.updatePointerFollowTarget(engine.world.pointer) else {return .cancelled(.noSpace)}
            bird.updateHost(surfaces:engine.world.surfaces,sampleDT:dt,spriteScale:followScale)
        }
        return nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        guard ![BehaviorReason.replaced,.removed,.shutdown].contains(reason),let bird=engine.bird(id),
              !bird.isDeparting,bird.motionRevision==revision else {return}
        if let plan=engine.plan(for:bird,avoiding:center) {
            plan.apply(to:bird,random:engine.random)
        } else if followsPointer {
            // No safe recovery surface remains. Hold at the current position and
            // let ordinary routing retry; never keep a released follow run alive.
            bird.fly(to:bird.position,host:nil,arc:0,urgent:true)
        }
    }
}

final class FlockPassExecution:BehaviorExecution {
    let kind:BehaviorKind = .flockPass
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
        if engine.settings.companion != nil,engine.world.buttonsDown,
           participants.contains(where:{id in
               guard let bird=engine.bird(id),pending[id]==nil else {return false}
               return engine.bounds(of:bird).insetBy(dx:-90,dy:-90).contains(engine.world.pointer)
           }) {
            // Keep the visible birds continuous, but send them to the closest
            // offscreen edge and prevent hidden members entering the work area.
            for id in participants where pending[id]==nil {
                guard let bird=engine.bird(id),let screen=engine.world.displays.min(by:{
                    Geometry.distance(CGPoint(x:$0.midX,y:$0.midY),bird.position)<Geometry.distance(CGPoint(x:$1.midX,y:$1.midY),bird.position)
                }) else {continue}
                let margin=80*engine.spriteScale(for:bird)+40
                let exits=[CGPoint(x:screen.minX-margin,y:bird.position.y),CGPoint(x:screen.maxX+margin,y:bird.position.y),CGPoint(x:bird.position.x,y:screen.minY-margin)]
                let end=exits.min{Geometry.distance($0,bird.position)<Geometry.distance($1,bird.position)}!
                bird.redirectPass(to:end)
            }
            return .cancelled(.userInput)
        }
        for id in pending.keys.sorted() {
            guard engine.bird(id) != nil else {pending.removeValue(forKey:id);continue}
            let remaining=pending[id]!-dt
            if remaining<=0 {pending.removeValue(forKey:id);engine.show(id)}else{pending[id]=remaining}
        }
        return participants.allSatisfy{engine.bird($0)==nil} ? .completed:nil
    }
    func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {
        let hidden=Set(pending.keys);pending.removeAll()
        for id in participants {
            if engine.settings.companion == nil || hidden.contains(id) || [.shutdown,.sleep,.screensChanged,.spaceChanged].contains(reason) {engine.removeRecord(id)}
            // Visible members already own a bounded offscreen route. Let it finish.
        }
    }
}
