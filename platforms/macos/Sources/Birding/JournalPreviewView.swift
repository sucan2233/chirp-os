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

    /// Shared by drawing and native verification; sampling never advances time.
    func frameName(at age: Double) -> String {
        guard !silhouette, let profile, let action else {return "stand"}
        return GalleryPose.frame(profile.id, age: age, fps: profile.flapFPS,
                                 action: action, speedMultiplier: profile.speed)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let art, profile != nil, let context = NSGraphicsContext.current?.cgContext else {return}
        let pose = frameName(at: age)
        context.saveGState()
        if silhouette {context.beginTransparencyLayer(auxiliaryInfo: nil)}
        art.draw(name: pose, at: CGPoint(x: bounds.midX + 10, y: 88),
                 scale: 2, right: true, context: context)
        if silhouette {
            context.setBlendMode(.sourceIn); context.setFillColor(NSColor.secondaryLabelColor.cgColor)
            context.fill(bounds); context.endTransparencyLayer()
        }
        context.restoreGState()
    }
}
