import AppKit
import BirdingCore

enum ExpandedVerification {
    static func run(to folder:URL) {
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let d=DesktopController()
            let host=Surface(id:1,rect:CGRect(x:120,y:300,width:620,height:330))
            d.surfaces=[host]
            let specs:[(SpeciesID,CGFloat,Double)]=[(.nightHeron,230,12),(.plumbeousWaterRedstart,430,2.3),(.littleEgret,620,0)]
            for (id,x,age) in specs {
                let b=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(id));b.perch(on:host);b.position.x=x;b.tick(age);d.birds.append(b)
            }
            let wood=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.greatSpottedWoodpecker))
            wood.edge = .left;wood.perch(on:host);wood.tick(4.2);d.birds.append(wood)
            let window=OverlayPanel(contentRect:CGRect(x:200,y:150,width:840,height:690),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.ignoresMouseEvents=true;window.isOpaque=false;window.backgroundColor = .clear
            let view=DesktopView(frame:CGRect(x:0,y:0,width:840,height:690));view.controller=d;view.desktopRect=view.bounds
            window.contentView=view;window.orderFrontRegardless()
            var checks:[String:Bool]=[:]
            let bird=d.birds[0],s=d.spriteScale(for:d.birds[0]),art=d.arts[.nightHeron]!
            let opaque=(0..<48*48).first{art.contains(frame:bird.frameName,x:$0%48,y:$0/48)}!
            let point=CGPoint(x:bird.position.x+(CGFloat(opaque%48)+0.5-29)*s,y:bird.position.y+(CGFloat(opaque/48)+0.5-39)*s)
            d.updateHover(now:0,at:point);d.updateHover(now:0.99,at:point);checks["delayedHover"]=d.hoveredBird == nil
            d.updateHover(now:1,at:point);checks["visiblePixelName"]=d.hoveredBird === bird
            view.updateSprites();try SettingsVerification.snapshot(window,to:folder.appendingPathComponent("birds-and-hover.png"))
            d.hoverTracker=HoverTracker<BirdID>();d.settings.hoverDelay=0.25
            d.updateHover(now:2,at:point);d.updateHover(now:2.24,at:point)
            checks["customHoverDelayWaitsUntilConfiguredTime"]=d.hoveredBird == nil
            d.updateHover(now:2.25,at:point);checks["customHoverDelayShowsName"]=d.hoveredBird === bird
            d.hoverTracker=HoverTracker<BirdID>();d.settings.hoverDelay=0
            d.updateHover(now:3,at:point);checks["zeroHoverDelayShowsNameImmediately"]=d.hoveredBird === bird
            d.settings.hoverDelay=1
            d.surfaces.insert(Surface(id:2,rect:CGRect(x:point.x-2,y:point.y-2,width:4,height:4)),at:0)
            d.updateHover(now:4,at:point);checks["occludedPixelResetsHover"]=d.hoveredBird == nil
            d.surfaces=[host]
            d.updateHover(now:8,at:CGPoint(x:bird.position.x-29*s+0.1,y:bird.position.y-39*s+0.1))
            checks["transparentPixelNotHit"]=d.hoveredBird == nil
            checks["overlayPassesInput"]=window.ignoresMouseEvents && !window.canBecomeKey && !window.canBecomeMain
            d.birds[0].tick(19.4);checks["nightHeronDropping"]=d.birds[0].frameName.hasPrefix("poop")
            view.updateSprites();try SettingsVerification.snapshot(window,to:folder.appendingPathComponent("night-heron-action.png"))
            checkRelocation(into:&checks,host:host)
            checkAmbient(into:&checks)
            try PerchActivityVerification.run(into:&checks,folder:folder)
            try SocialGreetingVerification.run(into:&checks,folder:folder)
            try ArrivalRenderingVerification.run(into:&checks,folder:folder)
            window.orderOut(nil)
            saveJSON(["passed":checks.values.allSatisfy{$0},"checks":checks],to:folder.appendingPathComponent("report.json"))
            print("Expanded bird UI: \(checks.values.allSatisfy{$0} ? "PASS":"FAIL") — \(checks.count) checks")
            exit(checks.values.allSatisfy{$0} ? 0:1)
        } catch {print(error);exit(1)}
    }

    static func visiblePoint(on bird:Bird,in d:DesktopController) -> CGPoint {
        let state=d.renderSnapshot().first{$0.id==d.engine.id(of:bird)}!
        let art=d.arts[state.species]!
        let pixel=(0..<48*48).first{art.contains(frame:state.frameName,x:$0%48,y:$0/48)}!
        let x=state.facingRight ? pixel%48:47-pixel%48
        return CGPoint(x:state.rect.minX+(CGFloat(x)+0.5)*state.scale,
                       y:state.rect.minY+(CGFloat(pixel/48)+0.5)*state.scale)
    }
    static func checkAmbient(into checks:inout [String:Bool]) {
        let d=DesktopController();d.automaticPopulation=false
        let screen=d.screenRects[0],center=CGPoint(x:screen.midX,y:screen.midY)
        let host=Surface(id:90,rect:CGRect(x:screen.minX+40,y:screen.maxY-65,width:screen.width-80,height:50))
        let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.treeSparrow))
        bird.perch(on:host);d.surfaces=[host];d.birds=[bird]
        checks["pointerVisitStartsOnPerchedBird"]=d.startPointerVisit(at:center) && d.engine.behavior(of:bird) == .pointerVisit && d.residentCount == 1
        checks["ambientEventsAreMutuallyExclusive"] = !d.startFlockPass()
        for _ in 0..<8 {d.advanceBirds(0.05,at:center,buttonsDown:false)}
        let position=bird.position
        d.advanceBirds(1.0/60,at:CGPoint(x:center.x+30,y:center.y),buttonsDown:false)
        checks["movingPointerCancelsWithoutTeleport"]=d.engine.behavior(of:bird) == nil && Geometry.distance(bird.position,position)<10 && !bird.isDeparting
        bird.perch(on:host);_=d.startPointerVisit(at:center)
        let hit=visiblePoint(on:bird,in:d)
        checks["clickOverridesPointerVisit"]=d.relocateBird(at:hit) && d.engine.behavior(of:bird) == .relocate && d.engine.activeRunCount == 1
        d.engine.handle(.cancelAmbient(.screensChanged));bird.perch(on:host)
        _=d.startPointerVisit(at:center)
        d.togglePause(NSMenuItem())
        checks["pauseEndsPointerInteraction"]=d.paused && d.engine.behavior(of:bird) == nil
        d.paused=false;bird.perch(on:host)
        checks["flockStarts"]=d.startFlockPass() && (3...5).contains(d.engine.pendingCount)
        let members=d.engine.events.last(where:{$0.type == .started && $0.kind == .flockPass})?.participants ?? []
        let count=members.count
        let duration=members.compactMap{d.engine.bird($0)?.flightDuration}.max() ?? 0
        let sameSpecies=Set(members.compactMap{d.engine.bird($0)?.profile.id}).count == 1
        checks["secondFlockCannotOverlap"] = !d.startFlockPass()
        bird.perchDuration=600
        var appeared:[BirdID:Int]=[:]
        for step in 0..<Int(ceil((duration+4)/0.05)) {
            d.advanceBirds(0.05,at:center,buttonsDown:false)
            for state in d.engine.renderSnapshot() where members.contains(state.id) && appeared[state.id]==nil {appeared[state.id]=step}
            if d.residentCount != 1 || d.birds.count>count+1 {checks["flockPopulationIsBounded"]=false}
        }
        checks["flockUsesSameSpeciesAndStaggeredEntry"]=sameSpecies && Set(appeared.values).count == count
        checks["flockPopulationIsBounded"] = checks["flockPopulationIsBounded"] ?? true
        checks["flockLeavesNoResidentsOrDepartureStats"]=d.birds.count == 1 && d.engine.pendingCount == 0 && d.departureCount == 0 && d.engine.leasedBirdCount == 0
        _=d.startFlockPass();d.advanceBirds(0.05,at:center,buttonsDown:false)
        d.engine.handle(.cancelAmbient(.sleep))
        checks["screenAndSleepCleanupRemovesTransientBirds"] = !d.ambientBusy && d.engine.pendingCount == 0 && d.birds.count == 1
        var solo=d.catalog;solo.species=[d.catalog.profile(.commonKestrel)]
        d.settings.probabilities=ProbabilityDistribution(catalog:solo)
        checks["flockRespectsDisabledSpecies"] = !d.startFlockPass()
    }
    static func checkRelocation(into checks:inout [String:Bool],host:Surface) {
        let d=DesktopController();d.automaticPopulation=false
        let screen=d.screenRects[0]
        let destination=Surface(id:3,rect:CGRect(x:screen.minX+30,y:screen.maxY-110,width:screen.width-60,height:110))
        d.surfaces=[host,destination];d.scale=1.5
        let behind=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.littleEgret))
        let bird=Bird(position:.zero,fraction:0.5,profile:d.catalog.profile(.littleEgret))
        for b in [behind,bird] {b.perch(on:host);b.facingRight=false}
        d.birds=[behind,bird]
        let s=d.spriteScale(for:bird),point=visiblePoint(on:bird,in:d)
        checks["mirroredScaledPixelHitsTopBird"]=d.bird(at:point) === bird
        // Desktop coordinates may be negative on a display left of the primary.
        for b in d.birds {b.position.x-=1200}
        checks["negativeDesktopCoordinatesHit"]=d.bird(at:CGPoint(x:point.x-1200,y:point.y)) === bird
        for b in d.birds {b.position.x+=1200}

        let transparent=CGPoint(x:bird.position.x-19*s+0.1,y:bird.position.y-39*s+0.1)
        checks["transparentClickDoesNotMoveBird"] = !d.relocateBird(at:transparent) && bird.state == .perched && behind.state == .perched
        d.surfaces.insert(Surface(id:2,rect:CGRect(x:point.x-2,y:point.y-2,width:4,height:4)),at:0)
        checks["occludedClickDoesNotMoveBird"] = !d.relocateBird(at:point) && bird.state == .perched && behind.state == .perched
        d.surfaces=[host,destination]
        d.updateHover(now:0,at:point);d.updateHover(now:1,at:point)
        checks["hoverNamesTopBirdBeforeClick"]=d.hoveredBird === bird

        if let cgEvent=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left),
           let event=NSEvent(cgEvent:cgEvent) {
            d.handleMouseDown(event)
            checks["clickEventMovesOnlyTopBird"] = !bird.isDeparting && bird.state == .flying && bird.hostID != nil && !bird.needsDestination && behind.state == .perched
            checks["clickImmediatelyClearsName"]=d.hoveredBird == nil && d.hoverTracker.target == nil
            // Taking off changes the sprite. Target a visible pixel in the new
            // frame; the original point can now reveal the bird underneath.
            let flyingPoint=visiblePoint(on:bird,in:d)
            checks["repeatedClickDoesNotRestartMove"] = d.bird(at:flyingPoint) === bird && !d.relocateBird(at:flyingPoint)
            d.updateHover(now:2,at:flyingPoint);d.updateHover(now:3,at:flyingPoint)
            checks["movingBirdDoesNotShowStaleName"]=d.hoveredBird == nil
        } else {checks["clickEventMovesOnlyTopBird"]=false}

        d.paused=true
        let start=bird.position,still=behind.position
        d.advanceBirds(0.05)
        checks["clickedBirdMovesWhileOthersStayPaused"]=bird.position != start && behind.position == still && behind.state == .perched
        for _ in 0..<Int(ceil((bird.flightDuration+1)/0.05)) {d.advanceBirds(0.05)}
        checks["clickedBirdLandsAwayFromOldSpot"]=bird.state == .perched && Geometry.distance(bird.position,start)>100 && d.displayRects.contains(where:{$0.contains(bird.position)})
        checks["relocationPreservesBirdAndPopulation"]=d.birds.count == 2 && d.birds.contains(where:{$0 === bird}) && !bird.isDeparting && d.residentCount == 2 && d.arrivalCount == 0 && d.departureCount == 0
        checks["relocationFinishesWhilePaused"]=d.engine.behavior(of:bird) == nil && behind.position == still
        let landedPoint=visiblePoint(on:bird,in:d)
        d.updateHover(now:10,at:landedPoint);d.updateHover(now:11,at:landedPoint)
        checks["hoverNameReturnsAtNewPerch"]=d.hoveredBird === bird

        let fallback=DesktopController();fallback.automaticPopulation=false
        let airborne=Bird(position:CGPoint(x:screen.midX,y:screen.midY),fraction:0.5,profile:fallback.catalog.profile(.blackKite))
        fallback.birds=[airborne]
        let original=airborne.position
        checks["noPerchStillStartsRelocation"]=fallback.relocateBird(at:visiblePoint(on:airborne,in:fallback))
        airborne.tick(airborne.flightDuration+0.01)
        checks["noPerchFallbackStaysOnscreen"] = !airborne.isDeparting && fallback.displayRects.contains(where:{$0.contains(airborne.position)}) && Geometry.distance(airborne.position,original)>100

        if let ground=fallback.groundSurfaces().first {
            fallback.engine.handle(.cancelAmbient(.screensChanged));fallback.surfaces=[ground]
            airborne.perch(on:ground)
            let groundStart=airborne.position
            let moved=fallback.relocateBird(at:visiblePoint(on:airborne,in:fallback))
            airborne.tick(airborne.flightDuration+0.01);airborne.tick(0.5)
            checks["groundBirdFindsDifferentGroundPerch"]=moved && airborne.state == .perched && airborne.hostID == ground.id && Geometry.distance(airborne.position,groundStart)>100 && !airborne.isDeparting
        } else {checks["groundBirdFindsDifferentGroundPerch"]=false}
        d.startMouseMonitoring()
        checks["mouseMonitorsInstalled"]=d.globalMouseMonitor != nil && d.localMouseMonitor != nil
        d.startMouseMonitoring();d.stopMouseMonitoring()
        checks["mouseMonitorsCleanedUp"]=d.globalMouseMonitor == nil && d.localMouseMonitor == nil
    }
}
