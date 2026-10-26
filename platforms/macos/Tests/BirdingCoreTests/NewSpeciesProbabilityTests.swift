import XCTest
@testable import BirdingCore

final class NewSpeciesProbabilityTests: XCTestCase {
    /// The 46 pre-expansion stable IDs occupy the original suffix of the enum;
    /// catalog ordering is deliberately independent of this migration fixture.
    private func legacySettings() -> BirdSettings {
        let oldIDs = Set(SpeciesID.allCases.suffix(46))
        return BirdSettings(catalog: SpeciesCatalog(species: SpeciesCatalog.standard.species.filter {oldIDs.contains($0.id)}))
    }
    private func migrated() throws -> BirdSettings {
        try BirdSettings.decode(JSONEncoder().encode(legacySettings()))
    }

    func testUpgradeAppends54ZeroEntriesWithoutChangingUserPreferences() throws {
        var old = legacySettings()
        old.probabilities.adjust(at: 0, to: 1234)
        old.probabilities.setLocked(true, at: 0)
        old.catalog.species[0].adultLengthCM = 23
        old.catalog.species[0].speed = 1.73
        old.catalog.species[0].flapFPS = 13.37
        old.catalog.species[0].perchMin = 17
        old.catalog.species[0].perchMax = 53
        old.bathEnabled = false; old.nestBuildingEnabled = false
        old.visitorGiftsEnabled = true; old.pointerFollowEnabled = true
        old.socialInteractions = false; old.activityRhythm = .quiet
        old.hoverDelay = 0.37
        let restored = try BirdSettings.decode(JSONEncoder().encode(old))
        XCTAssertEqual(restored.catalog.species.count, 100)
        XCTAssertEqual(restored.pendingSpecies?.count, 54)
        XCTAssertEqual(Array(restored.probabilities.entries.prefix(46)), old.probabilities.entries)
        XCTAssertTrue(restored.probabilities.entries.suffix(54).allSatisfy {$0.points == 0 && !$0.locked})
        let profile = restored.catalog.profile(old.catalog.species[0].id)
        XCTAssertEqual(profile.adultLengthCM, 23)
        XCTAssertEqual(profile.speed, 1.73)
        XCTAssertEqual(profile.flapFPS, 13.37)
        XCTAssertEqual(profile.perchMin, 17)
        XCTAssertEqual(profile.perchMax, 53)
        XCTAssertFalse(restored.bathEnabled); XCTAssertFalse(restored.nestBuildingEnabled)
        XCTAssertTrue(restored.visitorGiftsEnabled); XCTAssertTrue(restored.pointerFollowEnabled)
        XCTAssertFalse(restored.socialInteractions); XCTAssertEqual(restored.activityRhythm, .quiet)
        XCTAssertEqual(restored.hoverDelay, 0.37)
        XCTAssertTrue(restored.probabilities.isValid)
        let again = try BirdSettings.decode(JSONEncoder().encode(restored))
        XCTAssertEqual(again.probabilities, restored.probabilities)
        XCTAssertEqual(again.pendingSpecies, restored.pendingSpecies)
    }

    func testDefaultBudgetIs20PercentAndPreservesEveryLockAndProportion() throws {
        var settings = try migrated()
        settings.probabilities.setLocked(true, at: 0)
        settings.probabilities.setLocked(true, at: 3)
        let before = settings.probabilities.entries
        let ids = try XCTUnwrap(settings.pendingSpecies), fresh = Set(ids)
        let available = settings.probabilities.newSpeciesAllocationAvailable(ids)
        XCTAssertTrue(settings.probabilities.allocateNewSpecies(ids, catalog: .standard))
        let after = settings.probabilities.entries
        XCTAssertEqual(after.filter {fresh.contains($0.id)}.reduce(0) {$0 + $1.points}, 2000)
        XCTAssertEqual(after.filter(\.locked), before.filter(\.locked))
        for (old, new) in zip(before, after) where !old.locked && !fresh.contains(old.id) {
            XCTAssertEqual(Double(new.points), Double(available - 2000) * Double(old.points) / Double(available), accuracy: 1)
        }
        let totalWeight = ids.reduce(0.0) {$0 + SpeciesCatalog.standard.profile($1).weight}
        for entry in after where fresh.contains(entry.id) {
            XCTAssertEqual(Double(entry.points), 2000 * SpeciesCatalog.standard.profile(entry.id).weight / totalWeight, accuracy: 1)
        }
        XCTAssertTrue(settings.probabilities.isValid)
        let allocated = settings.probabilities
        XCTAssertFalse(settings.probabilities.allocateNewSpecies(ids, catalog: .standard))
        XCTAssertEqual(settings.probabilities, allocated)
    }

    func testAllLockedZeroBalanceAndInsufficientBudgetAreAtomicNoOps() throws {
        var settings = try migrated()
        let ids = try XCTUnwrap(settings.pendingSpecies), fresh = Set(ids)
        for index in settings.probabilities.entries.indices where !fresh.contains(settings.probabilities.entries[index].id) {
            settings.probabilities.setLocked(true, at: index)
        }
        let allLocked = settings.probabilities
        XCTAssertEqual(settings.probabilities.newSpeciesAllocationAvailable(ids), 0)
        XCTAssertFalse(settings.probabilities.allocateNewSpecies(ids, catalog: .standard))
        XCTAssertEqual(settings.probabilities, allLocked)

        settings = try migrated()
        settings.probabilities.adjust(at: 0, to: 9000)
        settings.probabilities.setLocked(true, at: 0)
        let insufficient = settings.probabilities
        XCTAssertFalse(settings.probabilities.allocateNewSpecies(ids, catalog: .standard))
        XCTAssertEqual(settings.probabilities, insufficient)
        XCTAssertTrue(settings.probabilities.allocateNewSpecies(ids, catalog: .standard, budgetPoints: 1000))
        XCTAssertEqual(settings.probabilities.entries[0], insufficient.entries[0])
        XCTAssertTrue(settings.probabilities.isValid)

        settings = try migrated()
        settings.probabilities.adjust(at: 0, to: 10_000)
        settings.probabilities.setLocked(true, at: 0)
        let zeroBalance = settings.probabilities
        XCTAssertEqual(settings.probabilities.newSpeciesAllocationAvailable(ids), 0)
        XCTAssertFalse(settings.probabilities.allocateNewSpecies(ids, catalog: .standard, budgetPoints: 1))
        XCTAssertEqual(settings.probabilities, zeroBalance)
    }

    func testInvalidBudgetsAndManuallyEditedRecipientsCannotOverwriteChoices() throws {
        var settings = try migrated()
        let ids = try XCTUnwrap(settings.pendingSpecies)
        let initial = settings.probabilities
        for budget in [-1, 0, 10_001] {
            XCTAssertFalse(settings.probabilities.allocateNewSpecies(ids, catalog: .standard, budgetPoints: budget))
            XCTAssertEqual(settings.probabilities, initial)
        }
        let recipient = try XCTUnwrap(settings.probabilities.entries.firstIndex {$0.id == ids[0]})
        settings.probabilities.setLocked(true, at: recipient)
        let locked = settings.probabilities
        XCTAssertFalse(settings.probabilities.allocateNewSpecies(ids, catalog: .standard))
        XCTAssertEqual(settings.probabilities, locked)
        settings.probabilities.setLocked(false, at: recipient)
        settings.probabilities.adjust(at: recipient, to: 50)
        let edited = settings.probabilities
        XCTAssertFalse(settings.probabilities.allocateNewSpecies(ids, catalog: .standard))
        XCTAssertEqual(settings.probabilities, edited)
    }

    func testSmallCustomBudgetRoundsToExactly100Percent() throws {
        var settings = try migrated()
        let ids = try XCTUnwrap(settings.pendingSpecies), fresh = Set(ids)
        XCTAssertTrue(settings.probabilities.allocateNewSpecies(ids, catalog: .standard, budgetPoints: 37))
        XCTAssertEqual(settings.probabilities.entries.filter {fresh.contains($0.id)}.reduce(0) {$0 + $1.points}, 37)
        XCTAssertEqual(settings.probabilities.entries.reduce(0) {$0 + $1.points}, 10_000)
        XCTAssertTrue(settings.probabilities.isValid)
    }
}
