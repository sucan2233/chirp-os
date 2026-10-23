import Foundation
import XCTest
@testable import BirdingCore

final class AllopreeningSettingsTests: XCTestCase {
    func testDefaultsEncodeEnabledWithoutChangingSchema() throws {
        let settings=BirdSettings(),json=try object(settings)
        XCTAssertTrue(settings.allopreeningEnabled)
        XCTAssertEqual(BirdSettings.currentSchemaVersion,1)
        XCTAssertEqual(json["schemaVersion"] as? Int,1)
        XCTAssertEqual(json["allopreeningEnabled"] as? Bool,true)
    }

    func testOldMissingAndNullSettingsDefaultOnWithoutLosingOtherPreferences() throws {
        let original=configuredSettings()
        for version:Int? in [nil,0,1] {
            for value:Any? in [nil,NSNull(),false,true] {
                var json=try object(original)
                json["schemaVersion"]=version
                json["allopreeningEnabled"]=value
                let data=try JSONSerialization.data(withJSONObject:json)
                for decoded in [try JSONDecoder().decode(BirdSettings.self,from:data),try BirdSettings.decode(data)] {
                    XCTAssertEqual(decoded.allopreeningEnabled,(value as? Bool) ?? true)
                    XCTAssertEqual(decoded.schemaVersion,1)
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
            original.socialInteractions=master;original.allopreeningEnabled=child
            try original.save(to:url)
            let reloaded=try BirdSettings.load(from:url,legacyURL:legacy)
            XCTAssertEqual(reloaded.allopreeningEnabled,child)
            XCTAssertEqual(reloaded.socialInteractions,master)
            XCTAssertEqual(try object(reloaded)["allopreeningEnabled"] as? Bool,child)
            try assertOtherSettingsEqual(reloaded,original)
        }
    }

    func testAbsentFileAndLegacyCatalogDefaultOnWithoutWriting() throws {
        let folder=temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json"),legacy=folder.appendingPathComponent("species.json")
        XCTAssertTrue(try BirdSettings.load(from:url,legacyURL:legacy).allopreeningEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        let bytes=try JSONEncoder().encode(catalog);try bytes.write(to:legacy)
        let migrated=try BirdSettings.load(from:url,legacyURL:legacy)
        XCTAssertTrue(migrated.allopreeningEnabled)
        XCTAssertEqual(migrated.catalog.species,catalog.species)
        XCTAssertEqual(try Data(contentsOf:legacy),bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
    }

    func testMalformedSwitchIsRejectedRatherThanCoerced() throws {
        for value:Any in ["true",1,[],["enabled":true]] {
            var json=try object(configuredSettings());json["allopreeningEnabled"]=value
            let data=try JSONSerialization.data(withJSONObject:json)
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data))
            XCTAssertThrowsError(try BirdSettings.decode(data))
        }
    }

    func testMissingChildDefaultsOnWithSavedMasterOffAndBothSocialSiblingsOff() throws {
        var json=try object(configuredSettings());json.removeValue(forKey:"allopreeningEnabled")
        let decoded=try BirdSettings.decode(JSONSerialization.data(withJSONObject:json))
        XCTAssertTrue(decoded.allopreeningEnabled)
        XCTAssertFalse(decoded.socialInteractions)
        XCTAssertFalse(decoded.chaseEnabled)
        XCTAssertFalse(decoded.travelTogetherEnabled)
        XCTAssertEqual(decoded.activityRhythm,.quiet)
    }

    func testResetIsLocalUntilSavedAndFailedSaveKeepsExistingFile() throws {
        let folder=temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        try configuredSettings().save(to:url)
        let bytes=try Data(contentsOf:url)
        var draft=try BirdSettings.decode(bytes)
        XCTAssertFalse(draft.allopreeningEnabled)
        draft=BirdSettings()
        XCTAssertTrue(draft.allopreeningEnabled)
        XCTAssertEqual(try Data(contentsOf:url),bytes)
        var future=try object(draft);future["schemaVersion"]=BirdSettings.currentSchemaVersion+1
        let futureBytes=try JSONSerialization.data(withJSONObject:future);try futureBytes.write(to:url)
        XCTAssertThrowsError(try draft.save(to:url))
        XCTAssertEqual(try Data(contentsOf:url),futureBytes)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AllopreeningSettings-"+UUID().uuidString)
    }
    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings()
        settings.allopreeningEnabled=false;settings.socialInteractions=false;settings.chaseEnabled=false
        settings.travelTogetherEnabled=false
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.pointerFollowEnabled=true;settings.flockPasses=false
        settings.perchActions=false;settings.passiveAttentionEnabled=false;settings.sideHopEnabled=false
        settings.takeoffPreparationEnabled=false;settings.edgePeekEnabled=false
        settings.leafPlayEnabled=false;settings.ambientLeafPlayEnabled=false;settings.visitorMemoryEnabled=false
        settings.ambientFrequency = .high;settings.activityRhythm = .quiet
        settings.probabilities.adjust(at:0,to:1234);settings.probabilities.setLocked(true,at:0)
        settings.catalog.species[0].speed=1.25;settings.pendingSpecies=[.nightHeron]
        return settings
    }
    private func object(_ settings:BirdSettings) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
    }
    private func assertOtherSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,
                                          file:StaticString = #filePath,line:UInt = #line) throws {
        var a=try object(actual),b=try object(expected)
        a.removeValue(forKey:"allopreeningEnabled");b.removeValue(forKey:"allopreeningEnabled")
        XCTAssertTrue(NSDictionary(dictionary:a).isEqual(to:b),file:file,line:line)
    }
}
