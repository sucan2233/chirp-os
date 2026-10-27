import XCTest
@testable import BirdingCore

final class InsectCatchSettingsTests:XCTestCase {
    func testMissingSwitchDefaultsTrueAcrossOldSchemasAndRetainsExistingUserPreferences() throws {
        XCTAssertTrue(BirdSettings().insectCatchEnabled);XCTAssertEqual(BirdSettings.currentSchemaVersion,3)
        var original=BirdSettings();original.insectCatchEnabled=false
        original.hoverDelay=0.3;original.pointerFollowEnabled=true
        original.leafCarryEnabled=false;original.bathEnabled=false;original.foodTrayEnabled=false
        original.activityRhythm = .quiet;original.ambientFrequency = .high
        original.probabilities.setManualWeight(at:0,to:1234)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        raw.removeValue(forKey:"insectCatchEnabled")
        for version:Int? in [BirdSettings.currentSchemaVersion] {
            raw["schemaVersion"]=version
            let restored=try BirdSettings.decode(JSONSerialization.data(withJSONObject:raw))
            XCTAssertTrue(restored.insectCatchEnabled);XCTAssertEqual(restored.schemaVersion,BirdSettings.currentSchemaVersion)
            XCTAssertEqual(restored.hoverDelay,original.hoverDelay);XCTAssertEqual(restored.pointerFollowEnabled,original.pointerFollowEnabled)
            XCTAssertEqual(restored.leafCarryEnabled,original.leafCarryEnabled);XCTAssertEqual(restored.bathEnabled,original.bathEnabled)
            XCTAssertEqual(restored.foodTrayEnabled,original.foodTrayEnabled);XCTAssertEqual(restored.probabilities,original.probabilities)
            XCTAssertEqual(restored.catalog.species,original.catalog.species);XCTAssertEqual(restored.activityRhythm,original.activityRhythm)
            XCTAssertEqual(restored.ambientFrequency,original.ambientFrequency)
        }
    }

    func testExplicitSwitchRoundTripsAndHasNoDependencyOnPerchSocialOrOtherSceneSwitches() throws {
        for enabled in [false,true] {
            for others in [false,true] {
                for rhythm:ActivityRhythmMode in [.steady,.quiet] {
                    var settings=BirdSettings();settings.insectCatchEnabled=enabled;settings.activityRhythm=rhythm
                    settings.perchActions=others;settings.socialInteractions=others;settings.pointerVisits=others
                    settings.bathEnabled=others;settings.leafCarryEnabled=others;settings.leafPlayEnabled=others
                    let decoded=try BirdSettings.decode(JSONEncoder().encode(settings))
                    XCTAssertEqual(decoded.insectCatchEnabled,enabled)
                    var toggled=settings;toggled.insectCatchEnabled = !enabled
                    for source:BehaviorSource in [.automatic,.preview,.user] {
                        XCTAssertEqual(BehaviorDefinitions.definition(for:.insectCatch).isEnabled(settings:decoded,source:source),
                            enabled && (source != .automatic || rhythm != .quiet))
                        for definition in BehaviorDefinitions.all where definition.kind != .insectCatch {
                            XCTAssertEqual(definition.isEnabled(settings:settings,source:source),
                                definition.isEnabled(settings:toggled,source:source),definition.kind.rawValue)
                        }
                    }
                }
            }
        }
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as? [String:Any])
        for invalid:Any in ["false",0,1,[],["enabled":true]] {
            raw["insectCatchEnabled"]=invalid
            XCTAssertThrowsError(try BirdSettings.decode(JSONSerialization.data(withJSONObject:raw)))
        }
    }
}
