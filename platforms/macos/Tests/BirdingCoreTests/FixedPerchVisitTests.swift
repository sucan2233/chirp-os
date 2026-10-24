import XCTest
@testable import BirdingCore

final class FixedPerchVisitTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:2000,height:1400)
    private let host=Surface(id:181,pid:42,rect:CGRect(x:200,y:1050,width:400,height:150))
    // Deliberately independent of the production definition.
    private let frames:Set<String> = ["stand","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","land0","land1","land2"]

    private func fixture(species:SpeciesID = .treeSparrow,scale:CGFloat=1,
                         points:[CGPoint] = [CGPoint(x:1300,y:700)],origin:Surface?=nil) -> BehaviorEngine {
        var settings=BirdSettings();settings.fixedPerchesEnabled=true
        settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.fixedPerches=points.enumerated().map {index,point in
            FixedPerchAnchor(slot:index+1,displayID:"",displayFrame:display,
                x:Double(point.x/display.width),y:Double(point.y/display.height))
        }
        let e=BehaviorEngine(seed:1818,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let surface=origin ?? host
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[surface],scale:scale,
            pointer:CGPoint(x:20,y:20),availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)})))
        let bird=Bird(position:.zero,fraction:0.5,profile:settings.catalog.profile(species),random:{0.5})
        bird.perch(on:surface,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
        e.installFixtureBirds([bird]);advance(e,seconds:0.6)
        return e
    }
    private func advance(_ e:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    private struct Session {
        let run:BehaviorRunID
        let execution:FixedPerchVisitExecution
        let bird:Bird
        var plan:FixedPerchVisitPlan {execution.plan}
    }
    private func start(_ e:BehaviorEngine,target:BirdID?=nil,slot:Int?=nil,source:BehaviorSource = .preview) throws -> Session {
        let plan=try XCTUnwrap(FixedPerchVisitPlan.candidates(in:e,source:source,target:target).first{slot==nil || $0.perch.slot==slot})
        let bird=try XCTUnwrap(e.bird(plan.id)),before=bird.position,revision=bird.motionRevision
        let execution=FixedPerchVisitExecution(plan:plan,source:source)
        guard case .started(let run)=e.runtime.start(execution,source:source,in:e) else {
            XCTFail("Expected a real fixed-perch journey")
            throw NSError(domain:"FixedPerchVisitTests",code:1)
        }
        XCTAssertEqual(bird.position,before);XCTAssertEqual(bird.motionRevision,revision+1)
        XCTAssertEqual(bird.state,.flying);XCTAssertTrue(bird.isCoordinatedFlying)
        XCTAssertFalse(e.ambientBusy)
        return Session(run:run,execution:execution,bird:bird)
    }
    private func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    private func released(_ e:BehaviorEngine,_ s:Session,_ type:BehaviorEventType,
                          reason:BehaviorReason?=nil,file:StaticString=#filePath,line:UInt=#line) {
        let events=terminals(e,s.run)
        XCTAssertEqual(events.map(\.type),[type],file:file,line:line)
        if let reason {XCTAssertEqual(events.first?.reason,reason,file:file,line:line)}
        XCTAssertNil(e.runtime.runs[s.run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(s.run),file:file,line:line)
        XCTAssertFalse(e.runtime.landingReservations.contains{$0.bird==s.plan.id},file:file,line:line)
        XCTAssertFalse(s.bird.isCoordinatedFlying,file:file,line:line)
    }
    private func reach(_ state:BirdState,in e:BehaviorEngine,session s:Session) throws {
        for _ in 0..<1800 {
            if s.bird.state==state {return}
            guard e.runtime.runs[s.run] != nil else {break}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Journey ended before reaching \(state)")
        throw NSError(domain:"FixedPerchVisitTests",code:2)
    }
    private func addBird(in e:BehaviorEngine,on surface:Surface,fraction:CGFloat=0.5) -> Bird {
        var world=e.world
        if !world.surfaces.contains(where:{$0.id==surface.id}) {world.surfaces.append(surface);e.updateWorld(world)}
        let bird=Bird(position:.zero,fraction:fraction,profile:e.settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:surface,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
        e.register(bird);bird.tick(0.6)
        return bird
    }
    private final class SlotExecution:BehaviorExecution {
        let kind:BehaviorKind = .relocate
        let occupiesEncounter:Bool
        let runsWhilePaused=false,timeout=60.0
        let landingReservations:[LandingReservation]
        var participants:[BirdID] {landingReservations.map(\.bird)}
        init(_ slot:LandingReservation,encounter:Bool=false) {landingReservations=[slot];occupiesEncounter=encounter}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }

    func testDefinitionRequiresActualStandingFlightAndLandingFrames() {
        let definition=BehaviorDefinitions.definition(for:.fixedPerchVisit)
        XCTAssertEqual(definition.requiredCapabilities,[.standing,.flight,.landing])
        XCTAssertEqual(definition.requiredFrames,frames);XCTAssertEqual(definition.priority,30)
        XCTAssertEqual(definition.cooldown,60);XCTAssertFalse(definition.occupiesEncounter)
        XCTAssertFalse(definition.runsWhilePaused)
        XCTAssertEqual(FixedPerchVisitBehavior.supportedSpecies,
            [.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.redWhiskeredBulbul,.magpieRobin,.redBilledLeiothrix,.lightVentedBulbul])
        for missing in frames {
            let e=fixture();var world=e.world;world.availableFrames[.treeSparrow]?.remove(missing);e.updateWorld(world)
            XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty,missing)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
        let e=fixture();var world=e.world;world.availableFrames=[:];e.updateWorld(world)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
    }

    func testEverySupportedSpeciesReallyFliesThenLandsThenRestsWithoutSpawningOrTeleporting() throws {
        for species in FixedPerchVisitBehavior.supportedSpecies.sorted(by:{$0.rawValue<$1.rawValue}) {
            for scale:CGFloat in [0.75,1,2] {
                let e=fixture(species:species,scale:scale),identity=ObjectIdentifier(e.birds[0]),s=try start(e)
                let origin=s.bird.position,startTime=e.time
                var observed=Set<String>(),landedAt:Double?,perchedAt:Double?,moved=false
                for _ in 0..<1800 {
                    let previous=s.bird.position;e.advance(BehaviorEngine.step)
                    let age=e.time-startTime
                    moved = moved || Geometry.distance(origin,s.bird.position)>20
                    XCTAssertLessThanOrEqual(Geometry.distance(previous,s.bird.position),
                        CGFloat(s.plan.route.legs[0].timing.peakSpeed*BehaviorEngine.step)+0.001)
                    XCTAssertTrue(display.contains(Geometry.landingFootprint(at:s.bird.position,scale:s.plan.scale)))
                    XCTAssertLessThan(Geometry.distance(s.bird.position,s.plan.route.position(at:age)),0.001)
                    let render=try XCTUnwrap(e.renderSnapshot().first)
                    XCTAssertTrue(frames.contains(render.frameName),render.frameName)
                    observed.insert(render.frameName)
                    if s.bird.state == .landing,landedAt==nil {landedAt=e.time}
                    if s.bird.state == .perched,perchedAt==nil {perchedAt=e.time}
                    if e.runtime.runs[s.run]==nil {break}
                    XCTAssertEqual(e.leasedBirdCount,1);XCTAssertEqual(e.reservedLandingCount,1)
                    if s.bird.state == .perched {
                        XCTAssertEqual(render.frameName,"stand");XCTAssertEqual(render.hopOffset,0)
                    }
                }
                XCTAssertTrue(moved);XCTAssertTrue(observed.contains{$0.hasPrefix("fly")})
                XCTAssertTrue(observed.contains("land0"));XCTAssertTrue(observed.contains("land1"))
                XCTAssertTrue(observed.contains("land2"));XCTAssertTrue(observed.contains("stand"))
                let landing=try XCTUnwrap(landedAt),perched=try XCTUnwrap(perchedAt)
                XCTAssertGreaterThanOrEqual(perched-landing,0.42)
                XCTAssertGreaterThanOrEqual(e.time-perched,3)
                released(e,s,.completed)
                XCTAssertEqual(e.birds.map(ObjectIdentifier.init),[identity])
                XCTAssertEqual(s.bird.position,s.plan.perch.foot);XCTAssertEqual(s.bird.fraction,0.5)
                XCTAssertEqual(s.bird.state,.perched);XCTAssertFalse(s.bird.needsDestination)
                XCTAssertEqual(s.bird.landedCount,1);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                advance(e,seconds:0.5);XCTAssertEqual(terminals(e,s.run).count,1)
                XCTAssertEqual(s.bird.position,s.plan.perch.foot)
            }
        }
    }

    func testLightVentedBulbulActuallyVisitsFromBothDirectionsAtHalfDefaultAndDoubleScale() throws {
        for scale:CGFloat in [0.5,1,2] {
            for rightward in [false,true] {
                let origin=rightward ? host:Surface(id:181,pid:42,rect:CGRect(x:1600,y:1050,width:300,height:150))
                let destination=CGPoint(x:rightward ? 1300:700,y:700)
                let e=fixture(species:.lightVentedBulbul,scale:scale,points:[destination],origin:origin)
                let bird=e.birds[0],initial=bird.position,identity=ObjectIdentifier(bird)
                let size=scale*bird.profile.relativeScale
                bird.facingRight = !rightward
                var observations:[BehaviorObservation]=[]
                e.observationObserver={observations.append($0)}
                guard case .started(let run)=e.handle(.fixedPerchVisit(.preview)) else {
                    XCTFail("The actual white-headed bulbul must fit at \(scale), rightward=\(rightward)");continue
                }
                let execution=try XCTUnwrap(e.runtime.runs[run]?.execution as? FixedPerchVisitExecution)
                let s=Session(run:run,execution:execution,bird:bird),began=e.time
                XCTAssertEqual(bird.position,initial);XCTAssertEqual(s.plan.scale,size)
                XCTAssertEqual(s.plan.perch.rect.width,128*scale)
                XCTAssertEqual(s.plan.perch.rect.height,24*scale)
                var moved=false,sawLanding=false,sawRest=false
                for _ in 0..<1800 {
                    guard e.runtime.runs[run] != nil else {break}
                    let before=bird.position
                    e.advance(BehaviorEngine.step)
                    let pose=try XCTUnwrap(e.renderSnapshot().first)
                    XCTAssertEqual(pose.scale,size);XCTAssertEqual(pose.position,bird.position)
                    XCTAssertTrue(display.contains(pose.rect))
                    XCTAssertTrue(display.contains(Geometry.landingFootprint(at:bird.position,scale:size)))
                    XCTAssertLessThanOrEqual(Geometry.distance(before,bird.position),
                        CGFloat(s.plan.route.legs[0].timing.peakSpeed*BehaviorEngine.step)+0.001)
                    XCTAssertLessThan(Geometry.distance(bird.position,s.plan.route.position(at:e.time-began)),0.001)
                    if abs(bird.position.x-initial.x)>20 {
                        moved=true;XCTAssertEqual(pose.facingRight,rightward)
                    }
                    sawLanding = sawLanding || bird.state == .landing
                    sawRest = sawRest || bird.state == .perched
                    if bird.state == .perched {
                        XCTAssertEqual(bird.position,destination)
                        XCTAssertEqual(pose.hopOffset,0)
                        XCTAssertEqual(pose.rect.minY+39*size,destination.y,accuracy:1e-8)
                    }
                }
                XCTAssertTrue(moved);XCTAssertTrue(sawLanding);XCTAssertTrue(sawRest)
                released(e,s,.completed)
                XCTAssertEqual(bird.position,destination);XCTAssertEqual(bird.hostID,s.plan.perch.surface.id)
                XCTAssertEqual(bird.landedCount,1);XCTAssertEqual(ObjectIdentifier(e.birds[0]),identity)
                XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
                XCTAssertEqual(observations.count,1)
            }
        }
    }

    func testLightVentedBulbulRejectsInsufficientActualSpriteClearanceWithoutMovingOrLeasing() throws {
        for scale:CGFloat in [0.5,1,2] {
            for rightward in [false,true] {
                let origin=rightward ? host:Surface(id:181,pid:42,rect:CGRect(x:1600,y:1050,width:300,height:150))
                let e=fixture(species:.lightVentedBulbul,scale:scale,
                    points:[CGPoint(x:rightward ? 1300:700,y:700)],origin:origin)
                let bird=e.birds[0],perch=try XCTUnwrap(e.fixedPerchSnapshot().first)
                XCTAssertFalse(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
                let size=e.spriteScale(for:bird),actual=bird.position,revision=bird.motionRevision
                // The feet and center are clear. A thin utility panel clips only
                // the outer half-point of the real, species-scaled footprint.
                let panel=CGRect(x:perch.foot.x+29*size-0.5,y:perch.foot.y-20*size,width:0.25,height:10*size)
                XCTAssertFalse(panel.contains(perch.foot))
                XCTAssertTrue(panel.intersects(Geometry.landingFootprint(at:perch.foot,scale:size)))
                var world=e.world
                world.surfaces.insert(Surface(id:199,pid:49,rect:panel,layer:1),at:0);e.updateWorld(world)
                XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
                XCTAssertEqual(e.handle(.fixedPerchVisit(.preview)),.rejected(.noSpace))
                XCTAssertEqual(bird.position,actual);XCTAssertEqual(bird.motionRevision,revision)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
                XCTAssertFalse(e.events.contains{$0.type == .started})
            }
        }
    }

    func testGroundWindowAndAnotherPerchAreValidOriginsButCurrentPerchIsNotATarget() throws {
        let ground=Geometry.ground(id:182,display:display,workArea:display)
        for origin in [host,ground] {
            let e=fixture(origin:origin),s=try start(e)
            advance(e,seconds:s.plan.duration+5);released(e,s,.completed)
        }
        let e=fixture(points:[CGPoint(x:400,y:700),CGPoint(x:1400,y:700)])
        let bird=e.birds[0],first=try XCTUnwrap(e.fixedPerchSnapshot().first)
        bird.perch(on:first.surface,spriteScale:e.spriteScale(for:bird));bird.tick(0.6)
        let plans=FixedPerchVisitPlan.candidates(in:e,source:.preview)
        XCTAssertFalse(plans.isEmpty);XCTAssertTrue(plans.allSatisfy{$0.perch.slot==2})
        let s=try start(e);advance(e,seconds:s.plan.duration+5);released(e,s,.completed)
        XCTAssertFalse(FixedPerchVisitPlan.candidates(in:e,source:.preview).contains{$0.perch.slot==2})
    }

    func testEligibilityUsesExistingVisibleCalmResidentsAndAutomaticCooldownButPreviewCanBypassIt() throws {
        let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e).isEmpty)
        e.perchPlanner.rhythms[id]?.quietTime=8
        XCTAssertFalse(FixedPerchVisitPlan.candidates(in:e).isEmpty)
        e.perchPlanner.rhythms[id]?.disturbance=0.35
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e).isEmpty)
        e.perchPlanner.rhythms[id]?.disturbance=0
        e.perchPlanner.rhythms[id]?.cooldowns[.fixedPerchVisit]=60
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e).isEmpty)
        XCTAssertFalse(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
        let s=try start(e);advance(e,seconds:s.plan.duration+5);released(e,s,.completed)
        XCTAssertGreaterThan(e.ecology(of:bird)?.cooldowns[.fixedPerchVisit] ?? 0,58)
        bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.tick(0.6)
        XCTAssertFalse(FixedPerchVisitPlan.candidates(in:e,source:.preview,target:id).isEmpty)
        bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.tick(0.49)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview,target:BirdID(99999)).isEmpty)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:fixture(species:.greyHeron),source:.preview).isEmpty)

        let hidden=fixture();hidden.installFixtureBirds([])
        let b=Bird(position:.zero,fraction:0.5,profile:bird.profile,random:{0.5})
        b.perch(on:host);b.tick(1);hidden.register(b,role:.resident,visible:false)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:hidden,source:.preview).isEmpty)
        hidden.show(try XCTUnwrap(hidden.id(of:b)));hidden.installFixtureBirds([])
        let transient=Bird(position:.zero,fraction:0.5,profile:bird.profile,random:{0.5})
        transient.perch(on:host);transient.tick(1);hidden.register(transient,role:.transient)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:hidden,source:.preview).isEmpty)
    }

    func testSingleSlotRejectsBothPhysicalOccupantsAndForeignEndpointReservations() throws {
        for reserved in [false,true] {
            let e=fixture(),perch=try XCTUnwrap(e.fixedPerchSnapshot().first)
            let remote=Surface(id:189,pid:49,rect:CGRect(x:1700,y:1200,width:200,height:100))
            let other=addBird(in:e,on:reserved ? remote:perch.surface,fraction:0)
            var run:BehaviorRunID?
            if reserved {
                other.fly(to:CGPoint(x:1800,y:1200),host:nil,arc:0,allowsOrbit:false,random:{0.5})
                let id=try XCTUnwrap(e.id(of:other))
                if case .started(let id)=e.runtime.start(SlotExecution(LandingReservation(bird:id,host:perch.surface,fraction:0)),source:.preview,in:e) {run=id}
                XCTAssertNotNil(run)
            }
            let before=e.birds.map(\.position)
            XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
            XCTAssertEqual(e.birds.map(\.position),before)
            if let run {e.runtime.cancel(run,reason:.removed,in:e)}
        }
    }

    func testNormallyExpiredPerchStillLaunchesFromItsRealHostForAutomaticAndPreview() throws {
        for source:BehaviorSource in [.automatic,.preview] {
            let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
            bird.perchDuration=0.55
            e.perchPlanner.rhythms[id]?.quietTime=8
            XCTAssertEqual(bird.state,.perched);XCTAssertTrue(bird.needsDestination)
            let origin=bird.position,s=try start(e,source:source)
            XCTAssertEqual(bird.position,origin);XCTAssertFalse(bird.needsDestination)
            // Production profiles have a normal dwell long enough for the
            // three-second rest; this test shortened only the takeoff deadline.
            bird.perchDuration=600
            advance(e,seconds:s.plan.duration+5);released(e,s,.completed)
        }
    }

    func testPreviewCommandUsesTheExistingResidentAndReleasesAllResources() throws {
        let e=fixture(),identity=ObjectIdentifier(e.birds[0]),actual=e.birds[0].position
        guard case .started(let run)=e.handle(.fixedPerchVisit(.preview)) else {return XCTFail("Expected fixed-perch preview")}
        let execution=try XCTUnwrap(e.runtime.runs[run]?.execution as? FixedPerchVisitExecution)
        let s=Session(run:run,execution:execution,bird:try XCTUnwrap(e.bird(execution.plan.id)))
        XCTAssertEqual(s.bird.position,actual);XCTAssertEqual(ObjectIdentifier(s.bird),identity)
        advance(e,seconds:s.plan.duration+5);released(e,s,.completed)
        XCTAssertEqual(e.birds.count,1);XCTAssertEqual(e.arrivalCount,0)
    }

    func testReusedOriginWindowIDCannotStartBeforeTheHostTrackingSample() {
        let e=fixture(),bird=e.birds[0],feet=bird.position
        var world=e.world
        world.surfaces[0]=Surface(id:host.id,pid:host.pid+1,rect:host.rect)
        e.updateWorld(world)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
        XCTAssertEqual(bird.position,feet);XCTAssertEqual(e.activeRunCount,0)
    }

    func testStalePlanNeverOverwritesAnExternalFlightOrMovesItsFeet() throws {
        let e=fixture(),bird=e.birds[0]
        let plan=try XCTUnwrap(FixedPerchVisitPlan.candidates(in:e,source:.preview).first)
        bird.fly(to:CGPoint(x:1800,y:1100),host:nil,arc:0,allowsOrbit:false,random:{0.5})
        let actual=bird.position,revision=bird.motionRevision
        let execution=FixedPerchVisitExecution(plan:plan,source:.preview)
        execution.start(in:e);execution.cancel(.replaced,in:e)
        XCTAssertEqual(bird.position,actual);XCTAssertEqual(bird.motionRevision,revision)
        XCTAssertFalse(bird.isCoordinatedFlying);XCTAssertFalse(bird.needsDestination)
        XCTAssertFalse(plan.canBegin(in:e))
    }

    func testSeparateSlotsCanRunTogetherWithoutClaimingEncounterBudget() throws {
        let e=fixture(points:[CGPoint(x:1300,y:850),CGPoint(x:1300,y:350)])
        let other=addBird(in:e,on:Surface(id:183,pid:43,rect:CGRect(x:200,y:350,width:400,height:100)))
        let first=try start(e,target:e.id(of:e.birds[0]),slot:1)
        let second=try start(e,target:e.id(of:other),slot:2)
        XCTAssertEqual(e.activeRunCount,2);XCTAssertEqual(e.leasedBirdCount,2);XCTAssertEqual(e.reservedLandingCount,2)
        XCTAssertFalse(e.ambientBusy)
        advance(e,seconds:max(first.plan.duration,second.plan.duration)+5)
        released(e,first,.completed);released(e,second,.completed)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
    }

    func testAmbientEncounterPreventsNewVisitEvenThoughVisitDoesNotOccupyBudget() throws {
        let e=fixture(),remote=Surface(id:184,pid:44,rect:CGRect(x:1700,y:1200,width:200,height:100))
        let other=addBird(in:e,on:remote),id=try XCTUnwrap(e.id(of:other))
        guard case .started(let run)=e.runtime.start(SlotExecution(LandingReservation(bird:id,host:remote,fraction:0.5),encounter:true),source:.preview,in:e)
        else {return XCTFail("Expected unrelated encounter lease")}
        XCTAssertTrue(e.ambientBusy);XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
        XCTAssertEqual(e.handle(.fixedPerchVisit(.preview)),.rejected(.busy))
        e.runtime.cancel(run,reason:.removed,in:e)
        XCTAssertFalse(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
    }

    func testCandidateEnumerationIsBoundedToEightBirdsAndThreeSlots() throws {
        let e=fixture(points:[CGPoint(x:1000,y:900),CGPoint(x:1350,y:900),CGPoint(x:1700,y:900)])
        var ids:[BirdID]=[]
        for index in 0..<12 {
            let x:CGFloat=200+CGFloat(index%6)*280,y:CGFloat=index<6 ? 1100:1250
            let b=addBird(in:e,on:Surface(id:UInt32(200+index),pid:50,rect:CGRect(x:x,y:y,width:180,height:60)))
            ids.append(try XCTUnwrap(e.id(of:b)))
        }
        let plans=FixedPerchVisitPlan.candidates(in:e,source:.preview)
        XCTAssertFalse(plans.isEmpty)
        XCTAssertLessThanOrEqual(plans.count,24);XCTAssertLessThanOrEqual(Set(plans.map(\.id)).count,8)
        XCTAssertTrue(plans.allSatisfy{$0.perch.slot<=3})
        let highID=try XCTUnwrap(ids.last)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview,target:highID).allSatisfy{$0.id==highID})
    }

    func testEachMotionPhaseReleasesOnClickMissingFramesAndGlobalSpaceCancellation() throws {
        for state:BirdState in [.flying,.landing,.perched] {
            for cause in ["click","frames","space","removed","disabled"] {
                let e=fixture(),s=try start(e);try reach(state,in:e,session:s)
                let actual=s.bird.position
                switch cause {
                case "click":e.handle(.pointerClick)
                case "frames":var world=e.world;world.availableFrames[.treeSparrow]?.remove("land2");e.updateWorld(world)
                case "space":e.handle(.cancelAmbient(.spaceChanged))
                case "removed":e.handle(.remove(s.plan.id))
                default:var settings=e.settings;settings.fixedPerchesEnabled=false;e.applySettings(settings)
                }
                released(e,s,cause=="frames" ? .failed:.cancelled,
                    reason:cause=="disabled" ? .settingsChanged:nil)
                XCTAssertEqual(s.bird.position,actual)
                if state != .perched {XCTAssertTrue(s.bird.needsDestination)}
                if cause != "removed" {advance(e,seconds:0.5);XCTAssertEqual(s.bird.position,actual)}
                XCTAssertEqual(terminals(e,s.run).count,1)
            }
        }
    }

    func testHostDeletionMovementResizeAndPIDReplacementNeverSnapFeetInAnyPhase() throws {
        for state:BirdState in [.flying,.landing,.perched] {
            for cause in ["delete","move","resize","pid","scale","screens","displays"] {
                let e=fixture(),s=try start(e);try reach(state,in:e,session:s)
                let actual=s.bird.position
                var world=e.world
                let index=try XCTUnwrap(world.surfaces.firstIndex{$0.id==s.plan.perch.surface.id})
                switch cause {
                case "delete":var settings=e.settings;settings.fixedPerches=[];e.applySettings(settings)
                case "move":var settings=e.settings;settings.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"",displayFrame:display,x:0.7,y:0.5)];e.applySettings(settings)
                case "resize":world.scale*=1.01
                case "pid":let old=world.surfaces[index];world.surfaces[index]=Surface(id:old.id,pid:99,rect:old.rect)
                case "scale":world.scale*=1.1
                case "screens":world.screens[0].size.height-=1
                default:world.displays[0].origin.x+=1
                }
                e.updateWorld(["delete","move"].contains(cause) ? e.world:world,sampleDT:0.1)
                released(e,s,.failed)
                XCTAssertEqual(s.bird.position,actual)
                if ["delete","move","resize","pid","scale"].contains(cause) {XCTAssertTrue(s.bird.needsDestination)}
                advance(e,seconds:0.2);XCTAssertEqual(s.bird.position,actual)
            }
        }
    }

    func testChangingPersistedAnchorCancelsBeforeMovingAnAlreadySettledBird() throws {
        for state:BirdState in [.flying,.landing,.perched] {
            let e=fixture(),s=try start(e);try reach(state,in:e,session:s)
            let actual=s.bird.position
            var settings=e.settings
            settings.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"",displayFrame:display,x:0.7,y:0.5)]
            e.applySettings(settings);e.updateWorld(e.world,sampleDT:0.1)
            released(e,s,.failed);XCTAssertEqual(s.bird.position,actual);XCTAssertTrue(s.bird.needsDestination)
        }
    }

    func testFuturePointerAndThinUtilityPanelBlockTheWholeRouteButOrdinaryWindowsDoNot() throws {
        for obstruction in ["pointer","panel","window"] {
            let e=fixture(),s=try start(e),p=s.plan.route.position(at:s.plan.duration*0.65)
            let actual=s.bird.position
            var world=e.world
            if obstruction=="pointer" {world.pointer=p}
            else {world.surfaces.insert(Surface(id:185,pid:45,
                rect:CGRect(x:p.x,y:p.y-2,width:0.01,height:4),layer:obstruction=="panel" ? 1:0),at:0)}
            e.updateWorld(world)
            XCTAssertEqual(s.bird.position,actual)
            if obstruction=="window" {
                XCTAssertTrue(terminals(e,s.run).isEmpty)
                advance(e,seconds:s.plan.duration+5);released(e,s,.completed)
            } else {released(e,s,obstruction=="pointer" ? .cancelled:.failed)}
        }
    }

    func testBlockedCenterIsRejectedBeforeLaunchWithoutDisplacingItsOccupant() throws {
        for obstruction in ["panel","pointer","bird"] {
            let e=fixture(),perch=try XCTUnwrap(e.fixedPerchSnapshot().first)
            var world=e.world
            switch obstruction {
            case "panel":world.surfaces.insert(Surface(id:186,pid:46,
                rect:Geometry.landingFootprint(at:perch.foot,scale:1),layer:1),at:0);e.updateWorld(world)
            case "pointer":world.pointer=perch.foot;e.updateWorld(world)
            default:_=addBird(in:e,on:perch.surface)
            }
            let positions=e.birds.map(\.position)
            XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
            XCTAssertEqual(e.birds.map(\.position),positions);XCTAssertEqual(e.leasedBirdCount,0)
        }
    }

    func testPeerFullFlightAndForeignReservationProtectFutureCorridor() throws {
        for reserved in [false,true] {
            let e=fixture(),s=try start(e),p=s.plan.route.position(at:s.plan.duration*0.6)
            let remote=Surface(id:187,pid:47,rect:CGRect(x:1700,y:1200,width:200,height:100))
            let other=addBird(in:e,on:remote),id=try XCTUnwrap(e.id(of:other))
            let corridor=Surface(id:188,pid:48,rect:CGRect(x:p.x-90,y:p.y,width:180,height:100))
            var world=e.world;world.surfaces.append(corridor);e.updateWorld(world)
            XCTAssertTrue(terminals(e,s.run).isEmpty)
            var foreign:BehaviorRunID?
            if reserved {
                if case .started(let run)=e.runtime.start(SlotExecution(LandingReservation(bird:id,host:corridor,fraction:0.5)),source:.preview,in:e) {foreign=run}
                XCTAssertNotNil(foreign)
            } else {
                other.fly(to:Geometry.foot(on:corridor,fraction:0.5,edge:.top),host:corridor,arc:0,allowsOrbit:false,random:{0.5})
            }
            let actual=e.birds.map(\.position);e.updateWorld(e.world)
            released(e,s,.failed);XCTAssertEqual(e.birds.map(\.position),actual)
            if let foreign {e.runtime.cancel(foreign,reason:.removed,in:e)}
            XCTAssertEqual(e.reservedLandingCount,0)
        }
    }

    func testIntrudingOccupantReleasesVisitorWithoutEvictingTheOtherBirdInEveryPhase() throws {
        for state:BirdState in [.flying,.landing,.perched] {
            let e=fixture(),s=try start(e);try reach(state,in:e,session:s)
            let actual=s.bird.position
            let peer=addBird(in:e,on:s.plan.perch.surface,fraction:0)
            let peerFoot=peer.position,revision=peer.motionRevision
            e.updateWorld(e.world)
            released(e,s,.failed)
            XCTAssertEqual(s.bird.position,actual);XCTAssertTrue(s.bird.needsDestination)
            XCTAssertEqual(peer.position,peerFoot);XCTAssertEqual(peer.motionRevision,revision)
            XCTAssertEqual(peer.state,.perched);XCTAssertEqual(peer.hostID,s.plan.perch.surface.id)
        }
    }

    func testExternalReplacementSurvivesCleanupAtEveryPhase() throws {
        for state:BirdState in [.flying,.landing,.perched] {
            let e=fixture(),s=try start(e);try reach(state,in:e,session:s)
            let actual=s.bird.position
            s.bird.fly(to:CGPoint(x:1700,y:1150),host:nil,arc:0,allowsOrbit:false,random:{0.5})
            let revision=s.bird.motionRevision;e.updateWorld(e.world)
            released(e,s,.failed);XCTAssertEqual(s.bird.position,actual)
            XCTAssertEqual(s.bird.motionRevision,revision);XCTAssertFalse(s.bird.needsDestination)
            advance(e,seconds:0.2);XCTAssertNotEqual(s.bird.position,actual)
            XCTAssertEqual(s.bird.motionRevision,revision)
        }
    }

    func testCrossingPeerRouteIsProtectedEvenWhenBothPeerEndpointsAreClear() throws {
        let e=fixture(),s=try start(e),p=s.plan.route.position(at:s.plan.duration*0.6)
        let origin=Surface(id:190,pid:50,rect:CGRect(x:p.x-400,y:p.y-350,width:200,height:80))
        let destination=Surface(id:191,pid:51,rect:CGRect(x:p.x+200,y:p.y+350,width:200,height:80))
        let peer=addBird(in:e,on:origin)
        var world=e.world;world.surfaces.append(destination);e.updateWorld(world)
        XCTAssertTrue(terminals(e,s.run).isEmpty)
        let foot=Geometry.foot(on:destination,fraction:0.5,edge:.top,scale:e.spriteScale(for:peer))
        peer.fly(to:foot,host:destination,arc:0,allowsOrbit:false,random:{0.5})
        let positions=e.birds.map(\.position);e.updateWorld(e.world)
        released(e,s,.failed);XCTAssertEqual(e.birds.map(\.position),positions)
        XCTAssertFalse(peer.needsDestination);XCTAssertEqual(peer.state,.flying)
    }

    func testTimeoutDetachesLeaseAndReservationAtActualFeetExactlyOnce() throws {
        let e=fixture(),s=try start(e),actual=s.bird.position
        e.runtime.advance(s.execution.timeout+1,in:e)
        released(e,s,.failed,reason:.timedOut)
        XCTAssertEqual(s.bird.position,actual);XCTAssertTrue(s.bird.needsDestination)
        e.runtime.cancel(s.run,reason:.removed,in:e)
        XCTAssertEqual(terminals(e,s.run).count,1)
    }

    func testQuietModeClosesAutomaticOpportunityWhileActiveVisitFinishes() throws {
        let e=fixture(),s=try start(e)
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings)
        XCTAssertTrue(terminals(e,s.run).isEmpty)
        advance(e,seconds:s.plan.duration+5);released(e,s,.completed)
        s.bird.perch(on:host,spriteScale:e.spriteScale(for:s.bird));s.bird.tick(0.6)
        e.perchPlanner.rhythms[s.plan.id]?.quietTime=10
        e.perchPlanner.rhythms[s.plan.id]?.cooldowns.removeValue(forKey:.fixedPerchVisit)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e).isEmpty)
        XCTAssertFalse(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
    }

    func testPausedMotionIsFrozenButSafetyValidationStillReleasesResources() throws {
        for state:BirdState in [.flying,.landing,.perched] {
            let e=fixture(),s=try start(e);try reach(state,in:e,session:s)
            let actual=s.bird.position,clock=s.bird.coordinatedFlightAge
            e.handle(.pause(true));advance(e,seconds:2)
            XCTAssertEqual(s.bird.position,actual);XCTAssertEqual(s.bird.coordinatedFlightAge,clock)
            XCTAssertTrue(terminals(e,s.run).isEmpty)
            var world=e.world;world.buttonsDown=true;e.updateWorld(world)
            released(e,s,.cancelled,reason:.userInput);XCTAssertEqual(s.bird.position,actual)
        }
    }

    func testThirtySixtyAndOneHundredFortyFourHzFollowIdenticalFixedStepMotion() throws {
        var journeys:[[CGPoint]]=[],completions:[Double]=[]
        for hz in [30,60,144] {
            let e=fixture(),s=try start(e),started=e.time
            var samples:[CGPoint]=[]
            for _ in 0..<24 {advance(e,seconds:0.5,hz:hz);samples.append(s.bird.position)}
            released(e,s,.completed)
            journeys.append(samples)
            completions.append(try XCTUnwrap(terminals(e,s.run).first?.time)-started)
        }
        XCTAssertEqual(journeys[0],journeys[1]);XCTAssertEqual(journeys[1],journeys[2])
        XCTAssertEqual(completions[0],completions[1],accuracy:0.000001)
        XCTAssertEqual(completions[1],completions[2],accuracy:0.000001)
    }

    func testDifferentDisplaysCannotBeJoinedByAVirtualBridge() {
        let e=fixture();var world=e.world
        world.displays=[CGRect(x:0,y:0,width:900,height:1400),CGRect(x:1000,y:0,width:1000,height:1400)]
        world.screens=world.displays;e.updateWorld(world)
        XCTAssertTrue(FixedPerchVisitPlan.candidates(in:e,source:.preview).isEmpty)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.arrivalCount,0)
    }
}
