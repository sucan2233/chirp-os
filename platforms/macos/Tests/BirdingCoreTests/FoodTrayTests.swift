import XCTest
@testable import BirdingCore

final class FoodTrayTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:2000,height:1400)
    private let host=Surface(id:141,pid:42,rect:CGRect(x:200,y:1050,width:400,height:150))
    private let trayPoint=CGPoint(x:1300,y:700)
    // Independent expectations: do not derive required artwork from production.
    private let feeding:Set<String>=["feedLook","feedDown0","feedDown1","feedLift"]
    private let frames:Set<String>=["stand","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7",
        "land0","land1","land2","feedLook","feedDown0","feedDown1","feedLift"]

    private func fixture(species:SpeciesID = .treeSparrow,seed:UInt64=1414,scale:CGFloat=1,
                         settle:Double=0.6,perchDuration:Double=600) -> BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        settings.ambientLeafPlayEnabled=false;settings.foodTrayEnabled=true
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[host],scale:scale,
            pointer:CGPoint(x:20,y:20),availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)})))
        let bird=Bird(position:.zero,fraction:0.5,profile:settings.catalog.profile(species),random:{0.5})
        bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=perchDuration
        e.installFixtureBirds([bird]);advance(e,settle)
        XCTAssertTrue(e.handle(.placeFoodTray(at:trayPoint)).accepted)
        return e
    }
    private func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    private struct Session {
        let run:BehaviorRunID,execution:FoodTrayVisitExecution,bird:Bird
        var plan:FoodTrayVisitPlan {execution.plan}
    }
    private func start(_ e:BehaviorEngine,source:BehaviorSource = .preview) throws -> Session {
        let plan=try XCTUnwrap(FoodTrayVisitPlan.candidates(in:e,source:source).first)
        let bird=try XCTUnwrap(e.bird(plan.id)),actual=bird.position,revision=bird.motionRevision
        let execution=FoodTrayVisitExecution(plan:plan)
        guard case .started(let run)=e.runtime.start(execution,source:source,in:e) else {
            XCTFail("Expected an existing resident to visit the tray")
            throw NSError(domain:"FoodTrayTests",code:1)
        }
        XCTAssertEqual(bird.position,actual);XCTAssertEqual(bird.motionRevision,revision)
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(e.habitatReservationCount,1)
        XCTAssertEqual(e.reservedLandingCount,2);XCTAssertEqual(e.leasedBirdCount,1)
        XCTAssertFalse(e.ambientBusy)
        return Session(run:run,execution:execution,bird:bird)
    }
    private func reach(_ phase:FoodTrayVisitExecution.Phase,in e:BehaviorEngine,session s:Session) throws {
        for _ in 0..<3600 {
            if s.execution.phase==phase {return}
            guard e.runtime.runs[s.run] != nil else {break}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Visit ended before phase \(phase)")
        throw NSError(domain:"FoodTrayTests",code:2)
    }
    private func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID) -> [BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}
    }
    private func released(_ e:BehaviorEngine,_ s:Session,type:BehaviorEventType,
                          file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(terminals(e,s.run).map(\.type),[type],file:file,line:line)
        XCTAssertEqual(e.activeRunCount,0,file:file,line:line);XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line);XCTAssertEqual(e.habitatReservationCount,0,file:file,line:line)
        XCTAssertFalse(s.bird.isCoordinatedFlying,file:file,line:line)
    }

    func testDefinitionAndBothSpeciesRequireRealFeedingStandingFlightAndLandingFrames() {
        XCTAssertEqual(FoodTrayBehavior.supportedSpecies,[.treeSparrow,.spottedDove])
        let definition=BehaviorDefinitions.definition(for:.foodTrayVisit)
        XCTAssertEqual(definition.requiredCapabilities,[.standing,.flight,.landing,.feeding])
        XCTAssertEqual(definition.requiredFrames,frames);XCTAssertFalse(definition.occupiesEncounter)
        XCTAssertFalse(definition.runsWhilePaused)
        for species:SpeciesID in [.treeSparrow,.spottedDove] {
            for missing in frames.sorted() {
                let e=fixture(species:species);var world=e.world
                world.availableFrames[species]?.remove(missing);e.updateWorld(world)
                XCTAssertEqual(e.handle(.foodTrayVisit(.preview)),.rejected(.missingFrames),"\(species): \(missing)")
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.habitatReservationCount,0)
                XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3)
            }
        }
    }

    func testUnsupportedResidentsNeverBecomeVisitorsOrSpawnReplacementBirds() {
        for species:SpeciesID in [.barnSwallow,.swinhoesWhiteEye,.greatSpottedWoodpecker] {
            let e=fixture(species:species),bird=e.birds[0],actual=bird.position
            XCTAssertEqual(e.handle(.foodTrayVisit(.preview)),.rejected(.noSpecies))
            XCTAssertEqual(e.birds.count,1);XCTAssertTrue(e.birds[0] === bird)
            XCTAssertEqual(bird.position,actual);XCTAssertEqual(e.arrivalCount,0)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
        let e=fixture(settle:0)
        XCTAssertFalse(e.handle(.foodTrayVisit(.preview)).accepted,"Preview still requires 0.5s of settled time")
        advance(e,0.6);XCTAssertTrue(e.handle(.foodTrayVisit(.preview)).accepted)
    }

    func testPublicRejectionsPreservePausedDisabledMissingArtAndAbsentTrayReasons() {
        let e=fixture();e.handle(.pause(true))
        XCTAssertEqual(e.handle(.foodTrayVisit(.preview)),.rejected(.paused))
        e.handle(.pause(false));var settings=e.settings;settings.foodTrayEnabled=false;e.applySettings(settings)
        XCTAssertEqual(e.handle(.foodTrayVisit(.preview)),.rejected(.disabled))
        settings.foodTrayEnabled=true;e.applySettings(settings)
        XCTAssertEqual(e.handle(.foodTrayVisit(.preview)),.rejected(.noSpace))
        var world=e.world;world.foodTrayArtAvailable=false;e.updateWorld(world)
        XCTAssertEqual(e.handle(.foodTrayVisit(.preview)),.rejected(.missingFrames))
        XCTAssertEqual(e.handle(.placeFoodTray(at:trayPoint)),.rejected(.missingFrames))
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        XCTAssertEqual(e.habitatReservationCount,0)
    }

    func testBothSpeciesObserveFlyLandFeedOnceAndReallyReturnToOriginalFeet() throws {
        for species:SpeciesID in [.treeSparrow,.spottedDove] {
            for scale:CGFloat in [0.75,1,2] {
                let e=fixture(species:species,scale:scale),s=try start(e),origin=s.bird.position
                let revision=s.bird.motionRevision,started=e.time,identity=ObjectIdentifier(s.bird)
                advance(e,0.7)
                XCTAssertEqual(s.execution.phase,.observe);XCTAssertEqual(s.bird.position,origin)
                XCTAssertEqual(s.bird.motionRevision,revision);XCTAssertEqual(s.bird.state,.perched)
                var observed=Set<String>(),visited=false,returned=false,feedStart:Double?,feedEnd:Double?
                var lastPosition=s.bird.position
                for _ in 0..<3600 {
                    let phase=s.execution.phase
                    if phase == .feed {
                        feedStart=feedStart ?? e.time
                        observed.insert(try XCTUnwrap(e.renderSnapshot().first).frameName)
                        XCTAssertEqual(s.bird.position,trayPoint);XCTAssertEqual(s.bird.state,.perched)
                        XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3)
                        visited=true
                    }
                    if phase == .departure {feedEnd=feedEnd ?? e.time;returned=true}
                    if e.runtime.runs[s.run]==nil {break}
                    XCTAssertEqual(e.habitatReservationCount,1);XCTAssertEqual(e.reservedLandingCount,2)
                    e.advance(BehaviorEngine.step)
                    XCTAssertLessThan(Geometry.distance(lastPosition,s.bird.position),60*scale,"No phase may teleport feet")
                    lastPosition=s.bird.position
                }
                released(e,s,type:.completed)
                XCTAssertTrue(visited);XCTAssertTrue(returned);XCTAssertEqual(observed,feeding)
                XCTAssertEqual(try XCTUnwrap(feedEnd)-XCTUnwrap(feedStart),3.6,accuracy:BehaviorEngine.step*1.1)
                XCTAssertGreaterThan(e.time-started,0.8+3.6)
                XCTAssertEqual(s.bird.position,origin);XCTAssertEqual(s.bird.hostID,host.id)
                XCTAssertEqual(s.bird.state,.perched);XCTAssertEqual(s.bird.fraction,0.5)
                XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,2)
                XCTAssertEqual(e.birds.count,1);XCTAssertEqual(ObjectIdentifier(e.birds[0]),identity)
                XCTAssertEqual(e.arrivalCount,0)
            }
        }
    }

    func testPublicCommandRejectsSecondVisitorWhileBothSlotsAndTrayAreLeased() throws {
        let e=fixture(),s=try start(e)
        for phase:FoodTrayVisitExecution.Phase in [.observe,.approach,.feed,.departure,.settle] {
            try reach(phase,in:e,session:s)
            XCTAssertEqual(e.handle(.foodTrayVisit(.preview)),.rejected(.busy))
            XCTAssertEqual(e.habitatReservationCount,1);XCTAssertEqual(e.reservedLandingCount,2)
            let report=BehaviorReplayReport(engine:e,events:[])
            XCTAssertEqual(report.habitatReservations,1);XCTAssertEqual(report.habitats.count,1)
        }
        advance(e,2);released(e,s,type:.completed)
    }

    func testPauseFreezesEveryPhaseAndObjectLifetimeThenResumesOneConsumption() throws {
        for phase:FoodTrayVisitExecution.Phase in [.observe,.approach,.feed,.departure,.settle] {
            let e=fixture(),s=try start(e);try reach(phase,in:e,session:s)
            e.handle(.pause(true))
            let actual=s.bird.position,age=s.execution.phaseAge,flight=s.bird.coordinatedFlightAge
            let object=RecordedHabitatObjectState(try XCTUnwrap(e.habitatSnapshot().first))
            advance(e,5)
            XCTAssertEqual(s.bird.position,actual);XCTAssertEqual(s.execution.phaseAge,age)
            XCTAssertEqual(s.bird.coordinatedFlightAge,flight)
            XCTAssertEqual(RecordedHabitatObjectState(try XCTUnwrap(e.habitatSnapshot().first)),object)
            XCTAssertTrue(terminals(e,s.run).isEmpty);XCTAssertEqual(e.habitatReservationCount,1)
            e.handle(.pause(false));advance(e,40);released(e,s,type:.completed)
            XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,2)
        }
    }

    func testRemoveAndClearPropsCancelEveryPhaseWithoutMovingActualFeet() throws {
        for phase:FoodTrayVisitExecution.Phase in [.observe,.approach,.feed,.departure,.settle] {
            for command:EngineCommand in [.removeFoodTray,.clearProps] {
                let e=fixture(),s=try start(e);try reach(phase,in:e,session:s)
                let actual=s.bird.position
                e.handle(command);released(e,s,type:.cancelled)
                XCTAssertEqual(s.bird.position,actual);XCTAssertTrue(e.habitatSnapshot().isEmpty)
                if phase == .approach || phase == .feed || phase == .departure {
                    XCTAssertTrue(s.bird.needsDestination,"Recovery starts from the real foot anchor")
                }
                e.handle(command);XCTAssertEqual(terminals(e,s.run).count,1)
            }
        }
    }

    func testInterruptedFeedingNeverConsumesAndCompletedFeedingIsNotConsumedTwice() throws {
        for phase:FoodTrayVisitExecution.Phase in [.observe,.approach,.feed,.departure] {
            let e=fixture(),s=try start(e);try reach(phase,in:e,session:s)
            if phase == .feed {advance(e,1.5)}
            let actual=s.bird.position,before=e.habitatSnapshot().first?.remainingUses
            e.handle(.pointerClick);released(e,s,type:.cancelled)
            XCTAssertEqual(s.bird.position,actual)
            XCTAssertEqual(before,phase == .departure ? 2:3)
            XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,before)
            e.runtime.cancel(s.run,reason:.removed,in:e);advance(e,1)
            XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,before)
            XCTAssertEqual(terminals(e,s.run).count,1)
        }
    }

    func testExpiryRetiresTrayButKeepsVisitorAndBothReservationsUntilReturnCompletes() throws {
        let e=fixture(),s=try start(e);try reach(.feed,in:e,session:s)
        e.habitatObjects.advance(181);e.advance(BehaviorEngine.step)
        let expired=try XCTUnwrap(e.habitatSnapshot().first)
        XCTAssertTrue(expired.retiring);XCTAssertEqual(expired.remainingLifetime,0)
        XCTAssertEqual(expired.remainingUses,3);XCTAssertEqual(e.habitatReservationCount,1)
        XCTAssertTrue(terminals(e,s.run).isEmpty)
        XCTAssertFalse(e.handle(.foodTrayVisit(.preview)).accepted)
        advance(e,30);released(e,s,type:.completed)
        XCTAssertTrue(e.habitatSnapshot().isEmpty);XCTAssertEqual(s.bird.position,s.plan.originFoot)
    }

    func testThirdCompletedFeedRetiresObjectDuringReturnAndRemovesAfterFinalSettle() throws {
        let e=fixture()
        for portion in 1...3 {
            let s=try start(e);try reach(.departure,in:e,session:s)
            let tray=try XCTUnwrap(e.habitatSnapshot().first)
            XCTAssertEqual(tray.remainingUses,3-portion);XCTAssertEqual(tray.retiring,portion==3)
            XCTAssertEqual(e.habitatReservationCount,1);XCTAssertEqual(e.reservedLandingCount,2)
            advance(e,30);released(e,s,type:.completed)
            if portion<3 {
                XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3-portion)
                XCTAssertEqual(s.bird.position,s.plan.originFoot)
            }
        }
        XCTAssertTrue(e.habitatSnapshot().isEmpty)
        XCTAssertEqual(e.handle(.foodTrayVisit(.preview)),.rejected(.noSpace))
    }

    func testSettingsFramesArtScreensAndClickValidationReleaseEveryPhaseWithoutSnapping() throws {
        for phase:FoodTrayVisitExecution.Phase in [.observe,.approach,.feed,.departure,.settle] {
            for cause in ["setting","frames","art","screens","displays","scale","host","buttons"] {
                let e=fixture(),s=try start(e);try reach(phase,in:e,session:s)
                let actual=s.bird.position;var world=e.world
                switch cause {
                case "setting":var settings=e.settings;settings.foodTrayEnabled=false;e.applySettings(settings)
                case "frames":world.availableFrames[.treeSparrow]?.remove("feedDown1");e.updateWorld(world)
                case "art":world.foodTrayArtAvailable=false;e.updateWorld(world)
                case "screens":world.screens[0].size.height-=1;e.updateWorld(world)
                case "displays":world.displays[0].origin.x+=1;e.updateWorld(world)
                case "scale":world.scale*=1.1;e.updateWorld(world)
                case "host":world.surfaces.removeAll{$0.id==host.id};e.updateWorld(world,sampleDT:0.1)
                default:world.buttonsDown=true;e.updateWorld(world)
                }
                XCTAssertEqual(s.bird.position,actual,cause)
                XCTAssertEqual(terminals(e,s.run).count,1,cause)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                XCTAssertEqual(e.habitatReservationCount,0);XCTAssertEqual(e.reservedLandingCount,0)
                XCTAssertFalse(s.bird.isCoordinatedFlying)
            }
        }
    }

    func testQuietClosesAutomaticVisitButAllowsActiveJourneyToFinishAndManualPreview() throws {
        let e=fixture(settle:10),s=try start(e,source:.automatic)
        var settings=e.settings;settings.activityRhythm = .quiet;e.applySettings(settings)
        XCTAssertTrue(terminals(e,s.run).isEmpty);advance(e,40);released(e,s,type:.completed)
        XCTAssertEqual(e.handle(.foodTrayVisit(.automatic)),.rejected(.disabled))
        XCTAssertTrue(e.handle(.foodTrayVisit(.preview)).accepted)
    }

    func testPanelOccludingReturnedHomeDuringSettleRecoversFromActualFeet() throws {
        let e=fixture(),s=try start(e);try reach(.settle,in:e,session:s)
        XCTAssertEqual(s.bird.state,.perched);XCTAssertNotNil(e.runtime.runs[s.run])
        XCTAssertEqual(s.bird.position,s.plan.originFoot)
        let actual=s.bird.position
        var world=e.world
        world.surfaces.insert(Surface(id:149,pid:77,
            rect:Geometry.landingFootprint(at:actual,scale:e.spriteScale(for:s.bird)),layer:1),at:0)
        e.updateWorld(world,sampleDT:0.1)
        XCTAssertEqual(s.bird.position,actual)
        XCTAssertEqual(s.bird.state,.flying);XCTAssertTrue(s.bird.needsDestination)
        released(e,s,type:.failed)
        XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,2)
        advance(e,0.2);XCTAssertEqual(s.bird.position,actual)
        XCTAssertEqual(terminals(e,s.run).count,1)
    }

    func testAutomaticCooldownPreventsAnotherVisitWhileManualPreviewRemainsAvailable() throws {
        let e=fixture(settle:10),s=try start(e,source:.automatic)
        advance(e,40);released(e,s,type:.completed)
        XCTAssertTrue(FoodTrayVisitPlan.candidates(in:e,source:.automatic).isEmpty)
        XCTAssertFalse(FoodTrayVisitPlan.candidates(in:e,source:.preview).isEmpty)
        XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,2)
    }

    func testTimeoutAtActualFlightPositionReleasesAllThreeReservationsExactlyOnce() throws {
        let e=fixture(),s=try start(e);try reach(.approach,in:e,session:s);advance(e,0.3)
        let actual=s.bird.position
        e.runtime.advance(s.execution.timeout+1,in:e)
        released(e,s,type:.failed)
        XCTAssertEqual(terminals(e,s.run).first?.reason,.timedOut)
        XCTAssertEqual(s.bird.position,actual);XCTAssertTrue(s.bird.needsDestination)
        XCTAssertEqual(e.habitatSnapshot().first?.remainingUses,3)
        e.runtime.cancel(s.run,reason:.removed,in:e);XCTAssertEqual(terminals(e,s.run).count,1)
    }

    func testNaturalVisitUsesOneQuarterSeedChoiceOnlyAtExistingDepartureAndNeverSpawns() {
        var starts=0,expectedStarts=0
        for seed:UInt64 in 1...64 {
            let e=fixture(seed:seed,settle:19,perchDuration:20),bird=e.birds[0],identity=ObjectIdentifier(bird)
            e.ambientEnabled=true;e.autonomousRouting=true
            advance(e,0.5)
            XCTAssertFalse(e.events.contains{$0.kind == .foodTrayVisit && $0.type == .started})
            let chosen=EngineRandom(seed:seed ^ 0x464F4F4454524159).unit()<0.25
            expectedStarts+=chosen ? 1:0
            advance(e,0.6);e.autonomousRouting=false;advance(e,40)
            let visits=e.events.filter{$0.kind == .foodTrayVisit && $0.type == .started}
            starts+=visits.count
            XCTAssertEqual(visits.count,chosen ? 1:0,"seed \(seed)")
            XCTAssertTrue(visits.allSatisfy{$0.source == .automatic})
            XCTAssertEqual(e.events.filter{$0.kind == .foodTrayVisit && $0.type == .completed}.count,visits.count)
            XCTAssertEqual(e.birds.count,1);XCTAssertEqual(ObjectIdentifier(e.birds[0]),identity)
            XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.habitatReservationCount,0)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        }
        XCTAssertEqual(starts,expectedStarts);XCTAssertGreaterThan(starts,0);XCTAssertLessThan(starts,64)
    }

    func testQuietDisabledMissingArtAndNoDepartureCannotGenerateAutomaticVisits() {
        for mode in ["quiet","disabled","art","noDeparture"] {
            for seed:UInt64 in 1...16 {
                let e=fixture(seed:seed,settle:19,perchDuration:mode=="noDeparture" ? 600:20)
                var settings=e.settings
                if mode=="quiet" {settings.activityRhythm = .quiet;e.applySettings(settings)}
                if mode=="disabled" {settings.foodTrayEnabled=false;e.applySettings(settings)}
                if mode=="art" {var world=e.world;world.foodTrayArtAvailable=false;e.updateWorld(world)}
                e.ambientEnabled=true;e.autonomousRouting=true;advance(e,5)
                XCTAssertFalse(e.events.contains{$0.kind == .foodTrayVisit && $0.type == .started},mode)
                XCTAssertEqual(e.birds.count,1)
            }
        }
    }

    func testNaturalSeedSamplesHaveIdenticalCompleteReportsAtThirtySixtyAndOneHundredTwentyHz() {
        for seed:UInt64 in 1...16 {
            let reports=[30,60,120].map {hz -> BehaviorReplayReport in
                let e=fixture(seed:seed,settle:19,perchDuration:20)
                e.ambientEnabled=true;e.autonomousRouting=true;advance(e,1.1,hz:hz)
                e.autonomousRouting=false;advance(e,40,hz:hz)
                return BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
            }
            XCTAssertEqual(reports[0],reports[1],"seed \(seed)");XCTAssertEqual(reports[1],reports[2],"seed \(seed)")
        }
    }

    private func appendAdvance(_ seconds:Double,to log:inout BehaviorInputLog,in e:BehaviorEngine) {
        var input=RecordedInput.advance(1.0/30,in:e)
        input.repeatCount=Int((seconds*30).rounded());log.inputs.append(input)
    }

    func testBothSpeciesReplayEveryJourneyBoundaryWithObjectAndReservationState() throws {
        for species:SpeciesID in [.treeSparrow,.spottedDove] {
            let source=fixture(species:species)
            var world=source.world;world.surfaces.removeAll{$0.habitatKind != nil}
            var log=BehaviorInputLog(seed:1414,settings:source.settings)
            log.initialWorld=RecordedWorld(world)
            log.fixtureBirds=[RecordedFixtureBird(species:species,host:host.id,fraction:0.5,perchDuration:600,facingRight:true)]
            appendAdvance(0.6,to:&log,in:source)
            log.inputs.append(.command(.placeFoodTray(at:trayPoint)))
            log.inputs.append(.command(.foodTrayVisit(.preview)))
            var references:[BehaviorReplayReport]=[]
            for seconds in [0.4,1.6,2.0,2.0,2.0,8.0] {
                appendAdvance(seconds,to:&log,in:source)
                let reference=try log.replay(callbackHz:60);references.append(reference)
                XCTAssertEqual(try log.replay(callbackHz:30),reference)
                XCTAssertEqual(try log.replay(callbackHz:120),reference)
                XCTAssertEqual(reference.habitats.count,1)
                XCTAssertEqual(reference.habitatReservations,reference.runs==0 ? 0:1)
                XCTAssertEqual(reference.reservations,reference.runs==0 ? 0:2)
            }
            let finished=try XCTUnwrap(references.last)
            XCTAssertEqual(finished.events.filter{$0.kind=="foodTrayVisit" && $0.type=="completed"}.count,1)
            XCTAssertEqual(finished.birds.map(\.state),["perched"])
            XCTAssertEqual(finished.birds.map(\.position.x),[400]);XCTAssertEqual(finished.birds.map(\.position.y),[1050])
            XCTAssertEqual(finished.habitats.first?.remainingUses,2)
            XCTAssertEqual(finished.runs,0);XCTAssertEqual(finished.leases,0)
        }
    }

    func testSharedFoodTrayFixtureCompletesWithPauseAndPersistentObjectAtAllReplayRates() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file=root.appendingPathComponent("shared/behavior-fixtures/v1/food-tray.json")
        let log=try BehaviorInputLog.load(from:file),reference=try log.replay(callbackHz:60)
        XCTAssertEqual(log.simulationVersion,15)
        for hz in [30,120] {XCTAssertEqual(try log.replay(callbackHz:hz),reference)}
        XCTAssertEqual(reference.events.filter{$0.kind=="foodTrayVisit" && $0.type=="completed"}.count,1)
        XCTAssertFalse(reference.events.contains{["cancelled","failed","rejected"].contains($0.type)})
        XCTAssertEqual(reference.birds.map(\.id),["1"])
        XCTAssertEqual(reference.birds.map(\.position.x),[400]);XCTAssertEqual(reference.birds.map(\.position.y),[1050])
        XCTAssertEqual(reference.birds.map(\.state),["perched"])
        XCTAssertEqual(reference.habitats.count,1);XCTAssertEqual(reference.habitats.first?.remainingUses,2)
        XCTAssertFalse(try XCTUnwrap(reference.habitats.first).retiring)
        XCTAssertFalse(reference.hasFoodTrayPlacement);XCTAssertEqual(reference.habitatReservations,0)
        XCTAssertEqual(reference.runs,0);XCTAssertEqual(reference.leases,0);XCTAssertEqual(reference.reservations,0)
    }
}
