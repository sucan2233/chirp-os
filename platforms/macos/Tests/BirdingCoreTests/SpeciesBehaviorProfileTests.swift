import XCTest
@testable import BirdingCore

final class SpeciesBehaviorProfileTests:XCTestCase {
    // Literal M7b/c authorization, independent of the implementation. Existing
    // entries retain their relative order; only the approved species are added.
    private let dedicated:[(BehaviorKind,[SpeciesID])] = [
        (.edgePeek,[.treeSparrow,.chineseBlackbird,.hoopoe,.whimbrel,.lightVentedBulbul,.magpieRobin]),
        (.chase,[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling,.redWhiskeredBulbul]),
        (.travelTogether,[.treeSparrow,.barnSwallow,.spottedDove,.lightVentedBulbul,.azureWingedMagpie,.blackCollaredStarling,.redWhiskeredBulbul]),
        (.allopreening,[.barnSwallow,.swinhoesWhiteEye]),
        (.fixedPerchVisit,[.treeSparrow,.barnSwallow,.swinhoesWhiteEye,.redWhiskeredBulbul,.magpieRobin,.redBilledLeiothrix,.lightVentedBulbul]),
        (.foodTrayVisit,[.treeSparrow,.spottedDove]),
        (.bathVisit,[.treeSparrow,.lightVentedBulbul]),
        (.leafCarry,[.treeSparrow]),
        (.insectCatch,[.barnSwallow,.yellowRumpedFlycatcher]),
        (.visitorGift,[.azureWingedMagpie]),
        (.courtshipDisplay,[.spottedDove]),
        (.nestMaterialCarry,[.spottedDove]),
        (.nestBuild,[.spottedDove])
    ]
    private let flock:[SpeciesID] = [.treeSparrow,.barnSwallow,.swinhoesWhiteEye,
        .lightVentedBulbul,.azureWingedMagpie,.mallard,.blackHeadedGull,.blackCollaredStarling]
    private let poseSpecies:[SpeciesID] = [.treeSparrow,.spottedDove,.barnSwallow,.nightHeron,
        .lightVentedBulbul,.redWhiskeredBulbul,.chineseBlackbird,.magpieRobin,
        .swinhoesWhiteEye,.azureWingedMagpie,.redBilledLeiothrix,.littleOwl,
        .greatTit,.orientalMagpie,.greatSpottedWoodpecker,.mallard,.littleEgret,
        .eurasianGreatTit,.whiteWagtail,.indianWhiteEye,.crestedMyna,.eurasianNuthatch,.greatEgret,
        .yellowBrowedWarbler,.vinousThroatedParrotbill,.yellowRumpedFlycatcher,
        .redFlankedBluetail,.plumbeousWaterRedstart,.longTailedShrike,.blackDrongo,.yellowBilledGrosbeak,
        .greyHeron,.chinesePondHeron,.blackWingedStilt,.whimbrel,.littleRingedPlover,.commonMoorhen,.eurasianCoot,
        .commonKestrel,.peregrineFalcon,.blackKite,.commonBuzzard,.collaredScopsOwl,.asianBarredOwlet,.piedKingfisher,
        .blackHeadedGull,.hoopoe,.commonKingfisher,.eurasianWoodcock,.blackCollaredStarling,.largeBilledCrow,.asianKoel]
    private let expansionPilot:[SpeciesID] = [.eurasianGreatTit,.whiteWagtail,.indianWhiteEye,
        .crestedMyna,.eurasianNuthatch,.greatEgret]
    private let pilotSpecies:[SpeciesID] = [.greatTit,.orientalMagpie,.greatSpottedWoodpecker,
        .mallard,.littleEgret,.magpieRobin,
        .eurasianGreatTit,.whiteWagtail,.indianWhiteEye,.crestedMyna,.eurasianNuthatch,.greatEgret]
    private let reviewedPoseFrames:[BehaviorKind:Set<String>] = [
        .watch:["lookNear","lookFar"],.alert:["alertRise","alertHold","alertRelax"],
        .rest:["restLower","restTuck","restWake"],.takeoffPreparation:["takeoffCrouch","takeoffPush"]]
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

    func testAllHundredSpeciesKeepExactDedicatedPermissionsAndOrder() {
        XCTAssertEqual(SpeciesID.allCases.count,100)
        XCTAssertEqual(SpeciesCatalog.standard.species.count,100)
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

    func testGenericPermissionsAddOnlyTheFourReviewedExpansionPilotBehaviors() throws {
        let catalogOrder=SpeciesCatalog.standard.species.map(\.id)
        let legacy=Array(catalogOrder.prefix(46))
        XCTAssertEqual(SpeciesBehaviorProfile.legacySpecies,legacy)
        for kind in generic {
            let reviewed=reviewedPoseFrames[kind] ?? []
            let allowed=catalogOrder.filter {
                kind == .relocate || legacy.contains($0) || (expansionPilot.contains($0) && !reviewed.isEmpty)
            }
            XCTAssertEqual(SpeciesBehaviorProfile.species(for:kind),allowed,kind.rawValue)
            for species in SpeciesID.allCases {
                let supported=allowed.contains(species)
                XCTAssertEqual(SpeciesBehaviorProfile.profile(for:species).allows(kind),supported,"\(species): \(kind)")
                let audit=SpeciesSupportAudit(species:species,availableFrames:commonFrames)
                let entry=try XCTUnwrap(audit.behaviors.first{$0.kind==kind})
                XCTAssertEqual(entry.productAllowed,supported)
                let missing=expansionPilot.contains(species) ? reviewed.sorted():[]
                XCTAssertEqual(entry.contentSupported,supported && missing.isEmpty,
                    "E0 review requires the authored pose package: \(species): \(kind)")
                XCTAssertEqual(entry.missingFrames,missing)
                let complete=SpeciesSupportAudit(species:species,availableFrames:commonFrames.union(poseFrames))
                XCTAssertEqual(try XCTUnwrap(complete.behaviors.first{$0.kind==kind}).contentSupported,supported)
            }
        }
    }

    func testTwelveMotionPilotsKeepExpansionReviewLimitedToFourPoseBehaviors() {
        XCTAssertEqual(Array(LivelyMotion.species.prefix(12)),pilotSpecies)
        XCTAssertEqual(Set(LivelyMotion.species),Set(poseSpecies))
        XCTAssertEqual(pilotSpecies.count,12)
        XCTAssertEqual(Set(pilotSpecies).count,12)
        XCTAssertEqual(SpeciesBehaviorProfile.expansionPilotSpecies,expansionPilot)
        XCTAssertEqual(ExpansionPilotArtGeometry.species,expansionPilot)
        XCTAssertEqual(SpeciesBehaviorProfile.expansionPilotKinds,Set(reviewedPoseFrames.keys))
        let base:Set<BirdCapability> = [.standing,.blinking,.flight,.landing]
        let added:Set<BirdCapability> = [.observationPose,.alertPose,.restPose,.takeoffPose]
        for species in SpeciesCatalog.standard.species.dropFirst(46).map(\.id) {
            let profile=SpeciesBehaviorProfile.profile(for:species),pilot=expansionPilot.contains(species)
            XCTAssertEqual(profile.isExpansionPilot,pilot)
            XCTAssertEqual(profile.reviewedCapabilities,pilot ? base.union(added):base)
            for kind in BehaviorDefinitions.all.map(\.kind) {
                XCTAssertEqual(profile.hasReviewedContent(for:kind),
                    kind == .relocate || (pilot && reviewedPoseFrames[kind] != nil),"\(species): \(kind)")
            }
        }
    }

    func testPosePackageCoversAllOriginalSpeciesAndOnlySixReviewedExpansionSpecies() {
        XCTAssertEqual(SpeciesBehaviorProfile.poseSpecies,poseSpecies)
        XCTAssertEqual(poseSpecies.count,52)
        XCTAssertEqual(Set(poseSpecies).count,52)
        XCTAssertEqual(SpeciesID.allCases.filter{!poseSpecies.contains($0)}.count,48)
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
        let allFrames=commonFrames.union(contactFrames).union(poseFrames).union(peekFrames).union(bathFrames).union(carryFrames).union(["catchOpen","catchClose","catchRecover","courtRaise","courtBow0","courtBow1","courtBowRecover","courtObserve","nestPlace","nestAdjust0","nestAdjust1","nestSettle"])
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
                let allowed=SpeciesCatalog.standard.species.prefix(46).contains{$0.id == species} ||
                    (expansionPilot.contains(species) && reviewedPoseFrames[kind] != nil)
                XCTAssertEqual(row.productAllowed,allowed)
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
                let base=BehaviorDefinitions.definition(for:kind).requiredFrames
                let reviewed=expansionPilot.contains(species) ? (reviewedPoseFrames[kind] ?? []):[]
                XCTAssertEqual(profile.requiredFrames(for:kind),base.union(reviewed),
                    "Only E0's reviewed poses become admission requirements: \(species), \(kind)")
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
        for species in poseSpecies where !expansionPilot.contains(species) {
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

    func testMissingExpansionPilotPoseFrameDisablesOnlyItsReviewedBehavior() throws {
        for species in expansionPilot {
            for missing in poseFrames {
                let frames=commonFrames.union(poseFrames).subtracting([missing])
                let audit=SpeciesSupportAudit(species:species,availableFrames:frames)
                XCTAssertEqual(audit.poseFrames,poseFrames)
                XCTAssertEqual(audit.missingPoseFrames,[missing])
                for (kind,required) in reviewedPoseFrames {
                    let row=try XCTUnwrap(audit.behaviors.first{$0.kind == kind})
                    XCTAssertTrue(row.productAllowed)
                    XCTAssertEqual(row.contentSupported,!required.contains(missing),"\(species): \(kind): \(missing)")
                    XCTAssertEqual(row.missingFrames,required.contains(missing) ? [missing]:[])
                }
                let decoded=try JSONDecoder().decode(SpeciesSupportAudit.self,from:JSONEncoder().encode(audit))
                XCTAssertEqual(decoded.missingPoseFrames,[missing])
                XCTAssertEqual(decoded.behaviors.map(\.contentSupported),audit.behaviors.map(\.contentSupported))
                XCTAssertEqual(decoded.contentReview?.cohort,"expansion-e0-partial")
                XCTAssertEqual(decoded.contentReview?.managedBehaviorReviewPending,true)
            }
        }
    }
}
