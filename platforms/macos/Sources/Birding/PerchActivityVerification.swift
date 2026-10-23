import AppKit
import BirdingCore

enum PerchActivityVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let d=DesktopController();d.automaticPopulation=false;d.scale=1.5;d.settings.hoverDelay=0
        let display=d.displayRects[0],work=d.screenRects[0]
        let host=Surface(id:901,rect:CGRect(x:work.minX+60,y:work.midY,width:work.width-120,height:180))
        let far=CGPoint(x:work.minX+10,y:work.minY+10)
        let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host);bird.perchDuration=600;bird.facingRight=false
        d.birds=[bird];d.surfaces=[host]
        let window=OverlayPanel(contentRect:NSScreen.screens[0].frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
        let view=DesktopView(frame:CGRect(origin:.zero,size:window.frame.size));view.controller=d;view.desktopRect=display
        window.contentView=view;window.orderFrontRegardless()
        defer {window.orderOut(nil)}
        checks["perchActionsHaveRealFramesForAllSpecies"]=d.arts.values.allSatisfy {art in
            ["stand","blink","preen0","preen1"].allSatisfy{art.frames[$0] != nil}
        }
        for action:PerchActionKind in [.rest,.preen] {
            d.engine.handle(.cancelAmbient(.screensChanged));bird.perch(on:host);bird.facingRight=false
            d.syncWorld(at:far,buttonsDown:false)
            let started=d.engine.handle(.perchAction(action,.preview)).accepted
            let desired:Set<String>=action == .rest ? ["blink"]:["preen0","preen1"]
            var observed=Set<String>(),rendered=true,hit=true,hover=true
            for step in 0..<90 {
                d.advanceBirds(1.0/60,at:far,buttonsDown:false)
                guard let state=d.engine.renderSnapshot().first,desired.contains(state.frameName),!observed.contains(state.frameName) else {continue}
                observed.insert(state.frameName)
                view.updateSprites()
                let contents=view.layer?.sublayers?.first?.sublayers?.first?.contents as AnyObject?
                rendered = rendered && contents === d.arts[state.species]!.frames[state.frameName]
                let art=d.arts[state.species]!
                let pixel=(0..<48*48).first{art.contains(frame:state.frameName,x:$0%48,y:$0/48)}!
                let x=state.facingRight ? pixel%48:47-pixel%48
                let point=CGPoint(x:state.rect.minX+(CGFloat(x)+0.5)*state.scale,y:state.rect.minY+(CGFloat(pixel/48)+0.5)*state.scale)
                hit = hit && d.bird(at:point) === bird
                d.updateHover(now:Double(step),at:point);hover = hover && d.hoveredBird === bird
                view.updateSprites()
                try SettingsVerification.snapshot(window,to:folder.appendingPathComponent("perch-\(action.rawValue)-\(state.frameName).png"))
            }
            checks["\(action.rawValue)PoseReachesActualSpriteLayer"]=started && observed==desired && rendered
            checks["\(action.rawValue)MirroredScaledPixelsHitAndHover"]=started && !observed.isEmpty && hit && hover
            let coveredPoint=ExpandedVerification.visiblePoint(on:bird,in:d)
            d.surfaces.insert(Surface(id:902,rect:CGRect(x:coveredPoint.x-1,y:coveredPoint.y-1,width:2,height:2)),at:0)
            checks["\(action.rawValue)OccludedPixelsDoNotHit"]=started && !observed.isEmpty && d.bird(at:coveredPoint) == nil
            d.engine.handle(.cancelAmbient(.screensChanged));d.surfaces=[host]
            bird.perch(on:host);d.syncWorld(at:far,buttonsDown:false)
            let restarted=d.engine.handle(.perchAction(action,.preview)).accepted
            for _ in 0..<30 {d.advanceBirds(1.0/60,at:far,buttonsDown:false)}
            if let state=d.engine.renderSnapshot().first {
                let point=ExpandedVerification.visiblePoint(on:bird,in:d),position=bird.position
                checks["\(action.rawValue)ClickReleasesPoseAndKeepsIdentity"]=restarted && d.relocateBird(at:point) && d.engine.behavior(of:bird) == .relocate &&
                    d.engine.renderSnapshot().first?.id == state.id && bird.position==position && d.engine.renderSnapshot().first?.frameName == bird.frameName
            }
        }
    }
}
