import XCTest
@testable import BirdingCore

final class PassiveSettingsTests: XCTestCase {
    func testNewSettingsEnableBothPreferencesAndMasters() {
        let settings=BirdSettings()
        XCTAssertTrue(settings.passiveAttentionEnabled)
        XCTAssertTrue(settings.ambientLeafPlayEnabled)
        XCTAssertTrue(settings.perchActions)
        XCTAssertTrue(settings.leafPlayEnabled)
    }

    func testMissingAndNullPreferencesDefaultIndependentlyWithoutResettingOtherEdits() throws {
        let original=configuredSettings()
        for keys in [["passiveAttentionEnabled"],["ambientLeafPlayEnabled"],
                     ["passiveAttentionEnabled","ambientLeafPlayEnabled"]] {
            for nullValue in [false,true] {
                var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
                for key in keys {
                    if nullValue {object[key]=NSNull()}
                    else {object.removeValue(forKey:key)}
                }
                let data=try JSONSerialization.data(withJSONObject:object)
                let direct=try JSONDecoder().decode(BirdSettings.self,from:data)
                let migrated=try BirdSettings.decode(data)
                for value in [direct,migrated] {
                    XCTAssertEqual(value.passiveAttentionEnabled,keys.contains("passiveAttentionEnabled"))
                    XCTAssertEqual(value.ambientLeafPlayEnabled,keys.contains("ambientLeafPlayEnabled"))
                    assertOtherSettingsEqual(value,original)
                }
            }
        }
    }

    func testSaveAndReloadPreserveEveryMasterAndSubordinateCombination() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        for perch in [false,true] {
            for leaf in [false,true] {
                for attention in [false,true] {
                    for automaticLeaf in [false,true] {
                        var original=configuredSettings()
                        original.perchActions=perch;original.leafPlayEnabled=leaf
                        original.passiveAttentionEnabled=attention;original.ambientLeafPlayEnabled=automaticLeaf
                        try original.save(to:url)
                        let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
                        XCTAssertEqual(object["passiveAttentionEnabled"] as? Bool,attention)
                        XCTAssertEqual(object["ambientLeafPlayEnabled"] as? Bool,automaticLeaf)
                        let saved=try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("legacy.json"))
                        XCTAssertEqual(saved.passiveAttentionEnabled,attention)
                        XCTAssertEqual(saved.ambientLeafPlayEnabled,automaticLeaf)
                        assertOtherSettingsEqual(saved,original)
                    }
                }
            }
        }
    }

    func testLegacyCatalogEnablesBothPreferencesAndKeepsCustomization() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let legacy=folder.appendingPathComponent("species.json")
        var catalog=SpeciesCatalog.standard;catalog.species[0].speed=1.25
        try JSONEncoder().encode(catalog).write(to:legacy)
        let settings=try BirdSettings.load(from:folder.appendingPathComponent("settings.json"),legacyURL:legacy)
        XCTAssertTrue(settings.passiveAttentionEnabled)
        XCTAssertTrue(settings.ambientLeafPlayEnabled)
        XCTAssertEqual(settings.catalog.species,catalog.species)
    }

    func testInvalidPreferenceTypesAreRejected() throws {
        for key in ["passiveAttentionEnabled","ambientLeafPlayEnabled"] {
            let invalidValues:[Any] = ["enabled",1,[],["enabled":true]]
            for invalid in invalidValues {
                var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as! [String:Any]
                object[key]=invalid
                let data=try JSONSerialization.data(withJSONObject:object)
                XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data),key)
                XCTAssertThrowsError(try BirdSettings.decode(data),key)
            }
        }
    }

    func testRestoringDefaultsDoesNotChangeStoredPreferencesUntilSaved() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        try configuredSettings().save(to:url)
        var draft=try BirdSettings.decode(Data(contentsOf:url))
        XCTAssertFalse(draft.passiveAttentionEnabled);XCTAssertFalse(draft.ambientLeafPlayEnabled)
        draft=BirdSettings()
        let unchanged=try BirdSettings.decode(Data(contentsOf:url))
        XCTAssertFalse(unchanged.passiveAttentionEnabled);XCTAssertFalse(unchanged.ambientLeafPlayEnabled)
        try draft.save(to:url)
        let restored=try BirdSettings.decode(Data(contentsOf:url))
        XCTAssertTrue(restored.passiveAttentionEnabled);XCTAssertTrue(restored.ambientLeafPlayEnabled)
    }

    func testAttentionCommandsRejectEitherDisabledGateAndPauseWithoutLeasingBirds() {
        let commands:[EngineCommand] = [.attention(.watch,.preview),.attention(.alert,.preview)]
        for perch in [false,true] {
            for attention in [false,true] {
                var settings=BirdSettings();settings.perchActions=perch;settings.passiveAttentionEnabled=attention
                let engine=BehaviorEngine(seed:73,settings:settings)
                engine.populationEnabled=false;engine.ambientEnabled=false
                if !perch || !attention {
                    for command in commands {
                        XCTAssertEqual(engine.handle(command),.rejected(.disabled))
                        XCTAssertEqual(engine.events.last?.type,.rejected)
                        XCTAssertEqual(engine.events.last?.source,.preview)
                        XCTAssertEqual(engine.events.last?.reason,.disabled)
                    }
                }
                engine.handle(.pause(true))
                for command in commands {
                    XCTAssertEqual(engine.handle(command),.rejected(.paused))
                    XCTAssertEqual(engine.events.last?.source,.preview)
                    XCTAssertEqual(engine.events.last?.reason,.paused)
                }
                XCTAssertTrue(engine.birds.isEmpty)
                XCTAssertEqual(engine.activeRunCount,0);XCTAssertEqual(engine.leasedBirdCount,0)
            }
        }
    }

    func testDisablingAutomaticLeafPlayKeepsManualDelayAvailableButRespectsMaster() {
        var settings=BirdSettings();settings.ambientLeafPlayEnabled=false
        let engine=BehaviorEngine(seed:73,settings:settings)
        engine.populationEnabled=false;engine.ambientEnabled=false
        XCTAssertEqual(engine.handle(.releaseLeafAfter(3)),.scheduled)
        XCTAssertTrue(engine.hasLeafPreview);XCTAssertEqual(engine.scenePropCount,0)
        engine.handle(.clearProps)
        settings.leafPlayEnabled=false;engine.applySettings(settings)
        XCTAssertEqual(engine.handle(.releaseLeafAfter(3)),.rejected(.disabled))
        XCTAssertFalse(engine.hasLeafPreview)
    }

    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings()
        settings.passiveAttentionEnabled=false;settings.ambientLeafPlayEnabled=false
        settings.perchActions=false;settings.leafPlayEnabled=false
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.pointerFollowEnabled=true
        settings.flockPasses=false;settings.socialInteractions=false;settings.ambientFrequency = .high
        settings.probabilities.adjust(at:0,to:1234);settings.probabilities.setLocked(true,at:0)
        settings.catalog.species[0].speed=1.25;settings.pendingSpecies=[.nightHeron]
        return settings
    }

    private func assertOtherSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,file:StaticString = #filePath,line:UInt = #line) {
        XCTAssertEqual(actual.perchActions,expected.perchActions,file:file,line:line)
        XCTAssertEqual(actual.leafPlayEnabled,expected.leafPlayEnabled,file:file,line:line)
        XCTAssertEqual(actual.hoverDelay,expected.hoverDelay,file:file,line:line)
        XCTAssertEqual(actual.pointerVisits,expected.pointerVisits,file:file,line:line)
        XCTAssertEqual(actual.pointerFollowEnabled,expected.pointerFollowEnabled,file:file,line:line)
        XCTAssertEqual(actual.flockPasses,expected.flockPasses,file:file,line:line)
        XCTAssertEqual(actual.socialInteractions,expected.socialInteractions,file:file,line:line)
        XCTAssertEqual(actual.ambientFrequency,expected.ambientFrequency,file:file,line:line)
        XCTAssertEqual(actual.probabilities,expected.probabilities,file:file,line:line)
        XCTAssertEqual(actual.catalog.species,expected.catalog.species,file:file,line:line)
        XCTAssertEqual(actual.perchDefaultsVersion,expected.perchDefaultsVersion,file:file,line:line)
        XCTAssertEqual(actual.pendingSpecies,expected.pendingSpecies,file:file,line:line)
    }
}
