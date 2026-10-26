import AppKit
import BirdingCore

/// Pure artwork preview, advanced only by the existing desktop refresh. It
/// never records observations, creates birds or owns a timer.
final class JournalPreviewView: NSView {
    var art: BirdArt?
    var profile: SpeciesProfile?
    var silhouette = false
    var action: GalleryAction?
    private var age: Double = 0
    private var previousTime: Double?
    override var isFlipped: Bool {true}

    func advance(paused: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        defer {previousTime = now}
        guard action != nil, !paused, !silhouette, window?.isVisible == true else {return}
        if let previousTime {age += min(0.1, max(0, now - previousTime))}
        needsDisplay = true
    }
    func reset() {age = 0; previousTime = nil; needsDisplay = true}

    override func draw(_ dirtyRect: NSRect) {
        guard let art, let profile, let context = NSGraphicsContext.current?.cgContext else {return}
        let pose = action.map {GalleryPose.frame(profile.id, age: age, fps: profile.flapFPS,
                                                action: $0, speedMultiplier: profile.speed)} ?? "stand"
        context.saveGState()
        if silhouette {context.beginTransparencyLayer(auxiliaryInfo: nil)}
        art.draw(name: silhouette ? "stand" : pose, at: CGPoint(x: bounds.midX + 10, y: 88),
                 scale: 2, right: true, context: context)
        if silhouette {
            context.setBlendMode(.sourceIn); context.setFillColor(NSColor.secondaryLabelColor.cgColor)
            context.fill(bounds); context.endTransparencyLayer()
        }
        context.restoreGState()
    }
}
