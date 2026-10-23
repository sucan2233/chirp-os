import XCTest
@testable import BirdingCore

final class TemperamentTests:XCTestCase {
    private let seed:UInt64=73
    private let id=BirdID(1)
    private let still=BirdStimulus(near:false,inAttentionRange:false,fastPass:false,click:false)
    private let watching=BirdStimulus(near:false,inAttentionRange:true,fastPass:false,click:false)
    private let passing=BirdStimulus(near:false,inAttentionRange:true,fastPass:true,click:false)
    private let clicking=BirdStimulus(near:true,inAttentionRange:true,fastPass:false,click:true)

    private func bird(_ species:SpeciesID = .treeSparrow) -> Bird {
        let bird=Bird(position:.zero,fraction:0.5,
            profile:SpeciesCatalog.standard.profile(species),random:{0.5})
        bird.perch(on:Surface(id:71,rect:CGRect(x:0,y:800,width:1200,height:400)))
        bird.perchDuration=600
        return bird
    }

    private func fixture(count:Int=1) -> PerchActivityPlanner {
        let planner=PerchActivityPlanner(seed:seed)
        for value in 1...count {planner.register(BirdID(UInt64(value)),bird:bird())}
        return planner
    }

    func testStableIndividualTraitsIgnoreSpeciesObjectAndRegistrationOrder() throws {
        let forward=fixture(count:32),reverse=PerchActivityPlanner(seed:seed)
        for value in (1...32).reversed() {reverse.register(BirdID(UInt64(value)),bird:bird(.redWhiskeredBulbul))}
        var traits:[BirdTemperament]=[]
        for value in 1...32 {
            let birdID=BirdID(UInt64(value))
            let snapshot=try XCTUnwrap(forward.ecology(birdID))
            XCTAssertEqual(snapshot,reverse.ecology(birdID))
            XCTAssertEqual(snapshot.temperament,BirdTemperament(seed:seed,birdID:birdID))
            let t=snapshot.temperament
            for trait in [t.boldness,t.curiosity,t.sociability,t.activity] {
                XCTAssertTrue((0.2...0.8).contains(trait))
            }
            traits.append(t)
        }
        XCTAssertEqual(Set(traits.map(\.boldness)).count,32)
        XCTAssertEqual(Set(traits.map(\.curiosity)).count,32)
        XCTAssertEqual(Set(traits.map(\.sociability)).count,32)
        XCTAssertEqual(Set(traits.map(\.activity)).count,32)
        XCTAssertNotEqual(traits[0],BirdTemperament(seed:seed+1,birdID:id))
        XCTAssertEqual(BirdTemperament(boldness:-1,curiosity:2,sociability:.nan,activity:.infinity),
            BirdTemperament(boldness:0.2,curiosity:0.8,sociability:0.5,activity:0.5))
    }

    func testEcologyDoesNotConsumePoseSelectionOrFlightRandomDomains() throws {
        let observedEngine=BehaviorEngine(seed:seed),controlEngine=BehaviorEngine(seed:seed)
        observedEngine.installFixtureBirds((0..<8).map{_ in bird()})
        controlEngine.installFixtureBirds((0..<8).map{_ in bird()})
        let observed=observedEngine.perchPlanner,control=controlEngine.perchPlanner
        let ids=observedEngine.birds.compactMap{observedEngine.id(of:$0)}
        XCTAssertEqual(ids.count,8)
        for _ in 0..<20 {
            for birdID in ids {
                observed.observe(birdID,stimulus:watching,dt:1)
                _=observed.attentionCandidate(birdID)
                observed.observe(birdID,stimulus:passing,dt:0.1)
                observed.noteClick(birdID)
                observed.observe(birdID,stimulus:still,dt:30)
                _=BirdTemperament(seed:seed,birdID:birdID)
            }
        }
        for birdID in ids {
            for kind in PerchActionKind.allCases {
                let a=try XCTUnwrap(observed.plan(kind,for:birdID))
                let b=try XCTUnwrap(control.plan(kind,for:birdID))
                XCTAssertEqual(a.duration,b.duration);XCTAssertEqual(a.rate,b.rate)
            }
            XCTAssertEqual(observed.rhythms[birdID]?.nextRest,control.rhythms[birdID]?.nextRest)
        }
        for _ in 0..<32 {
            XCTAssertEqual(observed.select(ids),control.select(ids))
            XCTAssertEqual(observedEngine.random.unit(),controlEngine.random.unit())
        }
    }

    func testDisturbanceHasSixSecondHalfLifeAndCallerPauseFreezesMemory() throws {
        let planner=fixture(),control=fixture()
        planner.noteClick(id);control.noteClick(id)
        let initial=try XCTUnwrap(planner.ecology(id))
        XCTAssertEqual(initial.disturbance,0.8*(1-initial.temperament.boldness),accuracy:1e-12)
        for _ in 0..<100 {
            // A paused engine omits observe; diagnostics and gates are read-only.
            _=planner.attentionCandidate(id);_=planner.automaticWeight(id,kind:.rest)
            XCTAssertEqual(planner.ecology(id),initial)
        }
        planner.observe(id,stimulus:still,dt:6)
        for _ in 0..<60 {control.observe(id,stimulus:still,dt:0.1)}
        let after=try XCTUnwrap(planner.ecology(id)),stepped=try XCTUnwrap(control.ecology(id))
        XCTAssertEqual(after.disturbance,initial.disturbance/2,accuracy:1e-12)
        XCTAssertEqual(after.disturbance,stepped.disturbance,accuracy:1e-12)
        XCTAssertTrue(after.cooldowns.isEmpty)
        planner.observe(id,stimulus:still,dt:6)
        XCTAssertEqual(try XCTUnwrap(planner.ecology(id)).disturbance,initial.disturbance/4,accuracy:1e-12)
    }

    func testAllTraitsAffectActualAutomaticWeightsAndRestCadence() throws {
        let planner=fixture(count:32)
        var restWeights:[Double]=[],watchWeights:[Double]=[],socialWeights:[Double]=[],leafWeights:[Double]=[]
        for value in 1...32 {
            let birdID=BirdID(UInt64(value)),t=try XCTUnwrap(planner.ecology(BirdID(UInt64(value)))).temperament
            let rest=planner.automaticWeight(birdID,kind:.rest)
            let watch=planner.automaticWeight(birdID,kind:.watch)
            let social=planner.automaticWeight(birdID,kind:.socialGreeting)
            let leaf=planner.automaticWeight(birdID,kind:.leafPlay)
            XCTAssertEqual(rest,1.2-0.4*t.activity,accuracy:1e-12)
            XCTAssertEqual(watch,0.4+1.2*t.curiosity,accuracy:1e-12)
            XCTAssertEqual(social/(0.8+0.4*t.boldness),0.4+1.2*t.sociability,accuracy:1e-12)
            XCTAssertEqual(planner.automaticWeight(birdID,kind:.preen)/(0.9+0.2*t.curiosity),0.6+0.8*t.boldness,accuracy:1e-12)
            XCTAssertEqual(leaf,(0.3+1.4*t.curiosity)*(0.6+0.8*t.activity)*(0.7+0.6*t.boldness),accuracy:1e-12)
            restWeights.append(rest);watchWeights.append(watch);socialWeights.append(social);leafWeights.append(leaf)
        }
        for weights in [restWeights,watchWeights,socialWeights,leafWeights] {XCTAssertGreaterThan(Set(weights).count,1)}

        // Hold the original rhythm RNG fixed and vary activity alone.
        let calm=PerchActivityPlanner.Rhythm(seed:19,bird:bird(),
            temperament:BirdTemperament(boldness:0.5,curiosity:0.5,sociability:0.5,activity:0.2))
        let active=PerchActivityPlanner.Rhythm(seed:19,bird:bird(),
            temperament:BirdTemperament(boldness:0.5,curiosity:0.5,sociability:0.5,activity:0.8))
        XCTAssertGreaterThan(calm.nextRest,active.nextRest)
        XCTAssertEqual(calm.nextRest/active.nextRest,1.12/0.88,accuracy:1e-12)
        XCTAssertEqual(calm.restDuration,active.restDuration)
        XCTAssertEqual(calm.preenDuration,active.preenDuration)
        XCTAssertEqual(calm.preenRate,active.preenRate);XCTAssertEqual(calm.landingDelay,active.landingDelay)
        calm.suppress();active.suppress()
        XCTAssertEqual(calm.nextRest/active.nextRest,1.12/0.88,accuracy:1e-12)

        // The public candidate path actually uses the adjusted schedule.
        let solo=fixture(),perched=bird(),rhythm=try XCTUnwrap(solo.rhythms[id])
        let interval=rhythm.nextRest
        XCTAssertNil(solo.candidate(id,bird:perched,dt:interval-0.01,enabled:true,occupied:false,quiet:true))
        XCTAssertEqual(solo.candidate(id,bird:perched,dt:0.02,enabled:true,occupied:false,quiet:true),.rest)
    }

    func testHotBirdSuppressesQuietActivitiesAndColdBirdCannotAlert() throws {
        let planner=fixture()
        let quietKinds:[BehaviorKind]=[.rest,.preen,.socialGreeting,.sideBySide,.giveWay,.pairedTakeoff,.leafPlay,.watch]
        for kind in quietKinds {XCTAssertGreaterThan(planner.automaticWeight(id,kind:kind),0)}
        XCTAssertEqual(planner.automaticWeight(id,kind:.alert),0)
        for _ in 0..<8 {planner.noteClick(id)}
        XCTAssertEqual(planner.ecology(id)?.disturbance,1)
        for kind in quietKinds {XCTAssertEqual(planner.automaticWeight(id,kind:kind),0)}
        // Click cooldown elapses while disturbance stays above the alert threshold.
        planner.observe(id,stimulus:still,dt:4)
        XCTAssertGreaterThan(planner.automaticWeight(id,kind:.alert),0)
        XCTAssertNil(planner.attentionCandidate(id),"Disturbance alone cannot synthesize a fast-pass event")
        planner.observe(id,stimulus:still,dt:20)
        for kind in quietKinds {XCTAssertGreaterThan(planner.automaticWeight(id,kind:kind),0)}
        XCTAssertEqual(planner.automaticWeight(id,kind:.alert),0)
    }

    func testFastPassAndHeldClickAreEdgesWithNoPerFrameRepetition() throws {
        let planner=fixture(),t=try XCTUnwrap(planner.ecology(id)).temperament
        planner.observe(id,stimulus:passing,dt:0)
        let initial=0.65*(1-t.boldness)
        XCTAssertEqual(try XCTUnwrap(planner.ecology(id)).disturbance,initial,accuracy:1e-12)
        XCTAssertEqual(planner.attentionCandidate(id),initial>=0.2 ? .alert:nil)
        for _ in 0..<60 {planner.observe(id,stimulus:passing,dt:0.1)}
        XCTAssertEqual(try XCTUnwrap(planner.ecology(id)).disturbance,initial/2,accuracy:1e-12)
        XCTAssertNil(planner.attentionCandidate(id))
        planner.observe(id,stimulus:still,dt:0)
        planner.observe(id,stimulus:passing,dt:0)
        XCTAssertEqual(try XCTUnwrap(planner.ecology(id)).disturbance,initial*1.5,accuracy:1e-12)

        let clicked=fixture()
        clicked.noteClick(id)
        let clickValue=try XCTUnwrap(clicked.ecology(id)).disturbance
        clicked.observe(id,stimulus:clicking,dt:0)
        XCTAssertEqual(clicked.ecology(id)?.disturbance,clickValue,"Command plus held-button sample is one click")
        for _ in 0..<60 {clicked.observe(id,stimulus:clicking,dt:0.1)}
        XCTAssertEqual(try XCTUnwrap(clicked.ecology(id)).disturbance,clickValue/2,accuracy:1e-12)
        XCTAssertNil(clicked.attentionCandidate(id))
        clicked.observe(id,stimulus:still,dt:0)
        clicked.observe(id,stimulus:clicking,dt:0)
        XCTAssertEqual(try XCTUnwrap(clicked.ecology(id)).disturbance,min(1,clickValue*1.5),accuracy:1e-12)
    }

    func testWatchDrawOccursOncePerRangeEntryAndPendingExpires() throws {
        let planner=fixture(count:64)
        var accepted=0,retried=0
        for value in 1...64 {
            let birdID=BirdID(UInt64(value))
            planner.observe(birdID,stimulus:watching,dt:0)
            let first=planner.attentionCandidate(birdID)
            if first == .watch {accepted+=1}
            planner.observe(birdID,stimulus:watching,dt:0.49)
            XCTAssertEqual(planner.attentionCandidate(birdID),first)
            planner.observe(birdID,stimulus:watching,dt:0.02)
            XCTAssertNil(planner.attentionCandidate(birdID))
            for _ in 0..<20 {planner.observe(birdID,stimulus:watching,dt:1)}
            XCTAssertNil(planner.attentionCandidate(birdID),"Remaining in range cannot reroll curiosity")
            planner.observe(birdID,stimulus:still,dt:0)
            planner.observe(birdID,stimulus:watching,dt:0)
            if planner.attentionCandidate(birdID) == .watch {retried+=1}
            planner.observe(birdID,stimulus:still,dt:0)
            XCTAssertNil(planner.attentionCandidate(birdID),"Leaving range drops the old watch")
        }
        XCTAssertGreaterThan(accepted,0);XCTAssertLessThan(accepted,64)
        XCTAssertGreaterThan(retried,0)
    }

    func testClickClearsPendingAndBlocksImmediateRangeAndFastPassRetriggers() throws {
        let planner=fixture(count:64)
        var cleared=0
        for value in 1...64 {
            let birdID=BirdID(UInt64(value))
            planner.observe(birdID,stimulus:watching,dt:0)
            if planner.attentionCandidate(birdID) != nil {cleared+=1}
            planner.noteClick(birdID)
            XCTAssertNil(planner.attentionCandidate(birdID))
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(planner.ecology(birdID)?.cooldowns[.watch]),4)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(planner.ecology(birdID)?.cooldowns[.alert]),4)
            planner.observe(birdID,stimulus:still,dt:0)
            planner.observe(birdID,stimulus:passing,dt:0)
            XCTAssertNil(planner.attentionCandidate(birdID))
            planner.observe(birdID,stimulus:watching,dt:4)
            XCTAssertNil(planner.attentionCandidate(birdID),"Cooldown expiry cannot retry the consumed range entry")
        }
        XCTAssertGreaterThan(cleared,0)
    }

    func testCooldownsBeginOnTerminationExpireAndDuplicateFinishIsHarmless() throws {
        let cases:[(BehaviorKind,Double)]=[(.watch,8),(.alert,12),(.rest,6),(.preen,6),
            (.socialGreeting,20),(.sideBySide,20),(.giveWay,20),(.pairedTakeoff,20),(.leafPlay,90)]
        for (kind,duration) in cases {
            let planner=fixture()
            planner.didStart(id,kind:kind)
            planner.observe(id,stimulus:still,dt:100)
            XCTAssertNil(planner.ecology(id)?.cooldowns[kind],"Running time must not consume the post-run cooldown")
            XCTAssertEqual(planner.automaticWeight(id,kind:kind),0)
            planner.didFinish(id,kind:kind)
            XCTAssertEqual(planner.ecology(id)?.cooldowns[kind],duration)
            planner.observe(id,stimulus:still,dt:duration-0.25)
            XCTAssertEqual(planner.automaticWeight(id,kind:kind),0)
            planner.didFinish(id,kind:kind)
            XCTAssertEqual(try XCTUnwrap(planner.ecology(id)?.cooldowns[kind]),0.25,accuracy:1e-12)
            planner.observe(id,stimulus:still,dt:0.25)
            XCTAssertNil(planner.ecology(id)?.cooldowns[kind])
            if kind != .alert {XCTAssertGreaterThan(planner.automaticWeight(id,kind:kind),0)}
            if kind.isSocial {
                for social:BehaviorKind in [.socialGreeting,.sideBySide,.giveWay,.pairedTakeoff] {
                    XCTAssertGreaterThan(planner.automaticWeight(id,kind:social),0)
                }
            }
        }
        let shared=fixture()
        shared.didStart(id,kind:.socialGreeting);shared.didFinish(id,kind:.socialGreeting)
        for social:BehaviorKind in [.socialGreeting,.sideBySide,.giveWay,.pairedTakeoff] {
            XCTAssertEqual(shared.automaticWeight(id,kind:social),0)
            XCTAssertEqual(shared.ecology(id)?.cooldowns[social],20)
        }
    }

    func testResetPerceptionKeepsPersonalityAndMemoryAndRemovalDropsEverything() throws {
        let planner=fixture()
        planner.observe(id,stimulus:passing,dt:0)
        planner.didStart(id,kind:.leafPlay);planner.didFinish(id,kind:.leafPlay)
        planner.noteClick(id)
        let memory=try XCTUnwrap(planner.ecology(id))
        planner.resetPerception()
        XCTAssertEqual(planner.ecology(id),memory);XCTAssertNil(planner.attentionCandidate(id))
        let rhythm=try XCTUnwrap(planner.rhythms[id])
        XCTAssertFalse(rhythm.previousNear);XCTAssertFalse(rhythm.previousFast)
        XCTAssertFalse(rhythm.previousRange);XCTAssertFalse(rhythm.previousClick)
        planner.remove(id);planner.remove(id)
        planner.observe(id,stimulus:passing,dt:1);planner.noteClick(id)
        planner.didStart(id,kind:.watch);planner.didFinish(id,kind:.watch)
        XCTAssertNil(planner.ecology(id));XCTAssertNil(planner.attentionCandidate(id))
        XCTAssertEqual(planner.automaticWeight(id,kind:.rest),0)
        planner.register(id,bird:bird())
        XCTAssertEqual(planner.ecology(id)?.temperament,memory.temperament)
        XCTAssertEqual(planner.ecology(id)?.disturbance,0)
        XCTAssertTrue(try XCTUnwrap(planner.ecology(id)).cooldowns.isEmpty)
    }

    func testDisturbanceCancelsPendingPreenAndQuietRestProgressWithoutRerolling() throws {
        let planner=fixture(),perched=bird(),rhythm=try XCTUnwrap(planner.rhythms[id])
        rhythm.pendingPreen=true;rhythm.landingAge=0.2;rhythm.quiet=7
        let nextRest=rhythm.nextRest
        for _ in 0..<8 {planner.noteClick(id)}
        XCTAssertFalse(rhythm.pendingPreen);XCTAssertEqual(rhythm.quiet,0)
        XCTAssertEqual(rhythm.nextRest,nextRest)
        XCTAssertNil(planner.candidate(id,bird:perched,dt:100,enabled:true,occupied:false,quiet:true))
        XCTAssertEqual(rhythm.quiet,0)
        planner.observe(id,stimulus:still,dt:24)
        XCTAssertEqual(planner.candidate(id,bird:perched,dt:nextRest+0.01,enabled:true,occupied:false,quiet:true),.rest)
    }

    func testInvalidObservationDoesNotChangeMemoryOrPerception() throws {
        let planner=fixture(),initial=try XCTUnwrap(planner.ecology(id))
        for dt in [-1,Double.nan,Double.infinity] {
            planner.observe(id,stimulus:clicking,dt:dt)
            XCTAssertEqual(planner.ecology(id),initial)
        }
    }
}
