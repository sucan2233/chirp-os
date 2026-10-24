import XCTest
@testable import BirdingCore

enum InsectCatchTestSupport {
    static let display=CGRect(x:0,y:0,width:2400,height:2000)
    static let frames:Set<String>=["stand","blink","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7",
        "land0","land1","land2","glide0","glide1","glide2","bank0","bank1","bank2","bound",
        "catchOpen","catchClose","catchRecover"]
    static func settings()->BirdSettings {
        var value=BirdSettings();value.perchActions=false;value.passiveAttentionEnabled=false
        value.pointerVisits=false;value.flockPasses=false;value.socialInteractions=false
        value.ambientLeafPlayEnabled=false;return value
    }
    static func host(right:Bool=true)->Surface {
        Surface(id:1901,pid:42,rect:CGRect(x:right ? 2000:120,y:1650,width:280,height:180))
    }
    static func fixtureBird(right:Bool=true,airborne:Bool=true)->RecordedFixtureBird {
        var bird=RecordedFixtureBird(species:.barnSwallow,host:1901,fraction:0.5,perchDuration:600,facingRight:right)
        if airborne {bird.flightOrigin=RecordedPoint(CGPoint(x:right ? 220:2180,y:1650))}
        return bird
    }
    static func engine(right:Bool=true,airborne:Bool=true,residents:Int=1,
                       scale:CGFloat=1,displayOrigin:CGPoint = .zero)throws->BehaviorEngine {
        let settings=Self.settings(),e=BehaviorEngine(seed:1901,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let area=display.offsetBy(dx:displayOrigin.x,dy:displayOrigin.y)
        func translated(_ surface:Surface)->Surface {
            var value=surface;value.rect=value.rect.offsetBy(dx:displayOrigin.x,dy:displayOrigin.y);return value
        }
        let species:[SpeciesID]=[.lightVentedBulbul,.redWhiskeredBulbul,.magpieRobin,.swinhoesWhiteEye,.chineseBlackbird]
        let hosts=(0..<max(0,residents-1)).map {index in
            translated(Surface(id:UInt32(2000+index),pid:42,
                rect:CGRect(x:140+CGFloat(index%8)*280,y:140+CGFloat(index/8)*110,width:180,height:30)))
        }
        var manifest=Dictionary(uniqueKeysWithValues:species.map{($0,frames.subtracting(SpeciesBehaviorProfile.catchFrameNames))})
        manifest[.barnSwallow]=frames
        e.updateWorld(.init(screens:[area],displays:[area],surfaces:[translated(host(right:right))]+hosts,scale:scale,
            pointer:CGPoint(x:displayOrigin.x+20,y:displayOrigin.y+20),availableFrames:manifest))
        var fixture=fixtureBird(right:right,airborne:airborne)
        if let origin=fixture.flightOrigin {
            fixture.flightOrigin=RecordedPoint(CGPoint(x:origin.value.x+displayOrigin.x,y:origin.value.y+displayOrigin.y))
        }
        let swallow=try fixture.make(in:e)
        let others=hosts.enumerated().map {index,host in
            let bird=Bird(position:.zero,fraction:0.5,profile:settings.catalog.profile(species[index%species.count]),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600;return bird
        }
        e.installFixtureBirds([swallow]+others)
        if airborne {advance(e,0.75)}
        return e
    }
    static func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    static func start(_ e:BehaviorEngine,source:BehaviorSource = .preview)throws->(BehaviorRunID,InsectCatchExecution) {
        let result=e.handle(.insectCatch(species:.barnSwallow,source:source))
        guard case .started(let run)=result else {
            XCTFail("An established ordinary swallow flight must admit a real catch: \(result)")
            throw NSError(domain:"InsectCatchTests",code:1)
        }
        return (run,try XCTUnwrap(e.runtime.runs[run]?.execution as? InsectCatchExecution))
    }
    static func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID)->[BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    static func finish(_ e:BehaviorEngine,_ run:BehaviorRunID) {
        for _ in 0..<35*60+2 {
            guard e.runtime.runs[run] != nil else {return}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("The catch run exceeded its35s deadline")
    }
    static func released(_ e:BehaviorEngine,_ run:BehaviorRunID,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertNil(e.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line);XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertEqual(e.habitatReservationCount,0,file:file,line:line);XCTAssertFalse(e.ambientBusy,file:file,line:line)
        XCTAssertEqual(terminals(e,run).count,1,file:file,line:line)
    }
    static func missTrajectory(in e:BehaviorEngine)throws->InsectTrajectory {
        // The bird stays in the lower corridor; this immutable insect crosses
        // the upper screen without ever intersecting its beak or return path.
        try XCTUnwrap(InsectTrajectory(waypoints:[.init(time:0,position:CGPoint(x:-20,y:70)),
            .init(time:14,position:CGPoint(x:2420,y:70))],display:display,worldScale:e.world.scale,
            screens:e.world.screens,displays:e.world.displays,displayIDs:e.world.displayIDs))
    }
}

final class InsectCatchTests:XCTestCase {
    private typealias F=InsectCatchTestSupport
    private func vector(_ a:CGPoint,_ b:CGPoint)->CGPoint {CGPoint(x:b.x-a.x,y:b.y-a.y)}
    private func alignment(_ a:CGPoint,_ b:CGPoint)->CGFloat {
        (a.x*b.x+a.y*b.y)/max(1e-9,Geometry.distance(.zero,a)*Geometry.distance(.zero,b))
    }

    func testBothHeadingsJoinMeasuredOrdinaryFlightThenCompleteOnlyAfterRealRecoveryAcrossScalesAndNegativeDisplays() throws {
      for origin in [CGPoint.zero,CGPoint(x:-3000,y:-2200)] {
        for scale:CGFloat in [0.5,1,2] {
          for right in [false,true] {
            let area=F.display.offsetBy(dx:origin.x,dy:origin.y)
            let e=try F.engine(right:right,scale:scale,displayOrigin:origin),bird=try XCTUnwrap(e.birds.first)
            XCTAssertEqual(e.world.screens,[area]);XCTAssertEqual(e.world.displays,[area])
            XCTAssertEqual(e.world.scale,scale)
            if origin != .zero {
                XCTAssertLessThan(area.maxX,0);XCTAssertLessThan(area.maxY,0)
                XCTAssertLessThan(bird.position.x,0);XCTAssertLessThan(bird.position.y,0)
            }
            let initial=try XCTUnwrap(bird.airborneFlight),identity=ObjectIdentifier(bird)
            let frame=e.renderSnapshot().first?.frameName
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            let (run,x)=try F.start(e),plan=x.plan,start=e.time
            XCTAssertEqual(bird.position,initial.position);XCTAssertEqual(ObjectIdentifier(bird),identity)
            XCTAssertEqual(plan.route.position(at:0),initial.position)
            XCTAssertEqual(plan.route.speed(at:0),Double(Geometry.distance(.zero,initial.velocity)),accuracy:0.1)
            XCTAssertGreaterThan(alignment(vector(plan.route.position(at:0),plan.route.position(at:0.001)),initial.velocity),0.99)
            if plan.interceptionWindow.lowerBound>0 {XCTAssertEqual(e.renderSnapshot().first?.frameName,frame)}
            XCTAssertLessThanOrEqual(plan.interceptionWindow.upperBound,4)
            XCTAssertLessThanOrEqual(plan.route.legs[0].timing.duration,4)
            XCTAssertEqual(x.timeout,35);XCTAssertEqual(e.leasedBirdCount,1);XCTAssertEqual(e.reservedLandingCount,1)
            let entity=try XCTUnwrap(e.insectSnapshot()),path=entity.trajectory
            XCTAssertEqual(path.display,area);XCTAssertEqual(path.worldScale,scale)
            XCTAssertEqual(path.collisionRadius,3*scale)
            XCTAssertEqual(plan.spriteScale,e.spriteScale(for:bird))
            XCTAssertEqual(entity.age,0);XCTAssertLessThanOrEqual(e.propSnapshot().count,1)
            XCTAssertFalse(area.intersects(CGRect(x:entity.position.x-8*scale,y:entity.position.y-8*scale,width:16*scale,height:16*scale)))
            // Independent product limits, rather than the planner's constants
            // or its partial-sprite visibleFrom timestamp.
            for (a,b) in zip(path.waypoints,path.waypoints.dropFirst()) {
                let dt=b.time-a.time
                XCTAssertGreaterThan(dt,0)
                let speed=Double(hypot(b.position.x-a.position.x,b.position.y-a.position.y))/dt
                XCTAssertTrue(speed.isFinite)
                XCTAssertLessThanOrEqual(speed,480*Double(scale)+1e-7)
            }
            let readableAt=plan.interceptionWindow.lowerBound-0.8
            XCTAssertGreaterThanOrEqual(readableAt,0)
            XCTAssertGreaterThanOrEqual(path.duration,plan.interceptionWindow.lowerBound)
            // On a piecewise linear path, containment at both ends and every
            // intervening waypoint proves continuous full-canvas visibility
            // throughout the .8s immediately before the open-beak window.
            let visibilityTimes = [readableAt,plan.interceptionWindow.lowerBound] +
                path.waypoints.filter{$0.time>readableAt && $0.time<plan.interceptionWindow.lowerBound}.map(\.time)
            for age in visibilityTimes {
                let center=path.position(at:age)
                let canvas=CGRect(x:center.x-8*scale,y:center.y-8*scale,width:16*scale,height:16*scale)
                XCTAssertGreaterThanOrEqual(canvas.minX,area.minX-1e-7)
                XCTAssertGreaterThanOrEqual(canvas.minY,area.minY-1e-7)
                XCTAssertLessThanOrEqual(canvas.maxX,area.maxX+1e-7)
                XCTAssertLessThanOrEqual(canvas.maxY,area.maxY+1e-7)
            }
            let maxSpeed=try XCTUnwrap(plan.route.legs.map{$0.timing.peakSpeed}.max())
            var sawCapturedWithOwner=false,sawOpen=false,sawClose=false,sawRecover=false
            for _ in 0..<35*60+2 {
                let before=bird.position,t=e.time
                e.advance(BehaviorEngine.step)
                XCTAssertLessThanOrEqual(Geometry.distance(before,bird.position),CGFloat(maxSpeed*(e.time-t))+0.002)
                XCTAssertTrue(area.contains(e.bounds(of:bird)))
                XCTAssertEqual(e.residentCount,1);XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.departureCount,0)
                if let insect=e.insectSnapshot() {
                    XCTAssertEqual(insect.id,entity.id);XCTAssertEqual(insect.trajectory,path)
                    XCTAssertEqual(insect.position,path.position(at:insect.age))
                }
                let pose=e.runtime.presentation(for:plan.id,in:e)?.frameName
                sawOpen = sawOpen || pose == "catchOpen";sawClose = sawClose || pose == "catchClose"
                sawRecover = sawRecover || pose == "catchRecover"
                if let contact=e.lastInsectContact,e.runtime.runs[run] != nil {
                    sawCapturedWithOwner=true;XCTAssertNil(e.insectSnapshot());XCTAssertTrue(observations.isEmpty)
                    XCTAssertEqual(contact.insectID,entity.id);XCTAssertEqual(contact.runID,run)
                    XCTAssertEqual(contact.insectPosition,path.position(at:contact.insectAge))
                    XCTAssertLessThanOrEqual(Geometry.distance(contact.beakPosition,contact.insectPosition),3*scale)
                    XCTAssertTrue(area.contains(contact.insectPosition))
                    XCTAssertGreaterThanOrEqual(contact.insectAge,plan.interceptionWindow.lowerBound)
                    XCTAssertLessThan(contact.insectAge,plan.interceptionWindow.upperBound)
                }
                if e.runtime.runs[run]==nil {break}
            }
            F.released(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            let contact=try XCTUnwrap(e.lastInsectContact),terminal=try XCTUnwrap(F.terminals(e,run).first)
            XCTAssertGreaterThanOrEqual(terminal.time-contact.time,0.48-1e-8)
            XCTAssertLessThanOrEqual(terminal.time-start,35+1e-8)
            XCTAssertTrue(sawCapturedWithOwner);XCTAssertTrue(sawOpen);XCTAssertTrue(sawClose);XCTAssertTrue(sawRecover)
            XCTAssertFalse(bird.isCoordinatedFlying);XCTAssertFalse(bird.needsDestination)
            XCTAssertEqual(bird.state,.flying,"Completion restores real ordinary flight, before that flight lands")
            XCTAssertEqual(try XCTUnwrap(bird.airborneFlight).destination,initial.destination)
            XCTAssertEqual(bird.hostID,plan.originalHost.id)
            XCTAssertGreaterThan(Geometry.distance(.zero,bird.ordinaryFlightVelocity),0)
            XCTAssertEqual(observations.count,1);XCTAssertEqual(observations.first?.kind,.insectCatch)
            XCTAssertEqual(observations.first?.species,[.barnSwallow]);XCTAssertEqual(e.insectMissedTargetCount,0)
            F.advance(e,30)
            XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.position,initial.destination)
            XCTAssertEqual(F.terminals(e,run).count,1);XCTAssertEqual(observations.count,1)
            XCTAssertTrue(e.propSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
          }
        }
      }
    }

    func testLegalNonintersectingTargetRestoresThenFailsMissedTargetWithoutObservation() throws {
        let e=try F.engine(),bird=try XCTUnwrap(e.birds.first),initial=try XCTUnwrap(bird.airborneFlight)
        let path=try F.missTrajectory(in:e)
        var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
        guard case .started(let run)=e.startInsectCatchFixture(species:.barnSwallow,trajectory:path) else {
            return XCTFail("A legal independent insect route must enter the same production execution")
        }
        let id=try XCTUnwrap(e.insectSnapshot()).id
        let x=try XCTUnwrap(e.runtime.runs[run]?.execution as? InsectCatchExecution)
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.failed]);XCTAssertEqual(F.terminals(e,run).first?.reason,.missedTarget)
        XCTAssertFalse(x.captured);XCTAssertGreaterThan(try XCTUnwrap(x.minimumBeakDistance),3)
        XCTAssertNil(e.lastInsectContact);XCTAssertEqual(e.insectMissedTargetCount,1);XCTAssertTrue(observations.isEmpty)
        XCTAssertFalse(bird.isCoordinatedFlying);XCTAssertFalse(bird.needsDestination)
        XCTAssertEqual(try XCTUnwrap(bird.airborneFlight).destination,initial.destination)
        XCTAssertGreaterThan(Geometry.distance(.zero,bird.ordinaryFlightVelocity),0)
        XCTAssertEqual(e.insectSnapshot()?.id,id,"Missed contact cannot erase an unexpired independent target")
        XCTAssertEqual(e.insectSnapshot()?.trajectory,path)
        F.advance(e,13);XCTAssertNil(e.insectSnapshot());XCTAssertTrue(e.propSnapshot().isEmpty)
        XCTAssertEqual(e.insectMissedTargetCount,1);XCTAssertTrue(observations.isEmpty)
        XCTAssertEqual(F.terminals(e,run).count,1)
    }

    func testClickCancellationKeepsTheSameTargetRouteAndRemainingLifetime() throws {
        for phase in [0,1] {
            let e=try F.engine(),(run,x)=try F.start(e)
            if phase==1 {F.advance(e,max(BehaviorEngine.step,x.plan.interceptionWindow.lowerBound+0.02))}
            let before=try XCTUnwrap(e.insectSnapshot()),bird=try XCTUnwrap(e.bird(x.plan.id)),foot=bird.position
            var observations:[BehaviorObservation]=[];e.observationObserver={observations.append($0)}
            e.handle(.pointerClick)
            F.released(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.cancelled])
            XCTAssertEqual(F.terminals(e,run).first?.reason,.userInput);XCTAssertEqual(bird.position,foot)
            let after=try XCTUnwrap(e.insectSnapshot())
            XCTAssertEqual(after.id,before.id);XCTAssertEqual(after.age,before.age);XCTAssertEqual(after.trajectory,before.trajectory)
            F.advance(e,0.1)
            let moved=try XCTUnwrap(e.insectSnapshot())
            XCTAssertEqual(moved.id,before.id);XCTAssertEqual(moved.age,before.age+0.1,accuracy:1e-9)
            XCTAssertEqual(moved.position,before.trajectory.position(at:moved.age))
            XCTAssertEqual(moved.remainingLifetime,12-moved.age,accuracy:1e-9)
            F.advance(e,13);XCTAssertNil(e.insectSnapshot());XCTAssertNil(e.lastInsectContact)
            XCTAssertTrue(observations.isEmpty);XCTAssertEqual(e.insectMissedTargetCount,0)
        }
    }

    func testPauseFreezesEntryOpenAndCaptureRecoveryWithoutResettingAnyClock() throws {
        for phase in [0,1,2] {
            let e=try F.engine(),(run,x)=try F.start(e)
            if phase==1 {F.advance(e,x.plan.interceptionWindow.lowerBound+0.02)}
            if phase==2 {
                for _ in 0..<4*60 {if e.lastInsectContact != nil {break};e.advance(BehaviorEngine.step)}
                XCTAssertNotNil(e.lastInsectContact)
            }
            XCTAssertNotNil(e.runtime.runs[run]);e.handle(.pause(true))
            let before=BehaviorReplayReport(engine:e,events:[]),age=e.runtime.runs[run]?.age
            F.advance(e,2)
            let after=BehaviorReplayReport(engine:e,events:[])
            XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(after.props,before.props)
            XCTAssertEqual(after.insect,before.insect);XCTAssertEqual(after.lastInsectContact,before.lastInsectContact)
            XCTAssertEqual(after.schedulerRemaining,before.schedulerRemaining)
            XCTAssertEqual(after.insectCooldownRemaining,before.insectCooldownRemaining)
            XCTAssertEqual(e.runtime.runs[run]?.age,age);XCTAssertTrue(F.terminals(e,run).isEmpty)
            e.handle(.pause(false));F.finish(e,run);F.released(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            XCTAssertNil(e.insectSnapshot());XCTAssertEqual(e.insectMissedTargetCount,0)
        }
    }

    func testDisabledClearSleepAndPausedGeometryLossReleaseRunAndEntity() throws {
        for mutation in ["disabled","clear","clearScene","clearProps","removeProp","sleep","screens","scale","art","frames"] {
            let e=try F.engine(),(run,x)=try F.start(e),id=x.insectID
            F.advance(e,0.05);e.handle(.pause(true))
            switch mutation {
            case "disabled":var settings=e.settings;settings.insectCatchEnabled=false;e.applySettings(settings)
            case "clear":e.handle(.clearInsect)
            case "clearScene":e.handle(.clearCurrentScene)
            case "clearProps":e.handle(.clearProps)
            case "removeProp":e.handle(.removeProp(id))
            case "sleep":e.handle(.cancelAmbient(.sleep))
            default:
                var world=e.world
                if mutation == "screens" {world.screens[0].size.width-=10}
                if mutation == "scale" {world.scale=1.1}
                if mutation == "art" {world.insectArtAvailable=false}
                if mutation == "frames" {world.availableFrames[.barnSwallow]?.remove("catchClose")}
                e.updateWorld(world)
            }
            F.released(e,run);XCTAssertFalse(F.terminals(e,run).contains{$0.type == .completed},mutation)
            if mutation != "frames" {XCTAssertNil(e.insectSnapshot(),mutation);XCTAssertTrue(e.propSnapshot().isEmpty,mutation)}
            XCTAssertFalse(e.hasInsectCatchPreview);XCTAssertNil(e.sceneFocus)
            e.handle(.pause(false));F.advance(e,13)
            XCTAssertNil(e.insectSnapshot());XCTAssertEqual(F.terminals(e,run).count,1)
        }
    }

    func testCapturedBirdRestoresASafeOrdinaryTargetWhenOriginalHostDisappears() throws {
        let e=try F.engine(),(run,x)=try F.start(e),bird=try XCTUnwrap(e.bird(x.plan.id))
        for _ in 0..<4*60 {if e.lastInsectContact != nil {break};e.advance(BehaviorEngine.step)}
        XCTAssertNotNil(e.lastInsectContact);XCTAssertNotNil(e.runtime.runs[run])
        let foot=bird.position
        let replacement=Surface(id:1903,pid:43,rect:CGRect(x:1900,y:1650,width:300,height:180))
        var world=e.world;world.surfaces=[replacement];e.updateWorld(world)
        XCTAssertEqual(bird.position,foot,"Host loss cannot translate the airborne bird")
        XCTAssertFalse(bird.isCoordinatedFlying);XCTAssertFalse(bird.needsDestination)
        XCTAssertEqual(bird.hostID,replacement.id);XCTAssertNotNil(e.runtime.runs[run])
        F.finish(e,run);F.released(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
        XCTAssertEqual(e.insectMissedTargetCount,0);XCTAssertNil(e.insectSnapshot())
        F.advance(e,30)
        XCTAssertEqual(bird.state,.perched);XCTAssertEqual(bird.hostID,replacement.id)
        XCTAssertTrue(F.display.contains(e.bounds(of:bird)))
        XCTAssertTrue(Geometry.isLandingVisible(on:replacement.id,at:bird.position,surfaces:e.world.surfaces,scale:e.spriteScale(for:bird)))
    }

    func testRealClickRelocationAndExternalRouteReplacementKeepTheirNewOwnership() throws {
        for replace in [false,true] {
            let e=try F.engine(),(run,x)=try F.start(e),bird=try XCTUnwrap(e.bird(x.plan.id))
            F.advance(e,0.05);let foot=bird.position
            var replacementRun:BehaviorRunID?
            if replace {
                bird.fly(to:CGPoint(x:1800,y:1400),host:nil,arc:0,allowsOrbit:false,random:{0.5})
                e.updateWorld(e.world)
            } else {
                guard case .started(let id)=e.handle(.relocate(x.plan.id)) else {return XCTFail("An active catch must accept immediate user relocation")}
                replacementRun=id
            }
            XCTAssertEqual(bird.position,foot)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[replace ? .failed:.cancelled])
            XCTAssertEqual(F.terminals(e,run).first?.reason,replace ? .targetInvalid:.replaced)
            XCTAssertFalse(e.runtime.owners.values.contains(run));XCTAssertFalse(bird.isCoordinatedFlying)
            if let replacementRun {XCTAssertEqual(e.runtime.owners[x.plan.id],replacementRun)}
            let revision=bird.motionRevision
            F.advance(e,0.2)
            XCTAssertEqual(bird.motionRevision,revision);XCTAssertNotEqual(bird.position,foot)
            XCTAssertEqual(F.terminals(e,run).count,1);XCTAssertEqual(e.insectMissedTargetCount,0)
            e.handle(.cancelAmbient(.sleep));XCTAssertEqual(e.activeRunCount,0);XCTAssertNil(e.insectSnapshot())
        }
    }
}
