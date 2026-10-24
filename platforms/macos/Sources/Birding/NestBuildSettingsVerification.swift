import AppKit
import BirdingCore

enum NestBuildSettingsVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("nest-build-settings-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        var completed=false
        defer {NestMaterialVerification.report(checks,evidence:evidence,prefix:"nestBuildSettings",folder:output,completed:completed)}
        try autoreleasepool {
            let f=try NestMaterialVerification.Fixture(folder:output);defer {f.close()}
            let d=f.d,w=f.controls;w.showWindow(nil)
            for language:AppLanguage in [.chinese,.english] {
                d.language=language;w.relocalize();w.tabs.selectTabViewItem(at:2)
                let key="nestBuildSettings-"+language.rawValue+"-"
                try f.install();try f.place()
                NestMaterialSettingsVerification.rejection(f,build:true,reason:.noSpace,key:key+"NoDeliveredMaterial",into:&checks)
                checks[key+"ExplainsOneStepAndNoReplenishment"]=w.message.stringValue==w.nestMessage(.noSpace,build:true) &&
                    w.message.stringValue.contains(w.t("请先预览运送一根","preview one delivery first")) &&
                    d.engine.nestSnapshot().first?.available==3 && d.engine.nestSnapshot().first?.progress==0
                guard NestMaterialVerification.journey(f,kind:.nestMaterialCarry,source:.preview,key:key+"real-delivery-",capture:false,
                    into:&checks,evidence:&evidence,folder:output) else {checks[key+"ActualDeliveryPreparesBuild"]=false;continue}
                f.settle()
                d.frameCapabilities[.spottedDove]?.remove("nestAdjust1")
                NestMaterialSettingsVerification.rejection(f,build:true,reason:.missingFrames,key:key+"MissingDedicatedFrame",into:&checks)
                d.frameCapabilities=d.arts.mapValues{Set($0.frames.keys)}
                d.paused=true
                NestMaterialSettingsVerification.rejection(f,build:true,reason:.paused,key:key+"Paused",into:&checks);d.paused=false
                let archive=d.observationJournal.archive,nest=d.engine.nestSnapshot().first,ids=d.birds.compactMap{d.engine.id(of:$0)}
                NestMaterialSettingsVerification.set(w.nestBuildingButton,false)
                NestMaterialSettingsVerification.set(w.socialInteractionsButton,false)
                guard let run=f.start(.nestBuild) else {checks[key+"SavedOnSingleStepStarts"]=false;continue}
                checks[key+"SavedOnSingleStepStarts"] = !w.draft.nestBuildingEnabled && !w.draft.socialInteractions &&
                    d.settings.nestBuildingEnabled && !d.settings.socialInteractions && d.birds.compactMap{d.engine.id(of:$0)}==ids
                NestMaterialSettingsVerification.rejection(f,build:true,reason:.busy,key:key+"BusyKeepsExistingVisit",into:&checks)
                guard f.seek({n,_ in n.progress==(nest?.progress ?? -1)+1}) else {checks[key+"ReachedRealCommit"]=false;continue}
                w.refreshNestControls()
                checks[key+"CommitProgressDoesNotCreditEarly"]=d.engine.nestSnapshot().first?.progress==1 &&
                    d.engine.nestSnapshot().first?.available==2 && d.observationJournal.archive==archive &&
                    !d.engine.events.contains{$0.runID==run && $0.type == .completed}
                for _ in 0..<31*120 {if d.engine.behavior(of:f.bird!) != .nestBuild {break};f.step()}
                let ends=NestMaterialVerification.terminal(d.engine,run)
                let before=archive.entries.first{$0.species == .spottedDove && $0.behavior=="nestBuild"}?.previewCount ?? 0
                checks[key+"SinglePreviewArrangesExactlyOneAndCountsOnce"]=ends.count==1 && ends.first?.type == .completed &&
                    d.engine.nestSnapshot().first?.progress==1 && d.engine.nestSnapshot().first?.delivered==0 &&
                    d.engine.nestSnapshot().first?.available==2 && NestMaterialVerification.entry(d,kind:.nestBuild)?.previewCount==before+1
                w.refreshNestControls()
                if let scroll=w.tabs.tabViewItems[2].view as? NSScrollView,let doc=scroll.documentView {
                    scroll.contentView.scroll(to:CGPoint(x:0,y:doc.bounds.height-scroll.contentView.bounds.height));scroll.reflectScrolledClipView(scroll.contentView)
                    checks[key+"ProgressAndAllFiveInventoryStatesFit"]=EdgePeekSettingsVerification.messageIsFullyVisible(w.nestStatus) &&
                        w.nestStatus.stringValue.contains(w.t("已整理 1 / 3","Arranged 1 / 3"))
                    try SettingsVerification.snapshot(w.window!,to:output.appendingPathComponent("nest-build-progress-"+language.rawValue+".png"))
                }
                let completedArchive=d.observationJournal.archive
                w.removeNestButton.performClick(nil);f.advance(3)
                checks[key+"ClearDoesNotAddObservationOrLoseDraft"]=NestMaterialVerification.clear(d.engine) &&
                    d.observationJournal.archive==completedArchive && !w.draft.nestBuildingEnabled
            }
            checks["nestBuildSettingsBoundedControllersAndPersistence"]=f.isolated
        }
        try autoreleasepool {try NestMaterialSettingsVerification.journal(kind:.nestBuild,prefix:"nestBuildSettings",into:&checks,folder:output)}
        completed=true
    }
}
