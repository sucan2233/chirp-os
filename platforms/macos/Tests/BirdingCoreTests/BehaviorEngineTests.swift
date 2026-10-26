import XCTest
@testable import BirdingCore

final class BehaviorEngineTests:XCTestCase {
    private let screen=CGRect(x:-700,y:-200,width:1400,height:1000)
    private let host=Surface(id:41,rect:CGRect(x:-640,y:680,width:1280,height:100))

    private func fixture(seed:UInt64=73,count:Int=1) -> BehaviorEngine {
        let engine=BehaviorEngine(seed:seed)
        engine.populationEnabled=false;engine.ambientEnabled=false
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:0,y:300)))
        engine.installFixtureBirds((0..<count).map {index in
            let bird=Bird(position:.zero,fraction:count==1 ? 0.5:CGFloat(index+1)/CGFloat(count+1),
                          profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
            bird.perch(on:host);bird.perchDuration=600;return bird
        })
        return engine
    }
    private func advance(_ engine:BehaviorEngine,seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded(.up)) {engine.advance(1/Double(hz))}
    }
    private func runID(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line) throws -> BehaviorRunID {
        guard case .started(let id)=result else {
            XCTFail("Expected started, got \(result)",file:file,line:line)
            throw NSError(domain:"BehaviorEngineTests",code:1)
        }
        return id
    }
    private func terminals(_ engine:BehaviorEngine,_ id:BehaviorRunID) -> [BehaviorEvent] {
        engine.events.filter{$0.runID==id && [.completed,.cancelled,.failed].contains($0.type)}
    }

    func testFixedStepReplayAt30And60And120Hz() throws {
        struct Trace:Equatable {let positions:[CGPoint];let frames:[String];let events:[String];let counts:[Int]}
        func replay(hz:Int) throws -> [Trace] {
            let e=fixture();e.ambientEnabled=true
            var settings=e.settings;settings.ambientFrequency = .high;e.applySettings(settings)
            let bird=e.birds[0],id=e.id(of:bird)!
            var trace:[Trace]=[]
            // Preserve the whole scripted prefix, then allow bounded additional
            // opportunities after input suppression and reserved empty draws.
            for second in 0..<600 {
                switch second {
                case 0:_=try runID(e.handle(.pointerVisit(.preview)))
                case 2:e.handle(.pointerClick)
                case 3:_=try runID(e.handle(.relocate(id)))
                case 8:_=try runID(e.handle(.flockPass(.preview)))
                case 9:e.handle(.pause(true))
                case 11:e.handle(.pause(false))
                case 12:e.handle(.cancelAmbient(.screensChanged))
                case 14:_=try runID(e.handle(.flockPass(.preview)))
                default:break
                }
                advance(e,seconds:1,hz:hz)
                let states=e.renderSnapshot()
                trace.append(Trace(positions:states.map(\.position),frames:states.map(\.frameName),
                    events:e.events.map{"\($0.sequence):\($0.time):\($0.type):\($0.kind?.rawValue ?? ""):\($0.reason?.rawValue ?? ""):\($0.participants.map(\.rawValue))"},
                    counts:[e.residentCount,e.passingCount,e.pendingCount,e.activeRunCount,e.leasedBirdCount]))
                if second>=149,e.events.contains(where:{$0.type == .started && $0.source == .automatic}) {break}
            }
            XCTAssertTrue(e.events.contains{$0.type == .started && $0.source == .automatic})
            return trace
        }
        let reference=try replay(hz:60)
        XCTAssertEqual(try replay(hz:30),reference)
        XCTAssertEqual(try replay(hz:120),reference)
    }

    func testClickPreemptsVisitAndRepeatedClickCannotRestartRelocation() throws {
        let e=fixture(),bird=e.birds[0],id=e.id(of:e.birds[0])!
        let visit=try runID(e.handle(.pointerVisit(.preview)))
        advance(e,seconds:0.5)
        let position=bird.position
        let relocation=try runID(e.handle(.relocate(id)))
        XCTAssertEqual(bird.position,position)
        XCTAssertEqual(e.behavior(of:bird),.relocate)
        XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
        XCTAssertEqual(terminals(e,visit).map(\.reason),[.replaced])
        let revision=bird.motionRevision
        XCTAssertEqual(e.handle(.relocate(id)),.rejected(.busy))
        XCTAssertEqual(bird.motionRevision,revision)
        e.handle(.pointerClick)
        XCTAssertEqual(e.behavior(of:bird),.relocate)
        advance(e,seconds:10)
        XCTAssertEqual(terminals(e,relocation).map(\.type),[.completed])
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.residentCount,1)
        XCTAssertTrue(e.birds[0] === bird)
    }

    func testPauseFreezesAutonomyButManualRelocationCanFinish() throws {
        let e=fixture(count:2),bird=e.birds[0],other=e.birds[1]
        let id=try runID(e.handle(.relocate(e.id(of:bird)!)))
        e.handle(.pause(true))
        let origin=bird.position,otherPosition=other.position,otherAge=other.stateTime
        let remaining=e.scheduler.remaining,populationRemaining=e.population.remaining
        advance(e,seconds:10)
        XCTAssertGreaterThan(Geometry.distance(origin,bird.position),100)
        XCTAssertEqual(bird.state,.perched)
        XCTAssertEqual(other.position,otherPosition);XCTAssertEqual(other.stateTime,otherAge)
        XCTAssertEqual(e.scheduler.remaining,remaining);XCTAssertEqual(e.population.remaining,populationRemaining)
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
        XCTAssertEqual(e.handle(.flockPass(.preview)),.rejected(.paused))
        XCTAssertEqual(e.handle(.pointerVisit(.automatic)),.rejected(.paused))
    }

    func testPointerMovementAndClickCancelWithOneTerminalAndContinuousRecovery() throws {
        for buttons in [false,true] {
            let e=fixture(),bird=e.birds[0]
            let id=try runID(e.handle(.pointerVisit(.preview)))
            advance(e,seconds:0.5)
            let position=bird.position,revision=bird.motionRevision
            var world=e.world;world.buttonsDown=buttons
            if !buttons {world.pointer.x+=30}
            e.updateWorld(world);e.advance(BehaviorEngine.step)
            XCTAssertLessThan(Geometry.distance(position,bird.position),10)
            XCTAssertGreaterThan(bird.motionRevision,revision)
            XCTAssertEqual(terminals(e,id).map(\.type),[.cancelled])
            XCTAssertEqual(terminals(e,id).first?.reason,buttons ? .userInput:.pointerMoved)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertFalse(bird.isDeparting)
        }
    }

    func testPointerCompletesAndPauseOrDisableCancelsSafely() throws {
        let e=fixture(),bird=e.birds[0],origin=e.birds[0].position
        let first=try runID(e.handle(.pointerVisit(.preview)))
        advance(e,seconds:bird.flightDuration+1)
        XCTAssertEqual(terminals(e,first).map(\.type),[.completed])
        XCTAssertEqual(bird.position,origin);XCTAssertEqual(e.leasedBirdCount,0)
        for pause in [false,true] {
            let next=try runID(e.handle(.pointerVisit(.preview)))
            let position=bird.position
            if pause {e.handle(.pause(true))}
            else {var settings=e.settings;settings.pointerVisits=false;e.applySettings(settings)}
            XCTAssertEqual(bird.position,position)
            XCTAssertEqual(terminals(e,next).map(\.type),[.cancelled])
            XCTAssertEqual(terminals(e,next).first?.reason,pause ? .paused:.settingsChanged)
            bird.perch(on:host)
            var settings=e.settings;settings.pointerVisits=true;e.applySettings(settings)
        }
    }

    func testFlockOwnsEncounterAndPausesPendingMembers() throws {
        let e=fixture()
        let id=try runID(e.handle(.flockPass(.preview)))
        let members=e.events.last!.participants
        XCTAssertTrue((3...5).contains(members.count))
        XCTAssertEqual(e.pendingCount,members.count)
        XCTAssertEqual(e.handle(.pointerVisit(.preview)),.rejected(.busy))
        XCTAssertEqual(e.handle(.flockPass(.automatic)),.rejected(.busy))
        e.handle(.pause(true));advance(e,seconds:10)
        XCTAssertEqual(e.pendingCount,members.count);XCTAssertEqual(e.passingCount,0)
        XCTAssertTrue(terminals(e,id).isEmpty)
        e.handle(.pause(false))
        var appearances:[BirdID:Int]=[:]
        for tick in 0..<60*30 {
            e.advance(BehaviorEngine.step)
            for state in e.renderSnapshot() where members.contains(state.id) && appearances[state.id]==nil {appearances[state.id]=tick}
            XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.departingCount,0)
            XCTAssertLessThanOrEqual(e.passingCount+e.pendingCount,5)
        }
        XCTAssertEqual(Set(appearances.values).count,members.count)
        XCTAssertEqual(e.birds.count,1);XCTAssertEqual(e.pendingCount,0);XCTAssertEqual(e.departureCount,0)
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
    }

    func testDisablingFlockDropsOnlyPendingAndLetsVisibleVisitorsLeave() throws {
        let e=fixture()
        let id=try runID(e.handle(.flockPass(.preview)))
        advance(e,seconds:0.2)
        let visible=e.passingCount
        XCTAssertEqual(visible,1);XCTAssertGreaterThan(e.pendingCount,0)
        var settings=e.settings;settings.flockPasses=false;e.applySettings(settings)
        XCTAssertEqual(e.pendingCount,0);XCTAssertEqual(e.passingCount,visible)
        XCTAssertEqual(e.handle(.flockPass(.preview)),.rejected(.disabled))
        advance(e,seconds:30)
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
        XCTAssertEqual(e.birds.count,1);XCTAssertEqual(e.leasedBirdCount,0)
    }

    func testLifecycleChangesCleanAllPendingMembersAndLeasesIdempotently() throws {
        for reason:BehaviorReason in [.sleep,.screensChanged,.spaceChanged,.shutdown] {
            for elapsed in [0.0,0.2,2.0] {
                let e=fixture(),resident=e.birds[0]
                let move=try runID(e.handle(.relocate(e.id(of:resident)!)))
                let flock=try runID(e.handle(.flockPass(.preview)))
                advance(e,seconds:elapsed)
                e.handle(.cancelAmbient(reason));e.handle(.cancelAmbient(reason))
                XCTAssertEqual(e.birds.count,1);XCTAssertTrue(e.birds[0] === resident)
                XCTAssertEqual(e.pendingCount,0);XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
                XCTAssertEqual(terminals(e,flock).map(\.type),[.cancelled])
                XCTAssertEqual(terminals(e,flock).first?.reason,reason)
                XCTAssertEqual(terminals(e,move).count,1)
            }
        }
    }

    func testRemovingFlockParticipantCancelsWholeSessionWithoutGhosts() throws {
        let e=fixture()
        let id=try runID(e.handle(.flockPass(.preview)))
        let members=e.events.last!.participants
        e.handle(.remove(members.last!))
        XCTAssertEqual(terminals(e,id).map(\.type),[.cancelled])
        XCTAssertEqual(e.pendingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
        for member in members {
            XCTAssertNil(e.bird(member))
            XCTAssertEqual(e.events.filter{$0.type == .birdRemoved && $0.participants == [member]}.count,1)
        }
        advance(e,seconds:5);XCTAssertEqual(e.birds.count,1)
    }

    func testTargetInvalidationReplansRelocationAndStillAvoidsOriginalSpot() throws {
        let e=fixture(),bird=e.birds[0],origin=e.birds[0].position
        let id=try runID(e.handle(.relocate(e.id(of:bird)!)))
        let revision=bird.motionRevision
        let alternative=Surface(id:42,rect:CGRect(x:-640,y:470,width:1280,height:100))
        var world=e.world;world.surfaces=[alternative]
        e.updateWorld(world,sampleDT:1.0/30)
        XCTAssertEqual(bird.position,origin)
        XCTAssertGreaterThan(bird.motionRevision,revision)
        e.advance(BehaviorEngine.step)
        XCTAssertEqual(bird.hostID,alternative.id)
        advance(e,seconds:10)
        XCTAssertGreaterThan(Geometry.distance(origin,bird.position),100)
        XCTAssertEqual(terminals(e,id).map(\.type),[.completed])
        XCTAssertEqual(e.leasedBirdCount,0)
    }

    func testLostPointerTargetFailsOnceAndRecoversThroughNormalRouting() throws {
        let e=fixture(),bird=e.birds[0]
        let id=try runID(e.handle(.pointerVisit(.automatic)))
        var world=e.world;world.surfaces=[]
        e.updateWorld(world,sampleDT:1.0/30);e.advance(BehaviorEngine.step)
        XCTAssertEqual(terminals(e,id).map(\.type),[.failed])
        XCTAssertEqual(terminals(e,id).first?.reason,.targetInvalid)
        XCTAssertEqual(e.leasedBirdCount,0);XCTAssertNil(bird.hostID)
        advance(e,seconds:5)
        XCTAssertEqual(terminals(e,id).count,1);XCTAssertEqual(e.residentCount,1)
    }

    func testPreviewAndAutomaticUseIdenticalRejectionRules() {
        let e=fixture(),id=e.id(of:e.birds[0])!
        XCTAssertEqual(e.handle(.relocate(BirdID(999))),.rejected(.missingBird))
        var settings=e.settings;settings.pointerVisits=false;settings.flockPasses=false;e.applySettings(settings)
        for source:BehaviorSource in [.preview,.automatic] {
            XCTAssertEqual(e.handle(.pointerVisit(source)),.rejected(.disabled))
            XCTAssertEqual(e.handle(.flockPass(source)),.rejected(.disabled))
        }
        settings.pointerVisits=true;settings.flockPasses=true
        var solo=settings.catalog;solo.species=[solo.profile(.commonKestrel)]
        for entry in settings.probabilities.entries { settings.probabilities.setWeight(entry.id == .commonKestrel ? 1 : 0, for: entry.id) }; settings.probabilities.manualAdjustmentEnabled=true;e.applySettings(settings)
        for source:BehaviorSource in [.preview,.automatic] {XCTAssertEqual(e.handle(.flockPass(source)),.rejected(.noSpecies))}
        e.updateWorld(BehaviorWorld())
        XCTAssertEqual(e.handle(.relocate(id)),.rejected(.noSpace))
        for source:BehaviorSource in [.preview,.automatic] {
            XCTAssertEqual(e.handle(.pointerVisit(source)),.rejected(.noSpace))
            XCTAssertEqual(e.handle(.flockPass(source)),.rejected(.noSpace))
        }
    }

    func testDelayedPreviewReservesEncounterAndReportsStartOrCancellation() {
        let e=fixture()
        XCTAssertEqual(e.handle(.previewPointerAfter(3)),.scheduled)
        XCTAssertEqual(e.handle(.previewPointerAfter(3)),.rejected(.busy))
        XCTAssertEqual(e.handle(.flockPass(.preview)),.rejected(.busy))
        advance(e,seconds:2)
        XCTAssertEqual(e.activeRunCount,0)
        advance(e,seconds:1.1)
        XCTAssertFalse(e.hasPointerPreview);XCTAssertEqual(e.activeRunCount,1)
        XCTAssertEqual(e.events.filter{$0.type == .previewResult}.count,1)
        XCTAssertNil(e.events.last(where:{$0.type == .previewResult})?.reason)
        e.handle(.pause(true))
        XCTAssertEqual(e.activeRunCount,0)
        e.handle(.pause(false))
        XCTAssertEqual(e.handle(.previewPointerAfter(3)),.scheduled)
        e.handle(.pause(true));advance(e,seconds:4)
        XCTAssertFalse(e.hasPointerPreview)
        XCTAssertEqual(e.events.last(where:{$0.type == .previewResult})?.reason,.paused)
        e.handle(.pause(false));advance(e,seconds:4)
        XCTAssertEqual(e.activeRunCount,0)
    }

    func testSnapshotsAreValuesAndRemovedIDsAreNotReused() throws {
        let e=fixture(),bird=e.birds[0]
        let before=try XCTUnwrap(e.renderSnapshot().first)
        _=try runID(e.handle(.relocate(before.id)))
        advance(e,seconds:0.2)
        XCTAssertNotEqual(e.renderSnapshot().first?.position,before.position)
        XCTAssertEqual(before.position,Geometry.foot(on:host,fraction:0.5,edge:.top))
        e.handle(.remove(before.id))
        XCTAssertTrue(e.renderSnapshot().isEmpty);XCTAssertEqual(e.leasedBirdCount,0)
        e.installFixtureBirds([bird])
        XCTAssertGreaterThan(try XCTUnwrap(e.id(of:bird)),before.id)
        XCTAssertEqual(e.events.filter{$0.type == .birdRemoved && $0.participants == [before.id]}.count,1)
    }

    func testTimeoutReleasesResourcesAndLogHasBoundedMonotonicSequence() throws {
        final class Stalled:BehaviorExecution {
            let kind:BehaviorKind = .relocate
            let participants:[BirdID]
            let occupiesEncounter=false,runsWhilePaused=true,timeout=0.05
            var cancellations:[BehaviorReason]=[]
            init(_ id:BirdID) {participants=[id]}
            func start(in engine:BehaviorEngine) {}
            func advance(_ dt:Double,in engine:BehaviorEngine) -> BehaviorCompletion? {nil}
            func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {cancellations.append(reason)}
        }
        let e=fixture()
        let actual=Stalled(e.id(of:e.birds[0])!)
        let id=try runID(e.runtime.start(actual,source:.user,in:e))
        advance(e,seconds:1)
        XCTAssertEqual(actual.cancellations,[.timedOut])
        XCTAssertEqual(terminals(e,id).map(\.type),[.failed]);XCTAssertEqual(e.leasedBirdCount,0)
        e.handle(.cancelAmbient(.shutdown))
        XCTAssertEqual(terminals(e,id).count,1)
        for _ in 0..<400 {e.handle(.relocate(BirdID(999)))}
        XCTAssertEqual(e.events.count,256)
        XCTAssertEqual(Set(e.events.map(\.sequence)).count,256)
        XCTAssertEqual(e.events.map(\.sequence),e.events.map(\.sequence).sorted())
    }

    func testLongOrInvalidElapsedTimeCannotCreateCatchUpBurst() {
        let e=fixture();e.populationEnabled=true
        e.advance(.nan);e.advance(.infinity);e.advance(-1)
        XCTAssertEqual(e.time,0)
        e.advance(3600)
        XCTAssertEqual(e.time,0.05,accuracy:0.000001)
        XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.residentCount,1)
    }
}
