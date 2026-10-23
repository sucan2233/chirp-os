import AppKit
import BirdingCore

enum LeafPlayVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let d=DesktopController();d.automaticPopulation=false
        d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
        var settings=d.settings;settings.leafPlayEnabled=true;settings.perchActions=false;d.settings=settings
        let work=d.screenRects[0],display=d.displayRects[0]
        let center=CGPoint(x:work.midX,y:work.midY)
        let host=Surface(id:945,pid:41,rect:CGRect(x:work.minX+40,y:work.maxY-60,width:work.width-80,height:50))
        let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.treeSparrow),random:{0.5})
        bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600
        d.surfaces=[host];d.birds=[bird];d.syncWorld(at:center,buttonsDown:false)
        let origin=bird.position,started=d.engine.handle(.leafPlay(at:center,source:.preview)).accepted
        let run=d.engine.events.last{$0.kind == .leafPlay && $0.type == .started}?.runID
        let window=OverlayPanel(contentRect:NSScreen.screens[0].frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
        let view=DesktopView(frame:CGRect(origin:.zero,size:window.frame.size));view.controller=d;view.desktopRect=display
        window.contentView=view;window.orderFrontRegardless();defer {window.orderOut(nil)}
        let propLayer:()->CALayer? = {view.layer?.sublayers?.first{$0.name?.hasPrefix("scene-prop-")==true}}
        view.updateSprites()
        let asset=ScenePropAssets.leafURL.flatMap{NSImage(contentsOf:$0)?.cgImage(forProposedRect:nil,context:nil,hints:nil)}
        let bitmap=asset.map{NSBitmapImageRep(cgImage:$0)}
        checks["leafAssetHasTransparentBackgroundAndVisibleCenter"]=bitmap.map {
            ($0.colorAt(x:0,y:0)?.alphaComponent ?? 1)==0 && ($0.colorAt(x:$0.pixelsWide/2,y:$0.pixelsHigh/2)?.alphaComponent ?? 0)>0.9
        } ?? false
        checks["leafStartsWithOneResidentAndOneOwnedProp"]=started && d.engine.scenePropCount==1 && d.engine.leasedBirdCount==1 && d.residentCount==1
        checks["leafUsesRealTextureAndClickThroughOverlay"]=propLayer()?.sublayers?.first?.contents != nil && window.ignoresMouseEvents && !window.canBecomeKey
        var flightCaptured=false,continuous=true,previousBird=bird.position,previousLeaf=d.engine.propSnapshot().first?.position
        for step in 0..<35*60 {
            d.advanceBirds(1.0/60,at:center,buttonsDown:false)
            continuous = continuous && Geometry.distance(previousBird,bird.position)<15
            previousBird=bird.position
            if let leaf=d.engine.propSnapshot().first?.position {
                if let previousLeaf {continuous = continuous && Geometry.distance(previousLeaf,leaf)<15}
                previousLeaf=leaf
            }
            if bird.isCircling && !flightCaptured {
                flightCaptured=true;view.updateSprites()
                checks["leafVisibleAlongsideFlyingBird"]=propLayer()?.isHidden == false && (propLayer()?.opacity ?? 0)>0
                try SettingsVerification.snapshot(window,to:folder.appendingPathComponent("leaf-play-chase.png"))
                d.engine.handle(.pause(true))
                let beforeBird=bird.position,beforeLeaf=d.engine.propSnapshot().first?.position
                for _ in 0..<60 {d.advanceBirds(1.0/60,at:center,buttonsDown:false)}
                checks["leafAndBirdPauseTogether"]=bird.position==beforeBird && d.engine.propSnapshot().first?.position==beforeLeaf
                d.engine.handle(.pause(false))
            }
            if step==12 {view.updateSprites();try SettingsVerification.snapshot(window,to:folder.appendingPathComponent("leaf-play-observe.png"))}
            if d.engine.events.contains(where:{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}) {break}
        }
        let endings=d.engine.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
        view.updateSprites()
        checks["leafSceneCompletesWithContinuousMotion"]=started && flightCaptured && continuous && endings.count==1 && endings.first?.type == .completed
        checks["leafReturnsAndReleasesAllResources"]=bird.position==origin && bird.state == .perched && d.engine.scenePropCount==0 && d.engine.leasedBirdCount==0 && d.engine.reservedLandingCount==0 && propLayer()==nil
        bird.perch(on:host,spriteScale:d.spriteScale(for:bird));bird.perchDuration=600;d.syncWorld(at:center,buttonsDown:false)
        let restarted=d.engine.handle(.leafPlay(at:center,source:.preview)).accepted
        for _ in 0..<90 {d.advanceBirds(1.0/60,at:center,buttonsDown:false)}
        let point=ExpandedVerification.visiblePoint(on:bird,in:d)
        let relocated=d.relocateBird(at:point)
        view.updateSprites()
        checks["leafClickPreemptionClearsPropAndKeepsBird"]=restarted && relocated && d.engine.behavior(of:bird) == .relocate && d.engine.scenePropCount==0 && propLayer()==nil && d.residentCount==1
    }
}
