import Foundation
import XCTest
@testable import BirdingCore

final class ProbabilityTests: XCTestCase {
    func testDefaultsManualCacheAndIsolatedReset() throws {
        var settings=BirdSettings();settings.hoverDelay=0.25
        XCTAssertEqual(settings.probabilities.entries.count,100)
        XCTAssertEqual(settings.probabilities.totalWeight,5358)
        XCTAssertTrue(settings.probabilities.entries.allSatisfy{$0.weight>0})
        let peers=Array(settings.probabilities.entries.dropFirst())
        XCTAssertTrue(settings.probabilities.setManualWeight(at:0,to:1234))
        XCTAssertEqual(settings.probabilities.entries[0].weight,1234)
        XCTAssertEqual(Array(settings.probabilities.entries.dropFirst()),peers)
        settings.probabilities.manualAdjustmentEnabled=false
        XCTAssertEqual(settings.probabilities.entries,ProbabilityDistribution().entries)
        settings=try BirdSettings.decode(JSONEncoder().encode(settings))
        XCTAssertEqual(settings.probabilities.overrides["redWhiskeredBulbul"],1234)
        settings.probabilities.manualAdjustmentEnabled=true
        XCTAssertEqual(settings.probabilities.entries[0].weight,1234)
        settings.probabilities.resetToDefaults()
        XCTAssertEqual(settings.probabilities,ProbabilityDistribution())
        XCTAssertEqual(settings.hoverDelay,0.25)
    }
    func testZeroEmptyAndValidation() throws {
        var d=ProbabilityDistribution()
        for entry in d.entries {d.setWeight(0,for:entry.id)}
        d.manualAdjustmentEnabled=true
        var calls=0
        XCTAssertNil(d.choose(using:{calls+=1;return 0.5}))
        XCTAssertEqual(calls,0);XCTAssertEqual(d.totalWeight,0)
        for invalid in [-1,Double.nan,Double.infinity,0.0000001,1_000_001] {
            XCTAssertFalse(d.setWeight(invalid,for:.treeSparrow))
        }
        XCTAssertTrue(d.setWeight(0.000001,for:.treeSparrow))
        XCTAssertEqual(d.choose(unit:0),.treeSparrow)
        XCTAssertEqual(d.choose(unit:0.999999),.treeSparrow)
        XCTAssertNil(d.choose(unit:1))
        XCTAssertFalse(d.setManualWeight(at:-1,to:100))
    }
    func testSharedCrossPlatformFixtures() throws {
        struct Fixture:Decodable {let name:String;let weights:[Double];let units:[Double];let expected:[Int?]}
        var root=URL(fileURLWithPath:#filePath)
        for _ in 0..<5 {root.deleteLastPathComponent()}
        let fixtures=try JSONDecoder().decode([Fixture].self,from:Data(contentsOf:root.appendingPathComponent("shared/probability-fixtures.json")))
        for f in fixtures {
            let pool=try WeightedChoice(Array(f.weights.indices),weight:{f.weights[$0]})
            XCTAssertEqual(try f.units.map{try pool.choose(unit:$0)},f.expected,f.name)
        }
    }
    func testSamplerErrorsAndScaleInvariance() throws {
        for bad in [-1,Double.nan,Double.infinity] {
            XCTAssertThrowsError(try WeightedChoice([bad],weight:{$0}))
        }
        let pool=try WeightedChoice([1,3,6],weight:Double.init)
        let huge=try WeightedChoice([1,3,6],weight:{Double($0)*1e300})
        let tiny=try WeightedChoice([1,3,6],weight:{Double($0)*1e-300})
        for unit in [-0.01,1,Double.nan,Double.infinity] {XCTAssertThrowsError(try pool.choose(unit:unit))}
        var counts=[1:0,3:0,6:0]
        for n in 0..<10000 {
            let unit=(Double(n)+0.5)/10000
            let picked=try XCTUnwrap(pool.choose(unit:unit))
            XCTAssertEqual(try huge.choose(unit:unit),picked)
            XCTAssertEqual(try tiny.choose(unit:unit),picked)
            counts[picked,default:0]+=1
        }
        XCTAssertEqual(counts,[1:1000,3:3000,6:6000])
    }
    func testOddsAndUniformHelpers() throws {
        XCTAssertEqual(try RandomChoice.odds(success:1,failure:3,using:{0.24}),true)
        XCTAssertEqual(try RandomChoice.odds(success:1,failure:3,using:{0.25}),false)
        XCTAssertNil(try RandomChoice.odds(success:0,failure:0,using:{XCTFail("empty draw");return 0}))
        XCTAssertNil(RandomChoice.index(count:0,using:{XCTFail("empty draw");return 0}))
        XCTAssertEqual(RandomChoice.index(count:4,using:{0.5}),2)
    }
}
