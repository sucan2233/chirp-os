import XCTest
@testable import BirdingCore

enum FlycatcherInsectCatchTestSupport {
    static let species:SpeciesID = .yellowRumpedFlycatcher
    static let display=CGRect(x:0,y:0,width:2400,height:2000)
    static let frames=InsectCatchTestSupport.frames
    static func host(ground:Bool=false,origin:CGPoint = .zero)->Surface {
        Surface(id:2101,pid:42,rect:CGRect(x:origin.x+200,y:origin.y+(ground ? 2000:1650),
            width:2000,height:ground ? 0:180),isGround:ground)
    }
    static func engine(right:Bool=true,ground:Bool=false,scale:CGFloat=1,origin:CGPoint = .zero,
                       residents:Int=1,seed:UInt64=2101)throws->BehaviorEngine {
        let settings=InsectCatchTestSupport.settings(),e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let area=display.offsetBy(dx:origin.x,dy:origin.y)
        let others:[SpeciesID]=[.lightVentedBulbul,.redWhiskeredBulbul,.magpieRobin,.swinhoesWhiteEye,.chineseBlackbird]
        let hosts:[Surface]=(0..<max(0,residents-1)).map { index -> Surface in
            let x:CGFloat=origin.x+140+CGFloat(index%8)*280
            let y:CGFloat=origin.y+140+CGFloat(index/8)*110
            let rect=CGRect(x:x,y:y,width:180,height:30)
            return Surface(id:UInt32(2200+index),pid:43,rect:rect)
        }
        var manifest=Dictionary(uniqueKeysWithValues:others.map{($0,frames.subtracting(["catchOpen","catchClose","catchRecover"]))})
        manifest[species]=frames
        e.updateWorld(.init(screens:[area],displays:[area],surfaces:[host(ground:ground,origin:origin)]+hosts,
            scale:scale,pointer:CGPoint(x:origin.x+20,y:origin.y+20),availableFrames:manifest))
        let carrier=try RecordedFixtureBird(species:species,host:2101,fraction:right ? 0.15:0.85,
            perchDuration:600,facingRight:right).make(in:e)
        let background=hosts.enumerated().map {index,host in
            let bird=Bird(position:.zero,fraction:0.5,profile:settings.catalog.profile(others[index%others.count]),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600;return bird
        }
        e.installFixtureBirds([carrier]+background);advance(e,1)
        return e
    }
    static func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        InsectCatchTestSupport.advance(e,seconds,hz:hz)
    }
    static func start(_ e:BehaviorEngine,source:BehaviorSource = .preview)throws->(BehaviorRunID,FlycatcherInsectCatchExecution) {
        let result=e.handle(.insectCatch(species:species,source:source))
        guard case .started(let run)=result else {
            XCTFail("An ordinary perched flycatcher must enter a real sally: \(result)")
            throw NSError(domain:"FlycatcherInsectCatchTests",code:1)
        }
        return (run,try XCTUnwrap(e.runtime.runs[run]?.execution as? FlycatcherInsectCatchExecution))
    }
    static func finish(_ e:BehaviorEngine,_ run:BehaviorRunID,file:StaticString=#filePath,line:UInt=#line) {
        let remaining=max(0,25-(e.runtime.runs[run]?.age ?? 0))
        for _ in 0..<Int(ceil(remaining*60))+2 {
            if e.runtime.runs[run]==nil {return}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("The actual flycatcher run exceeded 25s",file:file,line:line)
    }
    static func missTrajectory(_ e:BehaviorEngine)throws->InsectTrajectory {
        let area=try XCTUnwrap(e.world.displays.first)
        return try XCTUnwrap(InsectTrajectory(waypoints:[
            .init(time:0,position:CGPoint(x:area.minX-20,y:area.minY+70)),
            .init(time:14,position:CGPoint(x:area.maxX+20,y:area.minY+70))],
            display:area,worldScale:e.world.scale,screens:e.world.screens,
            displays:e.world.displays,displayIDs:e.world.displayIDs))
    }
    static func reachContact(_ e:BehaviorEngine,_ run:BehaviorRunID)throws {
        for _ in 0..<3*60+2 {
            if e.lastInsectContact?.runID==run {return}
            if e.runtime.runs[run]==nil {break}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Production contact must occur within 3s")
        throw NSError(domain:"FlycatcherInsectCatchTests",code:2)
    }
    static func released(_ e:BehaviorEngine,_ run:BehaviorRunID,file:StaticString=#filePath,line:UInt=#line) {
        InsectCatchTestSupport.released(e,run,file:file,line:line)
        XCTAssertFalse(e.hasInsectCatchPreview,file:file,line:line)
        XCTAssertNil(e.sceneFocus,file:file,line:line)
    }
}

final class FlycatcherInsectCatchTests:XCTestCase {
    private typealias F=FlycatcherInsectCatchTestSupport
    private typealias Common=InsectCatchTestSupport

    private func edgeRoundingBudget(_ inner:CGFloat,_ outer:CGFloat,position:CGFloat,extent:CGFloat)->CGFloat {
        // Left-facing maxX evaluates (x-19*s)+48*s versus (x-29*s)+58*s.
        // Equal real-number edges can differ by one ULP after these operations.
        // Bound each edge by four ULPs of its coordinates and position/scale
        // operands, including cancellation near zero; never use a point margin.
        let magnitude=max(max(abs(inner),abs(outer)),max(abs(position),abs(extent)))
        return 4*magnitude.ulp
    }

    func testRealTopAndGroundSalliesReturnToOriginalLegalFeetAcrossDisplaysScalesAndHeadings() throws {
      for ground in [false,true] {
        for origin in [CGPoint.zero,CGPoint(x:-3000,y:-2200)] {
          for scale:CGFloat in [0.5,1,2] {
            for right in [false,true] {
                let e=try F.engine(right:right,ground:ground,scale:scale,origin:origin)
                let bird=try XCTUnwrap(e.birds.first),id=try XCTUnwrap(e.id(of:bird))
                let foot=bird.position,fraction=bird.fraction,identity=ObjectIdentifier(bird),start=e.time
                let area=try XCTUnwrap(e.world.displays.first)
                XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.edge,.top)
                XCTAssertEqual(bird.facingRight,right);XCTAssertFalse(bird.needsDestination)
                XCTAssertEqual(e.world.screens,[area]);XCTAssertEqual(e.world.scale,scale)
                if origin != .zero {XCTAssertLessThan(area.maxX,0);XCTAssertLessThan(area.maxY,0)}
                var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
                let (run,x)=try F.start(e),insect=try XCTUnwrap(e.insectSnapshot())
                let plan=x.plan,maxSpeed=try XCTUnwrap(plan.route.legs.map{$0.timing.peakSpeed}.max())
                XCTAssertEqual(plan.originalFoot,foot);XCTAssertEqual(plan.originalDestination.fraction,fraction)
                XCTAssertEqual(plan.route.position(at:0),foot)
                XCTAssertEqual(plan.route.speed(at:0),0,accuracy:1e-8)
                XCTAssertLessThanOrEqual(plan.route.legs[0].timing.duration,3)
                XCTAssertLessThanOrEqual(plan.interceptionWindow.upperBound,3)
                let radius=Geometry.distance(foot,plan.route.position(at:plan.nominalInterceptAge))/scale
                XCTAssertGreaterThanOrEqual(radius,80);XCTAssertLessThanOrEqual(radius,220)
                XCTAssertEqual(x.timeout,25);XCTAssertEqual(bird.position,foot)
                XCTAssertEqual(e.leasedBirdCount,1);XCTAssertEqual(e.reservedLandingCount,1)
                XCTAssertEqual(e.runtime.owners[id],run);XCTAssertEqual(insect.age,0)
                XCTAssertEqual(insect.trajectory.worldScale,scale);XCTAssertEqual(insect.remainingLifetime,12)
                XCTAssertFalse(area.intersects(CGRect(x:insect.position.x-8*scale,y:insect.position.y-8*scale,width:16*scale,height:16*scale)))
                for (a,b) in zip(insect.trajectory.waypoints,insect.trajectory.waypoints.dropFirst()) {
                    let speed=Double(Geometry.distance(a.position,b.position))/(b.time-a.time)
                    XCTAssertTrue(speed.isFinite);XCTAssertLessThanOrEqual(speed,480*Double(scale)+1e-7)
                }
                let readableAt=plan.interceptionWindow.lowerBound-0.8
                XCTAssertGreaterThanOrEqual(readableAt,0)
                let readableTimes = [readableAt,plan.interceptionWindow.lowerBound] +
                    insect.trajectory.waypoints.filter{$0.time>readableAt && $0.time<plan.interceptionWindow.lowerBound}.map(\.time)
                for age in readableTimes {
                    let center=insect.trajectory.position(at:age)
                    let canvas=CGRect(x:center.x-8*scale,y:center.y-8*scale,width:16*scale,height:16*scale)
                    XCTAssertGreaterThanOrEqual(canvas.minX,area.minX-1e-7)
                    XCTAssertGreaterThanOrEqual(canvas.minY,area.minY-1e-7)
                    XCTAssertLessThanOrEqual(canvas.maxX,area.maxX+1e-7)
                    XCTAssertLessThanOrEqual(canvas.maxY,area.maxY+1e-7)
                }
                var sawFlight=false,sawCapturedBeforeReturn=false,poses=Set<String>()
                for _ in 0..<25*60+2 {
                    let before=bird.position,time=e.time
                    e.advance(BehaviorEngine.step)
                    XCTAssertLessThanOrEqual(Geometry.distance(before,bird.position),CGFloat(maxSpeed*(e.time-time))+0.002)
                    XCTAssertLessThanOrEqual(Geometry.distance(foot,bird.position),220*scale+0.001)
                    // Engine.bounds adds a 2pt interaction margin. Screen
                    // containment applies to the actual canvas and the full
                    // landing footprint for either facing, including ground.
                    let render=try XCTUnwrap(e.renderSnapshot().first{$0.id==id})
                    let landing=Geometry.landingFootprint(at:bird.position,scale:render.scale)
                    let context="ground=\(ground), origin=\(origin), scale=\(scale), right=\(right), age=\(e.time-start)"
                    XCTAssertEqual(render.position,bird.position)
                    XCTAssertTrue(area.contains(render.rect),context)
                    XCTAssertTrue(area.contains(landing),context)
                    XCTAssertLessThanOrEqual(landing.minX-render.rect.minX,
                        edgeRoundingBudget(render.rect.minX,landing.minX,position:render.position.x,extent:29*render.scale),"left: \(context)")
                    XCTAssertLessThanOrEqual(render.rect.maxX-landing.maxX,
                        edgeRoundingBudget(render.rect.maxX,landing.maxX,position:render.position.x,extent:58*render.scale),"right: \(context)")
                    XCTAssertLessThanOrEqual(landing.minY-render.rect.minY,
                        edgeRoundingBudget(render.rect.minY,landing.minY,position:render.position.y,
                            extent:max(39,abs(render.hopOffset-39))*render.scale),"top: \(context)")
                    XCTAssertLessThanOrEqual(render.rect.maxY-landing.maxY,
                        edgeRoundingBudget(render.rect.maxY,landing.maxY,position:render.position.y,
                            extent:max(48,abs(render.hopOffset-39))*render.scale),"bottom: \(context)")
                    XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                    XCTAssertEqual(ObjectIdentifier(bird),identity)
                    if bird.state == .flying {sawFlight=true}
                    if let pose=e.runtime.presentation(for:id,in:e)?.frameName {poses.insert(pose)}
                    if let target=e.insectSnapshot() {
                        XCTAssertEqual(target.id,insect.id);XCTAssertEqual(target.trajectory,insect.trajectory)
                        XCTAssertEqual(target.position,insect.trajectory.position(at:target.age))
                    }
                    if e.runtime.runs[run] != nil {
                        XCTAssertTrue(observations.isEmpty);XCTAssertTrue(Common.terminals(e,run).isEmpty)
                        if let contact=e.lastInsectContact {
                            XCTAssertTrue(x.captured);XCTAssertNil(e.insectSnapshot())
                            XCTAssertEqual(contact.runID,run);XCTAssertEqual(contact.birdID,id);XCTAssertEqual(contact.insectID,insect.id)
                            XCTAssertLessThanOrEqual(contact.insectAge,3+1e-8)
                            XCTAssertLessThanOrEqual(Geometry.distance(contact.beakPosition,contact.insectPosition),3*scale+1e-8)
                            if bird.state != .perched {sawCapturedBeforeReturn=true}
                        }
                    } else {break}
                }
                F.released(e,run);XCTAssertEqual(Common.terminals(e,run).map(\.type),[.completed])
                let contact=try XCTUnwrap(e.lastInsectContact),terminal=try XCTUnwrap(Common.terminals(e,run).first)
                XCTAssertLessThanOrEqual(terminal.time-start,25+1e-8)
                XCTAssertGreaterThanOrEqual(terminal.time-contact.time,0.48-1e-8)
                XCTAssertTrue(sawFlight);XCTAssertTrue(sawCapturedBeforeReturn)
                XCTAssertTrue(poses.isSuperset(of:["catchOpen","catchClose","catchRecover"]))
                XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.hostID,2101);XCTAssertEqual(bird.hostPID,42)
                XCTAssertEqual(bird.position,foot);XCTAssertEqual(bird.fraction,fraction)
                XCTAssertFalse(bird.needsDestination);XCTAssertFalse(bird.isCoordinatedFlying)
                let returnedHostID=try XCTUnwrap(bird.hostID)
                XCTAssertTrue(Geometry.isLandingVisible(on:returnedHostID,at:foot,surfaces:e.world.surfaces,scale:e.spriteScale(for:bird)))
                XCTAssertEqual(observations.count,1);XCTAssertEqual(observations.first?.kind,.insectCatch)
                XCTAssertEqual(observations.first?.species,[F.species]);XCTAssertEqual(observations.first?.source,.preview)
                XCTAssertEqual(e.insectMissedTargetCount,0);XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
                F.advance(e,1);XCTAssertEqual(Common.terminals(e,run).count,1);XCTAssertEqual(observations.count,1)
            }
          }
        }
      }
    }

    func testGenuineNonintersectingMissReturnsBeforeFailureAndNeverObservesSuccess() throws {
        let e=try F.engine(),bird=try XCTUnwrap(e.birds.first),foot=bird.position
        let path=try F.missTrajectory(e)
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        guard case .started(let run)=e.startInsectCatchFixture(species:F.species,trajectory:path) else {
            return XCTFail("A physical nonintersecting route must use normal admission and execution")
        }
        let x=try XCTUnwrap(e.runtime.runs[run]?.execution as? InsectCatchMotionExecution)
        let insect=try XCTUnwrap(e.insectSnapshot())
        F.advance(e,0.1);XCTAssertTrue(Common.terminals(e,run).isEmpty)
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(Common.terminals(e,run).map(\.type),[.failed])
        XCTAssertEqual(Common.terminals(e,run).first?.reason,.missedTarget)
        XCTAssertFalse(x.captured);XCTAssertGreaterThan(try XCTUnwrap(x.minimumBeakDistance),3)
        XCTAssertNil(e.lastInsectContact);XCTAssertEqual(e.insectMissedTargetCount,1);XCTAssertTrue(observations.isEmpty)
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,foot);XCTAssertEqual(bird.hostID,2101)
        XCTAssertFalse(bird.isCoordinatedFlying);XCTAssertFalse(bird.needsDestination)
        XCTAssertEqual(e.insectSnapshot()?.id,insect.id);XCTAssertEqual(e.insectSnapshot()?.trajectory,path)
        F.advance(e,13);XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
        XCTAssertEqual(Common.terminals(e,run).count,1);XCTAssertTrue(observations.isEmpty)
    }

    func testAdmissionRequiresWholeArtEnabledSpeciesAndAnOrdinaryPerchedResidentWithoutWaiting() throws {
        let required:Set<String>=["stand","land0","land1","land2","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","catchOpen","catchClose","catchRecover"]
        for missing in required.sorted() {
            let e=try F.engine();var world=e.world;world.availableFrames[F.species]?.remove(missing);e.updateWorld(world)
            XCTAssertEqual(e.handle(.insectCatch(species:F.species,source:.preview)),.rejected(.missingFrames),missing)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertNil(e.insectSnapshot());XCTAssertFalse(e.hasInsectCatchPreview)
        }
        for condition in ["art","disabled","speciesDisabled","noBird","fixedPerch","airborne","side","panel","noSpace"] {
            let e=try F.engine(),bird=try XCTUnwrap(e.birds.first),foot=bird.position
            var world=e.world,settings=e.settings
            let reason:BehaviorReason
            switch condition {
            case "art":world.insectArtAvailable=false;e.updateWorld(world);reason = .missingFrames
            case "disabled":settings.insectCatchEnabled=false;e.applySettings(settings);reason = .disabled
            case "speciesDisabled":
                let index=try XCTUnwrap(settings.probabilities.entries.firstIndex{$0.id==F.species})
                settings.probabilities.adjust(at:index,to:0);e.applySettings(settings);reason = .noSpecies
            case "noBird":e.handle(.remove(try XCTUnwrap(e.id(of:bird))));reason = .noSpecies
            case "fixedPerch":
                let host=Surface(id:2102,pid:42,rect:F.host().rect,isFixedPerch:true)
                world.surfaces=[host];e.updateWorld(world);bird.perch(on:host,spriteScale:e.spriteScale(for:bird));reason = .unavailableBird
            case "airborne":bird.fly(to:CGPoint(x:1500,y:1400),host:nil,arc:0,allowsOrbit:false,random:{0.5});reason = .unavailableBird
            case "side":bird.edge = .left;bird.perch(on:F.host(),spriteScale:e.spriteScale(for:bird));reason = .unavailableBird
            case "panel":
                let panel=Surface(id:2103,pid:42,rect:F.host().rect,layer:1)
                world.surfaces=[panel];e.updateWorld(world);bird.perch(on:panel,spriteScale:e.spriteScale(for:bird));reason = .unavailableBird
            default:
                let box=Geometry.landingFootprint(at:foot,scale:e.spriteScale(for:bird)).insetBy(dx:-2,dy:-2)
                world.screens=[box];world.displays=[box];e.updateWorld(world);reason = .noSpace
            }
            let residents=e.residentCount
            XCTAssertEqual(e.handle(.insectCatch(species:F.species,source:.preview)),.rejected(reason),condition)
            XCTAssertFalse(e.hasInsectCatchPreview,condition);XCTAssertEqual(e.activeRunCount,0,condition)
            XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
            XCTAssertNil(e.insectSnapshot());XCTAssertEqual(e.residentCount,residents)
        }
    }
}
