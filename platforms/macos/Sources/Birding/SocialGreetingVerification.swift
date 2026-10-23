import AppKit
import BirdingCore

enum SocialGreetingVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let d=DesktopController();d.automaticPopulation=false;d.scale=1.5;d.settings.hoverDelay=0
        d.engine.ambientEnabled=false
        let display=d.displayRects[0],work=d.screenRects[0]
        let host=Surface(id:911,rect:CGRect(x:work.midX-250,y:work.midY,width:500,height:160))
        let far=CGPoint(x:work.minX+10,y:work.minY+10)
        let birds:[Bird]=[CGFloat(0.3),0.7].map {fraction in
            let bird=Bird(position:.zero,fraction:fraction,profile:d.catalog.profile(.treeSparrow),random:{0.5})
            bird.perch(on:host);bird.perchDuration=600;bird.facingRight=fraction>0.5
            return bird
        }
        d.birds=birds;d.surfaces=[host];d.syncWorld(at:far,buttonsDown:false)
        let origins=birds.map(\.position)
        let started=d.engine.handle(.socialGreeting(.preview)).accepted
        let participants=d.engine.events.last(where:{$0.type == .started && $0.kind == .socialGreeting})?.participants ?? []
        checks["socialPreviewUsesTwoExistingResidents"]=started && participants.count==2 && d.residentCount==2 && d.engine.leasedBirdCount==2
        checks["socialGreetingSharesEncounterBudget"]=started && !d.engine.handle(.flockPass(.preview)).accepted
        let window=OverlayPanel(contentRect:NSScreen.screens[0].frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
        let view=DesktopView(frame:CGRect(origin:.zero,size:window.frame.size));view.controller=d;view.desktopRect=display
        window.contentView=view;window.orderFrontRegardless()
        defer {window.orderOut(nil)}
        var observed=Set<BirdID>(),rendered=true,hit=true,hover=true,facing=true
        for step in 0..<4*60 {
            d.advanceBirds(1.0/60,at:far,buttonsDown:false)
            let snapshot=d.engine.renderSnapshot()
            guard snapshot.count==2 else {rendered=false;continue}
            facing = facing && snapshot[0].facingRight && !snapshot[1].facingRight
            guard let actor=snapshot.first(where:{$0.frameName.hasPrefix("idle")}),!observed.contains(actor.id) else {continue}
            observed.insert(actor.id);view.updateSprites()
            let layers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
            for (index,state) in snapshot.enumerated() {
                guard index<layers.count,let texture=layers[index].sublayers?.first else {rendered=false;continue}
                rendered = rendered && !layers[index].isHidden &&
                    (texture.contents as AnyObject?) === d.arts[state.species]!.frames[state.frameName] &&
                    texture.affineTransform().a == (state.facingRight ? 1:-1)
                let art=d.arts[state.species]!
                let pixel=(0..<48*48).first{art.contains(frame:state.frameName,x:$0%48,y:$0/48)}!
                let x=state.facingRight ? pixel%48:47-pixel%48
                let point=CGPoint(x:state.rect.minX+(CGFloat(x)+0.5)*state.scale,
                                  y:state.rect.minY+(CGFloat(pixel/48)+0.5)*state.scale)
                hit = hit && d.bird(at:point) === birds[index]
                d.updateHover(now:Double(step),at:point);hover = hover && d.hoveredBird === birds[index]
            }
            try SettingsVerification.snapshot(window,to:folder.appendingPathComponent("social-greeting-\(observed.count).png"))
        }
        checks["socialBothRolesReachMirroredSpriteLayers"]=started && observed==Set(participants) && rendered && facing
        checks["socialMirroredPixelsHitAndHover"]=started && observed.count==2 && hit && hover
        checks["socialGreetingKeepsBothFootAnchors"]=started && birds.map(\.position)==origins
        // Select a real visible pixel after turning. Clicking must release the
        // companion as well as transfer the clicked bird into manual flight.
        let point=ExpandedVerification.visiblePoint(on:birds[0],in:d)
        checks["socialClickReleasesCompanionWithoutMovingIt"]=started && d.relocateBird(at:point) &&
            d.engine.behavior(of:birds[0]) == .relocate && d.engine.behavior(of:birds[1]) == nil &&
            birds[1].position==origins[1] && d.engine.leasedBirdCount==1 && !d.engine.ambientBusy
    }
}
