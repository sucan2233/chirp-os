import AppKit
import BirdingCore

extension BirdArt {
    func topPixel(frame:String) -> Int {
        for y in 0..<48 { if (0..<48).contains(where:{contains(frame:frame,x:$0,y:y)}) {return y} }
        return 0
    }
    func contains(frame:String,x:Int,y:Int) -> Bool {
        guard (0..<48).contains(x),(0..<48).contains(y),let image=frames[frame],
              let data=image.dataProvider?.data,let bytes=CFDataGetBytePtr(data) else {return false}
        let px=min(image.width-1,x*image.width/48),py=min(image.height-1,y*image.height/48)
        return bytes[py*image.bytesPerRow+px*4+3]>0
    }
}
extension DesktopController {
    // Use the same visible sprite pixels for hovering and clicking, including
    // mirroring, species size, hops, and foreground-window occlusion.
    func birdSnapshot(at point:CGPoint) -> BirdRenderState? {
        renderSnapshot().reversed().first { bird in
            let x=(point.x-bird.position.x)/bird.scale+(bird.facingRight ? 29:19)
            let y=(point.y-bird.position.y)/bird.scale-bird.hopOffset+39
            guard x>=0,x<48,y>=0,y<48,
                  !bird.blockers.contains(where:{$0.contains(point)}) else {return false}
            return arts[bird.species]!.contains(frame:bird.frameName,x:bird.facingRight ? Int(x):47-Int(x),y:Int(y))
        }
    }
    func bird(at point:CGPoint) -> Bird? {birdSnapshot(at:point).flatMap{engine.bird($0.id)}}
    func updateHover(now:Double, at suppliedPoint:CGPoint? = nil) {
        let hit=birdSnapshot(at:suppliedPoint ?? pointerPosition)
        hoveredID=hoverTracker.update(hit.flatMap{$0.hoverable ? $0.id:nil},now:now,delay:settings.hoverDelay)
    }
    @discardableResult
    func relocateBird(at point:CGPoint) -> Bool {
        guard let hit=birdSnapshot(at:point),engine.handle(.relocate(hit.id)).accepted else {return false}
        hoverTracker=HoverTracker<BirdID>();hoveredID=nil
        for view in views {view.updateSprites()}
        return true
    }
    func handleMouseDown(_ event:NSEvent) {
        // CGEvent locations already use the desktop's top-left coordinates.
        // Relocate before cancelling pointer visits so the clicked bird keeps priority.
        guard let point=event.cgEvent?.location else {return}
        relocateBird(at:point)
        // Render/hit-test snapshots may resample the live pointer. Bind the
        // stimulus to this event after those reads and before issuing the command.
        syncWorld(at:point,buttonsDown:true)
        engine.handle(.pointerClick)
    }
    private func handleMouseEvent(_ event:NSEvent) {
        if event.type == .leftMouseUp {syncWorld(at:event.cgEvent?.location,buttonsDown:false)}
        else {handleMouseDown(event)}
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
