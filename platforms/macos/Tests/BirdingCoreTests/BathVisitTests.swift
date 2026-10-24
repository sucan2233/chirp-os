import XCTest
@testable import BirdingCore

final class BathVisitTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:2400,height:1500)
    private let host=Surface(id:911,pid:42,rect:CGRect(x:200,y:1100,width:1800,height:150))
    private let bathPoint=CGPoint(x:1200,y:650)
    private let bathFrames:[String]=["bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise"]
    private var required:Set<String> {
        Set(["stand","shake","land0","land1","land2"]+bathFrames+(0...7).map{"fly\($0)"})
    }
    private enum Stage:CaseIterable {
        case reserved,approach,inspect,touch,lower,wash,rise,shake,departure,settle
    }
    private func fixture(species:SpeciesID = .treeSparrow,scale:CGFloat=1,right:Bool=true,
                         seed:UInt64=911,settle:Double=9)->BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.pointerVisits=true;settings.flockPasses=true;settings.socialInteractions=true
        settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(.init(screens:[display],displays:[display],surfaces:[host],scale:scale,
            pointer:CGPoint(x:20,y:20),availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,required)})))
        let bird=Bird(position:.zero,fraction:right ? 0.15:0.85,profile:settings.catalog.profile(species),random:{0.5})
        bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
        e.installFixtureBirds([bird]);advance(e,settle)
        XCTAssertTrue(e.handle(.placeBath(at:bathPoint)).accepted)
        return e
    }
    private func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    private func started(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line)throws->BehaviorRunID {
        guard case .started(let run)=result else {
            XCTFail("Expected bath run, got \(result)",file:file,line:line)
            throw NSError(domain:"BathVisitTests",code:1)
        }
        return run
    }
    private func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID)->[BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    private func reach(_ stage:Stage,in e:BehaviorEngine,run:BehaviorRunID)throws {
        if stage == .reserved {return}
        let bird=try XCTUnwrap(e.birds.first)
        for _ in 0..<35*60 {
            guard let active=e.runtime.runs[run] else {break}
            let frame=e.renderSnapshot().first?.frameName
            let onBath=e.world.surfaces.first{$0.id==bird.hostID}?.habitatKind == .bath
            let ready:Bool
            switch stage {
            case .reserved:ready=true
            case .approach:ready=bird.state == .flying && onBath
            case .inspect:ready=frame == "bathInspect"
            case .touch:ready=frame == "bathTouch"
            case .lower:ready=frame == "bathLower"
            case .wash:ready=frame == "bath0"
            case .rise:ready=frame == "bathRise"
            case .shake:ready=frame == "shake"
            case .departure:ready=bird.state == .flying && bird.hostID==host.id
            case .settle:ready=bird.state == .perched && bird.hostID==host.id && active.age>5.2
            }
            if ready {return}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Bath never reached \(stage)");throw NSError(domain:"BathVisitTests",code:2)
    }
    private func released(_ e:BehaviorEngine,_ run:BehaviorRunID,type:BehaviorEventType,
                          file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(terminals(e,run).map(\.type),[type],file:file,line:line)
        XCTAssertNil(e.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertEqual(e.habitatReservationCount,0,file:file,line:line)
        XCTAssertFalse(e.ambientBusy,file:file,line:line)
        XCTAssertTrue(e.propSnapshot().isEmpty,file:file,line:line)
        XCTAssertTrue(e.bathImmersionSnapshot().isEmpty,file:file,line:line)
    }

    func testBothSpeciesReallyBatheAndReturnWithExactFrameDurationsMirroredContactAndNoPopulationChange() throws {
        XCTAssertEqual(SpeciesBehaviorProfile.species(for:.bathVisit),[.treeSparrow,.lightVentedBulbul])
        XCTAssertEqual(SpeciesBehaviorProfile.bathFrameNames,bathFrames)
        XCTAssertEqual(BehaviorDefinitions.definition(for:.bathVisit).requiredFrames,required)
        for species:SpeciesID in [.treeSparrow,.lightVentedBulbul] {
            for scale:CGFloat in [0.5,1,2] {
                for right in [false,true] {
                    let e=fixture(species:species,scale:scale,right:right),bird=e.birds[0]
                    let origin=bird.position,id=try XCTUnwrap(e.id(of:bird)),identity=ObjectIdentifier(bird)
                    let object=try XCTUnwrap(e.habitatSnapshot().first),size=e.spriteScale(for:bird)
                    let journal=ObservationJournal();var values:[BehaviorObservation]=[]
                    e.observationObserver={value in
                        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,origin)
                        values.append(value);journal.observe(value,at:Date(timeIntervalSince1970:1_790_000_000))
                    }
                    let run=try started(e.handle(.bathVisit(.preview)))
                    let execution=try XCTUnwrap(e.runtime.runs[run]?.execution as? BathVisitExecution)
                    let maximumSpeed=try XCTUnwrap((execution.plan.approach.route.legs + execution.plan.departure.route.legs)
                        .map{ $0.timing.peakSpeed }.max())
                    XCTAssertEqual(bird.position,origin)
                    XCTAssertEqual(e.runtime.runs[run]?.execution.timeout,35)
                    XCTAssertTrue(e.ambientBusy);XCTAssertEqual(e.habitatReservationCount,1)
                    XCTAssertEqual(e.reservedLandingCount,2)
                    var sequence:[String]=[],ticks:[String:Int]=[:],splashFrames=Set<String>()
                    var splashBirths:[ScenePropID:Double]=[:],splashPreviousFrames:[ScenePropID:String]=[:]
                    var maximumSplashes=0
                    for _ in 0..<35*60 {
                        guard e.runtime.runs[run] != nil else {break}
                        let pose=try XCTUnwrap(e.renderSnapshot().first),frame=pose.frameName
                        XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3,"Safe final landing is the commit boundary")
                        XCTAssertEqual(pose.position,bird.position);XCTAssertEqual(pose.scale,size)
                        XCTAssertTrue(display.contains(pose.rect));XCTAssertTrue(values.isEmpty)
                        if bathFrames.contains(frame) || frame == "shake" {
                            if sequence.last != frame {sequence.append(frame)}
                            ticks[frame,default:0]+=1
                            XCTAssertEqual(bird.position,bathPoint);XCTAssertEqual(pose.hopOffset,0)
                            XCTAssertEqual(pose.facingRight,right)
                            XCTAssertEqual(pose.rect.minY+39*size,bathPoint.y,accuracy:1e-8)
                            if frame == "bathTouch" {
                                let contact=CGPoint(x:pose.rect.minX+(right ? 40:8)*size,y:pose.rect.minY+39*size)
                                XCTAssertEqual(contact.y,object.rect.minY+20*scale,accuracy:1e-8)
                                let water=BathGeometry.waterRect(in:object.rect,scale:scale)
                                XCTAssertTrue(BathGeometry.containsContact(contact,waterRect:water))
                            }
                        }
                        let splashes=e.propSnapshot().filter{$0.kind == .waterSplash}
                        maximumSplashes=max(maximumSplashes,splashes.count);XCTAssertLessThanOrEqual(splashes.count,6)
                        for splash in splashes {
                            // A stable particle slot may host a new finite burst.
                            if splashBirths[splash.id]==nil || (splash.frameName=="splash0" && splashPreviousFrames[splash.id] != "splash0") {
                                splashBirths[splash.id]=e.time
                            }
                            XCTAssertLessThanOrEqual(e.time-(try XCTUnwrap(splashBirths[splash.id])),0.4+BehaviorEngine.step)
                            XCTAssertTrue(["splash0","splash1","splash2","splash3"].contains(splash.frameName))
                            splashFrames.insert(splash.frameName)
                            splashPreviousFrames[splash.id]=splash.frameName
                            XCTAssertGreaterThanOrEqual(splash.opacity,0);XCTAssertLessThanOrEqual(splash.opacity,1)
                        }
                        let before=bird.position,beforeTime=e.time
                        e.advance(BehaviorEngine.step)
                        // Route speed is in world points/second, independent of
                        // sprite size. Allow only the two <.001 route seams.
                        let maximumDisplacement=CGFloat(maximumSpeed*(e.time-beforeTime))+0.002
                        XCTAssertLessThanOrEqual(Geometry.distance(before,bird.position),maximumDisplacement)
                    }
                    released(e,run,type:.completed)
                    XCTAssertEqual(sequence,["bathInspect","bathTouch","bathLower"] +
                        Array(repeating:["bath0","bath1","bath2"],count:3).flatMap{$0} + ["bathRise","shake"])
                    for (frame,seconds) in zip(bathFrames+["shake"],[0.6,0.6,0.4,0.8,0.8,0.8,0.4,0.8]) {
                        XCTAssertEqual(Double(ticks[frame,default:0])*BehaviorEngine.step,seconds,accuracy:BehaviorEngine.step*1.1,frame)
                    }
                    XCTAssertGreaterThan(maximumSplashes,0);XCTAssertEqual(splashFrames,["splash0","splash1","splash2","splash3"])
                    XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.hostID,host.id)
                    XCTAssertEqual(bird.state,.perched);XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,2)
                    XCTAssertEqual(e.sceneFocus?.objectID,object.id);XCTAssertEqual(values.count,1)
                    XCTAssertEqual(values.first?.species,[species]);XCTAssertEqual(values.first?.kind,.bathVisit)
                    XCTAssertEqual(journal.archive.entries.first?.previewCount,1)
                    XCTAssertEqual(e.runtime.owners[id],nil);XCTAssertEqual(e.birds.map(ObjectIdentifier.init),[identity])
                    XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                }
            }
        }
    }

    func testAllRequiredFramesIncludingShakeRefuseBeforeStartAndUnsupportedSpeciesNeverGainBathPermission() throws {
        for species:SpeciesID in [.treeSparrow,.lightVentedBulbul] {
            for missing in required.sorted()+["manifest","basin"] {
                let e=fixture(species:species),bird=e.birds[0],origin=bird.position,revision=bird.motionRevision
                var world=e.world
                if missing == "manifest" {world.availableFrames=[:]}
                else if missing == "basin" {world.bathArtAvailable=false}
                else {world.availableFrames[species]?.remove(missing)}
                e.updateWorld(world)
                XCTAssertEqual(e.handle(.bathVisit(.preview)),.rejected(.missingFrames),missing)
                XCTAssertEqual(bird.position,origin);XCTAssertEqual(bird.motionRevision,revision)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                XCTAssertFalse(e.events.contains{$0.kind == .bathVisit && $0.type == .started})
            }
        }
        for species in SpeciesID.allCases where ![SpeciesID.treeSparrow,.lightVentedBulbul].contains(species) {
            let e=fixture(species:species),bird=e.birds[0],origin=bird.position
            XCTAssertEqual(e.handle(.bathVisit(.preview)),.rejected(.noSpecies))
            XCTAssertEqual(e.birds.count,1);XCTAssertEqual(bird.position,origin);XCTAssertEqual(e.arrivalCount,0)
        }
    }

    func testThreeRealSuccessesConsumeOnceOnlyAfterSafeReturnAndReleaseFocusOnTheThird() throws {
        let e=fixture(),bird=e.birds[0],object=try XCTUnwrap(e.habitatSnapshot().first)
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        for visit in 1...3 {
            let run=try started(e.handle(.bathVisit(.preview)))
            try reach(.departure,in:e,run:run)
            XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,4-visit)
            XCTAssertEqual(observations.count,visit-1)
            advance(e,20);released(e,run,type:.completed)
            XCTAssertFalse(e.habitatObjects.completeVisit(object.id,runID:run),"A repeated completion cannot consume again")
            XCTAssertEqual(observations.count,visit);XCTAssertEqual(bird.state,.perched)
            e.runtime.cancel(run,reason:.removed,in:e)
            XCTAssertEqual(terminals(e,run).count,1)
            if visit<3 {
                XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3-visit)
                advance(e,9)
            }
        }
        XCTAssertTrue(e.habitatSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
        XCTAssertEqual(e.handle(.bathVisit(.preview)),.rejected(.noSpace))
        XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0)
    }

    func testQuietSettlingDisturbanceAndAutomaticCooldownRemainRealAdmissionRequirements() throws {
        for source:BehaviorSource in [.preview,.automatic] {
            let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
            let rhythm=try XCTUnwrap(e.perchPlanner.rhythms[id])
            e.ambientEnabled=true
            rhythm.quietTime=7.99
            XCTAssertTrue(BathVisitPlan.candidates(in:e,source:source).isEmpty)
            rhythm.quietTime=8;rhythm.disturbance=0.35
            XCTAssertTrue(BathVisitPlan.candidates(in:e,source:source).isEmpty)
            rhythm.disturbance=0.349
            XCTAssertFalse(BathVisitPlan.candidates(in:e,source:source).isEmpty)
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird))
            XCTAssertTrue(BathVisitPlan.candidates(in:e,source:source).isEmpty)
            bird.tick(1)
            XCTAssertFalse(BathVisitPlan.candidates(in:e,source:source).isEmpty)
            rhythm.cooldowns[.bathVisit]=45
            XCTAssertEqual(BathVisitPlan.candidates(in:e,source:source).isEmpty,source == .automatic)
        }
        let e=fixture();e.ambientEnabled=true
        let run=try started(e.handle(.bathVisit(.automatic)))
        e.ambientEnabled=false;advance(e,35);released(e,run,type:.completed)
        e.ambientEnabled=true
        XCTAssertFalse(e.handle(.bathVisit(.automatic)).accepted)
        XCTAssertTrue(e.handle(.bathVisit(.preview)).accepted,"Manual preview bypasses automatic cooldown only")
    }

    func testExpiryDuringBathCancelsWithoutConsumptionReleasesFocusAndRecoversWithinTwoLiveSeconds() throws {
        for paused in [false,true] {
            let e=fixture(),bird=e.birds[0],run=try started(e.handle(.bathVisit(.preview)))
            try reach(.wash,in:e,run:run)
            let object=try XCTUnwrap(e.habitatSnapshot().first),actual=bird.position
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            if paused {e.handle(.pause(true))}
            e.habitatObjects.advance(301)
            // Metadata validation must observe expiry without waiting for Bird.tick.
            e.updateWorld(e.world)
            XCTAssertEqual(bird.position,actual)
            XCTAssertEqual(terminals(e,run).count,1);XCTAssertNotEqual(terminals(e,run).first?.type,.completed)
            XCTAssertEqual(e.habitatReservationCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(e.reservedLandingCount,0);XCTAssertNil(e.sceneFocus)
            XCTAssertTrue(e.propSnapshot().isEmpty);XCTAssertTrue(observations.isEmpty)
            XCTAssertFalse(e.habitatObjects.completeVisit(object.id,runID:run))
            if paused {
                XCTAssertTrue(e.habitatSnapshot().isEmpty)
                XCTAssertNil(bird.hostID);XCTAssertTrue(bird.needsDestination)
                advance(e,5);XCTAssertEqual(bird.position,actual)
                e.handle(.pause(false))
            }
            advance(e,2.1)
            XCTAssertFalse(e.habitatSnapshot().contains{$0.id==object.id})
            XCTAssertFalse(e.world.surfaces.contains{$0.habitatKind == .bath})
            XCTAssertFalse(bird.needsDestination,"Recovery must choose an existing destination or bounded departure")
            advance(e,15);XCTAssertTrue(observations.isEmpty);XCTAssertEqual(terminals(e,run).count,1)
        }
    }

    func testClearLeafLeavesBathRunWaterSplashesAndFocusIntact() throws {
        let e=fixture(),run=try started(e.handle(.bathVisit(.preview)))
        try reach(.wash,in:e,run:run)
        // Pose sampling tolerates a tiny phase-boundary epsilon; a particle
        // starts only at its actual nonnegative birth age.
        for _ in 0..<6 where e.propSnapshot().isEmpty {e.advance(BehaviorEngine.step)}
        let bird=e.birds[0],actual=bird.position,age=e.runtime.runs[run]?.age
        let before=e.propSnapshot().map(RecordedPropState.init),focus=e.sceneFocus
        XCTAssertFalse(before.isEmpty)
        XCTAssertTrue(e.propSnapshot().allSatisfy{$0.kind == .waterSplash})
        e.handle(.clearLeaf)
        XCTAssertEqual(bird.position,actual);XCTAssertEqual(e.runtime.runs[run]?.age,age)
        XCTAssertEqual(e.propSnapshot().map(RecordedPropState.init),before)
        XCTAssertEqual(e.sceneFocus,focus);XCTAssertTrue(terminals(e,run).isEmpty)
        advance(e,30);released(e,run,type:.completed)
        XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,2)
    }

    func testPausedBathDeletionThenUserRelocationRetainsTheNewOwnerAndRouteOnResume() throws {
        let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
        let bath=try started(e.handle(.bathVisit(.preview)))
        try reach(.wash,in:e,run:bath)
        e.handle(.pause(true));let actual=bird.position
        e.handle(.removeBath);released(e,bath,type:.cancelled)
        XCTAssertNil(bird.hostID);XCTAssertTrue(bird.needsDestination)
        XCTAssertTrue(e.habitatSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
        let relocation=try started(e.handle(.relocate(id))),revision=bird.motionRevision
        XCTAssertEqual(bird.position,actual);XCTAssertEqual(e.runtime.owners[id],relocation)
        // Relocation keeps its historical permission to move while paused.
        advance(e,0.1);XCTAssertNotEqual(bird.position,actual)
        XCTAssertEqual(bird.motionRevision,revision)
        e.handle(.pause(false));advance(e,0.1)
        XCTAssertEqual(e.runtime.owners[id],relocation)
        XCTAssertEqual(bird.motionRevision,revision,"Pending bath recovery must not install a second route")
        advance(e,30)
        XCTAssertEqual(terminals(e,relocation).map(\.type),[.completed])
        XCTAssertEqual(terminals(e,bath).map(\.type),[.cancelled])
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.habitatReservationCount,0)
    }

    func testTimeoutAndExternalRouteReplacementAreFailuresWithoutConsumptionOrOverwritingRecovery() throws {
        for timeout in [false,true] {
            let e=fixture(),bird=e.birds[0],run=try started(e.handle(.bathVisit(.preview)))
            try reach(.wash,in:e,run:run);let actual=bird.position
            var revision=bird.motionRevision
            if timeout {e.runtime.advance(36,in:e)}
            else {
                bird.fly(to:CGPoint(x:1700,y:1000),host:host,arc:0,allowsOrbit:false,random:{0.5})
                revision=bird.motionRevision;e.updateWorld(e.world)
            }
            released(e,run,type:.failed)
            XCTAssertEqual(terminals(e,run).first?.reason,timeout ? .timedOut:.targetInvalid)
            XCTAssertEqual(bird.position,actual);XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3)
            if !timeout {XCTAssertEqual(bird.motionRevision,revision)}
            advance(e,0.2);XCTAssertNotEqual(bird.position,actual)
            if !timeout {XCTAssertEqual(bird.motionRevision,revision)}
            XCTAssertEqual(terminals(e,run).count,1)
        }
    }

    func testBothSpeciesCompletionAndPausedRemovalMatchAtThirtySixtyAndOneHundredTwentyHz() throws {
        struct Trace:Equatable {
            let birds:[RecordedBirdState],props:[RecordedPropState],objects:[RecordedHabitatObjectState]
            let events:[RecordedEvent],counts:[Int],focus:SceneFocus?,remaining:Double
        }
        func replay(_ species:SpeciesID,_ hz:Int,_ cancel:Bool)throws->[Trace] {
            let e=fixture(species:species),run=try started(e.handle(.bathVisit(.preview)))
            var observations:[BehaviorObservation]=[],trace:[Trace]=[]
            e.observationObserver={observations.append($0)}
            for sample in 0..<350 {
                if sample==70 {e.handle(.pause(true))}
                if sample==75,cancel {e.handle(.removeBath)}
                if sample==80 {e.handle(.pause(false))}
                advance(e,0.1,hz:hz)
                trace.append(Trace(birds:e.renderSnapshot().map{RecordedBirdState($0,engine:e)},
                    props:e.propSnapshot().map(RecordedPropState.init),objects:e.habitatSnapshot().map(RecordedHabitatObjectState.init),
                    events:e.events.map(RecordedEvent.init),counts:[e.activeRunCount,e.leasedBirdCount,e.reservedLandingCount,
                        e.habitatReservationCount,e.residentCount,e.arrivalCount,e.departureCount,observations.count],
                    focus:e.sceneFocus,remaining:e.scheduler.remaining))
            }
            XCTAssertEqual(terminals(e,run).map(\.type),[cancel ? .cancelled:.completed])
            XCTAssertEqual(observations.count,cancel ? 0:1)
            return trace
        }
        for species:SpeciesID in [.treeSparrow,.lightVentedBulbul] {
            for cancel in [false,true] {
                let reference=try replay(species,60,cancel)
                XCTAssertEqual(try replay(species,30,cancel),reference)
                XCTAssertEqual(try replay(species,120,cancel),reference)
            }
        }
    }

    func testPauseFreezesEveryBathStageLifetimeSchedulerAndParticlesThenStillCompletesExactlyOnce() throws {
        for stage in Stage.allCases {
            let e=fixture(),bird=e.birds[0],run=try started(e.handle(.bathVisit(.preview)))
            try reach(stage,in:e,run:run)
            let before=BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            let clock=e.runtime.runs[run]?.age,flight=bird.coordinatedFlightAge
            e.handle(.pause(true));advance(e,5)
            for _ in 0..<3 {e.updateWorld(e.world);_=e.renderSnapshot();_=e.propSnapshot()}
            let after=BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(after.habitats,before.habitats)
            XCTAssertEqual(after.props,before.props);XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
            XCTAssertEqual(after.sceneCooldownRemaining,before.sceneCooldownRemaining)
            XCTAssertEqual(e.runtime.runs[run]?.age,clock);XCTAssertEqual(bird.coordinatedFlightAge,flight)
            XCTAssertTrue(terminals(e,run).isEmpty)
            XCTAssertEqual(e.handle(.bathVisit(.preview)),.rejected(.paused))
            e.handle(.pause(false));advance(e,35);released(e,run,type:.completed)
            XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,2)
        }
    }

    func testEveryStageCancellationOrInvalidationReleasesImmediatelyAndNeverConsumesOrBecomesDiscovery() throws {
        for stage in Stage.allCases {
            for paused in [false,true] {
                for cause in ["click","relocate","removeBird","clear","clearScene","clearProps","disable","host","display","screens","scale","frames","art","buttons","pointer","sleep","space","shutdown"] {
                    let e=fixture(),bird=e.birds[0],id=try XCTUnwrap(e.id(of:bird))
                    let run=try started(e.handle(.bathVisit(.preview)))
                    try reach(stage,in:e,run:run)
                    if paused {e.handle(.pause(true))}
                    let actual=bird.position
                    var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
                    var replacement:BehaviorRunID?
                    switch cause {
                    case "click":e.handle(.pointerClick)
                    case "relocate":replacement=try started(e.handle(.relocate(id)))
                    case "removeBird":e.handle(.remove(id))
                    case "clear":e.handle(.removeBath)
                    case "clearScene":e.handle(.clearCurrentScene)
                    case "clearProps":e.handle(.clearProps)
                    case "disable":var settings=e.settings;settings.bathEnabled=false;e.applySettings(settings)
                    case "host":var world=e.world;world.surfaces.removeAll{$0.id==host.id};e.updateWorld(world)
                    case "display":var world=e.world;world.displays[0].size.width-=1;e.updateWorld(world)
                    case "screens":var world=e.world;world.screens[0].size.width-=1;e.updateWorld(world)
                    case "scale":var world=e.world;world.scale*=1.1;e.updateWorld(world)
                    case "frames":var world=e.world;world.availableFrames[.treeSparrow]?.remove("shake");e.updateWorld(world)
                    case "art":var world=e.world;world.bathArtAvailable=false;e.updateWorld(world)
                    case "buttons":var world=e.world;world.buttonsDown=true;e.updateWorld(world)
                    case "pointer":var world=e.world;world.pointer=bird.position;e.updateWorld(world)
                    case "sleep":e.handle(.cancelAmbient(.sleep))
                    case "space":e.handle(.cancelAmbient(.spaceChanged))
                    default:e.handle(.cancelAmbient(.shutdown))
                    }
                    XCTAssertEqual(bird.position,actual,"\(stage), \(cause), pause=\(paused)")
                    let terminal=terminals(e,run)
                    XCTAssertEqual(terminal.count,1);XCTAssertNotEqual(terminal.first?.type,.completed)
                    if cause == "frames" {XCTAssertEqual(terminal.first?.reason,.missingFrames)}
                    if cause == "relocate" {XCTAssertEqual(terminal.first?.reason,.replaced)}
                    if cause == "disable" {XCTAssertEqual(terminal.first?.reason,.settingsChanged)}
                    XCTAssertFalse(e.runtime.owners.values.contains(run));XCTAssertEqual(e.habitatReservationCount,0)
                    XCTAssertEqual(e.reservedLandingCount,0);XCTAssertTrue(e.propSnapshot().isEmpty)
                    XCTAssertTrue(e.bathImmersionSnapshot().isEmpty);XCTAssertTrue(observations.isEmpty)
                    if let replacement {XCTAssertEqual(e.runtime.owners[id],replacement)}
                    else {XCTAssertEqual(e.leasedBirdCount,0)}
                    if let object=e.habitatSnapshot().first {XCTAssertEqual(object.remainingUses,3)}
                    let removesScene=["clear","clearScene","clearProps","disable","display","screens","scale","art","sleep","space","shutdown"].contains(cause)
                    if paused && removesScene {
                        XCTAssertTrue(e.habitatSnapshot().isEmpty)
                        XCTAssertFalse(e.world.surfaces.contains{$0.habitatKind == .bath})
                        XCTAssertFalse(bird.hostID.map{hostID in e.world.surfaces.contains{$0.id==hostID && $0.habitatKind == .bath}} ?? false)
                    }
                    e.handle(.pause(false));advance(e,2.1)
                    XCTAssertEqual(terminals(e,run).count,1);XCTAssertTrue(observations.isEmpty)
                    if removesScene {
                        XCTAssertTrue(e.habitatSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
                    }
                    e.handle(.cancelAmbient(.sleep));XCTAssertEqual(e.activeRunCount,0)
                }
            }
        }
    }
}
