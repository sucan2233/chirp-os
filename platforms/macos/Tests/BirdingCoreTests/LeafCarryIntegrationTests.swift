import XCTest
@testable import BirdingCore

final class LeafCarryIntegrationTests:XCTestCase {
    private typealias F=LeafCarryTestSupport
    private func start(_ e:BehaviorEngine)throws->BehaviorRunID {
        XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)
        return try F.start(e.handle(.leafCarry(.preview)))
    }
    private func reach(_ phase:LeafCarryExecution.Phase,_ e:BehaviorEngine,_ run:BehaviorRunID)throws {
        for _ in 0..<25*60 {
            guard let active=e.runtime.runs[run]?.execution as? LeafCarryExecution else {break}
            if active.phase==phase {return}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Missing real phase \(phase)");throw NSError(domain:"LeafCarryIntegrationTests",code:1)
    }

    func testCompleteAndCancelledJourneysHaveIdenticalSegmentedEntityAndEventTracesAcrossCallbackRates() throws {
        func trace(_ hz:Int,_ cancel:Bool)throws->[BehaviorReplayReport] {
            let e=F.engine(),run=try start(e)
            var result:[BehaviorReplayReport]=[]
            for tenth in 0..<300 {
                if tenth==5 {e.handle(.pause(true))}
                if tenth==8,cancel {e.handle(.removeCarryLeaf)}
                if tenth==12 {e.handle(.pause(false))}
                F.advance(e,0.1,hz:hz)
                result.append(BehaviorReplayReport(engine:e,events:e.events.map(RecordedEvent.init)))
            }
            XCTAssertEqual(F.terminals(e,run).map(\.type),[cancel ? .cancelled:.completed])
            F.assertReleased(e,run);XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
            XCTAssertNil(e.sceneFocus);XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0)
            return result
        }
        for cancel in [false,true] {
            let reference=try trace(60,cancel)
            XCTAssertEqual(try trace(30,cancel),reference)
            XCTAssertEqual(try trace(120,cancel),reference)
        }
    }

    func testSmallHostRejectsTheTransportBeforePickupWithoutReclaimingTheAvailableEntity() throws {
        let e=F.engine(species:nil),host=Surface(id:F.host.id,pid:F.host.pid,rect:CGRect(x:100,y:1100,width:100,height:180))
        var world=e.world;world.surfaces=[host];e.updateWorld(world)
        let bird=Bird(position:.zero,fraction:0,profile:e.settings.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
        e.installFixtureBirds([bird]);F.advance(e,9)
        // The 100pt host has inset perch limits 133⅓...166⅔, not
        // 100...200. Keep the token clear of the bird and inside that range.
        let point=CGPoint(x:165,y:1100)
        XCTAssertNotNil(SurfaceAnchor.at(point,on:host,scale:e.spriteScale(for:bird)))
        XCTAssertEqual(e.handle(.placeCarryLeaf(at:point)),.accepted)
        let token=try XCTUnwrap(F.tokens(e).first),object=try XCTUnwrap(e.carriedObjectSnapshot().first)
        XCTAssertEqual(object.state,.available);XCTAssertEqual(token.position,point)
        XCTAssertFalse(e.bounds(of:bird).intersects(token.rect))
        let pickup=CarriedObjectGeometry.pickupFoot(surface:point,worldScale:e.world.scale,
            birdScale:e.spriteScale(for:bird),facingRight:object.facingRight)
        XCTAssertNotNil(SurfaceAnchor.at(pickup,on:host,scale:e.spriteScale(for:bird)))
        XCTAssertLessThan(Geometry.perchX(1,rect:host.rect)-Geometry.perchX(0,rect:host.rect),80*e.world.scale,
            "The pickup fits, but the host cannot provide the minimum 80pt transport")
        let before=e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),position=bird.position
        XCTAssertEqual(e.handle(.leafCarry(.preview)),.rejected(.noSpace))
        XCTAssertEqual(e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),before)
        XCTAssertEqual(bird.position,position);XCTAssertEqual(e.activeRunCount,0)
        XCTAssertEqual(e.reservedLandingCount,0);XCTAssertNotNil(e.sceneFocus)
    }

    func testHostFractionTracksLightMovementWhileInvalidIdentityCancelsWithoutTranslatingTheFoot() throws {
        for phase:LeafCarryExecution.Phase in [.approach,.grip,.carry,.recover] {
            let e=F.engine(),bird=e.birds[0],run=try start(e)
            try reach(phase,e,run)
            let object=try XCTUnwrap(e.carriedObjectSnapshot().first)
            let active=try XCTUnwrap(e.runtime.runs[run]?.execution as? LeafCarryExecution)
            let sourceFraction=active.plan.source.fraction,destinationFraction=active.plan.placement.fraction
            let age=e.runtime.runs[run]?.age
            var world=e.world;world.surfaces[0].rect.origin.x+=2;world.surfaces[0].rect.origin.y+=1
            let original=bird.position
            e.updateWorld(world,sampleDT:1.0/60)
            XCTAssertNotNil(e.runtime.runs[run],
                "requested phase=\(phase.rawValue), current phase=\(active.phase.rawValue), failure phase=\(active.reconciliationFailurePhase?.rawValue ?? "none"), diagnostic=\(active.reconciliationFailure ?? "none")")
            XCTAssertEqual(e.runtime.runs[run]?.age,age)
            XCTAssertEqual(active.plan.source.fraction,sourceFraction)
            XCTAssertEqual(active.plan.placement.fraction,destinationFraction)
            XCTAssertEqual(e.carriedObjectSnapshot().first?.id,object.id)
            if bird.state == .flying {XCTAssertEqual(bird.position,original,"A replan may change the route, never teleport its origin")}
            F.advance(e,0.1)
            XCTAssertTrue(F.terminals(e,run).isEmpty)
            let actual=bird.position
            world=e.world;world.surfaces[0]=Surface(id:F.host.id,pid:F.host.pid+1,rect:world.surfaces[0].rect)
            e.updateWorld(world,sampleDT:1.0/60)
            XCTAssertEqual(bird.position,actual);F.assertReleased(e,run)
            XCTAssertNotEqual(F.terminals(e,run).first?.type,.completed)
            if phase != .recover {F.advance(e,0.3);XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)}
        }
    }

    func testObstacleInLeafOnlySpaceCancelsEvenWhenTheRenderedBirdBodyIsClear() throws {
        let e=F.engine(),bird=e.birds[0],run=try start(e)
        try reach(.grip,e,run)
        let token=try XCTUnwrap(F.tokens(e).first),body=try XCTUnwrap(e.renderSnapshot().first).rect
        // Pick an interior part of the actual leaf outside the drawn body. This
        // exercises scene validation, not a copied envelope implementation.
        let leafOnly=Geometry.subtract(token.rect,body).filter{$0.width>0.01 && $0.height>0.01}
        let region=try XCTUnwrap(leafOnly.max(by:{$0.width*$0.height<$1.width*$1.height}))
        let obstruction=region.insetBy(dx:region.width/4,dy:region.height/4)
        XCTAssertFalse(body.intersects(obstruction));XCTAssertTrue(token.rect.intersects(obstruction))
        let actual=bird.position
        var world=e.world
        world.surfaces.insert(Surface(id:990,pid:42,rect:obstruction,layer:1),at:0)
        e.updateWorld(world)
        F.assertReleased(e,run);XCTAssertNotEqual(F.terminals(e,run).first?.type,.completed)
        XCTAssertEqual(bird.position,actual);F.advance(e,0.3)
        XCTAssertTrue(e.carriedObjectSnapshot().isEmpty)
    }

    func testRealCarryRejectsOldFoodFixedPerchAndEncounterEntrypointsWithoutChangingItsLeases() throws {
        let e=F.engine(),run=try start(e)
        try reach(.grip,e,run)
        let id=try XCTUnwrap(e.carriedObjectSnapshot().first?.id)
        for command:EngineCommand in [.foodTrayVisit(.preview),.fixedPerchVisit(.preview),.bathVisit(.preview),
            .leafCarry(.preview),.flockPass(.preview),.pointerVisit(.preview),.chase(.preview),.travelTogether(.preview),
            .socialGreeting(.preview),.allopreening(.preview),.leafPlay(at:CGPoint(x:1700,y:650),source:.preview)] {
            XCTAssertEqual(e.handle(command),.rejected(.busy))
            XCTAssertEqual(e.activeRunCount,1);XCTAssertEqual(e.leasedBirdCount,1)
            XCTAssertEqual(e.reservedLandingCount,2);XCTAssertEqual(e.carriedObjectSnapshot().first?.id,id)
        }
        F.advance(e,25);F.assertReleased(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
    }

    func testLeafChoiceUsesIndependentRandomnessAndTheSameSortedResidents() throws {
        struct Choice:Equatable {let participants:[BirdID],destination:SurfaceAnchor}
        func choose(_ consume:Bool)throws->Choice {
            let e=F.engine(species:nil,seed:171)
            let birds:[Bird]=[CGFloat(0.1),0.3,0.8].map {fraction in
                let bird=Bird(position:.zero,fraction:fraction,profile:e.settings.catalog.profile(.treeSparrow),random:{0.5})
                bird.perch(on:F.host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600;return bird
            }
            e.installFixtureBirds(birds);F.advance(e,9)
            if consume {for _ in 0..<503 {_=e.random.unit()}}
            let run=try start(e),active=try XCTUnwrap(e.runtime.runs[run]?.execution as? LeafCarryExecution)
            return Choice(participants:active.participants,destination:active.plan.placement)
        }
        XCTAssertEqual(try choose(false),try choose(true))
    }

    func testSingleSceneSchedulerEventuallyRunsAnActualAutomaticCarryAndInputSuppressionSurvivesPlacement() throws {
        // A bounded set of independent first opportunities checks the actual
        // scheduler dispatch. Empty/legacy outcomes are legitimate 30% choices.
        var automaticSuccesses=0
        for seed:UInt64 in 0..<12 {
            let e=F.engine(seed:seed)
            e.ambientEnabled=true
            XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)
            let object=try XCTUnwrap(e.carriedObjectSnapshot().first)
            XCTAssertLessThanOrEqual(e.scheduler.remaining,10)
            F.advance(e,36)
            let started=e.events.filter{$0.kind == .leafCarry && $0.type == .started}
            if !started.isEmpty {
                XCTAssertEqual(started.first?.source,.automatic)
                XCTAssertEqual(started.count,1)
                XCTAssertEqual(e.events.filter{$0.kind == .leafCarry && $0.type == .completed}.count,1)
                automaticSuccesses+=1
            }
            XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0)
            if let current=e.carriedObjectSnapshot().first {XCTAssertEqual(current.id,object.id)}
        }
        XCTAssertGreaterThan(automaticSuccesses,0)
        let e=F.engine();e.ambientEnabled=true
        e.handle(.pointerClick)
        XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)
        XCTAssertGreaterThanOrEqual(e.scheduler.remaining,60)
        F.advance(e,59)
        XCTAssertFalse(e.events.contains{$0.kind == .leafCarry && $0.type == .started})
        let remaining=e.scheduler.remaining
        e.handle(.pause(true));F.advance(e,10)
        XCTAssertEqual(e.scheduler.remaining,remaining)
        e.handle(.pause(false));F.advance(e,0.5)
        XCTAssertFalse(e.events.contains{$0.kind == .leafCarry && $0.type == .started})
    }
}
