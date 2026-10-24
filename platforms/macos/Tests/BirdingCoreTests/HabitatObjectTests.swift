import XCTest
@testable import BirdingCore

final class HabitatObjectTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:2000,height:1400)
    private let point=CGPoint(x:1300,y:700)

    private func fixture(record:Bool=false) -> BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:1414,settings:settings,recordInputs:record)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(BehaviorWorld(screens:[display],displays:[display],pointer:point))
        return e
    }
    private func advance(_ e:BehaviorEngine,_ seconds:Double) {
        for _ in 0..<Int((seconds*60).rounded()) {e.advance(1.0/60)}
    }
    private func report(_ e:BehaviorEngine) -> BehaviorReplayReport {
        BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init))
    }
    private func assertReplay(_ e:BehaviorEngine,file:StaticString=#filePath,line:UInt=#line) throws {
        let log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        XCTAssertEqual(log.simulationVersion,15,file:file,line:line)
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected,"\(hz)Hz",file:file,line:line)}
        XCTAssertEqual(try log.replay(),log.expected,file:file,line:line)
    }

    func testPlacementCreatesPersistentObjectWithoutStartingRunOrSpawningBird() throws {
        let e=fixture()
        XCTAssertTrue(e.handle(.placeFoodTray(at:point)).accepted)
        let object=try XCTUnwrap(e.habitatSnapshot().first)
        XCTAssertEqual(e.habitatSnapshot().count,1);XCTAssertEqual(object.kind,.foodTray)
        XCTAssertGreaterThan(object.id.rawValue,0)
        XCTAssertEqual(object.rect.midX,point.x);XCTAssertEqual(object.rect.minY,point.y)
        XCTAssertEqual(object.remainingUses,3);XCTAssertEqual(object.remainingLifetime,180)
        XCTAssertFalse(object.retiring);XCTAssertTrue(object.blockers.isEmpty)
        XCTAssertTrue(e.birds.isEmpty);XCTAssertEqual(e.activeRunCount,0)
        XCTAssertEqual(e.habitatReservationCount,0);XCTAssertTrue(e.propSnapshot().isEmpty)
        advance(e,5)
        let later=try XCTUnwrap(e.habitatSnapshot().first)
        XCTAssertEqual(later.id,object.id);XCTAssertEqual(later.remainingUses,3)
        XCTAssertEqual(later.remainingLifetime,175,accuracy:1e-7)
        XCTAssertFalse(e.hasFoodTrayPlacement)
    }

    func testDuplicatePlacementCannotMoveRefillOrExtendExistingTray() throws {
        let e=fixture();XCTAssertTrue(e.handle(.placeFoodTray(at:point)).accepted);advance(e,10)
        let before=report(e).habitats
        XCTAssertFalse(e.handle(.placeFoodTray(at:CGPoint(x:1600,y:700))).accepted)
        XCTAssertEqual(report(e).habitats,before)
        XCTAssertFalse(e.handle(.placeFoodTrayAfter(1)).accepted)
        XCTAssertFalse(e.hasFoodTrayPlacement);XCTAssertEqual(report(e).habitats,before)
        e.handle(.removeFoodTray);XCTAssertTrue(e.habitatSnapshot().isEmpty)
        XCTAssertTrue(e.handle(.placeFoodTray(at:point)).accepted)
        let replacement=try XCTUnwrap(e.habitatSnapshot().first)
        XCTAssertNotEqual(String(replacement.id.rawValue),before.first?.id)
        XCTAssertEqual(replacement.remainingUses,3);XCTAssertEqual(replacement.remainingLifetime,180)
    }

    func testFullTrayAndBirdClearanceMustFitOneWorkAreaAndPhysicalDisplay() {
        for p in [CGPoint(x:1,y:700),CGPoint(x:1999,y:700),CGPoint(x:1300,y:1),
                  CGPoint(x:1300,y:1399),CGPoint(x:2100,y:700),
                  CGPoint(x:CGFloat.nan,y:700),CGPoint(x:1300,y:CGFloat.infinity)] {
            let e=fixture();XCTAssertFalse(e.handle(.placeFoodTray(at:p)).accepted,"\(p)")
            XCTAssertTrue(e.habitatSnapshot().isEmpty)
        }
        for workAreas in [[CGRect(x:1290,y:600,width:200,height:300)],
                          [CGRect(x:0,y:0,width:1300,height:1400),CGRect(x:1300,y:0,width:700,height:1400)]] {
            let e=fixture();var world=e.world;world.screens=workAreas;e.updateWorld(world)
            XCTAssertFalse(e.handle(.placeFoodTray(at:point)).accepted)
            XCTAssertTrue(e.habitatSnapshot().isEmpty,"Adjacent work areas cannot bridge the tray")
        }
        let e=fixture();var world=e.world
        world.displays=[CGRect(x:0,y:0,width:1300,height:1400),CGRect(x:1300,y:0,width:700,height:1400)]
        e.updateWorld(world);XCTAssertFalse(e.handle(.placeFoodTray(at:point)).accepted)
    }

    func testMissingArtDisabledSettingAndHighLayerOcclusionRejectPlacement() {
        for mode in ["art","setting","panel"] {
            let e=fixture();var world=e.world
            switch mode {
            case "art":world.foodTrayArtAvailable=false;e.updateWorld(world)
            case "setting":var settings=e.settings;settings.foodTrayEnabled=false;e.applySettings(settings)
            default:world.surfaces=[Surface(id:99,pid:42,rect:CGRect(x:1299,y:680,width:2,height:40),layer:1)];e.updateWorld(world)
            }
            XCTAssertFalse(e.handle(.placeFoodTray(at:point)).accepted,mode)
            XCTAssertTrue(e.habitatSnapshot().isEmpty);XCTAssertEqual(e.habitatReservationCount,0)
        }
        let e=fixture();var world=e.world
        world.surfaces=[Surface(id:99,pid:42,rect:CGRect(x:1000,y:650,width:700,height:200),layer:0)]
        e.updateWorld(world);XCTAssertTrue(e.handle(.placeFoodTray(at:point)).accepted)
    }

    func testPlacementRejectsFixedPerchAndResidentCollision() {
        let e=fixture();var settings=e.settings
        settings.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"",displayFrame:display,x:0.65,y:0.5)]
        e.applySettings(settings);XCTAssertFalse(e.handle(.placeFoodTray(at:point)).accepted)
        let other=fixture(),host=Surface(id:95,pid:42,rect:CGRect(x:1100,y:700,width:400,height:100))
        var world=other.world;world.surfaces=[host];other.updateWorld(world)
        let bird=Bird(position:.zero,fraction:0.5,profile:other.settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:other.spriteScale(for:bird));other.installFixtureBirds([bird])
        let actual=bird.position
        XCTAssertFalse(other.handle(.placeFoodTray(at:point)).accepted)
        XCTAssertEqual(bird.position,actual);XCTAssertEqual(other.activeRunCount,0)
    }

    func testNegativeDesktopCoordinatesAndScalePreserveCompleteGeometry() throws {
        for scale:CGFloat in [0.5,1,2] {
            let e=fixture();var world=e.world
            let left=CGRect(x:-2000,y:-400,width:2000,height:1400)
            world.screens=[left];world.displays=[left];world.scale=scale;e.updateWorld(world)
            let foot=CGPoint(x:-1000,y:300)
            XCTAssertTrue(e.handle(.placeFoodTray(at:foot)).accepted)
            let object=try XCTUnwrap(e.habitatSnapshot().first)
            XCTAssertEqual(object.rect,CGRect(x:foot.x-64*scale,y:foot.y,width:128*scale,height:24*scale))
            XCTAssertTrue(left.contains(object.rect))
        }
    }

    private final class ReservedSlot:BehaviorExecution {
        let kind:BehaviorKind = .relocate
        let timeout=60.0
        let landingReservations:[LandingReservation]
        var participants:[BirdID] {landingReservations.map(\.bird)}
        init(_ reservation:LandingReservation) {landingReservations=[reservation]}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }

    func testPlacementRespectsForeignLandingReservationBeforeObjectAllocation() throws {
        let e=fixture()
        let home=Surface(id:96,pid:42,rect:CGRect(x:200,y:1050,width:400,height:150))
        let destination=Surface(id:97,pid:42,rect:CGRect(x:1100,y:700,width:400,height:100))
        var world=e.world;world.pointer=CGPoint(x:20,y:20);world.surfaces=[home,destination];e.updateWorld(world)
        let bird=Bird(position:.zero,fraction:0.5,profile:e.settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:home,spriteScale:e.spriteScale(for:bird));e.installFixtureBirds([bird])
        let id=try XCTUnwrap(e.id(of:bird))
        guard case .started(let run)=e.runtime.start(ReservedSlot(LandingReservation(bird:id,host:destination,fraction:0.5)),source:.preview,in:e) else {
            return XCTFail("Expected an independent reserved future landing")
        }
        XCTAssertFalse(e.handle(.placeFoodTray(at:point)).accepted)
        XCTAssertTrue(e.habitatSnapshot().isEmpty);XCTAssertEqual(e.reservedLandingCount,1)
        e.runtime.cancel(run,reason:.removed,in:e)
        XCTAssertTrue(e.handle(.placeFoodTray(at:point)).accepted)
    }

    func testObjectSnapshotPreservesDecimalUInt64IdentityAndBlockerGeometry() throws {
        let panel=CGRect(x:-900,y:400,width:20,height:60)
        let object=HabitatObjectRenderState(id:HabitatObjectID(UInt64.max),kind:.foodTray,
            rect:CGRect(x:-1100,y:700,width:128,height:24),blockers:[panel],
            remainingUses:0,retiring:true,remainingLifetime:0)
        let recorded=RecordedHabitatObjectState(object)
        let decoded=try JSONDecoder().decode(RecordedHabitatObjectState.self,from:JSONEncoder().encode(recorded))
        XCTAssertEqual(decoded,recorded);XCTAssertEqual(decoded.id,"18446744073709551615")
        XCTAssertEqual(decoded.kind,"foodTray");XCTAssertEqual(decoded.blockers.map(\.value),[panel])
        XCTAssertEqual(decoded.remainingUses,0);XCTAssertTrue(decoded.retiring);XCTAssertEqual(decoded.remainingLifetime,0)
    }

    func testObjectLifetimeAndPendingPlacementFreezeDuringPause() throws {
        let e=fixture();e.handle(.placeFoodTray(at:point));advance(e,2)
        e.handle(.pause(true));let before=report(e).habitats;advance(e,200)
        XCTAssertEqual(report(e).habitats,before)
        e.handle(.pause(false));advance(e,177)
        XCTAssertEqual(try XCTUnwrap(e.habitatSnapshot().first).remainingLifetime,1,accuracy:1e-7)
        advance(e,2);XCTAssertTrue(e.habitatSnapshot().isEmpty)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.habitatReservationCount,0)
        let pending=fixture();XCTAssertTrue(pending.handle(.placeFoodTrayAfter(2)).accepted)
        XCTAssertTrue(pending.hasFoodTrayPlacement);advance(pending,0.5)
        pending.handle(.pause(true));advance(pending,5)
        XCTAssertTrue(pending.hasFoodTrayPlacement);XCTAssertTrue(pending.habitatSnapshot().isEmpty)
        pending.handle(.pause(false));advance(pending,1.6)
        XCTAssertFalse(pending.hasFoodTrayPlacement);XCTAssertEqual(pending.habitatSnapshot().count,1)
    }

    func testPendingPlacementUsesCurrentPointerAndCancelsWithoutCreatingObject() throws {
        for command:EngineCommand in [.cancelFoodTrayPlacement,.removeFoodTray,.clearProps,.cancelAmbient(.settingsChanged)] {
            let e=fixture();XCTAssertTrue(e.handle(.placeFoodTrayAfter(1)).accepted)
            e.handle(command);XCTAssertFalse(e.hasFoodTrayPlacement);advance(e,2)
            XCTAssertTrue(e.habitatSnapshot().isEmpty)
        }
        let e=fixture();XCTAssertTrue(e.handle(.placeFoodTrayAfter(1)).accepted)
        var world=e.world;world.pointer=CGPoint(x:1500,y:850);e.updateWorld(world);advance(e,1.2)
        let object=try XCTUnwrap(e.habitatSnapshot().first)
        XCTAssertEqual(object.rect.midX,1500);XCTAssertEqual(object.rect.minY,850)
        XCTAssertFalse(e.hasFoodTrayPlacement)
    }

    func testClearLeafPreservesPlacedTrayAndPendingPlacementWhileClearPropsRemovesBoth() throws {
        for pending in [false,true] {
            let e=fixture(record:true)
            XCTAssertTrue(e.handle(pending ? .placeFoodTrayAfter(2):.placeFoodTray(at:point)).accepted)
            XCTAssertTrue(e.handle(.releaseLeafAfter(1)).accepted)
            XCTAssertTrue(e.hasLeafPreview)
            let before=report(e).habitats
            XCTAssertTrue(e.handle(.clearLeaf).accepted)
            XCTAssertFalse(e.hasLeafPreview)
            XCTAssertEqual(report(e).habitats,before)
            XCTAssertEqual(e.hasFoodTrayPlacement,pending)
            try assertReplay(e)
            if pending {
                advance(e,2.1)
                XCTAssertEqual(e.habitatSnapshot().count,1)
                XCTAssertFalse(e.hasFoodTrayPlacement)
            }
            XCTAssertTrue(e.handle(.clearProps).accepted)
            XCTAssertTrue(e.habitatSnapshot().isEmpty);XCTAssertFalse(e.hasFoodTrayPlacement)
            try assertReplay(e)
            e.handle(.placeFoodTrayAfter(2));e.handle(.clearProps);advance(e,3)
            XCTAssertFalse(e.hasFoodTrayPlacement);XCTAssertTrue(e.habitatSnapshot().isEmpty)
            try assertReplay(e)
        }
    }

    func testSettingsRemoveObjectsAndCancelPendingPlacementWhileMissingArtRemovesExistingObject() {
        for pending in [false,true] {
            for cause in ["setting","art"] {
                let e=fixture()
                e.handle(pending ? .placeFoodTrayAfter(2):.placeFoodTray(at:point))
                if cause=="setting" {var settings=e.settings;settings.foodTrayEnabled=false;e.applySettings(settings)}
                else {var world=e.world;world.foodTrayArtAvailable=false;e.updateWorld(world)}
                XCTAssertTrue(e.habitatSnapshot().isEmpty)
                if cause=="setting" || !pending {XCTAssertFalse(e.hasFoodTrayPlacement)}
                advance(e,3);XCTAssertTrue(e.habitatSnapshot().isEmpty)
                XCTAssertFalse(e.hasFoodTrayPlacement)
            }
        }
    }

    func testSurfaceTagsAndLegacyFixedPerchFlagRoundTrip() throws {
        for kind:HabitatSurfaceKind in [.fixedPerch,.foodTray] {
            let surface=Surface(id:100,pid:42,rect:CGRect(x:100,y:500,width:300,height:1),habitatKind:kind)
            let recorded=RecordedSurface(surface)
            let restored=try JSONDecoder().decode(RecordedSurface.self,from:JSONEncoder().encode(recorded)).value
            XCTAssertEqual(restored,surface);XCTAssertEqual(restored.habitatKind,kind)
            XCTAssertEqual(restored.isFixedPerch,kind == .fixedPerch)
        }
        let legacy=Data(#"{"id":100,"pid":42,"layer":0,"rect":{"x":100,"y":500,"width":300,"height":1},"isGround":false,"isFixedPerch":true}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RecordedSurface.self,from:legacy).value.habitatKind,.fixedPerch)
        let invalid=Data(#"{"id":100,"pid":42,"layer":0,"rect":{"x":100,"y":500,"width":300,"height":1},"isGround":false,"habitatKind":"future"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(RecordedSurface.self,from:invalid))
    }

    func testFoodTrayCommandsRoundTripAndRejectInvalidPayloads() throws {
        let commands:[EngineCommand]=[.placeFoodTray(at:point),.placeFoodTrayAfter(2),.cancelFoodTrayPlacement,
            .removeFoodTray,.foodTrayVisit(.automatic),.foodTrayVisit(.preview),.foodTrayVisit(.user),.clearLeaf]
        for command in commands {
            let data=try BehaviorInputLog.encoder().encode(RecordedCommand(command))
            let decoded=try JSONDecoder().decode(RecordedCommand.self,from:data)
            XCTAssertEqual(try BehaviorInputLog.encoder().encode(RecordedCommand(decoded.validated())),data)
        }
        var command=RecordedCommand(.placeFoodTray(at:point));command.point=nil
        XCTAssertThrowsError(try command.validated())
        command.point=RecordedPoint(CGPoint(x:CGFloat.nan,y:700));XCTAssertThrowsError(try command.validated())
        command.point=RecordedPoint(CGPoint(x:1_000_001,y:700));XCTAssertThrowsError(try command.validated())
        command=RecordedCommand(.placeFoodTrayAfter(2));command.delay=nil;XCTAssertThrowsError(try command.validated())
        for delay in [-1.0,10.01,Double.nan,Double.infinity] {command.delay=delay;XCTAssertThrowsError(try command.validated())}
        command=RecordedCommand(.foodTrayVisit(.preview));command.source="future";XCTAssertThrowsError(try command.validated())
    }

    func testWorldCapabilityOmissionDefaultsTrueAndExplicitFalseDoesNotInherit() throws {
        let e=fixture();var recorded=RecordedWorld(e.world)
        XCTAssertEqual(recorded.foodTrayArtAvailable,true)
        recorded.foodTrayArtAvailable=nil;XCTAssertTrue(try recorded.validated().foodTrayArtAvailable)
        recorded.foodTrayArtAvailable=false
        let absent=try recorded.validated();XCTAssertFalse(absent.foodTrayArtAvailable)
        recorded.foodTrayArtAvailable=nil;XCTAssertTrue(try recorded.validated(inheriting:absent).foodTrayArtAvailable)
    }

    func testReplayReportsCapturePlacementObjectAndCapabilityChangesAtEveryBoundary() throws {
        let e=fixture(record:true)
        e.handle(.placeFoodTrayAfter(2));advance(e,0.5)
        XCTAssertTrue(try XCTUnwrap(e.recordedInputs().expected).hasFoodTrayPlacement);try assertReplay(e)
        e.handle(.cancelFoodTrayPlacement);e.handle(.placeFoodTray(at:point));advance(e,1)
        let expected=try XCTUnwrap(e.recordedInputs().expected)
        XCTAssertEqual(expected.habitats.count,1);XCTAssertFalse(expected.hasFoodTrayPlacement)
        XCTAssertEqual(expected.habitats.first?.remainingUses,3);XCTAssertEqual(expected.habitatReservations,0)
        try assertReplay(e)
        var world=e.world;world.foodTrayArtAvailable=false;e.updateWorld(world);try assertReplay(e)
        world.foodTrayArtAvailable=true;e.updateWorld(world)
        e.handle(.placeFoodTrayAfter(0));advance(e,0.1);e.handle(.clearProps);try assertReplay(e)
    }

    func testClampedPlacementCommandsAndPendingPauseReplayAtEveryCallbackRate() throws {
        let e=fixture(record:true)
        for delay in [-5.0,100,Double.nan,Double.infinity] {
            e.handle(.placeFoodTrayAfter(delay));try assertReplay(e)
            e.handle(.cancelFoodTrayPlacement)
        }
        e.handle(.placeFoodTrayAfter(2));advance(e,0.5);e.handle(.pause(true));advance(e,5)
        XCTAssertTrue(e.hasFoodTrayPlacement);XCTAssertTrue(e.habitatSnapshot().isEmpty)
        try assertReplay(e)
        e.handle(.pause(false));advance(e,1.6)
        XCTAssertFalse(e.hasFoodTrayPlacement);XCTAssertEqual(e.habitatSnapshot().count,1)
        try assertReplay(e)
    }

    func testSettingsDefaultEnabledAndPersistExplicitDisableWithoutChangingOtherSettings() throws {
        XCTAssertTrue(BirdSettings().foodTrayEnabled)
        var settings=BirdSettings();settings.foodTrayEnabled=false;settings.hoverDelay=0.25
        let data=try JSONEncoder().encode(settings),disabled=try BirdSettings.decode(data)
        XCTAssertFalse(disabled.foodTrayEnabled);XCTAssertEqual(disabled.hoverDelay,0.25)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        object.removeValue(forKey:"foodTrayEnabled")
        let legacy=try BirdSettings.decode(JSONSerialization.data(withJSONObject:object))
        XCTAssertTrue(legacy.foodTrayEnabled);XCTAssertEqual(legacy.hoverDelay,0.25)
        for bad:Any in ["false",1,[],["enabled":true]] {
            object["foodTrayEnabled"]=bad
            XCTAssertThrowsError(try BirdSettings.decode(JSONSerialization.data(withJSONObject:object)))
        }
    }

    func testSimulationNineEnvelopeIsRejectedBeforeDecodingNestedData() throws {
        let e=fixture(record:true)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:BehaviorInputLog.encoder().encode(e.recordedInputs())) as? [String:Any])
        object["simulationVersion"]=9;object["settings"]="incompatible nested settings"
        XCTAssertThrowsError(try BehaviorInputLog.decode(JSONSerialization.data(withJSONObject:object))) {error in
            XCTAssertTrue(error.localizedDescription.contains("unsupported recording or simulation version"))
        }
    }
}
