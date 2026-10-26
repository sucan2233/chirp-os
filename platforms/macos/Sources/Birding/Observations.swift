import AppKit
import BirdingCore

struct ManualObservationVisit {
    let session:UUID
    let bird:BirdID
    let ordinal:UInt64
    var recorded=false
}

extension DesktopController {
    func loadObservationMode() {
        // No first-launch modal or catalog switch. Importing a legacy preference
        // is handled only after its archive has passed migration validation.
        if let explicit=preferences.object(forKey:"birdwatchingMode") as? Bool {observationsEnabled=explicit}
        else if let imported=observationPersistence?.importedModePreference {
            observationsEnabled=imported
            if !isolatedSession {preferences.set(imported,forKey:"birdwatchingMode")}
        } else {observationsEnabled=false}
    }
    func reconcileObservationVisits() {
        let live=Set(birds.compactMap{engine.id(of:$0)})
        observationVisits=observationVisits.filter{live.contains($0.key)}
        for id in live.sorted() where observationVisits[id] == nil {
            observationArrivalOrdinal &+= 1
            observationVisits[id]=ManualObservationVisit(session:observationSession,bird:id,ordinal:observationArrivalOrdinal)
        }
    }
    func hideObservationOverlays() {
        cameraPanel?.orderOut(nil);feedbackPanel?.orderOut(nil)
        cameraID=nil;cameraPressed=false;observationClickHeld=false
    }
    @objc func toggleObservations() {
        observationsEnabled.toggle()
        if !isolatedSession {preferences.set(observationsEnabled,forKey:"birdwatchingMode")}
        hideObservationOverlays()
        hoverTracker=HoverTracker<BirdID>();hoveredID=nil
        reconcileObservationVisits()
        makeMenu();observationWindow?.refresh()
    }
    func updateCamera(now:Double) {
        if observationClickHeld && !pointerButtonsDown() {observationClickHeld=false}
        if let feedback=feedbackPanel,feedback.isVisible {
            let age=now-feedbackStarted
            if age>=1.2 || paused {feedback.orderOut(nil)}
            else if let view=feedback.contentView as? ObservationFeedbackView {
                if view.awaitingSave,let persistence=observationPersistence {
                    if persistence.saveFailed || persistence.writesDisabled || !persistence.enabled {
                        view.text=view.text.replacingOccurrences(of:t("正在保存","saving"),with:t("尚未保存","not saved"))
                        view.awaitingSave=false
                    } else if !persistence.hasUnsavedChanges {
                        view.text=view.text.replacingOccurrences(of:t("正在保存","saving"),with:t("已保存","saved"))
                        view.awaitingSave=false
                    }
                }
                view.age=age;view.needsDisplay=true
            }
        }
        guard observationsEnabled,!paused,!observationMenuOpen,NSApp.modalWindow == nil,
              cameraBird != nil,!pointerButtonsDown(),
              !NSApp.windows.contains(where:{!($0 is OverlayPanel) && $0.isVisible && $0.frame.contains(NSEvent.mouseLocation)}) else {
            if cameraPanel?.isVisible == true {cameraPanel?.orderOut(nil);NSCursor.arrow.set()}
            return
        }
        if cameraPanel == nil {
            let panel=observationPanel(size:NSSize(width:28,height:28),interactive:true)
            let view=CameraTargetView(frame:NSRect(x:0,y:0,width:28,height:28))
            view.desktop=self;panel.contentView=view;cameraPanel=panel
        }
        let point=NSEvent.mouseLocation
        cameraPanel?.setFrameOrigin(NSPoint(x:point.x-14,y:point.y-14))
        if cameraPanel?.isVisible != true {cameraPanel?.orderFrontRegardless()}
        CameraTargetView.cameraCursor.set()
    }
    func observationPanel(size:NSSize,interactive:Bool) -> OverlayPanel {
        let panel=OverlayPanel(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.animationBehavior = .none;panel.isMovable=false;panel.isMovableByWindowBackground=false
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false
        panel.ignoresMouseEvents = !interactive;panel.hidesOnDeactivate=false
        panel.level = .floating;panel.isReleasedWhenClosed=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        return panel
    }
    func photograph(at suppliedPoint:CGPoint?=nil) {
        guard observationsEnabled,!paused,!observationMenuOpen,NSApp.modalWindow == nil else {return}
        let point=suppliedPoint ?? pointerPosition
        guard let hit=birdSnapshot(at:point,synchronize:!observationClickHeld) else {return}
        reconcileObservationVisits()
        guard var visit=observationVisits[hit.id] else {return}
        let text:String
        var isNew=false,awaitingSave=false
        if visit.recorded {text=language.name(hit.species)+t(" · 本次已记录"," · Already recorded this visit")}
        else {
            loadObservationJournal()
            isNew = !observationJournal.archive.isDiscovered(hit.species)
            guard observationJournal.recordManual(species:hit.species,at:observationDate()) else {return}
            visit.recorded=true;observationVisits[hit.id]=visit;awaitingSave=true
            observationPersistence?.flush(from:observationJournal,now:ProcessInfo.processInfo.systemUptime)
            text=language.name(hit.species)+t(" · 已记录，正在保存"," · Recorded, saving")
        }
        observationWindow?.refresh()
        showObservationFeedback(text,isNew:isNew,at:point,awaitingSave:awaitingSave)
    }
    func showObservationFeedback(_ text:String,isNew:Bool,at quartzPoint:CGPoint,awaitingSave:Bool=false) {
        let point=CGPoint(x:quartzPoint.x,y:primaryHeight-quartzPoint.y)
        guard let screen=NSScreen.screens.first(where:{$0.frame.contains(point)})?.visibleFrame ?? NSScreen.main?.visibleFrame else {return}
        let width=min(screen.width,max(140,ObservationFeedbackView.textWidth(text)+8))
        if feedbackPanel == nil {feedbackPanel=observationPanel(size:NSSize(width:width,height:110),interactive:false)}
        feedbackPanel?.setContentSize(NSSize(width:width,height:110))
        let view=ObservationFeedbackView(frame:NSRect(x:0,y:0,width:width,height:110))
        view.text=text;view.isNew=isNew && settings.activityRhythm != .quiet
        view.awaitingSave=awaitingSave;view.reduceMotion=settings.activityRhythm == .quiet;feedbackPanel?.contentView=view
        feedbackPanel?.setFrameOrigin(NSPoint(x:min(screen.maxX-width,max(screen.minX,point.x-width/2)),y:min(screen.maxY-110,max(screen.minY,point.y-20))))
        feedbackStarted=ProcessInfo.processInfo.systemUptime;feedbackPanel?.orderFrontRegardless()
    }
}

final class CameraTargetView:NSView {
    weak var desktop:DesktopController?
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    // Draw independently of the system cursor: another foreground application
    // may replace NSCursor while this nonactivating panel still receives clicks.
    override func draw(_ dirtyRect:NSRect) { Self.cameraCursor.image.draw(in:bounds) }
    override func resetCursorRects() { addCursorRect(bounds,cursor:Self.cameraCursor) }
    static let cameraCursor:NSCursor = {
        let image=NSImage(size:NSSize(width:28,height:28))
        image.lockFocus()
        let path=NSBezierPath()
        for (x,y,dx,dy) in [(3.0,3.0,1.0,1.0),(25,3,-1,1),(3,25,1,-1),(25,25,-1,-1)] {
            path.move(to:NSPoint(x:x+dx*6,y:y));path.line(to:NSPoint(x:x,y:y));path.line(to:NSPoint(x:x,y:y+dy*6))
        }
        NSColor.black.setStroke();path.lineWidth=3;path.stroke()
        NSColor.white.setStroke();path.lineWidth=1.5;path.stroke()
        NSColor.white.setFill();NSBezierPath(ovalIn:NSRect(x:13,y:13,width:2,height:2)).fill()
        image.unlockFocus();return NSCursor(image:image,hotSpot:NSPoint(x:14,y:14))
    }()
    override func mouseDown(with event:NSEvent) { desktop?.cameraPressed=true;desktop?.handleMouseDown(event) }
    override func mouseUp(with event:NSEvent) { desktop?.cameraPressed=false;desktop?.observationClickHeld=false;desktop?.syncWorld(at:event.cgEvent?.location,buttonsDown:false) }
}

final class ObservationFeedbackView:NSView {
    static let textFont=NSFont.systemFont(ofSize:13,weight:.medium)
    static func textWidth(_ text:String) -> CGFloat { ceil((text as NSString).size(withAttributes:[.font:textFont]).width)+20 }
    var text="", isNew=false, age=0.0
    var awaitingSave=false,reduceMotion=false
    override func draw(_ dirtyRect:NSRect) {
        let alpha=max(0,min(1,(1.2-age)*3))
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
        let width=min(bounds.width-8,Self.textWidth(text))
        let rect=NSRect(x:(bounds.width-width)/2,y:32+(reduceMotion ? 0:age*16),width:width,height:25)
        NSColor.black.withAlphaComponent(0.8*alpha).setFill();NSBezierPath(roundedRect:rect,xRadius:6,yRadius:6).fill()
        (text as NSString).draw(in:rect.insetBy(dx:4,dy:3),withAttributes:[.font:Self.textFont,.foregroundColor:NSColor.white.withAlphaComponent(alpha),.paragraphStyle:paragraph])
        if !reduceMotion,age < 0.2 {
            NSColor.white.withAlphaComponent(1-age/0.2).setStroke()
            let flash=NSBezierPath(rect:NSRect(x:bounds.midX-14,y:6,width:28,height:28));flash.lineWidth=2;flash.stroke()
        }
        if isNew {
            let colors:[NSColor]=[.systemPink,.systemYellow,.systemTeal,.systemBlue,.systemOrange]
            for i in 0..<16 {
                let angle=Double(i)*2.4, radius=12+age*42
                colors[i%colors.count].withAlphaComponent(alpha).setFill()
                NSBezierPath(rect:NSRect(x:bounds.midX+cos(angle)*radius,y:35+sin(angle)*radius+age*12,width:4,height:3)).fill()
            }
        }
    }
}
