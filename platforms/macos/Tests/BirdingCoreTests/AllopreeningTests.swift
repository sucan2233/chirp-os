import XCTest
@testable import BirdingCore

final class AllopreeningTests:XCTestCase {
    // Independent of the production definition, so incomplete manifests fail.
    private let frames:Set<String> = ["stand","land0","land1","land2",
        "allopreenGive0","allopreenGive1","allopreenGive2",
        "allopreenReceive0","allopreenReceive1","allopreenReceive2"]
    private let display=CGRect(x:-1200,y:-400,width:2400,height:1400)
    private let host=Surface(id:812,pid:42,rect:CGRect(x:-900,y:450,width:1800,height:300))

    private func fixture(species:[SpeciesID] = [.barnSwallow,.barnSwallow],scale:CGFloat=1,
                         gap:CGFloat=120,mirrored:Bool=false,dwell:Double=0.6) -> BehaviorEngine {
        var settings=BirdSettings();settings.socialInteractions=true;settings.allopreeningEnabled=true
        settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.pointerVisits=false;settings.flockPasses=false
        let e=BehaviorEngine(seed:812,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[host],scale:scale,
            pointer:CGPoint(x:-1100,y:-300),availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)})))
        let size=scale*settings.catalog.profile(species[0]).relativeScale
        e.installFixtureBirds(species.enumerated().map {index,id in
            let x:CGFloat = -100+(index==0 ? 0:(mirrored ? -1:1)*gap*size)
            let bird=Bird(position:.zero,fraction:fraction(at:x,on:host),profile:settings.catalog.profile(id),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
            return bird
        })
        advance(e,seconds:dwell)
        return e
    }
    private func fraction(at x:CGFloat,on host:Surface) -> CGFloat {
        (x-Geometry.perchX(0,rect:host.rect))/(Geometry.perchX(1,rect:host.rect)-Geometry.perchX(0,rect:host.rect))
    }
    private func advance(_ e:BehaviorEngine,seconds:Double) {
        for _ in 0..<max(0,Int(ceil(seconds/BehaviorEngine.step-1e-9))) {e.advance(BehaviorEngine.step)}
    }
    private struct Session {
        let run:BehaviorRunID,plan:AllopreeningPlan,execution:AllopreeningExecution,birds:[Bird]
    }
    private func start(_ e:BehaviorEngine,source:BehaviorSource = .preview) throws -> Session {
        let plan=try XCTUnwrap(AllopreeningPlan.candidates(in:e,source:source).first)
        let execution=AllopreeningExecution(plan:plan,source:source)
        let positions=e.birds.map(\.position)
        guard case .started(let run)=e.runtime.start(execution,source:source,in:e) else {
            XCTFail("A safe pair on one ledge must start with one shared reservation")
            throw NSError(domain:"AllopreeningTests",code:1)
        }
        XCTAssertEqual(e.birds.map(\.position),positions)
        XCTAssertEqual(e.leasedBirdCount,2);XCTAssertEqual(e.reservedLandingCount,1)
        XCTAssertEqual(e.activeRunCount,1);XCTAssertTrue(e.ambientBusy)
        return Session(run:run,plan:plan,execution:execution,birds:try plan.participants.map{try XCTUnwrap(e.bird($0))})
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
        XCTAssertFalse(s.birds.contains(where:{$0.isSideHopping}),file:file,line:line)
    }
    private func poses(_ e:BehaviorEngine,_ s:Session) throws -> [BirdRenderState] {
        try s.plan.participants.map {id in try XCTUnwrap(e.renderSnapshot().first{$0.id==id})}
    }
    private func reachContact(_ e:BehaviorEngine,_ s:Session) throws {
        for _ in 0..<90 {
            if s.birds[0].state == .perched,!s.birds[0].isSideHopping,
               Geometry.distance(s.birds[0].position,s.plan.contactPoint)<0.001 {return}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Helper must settle at the contact anchor before grooming")
        throw NSError(domain:"AllopreeningTests",code:2)
    }

    func testSupportedSpeciesAndRequiredFramesAreDedicatedToGivingAndReceiving() {
        XCTAssertEqual(AllopreeningBehavior.supportedSpecies,[.barnSwallow,.swinhoesWhiteEye])
        XCTAssertEqual(AllopreeningBehavior.contactSeparation,24)
        XCTAssertEqual(AllopreeningPlan.requiredFrames,frames)
        for frame in frames {
            let e=fixture();var world=e.world;world.availableFrames[.barnSwallow]?.remove(frame);e.updateWorld(world)
            XCTAssertTrue(AllopreeningPlan.candidates(in:e,source:.preview).isEmpty,frame)
        }
    }

    func testBothSpeciesAndDirectionsUseRealSmoothHopsAndReturnBothOriginalAnchors() throws {
        for species:SpeciesID in [.barnSwallow,.swinhoesWhiteEye] {
            for scale:CGFloat in [0.75,1,2] {
                for mirrored in [false,true] {
                    let e=fixture(species:[species,species],scale:scale,mirrored:mirrored),s=try start(e)
                    let helper=s.birds[0],recipient=s.birds[1],initialCounts=s.birds.map(\.landedCount)
                    let initialFractions=s.birds.map(\.fraction),initialPositions=s.birds.map(\.position)
                    XCTAssertTrue(helper.isSideHopping);XCTAssertEqual(helper.state,.flying)
                    XCTAssertEqual(recipient.state,.perched)
                    var observed=Set<String>(),last=helper.position,minY=last.y,contactTicks=0
                    var outgoing=false,returning=false
                    for _ in 0..<420 {
                        guard terminals(e,s.run).isEmpty else {break}
                        let rendering=try poses(e,s)
                        for (index,pose) in rendering.enumerated() {
                            XCTAssertEqual(pose.hopOffset,0)
                            XCTAssertEqual(pose.facingRight,s.birds[index].position.x<s.birds[1-index].position.x)
                            XCTAssertTrue(pose.frameName.hasPrefix(index==0 ? "allopreenGive":"allopreenReceive"))
                            observed.insert(pose.frameName)
                        }
                        XCTAssertEqual(recipient.position,initialPositions[1]);XCTAssertEqual(recipient.fraction,initialFractions[1])
                        XCTAssertFalse(recipient.needsDestination)
                        if helper.isSideHopping {
                            XCTAssertEqual(rendering[0].frameName,"allopreenGive0")
                            XCTAssertEqual(rendering[1].frameName,"allopreenReceive0")
                            if helper.landedCount==initialCounts[0] {outgoing=true}
                            if helper.landedCount>initialCounts[0] {returning=true}
                        }
                        if helper.state == .perched,abs(helper.position.x-recipient.position.x)<25*s.plan.scale {
                            contactTicks+=1
                            XCTAssertEqual(abs(helper.position.x-recipient.position.x),24*s.plan.scale,accuracy:0.001)
                            XCTAssertEqual(helper.flightSpeed,0)
                        }
                        e.advance(BehaviorEngine.step)
                        XCTAssertLessThanOrEqual(Geometry.distance(last,helper.position),12*s.plan.scale)
                        minY=min(minY,helper.position.y);last=helper.position
                    }
                    released(e,s,type:.completed)
                    XCTAssertTrue(outgoing);XCTAssertTrue(returning)
                    XCTAssertGreaterThanOrEqual(contactTicks,216)
                    XCTAssertLessThan(minY,initialPositions[0].y-0.95*Bird.sideHopRise(scale:s.plan.scale))
                    XCTAssertTrue(Set(["allopreenGive0","allopreenGive1","allopreenGive2",
                        "allopreenReceive0","allopreenReceive1","allopreenReceive2"]).isSubset(of:observed))
                    for index in 0..<2 {
                        XCTAssertLessThan(Geometry.distance(s.birds[index].position,initialPositions[index]),0.001)
                        XCTAssertEqual(s.birds[index].fraction,initialFractions[index],accuracy:0.000001)
                        XCTAssertEqual(s.birds[index].state,.perched);XCTAssertFalse(s.birds[index].needsDestination)
                    }
                    XCTAssertEqual(helper.landedCount,initialCounts[0]+2)
                    XCTAssertEqual(recipient.landedCount,initialCounts[1])
                    advance(e,seconds:0.5);XCTAssertEqual(terminals(e,s.run).count,1)
                }
            }
        }
    }

    func testContactAnimationHasPausesAndBirdTicksAloneMoveTheFeet() throws {
        let e=fixture(),s=try start(e),origin=s.birds.map(\.position)
        s.execution.start(in:e)
        for _ in 0..<3 {XCTAssertNil(s.execution.validate(in:e));_ = s.execution.presentation(for:s.plan.participants[0],in:e)}
        XCTAssertEqual(s.birds.map(\.position),origin)
        try reachContact(e,s)
        var contactFrames:[String]=[]
        for _ in 0..<100 {
            contactFrames.append(try poses(e,s)[0].frameName)
            e.advance(BehaviorEngine.step)
        }
        var longest=0,current=0
        for frame in contactFrames {
            current=frame == "allopreenGive0" ? current+1:0;longest=max(longest,current)
        }
        XCTAssertGreaterThanOrEqual(longest,20,"Each rotation includes a visible neutral pause")
        XCTAssertTrue(contactFrames.contains("allopreenGive1"));XCTAssertTrue(contactFrames.contains("allopreenGive2"))
        advance(e,seconds:s.plan.duration);released(e,s,type:.completed)
    }

    func testOneReservationIncludesBothOriginalBodiesAndFullRaisedCorridor() throws {
        let e=fixture(),s=try start(e),slot=try XCTUnwrap(e.runtime.landingReservations.first)
        XCTAssertEqual(slot.bird,s.plan.participants[0]);XCTAssertNotNil(slot.span)
        XCTAssertEqual(slot.headroom,Bird.sideHopRise(scale:s.plan.scale))
        let area=try XCTUnwrap(slot.footprint(in:e))
        for point in s.plan.originalPositions {
            let body=Geometry.landingFootprint(at:point,scale:s.plan.scale)
            XCTAssertTrue(area.contains(body));XCTAssertTrue(area.contains(body.offsetBy(dx:0,dy:-slot.headroom)))
        }
        XCTAssertEqual(s.execution.sweptFootprint(in:e),area)
        let peer=Bird(position:CGPoint(x:900,y:850),fraction:s.plan.originalFractions[1],profile:s.birds[0].profile,random:{0.5})
        let id=e.register(peer),foreign=LandingReservation(bird:id,host:host,fraction:peer.fraction)
        XCTAssertTrue(slot.conflicts(with:foreign,in:e))
        XCTAssertEqual(e.runtime.start(OccupiedSlot(foreign),source:.preview,in:e),.rejected(.noSpace))
        e.runtime.cancel(s.run,reason:.removed,in:e)
    }

    func testCandidateReadsArePureAndPreviewStillRespectsAllGeometry() {
        let e=fixture(),positions=e.birds.map(\.position),fractions=e.birds.map(\.fraction),revisions=e.birds.map(\.motionRevision)
        let ecology=e.birds.map{e.ecology(of:$0)},events=e.events.map(\.sequence)
        let first=AllopreeningPlan.candidates(in:e,source:.preview),second=AllopreeningPlan.candidates(in:e,source:.preview)
        XCTAssertFalse(first.isEmpty);XCTAssertLessThanOrEqual(first.count,4)
        XCTAssertEqual(first.map(\.participants),second.map(\.participants))
        XCTAssertEqual(first.map(\.contactFraction),second.map(\.contactFraction))
        XCTAssertEqual(e.birds.map(\.position),positions);XCTAssertEqual(e.birds.map(\.fraction),fractions)
        XCTAssertEqual(e.birds.map(\.motionRevision),revisions);XCTAssertEqual(e.birds.map{e.ecology(of:$0)},ecology)
        XCTAssertEqual(e.events.map(\.sequence),events);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        let untouched=fixture()
        XCTAssertEqual(e.random.unit(),untouched.random.unit());XCTAssertEqual(e.ecologyRandom.unit(),untouched.ecologyRandom.unit())
        for gap:CGFloat in [50,94,135,145,180] {XCTAssertTrue(AllopreeningPlan.candidates(in:fixture(gap:gap),source:.preview).isEmpty)}
        XCTAssertFalse(AllopreeningPlan.candidates(in:fixture(gap:96),source:.preview).isEmpty)
        XCTAssertFalse(AllopreeningPlan.candidates(in:fixture(gap:133),source:.preview).isEmpty)
        XCTAssertTrue(AllopreeningPlan.candidates(in:fixture(species:[.barnSwallow,.swinhoesWhiteEye]),source:.preview).isEmpty)
        XCTAssertTrue(AllopreeningPlan.candidates(in:fixture(species:[.treeSparrow,.treeSparrow]),source:.preview).isEmpty)
        XCTAssertTrue(AllopreeningPlan.candidates(in:fixture(dwell:0.4),source:.preview).isEmpty)
    }

    func testUnstableAnchorsShortDwellDifferentHostsAndOwnedBirdsCannotStart() throws {
        for mutation in ["shortPerch","offset","ground","side","differentHost","busy","transient","needsDestination","idleHop"] {
            let e=fixture(),bird=e.birds[1];var world=e.world
            switch mutation {
            case "shortPerch":bird.perchDuration=bird.stateTime+AllopreeningPlan.duration+0.5
            case "offset":bird.position.x+=1
            case "ground":
                let ground=Surface(id:99,rect:host.rect,isGround:true);world.surfaces=[ground]
                for bird in e.birds {bird.perch(on:ground,spriteScale:e.spriteScale(for:bird))}
                advance(e,seconds:0.5)
            case "side":bird.edge = .left
            case "differentHost":
                let other=Surface(id:99,pid:host.pid,rect:host.rect);world.surfaces.append(other)
                bird.perch(on:other,spriteScale:e.spriteScale(for:bird));advance(e,seconds:0.5)
            case "busy":
                let id=try XCTUnwrap(e.id(of:bird))
                _=e.runtime.start(OccupiedSlot(LandingReservation(bird:id,host:host,fraction:bird.fraction)),source:.preview,in:e)
            case "transient":
                e.removeRecord(try XCTUnwrap(e.id(of:bird)));e.register(bird,role:.transient)
            case "needsDestination":bird.requestFlightRecovery()
            default:
                let jumping=fixture(species:[.swinhoesWhiteEye,.swinhoesWhiteEye],dwell:1.2)
                XCTAssertTrue(jumping.birds.contains{abs($0.hopOffset)>0.001})
                XCTAssertTrue(AllopreeningPlan.candidates(in:jumping,source:.preview).isEmpty);continue
            }
            e.updateWorld(world)
            XCTAssertTrue(AllopreeningPlan.candidates(in:e,source:.preview).isEmpty,mutation)
        }
    }

    func testPlanningCapsOutputAtFourAndDoesNotSearchPastTwelvePairsOrSixteenBirds() {
        let e=fixture(),profile=e.birds[0].profile,size=e.spriteScale(for:e.birds[0])
        for x:CGFloat in [450,450+120*size] {
            let bird=Bird(position:.zero,fraction:fraction(at:x,on:host),profile:profile,random:{0.5})
            bird.perch(on:host,spriteScale:size);bird.perchDuration=600;e.register(bird)
        }
        advance(e,seconds:0.6)
        XCTAssertEqual(AllopreeningPlan.candidates(in:e,source:.preview).count,4)
        for count in [13,14,17] {
            let bounded=fixture()
            let ledge=Surface(id:host.id,pid:host.pid,rect:CGRect(x:-10000,y:450,width:30000,height:300))
            let desktop=CGRect(x:-12000,y:-400,width:35000,height:1400)
            var world=bounded.world;world.screens=[desktop];world.displays=[desktop];world.surfaces=[ledge]
            world.pointer=CGPoint(x:-11500,y:-300);bounded.updateWorld(world)
            bounded.installFixtureBirds((0..<count).map {index in
                // Only the final bird is within visiting distance of the first.
                let x:CGFloat = index==count-1 ? -5000+120*size:-5000+CGFloat(index)*700
                let bird=Bird(position:.zero,fraction:fraction(at:x,on:ledge),profile:profile,random:{0.5})
                bird.perch(on:ledge,spriteScale:size);bird.perchDuration=600;return bird
            })
            advance(bounded,seconds:0.6)
            let plans=AllopreeningPlan.candidates(in:bounded,source:.preview)
            XCTAssertEqual(plans.count,count==13 ? 2:0,"Candidate search must remain bounded for \(count) residents")
        }
    }

    func testAutomaticNeedsEightQuietSecondsAndSharedCooldownWhilePreviewMayBypassEcology() throws {
        let young=fixture()
        XCTAssertTrue(AllopreeningPlan.candidates(in:young,source:.automatic).isEmpty)
        XCTAssertFalse(AllopreeningPlan.candidates(in:young,source:.preview).isEmpty)
        let calm=fixture(dwell:8.1)
        XCTAssertFalse(AllopreeningPlan.candidates(in:calm,source:.automatic).isEmpty)
        let id=try XCTUnwrap(calm.id(of:calm.birds[0]));calm.perchPlanner.noteClick(id)
        XCTAssertTrue(AllopreeningPlan.candidates(in:calm,source:.automatic).isEmpty)
        XCTAssertFalse(AllopreeningPlan.candidates(in:calm,source:.preview).isEmpty)
        for kind:BehaviorKind in [.allopreening,.travelTogether,.chase,.socialGreeting] {
            let cooled=fixture(dwell:8.1),id=try XCTUnwrap(cooled.id(of:cooled.birds[0]))
            cooled.perchPlanner.didStart(id,kind:kind);cooled.perchPlanner.didFinish(id,kind:kind)
            advance(cooled,seconds:8.1)
            XCTAssertTrue(AllopreeningPlan.candidates(in:cooled,source:.automatic).isEmpty)
            XCTAssertFalse(AllopreeningPlan.candidates(in:cooled,source:.preview).isEmpty)
        }
    }

    func testQuietModeClosesOnlyNewAutomaticOpportunities() throws {
        let e=fixture(dwell:8.1),s=try start(e,source:.automatic)
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings);e.updateWorld(e.world)
        XCTAssertTrue(terminals(e,s.run).isEmpty)
        advance(e,seconds:s.plan.duration+0.5);released(e,s,type:.completed)
        let quiet=fixture(dwell:8.1);settings=quiet.settings;settings.activityRhythm = .quiet;quiet.applySettings(settings)
        XCTAssertTrue(AllopreeningPlan.candidates(in:quiet,source:.automatic).isEmpty)
        XCTAssertFalse(AllopreeningPlan.candidates(in:quiet,source:.preview).isEmpty)
    }

    func testClickEitherBirdDuringApproachContactAndRetreatRecoversHelperOnce() throws {
        for clicked in 0..<2 {
            for elapsed in [0.2,1.4,4.8] {
                let e=fixture(),s=try start(e);advance(e,seconds:elapsed)
                XCTAssertTrue(terminals(e,s.run).isEmpty)
                let before=s.birds.map(\.position)
                var world=e.world;world.pointer=s.birds[clicked].position;world.buttonsDown=true;e.updateWorld(world)
                e.handle(.pointerClick);e.runtime.cancel(s.run,reason:.userInput,in:e)
                released(e,s,type:.cancelled)
                XCTAssertEqual(terminals(e,s.run).first?.reason,.userInput)
                XCTAssertEqual(s.birds.map(\.position),before)
                XCTAssertEqual(s.birds[0].state,.flying);XCTAssertTrue(s.birds[0].needsDestination)
                XCTAssertEqual(s.birds[1].state,.perched);XCTAssertFalse(s.birds[1].needsDestination)
                advance(e,seconds:0.3);XCTAssertEqual(s.birds.map(\.position),before)
            }
        }
    }

    func testContactCancellationEvenWhenPerchedRequestsFlightInsteadOfRestoringStand() throws {
        let e=fixture(),s=try start(e);try reachContact(e,s)
        XCTAssertEqual(s.birds[0].state,.perched);XCTAssertFalse(s.birds[0].isSideHopping)
        let feet=s.birds.map(\.position),revision=s.birds[0].motionRevision
        e.runtime.cancel(s.run,reason:.removed,in:e)
        released(e,s,type:.cancelled)
        XCTAssertEqual(s.birds.map(\.position),feet);XCTAssertGreaterThan(s.birds[0].motionRevision,revision)
        XCTAssertEqual(s.birds[0].state,.flying);XCTAssertTrue(s.birds[0].needsDestination)
        XCTAssertEqual(s.birds[1].state,.perched)
        let recovered=s.birds[0].motionRevision
        s.execution.cancel(.removed,in:e);s.execution.start(in:e)
        XCTAssertNil(s.execution.advance(0.1,in:e));XCTAssertEqual(s.birds[0].motionRevision,recovered)
        XCTAssertEqual(terminals(e,s.run).count,1)
    }

    func testPauseFreezesMotionAndGroomingClocksAndResumeFinishes() throws {
        for contact in [false,true] {
            let e=fixture(),s=try start(e)
            if contact {try reachContact(e,s);advance(e,seconds:0.5)} else {advance(e,seconds:0.15)}
            e.handle(.pause(true))
            let feet=s.birds.map(\.position),times=s.birds.map(\.stateTime),age=e.runtime.runs[s.run]?.age
            let before=try poses(e,s).map(\.frameName)
            e.updateWorld(e.world,sampleDT:0.1);advance(e,seconds:1)
            XCTAssertEqual(s.birds.map(\.position),feet);XCTAssertEqual(s.birds.map(\.stateTime),times)
            XCTAssertEqual(try poses(e,s).map(\.frameName),before);XCTAssertEqual(e.runtime.runs[s.run]?.age,age)
            XCTAssertTrue(terminals(e,s.run).isEmpty)
            e.handle(.pause(false));advance(e,seconds:s.plan.duration+0.5);released(e,s,type:.completed)
        }
    }

    func testPausedHostScreenScaleFrameAndSettingsChangesStillTerminate() throws {
        for mutation in ["move","resize","removeHost","pid","screens","displays","scale","frames","childOff","masterOff"] {
            for contact in [false,true] {
                let e=fixture(),s=try start(e)
                if contact {try reachContact(e,s)} else {advance(e,seconds:0.15)}
                e.handle(.pause(true));let helperFoot=s.birds[0].position
                var world=e.world
                switch mutation {
                case "move":world.surfaces[0].rect.origin.x+=1
                case "resize":world.surfaces[0].rect.size.width+=1
                case "removeHost":world.surfaces=[]
                case "pid":world.surfaces[0]=Surface(id:host.id,pid:99,rect:host.rect)
                case "screens":world.screens[0].size.width-=1
                case "displays":world.displays[0].size.height-=1
                case "scale":world.scale*=1.1
                case "frames":world.availableFrames[.barnSwallow]?.remove("allopreenReceive2")
                case "childOff":var settings=e.settings;settings.allopreeningEnabled=false;e.applySettings(settings)
                default:var settings=e.settings;settings.socialInteractions=false;e.applySettings(settings)
                }
                // Exercise the actual metadata sampling path, including host
                // tracking, rather than only replacing a fixture world.
                e.updateWorld(world,sampleDT:0.1)
                released(e,s,type:mutation.hasSuffix("Off") ? .cancelled:.failed)
                XCTAssertEqual(s.birds[0].position,helperFoot);XCTAssertTrue(s.birds[0].needsDestination)
            }
        }
    }

    func testPointerProtectsFutureCorridorWithAtLeastNinetyScaledPointsAndOneHundredPoints() throws {
        for scale:CGFloat in [0.75,2] {
            for active in [false,true] {
                let e=fixture(scale:scale)
                let plan=try XCTUnwrap(AllopreeningPlan.candidates(in:e,source:.preview).first)
                let area=try XCTUnwrap(plan.sweptFootprint(in:e))
                let s:Session?
                if active {s=try start(e)} else {s=nil}
                let radius=max(100,90*plan.scale)
                var world=e.world;world.pointer=CGPoint(x:area.midX,y:area.minY-radius+1)
                let before=e.birds.map(\.position);e.updateWorld(world)
                if let s {released(e,s,type:.cancelled);XCTAssertEqual(terminals(e,s.run).first?.reason,.pointerNearby)}
                else {XCTAssertTrue(AllopreeningPlan.candidates(in:e,source:.preview).isEmpty)}
                XCTAssertEqual(e.birds.map(\.position),before)
            }
        }
    }

    private func addPeer(_ e:BehaviorEngine,at point:CGPoint) -> Bird {
        let peer=Bird(position:point,fraction:0.5,profile:e.settings.catalog.profile(.barnSwallow),random:{0.5})
        e.register(peer);return peer
    }
    private final class OccupiedSlot:BehaviorExecution {
        let kind:BehaviorKind = .relocate
        let occupiesEncounter=false,runsWhilePaused=false,timeout=30.0
        let landingReservations:[LandingReservation]
        var participants:[BirdID] {landingReservations.map(\.bird)}
        init(_ slot:LandingReservation) {landingReservations=[slot]}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }
    private final class CrossingTraversal:LedgeTraversalExecution {
        let kind:BehaviorKind = .sideHop
        let occupiesEncounter=false,runsWhilePaused=false,timeout=30.0
        let participants:[BirdID],area:CGRect
        init(_ id:BirdID,area:CGRect) {participants=[id];self.area=area}
        func sweptFootprint(in engine:BehaviorEngine) -> CGRect? {area}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }

    func testThirdBirdActualBodyWholeFlightDestinationAndOtherTraversalAreProtected() throws {
        for obstruction in ["body","flight","destination","traversal","thinPanel"] {
            for active in [false,true] {
                let e=fixture(),plan=try XCTUnwrap(AllopreeningPlan.candidates(in:e,source:.preview).first)
                let s:Session?
                if active {s=try start(e)} else {s=nil}
                let middle=CGPoint(x:(plan.originalPositions[0].x+plan.originalPositions[1].x)/2,y:host.rect.minY)
                if obstruction == "thinPanel" {
                    let area=try XCTUnwrap(plan.sweptFootprint(in:e))
                    var world=e.world
                    world.surfaces.insert(Surface(id:99,rect:CGRect(x:middle.x,y:area.minY+1,width:0.01,height:1),layer:1),at:0)
                    e.updateWorld(world)
                } else {
                    let peer=addPeer(e,at:obstruction == "body" ? middle:CGPoint(x:900,y:850))
                    let id=try XCTUnwrap(e.id(of:peer))
                    switch obstruction {
                    case "flight":
                        peer.position=CGPoint(x:middle.x,y:50)
                        peer.fly(to:CGPoint(x:middle.x,y:850),host:nil,arc:0,allowsOrbit:false,random:{0.5})
                        XCTAssertGreaterThan(Geometry.distance(peer.position,middle),200)
                    case "destination":
                        peer.fraction=fraction(at:middle.x,on:host)
                        peer.fly(to:middle,host:host,arc:0,allowsOrbit:false,random:{0.5})
                    case "traversal":
                        let crossing=CrossingTraversal(id,area:CGRect(x:middle.x,y:middle.y-20,width:1,height:1))
                        XCTAssertTrue(e.runtime.start(crossing,source:.preview,in:e).accepted)
                    default:break
                    }
                    e.updateWorld(e.world)
                }
                if let s {
                    XCTAssertEqual(terminals(e,s.run).map(\.type),[.failed])
                    XCTAssertTrue(s.birds[0].needsDestination)
                    XCTAssertEqual(s.birds[1].position,plan.originalPositions[1])
                    XCTAssertFalse(e.runtime.owners.values.contains(s.run));XCTAssertEqual(e.reservedLandingCount,0)
                } else {XCTAssertTrue(AllopreeningPlan.candidates(in:e,source:.preview).isEmpty,obstruction)}
            }
        }
    }

    func testForeignReservationAtEitherEndOrInRaisedCorridorPreventsPlanning() throws {
        for fraction in [CGFloat(0),0.5,1] {
            let e=fixture(),plan=try XCTUnwrap(AllopreeningPlan.candidates(in:e,source:.preview).first)
            let peer=addPeer(e,at:CGPoint(x:900,y:850)),id=try XCTUnwrap(e.id(of:peer))
            let x=plan.originalPositions[0].x+(plan.originalPositions[1].x-plan.originalPositions[0].x)*fraction
            let slot=LandingReservation(bird:id,host:host,fraction:self.fraction(at:x,on:host))
            XCTAssertTrue(e.runtime.start(OccupiedSlot(slot),source:.preview,in:e).accepted)
            XCTAssertTrue(AllopreeningPlan.candidates(in:e,source:.preview).isEmpty)
        }
    }

    func testStalePlanPreflightsBothBirdsWithoutInstallingAPartialHop() throws {
        let e=fixture(),plan=try XCTUnwrap(AllopreeningPlan.candidates(in:e,source:.preview).first)
        let recipient=try XCTUnwrap(e.bird(plan.participants[1]))
        recipient.fly(to:CGPoint(x:900,y:50),host:nil,arc:0,allowsOrbit:false,random:{0.5})
        XCTAssertFalse(plan.canBegin(in:e))
        let before=e.birds.map(\.position),revisions=e.birds.map(\.motionRevision)
        guard case .started(let run)=e.runtime.start(AllopreeningExecution(plan:plan,source:.preview),source:.preview,in:e)
        else {return XCTFail("The reservation is valid; stale motion fails during preflight")}
        XCTAssertFalse(e.birds.contains(where:{$0.isSideHopping}))
        e.updateWorld(e.world)
        XCTAssertEqual(terminals(e,run).map(\.type),[.failed])
        XCTAssertEqual(e.birds.map(\.position),before);XCTAssertEqual(e.birds.map(\.motionRevision),revisions)
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
    }

    func testExternalReplacementOfEitherRouteSurvivesCancellationDuringApproachAndContact() throws {
        for replaced in 0..<2 {
            for contact in [false,true] {
                let e=fixture(),s=try start(e)
                if contact {try reachContact(e,s)} else {advance(e,seconds:0.15)}
                let bird=s.birds[replaced],before=s.birds.map(\.position)
                bird.fly(to:CGPoint(x:900,y:50),host:nil,arc:0,allowsOrbit:false,random:{0.5})
                let revision=bird.motionRevision;e.updateWorld(e.world)
                released(e,s,type:.failed)
                XCTAssertEqual(bird.motionRevision,revision);XCTAssertFalse(bird.needsDestination)
                XCTAssertEqual(s.birds.map(\.position),before)
                if replaced==1 {XCTAssertTrue(s.birds[0].needsDestination)}
                advance(e,seconds:0.15)
                XCTAssertNotEqual(bird.position,before[replaced]);XCTAssertEqual(bird.motionRevision,revision)
            }
        }
    }

    func testRemovalGlobalCancellationAndRepeatedCompletionReleaseExactlyOnce() throws {
        for removed in [0,1,2] {
            let e=fixture(),s=try start(e);try reachContact(e,s)
            if removed<2 {e.handle(.remove(s.plan.participants[removed]))}
            else {e.handle(.cancelAmbient(.shutdown))}
            released(e,s,type:.cancelled)
            e.runtime.cancel(s.run,reason:.removed,in:e);advance(e,seconds:0.5)
            XCTAssertEqual(terminals(e,s.run).count,1)
        }
        let e=fixture(),s=try start(e);advance(e,seconds:s.plan.duration+0.5)
        released(e,s,type:.completed)
        let before=s.birds.map(\.position),revisions=s.birds.map(\.motionRevision)
        s.execution.start(in:e);s.execution.cancel(.removed,in:e);XCTAssertNil(s.execution.advance(0.1,in:e))
        XCTAssertEqual(s.birds.map(\.position),before);XCTAssertEqual(s.birds.map(\.motionRevision),revisions)
        XCTAssertEqual(terminals(e,s.run).count,1)
    }
}
