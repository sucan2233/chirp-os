import Foundation
import XCTest
import BirdingCore

final class BehaviorDefinitionTests:XCTestCase {
    private struct Expected {
        let kind:BehaviorKind
        let capabilities:Set<BirdCapability>
        let frames:Set<String>
        let encounter:Bool
        let paused:Bool
        let priority:Int
        let cooldown:Double
        // Independent masks for the settings truth table below.
        let settingsMask:Int
    }

    private let kinds:[BehaviorKind] = [.relocate,.pointerVisit,.flockPass,.rest,.preen,.socialGreeting,
        .sideBySide,.giveWay,.pairedTakeoff,.leafPlay,.watch,.alert]
    private let sources:[BehaviorSource] = [.user,.preview,.automatic]

    // Literal expectations intentionally do not read existing plan requirements
    // or derive frames from the capability implementation under test.
    private var expected:[Expected] {
        let socialFlight:Set<String> = ["stand","blink","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","land0","land1","land2"]
        let leafFlight:Set<String> = ["stand","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","land0","land1","land2"]
        return [
            Expected(kind:.relocate,capabilities:[],frames:[],encounter:false,paused:true,priority:100,cooldown:0,settingsMask:0),
            Expected(kind:.pointerVisit,capabilities:[],frames:[],encounter:true,paused:false,priority:60,cooldown:0,settingsMask:1),
            Expected(kind:.flockPass,capabilities:[],frames:[],encounter:true,paused:false,priority:60,cooldown:0,settingsMask:2),
            Expected(kind:.rest,capabilities:[.standing,.blinking],frames:["stand","blink"],encounter:false,paused:false,priority:10,cooldown:6,settingsMask:4),
            Expected(kind:.preen,capabilities:[.standing,.preening],frames:["stand","preen0","preen1"],encounter:false,paused:false,priority:10,cooldown:6,settingsMask:4),
            Expected(kind:.socialGreeting,capabilities:[.standing,.blinking,.greeting],frames:["stand","blink","idle0","idle1","idle2"],encounter:true,paused:false,priority:60,cooldown:20,settingsMask:16),
            Expected(kind:.sideBySide,capabilities:[.standing,.blinking,.flight,.landing],frames:socialFlight,encounter:true,paused:false,priority:60,cooldown:20,settingsMask:16),
            Expected(kind:.giveWay,capabilities:[.standing,.blinking,.flight,.landing],frames:socialFlight,encounter:true,paused:false,priority:60,cooldown:20,settingsMask:16),
            Expected(kind:.pairedTakeoff,capabilities:[.standing,.blinking,.flight,.landing],frames:socialFlight,encounter:true,paused:false,priority:60,cooldown:20,settingsMask:16),
            Expected(kind:.leafPlay,capabilities:[.standing,.flight,.landing],frames:leafFlight,encounter:true,paused:false,priority:60,cooldown:90,settingsMask:32),
            Expected(kind:.watch,capabilities:[.standing,.blinking],frames:["stand","blink"],encounter:false,paused:false,priority:20,cooldown:8,settingsMask:12),
            Expected(kind:.alert,capabilities:[.standing],frames:["stand"],encounter:false,paused:false,priority:40,cooldown:12,settingsMask:12)
        ]
    }

    func testCapabilitiesUseExactExistingFramesAndStableCodableNames() throws {
        let fixtures:[(BirdCapability,String,Set<String>)] = [
            (.standing,"standing",["stand"]),
            (.blinking,"blinking",["blink"]),
            (.preening,"preening",["preen0","preen1"]),
            (.greeting,"greeting",["idle0","idle1","idle2"]),
            (.flight,"flight",["fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7"]),
            (.landing,"landing",["land0","land1","land2"])
        ]
        XCTAssertEqual(BirdCapability.allCases,fixtures.map {$0.0})
        for (capability,name,frames) in fixtures {
            XCTAssertEqual(capability.rawValue,name)
            XCTAssertEqual(capability.requiredFrames,frames,name)
            let data=Data("\"\(name)\"".utf8)
            XCTAssertEqual(try JSONDecoder().decode(BirdCapability.self,from:data),capability)
            XCTAssertEqual(try JSONEncoder().encode(capability),data)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(BirdCapability.self,from:Data("\"unknown\"".utf8)))
    }

    func testAllDefinitionsHaveFixedOrderAndExactSchedulingPolicy() {
        XCTAssertEqual(BehaviorDefinitions.all.map(\.kind),kinds)
        XCTAssertEqual(Set(BehaviorDefinitions.all.map { $0.kind.rawValue }).count,12)
        for fixture in expected {
            let definition=BehaviorDefinitions.definition(for:fixture.kind)
            let label=fixture.kind.rawValue
            XCTAssertEqual(definition.kind,fixture.kind,label)
            XCTAssertEqual(definition.requiredCapabilities,fixture.capabilities,label)
            XCTAssertEqual(definition.requiredFrames,fixture.frames,label)
            XCTAssertEqual(definition.occupiesEncounter,fixture.encounter,label)
            XCTAssertEqual(definition.runsWhilePaused,fixture.paused,label)
            XCTAssertEqual(definition.priority,fixture.priority,label)
            XCTAssertEqual(definition.cooldown,fixture.cooldown,label)
        }
    }

    func testMissingFramesReportsExactDifferenceIncludingEverySingleAssetLoss() {
        for fixture in expected {
            let definition=BehaviorDefinitions.definition(for:fixture.kind)
            XCTAssertEqual(definition.missingFrames(in:[]),fixture.frames,fixture.kind.rawValue)
            XCTAssertTrue(definition.missingFrames(in:fixture.frames.union(["unrelated"])).isEmpty)
            for frame in fixture.frames.sorted() {
                XCTAssertEqual(definition.missingFrames(in:fixture.frames.subtracting([frame])),[frame],
                    "\(fixture.kind): \(frame)")
            }
            let partial:Set<String> = ["stand","fly0","idle1","unrelated"]
            XCTAssertEqual(definition.missingFrames(in:partial),fixture.frames.subtracting(partial))
        }
    }

    func testLegacyMovementRequiresNoManifest() {
        for kind:BehaviorKind in [.relocate,.pointerVisit,.flockPass] {
            let definition=BehaviorDefinitions.definition(for:kind)
            XCTAssertTrue(definition.requiredCapabilities.isEmpty)
            XCTAssertTrue(definition.requiredFrames.isEmpty)
            XCTAssertTrue(definition.missingFrames(in:[]).isEmpty)
            XCTAssertTrue(definition.missingFrames(in:["legacyFallback"]).isEmpty)
        }
    }

    func testAllBirdManifestsSupportEveryDefinedCapabilityAndBehavior() {
        // BirdArt currently generates this same manifest for every SpeciesID.
        // Keep this fixture independent of BirdArt (AppKit) and the definitions.
        let manifest:Set<String> = ["stand","breathe","blink","preen0","preen1","land0","land1","land2",
            "fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","idle0","idle1","idle2",
            "stretch","shake","poop0","poop1","cling0","cling1","peck0","peck1",
            "glide0","glide1","glide2","bank0","bank1","bank2","bound"]
        let manifests=Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map {($0,manifest)})
        XCTAssertFalse(manifests.isEmpty)
        for species in SpeciesID.allCases {
            let frames=manifests[species]!
            for capability in BirdCapability.allCases {
                XCTAssertTrue(capability.requiredFrames.isSubset(of:frames),"\(species): \(capability)")
            }
            for fixture in expected {
                XCTAssertTrue(BehaviorDefinitions.definition(for:fixture.kind).missingFrames(in:frames).isEmpty,
                    "\(species): \(fixture.kind)")
            }
        }
    }

    func testSettingsGatingForEverySwitchCombinationAndSource() {
        var settings=BirdSettings()
        // Eight independent bits include pointerFollowEnabled, which must never
        // disable pointerVisit, and the automatic-only ambient leaf preference.
        for bits in 0..<256 {
            settings.pointerVisits=bits & 1 != 0
            settings.flockPasses=bits & 2 != 0
            settings.perchActions=bits & 4 != 0
            settings.passiveAttentionEnabled=bits & 8 != 0
            settings.socialInteractions=bits & 16 != 0
            settings.leafPlayEnabled=bits & 32 != 0
            settings.ambientLeafPlayEnabled=bits & 64 != 0
            settings.pointerFollowEnabled=bits & 128 != 0
            for fixture in expected {
                for source in sources {
                    let mask=fixture.settingsMask | (fixture.kind == .leafPlay && source == .automatic ? 64:0)
                    let enabled=bits & mask == mask
                    XCTAssertEqual(BehaviorDefinitions.definition(for:fixture.kind).isEnabled(settings:settings,source:source),
                        enabled,"\(fixture.kind), \(source), settings bits \(bits)")
                }
            }
        }
    }

    func testPreemptionAllowsOnlyExplicitUserRelocationAndAutomaticAlert() {
        let relocationTargets:Set<BehaviorKind> = [.pointerVisit,.flockPass,.rest,.preen,.socialGreeting,
            .sideBySide,.giveWay,.pairedTakeoff,.leafPlay,.watch,.alert]
        let alertTargets:Set<BehaviorKind> = [.rest,.preen,.watch]
        for incoming in kinds {
            for source in sources {
                for current in kinds {
                    for currentSource in sources {
                        let userMove=incoming == .relocate && source == .user && relocationTargets.contains(current)
                        let automaticAlert=incoming == .alert && source == .automatic && currentSource == .automatic && alertTargets.contains(current)
                        XCTAssertEqual(BehaviorDefinitions.canPreempt(incoming:incoming,source:source,current:current,currentSource:currentSource),
                            userMove || automaticAlert,"\(incoming)/\(source) over \(current)/\(currentSource)")
                    }
                }
            }
        }
    }
}
