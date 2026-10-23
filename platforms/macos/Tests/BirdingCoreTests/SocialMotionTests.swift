import XCTest
@testable import BirdingCore

final class SocialMotionTests:XCTestCase {
    private let screen=CGRect(x:-1200,y:-400,width:3000,height:1800)
    private let host=Surface(id:71,pid:42,rect:CGRect(x:-900,y:800,width:2300,height:400))
    private let destination=Surface(id:72,pid:43,rect:CGRect(x:-900,y:400,width:2300,height:250))
    // Deliberately independent of SocialMotionPlan.requiredFrames.
    private let frames:Set<String> = ["stand","blink","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","land0","land1","land2"]

    private func fixture(seed:UInt64=73,ground:Bool=false) -> BehaviorEngine {
        var settings=BirdSettings();settings.socialInteractions=true;settings.perchActions=false
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let perch=ground ? Geometry.ground(id:73,display:screen,workArea:screen):host
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:ground ? [perch]:[destination,host],
            pointer:CGPoint(x:1200,y:0),availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)})))
        let species:[SpeciesID]=[.treeSparrow,.redWhiskeredBulbul]
        e.installFixtureBirds(species.enumerated().map {index,species in
            let lo=Geometry.perchX(0,rect:perch.rect),hi=Geometry.perchX(1,rect:perch.rect)
            let x:CGFloat = -500+CGFloat(index)*280
            let bird=Bird(position:.zero,fraction:(x-lo)/(hi-lo),profile:settings.catalog.profile(species),random:{0.5})
            bird.perch(on:perch,spriteScale:bird.profile.relativeScale);bird.perchDuration=600
            return bird
        })
        return e
    }

    private func levelDoveFixture(nearTop:Bool=false) -> BehaviorEngine {
        let e=fixture()
        // Keep the dove's wave-free motion, while making both actual sprite
        // scales exactly one so vertical bobbing cannot hide a crossing.
        var profile=SpeciesCatalog.standard.profile(.spottedDove)
        profile.adultLengthCM=19
        let perch=Surface(id:host.id,pid:host.pid,
            rect:CGRect(x:host.rect.minX,y:nearTop ? screen.minY+40:host.rect.minY,
                        width:host.rect.width,height:host.rect.height))
        var world=e.world;world.surfaces=[perch];world.scale=1;e.updateWorld(world)
        let xs:[CGFloat]=nearTop ? [-800,-717.75]:[-500,-220]
        let lo=Geometry.perchX(0,rect:perch.rect),hi=Geometry.perchX(1,rect:perch.rect)
        e.installFixtureBirds(xs.map {x in
            let bird=Bird(position:.zero,fraction:(x-lo)/(hi-lo),profile:profile,random:{0.5})
            bird.perch(on:perch,spriteScale:1);bird.perchDuration=600
            return bird
        })
        XCTAssertEqual(e.birds.map{e.spriteScale(for:$0)},[1,1])
        XCTAssertEqual(e.birds[0].position.y,e.birds[1].position.y)
        XCTAssertEqual(FlightBehavior.motion(.spottedDove).wave,0)
        return e
    }

    private func assertFourPointClearance(_ birds:[Bird],in e:BehaviorEngine,file:StaticString=#filePath,line:UInt=#line) {
        let areas=birds.map{Geometry.landingFootprint(at:$0.position,scale:e.spriteScale(for:$0)).insetBy(dx:-4,dy:-4)}
        let cut=areas[0].intersection(areas[1])
        XCTAssertTrue(cut.isNull || cut.isEmpty,"Both sprite envelopes need 4 pt clearance throughout the live flight",file:file,line:line)
    }

    private struct Session {
        let run:BehaviorRunID
        let event:BehaviorEvent
        let actors:[Bird]
        let origins:[CGPoint]
        let slots:[LandingReservation]
    }
    private func start(_ kind:SocialMotionKind,in e:BehaviorEngine,file:StaticString=#filePath,line:UInt=#line) throws -> Session {
        let before=e.birds.map(\.position)
        guard case .started(let run)=e.handle(.socialMotion(kind,.preview)) else {
            XCTFail("Expected \(kind) to start with ample space",file:file,line:line)
            throw NSError(domain:"SocialMotionTests",code:1)
        }
        let event=try XCTUnwrap(e.events.first{$0.runID==run && $0.type == .started},file:file,line:line)
        XCTAssertEqual(event.kind?.rawValue,kind.rawValue,file:file,line:line)
        XCTAssertEqual(event.source,.preview,file:file,line:line)
        guard event.participants.count==2,Set(event.participants).count==2 else {
            XCTFail("Expected two distinct ordered participants",file:file,line:line)
            throw NSError(domain:"SocialMotionTests",code:2)
        }
        let actors=try event.participants.map{try XCTUnwrap(e.bird($0),file:file,line:line)}
        let slots=try event.participants.map {id in
            try XCTUnwrap(e.runtime.landingReservations.first{$0.bird==id},file:file,line:line)
        }
        XCTAssertEqual(e.birds.map(\.position),before,file:file,line:line)
        XCTAssertEqual(e.activeRunCount,1,file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,2,file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,2,file:file,line:line)
        XCTAssertTrue(e.ambientBusy,file:file,line:line)
        XCTAssertFalse(slots[0].conflicts(with:slots[1],in:e),file:file,line:line)
        for bird in actors {
            XCTAssertEqual(e.role(of:bird),.resident,file:file,line:line)
            XCTAssertEqual(e.behavior(of:bird)?.rawValue,kind.rawValue,file:file,line:line)
        }
        return Session(run:run,event:event,actors:actors,origins:actors.map(\.position),slots:slots)
    }
    private func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    private func advance(_ e:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    private func released(_ e:BehaviorEngine,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(e.activeRunCount,0,file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertFalse(e.ambientBusy,file:file,line:line)
        for bird in e.birds {XCTAssertNil(e.behavior(of:bird),file:file,line:line)}
    }
    private func completed(_ e:BehaviorEngine,_ s:Session,file:StaticString=#filePath,line:UInt=#line) throws {
        let events=terminals(e,s.run)
        XCTAssertEqual(events.map(\.type),[.completed],file:file,line:line)
        let event=try XCTUnwrap(events.first,file:file,line:line)
        XCTAssertEqual(event.participants,s.event.participants,file:file,line:line)
        XCTAssertLessThanOrEqual(event.time-s.event.time,30,file:file,line:line)
        XCTAssertNil(event.reason,file:file,line:line)
        for (index,bird) in s.actors.enumerated() {
            XCTAssertEqual(bird.state,.perched,file:file,line:line)
            XCTAssertEqual(bird.position,try XCTUnwrap(s.slots[index].point(in:e)),file:file,line:line)
        }
        XCTAssertEqual(e.residentCount,2,file:file,line:line)
        XCTAssertEqual(Set(e.birds.compactMap{e.id(of:$0)}),Set(s.event.participants),file:file,line:line)
        XCTAssertEqual(e.passingCount,0,file:file,line:line);XCTAssertEqual(e.pendingCount,0,file:file,line:line)
        released(e,file:file,line:line)
    }
    private func finish(_ e:BehaviorEngine,_ s:Session) {
        for _ in 0..<60*30 {
            if !terminals(e,s.run).isEmpty {return}
            let positions=s.actors.map(\.position)
            e.advance(BehaviorEngine.step)
            for (index,bird) in s.actors.enumerated() {
                XCTAssertLessThan(Geometry.distance(positions[index],bird.position),40,"A flight step must not jump to its reserved anchor")
            }
        }
    }

    func testEveryPreviewUsesExistingBirdsAndCompletesExactlyOnceWithinThirtySeconds() throws {
        for kind in SocialMotionKind.allCases {
            let e=fixture(),identities=e.birds.map(ObjectIdentifier.init)
            let s=try start(kind,in:e)
            finish(e,s);try completed(e,s)
            XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
            XCTAssertTrue(s.actors.allSatisfy{$0.stateTime<0.05},"Completion resets the quiet perch timer")
            advance(e,seconds:3)
            XCTAssertEqual(terminals(e,s.run).count,1)
            XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities)
            XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
        }
    }

    func testSideBySideLeavesAnchorFixedAndGuestFliesToReservedNeighbor() throws {
        let e=fixture(),s=try start(.sideBySide,in:e)
        let anchor=s.actors[0],guest=s.actors[1]
        let target=try XCTUnwrap(s.slots[1].point(in:e))
        XCTAssertEqual(try XCTUnwrap(s.slots[0].point(in:e)),s.origins[0])
        XCTAssertLessThan(Geometry.distance(target,s.origins[0]),Geometry.distance(s.origins[1],s.origins[0]))
        var flew=false,sawIntermediate=false
        for _ in 0..<60*30 {
            let before=guest.position
            e.advance(BehaviorEngine.step)
            XCTAssertEqual(anchor.position,s.origins[0]);XCTAssertEqual(anchor.state,.perched)
            XCTAssertLessThan(Geometry.distance(before,guest.position),40)
            flew = flew || guest.state == .flying
            if guest.state == .flying,Geometry.distance(guest.position,s.origins[1])>1,
               Geometry.distance(guest.position,target)>1 {sawIntermediate=true}
            if !terminals(e,s.run).isEmpty {break}
        }
        XCTAssertTrue(flew);XCTAssertTrue(sawIntermediate)
        try completed(e,s)
    }

    func testRightHandGuestStaysOnItsSideAndNeverCrossesStationaryAnchor() throws {
        let e=levelDoveFixture(),birds=e.birds
        let ids=try birds.map{try XCTUnwrap(e.id(of:$0))}
        // Exercise this ordered pair explicitly: random selection could choose
        // the opposite roles and miss the right-to-left crossing regression.
        let plan=try XCTUnwrap(SocialMotionPlanner.candidates(.sideBySide,ids:ids,in:e).first{$0.participants==ids})
        let target=try XCTUnwrap(plan.destinations[1].point(in:e)),anchor=birds[0].position
        XCTAssertGreaterThan(birds[1].position.x,anchor.x)
        XCTAssertGreaterThan(target.x,anchor.x)
        XCTAssertLessThan(target.x,birds[1].position.x)
        guard case .started(let run)=e.runtime.start(SocialMotionExecution(plan:plan),source:.preview,in:e) else {
            return XCTFail("A clear approach from the guest's own side must start")
        }
        var flew=false
        for _ in 0..<60*30 {
            assertFourPointClearance(birds,in:e)
            e.advance(BehaviorEngine.step)
            XCTAssertEqual(birds[0].position,anchor);XCTAssertEqual(birds[0].state,.perched)
            XCTAssertGreaterThan(birds[1].position.x,anchor.x)
            assertFourPointClearance(birds,in:e)
            flew = flew || birds[1].state == .flying
            if !terminals(e,run).isEmpty {break}
        }
        XCTAssertTrue(flew);XCTAssertEqual(birds[1].position,target)
        XCTAssertEqual(terminals(e,run).map(\.type),[.completed]);released(e)
    }

    func testTightPairNearDisplayTopFlyingRightRejectsOrNeverCrossesWaitingBird() throws {
        let e=levelDoveFixture(nearTop:true),birds=e.birds
        let origins=birds.map(\.position),revisions=birds.map(\.motionRevision)
        XCTAssertEqual(origins[1].x-origins[0].x,82.25,accuracy:0.000001)
        XCTAssertEqual(origins[0].y,screen.minY+40)
        assertFourPointClearance(birds,in:e)
        let result=e.handle(.socialMotion(.pairedTakeoff,.preview))
        if case .rejected(let reason)=result {
            XCTAssertEqual(reason,.noSpace)
            XCTAssertEqual(birds.map(\.position),origins);XCTAssertEqual(birds.map(\.motionRevision),revisions)
            XCTAssertFalse(e.events.contains{$0.type == .started})
            released(e)
            return
        }
        guard case .started(let run)=result else {return XCTFail("Expected a safe plan or an atomic rejection")}
        let event=try XCTUnwrap(e.events.first{$0.runID==run && $0.type == .started})
        XCTAssertEqual(event.participants.count,2)
        let actors=try event.participants.map{try XCTUnwrap(e.bird($0))}
        guard actors.count==2 else {return XCTFail("Expected leader and follower")}
        XCTAssertGreaterThan(actors[0].position.x,actors[1].position.x,"The bird ahead in the direction of travel launches first")
        let slots=try event.participants.map {id in try XCTUnwrap(e.runtime.landingReservations.first{$0.bird==id})}
        let targets=try slots.map{try XCTUnwrap($0.point(in:e))}
        for index in 0..<2 {XCTAssertGreaterThan(targets[index].x,actors[index].position.x)}
        let waitingOrigin=actors[1].position
        var sawWaitingFollower=false,sawFollowerFlight=false
        for _ in 0..<60*30 {
            e.advance(BehaviorEngine.step)
            assertFourPointClearance(actors,in:e)
            for bird in actors {XCTAssertTrue(screen.contains(Geometry.landingFootprint(at:bird.position,scale:1)))}
            if actors[1].state == .flying {sawFollowerFlight=true}
            if actors[0].state == .flying && !sawFollowerFlight {
                sawWaitingFollower=true
                XCTAssertEqual(actors[1].state,.perched);XCTAssertEqual(actors[1].position,waitingOrigin)
            }
            if !terminals(e,run).isEmpty {break}
        }
        XCTAssertTrue(sawWaitingFollower);XCTAssertTrue(sawFollowerFlight)
        XCTAssertEqual(actors.map(\.position),targets)
        XCTAssertEqual(terminals(e,run).map(\.type),[.completed]);released(e)
    }

    func testGiveWayCancelsWhenThinPanelBlocksOnlyHopCorridorDuringPreparation() throws {
        let e=levelDoveFixture(),s=try start(.giveWay,in:e)
        advance(e,seconds:0.2)
        let origins=s.actors.map(\.position),revisions=s.actors.map(\.motionRevision),time=e.time
        let target=try XCTUnwrap(s.slots[0].point(in:e)),origin=s.origins[0]
        let panel=Surface(id:99,pid:90,
            rect:CGRect(x:min(origin.x,target.x)-29,y:origin.y-50,
                        width:abs(target.x-origin.x)+58,height:2),layer:1)
        // A two-point strip intersects the raised hop corridor, while remaining
        // above every origin and landing sprite, including reserved padding.
        let endpoints=origins + (try s.slots.map{try XCTUnwrap($0.point(in:e))})
        for point in endpoints {
            let cut=Geometry.landingFootprint(at:point,scale:1).insetBy(dx:-8,dy:-8).intersection(panel.rect)
            XCTAssertTrue(cut.isNull || cut.isEmpty)
        }
        var world=e.world;world.surfaces.insert(panel,at:0);e.updateWorld(world)
        XCTAssertTrue(s.slots.allSatisfy{$0.isValid(in:e)},"Valid endpoints must not hide a blocked hop corridor")
        XCTAssertEqual(e.time,time);XCTAssertEqual(s.actors.map(\.position),origins)
        XCTAssertEqual(s.actors.map(\.motionRevision),revisions)
        XCTAssertEqual(terminals(e,s.run).map(\.type),[.failed])
        XCTAssertEqual(terminals(e,s.run).map(\.reason),[.targetInvalid])
        released(e)
        advance(e,seconds:1)
        XCTAssertEqual(s.actors.map(\.position),origins)
        XCTAssertEqual(terminals(e,s.run).count,1)
    }

    func testGiveWayReplansAnAlreadyAirborneHopWhenItsCorridorBecomesBlocked() throws {
        let e=levelDoveFixture(),s=try start(.giveWay,in:e)
        advance(e,seconds:0.55)
        let first=s.actors[0],second=s.actors[1]
        XCTAssertEqual(first.state,.flying);XCTAssertEqual(second.state,.perched)
        XCTAssertGreaterThan(Geometry.distance(first.position,s.origins[0]),0)
        XCTAssertTrue(terminals(e,s.run).isEmpty)
        let positions=s.actors.map(\.position),revision=first.motionRevision,guestRevision=second.motionRevision,time=e.time
        let origin=s.origins[0],target=try XCTUnwrap(s.slots[0].point(in:e))
        let panel=Surface(id:99,pid:90,
            rect:CGRect(x:min(origin.x,target.x)-29,y:origin.y-50,
                        width:abs(target.x-origin.x)+58,height:2),layer:1)
        var world=e.world;world.surfaces.insert(panel,at:0);e.updateWorld(world)
        // Endpoints remain valid: releasing ownership alone would leave the old
        // short hop flying into the newly obstructed corridor.
        XCTAssertTrue(s.slots.allSatisfy{$0.isValid(in:e)})
        XCTAssertEqual(e.time,time);XCTAssertEqual(s.actors.map(\.position),positions)
        XCTAssertGreaterThan(first.motionRevision,revision)
        XCTAssertEqual(first.state,.flying)
        XCTAssertEqual(second.motionRevision,guestRevision);XCTAssertEqual(second.state,.perched)
        XCTAssertEqual(terminals(e,s.run).map(\.type),[.failed])
        XCTAssertEqual(terminals(e,s.run).map(\.reason),[.targetInvalid])
        released(e)
        let recoveryRevision=first.motionRevision
        e.advance(BehaviorEngine.step)
        XCTAssertLessThan(Geometry.distance(positions[0],first.position),40)
        XCTAssertEqual(first.motionRevision,recoveryRevision)
        XCTAssertEqual(second.position,positions[1])
        XCTAssertEqual(terminals(e,s.run).count,1)
        XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
    }

    func testGiveWayWaitsForFirstToPerchBeforeGuestTakesItsOldXIncludingGroundScale() throws {
        for ground in [false,true] {
            let e=fixture(ground:ground),s=try start(.giveWay,in:e)
            let first=s.actors[0],second=s.actors[1]
            let firstTarget=try XCTUnwrap(s.slots[0].point(in:e)),secondTarget=try XCTUnwrap(s.slots[1].point(in:e))
            XCTAssertEqual(secondTarget.x,s.origins[0].x,accuracy:0.000001)
            XCTAssertGreaterThan(abs(firstTarget.x-s.origins[0].x),20)
            if ground {
                XCTAssertNotEqual(e.spriteScale(for:first),e.spriteScale(for:second))
                XCTAssertEqual(secondTarget.y,screen.maxY-9*e.spriteScale(for:second),accuracy:0.000001)
                XCTAssertNotEqual(secondTarget.y,s.origins[0].y)
            }
            var firstFlew=false,secondFlew=false,firstPerched=false
            for _ in 0..<60*30 {
                let before=s.actors.map(\.position),firstState=first.state
                if firstFlew && firstState == .perched {firstPerched=true}
                e.advance(BehaviorEngine.step)
                if first.state == .flying {firstFlew=true}
                if second.state == .flying && !secondFlew {
                    XCTAssertTrue(firstFlew);XCTAssertTrue(firstPerched)
                    XCTAssertEqual(firstState,.perched)
                    XCTAssertEqual(first.position,firstTarget)
                    secondFlew=true
                }
                if !secondFlew {XCTAssertEqual(second.position,s.origins[1]);XCTAssertEqual(second.state,.perched)}
                for (index,bird) in s.actors.enumerated() {XCTAssertLessThan(Geometry.distance(before[index],bird.position),40)}
                if !terminals(e,s.run).isEmpty {break}
            }
            XCTAssertTrue(firstFlew);XCTAssertTrue(secondFlew)
            try completed(e,s)
            XCTAssertEqual(second.position.x,s.origins[0].x,accuracy:0.000001)
        }
    }

    func testPairedTakeoffPreparesFacingTargetsThenLaunchesPointSixFiveSecondsApart() throws {
        let e=fixture(),s=try start(.pairedTakeoff,in:e)
        let targets=try s.slots.map{try XCTUnwrap($0.point(in:e))}
        advance(e,seconds:0.2)
        XCTAssertEqual(s.actors.map(\.position),s.origins)
        XCTAssertTrue(s.actors.allSatisfy{$0.state == .perched})
        for (index,id) in s.event.participants.enumerated() where abs(targets[index].x-s.origins[index].x)>1 {
            let pose=try XCTUnwrap(e.renderSnapshot().first{$0.id==id})
            XCTAssertEqual(pose.facingRight,targets[index].x>s.origins[index].x)
        }
        var launched:[Int:Double]=[:]
        for _ in 0..<60*30 {
            let before=s.actors.map(\.position)
            e.advance(BehaviorEngine.step)
            for (index,bird) in s.actors.enumerated() {
                XCTAssertLessThan(Geometry.distance(before[index],bird.position),40)
                if bird.state == .flying && launched[index]==nil {launched[index]=e.time-s.event.time}
                if launched[index]==nil {XCTAssertEqual(bird.position,s.origins[index])}
            }
            if launched[0] != nil && launched[1]==nil {XCTAssertEqual(s.actors[1].state,.perched)}
            if !terminals(e,s.run).isEmpty {break}
        }
        let first=try XCTUnwrap(launched[0]),second=try XCTUnwrap(launched[1])
        XCTAssertGreaterThanOrEqual(first,0.45-1e-8)
        XCTAssertEqual(first,0.45,accuracy:1e-8)
        XCTAssertEqual(second,1.10,accuracy:1e-8)
        XCTAssertEqual(second-first,0.65,accuracy:1e-8)
        XCTAssertFalse(s.slots[0].conflicts(with:s.slots[1],in:e))
        try completed(e,s)
    }

    func testCompletionWaitsForBothBirdsToSettleBeforeReleasingReservations() throws {
        for kind in SocialMotionKind.allCases {
            let e=fixture(),s=try start(kind,in:e)
            var settledAt:Double?
            for _ in 0..<60*30 {
                e.advance(BehaviorEngine.step)
                let atTargets=try s.actors.enumerated().allSatisfy {index,bird in
                    let target=try XCTUnwrap(s.slots[index].point(in:e))
                    return bird.state == .perched && bird.position == target
                }
                if atTargets && settledAt==nil {settledAt=e.time}
                if !terminals(e,s.run).isEmpty {break}
                XCTAssertEqual(e.reservedLandingCount,2);XCTAssertEqual(e.leasedBirdCount,2)
            }
            let settled=try XCTUnwrap(settledAt),event=try XCTUnwrap(terminals(e,s.run).first)
            XCTAssertEqual(event.time-settled,1.2,accuracy:2*BehaviorEngine.step)
            try completed(e,s)
        }
    }

    func testClicksAndSettingsDisableReleaseWholeGroupWithoutMovingFeetSynchronously() throws {
        for kind in SocialMotionKind.allCases {
            for input in ["click","buttons","settings"] {
                for elapsed in [0.2,0.8] {
                    let e=fixture(),s=try start(kind,in:e)
                    advance(e,seconds:elapsed)
                    let positions=s.actors.map(\.position)
                    if input == "settings" {var value=e.settings;value.socialInteractions=false;e.applySettings(value)}
                    else if input == "buttons" {var world=e.world;world.buttonsDown=true;e.updateWorld(world)}
                    else {e.handle(.pointerClick)}
                    XCTAssertEqual(s.actors.map(\.position),positions)
                    e.advance(BehaviorEngine.step)
                    XCTAssertEqual(terminals(e,s.run).map(\.type),[.cancelled])
                    XCTAssertEqual(terminals(e,s.run).map(\.reason),[input == "settings" ? .settingsChanged:.userInput])
                    released(e);XCTAssertEqual(e.residentCount,2)
                    advance(e,seconds:3)
                    XCTAssertEqual(terminals(e,s.run).count,1)
                    XCTAssertEqual(Set(e.birds.compactMap{e.id(of:$0)}),Set(s.event.participants))
                }
            }
        }
    }

    func testRemovingEitherActorReleasesSurvivorAndNeverSpawnsAReplacement() throws {
        for kind in SocialMotionKind.allCases {
            for index in 0..<2 {
                let e=fixture(),s=try start(kind,in:e)
                advance(e,seconds:0.8)
                let survivor=s.actors[1-index],position=survivor.position
                e.handle(.remove(s.event.participants[index]))
                XCTAssertEqual(survivor.position,position)
                XCTAssertEqual(terminals(e,s.run).map(\.reason),[.removed])
                XCTAssertEqual(terminals(e,s.run).map(\.type),[.cancelled])
                released(e);XCTAssertEqual(e.residentCount,1)
                XCTAssertNil(e.bird(s.event.participants[index]))
                advance(e,seconds:3)
                XCTAssertEqual(e.birds.count,1);XCTAssertTrue(e.birds.first === survivor)
                XCTAssertEqual(terminals(e,s.run).count,1)
                XCTAssertEqual(e.events.filter{$0.type == .birdRemoved && $0.participants == [s.event.participants[index]]}.count,1)
            }
        }
    }

    func testPauseFreezesPreparationAndFlightThenResumesToCompletion() throws {
        for kind in SocialMotionKind.allCases {
            for elapsed in [0.2,0.8] {
                let e=fixture(),s=try start(kind,in:e)
                advance(e,seconds:elapsed);e.handle(.pause(true))
                let before=e.renderSnapshot(),ages=s.actors.map(\.stateTime),revisions=s.actors.map(\.motionRevision)
                advance(e,seconds:4)
                let after=e.renderSnapshot()
                XCTAssertEqual(after.map(\.position),before.map(\.position))
                XCTAssertEqual(after.map(\.frameName),before.map(\.frameName))
                XCTAssertEqual(after.map(\.facingRight),before.map(\.facingRight))
                XCTAssertEqual(after.map(\.hopOffset),before.map(\.hopOffset))
                XCTAssertEqual(s.actors.map(\.stateTime),ages);XCTAssertEqual(s.actors.map(\.motionRevision),revisions)
                XCTAssertTrue(terminals(e,s.run).isEmpty)
                XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.reservedLandingCount,2);XCTAssertEqual(e.leasedBirdCount,2)
                e.handle(.pause(false));finish(e,s)
                XCTAssertEqual(terminals(e,s.run).map(\.type),[.completed]);released(e)
            }
        }
    }

    func testWorldInvalidationReleasesBothSlotsEvenWhilePaused() throws {
        for kind in SocialMotionKind.allCases {
            for paused in [false,true] {
                for change in ["removed","narrow","occluded","pid","frames","scale","display"] {
                    for elapsed in [0.2,0.8] {
                        let e=fixture(),s=try start(kind,in:e)
                        advance(e,seconds:elapsed)
                        if paused {e.handle(.pause(true))}
                        let time=e.time,positions=s.actors.map(\.position)
                        var world=e.world
                        switch change {
                        case "removed":world.surfaces=[]
                        case "narrow":
                            for index in world.surfaces.indices {world.surfaces[index].rect.size.width=40}
                        case "occluded":world.surfaces.insert(Surface(id:99,pid:90,rect:screen,layer:1),at:0)
                        case "pid":world.surfaces=world.surfaces.map{Surface(id:$0.id,pid:$0.pid+100,rect:$0.rect)}
                        case "frames":world.availableFrames[s.actors[1].profile.id]?.remove("fly7")
                        case "scale":world.scale=1.1
                        default:world.displays=[];world.screens=[]
                        }
                        e.updateWorld(world)
                        XCTAssertEqual(e.time,time);XCTAssertEqual(s.actors.map(\.position),positions)
                        XCTAssertEqual(terminals(e,s.run).map(\.type),[.failed],"\(kind) / \(change)")
                        released(e);XCTAssertEqual(e.residentCount,2)
                        e.updateWorld(world);advance(e,seconds:1)
                        XCTAssertEqual(terminals(e,s.run).count,1)
                    }
                }
            }
        }
    }

    func testMissingAnyRequiredFrameRejectsAtomicallyBeforeEitherBirdMoves() {
        for kind in SocialMotionKind.allCases {
            for frame in frames.sorted() {
                let e=fixture(),birds=e.birds
                var world=e.world;world.availableFrames[birds[1].profile.id]?.remove(frame);e.updateWorld(world)
                let positions=birds.map(\.position),revisions=birds.map(\.motionRevision)
                let result=e.handle(.socialMotion(kind,.preview))
                if case .rejected = result {} else {XCTFail("Missing \(frame) must reject \(kind)")}
                XCTAssertEqual(birds.map(\.position),positions);XCTAssertEqual(birds.map(\.motionRevision),revisions)
                XCTAssertFalse(e.events.contains{$0.type == .started})
                released(e);XCTAssertEqual(e.residentCount,2)
            }
        }
    }

    func testIneligiblePairsCannotStartOrLeaveHalfAGroup() {
        for kind in SocialMotionKind.allCases {
            for change in ["oneBird","flying","side","departing","transient","leased","pointer","noSpace","crossScreen"] {
                let e=fixture(),first=e.birds[0],second=e.birds[1]
                switch change {
                case "oneBird":e.installFixtureBirds([first])
                case "flying":second.fly(to:second.position,host:host,urgent:true)
                case "side":second.edge = .left;second.perch(on:host)
                case "departing":second.depart(to:CGPoint(x:screen.maxX+200,y:500),duration:3)
                case "transient":e.installFixtureBirds([first]);e.register(second,role:.transient)
                case "leased":_=e.handle(.relocate(e.id(of:second)!))
                case "pointer":var world=e.world;world.pointer=first.position;e.updateWorld(world)
                case "noSpace":
                    var world=e.world;world.surfaces=[];e.updateWorld(world)
                default:
                    let otherScreen=screen.offsetBy(dx:screen.width,dy:0)
                    let otherHost=Surface(id:90,pid:70,rect:host.rect.offsetBy(dx:screen.width,dy:0))
                    second.perch(on:otherHost,spriteScale:e.spriteScale(for:second))
                    var world=e.world;world.screens.append(otherScreen);world.displays.append(otherScreen)
                    world.surfaces.append(otherHost);e.updateWorld(world)
                }
                let positions=e.birds.map(\.position),revisions=e.birds.map(\.motionRevision)
                let counts=[e.activeRunCount,e.leasedBirdCount,e.reservedLandingCount,e.birds.count]
                let startedBefore=e.events.filter{$0.type == .started}.count
                let result=e.handle(.socialMotion(kind,.preview))
                if case .rejected = result {} else {XCTFail("\(kind) must reject \(change)")}
                XCTAssertEqual(e.birds.map(\.position),positions);XCTAssertEqual(e.birds.map(\.motionRevision),revisions)
                XCTAssertEqual([e.activeRunCount,e.leasedBirdCount,e.reservedLandingCount,e.birds.count],counts)
                XCTAssertEqual(e.events.filter{$0.type == .started}.count,startedBefore)
            }
        }
    }

    func testSocialSwitchPauseAndAmbientEncounterBudgetGatePreviewAndAutomaticEqually() throws {
        for kind in SocialMotionKind.allCases {
            for source:BehaviorSource in [.preview,.automatic] {
                let disabled=fixture();var settings=disabled.settings;settings.socialInteractions=false;disabled.applySettings(settings)
                XCTAssertEqual(disabled.handle(.socialMotion(kind,source)),.rejected(.disabled));released(disabled)
                let paused=fixture();paused.handle(.pause(true))
                XCTAssertEqual(paused.handle(.socialMotion(kind,source)),.rejected(.paused));released(paused)
                let reserved=fixture()
                XCTAssertEqual(reserved.handle(.previewPointerAfter(3)),.scheduled)
                XCTAssertEqual(reserved.handle(.socialMotion(kind,source)),.rejected(.busy))
                XCTAssertEqual(reserved.reservedLandingCount,0);XCTAssertEqual(reserved.leasedBirdCount,0)
            }
            let e=fixture(),s=try start(kind,in:e)
            for source:BehaviorSource in [.preview,.automatic] {
                for other in SocialMotionKind.allCases {XCTAssertEqual(e.handle(.socialMotion(other,source)),.rejected(.busy))}
                XCTAssertEqual(e.handle(.pointerVisit(source)),.rejected(.busy))
                XCTAssertEqual(e.handle(.flockPass(source)),.rejected(.busy))
                XCTAssertEqual(e.handle(.socialGreeting(source)),.rejected(.busy))
            }
            XCTAssertEqual(e.leasedBirdCount,2);XCTAssertEqual(e.reservedLandingCount,2)
            finish(e,s);try completed(e,s)
            let other=fixture()
            guard case .started = other.handle(.pointerVisit(.preview)) else {return XCTFail("Pointer fixture must own the ambient budget")}
            XCTAssertEqual(other.handle(.socialMotion(kind,.preview)),.rejected(.busy))
            XCTAssertEqual(other.leasedBirdCount,1);XCTAssertEqual(other.reservedLandingCount,0)
        }
    }

    func testWorldSyncAndRenderingDoNotAdvancePreparationOrFlyEitherActor() throws {
        for kind in SocialMotionKind.allCases {
            let e=fixture(),s=try start(kind,in:e)
            let revisions=s.actors.map(\.motionRevision),time=e.time
            for _ in 0..<20 {e.updateWorld(e.world);_=e.renderSnapshot()}
            XCTAssertEqual(e.time,time);XCTAssertEqual(s.actors.map(\.position),s.origins)
            XCTAssertEqual(s.actors.map(\.motionRevision),revisions)
            XCTAssertTrue(s.actors.allSatisfy{$0.state == .perched})
            XCTAssertEqual(e.reservedLandingCount,2);XCTAssertEqual(e.leasedBirdCount,2)
            advance(e,seconds:0.4)
            XCTAssertTrue(s.actors.allSatisfy{$0.state == .perched})
            XCTAssertEqual(s.actors.map(\.position),s.origins)
            advance(e,seconds:0.1)
            XCTAssertEqual(s.actors[kind == .sideBySide ? 1:0].state,.flying)
        }
    }

    func testFixedStepReplayMatchesAtThirtySixtyAndOneHundredTwentyHz() throws {
        struct Trace:Equatable {
            let ids:[BirdID],positions:[CGPoint],states:[String],frames:[String],directions:[Bool]
            let revisions:[UInt64],events:[String],counts:[Int]
        }
        func replay(_ kind:SocialMotionKind,hz:Int) throws -> [Trace] {
            let e=fixture(),s=try start(kind,in:e)
            var trace:[Trace]=[]
            for second in 0..<35 {
                if second==1 {e.handle(.pause(true))}
                if second==3 {e.handle(.pause(false))}
                advance(e,seconds:1,hz:hz)
                let snapshot=e.renderSnapshot()
                trace.append(Trace(ids:snapshot.map(\.id),positions:snapshot.map(\.position),states:e.birds.map{$0.state.rawValue},
                    frames:snapshot.map(\.frameName),directions:snapshot.map(\.facingRight),revisions:e.birds.map(\.motionRevision),
                    events:e.events.map{"\($0.sequence):\($0.time):\($0.type):\($0.kind?.rawValue ?? ""):\($0.reason?.rawValue ?? ""):\($0.participants.map(\.rawValue))"},
                    counts:[e.activeRunCount,e.leasedBirdCount,e.reservedLandingCount,e.residentCount,e.pendingCount,e.passingCount]))
            }
            XCTAssertEqual(terminals(e,s.run).map(\.type),[.completed]);released(e)
            return trace
        }
        for kind in SocialMotionKind.allCases {
            let reference=try replay(kind,hz:60)
            XCTAssertEqual(try replay(kind,hz:30),reference)
            XCTAssertEqual(try replay(kind,hz:120),reference)
        }
    }
}
