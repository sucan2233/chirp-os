import Foundation
import XCTest
@testable import BirdingCore

final class GiftLedgerTests:XCTestCase {
    private func folder() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("GiftLedgerTests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:url)}
        return url
    }
    private func archive(seed:UInt64=73) throws -> VisitorMemoryArchive {
        let memory=VisitorMemory(seed:seed)
        let profile=try XCTUnwrap(memory.acquire(species:.azureWingedMagpie))
        for _ in 0..<4000 {memory.learn(profile.id,elapsed:0.05)}
        memory.release(profile.id)
        _=memory.acquire(species:.azureWingedMagpie);memory.release(profile.id)
        _=memory.acquire(species:.azureWingedMagpie)
        return memory.archive
    }
    private func request(_ archive:VisitorMemoryArchive,source:BehaviorSource = .automatic,requestID:String="1") -> GiftAuthorizationRequest {
        .init(binding:.init(requestID:requestID,visitorArchiveSeed:archive.seed,visitorID:archive.profiles[0].id,
            birdID:BirdID(1),species:.azureWingedMagpie,source:source,leafID:ScenePropID(1),receiverSlot:1,receiverRevision:1))
    }
    private func clock(_ wall:Double)->GiftLedgerClock {.init(wallTime:{wall},monotonicTime:{0})}

    func testCommittedGrantSurvivesRestartAndCancellationDoesNotRefund() throws {
        let url=try folder().appendingPathComponent("gifts.json"),memory=try archive(),r=request(memory)
        let result=GiftLedgerStore(url:url).authorize(r,visitorArchive:memory,deadline:5,clock:clock(100_000))
        XCTAssertTrue(result.isValid);XCTAssertEqual(result.token?.binding,r.binding);XCTAssertNil(result.denial)
        let disk=try GiftLedger.load(from:url)
        XCTAssertEqual(disk.version,1);XCTAssertEqual(disk.grants.count,1)
        XCTAssertEqual(disk.grants.first?.visitorArchiveSeed,memory.seed)
        XCTAssertEqual(disk.grants.first?.visitorID,memory.profiles[0].id)
        XCTAssertEqual(disk.lastGrantedAt,100_000)
        // Discard the token without any execution/release, then use a new store.
        let before=try Data(contentsOf:url)
        let again=GiftLedgerStore(url:url).authorize(request(memory,requestID:"2"),visitorArchive:memory,deadline:5,clock:clock(300_000))
        XCTAssertEqual(again.denial,.alreadyGranted);XCTAssertNil(again.token)
        XCTAssertEqual(try Data(contentsOf:url),before)
    }

    func testCooldownIsGlobalAcrossNamespacesAndBoundaryIsInclusive() throws {
        let url=try folder().appendingPathComponent("gifts.json"),a=try archive(),b=try archive(seed:74)
        let store=GiftLedgerStore(url:url)
        XCTAssertNotNil(store.authorize(request(a),visitorArchive:a,deadline:5,clock:clock(100_000)).token)
        let before=try Data(contentsOf:url)
        XCTAssertEqual(store.authorize(request(b),visitorArchive:b,deadline:5,clock:clock(99_999)).denial,.clockRollback)
        XCTAssertEqual(store.authorize(request(b),visitorArchive:b,deadline:5,clock:clock(186_399.999)).denial,.globalCooldown)
        XCTAssertEqual(try Data(contentsOf:url),before)
        XCTAssertNotNil(store.authorize(request(b),visitorArchive:b,deadline:5,clock:clock(186_400)).token)
        XCTAssertEqual(try GiftLedger.load(from:url).grants.count,2)
    }

    func testPreviewMalformedAndIneligibleRequestsNeverCreateLedgerOrLock() throws {
        let root=try folder(),url=root.appendingPathComponent("unused/gifts.json"),a=try archive()
        let store=GiftLedgerStore(url:url)
        XCTAssertEqual(store.authorize(request(a,source:.preview),visitorArchive:a,deadline:5,clock:clock(0)).denial,.invalidRequest)
        XCTAssertEqual(store.authorize(request(a,requestID:"01"),visitorArchive:a,deadline:5,clock:clock(0)).denial,.invalidRequest)
        let other=try archive(seed:74)
        XCTAssertEqual(store.authorize(request(a),visitorArchive:other,deadline:5,clock:clock(0)).denial,.namespaceUnavailable)
        let fresh=VisitorMemory(seed:73);_=fresh.acquire(species:.azureWingedMagpie)
        XCTAssertEqual(store.authorize(request(fresh.archive),visitorArchive:fresh.archive,deadline:5,clock:clock(0)).denial,.notEligible)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.deletingLastPathComponent().path))
    }

    func testFutureCorruptDuplicateAndOversizedLedgersArePreservedByteForByte() throws {
        let root=try folder(),a=try archive()
        let grant:[String:Any]=["visitorArchiveSeed":"73","visitorID":"1","grantedAt":100_000]
        let duplicate=try JSONSerialization.data(withJSONObject:["version":1,"grants":[grant,grant],"lastGrantedAt":100_000])
        let cases:[(Data,GiftAuthorizationDenial)]=[
            (Data("{\"version\":2,\"unknown\":true}".utf8),.unsupportedVersion),
            (Data("{\"version\":1,\"grants\":".utf8),.invalidLedger),
            (duplicate,.invalidLedger),(Data(repeating:32,count:GiftLedger.maximumBytes+1),.invalidLedger)
        ]
        for (index,entry) in cases.enumerated() {
            let url=root.appendingPathComponent("\(index).json");try entry.0.write(to:url)
            let result=GiftLedgerStore(url:url).authorize(request(a),visitorArchive:a,deadline:5,clock:clock(300_000))
            XCTAssertEqual(result.denial,entry.1);XCTAssertNil(result.token)
            XCTAssertEqual(try Data(contentsOf:url),entry.0)
        }
    }

    func testPermanentTenThousandKeysAreNeverEvicted() throws {
        let url=try folder().appendingPathComponent("full.json"),a=try archive()
        let grants=(1...GiftLedger.maximumEntries).map {id -> [String:Any] in
            ["visitorArchiveSeed":"999","visitorID":String(id),"grantedAt":Double(id)*GiftLedger.minimumInterval]
        }
        let bytes=try JSONSerialization.data(withJSONObject:["version":1,"grants":grants,"lastGrantedAt":Double(grants.count)*GiftLedger.minimumInterval])
        XCTAssertLessThan(bytes.count,GiftLedger.maximumBytes)
        try bytes.write(to:url)
        let result=GiftLedgerStore(url:url).authorize(request(a),visitorArchive:a,deadline:5,
            clock:clock(Double(grants.count+1)*GiftLedger.minimumInterval))
        XCTAssertEqual(result.denial,.ledgerFull);XCTAssertEqual(try Data(contentsOf:url),bytes)
        XCTAssertEqual(try GiftLedger.load(from:url).grants.count,10_000)
    }

    func testExpiredDeadlineBeforeCommitLeavesNoGrant() throws {
        let url=try folder().appendingPathComponent("expired.json"),a=try archive()
        let result=GiftLedgerStore(url:url).authorize(request(a),visitorArchive:a,deadline:0,clock:clock(100_000))
        XCTAssertEqual(result.denial,.timedOut);XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
    }

    func testWriteFailureDoesNotIssueTokenOrReplaceUnrelatedBytes() throws {
        let parent=try folder().appendingPathComponent("blocked"),memory=try archive(),sentinel=Data("retained".utf8)
        try sentinel.write(to:parent)
        let result=GiftLedgerStore(url:parent.appendingPathComponent("gifts.json")).authorize(request(memory),
            visitorArchive:memory,deadline:5,clock:clock(100_000))
        XCTAssertEqual(result.denial,.storageUnavailable);XCTAssertNil(result.token)
        XCTAssertEqual(try Data(contentsOf:parent),sentinel)
    }

    func testDeadlineExpiringDuringCommitConsumesWithoutReturningToken() throws {
        let url=try folder().appendingPathComponent("late.json"),a=try archive()
        var reads=0
        let time=GiftLedgerClock(wallTime:{100_000},monotonicTime:{
            reads+=1
            // Advance only once the real atomic rename has become observable.
            return FileManager.default.fileExists(atPath:url.path) ? 6:0
        })
        let result=GiftLedgerStore(url:url).authorize(request(a),visitorArchive:a,deadline:5,clock:time)
        XCTAssertGreaterThan(reads,1);XCTAssertEqual(result.denial,.timedOut);XCTAssertNil(result.token)
        XCTAssertEqual(try GiftLedger.load(from:url).grants.count,1)
        XCTAssertEqual(GiftLedgerStore(url:url).authorize(request(a),visitorArchive:a,deadline:5,clock:clock(300_000)).denial,.alreadyGranted)
    }

    func testIndependentStoreInstancesSerializeTheEntireReadModifyWrite() throws {
        let url=try folder().appendingPathComponent("race.json"),a=try archive(),r=request(a)
        let group=DispatchGroup(),lock=NSLock()
        var results:[GiftAuthorizationResult]=[]
        for _ in 0..<8 {
            group.enter();DispatchQueue.global().async {
                let result=GiftLedgerStore(url:url).authorize(r,visitorArchive:a,
                    deadline:ProcessInfo.processInfo.systemUptime+5,
                    clock:.init(wallTime:{100_000},monotonicTime:{ProcessInfo.processInfo.systemUptime}))
                lock.lock();results.append(result);lock.unlock();group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout:.now()+10),.success)
        lock.lock();let snapshot=results;lock.unlock()
        XCTAssertEqual(snapshot.count,8);XCTAssertEqual(snapshot.filter{$0.token != nil}.count,1)
        XCTAssertEqual(snapshot.filter{$0.denial == .alreadyGranted}.count,7)
        XCTAssertEqual(try GiftLedger.load(from:url).grants.count,1)
    }

    func testLockWaitUsesDeadlineAndReleaseAllowsRetry() throws {
        let url=try folder().appendingPathComponent("locked.json"),a=try archive()
        let acquired=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),done=DispatchSemaphore(value:0)
        DispatchQueue.global().async {
            defer {done.signal()}
            try? GiftLedgerFileAccess.withLock(for:url,deadline:ProcessInfo.processInfo.systemUptime+5) {
                acquired.signal();_=release.wait(timeout:.now()+5)
            }
        }
        XCTAssertEqual(acquired.wait(timeout:.now()+2),.success)
        let result=GiftLedgerStore(url:url).authorize(request(a),visitorArchive:a,deadline:ProcessInfo.processInfo.systemUptime+0.05)
        XCTAssertEqual(result.denial,.timedOut);XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        release.signal();XCTAssertEqual(done.wait(timeout:.now()+2),.success)
        XCTAssertNotNil(GiftLedgerStore(url:url).authorize(request(a),visitorArchive:a,deadline:ProcessInfo.processInfo.systemUptime+5).token)
    }
}
