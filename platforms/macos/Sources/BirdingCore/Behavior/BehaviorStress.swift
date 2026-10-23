import Foundation
import CoreGraphics

/// Synchronous production-core workload. Call on the engine owner's executor;
/// this harness creates neither timers nor threads and writes no artifacts.
public enum BehaviorStress {
    public struct Configuration: Codable, Equatable {
        public let seconds: Double
        public let birds: Int
        public let displays: Int
        public let seed: UInt64
        public let autonomous: Bool
        public init(seconds: Double = 600, birds: Int = 24, displays: Int = 2, seed: UInt64 = 73, autonomous:Bool=false) {
            self.seconds=seconds; self.birds=birds; self.displays=displays; self.seed=seed
            self.autonomous=autonomous
        }
        func validate() throws {
            guard seconds.isFinite, (1...3600).contains(seconds) else {throw ConfigurationError.seconds}
            guard (1...64).contains(birds) else {throw ConfigurationError.birds}
            guard (1...4).contains(displays) else {throw ConfigurationError.displays}
        }
    }
    public enum ConfigurationError: String, Error, LocalizedError {
        case seconds, birds, displays
        public var errorDescription: String? {
            switch self {
            case .seconds:return "seconds must be finite and in 1...3600"
            case .birds:return "birds must be in 1...64"
            case .displays:return "displays must be in 1...4"
            }
        }
    }
    public struct Workload: Codable, Equatable {
        public let version: Int
        public let fixedStepSeconds: Double
        public let activeSteps: Int
        public let warmupSteps: Int
        public let drainSteps: Int
        public let drainLimitSteps: Int
        public let worldSampleEverySteps: Int
        public let timingSampleLimit: Int
        public let frameManifest: String
        public let species: [String]
    }
    public struct Metrics: Codable, Equatable {
        public internal(set) var commands=0, acceptedCommands=0, rejectedCommands=0
        public internal(set) var worldSamples=0, pointerSweepSamples=0, hostRemovalTransitions=0
        public internal(set) var residentRemovals=0, replacementBirds=0, repeatedRemovalChecks=0
        public internal(set) var pauseTransitions=0, settingsChanges=0, lifecycleCancellations=0
        public internal(set) var events=0, startedRuns=0, completedRuns=0, cancelledRuns=0, failedRuns=0
        public internal(set) var automaticStartedRuns=0, automaticCompletedRuns=0
        public internal(set) var drainCompletions=0, explicitCleanupCancellations=0, removedBirdEvents=0
        public internal(set) var previewResults=0, successfulPreviews=0
        public internal(set) var startedByKind: [String:Int]=[:]
        public internal(set) var completedByKind: [String:Int]=[:]
        public internal(set) var cancellationReasons: [String:Int]=[:]
        public internal(set) var failureReasons: [String:Int]=[:]
        public internal(set) var eventDigest: String=""
        public internal(set) var stateDigest: String=""
    }
    public struct Peaks: Codable, Equatable {
        public internal(set) var activeRuns=0, birds=0, leases=0, reservations=0, props=0, events=0
        public internal(set) var ecologyMemories=0, pendingBirds=0
        public internal(set) var visitorProfiles=0, visitorLeases=0
    }
    public struct Integrity: Codable, Equatable {
        public let samples: Int
        public let checks: [String:Bool]
        public let violations: [String:Int]
        public var passed: Bool {checks.values.allSatisfy{$0}}
    }
    public struct Cleanup: Codable, Equatable {
        public let activeRunsBeforeDrain: Int
        public let activeRunsAfterDrain: Int
        public let drainReachedIdle: Bool
        public let naturallyCompletedDuringDrain: Int
        public let explicitlyCancelledRuns: Int
        public let residentsBeforeRemoval: Int
        public let explicitlyRemovedBirds: Int
        public let activeRuns: Int
        public let birds: Int
        public let pendingBirds: Int
        public let leases: Int
        public let reservations: Int
        public let props: Int
        public let ecologyMemories: Int
        public let visitorLeases:Int
        public let retainedVisitorProfiles:Int
        public let pendingPreviews: Int
        public var passed: Bool {
            [activeRuns,birds,pendingBirds,leases,reservations,props,ecologyMemories,pendingPreviews,visitorLeases].allSatisfy{$0==0} && retainedVisitorProfiles<=VisitorMemoryArchive.maximumProfiles
        }
    }
    public struct Timing: Codable, Equatable {
        public let calls: Int
        public let sampledCalls: Int
        public let p50Milliseconds: Double
        public let p95Milliseconds: Double
        public let p99Milliseconds: Double
        public let maxMilliseconds: Double
    }
    public struct Timings: Codable {
        /// Monotonic wall time, including harness event observation. Percentiles
        /// use a deterministic bounded reservoir and nearest rank; max uses all
        /// calls. World construction and integrity checks are outside callbacks.
        public let method: String
        public let warmup: [String:Timing]
        public let active: [String:Timing]
        public let drain: [String:Timing]
        public let cleanup: [String:Timing]
    }
    public struct Report: Codable {
        public let configuration: Configuration
        public let workload: Workload
        public let metrics: Metrics
        public let integrity: Integrity
        public let peaks: Peaks
        public let cleanup: Cleanup
        public let timings: Timings
        public var passed: Bool {integrity.passed && cleanup.passed && cleanup.drainReachedIdle && metrics.startedRuns>0 && metrics.completedRuns>0}

        // Encode passed as a field as well as exposing the Swift computed value.
        private enum CodingKeys: String, CodingKey {
            case configuration, workload, metrics, integrity, peaks, cleanup, timings, passed
        }
        public func encode(to encoder: Encoder) throws {
            var c=encoder.container(keyedBy:CodingKeys.self)
            try c.encode(configuration,forKey:.configuration); try c.encode(workload,forKey:.workload)
            try c.encode(metrics,forKey:.metrics); try c.encode(integrity,forKey:.integrity)
            try c.encode(peaks,forKey:.peaks); try c.encode(cleanup,forKey:.cleanup)
            try c.encode(timings,forKey:.timings); try c.encode(passed,forKey:.passed)
        }
        public init(from decoder: Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            configuration=try c.decode(Configuration.self,forKey:.configuration)
            workload=try c.decode(Workload.self,forKey:.workload)
            metrics=try c.decode(Metrics.self,forKey:.metrics)
            integrity=try c.decode(Integrity.self,forKey:.integrity)
            peaks=try c.decode(Peaks.self,forKey:.peaks); cleanup=try c.decode(Cleanup.self,forKey:.cleanup)
            timings=try c.decode(Timings.self,forKey:.timings)
        }
        init(configuration: Configuration, workload: Workload, auditor: Auditor, cleanup: Cleanup, timings: Timings) {
            self.configuration=configuration; self.workload=workload; metrics=auditor.metrics
            integrity=auditor.report; peaks=auditor.peaks; self.cleanup=cleanup; self.timings=timings
        }
    }

    public static func run(configuration: Configuration = Configuration()) throws -> Report {
        try configuration.validate()
        return Runner(configuration).run()
    }

    /// Incremental accounting deliberately retains only currently open runs.
    /// Run IDs increase strictly, so a terminal absent from open is invalid
    /// without retaining the entire terminal history.
    final class Auditor {
        struct Open {let participants:[BirdID]; let kind:BehaviorKind?; let source:BehaviorSource}
        var metrics=Metrics(), peaks=Peaks()
        private var open:[BehaviorRunID:Open]=[:]
        private var sequence:UInt64=0, highestRun:UInt64=0
        private var eventHash:UInt64=14695981039346656037, stateHash:UInt64=14695981039346656037
        private var samples=0
        private var violations:[String:Int]=[:]
        private static let names=["eventSequence","runLifecycle","leaseOwnership","reservations","propOwnership",
                                  "finitePresentation","uniqueBirds","ecologyMemory","boundedResources","finalRunBalance","successfulWork","noTimeouts","actionCoverage","autonomousCoverage","visitorMemory"]
        func check(_ name:String,_ condition:Bool) {if !condition {violations[name,default:0]+=1}}
        private func hash(_ value:UInt64,into digest:inout UInt64) {digest=(digest ^ value) &* 1099511628211}
        private func hash(_ value:String,into digest:inout UInt64) {for byte in value.utf8 {hash(UInt64(byte),into:&digest)}; hash(255,into:&digest)}
        func observe(_ event:BehaviorEvent) {
            check("eventSequence",event.sequence==sequence+1 && event.time.isFinite); sequence=event.sequence
            metrics.events+=1
            hash(event.sequence,into:&eventHash); hash(event.time.bitPattern,into:&eventHash)
            hash(event.type.rawValue,into:&eventHash); hash(event.kind?.rawValue ?? "",into:&eventHash)
            hash(event.reason?.rawValue ?? "",into:&eventHash); hash(event.source.rawValue,into:&eventHash)
            hash(event.runID?.rawValue ?? 0,into:&eventHash)
            for id in event.participants {hash(id.rawValue,into:&eventHash)}
            switch event.type {
            case .started:
                if event.source == .automatic {metrics.automaticStartedRuns+=1}
                metrics.startedRuns+=1; metrics.startedByKind[event.kind?.rawValue ?? "unknown",default:0]+=1
                guard let id=event.runID else {check("runLifecycle",false); return}
                check("runLifecycle",id.rawValue>highestRun && open[id]==nil && !event.participants.isEmpty && Set(event.participants).count==event.participants.count)
                highestRun=max(highestRun,id.rawValue)
                open[id]=Open(participants:event.participants,kind:event.kind,source:event.source)
            case .completed,.cancelled,.failed:
                if event.type == .completed && event.source == .automatic {metrics.automaticCompletedRuns+=1}
                if event.type == .completed {metrics.completedRuns+=1; metrics.completedByKind[event.kind?.rawValue ?? "unknown",default:0]+=1}
                if event.type == .cancelled {
                    metrics.cancelledRuns+=1; metrics.cancellationReasons[event.reason?.rawValue ?? "unspecified",default:0]+=1
                }
                if event.type == .failed {
                    metrics.failedRuns+=1; metrics.failureReasons[event.reason?.rawValue ?? "unspecified",default:0]+=1
                }
                check("noTimeouts",event.reason != .timedOut)
                guard let id=event.runID,let started=open.removeValue(forKey:id) else {check("runLifecycle",false); return}
                check("runLifecycle",started.participants==event.participants && started.kind==event.kind && started.source==event.source)
            case .birdRemoved:metrics.removedBirdEvents+=1
            case .previewResult:
                metrics.previewResults+=1
                if event.reason==nil {metrics.successfulPreviews+=1}
            case .rejected:break
            }
        }
        func sample(_ engine:BehaviorEngine,birds:[BirdRenderState],props:[ScenePropRenderState],birdLimit:Int) {
            samples+=1
            let runs=engine.runtime.runs, owners=engine.runtime.owners, slots=engine.runtime.landingReservations
            let models=engine.birds, ids=models.compactMap{engine.id(of:$0)}
            check("uniqueBirds",ids.count==models.count && Set(ids).count==ids.count && Set(birds.map(\.id))==Set(ids))
            check("leaseOwnership",runs.count==open.count && runs.allSatisfy {id,run in
                open[id] != nil && Set(run.execution.participants).count==run.execution.participants.count &&
                    run.execution.participants.allSatisfy{owners[$0]==id && (engine.bird($0) != nil || run.execution.kind == .flockPass)}
            } && owners.allSatisfy {bird,id in runs[id]?.execution.participants.contains(bird)==true})
            check("reservations",slots.allSatisfy {slot in
                guard let id=owners[slot.bird],let run=runs[id] else {return false}
                return run.execution.participants.contains(slot.bird) && slot.isValid(in:engine)
            } && !slots.enumerated().contains {index,slot in slots.dropFirst(index+1).contains{slot.conflicts(with:$0,in:engine)}})
            let propIDs=runs.values.flatMap{$0.execution.propIDs}
            check("propOwnership",Set(propIDs).count==propIDs.count && Set(props.map(\.id)).count==props.count && Set(props.map(\.id)).isSubset(of:Set(propIDs)))
            check("finitePresentation",birds.allSatisfy {b in
                b.position.x.isFinite && b.position.y.isFinite && b.scale.isFinite && b.scale>0 && b.hopOffset.isFinite &&
                    engine.world.availableFrames[b.species]?.contains(b.frameName)==true
            } && props.allSatisfy {p in
                p.position.x.isFinite && p.position.y.isFinite && p.rotation.isFinite && p.size.isFinite && p.size>0 && p.opacity.isFinite && (0...1).contains(p.opacity)
            })
            let residents=Set(models.filter{engine.role(of:$0) == .resident}.compactMap{engine.id(of:$0)})
            let visitors=models.compactMap{engine.visitor(of:$0)}
            check("visitorMemory",Set(visitors.map(\.id)).count==visitors.count && engine.activeVisitorCount==visitors.count &&
                  engine.rememberedVisitorCount<=VisitorMemoryArchive.maximumProfiles &&
                  visitors.allSatisfy{$0.familiarity.isFinite && (0...1).contains($0.familiarity)})
            check("ecologyMemory",Set(engine.perchPlanner.rhythms.keys)==residents && models.allSatisfy {bird in
                guard engine.role(of:bird) == .resident else {return true}
                guard let state=engine.ecology(of:bird) else {return false}
                return state.disturbance.isFinite && (0...1).contains(state.disturbance) && state.quietTime.isFinite && state.quietTime>=0 &&
                    state.cooldowns.values.allSatisfy{$0.isFinite && $0>0}
            })
            let total=models.count+engine.pendingCount
            let reservationCounts=Dictionary(grouping:slots,by: \.bird).mapValues(\.count)
            let perBirdSlotsBounded=reservationCounts.allSatisfy {bird,count in
                guard let owner=owners[bird],let run=runs[owner] else {return false}
                return count <= (run.execution.kind == .edgePeek ? 2:1)
            }
            check("boundedResources",total<=birdLimit+5 && runs.count<=birdLimit+1 && owners.count<=birdLimit+5 &&
                slots.count<=2*birdLimit+5 && perBirdSlotsBounded && propIDs.count<=1 && engine.events.count<=256)
            peaks.activeRuns=max(peaks.activeRuns,runs.count); peaks.birds=max(peaks.birds,total)
            peaks.leases=max(peaks.leases,owners.count); peaks.reservations=max(peaks.reservations,slots.count)
            peaks.props=max(peaks.props,propIDs.count); peaks.events=max(peaks.events,engine.events.count)
            peaks.ecologyMemories=max(peaks.ecologyMemories,engine.perchPlanner.rhythms.count); peaks.pendingBirds=max(peaks.pendingBirds,engine.pendingCount)
            peaks.visitorProfiles=max(peaks.visitorProfiles,engine.rememberedVisitorCount)
            peaks.visitorLeases=max(peaks.visitorLeases,engine.activeVisitorCount)
            hash(UInt64(runs.count),into:&stateHash); hash(UInt64(slots.count),into:&stateHash)
            for b in birds {
                hash(b.id.rawValue,into:&stateHash); hash(b.species.rawValue,into:&stateHash)
                hash(Double(b.position.x).bitPattern,into:&stateHash); hash(Double(b.position.y).bitPattern,into:&stateHash)
                hash(Double(b.hopOffset).bitPattern,into:&stateHash); hash(b.frameName,into:&stateHash)
            }
            for p in props {
                hash(p.id.rawValue,into:&stateHash); hash(Double(p.position.x).bitPattern,into:&stateHash)
                hash(Double(p.position.y).bitPattern,into:&stateHash); hash(p.opacity.bitPattern,into:&stateHash)
            }
        }
        func finish(requiredCompletedKinds:[String]=[],requireAutonomy:Bool=false) {
            check("finalRunBalance",open.isEmpty && metrics.startedRuns==metrics.completedRuns+metrics.cancelledRuns+metrics.failedRuns)
            check("successfulWork",metrics.startedRuns>0 && metrics.completedRuns>0)
            check("actionCoverage",requiredCompletedKinds.allSatisfy{metrics.completedByKind[$0,default:0]>0})
            check("autonomousCoverage",!requireAutonomy || (metrics.automaticStartedRuns>0 && metrics.automaticCompletedRuns>0))
            metrics.eventDigest=String(eventHash,radix:16); metrics.stateDigest=String(stateHash,radix:16)
        }
        var report:Integrity {Integrity(samples:samples,checks:Dictionary(uniqueKeysWithValues:Self.names.map{($0,violations[$0,default:0]==0)}),violations:violations)}
    }

    private final class WallSamples {
        static let limit=4096
        var count=0, maximum=0.0
        var values:[Double]=[]
        func append(_ value:Double) {
            count+=1; maximum=max(maximum,value)
            if values.count<Self.limit {values.append(value); return}
            // Deterministic reservoir indexes; timing never affects simulation RNG.
            var n=UInt64(count) &* 0x9E3779B97F4A7C15
            n=(n ^ (n>>30)) &* 0xBF58476D1CE4E5B9; n=(n ^ (n>>27)) &* 0x94D049BB133111EB
            let index=Int((n ^ (n>>31)) % UInt64(count))
            if index<Self.limit {values[index]=value}
        }
        var report:Timing {
            let sorted=values.sorted()
            func percentile(_ p:Double) -> Double {sorted.isEmpty ? 0:sorted[max(0,Int(ceil(Double(sorted.count)*p))-1)]}
            return Timing(calls:count,sampledCalls:sorted.count,p50Milliseconds:percentile(0.5),p95Milliseconds:percentile(0.95),p99Milliseconds:percentile(0.99),maxMilliseconds:maximum)
        }
    }

    private final class Runner {
        let config:Configuration, engine:BehaviorEngine
        let auditor=Auditor()
        let screens:[CGRect]
        let baseHosts:[Surface]
        let frames:[SpeciesID:Set<String>]
        let species:[SpeciesID]
        var phase="warmup"
        var timings:[String:[String:WallSamples]]=[:]
        let warmupSteps=6*60, drainLimit=120*60
        var moving=false, removed=false, sweep=false
        var sampleTick=0

        init(_ configuration:Configuration) {
            config=configuration
            var settings=BirdSettings(); settings.ambientFrequency = .high
            engine=BehaviorEngine(seed:configuration.seed,settings:settings)
            screens=(0..<configuration.displays).map {i in CGRect(x:-2400+i*2400,y:-400+(i%2)*80,width:2400,height:1800)}
            var hosts:[Surface]=[]
            for (display,area) in screens.enumerated() {
                for row in 0..<8 {
                    hosts.append(Surface(id:UInt32(100+display*10+row),pid:Int32(700+display),
                        rect:CGRect(x:area.minX+100,y:area.minY+420+CGFloat(row)*130,width:2200,height:70)))
                }
            }
            baseHosts=hosts
            // BirdArt's existing atlas vocabulary, for each real catalog entry.
            // No asset loading or AppKit dependency is needed for core snapshots.
            let names:Set<String>=["stand","breathe","blink","preen0","preen1","land0","land1","land2",
                "fly0","fly1","fly2","fly3","fly4","fly5","fly6","fly7","idle0","idle1","idle2",
                "stretch","shake","poop0","poop1","cling0","cling1","peck0","peck1","glide0","glide1","glide2","bank0","bank1","bank2","bound"]
            frames=Dictionary(uniqueKeysWithValues:settings.catalog.species.map{($0.id,names)})
            // The first pair is small enough for every optional behavior; the
            // remaining residents cover the catalog in its stable content order.
            species=[.treeSparrow,.redWhiskeredBulbul]+settings.catalog.species.map(\.id)
            engine.populationEnabled=false; engine.ambientEnabled=false
            engine.eventObserver={ [weak auditor] event in auditor?.observe(event) }
        }
        func measured<T>(_ name:String,_ body:()->T) -> T {
            let begin=DispatchTime.now().uptimeNanoseconds
            let result=body()
            let ms=Double(DispatchTime.now().uptimeNanoseconds-begin)/1_000_000
            let samples=timings[phase]?[name] ?? WallSamples(); samples.append(ms)
            timings[phase,default:[:]][name]=samples
            return result
        }
        @discardableResult func command(_ command:EngineCommand) -> BehaviorResult {
            let result=measured("command"){engine.handle(command)}
            auditor.metrics.commands+=1
            if result.accepted {auditor.metrics.acceptedCommands+=1} else {auditor.metrics.rejectedCommands+=1}
            inspect()
            return result
        }
        func inspect() {
            let snapshots=measured("snapshot"){(engine.renderSnapshot(),engine.propSnapshot())}
            auditor.sample(engine,birds:snapshots.0,props:snapshots.1,birdLimit:config.birds)
        }
        func sampleWorld() {
            let value=measured("worldSampling") { () -> BehaviorWorld in
                var hosts=baseHosts
                if moving {
                    let offset=CGFloat((sampleTick/6)%40)*0.25
                    for i in hosts.indices {hosts[i].rect.origin.x+=offset}
                }
                if removed {hosts.removeAll{$0.id==100}}
                let area=screens[(sampleTick/(60*4))%screens.count]
                let pointer:CGPoint
                if sweep {
                    pointer=CGPoint(x:area.minX+200+CGFloat((sampleTick/6)%20)*100,y:area.minY+420)
                } else {pointer=CGPoint(x:screens[0].minX+1000,y:screens[0].minY+750)}
                return BehaviorWorld(screens:screens,displays:screens,surfaces:hosts,pointer:pointer,availableFrames:frames)
            }
            if engine.world.surfaces.contains(where:{$0.id==100}) && !value.surfaces.contains(where:{$0.id==100}) {auditor.metrics.hostRemovalTransitions+=1}
            measured("worldUpdate"){engine.updateWorld(value,sampleDT:0.1)}
            auditor.metrics.worldSamples+=1
            if sweep {auditor.metrics.pointerSweepSamples+=1}
            inspect()
        }
        func makeBird(_ index:Int) -> Bird {
            // Keep a useful pair on the same display and host even with four
            // displays. Every other bird has bounded, separated initial feet.
            let display=index<2 ? 0:(index-2)%config.displays
            let ordinal=index<2 ? index:(index-2)/config.displays
            let row=index<2 ? 7:min(6,ordinal/8)
            let host=baseHosts[display*8+row]
            let profile=engine.settings.catalog.profile(index==2 ? .treeSparrow:species[index%species.count])
            // One endpoint resident exercises the complete two-slot excursion.
            let x=index==2 ? Geometry.perchX(0,rect:host.rect)+90*profile.relativeScale:
                (index<2 ? host.rect.minX+700+CGFloat(index)*280:host.rect.minX+180+CGFloat(ordinal%8)*250)
            let fraction=(x-Geometry.perchX(0,rect:host.rect))/(Geometry.perchX(1,rect:host.rect)-Geometry.perchX(0,rect:host.rect))
            let bird=Bird(position:.zero,fraction:fraction,profile:profile,random:{0.5})
            bird.perch(on:host,spriteScale:engine.spriteScale(for:bird)); bird.perchDuration=600
            return bird
        }
        func tick(_ index:Int) {
            sampleTick=index
            if index%6==0 {sampleWorld()}
            measured("advance"){engine.advance(BehaviorEngine.step)}
            inspect()
        }
        func settings(_ enabled:Bool) {
            var value=engine.settings
            value.pointerVisits=enabled; value.flockPasses=enabled; value.socialInteractions=enabled
            value.perchActions=enabled; value.leafPlayEnabled=enabled; value.ambientLeafPlayEnabled=enabled
            value.sideHopEnabled=enabled; value.takeoffPreparationEnabled=enabled; value.passiveAttentionEnabled=enabled
            value.pointerFollowEnabled=enabled;value.edgePeekEnabled=enabled
            measured("settings"){engine.applySettings(value)}; auditor.metrics.settingsChanges+=1; inspect()
        }
        func pause(_ value:Bool) {
            if engine.paused != value {auditor.metrics.pauseTransitions+=1}
            command(.pause(value))
        }
        func lifecycle(_ reason:BehaviorReason) {
            command(.cancelAmbient(reason)); command(.cancelAmbient(reason))
            auditor.metrics.lifecycleCancellations+=2
        }
        func activeCommand(_ second:Int) {
            if config.autonomous {
                // One initial scene probes a complete prop lifecycle. Afterwards
                // only external interruptions are scripted; the planner chooses
                // every new behavior itself for the entire active workload.
                let interruptions:Set<Int>=[86,87,88,89,90,94,96,98,100,102,104,106,108,109]
                guard second==0 || interruptions.contains(second%120) else {return}
            }
            switch second%120 {
            case 0:command(.releaseLeafAfter(0.1))
            case 18:command(.socialGreeting(.preview))
            case 24:command(.socialMotion(.sideBySide,.preview))
            case 34:command(.socialMotion(.giveWay,.preview))
            case 46:command(.socialMotion(.pairedTakeoff,.preview))
            case 58:command(.previewPointerAfter(0.1))
            case 72:command(.flockPass(.preview))
            case 80:command(.edgePeek(.preview))
            case 84:
                if let id=engine.birds.first(where:{engine.role(of:$0) == .resident}).flatMap({engine.id(of:$0)}) {command(.relocate(id))}
            case 86:pause(true); if !config.autonomous {command(.pointerVisit(.preview))}
            case 87:pause(false)
            case 88:settings(false); if !config.autonomous {command(.sideHop(.preview))}
            case 89:settings(true)
            case 90:moving=true; sweep=true
            case 94:removed=true
            case 96:removed=false
            case 98:
                if let bird=engine.birds.first(where:{engine.role(of:$0) == .resident}),let id=engine.id(of:bird) {
                    command(.remove(id)); auditor.metrics.residentRemovals+=1
                    auditor.check("ecologyMemory",engine.perchPlanner.ecology(id)==nil)
                    auditor.check("runLifecycle",command(.remove(id)) == .rejected(.missingBird))
                    auditor.metrics.repeatedRemovalChecks+=1
                    engine.register(makeBird(second/120%config.birds)); auditor.metrics.replacementBirds+=1; inspect()
                }
            case 100:lifecycle(.sleep)
            case 102:lifecycle(.screensChanged)
            case 104:lifecycle(.spaceChanged)
            case 106:
                moving=false; sweep=false; command(.clearProps)
                if !config.autonomous {command(.releaseLeafAfter(3))}
            case 108:pause(true)
            case 109:pause(false)
            case 110:engine.ambientEnabled=true; command(.perchAction(.rest,.preview)); command(.attention(.watch,.preview))
            case 116:command(.attention(.alert,.preview)); command(.prepareTakeoff(.preview))
            case 119:engine.ambientEnabled=false
            default:break
            }
        }
        func timingReport(_ phase:String) -> [String:Timing] {(timings[phase] ?? [:]).mapValues(\.report)}
        func run() -> Report {
            sampleWorld()
            for i in 0..<config.birds {engine.register(makeBird(i))}
            inspect(); command(.perchAction(.preen,.preview))
            for tickIndex in 0..<warmupSteps {
                if tickIndex==4*60 {
                    if config.birds>=3 {command(.edgePeek(.preview))}
                    command(.sideHop(.preview))
                }
                tick(tickIndex)
            }
            phase="active"
            engine.ambientEnabled=config.autonomous
            let activeSteps=Int(ceil(config.seconds/BehaviorEngine.step))
            for index in 0..<activeSteps {
                if index%60==0 {activeCommand(index/60)}
                tick(index)
            }
            // Stop producing work, resume clocks, and drain finite runs without
            // moving/removing hosts or toggling behavior settings underneath them.
            phase="drain"; engine.ambientEnabled=false; engine.populationEnabled=false; engine.autonomousRouting=false
            pause(false)
            let beforeDrain=engine.activeRunCount, completed=auditor.metrics.completedRuns
            var drainSteps=0
            while drainSteps<drainLimit && (engine.activeRunCount>0 || engine.hasPointerPreview || engine.hasLeafPreview) {
                measured("advance"){engine.advance(BehaviorEngine.step)}; inspect(); drainSteps+=1
            }
            let afterDrain=engine.activeRunCount
            auditor.metrics.drainCompletions=auditor.metrics.completedRuns-completed
            let idle=afterDrain==0 && !engine.hasPointerPreview && !engine.hasLeafPreview
            phase="cleanup"
            let cancellations=auditor.metrics.cancelledRuns
            lifecycle(.shutdown)
            auditor.metrics.explicitCleanupCancellations=auditor.metrics.cancelledRuns-cancellations
            let retained=engine.residentCount
            var removedBirds=0
            // Explicitly remove *all* current birds; cancellation alone quite
            // correctly retains residents and their ecology memory.
            for bird in engine.birds {
                guard let id=engine.id(of:bird) else {continue}
                if command(.remove(id)).accepted {removedBirds+=1}
                auditor.check("ecologyMemory",engine.perchPlanner.ecology(id)==nil)
                auditor.check("runLifecycle",command(.remove(id)) == .rejected(.missingBird))
                auditor.metrics.repeatedRemovalChecks+=1
            }
            command(.clearProps); lifecycle(.shutdown); inspect()
            auditor.finish(requiredCompletedKinds:["preen","leafPlay"]+(config.birds>=3 ? ["edgePeek"]:[]),requireAutonomy:config.autonomous && config.seconds>=120)
            let cleanup=Cleanup(activeRunsBeforeDrain:beforeDrain,activeRunsAfterDrain:afterDrain,drainReachedIdle:idle,
                naturallyCompletedDuringDrain:auditor.metrics.drainCompletions,explicitlyCancelledRuns:auditor.metrics.explicitCleanupCancellations,
                residentsBeforeRemoval:retained,explicitlyRemovedBirds:removedBirds,activeRuns:engine.activeRunCount,birds:engine.birds.count,
                pendingBirds:engine.pendingCount,leases:engine.leasedBirdCount,reservations:engine.reservedLandingCount,props:engine.scenePropCount,
                ecologyMemories:engine.perchPlanner.rhythms.count,visitorLeases:engine.activeVisitorCount,
                retainedVisitorProfiles:engine.rememberedVisitorCount,pendingPreviews:(engine.hasLeafPreview ? 1:0)+(engine.hasPointerPreview ? 1:0))
            return Report(configuration:config,workload:Workload(version:2,fixedStepSeconds:BehaviorEngine.step,activeSteps:activeSteps,
                warmupSteps:warmupSteps,drainSteps:drainSteps,drainLimitSteps:drainLimit,worldSampleEverySteps:6,timingSampleLimit:WallSamples.limit,
                frameManifest:"Existing BirdArt atlas vocabulary, keyed by SpeciesCatalog.standard entries; no renderer assets loaded",
                species:Array(Set((0..<config.birds).map{($0==2 ? SpeciesID.treeSparrow:species[$0%species.count]).rawValue})).sorted()),auditor:auditor,cleanup:cleanup,
                timings:Timings(method:"Monotonic wall milliseconds; deterministic reservoir (4096/category/phase), nearest-rank percentiles; max over every call. No machine-independent performance threshold.",
                    warmup:timingReport("warmup"),active:timingReport("active"),drain:timingReport("drain"),cleanup:timingReport("cleanup")))
        }
    }
}
