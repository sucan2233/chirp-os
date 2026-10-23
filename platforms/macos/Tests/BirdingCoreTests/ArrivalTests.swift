import XCTest
@testable import BirdingCore

final class ArrivalTests: XCTestCase {
    private let layouts: [[CGRect]] = [
        [CGRect(x:0,y:0,width:1600,height:1200)],
        [CGRect(x:-1600,y:0,width:1600,height:1200),CGRect(x:0,y:0,width:1600,height:1200)],
        [CGRect(x:0,y:-1200,width:1600,height:1200),CGRect(x:0,y:0,width:1600,height:1200)],
        [CGRect(x:-1800,y:-800,width:1600,height:1200),CGRect(x:0,y:200,width:1600,height:1200)]
    ]

    private func fixture(displays:[CGRect],scale:CGFloat,species:SpeciesID,seed:UInt64=73) -> BehaviorEngine {
        var settings=BirdSettings()
        let index=settings.probabilities.entries.firstIndex{$0.id == species}!
        settings.probabilities.adjust(at:index,to:10000)
        // Exercise the largest supported species setting as well as global zoom.
        let profileIndex=settings.catalog.species.firstIndex{$0.id == species}!
        settings.catalog.species[profileIndex].adultLengthCM=110
        settings.perchActions=false
        let engine=BehaviorEngine(seed:seed,settings:settings)
        engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
        let workAreas=displays.map{CGRect(x:$0.minX+40,y:$0.minY+24,width:$0.width-80,height:$0.height-74)}
        let grounds=displays.indices.map{Geometry.ground(id:UInt32($0+1),display:displays[$0],workArea:workAreas[$0])}
        engine.updateWorld(BehaviorWorld(screens:workAreas,displays:displays,surfaces:grounds,scale:scale))
        return engine
    }

    private func intersects(_ rect:CGRect,_ displays:[CGRect]) -> Bool {
        displays.contains{$0.intersects(rect)}
    }

    private func stepLimit(_ bird:Bird) -> CGFloat {
        let motion=FlightBehavior.motion(bird.profile.id)
        let cruise=FlightBehavior.cruiseSpeed(bird.profile.id,multiplier:bird.profile.speed)
        // Transit wave derivatives add to the arc-length speed. Fixed hosts do
        // not contribute any target movement in these fixtures.
        let waveSpeed=motion.wave*(2 * .pi/motion.cycle + .pi/max(0.001,bird.flightDuration))
        return CGFloat((cruise+waveSpeed)*BehaviorEngine.step)+0.1
    }

    func testFailedArrivalDoesNotPublishAnUnplannedBirdAndCanRetry() {
        let engine=BehaviorEngine(seed:73)
        engine.populationEnabled=false;engine.ambientEnabled=false
        engine.updateWorld(BehaviorWorld(displays:layouts[0]))
        engine.bringInBird()
        XCTAssertTrue(engine.birds.isEmpty)
        XCTAssertTrue(engine.renderSnapshot().isEmpty)
        XCTAssertEqual(engine.arrivalCount,0)
        XCTAssertNil(engine.lastArrivalPosition)
        engine.updateWorld(BehaviorWorld(screens:layouts[0],displays:layouts[0]))
        engine.bringInBird()
        XCTAssertEqual(engine.birds.count,1)
        XCTAssertEqual(engine.arrivalCount,1)
        XCTAssertFalse(intersects(engine.renderSnapshot()[0].rect,layouts[0]))
        let bird=engine.birds[0],origin=bird.position
        engine.advance(BehaviorEngine.step)
        XCTAssertGreaterThan(Geometry.distance(origin,bird.position),0)
        XCTAssertLessThanOrEqual(Geometry.distance(origin,bird.position),stepLimit(bird))
    }

    func testEverySpeciesPreservesBothOffscreenOriginsThroughItsFirstFlight() throws {
        let display=CGRect(x:-1600,y:-400,width:1600,height:1200)
        let area=display.insetBy(dx:130,dy:180)
        let host=Surface(id:1,rect:CGRect(x:-1400,y:500,width:1200,height:200))
        let target=CGPoint(x:-800,y:500)
        for profile in SpeciesCatalog.standard.species {
            for right in [false,true] {
                let origin=try XCTUnwrap(Migration.outsidePoint(screens:[display],right:right,fraction:0.4,margin:380))
                let bird=Bird(position:origin,fraction:0.5,profile:profile,random:{0.5})
                bird.fly(to:target,host:host,airspace:area,random:{0.5})
                XCTAssertEqual(bird.position,origin,profile.id.rawValue)
                bird.tick(0)
                XCTAssertEqual(bird.position,origin,profile.id.rawValue)
                var previous=origin,crossed=false
                for _ in 0...Int(ceil(bird.flightDuration/BehaviorEngine.step)) {
                    bird.tick(BehaviorEngine.step)
                    XCTAssertLessThanOrEqual(Geometry.distance(previous,bird.position),stepLimit(bird),profile.id.rawValue)
                    crossed = crossed || display.contains(bird.position)
                    previous=bird.position
                }
                XCTAssertTrue(crossed,profile.id.rawValue)
                XCTAssertEqual(bird.position,target,profile.id.rawValue)
                XCTAssertEqual(bird.state,.landing,profile.id.rawValue)
            }
        }
    }

    func testFirstAndLaterScheduledResidentsEnterContinuouslyOnEveryLayout() throws {
        for displays in layouts {
            for scale:CGFloat in [1,1.5] {
                for species:SpeciesID in [.treeSparrow,.greyHeron,.blackKite] {
                    let engine=fixture(displays:displays,scale:scale,species:species)
                    engine.population=Population(range:PopulationRange(lower:2,upper:2)!)
                    engine.populationEnabled=true
                    var previous:[BirdID:CGPoint]=[:],crossed=Set<BirdID>()
                    XCTAssertTrue(engine.renderSnapshot().isEmpty)
                    for _ in 0..<60*90 {
                        engine.advance(BehaviorEngine.step)
                        for snapshot in engine.renderSnapshot() {
                            let bird=try XCTUnwrap(engine.bird(snapshot.id))
                            if let old=previous[snapshot.id] {
                                XCTAssertLessThanOrEqual(Geometry.distance(old,snapshot.position),stepLimit(bird))
                            } else {
                                XCTAssertFalse(intersects(snapshot.rect,displays),"First rendered frame must be wholly offscreen")
                                let origin=try XCTUnwrap(engine.lastArrivalPosition)
                                XCTAssertLessThanOrEqual(Geometry.distance(origin,snapshot.position),stepLimit(bird))
                            }
                            if intersects(snapshot.rect,displays) {crossed.insert(snapshot.id)}
                            previous[snapshot.id]=snapshot.position
                        }
                        if crossed.count == 2 {break}
                    }
                    XCTAssertEqual(engine.arrivalCount,2)
                    XCTAssertEqual(previous.count,2)
                    XCTAssertEqual(crossed.count,2)
                }
            }
        }
    }

    func testDelayedFlockMembersRemainOutsideUntilTheirContinuousEntry() throws {
        var directions=Set<Bool>()
        for displays in layouts {
            for scale:CGFloat in [1,1.5] {
                // A fixed seed matrix covers both sampled directions; the first
                // four seeds alone all happen to select leftward flight.
                for seed:UInt64 in 0..<32 {
                    let engine=fixture(displays:displays,scale:scale,species:.treeSparrow,seed:seed)
                    XCTAssertTrue(engine.handle(.flockPass(.preview)).accepted)
                    let members=try XCTUnwrap(engine.events.last).participants
                    XCTAssertTrue((3...5).contains(members.count))
                    XCTAssertTrue(engine.renderSnapshot().isEmpty)
                    var previous:[BirdID:CGPoint]=[:],shown=Set<BirdID>(),crossed=Set<BirdID>()
                    for id in members {
                        let bird=try XCTUnwrap(engine.bird(id))
                        previous[id]=bird.position
                        XCTAssertFalse(intersects(engine.bounds(of:bird),displays))
                    }
                    for _ in 0..<60*60 {
                        engine.advance(BehaviorEngine.step)
                        let snapshots=engine.renderSnapshot()
                        for id in members {
                            guard let bird=engine.bird(id),let old=previous[id] else {continue}
                            if let snapshot=snapshots.first(where:{$0.id == id}) {
                                if shown.insert(id).inserted {
                                    XCTAssertFalse(intersects(snapshot.rect,displays),"Delayed reveal must still be offscreen")
                                }
                                if intersects(snapshot.rect,displays) {crossed.insert(id)}
                                directions.insert(snapshot.position.x > old.x)
                                let cruise=FlightBehavior.cruiseSpeed(bird.profile.id,multiplier:bird.profile.speed)
                                XCTAssertLessThanOrEqual(Geometry.distance(old,bird.position),CGFloat(cruise*1.04*BehaviorEngine.step)+1)
                            } else {
                                XCTAssertEqual(bird.position,old,"A pending member must not advance invisibly")
                            }
                            previous[id]=bird.position
                        }
                        if engine.activeRunCount == 0 {break}
                    }
                    XCTAssertEqual(shown,Set(members))
                    XCTAssertEqual(crossed,Set(members))
                    XCTAssertEqual(engine.activeRunCount,0)
                    XCTAssertTrue(engine.birds.isEmpty)
                }
            }
        }
        XCTAssertEqual(directions,Set([false,true]))
    }
}
