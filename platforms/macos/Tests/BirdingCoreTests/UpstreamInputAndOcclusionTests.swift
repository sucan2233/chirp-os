import XCTest
@testable import BirdingCore

final class UpstreamInputAndOcclusionTests:XCTestCase {
    let screen=CGRect(x:0,y:0,width:1800,height:1200)
    let host=Surface(id:71,rect:CGRect(x:150,y:700,width:1200,height:400))

    func testOwnOrdinaryWindowMasksFlightWithoutBecomingAHost() throws {
        let control=Surface(id:72,rect:CGRect(x:250,y:250,width:700,height:400),
                            canHostBirds:false,occludesFlight:true)
        let ordinary=Surface(id:73,rect:control.rect)
        let bird=Bird(position:CGPoint(x:400,y:400),fraction:0.5)
        XCTAssertEqual(bird.blockers(in:[control,ordinary,host]),[control.rect])
        XCTAssertTrue(Geometry.landingRanges(on:control,surfaces:[control,host],screen:screen,scale:1).isEmpty)
        XCTAssertTrue(Geometry.sideRanges(on:control,edge:.left,surfaces:[control,host],screen:screen,scale:1,occupied:[]).isEmpty)
        XCTAssertNil(SurfaceAnchor.at(CGPoint(x:400,y:250),on:control,scale:1))
        let world=BehaviorWorld(screens:[screen],displays:[screen],surfaces:[control,host])
        let decoded=try JSONDecoder().decode(RecordedWorld.self,from:JSONEncoder().encode(RecordedWorld(world)))
        let restored=try decoded.validated()
        XCTAssertFalse(restored.surfaces[0].canHostBirds)
        XCTAssertTrue(restored.surfaces[0].occludesFlight)
        XCTAssertEqual(restored.surfaces,world.surfaces)
    }

    func testLegacyRecordedSurfacesRetainOriginalEligibility() throws {
        let data=Data("{\"id\":1,\"pid\":0,\"layer\":0,\"isGround\":false,\"rect\":{\"x\":100,\"y\":300,\"width\":500,\"height\":250}}".utf8)
        let surface=try JSONDecoder().decode(RecordedSurface.self,from:data).value
        XCTAssertTrue(surface.canHostBirds);XCTAssertFalse(surface.occludesFlight)
    }

    func testCaptureButtonDoesNotCancelExistingActionButBlocksNewAction() throws {
        for capture in [true,false] {
            var settings=BirdSettings();settings.pointerVisits=false;settings.flockPasses=false
            let engine=BehaviorEngine(seed:73,settings:settings)
            engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
            let frames:Set<String>=["stand","blink","breathe","preen0","preen1"]
            engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],
                pointer:CGPoint(x:0,y:0),availableFrames:[.treeSparrow:frames]))
            let first=Bird(position:.zero,fraction:0.25,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
            let second=Bird(position:.zero,fraction:0.75,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
            for bird in [first,second] {bird.perch(on:host);bird.perchDuration=600}
            engine.installFixtureBirds([first,second])
            guard case .started(let run)=engine.handle(.perchAction(.rest,.preview)) else {return XCTFail("rest must start")}
            var world=engine.world;world.buttonsDown=true;world.observationClick=capture
            engine.updateWorld(world);engine.advance(BehaviorEngine.step)
            let terminals=engine.events.filter{$0.runID==run && $0.type == .cancelled}
            XCTAssertEqual(terminals.isEmpty,capture)
            let next=engine.handle(.perchAction(.preen,.preview))
            XCTAssertFalse(next.accepted,"physical button must still suppress new actions")
            let recorded=try RecordedWorld(world).validated()
            XCTAssertEqual(recorded.buttonsDown,true);XCTAssertEqual(recorded.observationClick,capture)
            if capture {
                world.buttonsDown=false;world.observationClick=false;engine.updateWorld(world)
                for _ in 0..<600 {engine.advance(BehaviorEngine.step)}
                XCTAssertEqual(engine.events.filter{$0.runID==run && $0.type == .completed}.count,1)
            }
        }
    }
}
