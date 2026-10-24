import XCTest
@testable import BirdingCore

final class ChaseTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:1600,height:1200)
    private let host=Surface(id:171,pid:42,rect:CGRect(x:100,y:900,width:1400,height:200))
    // Independent of the production capability declaration.
    private let frames:Set<String> = ["stand","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","land0","land1","land2"]

    private func fixture(species:[SpeciesID] = [.treeSparrow,.treeSparrow],scale:CGFloat=1) -> BehaviorEngine {
        var settings=BirdSettings();settings.socialInteractions=true;settings.chaseEnabled=true
        settings.perchActions=false;settings.passiveAttentionEnabled=false
        let e=BehaviorEngine(seed:171,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[host],scale:scale,
            pointer:CGPoint(x:40,y:40),availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)})))
        e.installFixtureBirds(species.enumerated().map {index,species in
            let bird=Bird(position:.zero,fraction:index==0 ? 0.35:0.55,profile:settings.catalog.profile(species),random:{0.5})
            bird.perch(on:host,spriteScale:scale*bird.profile.relativeScale);bird.perchDuration=600
            return bird
        })
        advance(e,seconds:0.5)
        return e
    }
    private func advance(_ e:BehaviorEngine,seconds:Double) {
        for _ in 0..<Int(ceil(seconds/BehaviorEngine.step-1e-9)) {e.advance(BehaviorEngine.step)}
    }
    private struct Session {
        let run:BehaviorRunID,plan:ChasePlan
        let birds:[Bird],origins:[CGPoint]
    }
    private func start(_ e:BehaviorEngine,source:BehaviorSource = .preview) throws -> Session {
        let origins=e.birds.map(\.position),identities=e.birds.map(ObjectIdentifier.init)
        guard case .started(let run)=e.handle(.chase(source)) else {
            XCTFail("Expected a bounded chase in the shared 1600x1200 fixture")
            throw NSError(domain:"ChaseTests",code:1)
        }
        let execution=try XCTUnwrap(e.runtime.runs[run]?.execution as? ChaseExecution)
        let birds=try execution.participants.map{try XCTUnwrap(e.bird($0))}
        XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
        XCTAssertEqual(e.birds.map(\.position),origins)
        XCTAssertEqual(Set(execution.participants).count,2)
        XCTAssertEqual(e.leasedBirdCount,2);XCTAssertEqual(e.reservedLandingCount,2)
        XCTAssertTrue(e.ambientBusy);XCTAssertTrue(birds.allSatisfy{$0.state == .perched && $0.isCoordinatedFlying})
        return Session(run:run,plan:execution.plan,birds:birds,origins:birds.map(\.position))
    }
    private func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    private func released(_ e:BehaviorEngine,_ s:Session,type:BehaviorEventType,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(terminals(e,s.run).map(\.type),[type],file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line);XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertFalse(e.ambientBusy,file:file,line:line)
        XCTAssertTrue(s.birds.allSatisfy{!$0.isCoordinatedFlying},file:file,line:line)
    }

    func testSameLoopHasRealPhaseLagAndReturnsBothExistingResidents() throws {
        let e=fixture(),s=try start(e),entries=s.plan.loopEntries
        let lag=entries[1]-entries[0]
        XCTAssertGreaterThan(lag,0.5)
        XCTAssertGreaterThanOrEqual(s.plan.loopDuration-lag,3)
        XCTAssertLessThanOrEqual(s.plan.loopDuration,5)
        var waitingSeen=false,pairedSamples=0,leaderSamples:[(Double,CGPoint)]=[]
        let startedAt=e.time
        for _ in 0..<Int(ceil((s.plan.duration+1)/BehaviorEngine.step)) {
            let before=s.birds.map(\.position)
            e.advance(BehaviorEngine.step)
            let age=e.time-startedAt
            waitingSeen = waitingSeen || (s.birds[0].state == .flying && s.birds[1].state == .perched)
            let areas=s.birds.map{Geometry.landingFootprint(at:$0.position,scale:e.spriteScale(for:$0)).insetBy(dx:-4,dy:-4)}
            let cut=areas[0].intersection(areas[1]);XCTAssertTrue(cut.isNull || cut.isEmpty)
            for (index,bird) in s.birds.enumerated() {
                XCTAssertTrue(display.contains(Geometry.landingFootprint(at:bird.position,scale:e.spriteScale(for:bird))))
                XCTAssertLessThan(Geometry.distance(before[index],bird.position),20*e.spriteScale(for:bird))
            }
            if age>=entries[0],age<=entries[0]+s.plan.loopDuration {leaderSamples.append((age,s.birds[0].position))}
            if age>=entries[1],age<=entries[0]+s.plan.loopDuration {
                pairedSamples+=1
                for index in 0..<2 {
                    let expected=s.plan.loop.point((age-entries[index])/s.plan.loopDuration)
                    XCTAssertLessThan(Geometry.distance(s.birds[index].position,expected),0.01)
                }
                // A follower revisits actual earlier leader coordinates. Parallel
                // translated ellipses cannot satisfy this time-shifted assertion.
                let earlier=try XCTUnwrap(leaderSamples.min{abs($0.0-(age-lag))<abs($1.0-(age-lag))})
                XCTAssertLessThan(Geometry.distance(s.birds[1].position,earlier.1),4)
            }
            if !terminals(e,s.run).isEmpty {break}
        }
        XCTAssertTrue(waitingSeen);XCTAssertGreaterThan(pairedSamples,170)
        released(e,s,type:.completed)
        for (index,bird) in s.birds.enumerated() {
            XCTAssertEqual(bird.position,s.origins[index]);XCTAssertEqual(bird.state,.perched)
            XCTAssertEqual(bird.fraction,s.plan.destinations[index].fraction)
            XCTAssertEqual(bird.landedCount,1)
        }
        XCTAssertEqual(e.residentCount,2);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
        advance(e,seconds:1);XCTAssertEqual(terminals(e,s.run).count,1)
    }

    func testSevenSpeciesUseTheirActualSizesAndTangentSpeedMatchedJoins() throws {
        let species:[SpeciesID]=[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling,.redWhiskeredBulbul]
        XCTAssertEqual(ChaseBehavior.supportedSpecies,Set(species))
        for species in species {
            let e=fixture(species:[species,species])
            let candidates=ChasePlan.candidates(in:e,source:.preview)
            XCTAssertLessThanOrEqual(candidates.count,4)
            let plan=try XCTUnwrap(candidates.first,"Species \(species) needs a clear geometry plan")
            XCTAssertEqual(plan.scales,e.birds.map{e.spriteScale(for:$0)})
            for route in plan.routes {
                for index in 1..<route.legs.count {
                    let a=route.legs[index-1],b=route.legs[index]
                    XCTAssertEqual(a.path.point(1),b.path.point(0))
                    XCTAssertEqual(a.timing.speed(at:a.timing.duration),b.timing.speed(at:0),accuracy:0.001)
                    let p=a.path.point(1),before=a.path.point(0.9999),after=b.path.point(0.0001)
                    let u=CGPoint(x:p.x-before.x,y:p.y-before.y),v=CGPoint(x:after.x-p.x,y:after.y-p.y)
                    let dot=(u.x*v.x+u.y*v.y)/(Geometry.distance(.zero,u)*Geometry.distance(.zero,v))
                    XCTAssertGreaterThan(dot,0.99,"Each join must keep its tangent")
                }
            }
            let s=try start(e)
            advance(e,seconds:s.plan.duration+1)
            released(e,s,type:.completed)
        }
    }

    func testRejectsUnavailablePairsMissingFramesAndNoFlightRoomWithoutMovingBirds() {
        let mismatch=fixture(species:[.treeSparrow,.barnSwallow])
        XCTAssertEqual(mismatch.handle(.chase(.preview)),.rejected(.noCompanion))
        let unsupported=fixture(species:[.spottedDove,.spottedDove])
        XCTAssertEqual(unsupported.handle(.chase(.preview)),.rejected(.noSpecies))
        for scenario in ["unsettled","dwell","frames","pointer","panel","top"] {
            let e=fixture(),before=e.birds.map(\.position)
            var world=e.world
            switch scenario {
            case "unsettled":e.birds[0].perch(on:host,spriteScale:e.spriteScale(for:e.birds[0]))
            case "dwell":e.birds[0].perchDuration=e.birds[0].stateTime+8
            case "frames":world.availableFrames[.treeSparrow]?.remove("land2")
            case "pointer":world.pointer=e.birds[0].position
            case "panel":world.surfaces.insert(Surface(id:172,rect:CGRect(x:0,y:0,width:1600,height:800),layer:1),at:0)
            default:world.displays=[CGRect(x:0,y:840,width:1600,height:360)]
            }
            e.updateWorld(world)
            XCTAssertFalse(e.handle(.chase(.preview)).accepted,scenario)
            XCTAssertEqual(e.birds.map(\.position),before);XCTAssertEqual(e.activeRunCount,0)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
    }

    func testClickAtWaitingStaggerEntryLoopExitAndLandingNeverTeleports() throws {
        for phase in 0..<6 {
            let e=fixture(),s=try start(e),entries=s.plan.loopEntries
            let times=[0.1,(s.plan.launchOffsets[0]+s.plan.launchOffsets[1])/2,
                s.plan.launchOffsets[1]+0.1,entries[1]+0.5,
                entries[0]+s.plan.loopDuration+0.1,s.plan.launchOffsets[0]+s.plan.routes[0].duration+0.1]
            advance(e,seconds:times[phase])
            XCTAssertTrue(terminals(e,s.run).isEmpty)
            let before=s.birds.map(\.position),states=s.birds.map(\.state)
            e.handle(.pointerClick)
            released(e,s,type:.cancelled)
            XCTAssertEqual(terminals(e,s.run).first?.reason,.userInput)
            XCTAssertEqual(s.birds.map(\.position),before)
            for (index,bird) in s.birds.enumerated() {
                if states[index] == .perched {XCTAssertEqual(bird.state,.perched)}
                else {XCTAssertTrue(bird.needsDestination)}
            }
            advance(e,seconds:0.2);XCTAssertEqual(s.birds.map(\.position),before)
            XCTAssertEqual(terminals(e,s.run).count,1)
        }
    }

    func testPauseFreezesEveryClockAndBothSlowAndFastHostChangesCancelAtActualFeet() throws {
        for waiting in [true,false] {
            for sampleDT in [0.1,1.0] {
                let e=fixture(),s=try start(e)
                advance(e,seconds:waiting ? 0.1:s.plan.loopEntries[1]+0.3)
                e.handle(.pause(true))
                let before=s.birds.map(\.position),ages=s.birds.map(\.coordinatedFlightAge),runAge=e.runtime.runs[s.run]?.age
                e.updateWorld(e.world,sampleDT:sampleDT);advance(e,seconds:0.5)
                XCTAssertEqual(s.birds.map(\.position),before);XCTAssertEqual(s.birds.map(\.coordinatedFlightAge),ages)
                XCTAssertEqual(e.runtime.runs[s.run]?.age,runAge)
                var world=e.world;world.surfaces[0].rect.origin.x+=30
                e.updateWorld(world,sampleDT:sampleDT)
                released(e,s,type:.failed)
                XCTAssertEqual(s.birds.map(\.position),before)
                XCTAssertTrue(s.birds.allSatisfy(\.needsDestination))
                advance(e,seconds:1);XCTAssertEqual(s.birds.map(\.position),before)
            }
        }
    }

    func testPausedInvalidationOfFramesScaleScreensInputAndSettingsReleasesBothSlots() throws {
        for scenario in ["frames","scale","screens","input","settings"] {
            let e=fixture(),s=try start(e)
            advance(e,seconds:s.plan.loopEntries[1]+0.1);e.handle(.pause(true))
            let before=s.birds.map(\.position)
            var world=e.world
            switch scenario {
            case "frames":world.availableFrames[.treeSparrow]?.remove("fly7");e.updateWorld(world)
            case "scale":world.scale*=1.1;e.updateWorld(world)
            case "screens":world.screens[0].size.height-=1;e.updateWorld(world)
            case "input":world.buttonsDown=true;e.updateWorld(world)
            default:var settings=e.settings;settings.chaseEnabled=false;e.applySettings(settings)
            }
            released(e,s,type:["input","settings"].contains(scenario) ? .cancelled:.failed)
            XCTAssertEqual(s.birds.map(\.position),before)
            XCTAssertTrue(s.birds.allSatisfy(\.needsDestination))
        }
    }

    func testPointerAndThinUtilityPanelProtectFutureSweepsButNormalWindowDoesNot() throws {
        for obstruction in ["pointer","panel","normal"] {
            let e=fixture(),s=try start(e)
            let p=s.plan.loop.point(0.37),before=s.birds.map(\.position)
            var world=e.world
            if obstruction == "pointer" {world.pointer=p}
            else {world.surfaces.insert(Surface(id:172,rect:CGRect(x:p.x,y:p.y-3,width:0.01,height:6),layer:obstruction == "panel" ? 1:0),at:0)}
            e.updateWorld(world)
            XCTAssertEqual(s.birds.map(\.position),before)
            if obstruction == "normal" {
                XCTAssertTrue(terminals(e,s.run).isEmpty)
                advance(e,seconds:s.plan.duration+1);released(e,s,type:.completed)
            } else {
                released(e,s,type:obstruction == "pointer" ? .cancelled:.failed)
            }
        }
    }

    private final class SlotExecution:BehaviorExecution {
        let kind:BehaviorKind = .relocate
        let occupiesEncounter=false,runsWhilePaused=false,timeout=20.0
        let landingReservations:[LandingReservation]
        var participants:[BirdID] {landingReservations.map(\.bird)}
        init(_ slot:LandingReservation) {landingReservations=[slot]}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }
    func testForeignLandingReservationProtectsAirborneCorridorBeforeEitherBirdLaunches() throws {
        let e=fixture(),s=try start(e),p=s.plan.loop.point(0.25)
        let remote=Bird(position:CGPoint(x:1500,y:1100),fraction:0.5,profile:e.birds[0].profile,random:{0.5})
        let id=e.register(remote)
        remote.fly(to:CGPoint(x:1510,y:1100),host:nil,arc:0,allowsOrbit:false,random:{0.5})
        let ledge=Surface(id:173,pid:43,rect:CGRect(x:p.x-100,y:p.y,width:200,height:100))
        var world=e.world;world.surfaces.append(ledge);e.updateWorld(world)
        let slot=LandingReservation(bird:id,host:ledge,fraction:0.5)
        guard case .started(let foreign)=e.runtime.start(SlotExecution(slot),source:.preview,in:e) else {return XCTFail("Distant owner can reserve a valid airborne-corridor ledge")}
        let before=s.birds.map(\.position)
        e.updateWorld(e.world)
        XCTAssertEqual(terminals(e,s.run).map(\.type),[.failed])
        XCTAssertEqual(s.birds.map(\.position),before)
        XCTAssertEqual(e.leasedBirdCount,1);XCTAssertEqual(e.reservedLandingCount,1)
        e.runtime.cancel(foreign,reason:.removed,in:e)
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
    }

    func testThirdBirdHostCorrectionCrossingLoopCancelsBeforeAnyFeetAdvance() throws {
        let e=fixture(),s=try start(e)
        advance(e,seconds:0.1)
        let peerHost=Surface(id:174,pid:44,rect:CGRect(x:1450,y:1080,width:100,height:100))
        let peer=Bird(position:CGPoint(x:1510,y:1050),fraction:0.5,profile:e.birds[0].profile,random:{0.5})
        e.register(peer)
        let target=Geometry.foot(on:peerHost,fraction:0.5,edge:.top,scale:e.spriteScale(for:peer))
        peer.fly(to:target,host:peerHost,arc:0,allowsOrbit:false,random:{0.5})
        var world=e.world;world.surfaces.append(peerHost);e.updateWorld(world)
        XCTAssertTrue(terminals(e,s.run).isEmpty,"The original far-right route is clear")
        let before=e.birds.map(\.position),crossing=s.plan.loop.point(0.25)
        world.surfaces[1].rect.origin.x+=crossing.x-target.x
        world.surfaces[1].rect.origin.y+=crossing.y-target.y
        e.updateWorld(world,sampleDT:0.1)
        released(e,s,type:.failed)
        XCTAssertEqual(e.birds.map(\.position),before,"Metadata changes only the peer's target; validation must cancel before tick")
        XCTAssertFalse(peer.needsDestination);XCTAssertEqual(peer.state,.flying)
    }

    func testExternalRouteReplacementIsNeverOverwrittenByChaseCleanup() throws {
        for waiting in [true,false] {
            let e=fixture(),s=try start(e)
            advance(e,seconds:waiting ? 0.1:s.plan.loopEntries[1]+0.2)
            let bird=s.birds[0],before=s.birds.map(\.position)
            bird.fly(to:CGPoint(x:1200,y:650),host:nil,arc:20,allowsOrbit:false,random:{0.5})
            let revision=bird.motionRevision
            e.updateWorld(e.world)
            released(e,s,type:.failed)
            XCTAssertEqual(bird.motionRevision,revision);XCTAssertFalse(bird.needsDestination)
            XCTAssertEqual(s.birds.map(\.position),before)
            advance(e,seconds:0.2)
            XCTAssertNotEqual(bird.position,before[0]);XCTAssertEqual(bird.motionRevision,revision)
        }
    }

    func testRedWhiskeredBulbulReallyChasesWithContinuousSampledJoinsAndBothOriginalLandings() throws {
        for source:BehaviorSource in [.preview,.automatic] {
            let e=fixture(species:[.redWhiskeredBulbul,.redWhiskeredBulbul])
            for bird in e.birds {e.perchPlanner.rhythms[try XCTUnwrap(e.id(of:bird))]?.quietTime=4}
            let identities=e.birds.map(ObjectIdentifier.init),s=try start(e,source:source)
            XCTAssertEqual(s.plan.scales,s.birds.map{e.spriteScale(for:$0)})
            var joins=Set<String>(),observations:[BehaviorObservation]=[]
            e.observationObserver={observations.append($0)}
            for _ in 0..<Int(ceil((s.plan.duration+1)/BehaviorEngine.step)) {
                let before=s.birds.map(\.position),ages=s.birds.map{$0.coordinatedFlightAge ?? 0}
                let speeds=s.birds.map(\.flightSpeed)
                e.advance(BehaviorEngine.step)
                for index in 0..<2 {
                    let bird=s.birds[index],route=s.plan.routes[index],dt=BehaviorEngine.step
                    let clock=bird.coordinatedFlightAge ?? route.duration
                    let size=e.spriteScale(for:bird)
                    XCTAssertTrue(display.contains(Geometry.landingFootprint(at:bird.position,scale:size)))
                    XCTAssertLessThanOrEqual(Double(Geometry.distance(before[index],bird.position)),
                        (route.legs.map{$0.timing.peakSpeed}.max() ?? 0)*dt+0.001)
                    var boundary=0.0
                    for join in 1..<route.legs.count {
                        boundary+=route.legs[join-1].timing.duration
                        if ages[index]<boundary,clock>=boundary {
                            joins.insert("\(index):\(join)")
                            let cruise=route.legs[join].timing.speed(at:0)
                            XCTAssertEqual(bird.flightSpeed,cruise,accuracy:2,"Actual feet must keep cruise across join \(index):\(join)")
                            XCTAssertLessThan(abs(bird.flightSpeed-speeds[index]),8)
                        }
                    }
                }
                if !terminals(e,s.run).isEmpty {break}
            }
            XCTAssertEqual(joins,["0:1","0:2","1:1","1:2"])
            released(e,s,type:.completed)
            XCTAssertEqual(s.birds.map(\.position),s.origins)
            XCTAssertTrue(s.birds.allSatisfy{$0.state == .perched && $0.landedCount == 1})
            XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
            XCTAssertEqual(observations.count,1);XCTAssertEqual(observations.first?.source,source)
            XCTAssertEqual(e.residentCount,2);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
        }
    }

    func testRedWhiskeredBulbulEitherParticipantCanLeaveEveryChasePhaseIndependently() throws {
        for actor in 0..<2 {
            for phase in 0..<6 {
                for cause in ["relocate","external","remove"] {
                    let e=fixture(species:[.redWhiskeredBulbul,.redWhiskeredBulbul]),s=try start(e)
                    let times=[0.1,(s.plan.launchOffsets[0]+s.plan.launchOffsets[1])/2,
                        s.plan.launchOffsets[1]+0.1,s.plan.loopEntries[1]+0.5,
                        s.plan.loopEntries[0]+s.plan.loopDuration+0.1,
                        s.plan.launchOffsets[0]+s.plan.routes[0].duration+0.1]
                    advance(e,seconds:times[phase]);XCTAssertTrue(terminals(e,s.run).isEmpty)
                    let bird=s.birds[actor],other=s.birds[1-actor],before=s.birds.map(\.position),otherState=other.state
                    var observations:[BehaviorObservation]=[]
                    e.observationObserver={observations.append($0)}
                    var replacement:BehaviorRunID?
                    switch cause {
                    case "relocate":
                        guard case .started(let run)=e.handle(.relocate(s.plan.participants[actor])) else {
                            XCTFail("Either bulbul must accept immediate relocation in phase \(phase)");continue
                        }
                        replacement=run
                    case "external":
                        bird.fly(to:CGPoint(x:1200,y:650),host:nil,arc:0,allowsOrbit:false,random:{0.5})
                        e.updateWorld(e.world)
                    default:e.handle(.remove(s.plan.participants[actor]))
                    }
                    let revision=bird.motionRevision
                    XCTAssertEqual(terminals(e,s.run).map(\.type),[cause == "external" ? .failed:.cancelled])
                    XCTAssertEqual(terminals(e,s.run).first?.reason,
                        cause == "external" ? .targetInvalid:(cause == "remove" ? .removed:.replaced))
                    XCTAssertEqual(s.birds.map(\.position),before)
                    XCTAssertFalse(e.runtime.owners.values.contains(s.run));XCTAssertEqual(e.reservedLandingCount,0)
                    XCTAssertFalse(s.birds.contains(where:{$0.isCoordinatedFlying}))
                    if let replacement {XCTAssertEqual(e.runtime.owners[s.plan.participants[actor]],replacement)}
                    else {XCTAssertEqual(e.leasedBirdCount,0)}
                    if otherState == .perched {XCTAssertEqual(other.state,.perched)}
                    else {XCTAssertTrue(other.needsDestination)}
                    advance(e,seconds:0.2)
                    if cause != "remove" {
                        XCTAssertNotEqual(bird.position,before[actor]);XCTAssertEqual(bird.motionRevision,revision)
                    }
                    XCTAssertEqual(other.position,before[1-actor])
                    XCTAssertTrue(observations.isEmpty);XCTAssertEqual(terminals(e,s.run).count,1)
                    e.handle(.cancelAmbient(.sleep))
                    XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                }
            }
        }
    }

    func testRedWhiskeredBulbulChaseCompletionAndEitherRemovalMatchAtThirtySixtyAndOneHundredTwentyHz() throws {
        struct Trace:Equatable {
            let positions:[CGPoint],frames:[String],states:[BirdState]
            let counts:[Int],events:[String]
        }
        func replay(_ hz:Int,removed:Int?) throws -> [Trace] {
            let e=fixture(species:[.redWhiskeredBulbul,.redWhiskeredBulbul]),s=try start(e)
            var observations:[BehaviorObservation]=[],trace:[Trace]=[]
            e.observationObserver={observations.append($0)}
            for sample in 0..<340 {
                if sample==2 {e.handle(.pause(true))}
                if sample==5 {e.handle(.pause(false))}
                if sample==12,let removed {e.handle(.remove(s.plan.participants[removed]))}
                for _ in 0..<(hz/10) {e.advance(1/Double(hz))}
                trace.append(Trace(positions:s.birds.map(\.position),frames:e.renderSnapshot().map(\.frameName),
                    states:s.birds.map(\.state),counts:[e.activeRunCount,e.leasedBirdCount,e.reservedLandingCount,
                        e.residentCount,e.arrivalCount,e.departureCount,observations.count],
                    events:e.events.map{"\($0.sequence):\($0.time):\($0.runID?.rawValue ?? 0):\($0.kind?.rawValue ?? ""):\($0.type):\($0.reason?.rawValue ?? ""):\($0.participants.map(\.rawValue))"}))
            }
            released(e,s,type:removed == nil ? .completed:.cancelled)
            XCTAssertEqual(observations.count,removed == nil ? 1:0)
            return trace
        }
        let actors:[Int?]=[nil,0,1]
        for actor in actors {
            let reference=try replay(60,removed:actor)
            XCTAssertEqual(try replay(30,removed:actor),reference)
            XCTAssertEqual(try replay(120,removed:actor),reference)
        }
    }
}
