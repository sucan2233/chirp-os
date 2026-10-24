import AppKit
import BirdingCore

enum AttentionVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let d=DesktopController();d.automaticPopulation=false;d.scale=1.5;d.settings.hoverDelay=0
        let display=d.displayRects[0],work=d.screenRects[0]
        let host=Surface(id:951,pid:42,rect:CGRect(x:work.minX+60,y:work.midY,width:work.width-120,height:180))
        let far=CGPoint(x:work.minX+10,y:work.minY+10)
        let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;bird.facingRight=false
        d.birds=[bird];d.surfaces=[host]
        let window=OverlayPanel(contentRect:NSScreen.screens[0].frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
        let view=DesktopView(frame:CGRect(origin:.zero,size:window.frame.size));view.controller=d;view.desktopRect=display
        window.contentView=view;window.orderFrontRegardless()
        defer {window.orderOut(nil)}
        for action in AttentionKind.allCases {
            d.engine.handle(.cancelAmbient(.screensChanged));bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600
            bird.facingRight=false;d.syncWorld(at:far,buttonsDown:false)
            let started=d.engine.handle(.attention(action,.preview)).accepted,origin=bird.position
            var seen=Set<String>(),layerMatches=true,hit=true,turned=false
            for step in 0..<180 {
                let pointer=CGPoint(x:bird.position.x+150,y:bird.position.y-30)
                d.advanceBirds(1.0/60,at:pointer,buttonsDown:false)
                guard d.engine.behavior(of:bird)==action.behavior,let state=d.engine.renderSnapshot().first else {continue}
                turned = turned || state.facingRight
                guard !seen.contains(state.frameName) else {continue}
                seen.insert(state.frameName);view.updateSprites()
                let contents=view.layer?.sublayers?.first?.sublayers?.first?.contents as AnyObject?
                layerMatches = layerMatches && contents === d.arts[state.species]?.frames[state.frameName]
                let point=ExpandedVerification.visiblePoint(on:bird,in:d)
                hit = hit && d.bird(at:point) === bird
                d.updateHover(now:Double(step),at:point);hit = hit && d.hoveredBird === bird
                try SettingsVerification.snapshot(window,to:folder.appendingPathComponent("attention-\(action.rawValue)-\(state.frameName).png"))
            }
            let expected:Set<String>=action == .watch ? ["lookNear","lookFar"]:["alertRise","alertHold","alertRelax"]
            checks["\(action.rawValue)ActualEnhancedPoseLayers"]=started && seen==expected && layerMatches
            checks["\(action.rawValue)TurnsAndPreservesFootAndModelFacing"]=started && turned && !bird.facingRight && bird.position==origin
            checks["\(action.rawValue)VisiblePixelsHitAndHover"]=started && hit
            checks["\(action.rawValue)ReleasesLeaseAfterCompletion"]=started && d.engine.activeRunCount==0 && d.engine.leasedBirdCount==0
            d.syncWorld(at:far,buttonsDown:false)
            let again=d.engine.handle(.attention(action,.preview)).accepted
            let point=ExpandedVerification.visiblePoint(on:bird,in:d)
            checks["\(action.rawValue)ClickRelocatesSameBird"]=again && d.relocateBird(at:point) && d.engine.behavior(of:bird) == .relocate && d.birds.first === bird
        }
    }
}
