import Foundation
import BirdingCore

/// Exercises the production authentication/staging/replacement functions against
/// disposable app copies. Never launches, quits or replaces the user's app.
enum ProUpdateInstallVerification {
    static func run(folder requestedFolder: URL) throws {
        let folder=requestedFolder.resolvingSymlinksInPath()
        guard AppBranding.isPro, AppBranding.updatesEnabled else {
            throw UpdateFailure.invalid("Run verification with the update-enabled Pro app")
        }
        let fm=FileManager.default
        let release=try UpdateInstaller.read(UpdateRelease.self,at:folder.appendingPathComponent("release.json"))
        let workspace=folder.appendingPathComponent("transaction-"+UUID().uuidString)
        try fm.createDirectory(at:workspace,withIntermediateDirectories:false)
        defer {try? fm.removeItem(at:workspace)}
        let target=workspace.appendingPathComponent("ChirpOS Pro.app")
        try fm.copyItem(at:Bundle.main.bundleURL,to:target)
        let plist=target.appendingPathComponent("Contents/Info.plist")
        try UpdateInstaller.command("/usr/libexec/PlistBuddy",["-c","Set :CFBundleShortVersionString 0.0.0",plist.path])
        try UpdateInstaller.command("/usr/bin/codesign",["--force","--sign","-",target.path])
        let stage=workspace.appendingPathComponent("staging")
        try fm.createDirectory(at:stage,withIntermediateDirectories:false)
        let archive=stage.appendingPathComponent("package.zip")
        try fm.copyItem(at:folder.appendingPathComponent("package.zip"),to:archive)
        var checks:[String:Bool]=[:]
        let token=UUID().uuidString
        try UpdateInstaller.stage(release:release,token:token,target:target,stagingRoot:stage)
        checks["authenticatedArchiveStaged"]=true
        let extracted=stage.appendingPathComponent("extracted/ChirpOS Pro.app")
        let transaction=try UpdateInstaller.makeReplacement(target:target,token:token)
        func version(_ app:URL) throws -> String {
            let data=try Data(contentsOf:app.appendingPathComponent("Contents/Info.plist"))
            return (try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any])?["CFBundleShortVersionString"] as? String ?? ""
        }
        try transaction.prepare(from:extracted)
        checks["preparePreservesInstalledApp"] = try version(target)=="0.0.0"
        try transaction.replace()
        checks["atomicReplacementInstallsCandidate"] = try version(target)==release.version && version(transaction.backup)=="0.0.0"
        try transaction.rollback()
        checks["failedHealthRollbackRestoresOldApp"] = try version(target)=="0.0.0" && !fm.fileExists(atPath:transaction.backup.path)
        try transaction.prepare(from:extracted)
        try transaction.replace()
        try transaction.complete()
        checks["confirmedReplacementRemovesBackup"] = try version(target)==release.version && !fm.fileExists(atPath:transaction.backup.path)

        // Same-size corruption must fail before extraction or any replacement.
        var bytes=try Data(contentsOf:archive);bytes[bytes.count/2] ^= 1;try bytes.write(to:archive)
        do {try release.verify(archive);checks["corruptArchiveRejected"]=false}
        catch {checks["corruptArchiveRejected"]=true}
        checks["rejectedArchivePreservesInstalledApp"] = try version(target)==release.version
        let wrongKey=Data(repeating:7,count:32).base64EncodedString()
        do {try release.verifySignature(publicKey:wrongKey);checks["wrongPublisherKeyRejected"]=false}
        catch {checks["wrongPublisherKeyRejected"]=true}
        let changed=workspace.appendingPathComponent("wrong-key.app")
        try fm.copyItem(at:extracted,to:changed)
        try UpdateInstaller.command("/usr/libexec/PlistBuddy",["-c","Set :ChirpOSUpdatePublicKey \(wrongKey)",changed.appendingPathComponent("Contents/Info.plist").path])
        try UpdateInstaller.command("/usr/bin/codesign",["--force","--sign","-",changed.path])
        do {try UpdateInstaller.validateApp(changed,release:release,target:target);checks["candidateKeyRotationRejected"]=false}
        catch {checks["candidateKeyRotationRejected"]=true}
        let passed=checks.values.allSatisfy{$0}
        saveJSON(["passed":passed,"checks":checks,"scope":"Signed archive, actual app staging and atomic swap/rollback on disposable copies; no live quit/relaunch or Gatekeeper interaction."],to:folder.appendingPathComponent("report.json"))
        guard passed else {throw UpdateFailure.invalid("Pro update install verification failed")}
        print("Pro update staging/replacement: PASS — \(checks.count) checks")
    }
}
