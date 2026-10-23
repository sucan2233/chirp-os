import XCTest
@testable import BirdingCore

final class SocialSchedulingTests: XCTestCase {
    func testAutomaticGreetingUsesTheSharedSchedulerAndPauseDoesNotAccumulateAttempts() {
        var settings=BirdSettings()
        settings.pointerVisits=false;settings.flockPasses=false;settings.perchActions=false
        settings.socialInteractions=true;settings.ambientFrequency = .high
        let engine=BehaviorEngine(seed:73,settings:settings)
        engine.populationEnabled=false;engine.autonomousRouting=false
        let screen=CGRect(x:-1000,y:-300,width:1800,height:1200)
        let host=Surface(id:31,rect:CGRect(x:-600,y:400,width:500,height:160))
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],
            pointer:CGPoint(x:0,y:0),availableFrames:[.treeSparrow:SocialGreetingPlan.requiredFrames]))
        engine.installFixtureBirds([CGFloat(0.3),0.7].map {fraction in
            let bird=Bird(position:.zero,fraction:fraction,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
            bird.perch(on:host);bird.perchDuration=600;return bird
        })
        func advance(_ seconds:Int) {for _ in 0..<seconds*60 {engine.advance(BehaviorEngine.step)}}
        advance(44)
        XCTAssertFalse(engine.events.contains{$0.kind == .socialGreeting})
        engine.handle(.pause(true));advance(200)
        XCTAssertFalse(engine.events.contains{$0.kind == .socialGreeting})
        engine.handle(.pause(false));advance(59)
        XCTAssertFalse(engine.events.contains{$0.kind == .socialGreeting})
        advance(2)
        let starts=engine.events.filter{$0.kind == .socialGreeting && $0.type == .started}
        XCTAssertEqual(starts.count,1)
        XCTAssertEqual(starts.first?.source,.automatic)
        XCTAssertEqual(starts.first?.participants.count,2)
        XCTAssertEqual(engine.activeRunCount,1)
        advance(5)
        XCTAssertEqual(engine.events.filter{$0.kind == .socialGreeting && $0.type == .completed}.count,1)
        XCTAssertEqual(engine.leasedBirdCount,0)
        XCTAssertEqual(engine.residentCount,2)
    }

    func testThreeEncountersShareOneOpportunityRatherThanAddingAnotherClock() {
        for selection in [0.0,0.4,0.9] {
            var scheduler=AmbientScheduler();scheduler.reset(.high)
            var events:[AmbientEvent]=[]
            for _ in 0..<46*60 {
                if let event=scheduler.tick(1.0/60,pointer:.zero,buttonsDown:false,
                    pointerEnabled:true,flockEnabled:true,socialEnabled:true,
                    frequency:.high,busy:false,random:{selection}) {events.append(event)}
            }
            XCTAssertEqual(events,[selection==0 ? .pointerVisit:selection<0.5 ? .flockPass:.socialGreeting])
        }
    }

    func testSocialOnlyModeAndBusyOpportunitiesHaveNoBacklog() {
        var scheduler=AmbientScheduler();scheduler.reset(.high)
        func advance(_ seconds:Int,enabled:Bool=true,busy:Bool=false) -> [AmbientEvent] {
            var events:[AmbientEvent]=[]
            for _ in 0..<seconds*60 {
                if let event=scheduler.tick(1.0/60,pointer:.zero,buttonsDown:false,
                    pointerEnabled:false,flockEnabled:false,socialEnabled:enabled,
                    frequency:.high,busy:busy,random:{0}) {events.append(event)}
            }
            return events
        }
        XCTAssertEqual(advance(46),[.socialGreeting])
        XCTAssertTrue(advance(45,busy:true).isEmpty)
        XCTAssertTrue(advance(10).isEmpty)
        XCTAssertTrue(advance(40,enabled:false).isEmpty)
        XCTAssertTrue(advance(10).isEmpty)
    }
}
