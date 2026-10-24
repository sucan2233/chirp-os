import XCTest
@testable import BirdingCore

final class ObservationJournalTests:XCTestCase {
    private let screen=CGRect(x:-700,y:-200,width:1400,height:1000)
    private let host=Surface(id:41,rect:CGRect(x:-640,y:680,width:1280,height:100))
    private let date=Date(timeIntervalSince1970:1_790_000_000)
    private let kinds:[BehaviorKind]=[.pointerVisit,.flockPass,.rest,.preen,.socialGreeting,.sideBySide,.giveWay,
        .pairedTakeoff,.leafPlay,.watch,.alert,.sideHop,.takeoffPreparation,.edgePeek,.chase,.travelTogether,
        .allopreening,.fixedPerchVisit,.foodTrayVisit,.bathVisit,.leafCarry,.insectCatch]

    private func fixture(seed:UInt64=73,species:[SpeciesID]=[.treeSparrow]) -> BehaviorEngine {
        let engine=BehaviorEngine(seed:seed)
        engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:0,y:300)))
        engine.installFixtureBirds(species.enumerated().map {index,speciesID in
            let bird=Bird(position:.zero,fraction:CGFloat(index+1)/CGFloat(species.count+1),
                          profile:SpeciesCatalog.standard.profile(speciesID),random:{0.5})
            bird.perch(on:host);bird.perchDuration=600;return bird
        })
        return engine
    }
    private func advance(_ engine:BehaviorEngine,seconds:Double) {
        for _ in 0..<Int((seconds*60).rounded(.up)) {engine.advance(BehaviorEngine.step)}
    }
    private func flockMember(in engine:BehaviorEngine,species:SpeciesID,delay:Double=0,y:CGFloat)->(BirdID,FlockMemberPlan) {
        let path=FlightPath(points:[CGPoint(x:screen.minX-120,y:y),CGPoint(x:screen.maxX+120,y:y)])
        let plan=FlockMemberPlan(delay:delay,path:path,speed:400,wingPhase:0)
        let bird=Bird(position:path.point(0),fraction:0.5,profile:SpeciesCatalog.standard.profile(species),random:{0.5})
        return (engine.register(bird,role:.transient,visible:false),plan)
    }
    private func runID(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let id)=result else {
            XCTFail("Expected started, got \(result)",file:file,line:line)
            throw ObservationJournalError.invalid("expected started")
        }
        return id
    }
    private func observation(_ sequence:UInt64,runID:UInt64?=nil,kind:BehaviorKind = .rest,
                             source:BehaviorSource = .automatic,species:[SpeciesID]=[.treeSparrow],
                             simulationTime:Double=1)->BehaviorObservation {
        BehaviorObservation(sequence:sequence,simulationTime:simulationTime,kind:kind,source:source,
                            species:species,runID:runID ?? sequence)
    }
    private func entry(species:SpeciesID = .treeSparrow,behavior:String="rest",count:Int=1)->ObservationEntry {
        ObservationEntry(species:species,behavior:behavior,firstSeen:date,lastSeen:date,automaticCount:count)
    }
    private func object(_ archive:ObservationArchive) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(archive)) as? [String:Any])
    }
    private func data(_ value:Any) throws -> Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])}
    private func temporaryFolder()->URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ObservationJournalTests-"+UUID().uuidString)
    }

    /// Exercises runtime lifecycle in isolation without inventing species at finish.
    private final class CompletionExecution:BehaviorExecution {
        let kind:BehaviorKind
        let participants:[BirdID]
        let result:BehaviorCompletion
        let removeParticipants:Bool
        var ready=true
        let occupiesEncounter=false
        let timeout=100.0
        init(kind:BehaviorKind,participants:[BirdID],result:BehaviorCompletion = .completed,removeParticipants:Bool=false) {
            self.kind=kind;self.participants=participants;self.result=result;self.removeParticipants=removeParticipants
        }
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine)->BehaviorCompletion? {
            guard ready else {return nil}
            if removeParticipants {for id in participants {engine.removeRecord(id)}}
            return result
        }
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }

    func testRealPointerCompletionUsesCompletedEventSequenceAndDeliversAfterNormalEvent() throws {
        let engine=fixture(),journal=ObservationJournal()
        var observations:[BehaviorObservation]=[],completed:[UInt64]=[]
        engine.eventObserver={event in if event.type == .completed {completed.append(event.sequence)}}
        engine.observationObserver={value in
            XCTAssertEqual(completed.last,value.sequence)
            XCTAssertEqual(engine.events.last?.sequence,value.sequence)
            XCTAssertEqual(engine.activeRunCount,0)
            observations.append(value);journal.observe(value,at:self.date)
        }
        let run=try runID(engine.handle(.pointerVisit(.preview)))
        advance(engine,seconds:engine.birds[0].flightDuration+1)
        XCTAssertEqual(observations.count,1)
        let value=try XCTUnwrap(observations.first)
        XCTAssertEqual(value.runID,run.rawValue);XCTAssertEqual(value.kind,.pointerVisit)
        XCTAssertEqual(value.source,.preview);XCTAssertEqual(value.species,[.treeSparrow])
        let event=try XCTUnwrap(engine.events.first{$0.type == .completed && $0.runID==run})
        XCTAssertEqual(value.sequence,event.sequence);XCTAssertEqual(value.simulationTime,event.time)
        XCTAssertEqual(journal.archive.entries.first?.previewCount,1)
        advance(engine,seconds:1);XCTAssertEqual(observations.count,1)
    }

    func testRealFlockStillReportsActualSpeciesAfterEveryTransientWasRemoved() throws {
        let engine=fixture(),journal=ObservationJournal()
        var values:[BehaviorObservation]=[]
        engine.observationObserver={values.append($0);journal.observe($0,at:self.date)}
        let run=try runID(engine.handle(.flockPass(.preview)))
        let members=try XCTUnwrap(engine.events.last).participants
        let expected=Set(members.compactMap{engine.bird($0)?.profile.id}).sorted{$0.rawValue<$1.rawValue}
        XCTAssertFalse(expected.isEmpty)
        advance(engine,seconds:35)
        XCTAssertTrue(members.allSatisfy{engine.bird($0)==nil})
        XCTAssertEqual(values.count,1);XCTAssertEqual(values.first?.runID,run.rawValue)
        XCTAssertEqual(values.first?.species,expected)
        XCTAssertEqual(journal.archive.entries.map(\.species),expected)
        XCTAssertTrue(journal.archive.entries.allSatisfy{$0.previewCount==1 && $0.totalCount==1})
        XCTAssertEqual(engine.pendingCount,0);XCTAssertEqual(engine.passingCount,0)
    }

    func testDisabledFlockBeforeFirstStepCompletesWithoutInventingDiscovery() throws {
        let engine=fixture(),journal=ObservationJournal()
        var values:[BehaviorObservation]=[]
        engine.observationObserver={values.append($0);journal.observe($0,at:self.date)}
        let run=try runID(engine.handle(.flockPass(.preview)))
        let members=try XCTUnwrap(engine.events.last).participants
        XCTAssertEqual(engine.pendingCount,members.count);XCTAssertEqual(engine.passingCount,0)
        var settings=engine.settings;settings.flockPasses=false;engine.applySettings(settings)
        XCTAssertTrue(members.allSatisfy{engine.bird($0)==nil})
        engine.advance(BehaviorEngine.step)
        XCTAssertEqual(engine.events.filter{$0.runID==run && $0.type == .completed}.count,1)
        XCTAssertTrue(values.isEmpty);XCTAssertTrue(journal.archive.entries.isEmpty)
        XCTAssertEqual(journal.revision,0)
    }

    func testShownFlockThatNeverIntersectsDisplayDoesNotBecomeDiscovery() throws {
        let engine=fixture(species:[]),journal=ObservationJournal()
        let member=flockMember(in:engine,species:.mallard,y:screen.minY-300)
        var values:[BehaviorObservation]=[]
        engine.observationObserver={values.append($0);journal.observe($0,at:self.date)}
        let run=try runID(engine.runtime.start(FlockPassExecution(members:[member]),source:.preview,in:engine))
        engine.advance(BehaviorEngine.step)
        let bird=try XCTUnwrap(engine.bird(member.0))
        XCTAssertEqual(engine.passingCount,1)
        XCTAssertFalse(engine.world.displays.contains{$0.intersects(engine.bounds(of:bird))})
        var settings=engine.settings;settings.flockPasses=false;engine.applySettings(settings)
        advance(engine,seconds:6)
        XCTAssertNil(engine.bird(member.0))
        XCTAssertEqual(engine.events.filter{$0.runID==run && $0.type == .completed}.count,1)
        XCTAssertTrue(values.isEmpty);XCTAssertTrue(journal.archive.entries.isEmpty)
    }

    func testMixedFlockReportsOnlySpeciesThatActuallyEnteredDisplay() throws {
        let engine=fixture(species:[]),journal=ObservationJournal()
        let first=flockMember(in:engine,species:.treeSparrow,y:200)
        let duplicate=flockMember(in:engine,species:.treeSparrow,y:250)
        let second=flockMember(in:engine,species:.lightVentedBulbul,y:300)
        let hidden=flockMember(in:engine,species:.barnSwallow,delay:10,y:350)
        let offscreen=flockMember(in:engine,species:.mallard,y:screen.minY-300)
        let members=[first,duplicate,second,hidden,offscreen]
        var values:[BehaviorObservation]=[]
        engine.observationObserver={values.append($0);journal.observe($0,at:self.date)}
        let run=try runID(engine.runtime.start(FlockPassExecution(members:members),source:.preview,in:engine))
        advance(engine,seconds:1)
        XCTAssertEqual(engine.pendingCount,1);XCTAssertEqual(engine.passingCount,4)
        for member in [first,duplicate,second] {
            let bird=try XCTUnwrap(engine.bird(member.0))
            XCTAssertTrue(engine.world.displays.contains{$0.intersects(engine.bounds(of:bird))})
        }
        let outside=try XCTUnwrap(engine.bird(offscreen.0))
        XCTAssertFalse(engine.world.displays.contains{$0.intersects(engine.bounds(of:outside))})
        var settings=engine.settings;settings.flockPasses=false;engine.applySettings(settings)
        XCTAssertNil(engine.bird(hidden.0))
        advance(engine,seconds:6)
        XCTAssertTrue(members.allSatisfy{engine.bird($0.0)==nil})
        XCTAssertEqual(values.count,1);XCTAssertEqual(values.first?.runID,run.rawValue)
        XCTAssertEqual(values.first?.species,[.lightVentedBulbul,.treeSparrow])
        XCTAssertEqual(journal.archive.entries.map(\.species),[.lightVentedBulbul,.treeSparrow])
        XCTAssertTrue(journal.archive.entries.allSatisfy{$0.previewCount==1 && $0.totalCount==1})
    }

    func testEveryDiscoveryKindAndSourceIncludesSortedDeduplicatedActualSpecies() throws {
        for (index,kind) in kinds.enumerated() {
            let engine=fixture(species:[.treeSparrow,.littleOwl,.treeSparrow])
            let ids=engine.birds.compactMap{engine.id(of:$0)}
            var values:[BehaviorObservation]=[]
            engine.observationObserver={values.append($0)}
            let source:[BehaviorSource]=[.automatic,.preview,.user]
            let run=try runID(engine.runtime.start(CompletionExecution(kind:kind,participants:ids,removeParticipants:true),
                                                  source:source[index%3],in:engine))
            engine.runtime.advance(BehaviorEngine.step,in:engine)
            engine.runtime.advance(BehaviorEngine.step,in:engine)
            XCTAssertEqual(values.count,1,kind.rawValue)
            XCTAssertEqual(values.first?.species,[.littleOwl,.treeSparrow])
            XCTAssertEqual(values.first?.source,source[index%3]);XCTAssertEqual(values.first?.runID,run.rawValue)
            XCTAssertTrue(engine.birds.isEmpty)
        }
    }

    func testRealCancelledFailedRejectedAndRelocationDoNotBecomeDiscoveries() throws {
        let cancelled=fixture(),failed=fixture(),relocated=fixture(),empty=fixture(species:[])
        var values:[BehaviorObservation]=[]
        for engine in [cancelled,failed,relocated,empty] {engine.observationObserver={values.append($0)}}
        let cancellation=try runID(cancelled.handle(.pointerVisit(.preview)))
        cancelled.handle(.pointerClick);advance(cancelled,seconds:1)
        XCTAssertTrue(cancelled.events.contains{$0.runID==cancellation && $0.type == .cancelled})

        let failure=try runID(failed.handle(.pointerVisit(.preview)))
        failed.birds[0].perch(on:host)
        failed.advance(BehaviorEngine.step)
        XCTAssertTrue(failed.events.contains{$0.runID==failure && $0.type == .failed})

        let relocation=try runID(relocated.handle(.relocate(try XCTUnwrap(relocated.id(of:relocated.birds[0])))))
        advance(relocated,seconds:12)
        XCTAssertTrue(relocated.events.contains{$0.runID==relocation && $0.type == .completed})
        XCTAssertFalse(empty.handle(.pointerVisit(.preview)).accepted)
        XCTAssertTrue(empty.events.contains{$0.type == .rejected})
        _=try runID(empty.runtime.start(CompletionExecution(kind:.rest,participants:[]),source:.automatic,in:empty))
        empty.runtime.advance(BehaviorEngine.step,in:empty)
        XCTAssertTrue(values.isEmpty)
    }

    func testObserverDoesNotChangeRandomStreamsRecordingOrReplayReport() throws {
        func recorded(withObserver:Bool) throws -> (Data,Double,Double,Int) {
            let engine=BehaviorEngine(seed:817,recordInputs:true),journal=ObservationJournal()
            engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
            engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host]))
            if withObserver {engine.observationObserver={_ = journal.observe($0,at:self.date)}}
            for source:BehaviorSource in [.automatic,.preview,.user] {
                _=try runID(engine.handle(.flockPass(source)))
                advance(engine,seconds:35)
            }
            let log=try engine.recordedInputs()
            let replay=try log.replay()
            XCTAssertEqual(replay,log.expected)
            return (try BehaviorInputLog.encoder().encode(log),engine.random.unit(),engine.ecologyRandom.unit(),journal.archive.entries.count)
        }
        let baseline=try recorded(withObserver:false),observed=try recorded(withObserver:true)
        XCTAssertEqual(baseline.0,observed.0);XCTAssertEqual(baseline.1,observed.1);XCTAssertEqual(baseline.2,observed.2)
        XCTAssertEqual(baseline.3,0);XCTAssertGreaterThan(observed.3,0)
    }

    func testSpeciesDeduplicationSourceCountsAndSequenceDeduplication() throws {
        let journal=ObservationJournal(),species:[SpeciesID]=[.treeSparrow,.littleOwl,.treeSparrow]
        XCTAssertTrue(journal.observe(observation(10,runID:100,source:.automatic,species:species),at:date))
        XCTAssertFalse(journal.observe(observation(10,runID:100,source:.automatic,species:species),at:date))
        XCTAssertFalse(journal.observe(observation(9,runID:99,species:species),at:date))
        XCTAssertTrue(journal.observe(observation(11,runID:101,source:.preview,species:species),at:date))
        XCTAssertTrue(journal.observe(observation(12,runID:102,source:.user,species:species),at:date))
        XCTAssertEqual(journal.archive.entries.map(\.species),[.littleOwl,.treeSparrow])
        for value in journal.archive.entries {
            XCTAssertEqual(value.automaticCount,1);XCTAssertEqual(value.previewCount,1)
            XCTAssertEqual(value.userCount,1);XCTAssertEqual(value.totalCount,3)
        }
        XCTAssertEqual(journal.revision,3);try journal.archive.validate()
    }

    func testLateLowRunIDAfterThousandsOfNewerCompletionsStillCounts() {
        let journal=ObservationJournal()
        for sequence:UInt64 in 1...5000 {
            XCTAssertTrue(journal.observe(observation(sequence,runID:sequence+1),at:date))
        }
        XCTAssertTrue(journal.observe(observation(5001,runID:1),at:date))
        XCTAssertEqual(journal.archive.entries.first?.automaticCount,5001)
        XCTAssertEqual(journal.archive.entries.count,1)
    }

    func testRuntimeLateCompletionSurvivesThousandsOfNewRunsAndEventRingRollover() throws {
        let engine=fixture(species:[.littleOwl,.treeSparrow]),journal=ObservationJournal()
        let ids=engine.birds.compactMap{engine.id(of:$0)}
        let older=CompletionExecution(kind:.rest,participants:[ids[0]])
        older.ready=false
        let olderID=try runID(engine.runtime.start(older,source:.automatic,in:engine))
        engine.observationObserver={_ = journal.observe($0,at:self.date)}
        for _ in 0..<3000 {
            _=try runID(engine.runtime.start(CompletionExecution(kind:.preen,participants:[ids[1]]),source:.preview,in:engine))
            engine.runtime.advance(BehaviorEngine.step,in:engine)
        }
        XCTAssertEqual(engine.activeRunCount,1);XCTAssertEqual(engine.events.count,256)
        older.ready=true
        engine.runtime.advance(BehaviorEngine.step,in:engine)
        XCTAssertEqual(engine.events.last?.runID,olderID)
        XCTAssertEqual(journal.archive.entries.first{$0.species == .littleOwl}?.automaticCount,1)
        XCTAssertEqual(journal.archive.entries.first{$0.species == .treeSparrow}?.previewCount,3000)
        XCTAssertEqual(engine.activeRunCount,0)
    }

    func testRestorationIsValidatedAndOnlyAllowedBeforeObservation() throws {
        let journal=ObservationJournal(),archive=ObservationArchive(entries:[entry()])
        XCTAssertEqual(journal.revision,0);try journal.restore(archive)
        XCTAssertEqual(journal.archive,archive);XCTAssertEqual(journal.revision,1)
        try journal.restore(archive);XCTAssertEqual(journal.revision,1)
        XCTAssertTrue(journal.observe(observation(1),at:date))
        let before=journal.archive,revision=journal.revision
        XCTAssertThrowsError(try journal.restore(.init()))
        XCTAssertEqual(journal.archive,before);XCTAssertEqual(journal.revision,revision)
        let fresh=ObservationJournal()
        XCTAssertThrowsError(try fresh.restore(.init(entries:[entry(count:-1)])))
        XCTAssertEqual(fresh.archive,.init());XCTAssertEqual(fresh.revision,0)
        XCTAssertTrue(fresh.observe(observation(1),at:date))
    }

    func testInvalidObservationsAndDatesDoNotPoisonSequenceOrChangeRevision() {
        let journal=ObservationJournal()
        let invalid=[observation(0),observation(99,runID:0),observation(99,kind:.relocate),
                     observation(99,species:[]),observation(99,simulationTime:.nan),
                     observation(99,simulationTime:.infinity),observation(99,simulationTime:-1)]
        for value in invalid {XCTAssertFalse(journal.observe(value,at:date))}
        for timestamp in [-1.0,Double.nan,Double.infinity,ObservationArchive.maximumTimestamp+1] {
            XCTAssertFalse(journal.observe(observation(99),at:Date(timeIntervalSince1970:timestamp)))
        }
        XCTAssertEqual(journal.revision,0);XCTAssertTrue(journal.archive.entries.isEmpty)
        XCTAssertTrue(journal.observe(observation(1),at:Date(timeIntervalSince1970:0)))
        XCTAssertTrue(journal.observe(observation(2),at:Date(timeIntervalSince1970:ObservationArchive.maximumTimestamp)))
    }

    func testMonotonicDatesSaturatingCountsAndNoOpRevision() throws {
        let capped=ObservationEntry(species:.treeSparrow,behavior:"rest",firstSeen:date,lastSeen:date,
                                    automaticCount:ObservationArchive.maximumCount,previewCount:ObservationArchive.maximumCount,
                                    userCount:ObservationArchive.maximumCount)
        let journal=ObservationJournal();try journal.restore(.init(entries:[capped]))
        let revision=journal.revision
        for (index,source) in [BehaviorSource.automatic,.preview,.user].enumerated() {
            XCTAssertFalse(journal.observe(observation(UInt64(index+1),source:source),at:date.addingTimeInterval(-100)))
        }
        XCTAssertEqual(journal.revision,revision);XCTAssertEqual(journal.archive.entries,[capped])
        XCTAssertTrue(journal.observe(observation(4),at:date.addingTimeInterval(50)))
        let value=try XCTUnwrap(journal.archive.entries.first)
        XCTAssertEqual(value.firstSeen,date);XCTAssertEqual(value.lastSeen,date.addingTimeInterval(50))
        XCTAssertEqual(value.totalCount,3*ObservationArchive.maximumCount)
        try journal.archive.validate()
    }

    func testDeterministicBoundedAggregationAcrossAllSpeciesAndBehaviors() throws {
        let a=ObservationJournal(),b=ObservationJournal()
        var sequence:UInt64=0
        for pass in 0..<5 {
            for species in SpeciesID.allCases {
                for kind in kinds {
                    sequence+=1
                    let list=pass.isMultiple(of:2) ? [species,.treeSparrow,species]:[.treeSparrow,species]
                    let value=observation(sequence,kind:kind,source:[.automatic,.preview,.user][pass%3],species:list)
                    let timestamp=date.addingTimeInterval(Double(pass))
                    XCTAssertEqual(a.observe(value,at:timestamp),b.observe(value,at:timestamp))
                }
            }
        }
        XCTAssertEqual(a.archive,b.archive);XCTAssertEqual(a.revision,b.revision)
        XCTAssertEqual(a.archive.entries.count,SpeciesID.allCases.count*kinds.count)
        XCTAssertLessThanOrEqual(a.archive.entries.count,ObservationArchive.maximumEntries)
        XCTAssertLessThan(try JSONEncoder().encode(a.archive).count,ObservationArchive.maximumBytes)
        try a.archive.validate()
        let restored=ObservationJournal();try restored.restore(a.archive)
        XCTAssertTrue(restored.observe(observation(1),at:date))
    }

    func testArchiveRoundTripCreatesParentsAndReplacesOnlyValidArchives() throws {
        let root=temporaryFolder(),target=root.appendingPathComponent("nested/observations.json")
        defer {try? FileManager.default.removeItem(at:root)}
        let journal=ObservationJournal()
        journal.observe(observation(1),at:date)
        try journal.archive.save(to:target)
        XCTAssertEqual(try ObservationArchive.load(from:target),journal.archive)
        journal.observe(observation(2,source:.user),at:date.addingTimeInterval(1))
        try journal.archive.save(to:target)
        XCTAssertEqual(try ObservationArchive.load(from:target),journal.archive)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:target.deletingLastPathComponent().path),["observations.json"])
        XCTAssertEqual(try ObservationArchive.decode(JSONEncoder().encode(journal.archive)),journal.archive)
    }

    func testMalformedFutureAndCorruptDestinationsArePreserved() throws {
        let root=temporaryFolder(),target=root.appendingPathComponent("observations.json")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var corrupt=try object(.init(entries:[entry()]))
        var entries=try XCTUnwrap(corrupt["entries"] as? [[String:Any]])
        entries[0]["automaticCount"] = -1;corrupt["entries"]=entries
        let payloads=[try data(["formatVersion":3,"entries":"future schema"]),Data("broken json".utf8),
                      try data(corrupt),Data(repeating:32,count:ObservationArchive.maximumBytes+1)]
        for payload in payloads {
            try payload.write(to:target)
            XCTAssertThrowsError(try ObservationArchive.load(from:target))
            XCTAssertThrowsError(try ObservationArchive().save(to:target))
            XCTAssertEqual(try Data(contentsOf:target),payload)
        }
        let dangling=root.appendingPathComponent("dangling.json"),missing=root.appendingPathComponent("missing.json")
        try FileManager.default.createSymbolicLink(at:dangling,withDestinationURL:missing)
        XCTAssertThrowsError(try ObservationArchive().save(to:dangling))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath:dangling.path),missing.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path))
        XCTAssertThrowsError(try ObservationArchive.load(from:missing))
        XCTAssertThrowsError(try ObservationArchive().save(to:root))
    }

    func testRejectsVersionsUnknownBehaviorsSpeciesDuplicatesAndCorruptCounts() throws {
        let original=try object(.init(entries:[entry()]))
        for version:Any in [3,0,-1,true,"1",1.5,NSNull()] {
            XCTAssertThrowsError(try ObservationArchive.decode(data(["formatVersion":version,"entries":"future schema"])))
        }
        for payload in [Data(),Data("null".utf8),Data("[]".utf8),Data("{".utf8),Data("{}".utf8)] {
            XCTAssertThrowsError(try ObservationArchive.decode(payload))
        }
        let originalEntry=try XCTUnwrap(original["entries"] as? [[String:Any]])[0]
        let invalid:[(String,[Any])]=[
            ("species",["unknown",1,NSNull()]),("behavior",["unknown","relocate",1,NSNull()]),
            ("automaticCount",[-1,1_000_001,Int.max,1.5,true,"1"]),
            ("previewCount",[-1,1_000_001,true]),("userCount",[-1,1_000_001,true]),
            ("firstSeen",[Date(timeIntervalSince1970:-1).timeIntervalSinceReferenceDate,"NaN",true]),
            ("lastSeen",[Date(timeIntervalSince1970:ObservationArchive.maximumTimestamp+1).timeIntervalSinceReferenceDate,
                         date.addingTimeInterval(-1).timeIntervalSinceReferenceDate,"Infinity",true])]
        for (key,values) in invalid {
            for value in values {
                var raw=original,entry=originalEntry;entry[key]=value;raw["entries"]=[entry]
                XCTAssertThrowsError(try ObservationArchive.decode(data(raw)),"\(key): \(value)")
            }
            var raw=original,entry=originalEntry;entry.removeValue(forKey:key);raw["entries"]=[entry]
            XCTAssertThrowsError(try ObservationArchive.decode(data(raw)))
        }
        var raw=original;raw["entries"]=[originalEntry,originalEntry]
        XCTAssertThrowsError(try ObservationArchive.decode(data(raw)))
        XCTAssertThrowsError(try ObservationArchive(entries:[entry(count:0)]).validate())
        XCTAssertThrowsError(try ObservationArchive(entries:Array(repeating:entry(),count:ObservationArchive.maximumEntries+1)).validate())
        raw["entries"]=Array(repeating:originalEntry,count:ObservationArchive.maximumEntries+1)
        XCTAssertThrowsError(try ObservationArchive.decode(data(raw)))
    }

    func testNonfiniteDateViaCustomDecoderAndExactByteBoundary() throws {
        var raw=try object(.init(entries:[entry()]))
        var entry=try XCTUnwrap(raw["entries"] as? [[String:Any]])[0]
        let decoder=JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity:"Infinity",negativeInfinity:"-Infinity",nan:"NaN")
        for symbol in ["NaN","Infinity","-Infinity"] {
            entry["lastSeen"]=symbol;raw["entries"]=[entry]
            XCTAssertThrowsError(try decoder.decode(ObservationArchive.self,from:data(raw)))
        }
        let archive=ObservationArchive(entries:[self.entry()])
        var exact=try JSONEncoder().encode(archive)
        exact.append(Data(repeating:32,count:ObservationArchive.maximumBytes-exact.count))
        XCTAssertEqual(try ObservationArchive.decode(exact),archive)
        exact.append(32);XCTAssertThrowsError(try ObservationArchive.decode(exact))
    }
}
