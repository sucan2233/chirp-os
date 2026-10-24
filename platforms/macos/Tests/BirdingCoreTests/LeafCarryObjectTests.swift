import XCTest
@testable import BirdingCore

enum LeafCarryTestSupport {
    static let display=CGRect(x:0,y:0,width:2400,height:1500)
    static let host=Surface(id:971,pid:42,rect:CGRect(x:200,y:1100,width:2000,height:180))
    static let point=CGPoint(x:1200,y:1100)
    static let required:Set<String>=Set(["stand","land0","land1","land2","carryLook","carryLower","carryGrip","carryPlace"]
        + (0..<8).map{"fly\($0)"})
    static func engine(species:SpeciesID? = .treeSparrow,scale:CGFloat=1,right:Bool=true,seed:UInt64=971)->BehaviorEngine {
        var settings=BirdSettings();settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(.init(screens:[display],displays:[display],surfaces:[host],scale:scale,pointer:CGPoint(x:20,y:20),
            availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,required)})))
        if let species {
            let bird=Bird(position:.zero,fraction:right ? 0.15:0.85,profile:settings.catalog.profile(species),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
            e.installFixtureBirds([bird])
        }
        advance(e,9)
        return e
    }
    static func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    static func start(_ result:BehaviorResult,file:StaticString=#filePath,line:UInt=#line)throws->BehaviorRunID {
        guard case .started(let run)=result else {
            XCTFail("Expected real leafCarry run, got \(result)",file:file,line:line)
            throw NSError(domain:"LeafCarryTests",code:1)
        }
        return run
    }
    static func tokens(_ e:BehaviorEngine)->[ScenePropRenderState] {e.propSnapshot().filter{$0.kind == .leafToken}}
    static func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID)->[BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    static func assertReleased(_ e:BehaviorEngine,_ run:BehaviorRunID,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(terminals(e,run).count,1,file:file,line:line)
        XCTAssertNil(e.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertEqual(e.habitatReservationCount,0,file:file,line:line)
        XCTAssertFalse(e.ambientBusy,file:file,line:line)
    }
}

final class LeafCarryObjectTests:XCTestCase {
    private typealias F=LeafCarryTestSupport

    func testUserPlacementUsesAnExistingOrdinarySupportOneFixedSizeTokenAndNoNewBirdOrRun() throws {
        for scale:CGFloat in [0.5,1,2] {
            for ground in [false,true] {
                let e=F.engine(species:nil,scale:scale)
                var world=e.world
                if ground {world.surfaces=[Surface(id:F.host.id,pid:F.host.pid,rect:F.host.rect,isGround:true)]}
                e.updateWorld(world)
                let surfaces=e.world.surfaces
                XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)
                let token=try XCTUnwrap(F.tokens(e).first)
                XCTAssertEqual(F.tokens(e).count,1);XCTAssertEqual(token.frameName,"leafToken")
                XCTAssertEqual(token.size,16*scale);XCTAssertEqual(token.opacity,1)
                XCTAssertEqual(token.anchor,CGPoint(x:10.0/16,y:12.0/16))
                XCTAssertEqual(token.position,F.point);XCTAssertEqual(token.rotation,0)
                XCTAssertEqual(token.rect.minY,F.point.y-12*scale,accuracy:1e-9)
                XCTAssertTrue(F.display.contains(token.rect))
                XCTAssertEqual(e.world.surfaces,surfaces,"A leaf uses its real host, without creating an airborne perch")
                XCTAssertEqual(e.sceneFocus?.leafID,token.id);XCTAssertNil(e.sceneFocus?.objectID)
                XCTAssertTrue(e.birds.isEmpty);XCTAssertEqual(e.activeRunCount,0)
                XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                XCTAssertFalse(e.hasCarryLeafPlacement)
                let before=F.tokens(e).map(RecordedPropState.init)
                XCTAssertEqual(e.handle(.placeCarryLeaf(at:CGPoint(x:1500,y:1100))),.rejected(.busy))
                XCTAssertEqual(e.handle(.placeCarryLeafAfter(1)),.rejected(.busy))
                XCTAssertEqual(F.tokens(e).map(RecordedPropState.init),before)
            }
        }
    }

    func testPlacementRejectsUnsupportedAirAndArtWithoutReplacingAnExistingFocus() throws {
        let e=F.engine(species:nil)
        for invalid in [CGPoint(x:1200,y:650),CGPoint(x:20,y:1100),CGPoint(x:CGFloat.nan,y:1100)] {
            XCTAssertEqual(e.handle(.placeCarryLeaf(at:invalid)),.rejected(.noSpace))
            XCTAssertTrue(F.tokens(e).isEmpty);XCTAssertNil(e.sceneFocus)
        }
        var world=e.world;world.leafCarryArtAvailable=false;e.updateWorld(world)
        XCTAssertEqual(e.handle(.placeCarryLeaf(at:F.point)),.rejected(.missingFrames))
        world.leafCarryArtAvailable=true;e.updateWorld(world)
        XCTAssertTrue(e.handle(.placeBath(at:CGPoint(x:1200,y:650))).accepted)
        let focus=e.sceneFocus,bath=e.habitatSnapshot().map(RecordedHabitatObjectState.init)
        XCTAssertEqual(e.handle(.placeCarryLeaf(at:F.point)),.rejected(.busy))
        XCTAssertEqual(e.handle(.placeCarryLeafAfter(1)),.rejected(.busy))
        XCTAssertEqual(e.sceneFocus,focus);XCTAssertEqual(e.habitatSnapshot().map(RecordedHabitatObjectState.init),bath)
        e.handle(.clearCurrentScene);F.advance(e,2.1)
        XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)
        let token=try XCTUnwrap(F.tokens(e).first)
        XCTAssertEqual(e.handle(.placeBath(at:CGPoint(x:1200,y:650))),.rejected(.busy))
        XCTAssertEqual(e.handle(.placeBathAfter(1)),.rejected(.busy))
        XCTAssertEqual(F.tokens(e).map(\.id),[token.id]);XCTAssertEqual(e.sceneFocus?.leafID,token.id)
    }

    func testAvailableLifetimeAndFocusFreezeDuringPauseThenExpireWithoutASecondIdentity() throws {
        let e=F.engine(species:nil)
        XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)
        let id=try XCTUnwrap(F.tokens(e).first?.id)
        F.advance(e,179.9)
        let before=F.tokens(e).map(RecordedPropState.init),focus=e.sceneFocus,clock=e.scheduler.remaining
        XCTAssertEqual(before.count,1);XCTAssertEqual(before.first?.opacity,1)
        e.handle(.pause(true));F.advance(e,300)
        XCTAssertEqual(F.tokens(e).map(RecordedPropState.init),before)
        XCTAssertEqual(e.sceneFocus,focus);XCTAssertEqual(e.scheduler.remaining,clock)
        XCTAssertEqual(e.handle(.leafCarry(.preview)),.rejected(.paused))
        e.handle(.pause(false));F.advance(e,0.15)
        XCTAssertNil(e.sceneFocus)
        XCTAssertTrue(F.tokens(e).allSatisfy{$0.id==id && $0.opacity<1})
        F.advance(e,0.3)
        XCTAssertTrue(F.tokens(e).isEmpty);XCTAssertNil(e.sceneFocus)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
    }

    func testDelayedPlacementFreezesCanBeCancelledAndSamplesTheFinalRealHostPoint() throws {
        let e=F.engine(species:nil)
        var world=e.world;world.pointer=F.point;e.updateWorld(world)
        XCTAssertEqual(e.handle(.placeCarryLeafAfter(2)),.scheduled)
        F.advance(e,0.5);e.handle(.pause(true));F.advance(e,20)
        XCTAssertTrue(e.hasCarryLeafPlacement);XCTAssertTrue(F.tokens(e).isEmpty)
        XCTAssertEqual(e.handle(.placeCarryLeaf(at:F.point)),.rejected(.paused))
        e.handle(.cancelCarryLeafPlacement)
        XCTAssertFalse(e.hasCarryLeafPlacement)
        e.handle(.pause(false));F.advance(e,3)
        XCTAssertTrue(F.tokens(e).isEmpty);XCTAssertNil(e.sceneFocus)
        XCTAssertEqual(e.handle(.placeCarryLeafAfter(1)),.scheduled)
        world.pointer=CGPoint(x:1500,y:1100);e.updateWorld(world);F.advance(e,1.1)
        XCTAssertFalse(e.hasCarryLeafPlacement)
        XCTAssertEqual(F.tokens(e).first?.position,world.pointer)
        e.handle(.removeCarryLeaf);F.advance(e,0.3)
        XCTAssertTrue(F.tokens(e).isEmpty);XCTAssertNil(e.sceneFocus)
    }

    func testClearingDynamicLeafDoesNotEraseAvailableCarryLeafAndInvalidationDoesCleanIt() throws {
        for cause in ["remove","clearProps","clearScene","disable","art","host","pid","screens","display","scale","sleep","shutdown"] {
            let e=F.engine(species:nil)
            XCTAssertTrue(e.handle(.placeCarryLeaf(at:F.point)).accepted)
            let before=F.tokens(e).map(RecordedPropState.init)
            e.handle(.clearLeaf)
            XCTAssertEqual(F.tokens(e).map(RecordedPropState.init),before)
            e.handle(.pause(true))
            switch cause {
            case "remove":e.handle(.removeCarryLeaf)
            case "clearProps":e.handle(.clearProps)
            case "clearScene":e.handle(.clearCurrentScene)
            case "disable":var settings=e.settings;settings.leafCarryEnabled=false;e.applySettings(settings)
            case "art":var world=e.world;world.leafCarryArtAvailable=false;e.updateWorld(world)
            case "host":var world=e.world;world.surfaces=[];e.updateWorld(world)
            case "pid":var world=e.world;world.surfaces[0]=Surface(id:F.host.id,pid:F.host.pid+1,rect:F.host.rect);e.updateWorld(world)
            case "screens":var world=e.world;world.screens[0].size.width-=1;e.updateWorld(world)
            case "display":var world=e.world;world.displays[0].size.width-=1;e.updateWorld(world)
            case "scale":var world=e.world;world.scale*=1.1;e.updateWorld(world)
            case "sleep":e.handle(.cancelAmbient(.sleep))
            default:e.handle(.cancelAmbient(.shutdown))
            }
            XCTAssertTrue(F.tokens(e).isEmpty,cause);XCTAssertNil(e.sceneFocus,cause)
            XCTAssertFalse(e.hasCarryLeafPlacement);XCTAssertEqual(e.activeRunCount,0)
        }
    }
}
