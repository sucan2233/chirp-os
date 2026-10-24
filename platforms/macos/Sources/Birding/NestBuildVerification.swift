import AppKit
import BirdingCore

enum NestBuildVerification {
    static func run(into checks:inout [String:Bool],folder:URL) throws {
        let output=folder.appendingPathComponent("nest-build-native-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var evidence=[[String:Any]]()
        var completed=false
        var caseErrors=[String:String]()
        defer {NestMaterialVerification.report(checks,evidence:evidence,prefix:"nestBuildNative",folder:output,completed:completed,caseErrors:caseErrors)}
        for scale:CGFloat in [0.5,1,2] {for right in [true,false] {
            NestMaterialVerification.runCase("scale-\(scale)-\(right ? "right":"left")",errors:&caseErrors) {
            let f=try NestMaterialVerification.Fixture(folder:output);defer {f.close()}
            try f.install(scale:scale,right:right);try f.place()
            let key="nestBuildNative-\(scale)-\(right ? "right":"left")-"
            guard NestMaterialVerification.journey(f,kind:.nestMaterialCarry,source:.preview,key:key+"prepare-",capture:false,
                into:&checks,evidence:&evidence,folder:output) else {checks[key+"PreparationDeliveredRealTwig"]=false;return}
            _=NestMaterialVerification.journey(f,kind:.nestBuild,source:.preview,key:key,capture:true,
                into:&checks,evidence:&evidence,folder:output)
        }}}
        NestMaterialVerification.runCase("completeThree",errors:&caseErrors) {
            let f=try NestMaterialVerification.Fixture(folder:output);defer {f.close()}
            try completeThree(f,into:&checks,evidence:&evidence,folder:output)
        }
        NestMaterialVerification.runCase("automaticFocus",errors:&caseErrors) {
            let f=try NestMaterialVerification.Fixture(folder:output);defer {f.close()}
            try automaticFocus(f,into:&checks,evidence:&evidence)
        }
        NestMaterialVerification.runCase("pauseAndResume",errors:&caseErrors) {
            let f=try NestMaterialVerification.Fixture(folder:output);defer {f.close()}
            try pauseAndResume(f,into:&checks,evidence:&evidence,folder:output)
        }
        NestMaterialVerification.runCase("interruptions",errors:&caseErrors) {
            let f=try NestMaterialVerification.Fixture(folder:output);defer {f.close()}
            try NestMaterialVerification.interruptions(f,build:true,into:&checks,evidence:&evidence,folder:output)
            checks["nestBuildNativeIsolationAndFinalResources"]=f.isolated && NestMaterialVerification.clear(f.d.engine)
        }
        try NestMaterialVerification.requireAllCases(caseErrors)
        completed=true
    }
    private static func pauseAndResume(_ f:NestMaterialVerification.Fixture,into checks:inout [String:Bool],
        evidence:inout [[String:Any]],folder:URL) throws {
        for phase in NestMaterialVerification.buildPhases {try autoreleasepool {
            let key="nestBuildNativePauseResume-\(phase)-"
            try f.install();try f.place()
            guard NestMaterialVerification.journey(f,kind:.nestMaterialCarry,source:.preview,key:key+"prepare-",capture:false,
                into:&checks,evidence:&evidence,folder:folder),let bird=f.bird else {checks[key+"Preparation"]=false;return}
            f.settle()
            let d=f.d,archive=d.observationJournal.archive,beforeCounts=NestMaterialVerification.counts(NestMaterialVerification.entry(d,kind:.nestBuild))
            let carryBefore=NestMaterialVerification.entry(d,kind:.nestMaterialCarry)
            guard let run=f.start(.nestBuild),NestMaterialVerification.seekPhase(phase,build:true,in:f),
                  let before=d.engine.nestSnapshot().first else {checks[key+"ReachedLiveStage"]=false;return}
            checks[key+"ReachedLiveStage"]=NestMaterialVerification.terminal(d.engine,run).isEmpty && d.observationJournal.archive==archive
            checks[key+"FrozenMaterialPoseLifetimeAndObservation"]=NestMaterialVerification.pauseFreezesVisit(f,run:run,kind:.nestBuild)
            checks[key+"PreviewRejectedWhilePaused"]=d.engine.handle(.nestBuild(.preview)) == .rejected(.paused)
            d.paused=false
            var noEarlyObservation=true
            for _ in 0..<30*120 {
                if !NestMaterialVerification.terminal(d.engine,run).isEmpty {break}
                noEarlyObservation = noEarlyObservation && d.observationJournal.archive==archive
                f.step()
            }
            let ends=NestMaterialVerification.terminal(d.engine,run),after=d.engine.nestSnapshot().first
            let delta=zip(beforeCounts,NestMaterialVerification.counts(NestMaterialVerification.entry(d,kind:.nestBuild))).map{$0.1-$0.0}
            checks[key+"ActualSafeExitAndUniqueObservation"]=noEarlyObservation && ends.count==1 && ends.first?.type == .completed &&
                delta==[0,1,0] && NestMaterialVerification.entry(d,kind:.nestMaterialCarry)==carryBefore &&
                NestMaterialVerification.safeOrdinaryRest(bird,in:d) && bird.hostID==f.host.id &&
                NestMaterialVerification.clearRun(d.engine) && NestMaterialVerification.releasedNestMaterials(d.engine)
            checks[key+"ExactlyOneCommittedTwig"]=after.map {nest in
                NestMaterialVerification.conserved(nest) && nest.progress==1 && nest.delivered==0 && nest.available==2 &&
                    nest.materials.map(\.id)==before.materials.map(\.id) &&
                    nest.materials.filter{$0.state == .arranged}.map(\.arrangementRunID)==[run] &&
                    nest.materials.map(\.deliveryRunID)==before.materials.map(\.deliveryRunID)
            }==true
            let completedArchive=d.observationJournal.archive
            f.advance(0.5)
            checks[key+"NoDuplicateAfterResume"]=NestMaterialVerification.terminal(d.engine,run).count==1 &&
                d.observationJournal.archive==completedArchive && d.engine.nestSnapshot().first?.progress==1 &&
                d.engine.nestSnapshot().first?.materials==after?.materials
            evidence.append(["pauseResume":phase,"run":run.rawValue,"beforeProgress":before.progress,
                "afterProgress":after.map{$0.progress as Any} ?? NSNull(),"terminal":ends.first?.type.rawValue ?? "none",
                "foot":NSStringFromPoint(bird.position),"host":bird.hostID.map{Int($0)} ?? -1])
            d.engine.handle(.clearCurrentScene);f.advance(3)
            checks[key+"FinalCleanup"]=NestMaterialVerification.clear(d.engine)
        }}
    }
    private static func completeThree(_ f:NestMaterialVerification.Fixture,into checks:inout [String:Bool],
        evidence:inout [[String:Any]],folder:URL) throws {
        try f.install();try f.place()
        let d=f.d,carryBefore=NestMaterialVerification.counts(NestMaterialVerification.entry(d,kind:.nestMaterialCarry)),
            buildBefore=NestMaterialVerification.counts(NestMaterialVerification.entry(d,kind:.nestBuild))
        var completed=true
        for index in 1...3 {
            let key="nestBuildNativeThree-\(index)-"
            let carry=NestMaterialVerification.journey(f,kind:.nestMaterialCarry,source:.preview,key:key+"carry-",capture:false,
                into:&checks,evidence:&evidence,folder:folder)
            let build=carry && NestMaterialVerification.journey(f,kind:.nestBuild,source:.preview,key:key+"build-",capture:index==3,
                into:&checks,evidence:&evidence,folder:folder)
            completed = completed && carry && build
            let nest=d.engine.nestSnapshot().first
            checks[key+"ProgressOverlayAndStock"]=nest?.progress==index && nest?.available==3-index &&
                nest?.delivered==0 && nest?.attached==0 && nest?.completed==(index==3)
        }
        f.controls.refreshNestControls();f.view.updateSprites()
        let final=d.engine.nestSnapshot().first
        let overlay=final.flatMap{f.layer("habitat-nest-progress-\($0.id.rawValue)")}
        checks["nestBuildNativeThirdCommitDisplaysCompleteWithoutFourthObservation"]=completed && final?.completed==true &&
            overlay?.isHidden==false && (overlay?.sublayers?.first?.contents as AnyObject?) === NestArt.overlayImage(progress:3) &&
            f.controls.nestStatus.stringValue.contains(f.d.t("巢台完成","Nest platform complete")) &&
            NestMaterialVerification.entry(d,kind:.nestBuild)?.previewCount==buildBefore[1]+3 &&
            NestMaterialVerification.entry(d,kind:.nestMaterialCarry)?.previewCount==carryBefore[1]+3
        let archive=d.observationJournal.archive,sequence=d.engine.events.last?.sequence ?? 0
        f.controls.previewNestBuildButton.performClick(nil);f.controls.previewNestMaterialButton.performClick(nil)
        checks["nestBuildNativeCompletePlatformNeverRefillsOrStartsFourthStep"]=d.engine.activeRunCount==0 &&
            d.engine.events.filter{$0.sequence>sequence && $0.type == .started}.isEmpty &&
            d.engine.nestSnapshot().first?.available==0 && d.engine.nestSnapshot().first?.progress==3 && d.observationJournal.archive==archive
        // A final arrangement may commit without the observation completing.
        // Recreate stock via the real user placement command, never by restoring
        // a pre-arranged snapshot or granting inventory to the current object.
        try f.install();try f.place()
        for index in 1...2 {
            guard NestMaterialVerification.journey(f,kind:.nestMaterialCarry,source:.preview,key:"nestBuildNativeCommitSetup-\(index)-carry-",capture:false,
                into:&checks,evidence:&evidence,folder:folder),
                NestMaterialVerification.journey(f,kind:.nestBuild,source:.preview,key:"nestBuildNativeCommitSetup-\(index)-build-",capture:false,
                into:&checks,evidence:&evidence,folder:folder) else {checks["nestBuildNativeFinalCommitClickSetup"]=false;return}
        }
        guard NestMaterialVerification.journey(f,kind:.nestMaterialCarry,source:.preview,key:"nestBuildNativeCommitSetup-third-carry-",capture:false,
            into:&checks,evidence:&evidence,folder:folder),let bird=f.bird else {checks["nestBuildNativeFinalCommitClickSetup"]=false;return}
        f.settle();let before=d.observationJournal.archive
        guard let run=f.start(.nestBuild),f.seek({nest,_ in nest.progress==3}),
              let nest=d.engine.nestSnapshot().first,let state=d.engine.renderSnapshot().first,
              let p=InsectCatchVerification.visiblePoint(state,in:d) else {checks["nestBuildNativeFinalCommitClick"]=false;return}
        f.controls.refreshNestControls();f.view.updateSprites()
        _=try InsectCatchVerification.snapshot(f.view,around:f.crop,to:folder.appendingPathComponent("third-commit-before-exit-actual-layer.png"))
        let visibleComplete=nest.completed && f.controls.nestStatus.stringValue.contains(d.t("巢台完成","Nest platform complete"))
        let hit=d.bird(at:p) === bird,sequenceBeforeClick=d.engine.events.last?.sequence ?? 0
        if hit,let cg=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:p,mouseButton:.left),let event=NSEvent(cgEvent:cg) {d.handleMouseDown(event)}
        let ends=NestMaterialVerification.terminal(d.engine,run)
        checks["nestBuildNativeFinalCommitClickKeepsCompleteButNoObservation"]=visibleComplete && hit &&
            d.engine.events.contains{$0.sequence>sequenceBeforeClick && $0.kind == .relocate && $0.type == .started} &&
            ends.count==1 && ends.first?.reason == .replaced && ends.first?.type != .completed &&
            d.engine.nestSnapshot().first?.progress==3 && d.observationJournal.archive==before
        for _ in 0..<36*120 {if d.engine.behavior(of:bird)==nil {break};f.step()}
        checks["nestBuildNativeFinalCommitClickRelocatesAndSettles"]=NestMaterialVerification.safeOrdinaryRest(bird,in:d) &&
            NestMaterialVerification.clearRun(d.engine) && NestMaterialVerification.releasedNestMaterials(d.engine)
        d.engine.handle(.clearCurrentScene);f.advance(3)
    }
    private static func automaticFocus(_ f:NestMaterialVerification.Fixture,into checks:inout [String:Bool],evidence:inout [[String:Any]]) throws {
        try f.install();try f.place()
        let d=f.d,before=d.observationJournal.archive,sequence=d.engine.events.last?.sequence ?? 0
        d.engine.ambientEnabled=true
        var carryRun:BehaviorRunID?,buildRun:BehaviorRunID?
        for _ in 0..<150*120 {
            f.step()
            let started=d.engine.events.filter{$0.sequence>sequence && $0.source == .automatic && $0.type == .started}
            carryRun=started.first{$0.kind == .nestMaterialCarry}?.runID
            buildRun=started.first{$0.kind == .nestBuild}?.runID
            if let buildRun,NestMaterialVerification.terminal(d.engine,buildRun).contains(where:{$0.type == .completed}) {break}
        }
        d.engine.ambientEnabled=false
        let carryEnds=carryRun.map{NestMaterialVerification.terminal(d.engine,$0)} ?? [],buildEnds=buildRun.map{NestMaterialVerification.terminal(d.engine,$0)} ?? []
        checks["nestBuildNativeRealSchedulerPrefersDeliveredMaterial"]=carryRun != nil && buildRun != nil &&
            carryEnds.contains{$0.type == .completed} && buildEnds.contains{$0.type == .completed} && carryRun != buildRun &&
            (NestMaterialVerification.entry(d,kind:.nestMaterialCarry)?.automaticCount ?? 0)>0 &&
            (NestMaterialVerification.entry(d,kind:.nestBuild)?.automaticCount ?? 0)>0 && d.observationJournal.archive != before
        evidence.append(["automaticCarryRun":carryRun?.rawValue ?? 0,"automaticBuildRun":buildRun?.rawValue ?? 0,
            "source":"real shared scheduler; no direct automatic command","materials":d.engine.nestSnapshot().first.map(NestMaterialVerification.materialRows) ?? []])
        d.engine.handle(.clearCurrentScene);f.advance(3)
    }
}
