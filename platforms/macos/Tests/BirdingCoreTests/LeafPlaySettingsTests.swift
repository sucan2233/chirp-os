import XCTest
@testable import BirdingCore

final class LeafPlaySettingsTests: XCTestCase {
    func testNewSettingsEnableLeafPlay() {
        XCTAssertTrue(BirdSettings().leafPlayEnabled)
    }

    func testMissingOrNullSettingDefaultsOnWithoutChangingExistingSettings() throws {
        let original=configuredSettings()
        for nullValue in [false,true] {
            var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
            if nullValue {object["leafPlayEnabled"]=NSNull()}
            else {object.removeValue(forKey:"leafPlayEnabled")}
            let data=try JSONSerialization.data(withJSONObject:object)
            XCTAssertTrue(try JSONDecoder().decode(BirdSettings.self,from:data).leafPlayEnabled)
            let migrated=try BirdSettings.decode(data)
            XCTAssertTrue(migrated.leafPlayEnabled)
            assertOtherSettingsEqual(migrated,original)
        }
    }

    func testSaveAndReloadRetainsBothValuesAcrossOverwrites() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        for enabled in [false,true,false] {
            var original=configuredSettings();original.leafPlayEnabled=enabled
            try original.save(to:url)
            let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
            XCTAssertEqual(object["leafPlayEnabled"] as? Bool,enabled)
            let saved=try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("legacy.json"))
            XCTAssertEqual(saved.leafPlayEnabled,enabled)
            assertOtherSettingsEqual(saved,original)
        }
    }

    func testLegacyCatalogEnablesLeafPlayAndRetainsCustomization() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let legacy=folder.appendingPathComponent("species.json")
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        try JSONEncoder().encode(catalog).write(to:legacy)
        let migrated=try BirdSettings.load(from:folder.appendingPathComponent("settings.json"),legacyURL:legacy)
        XCTAssertTrue(migrated.leafPlayEnabled)
        XCTAssertEqual(migrated.catalog.species,catalog.species)
    }

    func testInvalidLeafSettingIsRejected() throws {
        let invalidValues:[Any] = ["enabled",1,[],["enabled":true]]
        for invalid in invalidValues {
            var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as! [String:Any]
            object["leafPlayEnabled"]=invalid
            XCTAssertThrowsError(try BirdSettings.decode(JSONSerialization.data(withJSONObject:object)))
        }
    }

    func testRestoreDefaultsCanBeSavedOverDisabledPreference() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        try configuredSettings().save(to:url)
        var draft=try BirdSettings.decode(Data(contentsOf:url))
        XCTAssertFalse(draft.leafPlayEnabled)
        draft=BirdSettings()
        XCTAssertFalse(try BirdSettings.decode(Data(contentsOf:url)).leafPlayEnabled)
        try draft.save(to:url)
        XCTAssertTrue(try BirdSettings.decode(Data(contentsOf:url)).leafPlayEnabled)
    }

    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings()
        settings.leafPlayEnabled=false
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.pointerFollowEnabled=true
        settings.flockPasses=false;settings.socialInteractions=false;settings.perchActions=false
        settings.ambientFrequency = .high
        settings.probabilities.setManualWeight(at:0,to:1234)
        settings.catalog.species[0].speed=1.25

        return settings
    }

    private func assertOtherSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,file:StaticString = #filePath,line:UInt = #line) {
        XCTAssertEqual(actual.hoverDelay,expected.hoverDelay,file:file,line:line)
        XCTAssertEqual(actual.pointerVisits,expected.pointerVisits,file:file,line:line)
        XCTAssertEqual(actual.pointerFollowEnabled,expected.pointerFollowEnabled,file:file,line:line)
        XCTAssertEqual(actual.flockPasses,expected.flockPasses,file:file,line:line)
        XCTAssertEqual(actual.socialInteractions,expected.socialInteractions,file:file,line:line)
        XCTAssertEqual(actual.perchActions,expected.perchActions,file:file,line:line)
        XCTAssertEqual(actual.ambientFrequency,expected.ambientFrequency,file:file,line:line)
        XCTAssertEqual(actual.probabilities,expected.probabilities,file:file,line:line)
        XCTAssertEqual(actual.catalog.species,expected.catalog.species,file:file,line:line)
        XCTAssertEqual(actual.perchDefaultsVersion,expected.perchDefaultsVersion,file:file,line:line)
    }
}
