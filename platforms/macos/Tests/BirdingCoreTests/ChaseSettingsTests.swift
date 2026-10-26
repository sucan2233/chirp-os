import Foundation
import XCTest
@testable import BirdingCore

final class ChaseSettingsTests: XCTestCase {
    func testDefaultIsEncodedInSchemaOne() throws {
        let settings=BirdSettings(),object=try settingsObject(settings)
        XCTAssertTrue(settings.chaseEnabled)
        XCTAssertEqual(BirdSettings.currentSchemaVersion,2)
        XCTAssertEqual(object["schemaVersion"] as? Int,BirdSettings.currentSchemaVersion)
        XCTAssertEqual(object["chaseEnabled"] as? Bool,true)
    }

    func testMissingAndNullMigrateOnAndExplicitFalseSurvives() throws {
        let original=configuredSettings()
        let legacyValues:[Any?]=[nil,NSNull(),false]
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            for value in legacyValues {
                var object=try settingsObject(original)
                if let version {object["schemaVersion"]=version}
                else {object["schemaVersion"]=BirdSettings.currentSchemaVersion}
                if let value {object["chaseEnabled"]=value}
                else {object.removeValue(forKey:"chaseEnabled")}
                let bytes=try JSONSerialization.data(withJSONObject:object)
                let expected=(value as? Bool) ?? true
                for decoded in [try JSONDecoder().decode(BirdSettings.self,from:bytes),try BirdSettings.decode(bytes)] {
                    XCTAssertEqual(decoded.chaseEnabled,expected)
                    XCTAssertEqual(decoded.schemaVersion,BirdSettings.currentSchemaVersion)
                    try assertOtherSettingsEqual(decoded,original)
                }
            }
        }
    }

    func testMasterAndChildPersistIndependentlyAcrossRhythmsAndFrequencies() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json"),legacy=folder.appendingPathComponent("legacy.json")
        for master in [false,true] {
            for child in [true,false] {
                for rhythm in ActivityRhythmMode.allCases {
                    for frequency in AmbientFrequency.allCases {
                        var original=configuredSettings()
                        original.socialInteractions=master;original.chaseEnabled=child
                        original.activityRhythm=rhythm;original.ambientFrequency=frequency
                        try original.save(to:url)
                        let saved=try BirdSettings.load(from:url,legacyURL:legacy)
                        let object=try settingsObject(saved)
                        XCTAssertEqual(saved.chaseEnabled,child)
                        XCTAssertEqual(saved.socialInteractions,master)
                        XCTAssertEqual(object["chaseEnabled"] as? Bool,child)
                        try assertOtherSettingsEqual(saved,original)
                    }
                }
            }
        }
    }

    func testLegacyCatalogAndAbsentFileEnableChaseWithoutWriting() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json"),legacy=folder.appendingPathComponent("species.json")
        XCTAssertTrue(try BirdSettings.load(from:url,legacyURL:legacy).chaseEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        let bytes=try JSONEncoder().encode(catalog);try bytes.write(to:legacy)
        let migrated=try BirdSettings.load(from:url,legacyURL:legacy)
        XCTAssertTrue(migrated.chaseEnabled)
        XCTAssertEqual(migrated.catalog.species,catalog.species)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        XCTAssertEqual(try Data(contentsOf:legacy),bytes)
    }

    func testInvalidChildTypesAreRejectedByBothDecoders() throws {
        let invalid:[Any]=["true",0,1,[],["enabled":true]]
        for value in invalid {
            var object=try settingsObject(configuredSettings());object["chaseEnabled"]=value
            let bytes=try JSONSerialization.data(withJSONObject:object)
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:bytes))
            XCTAssertThrowsError(try BirdSettings.decode(bytes))
        }
    }

    func testDefaultsStayInDraftUntilSavedAndFutureFileIsProtected() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        try configuredSettings().save(to:url)
        let savedBytes=try Data(contentsOf:url)
        var draft=try BirdSettings.decode(savedBytes)
        XCTAssertFalse(draft.chaseEnabled)
        draft=BirdSettings()
        XCTAssertTrue(draft.chaseEnabled)
        XCTAssertEqual(try Data(contentsOf:url),savedBytes)
        try draft.save(to:url)
        XCTAssertTrue(try BirdSettings.decode(Data(contentsOf:url)).chaseEnabled)
        var future=try settingsObject(draft);future["schemaVersion"]=BirdSettings.currentSchemaVersion+1
        let futureBytes=try JSONSerialization.data(withJSONObject:future);try futureBytes.write(to:url)
        XCTAssertThrowsError(try draft.save(to:url))
        XCTAssertEqual(try Data(contentsOf:url),futureBytes)
    }

    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings()
        settings.chaseEnabled=false;settings.socialInteractions=false
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.pointerFollowEnabled=true;settings.flockPasses=false
        settings.perchActions=false;settings.passiveAttentionEnabled=false;settings.sideHopEnabled=false
        settings.takeoffPreparationEnabled=false;settings.edgePeekEnabled=false
        settings.leafPlayEnabled=false;settings.ambientLeafPlayEnabled=false;settings.visitorMemoryEnabled=false
        settings.ambientFrequency = .high;settings.activityRhythm = .quiet
        settings.probabilities.setManualWeight(at:0,to:1234)
        settings.catalog.species[0].speed=1.25
        return settings
    }

    private func settingsObject(_ settings:BirdSettings) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
    }

    private func assertOtherSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,
                                          file:StaticString = #filePath,line:UInt = #line) throws {
        var a=try settingsObject(actual),b=try settingsObject(expected)
        a.removeValue(forKey:"chaseEnabled");b.removeValue(forKey:"chaseEnabled")
        XCTAssertTrue(NSDictionary(dictionary:a).isEqual(to:b),file:file,line:line)
    }
}
