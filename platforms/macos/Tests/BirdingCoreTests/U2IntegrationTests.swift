import XCTest
@testable import BirdingCore

final class U2IntegrationTests:XCTestCase {
    private var expansion:[SpeciesID] {
        SpeciesID.allCases.filter{SpeciesBehaviorProfile.profile(for:$0).isExpansionSpecies}
    }
    private var everyFrame:Set<String> {
        Set(BirdCapability.allCases.flatMap{Array($0.requiredFrames)})
            .union(["breathe","stretch","shake","poop0","poop1","cling0","cling1","peck0","peck1"])
    }

    func testNewCatalogDoesNotGrantManagedActionsEvenWithEveryFrameInjected() {
        XCTAssertEqual(SpeciesCatalog.standard.species.count,100)
        XCTAssertEqual(Set(SpeciesBehaviorProfile.legacySpecies).count,46)
        XCTAssertEqual(expansion.count,54)
        XCTAssertEqual(SpeciesCatalog.standard.profile(.greatTit).scientificName,"Parus minor")
        XCTAssertEqual(SpeciesCatalog.standard.profile(.eurasianGreatTit).scientificName,"Parus major")
        for id in expansion {
            let profile=SpeciesBehaviorProfile.profile(for:id)
            let audit=SpeciesSupportAudit(species:id,availableFrames:everyFrame)
            XCTAssertEqual(Set(audit.capabilities),[.standing,.blinking,.flight,.landing],id.rawValue)
            XCTAssertTrue(profile.poseFrameNames.isEmpty)
            XCTAssertTrue(audit.contentReview?.managedBehaviorReviewPending == true)
            for kind in BehaviorDefinitions.all.map(\.kind) {
                XCTAssertEqual(profile.allows(kind),kind == .relocate,"\(id): \(kind)")
                XCTAssertEqual(audit.behaviors.first{$0.kind==kind}?.contentSupported,kind == .relocate)
            }
            XCTAssertEqual(profile.frameFallbacks["stretch"],"stand")
            XCTAssertEqual(profile.frameFallbacks["shake"],"stand")
            XCTAssertEqual(profile.frameFallbacks["cling0"],id == .eurasianNuthatch ? nil:"stand")
        }
    }

    func testNuthatchPlansBothSidesWithStableFootFacingAndTopExit() throws {
        let host=Surface(id:51,rect:CGRect(x:300,y:200,width:700,height:500))
        for rightSide in [false,true] {
            let display=CGRect(x:rightSide ? 800:0,y:0,width:800,height:1000)
            for zoom:CGFloat in [0.75,1,2] {
                let bird=Bird(position:CGPoint(x:display.midX,y:100),fraction:0.5,
                              profile:SpeciesCatalog.standard.profile(.eurasianNuthatch),random:{0.5})
                let world=BehaviorWorld(screens:[display],displays:[display],surfaces:[host],scale:zoom)
                let rng=EngineRandom(seed:73)
                let plan=try XCTUnwrap(DestinationPlanner.plan(for:bird,birds:[bird],world:world,random:rng))
                XCTAssertEqual(plan.edge,rightSide ? .right:.left)
                XCTAssertEqual(plan.host?.id,host.id)
                XCTAssertEqual(plan.point,Geometry.foot(on:host,fraction:plan.fraction,edge:plan.edge))
                plan.apply(to:bird,random:rng)
                bird.tick(bird.flightDuration+0.01);bird.tick(0.43)
                XCTAssertEqual(bird.state,.perched)
                XCTAssertEqual(bird.position,plan.point)
                XCTAssertEqual(bird.facingRight,!rightSide)
                XCTAssertEqual(bird.frameName,"cling0")
                XCTAssertEqual(SpeciesBehavior.frame(.eurasianNuthatch,age:3.1,side:true),"peck0")
                XCTAssertEqual(SpeciesBehavior.frame(.eurasianNuthatch,age:3.4,side:true),"peck1")
                let ground=Surface(id:52,rect:CGRect(x:display.minX,y:900,width:display.width,height:100),isGround:true)
                let exitWorld=BehaviorWorld(screens:[display],displays:[display],surfaces:[ground],scale:zoom)
                let exit=try XCTUnwrap(DestinationPlanner.plan(for:bird,birds:[bird],world:exitWorld,random:rng))
                XCTAssertEqual(exit.edge,.top)
                exit.apply(to:bird,random:rng)
                bird.tick(bird.flightDuration+0.01);bird.tick(0.43)
                XCTAssertEqual(bird.edge,.top)
                XCTAssertEqual(bird.position,exit.point)
                XCTAssertFalse(bird.frameName.hasPrefix("cling"))
            }
        }
    }

    func testNonHostingWindowCannotBeChosenForEitherPerchKind() throws {
        let screen=CGRect(x:0,y:0,width:1600,height:1000)
        let host=Surface(id:61,rect:CGRect(x:300,y:300,width:800,height:400),canHostBirds:false)
        for species:SpeciesID in [.eurasianNuthatch,.greatSpottedWoodpecker,.treeSparrow] {
            let bird=Bird(position:CGPoint(x:200,y:200),fraction:0.5,profile:SpeciesCatalog.standard.profile(species),random:{0.5})
            let world=BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host])
            let plan=try XCTUnwrap(DestinationPlanner.plan(for:bird,birds:[bird],world:world,random:EngineRandom(seed:91)))
            XCTAssertNil(plan.host)
            XCTAssertEqual(plan.edge,.top)
        }
    }

    private func engine(_ species:SpeciesID) -> BehaviorEngine {
        let screen=CGRect(x:0,y:0,width:2200,height:1500)
        let host=Surface(id:71,rect:CGRect(x:100,y:900,width:2000,height:450))
        var settings=BirdSettings()
        // Keep the probe population fixed; flock spawning is independently
        // restricted to its legacy whitelist and could create unrelated birds.
        settings.flockPasses=false
        let e=BehaviorEngine(seed:73,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        e.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:[host],
            pointer:CGPoint(x:1100,y:300),availableFrames:[species:everyFrame]))
        e.installFixtureBirds([0.4,0.6].map {fraction in
            let bird=Bird(position:.zero,fraction:CGFloat(fraction),profile:SpeciesCatalog.standard.profile(species),random:{0.5})
            bird.perch(on:host);bird.perchDuration=600;bird.tick(1)
            return bird
        })
        return e
    }

    func testAllNewSpeciesRejectRealGenericRequestsAndProduceNoObservations() throws {
        for species in expansion {
            let e=engine(species)
            var observations:[BehaviorObservation]=[]
            e.observationObserver={observations.append($0)}
            let commands:[EngineCommand]=[.perchAction(.rest,.preview),.perchAction(.preen,.user),
                .attention(.watch,.preview),.attention(.alert,.user),.sideHop(.preview),.prepareTakeoff(.preview),
                .pointerVisit(.user),.socialGreeting(.preview),.leafPlay(at:CGPoint(x:1100,y:400),source:.user)]
            for command in commands {XCTAssertFalse(e.handle(command).accepted,species.rawValue)}
            for kind in SocialMotionKind.allCases {XCTAssertFalse(e.handle(.socialMotion(kind,.preview)).accepted)}
            e.ambientEnabled=true
            for _ in 0..<600 {e.advance(BehaviorEngine.step)}
            XCTAssertEqual(e.activeRunCount,0)
            XCTAssertTrue(observations.isEmpty)
            XCTAssertFalse(e.events.contains{$0.type == .started || $0.type == .completed})
            let id=try XCTUnwrap(e.id(of:e.birds[0]))
            XCTAssertTrue(e.handle(.relocate(id)).accepted,"Base relocation must remain available: \(species)")
        }
    }

    private final class Probe:BehaviorExecution {
        let kind:BehaviorKind
        let participants:[BirdID]
        let timeout=2.0
        var starts=0
        init(_ id:BirdID,_ kind:BehaviorKind) {participants=[id];self.kind=kind}
        func start(in engine:BehaviorEngine) {starts+=1}
        func advance(_ dt:Double,in engine:BehaviorEngine)->BehaviorCompletion? {.completed}
        func cancel(_ reason:BehaviorReason,in engine:BehaviorEngine) {}
    }

    func testRuntimeRejectsBypassBeforeExecutingOrLeasingNewBirds() throws {
        let e=engine(.eurasianNuthatch),id=try XCTUnwrap(e.id(of:e.birds[0]))
        let revision=e.birds[0].motionRevision
        for definition in BehaviorDefinitions.all where definition.kind != .relocate {
            let probe=Probe(id,definition.kind)
            XCTAssertEqual(e.runtime.start(probe,source:.preview,in:e),.rejected(.unavailableBird))
            XCTAssertEqual(probe.starts,0)
            XCTAssertEqual(e.activeRunCount,0)
            XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(e.birds[0].motionRevision,revision)
        }
    }
}
