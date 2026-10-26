import XCTest
@testable import BirdingCore

/// Literal E1–E5 scope transcribed from the approved batch list, independent
/// of production renderer/catalog arrays so accidental omissions are visible.
enum ExpansionCompletionFixture {
    static let e1: [SpeciesID] = [
        .marshTit,
        .greenBackedTit,
        .blackThroatedBushtit,
        .silverThroatedBushtit,
        .whiskeredYuhina,
        .daurianRedstart,
        .blueFrontedRedstart,
        .blackRedstart,
        .commonTailorbird,
        .greyCappedGreenfinch,
        .twite,
        .ornateSunbird
    ]
    static let e2: [SpeciesID] = [
        .silkyStarling,
        .whiteCheekedStarling,
        .carrionCrow,
        .daurianJackdaw,
        .redBilledChough,
        .plainLaughingthrush,
        .henricsLaughingthrush,
        .whiteBrowedLaughingthrush,
        .groundTit,
        .rufousBreastedAccentor,
        .hornedLark,
        .redThroatedThrush
    ]
    static let e3: [SpeciesID] = [
        .eurasianMagpie,
        .greyTreepie,
        .redBilledBlueMagpie,
        .yellowBilledBlueMagpie,
        .ashyDrongo,
        .blueWhistlingThrush,
        .sootyHeadedBulbul,
        .brownBreastedBulbul,
        .blackBulbul,
        .collaredFinchbill,
        .taiwanBarbet,
        .blueThroatedBarbet
    ]
    static let e4: [SpeciesID] = [
        .easternSpotBilledDuck,
        .ruddyShelduck,
        .easternCattleEgret,
        .blackTailedGull,
        .greatCrestedGrebe,
        .littleGrebe
    ]
    static let e5: [SpeciesID] = [
        .orientalTurtleDove,
        .eurasianCollaredDove,
        .uplandBuzzard,
        .himalayanVulture,
        .commonPheasant,
        .greaterCoucal
    ]
    static let newSpecies = e1 + e2 + e3 + e4 + e5
}
