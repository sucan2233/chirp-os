import Foundation
import XCTest
@testable import BirdingCore

final class VisitorMemoryTests:XCTestCase {
    private func object(_ archive:VisitorMemoryArchive) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(archive)) as? [String:Any])
    }
    private func data(_ object:[String:Any]) throws -> Data {try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])}
    private func fixture() throws -> [String:Any] {
        let memory=VisitorMemory(seed:73)
        _=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        return try object(memory.archive)
    }
    private func assertInvalid(_ body:() throws -> Void,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertThrowsError(try body(),file:file,line:line) {error in
            guard case let VisitorMemoryError.invalid(reason)=error else {
                XCTFail("Expected VisitorMemoryError.invalid, got \(error)",file:file,line:line);return
            }
            XCTAssertFalse(reason.isEmpty,file:file,line:line)
            XCTAssertFalse(error.localizedDescription.isEmpty,file:file,line:line)
        }
    }
    private func temporaryFolder() -> URL {FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)}

    func testEmptyArchiveAndFirstVisitorMatchSessionTemperament() throws {
        let memory=VisitorMemory(seed:UInt64.max)
        XCTAssertEqual(VisitorMemoryArchive.currentVersion,1)
        XCTAssertEqual(VisitorMemoryArchive.maximumProfiles,128)
        XCTAssertEqual(VisitorMemoryArchive.maximumBytes,262_144)
        XCTAssertEqual(memory.archive.seed,String(UInt64.max))
        XCTAssertEqual(memory.archive.nextID,"1");XCTAssertEqual(memory.archive.visitOrdinal,"0")
        XCTAssertTrue(memory.archive.profiles.isEmpty);XCTAssertEqual(memory.activeCount,0)
        XCTAssertEqual(memory.profileCount,0)
        try memory.archive.validate()
        let bird=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        XCTAssertEqual(bird.id,"1");XCTAssertEqual(bird.species,.treeSparrow)
        XCTAssertEqual(bird.temperament,BirdTemperament(seed:UInt64.max,birdID:BirdID(1)))
        XCTAssertEqual(bird.calmSeconds,0);XCTAssertEqual(bird.familiarity,0);XCTAssertEqual(bird.visits,1)
        XCTAssertEqual(memory.archive.nextID,"2");XCTAssertEqual(memory.archive.visitOrdinal,"1")
        XCTAssertEqual(memory.profileCount,1)
        try memory.archive.validate()
    }

    func testCrossSessionRoundTripRetainsIdentityTraitsAndCalmWithoutActiveLeases() throws {
        let first=VisitorMemory(seed:73)
        let bird=try XCTUnwrap(first.acquire(species:.treeSparrow))
        for _ in 0..<120 {first.learn(bird.id,elapsed:0.05)}
        let learned=try XCTUnwrap(first.profile(bird.id))
        let frozen=first.archive
        let archive=try VisitorMemoryArchive.decode(JSONEncoder().encode(frozen))
        XCTAssertEqual(archive,frozen)
        let second=VisitorMemory(seed:999)
        try second.restore(archive)
        XCTAssertEqual(second.activeCount,0)
        XCTAssertEqual(second.profileCount,1)
        XCTAssertEqual(second.profile(bird.id),learned)
        XCTAssertEqual(second.archive.seed,"73")
        let returned=try XCTUnwrap(second.acquire(species:.treeSparrow))
        XCTAssertEqual(returned.id,learned.id);XCTAssertEqual(returned.temperament,learned.temperament)
        XCTAssertEqual(returned.calmSeconds,learned.calmSeconds);XCTAssertEqual(returned.familiarity,learned.familiarity)
        XCTAssertEqual(returned.visits,learned.visits+1)
        let newcomer=try XCTUnwrap(second.acquire(species:.littleOwl))
        XCTAssertEqual(newcomer.id,"2")
        XCTAssertEqual(newcomer.temperament,BirdTemperament(seed:73,birdID:BirdID(2)))
        XCTAssertEqual(first.archive,frozen,"Archives are independent values across sessions")
        let serialized=try object(archive)
        XCTAssertNil(serialized["active"]);XCTAssertNil(serialized["leases"])
        XCTAssertEqual(Set(serialized.keys),["version","seed","nextID","visitOrdinal","profiles"])
    }

    func testProfileSeedIsRetainedIndependentlyOfSessionAndArchiveSeed() throws {
        var raw=try fixture()
        var profiles=try XCTUnwrap(raw["profiles"] as? [[String:Any]])
        profiles[0]["seed"]=String(UInt64.max);raw["profiles"]=profiles
        let restored=VisitorMemory(seed:0)
        try restored.restore(VisitorMemoryArchive.decode(data(raw)))
        let bird=try XCTUnwrap(restored.acquire(species:.treeSparrow))
        XCTAssertEqual(bird.seed,String(UInt64.max))
        XCTAssertEqual(bird.temperament,BirdTemperament(seed:UInt64.max,birdID:BirdID(1)))
        let other=try XCTUnwrap(restored.acquire(species:.littleOwl))
        XCTAssertEqual(other.seed,"73")
        XCTAssertEqual(other.temperament,BirdTemperament(seed:73,birdID:BirdID(2)))
        XCTAssertEqual(try VisitorMemoryArchive.decode(JSONEncoder().encode(restored.archive)),restored.archive)
    }

    func testSharedFixtureVisitor99RetainsIdentityAcrossAcquireReleaseAndReacquire() throws {
        let json=Data(#"{"version":1,"seed":"73","nextID":"100","visitOrdinal":"100","profiles":[{"id":"99","species":"treeSparrow","seed":"73","calmSeconds":150,"visits":2,"lastVisitOrdinal":"100"}]}"#.utf8)
        let memory=VisitorMemory(seed:999)
        try memory.restore(VisitorMemoryArchive.decode(json))
        XCTAssertEqual(memory.profileCount,1);XCTAssertEqual(memory.activeCount,0)
        let first=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        XCTAssertEqual(first.id,"99");XCTAssertEqual(first.visits,3);XCTAssertEqual(first.lastVisitOrdinal,"101")
        XCTAssertEqual(first.familiarity,0.5)
        XCTAssertEqual(first.temperament,BirdTemperament(seed:73,birdID:BirdID(99)))
        memory.release(first.id)
        XCTAssertEqual(memory.profileCount,1);XCTAssertEqual(memory.activeCount,0)
        let second=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        XCTAssertEqual(second.id,"99");XCTAssertEqual(second.visits,4);XCTAssertEqual(second.lastVisitOrdinal,"102")
        XCTAssertEqual(second.temperament,first.temperament);XCTAssertEqual(second.calmSeconds,150)
        XCTAssertEqual(second.familiarity,0.5)
        XCTAssertEqual(memory.profileCount,1);XCTAssertEqual(memory.activeCount,1)
        XCTAssertEqual(memory.archive.nextID,"100");XCTAssertEqual(memory.archive.visitOrdinal,"102")
        try memory.archive.validate()
    }

    func testMatchingSpeciesNeverSharesConcurrentIdentityAndReusesBeforeGlobalLRU() throws {
        let memory=VisitorMemory(seed:1)
        let owl=try XCTUnwrap(memory.acquire(species:.littleOwl))
        let a=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        let b=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        XCTAssertNotEqual(a.id,b.id);XCTAssertEqual(memory.activeCount,3)
        memory.release(owl.id);memory.release(a.id)
        let returned=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        XCTAssertEqual(returned.id,a.id);XCTAssertEqual(returned.species,.treeSparrow)
        XCTAssertEqual(returned.visits,2);XCTAssertEqual(memory.activeCount,2)
        XCTAssertEqual(memory.profile(owl.id),owl)
        memory.release("missing");memory.release(a.id);memory.release(a.id)
        XCTAssertEqual(memory.activeCount,1)
        XCTAssertNil(memory.profile("missing"))
        try memory.archive.validate()
    }

    func testSameSpeciesRotationUsesVisitOrdinalInsteadOfReleaseOrderAndSurvivesRestore() throws {
        let memory=VisitorMemory(seed:3)
        let birds=try (0..<3).map{_ in try XCTUnwrap(memory.acquire(species:.treeSparrow))}
        for bird in birds.reversed() {memory.release(bird.id)}
        for bird in birds {
            let returned=try XCTUnwrap(memory.acquire(species:.treeSparrow))
            XCTAssertEqual(returned.id,bird.id);memory.release(returned.id)
        }
        let second=VisitorMemory(seed:9)
        try second.restore(VisitorMemoryArchive.decode(JSONEncoder().encode(memory.archive)))
        for bird in birds {
            let returned=try XCTUnwrap(second.acquire(species:.treeSparrow))
            XCTAssertEqual(returned.id,bird.id);XCTAssertEqual(returned.visits,3)
            second.release(returned.id)
        }
        XCTAssertEqual(second.archive.nextID,"4");XCTAssertEqual(second.archive.visitOrdinal,"9")
        try second.archive.validate()
    }

    func testCapacityRejectsAllActiveAndEvictsOnlyLeastRecentlyVisitedInactive() throws {
        let memory=VisitorMemory(seed:4)
        let birds=try (0..<128).map{_ in try XCTUnwrap(memory.acquire(species:.treeSparrow))}
        XCTAssertEqual(Set(birds.map(\.id)).count,128)
        let full=memory.archive
        XCTAssertNil(memory.acquire(species:.treeSparrow));XCTAssertNil(memory.acquire(species:.littleOwl))
        XCTAssertEqual(memory.archive,full);XCTAssertEqual(memory.activeCount,128)
        XCTAssertEqual(memory.profileCount,128)
        memory.release(birds[7].id);memory.release(birds[2].id)
        let owl=try XCTUnwrap(memory.acquire(species:.littleOwl))
        XCTAssertEqual(owl.id,"129");XCTAssertNil(memory.profile(birds[2].id))
        XCTAssertNotNil(memory.profile(birds[7].id));XCTAssertEqual(memory.profile(birds[0].id),birds[0])
        let heron=try XCTUnwrap(memory.acquire(species:.greyHeron))
        XCTAssertEqual(heron.id,"130");XCTAssertNil(memory.profile(birds[7].id))
        XCTAssertEqual(memory.archive.profiles.count,128);XCTAssertEqual(memory.activeCount,128)
        XCTAssertEqual(memory.profileCount,128)
        XCTAssertNil(memory.acquire(species:.greyHeron))
        try memory.archive.validate()
    }

    func testCapacityReusesMatchingProfileAndUpdatesEvictionOrder() throws {
        let memory=VisitorMemory(seed:5)
        let owl=try XCTUnwrap(memory.acquire(species:.littleOwl))
        let sparrow=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        for _ in 2..<128 {_=try XCTUnwrap(memory.acquire(species:.greyHeron))}
        memory.release(owl.id);memory.release(sparrow.id)
        let returned=try XCTUnwrap(memory.acquire(species:.littleOwl))
        XCTAssertEqual(returned.id,owl.id);XCTAssertEqual(memory.archive.nextID,"129")
        memory.release(returned.id)
        let new=try XCTUnwrap(memory.acquire(species:.commonKestrel))
        XCTAssertEqual(new.id,"129");XCTAssertNil(memory.profile(sparrow.id))
        XCTAssertEqual(memory.profile(owl.id)?.visits,2)
        memory.learn(sparrow.id,elapsed:0.05)
        XCTAssertNil(memory.profile(sparrow.id))
        try memory.archive.validate()
    }

    func testCalmLearningRequiresActiveLeaseAndFinitePositiveTimeAndCapsEachObservation() throws {
        let memory=VisitorMemory(seed:6)
        let bird=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        for elapsed:Double in [0,-1,-Double.greatestFiniteMagnitude,.nan,.infinity,-.infinity] {
            memory.learn(bird.id,elapsed:elapsed)
        }
        memory.learn("missing",elapsed:0.05)
        XCTAssertEqual(memory.profile(bird.id)?.calmSeconds,0)
        memory.learn(bird.id,elapsed:Double.greatestFiniteMagnitude)
        XCTAssertEqual(try XCTUnwrap(memory.profile(bird.id)).calmSeconds,0.05,accuracy:1e-12)
        memory.learn(bird.id,elapsed:0.01)
        XCTAssertEqual(try XCTUnwrap(memory.profile(bird.id)).calmSeconds,0.06,accuracy:1e-12)
        memory.release(bird.id)
        let inactive=memory.archive
        for _ in 0..<100 {memory.learn(bird.id,elapsed:10);_=memory.profile(bird.id);_=memory.archive}
        XCTAssertEqual(memory.archive,inactive,"Inactive time and read-only access cannot learn or decay")
        _=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        for _ in 0..<6_100 {memory.learn(bird.id,elapsed:1)}
        XCTAssertEqual(memory.profile(bird.id)?.calmSeconds,300)
        XCTAssertEqual(memory.profile(bird.id)?.familiarity,1)
        try memory.archive.validate()
    }

    func testRestoreRejectsActiveLeaseWithoutMutatingSessionAndReleaseAllowsRestore() throws {
        let memory=VisitorMemory(seed:7),replacement=VisitorMemory(seed:8)
        let bird=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        let before=memory.archive
        assertInvalid {try memory.restore(replacement.archive)}
        XCTAssertEqual(memory.archive,before);XCTAssertEqual(memory.activeCount,1)
        memory.release(bird.id)
        try memory.restore(replacement.archive)
        XCTAssertEqual(memory.archive,replacement.archive)
        XCTAssertEqual(memory.profileCount,0)
        XCTAssertNil(memory.profile(bird.id))
    }

    func testRepeatSeedAndSameActionsAreDeterministic() throws {
        let a=VisitorMemory(seed:73),b=VisitorMemory(seed:73),other=VisitorMemory(seed:74)
        for species in SpeciesID.allCases {
            let first=try XCTUnwrap(a.acquire(species:species)),second=try XCTUnwrap(b.acquire(species:species))
            XCTAssertEqual(first,second)
            a.learn(first.id,elapsed:0.02);b.learn(second.id,elapsed:0.02)
            a.release(first.id);b.release(second.id)
        }
        XCTAssertEqual(a.archive,b.archive)
        let same=try XCTUnwrap(a.acquire(species:.treeSparrow)),different=try XCTUnwrap(other.acquire(species:.treeSparrow))
        XCTAssertNotEqual(same.temperament,different.temperament)
        try a.archive.validate()
    }

    func testUnsupportedVersionIsRejectedBeforeNestedPayloadAndDirectCodableAlsoValidates() throws {
        for version:Any in [2,-1,0,true,"1",1.5,NSNull()] {
            let raw:[String:Any]=["version":version,"profiles":"future nested schema"]
            assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
        }
        let future=try data(["version":2,"profiles":"future nested schema"])
        assertInvalid {_=try JSONDecoder().decode(VisitorMemoryArchive.self,from:future)}
        do {_=try VisitorMemoryArchive.decode(future);XCTFail("Future version was accepted")}
        catch VisitorMemoryError.invalid(let reason) {XCTAssertTrue(reason.contains("unsupported version"))}
        for malformed in [Data(),Data("null".utf8),Data("[]".utf8),Data("{".utf8),Data("{}".utf8)] {
            assertInvalid {_=try VisitorMemoryArchive.decode(malformed)}
        }
    }

    func testRejectsNoncanonicalAndOverflowedArchiveIntegers() throws {
        let base=try fixture()
        for key in ["seed","nextID","visitOrdinal"] {
            for value:Any in ["","-1","+1","01","1.0"," 1","1 ","18446744073709551616",1,true,NSNull()] {
                var raw=base;raw[key]=value
                assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
            }
        }
        for key in ["nextID","visitOrdinal"] {
            var raw=base;raw[key]="0"
            assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
        }
        var empty=try object(VisitorMemory(seed:0).archive)
        empty["nextID"]="2";empty["visitOrdinal"]="1"
        assertInvalid {_=try VisitorMemoryArchive.decode(data(empty))}
    }

    func testRejectsInvalidProfileFieldsRangesAndSpecies() throws {
        let base=try fixture(),original=try XCTUnwrap(base["profiles"] as? [[String:Any]])[0]
        let cases:[(String,[Any])]=[
            ("id",["0","01","+1","-1","18446744073709551616",1]),
            ("seed",["01","-1","18446744073709551616",1]),
            ("lastVisitOrdinal",["0","01","-1","18446744073709551616",1]),
            ("species",["unknownSpecies",1,NSNull()]),
            ("visits",[0,-1,1_000_000_001,1.5,true,"1"]),
            ("calmSeconds",[-0.001,300.001,"NaN","Infinity",true,NSNull()])]
        for (key,values) in cases {
            for value in values {
                var raw=base,profile=original;profile[key]=value;raw["profiles"]=[profile]
                assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
            }
            var raw=base,profile=original;profile.removeValue(forKey:key);raw["profiles"]=[profile]
            assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
        }
        for symbol in ["NaN","Infinity","-Infinity"] {
            var profile=original;profile["calmSeconds"]=symbol
            let decoder=JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity:"Infinity",negativeInfinity:"-Infinity",nan:"NaN")
            assertInvalid {_=try decoder.decode(VisitorProfile.self,from:data(profile))}
        }
    }

    func testRejectsDuplicateIDsDuplicateVisitOrdinalsAndImpossibleCounters() throws {
        let memory=VisitorMemory(seed:10)
        for _ in 0..<2 {_=try XCTUnwrap(memory.acquire(species:.treeSparrow))}
        let base=try object(memory.archive),original=try XCTUnwrap(base["profiles"] as? [[String:Any]])
        for key in ["id","lastVisitOrdinal"] {
            var profiles=original;profiles[0][key]=profiles[1][key]
            var raw=base;raw["profiles"]=profiles
            assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
        }
        for (key,value) in [("nextID","2"),("nextID","4"),("visitOrdinal","1"),("visitOrdinal","3")] {
            var raw=base;raw[key]=value
            assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
        }
        var raw=base,profiles=original
        profiles[0]["visits"]=2;raw["profiles"]=profiles
        assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
        profiles=original;profiles[1]["visits"]=2;raw["profiles"]=profiles
        assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
    }

    func testVisitsSaturateAndUInt64ExhaustionCannotWrapOrMutateFailedAcquisition() throws {
        var raw=try fixture(),profiles=try XCTUnwrap(raw["profiles"] as? [[String:Any]])
        raw["visitOrdinal"]="1000000000"
        profiles[0]["lastVisitOrdinal"]="1000000000";profiles[0]["visits"]=1_000_000_000;raw["profiles"]=profiles
        let memory=VisitorMemory(seed:99)
        try memory.restore(VisitorMemoryArchive.decode(data(raw)))
        let capped=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        XCTAssertEqual(capped.visits,1_000_000_000);try memory.archive.validate()

        raw=try fixture();profiles=try XCTUnwrap(raw["profiles"] as? [[String:Any]])
        raw["nextID"]=String(UInt64.max-1);raw["visitOrdinal"]=String(UInt64.max-2)
        profiles[0]["lastVisitOrdinal"]=String(UInt64.max-2);raw["profiles"]=profiles
        let exhausted=VisitorMemory(seed:0)
        try exhausted.restore(VisitorMemoryArchive.decode(data(raw)))
        let last=try XCTUnwrap(exhausted.acquire(species:.littleOwl))
        XCTAssertEqual(last.id,String(UInt64.max-1));XCTAssertEqual(exhausted.archive.nextID,String(UInt64.max))
        let before=exhausted.archive
        XCTAssertNil(exhausted.acquire(species:.greyHeron));XCTAssertEqual(exhausted.archive,before)
        let reused=try XCTUnwrap(exhausted.acquire(species:.treeSparrow))
        XCTAssertEqual(reused.id,"1");XCTAssertEqual(exhausted.archive.visitOrdinal,String(UInt64.max))
        exhausted.release(reused.id)
        let terminal=exhausted.archive
        XCTAssertNil(exhausted.acquire(species:.treeSparrow));XCTAssertEqual(exhausted.archive,terminal)
        try terminal.validate()
        XCTAssertEqual(try VisitorMemoryArchive.decode(JSONEncoder().encode(terminal)),terminal)
    }

    func testProfileAndByteLimitsAreEnforcedIncludingExactByteBoundary() throws {
        let memory=VisitorMemory(seed:11)
        for _ in 0..<128 {_=try XCTUnwrap(memory.acquire(species:.treeSparrow))}
        let archive=memory.archive
        let encoded=try JSONEncoder().encode(archive)
        XCTAssertLessThan(encoded.count,VisitorMemoryArchive.maximumBytes)
        var exact=encoded;exact.append(Data(repeating:32,count:VisitorMemoryArchive.maximumBytes-encoded.count))
        XCTAssertEqual(try VisitorMemoryArchive.decode(exact),archive)
        exact.append(32);assertInvalid {_=try VisitorMemoryArchive.decode(exact)}
        var raw=try object(archive),profiles=try XCTUnwrap(raw["profiles"] as? [[String:Any]])
        var extra=profiles[0];extra["id"]="129";extra["lastVisitOrdinal"]="129";profiles.append(extra)
        raw["profiles"]=profiles;raw["nextID"]="130";raw["visitOrdinal"]="129"
        assertInvalid {_=try VisitorMemoryArchive.decode(data(raw))}
    }

    func testSaveCreatesParentsRoundTripsAndCanAtomicallyReplaceValidArchive() throws {
        let root=temporaryFolder()
        defer {try? FileManager.default.removeItem(at:root)}
        let target=root.appendingPathComponent("nested/memory.json"),memory=VisitorMemory(seed:UInt64.max)
        let bird=try XCTUnwrap(memory.acquire(species:.treeSparrow))
        memory.learn(bird.id,elapsed:0.05)
        try memory.archive.save(to:target)
        XCTAssertEqual(try VisitorMemoryArchive.load(from:target),memory.archive)
        memory.learn(bird.id,elapsed:0.05)
        try memory.archive.save(to:target)
        XCTAssertEqual(try VisitorMemoryArchive.load(from:target),memory.archive)
        let second=VisitorMemory(seed:0)
        try second.restore(VisitorMemoryArchive.load(from:target))
        XCTAssertEqual(second.activeCount,0);XCTAssertEqual(second.profile(bird.id),memory.profile(bird.id))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:target.deletingLastPathComponent().path),["memory.json"])
    }

    func testSavePreservesFutureCorruptInvalidAndOversizedExistingTargets() throws {
        let root=temporaryFolder()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let target=root.appendingPathComponent("memory.json"),memory=VisitorMemory(seed:12)
        var invalid=try fixture();invalid["nextID"]="1"
        let payloads=[try data(["version":2,"profiles":"future schema"]),Data("broken json".utf8),
            try data(invalid),Data(repeating:32,count:VisitorMemoryArchive.maximumBytes+1)]
        for payload in payloads {
            try payload.write(to:target)
            assertInvalid {_=try VisitorMemoryArchive.load(from:target)}
            assertInvalid {try memory.archive.save(to:target)}
            XCTAssertEqual(try Data(contentsOf:target),payload)
        }
    }

    func testMissingLoadAndSaveFilesystemErrorsAreSurfacedWithoutDestroyingEntries() throws {
        let root=temporaryFolder()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let memory=VisitorMemory(seed:13),missing=root.appendingPathComponent("missing.json")
        XCTAssertThrowsError(try VisitorMemoryArchive.load(from:missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path))
        let parent=root.appendingPathComponent("file-parent")
        let sentinel=Data("keep me".utf8);try sentinel.write(to:parent)
        XCTAssertThrowsError(try memory.archive.save(to:parent.appendingPathComponent("memory.json")))
        XCTAssertEqual(try Data(contentsOf:parent),sentinel)
        let directory=root.appendingPathComponent("directory")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        XCTAssertThrowsError(try memory.archive.save(to:directory))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path),[])
        let link=root.appendingPathComponent("dangling.json")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:missing)
        XCTAssertThrowsError(try memory.archive.save(to:link))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath:link.path),missing.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path))
    }
}
