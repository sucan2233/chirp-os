import XCTest
@testable import BirdingCore

/// Bounded core lifecycle workloads. Keep the legacy BehaviorStress workload
/// and its performance baseline independent of these authored carry scenarios.
final class LeafCarryStressTests:XCTestCase {
    private typealias F=LeafCarryTestSupport
    private let display=CGRect(x:0,y:0,width:2400,height:2000)
    private let carrierHost=Surface(id:1200,pid:42,rect:CGRect(x:200,y:1650,width:2000,height:180))

    func testTwentyFourResidentsCompleteRepeatedCarriesAcrossPauseCancellationAndExpiry() throws {
        try exercise(residents:24)
    }

    func testSixtyFourResidentsCompleteRepeatedCarriesAcrossPauseCancellationAndExpiry() throws {
        try exercise(residents:64)
    }

    private func exercise(residents:Int)throws {
        var settings=BirdSettings()
        settings.perchActions=false;settings.passiveAttentionEnabled=false
        settings.sideHopEnabled=false;settings.edgePeekEnabled=false
        settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
        settings.ambientLeafPlayEnabled=false
        let e=BehaviorEngine(seed:UInt64(1200+residents),settings:settings)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let backgroundSpecies:[SpeciesID]=[.redWhiskeredBulbul,.lightVentedBulbul,.chineseBlackbird,
            .magpieRobin,.swinhoesWhiteEye,.redBilledLeiothrix]
        let common:Set<String>=Set(["stand","blink","breathe","preen0","preen1","idle0","idle1","idle2"])
            .union(TransportArtGeometry.frameNames)
        var frames=Dictionary(uniqueKeysWithValues:backgroundSpecies.map{($0,common)})
        frames[.treeSparrow]=common.union(F.required)
        // Up to eight rows of separate ordinary windows. The carrier's route
        // stays in the lower part of this same display, clear of all peers.
        let hosts=(0..<(residents-1)).map {index in
            Surface(id:UInt32(1300+index),pid:42,
                rect:CGRect(x:140+CGFloat(index%8)*280,y:140+CGFloat(index/8)*110,width:160,height:30))
        }
        e.updateWorld(.init(screens:[display],displays:[display],surfaces:[carrierHost]+hosts,
            pointer:CGPoint(x:20,y:20),availableFrames:frames))
        func makeBird(_ species:SpeciesID,on host:Surface,fraction:CGFloat)->Bird {
            let bird=Bird(position:.zero,fraction:fraction,profile:settings.catalog.profile(species),random:{0.5})
            bird.perch(on:host,spriteScale:e.spriteScale(for:bird));bird.perchDuration=600
            return bird
        }
        let carrier=makeBird(.treeSparrow,on:carrierHost,fraction:0.15)
        let background=hosts.enumerated().map {index,host in
            makeBird(backgroundSpecies[index%backgroundSpecies.count],on:host,fraction:0.5)
        }
        e.installFixtureBirds([carrier]+background)
        let carrierID=try XCTUnwrap(e.id(of:carrier))
        let identities=e.birds.map(ObjectIdentifier.init),backgroundPositions=background.map(\.position)
        var events:[BehaviorEvent]=[],observations:[BehaviorObservation]=[]
        e.eventObserver={events.append($0)};e.observationObserver={observations.append($0)}
        var expectedID:ScenePropID?,allocated=Set<ScenePropID>(),attached=Set<ScenePropID>(),placed=Set<ScenePropID>()
        var peakRuns=0,peakLeases=0,peakReservations=0,peakObjects=0,samples=0

        func sample(file:StaticString=#filePath,line:UInt=#line) {
            samples+=1
            XCTAssertEqual(e.residentCount,residents,file:file,line:line)
            XCTAssertEqual(e.birds.count,residents,file:file,line:line)
            XCTAssertEqual(e.birds.map(ObjectIdentifier.init),identities,file:file,line:line)
            XCTAssertEqual(background.map(\.position),backgroundPositions,file:file,line:line)
            XCTAssertEqual(background.map(\.hostID),hosts.map{Optional($0.id)},file:file,line:line)
            XCTAssertEqual(e.arrivalCount,0,file:file,line:line);XCTAssertEqual(e.departureCount,0,file:file,line:line)
            XCTAssertEqual(e.passingCount,0,file:file,line:line);XCTAssertEqual(e.pendingCount,0,file:file,line:line)
            XCTAssertEqual(e.perchPlanner.rhythms.count,residents,file:file,line:line)
            peakRuns=max(peakRuns,e.activeRunCount);peakLeases=max(peakLeases,e.leasedBirdCount)
            peakReservations=max(peakReservations,e.reservedLandingCount)
            let objects=e.carriedObjectSnapshot(),tokens=F.tokens(e)
            peakObjects=max(peakObjects,objects.count)
            XCTAssertLessThanOrEqual(e.activeRunCount,1,file:file,line:line)
            XCTAssertLessThanOrEqual(e.leasedBirdCount,1,file:file,line:line)
            XCTAssertLessThanOrEqual(e.reservedLandingCount,2,file:file,line:line)
            XCTAssertEqual(e.habitatReservationCount,0,file:file,line:line)
            XCTAssertLessThanOrEqual(objects.count,1,file:file,line:line)
            XCTAssertEqual(tokens.map(\.id),objects.map(\.id),file:file,line:line)
            XCTAssertEqual(e.scenePropCount,objects.count,file:file,line:line)
            if let object=objects.first {
                XCTAssertEqual(object.id,expectedID,file:file,line:line)
                XCTAssertEqual(tokens.first?.size,16,file:file,line:line)
                XCTAssertEqual(tokens.first?.mirrored,!object.facingRight,file:file,line:line)
                switch object.state {
                case .available:
                    XCTAssertNil(object.owner,file:file,line:line)
                    XCTAssertEqual(e.sceneFocus?.leafID,object.id,file:file,line:line)
                case .attached:
                    attached.insert(object.id)
                    XCTAssertEqual(object.owner,carrierID,file:file,line:line)
                    XCTAssertEqual(object.reservedByRun,e.runtime.owners[carrierID],file:file,line:line)
                    XCTAssertNotNil(object.reservedByRun,file:file,line:line)
                    XCTAssertEqual(object.remainingLifetime,0,file:file,line:line)
                    XCTAssertEqual(e.sceneFocus?.leafID,object.id,file:file,line:line)
                case .placed:
                    placed.insert(object.id)
                    XCTAssertNil(object.owner,file:file,line:line);XCTAssertNil(e.sceneFocus,file:file,line:line)
                case .retired:
                    XCTAssertNil(object.owner,file:file,line:line);XCTAssertNil(object.reservedByRun,file:file,line:line)
                    XCTAssertNil(e.sceneFocus,file:file,line:line)
                }
            } else {XCTAssertNil(e.sceneFocus,file:file,line:line)}
        }
        func advance(_ seconds:Double) {
            for tick in 0..<Int((seconds*60).rounded()) {
                e.advance(BehaviorEngine.step)
                if tick%30==0 {sample()}
            }
            sample()
        }
        func clean() {
            XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0)
            XCTAssertEqual(e.reservedLandingCount,0);XCTAssertEqual(e.habitatReservationCount,0)
            XCTAssertTrue(e.runtime.propIDs.isEmpty);XCTAssertFalse(e.ambientBusy)
            XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertTrue(e.propSnapshot().isEmpty)
            XCTAssertTrue(e.habitatSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
            XCTAssertFalse(e.hasCarryLeafPlacement);XCTAssertFalse(e.hasBathPlacement);XCTAssertFalse(e.hasFoodTrayPlacement)
            sample();expectedID=nil
        }
        func settle()throws {
            for _ in 0..<12*60 {
                if carrier.state == .perched,carrier.stateTime>=1,
                   abs(e.baseHop(for:carrierID,bird:carrier))<0.001,e.runtime.owners[carrierID]==nil {return}
                e.advance(BehaviorEngine.step)
            }
            XCTFail("The real carrier did not settle under \(residents) residents")
            throw NSError(domain:"LeafCarryStressTests",code:1)
        }
        func place(_ x:CGFloat)throws->ScenePropID {
            XCTAssertEqual(e.handle(.placeCarryLeaf(at:CGPoint(x:x,y:carrierHost.rect.minY))),.accepted)
            let object=try XCTUnwrap(e.carriedObjectSnapshot().first)
            XCTAssertTrue(allocated.insert(object.id).inserted,"Each new leaf must receive a fresh identity")
            expectedID=object.id;sample();return object.id
        }
        func start(_ x:CGFloat)throws->(BehaviorRunID,ScenePropID) {
            try settle()
            let id=try place(x),run=try F.start(e.handle(.leafCarry(.preview)))
            XCTAssertEqual(e.runtime.runs[run]?.execution.participants,[carrierID])
            XCTAssertEqual(e.carriedObjectSnapshot().first?.reservedByRun,run)
            sample();return (run,id)
        }
        func reachAttached(_ run:BehaviorRunID)throws {
            for _ in 0..<25*60 {
                if e.carriedObjectSnapshot().first?.state == .attached {sample();return}
                guard e.runtime.runs[run] != nil else {break}
                e.advance(BehaviorEngine.step);sample()
            }
            XCTFail("No real pickup under \(residents) residents; terminals=\(F.terminals(e,run))")
            throw NSError(domain:"LeafCarryStressTests",code:2)
        }
        func pause(_ seconds:Double) {
            e.handle(.pause(true))
            let before=BehaviorReplayReport(engine:e,events:[]),ages=e.runtime.runs.mapValues(\.age)
            let clock=e.scheduler.remaining
            advance(seconds)
            let after=BehaviorReplayReport(engine:e,events:[])
            XCTAssertEqual(after.birds,before.birds);XCTAssertEqual(after.props,before.props)
            XCTAssertEqual(after.carriedObjects,before.carriedObjects)
            XCTAssertEqual(after.sceneFocusID,before.sceneFocusID);XCTAssertEqual(after.sceneFocusKind,before.sceneFocusKind)
            XCTAssertEqual(e.runtime.runs.mapValues(\.age),ages);XCTAssertEqual(e.scheduler.remaining,clock)
            e.handle(.pause(false))
        }
        func complete(_ x:CGFloat,withPause:Bool)throws {
            let (run,id)=try start(x),count=observations.count
            try reachAttached(run)
            if withPause {pause(2)}
            for _ in 0..<25*60 {
                guard e.runtime.runs[run] != nil else {break}
                e.advance(BehaviorEngine.step);sample()
            }
            F.assertReleased(e,run)
            XCTAssertEqual(F.terminals(e,run).map(\.type),[.completed])
            XCTAssertEqual(observations.count,count+1)
            let object=try XCTUnwrap(e.carriedObjectSnapshot().first)
            XCTAssertEqual(object.id,id);XCTAssertEqual(object.state,.placed)
            XCTAssertNil(object.owner);XCTAssertNil(object.reservedByRun);XCTAssertNil(e.sceneFocus)
            if withPause {pause(1)}
            advance(8.1) // The actual placed lifetime expires, without a clear command.
            clean()
        }

        // Check the real resident arrangement before beginning the workload.
        XCTAssertEqual(e.birds.filter{$0.profile.id == .treeSparrow}.count,1)
        for (index,bird) in e.birds.enumerated() {
            XCTAssertTrue(display.contains(e.bounds(of:bird)))
            let host=index==0 ? carrierHost:hosts[index-1]
            XCTAssertTrue(Geometry.isLandingVisible(on:host.id,at:bird.position,surfaces:e.world.surfaces,scale:e.spriteScale(for:bird)))
        }
        for a in e.birds.indices {
            for b in e.birds.indices where b>a {
                XCTAssertFalse(e.bounds(of:e.birds[a]).intersects(e.bounds(of:e.birds[b])))
            }
        }
        advance(9)
        try complete(1200,withPause:true)

        let (cancelled,cancelledID)=try start(800)
        try reachAttached(cancelled);pause(1)
        let contact=try XCTUnwrap(F.tokens(e).first)
        e.handle(.pointerClick)
        F.assertReleased(e,cancelled);XCTAssertEqual(F.terminals(e,cancelled).map(\.type),[.cancelled])
        XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.retired)
        XCTAssertEqual(F.tokens(e).first?.id,cancelledID);XCTAssertEqual(F.tokens(e).first?.rect,contact.rect)
        advance(0.1);pause(1);advance(0.2);clean()
        XCTAssertEqual(observations.count,1)

        try complete(1200,withPause:false)
        try complete(800,withPause:true)
        XCTAssertEqual(observations.count,3)

        let expiredID=try place(1200)
        advance(179.9);pause(2)
        XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.available)
        XCTAssertEqual(e.sceneFocus?.leafID,expiredID)
        advance(0.15)
        XCTAssertNil(e.sceneFocus);XCTAssertEqual(e.carriedObjectSnapshot().first?.state,.retired)
        XCTAssertEqual(F.tokens(e).first?.id,expiredID)
        advance(0.3);clean()

        XCTAssertEqual(allocated.count,5);XCTAssertEqual(attached.count,4);XCTAssertEqual(placed.count,3)
        XCTAssertEqual(events.filter{$0.kind == .leafCarry && $0.type == .started}.count,4)
        XCTAssertEqual(events.filter{$0.kind == .leafCarry && $0.type == .completed}.count,3)
        XCTAssertEqual(events.filter{$0.kind == .leafCarry && $0.type == .cancelled}.count,1)
        XCTAssertFalse(events.contains{$0.type == .failed || $0.type == .rejected})
        for run in events.filter({$0.type == .started}).compactMap(\.runID) {
            XCTAssertEqual(events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}.count,1)
        }
        XCTAssertEqual(observations.map(\.kind),Array(repeating:.leafCarry,count:3))
        XCTAssertEqual(observations.map(\.source),Array(repeating:.preview,count:3))
        XCTAssertEqual([peakRuns,peakLeases,peakReservations,peakObjects],[1,1,2,1])
        XCTAssertGreaterThan(samples,0)

        XCTAssertEqual(e.handle(.placeCarryLeafAfter(3)),.scheduled)
        e.handle(.cancelAmbient(.sleep));clean()
        for id in e.birds.compactMap({e.id(of:$0)}) {e.handle(.remove(id))}
        XCTAssertTrue(e.birds.isEmpty);XCTAssertEqual(e.residentCount,0)
        XCTAssertEqual(e.activeRunCount,0);XCTAssertEqual(e.leasedBirdCount,0);XCTAssertEqual(e.reservedLandingCount,0)
        XCTAssertEqual(e.habitatReservationCount,0);XCTAssertEqual(e.scenePropCount,0)
        XCTAssertTrue(e.carriedObjectSnapshot().isEmpty);XCTAssertNil(e.sceneFocus)
        XCTAssertTrue(e.perchPlanner.rhythms.isEmpty);XCTAssertEqual(e.activeVisitorCount,0)
        XCTAssertFalse(e.hasCarryLeafPlacement)
    }
}
