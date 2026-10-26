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
        .sideBySide,.giveWay,.pairedTakeoff,.leafPlay,.watch,.alert,.sideHop,.takeoffPreparation,.edgePeek,.chase,.travelTogether,.allopreening,.fixedPerchVisit,.foodTrayVisit,.bathVisit,.leafCarry,.insectCatch,.visitorGift,.courtshipDisplay,.nestMaterialCarry,.nestBuild]
    private let sources:[BehaviorSource] = [.user,.preview,.automatic]

    // Frozen pre-v0.7 fixture, independent of the profile's cohort classification.
    private let legacySpecies:Set<SpeciesID> = [
        .redWhiskeredBulbul,.treeSparrow,.lightVentedBulbul,.spottedDove,.chineseBlackbird,
        .magpieRobin,.longTailedShrike,.nightHeron,.plumbeousWaterRedstart,.littleEgret,
        .greyHeron,.commonKestrel,.peregrineFalcon,.blackKite,.commonBuzzard,.orientalMagpie,
        .azureWingedMagpie,.largeBilledCrow,.hoopoe,.barnSwallow,.mallard,.asianKoel,
        .swinhoesWhiteEye,.blackHeadedGull,.whimbrel,.piedKingfisher,.eurasianWoodcock,
        .blackDrongo,.chinesePondHeron,.yellowRumpedFlycatcher,.yellowBrowedWarbler,
        .greatTit,.commonMoorhen,.greatSpottedWoodpecker,.vinousThroatedParrotbill,
        .blackWingedStilt,.eurasianCoot,.redBilledLeiothrix,.blackCollaredStarling,
        .commonKingfisher,.littleRingedPlover,.yellowBilledGrosbeak,.redFlankedBluetail,
        .collaredScopsOwl,.asianBarredOwlet,.littleOwl
    ]

    func testReviewedCohortRemainsTheOriginal46With54UnreviewedAdditions() {
        XCTAssertEqual(legacySpecies.count,46)
        XCTAssertEqual(Set(SpeciesID.allCases).count,100)
        XCTAssertEqual(Set(SpeciesID.allCases).subtracting(legacySpecies).count,54)
        XCTAssertEqual(Set(SpeciesBehaviorProfile.legacySpecies),legacySpecies)
        for species in SpeciesID.allCases {
            XCTAssertEqual(SpeciesBehaviorProfile.profile(for:species).isExpansionSpecies,
                           !legacySpecies.contains(species),species.rawValue)
        }
    }

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
            Expected(kind:.alert,capabilities:[.standing],frames:["stand"],encounter:false,paused:false,priority:40,cooldown:12,settingsMask:12),
            Expected(kind:.sideHop,capabilities:[.standing,.landing],frames:["stand","land0","land1","land2"],encounter:false,paused:false,priority:30,cooldown:24,settingsMask:260),
            Expected(kind:.takeoffPreparation,capabilities:[.standing,.flight],frames:["stand","fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7"],encounter:false,paused:false,priority:30,cooldown:4,settingsMask:516),
            Expected(kind:.edgePeek,capabilities:[.standing,.greeting,.landing],frames:["stand","idle0","idle1","idle2","land0","land1","land2"],encounter:false,paused:false,priority:15,cooldown:45,settingsMask:1028),
            Expected(kind:.chase,capabilities:[.standing,.flight,.landing],frames:leafFlight,encounter:true,paused:false,priority:60,cooldown:60,settingsMask:2064),
            Expected(kind:.travelTogether,capabilities:[.standing,.flight,.landing],frames:leafFlight,encounter:true,paused:false,priority:60,cooldown:60,settingsMask:4112),
            Expected(kind:.allopreening,capabilities:[.standing,.landing,.allopreening],frames:["stand","land0","land1","land2","allopreenGive0","allopreenGive1","allopreenGive2","allopreenReceive0","allopreenReceive1","allopreenReceive2"],encounter:true,paused:false,priority:60,cooldown:90,settingsMask:8208),
            Expected(kind:.fixedPerchVisit,capabilities:[.standing,.flight,.landing],frames:leafFlight,encounter:false,paused:false,priority:30,cooldown:60,settingsMask:16384),
            Expected(kind:.foodTrayVisit,capabilities:[.standing,.flight,.landing,.feeding],frames:leafFlight.union(["feedLook","feedDown0","feedDown1","feedLift"]),encounter:false,paused:false,priority:30,cooldown:75,settingsMask:32768),
            Expected(kind:.bathVisit,capabilities:[.standing,.flight,.landing,.bathing],frames:leafFlight.union(["bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise","shake"]),encounter:true,paused:false,priority:30,cooldown:45,settingsMask:65536),
            Expected(kind:.leafCarry,capabilities:[.standing,.flight,.landing,.carryingLeaf],frames:leafFlight.union(["carryLook","carryLower","carryGrip","carryPlace"]),encounter:true,paused:false,priority:60,cooldown:45,settingsMask:131072),
            Expected(kind:.insectCatch,capabilities:[.standing,.flight,.landing,.insectCatching],frames:leafFlight.union(["catchOpen","catchClose","catchRecover"]),encounter:true,paused:false,priority:60,cooldown:180,settingsMask:262144),
            Expected(kind:.visitorGift,capabilities:[.standing,.flight,.landing,.carryingLeaf],frames:leafFlight.union(["carryLook","carryLower","carryGrip","carryPlace"]),encounter:true,paused:false,priority:60,cooldown:0,settingsMask:524288),
            Expected(kind:.courtshipDisplay,capabilities:[.standing,.courtship],frames:["stand","courtRaise","courtBow0","courtBow1","courtBowRecover","courtObserve"],encounter:true,paused:false,priority:60,cooldown:600,settingsMask:1048592),
            Expected(kind:.nestMaterialCarry,capabilities:[.standing,.flight,.landing,.carryingNestMaterial],frames:leafFlight.union(["carryLook","carryLower","carryGrip","carryPlace"]),encounter:true,paused:false,priority:60,cooldown:20,settingsMask:2097152),
            Expected(kind:.nestBuild,capabilities:[.standing,.flight,.landing,.buildingNest],frames:leafFlight.union(["nestPlace","nestAdjust0","nestAdjust1","nestSettle"]),encounter:true,paused:false,priority:60,cooldown:20,settingsMask:2097152)
        ]
    }

    func testCapabilitiesUseExactExistingFramesAndStableCodableNames() throws {
        let fixtures:[(BirdCapability,String,Set<String>)] = [
            (.standing,"standing",["stand"]),
            (.blinking,"blinking",["blink"]),
            (.preening,"preening",["preen0","preen1"]),
            (.greeting,"greeting",["idle0","idle1","idle2"]),
            (.flight,"flight",["fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7"]),
            (.landing,"landing",["land0","land1","land2"]),
            (.allopreening,"allopreening",["allopreenGive0","allopreenGive1","allopreenGive2","allopreenReceive0","allopreenReceive1","allopreenReceive2"]),
            (.feeding,"feeding",["feedLook","feedDown0","feedDown1","feedLift"]),
            (.observationPose,"observationPose",["lookNear","lookFar"]),
            (.alertPose,"alertPose",["alertRise","alertHold","alertRelax"]),
            (.restPose,"restPose",["restLower","restTuck","restWake"]),
            (.takeoffPose,"takeoffPose",["takeoffCrouch","takeoffPush"]),
            (.edgePeekPose,"edgePeekPose",["peekLower","peekLook","peekRecover"]),
            (.bathing,"bathing",["bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise","shake"]),
            (.carryingLeaf,"carryingLeaf",["carryLook","carryLower","carryGrip","carryPlace"]),
            (.insectCatching,"insectCatching",["catchOpen","catchClose","catchRecover"]),
            (.courtship,"courtship",["courtRaise","courtBow0","courtBow1","courtBowRecover","courtObserve"]),
            (.carryingNestMaterial,"carryingNestMaterial",["carryLook","carryLower","carryGrip","carryPlace"]),
            (.buildingNest,"buildingNest",["nestPlace","nestAdjust0","nestAdjust1","nestSettle"])
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
        XCTAssertEqual(Set(BehaviorDefinitions.all.map { $0.kind.rawValue }).count,27)
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

    func testSpeciesSpecificContactFramesDoNotAdvertiseUnsupportedBirdCapabilities() {
        // Frame presence alone is not approval for an expansion species.
        // Keep raw asset requirements separate from reviewed capabilities.
        // Keep this fixture independent of BirdArt (AppKit) and the definitions.
        let manifest:Set<String> = ["stand","breathe","blink","preen0","preen1","land0","land1","land2",
            "fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","idle0","idle1","idle2",
            "stretch","shake","poop0","poop1","cling0","cling1","peck0","peck1",
            "glide0","glide1","glide2","bank0","bank1","bank2","bound"]
        let extra:Set<String>=["allopreenGive0","allopreenGive1","allopreenGive2","allopreenReceive0","allopreenReceive1","allopreenReceive2"]
        let supported:Set<SpeciesID>=[.barnSwallow,.swinhoesWhiteEye]
        let feeding:Set<String>=["feedLook","feedDown0","feedDown1","feedLift"]
        let seedVisitors:Set<SpeciesID>=[.treeSparrow,.spottedDove]
        let manifests=Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map {species in
            var frames=manifest
            if supported.contains(species) {frames.formUnion(extra)}
            if seedVisitors.contains(species) {frames.formUnion(feeding)}
            return (species,frames)
        })
        XCTAssertFalse(manifests.isEmpty)
        let expansionCapabilities:Set<BirdCapability> = [.standing,.blinking,.flight,.landing]
        for species in SpeciesID.allCases {
            let frames=manifests[species]!
            let audit=SpeciesSupportAudit(species:species,availableFrames:frames)
            for capability in BirdCapability.allCases {
                let available:Bool
                switch capability {
                case .allopreening:available=supported.contains(species)
                case .feeding:available=seedVisitors.contains(species)
                case .observationPose,.alertPose,.restPose,.takeoffPose,.edgePeekPose,.bathing,.carryingLeaf,.insectCatching,.courtship,.carryingNestMaterial,.buildingNest:available=false
                default:available=true
                }
                XCTAssertEqual(capability.requiredFrames.isSubset(of:frames),available,"\(species): \(capability)")
                XCTAssertEqual(audit.capabilities.contains(capability),
                    available && (legacySpecies.contains(species) || expansionCapabilities.contains(capability)),
                    "Reviewed capability: \(species): \(capability)")
            }
            for fixture in expected {
                let available:Bool
                switch fixture.kind {
                case .allopreening:available=supported.contains(species)
                case .foodTrayVisit:available=seedVisitors.contains(species)
                case .bathVisit,.leafCarry,.insectCatch,.visitorGift,.courtshipDisplay,.nestMaterialCarry,.nestBuild:available=false
                default:available=true
                }
                XCTAssertEqual(BehaviorDefinitions.definition(for:fixture.kind).missingFrames(in:frames).isEmpty,available,
                    "\(species): \(fixture.kind)")
                if !legacySpecies.contains(species) {
                    let behavior=audit.behaviors.first{$0.kind == fixture.kind}
                    let reviewed:Set<BehaviorKind> = [.watch,.alert,.rest,.takeoffPreparation]
                    XCTAssertEqual(behavior?.productAllowed,fixture.kind == .relocate || reviewed.contains(fixture.kind),
                        "Expansion permission: \(species): \(fixture.kind)")
                    XCTAssertEqual(behavior?.contentSupported,fixture.kind == .relocate,
                        "Expansion content: \(species): \(fixture.kind)")
                }
            }
        }
    }

    func testEdgePeekPoseRequiresTheCompleteNewSetWithoutChangingTheLegacyDefinition() {
        let frames:Set<String> = ["peekLower","peekLook","peekRecover"]
        let legacy:Set<String> = ["stand","idle0","idle1","idle2","land0","land1","land2"]
        XCTAssertEqual(BirdCapability.edgePeekPose.requiredFrames,frames)
        XCTAssertEqual(BehaviorDefinitions.definition(for:.edgePeek).requiredCapabilities,[.standing,.greeting,.landing])
        XCTAssertEqual(BehaviorDefinitions.definition(for:.edgePeek).requiredFrames,legacy)
        for species in SpeciesID.allCases {
            XCTAssertFalse(SpeciesSupportAudit(species:species,availableFrames:legacy).capabilities.contains(.edgePeekPose),species.rawValue)
            let complete=SpeciesSupportAudit(species:species,availableFrames:legacy.union(frames))
            XCTAssertEqual(complete.capabilities.contains(.edgePeekPose),legacySpecies.contains(species),
                "Complete frame injection must not authorize an unreviewed species: \(species)")
            if !legacySpecies.contains(species) {
                let behavior=complete.behaviors.first{$0.kind == .edgePeek}
                XCTAssertEqual(behavior?.missingFrames,[],species.rawValue)
                XCTAssertEqual(behavior?.productAllowed,false,species.rawValue)
                XCTAssertEqual(behavior?.contentSupported,false,species.rawValue)
            }
            for missing in frames.sorted() {
                XCTAssertFalse(SpeciesSupportAudit(species:species,
                    availableFrames:legacy.union(frames).subtracting([missing])).capabilities.contains(.edgePeekPose),
                    "\(species): missing \(missing)")
            }
        }
    }

    func testSettingsGatingForEverySwitchCombinationAndSource() {
        var settings=BirdSettings()
        // Fifteen independent bits include pointerFollowEnabled, which must never
        // disable pointerVisit, and the automatic-only ambient leaf preference.
        for bits in 0..<32768 {
            settings.pointerVisits=bits & 1 != 0
            settings.flockPasses=bits & 2 != 0
            settings.perchActions=bits & 4 != 0
            settings.passiveAttentionEnabled=bits & 8 != 0
            settings.socialInteractions=bits & 16 != 0
            settings.leafPlayEnabled=bits & 32 != 0
            settings.ambientLeafPlayEnabled=bits & 64 != 0
            settings.pointerFollowEnabled=bits & 128 != 0
            settings.sideHopEnabled=bits & 256 != 0
            settings.takeoffPreparationEnabled=bits & 512 != 0
            settings.edgePeekEnabled=bits & 1024 != 0
            settings.chaseEnabled=bits & 2048 != 0
            settings.travelTogetherEnabled=bits & 4096 != 0
            settings.allopreeningEnabled=bits & 8192 != 0
            settings.fixedPerchesEnabled=bits & 16384 != 0
            // Food tray is checked independently below; keep this at 2^15.
            for fixture in expected where fixture.kind != .foodTrayVisit && fixture.kind != .bathVisit && fixture.kind != .leafCarry && fixture.kind != .insectCatch && fixture.kind != .visitorGift && fixture.kind != .courtshipDisplay && fixture.kind != .nestMaterialCarry && fixture.kind != .nestBuild {
                for source in sources {
                    let mask=fixture.settingsMask | (fixture.kind == .leafPlay && source == .automatic ? 64:0)
                    let enabled=bits & mask == mask
                    XCTAssertEqual(BehaviorDefinitions.definition(for:fixture.kind).isEnabled(settings:settings,source:source),
                        enabled,"\(fixture.kind), \(source), settings bits \(bits)")
                }
            }
        }
    }

    func testFoodTraySettingIsIndependentOfExistingSwitchesAndQuietOnlyClosesAutomaticSource() {
        for enabled in [false,true] {
            for others in [false,true] {
                for rhythm:ActivityRhythmMode in [.steady,.quiet] {
                    var settings=BirdSettings();settings.foodTrayEnabled=enabled;settings.activityRhythm=rhythm
                    settings.pointerVisits=others;settings.flockPasses=others;settings.perchActions=others
                    settings.passiveAttentionEnabled=others;settings.socialInteractions=others
                    settings.leafPlayEnabled=others;settings.ambientLeafPlayEnabled=others
                    settings.pointerFollowEnabled=others;settings.sideHopEnabled=others
                    settings.takeoffPreparationEnabled=others;settings.edgePeekEnabled=others
                    settings.chaseEnabled=others;settings.travelTogetherEnabled=others
                    settings.allopreeningEnabled=others;settings.fixedPerchesEnabled=others
                    for source in sources {
                        XCTAssertEqual(BehaviorDefinitions.definition(for:.foodTrayVisit).isEnabled(settings:settings,source:source),
                            enabled && (source != .automatic || rhythm != .quiet))
                        var toggled=settings;toggled.foodTrayEnabled = !enabled
                        for kind in kinds where kind != .foodTrayVisit {
                            let definition=BehaviorDefinitions.definition(for:kind)
                            XCTAssertEqual(definition.isEnabled(settings:settings,source:source),
                                definition.isEnabled(settings:toggled,source:source),"\(kind), \(source)")
                        }
                    }
                }
            }
        }
    }

    func testPreemptionAllowsOnlyExplicitUserRelocationAndAutomaticAlert() {
        let relocationTargets:Set<BehaviorKind> = [.pointerVisit,.flockPass,.rest,.preen,.socialGreeting,
            .sideBySide,.giveWay,.pairedTakeoff,.leafPlay,.watch,.alert,.sideHop,.takeoffPreparation,.edgePeek,.chase,.travelTogether,.allopreening,.fixedPerchVisit,.foodTrayVisit,.bathVisit,.leafCarry,.insectCatch,.visitorGift,.courtshipDisplay,.nestMaterialCarry,.nestBuild]
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
