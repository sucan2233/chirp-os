import Foundation
import XCTest
@testable import BirdingCore

final class TravelTogetherSettingsTests: XCTestCase {
    func testDefaultsEncodeEnabledWithoutChangingSchema() throws {
        let settings=BirdSettings(),json=try object(settings)
        XCTAssertTrue(settings.travelTogetherEnabled)
        XCTAssertEqual(BirdSettings.currentSchemaVersion,3)
        XCTAssertEqual(json["schemaVersion"] as? Int,BirdSettings.currentSchemaVersion)
        XCTAssertEqual(json["travelTogetherEnabled"] as? Bool,true)
    }

    func testOldMissingAndNullSettingsDefaultOnWithoutLosingOtherPreferences() throws {
        let original=configuredSettings()
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            for value:Any? in [nil,NSNull(),false] {
                var json=try object(original)
                json["schemaVersion"]=version
                json["travelTogetherEnabled"]=value
                let data=try JSONSerialization.data(withJSONObject:json)
                for decoded in [try JSONDecoder().decode(BirdSettings.self,from:data),try BirdSettings.decode(data)] {
                    XCTAssertEqual(decoded.travelTogetherEnabled,(value as? Bool) ?? true)
                    XCTAssertEqual(decoded.schemaVersion,BirdSettings.currentSchemaVersion)
                    try assertOtherSettingsEqual(decoded,original)
                }
            }
        }
    }

    func testParentAndChildSaveIndependentlyWithQuietAndCustomSettings() throws {
        let folder=temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json"),legacy=folder.appendingPathComponent("legacy.json")
        // The parent/child states matter; a rhythm/frequency Cartesian product adds no settings coverage.
        for (master,child) in [(false,true),(true,false),(false,false),(true,true)] {
            var original=configuredSettings()
            original.socialInteractions=master;original.travelTogetherEnabled=child
            try original.save(to:url)
            let reloaded=try BirdSettings.load(from:url,legacyURL:legacy)
            XCTAssertEqual(reloaded.travelTogetherEnabled,child)
            XCTAssertEqual(reloaded.socialInteractions,master)
            XCTAssertEqual(try object(reloaded)["travelTogetherEnabled"] as? Bool,child)
            try assertOtherSettingsEqual(reloaded,original)
        }
    }

    func testAbsentFileAndLegacyCatalogDefaultOnWithoutWriting() throws {
        let folder=temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json"),legacy=folder.appendingPathComponent("species.json")
        XCTAssertTrue(try BirdSettings.load(from:url,legacyURL:legacy).travelTogetherEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        let bytes=try JSONEncoder().encode(catalog);try bytes.write(to:legacy)
        let migrated=try BirdSettings.load(from:url,legacyURL:legacy)
        XCTAssertTrue(migrated.travelTogetherEnabled)
        XCTAssertEqual(migrated.catalog.species,catalog.species)
        XCTAssertEqual(try Data(contentsOf:legacy),bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
    }

    func testMalformedSwitchIsRejectedRatherThanCoerced() throws {
        for value:Any in ["true",1,[],["enabled":true]] {
            var json=try object(configuredSettings());json["travelTogetherEnabled"]=value
            let data=try JSONSerialization.data(withJSONObject:json)
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data))
            XCTAssertThrowsError(try BirdSettings.decode(data))
        }
    }

    func testResetIsLocalUntilSavedAndFailedSaveKeepsExistingFile() throws {
        let folder=temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        try configuredSettings().save(to:url)
        let bytes=try Data(contentsOf:url)
        var draft=try BirdSettings.decode(bytes)
        XCTAssertFalse(draft.travelTogetherEnabled)
        draft=BirdSettings()
        XCTAssertTrue(draft.travelTogetherEnabled)
        XCTAssertEqual(try Data(contentsOf:url),bytes)
        var future=try object(draft);future["schemaVersion"]=BirdSettings.currentSchemaVersion+1
        let futureBytes=try JSONSerialization.data(withJSONObject:future);try futureBytes.write(to:url)
        XCTAssertThrowsError(try draft.save(to:url))
        XCTAssertEqual(try Data(contentsOf:url),futureBytes)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TravelTogetherSettings-"+UUID().uuidString)
    }
    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings()
        settings.travelTogetherEnabled=false;settings.socialInteractions=false;settings.chaseEnabled=false
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.pointerFollowEnabled=true;settings.flockPasses=false
        settings.perchActions=false;settings.passiveAttentionEnabled=false;settings.sideHopEnabled=false
        settings.takeoffPreparationEnabled=false;settings.edgePeekEnabled=false
        settings.leafPlayEnabled=false;settings.ambientLeafPlayEnabled=false;settings.visitorMemoryEnabled=false
        settings.ambientFrequency = .high;settings.activityRhythm = .quiet
        settings.probabilities.setManualWeight(at:0,to:1234)
        settings.catalog.species[0].speed=1.25
        return settings
    }
    private func object(_ settings:BirdSettings) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
    }
    private func assertOtherSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,
                                          file:StaticString = #filePath,line:UInt = #line) throws {
        var a=try object(actual),b=try object(expected)
        a.removeValue(forKey:"travelTogetherEnabled");b.removeValue(forKey:"travelTogetherEnabled")
        XCTAssertTrue(NSDictionary(dictionary:a).isEqual(to:b),file:file,line:line)
    }
}
