import XCTest
@testable import BirdingCore

final class SpeciesBehaviorProfileTests:XCTestCase {
    // Literal M6e authorization, independent of the implementation. Existing
    // entries retain their relative order; only the approved species are added.
    private let dedicated:[(BehaviorKind,[SpeciesID])] = [
        (.edgePeek,[.treeSparrow,.chineseBlackbird,.hoopoe,.whimbrel,.lightVentedBulbul,.magpieRobin]),
        (.chase,[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling,.redWhiskeredBulbul]),
        (.travelTogether,[.treeSparrow,.barnSwallow,.spottedDove,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling,.redWhiskeredBulbul]),
        (.allopreening,[.barnSwallow,.swinhoesWhiteEye]),
        (.fixedPerchVisit,[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.redWhiskeredBulbul,.magpieRobin,.redBilledLeiothrix,.lightVentedBulbul]),
        (.foodTrayVisit,[.treeSparrow,.spottedDove]),
        (.bathVisit,[.treeSparrow,.lightVentedBulbul]),
        (.leafCarry,[.treeSparrow])
    ]
    private let flock:[SpeciesID] = [.treeSparrow,.barnSwallow,.swinhoesWhiteEye,
        .lightVentedBulbul,.azureWingedMagpie,.mallard,.blackHeadedGull,.blackCollaredStarling]
    private let poseSpecies:[SpeciesID] = [.treeSparrow,.spottedDove,.barnSwallow,.nightHeron,
        .lightVentedBulbul,.redWhiskeredBulbul,.chineseBlackbird,.magpieRobin,
        .swinhoesWhiteEye,.azureWingedMagpie,.redBilledLeiothrix,.littleOwl]
    private let peekSpecies:[SpeciesID] = [.lightVentedBulbul,.magpieRobin]
    private let peekFrames:[String] = ["peekLower","peekLook","peekRecover"]
    private let poseFrames = ["lookNear","lookFar","alertRise","alertHold","alertRelax",
        "restLower","restTuck","restWake","takeoffCrouch","takeoffPush"]
    private let generic:[BehaviorKind] = [.relocate,.pointerVisit,.rest,.preen,.socialGreeting,
        .sideBySide,.giveWay,.pairedTakeoff,.leafPlay,.watch,.alert,.sideHop,.takeoffPreparation]
    private var commonFrames:Set<String> {
        Set(["stand","blink","preen0","preen1","idle0","idle1","idle2","land0","land1","land2"]
            + (0...7).map{"fly\($0)"})
    }

    func testAllFortySixSpeciesKeepExactDedicatedPermissionsAndOrder() {
        XCTAssertEqual(SpeciesID.allCases.count,46)
        XCTAssertEqual(SpeciesCatalog.standard.species.count,46)
        XCTAssertEqual(Set(SpeciesCatalog.standard.species.map(\.id)),Set(SpeciesID.allCases))
        XCTAssertEqual(SpeciesBehaviorProfile.dedicatedKinds,dedicated.map{$0.0})
        for (kind,expected) in dedicated {
            XCTAssertEqual(SpeciesBehaviorProfile.species(for:kind),expected,kind.rawValue)
            XCTAssertEqual(Set(expected).count,expected.count)
            for species in SpeciesID.allCases {
                let profile=SpeciesBehaviorProfile.profile(for:species)
                XCTAssertEqual(profile.species,species)
                XCTAssertEqual(profile.allows(kind),expected.contains(species),"\(species): \(kind)")
            }
        }
        // Verify the actual entry-point lists use the centralized permission.
        XCTAssertEqual(EdgePeekExecution.supportedSpecies,Set(dedicated[0].1))
        XCTAssertEqual(ChaseBehavior.supportedSpecies,Set(dedicated[1].1))
        XCTAssertEqual(TravelTogetherBehavior.supportedSpecies,Set(dedicated[2].1))
        XCTAssertEqual(AllopreeningBehavior.supportedSpecies,Set(dedicated[3].1))
        XCTAssertEqual(FixedPerchVisitBehavior.supportedSpecies,Set(dedicated[4].1))
        XCTAssertEqual(FoodTrayBehavior.supportedSpecies,Set(dedicated[5].1))
    }

    func testAmbientFlockPreservesBothOrderedConfigurationAndExecutorMembership() {
        XCTAssertEqual(SpeciesBehaviorProfile.ambientFlockSpecies,flock)
        XCTAssertEqual(SpeciesBehaviorProfile.species(for:.flockPass),flock)
        XCTAssertEqual(AmbientFlock.species,Set(flock))
        for species in SpeciesID.allCases {
            XCTAssertEqual(SpeciesBehaviorProfile.profile(for:species).allows(.flockPass),flock.contains(species))
        }
    }

    func testGenericProductPermissionsRemainAvailableForEverySpecies() throws {
        let catalogOrder=SpeciesCatalog.standard.species.map(\.id)
        for kind in generic {
            XCTAssertEqual(SpeciesBehaviorProfile.species(for:kind),catalogOrder,kind.rawValue)
            for species in SpeciesID.allCases {
                XCTAssertTrue(SpeciesBehaviorProfile.profile(for:species).allows(kind),"\(species): \(kind)")
                let audit=SpeciesSupportAudit(species:species,availableFrames:commonFrames)
                let entry=try XCTUnwrap(audit.behaviors.first{$0.kind==kind})
                XCTAssertTrue(entry.productAllowed)
                XCTAssertTrue(entry.contentSupported,"Existing complete common frames must still support \(species): \(kind)")
                XCTAssertTrue(entry.missingFrames.isEmpty)
            }
        }
    }

    func testPosePackageIsExactlyTenFramesForOnlyTheTwelveAuthorizedSpecies() {
        XCTAssertEqual(SpeciesBehaviorProfile.poseSpecies,poseSpecies)
        XCTAssertEqual(poseSpecies.count,12)
        XCTAssertEqual(SpeciesID.allCases.filter{!poseSpecies.contains($0)}.count,34)
        XCTAssertEqual(PoseClip.frameNames,poseFrames)
        XCTAssertEqual(Set(poseFrames).count,10)
        for species in SpeciesID.allCases {
            let profile=SpeciesBehaviorProfile.profile(for:species)
            XCTAssertEqual(profile.poseFrameNames,poseSpecies.contains(species) ? poseFrames:[])
            for kind:BehaviorKind in [.watch,.alert,.rest,.takeoffPreparation] {
                XCTAssertEqual(profile.poseClip(for:kind,duration:2) != nil,poseSpecies.contains(species),
                    "\(species): \(kind)")
            }
            for kind:BehaviorKind in [.preen,.edgePeek,.chase,.travelTogether,.allopreening,.foodTrayVisit] {
                XCTAssertNil(profile.poseClip(for:kind,duration:2),"An enhancement package grants no new behavior")
            }
        }
    }

    func testPoseCapabilitiesRequireEveryFrameWithoutChangingLegacyRequirements() {
        let packages:[(BirdCapability,Set<String>)] = [
            (.observationPose,["lookNear","lookFar"]),
            (.alertPose,["alertRise","alertHold","alertRelax"]),
            (.restPose,["restLower","restTuck","restWake"]),
            (.takeoffPose,["takeoffCrouch","takeoffPush"])
        ]
        for (capability,frames) in packages {
            XCTAssertEqual(capability.requiredFrames,frames)
            XCTAssertTrue(SpeciesSupportAudit(species:.treeSparrow,availableFrames:frames).capabilities.contains(capability))
            for missing in frames.sorted() {
                XCTAssertFalse(SpeciesSupportAudit(species:.treeSparrow,
                    availableFrames:frames.subtracting([missing])).capabilities.contains(capability),missing)
            }
        }
        let old:[(BehaviorKind,Set<BirdCapability>)] = [
            (.watch,[.standing,.blinking]),(.alert,[.standing]),
            (.rest,[.standing,.blinking]),(.takeoffPreparation,[.standing,.flight])
        ]
        for (kind,capabilities) in old {
            XCTAssertEqual(BehaviorDefinitions.definition(for:kind).requiredCapabilities,capabilities)
            XCTAssertTrue(BehaviorDefinitions.definition(for:kind).missingFrames(in:commonFrames).isEmpty)
        }
    }

    func testSupportAuditSeparatesProductPermissionFromFrameCompleteness() throws {
        let contactFrames:Set<String> = ["feedLook","feedDown0","feedDown1","feedLift",
            "allopreenGive0","allopreenGive1","allopreenGive2",
            "allopreenReceive0","allopreenReceive1","allopreenReceive2"]
        let bathFrames:Set<String>=["bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise","shake"]
        let carryFrames:Set<String>=["carryLook","carryLower","carryGrip","carryPlace"]
        let allFrames=commonFrames.union(contactFrames).union(poseFrames).union(peekFrames).union(bathFrames).union(carryFrames)
        for species in SpeciesID.allCases {
            let audit=SpeciesSupportAudit(species:species,availableFrames:allFrames)
            XCTAssertEqual(audit.species,species)
            XCTAssertEqual(audit.behaviors.map(\.kind),BehaviorDefinitions.all.map(\.kind))
            for (kind,allowed) in dedicated {
                let row=try XCTUnwrap(audit.behaviors.first{$0.kind==kind})
                XCTAssertTrue(row.missingFrames.isEmpty)
                XCTAssertEqual(row.productAllowed,allowed.contains(species))
                XCTAssertEqual(row.contentSupported,allowed.contains(species),"Frames alone cannot expand \(kind)")
            }
            XCTAssertTrue(audit.missingPoseFrames.isEmpty)
            let empty=SpeciesSupportAudit(species:species,availableFrames:[])
            XCTAssertTrue(empty.capabilities.isEmpty)
            for kind:BehaviorKind in [.watch,.alert,.rest,.preen,.takeoffPreparation] {
                let row=try XCTUnwrap(empty.behaviors.first{$0.kind==kind})
                XCTAssertTrue(row.productAllowed)
                XCTAssertFalse(row.contentSupported)
                XCTAssertFalse(row.missingFrames.isEmpty)
            }
        }
    }

    func testDedicatedPeekRequirementsAndAuditRequireAllThreeFramesOnlyForTheTwoNewSpecies() throws {
        let legacy:Set<String> = ["stand","idle0","idle1","idle2","land0","land1","land2"]
        XCTAssertEqual(SpeciesBehaviorProfile.peekSpecies,peekSpecies)
        XCTAssertEqual(SpeciesBehaviorProfile.peekFrameNames,peekFrames)
        XCTAssertEqual(BehaviorDefinitions.definition(for:.edgePeek).requiredFrames,legacy)
        for species in SpeciesID.allCases {
            let profile=SpeciesBehaviorProfile.profile(for:species),enhanced=peekSpecies.contains(species)
            XCTAssertEqual(profile.requiredFrames(for:.edgePeek),enhanced ? legacy.union(peekFrames):legacy)
            for kind in BehaviorDefinitions.all.map(\.kind) where kind != .edgePeek {
                XCTAssertEqual(profile.requiredFrames(for:kind),BehaviorDefinitions.definition(for:kind).requiredFrames,
                    "Optional pose art must not become a new admission requirement: \(species), \(kind)")
            }
            let allowed=dedicated[0].1.contains(species)
            for missing in peekFrames {
                let available=legacy.union(peekFrames).subtracting([missing])
                let audit=SpeciesSupportAudit(species:species,availableFrames:available)
                let row=try XCTUnwrap(audit.behaviors.first{$0.kind == .edgePeek})
                XCTAssertEqual(row.productAllowed,allowed)
                XCTAssertEqual(row.missingFrames,enhanced ? [missing]:[])
                XCTAssertEqual(row.contentSupported,allowed && !enhanced)
                let decoded=try JSONDecoder().decode(SpeciesSupportAudit.self,from:JSONEncoder().encode(audit))
                XCTAssertEqual(decoded.behaviors.first{$0.kind == .edgePeek}?.missingFrames,row.missingFrames)
            }
            let old=try XCTUnwrap(SpeciesSupportAudit(species:species,availableFrames:legacy).behaviors.first{$0.kind == .edgePeek})
            XCTAssertEqual(old.missingFrames,enhanced ? peekFrames.sorted():[])
            XCTAssertEqual(old.contentSupported,allowed && !enhanced)
            let complete=try XCTUnwrap(SpeciesSupportAudit(species:species,
                availableFrames:legacy.union(peekFrames)).behaviors.first{$0.kind == .edgePeek})
            XCTAssertTrue(complete.missingFrames.isEmpty)
            XCTAssertEqual(complete.contentSupported,allowed)
        }
    }

    func testMissingOptionalPoseFrameIsReportedButDoesNotDisableOldBehavior() throws {
        for species in poseSpecies {
            for missing in poseFrames {
                let frames=commonFrames.union(poseFrames).subtracting([missing])
                let audit=SpeciesSupportAudit(species:species,availableFrames:frames)
                XCTAssertEqual(audit.poseFrames,poseFrames)
                XCTAssertEqual(audit.missingPoseFrames,[missing])
                for kind:BehaviorKind in [.watch,.alert,.rest,.takeoffPreparation] {
                    XCTAssertTrue(try XCTUnwrap(audit.behaviors.first{$0.kind==kind}).contentSupported)
                }
                let data=try JSONEncoder().encode(audit)
                let decoded=try JSONDecoder().decode(SpeciesSupportAudit.self,from:data)
                XCTAssertEqual(decoded.species,species)
                XCTAssertEqual(decoded.poseFrames,poseFrames)
                XCTAssertEqual(decoded.missingPoseFrames,[missing])
                XCTAssertEqual(decoded.behaviors.map(\.contentSupported),audit.behaviors.map(\.contentSupported))
            }
        }
    }
}
