import XCTest
@testable import BirdingCore

final class EdgePeekTests:XCTestCase {
    private let display=CGRect(x:-1800,y:-600,width:3600,height:1800)
    private let host=Surface(id:171,pid:23,rect:CGRect(x:-900,y:500,width:1800,height:300))
    private let phases:[EdgePeekExecution.Phase]=[.approach,.observe,.returning]
    private let legacySpecies:[SpeciesID] = [.treeSparrow,.chineseBlackbird,.hoopoe,.whimbrel]
    private let newSpecies:[SpeciesID] = [.lightVentedBulbul,.magpieRobin]
    private let peekFrames:Set<String> = ["peekLower","peekLook","peekRecover"]

    private func fraction(at x:CGFloat,on surface:Surface) -> CGFloat {
        (x-Geometry.perchX(0,rect:surface.rect))/(Geometry.perchX(1,rect:surface.rect)-Geometry.perchX(0,rect:surface.rect))
    }
    private func fixture(right:Bool=false,scale:CGFloat=1,species:SpeciesID = .treeSparrow,
                         distance:CGFloat=95,host custom:Surface?=nil) -> BehaviorEngine {
        var settings=BirdSettings();settings.pointerVisits=false;settings.flockPasses=false
        settings.ambientLeafPlayEnabled=false;settings.edgePeekEnabled=true
        let e=BehaviorEngine(seed:739,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let surface=custom ?? host
        var frames:Set<String> = ["stand","idle0","idle1","idle2","land0","land1","land2","blink","breathe"]
        frames.formUnion((0...7).map{"fly\($0)"})
        if newSpecies.contains(species) {frames.formUnion(peekFrames)}
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[surface],scale:scale,
            pointer:CGPoint(x:-1700,y:-500),availableFrames:[species:frames]))
        let bird=Bird(position:.zero,fraction:0,profile:settings.catalog.profile(species),random:{0.5})
        let size=e.spriteScale(for:bird)
        let x=Geometry.perchX(right ? 1:0,rect:surface.rect)+(right ? -1:1)*distance*size
        bird.fraction=fraction(at:x,on:surface)
        bird.perch(on:surface,spriteScale:size);bird.perchDuration=600
        e.installFixtureBirds([bird]);advance(e,seconds:0.5)
        return e
    }
    private func advance(_ e:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    private func started(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let run)=result else {
            XCTFail("Expected edge peek start, got \(result)",file:file,line:line)
            throw NSError(domain:"EdgePeekTests",code:1)
        }
        return run
    }
    private func execution(_ e:BehaviorEngine,_ run:BehaviorRunID) throws -> EdgePeekExecution {
        try XCTUnwrap(e.runtime.runs[run]?.execution as? EdgePeekExecution)
    }
    private func reach(_ phase:EdgePeekExecution.Phase,in e:BehaviorEngine,run:BehaviorRunID) throws {
        let peek=try execution(e,run)
        for _ in 0..<300 {
            if peek.phase==phase {advance(e,seconds:0.1);return}
            guard e.runtime.runs[run] != nil else {break}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Did not reach \(phase.rawValue)")
        throw NSError(domain:"EdgePeekTests",code:2)
    }
    private func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    private func terminal(_ e:BehaviorEngine,_ run:BehaviorRunID,_ type:BehaviorEventType,
                          _ reason:BehaviorReason?=nil,file:StaticString=#filePath,line:UInt=#line) {
        let events=terminals(e,run)
        XCTAssertEqual(events.count,1,file:file,line:line)
        XCTAssertEqual(events.first?.type,type,file:file,line:line)
        XCTAssertEqual(events.first?.reason,reason,file:file,line:line)
        XCTAssertNil(e.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
    }
    private func pointer(_ point:CGPoint,in e:BehaviorEngine) {
        var world=e.world;world.pointer=point;e.updateWorld(world)
    }
    private func distantBird(in e:BehaviorEngine) -> Bird {
        let other=Bird(position:CGPoint(x:1300,y:-300),fraction:0.5,profile:e.birds[0].profile,random:{0.5})
        e.register(other);return other
    }

    func testLegacyFourSpeciesKeepTheirOriginalRoundTripAndIdleSequenceAtBothEndpointsAndScales() throws {
        XCTAssertEqual(EdgePeekExecution.supportedSpecies,Set(legacySpecies+newSpecies))
        for species in legacySpecies {
            let action=SpeciesBehavior.motion(species).action
            XCTAssertTrue(action == .peck || action == .probe)
            for right in [false,true] {
                for scale:CGFloat in [0.75,1,2] {
                    let e=fixture(right:right,scale:scale,species:species),bird=e.birds[0]
                    let origin=bird.position,originFraction=bird.fraction,size=e.spriteScale(for:bird)
                    let id=try XCTUnwrap(e.id(of:bird)),run=try started(e.handle(.edgePeek(.preview)))
                    let peek=try execution(e,run),endpoint=try XCTUnwrap(peek.plan.approach.destination.point(in:e))
                    XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.fraction,originFraction)
                    XCTAssertEqual(e.behavior(of:bird),.edgePeek);XCTAssertFalse(e.ambientBusy)
                    XCTAssertEqual(e.leasedBirdCount,1);XCTAssertEqual(e.reservedLandingCount,2)
                    XCTAssertEqual(e.runtime.owners[id],run)
                    XCTAssertEqual(peek.plan.approach.destination.fraction,right ? 1:0)
                    XCTAssertEqual(peek.plan.origin.fraction,originFraction)
                    XCTAssertEqual(e.requestEdgePeek(source:.preview,target:id),.rejected(.busy))
                    XCTAssertTrue(e.runtime.runs[run]?.execution is LedgeTraversalExecution)
                    var frames=Set<String>(),sequence:[String]=[],last=origin,minY=origin.y
                    var observeStart:Double?,returnStart:Double?
                    for _ in 0..<300 {
                        guard e.runtime.runs[run] != nil else {break}
                        let pose=try XCTUnwrap(e.renderSnapshot().first)
                        frames.insert(pose.frameName)
                        XCTAssertEqual(pose.position,bird.position);XCTAssertEqual(pose.hopOffset,0)
                        XCTAssertEqual(e.bounds(of:bird),pose.rect.insetBy(dx:-2,dy:-2))
                        XCTAssertFalse(pose.frameName.hasPrefix("fly"));XCTAssertFalse(bird.isGliding)
                        XCTAssertEqual(e.reservedLandingCount,2)
                        XCTAssertGreaterThanOrEqual(bird.fraction,min(originFraction,right ? 1:0)-0.000001)
                        XCTAssertLessThanOrEqual(bird.fraction,max(originFraction,right ? 1:0)+0.000001)
                        if peek.phase == .observe {
                            if observeStart==nil {observeStart=e.time}
                            if sequence.last != pose.frameName {sequence.append(pose.frameName)}
                            XCTAssertEqual(bird.position,endpoint);XCTAssertEqual(bird.state,.perched)
                            XCTAssertEqual(bird.fraction,right ? 1:0);XCTAssertEqual(pose.facingRight,right)
                        } else if peek.phase == .returning,returnStart==nil {returnStart=e.time}
                        let before=peek.phase
                        e.advance(BehaviorEngine.step)
                        let direction:CGFloat=right ? 1:-1
                        if before == .approach {XCTAssertGreaterThanOrEqual((bird.position.x-last.x)*direction,-0.000001)}
                        if before == .returning {XCTAssertLessThanOrEqual((bird.position.x-last.x)*direction,0.000001)}
                        XCTAssertLessThan(Geometry.distance(bird.position,last),20*size)
                        minY=min(minY,bird.position.y);last=bird.position
                    }
                    XCTAssertEqual(sequence,["idle0","idle1","idle2","idle1","idle0"])
                    XCTAssertEqual(try XCTUnwrap(returnStart)-XCTUnwrap(observeStart),1.6,accuracy:BehaviorEngine.step/2)
                    XCTAssertTrue(Set(["stand","land0","land1","land2"]).isSubset(of:frames))
                    XCTAssertEqual(minY,origin.y-12*size,accuracy:0.1*size)
                    XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.fraction,originFraction)
                    XCTAssertEqual(bird.hostID,host.id);XCTAssertEqual(bird.state,.perched)
                    XCTAssertEqual(bird.landedCount,2);XCTAssertFalse(bird.isSideHopping)
                    terminal(e,run,.completed)
                    XCTAssertEqual(e.ecology(of:bird)?.cooldowns[.edgePeek],45)
                    advance(e,seconds:1);terminal(e,run,.completed)
                }
            }
        }
    }

    func testTwoNewSpeciesUseDedicatedFramesAndRealRoundTripsAtBothEdgesAndThreeScales() throws {
        for species in newSpecies {
            for right in [false,true] {
                for scale:CGFloat in [0.5,1,2] {
                    for source:BehaviorSource in [.preview,.automatic] {
                        let e=fixture(right:right,scale:scale,species:species),bird=e.birds[0]
                        let id=try XCTUnwrap(e.id(of:bird)),origin=bird.position,fraction=bird.fraction
                        let identity=ObjectIdentifier(bird),size=e.spriteScale(for:bird)
                        e.perchPlanner.rhythms[id]?.quietTime=8
                        var observations:[BehaviorObservation]=[]
                        e.observationObserver={observations.append($0)}
                        let run=try started(e.handle(.edgePeek(source))),peek=try execution(e,run)
                        XCTAssertEqual(bird.position,origin)
                        XCTAssertEqual(peek.plan.approach.scale,scale*bird.profile.relativeScale)
                        let endpoint=try XCTUnwrap(peek.plan.approach.destination.point(in:e))
                        var sequence:[String]=[],observeStart:Double?,returnStart:Double?
                        for _ in 0..<300 {
                            guard e.runtime.runs[run] != nil else {break}
                            let pose=try XCTUnwrap(e.renderSnapshot().first)
                            XCTAssertEqual(pose.position,bird.position);XCTAssertEqual(pose.hopOffset,0)
                            XCTAssertEqual(pose.scale,size)
                            XCTAssertEqual(pose.rect.minY+39*size,bird.position.y,accuracy:1e-8)
                            XCTAssertTrue(display.contains(pose.rect))
                            XCTAssertEqual(e.leasedBirdCount,1);XCTAssertEqual(e.reservedLandingCount,2)
                            if peek.phase == .observe {
                                if observeStart==nil {observeStart=e.time}
                                XCTAssertTrue(peekFrames.contains(pose.frameName))
                                if sequence.last != pose.frameName {sequence.append(pose.frameName)}
                                XCTAssertEqual(bird.position,endpoint);XCTAssertEqual(pose.facingRight,right)
                            } else if peek.phase == .returning,returnStart==nil {returnStart=e.time}
                            let previous=bird.position
                            e.advance(BehaviorEngine.step)
                            XCTAssertLessThan(Geometry.distance(previous,bird.position),20*size)
                        }
                        XCTAssertEqual(sequence,["peekLower","peekLook","peekRecover"])
                        XCTAssertEqual(try XCTUnwrap(returnStart)-XCTUnwrap(observeStart),1.6,accuracy:BehaviorEngine.step/2)
                        terminal(e,run,.completed)
                        XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.fraction,fraction)
                        XCTAssertEqual(bird.state,.perched);XCTAssertFalse(bird.isSideHopping)
                        XCTAssertEqual(ObjectIdentifier(e.birds[0]),identity)
                        XCTAssertEqual(observations.count,1);XCTAssertEqual(observations.first?.source,source)
                        XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                    }
                }
            }
        }
    }

    func testDedicatedPeekRenderingUsesTheObservationClockAndOriginalReturnDeadline() throws {
        for species in newSpecies {
            let e=fixture(species:species),bird=e.birds[0]
            let run=try started(e.handle(.edgePeek(.preview))),peek=try execution(e,run)
            for _ in 0..<120 {
                if peek.phase == .observe {break}
                e.advance(BehaviorEngine.step)
            }
            XCTAssertEqual(peek.phase,.observe);XCTAssertEqual(peek.observationAge,0)
            let began=e.time,endpoint=bird.position
            var elapsed=0
            // Adjacent fixed steps straddle 0.32 and 1.28 without relying on
            // a second presentation clock or sampling the production clip.
            for (ticks,frame) in [(0,"peekLower"),(19,"peekLower"),(20,"peekLook"),
                                  (76,"peekLook"),(77,"peekRecover"),(95,"peekRecover")] {
                advance(e,seconds:Double(ticks-elapsed)*BehaviorEngine.step);elapsed=ticks
                XCTAssertEqual(peek.observationAge,Double(ticks)*BehaviorEngine.step,accuracy:1e-9)
                XCTAssertEqual(e.renderSnapshot().first?.frameName,frame)
                XCTAssertEqual(bird.position,endpoint);XCTAssertEqual(peek.phase,.observe)
            }
            e.advance(BehaviorEngine.step)
            XCTAssertEqual(peek.phase,.returning)
            XCTAssertEqual(e.time-began,1.6,accuracy:1e-9)
            advance(e,seconds:2);terminal(e,run,.completed)
        }
    }

    func testNewPeekSpeciesRejectEveryIncompleteRequiredSetBeforePreviewOrAutomaticStart() throws {
        let required:Set<String> = ["stand","idle0","idle1","idle2","land0","land1","land2",
            "peekLower","peekLook","peekRecover"]
        for species in newSpecies {
            XCTAssertEqual(SpeciesBehaviorProfile.profile(for:species).requiredFrames(for:.edgePeek),required)
            for source:BehaviorSource in [.preview,.automatic] {
                for missing in required.sorted()+["manifest"] {
                    let e=fixture(species:species),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
                    e.perchPlanner.rhythms[id]?.quietTime=8
                    let origin=bird.position,revision=bird.motionRevision
                    var world=e.world
                    if missing == "manifest" {world.availableFrames=[:]}
                    else {world.availableFrames[species]?.remove(missing)}
                    e.updateWorld(world)
                    XCTAssertFalse(e.edgePeekCandidate(id,source:source),missing)
                    XCTAssertEqual(e.handle(.edgePeek(source)),.rejected(.missingFrames),missing)
                    XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
                    XCTAssertFalse(bird.isSideHopping);XCTAssertEqual(e.activeRunCount,0)
                    XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
                    XCTAssertFalse(e.events.contains{$0.type == .started})
                }
            }
        }
    }

    func testNewPeekExecutionRechecksTheFullRequiredSetBeforeInstallingAnAlreadyPlannedHop() throws {
        let required:Set<String> = ["stand","idle0","idle1","idle2","land0","land1","land2",
            "peekLower","peekLook","peekRecover"]
        for species in newSpecies {
            for missing in required.sorted() {
                let e=fixture(species:species),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
                let plan=try XCTUnwrap(EdgePeekPlan.make(id:id,in:e)),origin=bird.position,revision=bird.motionRevision
                var world=e.world;world.availableFrames[species]?.remove(missing);e.updateWorld(world)
                let run=try started(e.runtime.start(EdgePeekExecution(plan:plan,source:.preview),source:.preview,in:e))
                XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
                XCTAssertEqual(bird.state,.perched);XCTAssertFalse(bird.isSideHopping)
                e.runtime.validate(in:e)
                terminal(e,run,.failed,.missingFrames)
                XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
            }
        }
    }

    func testNewPeekSpeciesPauseEveryPhaseThenCompleteWithoutChangingFeetOrFrame() throws {
        for species in newSpecies {
            for phase in phases {
                let e=fixture(species:species),bird=e.birds[0],origin=bird.position
                let run=try started(e.handle(.edgePeek(.preview))),peek=try execution(e,run)
                try reach(phase,in:e,run:run)
                let pose=try XCTUnwrap(e.renderSnapshot().first),age=e.runtime.runs[run]?.age
                let stateTime=bird.stateTime,observationAge=peek.observationAge
                e.handle(.pause(true));advance(e,seconds:2)
                for _ in 0..<3 {e.updateWorld(e.world);_=e.bounds(of:bird)}
                let frozen=try XCTUnwrap(e.renderSnapshot().first)
                XCTAssertEqual(frozen.frameName,pose.frameName);XCTAssertEqual(frozen.rect,pose.rect)
                XCTAssertEqual(bird.position,pose.position);XCTAssertEqual(bird.stateTime,stateTime)
                XCTAssertEqual(e.runtime.runs[run]?.age,age);XCTAssertEqual(peek.observationAge,observationAge)
                XCTAssertTrue(terminals(e,run).isEmpty)
                e.handle(.pause(false));advance(e,seconds:4)
                terminal(e,run,.completed);XCTAssertEqual(bird.position,origin)
            }
        }
    }

    func testNewPeekSpeciesEachPhaseReleasesOnClickReplacementAndPausedInvalidation() throws {
        for species in newSpecies {
            for phase in phases {
                for paused in [false,true] {
                    for cause in ["click","relocate","disabled","removed","sleep","host","peekLower","peekLook","peekRecover"] {
                        let e=fixture(species:species),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
                        let run=try started(e.handle(.edgePeek(.preview)))
                        try reach(phase,in:e,run:run)
                        if paused {e.handle(.pause(true))}
                        let actual=bird.position,clock=e.time
                        var observations:[BehaviorObservation]=[]
                        e.observationObserver={observations.append($0)}
                        var replacement:BehaviorRunID?
                        switch cause {
                        case "click":e.handle(.pointerClick)
                        case "relocate":replacement=try started(e.handle(.relocate(id)))
                        case "disabled":var settings=e.settings;settings.edgePeekEnabled=false;e.applySettings(settings)
                        case "removed":e.handle(.remove(id))
                        case "sleep":e.handle(.cancelAmbient(.sleep))
                        case "host":var world=e.world;world.surfaces=[];e.updateWorld(world)
                        default:var world=e.world;world.availableFrames[species]?.remove(cause);e.updateWorld(world)
                        }
                        let failed=cause == "host" || peekFrames.contains(cause)
                        let reason:BehaviorReason=cause == "host" ? .targetInvalid:(peekFrames.contains(cause) ? .missingFrames:
                            (cause == "disabled" ? .settingsChanged:(cause == "relocate" ? .replaced:
                                (cause == "removed" ? .removed:(cause == "sleep" ? .sleep:.userInput)))))
                        terminal(e,run,failed ? .failed:.cancelled,reason)
                        XCTAssertEqual(bird.position,actual);XCTAssertEqual(e.time,clock)
                        XCTAssertFalse(bird.isSideHopping);XCTAssertTrue(observations.isEmpty)
                        if let replacement {XCTAssertEqual(e.runtime.owners[id],replacement)}
                        else {XCTAssertEqual(e.leasedBirdCount,0)}
                        e.updateWorld(e.world);advance(e,seconds:0.1)
                        terminal(e,run,failed ? .failed:.cancelled,reason)
                        XCTAssertTrue(observations.isEmpty)
                    }
                }
            }
        }
    }

    func testOnlyBirdTickMovesFeetIncludingDuringObservationAndReturnSetup() throws {
        let e=fixture(),bird=e.birds[0],origin=bird.position
        let run=try started(e.requestEdgePeek(source:.preview)),peek=try execution(e,run)
        for _ in 0..<20 {
            XCTAssertNil(peek.validate(in:e));XCTAssertNil(peek.advance(0.1,in:e))
            e.updateWorld(e.world,sampleDT:0.1);_=e.renderSnapshot()
            XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.stateTime,0)
        }
        bird.tick(BehaviorEngine.step);XCTAssertNotEqual(bird.position,origin)
        try reach(.observe,in:e,run:run)
        let endpoint=bird.position,runtimeAge=e.runtime.runs[run]?.age
        for _ in 0..<100 {
            XCTAssertNil(peek.validate(in:e));_=peek.advance(BehaviorEngine.step,in:e)
            XCTAssertEqual(bird.position,endpoint)
        }
        XCTAssertEqual(peek.phase,.returning);XCTAssertEqual(bird.state,.flying)
        XCTAssertEqual(e.runtime.runs[run]?.age,runtimeAge)
        bird.tick(BehaviorEngine.step);XCTAssertNotEqual(bird.position,endpoint)
    }

    func testNormalizedDistanceRealEndpointsAndSmallScalePreflight() throws {
        for right in [false,true] {
            for distance:CGFloat in [79,80,95,110,111,400] {
                let e=fixture(right:right,distance:distance),id=try XCTUnwrap(e.id(of:e.birds[0]))
                let fits=(80...110).contains(distance)
                XCTAssertEqual(e.edgePeekCandidate(id,source:.preview),fits)
                if fits {_=try started(e.requestEdgePeek(source:.preview,target:id))}
                else {
                    XCTAssertEqual(e.requestEdgePeek(source:.preview,target:id),.rejected(.noSpace))
                    XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
                }
            }
        }
        let small=fixture(scale:0.25),bird=small.birds[0],id=try XCTUnwrap(small.id(of:bird)),origin=bird.position
        let a=LandingReservation(bird:id,host:host,fraction:bird.fraction)
        let b=LandingReservation(bird:id,host:host,fraction:0)
        XCTAssertTrue(a.conflicts(with:b,in:small))
        XCTAssertFalse(small.edgePeekCandidate(id,source:.preview))
        XCTAssertEqual(small.requestEdgePeek(source:.preview),.rejected(.noSpace))
        XCTAssertFalse(small.events.contains{$0.type == .started});XCTAssertEqual(bird.position,origin)
        XCTAssertEqual(small.leasedBirdCount,0);XCTAssertEqual(small.reservedLandingCount,0)

        let source=Surface(id:179,pid:23,rect:CGRect(x:100,y:900,width:800,height:200))
        let shared=fixture(host:source),model=shared.birds[0]
        model.fraction=0.1;model.perch(on:source,spriteScale:shared.spriteScale(for:model));advance(shared,seconds:0.5)
        let plan=try XCTUnwrap(EdgePeekPlan.make(id:try XCTUnwrap(shared.id(of:model)),in:shared))
        XCTAssertEqual(abs(try XCTUnwrap(plan.approach.destination.point(in:shared)).x-model.position.x),71.6,accuracy:0.001)
        XCTAssertFalse(plan.origin.conflicts(with:plan.approach.destination,in:shared))
        _=try started(shared.requestEdgePeek(source:.preview))
    }

    func testGroundOcclusionSeamsUnsettledAndSidePerchesCannotStart() throws {
        let ground=Geometry.ground(id:999,display:display,workArea:display)
        let e=fixture(host:ground)
        XCTAssertEqual(e.requestEdgePeek(source:.preview),.rejected(.noSpace))
        let seam=fixture(),bird=seam.birds[0],size=seam.spriteScale(for:bird)
        bird.fraction=fraction(at:-200+95*size,on:host);bird.perch(on:host,spriteScale:size);advance(seam,seconds:0.5)
        var world=seam.world
        world.surfaces.insert(Surface(id:172,rect:CGRect(x:-1000,y:400,width:800,height:200)),at:0);seam.updateWorld(world)
        XCTAssertTrue(seam.hasUsablePerch(bird))
        XCTAssertEqual(seam.requestEdgePeek(source:.preview),.rejected(.noSpace))
        let unsettled=fixture(),model=unsettled.birds[0]
        model.perch(on:host,spriteScale:unsettled.spriteScale(for:model))
        XCTAssertEqual(unsettled.requestEdgePeek(source:.preview),.rejected(.unavailableBird))
        advance(unsettled,seconds:0.5);model.perchDuration=model.stateTime+5
        XCTAssertEqual(unsettled.requestEdgePeek(source:.preview),.rejected(.unavailableBird))
        model.edge = .left;model.perch(on:host,spriteScale:unsettled.spriteScale(for:model));advance(unsettled,seconds:0.5)
        XCTAssertEqual(unsettled.requestEdgePeek(source:.preview),.rejected(.unavailableBird))
        XCTAssertEqual(unsettled.requestEdgePeek(source:.preview,target:BirdID(999)),.rejected(.missingBird))
    }

    func testUnsupportedSpeciesAndEveryMissingRequiredFrameRefuseBeforeStart() {
        for species in SpeciesID.allCases where !EdgePeekExecution.supportedSpecies.contains(species) {
            let e=fixture(species:species),origin=e.birds[0].position
            XCTAssertEqual(e.requestEdgePeek(source:.preview),.rejected(.noSpecies))
            XCTAssertEqual(e.birds[0].position,origin);XCTAssertEqual(e.leasedBirdCount,0)
        }
        for missing in EdgePeekPlan.requiredFrames.sorted()+["manifest"] {
            let e=fixture(),bird=e.birds[0],origin=bird.position
            var world=e.world
            if missing == "manifest" {world.availableFrames=[:]}
            else {world.availableFrames[bird.profile.id]?.remove(missing)}
            e.updateWorld(world)
            XCTAssertEqual(e.requestEdgePeek(source:.preview),.rejected(.missingFrames))
            XCTAssertEqual(bird.position,origin);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertFalse(e.events.contains{$0.type == .started})
        }
    }

    func testAutomaticQuietDisturbanceCooldownAndPreviewBypassesOnlyTiming() throws {
        let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
        let rhythm=try XCTUnwrap(e.perchPlanner.rhythms[id])
        XCTAssertFalse(e.edgePeekCandidate(id));XCTAssertEqual(e.requestEdgePeek(source:.automatic),.rejected(.unavailableBird))
        rhythm.quietTime=8;rhythm.disturbance=0.34
        XCTAssertTrue(e.edgePeekCandidate(id));rhythm.disturbance=0.35
        XCTAssertFalse(e.edgePeekCandidate(id));rhythm.disturbance=0
        rhythm.cooldowns[.edgePeek]=45;XCTAssertFalse(e.edgePeekCandidate(id))
        let preview=try started(e.requestEdgePeek(source:.preview,target:id))
        advance(e,seconds:4);terminal(e,preview,.completed)
        rhythm.quietTime=8
        XCTAssertEqual(e.requestEdgePeek(source:.automatic,target:id),.rejected(.unavailableBird))
        rhythm.cooldowns[.edgePeek]=nil
        let automatic=try started(e.requestEdgePeek(source:.automatic,target:id))
        advance(e,seconds:4);terminal(e,automatic,.completed)
        let unsafe=fixture(),model=unsafe.birds[0]
        pointer(model.position,in:unsafe)
        XCTAssertFalse(unsafe.edgePeekCandidate(try XCTUnwrap(unsafe.id(of:model)),source:.preview))
        XCTAssertEqual(unsafe.requestEdgePeek(source:.preview),.rejected(.noSpace))
    }

    func testPointerMustStayOutsideWholeCorridorMarginInEveryPhase() throws {
        for phase in phases {
            for atOrigin in [false,true] {
                let e=fixture(),bird=e.birds[0],run=try started(e.requestEdgePeek(source:.preview))
                let peek=try execution(e,run);try reach(phase,in:e,run:run)
                let actual=bird.position,oldFraction=bird.fraction,revision=bird.motionRevision
                let slot=atOrigin ? peek.plan.origin:peek.plan.approach.destination
                let p=try XCTUnwrap(slot.point(in:e)),size=e.spriteScale(for:bird)
                // Outside the sprite itself, still inside the protected margin.
                pointer(CGPoint(x:p.x,y:p.y+40*size),in:e)
                terminal(e,run,.cancelled,.pointerMoved)
                XCTAssertEqual(bird.position,actual);XCTAssertEqual(bird.fraction,oldFraction)
                XCTAssertFalse(bird.isSideHopping)
                if phase == .observe {
                    XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.motionRevision,revision)
                    XCTAssertFalse(bird.needsDestination)
                } else {XCTAssertEqual(bird.state,.flying);XCTAssertTrue(bird.needsDestination)}
                advance(e,seconds:0.2);XCTAssertEqual(bird.position,actual)
                terminal(e,run,.cancelled,.pointerMoved)
            }
        }
        let e=fixture(),run=try started(e.requestEdgePeek(source:.preview)),peek=try execution(e,run)
        let area=try XCTUnwrap(peek.sweptFootprint(in:e)),margin=48*peek.plan.approach.scale
        pointer(CGPoint(x:area.midX,y:area.minY-margin-1),in:e)
        advance(e,seconds:4);terminal(e,run,.completed)
    }

    func testSettingsButtonsClickAndRelocationCancelEachPhaseAtActualPosition() throws {
        for phase in phases {
            for action in ["setting","master","buttons","click","relocate"] {
                let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
                let run=try started(e.requestEdgePeek(source:.preview));try reach(phase,in:e,run:run)
                let actual=bird.position,oldFraction=bird.fraction
                var replacement:BehaviorRunID?
                switch action {
                case "setting","master":
                    var settings=e.settings
                    if action == "setting" {settings.edgePeekEnabled=false} else {settings.perchActions=false}
                    e.applySettings(settings)
                case "buttons":
                    e.handle(.pause(true));var world=e.world;world.buttonsDown=true;e.updateWorld(world)
                case "click":e.handle(.pointerClick)
                default:replacement=try started(e.handle(.relocate(id)))
                }
                terminal(e,run,.cancelled,action == "setting" || action == "master" ? .settingsChanged:(action == "relocate" ? .replaced:.userInput))
                XCTAssertEqual(bird.position,actual)
                if replacement==nil {XCTAssertEqual(bird.fraction,oldFraction)}
                XCTAssertFalse(bird.isSideHopping)
                if let replacement {XCTAssertEqual(e.runtime.owners[id],replacement)}
                else if phase == .observe {XCTAssertEqual(bird.state,.perched);XCTAssertFalse(bird.needsDestination)}
                else {XCTAssertTrue(bird.needsDestination)}
                if action == "setting" || action == "master" {
                    XCTAssertEqual(e.requestEdgePeek(source:.preview),.rejected(.disabled))
                }
                if action == "click" {
                    _=try started(e.handle(.relocate(id)));XCTAssertEqual(bird.position,actual)
                }
                advance(e,seconds:0.1)
                XCTAssertEqual(terminals(e,run).count,1)
            }
        }
    }

    func testPauseFreezesEachPhaseAndHostMetadataUntilBirdTickResumes() throws {
        for phase in phases {
            for sampleDT in [0.1,1.0] {
                let e=fixture(),bird=e.birds[0],originFraction=bird.fraction
                let run=try started(e.requestEdgePeek(source:.preview)),peek=try execution(e,run)
                try reach(phase,in:e,run:run);e.handle(.pause(true))
                let actual=bird.position,stateTime=bird.stateTime,age=e.runtime.runs[run]?.age,observationAge=peek.observationAge
                let frame=e.renderSnapshot().first?.frameName,oldFraction=bird.fraction
                var world=e.world;world.surfaces[0].rect.origin.x+=20;world.surfaces[0].rect.origin.y+=3
                e.updateWorld(world,sampleDT:sampleDT);advance(e,seconds:8)
                XCTAssertEqual(bird.position,actual);XCTAssertEqual(bird.fraction,oldFraction)
                XCTAssertEqual(bird.stateTime,stateTime);XCTAssertEqual(e.runtime.runs[run]?.age,age)
                XCTAssertEqual(peek.observationAge,observationAge);XCTAssertEqual(e.renderSnapshot().first?.frameName,frame)
                XCTAssertTrue(terminals(e,run).isEmpty);XCTAssertEqual(e.reservedLandingCount,2)
                XCTAssertEqual(e.requestEdgePeek(source:.preview),.rejected(.paused))
                e.handle(.pause(false));e.advance(BehaviorEngine.step)
                XCTAssertLessThan(Geometry.distance(bird.position,actual),20*e.spriteScale(for:bird))
                advance(e,seconds:4);terminal(e,run,.completed)
                XCTAssertEqual(bird.fraction,originFraction)
                XCTAssertEqual(bird.position,Geometry.foot(on:world.surfaces[0],fraction:originFraction,edge:.top,scale:e.spriteScale(for:bird)))
            }
        }
    }

    func testHostFramesScreensAndScaleInvalidationStillValidateWhenPaused() throws {
        for phase in phases {
            for scenario in ["removed","pid","resize","scale","display","workArea","fast","frames"] {
                let e=fixture(),bird=e.birds[0],run=try started(e.requestEdgePeek(source:.preview))
                try reach(phase,in:e,run:run);e.handle(.pause(true));let actual=bird.position
                var world=e.world
                switch scenario {
                case "removed":world.surfaces=[]
                case "pid":world.surfaces=[Surface(id:host.id,pid:host.pid+1,rect:host.rect)]
                case "resize":world.surfaces[0].rect.size.width-=10
                case "scale":world.scale*=1.1
                case "display":world.displays[0].origin.x+=1
                case "workArea":world.screens[0].size.height-=1
                case "fast":world.surfaces[0].rect.origin.x+=30
                default:world.availableFrames[bird.profile.id]?.remove("idle2")
                }
                e.updateWorld(world,sampleDT:BehaviorEngine.step)
                terminal(e,run,.failed,scenario == "frames" ? .missingFrames:.targetInvalid)
                XCTAssertEqual(bird.position,actual);XCTAssertFalse(bird.isSideHopping)
                advance(e,seconds:2);XCTAssertEqual(bird.position,actual)
                terminal(e,run,.failed,scenario == "frames" ? .missingFrames:.targetInvalid)
            }
        }
    }

    func testGentleWindowSamplesFollowThroughoutAndReturnToOriginalRelativeAnchor() throws {
        for right in [false,true] {
            let e=fixture(right:right),bird=e.birds[0],origin=bird.position,originFraction=bird.fraction
            let run=try started(e.requestEdgePeek(source:.preview)),peek=try execution(e,run)
            var world=e.world,metadataSteps=0,observedMotion=false,last=origin
            for step in 0..<300 {
                guard e.runtime.runs[run] != nil else {break}
                if step%6==0 {
                    let actual=bird.position
                    world.surfaces[0].rect.origin.x+=2;world.surfaces[0].rect.origin.y+=1
                    e.updateWorld(world,sampleDT:0.1);metadataSteps+=1
                    XCTAssertEqual(bird.position,actual,"Metadata must queue a move rather than reset feet")
                }
                let before=bird.position,phase=peek.phase
                e.advance(BehaviorEngine.step)
                if phase == .observe,bird.position != before {observedMotion=true}
                XCTAssertLessThan(Geometry.distance(bird.position,last),20*e.spriteScale(for:bird));last=bird.position
            }
            terminal(e,run,.completed);XCTAssertTrue(observedMotion)
            XCTAssertGreaterThan(metadataSteps,10);XCTAssertEqual(bird.fraction,originFraction)
            XCTAssertEqual(bird.position,Geometry.foot(on:world.surfaces[0],fraction:originFraction,edge:.top,scale:e.spriteScale(for:bird)))
            XCTAssertEqual(bird.position.x-origin.x,CGFloat(metadataSteps*2),accuracy:0.001)
            XCTAssertEqual(bird.position.y-origin.y,CGFloat(metadataSteps),accuracy:0.001)
        }
    }

    func testQueuedHostMoveAtReturnAndCompletionBoundariesMustSettleWithoutTeleporting() throws {
        for completing in [false,true] {
            let e=fixture(),bird=e.birds[0],originFraction=bird.fraction
            let run=try started(e.requestEdgePeek(source:.preview)),peek=try execution(e,run)
            var reached=false
            for _ in 0..<300 {
                let ready=completing ? peek.phase == .returning && bird.state == .perched:
                    peek.phase == .observe && peek.observationAge>=EdgePeekExecution.observationDuration-BehaviorEngine.step-1e-10
                if ready {reached=true;break}
                guard e.runtime.runs[run] != nil else {break}
                e.advance(BehaviorEngine.step)
            }
            XCTAssertTrue(reached)
            let actual=bird.position,revision=bird.motionRevision
            var world=e.world;world.surfaces[0].rect.origin.x+=20
            e.updateWorld(world,sampleDT:0.1);XCTAssertEqual(bird.position,actual)
            e.advance(BehaviorEngine.step)
            XCTAssertNotNil(e.runtime.runs[run]);XCTAssertEqual(e.reservedLandingCount,2)
            XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertEqual(peek.phase,completing ? .returning:.observe)
            XCTAssertGreaterThan(bird.position.x,actual.x)
            XCTAssertLessThanOrEqual(bird.position.x-actual.x,360*CGFloat(BehaviorEngine.step)+0.001)
            advance(e,seconds:4);terminal(e,run,.completed)
            XCTAssertEqual(bird.fraction,originFraction)
            XCTAssertEqual(bird.position,Geometry.foot(on:world.surfaces[0],fraction:originFraction,edge:.top,scale:e.spriteScale(for:bird)))
        }
    }

    func testBlockersOtherBirdsOrdinaryArrivalsAndBothReservedSlotsProtectRoute() throws {
        for blocker in ["endpoint","origin","arch","bird","arrival","reservation"] {
            let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird)),size=e.spriteScale(for:bird)
            let plan=try XCTUnwrap(EdgePeekPlan.make(id:id,in:e)),end=try XCTUnwrap(plan.approach.destination.point(in:e))
            let middle=CGPoint(x:(end.x+bird.position.x)/2,y:host.rect.minY)
            switch blocker {
            case "endpoint","origin","arch":
                let point=blocker == "endpoint" ? end:bird.position
                let rect=blocker == "arch" ? CGRect(x:middle.x,y:middle.y-49*size,width:size,height:2*size):
                    Geometry.landingFootprint(at:point,scale:size)
                var world=e.world;world.surfaces.insert(Surface(id:172,rect:rect),at:0);e.updateWorld(world)
                if blocker == "arch" {
                    XCTAssertTrue(plan.origin.isValid(in:e));XCTAssertTrue(plan.approach.destination.isValid(in:e))
                }
            case "bird":
                let other=distantBird(in:e);other.position=middle
            case "arrival":
                let other=distantBird(in:e);other.fraction=fraction(at:middle.x,on:host)
                other.fly(to:middle,host:host,duration:8,allowsOrbit:false,random:{0.5})
                XCTAssertGreaterThan(Geometry.distance(other.position,middle),500)
            default:
                let other=distantBird(in:e)
                let slot=LandingReservation(bird:try XCTUnwrap(e.id(of:other)),host:host,fraction:fraction(at:middle.x,on:host))
                _=try started(e.runtime.start(SlotExecution(slot),source:.preview,in:e))
            }
            XCTAssertEqual(e.requestEdgePeek(source:.preview,target:id),.rejected(.noSpace))
            XCTAssertNil(e.runtime.owners[id]);XCTAssertFalse(bird.isSideHopping)
        }
        for atOrigin in [false,true] {
            let e=fixture(),run=try started(e.requestEdgePeek(source:.preview)),peek=try execution(e,run)
            let other=distantBird(in:e),id=try XCTUnwrap(e.id(of:other))
            let fraction=atOrigin ? peek.plan.origin.fraction:peek.plan.approach.destination.fraction
            XCTAssertEqual(e.runtime.start(SlotExecution(LandingReservation(bird:id,host:host,fraction:fraction)),source:.preview,in:e),.rejected(.noSpace))
            XCTAssertEqual(e.reservedLandingCount,2);XCTAssertEqual(e.leasedBirdCount,1)
            advance(e,seconds:4);terminal(e,run,.completed)
            let next=try started(e.runtime.start(SlotExecution(LandingReservation(bird:id,host:host,fraction:fraction)),source:.preview,in:e))
            e.runtime.cancel(next,reason:.removed,in:e);XCTAssertEqual(e.reservedLandingCount,0)
        }
    }

    func testLateThinBlockerAndBirdIntrusionCancelEveryPhaseWithoutTeleporting() throws {
        for phase in phases {
            for intruder in [false,true] {
                let e=fixture(),bird=e.birds[0],run=try started(e.requestEdgePeek(source:.preview))
                let peek=try execution(e,run);try reach(phase,in:e,run:run)
                let actual=bird.position,size=e.spriteScale(for:bird)
                let start=try XCTUnwrap(peek.plan.origin.point(in:e)),end=try XCTUnwrap(peek.plan.approach.destination.point(in:e))
                if intruder {let other=distantBird(in:e);other.position=start}
                else {
                    var world=e.world
                    world.surfaces.insert(Surface(id:172,rect:CGRect(x:(start.x+end.x)/2,y:start.y-49*size,width:size,height:2*size)),at:0)
                    e.updateWorld(world)
                }
                e.updateWorld(e.world);terminal(e,run,.failed,.targetInvalid)
                XCTAssertEqual(bird.position,actual)
                if phase == .observe {XCTAssertEqual(bird.state,.perched);XCTAssertFalse(bird.needsDestination)}
                else {XCTAssertTrue(bird.needsDestination)}
            }
        }
    }

    func testOccludedObservationEndpointRecoversFromActualFoot() throws {
        let e=fixture(),bird=e.birds[0],run=try started(e.handle(.edgePeek(.preview)))
        try reach(.observe,in:e,run:run)
        e.handle(.pause(true));let actual=bird.position
        var world=e.world
        world.surfaces.insert(Surface(id:172,rect:Geometry.landingFootprint(at:actual,
            scale:e.spriteScale(for:bird)).insetBy(dx:-5,dy:-5)),at:0)
        e.updateWorld(world)
        terminal(e,run,.failed,.targetInvalid)
        XCTAssertEqual(bird.position,actual);XCTAssertTrue(bird.needsDestination)
        XCTAssertNil(bird.hostID);XCTAssertFalse(bird.isSideHopping)
        e.updateWorld(world);advance(e,seconds:1)
        XCTAssertEqual(bird.position,actual)
        e.handle(.pause(false));advance(e,seconds:1)
        XCTAssertEqual(bird.position,actual)
    }

    func testCancelWhilePausedWithPendingHostMovementNeverSnapsToHost() throws {
        for master in [false,true] {
            let e=fixture(),bird=e.birds[0],run=try started(e.handle(.edgePeek(.preview)))
            try reach(.observe,in:e,run:run);e.handle(.pause(true))
            let actual=bird.position
            var world=e.world;world.surfaces[0].rect.origin.x+=20
            e.updateWorld(world,sampleDT:0.1)
            XCTAssertEqual(bird.position,actual)
            var settings=e.settings
            if master {settings.perchActions=false} else {settings.edgePeekEnabled=false}
            e.applySettings(settings);terminal(e,run,.cancelled,.settingsChanged)
            XCTAssertTrue(bird.needsDestination);XCTAssertNil(bird.hostID)
            e.updateWorld(world,sampleDT:0.1);advance(e,seconds:2)
            XCTAssertEqual(bird.position,actual);XCTAssertFalse(bird.isSideHopping)
            e.handle(.pause(false));advance(e,seconds:1)
            XCTAssertEqual(bird.position,actual)
        }
    }

    private final class SlotExecution:BehaviorExecution {
        let kind:BehaviorKind = .relocate
        let occupiesEncounter=false,runsWhilePaused=false,timeout=10.0
        let landingReservations:[LandingReservation]
        var participants:[BirdID] {landingReservations.map(\.bird)}
        init(_ slot:LandingReservation) {landingReservations=[slot]}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }
    private final class TraversalExecution:LedgeTraversalExecution {
        let kind:BehaviorKind
        let participants:[BirdID]
        let area:CGRect
        let timeout=10.0
        init(id:BirdID,kind:BehaviorKind,area:CGRect) {participants=[id];self.kind=kind;self.area=area}
        func sweptFootprint(in engine:BehaviorEngine) -> CGRect? {area}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }
    func testSideHopAndEdgePeekShareContinuousCorridorChecksAndSkipOwnRun() throws {
        for kind:BehaviorKind in [.sideHop,.edgePeek] {
            let e=fixture(),bird=e.birds[0],other=distantBird(in:e),size=e.spriteScale(for:bird)
            // The foreign participant and its slots cannot cause a collision;
            // only the traversal protocol exposes this thin overhead corridor.
            let area=CGRect(x:bird.position.x,y:bird.position.y-49*size,width:size,height:2*size)
            let blocker=try started(e.runtime.start(TraversalExecution(id:try XCTUnwrap(e.id(of:other)),kind:kind,area:area),source:.preview,in:e))
            let id=try XCTUnwrap(e.id(of:bird))
            let rejected=kind == .sideHop ? e.requestEdgePeek(source:.preview,target:id):e.requestSideHop(source:.preview,target:id)
            XCTAssertEqual(rejected,.rejected(.noSpace));XCTAssertEqual(e.reservedLandingCount,0)
            e.runtime.cancel(blocker,reason:.removed,in:e)
            let accepted=kind == .sideHop ? e.requestEdgePeek(source:.preview,target:id):e.requestSideHop(source:.preview,target:id)
            let run=try started(accepted)
            advance(e,seconds:4);terminal(e,run,.completed)
        }
    }

    func testTimeoutAndExternalRouteReplacementReleaseOnceWithoutRestoringOldCoordinates() throws {
        let e=fixture(),bird=e.birds[0],run=try started(e.requestEdgePeek(source:.preview))
        advance(e,seconds:0.1);let actual=bird.position
        // Deliberately stall Bird.tick to exercise the runtime's finite deadline.
        e.runtime.advance(6.1,in:e);terminal(e,run,.failed,.timedOut)
        XCTAssertEqual(bird.position,actual);XCTAssertTrue(bird.needsDestination)
        advance(e,seconds:1);XCTAssertEqual(bird.position,actual);terminal(e,run,.failed,.timedOut)
        let routed=fixture(),model=routed.birds[0],old=try started(routed.requestEdgePeek(source:.preview))
        try reach(.observe,in:routed,run:old)
        let endpoint=model.position
        model.fly(to:CGPoint(x:100,y:300),host:host,duration:3,allowsOrbit:false,random:{0.5})
        let revision=model.motionRevision
        routed.updateWorld(routed.world);terminal(routed,old,.failed,.targetInvalid)
        XCTAssertEqual(model.position,endpoint);XCTAssertEqual(model.motionRevision,revision)
        advance(routed,seconds:0.1);XCTAssertNotEqual(model.position,endpoint)
    }

    func testFixedStepResultsMatchAcrossRenderRatesIncludingPauseAndCancellation() throws {
        struct Trace:Equatable {
            let position:CGPoint,fraction:CGFloat,frame:String
            let counts:[Int],events:[String]
        }
        func replay(_ hz:Int) throws -> [Trace] {
            let e=fixture(),bird=e.birds[0],run=try started(e.requestEdgePeek(source:.preview))
            var trace:[Trace]=[]
            for part in 0..<40 {
                if part==10 {e.handle(.pause(true))}
                if part==13 {e.handle(.pause(false))}
                if part==20 {e.handle(.pointerClick)}
                advance(e,seconds:0.1,hz:hz)
                trace.append(Trace(position:bird.position,fraction:bird.fraction,frame:e.renderSnapshot().first!.frameName,
                    counts:[e.activeRunCount,e.leasedBirdCount,e.reservedLandingCount],
                    events:e.events.map{"\($0.time):\($0.type):\($0.kind?.rawValue ?? ""):\($0.reason?.rawValue ?? "")"}))
            }
            terminal(e,run,.cancelled,.userInput)
            return trace
        }
        let reference=try replay(60)
        XCTAssertEqual(try replay(30),reference);XCTAssertEqual(try replay(120),reference)
    }
}
