import XCTest
@testable import BirdingCore

final class CompanionSceneTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:2400,height:1600)
    private func engine(record:Bool=false)->BehaviorEngine {
        let e=BehaviorEngine(seed:742,settings:.companionDefaults,recordInputs:record)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[Surface(id:1,pid:1,rect:CGRect(x:100,y:900,width:2200,height:500))],pointer:CGPoint(x:10,y:10),displayIDs:["screen"]))
        return e
    }
    private func item(_ kind:SceneItemKind,_ x:Double,_ y:Double,slot:Int=1)->SceneInstance {
        SceneInstance(kind:kind,anchor:FixedPerchAnchor(slot:slot,displayID:"screen",displayFrame:display,x:x/2400,y:y/1600))
    }
    private func apply(_ items:[SceneInstance],to e:BehaviorEngine,file:StaticString=#filePath,line:UInt=#line) {
        var draft=e.beginSceneEditing();draft.edit{$0.instances=items}
        XCTAssertTrue(e.applySceneLayout(draft.layout,baseRevision:draft.baseRevision),e.sceneError ?? "",file:file,line:line)
        XCTAssertEqual(e.sceneEditPhase,.committed,file:file,line:line)
    }
    private func advance(_ e:BehaviorEngine,_ duration:Double) {for _ in 0..<Int(duration*60) {e.advance(1.0/60)}}

    func testMigrationPreservesSourceBoundariesAndIndependentSwitches() throws {
        var legacy=BirdSettings();legacy.activityRhythm = .quiet;legacy.flockPasses=false;legacy.visitorGiftsEnabled=false;legacy.ambientLeafPlayEnabled=false;legacy.ambientFrequency = .high
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(legacy)) as? [String:Any]);json["schemaVersion"]=2
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:json))
        let p=try XCTUnwrap(migrated.companion)
        XCTAssertEqual(p.mode,.focus);XCTAssertTrue(p.manualAdjustmentEnabled)
        XCTAssertEqual(p.legacyCadence,.high)
        XCTAssertFalse(BehaviorDefinitions.definition(for:.bathVisit).isEnabled(settings:migrated,source:.automatic))
        XCTAssertTrue(BehaviorDefinitions.definition(for:.bathVisit).isEnabled(settings:migrated,source:.preview))
        var disabled=migrated;disabled.bathEnabled=false
        XCTAssertFalse(BehaviorDefinitions.definition(for:.bathVisit).isEnabled(settings:disabled,source:.preview))
        disabled.companion?.mode = .lively;disabled.companion?.restoreModeDefaults()
        XCTAssertFalse(disabled.flockPasses);XCTAssertFalse(disabled.visitorGiftsEnabled)
        XCTAssertTrue(p.allows(.leafPlay,source:.preview));XCTAssertFalse(p.allows(.leafPlay,source:.automatic))
    }
    func testIndependentFlockClockSinglePendingAndInputQuiet() {
        for mode in CompanionMode.allCases {
            let scheduler=CompanionOpportunityScheduler(seed:9),policy=CompanionPreferences(mode:mode).policy
            scheduler.configure(policy,flockEnabled:true)
            XCTAssertTrue(policy.flockInterval.contains(scheduler.flockRemaining))
            let first=scheduler.flockRemaining
            scheduler.configure(policy,flockEnabled:true);XCTAssertEqual(first,scheduler.flockRemaining)
            for _ in 0...Int(ceil(first*60)) {_=scheduler.advance(1.0/60,pointer:.zero,buttonsDown:true,cadence:1,flockEnabled:true)}
            XCTAssertNotNil(scheduler.pendingFlockAge)
            scheduler.clicked()
            XCTAssertFalse(scheduler.advance(2,pointer:CGPoint(x:10,y:10),buttonsDown:false,cadence:1,flockEnabled:true).flock)
            XCTAssertTrue(scheduler.advance(1.1,pointer:CGPoint(x:20,y:10),buttonsDown:false,cadence:1,flockEnabled:true).flock)
            scheduler.didStart(.flockPass);XCTAssertNil(scheduler.pendingFlockAge)
            scheduler.configure(policy,flockEnabled:false);XCTAssertNil(scheduler.pendingFlockAge)
        }
    }
    func testMixedInstancesHaveUniqueSurfacesAndDoNotExpireOrRefillOnMove() throws {
        let e=engine(),food=item(.foodTray,500,600),bath=item(.bath,1300,600),nest=item(.nest,1800,900)
        apply([food,bath,nest],to:e)
        XCTAssertEqual(e.habitatSnapshot().count,3)
        XCTAssertEqual(Set(e.habitatObjects.objects.values.map{$0.surface.id}).count,3)
        let tray=try XCTUnwrap(e.habitatObjects.objects.values.first{$0.persistentID==food.id})
        XCTAssertTrue(e.habitatObjects.consume(tray.id));XCTAssertEqual(e.sceneArchive.resources[food.id]?.remainingUses,2)
        e.habitatObjects.advance(3600)
        XCTAssertFalse(e.habitatSnapshot().contains{$0.retiring})
        var moved=food;moved.anchor=item(.foodTray,500,700).anchor;moved.revision+=1
        apply([moved,bath,nest],to:e)
        XCTAssertEqual(e.habitatObjects.objects.values.first{$0.persistentID==food.id}?.remainingUses,2)
        let restored=engine();try restored.restoreScene(e.sceneArchive)
        XCTAssertEqual(restored.habitatSnapshot().count,2)
        XCTAssertTrue(restored.sceneNeedsPlacement.contains(nest.id))
        XCTAssertEqual(restored.sceneArchive.resources[food.id]?.remainingUses,2)
    }
    func testResourceWriteFailureCannotConsumeAndLayoutFailureKeepsLatestLedger() throws {
        let e=engine(),food=item(.foodTray,500,600)
        apply([food],to:e)
        let id=try XCTUnwrap(e.habitatObjects.objects.keys.first)
        e.sceneWriter={_ in throw SceneError.invalid("injected disk failure")}
        XCTAssertFalse(e.habitatObjects.consume(id));XCTAssertEqual(e.habitatObjects.objects[id]?.remainingUses,3)
        e.sceneWriter=nil;XCTAssertTrue(e.habitatObjects.consume(id))
        let previous=e.sceneArchive
        var draft=e.beginSceneEditing();draft.edit{$0.instances[0].anchor=self.item(.foodTray,1000,600).anchor;$0.instances[0].revision+=1}
        e.sceneWriter={_ in throw SceneError.invalid("injected disk failure")}
        XCTAssertFalse(e.applySceneLayout(draft.layout,baseRevision:draft.baseRevision))
        XCTAssertEqual(e.sceneEditPhase,.failed);XCTAssertEqual(e.sceneArchive,previous)
        XCTAssertEqual(e.habitatObjects.objects[id]?.remainingUses,2)
        e.cancelSceneEditing();XCTAssertFalse(e.sceneEditing)
    }
    func testPausedEditWithoutOccupantsCommitsAndOccupiedEditRetainsDraft() throws {
        let e=engine(),bath=item(.bath,1200,600)
        e.handle(.pause(true));apply([bath],to:e);XCTAssertTrue(e.paused)
        let object=try XCTUnwrap(e.habitatObjects.objects.values.first)
        let bird=Bird(position:object.foot,fraction:0.5,profile:e.settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:object.surface,spriteScale:e.spriteScale(for:bird));_=e.register(bird)
        var draft=e.beginSceneEditing();draft.edit{$0.instances=[]}
        XCTAssertFalse(e.applySceneLayout(draft.layout,baseRevision:draft.baseRevision))
        XCTAssertTrue(e.sceneError?.contains("继续动画") == true);XCTAssertEqual(e.sceneArchive.layout.instances.count,1)
        let position=bird.position;advance(e,2);XCTAssertEqual(bird.position,position)
        e.handle(.pause(false));XCTAssertTrue(e.applySceneLayout(draft.layout,baseRevision:draft.baseRevision),e.sceneError ?? "")
        advance(e,20)
        XCTAssertEqual(e.sceneEditPhase,.committed,e.sceneError ?? "")
        XCTAssertTrue(e.sceneArchive.layout.instances.isEmpty);XCTAssertFalse(e.sceneEditing)
    }
    func testRestartNormalizesAttachedWithoutRefundOrReusingSessionRunIDs() throws {
        let e=engine(),nest=item(.nest,1200,900)
        apply([nest],to:e)
        var archive=e.sceneArchive
        archive.resources[nest.id]?.materials=[.attached,.delivered,.arranged]
        archive.resources[nest.id]?.remainingUses=0
        let restored=engine();try restored.restoreScene(archive)
        XCTAssertEqual(restored.sceneArchive.resources[nest.id]?.materials,[.spent,.delivered,.arranged])
        XCTAssertTrue(restored.sceneNeedsPlacement.contains(nest.id))
        var repositioned=nest;repositioned.revision+=1
        apply([repositioned],to:restored)
        let snapshot=try XCTUnwrap(restored.nestSnapshot().first)
        XCTAssertEqual(snapshot.available,0);XCTAssertEqual(snapshot.delivered,1);XCTAssertEqual(snapshot.arranged,1)
        XCTAssertNil(snapshot.reservation);XCTAssertTrue(snapshot.materials.allSatisfy{$0.pickupRunID==nil && $0.reservedByRun==nil})
    }
    func testUndoOnlyChangesLayoutIntentAndMissingDisplayParksObject() throws {
        let e=engine(),food=item(.foodTray,500,600)
        apply([food],to:e)
        var draft=SceneDraft(e.sceneArchive.layout);draft.edit{$0.instances=[]};draft.undo()
        XCTAssertEqual(draft.layout,e.sceneArchive.layout);draft.redo();XCTAssertTrue(draft.layout.instances.isEmpty)
        let archive=e.sceneArchive
        var world=e.world;world.displayIDs=["other"]
        let restored=engine();restored.updateWorld(world);try restored.restoreScene(archive)
        XCTAssertTrue(restored.habitatSnapshot().isEmpty);XCTAssertEqual(restored.sceneArchive.layout.instances,[food])
        restored.updateWorld(e.world);advance(restored,3);XCTAssertEqual(restored.habitatSnapshot().count,1)
    }
    func testAtomicPersistenceRejectsExternalChangesAndCorruptFiles() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("scene.json"),store=ScenePersistence(url:url)
        let empty=try store.load();try store.save(empty)
        let loaded=try ScenePersistence(url:url).load();XCTAssertEqual(loaded,empty)
        try Data("broken".utf8).write(to:url)
        XCTAssertThrowsError(try store.save(empty))
        let corrupt=ScenePersistence(url:url);XCTAssertThrowsError(try corrupt.load());XCTAssertThrowsError(try corrupt.save(empty))
        XCTAssertEqual(try String(contentsOf:url),"broken")
    }
    func testSceneTransactionsAndFailedWritesReplayWithoutDiskAccess() throws {
        let e=engine(record:true),food=item(.foodTray,500,600)
        apply([food],to:e)
        var draft=e.beginSceneEditing();draft.edit{$0.instances=[]}
        e.sceneWriter={_ in throw SceneError.invalid("full disk")}
        XCTAssertFalse(e.applySceneLayout(draft.layout,baseRevision:draft.baseRevision));e.cancelSceneEditing()
        let log=try e.recordedInputs()
        XCTAssertEqual(log.sceneWrites?.map(\.accepted),[true,false])
        XCTAssertEqual(try log.replay(),log.expected)
    }
    func testDirectAutomaticFlockCannotBypassAdmissionOrLeakHiddenBirds() {
        let e=engine();XCTAssertFalse(e.handle(.flockPass(.automatic)).accepted)
        XCTAssertEqual(e.pendingCount,0);XCTAssertEqual(e.passingCount,0)
    }
    func testFlightEpisodeSurvivesReplanningUntilRealSettling() {
        let bird=Bird(position:CGPoint(x:100,y:100),fraction:0.5,random:{0.5})
        bird.fly(to:CGPoint(x:900,y:400),host:nil,allowsOrbit:false,random:{0.5})
        bird.advanceEpisodeClock(7)
        bird.fly(to:CGPoint(x:500,y:500),host:nil,allowsOrbit:false,random:{0.5});bird.advanceEpisodeClock(3)
        XCTAssertEqual(bird.continuousFlightAge,10)
        let host=Surface(id:22,pid:1,rect:CGRect(x:0,y:800,width:2000,height:200))
        bird.perch(on:host);bird.tick(0.6);bird.advanceEpisodeClock(0.1)
        XCTAssertEqual(bird.continuousFlightAge,0)
    }
    func testWindowSupportedSceneParksOnRestartUntilExplicitReposition() throws {
        let e=engine();var leaf=item(.leaf,1200,900);leaf.support = .window
        apply([leaf],to:e)
        XCTAssertEqual(e.carriedObjects.objects.count,1)
        let restored=engine();try restored.restoreScene(e.sceneArchive)
        XCTAssertTrue(restored.sceneNeedsPlacement.contains(leaf.id));XCTAssertTrue(restored.carriedObjects.objects.isEmpty)
        XCTAssertEqual(restored.previewSceneInstance(leaf.id),.rejected(.noSpace))
        leaf.revision+=1
        apply([leaf],to:restored)
        XCTAssertFalse(restored.sceneNeedsPlacement.contains(leaf.id));XCTAssertEqual(restored.carriedObjects.objects.count,1)
    }
    func testFiniteLeafEffectCannotGainTimeThroughRepeatedRestartsOrFailedWrites() throws {
        func groundEngine()->BehaviorEngine {
            let e=engine();var world=e.world
            world.surfaces=[Geometry.ground(id:700,display:display,workArea:display.insetBy(dx:0,dy:100))]
            e.updateWorld(world);return e
        }
        let e=groundEngine(),host=e.world.surfaces[0]
        let point=Geometry.foot(on:host,fraction:0.5,edge:.top,scale:CGFloat(e.settings.catalog.profile(.treeSparrow).relativeScale))
        var leaf=item(.leaf,point.x,point.y);leaf.support = .ground
        apply([leaf],to:e)
        var archive=e.sceneArchive
        archive.resources[leaf.id]?.leafConsumed=true
        archive.resources[leaf.id]?.leafEffect=SceneLeafEffect(anchor:leaf.anchor,support:.ground,remaining:6,facingRight:true)
        for expected in [4.0,2.0,0.0] {
            let restored=groundEngine();try restored.restoreScene(archive)
            XCTAssertEqual(restored.carriedObjects.objects.count,1)
            advance(restored,0.1)
            XCTAssertEqual(restored.sceneArchive.resources[leaf.id]?.leafEffect?.remaining,expected)
            archive=restored.sceneArchive
        }
        let exhausted=groundEngine();try exhausted.restoreScene(archive)
        XCTAssertTrue(exhausted.carriedObjects.objects.isEmpty)
        archive.resources[leaf.id]?.leafEffect?.remaining=6
        let denied=groundEngine();try denied.restoreScene(archive)
        denied.sceneWriter={_ in throw SceneError.invalid("disk full")}
        advance(denied,0.5)
        XCTAssertTrue(denied.carriedObjects.objects.isEmpty)
        XCTAssertEqual(denied.sceneArchive.resources[leaf.id]?.leafEffect?.remaining,6)
    }
    func testSelectedFoodTrayPreviewDoesNotConsumeAnotherInstance() throws {
        let e=engine(),first=item(.foodTray,900,500),selected=item(.foodTray,1700,500)
        var settings=e.settings;settings.companion?.mode = .lively;settings.perchActions=false;e.applySettings(settings)
        var world=e.world;world.availableFrames[.treeSparrow]=BehaviorDefinitions.definition(for:.foodTrayVisit).requiredFrames;e.updateWorld(world)
        let bird=Bird(position:.zero,fraction:0.1,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:world.surfaces[0],spriteScale:e.spriteScale(for:bird));bird.perchDuration=3600
        e.installFixtureBirds([bird]);advance(e,1)
        apply([first,selected],to:e)
        XCTAssertTrue(e.previewSceneInstance(selected.id).accepted)
        advance(e,40)
        XCTAssertEqual(e.sceneArchive.resources[first.id]?.remainingUses,3)
        XCTAssertEqual(e.sceneArchive.resources[selected.id]?.remainingUses,2)
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.habitatReservationCount,0)
    }
    func testAutomaticNestCompletesThreeSeparateDeliveriesAndBuilds() throws {
        let e=NestTestSupport.engine(seed:3701)
        var settings=e.settings;settings.companion=CompanionPreferences(mode:.lively)
        settings.companion?.manualAdjustmentEnabled=true;settings.companion?.legacyCadence = .high
        settings.companion?.behaviorDisables=Set(BehaviorDefinitions.all.map(\.kind).filter{!$0.isNestActivity && $0 != .relocate})
        e.applySettings(settings)
        let point=NestTestSupport.point(e)
        let anchor=try XCTUnwrap(FixedPerchAnchor.capture(slot:1,point:point,displayIDs:e.world.displayIDs,displays:e.world.displays))
        let nest=SceneInstance(kind:.nest,anchor:anchor)
        apply([nest],to:e);e.ambientEnabled=true
        for _ in 0..<900*60 {
            if e.sceneArchive.resources[nest.id]?.materials.allSatisfy({$0 == .arranged}) == true {break}
            e.advance(BehaviorEngine.step)
            XCTAssertLessThanOrEqual(e.runtime.runs.values.filter{$0.execution.kind.isSignificant}.count,1)
        }
        advance(e,40)
        XCTAssertEqual(e.sceneArchive.resources[nest.id]?.materials,[.arranged,.arranged,.arranged])
        let finished=e.events.filter{$0.type == .completed && $0.kind?.isNestActivity == true}
        XCTAssertEqual(finished.filter{$0.kind == .nestMaterialCarry}.count,3)
        XCTAssertEqual(finished.filter{$0.kind == .nestBuild}.count,3)
        XCTAssertTrue(finished.allSatisfy{$0.source == .automatic})
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.habitatReservationCount,0)
    }
    func testFlockVisibleDurationAcrossModesAndDisplays() {
        for mode in CompanionMode.allCases {
            for width in [1440.0,2400.0,5120.0] {
                for seed:UInt64 in 0..<4 {
                    var settings=BirdSettings.companionDefaults;settings.companion?.mode=mode
                    let e=BehaviorEngine(seed:seed,settings:settings)
                    e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
                    let screen=CGRect(x:-width,y:-400,width:width,height:1200)
                    e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[],pointer:CGPoint(x:screen.midX,y:600)))
                    XCTAssertTrue(e.handle(.flockPass(.preview)).accepted,"\(mode) / \(width) / \(seed)")
                    var first:Double?,last:Double=0
                    for step in 0..<20*60 {
                        e.advance(BehaviorEngine.step)
                        if e.birds.contains(where:{screen.intersects(e.bounds(of:$0))}) {
                            if first==nil {first=Double(step)/60};last=Double(step)/60
                        }
                    }
                    let duration=last-(first ?? last),range=settings.companion!.policy.flockDuration
                    XCTAssertGreaterThanOrEqual(duration,range.lowerBound-0.15,"\(mode) \(width) \(seed): \(duration)")
                    XCTAssertLessThanOrEqual(duration,range.upperBound+0.15,"\(mode) \(width) \(seed): \(duration)")
                    XCTAssertEqual(e.passingCount,0);XCTAssertEqual(e.activeRunCount,0)
                }
            }
        }
    }
    func testPauseDiscardsFlockPendingAndDragCancelsOnlyWithNearbyBirds() {
        let e=engine();let policy=e.settings.companion!.policy
        e.companionScheduler.configure(policy,flockEnabled:true)
        _=e.companionScheduler.advance(450,pointer:.zero,buttonsDown:false,cadence:1,flockEnabled:true)
        _=e.companionScheduler.advance(450,pointer:.zero,buttonsDown:false,cadence:1,flockEnabled:true)
        e.handle(.pause(true));XCTAssertNil(e.companionScheduler.pendingFlockAge)
        e.handle(.pause(false));XCTAssertTrue(e.handle(.flockPass(.preview)).accepted)
        advance(e,1)
        e.handle(.pointerClick);XCTAssertEqual(e.activeRunCount,1)
        if let bird=e.birds.first {
            var world=e.world;world.pointer=bird.position;world.buttonsDown=true;e.updateWorld(world)
            advance(e,0.1)
            XCTAssertEqual(e.activeRunCount,0)
            advance(e,20);XCTAssertEqual(e.passingCount,0)
        } else {XCTFail("Flock should be visible")}
    }

    func testTwoAutomaticFoodTraysRotateWithinOneSharedOpportunityClock() throws {
        let ids=[UUID(uuidString:"00000000-0000-4000-8000-000000000001")!,
                 UUID(uuidString:"00000000-0000-4000-8000-000000000002")!]
        for reversed in [false,true] {
            let e=engine()
            let first=SceneInstance(id:ids[reversed ? 1:0],kind:.foodTray,anchor:item(.foodTray,900,500).anchor)
            let second=SceneInstance(id:ids[reversed ? 0:1],kind:.foodTray,anchor:item(.foodTray,1700,500).anchor)
            var settings=e.settings;settings.companion?.mode = .lively
            settings.companion?.manualAdjustmentEnabled=true;settings.companion?.legacyCadence = .high
            settings.companion?.behaviorDisables=Set(BehaviorDefinitions.all.map(\.kind).filter{$0 != .foodTrayVisit && $0 != .relocate})
            e.applySettings(settings)
            var world=e.world;world.availableFrames[.treeSparrow]=BehaviorDefinitions.definition(for:.foodTrayVisit).requiredFrames;e.updateWorld(world)
            let bird=Bird(position:.zero,fraction:0.1,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
            bird.perch(on:world.surfaces[0],spriteScale:e.spriteScale(for:bird));bird.perchDuration=3600;e.installFixtureBirds([bird]);advance(e,1)
            apply([first,second],to:e);e.ambientEnabled=true
            // Allow 15 simulated minutes for six shared-clock opportunities and their flights.
            for _ in 0..<900*60 {
                if e.sceneArchive.resources.values.allSatisfy({$0.remainingUses==0}) {break}
                e.advance(BehaviorEngine.step)
                XCTAssertLessThanOrEqual(e.activeRunCount,1)
            }
            // Consumption precedes the return flight; its duration depends on which tray was last.
            // Bound the wait by the remaining execution deadline and require successful completion.
            let remaining=e.runtime.runs.values.map{max(0,$0.execution.timeout-$0.age)}.max() ?? 0
            advance(e,ceil(remaining)+1)
            XCTAssertEqual(e.events.filter{$0.type == .completed && $0.kind == .foodTrayVisit}.count,6)
            XCTAssertEqual(e.activeRunCount,0)
            XCTAssertEqual(e.sceneArchive.resources[first.id]?.remainingUses,0)
            XCTAssertEqual(e.sceneArchive.resources[second.id]?.remainingUses,0)
            XCTAssertEqual(e.companionMetrics.sceneVisits[first.id.uuidString],3)
            XCTAssertEqual(e.companionMetrics.sceneVisits[second.id.uuidString],3)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.habitatReservationCount,0)
        }
    }

    func testModeOpportunityDistributionAcrossSixteenSeedsAndOneHour() {
        var averages:[Double]=[]
        for mode in CompanionMode.allCases {
            var flockCount=0,encounterCount=0
            for seed:UInt64 in 0..<16 {
                let s=CompanionOpportunityScheduler(seed:seed)
                s.configure(CompanionPreferences(mode:mode).policy,flockEnabled:true)
                for _ in 0..<3600 {
                    let due=s.advance(1,pointer:.zero,buttonsDown:false,cadence:1,flockEnabled:true)
                    if due.flock {s.didStart(.flockPass);s.didSettle()}
                    else if due.encounter {s.didStart(.socialGreeting);s.didSettle()}
                }
                flockCount+=s.flockDueCount;encounterCount+=s.encounterDueCount
                XCTAssertLessThan(s.maximumFlockWait,120)
            }
            let flockMean=Double(flockCount)/16,encounterMean=Double(encounterCount)/16
            averages.append(flockMean)
            let flockExpected=mode == .focus ? 5.0...7.0:mode == .natural ? 9.0...12.0:18.0...22.0
            let encounterExpected=mode == .focus ? 6.0...8.0:12.0...15.0
            XCTAssertTrue(flockExpected.contains(flockMean),"\(mode): \(flockMean)")
            XCTAssertTrue(encounterExpected.contains(encounterMean),"\(mode): \(encounterMean)")
            print("Companion hourly opportunities \(mode): flock=\(flockMean), encounter=\(encounterMean), seeds=16")
        }
        XCTAssertLessThan(averages[0],averages[1]);XCTAssertLessThan(averages[1],averages[2])
    }
    func testAllSpeciesOrdinaryTravelHasNoDecorativeOrbitAndWallDiagnosticsDoNotSkipPhysics() {
        for mode in CompanionMode.allCases {
            for species in SpeciesID.allCases {
                let e=engine();var settings=e.settings;settings.companion?.mode=mode;e.applySettings(settings)
                let bird=Bird(position:CGPoint(x:500,y:500),fraction:0.5,profile:settings.catalog.profile(species),random:{0.5})
                _=e.register(bird)
                let host=e.world.surfaces[0],destination=Geometry.foot(on:host,fraction:0.5,edge:.top,scale:e.spriteScale(for:bird))
                bird.fly(to:destination,host:host,random:{0.5})
                advance(e,25)
                XCTAssertEqual(bird.state,.perched,"\(mode) / \(species)")
                XCTAssertLessThan(e.companionMetrics.maximumContinuousFlight,25)
                XCTAssertGreaterThan(bird.flightEpisodeID,0)
            }
        }
        let e=engine();e.advance(2)
        XCTAssertEqual(e.companionMetrics.unpausedElapsed,2)
        XCTAssertEqual(e.companionMetrics.simulatedElapsed,0.05,accuracy:0.00001)
        e.handle(.pause(true));e.advance(2);XCTAssertEqual(e.companionMetrics.unpausedElapsed,2)
    }

    func testPausedWindowReplacementCannotReattachLeafToAnUnrelatedWindow() {
        let e=engine();var leaf=item(.leaf,1200,900);leaf.support = .window
        apply([leaf],to:e);e.handle(.pause(true))
        var world=e.world;world.surfaces=[Surface(id:99,pid:99,rect:world.surfaces[0].rect)]
        e.updateWorld(world)
        XCTAssertTrue(e.sceneNeedsPlacement.contains(leaf.id));XCTAssertTrue(e.carriedObjects.objects.isEmpty)
        e.handle(.pause(false));advance(e,3)
        XCTAssertTrue(e.carriedObjects.objects.isEmpty)
    }
    func testFullCapacityDoesNotRecreateResourcesDuringIdleFrames() {
        var costs:[Double]=[]
        for populated in [false,true] {
            let e=engine()
            if populated {
                apply([item(.perch,300,200,slot:1),item(.perch,1000,200,slot:2),item(.perch,1800,200,slot:3),
                       item(.foodTray,500,600),item(.bath,1300,600),item(.nest,1800,900)],to:e)
            }
            let archive=e.sceneArchive,next=e.habitatObjects.nextID
            for index in 0..<6 {
                let bird=Bird(position:.zero,fraction:CGFloat(index+1)/9,profile:e.settings.catalog.profile(.treeSparrow),random:{0.5})
                bird.perch(on:e.world.surfaces.first{$0.id==1}!,spriteScale:e.spriteScale(for:bird));bird.perchDuration=3600;_=e.register(bird)
            }
            let start=Date.timeIntervalSinceReferenceDate
            for _ in 0..<600 {e.advance(BehaviorEngine.step);_=e.renderSnapshot();_=e.propSnapshot();_=e.habitatSnapshot()}
            let cost=(Date.timeIntervalSinceReferenceDate-start)/600;costs.append(cost)
            XCTAssertEqual(e.sceneArchive,archive);XCTAssertEqual(e.habitatObjects.nextID,next)
            if populated {XCTAssertEqual(e.fixedPerchSnapshot().count,3);XCTAssertEqual(e.habitatSnapshot().count,3)}
        }
        print("Companion frame sample (6 birds, 600 frames, debug): baseline_ms=\(costs[0]*1000), six_objects_ms=\(costs[1]*1000)")
    }

    func testSchemaTwoMigrationPreservesProbabilityV2AndOnlyBacksUpOnSave() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        var original=BirdSettings();original.probabilities.setManualWeight(at:0,to:1234);original.activityRhythm = .localDayNight
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any]);raw["schemaVersion"]=2
        let data=try JSONSerialization.data(withJSONObject:raw),url=folder.appendingPathComponent("settings.json")
        try data.write(to:url)
        let restored=try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("absent"))
        XCTAssertEqual(restored.probabilities,original.probabilities)
        XCTAssertEqual(restored.companion?.mode,.lively);XCTAssertEqual(restored.companion?.followLocalDayNight,true)
        XCTAssertEqual(try Data(contentsOf:url),data)
        try restored.save(to:url)
        let backups=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.pathExtension=="bak"}
        XCTAssertEqual(backups.count,1);XCTAssertEqual(try Data(contentsOf:backups[0]),data)
        let second=try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("absent"))
        XCTAssertEqual(second.companion,restored.companion);XCTAssertEqual(second.probabilities,original.probabilities)
    }

    func testMultipleRestartResourceCommitsReplayInStableIdentityOrder() throws {
        let e=engine(record:true)
        var archive=SceneArchive();archive.layout.instances=[item(.nest,600,900),item(.nest,1800,900)]
        for item in archive.layout.instances.reversed() {
            var resource=SceneResource(kind:.nest);resource.materials=[.attached,.delivered,.arranged];resource.remainingUses=0
            archive.resources[item.id]=resource
        }
        try e.restoreScene(archive)
        let log=try e.recordedInputs()
        XCTAssertEqual(log.sceneWrites?.count,2)
        XCTAssertTrue(e.sceneArchive.resources.values.allSatisfy{$0.materials == [.spent,.delivered,.arranged]})
        for hz in [30,60,120] {
            let decoded=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(log))
            XCTAssertEqual(try decoded.replay(callbackHz:hz),log.expected)
        }
    }

}
