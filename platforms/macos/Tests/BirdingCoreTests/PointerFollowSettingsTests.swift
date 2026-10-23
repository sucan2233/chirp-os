import XCTest
@testable import BirdingCore

final class PointerFollowSettingsTests: XCTestCase {
    func testNewSettingsDisablePointerFollowing() {
        XCTAssertFalse(BirdSettings().pointerFollowEnabled)
        XCTAssertTrue(BirdSettings().pointerVisits)
    }

    func testMissingOrNullSettingDefaultsOffWithoutChangingExistingSettings() throws {
        let original=configuredSettings()
        for nullValue in [false,true] {
            var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
            if nullValue {object["pointerFollowEnabled"]=NSNull()}
            else {object.removeValue(forKey:"pointerFollowEnabled")}
            let data=try JSONSerialization.data(withJSONObject:object)
            XCTAssertFalse(try JSONDecoder().decode(BirdSettings.self,from:data).pointerFollowEnabled)
            let migrated=try BirdSettings.decode(data)
            XCTAssertFalse(migrated.pointerFollowEnabled)
            assertOtherSettingsEqual(migrated,original)
        }
    }

    func testSaveAndReloadRetainsFollowingPreferenceWithEitherMasterSwitchState() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        let legacy=folder.appendingPathComponent("legacy.json")
        for visits in [true,false] {
            for follows in [false,true,false] {
                var original=configuredSettings()
                original.pointerVisits=visits;original.pointerFollowEnabled=follows
                try original.save(to:url)
                let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
                XCTAssertEqual(object["pointerFollowEnabled"] as? Bool,follows)
                let saved=try BirdSettings.load(from:url,legacyURL:legacy)
                XCTAssertEqual(saved.pointerFollowEnabled,follows)
                assertOtherSettingsEqual(saved,original)
            }
        }
    }

    func testLegacyCatalogDisablesPointerFollowing() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let legacy=folder.appendingPathComponent("species.json")
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        try JSONEncoder().encode(catalog).write(to:legacy)
        let migrated=try BirdSettings.load(from:folder.appendingPathComponent("settings.json"),legacyURL:legacy)
        XCTAssertFalse(migrated.pointerFollowEnabled)
        XCTAssertTrue(migrated.pointerVisits)
        XCTAssertEqual(migrated.catalog.species,catalog.species)
    }

    func testInvalidPointerFollowSettingIsRejected() throws {
        let invalidValues:[Any] = ["enabled",1,[],["enabled":true]]
        for invalid in invalidValues {
            var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as! [String:Any]
            object["pointerFollowEnabled"]=invalid
            XCTAssertThrowsError(try BirdSettings.decode(JSONSerialization.data(withJSONObject:object)))
        }
    }

    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings()
        settings.pointerFollowEnabled=true
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.flockPasses=false
        settings.socialInteractions=false;settings.perchActions=false;settings.ambientFrequency = .high
        settings.probabilities.adjust(at:0,to:1234)
        settings.probabilities.setLocked(true,at:0)
        settings.catalog.species[0].speed=1.25
        settings.pendingSpecies=[.nightHeron]
        return settings
    }

    private func assertOtherSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,file:StaticString = #filePath,line:UInt = #line) {
        XCTAssertEqual(actual.hoverDelay,expected.hoverDelay,file:file,line:line)
        XCTAssertEqual(actual.pointerVisits,expected.pointerVisits,file:file,line:line)
        XCTAssertEqual(actual.flockPasses,expected.flockPasses,file:file,line:line)
        XCTAssertEqual(actual.socialInteractions,expected.socialInteractions,file:file,line:line)
        XCTAssertEqual(actual.perchActions,expected.perchActions,file:file,line:line)
        XCTAssertEqual(actual.ambientFrequency,expected.ambientFrequency,file:file,line:line)
        XCTAssertEqual(actual.probabilities,expected.probabilities,file:file,line:line)
        XCTAssertEqual(actual.catalog.species,expected.catalog.species,file:file,line:line)
        XCTAssertEqual(actual.perchDefaultsVersion,expected.perchDefaultsVersion,file:file,line:line)
        XCTAssertEqual(actual.pendingSpecies,expected.pendingSpecies,file:file,line:line)
    }
}
