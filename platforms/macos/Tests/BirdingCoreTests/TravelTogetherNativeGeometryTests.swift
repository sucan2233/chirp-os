import XCTest
@testable import BirdingCore
final class TravelTogetherNativeGeometryTests:XCTestCase {
    func testTwoOrdinaryFlightsCanConvergeBeforeDistinctSlotsOnOneHost() {
        for species:SpeciesID in [.spottedDove,.blackCollaredStarling] {
          for mirrored in [false,true] {
            var settings=BirdSettings();settings.perchActions=false
            let e=BehaviorEngine(seed:813,settings:settings)
            e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
            let display=CGRect(x:0,y:0,width:1512,height:982)
            let host=Surface(id:1,pid:42,rect:CGRect(x:35,y:426,width:1442,height:100))
            let frames=Set(["stand","land0","land1","land2"]+(0...7).map{"fly\($0)"})
            e.updateWorld(BehaviorWorld(screens:[display],displays:[display],surfaces:[host],scale:0.85,
                pointer:CGPoint(x:756,y:918.5),availableFrames:[species:frames]))
            let scale=0.85*settings.catalog.profile(species).relativeScale
            let lo=Geometry.perchX(0,rect:host.rect),hi=Geometry.perchX(1,rect:host.rect)
            let birds=(0..<2).map {i -> Bird in
                func x(_ value:CGFloat) -> CGFloat {mirrored ? display.width-value:value}
                let target=CGPoint(x:x(hi-(i==0 ? 170:20)*scale),y:426)
                let bird=Bird(position:CGPoint(x:x(lo+20*scale),y:426-(i==0 ? 90:280)*scale),
                    fraction:(target.x-lo)/(hi-lo),profile:settings.catalog.profile(species),random:{0.5})
                bird.perchDuration=600;bird.fly(to:target,host:host,arc:0,allowsOrbit:false,random:{0.5});return bird
            }
            e.installFixtureBirds(birds)
            for _ in 0..<39 {e.advance(1.0/60)}
            let starts=birds.map(\.position)
            let targets=birds.compactMap{$0.airborneFlight?.destination}
            XCTAssertEqual(targets.count,2)
            XCTAssertTrue(e.handle(.travelTogether(.preview)).accepted,"\(species.rawValue), mirrored=\(mirrored)")
            XCTAssertEqual(birds.map(\.position),starts,"Handoff must not teleport either bird")
            for _ in 0..<24*60 {
                let before=birds.map(\.position)
                e.advance(1.0/60)
                for index in birds.indices {
                    XCTAssertLessThanOrEqual(Geometry.distance(before[index],birds[index].position),900.0/60+0.001,
                        "Every tick must remain within the coordinated flight speed limit")
                }
                let footprints=birds.map{Geometry.landingFootprint(at:$0.position,scale:scale)}
                let overlap=footprints[0].intersection(footprints[1])
                XCTAssertTrue(overlap.isNull || overlap.isEmpty,"Same-ledge returns must stay separate")
            }
            XCTAssertEqual(e.events.filter{$0.kind == .travelTogether && $0.type == .completed}.count,1)
            XCTAssertEqual(birds.map(\.position),targets)
            XCTAssertTrue(birds.allSatisfy{$0.state == .perched})
            XCTAssertEqual(e.reservedLandingCount,0)
          }
        }
    }
}
