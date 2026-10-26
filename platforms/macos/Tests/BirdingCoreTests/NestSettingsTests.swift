import XCTest
@testable import BirdingCore

final class NestSettingsTests:XCTestCase {
    func testMissingSwitchDefaultsTrueWithoutReplacingAnyExistingPreferencesOnEitherDecodePath() throws {
        XCTAssertTrue(BirdSettings().nestBuildingEnabled)
        var old=BirdSettings();old.nestBuildingEnabled=false;old.socialInteractions=false
        old.hoverDelay=0.3;old.pointerFollowEnabled=true;old.visitorGiftsEnabled=true
        old.visitorMemoryEnabled=false;old.activityRhythm = .quiet
        old.leafCarryEnabled=false;old.bathEnabled=false;old.insectCatchEnabled=false;old.courtshipEnabled=false
        old.probabilities.setManualWeight(at:0,to:1234)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as? [String:Any])
        raw.removeValue(forKey:"nestBuildingEnabled")
        var expected=old;expected.nestBuildingEnabled=true
        var migrated=expected
        let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            raw["schemaVersion"]=version;let data=try JSONSerialization.data(withJSONObject:raw)
            XCTAssertEqual(try encoder.encode(BirdSettings.decode(data)),try encoder.encode(migrated))
            XCTAssertEqual(try encoder.encode(JSONDecoder().decode(BirdSettings.self,from:data)),try encoder.encode(expected))
        }
    }

    func testSwitchSavesBothValuesButNoNestMaterialsOrProgressAndRejectsMalformedOrFutureSettings() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("settings.json")
        for enabled in [false,true] {
            var settings=BirdSettings();settings.nestBuildingEnabled=enabled;try settings.save(to:file)
            let restored=try BirdSettings.load(from:file,legacyURL:folder.appendingPathComponent("absent"))
            XCTAssertEqual(restored.nestBuildingEnabled,enabled)
            let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(restored)) as? [String:Any])
            for key in ["nest","nests","nestProgress","materials","nestPlacement","sceneFocus","runs","leases","eggs","chicks","mates"] {
                XCTAssertNil(raw[key],key)
            }
        }
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as? [String:Any])
        for bad:Any in ["true",0,1,[],["enabled":true]] {
            raw["nestBuildingEnabled"]=bad;let bytes=try JSONSerialization.data(withJSONObject:raw)
            XCTAssertThrowsError(try BirdSettings.decode(bytes))
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:bytes))
        }
        raw["nestBuildingEnabled"]=true;raw["schemaVersion"]=BirdSettings.currentSchemaVersion+1
        let future=try JSONSerialization.data(withJSONObject:raw);try future.write(to:file)
        XCTAssertThrowsError(try BirdSettings.load(from:file,legacyURL:folder.appendingPathComponent("absent")))
        XCTAssertThrowsError(try BirdSettings().save(to:file));XCTAssertEqual(try Data(contentsOf:file),future)
    }

    func testOneSwitchGatesBothActionsIndependentlyOfSocialAndOnlyQuietBlocksAutomatic() {
        for enabled in [false,true] {for social in [false,true] {for mode:ActivityRhythmMode in [.steady,.quiet] {
            var settings=BirdSettings();settings.nestBuildingEnabled=enabled;settings.socialInteractions=social
            settings.activityRhythm=mode;settings.perchActions=false;settings.leafCarryEnabled=false
            for source:BehaviorSource in [.user,.preview,.automatic] {
                for kind:BehaviorKind in [.nestMaterialCarry,.nestBuild] {
                    XCTAssertEqual(BehaviorDefinitions.definition(for:kind).isEnabled(settings:settings,source:source),
                        enabled && (source != .automatic || mode != .quiet))
                }
                var other=settings;other.nestBuildingEnabled = !enabled
                for definition in BehaviorDefinitions.all where ![BehaviorKind.nestMaterialCarry,.nestBuild].contains(definition.kind) {
                    XCTAssertEqual(definition.isEnabled(settings:settings,source:source),definition.isEnabled(settings:other,source:source))
                }
            }
        }}}
    }
}
