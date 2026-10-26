import Foundation

/// E1–E5 append-only artwork. This explicit cohort grants only the four reviewed
/// foundation behaviors; specialized ecology remains separately allowlisted.
public enum ExpansionArtCatalog {
    public static let species: [SpeciesID] = ExpansionSmallArtGeometry.species
        + ExpansionGroundArtGeometry.species
        + ExpansionDisplayArtGeometry.species
        + ExpansionWetlandArtGeometry.species
        + ExpansionLargeArtGeometry.species

    public static func appendedFrameNames(for species: SpeciesID) -> [String] {
        ExpansionSmallArtGeometry.frameNames(for: species)
            + ExpansionGroundArtGeometry.frameNames(for: species)
            + ExpansionDisplayArtGeometry.frameNames(for: species)
            + ExpansionWetlandArtGeometry.frameNames(for: species)
            + ExpansionLargeArtGeometry.frameNames(for: species)
    }

    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        ExpansionSmallArtGeometry.signatureFrameNames(for: species)
            + ExpansionGroundArtGeometry.signatureFrameNames(for: species)
            + ExpansionDisplayArtGeometry.signatureFrameNames(for: species)
            + ExpansionWetlandArtGeometry.signatureFrameNames(for: species)
            + ExpansionLargeArtGeometry.signatureFrameNames(for: species)
    }

    public static func beakAnchor(species: SpeciesID, frame: String) -> PoseClip.Anchor? {
        if let value = ExpansionSmallArtGeometry.beakAnchor(species: species, frame: frame) { return value }
        if let value = ExpansionGroundArtGeometry.beakAnchor(species: species, frame: frame) { return value }
        if let value = ExpansionDisplayArtGeometry.beakAnchor(species: species, frame: frame) { return value }
        if let value = ExpansionWetlandArtGeometry.beakAnchor(species: species, frame: frame) { return value }
        return ExpansionLargeArtGeometry.beakAnchor(species: species, frame: frame)
    }
}
