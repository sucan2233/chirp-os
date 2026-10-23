import Foundation

public struct HoverTracker<ID:Equatable> {
    public private(set) var target:ID?
    private var started:Double = 0
    public init() {}
    public mutating func update(_ hit:ID?, now:Double, delay:Double = 1) -> ID? {
        guard let hit else {target=nil;return nil}
        if target != hit {target=hit;started=now}
        let wait=delay.isFinite ? max(0,delay):1
        return now-started >= wait ? hit:nil
    }
}
