import XCTest
@testable import BirdingCore

final class LivelyMotionTests:XCTestCase {
    private let host=Surface(id:301,pid:31,rect:CGRect(x:200,y:600,width:1400,height:600))
    private func fixture(_ species:SpeciesID,side:Bool?=nil,frames:Bool=true) -> BehaviorEngine {
        var settings=BirdSettings()
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        settings.ambientLeafPlayEnabled=false;settings.edgePeekEnabled=false;settings.sideHopEnabled=false
        settings.passiveAttentionEnabled=false
        let engine=BehaviorEngine(seed:73,settings:settings)
        engine.populationEnabled=false;engine.ambientEnabled=false;engine.autonomousRouting=false
        let screen=CGRect(x:0,y:0,width:2200,height:1600)
        let base:Set<String>=["stand","breathe","blink","idle0","idle1","idle2","preen0","preen1","cling0","peck0","peck1"]
        engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],scale:1,
            pointer:CGPoint(x:10,y:10),availableFrames:[species:frames ? base.union(LivelyMotion.frameNames(for:species)).union(PoseClip.frameNames):base]))
        let bird=Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(species),random:{0.5})
        if side ?? LivelyMotion.isSideMotion(species) {bird.edge = .left}
        bird.perch(on:host,spriteScale:engine.spriteScale(for:bird));bird.perchDuration=600
        engine.installFixtureBirds([bird]);return engine
    }
    private func advance(_ engine:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {engine.advance(1/Double(hz))}
    }
    private func isSignature(_ engine:BehaviorEngine) -> Bool {
        guard let row=engine.renderSnapshot().first else {return false}
        return LivelyMotion.frameNames(for:row.species).contains(row.frameName)
    }
    func testHundredClipsHaveBoundedTwoVariantSequencesAndStableIndividualChoice() throws {
        XCTAssertEqual(LivelyMotion.species.count,100)
        XCTAssertEqual(Set(LivelyMotion.species).count,100)
        XCTAssertEqual(Set((1...32).map{LivelyMotion.variant(seed:73,bird:BirdID(UInt64($0)))}),[0,1])
        for species in LivelyMotion.species {
            let a=try XCTUnwrap(LivelyMotion.clip(species:species)),b=try XCTUnwrap(LivelyMotion.clip(species:species,variant:1))
            XCTAssertEqual(a.frames.count,4);XCTAssertEqual(a.maximumLoops,1)
            XCTAssertEqual(a.duration,LivelyMotion.window(species).duration,accuracy:1e-9)
            XCTAssertEqual(a.frames.map(\.name),b.frames.map(\.name))
            XCTAssertNotEqual(a.frames.map(\.duration),b.frames.map(\.duration))
            XCTAssertNil(a.sample(at:a.duration));XCTAssertNil(a.sample(at:-1))
            XCTAssertNil(LivelyMotion.previewFrame(species:species,age:.infinity))
        }
        XCTAssertEqual(Set(LivelyMotion.species),Set(SpeciesID.allCases))
    }
    func testDesktopPlaybackVisitsAllFourFramesAtAllCallbackRatesWithoutObservations() {
        for species in LivelyMotion.species {
            var references:[[String]]=[]
            for hz in [30,60,120] {
                let engine=fixture(species),initialEvents=engine.events.count
                var observations:[BehaviorObservation]=[];engine.observationObserver={observations.append($0)}
                var samples:[String]=[]
                for _ in 0..<Int((LivelyMotion.window(species).start+LivelyMotion.window(species).duration+0.5)*30) {
                    advance(engine,1.0/30,hz:hz)
                    let snapshot=engine.renderSnapshot()[0];samples.append(snapshot.frameName)
                    if isSignature(engine) {XCTAssertEqual(snapshot.hopOffset,0)}
                }
                XCTAssertTrue(Set(LivelyMotion.frameNames(for:species)).isSubset(of:Set(samples)),"\(species) \(hz)")
                XCTAssertEqual(engine.events.count,initialEvents);XCTAssertTrue(observations.isEmpty)
                references.append(samples)
            }
            XCTAssertEqual(references[0],references[1]);XCTAssertEqual(references[1],references[2])
        }
    }
    func testPauseFreezesThenResumesAndRepeatedRenderingDoesNotAdvance() {
        let engine=fixture(.greatTit);advance(engine,2.3)
        XCTAssertTrue(isSignature(engine));let frame=engine.renderSnapshot()[0].frameName
        _=engine.handle(.pause(true));advance(engine,3)
        for _ in 0..<20 {XCTAssertEqual(engine.renderSnapshot()[0].frameName,frame)}
        _=engine.handle(.pause(false));advance(engine,0.7)
        XCTAssertNotEqual(engine.renderSnapshot()[0].frameName,frame)
    }
    func testInputMissingFrameAndQuietCancelWholeOpportunityEvenWhilePaused() {
        for reason in 0..<3 {
            let engine=fixture(.greatTit);advance(engine,2.3);XCTAssertTrue(isSignature(engine))
            _=engine.handle(.pause(true))
            let originalWorld=engine.world,originalSettings=engine.settings
            if reason==0 {var world=engine.world;world.pointer=engine.birds[0].position;engine.updateWorld(world)}
            if reason==1 {var world=engine.world;world.availableFrames[.greatTit]?.remove("inspectDown");engine.updateWorld(world)}
            if reason==2 {var settings=engine.settings;settings.activityRhythm = .quiet;engine.applySettings(settings)}
            XCTAssertFalse(isSignature(engine))
            engine.updateWorld(originalWorld);engine.applySettings(originalSettings)
            XCTAssertFalse(isSignature(engine));_=engine.handle(.pause(false));advance(engine,1)
            XCTAssertFalse(isSignature(engine));advance(engine,7.5)
            XCTAssertTrue(isSignature(engine),"next opportunity: \(reason)")
        }
    }
    func testManagedRestOwnsPoseAndPreemptionDoesNotResumeOldSignature() {
        let engine=fixture(.greatTit);advance(engine,2.3);XCTAssertTrue(isSignature(engine))
        XCTAssertTrue(engine.handle(.perchAction(.rest,.preview)).accepted)
        XCTAssertEqual(engine.renderSnapshot()[0].hopOffset,0,accuracy:1e-9)
        advance(engine,0.1);XCTAssertEqual(engine.renderSnapshot()[0].frameName,"restLower")
        XCTAssertEqual(engine.renderSnapshot()[0].hopOffset,0,accuracy:1e-9)
        engine.runtime.cancel(where:{$0.kind == .rest},reason:.replaced,in:engine)
        XCTAssertFalse(isSignature(engine));advance(engine,0.5);XCTAssertFalse(isSignature(engine))
    }
    func testSideAndTopClipsCannotCrossPerchGeometryAndPartialPacksNeverStart() {
        for species in LivelyMotion.species {
            let wrong=fixture(species,side:!LivelyMotion.isSideMotion(species))
            let missing=fixture(species,frames:false)
            for engine in [wrong,missing] {
                for _ in 0..<Int((LivelyMotion.window(species).start+LivelyMotion.window(species).duration+0.5)*30) {engine.advance(1.0/30);XCTAssertFalse(isSignature(engine))}
            }
        }
    }
    func testMotionRevisionAndRemovalDiscardPreviousSlot() {
        let engine=fixture(.greatTit);advance(engine,2.3);XCTAssertTrue(isSignature(engine))
        let bird=engine.birds[0]
        bird.perch(on:host,spriteScale:engine.spriteScale(for:bird));bird.perchDuration=600
        XCTAssertFalse(isSignature(engine));advance(engine,2.3);XCTAssertTrue(isSignature(engine))
        engine.installFixtureBirds([]);XCTAssertTrue(engine.renderSnapshot().isEmpty)
    }
    func testExplicitClickAndLifecycleCommandsCancelWithoutDependingOnWorldUpdate() {
        let commands:[EngineCommand] = [.pointerClick,.cancelAmbient(.sleep),.cancelAmbient(.screensChanged),
                                       .cancelAmbient(.spaceChanged),.cancelAmbient(.shutdown)]
        for command in commands {
            let engine=fixture(.greatTit);advance(engine,2.3);XCTAssertTrue(isSignature(engine))
            _=engine.handle(command);XCTAssertFalse(isSignature(engine))
            advance(engine,0.5);XCTAssertFalse(isSignature(engine))
        }
    }
    func testClickJustBeforeIdleWindowRespectsExistingCooldown() throws {
        let engine=fixture(.greatTit);advance(engine,1.8)
        var world=engine.world;world.pointer=engine.birds[0].position;engine.updateWorld(world)
        _=engine.handle(.pointerClick)
        world.pointer=CGPoint(x:10,y:10);engine.updateWorld(world)
        let id=try XCTUnwrap(engine.id(of:engine.birds[0]))
        XCTAssertGreaterThan(engine.perchPlanner.rhythms[id]?.cooldowns[.watch] ?? 0,0)
        for _ in 0..<150 {engine.advance(1.0/60);XCTAssertFalse(isSignature(engine))}
    }
}
