import Foundation
import CoreGraphics

public enum SceneItemKind:String,Codable,CaseIterable {case perch,foodTray,bath,nest,leaf}
public enum SceneSupport:String,Codable {case display,ground,window}
public struct SceneInstance:Codable,Equatable,Identifiable {
    public let id:UUID
    public let kind:SceneItemKind
    public var anchor:FixedPerchAnchor
    public var revision:UInt64
    public var support:SceneSupport?
    public init(id:UUID=UUID(),kind:SceneItemKind,anchor:FixedPerchAnchor,revision:UInt64=1,support:SceneSupport?=nil) {
        self.id=id;self.kind=kind;self.anchor=anchor;self.revision=revision
        self.support=support ?? ([SceneItemKind.nest,.leaf].contains(kind) ? .window:.display)
    }
    var requiresWindowPlacement:Bool {support == .window || (support == nil && [.nest,.leaf].contains(kind))}
    public func point(in world:BehaviorWorld)->CGPoint? {
        let index=world.displays.indices.first {i in
            anchor.displayID.isEmpty ? world.displays[i]==anchor.displayFrame:
                world.displayIDs.indices.contains(i) && world.displayIDs[i]==anchor.displayID
        }
        guard let index else {return nil}
        let frame=world.displays[index]
        return CGPoint(x:frame.minX+frame.width*anchor.x,y:frame.minY+frame.height*anchor.y)
    }
}
public struct SceneLayout:Codable,Equatable {
    public var revision:UInt64=0
    public var instances:[SceneInstance]=[]
    public init() {}
    public func validate() throws {
        guard revision<UInt64.max-1,instances.count<=6,instances.filter({$0.kind == .perch}).count<=3,
              instances.filter({$0.kind != .perch}).count<=3,
              Set(instances.map(\.id)).count==instances.count,
              Set(instances.filter{$0.kind == .perch}.map{ $0.anchor.slot }).count==instances.filter({$0.kind == .perch}).count,
              instances.allSatisfy({$0.anchor.isValid && $0.revision>0 && $0.revision<UInt64.max-1}) else {
            throw SceneError.invalid("最多布置三根栖木和三个其他物件，身份、位置与栖木槽位必须有效。")
        }
    }
    public static func migrate(anchors:[FixedPerchAnchor])->Self {
        var result=Self()
        result.instances=anchors.map {anchor in
            // Stable old-slot identities make importing an unsaved migration idempotent.
            SceneInstance(id:UUID(uuidString:String(format:"00000000-0000-4000-8000-%012d",anchor.slot))!,kind:.perch,anchor:anchor)
        }
        return result
    }
}
public struct SceneLeafEffect:Codable,Equatable {
    public var anchor:FixedPerchAnchor
    public var support:SceneSupport
    /// Unreserved time. Rendering must first commit a bounded allowance.
    public var remaining:Double
    public var facingRight:Bool
}
public struct SceneResource:Codable,Equatable {
    public var revision:UInt64=0
    public var remainingUses:Int
    public var materials:[NestMaterialState]
    public var leafConsumed:Bool=false
    public var leafEffect:SceneLeafEffect?
    public init(kind:SceneItemKind) {
        remainingUses=[SceneItemKind.foodTray,.bath,.nest].contains(kind) ? 3:0
        materials=kind == .nest ? [.available,.available,.available]:[]
    }
    public var recovered:Self {
        var result=self
        result.materials=materials.map{$0 == .attached ? .spent:$0}
        return result
    }
}
/// Layout and resources have independent revisions but share one atomic file,
/// so a layout retry always starts with the newest committed resource balance.
public struct SceneArchive:Codable,Equatable {
    public var schemaVersion=1
    public var layout=SceneLayout()
    public var ledgerRevision:UInt64=0
    public var resources:[UUID:SceneResource]=[:]
    public init() {}
    public func validate() throws {
        guard schemaVersion==1 else {throw SceneError.invalid("不支持此场景文件版本，原文件已保留。")}
        try layout.validate()
        guard ledgerRevision<UInt64.max-1,resources.count<=64,resources.values.allSatisfy({
            $0.revision<UInt64.max-1 && (0...3).contains($0.remainingUses) && ($0.materials.isEmpty || $0.materials.count==3) && ($0.leafEffect.map{$0.remaining.isFinite && (0...120).contains($0.remaining) && $0.anchor.isValid} ?? true)
        }),layout.instances.allSatisfy({item in
            guard let r=resources[item.id] else {return false}
            return item.kind == .nest ? r.materials.count==3:r.materials.isEmpty
        }) else {throw SceneError.invalid("场景资源账本无效，原文件已保留。")}
    }
}
public enum SceneError:Error,LocalizedError {
    case invalid(String)
    public var errorDescription:String? {if case .invalid(let text)=self {return text};return nil}
}
public final class ScenePersistence {
    public let url:URL
    private var blocked=false
    private var expectedData:Data?
    public init(url:URL) {self.url=url}
    public func load(legacyAnchors:[FixedPerchAnchor]=[]) throws -> SceneArchive {
        guard FileManager.default.fileExists(atPath:url.path) else {
            var result=SceneArchive();result.layout = .migrate(anchors:legacyAnchors)
            for item in result.layout.instances {result.resources[item.id]=SceneResource(kind:item.kind)}
            return result
        }
        do {
            let data=try Data(contentsOf:url)
            guard data.count<=1_048_576 else {throw SceneError.invalid("场景文件过大。")}
            let value=try JSONDecoder().decode(SceneArchive.self,from:data)
            try value.validate();expectedData=data;return value
        } catch {blocked=true;throw error}
    }
    public func save(_ value:SceneArchive) throws {
        guard !blocked else {throw SceneError.invalid("场景文件损坏或版本较新，已禁止覆盖。请先修复或移走原文件。")}
        try value.validate()
        let disk=try? Data(contentsOf:url)
        guard disk==expectedData else {throw SceneError.invalid("场景文件已由其他进程修改，请重新打开应用后再试。")}
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let data=try encoder.encode(value)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if let disk {try disk.write(to:url.appendingPathExtension("backup"),options:.atomic)}
        try data.write(to:url,options:.atomic);expectedData=data
    }
}
public enum SceneEditPhase:String {case idle,editing,applying,failed,committed,cancelled}

/// Undo only edits placement intent. Resources are read from the live ledger on apply.
public struct SceneDraft {
    public private(set) var layout:SceneLayout
    public let baseRevision:UInt64
    private var undoStack:[SceneLayout]=[]
    private var redoStack:[SceneLayout]=[]
    public init(_ layout:SceneLayout) {self.layout=layout;baseRevision=layout.revision}
    public var canUndo:Bool {!undoStack.isEmpty}
    public var canRedo:Bool {!redoStack.isEmpty}
    public mutating func edit(_ body:(inout SceneLayout)->Void) {
        let previous=layout;body(&layout)
        if layout != previous {undoStack.append(previous);redoStack=[]}
    }
    public mutating func undo() {if let old=undoStack.popLast() {redoStack.append(layout);layout=old}}
    public mutating func redo() {if let next=redoStack.popLast() {undoStack.append(layout);layout=next}}
}

public struct SceneWriteDecision:Codable,Equatable {
    public let archive:SceneArchive
    public let accepted:Bool
}
