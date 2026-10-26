import XCTest
@testable import BirdingCore

final class CourtshipAdmissionTests:XCTestCase {
    private typealias F=CourtshipTestSupport

    func testEveryMissingRequiredFrameRejectsWithoutSamplingAPartnerOrChangingResidents() throws {
        let required:Set<String>=["stand","courtRaise","courtBow0","courtBow1","courtBowRecover","courtObserve"]
        XCTAssertEqual(BehaviorDefinitions.definition(for:.courtshipDisplay).requiredFrames,required)
        for missing in required.sorted() {
            let e=F.engine();var world=e.world;world.availableFrames[F.species]?.remove(missing);e.updateWorld(world)
            let feet=e.birds.map(\.position),revisions=e.birds.map(\.motionRevision),count=e.birds.count
            XCTAssertEqual(e.handle(.courtshipDisplay(.preview)),.rejected(.missingFrames),missing)
            XCTAssertEqual(e.birds.map(\.position),feet);XCTAssertEqual(e.birds.map(\.motionRevision),revisions)
            XCTAssertEqual(e.birds.count,count);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.activeRunCount,0)
        }
        let e=F.engine();var world=e.world;world.availableFrames[F.species]?.remove("blink");e.updateWorld(world)
        let run=try F.start(e);F.advance(e,4.1);F.clean(e,run)
        XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
    }

    func testWrongSpeciesOneBirdDisabledProbabilityAndTransientNeverCreateACompanion() throws {
        for kinds:[SpeciesID] in [[],[.spottedDove],[.treeSparrow,.treeSparrow],[.spottedDove,.treeSparrow]] {
            let e=F.engine(residents:kinds.count,species:kinds),ids=e.birds.compactMap{e.id(of:$0)}
            XCTAssertEqual(e.handle(.courtshipDisplay(.preview)),.rejected(.noCompanion))
            XCTAssertEqual(e.birds.compactMap{e.id(of:$0)},ids);XCTAssertEqual(e.activeRunCount,0)
            XCTAssertEqual(e.arrivalCount,0);XCTAssertEqual(e.pendingCount,0)
        }
        for cause in ["probability","onlyOtherSpecies","transient"] {
            let e=F.engine(),before=e.birds.map(ObjectIdentifier.init)
            if cause=="transient" {
                let bird=e.birds[1];e.removeRecord(try XCTUnwrap(e.id(of:bird)));e.register(bird,role:.transient)
            } else {
                var settings=e.settings
                if cause=="onlyOtherSpecies" {
                    let index=try XCTUnwrap(settings.probabilities.entries.firstIndex{$0.id == .treeSparrow})
                    for entry in settings.probabilities.entries { settings.probabilities.setWeight(0, for: entry.id) }; settings.probabilities.setManualWeight(at:index,to:1)
                } else {
                    let index=try XCTUnwrap(settings.probabilities.entries.firstIndex{$0.id==F.species})
                    settings.probabilities.setManualWeight(at:index,to:0)
                }
                e.applySettings(settings)
            }
            XCTAssertEqual(e.handle(.courtshipDisplay(.preview)),.rejected(cause=="transient" ? .noCompanion:.noSpecies),cause)
            XCTAssertEqual(e.birds.map(ObjectIdentifier.init),before);XCTAssertEqual(e.activeRunCount,0)
        }
    }

    func testBothResidentsNeedTenRealQuietSecondsEvenForPreviewAndOrdinaryTopOrGround() throws {
        for source:BehaviorSource in [.preview,.automatic] {
            let young=F.engine(quiet:9.8)
            young.ambientEnabled=source == .automatic
            XCTAssertEqual(young.handle(.courtshipDisplay(source)),.rejected(.noSpace))
            F.advance(young,0.4)
            for bird in young.birds {XCTAssertGreaterThanOrEqual(try XCTUnwrap(young.ecology(of:bird)).quietTime,10)}
            let run=try F.start(young,source:source);F.advance(young,4.1);F.clean(young,run)
            XCTAssertEqual(F.terminals(young,run).map(\.type),[.completed])
        }
        for ground in [false,true] {
            let e=F.engine(ground:ground),feet=e.birds.map(\.position),run=try F.start(e)
            F.advance(e,4.1);F.clean(e,run);XCTAssertEqual(e.birds.map(\.position),feet)
        }
        for cause in ["side","otherHost","fixed","moving","disturbed"] {
            let e=F.engine(),bird=e.birds[1];var world=e.world
            switch cause {
            case "side":bird.edge = .left
            case "otherHost":
                let host=Surface(id:2702,pid:42,rect:world.surfaces[0].rect);world.surfaces.append(host)
                bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.tick(10.1)
            case "fixed":
                let host=Surface(id:2702,pid:42,rect:world.surfaces[0].rect,isFixedPerch:true)
                world.surfaces=[host];for bird in e.birds {bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.tick(10.1)}
            case "moving":bird.position.x+=1
            default:e.perchPlanner.noteClick(try XCTUnwrap(e.id(of:bird)))
            }
            e.updateWorld(world)
            XCTAssertFalse(e.handle(.courtshipDisplay(.preview)).accepted,cause)
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
        }
    }

    func testTurningFootprintsNeedTwelveDesktopPointsAtEveryScale() throws {
        for scale:CGFloat in [0.5,1,2] {
            let size=scale*SpeciesCatalog.standard.profile(.spottedDove).relativeScale
            for extra:CGFloat in [-0.02,0.02] {
                let e=F.engine(scale:scale,gap:58*size+12+extra)
                let areas=e.birds.map{Geometry.landingFootprint(at:$0.position,scale:e.spriteScale(for:$0))}
                XCTAssertEqual(areas[1].minX-areas[0].maxX,12+extra,accuracy:1e-9)
                let result=e.handle(.courtshipDisplay(.preview))
                if extra<0 {XCTAssertEqual(result,.rejected(.noSpace))}
                else {
                    guard case .started(let run)=result else {XCTFail("A full turning gap above 12 must fit: \(result)");continue}
                    F.advance(e,4.1);F.clean(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
                }
            }
        }
    }

    func testActualGroundAtTheDockBoundaryFitsDisplayEvenWhenTailExtendsBelowWorkAreaAtThreeScales() throws {
        for scale:CGFloat in [0.5,1,2] {for negative in [false,true] {
            let e=F.engine(scale:scale,negative:negative,quiet:0)
            let display=e.world.displays[0]
            let work=CGRect(x:display.minX,y:display.minY+24*scale,
                width:display.width,height:display.height-124*scale)
            let ground=Geometry.ground(id:2797,display:display,workArea:work)
            var world=e.world;world.screens=[work];world.surfaces=[ground];e.updateWorld(world)
            for bird in e.birds {bird.perch(on:ground,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600}
            F.advance(e,10.1)
            let feet=e.birds.map(\.position)
            for bird in e.birds {
                let full=Geometry.landingFootprint(at:bird.position,scale:e.spriteScale(for:bird))
                XCTAssertTrue(display.contains(full));XCTAssertFalse(work.contains(full))
                XCTAssertGreaterThan(full.maxY,work.maxY);XCTAssertEqual(bird.hostID,ground.id)
            }
            let run=try F.start(e);F.advance(e,4.1);F.clean(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            XCTAssertEqual(e.birds.map(\.position),feet);XCTAssertTrue(e.birds.allSatisfy{$0.state == .perched})
        }}
    }

    func testMouseProtectsBothCompleteTurningBodiesByEightyLogicalPoints() throws {
        for scale:CGFloat in [0.5,1,2] {for participant in 0..<2 {for active in [false,true] {
            let e=F.engine(scale:scale)
            let run:BehaviorRunID?=active ? try F.start(e):nil
            let bird=e.birds[participant],area=Geometry.landingFootprint(at:bird.position,scale:e.spriteScale(for:bird))
            var world=e.world;world.pointer=CGPoint(x:area.midX,y:area.minY-80*scale+0.01);e.updateWorld(world)
            if let run {
                F.clean(e,run);XCTAssertEqual(F.terminals(e,run).first?.reason,.pointerNearby)
            } else {XCTAssertEqual(e.handle(.courtshipDisplay(.preview)),.rejected(.noSpace))}
        }}}
    }

    func testLegacyFoodTrayFixedPerchAndRealAuthorizedGiftAreBusyInBothDirections() throws {
        for fixed in [false,true] {for legacyFirst in [false,true] {
            let e=F.engine()
            // Each branch needs only its own object. A tray at (1800,700)
            // overlaps the headroom-protected branch at (1800,550).
            var s=e.settings;s.fixedPerches=fixed ? [FixedPerchAnchor(slot:1,displayID:"court-display",
                displayFrame:e.world.displays[0],x:0.75,y:0.25)]:[];e.applySettings(s)
            let support=Surface(id:2799,pid:42,rect:CGRect(x:200,y:1100,width:600,height:150))
            var world=e.world;world.surfaces.append(support)
            world.availableFrames[.treeSparrow]=F.frames.union(["feedLook","feedDown0","feedDown1","feedLift"])
            e.updateWorld(world)
            let bird=Bird(position:.zero,fraction:0.35,profile:s.catalog.profile(.treeSparrow),random:{0.5})
            bird.perch(on:support,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600;e.register(bird)
            F.advance(e,10.1)
            if !fixed {XCTAssertEqual(e.handle(.placeFoodTray(at:CGPoint(x:1800,y:700))),.accepted)}
            let legacy:EngineCommand=fixed ? .fixedPerchVisit(.preview):.foodTrayVisit(.preview)
            if legacyFirst {
                let result=e.handle(legacy)
                guard case .started(let old)=result else {XCTFail("Real legacy run must start: \(result)");continue}
                XCTAssertEqual(e.handle(.courtshipDisplay(.preview)),.rejected(.busy))
                XCTAssertEqual(e.runtime.runs[old]?.execution.kind,fixed ? .fixedPerchVisit:.foodTrayVisit)
                XCTAssertNotNil(e.runtime.runs[old]);XCTAssertEqual(e.activeRunCount,1)
                e.handle(.cancelAmbient(.shutdown))
            } else {
                let run=try F.start(e)
                XCTAssertEqual(e.handle(legacy),.rejected(.busy));XCTAssertNotNil(e.runtime.runs[run])
                e.handle(.cancelAmbient(.shutdown));F.clean(e,run)
            }
        }}
        for giftFirst in [false,true] {
            let e=try VisitorGiftTestSupport.prepared()
            // The gift-only helper disables social interactions. This combined
            // admission scenario must independently enable both behaviors.
            var settings=e.settings;settings.socialInteractions=true;settings.courtshipEnabled=true
            e.applySettings(settings)
            let support=Surface(id:2798,pid:42,rect:CGRect(x:200,y:2000,width:2000,height:100))
            var world=e.world;world.surfaces.append(support);world.availableFrames[.spottedDove]=F.frames;e.updateWorld(world)
            for fraction:CGFloat in [0.3,0.5] {
                let bird=Bird(position:.zero,fraction:fraction,profile:e.settings.catalog.profile(.spottedDove),random:{0.5})
                bird.perch(on:support,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600;e.register(bird)
            }
            F.advance(e,16)
            if giftFirst {
                let (gift,_)=try VisitorGiftTestSupport.authorize(e)
                XCTAssertEqual(e.handle(.courtshipDisplay(.preview)),.rejected(.busy))
                XCTAssertNotNil(e.runtime.runs[gift]);XCTAssertEqual(e.activeGiftAuthorizationCount,1)
                e.handle(.cancelAmbient(.shutdown));VisitorGiftTestSupport.released(e,gift)
            } else {
                let objects=e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init)
                let leaf=try XCTUnwrap(objects.first)
                XCTAssertEqual(objects.count,1);XCTAssertEqual(leaf.state,"available")
                let run=try F.start(e),started=e.time
                XCTAssertEqual(e.handle(.visitorGift(.preview)),.rejected(.busy))
                XCTAssertEqual(e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init),objects)
                XCTAssertNil(e.giftAuthorizationRequest);XCTAssertEqual(e.activeGiftAuthorizationCount,0)
                F.advance(e,4.1)
                XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed]);XCTAssertEqual(e.activeRunCount,0)
                let remaining=e.carriedObjectSnapshot().map(RecordedCarriedObjectState.init)
                XCTAssertEqual(remaining.count,1)
                var preserved=try XCTUnwrap(remaining.first)
                XCTAssertEqual(preserved.remainingLifetime,leaf.remainingLifetime-(e.time-started),accuracy:1e-9)
                preserved.remainingLifetime=leaf.remainingLifetime
                XCTAssertEqual(preserved,leaf,"Courtship and the rejected gift must preserve the ordinary available leaf")
                XCTAssertEqual(e.propSnapshot().map{String($0.id.rawValue)},[leaf.id])
                XCTAssertTrue(e.runtime.propIDs.isEmpty)
                // This user's available leaf predates the run and must survive
                // it. Remove the fixture input before the empty-scene check.
                XCTAssertEqual(e.handle(.removeCarryLeaf),.accepted)
                XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.retired)
                F.advance(e,0.25) // User removal keeps the existing 0.2s visual fade.
                F.clean(e,run)
            }
        }
    }

    func testThinOccluderOrThirdResidentInsideTheReservedTurningSpanRejectsOrInvalidatesTheWholePair() throws {
        for active in [false,true] {for cause in ["panel","body"] {
            let e=F.engine(),run:BehaviorRunID?=active ? try F.start(e):nil
            let center=(e.birds[0].position.x+e.birds[1].position.x)/2,host=e.world.surfaces[0]
            if cause=="panel" {
                let y=e.birds[0].position.y-20
                var world=e.world;world.surfaces.insert(Surface(id:2796,pid:77,
                    rect:CGRect(x:center,y:y,width:0.01,height:1),layer:1),at:0)
                e.updateWorld(world)
            } else {
                let bird=Bird(position:.zero,fraction:(center-Geometry.perchX(0,rect:host.rect))/(host.rect.width-84),
                    profile:e.settings.catalog.profile(.yellowBrowedWarbler),random:{0.5})
                bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
                e.register(bird);e.updateWorld(e.world)
            }
            if let run {F.clean(e,run);XCTAssertEqual(F.terminals(e,run).map(\.type),[.failed])}
            else {XCTAssertEqual(e.handle(.courtshipDisplay(.preview)),.rejected(.noSpace))}
        }}
    }
}
