import AppKit
import BirdingCore

func argument(_ flag:String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of:flag),i+1<CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i+1]
}
BehaviorStressCLI.runIfRequested()
if let token=argument("--apply-update") { exit(UpdateInstaller.runHelper(token:token)) }
if let path=argument("--verify-update-archive") {
    do { let expanded=try UpdateArchive.validate(Data(contentsOf:URL(fileURLWithPath:path),options:.mappedIfSafe));print("Update archive structure: PASS (\(expanded) expanded bytes)");exit(0) }
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
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
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
    func applicationDidFinishLaunching(_ notification:Notification) {
        if let path = argument("--verify-updates") { UpdateVerification.run(to:URL(fileURLWithPath:path)); return }
        if let path = argument("--verify-ground") { GroundVerification.run(to:URL(fileURLWithPath:path)); return }
        if let path = argument("--verify-birds") { ExpandedVerification.run(to:URL(fileURLWithPath:path)); return }
        if let path = argument("--verify-settings") { SettingsVerification.run(to:URL(fileURLWithPath:path)); return }
        if let path = argument("--fixture") {
            fixture = FixtureController(folder:URL(fileURLWithPath:path)); fixture?.start()
        } else {
            let d = DesktopController(); desktop = d
            d.diagnosticPath = argument("--diagnostics");d.recordingPath=argument("--record-behavior");d.start()
            if d.recordingPath != nil,let raw=argument("--record-duration"),let seconds=Double(raw),seconds.isFinite,(1...300).contains(seconds) {
                Timer.scheduledTimer(withTimeInterval:seconds,repeats:false) {_ in NSApp.terminate(nil)}
            }
            if !d.isDevelopmentBuild {UpdateInstaller.confirmHealthy(desktop:d)}
            if !d.isDevelopmentBuild && Bundle.main.bundleURL.pathExtension == "app" && !CommandLine.arguments.contains(where:{$0.hasPrefix("--verify") || $0 == "--integration"}) {
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        // Overlay windows are always visible, so the usual hasVisibleWindows
        // check would make a menu-bar-only app impossible to reopen reliably.
        desktop?.restoreStatusItem()
        desktop?.showSpeciesSettings()
        return true
    }
    func applicationWillTerminate(_ notification:Notification) {
        desktop?.engine.handle(.cancelAmbient(.shutdown));desktop?.stopMouseMonitoring()
        if let desktop,let path=desktop.recordingPath {
            do {try desktop.engine.saveRecording(to:URL(fileURLWithPath:path));print("Behavior recording saved: \(path)")}
            catch {fputs("Behavior recording failed: \(error)\n",stderr)}
        }
    }
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
