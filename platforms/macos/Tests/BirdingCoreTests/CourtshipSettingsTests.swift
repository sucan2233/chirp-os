import XCTest
@testable import BirdingCore

final class CourtshipSettingsTests:XCTestCase {
    func testLegacyMissingSwitchDefaultsTrueWithCompletePreferencesOnBothDecodePaths() throws {
        XCTAssertTrue(BirdSettings().courtshipEnabled)
        var original=BirdSettings();original.courtshipEnabled=false;original.socialInteractions=false
        original.hoverDelay=0.3;original.pointerFollowEnabled=true;original.visitorGiftsEnabled=true
        original.visitorMemoryEnabled=false;original.activityRhythm = .quiet
        original.leafCarryEnabled=false;original.bathEnabled=false;original.insectCatchEnabled=false
        original.probabilities.setManualWeight(at:0,to:1234)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        raw.removeValue(forKey:"courtshipEnabled")
        var expected=original;expected.courtshipEnabled=true
        var migrated=expected
        let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            raw["schemaVersion"]=version;let data=try JSONSerialization.data(withJSONObject:raw)
            // Public decode runs existing catalog migrations; Codable alone does not.
            for (value,wanted) in [(try BirdSettings.decode(data),migrated),
                                   (try JSONDecoder().decode(BirdSettings.self,from:data),expected)] {
                XCTAssertEqual(try encoder.encode(value),try encoder.encode(wanted))
            }
        }
    }

    func testSwitchPersistsWithoutRuntimePairOrGenderResourcesAndMalformedOrFutureSettingsReject() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("settings.json")
        for enabled in [false,true] {
            var s=BirdSettings();s.courtshipEnabled=enabled;try s.save(to:file)
            let restored=try BirdSettings.load(from:file,legacyURL:folder.appendingPathComponent("absent"))
            XCTAssertEqual(restored.courtshipEnabled,enabled)
            let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(restored)) as? [String:Any])
            for key in ["courtshipRole","courtshipPair","pairs","mates","gender","breedingResources","runs","leases"] {XCTAssertNil(raw[key],key)}
        }
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as? [String:Any])
        for bad:Any in ["true",0,1,[],["enabled":true]] {
            raw["courtshipEnabled"]=bad;let bytes=try JSONSerialization.data(withJSONObject:raw)
            XCTAssertThrowsError(try BirdSettings.decode(bytes));XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:bytes))
        }
        raw["courtshipEnabled"]=true;raw["schemaVersion"]=BirdSettings.currentSchemaVersion+1
        let future=try JSONSerialization.data(withJSONObject:raw);try future.write(to:file)
        XCTAssertThrowsError(try BirdSettings.load(from:file,legacyURL:folder.appendingPathComponent("absent")))
        XCTAssertThrowsError(try BirdSettings().save(to:file));XCTAssertEqual(try Data(contentsOf:file),future)
    }

    func testChildAndSocialMasterGateEverySourceAndQuietOnlyClosesAutomatic() {
        for child in [false,true] {for master in [false,true] {for mode:ActivityRhythmMode in [.quiet,.steady] {
            var s=BirdSettings();s.courtshipEnabled=child;s.socialInteractions=master;s.activityRhythm=mode
            for source:BehaviorSource in [.user,.preview,.automatic] {
                XCTAssertEqual(BehaviorDefinitions.definition(for:.courtshipDisplay).isEnabled(settings:s,source:source),
                    child && master && (source != .automatic || mode != .quiet))
                var toggled=s;toggled.courtshipEnabled = !child
                for definition in BehaviorDefinitions.all where definition.kind != .courtshipDisplay {
                    XCTAssertEqual(definition.isEnabled(settings:s,source:source),definition.isEnabled(settings:toggled,source:source))
                }
            }
        }}}
    }
}
