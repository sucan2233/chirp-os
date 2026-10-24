import XCTest
@testable import BirdingCore

final class BathRecordingTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:2000,height:1400)
    private let host=Surface(id:901,pid:42,rect:CGRect(x:200,y:1050,width:400,height:150))
    private let point=CGPoint(x:1300,y:700)
    private let frames:Set<String>=["stand","shake","blink","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7",
        "land0","land1","land2","bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise"]
    private func engine(record:Bool=false)->BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:901,settings:settings,recordInputs:record)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(.init(screens:[display],displays:[display],surfaces:[host],pointer:CGPoint(x:20,y:20),
            availableFrames:[.treeSparrow:frames,.lightVentedBulbul:frames]))
        return e
    }
    private func appendAdvance(_ seconds:Double,to log:inout BehaviorInputLog,engine:BehaviorEngine) {
        var input=RecordedInput(kind:"advance");input.elapsed=BehaviorEngine.step
        input.repeatCount=Int((seconds*60).rounded());input.options=RecordedSimulationOptions(engine)
        log.inputs.append(input)
    }

    func testBathCommandsHaveStableRoundTripsAndRejectMalformedCoordinatesDelayAndSource() throws {
        let commands:[EngineCommand]=[.placeBath(at:point),.placeBathAfter(2),.cancelBathPlacement,.removeBath,
            .clearCurrentScene,.bathVisit(.automatic),.bathVisit(.preview),.bathVisit(.user)]
        for command in commands {
            let bytes=try BehaviorInputLog.encoder().encode(RecordedCommand(command))
            let value=try JSONDecoder().decode(RecordedCommand.self,from:bytes)
            XCTAssertEqual(try BehaviorInputLog.encoder().encode(RecordedCommand(value.validated())),bytes)
        }
        var command=RecordedCommand(.placeBath(at:point));command.point=nil
        XCTAssertThrowsError(try command.validated())
        for value in [CGFloat.nan,CGFloat.infinity,1_000_001] {
            command.point=RecordedPoint(CGPoint(x:value,y:700));XCTAssertThrowsError(try command.validated())
        }
        command=RecordedCommand(.placeBathAfter(2));command.delay=nil;XCTAssertThrowsError(try command.validated())
        for value in [-1.0,10.01,Double.nan,Double.infinity] {
            command.delay=value;XCTAssertThrowsError(try command.validated())
        }
        command=RecordedCommand(.bathVisit(.preview));command.source="future"
        XCTAssertThrowsError(try command.validated())
    }

    func testBathArtOmissionDefaultsTrueAndExplicitFalseIsPreservedAcrossWorldDecode() throws {
        let e=engine();var world=RecordedWorld(e.world)
        XCTAssertEqual(world.bathArtAvailable,true)
        world.bathArtAvailable=false
        let absent=try world.validated();XCTAssertFalse(absent.bathArtAvailable)
        let decoded=try JSONDecoder().decode(RecordedWorld.self,from:JSONEncoder().encode(world))
        XCTAssertFalse(try decoded.validated().bathArtAvailable)
        world.bathArtAvailable=nil
        XCTAssertTrue(try world.validated(inheriting:absent).bathArtAvailable)
    }

    func testActualCurrentVersionRecordingPreservesPlacementPauseClearingAndArtLossAtEveryRate() throws {
        let e=engine(record:true)
        func advance(_ seconds:Double) {for _ in 0..<Int(seconds*60) {e.advance(BehaviorEngine.step)}}
        var placement=e.world;placement.pointer=point;e.updateWorld(placement)
        XCTAssertEqual(e.handle(.placeBathAfter(2)),.scheduled)
        advance(0.5);e.handle(.pause(true));advance(3)
        var log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        XCTAssertEqual(log.simulationVersion,17);XCTAssertNotNil(log.expected)
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
        e.handle(.pause(false));advance(1.6)
        XCTAssertEqual(e.habitatSnapshot().count,1)
        XCTAssertEqual(e.handle(.bathVisit(.preview)),.rejected(.noSpecies))
        e.handle(.clearCurrentScene);advance(2.1)
        var world=e.world;world.bathArtAvailable=false;e.updateWorld(world)
        XCTAssertEqual(e.handle(.placeBath(at:point)),.rejected(.missingFrames))
        log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        let expected=try XCTUnwrap(log.expected)
        XCTAssertTrue(expected.habitats.isEmpty);XCTAssertEqual(expected.runs,0)
        XCTAssertEqual(expected.leases,0);XCTAssertTrue(expected.props.isEmpty)
        XCTAssertTrue(log.inputs.contains{$0.world?.bathArtAvailable==false})
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),expected)}
    }

    func testHandwrittenBathInputsReplayRealSuccessPauseAndCancellationWithoutInventingExpected() throws {
        for species:SpeciesID in [.treeSparrow,.lightVentedBulbul] {
            for cancel in [false,true] {
                let e=engine()
                var log=BehaviorInputLog(seed:901,settings:e.settings)
                log.initialWorld=RecordedWorld(e.world)
                log.fixtureBirds=[RecordedFixtureBird(species:species,host:host.id,fraction:0.5,
                    perchDuration:600,facingRight:true)]
                appendAdvance(9,to:&log,engine:e)
                log.inputs.append(.command(.placeBath(at:point)))
                log.inputs.append(.command(.bathVisit(.preview)))
                appendAdvance(8,to:&log,engine:e)
                log.inputs.append(.command(.pause(true)));appendAdvance(3,to:&log,engine:e)
                if cancel {log.inputs.append(.command(.removeBath))}
                log.inputs.append(.command(.pause(false)));appendAdvance(27,to:&log,engine:e)
                XCTAssertNil(log.expected,"Literal inputs use independent semantic assertions")
                let reference=try log.replay(callbackHz:60)
                for hz in [30,120] {XCTAssertEqual(try log.replay(callbackHz:hz),reference)}
                let terminal=reference.events.filter{$0.kind=="bathVisit" && ["completed","cancelled","failed"].contains($0.type)}
                XCTAssertEqual(terminal.count,1)
                XCTAssertEqual(terminal.first?.type,cancel ? "cancelled":"completed")
                XCTAssertEqual(reference.runs,0);XCTAssertEqual(reference.leases,0)
                XCTAssertEqual(reference.reservations,0);XCTAssertEqual(reference.habitatReservations,0)
                XCTAssertEqual(reference.birds.count,1);XCTAssertEqual(reference.residents,1)
                XCTAssertEqual(reference.birds.first?.species,species.rawValue)
                XCTAssertTrue(reference.props.isEmpty)
                if cancel {XCTAssertTrue(reference.habitats.isEmpty)}
                else {
                    XCTAssertEqual(reference.habitats.first?.kind,"bath")
                    XCTAssertEqual(reference.habitats.first?.remainingUses,2)
                    XCTAssertEqual(reference.birds.first?.state,"perched")
                    XCTAssertEqual(reference.birds.first?.position,RecordedPoint(CGPoint(x:400,y:1050)))
                }
            }
        }
    }

    func testSharedBathFixturePreservesOriginalFeetTwoUsesAndOneFocusAcrossEveryInputBoundaryAndRate() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file=root.appendingPathComponent("shared/behavior-fixtures/v1/bath.json")
        let original=try BehaviorInputLog.load(from:file)
        XCTAssertEqual(original.simulationVersion,17);XCTAssertNil(original.expected)
        var boundaries:[BehaviorReplayReport]=[]
        for count in 1...original.inputs.count {
            var prefix=original;prefix.inputs=Array(original.inputs.prefix(count))
            let reference=try prefix.replay(callbackHz:60)
            XCTAssertEqual(try prefix.replay(callbackHz:30),reference,"input boundary \(count)")
            XCTAssertEqual(try prefix.replay(callbackHz:120),reference,"input boundary \(count)")
            XCTAssertEqual(reference.residents,1);XCTAssertEqual(reference.birds.map(\.id),["1"])
            XCTAssertLessThanOrEqual(reference.props.count,6)
            XCTAssertLessThanOrEqual(reference.habitats.count,1)
            if let bath=reference.habitats.first {XCTAssertEqual(reference.sceneFocusID,bath.id)}
            boundaries.append(reference)
        }
        let beforeWait=try XCTUnwrap(boundaries.first{$0.paused}),afterWait=try XCTUnwrap(boundaries.last{$0.paused})
        XCTAssertEqual(beforeWait.birds,afterWait.birds);XCTAssertEqual(beforeWait.props,afterWait.props)
        XCTAssertEqual(beforeWait.habitats,afterWait.habitats)
        XCTAssertEqual(beforeWait.schedulerRemaining,afterWait.schedulerRemaining)
        let final=try XCTUnwrap(boundaries.last)
        XCTAssertEqual(final.events.filter{$0.kind=="bathVisit" && $0.type=="completed"}.count,1)
        XCTAssertFalse(final.events.contains{["failed","cancelled","rejected"].contains($0.type)})
        XCTAssertEqual(final.birds.first?.position,RecordedPoint(CGPoint(x:400,y:1050)))
        XCTAssertEqual(final.birds.first?.state,"perched");XCTAssertEqual(final.habitats.first?.remainingUses,2)
        XCTAssertEqual(final.sceneFocusID,final.habitats.first?.id);XCTAssertNotNil(final.sceneFocusID)
        XCTAssertEqual(final.runs,0);XCTAssertEqual(final.leases,0);XCTAssertEqual(final.reservations,0)
        XCTAssertEqual(final.habitatReservations,0);XCTAssertTrue(final.props.isEmpty)
    }
}
