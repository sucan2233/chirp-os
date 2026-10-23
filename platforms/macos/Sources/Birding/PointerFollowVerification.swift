import AppKit
import BirdingCore

enum PointerFollowVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let d=DesktopController();d.automaticPopulation=false
        var settings=d.settings;settings.pointerFollowEnabled=true;d.settings=settings
        let work=d.screenRects[0],display=d.displayRects[0],center=CGPoint(x:d.screenRects[0].midX,y:d.screenRects[0].midY)
        let host=Surface(id:931,rect:CGRect(x:work.minX+40,y:work.maxY-60,width:work.width-80,height:50))
        let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600
        d.surfaces=[host];d.birds=[bird]
        let origin=bird.position,started=d.startPointerVisit(at:center),revision=bird.motionRevision
        let run=d.engine.events.last{$0.kind == .pointerVisit && $0.type == .started}?.runID
        let window=OverlayPanel(contentRect:NSScreen.screens[0].frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
        let view=DesktopView(frame:CGRect(origin:.zero,size:window.frame.size));view.controller=d;view.desktopRect=display
        window.contentView=view;window.orderFrontRegardless();defer {window.orderOut(nil)}
        var circled=false,continuous=true,rendered=false,previous=bird.position
        for tick in 0..<25*60 {
            let pointer=CGPoint(x:center.x+130*sin(Double(tick)/60),y:center.y+45*cos(Double(tick)/80))
            d.advanceBirds(1.0/60,at:pointer,buttonsDown:false)
            continuous = continuous && Geometry.distance(previous,bird.position)<12 && bird.motionRevision==revision
            previous=bird.position
            if bird.isCircling && !circled {
                circled=true;view.updateSprites()
                if let state=d.engine.renderSnapshot().first,
                   let layer=view.layer?.sublayers?.first(where:{$0.mask is CAShapeLayer}),
                   let texture=layer.sublayers?.first {
                    rendered = !layer.isHidden && (texture.contents as AnyObject?) === d.arts[state.species]?.frames[state.frameName]
                }
                try SettingsVerification.snapshot(window,to:folder.appendingPathComponent("pointer-follow-flight.png"))
            }
            if d.engine.events.contains(where:{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}) {break}
        }
        let ends=d.engine.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}
        checks["pointerFollowMovesContinuouslyWithRealFlightLayer"]=started && circled && continuous && rendered
        checks["pointerFollowFinishesAndReturnsDespiteMovingInput"]=started && ends.count==1 && ends.first?.type == .completed && bird.position==origin && bird.hostID==host.id && d.engine.leasedBirdCount==0
    }
}
