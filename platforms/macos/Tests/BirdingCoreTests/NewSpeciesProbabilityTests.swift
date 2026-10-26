import Foundation
import XCTest
@testable import BirdingCore

final class NewSpeciesProbabilityTests:XCTestCase {
    func testNewBirdsInheritDefaultsInBothModesAndReorderedCatalog() throws {
        for manual in [false,true] {
            var settings=BirdSettings(catalog:SpeciesCatalog(species:Array(SpeciesCatalog.standard.species.prefix(46).reversed())))
            settings.probabilities.setWeight(0,for:.treeSparrow)
            settings.probabilities.setWeight(4321,for:.redWhiskeredBulbul)
            settings.probabilities.manualAdjustmentEnabled=manual
            let expanded=try BirdSettings.decode(JSONEncoder().encode(settings))
            XCTAssertEqual(expanded.catalog.species.count,100)
            XCTAssertEqual(expanded.probabilities.weight(for:.treeSparrow),manual ? 0 : SpeciesCatalog.standard.profile(.treeSparrow).weight)
            XCTAssertEqual(expanded.probabilities.overrides,settings.probabilities.overrides)
            for bird in SpeciesCatalog.standard.species.dropFirst(46) {
                XCTAssertEqual(expanded.probabilities.weight(for:bird.id),bird.weight)
                XCTAssertGreaterThan(bird.weight,0)
            }
            XCTAssertEqual(try BirdSettings.decode(JSONEncoder().encode(expanded)).probabilities,expanded.probabilities)
        }
    }
    func testUnknownOverridesSurviveWithoutEnteringPool() throws {
        var raw=try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as! [String:Any]
        raw["speciesProbability"]=["manualAdjustmentEnabled":true,"overrides":["futureBird":125,"treeSparrow":0]]
        let settings=try BirdSettings.decode(JSONSerialization.data(withJSONObject:raw))
        XCTAssertEqual(settings.probabilities.overrides["futureBird"],125)
        XCTAssertEqual(settings.probabilities.entries.count,100)
        XCTAssertEqual(settings.probabilities.totalWeight,5358-SpeciesCatalog.standard.profile(.treeSparrow).weight)
        XCTAssertEqual(try BirdSettings.decode(JSONEncoder().encode(settings)).probabilities,settings.probabilities)
    }
}
