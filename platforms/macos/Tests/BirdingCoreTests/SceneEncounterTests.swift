import XCTest
@testable import BirdingCore

final class SceneEncounterTests:XCTestCase {
    private let display=CGRect(x:0,y:0,width:2400,height:1500)
    private let host=Surface(id:921,pid:42,rect:CGRect(x:100,y:1100,width:2100,height:150))
    private let bathPoint=CGPoint(x:900,y:600)
    private let foodPoint=CGPoint(x:1500,y:650)
    private let frames:Set<String>=["stand","shake","blink","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7",
        "land0","land1","land2","feedLook","feedDown0","feedDown1","feedLift",
        "bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise"]
    private func fixture()->BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.ambientLeafPlayEnabled=false
        settings.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"",displayFrame:display,x:0.83,y:0.27)]
        let e=BehaviorEngine(seed:921,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(.init(screens:[display],displays:[display],surfaces:[host],pointer:CGPoint(x:20,y:20),
            availableFrames:[.treeSparrow:frames]))
        let bird=Bird(position:.zero,fraction:0.15,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
        e.installFixtureBirds([bird])
        for _ in 0..<9*60 {e.advance(BehaviorEngine.step)}
        return e
    }
    private func started(_ result:BehaviorResult)throws->BehaviorRunID {
        guard case .started(let run)=result else {
            XCTFail("Expected a real visit, got \(result)");throw NSError(domain:"SceneEncounterTests",code:1)
        }
        return run
    }
    // Isolate the global lease from bird IDs, geometry and object capacity. A
    // competing scene must fail even when it asks for no overlapping bird/slot.
    private final class LeaseProbe:BehaviorExecution {
        let kind:BehaviorKind
        let participants:[BirdID]=[]
        let occupiesEncounter:Bool
        let timeout=35.0
        init(_ kind:BehaviorKind,encounter:Bool) {self.kind=kind;occupiesEncounter=encounter}
        func start(in engine:BehaviorEngine) {}
        func advance(_ dt:Double,in engine:BehaviorEngine)->BehaviorCompletion? {nil}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }

    func testActualBathExcludesOldFoodAndFixedPerchAndAllOtherEncounterEntrypoints() throws {
        let e=fixture(),bird=e.birds[0],before=bird.position
        XCTAssertTrue(e.handle(.placeBath(at:bathPoint)).accepted)
        let run=try started(e.handle(.bathVisit(.preview)))
        XCTAssertEqual(bird.position,before)
        let commands:[EngineCommand]=[.foodTrayVisit(.preview),.fixedPerchVisit(.preview),.bathVisit(.preview),.leafCarry(.preview),
            .flockPass(.preview),.pointerVisit(.preview),.chase(.preview),.travelTogether(.preview),
            .socialGreeting(.preview),.allopreening(.preview),.leafPlay(at:CGPoint(x:1400,y:500),source:.preview)]
        for command in commands {
            XCTAssertEqual(e.handle(command),.rejected(.busy))
            XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
            XCTAssertEqual(e.habitatReservationCount,1);XCTAssertEqual(e.reservedLandingCount,2)
        }
        for kind:BehaviorKind in [.foodTrayVisit,.fixedPerchVisit,.bathVisit,.flockPass,.leafCarry] {
            let probe=LeaseProbe(kind,encounter:kind == .bathVisit || kind == .flockPass || kind == .leafCarry)
            XCTAssertEqual(e.runtime.start(probe,source:.preview,in:e),.rejected(.busy))
        }
        e.runtime.cancel(run,reason:.sleep,in:e)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertFalse(e.ambientBusy)
    }

    func testRealOldFoodAndFixedPerchVisitsRejectNewGlobalEncountersInTheOppositeDirection() throws {
        for food in [false,true] {
            let e=fixture(),bird=e.birds[0],origin=bird.position
            if food {XCTAssertTrue(e.handle(.placeFoodTray(at:foodPoint)).accepted)}
            else {XCTAssertTrue(e.handle(.placeBath(at:bathPoint)).accepted)}
            let run=try started(e.handle(food ? .foodTrayVisit(.preview):.fixedPerchVisit(.preview)))
            XCTAssertEqual(bird.position,origin);XCTAssertFalse(e.ambientBusy)
            XCTAssertEqual(e.handle(.bathVisit(.preview)),.rejected(.busy))
            XCTAssertEqual(e.handle(.leafCarry(.preview)),.rejected(.busy))
            // This bypasses public eligibility deliberately to prove runtime
            // ownership protects the old entry even from an independent actor.
            for kind:BehaviorKind in [.bathVisit,.flockPass,.leafPlay,.leafCarry] {
                XCTAssertEqual(e.runtime.start(LeaseProbe(kind,encounter:true),source:.preview,in:e),.rejected(.busy))
            }
            XCTAssertEqual(e.activeRunCount,1)
            e.runtime.cancel(run,reason:.removed,in:e)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            let probe=try started(e.runtime.start(LeaseProbe(.bathVisit,encounter:true),source:.preview,in:e))
            e.runtime.cancel(probe,reason:.removed,in:e)
        }
    }

    func testAlreadyPlannedOldVisitsCannotInstallWhenAnUnrelatedEncounterAcquiresTheGlobalLease() throws {
        for food in [false,true] {
            let e=fixture(),bird=e.birds[0]
            if food {XCTAssertTrue(e.handle(.placeFoodTray(at:foodPoint)).accepted)}
            let execution:BehaviorExecution
            if food {execution=FoodTrayVisitExecution(plan:try XCTUnwrap(FoodTrayVisitPlan.candidates(in:e,source:.preview).first))}
            else {execution=FixedPerchVisitExecution(plan:try XCTUnwrap(FixedPerchVisitPlan.candidates(in:e,source:.preview).first),source:.preview)}
            let before=bird.position,revision=bird.motionRevision
            let encounter=try started(e.runtime.start(LeaseProbe(.bathVisit,encounter:true),source:.preview,in:e))
            XCTAssertEqual(e.runtime.start(execution,source:.preview,in:e),.rejected(.busy))
            XCTAssertEqual(bird.position,before);XCTAssertEqual(bird.motionRevision,revision)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            e.runtime.cancel(encounter,reason:.removed,in:e)
            let accepted=try started(e.runtime.start(execution,source:.preview,in:e))
            e.runtime.cancel(accepted,reason:.removed,in:e)
        }
    }
}
