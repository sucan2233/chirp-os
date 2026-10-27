import AppKit
import BirdingCore

/// Native acceptance uses a private preferences suite and caller-owned directory.
/// It never starts the production controller or writes its configuration.
enum CompanionSceneVerification {
    static func run(to folder:URL) {
        var checks:[String:Bool]=[:]
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let suite="ChirpOS.CompanionVerification."+UUID().uuidString
            let prefs=UserDefaults(suiteName:suite)!
            defer {prefs.removePersistentDomain(forName:suite)}
            let d=DesktopController(verificationSeed:742);d.isolatedSession=true;d.preferences=prefs
            d.settingsURL=folder.appendingPathComponent("settings.json");d.legacyURL=folder.appendingPathComponent("legacy.json")
            d.settings = .companionDefaults;d.makeMenu();d.loadSceneLayout();d.syncWorld()
            d.showSpeciesSettings();let settings=d.settingsWindow!
            settings.tabs.selectTabViewItem(at:2)
            checks["naturalDefaultAndNativeModePage"] = settings.companionModePopup.indexOfSelectedItem==1 && d.settings.companion?.mode == .natural
            checks["oldPlacementControlsRemoved"] = settings.placeBathButton.isHidden && settings.placeFoodTrayButton.isHidden && settings.placeNestButton.isHidden
            settings.companionModePopup.selectItem(at:2);settings.companionChanged()
            let menu=NSMenuItem();menu.tag=0;d.chooseCompanionMode(menu)
            checks["menuSaveDetectsEditedDraftConflict"] = settings.companionConflict && d.settings.companion?.mode == .focus && settings.draft.companion?.mode == .lively
            settings.save();checks["conflictCannotOverwriteMenuSelection"] = d.settings.companion?.mode == .focus
            settings.companionModePopup.selectItem(at:1);settings.companionChanged();settings.save()
            checks["explicitResolutionSavesNatural"] = !settings.companionConflict && d.settings.companion?.mode == .natural
            settings.companionManual.performClick(nil)
            checks["advancedCategoryControlsReveal"] = settings.companionCategoryControls.allSatisfy{!$0.0.isHidden && $0.1.isEnabled}
            settings.companionCategoryControls[2].0.performClick(nil);settings.save()
            checks["categoryOverrideSaved"] = d.settings.companion?.categoryOverrides[.social]?.enabled == false
            try capture(settings.window!.contentView!,to:folder.appendingPathComponent("companion-settings.png"))
            settings.cancel()
            d.showSceneEditor();let editor=d.sceneEditor!
            guard let area=d.engine.world.displays.first else {throw SceneError.invalid("No display for native verification")}
            let foot=CGPoint(x:area.minX+area.width*0.25,y:area.minY+area.height*0.65)
            let bathFoot=CGPoint(x:area.minX+area.width*0.72,y:foot.y)
            guard let food=editor.placement(kind:.foodTray,point:foot),let bath=editor.placement(kind:.bath,point:bathFoot) else {throw SceneError.invalid("Native placement unavailable")}
            checks["libraryPlacementToDraft"] = editor.place(food) && editor.place(bath)
            checks["draftDoesNotMutateLiveScene"] = d.engine.habitatSnapshot().isEmpty && d.engine.sceneEditing
            editor.selected=food.id
            let canvas=editor.canvases.first!
            let start=canvas.rect(food)!.centerPoint
            func mouse(_ type:NSEvent.EventType,_ point:NSPoint)->NSEvent {
                NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:canvas.window!.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            }
            canvas.mouseDown(with:mouse(.leftMouseDown,start))
            canvas.mouseDragged(with:mouse(.leftMouseDragged,NSPoint(x:start.x+60,y:start.y)))
            canvas.mouseUp(with:mouse(.leftMouseUp,NSPoint(x:start.x+60,y:start.y)))
            let moved=editor.draft.layout.instances.first{$0.id==food.id}!
            checks["nativeCanvasDragChangesDraftAnchor"] = moved.anchor != food.anchor && editor.draft.layout.instances.count==2
            editor.undoEdit();checks["undoDrag"] = editor.draft.layout.instances.first{$0.id==food.id}?.anchor==food.anchor
            editor.redoEdit();checks["redoDrag"] = editor.draft.layout.instances.first{$0.id==food.id}?.anchor==moved.anchor
            let key=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:canvas.window!.windowNumber,
                                    context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:124)!
            canvas.keyDown(with:key)
            checks["keyboardNudge"] = editor.draft.layout.instances.first{$0.id==food.id}?.anchor != moved.anchor
            try capture(editor.window!.contentView!,to:folder.appendingPathComponent("scene-editor.png"))
            try capture(canvas,to:folder.appendingPathComponent("scene-canvas.png"))
            let overlays=editor.overlays
            editor.apply()
            checks["applyCommitsBothKinds"] = d.engine.sceneArchive.layout.instances.count==2 && d.engine.habitatSnapshot().count==2
            checks["applyReleasesInputCapture"] = !d.engine.sceneEditing && editor.overlays.isEmpty && overlays.allSatisfy{$0.ignoresMouseEvents && !$0.isVisible}
            let saved=try ScenePersistence(url:folder.appendingPathComponent("scene-layout.json")).load()
            checks["layoutDurableReload"] = saved==d.engine.sceneArchive
            d.showSceneEditor();let cancelled=d.sceneEditor!
            cancelled.selected=food.id;cancelled.removeSelected();cancelled.cancel()
            checks["cancelKeepsCommittedLayout"] = d.engine.sceneArchive==saved && !d.engine.sceneEditing && cancelled.overlays.isEmpty
            d.showSceneEditor();let lostFocus=d.sceneEditor!;lostFocus.deactivated()
            checks["deactivationReleasesOverlay"] = !d.engine.sceneEditing && lostFocus.overlays.isEmpty
            d.status.isVisible=false
            let passed=checks.values.allSatisfy{$0}
            saveJSON(["passed":passed,"checks":checks,"physicalExternalDisplay":"not tested"],to:folder.appendingPathComponent("report.json"))
            print("Companion and scene native acceptance: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
            exit(passed ? 0:1)
        } catch {
            saveJSON(["passed":false,"checks":checks,"error":error.localizedDescription],to:folder.appendingPathComponent("report.json"))
            print(error);exit(1)
        }
    }
    private static func capture(_ view:NSView,to url:URL) throws {
        view.window?.displayIfNeeded();view.displayIfNeeded()
        guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {throw SceneError.invalid("Native capture unavailable")}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let png=bitmap.representation(using:.png,properties:[:]) else {throw SceneError.invalid("PNG encoding failed")}
        try png.write(to:url)
    }
}
private extension CGRect {var centerPoint:NSPoint {NSPoint(x:midX,y:midY)}}
