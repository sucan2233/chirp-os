import XCTest
@testable import BirdingCore

final class VisitorGiftSettingsTests:XCTestCase {
    func testLegacySettingsDefaultGiftsOffWithoutChangingAnyExistingPreference() throws {
        XCTAssertFalse(BirdSettings().visitorGiftsEnabled)
        var original=BirdSettings();original.visitorGiftsEnabled=true
        original.visitorMemoryEnabled=false;original.fixedPerchesEnabled=false
        original.leafCarryEnabled=false;original.insectCatchEnabled=false;original.bathEnabled=false
        original.foodTrayEnabled=false;original.pointerFollowEnabled=true;original.hoverDelay=0.3
        original.activityRhythm = .quiet;original.ambientFrequency = .high
        original.probabilities.setManualWeight(at:0,to:1234)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        raw.removeValue(forKey:"visitorGiftsEnabled")
        var expected=original;expected.visitorGiftsEnabled=false
        // The public migration API canonicalizes an absent pending list to [];
        // plain Codable decoding preserves nil. Compare every field on both paths.
        var migratedExpected=expected
        let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            raw["schemaVersion"]=version
            let data=try JSONSerialization.data(withJSONObject:raw)
            for (value,expectedValue) in [(try BirdSettings.decode(data),migratedExpected),
                                        (try JSONDecoder().decode(BirdSettings.self,from:data),expected)] {
                XCTAssertFalse(value.visitorGiftsEnabled)
                XCTAssertEqual(value.schemaVersion,BirdSettings.currentSchemaVersion)
                XCTAssertEqual(try encoder.encode(value),try encoder.encode(expectedValue))
            }
        }
    }

    func testExplicitPreferenceRoundTripsButAuthorizationAndObjectsAreNeverSettings() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        for enabled in [false,true] {
            var settings=BirdSettings();settings.visitorGiftsEnabled=enabled
            let file=folder.appendingPathComponent("settings.json")
            try settings.save(to:file)
            let restored=try BirdSettings.load(from:file,legacyURL:folder.appendingPathComponent("missing.json"))
            XCTAssertEqual(restored.visitorGiftsEnabled,enabled)
            let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(restored)) as? [String:Any])
            XCTAssertEqual(raw["visitorGiftsEnabled"] as? Bool,enabled)
            for key in ["giftAuthorizationRequest","giftAuthorization","giftToken","giftLedger","pendingGift",
                        "carriedObjects","sceneFocus","runs","leases"] {XCTAssertNil(raw[key],key)}
        }
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as? [String:Any])
        for invalid:Any in ["false",0,1,[],["enabled":true]] {
            raw["visitorGiftsEnabled"]=invalid
            let data=try JSONSerialization.data(withJSONObject:raw)
            XCTAssertThrowsError(try BirdSettings.decode(data))
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data))
        }
    }

    func testGiftNeedsAllThreeSwitchesAndQuietOnlyClosesAutomaticEncounters() {
        for gift in [false,true] {
            for memory in [false,true] {
                for perch in [false,true] {
                    for rhythm:ActivityRhythmMode in [.steady,.quiet] {
                        var settings=BirdSettings();settings.visitorGiftsEnabled=gift
                        settings.visitorMemoryEnabled=memory;settings.fixedPerchesEnabled=perch
                        settings.activityRhythm=rhythm
                        for source:BehaviorSource in [.preview,.automatic,.user] {
                            XCTAssertEqual(BehaviorDefinitions.definition(for:.visitorGift).isEnabled(settings:settings,source:source),
                                gift && memory && perch && (source != .automatic || rhythm != .quiet))
                            var toggled=settings;toggled.visitorGiftsEnabled = !gift
                            for definition in BehaviorDefinitions.all where definition.kind != .visitorGift {
                                XCTAssertEqual(definition.isEnabled(settings:settings,source:source),
                                    definition.isEnabled(settings:toggled,source:source),definition.kind.rawValue)
                            }
                        }
                    }
                }
            }
        }
    }
}
