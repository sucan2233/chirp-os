import Foundation
import XCTest
import BirdingCore

final class VisitorMemorySettingsTests: XCTestCase {
    func testNewSettingsEnableMemoryWithoutChangingSchemaVersion() throws {
        let settings=BirdSettings()
        XCTAssertTrue(settings.visitorMemoryEnabled)
        XCTAssertEqual(BirdSettings.currentSchemaVersion,2)
        XCTAssertEqual(settings.schemaVersion,BirdSettings.currentSchemaVersion)
        let object=try settingsObject(settings)
        XCTAssertEqual(object["schemaVersion"] as? Int,BirdSettings.currentSchemaVersion)
        XCTAssertEqual(object["visitorMemoryEnabled"] as? Bool,true)
    }

    func testMissingOrNullMemoryMigratesOnForEverySupportedSchema() throws {
        let original=configuredSettings()
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            for nullValue in [false,true] {
                var object=try settingsObject(original)
                if let version {object["schemaVersion"]=version}
                else {object["schemaVersion"]=BirdSettings.currentSchemaVersion}
                if nullValue {object["visitorMemoryEnabled"]=NSNull()}
                else {object.removeValue(forKey:"visitorMemoryEnabled")}
                let data=try JSONSerialization.data(withJSONObject:object)
                for migrated in [try JSONDecoder().decode(BirdSettings.self,from:data),try BirdSettings.decode(data)] {
                    XCTAssertTrue(migrated.visitorMemoryEnabled)
                    XCTAssertEqual(migrated.schemaVersion,BirdSettings.currentSchemaVersion)
                    try assertOtherSettingsEqual(migrated,original)
                }
            }
        }
    }

    func testMemoryAndPerchMasterRoundTripIndependently() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        for master in [false,true] {
            for enabled in [false,true,false] {
                var original=configuredSettings()
                original.perchActions=master;original.visitorMemoryEnabled=enabled
                let data=try JSONEncoder().encode(original)
                let direct=try JSONDecoder().decode(BirdSettings.self,from:data)
                XCTAssertEqual(direct.visitorMemoryEnabled,enabled)
                try assertOtherSettingsEqual(direct,original)
                try original.save(to:url)
                let saved=try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("legacy.json"))
                let object=try settingsObject(saved)
                XCTAssertEqual(saved.visitorMemoryEnabled,enabled)
                XCTAssertEqual(saved.perchActions,master)
                XCTAssertEqual(object["visitorMemoryEnabled"] as? Bool,enabled)
                XCTAssertEqual(object["schemaVersion"] as? Int,BirdSettings.currentSchemaVersion)
                try assertOtherSettingsEqual(saved,original)
            }
        }
    }

    func testLegacyCatalogEnablesMemoryWithoutWritingSources() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let legacy=folder.appendingPathComponent("species.json"),url=folder.appendingPathComponent("settings.json")
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        let data=try JSONEncoder().encode(catalog)
        try data.write(to:legacy)
        let migrated=try BirdSettings.load(from:url,legacyURL:legacy)
        XCTAssertTrue(migrated.visitorMemoryEnabled)
        XCTAssertEqual(migrated.catalog.species,catalog.species)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        XCTAssertEqual(try Data(contentsOf:legacy),data)
    }

    func testInvalidMemoryValuesAreRejectedByBothDecoders() throws {
        let invalidValues:[Any] = ["true",0,1,[],["enabled":true]]
        for value in invalidValues {
            var object=try settingsObject(configuredSettings());object["visitorMemoryEnabled"]=value
            let data=try JSONSerialization.data(withJSONObject:object)
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data))
            XCTAssertThrowsError(try BirdSettings.decode(data))
        }
    }

    func testRestoreDefaultsOnlyChangesMemoryAfterSave() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        try configuredSettings().save(to:url)
        var draft=try BirdSettings.decode(Data(contentsOf:url))
        XCTAssertFalse(draft.visitorMemoryEnabled)
        draft=BirdSettings()
        XCTAssertTrue(draft.visitorMemoryEnabled)
        XCTAssertFalse(try BirdSettings.decode(Data(contentsOf:url)).visitorMemoryEnabled)
        try draft.save(to:url)
        XCTAssertTrue(try BirdSettings.decode(Data(contentsOf:url)).visitorMemoryEnabled)
    }

    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings()
        settings.visitorMemoryEnabled=false
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.pointerFollowEnabled=true
        settings.flockPasses=false;settings.socialInteractions=false;settings.perchActions=false
        settings.passiveAttentionEnabled=false;settings.sideHopEnabled=false;settings.takeoffPreparationEnabled=false
        settings.leafPlayEnabled=false;settings.ambientLeafPlayEnabled=false;settings.ambientFrequency = .high
        settings.probabilities.setManualWeight(at:0,to:1234)
        settings.catalog.species[0].speed=1.25
        return settings
    }

    private func settingsObject(_ settings:BirdSettings) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
    }

    // Compare the entire remaining payload so additive preferences cannot hide
    // accidental changes to species, probability locks or independent switches.
    private func assertOtherSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,
                                          file:StaticString = #filePath,line:UInt = #line) throws {
        var actualObject=try settingsObject(actual),expectedObject=try settingsObject(expected)
        actualObject.removeValue(forKey:"visitorMemoryEnabled");expectedObject.removeValue(forKey:"visitorMemoryEnabled")
        XCTAssertTrue(NSDictionary(dictionary:actualObject).isEqual(to:expectedObject),file:file,line:line)
    }
}
