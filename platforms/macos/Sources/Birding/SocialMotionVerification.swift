import AppKit
import BirdingCore

/// Uses production commands, actual art layers and pixel hit testing. Fixtures
/// select roomy perches so acceptance does not depend on random desktop windows.
enum SocialMotionVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        for action in SocialMotionKind.allCases {
            let prefix="socialMotion-\(action.rawValue)"
            let d=DesktopController();d.automaticPopulation=false;d.scale=1
            d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            let display=d.displayRects[0],work=d.screenRects[0]
            let host=Surface(id:921,rect:CGRect(x:work.minX+60,y:work.midY+80,width:work.width-120,height:120))
            let destination=Surface(id:922,rect:CGRect(x:work.minX+60,y:work.midY-140,width:work.width-120,height:100))
            let far=CGPoint(x:work.minX+5,y:work.minY+5)
            func fixture() {
                d.surfaces=[destination,host]
                d.birds=[CGFloat(-155),155].map {offset in
                    let lo=Geometry.perchX(0,rect:host.rect),hi=Geometry.perchX(1,rect:host.rect)
                    let bird=Bird(position:.zero,fraction:(work.midX+offset-lo)/(hi-lo),profile:d.catalog.profile(.treeSparrow),random:{0.5})
                    bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;return bird
                }
                d.syncWorld(at:far,buttonsDown:false)
            }
            fixture()
            let result=d.engine.handle(.socialMotion(action,.preview))
            let event=d.engine.events.last{$0.type == .started}
            let ids=event?.participants ?? [],original=d.birds.map(\.position)
            checks[prefix+"ReservesBothExistingBirds"]=result.accepted && ids.count==2 && d.residentCount==2 && d.engine.reservedLandingCount==2 && d.engine.leasedBirdCount==2
            let window=OverlayPanel(contentRect:NSScreen.screens[0].frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
            let view=DesktopView(frame:CGRect(origin:.zero,size:window.frame.size));view.controller=d;view.desktopRect=display
            window.contentView=view;window.orderFrontRegardless()
            defer {window.orderOut(nil)}
            var seenAir=Set<BirdID>(),rendered=true,hit=true,continuous=true
            var previous=d.birds.map(\.position)
            for _ in 0..<25*60 {
                d.advanceBirds(1.0/60,at:far,buttonsDown:false)
                let snapshot=d.engine.renderSnapshot()
                for (index,bird) in d.birds.enumerated() {
                    if index<previous.count {continuous = continuous && Geometry.distance(previous[index],bird.position)<25}
                }
                previous=d.birds.map(\.position)
                let newlyFlying=snapshot.filter {state in
                    state.frameName.hasPrefix("fly") && !seenAir.contains(state.id)
                }
                if !newlyFlying.isEmpty {
                    view.updateSprites()
                    let layers=view.layer?.sublayers?.filter{$0.mask is CAShapeLayer} ?? []
                    for (index,state) in snapshot.enumerated() {
                        guard index<layers.count,let texture=layers[index].sublayers?.first,
                              let art=d.arts[state.species] else {rendered=false;continue}
                        rendered = rendered && !layers[index].isHidden &&
                            (texture.contents as AnyObject?) === art.frames[state.frameName] &&
                            texture.affineTransform().a == (state.facingRight ? 1:-1)
                        if let pixel=(0..<48*48).first(where:{art.contains(frame:state.frameName,x:$0%48,y:$0/48)}) {
                            let x=state.facingRight ? pixel%48:47-pixel%48
                            let point=CGPoint(x:state.rect.minX+(CGFloat(x)+0.5)*state.scale,
                                y:state.rect.minY+(CGFloat(pixel/48)+0.5)*state.scale)
                            hit = hit && d.bird(at:point) === d.engine.bird(state.id)
                        } else {hit=false}
                    }
                    for state in newlyFlying {seenAir.insert(state.id)}
                    try SettingsVerification.snapshot(window,to:folder.appendingPathComponent(prefix+"-\(seenAir.count).png"))
                }
                if let run=event?.runID,d.engine.events.contains(where:{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}) {break}
            }
            let expectedMovers=action == .sideBySide ? 1:2
            checks[prefix+"RealFlightFramesAndLayers"]=result.accepted && seenAir.count==expectedMovers && rendered
            checks[prefix+"PixelsHitMovingBirds"]=result.accepted && hit && seenAir.count==expectedMovers
            checks[prefix+"ContinuousFootMovement"]=result.accepted && continuous && d.birds.map(\.position) != original
            let terminal=d.engine.events.filter{$0.runID==event?.runID && [.completed,.failed,.cancelled].contains($0.type)}
            checks[prefix+"CompletesAndReleasesAllSlots"]=result.accepted && terminal.count==1 && terminal.first?.type == .completed && d.engine.reservedLandingCount==0 && d.engine.leasedBirdCount==0 && d.residentCount==2
            fixture()
            let again=d.engine.handle(.socialMotion(action,.preview)).accepted
            let bird=d.birds[0],point=ExpandedVerification.visiblePoint(on:bird,in:d)
            checks[prefix+"ClickReleasesPartnerAndSlots"]=again && d.relocateBird(at:point) &&
                d.engine.behavior(of:bird) == .relocate && d.engine.leasedBirdCount==1 && d.engine.reservedLandingCount==0 && !d.engine.ambientBusy
        }
    }
}
