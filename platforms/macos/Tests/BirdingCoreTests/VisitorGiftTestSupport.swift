import XCTest
@testable import BirdingCore

enum VisitorGiftTestSupport {
    static let species:SpeciesID = .azureWingedMagpie
    static let frames:Set<String>=Set(["stand","blink","land0","land1","land2",
        "carryLook","carryLower","carryGrip","carryPlace"]+(0..<8).map{"fly\($0)"})
    static let tokenID=UUID(uuidString:"00000000-0000-4000-8000-000000000073")!
    static func display(_ scale:CGFloat=1)->CGRect {CGRect(x:0,y:0,width:2400*scale,height:2200*scale)}
    static func host(_ scale:CGFloat=1)->Surface {
        Surface(id:1971,pid:42,rect:CGRect(x:200*scale,y:1700*scale,width:2000*scale,height:180*scale))
    }
    static func leafPoint(_ scale:CGFloat=1)->CGPoint {CGPoint(x:1000*scale,y:1700*scale)}
    static func settings(scale:CGFloat=1,right:Bool=true)->BirdSettings {
        var value=BirdSettings();value.visitorGiftsEnabled=true
        value.perchActions=false;value.passiveAttentionEnabled=false;value.ambientLeafPlayEnabled=false
        value.pointerVisits=false;value.flockPasses=false;value.socialInteractions=false
        value.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"gift-display",displayFrame:display(scale),
            x:right ? 0.75:0.25,y:0.5)]
        return value
    }
    static func memory(previousVisits:Int=2,calmSeconds:Double=180) throws -> VisitorMemoryArchive {
        // The real acquire path adds this visit. Archive namespace intentionally
        // differs from the profile's temperament seed.
        let raw:[String:Any]=["version":1,"seed":"73","nextID":"100","visitOrdinal":"100",
            "profiles":[["id":"99","species":species.rawValue,"seed":"9001",
                "calmSeconds":calmSeconds,"visits":previousVisits,"lastVisitOrdinal":"100"]]]
        return try VisitorMemoryArchive.decode(JSONSerialization.data(withJSONObject:raw))
    }
    static func engine(scale:CGFloat=1,right:Bool=true,previousVisits:Int=2,calmSeconds:Double=180,
                       residents:Int=2,seed:UInt64=1971,offset:CGPoint = .zero,
                       ordinaryCarryFirst:Bool=false) throws -> BehaviorEngine {
        var settings=settings(scale:scale,right:right)
        let screen=display(scale).offsetBy(dx:offset.x,dy:offset.y),original=host(scale)
        let host=Surface(id:original.id,pid:original.pid,rect:original.rect.offsetBy(dx:offset.x,dy:offset.y))
        settings.fixedPerches=settings.fixedPerches.map{FixedPerchAnchor(slot:$0.slot,displayID:$0.displayID,
            displayFrame:screen,x:$0.x,y:$0.y)}
        let e=BehaviorEngine(seed:seed,settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        try e.restoreVisitorMemory(memory(previousVisits:previousVisits,calmSeconds:calmSeconds))
        var surfaces=[host],birds:[Bird]=[]
        // For an initial ordinary carry, keep its approach between the magpie
        // and the leaf rather than routing the sparrow through the larger bird.
        let sparrowFraction:CGFloat=ordinaryCarryFirst ? (right ? 0.30:0.70):(right ? 0.02:0.98)
        let foreground:[(SpeciesID,CGFloat)]=[(species,right ? 0.15:0.85),(.treeSparrow,sparrowFraction)]
        for (kind,fraction) in foreground {
            let bird=Bird(position:.zero,fraction:fraction,profile:settings.catalog.profile(kind),random:{0.5})
            bird.perch(on:host,spriteScale:scale*bird.profile.relativeScale);bird.perchDuration=3600
            birds.append(bird)
        }
        if residents>2 {
            for row in 0..<Int(ceil(Double(residents-2)/8)) {
                let support=Surface(id:UInt32(2000+row),pid:43,
                    rect:CGRect(x:100*scale+offset.x,y:CGFloat(120+row*90)*scale+offset.y,width:2200*scale,height:40*scale))
                surfaces.append(support)
                for column in 0..<min(8,residents-2-row*8) {
                    let bird=Bird(position:.zero,fraction:CGFloat(column+1)/9,
                        profile:settings.catalog.profile(.yellowBrowedWarbler),random:{0.5})
                    bird.perch(on:support,spriteScale:scale*bird.profile.relativeScale);bird.perchDuration=3600
                    birds.append(bird)
                }
            }
        }
        e.updateWorld(.init(screens:[screen],displays:[screen],surfaces:surfaces,
            scale:scale,pointer:CGPoint(x:20*scale+offset.x,y:20*scale+offset.y),
            availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)}),displayIDs:["gift-display"]))
        // A prospective ordinary carrier must be settled: the sparrow's
        // periodic hop spans ages 1...2; the magpie is at rest at 1.1.
        // Tick before registration so setup cannot increase familiarity.
        for bird in birds {bird.tick(ordinaryCarryFirst && bird.profile.id == .treeSparrow ? 2.1:1.1)}
        e.installFixtureBirds(birds)
        return e
    }
    static func prepared(scale:CGFloat=1,right:Bool=true,residents:Int=2,seed:UInt64=1971,
                         ordinaryCarryFirst:Bool=false) throws -> BehaviorEngine {
        let e=try engine(scale:scale,right:right,residents:residents,seed:seed,ordinaryCarryFirst:ordinaryCarryFirst)
        XCTAssertTrue(e.handle(.placeCarryLeaf(at:leafPoint(scale))).accepted)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.facingRight,right)
        return e
    }
    static func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    static func authorize(_ e:BehaviorEngine,source:BehaviorSource = .preview,
                          tokenID:UUID=VisitorGiftTestSupport.tokenID) throws -> (BehaviorRunID,VisitorGiftExecution) {
        XCTAssertEqual(e.handle(.visitorGift(source)),.scheduled)
        let request=try XCTUnwrap(e.giftAuthorizationRequest)
        e.receiveGiftAuthorization(.init(granted:.init(id:tokenID,binding:request.binding)))
        let run=try XCTUnwrap(e.runtime.runs.values.first{$0.execution.kind == .visitorGift})
        return (run.id,try XCTUnwrap(run.execution as? VisitorGiftExecution))
    }
    static func reach(_ phase:VisitorGiftExecution.Phase,_ e:BehaviorEngine,_ run:BehaviorRunID) throws {
        for _ in 0..<35*60 {
            let active=try XCTUnwrap(e.runtime.runs[run]?.execution as? VisitorGiftExecution)
            if active.phase==phase {return}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Real gift did not reach \(phase)");throw NSError(domain:"VisitorGiftTests",code:1)
    }
    static func finish(_ e:BehaviorEngine,_ run:BehaviorRunID,hz:Int=60) {
        for _ in 0..<36*hz {if e.runtime.runs[run]==nil {return};e.advance(1/Double(hz))}
        XCTFail("Gift did not terminate within 35 seconds")
    }
    static func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID)->[BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}
    }
    static func token(_ e:BehaviorEngine)->ScenePropRenderState? {e.propSnapshot().first{$0.kind == .leafToken}}
    static func released(_ e:BehaviorEngine,_ run:BehaviorRunID,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(terminals(e,run).count,1,file:file,line:line)
        XCTAssertNil(e.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(e.activeGiftAuthorizationCount,0,file:file,line:line)
        XCTAssertNil(e.giftAuthorizationRequest,file:file,line:line)
        XCTAssertEqual(e.runtime.giftReceiverReservations.count,0,file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertFalse(e.ambientBusy,file:file,line:line)
        XCTAssertNil(e.sceneFocus,file:file,line:line)
    }
}
