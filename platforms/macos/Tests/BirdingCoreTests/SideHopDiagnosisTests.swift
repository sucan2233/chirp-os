import XCTest
@testable import BirdingCore

/// Production commands and world updates exercise the two validation paths.
/// These fixtures do not mock a safety predicate or turn targetInvalid into a
/// completion. Run after all M6a/M6b code is ready, together with the main suite.
final class SideHopDiagnosisTests:XCTestCase {
    private let display=CGRect(x:-1200,y:-400,width:2400,height:1400)
    private let host=Surface(id:151,pid:23,rect:CGRect(x:-900,y:500,width:1800,height:300))

    private func fixture(scale:CGFloat=1,right:Bool=true) -> BehaviorEngine {
        let engine=BehaviorEngine(seed:731)
        engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
        let frames=SideHopPlan.requiredFrames.union(["blink","breathe","idle0","idle1","idle2"])
            .union((0...7).map{"fly\($0)"})
        engine.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[host],scale:scale,
            pointer:CGPoint(x:right ? -1100:1100,y:-300),availableFrames:[.treeSparrow:frames]))
        let bird=Bird(position:.zero,fraction:0.5,profile:engine.settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:engine.spriteScale(for:bird));bird.perchDuration=600
        engine.installFixtureBirds([bird]);advance(engine,seconds:0.5)
        return engine
    }
    private func advance(_ engine:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {engine.advance(1/Double(hz))}
    }
    private func start(_ engine:BehaviorEngine) throws -> (BehaviorRunID,SideHopExecution) {
        guard case .started(let run)=engine.handle(.sideHop(.preview)) else {
            XCTFail("Expected a production sideHop command to start")
            throw NSError(domain:"SideHopDiagnosisTests",code:1)
        }
        return (run,try XCTUnwrap(engine.runtime.runs[run]?.execution as? SideHopExecution))
    }
    private func assertFailed(_ engine:BehaviorEngine,_ run:BehaviorRunID,file:StaticString=#filePath,line:UInt=#line) {
        let ends=engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
        XCTAssertEqual(ends.count,1,file:file,line:line)
        XCTAssertEqual(ends.first?.type,.failed,file:file,line:line)
        XCTAssertEqual(ends.first?.reason,.targetInvalid,file:file,line:line)
        XCTAssertNil(engine.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(engine.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(engine.leasedBirdCount,0,file:file,line:line)
        XCTAssertEqual(engine.reservedLandingCount,0,file:file,line:line)
    }
    private func distantBird(in engine:BehaviorEngine) -> Bird {
        let bird=Bird(position:CGPoint(x:-1000,y:-200),fraction:0.95,profile:engine.birds[0].profile,random:{0.5})
        engine.register(bird);return bird
    }

    func testThinArcObstructionAtExactTouchAndPositiveOverlapAcrossScalesAndFacings() throws {
        for scale:CGFloat in [0.5,1,2] {
            for right in [false,true] {
                let engine=fixture(scale:scale,right:right),bird=engine.birds[0]
                let (run,hop)=try start(engine)
                advance(engine,seconds:0.1)
                engine.handle(.pause(true))
                let actual=bird.position,size=engine.spriteScale(for:bird)
                let corridor=try XCTUnwrap(hop.sweptFootprint(in:engine))
                // The blocker is above the destination body, within the low
                // arch's interior in x. A zero-area contact is still safe.
                var world=engine.world
                let rect=CGRect(x:hop.plan.host.rect.midX+(right ? 30:-30)*size,
                    y:corridor.minY-size,width:size,height:size)
                world.surfaces.insert(Surface(id:152,rect:rect),at:0)
                engine.updateWorld(world)
                XCTAssertNil(hop.diagnostic)
                XCTAssertNotNil(engine.runtime.runs[run])
                XCTAssertTrue(hop.plan.destination.isValid(in:engine))
                world.surfaces[0].rect.origin.y+=0.001*size
                engine.updateWorld(world)
                assertFailed(engine,run)
                let diagnostic=try XCTUnwrap(hop.diagnostic)
                XCTAssertEqual(diagnostic.cause,.surfaceObstruction)
                XCTAssertEqual(diagnostic.classification,.safetyExit)
                XCTAssertEqual(diagnostic.stage,"executionValidation")
                XCTAssertEqual(diagnostic.conflictingSurface,152)
                XCTAssertEqual(diagnostic.position,actual)
                XCTAssertTrue(diagnostic.isSideHopping)
                XCTAssertFalse(diagnostic.needsDestination)
                XCTAssertTrue(bird.needsDestination)
                XCTAssertFalse(bird.isSideHopping)
                XCTAssertEqual(bird.position,actual)
                advance(engine,seconds:1)
                XCTAssertEqual(hop.diagnostic,diagnostic)
                assertFailed(engine,run)
            }
        }
    }

    func testLateBirdIntrusionAtTouchBoundaryPreservesPreCancelEvidenceWhilePaused() throws {
        for paused in [false,true] {
            let engine=fixture(),bird=engine.birds[0]
            let (run,hop)=try start(engine)
            advance(engine,seconds:0.1)
            engine.handle(.pause(paused))
            let actual=bird.position,other=distantBird(in:engine)
            let corridor=try XCTUnwrap(hop.sweptFootprint(in:engine)),size=engine.spriteScale(for:other)
            other.position=CGPoint(x:0,y:host.rect.minY)
            let footprint=Geometry.landingFootprint(at:other.position,scale:size)
                .union(engine.bounds(of:other)).insetBy(dx:-8,dy:-8)
            other.position.x+=corridor.maxX-footprint.minX
            engine.updateWorld(engine.world)
            XCTAssertNotNil(engine.runtime.runs[run])
            XCTAssertNil(hop.diagnostic)
            other.position.x-=0.001
            engine.updateWorld(engine.world)
            assertFailed(engine,run)
            let diagnostic=try XCTUnwrap(hop.diagnostic)
            XCTAssertEqual(diagnostic.cause,.birdIntrusion)
            XCTAssertEqual(diagnostic.classification,.safetyExit)
            XCTAssertEqual(diagnostic.conflictingBird,engine.id(of:other)?.rawValue)
            let cut=try XCTUnwrap(diagnostic.corridor).intersection(try XCTUnwrap(diagnostic.conflictingFootprint))
            XCTAssertFalse(cut.isNull);XCTAssertFalse(cut.isEmpty)
            XCTAssertEqual(diagnostic.expectedMotionRevision,diagnostic.actualMotionRevision)
            XCTAssertEqual(diagnostic.position,actual)
            XCTAssertEqual(bird.position,actual)
            XCTAssertTrue(bird.needsDestination)
        }
    }

    func testOrdinaryFutureArrivalIsDistinctFromPhysicalIntrusion() throws {
        let engine=fixture(),bird=engine.birds[0]
        let (run,hop)=try start(engine)
        advance(engine,seconds:0.1)
        let actual=bird.position,other=distantBird(in:engine),size=engine.spriteScale(for:other)
        let x=host.rect.midX+30*size
        other.fraction=(x-Geometry.perchX(0,rect:host.rect))/(Geometry.perchX(1,rect:host.rect)-Geometry.perchX(0,rect:host.rect))
        other.fly(to:Geometry.foot(on:host,fraction:other.fraction,edge:.top,scale:size),
            host:host,duration:8,allowsOrbit:false,random:{0.5})
        XCTAssertGreaterThan(Geometry.distance(other.position,actual),500)
        engine.updateWorld(engine.world)
        assertFailed(engine,run)
        let diagnostic=try XCTUnwrap(hop.diagnostic)
        XCTAssertEqual(diagnostic.cause,.arrivalConflict)
        XCTAssertEqual(diagnostic.classification,.safetyExit)
        XCTAssertEqual(diagnostic.conflictingBird,engine.id(of:other)?.rawValue)
        XCTAssertEqual(diagnostic.conflictingSurface,host.id)
        XCTAssertEqual(bird.position,actual)
    }

    func testRecordedRun183GeometryShowsMarginIntrusionWithoutDestinationSlotOverlap() {
        // Frozen measured geometry from .build/m6a-sidehop-183.json. This is
        // evidence of the failure boundary, not a reconstruction of bird 23's
        // unrecorded route or ownership history. The historical M5n/M6ab
        // seed73/run183/bird27/event396/t734.1 evidence and diagnosis remain in
        // docs/m6a-sidehop-diagnosis.md; simulation 12 has a different scheduler.
        let corridor=CGRect(x:256.8847997859697,y:50.5560272098087,
            width:138.63702174504618,height:58.16937975316625)
        let peer=CGRect(x:196.35375665100855,y:36.45638150969205,
            width:67.67699306179907,height:61.111994258040596)
        let cut=corridor.intersection(peer)
        XCTAssertEqual(cut.width,7.145949926837943,accuracy:0.000001)
        XCTAssertEqual(cut.height,47.01234855792395,accuracy:0.000001)
        let unpadded=peer.insetBy(dx:8,dy:8)
        XCTAssertEqual(corridor.minX-unpadded.maxX,0.8540500731620568,accuracy:0.000001)
        XCTAssertTrue(corridor.intersection(unpadded).isNull || corridor.intersection(unpadded).isEmpty)
        let slot=Geometry.landingFootprint(at:CGPoint(x:367.4066213169855,y:100),scale:0.9694896625527707)
            .insetBy(dx:-8,dy:-8)
        XCTAssertTrue(slot.intersection(peer).isNull || slot.intersection(peer).isEmpty)
        XCTAssertEqual(slot.minX-peer.maxX,67.26067139014757,accuracy:0.000001)
    }

    func testExistingUnleasedFlightDocumentsDynamicSafetyExitWithDistinctLandingSlots() throws {
        var failureTimes:[Double]=[]
        for hz in [30,60,120] {
            let engine=fixture(),bird=engine.birds[0],origin=bird.position
            let targetX=origin.x+400
            let fraction=(targetX-Geometry.perchX(0,rect:host.rect))/(Geometry.perchX(1,rect:host.rect)-Geometry.perchX(0,rect:host.rect))
            let other=Bird(position:CGPoint(x:origin.x-200,y:host.rect.minY),fraction:fraction,
                profile:bird.profile,random:{0.5})
            engine.register(other)
            // Install the peer's existing route BEFORE accepting the hop. A
            // short urgent transit makes this two-bird fixture finite; it still
            // uses the production flight integrator, with no position writes
            // after construction and no mocked collision/validation result.
            other.fly(to:CGPoint(x:targetX,y:host.rect.minY),host:host,duration:0.8,arc:0,
                urgent:true,allowsOrbit:false,random:{0.5})
            let otherID=try XCTUnwrap(engine.id(of:other))
            let (run,hop)=try start(engine)
            XCTAssertNil(engine.runtime.owners[otherID])
            XCTAssertEqual(engine.reservedLandingCount,1)
            XCTAssertNil(hop.plan.safetyIssue(in:engine),"Current body and future landing are clear at admission")
            let planned=try XCTUnwrap(other.plannedFlightFootprint(scale:engine.spriteScale(for:other)))
            let corridor=try XCTUnwrap(hop.sweptFootprint(in:engine))
            let futureCut=corridor.intersection(planned)
            XCTAssertFalse(futureCut.isNull);XCTAssertFalse(futureCut.isEmpty)
            let arrival=Geometry.landingFootprint(at:Geometry.foot(on:host,fraction:fraction,edge:.top,
                scale:engine.spriteScale(for:other)),scale:engine.spriteScale(for:other)).insetBy(dx:-8,dy:-8)
            let reserved=try XCTUnwrap(hop.plan.destination.footprint(in:engine))
            XCTAssertTrue(reserved.intersection(arrival).isNull || reserved.intersection(arrival).isEmpty)
            for _ in 0..<hz {
                engine.advance(1/Double(hz))
                if hop.diagnostic != nil {break}
            }
            assertFailed(engine,run)
            let diagnostic=try XCTUnwrap(hop.diagnostic)
            XCTAssertEqual(diagnostic.cause,.birdIntrusion)
            XCTAssertEqual(diagnostic.classification,.safetyExit)
            XCTAssertEqual(diagnostic.stage,"executionValidation")
            XCTAssertEqual(diagnostic.conflictingBird,otherID.rawValue)
            XCTAssertEqual(diagnostic.expectedMotionRevision,diagnostic.actualMotionRevision)
            XCTAssertNil(diagnostic.accompanyingSafety)
            XCTAssertEqual(diagnostic.position,bird.position)
            XCTAssertTrue(bird.needsDestination)
            XCTAssertFalse(bird.isSideHopping)
            XCTAssertGreaterThan(other.position.x,origin.x-200,"The peer reached the corridor by ticking its flight")
            XCTAssertNil(engine.runtime.owners[otherID])
            failureTimes.append(diagnostic.simulationTime)
            let stopped=bird.position
            advance(engine,seconds:1)
            XCTAssertEqual(bird.position,stopped)
            assertFailed(engine,run)
        }
        XCTAssertEqual(failureTimes[0],failureTimes[1],accuracy:0.000001)
        XCTAssertEqual(failureTimes[1],failureTimes[2],accuracy:0.000001)
    }

    func testRuntimeSlotPrevalidationRetainsDiagnosisBeforeCancelAndAfterEventRingEviction() throws {
        let engine=fixture(),bird=engine.birds[0],auditor=BehaviorStress.Auditor()
        var retained:SideHopExecution?
        engine.eventObserver={event in
            if event.type == .started,let id=event.runID {
                retained=engine.runtime.runs[id]?.execution as? SideHopExecution
            }
            auditor.observe(event,sideHop:event.type == .failed ? retained?.diagnostic:nil)
        }
        let (run,hop)=try start(engine)
        advance(engine,seconds:0.1)
        let actual=bird.position
        var world=engine.world
        let foot=try XCTUnwrap(hop.plan.destination.point(in:engine))
        let block=Geometry.landingFootprint(at:foot,scale:engine.spriteScale(for:bird))
        world.surfaces.insert(Surface(id:152,rect:block),at:0)
        engine.updateWorld(world)
        assertFailed(engine,run)
        let diagnostic=try XCTUnwrap(hop.diagnostic)
        XCTAssertEqual(diagnostic.cause,.destinationInvalid)
        XCTAssertEqual(diagnostic.classification,.safetyExit)
        XCTAssertEqual(diagnostic.stage,"runtimeValidation")
        XCTAssertEqual(diagnostic.conflictingSurface,152)
        XCTAssertTrue(diagnostic.isSideHopping)
        XCTAssertEqual(diagnostic.position,actual)
        for _ in 0..<300 {engine.handle(.relocate(BirdID(999)))}
        XCTAssertFalse(engine.events.contains{$0.runID==run})
        XCTAssertEqual(auditor.failures.byBehavior,["sideHop":1])
        XCTAssertEqual(auditor.failures.samples.first?.sideHop,diagnostic)
        XCTAssertEqual(try JSONDecoder().decode(BehaviorStress.FailureDiagnostics.self,
            from:JSONEncoder().encode(auditor.failures)),auditor.failures)
    }

    func testHostIdentityResizeScaleAndLayoutUseConcreteSafetyEvidence() throws {
        let cases:[(String,SideHopDiagnostic.Cause,SideHopDiagnostic.Cause?)]=[
            ("removed",.hostMissingOrReplaced,nil),("pid",.hostMissingOrReplaced,nil),
            ("resize",.motionRevisionChanged,.hostGeometryChanged),("scale",.motionRevisionChanged,.scaleChanged),
            ("display",.displayLayoutChanged,nil),("workArea",.displayLayoutChanged,nil)]
        for (scenario,cause,accompanyingCause) in cases {
            let engine=fixture(),bird=engine.birds[0]
            let (run,hop)=try start(engine)
            advance(engine,seconds:0.1);engine.handle(.pause(true))
            let actual=bird.position
            var world=engine.world
            switch scenario {
            case "removed":world.surfaces=[]
            case "pid":world.surfaces=[Surface(id:host.id,pid:host.pid+1,rect:host.rect)]
            case "resize":world.surfaces[0].rect.size.width-=10
            case "scale":world.scale*=1.1
            case "display":world.displays[0].origin.x+=1
            default:world.screens[0].size.height-=1
            }
            // Exercise the actual Bird.updateHost metadata path as well as the
            // runtime's early destination validation. No manual diagnostic call.
            engine.updateWorld(world,sampleDT:0.1)
            assertFailed(engine,run)
            let diagnostic=try XCTUnwrap(hop.diagnostic)
            XCTAssertEqual(diagnostic.cause,cause,scenario)
            XCTAssertEqual(diagnostic.classification,accompanyingCause==nil ? .safetyExit:.unresolved,scenario)
            XCTAssertEqual(diagnostic.accompanyingSafety?.cause,accompanyingCause,scenario)
            XCTAssertEqual(diagnostic.position,actual)
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

    func testRuntimeDoublePaddingConflictIsDiagnosedEvenWhenTraversalCorridorIsClear() throws {
        let engine=fixture(),bird=engine.birds[0]
        let (run,hop)=try start(engine)
        advance(engine,seconds:0.1)
        let actual=bird.position,other=distantBird(in:engine),size=engine.spriteScale(for:bird)
        let destination=try XCTUnwrap(hop.plan.destination.point(in:engine))
        // Body gap 12: foreign padding (8) misses the hop's body, but both
        // reservation margins together (16) overlap. A separate ground ledge
        // moves upward into this gap through a real world update.
        let x=destination.x+58*size+12
        let ground=Surface(id:159,rect:CGRect(x:x-250,y:650,width:500,height:100),isGround:true)
        var world=engine.world;world.surfaces.append(ground);engine.updateWorld(world)
        let slot=LandingReservation(bird:try XCTUnwrap(engine.id(of:other)),host:ground,fraction:0.5)
        guard case .started(let foreign)=engine.runtime.start(SlotExecution(slot),source:.preview,in:engine) else {
            return XCTFail("Expected separated reservations to be accepted")
        }
        world.surfaces[1].rect.origin.y=host.rect.minY
        engine.updateWorld(world)
        let diagnostic=try XCTUnwrap(hop.diagnostic)
        XCTAssertEqual(diagnostic.cause,.reservationConflict)
        XCTAssertEqual(diagnostic.classification,.safetyExit)
        XCTAssertEqual(diagnostic.stage,"runtimeValidation")
        XCTAssertEqual(diagnostic.conflictingBird,engine.id(of:other)?.rawValue)
        let cut=try XCTUnwrap(diagnostic.corridor).intersection(try XCTUnwrap(diagnostic.conflictingFootprint))
        XCTAssertTrue(cut.isNull || cut.isEmpty,"Only Runtime's two padded slots conflict")
        XCTAssertEqual(bird.position,actual)
        XCTAssertNil(engine.runtime.runs[run])
        XCTAssertEqual(engine.reservedLandingCount,1)
        engine.runtime.cancel(foreign,reason:.removed,in:engine)
        assertFailed(engine,run)
    }

    func testSafeCompletionHasNoFailureEvidenceAt30And60And120Hz() throws {
        var traces:[[String]]=[]
        for hz in [30,60,120] {
            let engine=fixture()
            let (run,hop)=try start(engine)
            advance(engine,seconds:1.5,hz:hz)
            XCTAssertNil(hop.diagnostic)
            let ends=engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
            XCTAssertEqual(ends.count,1)
            XCTAssertEqual(ends.first?.type,.completed)
            XCTAssertEqual(engine.leasedBirdCount,0)
            XCTAssertEqual(engine.reservedLandingCount,0)
            traces.append(engine.events.map{"\($0.sequence):\($0.time):\($0.type):\($0.reason?.rawValue ?? "")"})
        }
        XCTAssertEqual(traces[0],traces[1]);XCTAssertEqual(traces[1],traces[2])
    }

    func testUnexpectedMotionReplacementRemainsUnresolvedAndDoesNotCancelNewMotion() throws {
        let engine=fixture(),bird=engine.birds[0]
        let (run,hop)=try start(engine)
        advance(engine,seconds:0.1)
        let actual=bird.position
        bird.fly(to:CGPoint(x:500,y:500),host:host,duration:8,allowsOrbit:false,random:{0.5})
        let newRevision=bird.motionRevision
        engine.updateWorld(engine.world)
        assertFailed(engine,run)
        let diagnostic=try XCTUnwrap(hop.diagnostic)
        XCTAssertEqual(diagnostic.cause,.motionRevisionChanged)
        XCTAssertEqual(diagnostic.classification,.unresolved)
        XCTAssertNotEqual(diagnostic.expectedMotionRevision,diagnostic.actualMotionRevision)
        XCTAssertEqual(bird.motionRevision,newRevision)
        XCTAssertEqual(bird.position,actual)
        XCTAssertFalse(bird.needsDestination)
    }

    func testMotionRevisionChangeWithConcurrentBirdIntrusionKeepsActualGuardAsPrimary() throws {
        let engine=fixture(),bird=engine.birds[0]
        let (run,hop)=try start(engine)
        advance(engine,seconds:0.1)
        let actual=bird.position,other=distantBird(in:engine)
        bird.fly(to:CGPoint(x:500,y:500),host:host,duration:8,allowsOrbit:false,random:{0.5})
        let newRevision=bird.motionRevision
        other.position=actual
        engine.updateWorld(engine.world)
        assertFailed(engine,run)
        let diagnostic=try XCTUnwrap(hop.diagnostic)
        XCTAssertEqual(diagnostic.cause,.motionRevisionChanged)
        XCTAssertEqual(diagnostic.classification,.unresolved)
        XCTAssertEqual(diagnostic.stage,"executionValidation")
        XCTAssertNotEqual(diagnostic.expectedMotionRevision,diagnostic.actualMotionRevision)
        XCTAssertNil(diagnostic.conflictingBird,"Concurrent intrusion is not the primary failure")
        let safety=try XCTUnwrap(diagnostic.accompanyingSafety)
        XCTAssertEqual(safety.cause,.birdIntrusion)
        XCTAssertEqual(safety.conflictingBird,engine.id(of:other)?.rawValue)
        let cut=try XCTUnwrap(diagnostic.corridor).intersection(try XCTUnwrap(safety.conflictingFootprint))
        XCTAssertFalse(cut.isNull);XCTAssertFalse(cut.isEmpty)
        XCTAssertEqual(bird.motionRevision,newRevision,"Old run must not cancel replacement motion")
        XCTAssertEqual(bird.position,actual)
        XCTAssertFalse(bird.needsDestination)
        let data=try JSONEncoder().encode(diagnostic)
        XCTAssertEqual(try JSONDecoder().decode(SideHopDiagnostic.self,from:data),diagnostic)
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        legacy.removeValue(forKey:"accompanyingSafety")
        let decoded=try JSONDecoder().decode(SideHopDiagnostic.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertEqual(decoded.cause,.motionRevisionChanged)
        XCTAssertEqual(decoded.classification,.unresolved)
        XCTAssertNil(decoded.accompanyingSafety)
        engine.updateWorld(engine.world)
        XCTAssertEqual(hop.diagnostic,diagnostic,"Cancel fallback must not overwrite the primary failure")
    }

    func testMotionStateChangeWithConcurrentBirdIntrusionKeepsActualGuardAsPrimary() throws {
        let engine=fixture(),bird=engine.birds[0]
        let (run,hop)=try start(engine)
        advance(engine,seconds:0.1)
        let actual=bird.position,other=distantBird(in:engine)
        bird.edge = .left // Invalid motion state without changing its revision.
        other.position=actual
        engine.updateWorld(engine.world)
        assertFailed(engine,run)
        let diagnostic=try XCTUnwrap(hop.diagnostic)
        XCTAssertEqual(diagnostic.cause,.motionStateChanged)
        XCTAssertEqual(diagnostic.classification,.unresolved)
        XCTAssertEqual(diagnostic.stage,"executionValidation")
        XCTAssertEqual(diagnostic.expectedMotionRevision,diagnostic.actualMotionRevision)
        XCTAssertNil(diagnostic.conflictingBird)
        let safety=try XCTUnwrap(diagnostic.accompanyingSafety)
        XCTAssertEqual(safety.cause,.birdIntrusion)
        XCTAssertEqual(safety.conflictingBird,engine.id(of:other)?.rawValue)
        let cut=try XCTUnwrap(diagnostic.corridor).intersection(try XCTUnwrap(safety.conflictingFootprint))
        XCTAssertFalse(cut.isNull);XCTAssertFalse(cut.isEmpty)
        XCTAssertEqual(bird.position,actual)
        XCTAssertTrue(bird.needsDestination)
        XCTAssertFalse(bird.isSideHopping)
        engine.updateWorld(engine.world)
        XCTAssertEqual(hop.diagnostic,diagnostic)
    }

    func testAcceptedRunWithRejectedStartIsAnInvariantViolationRatherThanSafetySuccess() throws {
        let engine=fixture(),bird=engine.birds[0]
        let plan=try XCTUnwrap(SideHopPlan.make(id:try XCTUnwrap(engine.id(of:bird)),in:engine))
        bird.state = .landing // Deliberately violate start's precondition after planning.
        let hop=SideHopExecution(plan:plan,source:.preview)
        guard case .started(let run)=engine.runtime.start(hop,source:.preview,in:engine) else {return XCTFail("Expected runtime acceptance")}
        engine.updateWorld(engine.world)
        assertFailed(engine,run)
        XCTAssertEqual(hop.diagnostic?.cause,.startRejected)
        XCTAssertEqual(hop.diagnostic?.classification,.invariantViolation)
        XCTAssertEqual(hop.diagnostic?.stage,"start")
    }

    func testFailureSampleBudgetAndLegacyDecodingKeepOptionalEvidenceBackwardCompatible() throws {
        let engine=fixture()
        let (_,hop)=try start(engine)
        var world=engine.world;world.surfaces=[];engine.updateWorld(world)
        let diagnostic=try XCTUnwrap(hop.diagnostic),auditor=BehaviorStress.Auditor(),plain=BehaviorStress.Auditor()
        for index in 1...40 {
            let id=BehaviorRunID(rawValue:UInt64(index))
            let started=BehaviorEvent(sequence:UInt64(index*2-1),time:Double(index),runID:id,
                kind:.sideHop,source:.automatic,type:.started,participants:[BirdID(7)],reason:nil)
            let failed=BehaviorEvent(sequence:UInt64(index*2),time:Double(index)+0.5,runID:id,
                kind:.sideHop,source:.automatic,type:.failed,participants:[BirdID(7)],reason:.targetInvalid)
            auditor.observe(started);plain.observe(started)
            auditor.observe(failed,sideHop:diagnostic);plain.observe(failed)
        }
        auditor.finish();plain.finish()
        XCTAssertEqual(auditor.metrics,plain.metrics,"Diagnostic payload must not change event hashes or counters")
        XCTAssertEqual(auditor.failures.samples.count,32)
        XCTAssertEqual(auditor.failures.omittedSamples,8)
        XCTAssertEqual(auditor.failures.byBehavior,["sideHop":40])
        XCTAssertTrue(auditor.failures.samples.allSatisfy{$0.sideHop==diagnostic})
        let data=try JSONEncoder().encode(auditor.failures)
        XCTAssertEqual(try JSONDecoder().decode(BehaviorStress.FailureDiagnostics.self,from:data),auditor.failures)
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        var samples=try XCTUnwrap(legacy["samples"] as? [[String:Any]])
        for index in samples.indices {samples[index].removeValue(forKey:"sideHop")}
        legacy["samples"]=samples
        let decoded=try JSONDecoder().decode(BehaviorStress.FailureDiagnostics.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertTrue(decoded.samples.allSatisfy{$0.sideHop==nil})
        XCTAssertEqual(decoded.byBehavior,auditor.failures.byBehavior)
        XCTAssertEqual(decoded.omittedSamples,8)
    }

    func testCurrentSchedulerWorkloadPreservesSideHopTerminalsIntegrityAndCleanup() throws {
        // Keep the production workload's seed, population and duration, while
        // applying current simulation semantics. Historical event identities
        // belong to the archived evidence and frozen geometry test above.
        let report=try BehaviorStress.run(configuration:BehaviorStress.m5nSideHopConfiguration)
        XCTAssertTrue(report.passed,"Integrity: \(report.integrity.violations); cleanup: \(report.cleanup)")
        XCTAssertEqual(report.configuration.seed,73)
        XCTAssertEqual(report.configuration.birds,12);XCTAssertEqual(report.configuration.displays,2)
        XCTAssertTrue(report.configuration.autonomous)
        XCTAssertEqual(report.workload.version,7)
        XCTAssertEqual(report.workload.warmupSteps,160*60)
        XCTAssertEqual(report.workload.activeSteps,575*60)
        XCTAssertGreaterThan(report.metrics.startedByKind["sideHop"] ?? 0,0)
        XCTAssertGreaterThan(report.metrics.completedByKind["sideHop"] ?? 0,0)
        XCTAssertEqual(report.metrics.startedRuns,
            report.metrics.completedRuns+report.metrics.cancelledRuns+report.metrics.failedRuns)
        XCTAssertEqual(report.integrity.checks["runLifecycle"],true)
        XCTAssertEqual(report.integrity.checks["finalRunBalance"],true)
        XCTAssertEqual(report.integrity.checks["noTimeouts"],true)
        XCTAssertEqual(report.metrics.failureReasons["timedOut"] ?? 0,0)
        for sample in report.failures.samples where sample.behavior=="sideHop" {
            let diagnostic=try XCTUnwrap(sample.sideHop)
            XCTAssertEqual(sample.reason,"targetInvalid")
            XCTAssertEqual(sample.participants,[diagnostic.birdID])
            XCTAssertEqual(diagnostic.simulationTime,sample.simulationTime,accuracy:0.000001)
            XCTAssertNotEqual(diagnostic.classification,.invariantViolation)
        }
        XCTAssertTrue(report.cleanup.passed);XCTAssertTrue(report.cleanup.drainReachedIdle)
        XCTAssertEqual(report.cleanup.activeRuns,0)
        XCTAssertEqual(report.cleanup.leases,0)
        XCTAssertEqual(report.cleanup.reservations,0)
        XCTAssertEqual(report.cleanup.ecologyMemories,0)
        XCTAssertEqual(report.cleanup.birds,0);XCTAssertEqual(report.cleanup.pendingBirds,0)
        XCTAssertEqual(report.cleanup.props,0);XCTAssertEqual(report.cleanup.pendingPreviews,0)
        XCTAssertEqual(report.cleanup.habitatObjects,0);XCTAssertEqual(report.cleanup.habitatReservations,0)
        XCTAssertEqual(report.cleanup.visitorLeases,0)
    }
}
