import XCTest
@testable import BirdingCore

final class TravelTogetherTests:XCTestCase {
    // Deliberately independent of the production capability declaration.
    private let frames:Set<String> = ["stand","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","land0","land1","land2"]
    private let species:[SpeciesID] = [.treeSparrow,.barnSwallow,.spottedDove,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling]

    private func fixture(species:[SpeciesID] = [.treeSparrow,.treeSparrow],scale:CGFloat=1,
                         compact:Bool=false,origins:[CGPoint]?=nil,elapsed:Double?=nil,
                         reverseSecond:Bool=false) -> BehaviorEngine {
        var settings=BirdSettings();settings.socialInteractions=true;settings.travelTogetherEnabled=true
        settings.perchActions=false;settings.passiveAttentionEnabled=false
        let e=BehaviorEngine(seed:813,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let display=CGRect(x:0,y:0,width:compact ? 1440:1920,height:1100)
        let hosts=[CGFloat(400),640].enumerated().map {index,y in
            Surface(id:UInt32(813+index),pid:42,rect:CGRect(x:reverseSecond && index==1 ? 140:(compact ? 1190:1640),
                y:y,width:compact ? 220:240,height:160))
        }
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:hosts,scale:scale,
            pointer:CGPoint(x:30,y:30),availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)})))
        let starts=origins ?? [CGPoint(x:compact ? 60:100,y:400),CGPoint(x:compact ? 80:120,y:640)]
        e.installFixtureBirds(species.enumerated().map {index,species in
            let bird=Bird(position:starts[index],fraction:0.5,profile:settings.catalog.profile(species),random:{0.5})
            let host=hosts[index]
            let target=Geometry.foot(on:host,fraction:0.5,edge:.top,scale:e.spriteScale(for:bird))
            bird.fly(to:target,host:host,arc:0,allowsOrbit:false,random:{0.5});bird.perchDuration=600
            return bird
        })
        advance(e,seconds:elapsed ?? (compact ? 0.70:0.75))
        return e
    }
    private func advance(_ e:BehaviorEngine,seconds:Double) {
        for _ in 0..<max(0,Int(ceil(seconds/BehaviorEngine.step-1e-9))) {e.advance(BehaviorEngine.step)}
    }
    private struct Session {
        let run:BehaviorRunID,plan:TravelTogetherPlan,birds:[Bird]
    }
    private func start(_ e:BehaviorEngine,source:BehaviorSource = .preview) throws -> Session {
        let origins=e.birds.map(\.position),identities=e.birds.map(ObjectIdentifier.init)
        let velocities=try e.birds.map{try XCTUnwrap($0.airborneFlight).velocity}
        XCTAssertTrue(e.birds.allSatisfy{$0.state == .flying && !$0.isCoordinatedFlying && $0.landedCount==0})
        guard case .started(let run)=e.handle(.travelTogether(source)) else {
            XCTFail("Two established, parallel ordinary flights must have a bounded encounter")
            throw NSError(domain:"TravelTogetherTests",code:1)
        }
        let execution=try XCTUnwrap(e.runtime.runs[run]?.execution as? TravelTogetherExecution)
        let birds=try execution.participants.map{try XCTUnwrap(e.bird($0))}
        XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
        XCTAssertEqual(e.birds.map(\.position),origins,"Installing an airborne encounter cannot move either foot")
        XCTAssertEqual(execution.participants.count,2);XCTAssertEqual(Set(execution.participants).count,2)
        XCTAssertEqual(e.leasedBirdCount,2);XCTAssertEqual(e.reservedLandingCount,2);XCTAssertTrue(e.ambientBusy)
        for index in birds.indices {
            XCTAssertTrue(birds[index].isCoordinatedFlying);XCTAssertEqual(birds[index].state,.flying)
            XCTAssertEqual(birds[index].coordinatedFlightAge,0)
            XCTAssertEqual(execution.plan.routes[index].speed(at:0),Double(Geometry.distance(.zero,velocities[index])),accuracy:0.1)
            XCTAssertEqual(birds[index].flightSpeed,Double(Geometry.distance(.zero,velocities[index])),accuracy:0.1)
        }
        return Session(run:run,plan:execution.plan,birds:birds)
    }
    private func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    private func released(_ e:BehaviorEngine,_ s:Session,type:BehaviorEventType,
                          file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(terminals(e,s.run).map(\.type),[type],file:file,line:line)
        XCTAssertEqual(e.activeRunCount,0,file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertFalse(e.ambientBusy,file:file,line:line)
        XCTAssertFalse(s.birds.contains(where:{$0.isCoordinatedFlying}),file:file,line:line)
    }
    private func dot(_ a:CGPoint,_ b:CGPoint) -> Double {
        Double(a.x*b.x+a.y*b.y)/max(0.000001,Double(Geometry.distance(.zero,a)*Geometry.distance(.zero,b)))
    }
    private func delta(_ a:CGPoint,_ b:CGPoint) -> CGPoint {CGPoint(x:a.x-b.x,y:a.y-b.y)}

    func testRealIndependentFlightsConvergeStayInFormationThenResumeBothOriginalLandings() throws {
        let e=fixture(),original=try e.birds.map{try XCTUnwrap($0.airborneFlight)}
        XCTAssertTrue(e.birds.allSatisfy{$0.stateTime>=0.7 && !$0.isCoordinatedFlying})
        let s=try start(e),entry=s.plan.commonEntries.max()!,end=entry+s.plan.commonDuration
        XCTAssertEqual(s.plan.commonOverlap,2.2,accuracy:0.000001)
        XCTAssertEqual(s.plan.commonEntries[0],s.plan.commonEntries[1],accuracy:0.000001)
        XCTAssertEqual(s.plan.routes.count,2)
        let formation=delta(s.plan.formationOffsets[1],s.plan.formationOffsets[0])
        XCTAssertLessThan(Geometry.distance(.zero,formation),Geometry.distance(original[0].position,original[1].position))
        var pairedTicks=0,exitSeen=false
        for _ in 0..<Int(ceil((s.plan.duration+1)*60)) {
            e.advance(BehaviorEngine.step)
            guard terminals(e,s.run).isEmpty else {break}
            let age=try XCTUnwrap(s.birds[0].coordinatedFlightAge)
            for index in 0..<2 {
                let bird=s.birds[index],clock=try XCTUnwrap(bird.coordinatedFlightAge)
                XCTAssertLessThan(Geometry.distance(bird.position,s.plan.routes[index].position(at:clock)),0.01)
                if clock<s.plan.routes[index].duration {XCTAssertEqual(bird.state,.flying)}
            }
            if age>=entry+0.02,age<=end-0.02 {
                pairedTicks+=1
                XCTAssertLessThan(Geometry.distance(delta(s.birds[1].position,s.birds[0].position),formation),0.01)
                XCTAssertGreaterThan(s.birds[0].flightSpeed,0);XCTAssertGreaterThan(s.birds[1].flightSpeed,0)
                XCTAssertEqual(s.birds[0].flightSpeed,s.birds[1].flightSpeed,accuracy:0.01)
            }
            if age>end+0.3,age<min(s.plan.routes[0].duration,s.plan.routes[1].duration) {
                exitSeen=true
                XCTAssertGreaterThan(Geometry.distance(s.birds[0].position,s.birds[1].position),Geometry.distance(.zero,formation))
            }
        }
        XCTAssertGreaterThan(pairedTicks,120);XCTAssertTrue(exitSeen)
        released(e,s,type:.completed)
        for index in 0..<2 {
            XCTAssertEqual(s.birds[index].position,original[index].destination)
            XCTAssertEqual(s.birds[index].state,.perched);XCTAssertEqual(s.birds[index].landedCount,1)
            XCTAssertEqual(s.birds[index].hostID,s.plan.hosts[index].id)
        }
        XCTAssertNotEqual(s.birds[0].position,s.birds[1].position)
        XCTAssertEqual(e.residentCount,2);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
        advance(e,seconds:1);XCTAssertEqual(terminals(e,s.run).count,1)
    }

    func testAllSixSpeciesKeepInitialVelocityAndTangentSpeedContinuityAtEveryJoin() throws {
        XCTAssertEqual(TravelTogetherBehavior.supportedSpecies,Set(species))
        for species in species {
            let e=fixture(species:[species,species]),s=try start(e)
            XCTAssertEqual(s.plan.scales,e.birds.map{e.spriteScale(for:$0)})
            for index in 0..<2 {
                let route=s.plan.routes[index],initial=s.plan.initialFlights[index]
                XCTAssertEqual(route.legs.count,3)
                XCTAssertGreaterThan(dot(delta(route.position(at:0.001),route.position(at:0)),initial.velocity),0.99)
                let step=delta(route.position(at:0.001),route.position(at:0)),distance=Geometry.distance(.zero,step)
                let incoming=CGPoint(x:step.x/distance*route.speed(at:0),y:step.y/distance*route.speed(at:0))
                XCTAssertLessThanOrEqual(Geometry.distance(incoming,initial.velocity),max(2,route.speed(at:0)*0.01))
                XCTAssertEqual(route.position(at:0),initial.position)
                XCTAssertEqual(route.position(at:route.duration),initial.destination)
                XCTAssertEqual(route.speed(at:route.duration),0,accuracy:0.000001)
                let approach=route.legs[0]
                XCTAssertEqual(approach.timing.acceleration,1)
                for sample in 0...100 {
                    XCTAssertGreaterThan(approach.timing.speed(at:approach.timing.duration*Double(sample)/100),0)
                }
                for join in 1..<route.legs.count {
                    let a=route.legs[join-1],b=route.legs[join]
                    XCTAssertLessThan(Geometry.distance(a.path.point(1),b.path.point(0)),0.000001)
                    XCTAssertEqual(a.timing.speed(at:a.timing.duration),b.timing.speed(at:0),accuracy:0.001)
                    XCTAssertGreaterThan(dot(delta(a.path.point(1),a.path.point(0.9999)),delta(b.path.point(0.0001),b.path.point(0))),0.99)
                }
            }
            advance(e,seconds:s.plan.duration+1)
            released(e,s,type:.completed)
        }
    }

    func test1440WideDesktopAtDefaultAndSmallerScaleHasRoomWithoutSpeedDiscontinuity() throws {
        for scale:CGFloat in [1,0.8] {
            let e=fixture(scale:scale,compact:true),s=try start(e)
            XCTAssertEqual(s.plan.display.width,1440)
            XCTAssertGreaterThanOrEqual(s.plan.commonOverlap,1.8)
            for (index,route) in s.plan.routes.enumerated() {
                XCTAssertLessThanOrEqual(route.legs[1].timing.peakSpeed,221*Double(s.plan.scales[index]))
                XCTAssertEqual(route.speed(at:0),Double(Geometry.distance(.zero,s.plan.initialFlights[index].velocity)),accuracy:0.1)
            }
            advance(e,seconds:s.plan.duration+1);released(e,s,type:.completed)
        }
    }

    func testPlanningIsBoundedPureAndPreviewDoesNotBypassGeometryOrFrameRequirements() {
        let e=fixture(),positions=e.birds.map(\.position),revisions=e.birds.map(\.motionRevision)
        let a=TravelTogetherPlan.candidates(in:e,source:.preview)
        let b=TravelTogetherPlan.candidates(in:e,source:.preview)
        XCTAssertFalse(a.isEmpty);XCTAssertLessThanOrEqual(a.count,4)
        XCTAssertEqual(a.map(\.duration),b.map(\.duration))
        XCTAssertEqual(e.birds.map(\.position),positions);XCTAssertEqual(e.birds.map(\.motionRevision),revisions)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        for mutation in ["frames","pointer","panel","smallDisplay","targetConflict"] {
            let e=fixture();var world=e.world
            switch mutation {
            case "frames":world.availableFrames[.treeSparrow]?.remove("land2")
            case "pointer":world.pointer=e.birds[0].position
            case "panel":world.surfaces.insert(Surface(id:900,rect:world.displays[0],layer:1),at:0)
            case "smallDisplay":world.displays=[CGRect(x:0,y:0,width:650,height:1100)]
            default:
                let host=world.surfaces[0],bird=e.birds[1]
                bird.fly(to:Geometry.foot(on:host,fraction:0.5,edge:.top,scale:e.spriteScale(for:bird)),
                    host:host,arc:0,allowsOrbit:false,random:{0.5})
                advance(e,seconds:0.75)
            }
            e.updateWorld(world)
            let before=e.birds.map(\.position)
            XCTAssertTrue(TravelTogetherPlan.candidates(in:e,source:.preview).isEmpty,mutation)
            XCTAssertEqual(e.birds.map(\.position),before)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
    }

    private final class SlotExecution:BehaviorExecution {
        let kind:BehaviorKind = .relocate
        let occupiesEncounter=false,runsWhilePaused=false,timeout=30.0
        let landingReservations:[LandingReservation]
        var participants:[BirdID] {landingReservations.map(\.bird)}
        init(_ slot:LandingReservation) {landingReservations=[slot]}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }

    func testDistanceOppositeDirectionStationaryDifferentSpeciesAndOwnedBirdsAreRejected() throws {
        let mismatch=fixture(species:[.treeSparrow,.barnSwallow])
        XCTAssertTrue(TravelTogetherPlan.candidates(in:mismatch,source:.preview).isEmpty)
        let unsupported=fixture(species:[.swinhoesWhiteEye,.swinhoesWhiteEye])
        XCTAssertTrue(TravelTogetherPlan.candidates(in:unsupported,source:.preview).isEmpty)
        let reverse=fixture(origins:[CGPoint(x:100,y:400),CGPoint(x:1890,y:640)],reverseSecond:true)
        let reverseFlights=try reverse.birds.map{try XCTUnwrap($0.airborneFlight)}
        XCTAssertLessThan(dot(reverseFlights[0].velocity,reverseFlights[1].velocity),0)
        XCTAssertTrue(TravelTogetherPlan.candidates(in:reverse,source:.preview).isEmpty)
        let distant=fixture(origins:[CGPoint(x:100,y:80),CGPoint(x:120,y:1020)])
        XCTAssertTrue(TravelTogetherPlan.candidates(in:distant,source:.preview).isEmpty)
        let stopped=fixture()
        for (index,bird) in stopped.birds.enumerated() {bird.perch(on:stopped.world.surfaces[index],spriteScale:stopped.spriteScale(for:bird))}
        XCTAssertTrue(TravelTogetherPlan.candidates(in:stopped,source:.preview).isEmpty)
        let justStarted=fixture(elapsed:0)
        XCTAssertTrue(TravelTogetherPlan.candidates(in:justStarted,source:.preview).isEmpty)
        let busy=fixture(),bird=busy.birds[0],id=try XCTUnwrap(busy.id(of:bird))
        let slot=LandingReservation(bird:id,host:busy.world.surfaces[0],fraction:bird.fraction)
        guard case .started(let run)=busy.runtime.start(SlotExecution(slot),source:.preview,in:busy)
        else {return XCTFail("A foreign execution should own the ordinary flight")}
        XCTAssertTrue(TravelTogetherPlan.candidates(in:busy,source:.preview).isEmpty)
        busy.runtime.cancel(run,reason:.removed,in:busy)
        XCTAssertEqual(busy.leasedBirdCount,0);XCTAssertEqual(busy.reservedLandingCount,0)
    }

    func testStalePlanPreflightsBothBirdsBeforeInstallingEitherRoute() throws {
        for replace in [false,true] {
            let e=fixture(),plan=try XCTUnwrap(TravelTogetherPlan.candidates(in:e,source:.preview).first)
            XCTAssertTrue(plan.canBegin(in:e))
            if replace {
                let bird=e.birds[1],host=e.world.surfaces[1]
                bird.fly(to:Geometry.foot(on:host,fraction:0.5,edge:.top,scale:e.spriteScale(for:bird)),
                    host:host,arc:0,allowsOrbit:false,random:{0.5})
            } else {advance(e,seconds:BehaviorEngine.step)}
            XCTAssertFalse(plan.canBegin(in:e))
            let before=e.birds.map(\.position),revisions=e.birds.map(\.motionRevision)
            guard case .started(let run)=e.runtime.start(TravelTogetherExecution(plan:plan,source:.preview),source:.preview,in:e)
            else {return XCTFail("Reservations remain valid; stale handoffs fail during preflight")}
            XCTAssertFalse(e.birds.contains(where:{$0.isCoordinatedFlying}))
            XCTAssertEqual(e.birds.map(\.motionRevision),revisions)
            e.updateWorld(e.world)
            XCTAssertEqual(terminals(e,run).map(\.type),[.failed])
            XCTAssertEqual(e.birds.map(\.position),before);XCTAssertEqual(e.birds.map(\.motionRevision),revisions)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
    }

    func testAutomaticUsesCooldownWithoutPerchedQuietTimeAndQuietModeLetsStartedFlightsFinish() throws {
        let e=fixture()
        XCTAssertTrue(e.birds.allSatisfy{(e.ecology(of:$0)?.quietTime ?? 0)<4})
        XCTAssertFalse(TravelTogetherPlan.candidates(in:e,source:.automatic).isEmpty)
        let ids=try e.birds.map{try XCTUnwrap(e.id(of:$0))}
        for id in ids {e.perchPlanner.didStart(id,kind:.travelTogether);e.perchPlanner.didFinish(id,kind:.travelTogether)}
        XCTAssertTrue(TravelTogetherPlan.candidates(in:e,source:.automatic).isEmpty)
        XCTAssertFalse(TravelTogetherPlan.candidates(in:e,source:.preview).isEmpty)
        let s=try start(e)
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings);e.updateWorld(e.world)
        XCTAssertTrue(terminals(e,s.run).isEmpty)
        advance(e,seconds:s.plan.duration+1);released(e,s,type:.completed)
        let quiet=fixture();settings=quiet.settings;settings.activityRhythm = .quiet;quiet.applySettings(settings)
        XCTAssertTrue(TravelTogetherPlan.candidates(in:quiet,source:.automatic).isEmpty)
        XCTAssertFalse(TravelTogetherPlan.candidates(in:quiet,source:.preview).isEmpty)
    }

    func testClickNearEitherBirdDuringApproachFormationExitAndFirstLandingReleasesBothWithoutTeleport() throws {
        for clicked in 0..<2 {
            for phase in 0..<5 {
                let e=fixture(),s=try start(e),entry=s.plan.commonEntries.max()!
                let times=[0,0.3,entry+0.5,entry+s.plan.commonDuration+0.1,
                    (s.plan.routes.map(\.duration).min() ?? 0)+0.1]
                advance(e,seconds:times[phase])
                XCTAssertTrue(terminals(e,s.run).isEmpty)
                let before=s.birds.map(\.position)
                // Both a physical button snapshot and the explicit click may
                // reach the runtime; they must produce only one terminal event.
                var world=e.world;world.pointer=s.birds[clicked].position;world.buttonsDown=true
                e.updateWorld(world)
                e.handle(.pointerClick)
                released(e,s,type:.cancelled)
                XCTAssertEqual(terminals(e,s.run).first?.reason,.userInput)
                XCTAssertEqual(s.birds.map(\.position),before)
                advance(e,seconds:0.2);XCTAssertEqual(s.birds.map(\.position),before)
                XCTAssertEqual(terminals(e,s.run).count,1)
            }
        }
    }

    func testPauseFreezesAgesAndResumeFinishesUsingTheSameTickClock() throws {
        let e=fixture(),s=try start(e)
        advance(e,seconds:s.plan.commonEntries.max()!+0.4);e.handle(.pause(true))
        let feet=s.birds.map(\.position),ages=s.birds.map(\.coordinatedFlightAge),runAge=e.runtime.runs[s.run]?.age
        e.updateWorld(e.world,sampleDT:0.1);advance(e,seconds:0.8)
        XCTAssertEqual(s.birds.map(\.position),feet);XCTAssertEqual(s.birds.map(\.coordinatedFlightAge),ages)
        XCTAssertEqual(e.runtime.runs[s.run]?.age,runAge);XCTAssertTrue(terminals(e,s.run).isEmpty)
        e.handle(.pause(false));advance(e,seconds:s.plan.duration+1);released(e,s,type:.completed)
    }

    func testPausedHostMovementRemovalReuseScreenScaleFramesAndSettingsInvalidation() throws {
        for mutation in ["hostMove","hostResize","hostRemove","pid","screens","displays","scale","frames","settings"] {
            for sampleDT in [0.1,1.0] {
                let e=fixture(),s=try start(e)
                advance(e,seconds:0.3);e.handle(.pause(true));let before=s.birds.map(\.position)
                var world=e.world
                switch mutation {
                case "hostMove":world.surfaces[0].rect.origin.x+=1
                case "hostResize":world.surfaces[0].rect.size.width+=1
                case "hostRemove":world.surfaces.removeFirst()
                case "pid":let host=world.surfaces[0];world.surfaces[0]=Surface(id:host.id,pid:99,rect:host.rect)
                case "screens":world.screens[0].size.width-=1
                case "displays":world.displays[0].size.height-=1
                case "scale":world.scale*=1.1
                case "frames":world.availableFrames[.treeSparrow]?.remove("fly7")
                default:var settings=e.settings;settings.travelTogetherEnabled=false;e.applySettings(settings)
                }
                e.updateWorld(world,sampleDT:sampleDT)
                released(e,s,type:mutation == "settings" ? .cancelled:.failed)
                XCTAssertEqual(s.birds.map(\.position),before)
                XCTAssertTrue(s.birds.allSatisfy(\.needsDestination))
                advance(e,seconds:1);XCTAssertEqual(s.birds.map(\.position),before)
            }
        }
    }

    func testFuturePointerAndThinPanelCancelWhileOrdinaryWindowMayPassBelow() throws {
        for obstruction in ["pointer","panel","normal"] {
            let e=fixture(),s=try start(e),point=s.plan.routes[0].legs[1].path.point(0.4)
            let before=s.birds.map(\.position);var world=e.world
            if obstruction == "pointer" {world.pointer=point}
            else {world.surfaces.insert(Surface(id:900,rect:CGRect(x:point.x,y:point.y-3,width:0.01,height:6),layer:obstruction == "panel" ? 1:0),at:0)}
            e.updateWorld(world)
            XCTAssertEqual(s.birds.map(\.position),before)
            if obstruction == "normal" {
                XCTAssertTrue(terminals(e,s.run).isEmpty)
                advance(e,seconds:s.plan.duration+1);released(e,s,type:.completed)
            } else {released(e,s,type:obstruction == "pointer" ? .cancelled:.failed)}
        }
    }

    func testThirdBirdPlannedFlightAndHostCorrectionInvalidateCorridorBeforeNextTick() throws {
        for changeHost in [false,true] {
            let e=fixture(),s=try start(e),crossing=s.plan.routes[0].legs[1].path.point(0.5)
            let host=Surface(id:900,pid:43,rect:CGRect(x:1640,y:990,width:200,height:80))
            let peer=Bird(position:CGPoint(x:1800,y:990),fraction:0.5,profile:e.birds[0].profile,random:{0.5})
            e.register(peer)
            let target=Geometry.foot(on:host,fraction:0.5,edge:.top,scale:e.spriteScale(for:peer))
            peer.fly(to:target,host:host,arc:0,allowsOrbit:false,random:{0.5})
            var world=e.world;world.surfaces.append(host);e.updateWorld(world)
            XCTAssertTrue(terminals(e,s.run).isEmpty)
            let before=e.birds.map(\.position)
            if changeHost {
                world.surfaces[2].rect.origin.x+=crossing.x-target.x
                world.surfaces[2].rect.origin.y+=crossing.y-target.y
            } else {
                // The peer is still far away; only its future path crosses.
                peer.fly(to:crossing,host:nil,arc:0,allowsOrbit:false,random:{0.5})
            }
            e.updateWorld(world,sampleDT:0.1)
            released(e,s,type:.failed)
            XCTAssertEqual(e.birds.map(\.position),before)
            XCTAssertEqual(peer.state,.flying);XCTAssertFalse(peer.needsDestination)
        }
    }

    func testForeignReservationForEitherOriginalDestinationPreventsPlanning() throws {
        for occupied in 0..<2 {
            let e=fixture(),host=e.world.surfaces[occupied]
            let peer=Bird(position:CGPoint(x:1800,y:990),fraction:0.5,profile:e.birds[0].profile,random:{0.5})
            let id=e.register(peer)
            peer.fly(to:CGPoint(x:1810,y:990),host:nil,arc:0,allowsOrbit:false,random:{0.5})
            let slot=LandingReservation(bird:id,host:host,fraction:0.5)
            guard case .started(let run)=e.runtime.start(SlotExecution(slot),source:.preview,in:e)
            else {return XCTFail("The foreign landing reservation must be valid")}
            XCTAssertTrue(TravelTogetherPlan.candidates(in:e,source:.preview).isEmpty)
            e.runtime.cancel(run,reason:.removed,in:e)
            XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
        }
    }

    func testExternalRouteReplacementOfEitherParticipantIsPreservedDuringCleanup() throws {
        for replaced in 0..<2 {
            for common in [false,true] {
                let e=fixture(),s=try start(e)
                advance(e,seconds:common ? s.plan.commonEntries.max()!+0.2:0.2)
                let bird=s.birds[replaced],before=s.birds.map(\.position)
                bird.fly(to:CGPoint(x:1800,y:850),host:nil,arc:0,allowsOrbit:false,random:{0.5})
                let revision=bird.motionRevision;e.updateWorld(e.world)
                released(e,s,type:.failed)
                XCTAssertEqual(s.birds.map(\.position),before)
                XCTAssertEqual(bird.motionRevision,revision);XCTAssertFalse(bird.needsDestination)
                XCTAssertTrue(s.birds[1-replaced].needsDestination)
                advance(e,seconds:0.2)
                XCTAssertNotEqual(bird.position,before[replaced]);XCTAssertEqual(bird.motionRevision,revision)
                XCTAssertEqual(s.birds[1-replaced].position,before[1-replaced])
            }
        }
    }

    func testRemovalOfEitherBirdAndGlobalCancellationReleaseTheWholeEncounterOnce() throws {
        for removal in [0,1,2] {
            let e=fixture(),s=try start(e);advance(e,seconds:0.3)
            let before=s.birds.map(\.position)
            if removal<2 {e.handle(.remove(s.plan.participants[removal]))}
            else {e.handle(.cancelAmbient(.shutdown))}
            released(e,s,type:.cancelled)
            XCTAssertEqual(s.birds.map(\.position),before)
            advance(e,seconds:1);XCTAssertEqual(terminals(e,s.run).count,1)
        }
    }
}
