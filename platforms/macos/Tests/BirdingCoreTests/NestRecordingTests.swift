import XCTest
@testable import BirdingCore

final class NestRecordingTests:XCTestCase {
    private typealias F=NestTestSupport
    private func fixture(_ name:String)throws->BehaviorInputLog {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try BehaviorInputLog.load(from:root.appendingPathComponent("shared/behavior-fixtures/v1/\(name).json"))
    }

    func testHandwrittenCarryAndBuildFixturesKeepIndependentTransactionsPauseCompletionAndCleanupAtAllRates() throws {
        for name in ["nest-material-carry","nest-build"] {
            let log=try fixture(name)
            XCTAssertEqual(log.simulationVersion,22)
            func prefix(_ count:Int,_ hz:Int=60)throws->BehaviorReplayReport {
                var value=log;value.inputs=Array(log.inputs.prefix(count));return try value.replay(callbackHz:hz)
            }
            let placed=try prefix(2),initial=try XCTUnwrap(placed.nests?.first)
            let materialIDs=initial.materials.map(\.id)
            XCTAssertEqual(initial.materials.map(\.state),["available","available","available"])
            XCTAssertEqual(initial.materials.map(\.slot),[0,1,2]);XCTAssertEqual(Set(materialIDs).count,3)
            XCTAssertEqual(initial.progress,0);XCTAssertEqual(placed.sceneFocusID,initial.id)
            XCTAssertEqual(placed.sceneFocusKind,"nest")
            for count in 1...log.inputs.count {
                let report=try prefix(count)
                XCTAssertEqual(try prefix(count,30),report,"\(name) boundary \(count)")
                XCTAssertEqual(try prefix(count,120),report,"\(name) boundary \(count)")
                XCTAssertLessThanOrEqual(report.runs,1);XCTAssertLessThanOrEqual(report.leases,1)
                XCTAssertLessThanOrEqual(report.habitatReservations,1);XCTAssertEqual(report.residents,1)
                XCTAssertEqual(report.birds.map(\.id),["1"])
                XCTAssertFalse(report.events.contains{$0.type=="failed" || $0.type=="rejected"})
                for nest in report.nests ?? [] {
                    XCTAssertEqual(nest.materials.map(\.id),materialIDs);XCTAssertEqual(nest.materials.count,3)
                    XCTAssertEqual(nest.materials.filter{$0.state=="arranged"}.count,nest.progress)
                    XCTAssertTrue(nest.materials.allSatisfy{["available","attached","delivered","arranged","spent"].contains($0.state)})
                }
            }
            let pauseBefore=name=="nest-material-carry" ? 5:7
            let a=try prefix(pauseBefore),b=try prefix(pauseBefore+1)
            XCTAssertTrue(b.paused);XCTAssertEqual(a.nests,b.nests);XCTAssertEqual(a.birds,b.birds)
            XCTAssertEqual(a.props,b.props);XCTAssertEqual(a.events,b.events)
            XCTAssertEqual(a.schedulerRemaining,b.schedulerRemaining);XCTAssertEqual(a.nestCooldownRemaining,b.nestCooldownRemaining)
            if name=="nest-material-carry" {
                let completed=try prefix(8),nest=try XCTUnwrap(completed.nests?.first)
                XCTAssertEqual(nest.progress,0);XCTAssertEqual(nest.materials.filter{$0.state=="delivered"}.count,1)
                XCTAssertEqual(nest.materials.filter{$0.state=="available"}.count,2)
                let material=try XCTUnwrap(nest.materials.first{$0.state=="delivered"})
                let event=try XCTUnwrap(completed.events.first{$0.kind=="nestMaterialCarry" && $0.type=="completed"})
                XCTAssertEqual(material.pickupRunID,event.run);XCTAssertEqual(material.deliveryRunID,event.run)
                XCTAssertNil(material.arrangementRunID);XCTAssertEqual(event.source,"user")
                XCTAssertEqual(completed.runs,0);XCTAssertEqual(completed.leases,0);XCTAssertEqual(completed.habitatReservations,0)
                let bird=try XCTUnwrap(completed.birds.first)
                XCTAssertEqual(bird.state,"perched");XCTAssertEqual(bird.position.x,550,accuracy:1e-8)
                XCTAssertEqual(bird.position.y,1700)
                XCTAssertEqual(completed.sceneFocusID,nest.id)
            } else {
                for (count,progress) in [(10,1),(14,2),(18,3)] {
                    let report=try prefix(count),nest=try XCTUnwrap(report.nests?.first)
                    XCTAssertEqual(nest.progress,progress);XCTAssertEqual(nest.completed,progress==3)
                    XCTAssertEqual(nest.materials.filter{$0.state=="arranged"}.count,progress)
                    XCTAssertEqual(report.events.filter{$0.kind=="nestMaterialCarry" && $0.type=="completed"}.count,progress)
                    XCTAssertEqual(report.events.filter{$0.kind=="nestBuild" && $0.type=="completed"}.count,progress)
                    XCTAssertEqual(report.runs,0);XCTAssertEqual(report.leases,0);XCTAssertEqual(report.habitatReservations,0)
                    for material in nest.materials where material.state=="arranged" {
                        XCTAssertNotNil(material.pickupRunID);XCTAssertEqual(material.pickupRunID,material.deliveryRunID)
                        XCTAssertNotNil(material.arrangementRunID);XCTAssertNotEqual(material.deliveryRunID,material.arrangementRunID)
                    }
                    if progress==3 {XCTAssertNil(report.sceneFocusID);XCTAssertFalse(nest.canContinue)}
                }
            }
            let final=try prefix(log.inputs.count)
            XCTAssertEqual(try XCTUnwrap(log.expected),final)
            XCTAssertEqual(final.runs,0);XCTAssertEqual(final.leases,0);XCTAssertEqual(final.reservations,0)
            XCTAssertEqual(final.habitatReservations,0);XCTAssertTrue(final.props.isEmpty);XCTAssertTrue(final.habitats.isEmpty)
            XCTAssertNil(final.nests);XCTAssertNil(final.hasNestPlacement);XCTAssertNil(final.sceneFocusID)
            XCTAssertEqual(final.events.filter{$0.kind=="nestMaterialCarry" && $0.type=="completed"}.count,name=="nest-build" ? 3:1)
            XCTAssertEqual(final.events.filter{$0.kind=="nestBuild" && $0.type=="completed"}.count,name=="nest-build" ? 3:0)
            XCTAssertEqual(final.events.filter{$0.type=="cancelled"}.count,name=="nest-build" ? 0:1)
        }
    }

    func testRealProductionRecordingReplaysAllFieldsAndRejectsItsIntactVersionSeventeenEnvelope() throws {
        var settings=F.settings()
        let index=try XCTUnwrap(settings.probabilities.entries.firstIndex{$0.id==F.species})
        settings.probabilities.adjust(at:index,to:10000)
        let profile=try XCTUnwrap(settings.catalog.species.firstIndex{$0.id==F.species})
        settings.catalog.species[profile].perchMin=120;settings.catalog.species[profile].perchMax=180
        let e=BehaviorEngine(seed:2701,settings:settings,recordInputs:true)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let display=CGRect(x:0,y:0,width:2400,height:2200)
        let host=Surface(id:3701,pid:42,rect:CGRect(x:200,y:1700,width:2000,height:180))
        e.updateWorld(.init(screens:[display],displays:[display],surfaces:[host],pointer:CGPoint(x:20,y:20),availableFrames:[F.species:F.frames]))
        XCTAssertEqual(e.handle(.nestMaterialCarry(.preview)),.rejected(.noSpace))
        e.bringInBird();F.advance(e,22)
        XCTAssertEqual(e.birds.map{$0.profile.id},[.spottedDove]);XCTAssertEqual(e.birds.first?.state,.perched)
        // Arrival chooses a real ordinary slot. Use a finite set of actual
        // placement requests instead of assuming that slot never covers x1400.
        var placed=false
        for x:CGFloat in [1400,1000,1800,600] where !placed {
            placed=e.handle(.placeNest(at:CGPoint(x:x,y:1700))) == .accepted
        }
        XCTAssertTrue(placed)
        let carry=try F.start(e,source:.user);F.advance(e,0.4)
        e.handle(.pause(true));F.advance(e,2);e.handle(.pause(false));F.finish(e,carry)
        F.released(e,carry);XCTAssertEqual(F.terminals(e,carry).map(\.type),[.completed])
        F.advance(e,1.1);let build=try F.start(e,build:true);F.finish(e,build);F.released(e,build)
        XCTAssertEqual(F.terminals(e,build).map(\.type),[.completed]);XCTAssertEqual(try F.nest(e).progress,1)
        F.clear(e)
        let log=try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))
        let expected=try XCTUnwrap(log.expected)
        XCTAssertEqual(log.simulationVersion,22);XCTAssertNil(log.failure);XCTAssertNil(log.fixtureBirds)
        XCTAssertEqual(expected.events.filter{$0.kind=="nestMaterialCarry" && $0.type=="completed"}.map(\.source),["user"])
        XCTAssertEqual(expected.events.filter{$0.kind=="nestBuild" && $0.type=="completed"}.map(\.source),["preview"])
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),expected)}
        var old=log;old.simulationVersion=17
        XCTAssertEqual(old.expected,expected);XCTAssertEqual(old.inputs.count,log.inputs.count)
        let bytes=try BehaviorInputLog.encoder().encode(old)
        XCTAssertThrowsError(try BehaviorInputLog.decode(bytes))
        let unchecked=try JSONDecoder().decode(BehaviorInputLog.self,from:bytes)
        for hz in [30,60,120] {XCTAssertThrowsError(try unchecked.replay(callbackHz:hz))}
    }

    func testCommandsWorldArtAndOptionalReportFieldsRoundTripWithoutSerializingAbsentNestState() throws {
        let commands:[EngineCommand]=[.placeNest(at:CGPoint(x:-1400,y:-1700)),.placeNestAfter(2),.cancelNestPlacement,.removeNest,
            .nestMaterialCarry(.user),.nestMaterialCarry(.preview),.nestMaterialCarry(.automatic),
            .nestBuild(.user),.nestBuild(.preview),.nestBuild(.automatic)]
        for command in commands {
            let first=RecordedCommand(command),data=try BehaviorInputLog.encoder().encode(first)
            let decoded=try JSONDecoder().decode(RecordedCommand.self,from:data)
            XCTAssertEqual(try BehaviorInputLog.encoder().encode(RecordedCommand(decoded.validated())),data)
        }
        var missing=RecordedCommand(.placeNest(at:.zero));missing.point=nil;XCTAssertThrowsError(try missing.validated())
        missing=RecordedCommand(.placeNestAfter(2));missing.delay=nil;XCTAssertThrowsError(try missing.validated())
        for build in [false,true] {
            missing=RecordedCommand(build ? .nestBuild(.preview):.nestMaterialCarry(.preview))
            missing.source=nil;XCTAssertThrowsError(try missing.validated())
            missing.source="future";XCTAssertThrowsError(try missing.validated())
        }
        let e=F.engine(residents:0,species:nil),report=BehaviorReplayReport(engine:e,events:[])
        let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(report)) as? [String:Any])
        for key in ["nests","hasNestPlacement","nestCooldownRemaining"] {XCTAssertNil(raw[key],key)}
        var world=RecordedWorld(e.world);world.nestArtAvailable=nil
        XCTAssertTrue(try world.validated().nestArtAvailable)
        world.nestArtAvailable=false;XCTAssertFalse(try world.validated().nestArtAvailable)
        e.handle(.placeNestAfter(2));XCTAssertEqual(BehaviorReplayReport(engine:e,events:[]).hasNestPlacement,true)
        e.handle(.cancelNestPlacement);XCTAssertNil(BehaviorReplayReport(engine:e,events:[]).hasNestPlacement)
    }
}
