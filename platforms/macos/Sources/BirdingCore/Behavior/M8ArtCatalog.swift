import Foundation

/// The five remaining original-species batches. Geometry supplies appended art;
/// reviewed behavior permissions remain in SpeciesBehaviorProfile.
public enum M8ArtCatalog {
    public static let species: [SpeciesID] = M8CommonArtGeometry.species
        + M8SmallArtGeometry.species + M8WetlandArtGeometry.species
        + M8RaptorArtGeometry.species + M8DistinctArtGeometry.species

    public static func appendedFrameNames(for species: SpeciesID) -> [String] {
        M8CommonArtGeometry.frameNames(for: species)
            + M8SmallArtGeometry.frameNames(for: species)
            + M8WetlandArtGeometry.frameNames(for: species)
            + M8RaptorArtGeometry.frameNames(for: species)
            + M8DistinctArtGeometry.frameNames(for: species)
    }

    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        M8CommonArtGeometry.signatureFrameNames(for: species)
            + M8SmallArtGeometry.signatureFrameNames(for: species)
            + M8WetlandArtGeometry.signatureFrameNames(for: species)
            + M8RaptorArtGeometry.signatureFrameNames(for: species)
            + M8DistinctArtGeometry.signatureFrameNames(for: species)
    }

    public static func beakAnchor(species: SpeciesID, frame: String) -> PoseClip.Anchor? {
        if let value = M8CommonArtGeometry.beakAnchor(species: species, frame: frame) { return value }
        if let value = M8SmallArtGeometry.beakAnchor(species: species, frame: frame) { return value }
        if let value = M8WetlandArtGeometry.beakAnchor(species: species, frame: frame) { return value }
        if let value = M8RaptorArtGeometry.beakAnchor(species: species, frame: frame) { return value }
        return M8DistinctArtGeometry.beakAnchor(species: species, frame: frame)
    }
}
