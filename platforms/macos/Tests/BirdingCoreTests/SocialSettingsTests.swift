import XCTest
@testable import BirdingCore

final class SocialSettingsTests: XCTestCase {
    func testNewSettingsEnableSocialInteractions() {
        XCTAssertTrue(BirdSettings().socialInteractions)
    }

    func testMissingSocialSettingDefaultsOnWithoutChangingExistingSettings() throws {
        var original=configuredSettings();original.socialInteractions=false
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
        object.removeValue(forKey:"socialInteractions")
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:object))
        XCTAssertTrue(migrated.socialInteractions)
        assertOtherSettingsEqual(migrated,original)
    }

    func testOldSettingsWithoutInteractionFieldsReceiveDefaults() throws {
        let original=configuredSettings()
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
        for key in ["socialInteractions","pointerVisits","flockPasses","perchActions","ambientFrequency","hoverDelay"] {
            object.removeValue(forKey:key)
        }
        let migrated=try BirdSettings.decode(JSONSerialization.data(withJSONObject:object))
        XCTAssertTrue(migrated.socialInteractions)
        XCTAssertTrue(migrated.pointerVisits)
        XCTAssertTrue(migrated.flockPasses)
        XCTAssertTrue(migrated.perchActions)
        XCTAssertEqual(migrated.ambientFrequency,.low)
        XCTAssertEqual(migrated.hoverDelay,1)
        XCTAssertEqual(migrated.probabilities,original.probabilities)
        XCTAssertEqual(migrated.catalog.species,original.catalog.species)
    }

    func testSocialSwitchSaveAndReloadPreservesOtherSettings() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        let legacy=folder.appendingPathComponent("legacy.json")
        // Exercise explicit false, then overwrite the same file with true.
        for enabled in [false,true] {
            var original=configuredSettings();original.socialInteractions=enabled
            try original.save(to:url)
            let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
            XCTAssertEqual(object["socialInteractions"] as? Bool,enabled)
            let saved=try BirdSettings.load(from:url,legacyURL:legacy)
            XCTAssertEqual(saved.socialInteractions,enabled)
            assertOtherSettingsEqual(saved,original)
        }
    }

    func testLegacyCatalogEnablesSocialInteractions() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let legacy=folder.appendingPathComponent("species.json")
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        try JSONEncoder().encode(catalog).write(to:legacy)
        let migrated=try BirdSettings.load(from:folder.appendingPathComponent("settings.json"),legacyURL:legacy)
        XCTAssertTrue(migrated.socialInteractions)
        XCTAssertEqual(migrated.catalog.species,catalog.species)
        XCTAssertEqual(migrated.hoverDelay,1)
        XCTAssertTrue(migrated.pointerVisits)
        XCTAssertTrue(migrated.flockPasses)
        XCTAssertTrue(migrated.perchActions)
        XCTAssertEqual(migrated.ambientFrequency,.low)
    }

    func testInvalidSocialSettingIsRejected() throws {
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as! [String:Any]
        object["socialInteractions"]="enabled"
        XCTAssertThrowsError(try BirdSettings.decode(JSONSerialization.data(withJSONObject:object)))
    }

    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings()
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.flockPasses=false
        settings.perchActions=false;settings.ambientFrequency = .high
        settings.probabilities.setManualWeight(at:0,to:1234)
        settings.catalog.species[0].speed=1.25

        return settings
    }

    private func assertOtherSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,file:StaticString = #filePath,line:UInt = #line) {
        XCTAssertEqual(actual.hoverDelay,expected.hoverDelay,file:file,line:line)
        XCTAssertEqual(actual.pointerVisits,expected.pointerVisits,file:file,line:line)
        XCTAssertEqual(actual.flockPasses,expected.flockPasses,file:file,line:line)
        XCTAssertEqual(actual.perchActions,expected.perchActions,file:file,line:line)
        XCTAssertEqual(actual.ambientFrequency,expected.ambientFrequency,file:file,line:line)
        XCTAssertEqual(actual.probabilities,expected.probabilities,file:file,line:line)
        XCTAssertEqual(actual.catalog.species,expected.catalog.species,file:file,line:line)
        XCTAssertEqual(actual.perchDefaultsVersion,expected.perchDefaultsVersion,file:file,line:line)
    }
}
