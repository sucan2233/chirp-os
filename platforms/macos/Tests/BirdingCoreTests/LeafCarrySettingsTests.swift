import XCTest
@testable import BirdingCore

final class LeafCarrySettingsTests:XCTestCase {
    private func configured(_ enabled:Bool)->BirdSettings {
        var value=BirdSettings();value.leafCarryEnabled=enabled
        value.hoverDelay=0.3;value.pointerFollowEnabled=true
        value.pointerVisits=false;value.leafPlayEnabled=false;value.ambientLeafPlayEnabled=false
        value.bathEnabled=false;value.foodTrayEnabled=false;value.fixedPerchesEnabled=false
        value.activityRhythm = .quiet;value.ambientFrequency = .high
        value.probabilities.setManualWeight(at:0,to:1234)
        return value
    }

    func testMissingLeafCarrySettingDefaultsTrueWhileOldPreferencesAndSchemaRemainIntact() throws {
        XCTAssertTrue(BirdSettings().leafCarryEnabled)
        XCTAssertEqual(BirdSettings.currentSchemaVersion,2)
        let original=configured(false)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        raw.removeValue(forKey:"leafCarryEnabled")
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            raw["schemaVersion"]=version
            let data=try JSONSerialization.data(withJSONObject:raw)
            for restored in [try BirdSettings.decode(data),try JSONDecoder().decode(BirdSettings.self,from:data)] {
                XCTAssertTrue(restored.leafCarryEnabled);XCTAssertEqual(restored.schemaVersion,BirdSettings.currentSchemaVersion)
                XCTAssertEqual(restored.hoverDelay,original.hoverDelay)
                XCTAssertEqual(restored.pointerFollowEnabled,original.pointerFollowEnabled)
                XCTAssertEqual(restored.pointerVisits,original.pointerVisits)
                XCTAssertEqual(restored.leafPlayEnabled,original.leafPlayEnabled)
                XCTAssertEqual(restored.ambientLeafPlayEnabled,original.ambientLeafPlayEnabled)
                XCTAssertEqual(restored.bathEnabled,original.bathEnabled)
                XCTAssertEqual(restored.foodTrayEnabled,original.foodTrayEnabled)
                XCTAssertEqual(restored.fixedPerchesEnabled,original.fixedPerchesEnabled)
                XCTAssertEqual(restored.activityRhythm,original.activityRhythm)
                XCTAssertEqual(restored.ambientFrequency,original.ambientFrequency)
                XCTAssertEqual(restored.catalog.species,original.catalog.species)
                XCTAssertEqual(restored.probabilities,original.probabilities)
            }
        }
    }

    func testExplicitLeafCarryPreferenceRoundTripsOnDiskAndNeverPersistsSceneState() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        for enabled in [false,true] {
            let original=configured(enabled),file=folder.appendingPathComponent("settings.json")
            try original.save(to:file)
            let loaded=try BirdSettings.load(from:file,legacyURL:folder.appendingPathComponent("absent.json"))
            let bytes=try JSONEncoder().encode(loaded)
            let restored=try BirdSettings.decode(bytes)
            XCTAssertEqual(restored.leafCarryEnabled,enabled)
            XCTAssertEqual(restored.probabilities,original.probabilities)
            XCTAssertEqual(restored.hoverDelay,original.hoverDelay)
            XCTAssertEqual(restored.pointerFollowEnabled,original.pointerFollowEnabled)
            let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
            XCTAssertEqual(raw["leafCarryEnabled"] as? Bool,enabled)
            for transient in ["carriedObjects","carryLeaf","sceneFocus","runs","leases","hasCarryLeafPlacement"] {
                XCTAssertNil(raw[transient],transient)
            }
        }
    }

    func testMalformedSwitchRejectsAndCarryDoesNotDependOnDynamicLeafOrOtherSceneSwitches() throws {
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(configured(true))) as? [String:Any])
        for invalid:Any in ["false",0,1,[],["enabled":true]] {
            raw["leafCarryEnabled"]=invalid
            let bytes=try JSONSerialization.data(withJSONObject:raw)
            XCTAssertThrowsError(try BirdSettings.decode(bytes))
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:bytes))
        }
        for enabled in [false,true] {
            for others in [false,true] {
                for rhythm:ActivityRhythmMode in [.steady,.quiet] {
                    var settings=configured(enabled);settings.activityRhythm=rhythm
                    settings.leafPlayEnabled=others;settings.ambientLeafPlayEnabled=others
                    settings.bathEnabled=others;settings.foodTrayEnabled=others;settings.fixedPerchesEnabled=others
                    settings.perchActions=others;settings.socialInteractions=others
                    var toggled=settings;toggled.leafCarryEnabled = !enabled
                    for source:BehaviorSource in [.automatic,.preview,.user] {
                        XCTAssertEqual(BehaviorDefinitions.definition(for:.leafCarry).isEnabled(settings:settings,source:source),
                            enabled && (source != .automatic || rhythm != .quiet))
                        for definition in BehaviorDefinitions.all where definition.kind != .leafCarry {
                            XCTAssertEqual(definition.isEnabled(settings:settings,source:source),
                                definition.isEnabled(settings:toggled,source:source),definition.kind.rawValue)
                        }
                    }
                }
            }
        }
    }
}
