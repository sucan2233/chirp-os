import XCTest
@testable import BirdingCore

final class PerchSettingsTests: XCTestCase {
    func testNewSettingsEnablePerchActivities() {
        XCTAssertTrue(BirdSettings().perchActions)
    }

    func testMissingPerchSettingDefaultsOnWithoutChangingExistingSettings() throws {
        var original=BirdSettings()
        original.hoverDelay=0.25;original.pointerVisits=false;original.flockPasses=false
        original.ambientFrequency = .high
        original.probabilities.adjust(at:0,to:1234)
        original.probabilities.setLocked(true,at:0)
        original.catalog.species[0].speed=1.25
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
        object.removeValue(forKey:"perchActions")
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:object))
        XCTAssertTrue(migrated.perchActions)
        XCTAssertEqual(migrated.hoverDelay,original.hoverDelay)
        XCTAssertEqual(migrated.pointerVisits,original.pointerVisits)
        XCTAssertEqual(migrated.flockPasses,original.flockPasses)
        XCTAssertEqual(migrated.ambientFrequency,original.ambientFrequency)
        XCTAssertEqual(migrated.probabilities,original.probabilities)
        XCTAssertEqual(migrated.catalog.species,original.catalog.species)
    }

    func testPerchSwitchSaveAndReloadPreservesOtherSettings() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        let legacy=folder.appendingPathComponent("legacy.json")
        // Save off first, then back on to cover overwriting an existing profile.
        for enabled in [false,true] {
            var original=BirdSettings();original.perchActions=enabled
            original.hoverDelay=0.25;original.pointerVisits=false;original.flockPasses=false
            original.ambientFrequency = .high
            original.probabilities.adjust(at:0,to:1234)
            original.probabilities.setLocked(true,at:0)
            original.catalog.species[0].speed=1.25
            try original.save(to:url)
            let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
            XCTAssertEqual(object["perchActions"] as? Bool,enabled)
            let saved=try BirdSettings.load(from:url,legacyURL:legacy)
            XCTAssertEqual(saved.perchActions,enabled)
            XCTAssertEqual(saved.hoverDelay,original.hoverDelay)
            XCTAssertEqual(saved.pointerVisits,original.pointerVisits)
            XCTAssertEqual(saved.flockPasses,original.flockPasses)
            XCTAssertEqual(saved.ambientFrequency,original.ambientFrequency)
            XCTAssertEqual(saved.probabilities,original.probabilities)
            XCTAssertEqual(saved.catalog.species,original.catalog.species)
        }
    }

    func testLegacyCatalogEnablesPerchActivities() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let legacy=folder.appendingPathComponent("species.json")
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        try JSONEncoder().encode(catalog).write(to:legacy)
        let migrated=try BirdSettings.load(from:folder.appendingPathComponent("settings.json"),legacyURL:legacy)
        XCTAssertTrue(migrated.perchActions)
        XCTAssertEqual(migrated.catalog.species,catalog.species)
        XCTAssertEqual(migrated.hoverDelay,1)
        XCTAssertTrue(migrated.pointerVisits);XCTAssertTrue(migrated.flockPasses)
        XCTAssertEqual(migrated.ambientFrequency,.low)
    }

    func testInvalidPerchSettingIsRejected() throws {
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as! [String:Any]
        object["perchActions"]="enabled"
        XCTAssertThrowsError(try BirdSettings.decode(JSONSerialization.data(withJSONObject:object)))
    }
}
