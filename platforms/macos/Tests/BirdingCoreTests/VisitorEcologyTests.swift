import XCTest
@testable import BirdingCore

final class VisitorEcologyTests:XCTestCase {
    let screen=CGRect(x:0,y:0,width:1600,height:1200)
    let host=Surface(id:61,pid:42,rect:CGRect(x:100,y:900,width:1400,height:200))
    func bird() -> Bird {
        let value=Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
        value.perch(on:host);value.perchDuration=3600;value.tick(1)
        return value
    }
    func engine(enabled:Bool=true,seed:UInt64=73) -> BehaviorEngine {
        var settings=BirdSettings();settings.visitorMemoryEnabled=enabled
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:980,y:900),
            availableFrames:[.treeSparrow:Set(["stand","blink","preen0","preen1","land0","land1","land2"]+(0...7).map{"fly\($0)"})]))
        return e
    }
    func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int(seconds*Double(hz)) {e.advance(1/Double(hz))}
    }
    func testCalmProximityLearnsOnlyFromSimulationAndReturnsWithStableIdentity() throws {
        let e=engine(),first=bird();e.installFixtureBirds([first])
        let initial=try XCTUnwrap(e.visitor(of:first))
        XCTAssertEqual(initial.familiarity,0)
        advance(e,12)
        let learned=try XCTUnwrap(e.visitor(of:first))
        XCTAssertGreaterThan(learned.familiarity,0)
        XCTAssertLessThanOrEqual(learned.calmSeconds,12+1e-9)
        let before=e.visitorMemoryArchive
        for _ in 0..<120 {
            e.updateWorld(e.world);_=e.renderSnapshot();_=e.ecology(of:first);_=e.visitorMemoryArchive
        }
        XCTAssertEqual(e.visitorMemoryArchive,before)
        e.handle(.remove(e.id(of:first)!))
        XCTAssertEqual(e.activeVisitorCount,0)
        XCTAssertNil(e.ecology(of:first));XCTAssertNil(e.visitor(of:first))
        let returning=bird();e.installFixtureBirds([returning])
        let visitor=try XCTUnwrap(e.visitor(of:returning))
        XCTAssertEqual(visitor.id,initial.id)
        XCTAssertEqual(visitor.temperament,initial.temperament)
        XCTAssertEqual(visitor.familiarity,learned.familiarity)
        XCTAssertEqual(visitor.visits,initial.visits+1)
        XCTAssertEqual(e.ecology(of:returning)?.temperament,initial.temperament)
        XCTAssertNotEqual(e.id(of:returning),BirdID(1))
    }
    func testArchiveRestoresIdentityTraitsAndFamiliarityAcrossEngineSeeds() throws {
        let first=engine(),a=bird();first.installFixtureBirds([a]);advance(first,15)
        let remembered=try XCTUnwrap(first.visitor(of:a)),archive=first.visitorMemoryArchive
        let restored=engine(seed:9999)
        try restored.restoreVisitorMemory(archive)
        let b=bird();restored.installFixtureBirds([b])
        let visitor=try XCTUnwrap(restored.visitor(of:b))
        XCTAssertEqual(visitor.id,remembered.id)
        XCTAssertEqual(visitor.temperament,remembered.temperament)
        XCTAssertEqual(visitor.familiarity,remembered.familiarity)
        XCTAssertEqual(restored.ecology(of:b)?.familiarity,remembered.familiarity)
        let before=restored.visitorMemoryArchive
        XCTAssertThrowsError(try restored.restoreVisitorMemory(archive))
        XCTAssertEqual(restored.visitorMemoryArchive,before)
    }
    func testPauseButtonFlightCoverageAndDifferentDisplayCannotTeachCalmness() throws {
        let e=engine(),b=bird();e.installFixtureBirds([b]);advance(e,1)
        func unchanged(_ operation:()->Void,file:StaticString=#filePath,line:UInt=#line) {
            let before=e.visitor(of:b)?.calmSeconds;operation()
            XCTAssertEqual(e.visitor(of:b)?.calmSeconds,before,file:file,line:line)
        }
        unchanged {e.handle(.pause(true));advance(e,5)}
        e.handle(.pause(false))
        unchanged {var w=e.world;w.buttonsDown=true;e.updateWorld(w);advance(e,5)}
        var w=e.world;w.buttonsDown=false;w.pointer=CGPoint(x:800,y:900);e.updateWorld(w)
        unchanged {advance(e,12)} // Cursor on the body is not a calm approach.
        w.pointer=CGPoint(x:2200,y:900);w.displays.append(screen.offsetBy(dx:2000,dy:0));e.updateWorld(w)
        unchanged {advance(e,12)}
        w.pointer=CGPoint(x:980,y:900);w.surfaces.insert(Surface(id:62,rect:CGRect(x:700,y:800,width:200,height:200)),at:0);e.updateWorld(w)
        unchanged {advance(e,12)}
        w.surfaces=[host];e.updateWorld(w)
        unchanged {e.handle(.relocate(e.id(of:b)!));e.advance(BehaviorEngine.step)}
    }
    func testFastPointerSweepStopsLearningAfterPerceptionBaseline() throws {
        let e=engine(),b=bird();e.installFixtureBirds([b])
        func sweep(_ start:Int,_ end:Int) {
            for i in start..<end {
                var world=e.world;let angle=Double(i)*0.2
                world.pointer=CGPoint(x:b.position.x+150*cos(angle),y:b.position.y+150*sin(angle))
                e.updateWorld(world);e.advance(BehaviorEngine.step)
            }
        }
        sweep(0,60);let before=try XCTUnwrap(e.visitor(of:b)).calmSeconds
        XCTAssertTrue(e.perception.fast)
        sweep(60,180)
        XCTAssertEqual(e.visitor(of:b)?.calmSeconds,before)
    }
    func testDisableStopsLearningAndEffectsWithoutErasingKnownVisitors() throws {
        let e=engine(),b=bird();e.installFixtureBirds([b]);advance(e,12)
        let visitor=try XCTUnwrap(e.visitor(of:b)),traits=try XCTUnwrap(e.ecology(of:b)).temperament
        var settings=e.settings;settings.visitorMemoryEnabled=false;e.applySettings(settings)
        let archive=e.visitorMemoryArchive
        advance(e,12)
        XCTAssertEqual(e.visitorMemoryArchive,archive)
        XCTAssertEqual(e.ecology(of:b)?.familiarity,0)
        XCTAssertEqual(e.ecology(of:b)?.temperament,traits)
        settings.visitorMemoryEnabled=true;e.applySettings(settings)
        XCTAssertEqual(e.ecology(of:b)?.familiarity,visitor.familiarity)
        advance(e,1);XCTAssertGreaterThan(try XCTUnwrap(e.visitor(of:b)).familiarity,visitor.familiarity)
    }
    func testDisabledArrivalsStaySessionLocalAndTransientsNeverClaimVisitors() throws {
        let e=engine(enabled:false),resident=bird(),transient=bird()
        e.installFixtureBirds([resident]);e.register(transient,role:.transient)
        XCTAssertNil(e.visitor(of:resident));XCTAssertNil(e.visitor(of:transient));XCTAssertEqual(e.activeVisitorCount,0)
        var settings=e.settings;settings.visitorMemoryEnabled=true;e.applySettings(settings)
        XCTAssertNil(e.visitor(of:resident),"Enabling does not change an existing session-only bird's personality")
        let newcomer=bird();e.register(newcomer)
        XCTAssertNotNil(e.visitor(of:newcomer));XCTAssertEqual(e.activeVisitorCount,1)
    }
    func testFamiliarityAdjustsPassiveResponsesWithoutWeakeningClickRelocation() throws {
        let a=engine(),b=engine(),first=bird(),second=bird()
        a.installFixtureBirds([first]);b.installFixtureBirds([second])
        a.perchPlanner.setFamiliarity(1,for:a.id(of:first)!)
        let x=a.id(of:first)!,y=b.id(of:second)!
        XCTAssertGreaterThan(a.perchPlanner.automaticWeight(x,kind:.watch),b.perchPlanner.automaticWeight(y,kind:.watch))
        XCTAssertLessThan(a.perchPlanner.automaticWeight(x,kind:.sideHop),b.perchPlanner.automaticWeight(y,kind:.sideHop))
        a.handle(.pointerClick);b.handle(.pointerClick)
        XCTAssertEqual(a.ecology(of:first)?.disturbance,b.ecology(of:second)?.disturbance)
        let origin=first.position
        guard case .started = a.handle(.relocate(x)) else {return XCTFail("Click relocation must start immediately")}
        XCTAssertEqual(a.behavior(of:first),.relocate);XCTAssertEqual(first.state,.flying)
        XCTAssertEqual(first.position,origin);XCTAssertNotEqual(a.behavior(of:first),.takeoffPreparation)
    }
    func testCalmLearningAt30And60And120HzMatchesExactly() throws {
        var archives:[VisitorMemoryArchive]=[]
        for hz in [30,60,120] {
            let e=engine(),b=bird();e.installFixtureBirds([b]);advance(e,30,hz:hz)
            archives.append(e.visitorMemoryArchive)
        }
        XCTAssertEqual(archives[0],archives[1]);XCTAssertEqual(archives[1],archives[2])
    }
    func testPriorSimulationVersionsAreRejectedBeforeNestedPayloads() throws {
        for version in [1,2] {
            let object:[String:Any]=["version":1,"simulationVersion":version,"settings":"old payload"]
            XCTAssertThrowsError(try BehaviorInputLog.decode(JSONSerialization.data(withJSONObject:object)))
        }
    }
}
