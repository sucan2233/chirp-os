import Foundation
import CoreFoundation
import CoreGraphics

public enum BehaviorRecordingError:Error,LocalizedError {
    case invalid(String)
    public var errorDescription:String? {if case .invalid(let why)=self {return "Behavior recording: \(why)"};return nil}
}

/// Named coordinates keep the disk format independent of CoreGraphics encodings.
public struct RecordedPoint:Codable,Equatable {
    public var x,y:Double
    public init(_ point:CGPoint) {x=Double(point.x);y=Double(point.y)}
    var value:CGPoint {CGPoint(x:x,y:y)}
    var valid:Bool {x.isFinite && y.isFinite && abs(x)<=1_000_000 && abs(y)<=1_000_000}
}
public struct RecordedRect:Codable,Equatable {
    public var x,y,width,height:Double
    public init(_ rect:CGRect) {x=Double(rect.minX);y=Double(rect.minY);width=Double(rect.width);height=Double(rect.height)}
    var value:CGRect {CGRect(x:x,y:y,width:width,height:height)}
    var valid:Bool {[x,y,width,height].allSatisfy{$0.isFinite && abs($0)<=1_000_000} && width>0 && height>=0}
}
public struct RecordedSurface:Codable,Equatable {
    public var id:UInt32,pid:Int32,layer:Int
    public var rect:RecordedRect
    public var isGround:Bool
    init(_ surface:Surface) {id=surface.id;pid=surface.pid;layer=surface.layer;rect=RecordedRect(surface.rect);isGround=surface.isGround}
    var value:Surface {Surface(id:id,pid:pid,rect:rect.value,layer:layer,isGround:isGround)}
}
public struct RecordedWorld:Codable,Equatable {
    public var screens,displays:[RecordedRect]
    public var surfaces:[RecordedSurface]
    public var scale:Double,pointer:RecordedPoint
    public var buttonsDown:Bool
    public var localMinuteOfDay:Int?
    public var availableFrames:[String:[String]]?
    public init(_ world:BehaviorWorld) {
        screens=world.screens.map(RecordedRect.init);displays=world.displays.map(RecordedRect.init)
        surfaces=world.surfaces.map(RecordedSurface.init);scale=Double(world.scale);pointer=RecordedPoint(world.pointer)
        buttonsDown=world.buttonsDown;localMinuteOfDay=world.localMinuteOfDay
        availableFrames=Dictionary(uniqueKeysWithValues:world.availableFrames.map{($0.key.rawValue,$0.value.sorted())})
    }
    func validated(inheriting previous:BehaviorWorld?=nil) throws -> BehaviorWorld {
        let frames=availableFrames ?? previous.map{Dictionary(uniqueKeysWithValues:$0.availableFrames.map{($0.key.rawValue,$0.value.sorted())})} ?? [:]
        guard localMinuteOfDay.map({(0..<1440).contains($0)}) ?? true,
              screens.count<=16,displays.count<=16,surfaces.count<=256,
              screens.allSatisfy({$0.valid && $0.height>0}),displays.allSatisfy({$0.valid && $0.height>0}),
              surfaces.allSatisfy({$0.rect.valid && ($0.isGround || $0.rect.height>0)}),
              Set(surfaces.map(\.id)).count==surfaces.count,
              scale.isFinite,scale>0,scale<=10,pointer.valid,
              frames.count<=SpeciesID.allCases.count,
              frames.allSatisfy({SpeciesID(rawValue:$0.key) != nil && $0.value.count<=128 && $0.value.allSatisfy{$0.count<=64}}) else {
            throw BehaviorRecordingError.invalid("invalid world bounds, surfaces or frame manifest")
        }
        return BehaviorWorld(screens:screens.map(\.value),displays:displays.map(\.value),surfaces:surfaces.map(\.value),
            scale:scale,pointer:pointer.value,buttonsDown:buttonsDown,
            availableFrames:Dictionary(uniqueKeysWithValues:frames.map{(SpeciesID(rawValue:$0.key)!,Set($0.value))}),
            localMinuteOfDay:localMinuteOfDay)
    }
}
public struct RecordedSimulationOptions:Codable,Equatable {
    public var population,ambient,routing:Bool
    init(_ engine:BehaviorEngine) {population=engine.populationEnabled;ambient=engine.ambientEnabled;routing=engine.autonomousRouting}
    func apply(to engine:BehaviorEngine) {engine.populationEnabled=population;engine.ambientEnabled=ambient;engine.autonomousRouting=routing}
}

/// Explicit tagged payloads also make these files consumable by other platforms.
public struct RecordedCommand:Codable {
    public var name:String
    public var source:String?,action:String?,target:String?,reason:String?
    public var point:RecordedPoint?,delay:Double?,flag:Bool?
    public init(_ command:EngineCommand) {
        switch command {
        case .relocate(let id):name="relocate";target=String(id.rawValue)
        case .pointerVisit(let value):name="pointerVisit";source=value.rawValue
        case .flockPass(let value):name="flockPass";source=value.rawValue
        case .socialGreeting(let value):name="socialGreeting";source=value.rawValue
        case .socialMotion(let kind,let value):name="socialMotion";action=kind.rawValue;source=value.rawValue
        case .perchAction(let kind,let value):name="perchAction";action=kind.rawValue;source=value.rawValue
        case .sideHop(let value):name="sideHop";source=value.rawValue
        case .prepareTakeoff(let value):name="prepareTakeoff";source=value.rawValue
        case .attention(let kind,let value):name="attention";action=kind.rawValue;source=value.rawValue
        case .previewPointerAfter(let value):name="previewPointerAfter";delay=max(0,min(10,value.isFinite ? value:3))
        case .leafPlay(let value,let origin):name="leafPlay";point=RecordedPoint(value);source=origin.rawValue
        case .releaseLeafAfter(let value):name="releaseLeafAfter";delay=max(0,min(10,value.isFinite ? value:3))
        case .clearProps:name="clearProps"
        case .removeProp(let id):name="removeProp";target=String(id.rawValue)
        case .pointerClick:name="pointerClick"
        case .pause(let value):name="pause";flag=value
        case .cancelAmbient(let value):name="cancelAmbient";reason=value.rawValue
        case .scatter:name="scatter"
        case .remove(let id):name="remove";target=String(id.rawValue)
        }
    }
    func validated() throws -> EngineCommand {
        func bad() -> BehaviorRecordingError {.invalid("invalid command \(name)")}
        func origin() throws -> BehaviorSource {guard let source,let value=BehaviorSource(rawValue:source) else {throw bad()};return value}
        func id() throws -> UInt64 {guard let target,let value=UInt64(target),value>0 else {throw bad()};return value}
        func wait() throws -> Double {guard let delay,delay.isFinite,(0...10).contains(delay) else {throw bad()};return delay}
        switch name {
        case "relocate":return .relocate(BirdID(try id()))
        case "pointerVisit":return .pointerVisit(try origin())
        case "flockPass":return .flockPass(try origin())
        case "socialGreeting":return .socialGreeting(try origin())
        case "socialMotion":guard let action,let kind=SocialMotionKind(rawValue:action) else {throw bad()};return .socialMotion(kind,try origin())
        case "perchAction":guard let action,let kind=PerchActionKind(rawValue:action) else {throw bad()};return .perchAction(kind,try origin())
        case "sideHop":return .sideHop(try origin())
        case "prepareTakeoff":return .prepareTakeoff(try origin())
        case "attention":guard let action,let kind=AttentionKind(rawValue:action) else {throw bad()};return .attention(kind,try origin())
        case "previewPointerAfter":return .previewPointerAfter(try wait())
        case "leafPlay":guard let point,point.valid else {throw bad()};return .leafPlay(at:point.value,source:try origin())
        case "releaseLeafAfter":return .releaseLeafAfter(try wait())
        case "clearProps":return .clearProps
        case "removeProp":return .removeProp(ScenePropID(try id()))
        case "pointerClick":return .pointerClick
        case "pause":guard let flag else {throw bad()};return .pause(flag)
        case "cancelAmbient":guard let reason,let why=BehaviorReason(rawValue:reason) else {throw bad()};return .cancelAmbient(why)
        case "scatter":return .scatter
        case "remove":return .remove(BirdID(try id()))
        default:throw bad()
        }
    }
}
public struct RecordedInput:Codable {
    public var kind:String
    public var world:RecordedWorld?,settings:BirdSettings?,command:RecordedCommand?,options:RecordedSimulationOptions?
    public var visitorMemory:VisitorMemoryArchive?
    public var elapsed:Double?,sampleDT:Double?,remaining:Double?
    public var lower:Int?,upper:Int?,repeatCount:Int?
    public var bird:String?,entering:Bool?,avoiding:RecordedPoint?
    init(kind:String) {self.kind=kind}
    static func world(_ world:BehaviorWorld,sampleDT:Double?) -> Self {
        var value=Self(kind:"world");value.world=RecordedWorld(world);value.sampleDT=sampleDT;return value
    }
    static func settings(_ settings:BirdSettings) -> Self {var value=Self(kind:"settings");value.settings=settings;return value}
    static func command(_ command:EngineCommand) -> Self {var value=Self(kind:"command");value.command=RecordedCommand(command);return value}
    static func advance(_ elapsed:Double,in engine:BehaviorEngine) -> Self {
        var value=Self(kind:"advance");value.elapsed=elapsed;value.options=RecordedSimulationOptions(engine);return value
    }
    static func population(_ population:Population) -> Self {
        var value=Self(kind:"population");value.lower=population.range.lower;value.upper=population.range.upper
        value.remaining=population.remaining;return value
    }
}
public struct RecordedFixtureBird:Codable {
    public var species:SpeciesID,host:UInt32,fraction:Double,perchDuration:Double
    public var facingRight:Bool
    func make(in engine:BehaviorEngine) throws -> Bird {
        guard let surface=engine.world.surfaces.first(where:{$0.id==host}),fraction.isFinite,(0...1).contains(fraction),
              perchDuration.isFinite,(0.1...3600).contains(perchDuration) else {throw BehaviorRecordingError.invalid("invalid fixture bird")}
        let bird=Bird(position:.zero,fraction:fraction,profile:engine.settings.catalog.profile(species),random:{0.5})
        bird.perch(on:surface,spriteScale:engine.spriteScale(for:bird));bird.perchDuration=perchDuration;bird.facingRight=facingRight
        return bird
    }
}
public struct RecordedEvent:Codable,Equatable {
    public var sequence:String,time:Double,run:String?,kind:String?,source:String,type:String,participants:[String],reason:String?
    init(_ event:BehaviorEvent) {
        sequence=String(event.sequence);time=event.time;run=event.runID.map{String($0.rawValue)};kind=event.kind?.rawValue
        source=event.source.rawValue;type=event.type.rawValue;participants=event.participants.map{String($0.rawValue)};reason=event.reason?.rawValue
    }
}
public struct RecordedBirdState:Codable,Equatable {
    public var id:String,species:String,position:RecordedPoint,facingRight:Bool,frame:String,hop:Double,scale:Double
    public var state:String,behavior:String?,disturbance:Double?,cooldowns:[String:Double]?
    public var visitorID:String?,familiarity:Double?
    init(_ value:BirdRenderState,engine:BehaviorEngine) {
        id=String(value.id.rawValue);species=value.species.rawValue;position=RecordedPoint(value.position)
        facingRight=value.facingRight;frame=value.frameName;hop=Double(value.hopOffset);scale=Double(value.scale)
        let bird=engine.bird(value.id)!
        state=bird.state.rawValue;behavior=engine.behavior(of:bird)?.rawValue
        let ecology=engine.ecology(of:bird);disturbance=ecology?.disturbance
        visitorID=engine.visitor(of:bird)?.id;familiarity=ecology?.familiarity
        cooldowns=ecology.map{Dictionary(uniqueKeysWithValues:$0.cooldowns.map{($0.key.rawValue,$0.value)})}
    }
}
public struct RecordedPropState:Codable,Equatable {
    public var id:String,kind:String,position:RecordedPoint,size:Double,rotation:Double,opacity:Double
    init(_ prop:ScenePropRenderState) {
        id=String(prop.id.rawValue);kind=prop.kind.rawValue;position=RecordedPoint(prop.position);size=Double(prop.size)
        rotation=Double(prop.rotation);opacity=prop.opacity
    }
}
public struct BehaviorReplayReport:Codable,Equatable {
    public var time:Double,paused:Bool,residents:Int,transients:Int,pending:Int,runs:Int,leases:Int,reservations:Int
    public var events:[RecordedEvent],birds:[RecordedBirdState],props:[RecordedPropState]
    public var visitorMemory:VisitorMemoryArchive
    init(engine:BehaviorEngine,events:[RecordedEvent]) {
        time=engine.time;paused=engine.paused;residents=engine.residentCount;transients=engine.passingCount;pending=engine.pendingCount
        runs=engine.activeRunCount;leases=engine.leasedBirdCount;reservations=engine.reservedLandingCount
        self.events=events;birds=engine.renderSnapshot().map{RecordedBirdState($0,engine:engine)}
        props=engine.propSnapshot().map(RecordedPropState.init)
        visitorMemory=engine.visitorMemoryArchive
    }
    public func save(to url:URL) throws {try BehaviorInputLog.encoder().encode(self).write(to:url,options:.atomic)}
}

/// Files are local, opt-in recordings of geometry and input only. They contain
/// no window titles, document text or screenshots, and are never uploaded.
public struct BehaviorInputLog:Codable {
    public static let currentVersion=1,engineVersion=4,maximumInputs=60_000,maximumBytes=32*1024*1024
    public var version:Int=Self.currentVersion
    public var simulationVersion:Int=Self.engineVersion
    public var seed:String
    public var settings:BirdSettings
    public var initialWorld:RecordedWorld?
    public var fixtureBirds:[RecordedFixtureBird]?
    public var inputs:[RecordedInput]=[]
    public var expected:BehaviorReplayReport?
    public var failure:String?
    init(seed:UInt64,settings:BirdSettings) {self.seed=String(seed);self.settings=settings}
    static func encoder() -> JSONEncoder {let value=JSONEncoder();value.outputFormatting=[.sortedKeys];return value}
    public static func load(from url:URL) throws -> Self {
        let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard size<=maximumBytes else {throw BehaviorRecordingError.invalid("file exceeds 32 MiB")}
        return try decode(Data(contentsOf:url))
    }
    public static func decode(_ data:Data) throws -> Self {
        guard data.count<=maximumBytes else {throw BehaviorRecordingError.invalid("file exceeds 32 MiB")}
        // Reject incompatible envelopes before decoding newer nested payloads.
        guard let envelope=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let version=envelope["version"] as? NSNumber,CFGetTypeID(version) != CFBooleanGetTypeID(),version.doubleValue==Double(currentVersion),
              let simulation=envelope["simulationVersion"] as? NSNumber,CFGetTypeID(simulation) != CFBooleanGetTypeID(),simulation.doubleValue==Double(engineVersion) else {
            throw BehaviorRecordingError.invalid("unsupported recording or simulation version")
        }
        let value=try JSONDecoder().decode(Self.self,from:data)
        try value.validateEnvelope();return value
    }
    func validateEnvelope() throws {
        guard version==Self.currentVersion,simulationVersion==Self.engineVersion,UInt64(seed) != nil,
              inputs.count<=Self.maximumInputs,(fixtureBirds?.count ?? 0)<=64,failure==nil else {
            throw BehaviorRecordingError.invalid(failure ?? "unsupported or oversized recording")
        }
        _=try BirdSettings.decode(JSONEncoder().encode(settings))
    }
    public func save(to url:URL) throws {
        try validateEnvelope()
        let data=try Self.encoder().encode(self)
        guard data.count<=Self.maximumBytes else {throw BehaviorRecordingError.invalid("file exceeds 32 MiB")}
        try data.write(to:url,options:.atomic)
    }
    public func replay(callbackHz:Int?=nil) throws -> BehaviorReplayReport {
        try validateEnvelope()
        if let hz=callbackHz,![30,60,120].contains(hz) {throw BehaviorRecordingError.invalid("callbackHz must be 30, 60 or 120")}
        let engine=BehaviorEngine(seed:UInt64(seed)!,settings:try BirdSettings.decode(JSONEncoder().encode(settings)))
        var events:[RecordedEvent]=[]
        engine.eventObserver={events.append(RecordedEvent($0))}
        if let initialWorld {engine.updateWorld(try initialWorld.validated())}
        if let fixtureBirds {engine.installFixtureBirds(try fixtureBirds.map{try $0.make(in:engine)})}
        var totalElapsed=0.0,totalCallbacks=0
        for (index,input) in inputs.enumerated() {
            func bad() -> BehaviorRecordingError {.invalid("invalid input \(index): \(input.kind)")}
            switch input.kind {
            case "visitorMemory":
                guard let memory=input.visitorMemory else {throw bad()}
                try engine.restoreVisitorMemory(memory)
            case "world":
                guard let world=input.world,input.sampleDT.map({$0.isFinite && $0>0}) ?? true else {throw bad()}
                engine.updateWorld(try world.validated(inheriting:engine.world),sampleDT:input.sampleDT)
            case "settings":
                guard let settings=input.settings else {throw bad()}
                engine.applySettings(try BirdSettings.decode(JSONEncoder().encode(settings)))
            case "command":guard let command=input.command else {throw bad()};_=engine.handle(try command.validated())
            case "advance":
                guard let elapsed=input.elapsed,elapsed.isFinite,elapsed>=0,let options=input.options else {throw bad()}
                options.apply(to:engine)
                let count=input.repeatCount ?? 1
                guard (1...108_000).contains(count) else {throw bad()}
                totalCallbacks+=count
                let effective=min(0.05,elapsed);totalElapsed+=effective*Double(count)
                guard totalElapsed<=3600,totalCallbacks<=216_000 else {throw BehaviorRecordingError.invalid("simulation exceeds one hour or callback limit")}
                for _ in 0..<count {
                    if let hz=callbackHz {
                        var remaining=effective
                        while remaining>0 {let dt=min(remaining,1/Double(hz));engine.advance(dt);remaining-=dt}
                    } else {engine.advance(elapsed)}
                }
            case "population":
                guard let lower=input.lower,let upper=input.upper,let range=PopulationRange(lower:lower,upper:upper),
                      let remaining=input.remaining,remaining.isFinite,(0...60).contains(remaining) else {throw bad()}
                engine.population=Population(range:range,remaining:remaining)
            case "reconcileLayout":engine.reconcileLayout()
            case "arrive":engine.bringInBird()
            case "depart","route":
                guard let raw=input.bird,let id=UInt64(raw),let bird=engine.bird(BirdID(id)) else {throw bad()}
                if input.kind == "depart" {engine.sendAway(bird)}
                else {
                    guard let entering=input.entering,input.avoiding.map(\.valid) ?? true else {throw bad()}
                    _=engine.route(bird,entering:entering,avoiding:input.avoiding?.value)
                }
            default:throw bad()
            }
        }
        return BehaviorReplayReport(engine:engine,events:events)
    }
}

final class BehaviorInputRecorder {
    var log:BehaviorInputLog
    var events:[RecordedEvent]=[]
    var depth=0
    private var lastWorld:RecordedWorld?
    private var lastFrames:[String:[String]]?
    init(seed:UInt64,settings:BirdSettings) {log=BehaviorInputLog(seed:seed,settings:settings)}
    func append(_ input:RecordedInput) {
        guard log.failure==nil else {return}
        guard log.inputs.count<BehaviorInputLog.maximumInputs else {log.failure="recording input limit reached";return}
        var compact=input
        if let world=input.world,input.kind == "world" {
            if input.sampleDT==nil,log.inputs.last?.kind == "world",lastWorld==world {return}
            lastWorld=world
            if world.availableFrames==lastFrames {compact.world?.availableFrames=nil}
            else {lastFrames=world.availableFrames}
        }
        log.inputs.append(compact)
    }
    func event(_ event:BehaviorEvent) {
        guard events.count<120_000 else {log.failure="recording event limit reached";return}
        events.append(RecordedEvent(event))
    }
}
