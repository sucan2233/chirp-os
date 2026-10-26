import AppKit
import BirdingCore

enum ArrivalRenderingVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let d=DesktopController();d.automaticPopulation=false;d.scale=1.5
        d.engine.ambientEnabled=false
        d.surfaces=d.groundSurfaces()
        var settings=d.settings
        for entry in settings.probabilities.entries { settings.probabilities.setWeight(0, for: entry.id) }; settings.probabilities.setManualWeight(at:settings.probabilities.entries.firstIndex{$0.id == .treeSparrow}!,to:1)
        d.settings=settings
        let windows=NSScreen.screens.map { screen -> (OverlayPanel,DesktopView) in
            let panel=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.ignoresMouseEvents=true;panel.isOpaque=false;panel.backgroundColor = .clear
            let view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size))
            view.controller=d;view.desktopRect=Geometry.quartz(screen.frame,primaryHeight:d.primaryHeight)
            panel.contentView=view;panel.orderFrontRegardless()
            return (panel,view)
        }
        defer {windows.forEach{$0.0.orderOut(nil)}}
        for prefix in ["first","later"] {
            d.birds=[];d.bringInBird()
            windows.forEach{$0.1.updateSprites()}
            func visible(_ view:DesktopView) -> CALayer? {
                view.layer?.sublayers?.first(where:{$0.mask is CAShapeLayer && !$0.isHidden})
            }
            let spawned=d.birds.count == 1
            checks[prefix+"ArrivalLayerInitiallyHidden"]=spawned && windows.allSatisfy{visible($0.1)==nil}
            var atEdge=false,hasTexture=false
            if let bird=d.birds.first {
                for _ in 0...Int(ceil(bird.flightDuration/BehaviorEngine.step)) {
                    d.advanceBirds(BehaviorEngine.step)
                    windows.forEach{$0.1.updateSprites()}
                    if let pair=windows.first(where:{visible($0.1) != nil}),let layer=visible(pair.1) {
                        let local=pair.1.bounds
                        atEdge=local.intersects(layer.frame) && !local.contains(layer.frame)
                        hasTexture=layer.sublayers?.first?.contents != nil
                        try SettingsVerification.snapshot(pair.0,to:folder.appendingPathComponent(prefix+"-arrival-edge.png"))
                        break
                    }
                }
            }
            checks[prefix+"ArrivalFirstVisibleLayerCrossesEdge"]=spawned && atEdge
            checks[prefix+"ArrivalFirstVisibleLayerHasFlightTexture"]=spawned && hasTexture
        }
    }
}
