import AppKit
import BirdingCore

/// Uses isolated files and synthetic birds; never modifies the user's Life List.
enum ObservationVerification {
    @discardableResult static func snapshot(_ view:NSView,to url:URL) throws -> NSBitmapImageRep {
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(view.bounds.width),pixelsHigh:Int(view.bounds.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        view.draw(view.bounds);NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using:.png,properties:[:])!.write(to:url);return bitmap
    }
    static func run(to folder:URL) {exit(perform(to:folder))}
    private static func perform(to folder:URL)->Int32 {
        var checks:[String:Bool]=[:]
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let d=DesktopController(verificationSeed:73)
            d.isolatedSession=true
            let suite="ChirpOS.ObservationVerification."+UUID().uuidString
            d.preferences=UserDefaults(suiteName:suite)!
            defer {d.preferences.removePersistentDomain(forName:suite)}
            d.settingsURL=folder.appendingPathComponent("settings.json")
            d.observationJournalURL=folder.appendingPathComponent("observations.json")
            d.observationJournalPersistenceEnabled=true
            d.visitorMemoryPersistenceEnabled=false;d.giftLedgerPersistenceEnabled=false
            d.pointerButtonsDown={false}
            d.loadObservationJournal();d.loadObservationMode()
            checks["manualModeDefaultsOff"] = !d.observationsEnabled
            d.settings.probabilities.setManualWeight(at:0,to:8000)
            d.settings.catalog.species[0].speed=0.5
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            let original=try encoder.encode(d.settings)
            d.makeMenu()
            defer {
                d.observationWindow?.close();d.settingsWindow?.close();d.hideObservationOverlays()
                if let status=d.status {NSStatusBar.system.removeStatusItem(status)}
                if let domain=Bundle.main.bundleIdentifier {
                    let keys=UserDefaults.standard.persistentDomain(forName:domain)?.keys.filter{$0.contains(d.observationSession.uuidString)} ?? []
                    for key in keys {UserDefaults.standard.removeObject(forKey:key)}
                }
            }
            let host=Surface(id:171,rect:CGRect(x:100,y:400,width:900,height:300))
            d.surfaces=[host]
            func install(_ species:SpeciesID = .treeSparrow)->Bird {
                let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(species),random:{0.5})
                bird.perch(on:host);bird.perchDuration=600
                d.birds=[bird];d.reconcileObservationVisits();return bird
            }
            func hitPoint(_ bird:Bird)->CGPoint {
                let frame=d.engine.renderSnapshot().first{$0.id==d.engine.id(of:bird)}!
                let art=d.arts[frame.species]!
                for y in 0..<48 {for x in 0..<48 where art.contains(frame:frame.frameName,x:x,y:y) {
                    let point=CGPoint(x:frame.position.x+(CGFloat(frame.facingRight ? x:47-x)+0.5-(frame.facingRight ? 29:19))*frame.scale,
                                      y:frame.position.y+(CGFloat(y)+0.5+frame.hopOffset-39)*frame.scale)
                    if d.birdSnapshot(at:point) != nil {return point}
                }}
                return .zero
            }
            let old=install()
            d.toggleObservations()
            checks["modeKeepsCatalogPreferencesAndResidents"] = try d.observationsEnabled && !old.isDeparting && encoder.encode(d.settings)==original
            d.photograph(at:hitPoint(old))
            let first=d.observationJournal.speciesRecord(for:.treeSparrow)?.manualFirstRecordedAt
            if let view=d.feedbackPanel?.contentView as? ObservationFeedbackView {try snapshot(view,to:folder.appendingPathComponent("feedback-new.png"))}
            d.photograph(at:hitPoint(old))
            checks["sameVisitRecordedOnlyOnce"]=d.observationJournal.manualRecordCount==1
            checks["repeatExplainsVisitLimit"]=(d.feedbackPanel?.contentView as? ObservationFeedbackView)?.text.contains("本次已记录") == true
            d.toggleObservations();d.toggleObservations();d.photograph(at:hitPoint(old))
            checks["modeToggleKeepsVisitDedup"]=d.observationJournal.manualRecordCount==1
            let second=install();d.photograph(at:hitPoint(second))
            checks["newVisitCountsWithFirstDatePreserved"]=d.observationJournal.manualRecordCount==2 && d.observationJournal.speciesRecord(for:.treeSparrow)?.manualFirstRecordedAt==first
            checks["capturesNeverCompleteBehaviors"]=d.observationJournal.archive.entries.isEmpty
            d.paused=true;let pausedBird=install();d.photograph(at:hitPoint(pausedBird))
            checks["pausedCaptureRejected"]=d.observationJournal.manualRecordCount==2
            d.paused=false
            d.observationMenuOpen=true;d.photograph(at:hitPoint(pausedBird))
            checks["menuCaptureRejected"]=d.observationJournal.manualRecordCount==2
            d.observationMenuOpen=false
            let point=hitPoint(pausedBird)
            if let first=NativeVerificationInput.leftDown(at:point),
               let second=NativeVerificationInput.leftDown(at:point),
               let cg=first.cgEvent,let repeated=NSEvent(cgEvent:cg) {
                checks["nativeVerificationClickIdentitiesAreDistinctAndStable"] =
                    first.eventNumber>=1000 && second.eventNumber==first.eventNumber+1 &&
                    MouseEventIdentity(first) != MouseEventIdentity(second) &&
                    MouseEventIdentity(first)==MouseEventIdentity(repeated)
            } else {checks["nativeVerificationClickIdentitiesAreDistinctAndStable"]=false}
            let cgEvent=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left)!
            cgEvent.setIntegerValueField(.mouseEventNumber,value:1)
            let event=NSEvent(cgEvent:cgEvent)!
            let revision=pausedBird.motionRevision
            d.handleMouseDown(event);d.handleMouseDown(event)
            checks["nativeDuplicateCallbacksCountOnce"]=d.observationJournal.manualRecordCount==3
            checks["captureDoesNotRelocate"]=pausedBird.motionRevision==revision
            checks["captureKeepsPhysicalButtonAndClassifiesIt"]=d.engine.world.buttonsDown && d.engine.world.observationClick
            d.observationClickHeld=false;d.syncWorld(at:point,buttonsDown:false)
            d.updateHover(now:100,at:point);d.updateHover(now:102,at:point)
            checks["cameraHoverHidesDelayedName"]=d.cameraBird === pausedBird && d.hoveredBird == nil
            let countBeforeOption=d.observationJournal.manualRecordCount
            let optionCG=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left)!
            // Unposted CGEvents default to timestamp/number zero; give separate
            // clicks distinct identities while reusing one event above for dedup.
            optionCG.setIntegerValueField(.mouseEventNumber,value:2)
            optionCG.flags = .maskAlternate
            d.handleMouseDown(NSEvent(cgEvent:optionCG)!)
            checks["optionClickOnlyRelocates"]=d.observationJournal.manualRecordCount==countBeforeOption && pausedBird.motionRevision>revision
            d.observationClickHeld=false;d.syncWorld(at:point,buttonsDown:false)
            var masksMatch=true,frameCount=0
            for art in d.arts.values {for (name,image) in art.frames {
                frameCount+=1
                let data=image.dataProvider!.data!,bytes=CFDataGetBytePtr(data)!
                var top:Int?=nil
                for y in 0..<48 {for x in 0..<48 {
                    let opaque=bytes[(y*image.height/48)*image.bytesPerRow+(x*image.width/48)*4+3]>0
                    if opaque && top==nil {top=y}
                    if art.contains(frame:name,x:x,y:y) != opaque {masksMatch=false}
                }}
                if art.topPixel(frame:name) != (top ?? 0) {masksMatch=false}
            }}
            checks["cachedHitMasksMatchAll3587Frames"]=masksMatch && frameCount==3587
            // Compare both lookup algorithms against the same actual atlas frames.
            // Timings are evidence, not a flaky pass/fail speed threshold.
            let samples=d.arts.values.flatMap {art in art.frames.map {name,image in (art,name,image)}}
            var cachedSum=0,directSum=0
            let cachedStart=ProcessInfo.processInfo.systemUptime
            for pass in 0..<4 {for (art,name,_) in samples {for x in 0..<48 {
                if art.contains(frame:name,x:x,y:(x*7+pass*11)%48) {cachedSum+=1}
            }}}
            let cachedSeconds=ProcessInfo.processInfo.systemUptime-cachedStart
            let directStart=ProcessInfo.processInfo.systemUptime
            for pass in 0..<4 {for (_,_,image) in samples {for x in 0..<48 {
                if let data=image.dataProvider?.data,let bytes=CFDataGetBytePtr(data),
                   bytes[(((x*7+pass*11)%48)*image.height/48)*image.bytesPerRow+(x*image.width/48)*4+3]>0 {directSum+=1}
            }}}
            let directSeconds=ProcessInfo.processInfo.systemUptime-directStart
            checks["lookupBenchmarkSamePixelResults"]=cachedSum==directSum
            let metrics:[String:Any]=["species":d.arts.count,"frames":frameCount,
                "queries":samples.count*4*48,"cachedSeconds":cachedSeconds,"directSeconds":directSeconds,
                "cachedOpaqueCount":cachedSum,"directOpaqueCount":directSum,
                "decodedPixelBytes":samples.reduce(0){$0+$1.2.bytesPerRow*$1.2.height},
                "logicalMaskEntries":frameCount*48*48]
            try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys])
                .write(to:folder.appendingPathComponent("lookup-performance.json"))
            let target=CameraTargetView(frame:NSRect(x:0,y:0,width:28,height:28))
            let bitmap=try snapshot(target,to:folder.appendingPathComponent("viewfinder.png"))
            checks["visibleViewfinder"]=(0..<28).contains{x in (0..<28).contains{y in (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.5}}
            let items=d.status.menu!.items
            checks["singleHandbookMenu"]=items.filter{$0.action == #selector(d.showObservationJournal)}.count==1 && !items.contains{$0.action == #selector(d.showSpeciesGallery)}
            checks["pauseMenuRetained"]=items.contains{$0.action == #selector(d.togglePause(_:))}
            d.showObservationJournal()
            d.observationWindow?.selectAllSpecies()
            let content=d.observationWindow!.window!.contentView!
            content.layoutSubtreeIfNeeded();content.displayIfNeeded()
            if let image=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
                content.cacheDisplay(in:content.bounds,to:image)
                try image.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("handbook.png"))
            }
            let overlay=d.observationPanel(size:NSSize(width:30,height:30),interactive:false)
            overlay.orderFrontRegardless()
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15))
            d.sampleWindows(dt:0)
            let windowID=UInt32(d.observationWindow!.window!.windowNumber)
            checks["handbookMasksWithoutHostingInIsolatedSession"]=d.surfaces.contains{$0.id==windowID && !$0.canHostBirds && $0.occludesFlight}
            checks["overlayExcludedFromOcclusion"] = !d.surfaces.contains{$0.id==UInt32(overlay.windowNumber)}
            overlay.orderOut(nil)
            d.flushObservationJournal()
            let saved=try ObservationArchive.load(from:d.observationJournalURL)
            checks["unifiedArchivePersistsManualCounts"]=saved.speciesRecord(for:.treeSparrow)?.manualCount==3
            checks["oldLifeListNeverWritten"] = !FileManager.default.fileExists(atPath:d.lifeListURL.path)
            checks["settingsRemainUnchanged"]=try encoder.encode(d.settings)==original
            try JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("results.json"))
            print(checks.sorted{$0.key<$1.key}.map{"\($0.value ? "PASS":"FAIL") \($0.key)"}.joined(separator:"\n"))
            return checks.values.allSatisfy{$0} ? 0:1
        } catch {print("Observation verification failed: \(error)");return 1}
    }
}
