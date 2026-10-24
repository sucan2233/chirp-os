import XCTest
@testable import BirdingCore

final class NestAdmissionTests:XCTestCase {
    private typealias F=NestTestSupport
    func testEveryRequiredFrameLossRejectsBothStepsAndPreservesTheExistingMaterials() throws {
        for building in [false,true] {
            let required=F.common.subtracting(["blink"]).union(building ? F.build:F.carry)
            XCTAssertEqual(BehaviorDefinitions.definition(for:building ? .nestBuild:.nestMaterialCarry).requiredFrames,required)
            for missing in required.sorted() {
                let e=try F.prepared()
                if building {_=try F.deliver(e)}
                let before=e.nestSnapshot().map(RecordedNestState.init),feet=e.birds.map(\.position)
                var world=e.world;world.availableFrames[.spottedDove]?.remove(missing);e.updateWorld(world)
                XCTAssertEqual(e.handle(building ? .nestBuild(.preview):.nestMaterialCarry(.preview)),.rejected(.missingFrames),missing)
                XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),before)
                XCTAssertEqual(e.birds.map(\.position),feet);XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            }
            let e=try F.prepared();if building {_=try F.deliver(e)}
            var world=e.world;world.availableFrames[.spottedDove]?.remove("blink");e.updateWorld(world)
            let run=try F.start(e,build:building);F.finish(e,run);F.released(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        }
    }

    func testFortyFiveUnlistedSpeciesAndNoResidentNeverSpawnOrReclaimMaterial() throws {
        for species:SpeciesID? in [nil]+SpeciesID.allCases.filter{$0 != .spottedDove}.map(Optional.some) {
            let e=F.engine(residents:species==nil ? 0:1,species:species)
            XCTAssertEqual(e.handle(.placeNest(at:F.point(e))),.accepted)
            let before=e.nestSnapshot().map(RecordedNestState.init),birds=e.birds.map(ObjectIdentifier.init)
            for command:EngineCommand in [.nestMaterialCarry(.preview),.nestBuild(.preview)] {
                XCTAssertEqual(e.handle(command),.rejected(.noSpecies))
                XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),before)
                XCTAssertEqual(e.birds.map(ObjectIdentifier.init),birds)
                XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.pendingCount,0)
            }
        }
    }

    func testNoDeliveredMaterialRejectsBuildAndProbabilityZeroFixedPerchOrUnsettledBirdCannotVisit() throws {
        let e=try F.prepared(),before=try F.nest(e)
        XCTAssertEqual(e.handle(.nestBuild(.preview)),.rejected(.noSpace));XCTAssertEqual(try F.nest(e),before)
        for cause in ["probability","fixed","side","young","transient","moving","buttons"] {
            let e=try F.prepared(),bird=e.birds[0],actual=bird.position;var world=e.world
            switch cause {
            case "probability":var s=e.settings;let index=try XCTUnwrap(s.probabilities.entries.firstIndex{$0.id == .spottedDove});s.probabilities.adjust(at:index,to:0);e.applySettings(s)
            case "fixed":
                let perch=Surface(id:3790,pid:42,rect:CGRect(x:300,y:1200,width:400,height:1),isFixedPerch:true)
                world.surfaces.append(perch);bird.perch(on:perch,spriteScale:e.spriteScale(for:bird));bird.tick(2)
            case "side":bird.edge = .left
            case "young":bird.perch(on:world.surfaces[0],spriteScale:e.spriteScale(for:bird))
            case "transient":let id=try XCTUnwrap(e.id(of:bird));e.removeRecord(id);e.register(bird,role:.transient)
            case "moving":bird.position.x+=1
            default:world.buttonsDown=true
            }
            e.updateWorld(world)
            XCTAssertFalse(e.handle(.nestMaterialCarry(.preview)).accepted,cause)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(try F.nest(e).materials.map(\.state),[.available,.available,.available])
            if cause=="probability" || cause=="buttons" {XCTAssertEqual(bird.position,actual)}
        }
    }

    func testDisabledPausedQuietAndMissingArtRespectPublicGuardsWithoutChangingTheScene() throws {
        for cause in ["paused","setting","quiet","art"] {
            let e=try F.prepared();e.ambientEnabled=true
            if cause=="paused" {e.handle(.pause(true))}
            if cause=="setting" {var s=e.settings;s.nestBuildingEnabled=false;e.applySettings(s)}
            if cause=="quiet" {var s=e.settings;s.activityRhythm = .quiet;e.applySettings(s)}
            if cause=="art" {var w=e.world;w.nestArtAvailable=false;e.updateWorld(w)}
            for build in [false,true] {
                let expected:BehaviorReason=cause=="paused" ? .paused:cause=="art" ? .missingFrames:.disabled
                XCTAssertEqual(e.handle(build ? .nestBuild(.automatic):.nestMaterialCarry(.automatic)),.rejected(expected))
            }
            if cause=="quiet" {
                let run=try F.start(e);F.finish(e,run);F.released(e,run)
                XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            }
        }
    }

    func testRealLegacyRunsAndNestVisitsAreBusyInBothDirections() throws {
        for legacy in ["food","fixed","bath","leaf","gift","courtship"] {
            let e:BehaviorEngine,command:EngineCommand
            switch legacy {
            case "gift":
                e=try VisitorGiftTestSupport.prepared()
                // The gift helper already settles its familiar magpie at1.1s.
                // Another9s enters the periodic hop (age10.1 modulo8=2.1),
                // which legitimately excludes it from gift admission.
                let magpie=try XCTUnwrap(e.birds.first{$0.profile.id == .azureWingedMagpie})
                let id=try XCTUnwrap(e.id(of:magpie))
                XCTAssertGreaterThanOrEqual(magpie.stateTime,1)
                XCTAssertEqual(e.baseHop(for:id,bird:magpie),0,accuracy:0.001)
                let (run,_)=try VisitorGiftTestSupport.authorize(e)
                XCTAssertEqual(e.runtime.runs[run]?.execution.kind,.visitorGift)
                XCTAssertEqual(e.activeGiftAuthorizationCount,1)
                for command:EngineCommand in [.nestMaterialCarry(.preview),.nestBuild(.preview)] {
                    XCTAssertEqual(e.handle(command),.rejected(.busy));XCTAssertNotNil(e.runtime.runs[run])
                }
                e.handle(.cancelAmbient(.sleep));continue
            case "courtship":
                e=CourtshipTestSupport.engine();command = .courtshipDisplay(.preview)
            case "leaf":
                e=LeafCarryTestSupport.engine();XCTAssertEqual(e.handle(.placeCarryLeaf(at:LeafCarryTestSupport.point)),.accepted)
                command = .leafCarry(.preview)
            default:
                e=LeafCarryTestSupport.engine()
                var world=e.world
                world.availableFrames[.treeSparrow]?.formUnion(["feedLook","feedDown0","feedDown1","feedLift",
                    "bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise","shake"])
                e.updateWorld(world)
                if legacy=="fixed" {
                    var s=e.settings;s.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"",displayFrame:e.world.displays[0],x:0.75,y:0.4)]
                    e.applySettings(s);command = .fixedPerchVisit(.preview)
                } else if legacy=="food" {
                    XCTAssertEqual(e.handle(.placeFoodTray(at:CGPoint(x:1700,y:650))),.accepted);command = .foodTrayVisit(.preview)
                } else {
                    XCTAssertEqual(e.handle(.placeBath(at:CGPoint(x:1700,y:650))),.accepted);command = .bathVisit(.preview)
                }
            }
            let run=try LeafCarryTestSupport.start(e.handle(command))
            for command:EngineCommand in [.nestMaterialCarry(.preview),.nestBuild(.preview)] {
                XCTAssertEqual(e.handle(command),.rejected(.busy),legacy);XCTAssertNotNil(e.runtime.runs[run])
            }
            e.handle(.cancelAmbient(.sleep))
        }
        for building in [false,true] {
            let e=try F.prepared();if building {_=try F.deliver(e)}
            var settings=e.settings;settings.socialInteractions=true;settings.visitorGiftsEnabled=true;e.applySettings(settings)
            let run=try F.start(e,build:building),before=e.nestSnapshot().map(RecordedNestState.init)
            for command:EngineCommand in [.foodTrayVisit(.preview),.fixedPerchVisit(.preview),.bathVisit(.preview),
                .leafCarry(.preview),.visitorGift(.preview),.courtshipDisplay(.preview),.nestMaterialCarry(.preview),.nestBuild(.preview)] {
                XCTAssertEqual(e.handle(command),.rejected(.busy));XCTAssertNotNil(e.runtime.runs[run])
                XCTAssertEqual(e.nestSnapshot().map(RecordedNestState.init),before)
            }
            e.handle(.cancelAmbient(.sleep));F.released(e,run)
        }
    }

    func testForegroundOrdinaryWindowCoveringOnlyAFutureBirdBodyInvalidatesPickupAndDestination() throws {
        for stage in ["pickup","delivery","build"] {
            let e=try F.prepared()
            if stage=="build" {_=try F.deliver(e)}
            let nest=try F.nest(e),run=try F.start(e,build:stage=="build")
            let carrier=e.birds[0],feet=carrier.position
            let destination:CGPoint
            if stage=="build" {
                destination=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestBuildExecution).plan.destination.foot
            } else {
                let plan=try XCTUnwrap(e.runtime.runs[run]?.execution as? NestMaterialCarryExecution).plan
                destination=stage=="pickup" ? plan.pickup.foot:plan.destination.foot
            }
            let body=Geometry.landingFootprint(at:destination,scale:e.spriteScale(for:carrier))
            let group=nest.rect.union(nest.trayRect)
            // An ordinary foreground window, not a utility panel. It covers
            // future head/shoulders above the objects, so validating only the
            // .nest virtual host or the user's nest/tray rectangles misses it.
            let obstruction=CGRect(x:group.minX-80,y:body.minY+2,width:group.width+160,height:3)
            XCTAssertTrue(body.intersects(obstruction));XCTAssertFalse(group.intersects(obstruction))
            XCTAssertFalse(e.bounds(of:carrier).intersects(obstruction))
            let states=nest.materials.map(\.state)
            var world=e.world
            world.surfaces.insert(Surface(id:3799,pid:77,rect:obstruction,layer:0),at:0)
            e.updateWorld(world,sampleDT:BehaviorEngine.step)
            F.released(e,run);XCTAssertEqual(carrier.position,feet)
            XCTAssertNotEqual(F.terminals(e,run).first?.type,.completed)
            XCTAssertEqual(try F.nest(e).materials.map(\.state),states)
            XCTAssertFalse(try F.nest(e).retiring);XCTAssertEqual(e.sceneFocus?.nestID,nest.id)
            XCTAssertTrue(NestMaterialCarryPlan.candidates(in:e,source:.preview).isEmpty)
            XCTAssertTrue(NestBuildPlan.candidates(in:e,source:.preview).isEmpty)
            F.clear(e)
        }
    }
}
