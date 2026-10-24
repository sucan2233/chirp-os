import XCTest
@testable import BirdingCore

final class SocialMotionSchedulingTests:XCTestCase {
    private func fixture(seed:UInt64) -> BehaviorEngine {
        var settings=BirdSettings();settings.ambientLeafPlayEnabled=false;settings.pointerVisits=false;settings.flockPasses=false
        settings.perchActions=false;settings.ambientFrequency = .high
        let e=BehaviorEngine(seed:seed,settings:settings);e.populationEnabled=false;e.autonomousRouting=false
        let screen=CGRect(x:-1200,y:-400,width:3000,height:1800)
        let host=Surface(id:71,rect:CGRect(x:-900,y:800,width:2300,height:400))
        let frames=SocialMotionPlan.requiredFrames.union(SocialGreetingPlan.requiredFrames)
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],pointer:CGPoint(x:1200,y:0),availableFrames:[.treeSparrow:frames]))
        e.installFixtureBirds([CGFloat(0.3),0.42].map {f in
            let b=Bird(position:.zero,fraction:f,profile:settings.catalog.profile(.treeSparrow),random:{0.5})
            b.perch(on:host,spriteScale:b.profile.relativeScale);b.perchDuration=600;return b
        })
        return e
    }
    func testAutomaticSocialSelectionCanStartNewClipsOnTheExistingOpportunity() {
        var seen=Set<BehaviorKind>()
        // Fixed seeds whose independent scene stream admits the first daily
        // opportunity. Empty draws are covered by SceneSchedulingTests; keep
        // these 32 samples focused on the existing social selection branches.
        let seeds:[UInt64]=[0,1,2,3,4,6,7,8,9,10,11,12,13,14,15,17,
            19,20,21,22,23,24,25,26,27,28,29,31,32,33,35,36]
        for seed in seeds {
            let e=fixture(seed:seed)
            for _ in 0..<44*60 {e.advance(BehaviorEngine.step)}
            XCTAssertFalse(e.events.contains{$0.type == .started})
            for _ in 0..<2*60 {e.advance(BehaviorEngine.step)}
            let starts=e.events.filter{$0.type == .started}
            XCTAssertEqual(starts.count,1);XCTAssertEqual(starts.first?.source,.automatic)
            if let kind=starts.first?.kind {seen.insert(kind)}
            XCTAssertEqual(e.residentCount,2);XCTAssertEqual(e.leasedBirdCount,2)
        }
        XCTAssertTrue(seen.contains(.sideBySide));XCTAssertTrue(seen.contains(.giveWay));XCTAssertTrue(seen.contains(.pairedTakeoff))
    }
    func testAddingClipsDoesNotMultiplyFrequencyOrQueueWhilePaused() {
        let e=fixture(seed:4)
        for _ in 0..<190*60 {e.advance(BehaviorEngine.step)}
        let starts=e.events.filter{$0.type == .started}
        XCTAssertGreaterThanOrEqual(starts.count,2);XCTAssertLessThanOrEqual(starts.count,4)
        for pair in zip(starts,starts.dropFirst()) {XCTAssertGreaterThanOrEqual(pair.1.time-pair.0.time,45-BehaviorEngine.step)}
        e.handle(.pause(true));let count=starts.count
        for _ in 0..<200*60 {e.advance(BehaviorEngine.step)}
        XCTAssertEqual(e.events.filter{$0.type == .started}.count,count)
        e.handle(.pause(false));for _ in 0..<5*60 {e.advance(BehaviorEngine.step)}
        XCTAssertEqual(e.events.filter{$0.type == .started}.count,count)
        var settings=e.settings;settings.socialInteractions=false;e.applySettings(settings)
        for _ in 0..<200*60 {e.advance(BehaviorEngine.step)}
        XCTAssertEqual(e.events.filter{$0.type == .started}.count,count)
        XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.leasedBirdCount,0)
    }
}
