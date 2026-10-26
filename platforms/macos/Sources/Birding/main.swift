import AppKit
import BirdingCore

func argument(_ flag:String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of:flag),i+1<CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i+1]
}
// Ledger race workers never create NSApplication, windows or a controller.
if let status=GiftLedgerPersistenceVerification.worker() {exit(status)}
BehaviorStressCLI.runIfRequested()
if let token=argument("--apply-pro-update") { exit(UpdateInstaller.runHelper(token:token)) }
if let token=argument("--apply-update") { exit(UpdateInstaller.runHelper(token:token)) }
if let path=argument("--verify-pro-update-package") {
    do {try ProUpdateInstallVerification.run(folder:URL(fileURLWithPath:path));exit(0)}
    catch {print("Pro update staging/replacement: FAIL — \(error)");exit(1)}
}
if let path=argument("--verify-update-archive") {
    do { let expanded=try UpdateArchive.validate(Data(contentsOf:URL(fileURLWithPath:path),options:.mappedIfSafe),appName:AppBranding.updateChannel.appName);print("Update archive structure: PASS (\(expanded) expanded bytes)");exit(0) }
    catch { print("Update archive structure: FAIL — \(error)");exit(1) }
}
if let path=argument("--replay-behavior") {
    do {
        let log=try BehaviorInputLog.load(from:URL(fileURLWithPath:path))
        let hz=argument("--replay-hz").flatMap(Int.init)
        if argument("--replay-hz") != nil && hz == nil {throw BehaviorRecordingError.invalid("invalid callback frequency")}
        let report=try log.replay(callbackHz:hz)
        if let output=argument("--replay-output") {try report.save(to:URL(fileURLWithPath:output))}
        guard log.expected.map({$0==report}) ?? true else {throw BehaviorRecordingError.invalid("replay differs from the recorded result")}
        print("Behavior replay: PASS (\(log.inputs.count) inputs, \(report.events.count) events)");exit(0)
    } catch {fputs("Behavior replay: FAIL — \(error)\n",stderr);exit(1)}
}
if let path=argument("--verify-soak-smoke") {
    do {
        let checks=try SoakVerification.inspectCompletedSmoke(at:URL(fileURLWithPath:path))
        let passed=checks.values.allSatisfy{$0}
        if let output=argument("--verify-soak-output") {
            try JSONSerialization.data(withJSONObject:["passed":passed,"checks":checks],options:[.prettyPrinted,.sortedKeys])
                .write(to:URL(fileURLWithPath:output),options:.atomic)
        }
        print("Desktop soak smoke: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
        exit(passed ? 0:1)
    } catch {fputs("Desktop soak inspection: \(error)\n",stderr);exit(1)}
}
if let path=argument("--export-behavior-fixtures") {
    do {try SharedBehaviorExport.export(to:URL(fileURLWithPath:path));exit(0)}
    catch {fputs("Behavior fixture export failed: \(error)\n",stderr);exit(1)}
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let path = argument("--benchmark-motion") {
    exit(MotionBenchmark.run(to:URL(fileURLWithPath:path)))
}
if let path = argument("--verify-expansion-motion") ?? argument("--verify-m8-motion") ?? argument("--verify-pilot-motion") {
    exit(PilotMotionVerification.run(to:URL(fileURLWithPath:path)))
}
if let path = argument("--export-pose-previews") {
    do {try BirdArt.exportPosePreviews(to:URL(fileURLWithPath:path));exit(0)}
    catch {fputs("Pose preview export failed: \(error)\n",stderr);exit(1)}
}
if let path = argument("--export-species-support") {
    do {try BirdArt.exportSupport(to:URL(fileURLWithPath:path));exit(0)}
    catch {fputs("Support export failed: \(error)\n",stderr);exit(1)}
}
if let path = argument("--export-shared") {
    do { try BirdArt.exportShared(to:URL(fileURLWithPath:path)); exit(0) }
    catch { fputs("Shared export failed: \(error)\n",stderr); exit(1) }
}
if let path = argument("--export-icon") {
    do {
        try BirdArt().exportAppIcon(to:URL(fileURLWithPath:path),macOSMask:CommandLine.arguments.contains("--macos-mask"))
        exit(0)
    } catch { fputs("Icon export failed: \(error)\n",stderr); exit(1) }
}
if let path = argument("--export-art") {
    do { try BirdArt().export(to:URL(fileURLWithPath:path)); exit(0) }
    catch { fputs("Art export failed: \(error)\n",stderr); exit(1) }
}
if let path = argument("--export-species") {
    do { try BirdArt.exportSpecies(to:URL(fileURLWithPath:path)); exit(0) }
    catch { fputs("Species export failed: \(error)\n",stderr); exit(1) }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var desktop: DesktopController?
    var fixture: FixtureController?
    var populationCheck: PopulationVerification?
    var soakSession:DesktopSoakSession?
    func applicationDidFinishLaunching(_ notification:Notification) {
        if let path=argument("--soak-desktop") {
            do {
                guard path.hasPrefix("/"),let duration=Double(argument("--soak-duration") ?? "7200"),
                      let birds=Int(argument("--soak-birds") ?? "12") else {
                    throw DesktopSoakSession.SessionError.invalid("invalid path, duration or population")
                }
                let session=try DesktopSoakSession(output:URL(fileURLWithPath:path),duration:duration,birds:birds)
                soakSession=session;desktop=session.desktop
                try session.start()
            } catch {
                fputs("\(error)\n",stderr)
                if soakSession == nil {exit(1)}
                // Idempotent even when start() already began cleanup.
                soakSession?.finish(reason:"startupFailure")
            }
            return
        }
        if let path = argument("--verify-updates") { UpdateVerification.run(to:URL(fileURLWithPath:path)); return }
        if let path = argument("--verify-ground") { GroundVerification.run(to:URL(fileURLWithPath:path)); return }
        if let path = argument("--verify-m6-content") {
            do {
                let folder=URL(fileURLWithPath:path)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var checks:[String:Bool]=[:]
                try M6ContentVerification.run(into:&checks,folder:folder)
                let passed=checks.values.allSatisfy{$0}
                saveJSON(["passed":passed,"checks":checks],to:folder.appendingPathComponent("report.json"))
                print("M6 content: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
                exit(passed ? 0:1)
            } catch {print(error);exit(1)}
        }
        if let path = argument("--verify-bath") {
            do {
                let folder=URL(fileURLWithPath:path)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var checks:[String:Bool]=[:]
                try BathVerification.run(into:&checks,folder:folder)
                try BathSettingsVerification.run(into:&checks,folder:folder)
                let passed=checks.values.allSatisfy{$0}
                saveJSON(["passed":passed,"checks":checks],to:folder.appendingPathComponent("report.json"))
                print("Bath: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
                exit(passed ? 0:1)
            } catch {print(error);exit(1)}
        }
        if let path = argument("--verify-leaf-carry") {
            do {
                let folder=URL(fileURLWithPath:path)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var checks:[String:Bool]=[:]
                try LeafCarryArtVerification.run(into:&checks,folder:folder)
                try LeafCarryVerification.run(into:&checks,folder:folder)
                try LeafCarrySettingsVerification.run(into:&checks,folder:folder)
                let passed=checks.values.allSatisfy{$0}
                saveJSON(["passed":passed,"checks":checks],to:folder.appendingPathComponent("report.json"))
                print("Leaf carry: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
                exit(passed ? 0:1)
            } catch {print(error);exit(1)}
        }
        if let path = argument("--verify-insect-catch") {
            do {
                let folder=URL(fileURLWithPath:path)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var checks:[String:Bool]=[:]
                try autoreleasepool {try InsectCatchArtVerification.run(into:&checks,folder:folder)}
                try autoreleasepool {try InsectCatchVerification.run(into:&checks,folder:folder)}
                try autoreleasepool {try FlycatcherInsectCatchVerification.run(into:&checks,folder:folder)}
                try autoreleasepool {try InsectCatchSettingsVerification.run(into:&checks,folder:folder)}
                let passed=checks.values.allSatisfy{$0}
                saveJSON(["passed":passed,"checks":checks],to:folder.appendingPathComponent("report.json"))
                print("Insect catch: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
                exit(passed ? 0:1)
            } catch {print(error);exit(1)}
        }
        if let path = argument("--verify-visitor-gift") {
            do {
                let folder=URL(fileURLWithPath:path)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var checks:[String:Bool]=[:]
                try autoreleasepool {try VisitorGiftArtVerification.run(into:&checks,folder:folder)}
                try autoreleasepool {try GiftVerification.run(into:&checks,folder:folder)}
                try autoreleasepool {try VisitorGiftSettingsVerification.run(into:&checks,folder:folder)}
                try autoreleasepool {try GiftLedgerPersistenceVerification.run(into:&checks,folder:folder)}
                let passed=checks.values.allSatisfy{$0}
                saveJSON(["passed":passed,"checks":checks],to:folder.appendingPathComponent("report.json"))
                print("Visitor gift: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
                exit(passed ? 0:1)
            } catch {print(error);exit(1)}
        }
        if let path = argument("--verify-nest-art") {
            do {
                let folder=URL(fileURLWithPath:path)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var checks:[String:Bool]=[:]
                try NestArtVerification.run(into:&checks,folder:folder)
                let passed=checks.values.allSatisfy{$0}
                saveJSON(["passed":passed,"checks":checks,
                    "scope":"Source art only; excludes native transport, build and settings acceptance."],
                    to:folder.appendingPathComponent("report.json"))
                print("Nest art: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
                exit(passed ? 0:1)
            } catch {print(error);exit(1)}
        }
        if let path = argument("--verify-nest") {
            do {
                let folder=URL(fileURLWithPath:path)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var checks:[String:Bool]=[:]
                var errors:[String:String]=[:]
                let groups:[(String,(inout [String:Bool],URL)throws->Void)]=[
                    ("art",{try NestArtVerification.run(into:&$0,folder:$1)}),
                    ("materialNative",{try NestMaterialVerification.run(into:&$0,folder:$1)}),
                    ("materialSettings",{try NestMaterialSettingsVerification.run(into:&$0,folder:$1)}),
                    ("buildNative",{try NestBuildVerification.run(into:&$0,folder:$1)}),
                    ("buildSettings",{try NestBuildSettingsVerification.run(into:&$0,folder:$1)})]
                // Each group owns and tears down its fixture. A blocked native
                // route must fail the overall run without hiding other groups.
                for (name,run) in groups {
                    do {try autoreleasepool {try run(&checks,folder)}}
                    catch {errors[name]=error.localizedDescription}
                }
                let passed=errors.isEmpty && checks.values.allSatisfy{$0}
                saveJSON(["passed":passed,"checks":checks,"errors":errors],to:folder.appendingPathComponent("report.json"))
                print("Nest: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
                for name in errors.keys.sorted() {print("\(name): \(errors[name]!)")}
                exit(passed ? 0:1)
            } catch {print(error);exit(1)}
        }
        if let path = argument("--verify-courtship") {
            do {
                let folder=URL(fileURLWithPath:path)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var checks:[String:Bool]=[:]
                try autoreleasepool {try CourtshipArtVerification.run(into:&checks,folder:folder)}
                try autoreleasepool {try CourtshipVerification.run(into:&checks,folder:folder)}
                try autoreleasepool {try CourtshipSettingsVerification.run(into:&checks,folder:folder)}
                let passed=checks.values.allSatisfy{$0}
                saveJSON(["passed":passed,"checks":checks],to:folder.appendingPathComponent("report.json"))
                print("Courtship: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
                exit(passed ? 0:1)
            } catch {print(error);exit(1)}
        }
        if let path = argument("--verify-birds") { ExpandedVerification.run(to:URL(fileURLWithPath:path)); return }
        if let path = argument("--verify-observations") { ObservationVerification.run(to:URL(fileURLWithPath:path)); return }
        if let path = argument("--verify-fixed-perch-settings") {
            let folder=URL(fileURLWithPath:path)
            var checks:[String:Bool]=[:]
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try FixedPerchSettingsVerification.run(into:&checks,folder:folder)
                let passed = !checks.isEmpty && checks.values.allSatisfy{$0}
                saveJSON(["passed":passed,"checks":checks],to:folder.appendingPathComponent("report.json"))
                print("Fixed perch settings: \(passed ? "PASS":"FAIL") — \(checks.count) checks")
                exit(passed ? 0:1)
            } catch {
                saveJSON(["passed":false,"error":error.localizedDescription,"checks":checks],
                         to:folder.appendingPathComponent("report.json"))
                print(error);exit(1)
            }
        }
        if let path = argument("--verify-settings") { SettingsVerification.run(to:URL(fileURLWithPath:path)); return }
        if let path = argument("--fixture") {
            fixture = FixtureController(folder:URL(fileURLWithPath:path)); fixture?.start()
        } else {
            let d = DesktopController(); desktop = d
            d.diagnosticPath = argument("--diagnostics");d.recordingPath=argument("--record-behavior");d.start()
            if d.recordingPath != nil,let raw=argument("--record-duration"),let seconds=Double(raw),seconds.isFinite,(1...300).contains(seconds) {
                Timer.scheduledTimer(withTimeInterval:seconds,repeats:false) {_ in NSApp.terminate(nil)}
            }
            if AppBranding.updatesEnabled {UpdateInstaller.confirmHealthy(desktop:d)}
            if AppBranding.updatesEnabled && Bundle.main.bundleURL.pathExtension == "app" && !CommandLine.arguments.contains(where:{$0.hasPrefix("--verify") || $0 == "--integration"}) {
                d.updater=UpdateController(desktop:d);d.updater?.start();d.makeMenu()
            }
            if let path = argument("--verify-population") {
                populationCheck = PopulationVerification(desktop:d,path:path); populationCheck?.start()
            }
            if let path = argument("--integration") {
                let check = IntegrationCheck(desktop:d,folder:URL(fileURLWithPath:path))
                d.integration = check; check.start()
            }
        }
    }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        soakSession?.prepareForTermination() ?? .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        if let soakSession {return soakSession.handleReopen()}
        // Overlay windows are always visible, so the usual hasVisibleWindows
        // check would make a menu-bar-only app impossible to reopen reliably.
        desktop?.restoreStatusItem()
        desktop?.showSpeciesSettings()
        return true
    }
    func applicationWillTerminate(_ notification:Notification) {
        if let soakSession {soakSession.finish(reason:"applicationTermination");return}
        desktop?.cancelGiftAuthorization()
        desktop?.engine.handle(.cancelAmbient(.shutdown));desktop?.stopMouseMonitoring()
        desktop?.flushVisitorMemory()
        desktop?.flushObservationJournal()
        if let desktop,let path=desktop.recordingPath {
            do {try desktop.engine.saveRecording(to:URL(fileURLWithPath:path));print("Behavior recording saved: \(path)")}
            catch {fputs("Behavior recording failed: \(error)\n",stderr)}
        }
    }
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
