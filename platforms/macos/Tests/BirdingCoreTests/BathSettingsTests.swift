import XCTest
@testable import BirdingCore

final class BathSettingsTests:XCTestCase {
    private func configured(_ enabled:Bool)->BirdSettings {
        var value=BirdSettings();value.bathEnabled=enabled;value.hoverDelay=0.25
        value.pointerVisits=false;value.pointerFollowEnabled=true;value.foodTrayEnabled=false
        value.fixedPerchesEnabled=false;value.activityRhythm = .quiet;value.ambientFrequency = .high
        value.probabilities.setManualWeight(at:0,to:1234)
        return value
    }

    func testBathDefaultsTrueWithoutChangingTheSettingsSchemaOrAnyExistingPreference() throws {
        XCTAssertTrue(BirdSettings().bathEnabled);XCTAssertEqual(BirdSettings.currentSchemaVersion,3)
        let original=configured(false)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        raw.removeValue(forKey:"bathEnabled")
        for schema:Int? in [BirdSettings.currentSchemaVersion] {
            raw["schemaVersion"]=schema
            let bytes=try JSONSerialization.data(withJSONObject:raw)
            for restored in [try BirdSettings.decode(bytes),try JSONDecoder().decode(BirdSettings.self,from:bytes)] {
                XCTAssertTrue(restored.bathEnabled);XCTAssertEqual(restored.schemaVersion,BirdSettings.currentSchemaVersion)
                XCTAssertEqual(restored.hoverDelay,0.25);XCTAssertFalse(restored.pointerVisits)
                XCTAssertTrue(restored.pointerFollowEnabled);XCTAssertFalse(restored.foodTrayEnabled)
                XCTAssertFalse(restored.fixedPerchesEnabled);XCTAssertEqual(restored.activityRhythm,.quiet)
                XCTAssertEqual(restored.ambientFrequency,.high)
                XCTAssertEqual(restored.catalog.species,original.catalog.species)
                XCTAssertEqual(restored.probabilities,original.probabilities)
                XCTAssertEqual(restored.fixedPerches,original.fixedPerches)
            }
        }
    }

    func testExplicitBathSettingSurvivesRepeatedDecodeAndDiskSave() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        for enabled in [false,true] {
            let original=configured(enabled),url=folder.appendingPathComponent("settings.json")
            try original.save(to:url)
            let loaded=try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("absent.json"))
            let restored=try BirdSettings.decode(JSONEncoder().encode(loaded))
            XCTAssertEqual(restored.bathEnabled,enabled);XCTAssertEqual(restored.hoverDelay,original.hoverDelay)
            XCTAssertEqual(restored.probabilities,original.probabilities)
            XCTAssertEqual(restored.pointerFollowEnabled,original.pointerFollowEnabled)
            XCTAssertEqual(restored.foodTrayEnabled,original.foodTrayEnabled)
        }
    }

    func testMalformedBathSettingIsRejectedAndBathSwitchDoesNotGateOldBehaviors() throws {
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(configured(true))) as? [String:Any])
        for bad:Any in ["false",0,1,[],["enabled":true]] {
            raw["bathEnabled"]=bad
            let data=try JSONSerialization.data(withJSONObject:raw)
            XCTAssertThrowsError(try BirdSettings.decode(data))
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data))
        }
        for enabled in [false,true] {
            for rhythm:ActivityRhythmMode in [.steady,.quiet] {
                var settings=BirdSettings();settings.bathEnabled=enabled;settings.activityRhythm=rhythm
                var other=settings;other.bathEnabled = !enabled
                for source:BehaviorSource in [.automatic,.preview,.user] {
                    XCTAssertEqual(BehaviorDefinitions.definition(for:.bathVisit).isEnabled(settings:settings,source:source),
                        enabled && (source != .automatic || rhythm != .quiet))
                    for definition in BehaviorDefinitions.all where definition.kind != .bathVisit {
                        XCTAssertEqual(definition.isEnabled(settings:settings,source:source),
                            definition.isEnabled(settings:other,source:source),definition.kind.rawValue)
                    }
                }
            }
        }
    }
}
