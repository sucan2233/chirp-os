import Foundation
import XCTest
@testable import BirdingCore

final class EdgePeekSettingsTests: XCTestCase {
    func testDefaultsEnableEdgePeekWithinSchemaOne() throws {
        let settings=BirdSettings(),object=try settingsObject(settings)
        XCTAssertTrue(settings.edgePeekEnabled)
        XCTAssertEqual(BirdSettings.currentSchemaVersion,2)
        XCTAssertEqual(settings.schemaVersion,BirdSettings.currentSchemaVersion)
        XCTAssertEqual(object["schemaVersion"] as? Int,BirdSettings.currentSchemaVersion)
        XCTAssertEqual(object["edgePeekEnabled"] as? Bool,true)
    }

    func testMissingAndNullMigrateOnWithoutChangingOtherSettings() throws {
        let original=configuredSettings()
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            for nullValue in [false,true] {
                var object=try settingsObject(original)
                if let version {object["schemaVersion"]=version}
                else {object["schemaVersion"]=BirdSettings.currentSchemaVersion}
                if nullValue {object["edgePeekEnabled"]=NSNull()}
                else {object.removeValue(forKey:"edgePeekEnabled")}
                let data=try JSONSerialization.data(withJSONObject:object)
                for migrated in [try JSONDecoder().decode(BirdSettings.self,from:data),try BirdSettings.decode(data)] {
                    XCTAssertTrue(migrated.edgePeekEnabled)
                    XCTAssertEqual(migrated.schemaVersion,BirdSettings.currentSchemaVersion)
                    try assertOtherSettingsEqual(migrated,original)
                }
            }
        }
    }

    func testExplicitFalseSurvivesEverySupportedSchema() throws {
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            var object=try settingsObject(configuredSettings())
            if let version {object["schemaVersion"]=version}
            else {object["schemaVersion"]=BirdSettings.currentSchemaVersion}
            let data=try JSONSerialization.data(withJSONObject:object)
            XCTAssertFalse(try JSONDecoder().decode(BirdSettings.self,from:data).edgePeekEnabled)
            XCTAssertFalse(try BirdSettings.decode(data).edgePeekEnabled)
        }
    }

    func testChildAndMasterPersistIndependentlyAcrossExistingEnums() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json"),legacy=folder.appendingPathComponent("legacy.json")
        for master in [false,true] {
            for enabled in [false,true,false] {
                for rhythm in ActivityRhythmMode.allCases {
                    for frequency in AmbientFrequency.allCases {
                        var original=configuredSettings()
                        original.perchActions=master;original.edgePeekEnabled=enabled
                        original.activityRhythm=rhythm;original.ambientFrequency=frequency
                        let direct=try JSONDecoder().decode(BirdSettings.self,from:JSONEncoder().encode(original))
                        XCTAssertEqual(direct.edgePeekEnabled,enabled)
                        try assertOtherSettingsEqual(direct,original)
                        try original.save(to:url)
                        let saved=try BirdSettings.load(from:url,legacyURL:legacy)
                        let object=try settingsObject(saved)
                        XCTAssertEqual(saved.edgePeekEnabled,enabled)
                        XCTAssertEqual(saved.perchActions,master)
                        XCTAssertEqual(object["edgePeekEnabled"] as? Bool,enabled)
                        XCTAssertEqual(object["schemaVersion"] as? Int,BirdSettings.currentSchemaVersion)
                        XCTAssertEqual(object["activityRhythm"] as? String,rhythm.rawValue)
                        XCTAssertEqual(object["ambientFrequency"] as? String,frequency.rawValue)
                        try assertOtherSettingsEqual(saved,original)
                    }
                }
            }
        }
    }

    func testLegacyCatalogAndMissingFileDefaultOnWithoutWritingSources() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let legacy=folder.appendingPathComponent("species.json"),url=folder.appendingPathComponent("settings.json")
        XCTAssertTrue(try BirdSettings.load(from:url,legacyURL:legacy).edgePeekEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        let bytes=try JSONEncoder().encode(catalog);try bytes.write(to:legacy)
        let migrated=try BirdSettings.load(from:url,legacyURL:legacy)
        XCTAssertTrue(migrated.edgePeekEnabled)
        XCTAssertEqual(migrated.schemaVersion,BirdSettings.currentSchemaVersion)
        XCTAssertEqual(migrated.catalog.species,catalog.species)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        XCTAssertEqual(try Data(contentsOf:legacy),bytes)
    }

    func testInvalidChildValuesFailBothDecoders() throws {
        let invalidValues:[Any] = ["true",0,1,[],["enabled":true]]
        for invalid in invalidValues {
            var object=try settingsObject(configuredSettings());object["edgePeekEnabled"]=invalid
            let bytes=try JSONSerialization.data(withJSONObject:object)
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:bytes))
            XCTAssertThrowsError(try BirdSettings.decode(bytes))
        }
    }

    func testUnsupportedVersionsRemainRejectedAndCannotBeOverwritten() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url=folder.appendingPathComponent("settings.json")
        let invalidVersions:[Any] = [BirdSettings.currentSchemaVersion+1,-1,NSNull(),"1",1.5]
        for invalid in invalidVersions {
            var object=try settingsObject(configuredSettings());object["schemaVersion"]=invalid
            let bytes=try JSONSerialization.data(withJSONObject:object)
            try bytes.write(to:url)
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:bytes))
            XCTAssertThrowsError(try BirdSettings.decode(bytes))
            XCTAssertThrowsError(try BirdSettings().save(to:url))
            XCTAssertEqual(try Data(contentsOf:url),bytes)
        }
    }

    func testRestoreDefaultsDoesNotApplyUntilSaved() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        try configuredSettings().save(to:url)
        let bytes=try Data(contentsOf:url)
        var draft=try BirdSettings.decode(bytes)
        XCTAssertFalse(draft.edgePeekEnabled)
        draft=BirdSettings()
        XCTAssertTrue(draft.edgePeekEnabled)
        XCTAssertEqual(try Data(contentsOf:url),bytes)
        XCTAssertFalse(try BirdSettings.decode(Data(contentsOf:url)).edgePeekEnabled)
        try draft.save(to:url)
        XCTAssertTrue(try BirdSettings.decode(Data(contentsOf:url)).edgePeekEnabled)
    }

    func testBehaviorAndCommandNamesRemainCompatible() throws {
        let existing=["relocate","pointerVisit","flockPass","rest","preen","socialGreeting","sideBySide",
                      "giveWay","pairedTakeoff","leafPlay","watch","alert","sideHop","takeoffPreparation"]
        for name in existing {XCTAssertEqual(BehaviorKind(rawValue:name)?.rawValue,name)}
        XCTAssertEqual(BehaviorKind.edgePeek.rawValue,"edgePeek")
        let commands:[EngineCommand]=[.attention(.watch,.preview),.sideHop(.preview),.prepareTakeoff(.preview),.edgePeek(.preview)]
        for command in commands {
            let original=RecordedCommand(command)
            let decoded=try JSONDecoder().decode(RecordedCommand.self,from:JSONEncoder().encode(original))
            let replay=RecordedCommand(try decoded.validated())
            XCTAssertEqual(replay.name,original.name)
            XCTAssertEqual(replay.source,original.source)
            XCTAssertEqual(replay.action,original.action)
        }
        XCTAssertEqual(RecordedCommand(.edgePeek(.preview)).name,"edgePeek")
        XCTAssertEqual(RecordedCommand(.edgePeek(.preview)).source,"preview")
    }

    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings()
        settings.edgePeekEnabled=false;settings.perchActions=false
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.pointerFollowEnabled=true
        settings.flockPasses=false;settings.socialInteractions=false;settings.passiveAttentionEnabled=false
        settings.sideHopEnabled=false;settings.takeoffPreparationEnabled=false
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
        var actualObject=try settingsObject(actual),expectedObject=try settingsObject(expected)
        actualObject.removeValue(forKey:"edgePeekEnabled");expectedObject.removeValue(forKey:"edgePeekEnabled")
        XCTAssertTrue(NSDictionary(dictionary:actualObject).isEqual(to:expectedObject),file:file,line:line)
    }
}
