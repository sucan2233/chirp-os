import AppKit
import BirdingCore

extension BirdArt {
    func topPixel(frame:String) -> Int {topPixels[frame] ?? 0}
    func contains(frame:String,x:Int,y:Int) -> Bool {
        guard (0..<48).contains(x),(0..<48).contains(y),let mask=hitMasks[frame] else {return false}
        return mask[y*48+x]
    }
}
struct MouseEventIdentity:Equatable {
    let timestamp:TimeInterval
    let number:Int
    let window:Int
    init(_ event:NSEvent) {timestamp=event.timestamp;number=event.eventNumber;window=event.windowNumber}
}
extension DesktopController {
    // Use the same visible sprite pixels for hovering and clicking, including
    // mirroring, species size, hops, and foreground-window occlusion.
    func birdSnapshot(at point:CGPoint,synchronize:Bool=true) -> BirdRenderState? {
        let snapshot=synchronize ? renderSnapshot():engine.renderSnapshot(),immersion=engine.bathImmersionSnapshot()
        let baths=engine.habitatSnapshot().filter{$0.kind == .bath}
        // The visible foreground basin wall also occludes hit targets. Use its
        // authored alpha, exactly as the layer renderer does, at the same scale.
        let coveredByBasin=baths.contains {bath in
            guard bath.rect.contains(point),!bath.blockers.contains(where:{$0.contains(point)}) else {return false}
            let front=BathArt.image(layer:.front)
            guard let data=front.dataProvider?.data,let bytes=CFDataGetBytePtr(data) else {return false}
            let x=min(front.width-1,max(0,Int((point.x-bath.rect.minX)/bath.rect.width*CGFloat(front.width))))
            let y=min(front.height-1,max(0,Int((point.y-bath.rect.minY)/bath.rect.height*CGFloat(front.height))))
            return bytes[y*front.bytesPerRow+x*4+3]>0
        }
        guard !coveredByBasin else {return nil}
        return snapshot.reversed().first { bird in
            let x=(point.x-bird.position.x)/bird.scale+(bird.facingRight ? 29:19)
            let y=(point.y-bird.position.y)/bird.scale-bird.hopOffset+39
            guard x>=0,x<48,y>=0,y<48,
                  !bird.blockers.contains(where:{$0.contains(point)}) else {return false}
            if let bath=immersion[bird.id],bath.feetRect.contains(point) ||
                (point.y>bath.waterlineY && BathGeometry.containsContact(point,waterRect:bath.waterRect)) {return false}
            return arts[bird.species]!.contains(frame:bird.frameName,x:bird.facingRight ? Int(x):47-Int(x),y:Int(y))
        }
    }
    func bird(at point:CGPoint) -> Bird? {birdSnapshot(at:point).flatMap{engine.bird($0.id)}}
    func updateHover(now:Double, at suppliedPoint:CGPoint? = nil) {
        let hit=birdSnapshot(at:suppliedPoint ?? pointerPosition)
        cameraID=observationsEnabled && !paused ? hit?.id:nil
        if observationsEnabled {hoverTracker=HoverTracker<BirdID>();hoveredID=nil}
        else {hoveredID=hoverTracker.update(hit.flatMap{$0.hoverable ? $0.id:nil},now:now,delay:settings.hoverDelay)}
    }
    @discardableResult
    func relocateBird(at point:CGPoint) -> Bool {
        guard let hit=birdSnapshot(at:point),engine.handle(.relocate(hit.id)).accepted else {return false}
        hoverTracker=HoverTracker<BirdID>();hoveredID=nil
        for view in views {view.updateSprites()}
        return true
    }
    func handleMouseDown(_ event:NSEvent) {
        let identity=MouseEventIdentity(event)
        guard identity != lastRoutedMouseEvent,let point=event.cgEvent?.location else {return}
        lastRoutedMouseEvent=identity
        // Route local monitor and interactive view callbacks through one latch.
        // Ordinary application controls must never click a bird underneath them.
        if let window=NSApp.window(withWindowNumber:event.windowNumber),!(window is OverlayPanel) {
            observationClickHeld=false;syncWorld(at:point,buttonsDown:true);return
        }
        let recording=observationsEnabled && !event.modifierFlags.contains(.option)
        // Classify before sampling the newly pressed physical button. Hit testing
        // itself must not validate a running action with an unclassified click.
        observationClickHeld=recording && !paused && !observationMenuOpen && NSApp.modalWindow == nil && birdSnapshot(at:point,synchronize:false) != nil
        if recording {
            if observationClickHeld {photograph(at:point)}
        } else {
            relocateBird(at:point)
        }
        syncWorld(at:point,buttonsDown:true)
        if !recording {engine.handle(.pointerClick)}
    }
    private func handleMouseEvent(_ event:NSEvent) {
        if event.type == .leftMouseUp {
            observationClickHeld=false;cameraPressed=false
            syncWorld(at:event.cgEvent?.location,buttonsDown:false)
        } else {handleMouseDown(event)}
    }
    func startMouseMonitoring() {
        stopMouseMonitoring()
        // Observe clicks without consuming them or activating the overlay.
        globalMouseMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        // Global monitors exclude events sent to this application.
        localMouseMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }
    func stopMouseMonitoring() {
        if let globalMouseMonitor {NSEvent.removeMonitor(globalMouseMonitor)}
        if let localMouseMonitor {NSEvent.removeMonitor(localMouseMonitor)}
        globalMouseMonitor=nil;localMouseMonitor=nil
    }
}
