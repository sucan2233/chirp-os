import XCTest
@testable import BirdingCore

final class BehaviorRecordingTests:XCTestCase {
    let screen=CGRect(x:0,y:0,width:1600,height:1200)
    let host=Surface(id:61,pid:42,rect:CGRect(x:100,y:900,width:1400,height:250))
    func fixture(record:Bool=true) -> BehaviorEngine {
        var settings=BirdSettings();settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:UInt64.max-100,settings:settings,recordInputs:record)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let frames=Set(["stand","blink","preen0","preen1","idle0","idle1","idle2","land0","land1","land2"]+(0...7).map{"fly\($0)"})
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:30,y:30),
            availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)})))
        return e
    }
    func advance(_ e:BehaviorEngine,_ seconds:Double) {for _ in 0..<Int(seconds*30) {e.advance(1.0/30)}}
    func decoded(_ e:BehaviorEngine) throws -> BehaviorInputLog {try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(e.recordedInputs()))}
    func assertReplay(_ e:BehaviorEngine,file:StaticString=#filePath,line:UInt=#line) throws {
        let log=try decoded(e)
        XCTAssertNil(log.failure,file:file,line:line)
        for hz in [30,60,120] {XCTAssertEqual(try log.replay(callbackHz:hz),log.expected,"\(hz)Hz",file:file,line:line)}
        XCTAssertEqual(try log.replay(),log.expected,file:file,line:line)
    }
    func testRecordReplayPreservesExternalInputsAndDoesNotDoubleRecordNestedRoutes() throws {
        let e=fixture()
        e.bringInBird();advance(e,20)
        let bird=try XCTUnwrap(e.birds.first),id=try XCTUnwrap(e.id(of:bird))
        XCTAssertEqual(bird.state,.perched)
        _=e.handle(.attention(.watch,.preview));advance(e,0.5)
        e.handle(.pause(true));advance(e,2)
        e.handle(.relocate(id));advance(e,5)
        e.handle(.pause(false));advance(e,2)
        var settings=e.settings;settings.hoverDelay=0.3;e.applySettings(settings)
        e.population.setRange(PopulationRange(lower:8,upper:12)!)
        e.reconcileLayout();advance(e,10)
        let log=try e.recordedInputs()
        XCTAssertEqual(log.seed,String(UInt64.max-100))
        XCTAssertEqual(log.inputs.filter{$0.kind == "arrive"}.count,1)
        XCTAssertFalse(log.inputs.contains{$0.kind == "route"},"Internal routes are consequences, not external inputs")
        XCTAssertEqual(log.inputs.filter{$0.kind == "reconcileLayout"}.count,1)
        XCTAssertTrue(log.expected?.events.contains{$0.kind == "watch" && $0.type == "started"} ?? false)
        try assertReplay(e)
    }
    func testAutomaticPopulationAndEcologyUseTheSameRandomStreamsWhenRecorded() throws {
        let e=fixture(),control=fixture(record:false)
        for engine in [e,control] {engine.populationEnabled=true;engine.ambientEnabled=true;engine.autonomousRouting=true;advance(engine,60)}
        let a=e.renderSnapshot(),b=control.renderSnapshot()
        XCTAssertEqual(a.map(\.position),b.map(\.position));XCTAssertEqual(a.map(\.frameName),b.map(\.frameName))
        for _ in 0..<16 {XCTAssertEqual(e.random.unit(),control.random.unit())}
        try assertReplay(e)
    }
    func testWorldHostSamplingAndPopulationReplacementAreRecordedInOrder() throws {
        let e=fixture();e.bringInBird();advance(e,15)
        var world=e.world;world.surfaces[0].rect.origin.x+=20;e.updateWorld(world,sampleDT:1.0/30)
        e.population=Population(range:PopulationRange(lower:1,upper:1)!)
        e.populationEnabled=true;advance(e,5)
        if let bird=e.birds.first {e.sendAway(bird)}
        advance(e,10)
        try assertReplay(e)
    }
    func testPublicEdgePeekCommandRecordsRejectionForReplay() throws {
        let e=fixture()
        XCTAssertEqual(e.handle(.edgePeek(.preview)),.rejected(.unavailableBird))
        XCTAssertEqual(e.events.last?.kind,.edgePeek)
        XCTAssertEqual(e.events.last?.type,.rejected)
        try assertReplay(e)
    }
    func testRecorderRetainsEventsBeyondEngineDiagnosticRing() throws {
        let e=fixture()
        for _ in 0..<300 {e.handle(.remove(BirdID(999)));e.handle(.attention(.watch,.preview))}
        XCTAssertEqual(e.events.count,256)
        XCTAssertEqual(try e.recordedInputs().expected?.events.count,300)
        try assertReplay(e)
    }
    func testRecordingsRoundTripThroughDiskAndRejectUnsupportedEnvelopes() throws {
        let e=fixture();e.bringInBird();advance(e,1)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("replay.json");try e.saveRecording(to:file)
        let loaded=try BehaviorInputLog.load(from:file)
        XCTAssertEqual(try loaded.replay(),loaded.expected)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
        for bad:Any in [2,-1,true,"1",1.5] {
            object["version"]=bad;object["settings"]="future incompatible payload"
            XCTAssertThrowsError(try BehaviorInputLog.decode(JSONSerialization.data(withJSONObject:object)))
        }
    }
    func testM6dRecordsVersionTwelveAndRejectsPriorSimulationSemantics() throws {
        let e=fixture();e.bringInBird();advance(e,1)
        let current=try e.recordedInputs()
        XCTAssertEqual(BehaviorInputLog.currentVersion,1)
        XCTAssertEqual(BehaviorInputLog.engineVersion,12)
        XCTAssertEqual(current.simulationVersion,12)
        XCTAssertEqual(try BehaviorInputLog.decode(BehaviorInputLog.encoder().encode(current)).simulationVersion,12)

        // Exercise the compatibility boundary with a well-formed old envelope.
        // Never promote its version and replay it under the newly expanded lists.
        for version in [10,11] {
        var old=current;old.simulationVersion=version
        let data=try BehaviorInputLog.encoder().encode(old)
        XCTAssertEqual(old.expected,current.expected)
        XCTAssertThrowsError(try BehaviorInputLog.decode(data)) {error in
            XCTAssertTrue(error.localizedDescription.contains("unsupported recording or simulation version"))
        }
        let directlyDecoded=try JSONDecoder().decode(BehaviorInputLog.self,from:data)
        for hz in [30,60,120] {XCTAssertThrowsError(try directlyDecoded.replay(callbackHz:hz))}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("v\(version).json")
        XCTAssertThrowsError(try directlyDecoded.save(to:file))
        XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))

        var incompatible=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        incompatible["settings"]="prior-version nested settings must not be decoded"
        incompatible["inputs"]="unknown old representation"
        XCTAssertThrowsError(try BehaviorInputLog.decode(JSONSerialization.data(withJSONObject:incompatible))) {error in
            XCTAssertTrue(error.localizedDescription.contains("unsupported recording or simulation version"))
        }
        }
    }
    func testUnknownOrInvalidInputsAreRejectedWithoutSilentSkipping() throws {
        let e=fixture();var log=try e.recordedInputs()
        for kind in ["unknown","world","settings","visitorMemory","command","advance","population","route","depart"] {
            log.inputs=[RecordedInput(kind:kind)]
            XCTAssertThrowsError(try log.replay(),kind)
        }
        log=try e.recordedInputs();var input=RecordedInput(kind:"advance")
        input.elapsed = -.infinity;input.options=RecordedSimulationOptions(e);log.inputs=[input]
        XCTAssertThrowsError(try log.replay())
        input.elapsed=Double.greatestFiniteMagnitude;log.inputs=[input];XCTAssertNoThrow(try log.replay())
        log.inputs=[];XCTAssertThrowsError(try log.replay(callbackHz:0))
        log.failure="incomplete";XCTAssertThrowsError(try log.replay())
    }
    func testRestoredVisitorsAndLearningReplayWithoutReadingLocalMemory() throws {
        let memory=VisitorMemory(seed:9999)
        var identities:[SpeciesID:String]=[:]
        for species in SpeciesID.allCases {
            let profile=try XCTUnwrap(memory.acquire(species:species));identities[species]=profile.id
            for _ in 0..<20 {memory.learn(profile.id,elapsed:0.05)}
            memory.release(profile.id)
        }
        let e=fixture();try e.restoreVisitorMemory(memory.archive);e.bringInBird();advance(e,20)
        let bird=try XCTUnwrap(e.birds.first),visitor=try XCTUnwrap(e.visitor(of:bird))
        XCTAssertEqual(visitor.id,identities[bird.profile.id]);XCTAssertGreaterThan(visitor.familiarity,0)
        var world=e.world;world.pointer=CGPoint(x:bird.position.x+180,y:bird.position.y);e.updateWorld(world)
        advance(e,5)
        let inputCount=try e.recordedInputs().inputs.count
        XCTAssertThrowsError(try e.restoreVisitorMemory(memory.archive))
        XCTAssertEqual(try e.recordedInputs().inputs.count,inputCount)
        XCTAssertEqual(try e.recordedInputs().inputs.filter{$0.kind == "visitorMemory"}.count,1)
        try assertReplay(e)
    }
    func testWorldManifestDeltaPreservesChangesAndClearsAndLongHostSamples() throws {
        let e=fixture();e.bringInBird();advance(e,3)
        var world=e.world;world.pointer.x+=5;e.updateWorld(world,sampleDT:9000)
        let log=try e.recordedInputs()
        XCTAssertNotNil(log.inputs.first{$0.kind == "world"}?.world?.availableFrames)
        XCTAssertNil(log.inputs.last?.world?.availableFrames)
        world.availableFrames=[:];e.updateWorld(world)
        XCTAssertEqual(try e.recordedInputs().inputs.last?.world?.availableFrames,[:])
        try assertReplay(e)
    }
    func testWorldValidationAfterACommandIsNotElided() throws {
        let e=fixture();let world=e.world
        e.handle(.pause(true));e.updateWorld(world)
        XCTAssertEqual(try e.recordedInputs().inputs.suffix(2).map(\.kind),["command","world"])
        let count=try e.recordedInputs().inputs.count
        e.updateWorld(world)
        XCTAssertEqual(try e.recordedInputs().inputs.count,count)
        try assertReplay(e)
    }
    func testEveryCommandHasAStableRoundTrip() throws {
        let commands:[EngineCommand]=[.fixedPerchVisit(.preview),.allopreening(.preview),.travelTogether(.preview),.chase(.preview),.edgePeek(.preview),.sideHop(.preview),.prepareTakeoff(.automatic),.relocate(BirdID(1)),.pointerVisit(.automatic),.flockPass(.preview),.socialGreeting(.user),
            .placeFoodTray(at:CGPoint(x:800,y:500)),.placeFoodTrayAfter(2),.cancelFoodTrayPlacement,.removeFoodTray,
            .foodTrayVisit(.user),.foodTrayVisit(.preview),.foodTrayVisit(.automatic),
            .socialMotion(.giveWay,.automatic),.perchAction(.preen,.preview),.attention(.alert,.preview),.previewPointerAfter(3),
            .leafPlay(at:CGPoint(x:400,y:400),source:.preview),.releaseLeafAfter(2),.clearLeaf,.clearProps,.removeProp(ScenePropID(9)),
            .pointerClick,.pause(true),.cancelAmbient(.sleep),.scatter,.remove(BirdID(3))]
        for command in commands {
            let first=RecordedCommand(command),data=try BehaviorInputLog.encoder().encode(first)
            let decoded=try JSONDecoder().decode(RecordedCommand.self,from:data)
            XCTAssertEqual(try BehaviorInputLog.encoder().encode(RecordedCommand(decoded.validated())),data)
        }
        var command=RecordedCommand(.pause(true));command.flag=nil;XCTAssertThrowsError(try command.validated())
        command=RecordedCommand(.relocate(BirdID(1)));command.target="18446744073709551616";XCTAssertThrowsError(try command.validated())
        command.name="future";XCTAssertThrowsError(try command.validated())
    }
    func testClampedLongCallbackAndSubstepRemainderArePreserved() throws {
        let e=fixture();e.bringInBird()
        for dt in [0.001,0.1,0.005,0.034,0,0.008,0.05] {e.advance(dt)}
        try assertReplay(e)
    }
    func testClampedCommandsIgnoredNegativeTimeAndTinyCallbacksReplayExactly() throws {
        let e=fixture()
        e.handle(.previewPointerAfter(-5));e.handle(.cancelAmbient(.userInput))
        e.handle(.releaseLeafAfter(100));e.handle(.clearProps)
        e.handle(.previewPointerAfter(.nan));e.handle(.cancelAmbient(.userInput))
        e.advance(-1);e.advance(.nan);e.advance(.infinity)
        XCTAssertFalse(try e.recordedInputs().inputs.contains{$0.kind == "advance"})
        e.advance(BehaviorEngine.step-1.2e-10)
        for _ in 0..<30 {e.advance(1e-12)}
        XCTAssertEqual(e.time,BehaviorEngine.step)
        try assertReplay(e)
    }
    func testDirectPopulationClockMutationIsCapturedWithoutDuplicatingEngineTicks() throws {
        let e=fixture();e.populationEnabled=true
        _=e.population.tick(1,residents:0,total:0,random:{0.42})
        XCTAssertEqual(try e.recordedInputs().inputs.filter{$0.kind == "population"}.count,1)
        advance(e,10)
        XCTAssertEqual(try e.recordedInputs().inputs.filter{$0.kind == "population"}.count,1)
        try assertReplay(e)
    }
    func testMutableFixtureInjectionCannotProduceAFalseReplaySuccess() {
        let e=fixture();e.installFixtureBirds([])
        XCTAssertThrowsError(try e.recordedInputs())
        XCTAssertThrowsError(try fixture(record:false).recordedInputs())
    }
    func testAirborneFixtureStartsAtItsOriginAndRejectsInvalidCoordinates() throws {
        let e=fixture(record:false)
        var value=RecordedFixtureBird(species:.spottedDove,host:61,fraction:0.5,perchDuration:600,facingRight:true)
        value.flightOrigin=RecordedPoint(CGPoint(x:100,y:900))
        let bird=try value.make(in:e)
        XCTAssertEqual(bird.position,CGPoint(x:100,y:900));XCTAssertEqual(bird.state,.flying)
        XCTAssertNil(bird.airborneFlight,"Setup cannot invent measured velocity")
        for _ in 0..<45 {bird.tick(1.0/60)}
        XCTAssertNotNil(bird.airborneFlight)
        for coordinate in [Double.nan,Double.infinity,1_000_001] {
            value.flightOrigin=RecordedPoint(CGPoint(x:coordinate,y:900))
            XCTAssertThrowsError(try value.make(in:e))
        }
    }
    func testOversizedRecordingCannotBeReplayedOrSavedAsComplete() throws {
        let e=fixture()
        for _ in 0...BehaviorInputLog.maximumInputs {e.handle(.clearProps)}
        XCTAssertThrowsError(try e.recordedInputs())
        XCTAssertThrowsError(try BehaviorInputLog.decode(Data(repeating:32,count:BehaviorInputLog.maximumBytes+1)))
    }
    func testSharedFilesExerciseCompletedScenesAndReleaseAllResources() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder=root.appendingPathComponent("shared/behavior-fixtures/v1")
        let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}.sorted{$0.path<$1.path}
        XCTAssertEqual(Set(files.map(\.lastPathComponent)),["attention.json","leaf.json","social.json","interruptions.json","side-hop.json","takeoff-preparation.json","returning-visitor.json","activity-rhythm.json","edge-peek.json","chase.json","travel-together.json","allopreening.json","fixed-perch.json","food-tray.json","bath.json"])
        for file in files {
            let log=try BehaviorInputLog.load(from:file),reference=try log.replay(callbackHz:60)
            XCTAssertEqual(log.simulationVersion,12,file.lastPathComponent)
            if let expected=log.expected {XCTAssertEqual(reference,expected,file.lastPathComponent)}
            XCTAssertEqual(try log.replay(callbackHz:30),reference,file.lastPathComponent)
            XCTAssertEqual(try log.replay(callbackHz:120),reference,file.lastPathComponent)
            XCTAssertEqual(reference.runs,0,file.lastPathComponent);XCTAssertEqual(reference.leases,0,file.lastPathComponent)
            XCTAssertEqual(reference.reservations,0,file.lastPathComponent);XCTAssertTrue(reference.props.isEmpty,file.lastPathComponent)
            XCTAssertEqual(reference.habitatReservations,0,file.lastPathComponent)
            XCTAssertFalse(reference.hasFoodTrayPlacement,file.lastPathComponent)
            let finished=reference.events.filter{$0.type=="completed"}.compactMap(\.kind)
            if file.lastPathComponent=="bath.json" {
                XCTAssertEqual(finished.filter{$0=="bathVisit"}.count,1)
                XCTAssertEqual(reference.birds.map(\.id),["1"])
                XCTAssertEqual(reference.birds.map(\.position.x),[400]);XCTAssertEqual(reference.birds.map(\.position.y),[1050])
                XCTAssertEqual(reference.birds.map(\.state),["perched"])
                XCTAssertEqual(reference.habitats.count,1);XCTAssertEqual(reference.habitats.first?.kind,"bath")
                XCTAssertEqual(reference.habitats.first?.remainingUses,2)
                XCTAssertFalse(try XCTUnwrap(reference.habitats.first).retiring)
                XCTAssertEqual(reference.sceneFocusID,reference.habitats.first?.id)
                XCTAssertEqual(reference.hasBathPlacement,false);XCTAssertTrue(reference.props.isEmpty)
                XCTAssertFalse(reference.events.contains{$0.type=="failed" || $0.type=="cancelled" || $0.type=="rejected"})
            } else if file.lastPathComponent=="food-tray.json" {
                XCTAssertEqual(finished.filter{$0=="foodTrayVisit"}.count,1)
                XCTAssertEqual(reference.birds.map(\.id),["1"])
                XCTAssertEqual(reference.birds.map(\.position.x),[400]);XCTAssertEqual(reference.birds.map(\.position.y),[1050])
                XCTAssertEqual(reference.birds.map(\.state),["perched"])
                XCTAssertEqual(reference.habitats.count,1)
                XCTAssertEqual(reference.habitats.first?.kind,"foodTray")
                XCTAssertEqual(reference.habitats.first?.remainingUses,2)
                XCTAssertFalse(try XCTUnwrap(reference.habitats.first).retiring)
                XCTAssertFalse(reference.events.contains{$0.type=="failed" || $0.type=="cancelled" || $0.type=="rejected"})
            } else {XCTAssertTrue(reference.habitats.isEmpty,file.lastPathComponent)}
            if file.lastPathComponent=="fixed-perch.json" {
                XCTAssertEqual(finished.filter{$0=="fixedPerchVisit"}.count,1)
                XCTAssertEqual(reference.birds.map(\.id),["1"])
                XCTAssertEqual(reference.birds.map(\.position.x),[1100])
                XCTAssertEqual(reference.birds.map(\.position.y),[450])
                XCTAssertEqual(reference.birds.map(\.state),["perched"])
                XCTAssertEqual(reference.fixedPerches.map(\.slot),[1])
                XCTAssertFalse(reference.events.contains{$0.type=="failed" || $0.type=="cancelled"})
            }
            if file.lastPathComponent=="allopreening.json" {
                XCTAssertEqual(finished.filter{$0=="allopreening"}.count,1)
                XCTAssertEqual(reference.birds.map(\.id),["1","2"])
                XCTAssertEqual(reference.birds.map(\.position.x),[500,620])
                XCTAssertEqual(reference.birds.map(\.position.y),[450,450])
                XCTAssertEqual(reference.birds.map(\.state),["perched","perched"])
                XCTAssertFalse(reference.events.contains{$0.type=="failed" || $0.type=="cancelled"})
            }
            if file.lastPathComponent=="travel-together.json" {
                XCTAssertEqual(finished.filter{$0=="travelTogether"}.count,1)
                XCTAssertEqual(reference.birds.map(\.id),["1","2"])
                XCTAssertEqual(reference.birds.map(\.position.x),[1760,1760])
                XCTAssertEqual(reference.birds.map(\.position.y),[400,640])
                XCTAssertEqual(reference.birds.map(\.state),["perched","perched"])
                XCTAssertTrue(reference.events.contains{$0.kind=="travelTogether" && $0.type=="rejected" && $0.reason=="unavailableBird"})
                XCTAssertFalse(reference.events.contains{$0.type=="failed" || $0.type=="cancelled"})
            }
            if file.lastPathComponent=="chase.json" {
                XCTAssertEqual(finished.filter{$0=="chase"}.count,2)
                XCTAssertEqual(reference.birds.map(\.id),["1","2"])
                XCTAssertEqual(reference.birds.map(\.position.y),[900,900])
                XCTAssertEqual(reference.birds[0].position.x,602.6,accuracy:1e-8)
                XCTAssertEqual(reference.birds[1].position.x,865.8,accuracy:1e-8)
                XCTAssertFalse(reference.events.contains{$0.type=="failed" || $0.type=="cancelled"})
            }
            if file.lastPathComponent=="edge-peek.json" {
                XCTAssertEqual(finished.filter{$0=="edgePeek"}.count,2)
                let bird=try XCTUnwrap(reference.birds.first)
                XCTAssertEqual(reference.birds.count,1);XCTAssertEqual(bird.id,"1")
                XCTAssertEqual(bird.position.x,213.6,accuracy:1e-9)
                XCTAssertEqual(bird.position.y,900,accuracy:1e-9)
                XCTAssertFalse(reference.events.contains{$0.type=="failed" || $0.type=="cancelled"})
            }
            if file.lastPathComponent=="activity-rhythm.json" {
                XCTAssertTrue(finished.contains("rest"));XCTAssertTrue(finished.contains("flockPass"))
                XCTAssertTrue(reference.events.contains{$0.kind=="flockPass" && $0.type=="rejected" && $0.reason=="disabled"})
                XCTAssertFalse(reference.events.contains{$0.type=="started" && $0.source=="automatic" && $0.kind != "rest" && $0.kind != "preen"})
            }
            if file.lastPathComponent=="attention.json" {XCTAssertTrue(finished.contains("watch"));XCTAssertTrue(finished.contains("alert"))}
            if file.lastPathComponent=="side-hop.json" {
                XCTAssertTrue(finished.contains("sideHop"))
                let bird=try XCTUnwrap(reference.birds.first)
                XCTAssertNotEqual(bird.position.x,800,"hop must change the actual foot position")
            }
            if file.lastPathComponent=="takeoff-preparation.json" {XCTAssertTrue(finished.contains("takeoffPreparation"))}
            if file.lastPathComponent=="returning-visitor.json" {
                let bird=try XCTUnwrap(reference.birds.first)
                XCTAssertEqual(reference.birds.count,1);XCTAssertEqual(bird.id,"2")
                XCTAssertEqual(bird.visitorID,"99");XCTAssertEqual(bird.familiarity,0.5)
                let memory=VisitorMemory(seed:0);try memory.restore(reference.visitorMemory)
                let profile=try XCTUnwrap(memory.profile("99"))
                XCTAssertEqual(profile.visits,4);XCTAssertEqual(profile.familiarity,0.5)
                XCTAssertEqual(profile.temperament,BirdTemperament(seed:9001,birdID:BirdID(99)))
                XCTAssertTrue(reference.events.contains{$0.type=="birdRemoved" && $0.participants==["1"]})
            }
            if file.lastPathComponent=="leaf.json" {XCTAssertTrue(finished.contains("leafPlay"))}
            if file.lastPathComponent=="social.json" {XCTAssertTrue(finished.contains("socialGreeting"))}
            if file.lastPathComponent=="interruptions.json" {
                XCTAssertTrue(reference.events.contains{$0.kind=="watch" && $0.type=="cancelled" && $0.reason=="userInput"})
                XCTAssertTrue(finished.contains("relocate"))
            }
        }
    }
}
