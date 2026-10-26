import XCTest
@testable import BirdingCore

final class LeafCarryRecordingTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:2400,height:1500)
    private let host=Surface(id:961,pid:42,rect:CGRect(x:200,y:1100,width:2000,height:180))
    private let point=CGPoint(x:1200,y:1100)
    private let frames:Set<String>=["stand","blink","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7",
        "land0","land1","land2","carryLook","carryLower","carryGrip","carryPlace"]
    private func engine(record:Bool=false)->BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:961,settings:settings,recordInputs:record)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(.init(screens:[display],displays:[display],surfaces:[host],pointer:CGPoint(x:20,y:20),
            availableFrames:[.treeSparrow:frames]))
        return e
    }
    private func appendAdvance(_ seconds:Double,to log:inout BehaviorInputLog,engine:BehaviorEngine) {
        var input=RecordedInput(kind:"advance");input.elapsed=BehaviorEngine.step
        input.repeatCount=Int((seconds*60).rounded());input.options=RecordedSimulationOptions(engine)
        log.inputs.append(input)
    }

    func testFrozenCarryCommandsRoundTripAndRejectIncompleteOrNonfinitePayloads() throws {
        let commands:[EngineCommand]=[.placeCarryLeaf(at:point),.placeCarryLeafAfter(3),.cancelCarryLeafPlacement,
            .removeCarryLeaf,.leafCarry(.automatic),.leafCarry(.preview),.leafCarry(.user)]
        for command in commands {
            let bytes=try BehaviorInputLog.encoder().encode(RecordedCommand(command))
            let decoded=try JSONDecoder().decode(RecordedCommand.self,from:bytes)
            XCTAssertEqual(try BehaviorInputLog.encoder().encode(RecordedCommand(decoded.validated())),bytes)
        }
        var command=RecordedCommand(.placeCarryLeaf(at:point));command.point=nil
        XCTAssertThrowsError(try command.validated())
        for x in [CGFloat.nan,CGFloat.infinity,1_000_001] {
            command.point=RecordedPoint(CGPoint(x:x,y:1100));XCTAssertThrowsError(try command.validated())
        }
        command=RecordedCommand(.placeCarryLeafAfter(3));command.delay=nil
        XCTAssertThrowsError(try command.validated())
        for delay in [-1.0,10.01,Double.nan,Double.infinity] {
            command.delay=delay;XCTAssertThrowsError(try command.validated())
        }
        command=RecordedCommand(.leafCarry(.preview));command.source=nil
        XCTAssertThrowsError(try command.validated())
        command.source="future";XCTAssertThrowsError(try command.validated())
    }

    func testRecordedWorldDefaultsCarryArtTrueAndPreservesExplicitLoss() throws {
        let e=engine();var world=RecordedWorld(e.world)
        let bytes=try JSONEncoder().encode(world)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        XCTAssertEqual(raw["leafCarryArtAvailable"] as? Bool,true)
        raw["leafCarryArtAvailable"]=false
        world=try JSONDecoder().decode(RecordedWorld.self,from:JSONSerialization.data(withJSONObject:raw))
        let absent=try world.validated();XCTAssertFalse(absent.leafCarryArtAvailable)
        raw.removeValue(forKey:"leafCarryArtAvailable")
        world=try JSONDecoder().decode(RecordedWorld.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertTrue(try world.validated(inheriting:absent).leafCarryArtAvailable)
    }

    func testRealCurrentVersionRecordingReplaysPendingPlacementPauseClearAndArtLoss() throws {
        let e=engine(record:true)
        func advance(_ seconds:Double) {for _ in 0..<Int((seconds*60).rounded()) {e.advance(BehaviorEngine.step)}}
        var world=e.world;world.pointer=point;e.updateWorld(world)
        XCTAssertEqual(e.handle(.placeCarryLeafAfter(2)),.scheduled)
        advance(0.5);e.handle(.pause(true));advance(3)
        XCTAssertTrue(e.hasCarryLeafPlacement);XCTAssertTrue(e.propSnapshot().isEmpty)
        var log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        XCTAssertEqual(BehaviorInputLog.engineVersion,21);XCTAssertEqual(log.simulationVersion,21)
        XCTAssertNotNil(log.expected)
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected)}
        e.handle(.pause(false));advance(1.6)
        XCTAssertFalse(e.hasCarryLeafPlacement)
        XCTAssertEqual(e.propSnapshot().filter{$0.kind == .leafToken}.count,1)
        XCTAssertNotNil(e.sceneFocus)
        e.handle(.removeCarryLeaf);advance(0.3)
        XCTAssertTrue(e.propSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
        world=e.world;world.leafCarryArtAvailable=false;e.updateWorld(world)
        XCTAssertEqual(e.handle(.placeCarryLeaf(at:point)),.rejected(.missingFrames))
        log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        let expected=try XCTUnwrap(log.expected)
        XCTAssertTrue(expected.props.isEmpty);XCTAssertEqual(expected.runs,0);XCTAssertEqual(expected.leases,0)
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),expected)}
    }

    func testHandwrittenCarryInputsKeepOneIdentityAcrossInitialHeadingsAndCallbackRates() throws {
        for right in [false,true] {
            let e=engine();var log=BehaviorInputLog(seed:961,settings:e.settings)
            log.initialWorld=RecordedWorld(e.world)
            log.fixtureBirds=[RecordedFixtureBird(species:.treeSparrow,host:host.id,fraction:right ? 0.15:0.85,
                perchDuration:600,facingRight:right)]
            appendAdvance(9,to:&log,engine:e)
            log.inputs.append(.command(.placeCarryLeaf(at:point)))
            log.inputs.append(.command(.leafCarry(.preview)))
            for _ in 0..<250 {appendAdvance(0.1,to:&log,engine:e)}
            XCTAssertNil(log.expected,"Handwritten inputs retain independent semantic assertions")
            var identity:String?,sawToken=false,sawCarry=false
            var states=Set<String>()
            for count in [2,3]+Array(stride(from:4,through:log.inputs.count,by:5)) {
                var prefix=log;prefix.inputs=Array(log.inputs.prefix(count))
                let reference=try prefix.replay(callbackHz:60)
                XCTAssertEqual(try prefix.replay(callbackHz:30),reference,"boundary \(count)")
                XCTAssertEqual(try prefix.replay(callbackHz:120),reference,"boundary \(count)")
                XCTAssertEqual(reference.residents,1);XCTAssertEqual(reference.birds.map(\.id),["1"])
                XCTAssertLessThanOrEqual(reference.props.count,1)
                XCTAssertEqual(reference.carriedObjects?.count,reference.props.count)
                if let object=reference.carriedObjects?.first {
                    states.insert(object.state)
                    XCTAssertEqual(reference.props.first?.id,object.id)
                    XCTAssertEqual(object.worldScale,1);XCTAssertEqual(object.facingRight,right)
                    if object.state == "attached" {
                        XCTAssertEqual(object.owner,"1");XCTAssertNotNil(object.reservedByRun)
                        XCTAssertEqual(object.remainingLifetime,0)
                    }
                    if object.state == "available" {XCTAssertNil(object.owner)}
                    if object.state == "placed" {
                        XCTAssertNil(object.owner);XCTAssertNil(reference.sceneFocusID)
                        XCTAssertNil(reference.sceneFocusKind)
                    } else {
                        XCTAssertEqual(reference.sceneFocusID,object.id);XCTAssertEqual(reference.sceneFocusKind,"leaf")
                    }
                }
                if let token=reference.props.first {
                    XCTAssertEqual(token.kind,"leafToken")
                    if let identity {XCTAssertEqual(token.id,identity)} else {identity=token.id}
                    XCTAssertEqual(token.size,16)
                    let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(token)) as? [String:Any])
                    XCTAssertNotNil(raw["mirrored"] as? Bool,"Replay must retain actual token orientation")
                    sawToken=true
                }
                sawCarry = sawCarry || reference.birds.contains{$0.frame.hasPrefix("carry")}
            }
            let final=try log.replay(callbackHz:60)
            XCTAssertEqual(try log.replay(callbackHz:30),final);XCTAssertEqual(try log.replay(callbackHz:120),final)
            XCTAssertTrue(sawToken);XCTAssertTrue(sawCarry)
            XCTAssertEqual(states,["available","attached","placed"])
            XCTAssertEqual(final.events.filter{$0.kind=="leafCarry" && $0.type=="completed"}.count,1)
            XCTAssertFalse(final.events.contains{["failed","cancelled","rejected"].contains($0.type)})
            XCTAssertEqual(final.runs,0);XCTAssertEqual(final.leases,0);XCTAssertEqual(final.reservations,0)
            XCTAssertTrue(final.props.isEmpty);XCTAssertNil(final.sceneFocusID)
            XCTAssertEqual(final.carriedObjects,[]);XCTAssertEqual(final.hasCarryLeafPlacement,false)
            XCTAssertEqual(final.residents,1);XCTAssertEqual(final.birds.first?.state,"perched")
        }
    }

    func testSharedHandwrittenFixtureFreezesTheWholeEntityThenSeparatesCompletionFromPausedCancellation() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let log=try BehaviorInputLog.load(from:root.appendingPathComponent("shared/behavior-fixtures/v1/leaf-carry.json"))
        XCTAssertEqual(log.simulationVersion,21)
        func prefix(_ count:Int,_ hz:Int=60)throws->BehaviorReplayReport {
            var input=log;input.inputs=Array(log.inputs.prefix(count));return try input.replay(callbackHz:hz)
        }
        for count in 1...log.inputs.count {
            let reference=try prefix(count)
            XCTAssertEqual(try prefix(count,30),reference,"input \(count)")
            XCTAssertEqual(try prefix(count,120),reference,"input \(count)")
            XCTAssertLessThanOrEqual(reference.carriedObjects?.count ?? 0,1)
            XCTAssertEqual(reference.props.map(\.id),reference.carriedObjects?.map(\.id) ?? [])
        }
        let available=try prefix(2),reserved=try prefix(3)
        let object=try XCTUnwrap(available.carriedObjects?.first)
        XCTAssertEqual(object.state,"available");XCTAssertEqual(object.remainingLifetime,180)
        XCTAssertEqual(available.sceneFocusKind,"leaf");XCTAssertEqual(available.sceneFocusID,object.id)
        XCTAssertEqual(reserved.carriedObjects?.first?.id,object.id)
        XCTAssertNotNil(reserved.carriedObjects?.first?.reservedByRun)
        for (beforeCount,afterCount) in [(5,6),(11,12)] {
            let before=try prefix(beforeCount),after=try prefix(afterCount)
            XCTAssertTrue(after.paused);XCTAssertEqual(after.birds,before.birds)
            XCTAssertEqual(after.props,before.props);XCTAssertEqual(after.carriedObjects,before.carriedObjects)
            XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
            XCTAssertEqual(after.sceneCooldownRemaining,before.sceneCooldownRemaining)
            XCTAssertEqual(after.sceneFocusKind,before.sceneFocusKind);XCTAssertEqual(after.sceneFocusID,before.sceneFocusID)
        }
        let finished=try prefix(8)
        XCTAssertEqual(finished.events.filter{$0.kind=="leafCarry" && $0.type=="completed"}.count,1)
        XCTAssertEqual(finished.carriedObjects,[]);XCTAssertTrue(finished.props.isEmpty)
        XCTAssertNil(finished.sceneFocusID);XCTAssertEqual(finished.leases,0)
        let deleted=try prefix(13)
        XCTAssertTrue(deleted.paused);XCTAssertEqual(deleted.carriedObjects,[])
        XCTAssertTrue(deleted.props.isEmpty);XCTAssertEqual(deleted.runs,0);XCTAssertEqual(deleted.leases,0)
        XCTAssertEqual(deleted.reservations,0);XCTAssertNil(deleted.sceneFocusID)
        XCTAssertEqual(deleted.events.filter{$0.kind=="leafCarry" && $0.type=="cancelled"}.count,1)
        let final=try prefix(log.inputs.count)
        XCTAssertEqual(try XCTUnwrap(log.expected),final)
        XCTAssertEqual(final.carriedObjects,[]);XCTAssertEqual(final.hasCarryLeafPlacement,false)
        XCTAssertTrue(final.props.isEmpty);XCTAssertEqual(final.runs,0);XCTAssertEqual(final.reservations,0)
        XCTAssertEqual(final.events.filter{$0.kind=="leafCarry" && $0.type=="completed"}.count,1)
        XCTAssertFalse(final.events.contains{$0.type=="failed" || $0.type=="rejected"})
    }
}
