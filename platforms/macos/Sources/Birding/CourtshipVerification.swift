import AppKit
import BirdingCore

/// Production command/controls and the actual root CALayer. This fixture never
/// starts Desktop, loads user files, moves the system pointer or creates a pair
/// in response to a preview. Core owns rate/replay/pressure and virtual displays.
enum CourtshipVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("courtship-native-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        defer {saveJSON(["checks":checks.filter{$0.key.hasPrefix("courtshipNative")},"evidence":evidence,
            "limits":"Real attached display and live pointer; no physical hotplug claim. Core verifies replay, negative coordinates, dt equivalence and pressure. No sex or permanent pair model."],to:output.appendingPathComponent("report.json"))}
        try autoreleasepool {
            let f=try Fixture(folder:output);defer {f.close()}
            // A fresh engine has no prior display's global/per-bird cooldown.
            // Exercise automatic admission before previews consume that state.
            try complete(f,scale:1,mirrored:false,source:.automatic,into:&checks,evidence:&evidence,folder:output)
        }
        for scale:CGFloat in [0.5,1,2] {
            var headings=[Bool]()
            for mirrored in [false,true] {try autoreleasepool {
                // Same fresh seed and identities; mirror only the real perches.
                // This preserves production role sampling and proves that the
                // initiator is actually rendered in both directions.
                let f=try Fixture(folder:output);defer {f.close()}
                if let heading=try complete(f,scale:scale,mirrored:mirrored,source:.preview,
                    into:&checks,evidence:&evidence,folder:output) {headings.append(heading)}
            }}
            checks["courtshipNativeBothInitiatorHeadings-\(scale)"]=headings.count==2 && Set(headings).count==2
        }
        try autoreleasepool {
            let f=try Fixture(folder:output);defer {f.close()}
            try complete(f,scale:1,mirrored:false,source:.user,into:&checks,evidence:&evidence,folder:output)
            try interruptions(f,into:&checks,evidence:&evidence,folder:output)
            checks["courtshipNativeResourcesBoundedAndNoUserIO"]=f.d.timer==nil && f.d.status==nil && f.d.views.isEmpty &&
                f.d.panels.isEmpty && f.d.globalMouseMonitor==nil && f.d.localMouseMonitor==nil &&
                f.d.visitorMemoryPersistence==nil && f.d.observationPersistence==nil && f.d.giftLedgerPersistence==nil &&
                [f.d.settingsURL,f.d.legacyURL,f.d.visitorMemoryURL,f.d.observationJournalURL,f.d.giftLedgerURL].allSatisfy {
                    $0.deletingLastPathComponent()==output && !FileManager.default.fileExists(atPath:$0.path)
                } && clear(f.d.engine)
        }
    }

    /// Shared only with the settings verifier so accepted UI previews use the
    /// same real window geometry, live pointer and natural settling boundary.
    final class Fixture {
        let d:DesktopController,overlay:OverlayPanel,view:DesktopView,hostWindow:NSWindow
        let work:CGRect,display:CGRect,suite:String,preferences:UserDefaults
        var birds=[Bird](),origins=[CGPoint](),ids=[BirdID]()
        var host=Surface(id:0,rect:.zero),layout=[String:Any](),crop=CGRect.zero
        private var settingsWindow:SpeciesSettingsWindow?
        var controls:SpeciesSettingsWindow {
            if let settingsWindow {return settingsWindow}
            let w=SpeciesSettingsWindow(desktop:d);settingsWindow=w;d.settingsWindow=w;return w
        }
        init(folder:URL) throws {
            let d=DesktopController(verificationSeed:0x434F5552544E4154);self.d=d
            guard let screen=NSScreen.screens.first,let work=d.screenRects.first,let display=d.displayRects.first else {
                throw failure("Courtship native verification requires an attached display")
            }
            self.work=work;self.display=display
            suite="Birding.CourtshipVerification."+UUID().uuidString
            guard let preferences=UserDefaults(suiteName:suite) else {throw failure("Cannot isolate preferences")}
            self.preferences=preferences;d.preferences=preferences
            d.automaticPopulation=false;d.pointerButtonsDown={false}
            d.engine.populationEnabled=false;d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            d.visitorMemoryPersistenceEnabled=false;d.observationJournalPersistenceEnabled=false;d.giftLedgerPersistenceEnabled=false
            d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
            d.visitorMemoryURL=folder.appendingPathComponent("visitors.json")
            d.observationJournalURL=folder.appendingPathComponent("journal.json");d.giftLedgerURL=folder.appendingPathComponent("gifts.json")
            hostWindow=NSWindow(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
            hostWindow.isReleasedWhenClosed=false;hostWindow.hasShadow=false;hostWindow.ignoresMouseEvents=true
            hostWindow.backgroundColor=NSColor(calibratedWhite:0.92,alpha:1)
            overlay=OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            overlay.isReleasedWhenClosed=false;overlay.hasShadow=false;overlay.ignoresMouseEvents=true
            overlay.isOpaque=false;overlay.backgroundColor = .clear;overlay.level = .floating
            view=DesktopView(frame:CGRect(origin:.zero,size:screen.frame.size));view.controller=d;view.desktopRect=display
            overlay.contentView=view
            d.engine.observationObserver={ [weak d] event in
                guard let d else {return}
                _=d.observationJournal.observe(event,at:Date(timeIntervalSince1970:1_700_000_000+event.simulationTime))
            }
        }
        func close() {
            d.engine.handle(.cancelAmbient(.shutdown));d.engine.observationObserver=nil
            settingsWindow?.cancel();settingsWindow=nil;d.settingsWindow=nil
            overlay.orderOut(nil);overlay.close();hostWindow.orderOut(nil);hostWindow.close()
            preferences.removePersistentDomain(forName:suite)
        }
        func install(scale:CGFloat=1,mirrored:Bool=false,species:SpeciesID = .spottedDove,count:Int=2) throws {
            d.paused=false;d.engine.handle(.cancelAmbient(.shutdown));d.birds=[];d.scale=scale
            d.engine.ambientEnabled=false;d.engine.autonomousRouting=false
            var value=d.settings
            value.probabilities=BirdSettings().probabilities
            value.courtshipEnabled=true;value.socialInteractions=true;value.visitorMemoryEnabled=false
            value.perchActions=false;value.passiveAttentionEnabled=false;value.sideHopEnabled=false
            value.takeoffPreparationEnabled=false;value.edgePeekEnabled=false
            value.pointerVisits=false;value.flockPasses=false;value.ambientLeafPlayEnabled=false
            value.chaseEnabled=false;value.travelTogetherEnabled=false;value.allopreeningEnabled=false
            value.insectCatchEnabled=false;value.visitorGiftsEnabled=false;value.activityRhythm = .steady
            value.hoverDelay=0;value.fixedPerches=[];d.settings=value
            d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
            let effective=scale*d.catalog.profile(species).relativeScale
            // Both full 48-unit mirrored canvases plus a real 20pt gap; never
            // shrink the birds to make a fixture fit. The engine checks its
            // authored display hull independently at admission and each tick.
            let gap=58*effective+20,width=ceil(max(360,gap+100*effective+84)),height:CGFloat=100
            let top=ceil(work.minY+39*effective+16),bottom=floor(work.maxY-height-16)
            let xs=[ceil(work.minX+16),floor(work.maxX-width-16)]
            let pointer=d.pointerPosition,margin=CourtshipGeometry.pointerPadding*scale
            func full(_ rect:CGRect)->CGRect {
                CGRect(x:rect.midX-gap/2-29*effective,y:rect.minY-39*effective,
                    width:gap+58*effective,height:48*effective)
            }
            let candidates=xs.flatMap {x in [top,bottom].map {y in CGRect(x:x,y:y,width:width,height:height)}}
            let feasible=candidates.filter {work.contains($0) && display.contains(full($0)) &&
                !full($0).insetBy(dx:-margin,dy:-margin).contains(pointer)}
            guard let rect=feasible.max(by:{a,b in
                Geometry.distance(pointer,CGPoint(x:a.midX,y:a.minY))<Geometry.distance(pointer,CGPoint(x:b.midX,y:b.minY))
            }) else {throw failure("Courtship fixture has no full-size pair clear of the live pointer: "+NSStringFromPoint(pointer))}
            hostWindow.setFrame(Geometry.quartz(rect,primaryHeight:d.primaryHeight),display:true)
            hostWindow.orderFrontRegardless();overlay.orderFrontRegardless()
            host=Surface(id:UInt32(hostWindow.windowNumber),pid:ProcessInfo.processInfo.processIdentifier,
                rect:Geometry.quartz(hostWindow.frame,primaryHeight:d.primaryHeight))
            crop=full(host.rect).insetBy(dx:-16,dy:-16)
            layout=["pointer":NSStringFromPoint(pointer),"effectiveScale":effective,"pointerMargin":margin,
                "host":NSStringFromRect(host.rect),"pairCanvasHull":NSStringFromRect(full(host.rect)),"gap":gap-58*effective]
            let lo=Geometry.perchX(0,rect:host.rect),hi=Geometry.perchX(1,rect:host.rect)
            birds=(0..<count).map {i in
                let left=mirrored ? i==1:i==0
                let x=host.rect.midX+(left ? -gap/2:gap/2)
                let b=Bird(position:.zero,fraction:(x-lo)/(hi-lo),profile:d.catalog.profile(species),random:{0.5})
                b.perch(on:host,spriteScale:effective);b.perchDuration=600;b.facingRight=left;return b
            }
            d.surfaces=[host];d.birds=birds
            advance(10.1)
            // Avoid a species' genuine periodic idle hop at admission. Time
            // advances normally; no pose, hop phase or feet are overwritten.
            for _ in 0..<5*120 {
                if d.engine.renderSnapshot().allSatisfy({abs($0.hopOffset)<0.001}) {break};step()
            }
            origins=birds.map(\.position);ids=birds.compactMap{d.engine.id(of:$0)}
            layout["settledTime"]=d.engine.time
            layout["quietSeconds"]=birds.map{d.engine.ecology(of:$0)?.quietTime ?? -1}
            layout["actualPointerClear"]=CourtshipGeometry.pointerIsClear(d.pointerPosition,feet:origins,
                birdScale:effective,worldScale:scale)
        }
        func step() {d.syncWorld(buttonsDown:false);d.engine.advance(1.0/120)}
        func advance(_ seconds:Double) {for _ in 0..<Int((seconds*120).rounded()) {step()}}
        func start(_ source:BehaviorSource = .preview)->BehaviorRunID? {
            let sequence=d.engine.events.last?.sequence ?? 0
            if source == .preview {controls.previewCourtshipButton.performClick(nil)}
            else {
                d.engine.ambientEnabled=source == .automatic;d.syncWorld(buttonsDown:false)
                _=d.engine.handle(.courtshipDisplay(source))
            }
            return d.engine.events.last{$0.sequence>sequence && $0.kind == .courtshipDisplay && $0.type == .started}?.runID
        }
        func sprite(_ id:BirdID)->CALayer? {view.layer?.sublayers?.first{$0.name=="bird-sprite-\(id.rawValue)"}}
    }

    @discardableResult private static func complete(_ f:Fixture,scale:CGFloat,mirrored:Bool,source:BehaviorSource,
                                 into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws -> Bool? {
        try f.install(scale:scale,mirrored:mirrored)
        let d=f.d,key="courtshipNative-\(source.rawValue)-\(scale)-\(mirrored ? "mirror":"forward")-"
        let before=d.observationJournal.archive,beforeEntry=entry(d),originals=f.birds,ids=f.ids,feet=f.origins
        guard let run=f.start(source),let start=d.engine.events.last(where:{$0.runID==run && $0.type == .started}) else {
            checks[key+"ProductionStart"]=false;evidence.append(["case":key,"reason":d.engine.events.last?.reason?.rawValue ?? "none","layout":f.layout]);return nil
        }
        checks[key+"ProductionStart"]=start.participants.count==2 && Set(start.participants)==Set(ids) && start.source==source &&
            d.engine.leasedBirdCount==2 && d.birds.count==2 && f.birds.allSatisfy{$0.state == .perched}
        let output=folder.appendingPathComponent(key+"display",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var frames=Set<String>(),images=[URL](),times=[Double](),samples=[[String:Any]]()
        var feetFixed=true,identity=true,leases=true,noEarlyRecord=true,layers=true,hits=true,pauseOK=true,roles=true
        let initiatorID=start.participants.first,initiator=f.birds.first{d.engine.id(of:$0)==initiatorID}
        let initiatorRight=initiator.map{$0.position.x<f.host.rect.midX}
        var pixelSamples=0,paused=0.0
        for tick in 0..<6*120 {
            guard d.engine.behavior(of:f.birds[0]) == .courtshipDisplay else {break}
            let states=d.engine.renderSnapshot();f.view.updateSprites()
            feetFixed = feetFixed && zip(f.birds,feet).allSatisfy{$0.0.position==$0.1 && $0.0.state == .perched} &&
                states.allSatisfy{$0.hopOffset==0}
            identity = identity && d.birds.count==2 && zip(d.birds,originals).allSatisfy{$0.0 === $0.1} &&
                f.birds.compactMap{d.engine.id(of:$0)}==ids && d.residentCount==2 && d.arrivalCount==0 && d.departureCount==0
            leases = leases && d.engine.activeRunCount==1 && d.engine.leasedBirdCount==2 &&
                f.birds.allSatisfy{d.engine.behavior(of:$0) == .courtshipDisplay}
            noEarlyRecord = noEarlyRecord && d.observationJournal.archive==before
            frames.formUnion(states.map(\.frameName))
            let runAge=d.engine.time-start.time-paused
            for state in states {
                let role:CourtshipRole=state.id==initiatorID ? .initiator:.observer
                let expectedFrame=PoseClip.courtship(species:.spottedDove,role:role)?.sample(at:runAge)?.name
                roles = roles && state.frameName==expectedFrame && state.facingRight==(state.position.x<f.host.rect.midX)
            }
            if tick%8==0 {
                try autoreleasepool {
                    let file=output.appendingPathComponent(String(format:"%04d-actual-layer.png",images.count))
                    let capture=try InsectCatchVerification.snapshot(f.view,around:f.crop,to:file)
                    images.append(file);times.append(d.engine.time-start.time-paused)
                    var pixels=[Int]()
                    for state in states {
                        guard let layer=f.sprite(state.id),let texture=layer.sublayers?.first else {layers=false;continue}
                        let n=try InsectCatchVerification.contribution(f.view,layer:layer,actual:capture,region:state.rect)
                        pixels.append(n);pixelSamples+=1
                        layers = layers && n>0 && (texture.contents as AnyObject?) === d.arts[state.species]?.frames[state.frameName] &&
                            (texture.affineTransform().a>=0)==state.facingRight && layer.mask?.mask==nil
                        if let p=InsectCatchVerification.visiblePoint(state,in:d),let bird=d.engine.bird(state.id) {
                            hits = hits && d.bird(at:p) === bird
                        } else {hits=false}
                    }
                    samples.append(["image":file.lastPathComponent,"runAge":times.last!,"simulationTime":d.engine.time,
                        "frames":states.map(\.frameName),"feet":states.map{NSStringFromPoint($0.position)},
                        "facingRight":states.map(\.facingRight),"birdPixels":pixels])
                }
            }
            if source == .preview,scale==1,!mirrored,tick==240 {
                let poses=d.engine.renderSnapshot();d.paused=true;f.advance(1);paused+=1
                pauseOK=d.engine.renderSnapshot().map(\.frameName)==poses.map(\.frameName) &&
                    d.engine.renderSnapshot().map(\.position)==poses.map(\.position) && d.observationJournal.archive==before
                d.paused=false
            }
            f.step()
        }
        let ends=terminal(d.engine,run),age=(ends.first?.time ?? .infinity)-start.time-paused
        let after=entry(d),a=counts(beforeEntry),b=counts(after)
        let expected=source == .automatic ? [1,0,0]:(source == .preview ? [0,1,0]:[0,0,1])
        checks[key+"FourSecondsAndAllFiveRealFrames"]=ends.count==1 && ends.first?.type == .completed &&
            abs(age-4)<=1.0/120+1e-6 && Set(SpeciesBehaviorProfile.courtshipFrameNames).isSubset(of:frames)
        checks[key+"BothFeetAndPopulationStayFixed"]=feetFixed && identity && leases && f.birds.map(\.position)==feet &&
            f.birds.allSatisfy{$0.state == .perched && $0.hostID==f.host.id}
        checks[key+"ActualRootLayersAndOpaqueHits"]=layers && hits && pixelSamples>=2*45
        checks[key+"RolesUseSameClockAndOppositeHeadings"]=roles
        let countChanges=zip(a,b).map{$0.1-$0.0}
        checks[key+"UniqueSourceRecordOnlyAfterCompletion"]=noEarlyRecord && countChanges==expected && after?.totalCount==(beforeEntry?.totalCount ?? 0)+1
        checks[key+"PauseAndFinalLeaseCleanup"]=pauseOK && clear(d.engine)
        f.advance(0.25)
        checks[key+"NoRepeatedCompletionOrCount"]=terminal(d.engine,run).count==1 && entry(d)==after
        let gif=folder.appendingPathComponent(key+"actual-layers.gif")
        if !images.isEmpty {try InsectCatchVerification.writeGIF(images,times:times,to:gif)}
        evidence.append(["case":key,"source":source.rawValue,"layout":f.layout,"unpausedDuration":age.isFinite ? age as Any:NSNull(),
            "frames":frames.sorted(),"samples":samples,"gif":gif.lastPathComponent,"terminal":ends.first?.type.rawValue ?? "none",
            "sourceCountsBefore":a,"sourceCountsAfter":b,"initiatorFacesRight":initiatorRight.map{$0 as Any} ?? NSNull(),
            "roleMeaning":"animation only; no sex or persistent pair"])
        return initiatorRight
    }

    private static func interruptions(_ f:Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]],folder:URL) throws {
        // Each participant can be clicked during every visual stage. Remaining
        // lifecycle causes use one representative active phase each.
        var cases=[(String,Double,Int)]()
        for age in [0.2,0.6,1.5,3.1,3.7] {for member in 0..<2 {cases.append(("click",age,member))}}
        for cause in ["child-off","social-off","remove","host-removed","host-moved","missing-frame","sleep","shutdown","paused-remove"] {
            cases.append((cause,1.5,0))
        }
        cases.append(("remove",1.5,1))
        for (cause,age,member) in cases {
            try f.install();let d=f.d,before=d.observationJournal.archive
            let key="courtshipNativeInterrupt-\(cause)-\(age)-\(member)"
            guard let run=f.start() else {checks[key]=false;continue}
            f.advance(age);f.view.updateSprites()
            let feet=f.birds.map(\.position),seq=d.engine.events.last?.sequence ?? 0
            var hit=true
            switch cause {
            case "click":
                guard let id=d.engine.id(of:f.birds[member]),let state=d.engine.renderSnapshot().first(where:{$0.id==id}),
                      let point=InsectCatchVerification.visiblePoint(state,in:d) else {checks[key]=false;continue}
                hit=d.bird(at:point) === f.birds[member]
                if hit,let event=NativeVerificationInput.leftDown(at:point) {
                    d.handleMouseDown(event) // Handler only: never post a system event.
                } else {hit=false}
            case "child-off":var v=d.settings;v.courtshipEnabled=false;d.settings=v
            case "social-off":var v=d.settings;v.socialInteractions=false;d.settings=v
            case "remove":d.birds=f.birds.enumerated().filter{$0.offset != member}.map(\.element)
            case "paused-remove":d.paused=true;d.birds=[f.birds[1]]
            case "host-removed":d.surfaces=[];d.syncWorld(buttonsDown:false)
            case "host-moved":
                var moved=f.host;moved.rect.origin.y+=20;d.surfaces=[moved];d.syncWorld(buttonsDown:false)
            case "missing-frame":d.frameCapabilities[.spottedDove]?.remove("courtBow1");d.syncWorld(buttonsDown:false)
            case "sleep":d.engine.handle(.cancelAmbient(.sleep))
            default:d.engine.handle(.cancelAmbient(.shutdown))
            }
            let noJump=f.birds.map(\.position)==feet
            f.step()
            let ends=terminal(d.engine,run)
            var counterpart=true
            if cause=="click" {
                let other=f.birds[1-member]
                counterpart=hit && d.engine.events.contains{$0.sequence>seq && $0.kind == .relocate && $0.type == .started} &&
                    d.engine.behavior(of:other)==nil && other.state == .perched && other.position==feet[1-member]
            }
            checks[key]=noJump && counterpart && ends.count==1 && ends.first?.type != .completed &&
                f.birds.allSatisfy{d.engine.behavior(of:$0) != .courtshipDisplay} && d.observationJournal.archive==before &&
                (cause=="click" || clear(d.engine))
            if cause=="click" {
                for _ in 0..<35*120 {if d.engine.behavior(of:f.birds[member]) != .relocate {break};f.step()}
                checks[key+"RelocationLandsAndReleases"]=f.birds[member].state == .perched &&
                    f.birds[member].hostID==f.host.id && clear(d.engine) && d.observationJournal.archive==before
            }
            f.view.updateSprites()
            _=try InsectCatchVerification.snapshot(f.view,around:f.crop,to:folder.appendingPathComponent(key+"-actual-layer.png"))
            evidence.append(["interrupt":key,"hitOriginal":hit,"noJump":noJump,"terminal":ends.first?.type.rawValue ?? "none",
                "reason":ends.first?.reason?.rawValue ?? "none","counterpartRestored":counterpart,"layout":f.layout])
        }
    }
    static func entry(_ d:DesktopController)->ObservationEntry? {
        d.observationJournal.archive.entries.first{$0.species == .spottedDove && $0.behavior=="courtshipDisplay"}
    }
    static func counts(_ entry:ObservationEntry?)->[Int] {[entry?.automaticCount ?? 0,entry?.previewCount ?? 0,entry?.userCount ?? 0]}
    static func clear(_ e:BehaviorEngine)->Bool {e.activeRunCount==0 && e.leasedBirdCount==0 && e.reservedLandingCount==0 && e.scenePropCount==0}
    private static func terminal(_ e:BehaviorEngine,_ run:BehaviorRunID)->[BehaviorEvent] {e.events.filter{$0.runID==run && [.completed,.failed,.cancelled].contains($0.type)}}
    private static func failure(_ message:String)->NSError {NSError(domain:"CourtshipVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
}
