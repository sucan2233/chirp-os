import Foundation

/// Decorative motion uses the existing species idle opportunity and bird clock.
/// It owns no behavior, random stream, observation, habitat or persistent state.
public enum LivelyMotion {
    public static let species:[SpeciesID] = M8PilotArtGeometry.species + ExpansionPilotArtGeometry.species
    private static let namesBySpecies=Dictionary(uniqueKeysWithValues:species.map {
        ($0,M8PilotArtGeometry.signatureFrameNames(for:$0)+ExpansionPilotArtGeometry.signatureFrameNames(for:$0))
    })
    public static func frameNames(for species:SpeciesID) -> [String] {
        namesBySpecies[species] ?? []
    }
    public static func isSideMotion(_ species:SpeciesID) -> Bool {
        species == .greatSpottedWoodpecker || species == .eurasianNuthatch
    }
    public static func variant(seed:UInt64,bird:BirdID) -> Int {
        // SplitMix finalizer: stable across processes, independent of engine RNG.
        var value=seed &+ bird.rawValue &* 0x9E3779B97F4A7C15
        value=(value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value=(value ^ (value >> 27)) &* 0x94D049BB133111EB
        return Int((value ^ (value >> 31)) & 1)
    }
    public static func window(_ species:SpeciesID) -> (cycle:Double,start:Double,duration:Double) {
        if species == .eurasianNuthatch {return (10,3,2)}
        let motion=SpeciesBehavior.motion(species)
        return (motion.cycle,motion.start,motion.duration)
    }
    private static let clips=Dictionary(uniqueKeysWithValues:species.map { id in
        (id,(0...1).compactMap{makeClip(species:id,variant:$0)})
    })
    public static func clip(species:SpeciesID,variant:Int=0) -> PoseClip? {
        guard let variants=clips[species],variants.count==2 else {return nil}
        return variants[variant & 1]
    }
    private static func makeClip(species:SpeciesID,variant:Int) -> PoseClip? {
        let names=frameNames(for:species)
        guard names.count==4 else {return nil}
        // Preparation, action, return, settled rest: same total window, two cadences.
        let weights=variant % 2 == 0 ? [0.20,0.30,0.22,0.28]:[0.28,0.20,0.32,0.20]
        let duration=window(species).duration
        return PoseClip(id:"\(species.rawValue).signature.v\(variant % 2)",frames:zip(names,weights).map {
            PoseClip.Frame(name:$0.0,duration:$0.1*duration,beak:PoseClip.beakAnchor(species:species,frame:$0.0))
        })
    }
    public static func previewFrame(species:SpeciesID,age:Double,variant:Int=0) -> String? {
        guard age.isFinite,age>=0,let clip=clip(species:species,variant:variant) else {return nil}
        return clip.sample(at:age.truncatingRemainder(dividingBy:clip.duration+0.65))?.name ??
            (isSideMotion(species) ? "cling0":"stand")
    }
}

/// Latches each idle opportunity. Interrupted/skipped clips cannot resume halfway
/// after a managed behavior, input, settings change or motion revision.
final class LivelyMotionScheduler {
    private struct Slot:Equatable {let revision:UInt64;let cycle:Int}
    private struct State {let slot:Slot;var active:Bool}
    private var states:[BirdID:State]=[:]
    func cancel(_ id:BirdID) {states[id]?.active=false}
    func cancelAll() {for id in states.keys {states[id]?.active=false}}
    func remove(_ id:BirdID) {states.removeValue(forKey:id)}
    func update(id:BirdID,bird:Bird,eligible:Bool) {
        let w=LivelyMotion.window(bird.profile.id)
        let age=bird.stateTime
        guard age.isFinite,age>=0 else {remove(id);return}
        let slot=Slot(revision:bird.motionRevision,cycle:Int(age/w.cycle))
        let phase=age.truncatingRemainder(dividingBy:w.cycle)-w.start
        guard phase>=0,phase<w.duration else {return}
        if states[id]?.slot != slot {
            // A bird first seen mid-window waits for its next complete opportunity.
            states[id]=State(slot:slot,active:eligible && phase<1.0/30.0)
        } else if !eligible {states[id]?.active=false}
    }
    func frame(id:BirdID,bird:Bird,seed:UInt64,eligible:Bool) -> String? {
        guard eligible,let state=states[id],state.active,state.slot.revision==bird.motionRevision else {return nil}
        let w=LivelyMotion.window(bird.profile.id),age=bird.stateTime
        guard age.isFinite,age>=0,Int(age/w.cycle)==state.slot.cycle else {return nil}
        return LivelyMotion.clip(species:bird.profile.id,variant:LivelyMotion.variant(seed:seed,bird:id))?
            .sample(at:age.truncatingRemainder(dividingBy:w.cycle)-w.start)?.name
    }
}
