import XCTest
import CryptoKit
@testable import BirdingCore

final class UpdateTests: XCTestCase {
    func fixture(version:String="v1.10.0",platform:String="macOS-arm64",digest:String?="sha256:"+String(repeating:"a",count:64),url:String?=nil,draft:Bool=false,prerelease:Bool=false) throws -> Data {
        let number=version.hasPrefix("v") ? String(version.dropFirst()):version
        let name="ChirpOS-\(number)-\(platform).zip"
        var asset:[String:Any]=["name":name,"browser_download_url":url ?? "https://github.com/billtt/chirp-os/releases/download/\(version)/\(name)","size":100,"state":"uploaded"]
        if let digest { asset["digest"]=digest }
        return try JSONSerialization.data(withJSONObject:["tag_name":version,"draft":draft,"prerelease":prerelease,"body":"## Changes\n- A fix","assets":[asset]])
    }
    func testNumericVersionsRejectNonStableInput() {
        XCTAssertGreaterThan(UpdateVersion("1.10.0")!,UpdateVersion("1.9.99")!)
        XCTAssertEqual(UpdateVersion("v1.2.3"),UpdateVersion("1.2.3"))
        for value in ["1.2","1.2.3-beta","1.2.3+debug","-1.2.3","1.2.３","1.2.3/evil","1.2.99999999999999999"] { XCTAssertNil(UpdateVersion(value),value) }
    }
    func testReleaseSelectionNeverDowngradesOrCrossesArchitecture() throws {
        let release=try UpdateRelease.select(fixture(),current:"1.9.0",platform:"macOS-arm64")
        XCTAssertEqual(release?.version,"1.10.0");XCTAssertTrue(release!.notes.contains("A fix"))
        XCTAssertNil(try UpdateRelease.select(fixture(),current:"1.10.0",platform:"macOS-arm64"))
        XCTAssertNil(try UpdateRelease.select(fixture(),current:"2.0.0",platform:"macOS-arm64"))
        XCTAssertNil(try UpdateRelease.select(fixture(),current:"1.0.0",platform:"macOS-x86_64"))
        XCTAssertNil(try UpdateRelease.select(fixture(draft:true),current:"1.0.0",platform:"macOS-arm64"))
        XCTAssertNil(try UpdateRelease.select(fixture(prerelease:true),current:"1.0.0",platform:"macOS-arm64"))
    }
    func testMissingDigestAndUntrustedDownloadsFailClosed() throws {
        for digest in [nil,"sha256:abc","md5:"+String(repeating:"a",count:64),"sha256:"+String(repeating:"g",count:64)] {
            XCTAssertThrowsError(try UpdateRelease.select(fixture(digest:digest),current:"1.0.0",platform:"macOS-arm64"))
        }
        for url in ["http://github.com/billtt/chirp-os/evil.zip","https://example.com/ChirpOS.zip","https://github.com/other/repo/releases/download/v1.10.0/ChirpOS-1.10.0-macOS-arm64.zip"] {
            XCTAssertThrowsError(try UpdateRelease.select(fixture(url:url),current:"1.0.0",platform:"macOS-arm64"))
        }
    }
    func proFixture(version: String = "pro-v1.10.0", platform: String = "macOS-arm64") -> [String: Any] {
        let number = version.hasPrefix("pro-v") ? String(version.dropFirst(5)) : version
        let name = "ChirpOS-Pro-\(number)-\(platform).zip"
        let url = "https://github.com/sucan2233/chirp-os/releases/download/\(version)/\(name)"
        return ["tag_name": version, "draft": false, "prerelease": false, "body": "Pro changes", "assets": [
            ["name": name, "browser_download_url": url, "size": 100, "state": "uploaded", "digest": "sha256:" + String(repeating: "a", count: 64)],
            ["name": name + ".sig", "browser_download_url": url + ".sig", "size": 89, "state": "uploaded"]
        ]]
    }
    func metadata(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    func proRelease(platform: String = "macOS-arm64") throws -> UpdateRelease {
        try XCTUnwrap(UpdateRelease.select(metadata(proFixture(platform: platform)), current: "1.0.0", platform: platform, channel: .pro))
    }
    func testChannelsKeepLegacyDefaultsAndSeparateProIdentity() throws {
        XCTAssertEqual(UpdateChannel.legacy.repository, "billtt/chirp-os")
        XCTAssertEqual(UpdateChannel.legacy.appName, "ChirpOS.app")
        XCTAssertEqual(UpdateChannel.legacy.bundleIdentifier, "dev.birding.desktop")
        XCTAssertEqual(UpdateChannel.legacy.assetPrefix, "ChirpOS")
        XCTAssertEqual(UpdateRelease.endpoint, UpdateChannel.legacy.endpoint)
        XCTAssertEqual(UpdateRelease.endpoint.absoluteString, "https://api.github.com/repos/billtt/chirp-os/releases/latest")
        XCTAssertEqual(UpdateChannel.pro.repository, "sucan2233/chirp-os")
        XCTAssertEqual(UpdateChannel.pro.appName, "ChirpOS Pro.app")
        XCTAssertEqual(UpdateChannel.pro.bundleIdentifier, "dev.birding.desktop.development")
        XCTAssertEqual(UpdateChannel.pro.assetPrefix, "ChirpOS-Pro")
        XCTAssertEqual(UpdateChannel.pro.endpoint.absoluteString, "https://api.github.com/repos/sucan2233/chirp-os/releases?per_page=100")
        XCTAssertEqual(try JSONDecoder().decode(UpdateChannel.self, from: JSONEncoder().encode(UpdateChannel.pro)), .pro)
        XCTAssertNil(try UpdateRelease.select(metadata(proFixture()), current: "1.0.0", platform: "macOS-arm64"))
        XCTAssertNil(try UpdateRelease.select(fixture(), current: "1.0.0", platform: "macOS-arm64", channel: .pro))
    }
    func testProListSelectsHighestCompatibleStableVersionRegardlessOfOrder() throws {
        var draft = proFixture(version: "pro-v90.0.0"); draft["draft"] = true
        var prerelease = proFixture(version: "pro-v80.0.0"); prerelease["prerelease"] = true
        let releases = [proFixture(version: "pro-v1.9.0"), proFixture(version: "v99.0.0"),
                        proFixture(version: "pro-v1.10.0"), proFixture(version: "upstream-v99.0.0"),
                        proFixture(version: "pro-v1.11.0", platform: "macOS-x86_64"), draft, prerelease,
                        proFixture(version: "pro-latest"), proFixture(version: "pro-v2.0.0-beta"),
                        proFixture(version: "pro-v01.99.0"), proFixture(version: "pro-vv99.0.0")]
        let data = try metadata(releases)
        XCTAssertEqual(try UpdateRelease.select(data, current: "1.0.0", platform: "macOS-arm64", channel: .pro)?.version, "1.10.0")
        XCTAssertEqual(try UpdateRelease.select(data, current: "1.0.0", platform: "macOS-x86_64", channel: .pro)?.version, "1.11.0")
        XCTAssertNil(try UpdateRelease.select(data, current: "1.10.0", platform: "macOS-arm64", channel: .pro))
        XCTAssertNil(try UpdateRelease.select(data, current: "2.0.0", platform: "macOS-x86_64", channel: .pro))
        XCTAssertNil(try UpdateRelease.select(metadata(proFixture(platform: "linux-arm64")), current: "1.0.0", platform: "linux-arm64", channel: .pro))
        XCTAssertNil(try UpdateRelease.select(metadata([]), current: "1.0.0", platform: "macOS-arm64", channel: .pro))
        XCTAssertThrowsError(try UpdateRelease.select(data, current: "broken", platform: "macOS-arm64", channel: .pro))
        var oversized = try metadata(proFixture())
        oversized.append(Data(repeating: 32, count: 2_000_001 - oversized.count))
        XCTAssertThrowsError(try UpdateRelease.select(oversized, current: "1.0.0", platform: "macOS-arm64", channel: .pro))
    }
    func testProRequiresExactUploadedSidecarAndTrustedPackageDigest() throws {
        let original = proFixture()
        let assets = try XCTUnwrap(original["assets"] as? [[String: Any]])
        for replacement in [Array(assets.prefix(1)), assets + [assets[1]], assets + [assets[0]]] {
            var release = original; release["assets"] = replacement
            XCTAssertNil(try UpdateRelease.select(metadata(release), current: "1.0.0", platform: "macOS-arm64", channel: .pro))
        }
        for size in [1, 1024] {
            var release = original, changed = assets; changed[1]["size"] = size; release["assets"] = changed
            XCTAssertNotNil(try UpdateRelease.select(metadata(release), current: "1.0.0", platform: "macOS-arm64", channel: .pro))
        }
        let invalidFields: [(Int, String, Any?)] = [
            (0, "digest", nil), (0, "digest", "sha256:abc"),
            (0, "digest", "md5:" + String(repeating: "a", count: 64)),
            (0, "browser_download_url", "https://github.com/billtt/chirp-os/releases/download/pro-v1.10.0/" + (assets[0]["name"] as! String)),
            (0, "size", 0), (0, "size", UpdateRelease.maxDownload + 1),
            (1, "size", 0), (1, "size", 1025), (1, "state", "new"),
            (1, "browser_download_url", "https://example.com/update.sig"),
            (1, "browser_download_url", (assets[1]["browser_download_url"] as! String) + "?redirect=1")
        ]
        for (index, field, value) in invalidFields {
            var release = original, changed = assets; changed[index][field] = value; release["assets"] = changed
            XCTAssertThrowsError(try UpdateRelease.select(metadata(release), current: "1.0.0", platform: "macOS-arm64", channel: .pro), "\(index).\(field)")
        }
        var wrongName = original, changed = assets
        changed[1]["name"] = "update.sig"; wrongName["assets"] = changed
        XCTAssertNil(try UpdateRelease.select(metadata(wrongName), current: "1.0.0", platform: "macOS-arm64", channel: .pro))
    }
    func testProListSkipsInvalidNewerAssetsButRejectsInvalidOnlyCandidate() throws {
        var invalid = proFixture(version: "pro-v1.11.0")
        var assets = try XCTUnwrap(invalid["assets"] as? [[String: Any]])
        assets[0].removeValue(forKey: "digest"); invalid["assets"] = assets
        let data = try metadata([proFixture(), invalid])
        XCTAssertEqual(try UpdateRelease.select(data, current: "1.0.0", platform: "macOS-arm64", channel: .pro)?.version, "1.10.0")
        XCTAssertThrowsError(try UpdateRelease.select(metadata([invalid]), current: "1.0.0", platform: "macOS-arm64", channel: .pro))
    }
    func testSignaturePayloadSigningAndCodableCompatibility() throws {
        let key = Curve25519.Signing.PrivateKey(), publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        for platform in ["macOS-arm64", "macOS-x86_64"] {
            let release = try proRelease(platform: platform)
            XCTAssertEqual(String(data: release.signaturePayload, encoding: .utf8),
                           "ChirpOS Pro Update v1\n1.10.0\nChirpOS-Pro-1.10.0-\(platform).zip\n100\n" + String(repeating: "a", count: 64) + "\n")
            XCTAssertEqual(release.signatureURL, release.downloadURL + ".sig")
            XCTAssertNil(release.signature)
            let signature = try key.signature(for: release.signaturePayload).base64EncodedString()
            let signed = release.signed(signature)
            XCTAssertEqual(signed.version, release.version); XCTAssertEqual(signed.notes, release.notes)
            XCTAssertEqual(signed.assetName, release.assetName); XCTAssertEqual(signed.downloadURL, release.downloadURL)
            XCTAssertEqual(signed.sha256, release.sha256); XCTAssertEqual(signed.size, release.size)
            XCTAssertEqual(signed.signature, signature)
            XCTAssertNoThrow(try signed.verifySignature(publicKey: publicKey))
            XCTAssertNoThrow(try release.signed(signature + "\n").verifySignature(publicKey: publicKey))
            let restored = try JSONDecoder().decode(UpdateRelease.self, from: JSONEncoder().encode(signed))
            XCTAssertEqual(restored, signed)
            XCTAssertNoThrow(try restored.verifySignature(publicKey: publicKey))
        }
        let oldJournal = try metadata(["version": "1.0.0", "notes": "legacy", "assetName": "test", "downloadURL": "", "sha256": String(repeating: "a", count: 64), "size": 5])
        XCTAssertNil(try JSONDecoder().decode(UpdateRelease.self, from: oldJournal).signature)
    }
    func testSignatureRejectsForgeryWrongKeysAndMalformedInputs() throws {
        let release = try proRelease(), key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let signed = release.signed(try key.signature(for: release.signaturePayload).base64EncodedString())
        XCTAssertThrowsError(try release.verifySignature(publicKey: publicKey))
        XCTAssertThrowsError(try signed.verifySignature(publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
        for signature in ["", "not base64", Data(repeating: 0, count: 64).base64EncodedString(), Data(repeating: 0, count: 63).base64EncodedString(), Data(repeating: 0, count: 65).base64EncodedString(), String(repeating: " ", count: 1025)] {
            XCTAssertThrowsError(try release.signed(signature).verifySignature(publicKey: publicKey))
        }
        for invalidKey in ["", "not base64", Data(repeating: 0, count: 31).base64EncodedString(), Data(repeating: 0, count: 33).base64EncodedString()] {
            XCTAssertThrowsError(try signed.verifySignature(publicKey: invalidKey))
        }
    }
    func testSignatureBindsMetadataAndRejectsInvalidDiskLoadedMetadataEvenWhenSigned() throws {
        let release = try proRelease(), key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let signature = try key.signature(for: release.signaturePayload).base64EncodedString()
        let encoded = try JSONEncoder().encode(release)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let changes: [(String, Any)] = [("version", "1.10.1"), ("size", 101), ("sha256", String(repeating: "b", count: 64)),
                                      ("assetName", "ChirpOS-Pro-1.10.0-macOS-x86_64.zip")]
        for (field, value) in changes {
            var changed = original; changed[field] = value
            let tampered = try JSONDecoder().decode(UpdateRelease.self, from: metadata(changed)).signed(signature)
            XCTAssertThrowsError(try tampered.verifySignature(publicKey: publicKey), field)
        }
        // These fields could be self-consistently signed, but must still obey the Pro channel contract.
        let invalid: [(String, Any)] = [("version", "v1.10.0"), ("version", "01.10.0"), ("version", "1.10.0-beta"),
                                      ("size", 0), ("size", UpdateRelease.maxDownload + 1),
                                      ("sha256", String(repeating: "A", count: 64)), ("sha256", "invalid"),
                                      ("assetName", "ChirpOS-1.10.0-macOS-arm64.zip"),
                                      ("assetName", "ChirpOS-Pro-1.10.0-linux-arm64.zip"),
                                      ("downloadURL", release.downloadURL + "?download=1"),
                                      ("downloadURL", release.downloadURL.replacingOccurrences(of: "sucan2233", with: "billtt"))]
        for (field, value) in invalid {
            var changed = original; changed[field] = value
            let tampered = try JSONDecoder().decode(UpdateRelease.self, from: metadata(changed))
            let resigned = tampered.signed(try key.signature(for: tampered.signaturePayload).base64EncodedString())
            XCTAssertThrowsError(try resigned.verifySignature(publicKey: publicKey), "\(field)=\(value)")
        }
        let otherPlatform = try proRelease(platform: "macOS-x86_64")
        XCTAssertThrowsError(try otherPlatform.signed(signature).verifySignature(publicKey: publicKey))
        var changedNotes = original; changedNotes["notes"] = "Unsigned release notes"
        let renamedNotes = try JSONDecoder().decode(UpdateRelease.self, from: metadata(changedNotes)).signed(signature)
        XCTAssertNoThrow(try renamedNotes.verifySignature(publicKey: publicKey))
    }
    func folder() throws -> URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("chirpos-updater-tests-"+UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) };return root
    }
    func testHashDetectsSameSizeCorruptionAndTruncation() throws {
        let file=try folder().appendingPathComponent("archive.zip"),data=Data("hello".utf8)
        try data.write(to:file)
        let digest=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        let release=UpdateRelease(version:"1.0.0",notes:"",assetName:"test",downloadURL:"",sha256:digest,size:5)
        XCTAssertNoThrow(try release.verify(file))
        try Data("jello".utf8).write(to:file);XCTAssertThrowsError(try release.verify(file))
        try Data("hi".utf8).write(to:file);XCTAssertThrowsError(try release.verify(file))
    }
    func testHourlySchedulingBackoffAndNotificationAcrossRestarts() throws {
        var state=UpdateJournal();let now=Date(timeIntervalSince1970:1000)
        state.finishCheck(now:now,success:true);XCTAssertEqual(state.nextCheck.timeIntervalSince(now),3600)
        for delay in [300.0,900,3600,3600] { state.finishCheck(now:now,success:false);XCTAssertEqual(state.nextCheck.timeIntervalSince(now),delay) }
        XCTAssertTrue(state.announce("1.0.0"))
        var restored=try JSONDecoder().decode(UpdateJournal.self,from:JSONEncoder().encode(state))
        XCTAssertFalse(restored.announce("1.0.0"));XCTAssertTrue(restored.announce("1.0.1"))
        restored.finishCheck(now:now,success:true);XCTAssertEqual(restored.failures,0)
    }
    func makeApp(_ root:URL,_ name:String,_ contents:String) throws -> URL {
        let app=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:app,withIntermediateDirectories:true)
        try Data(contents.utf8).write(to:app.appendingPathComponent("version"));return app
    }
    func testReplacementRetainsOldVersionUntilHealthAcknowledgement() throws {
        let root=try folder(),app=try makeApp(root,"ChirpOS.app","old"),source=try makeApp(root,"download.app","new")
        let transaction=try UpdateReplacement(target:app,token:UUID().uuidString)
        try transaction.prepare(from:source)
        XCTAssertEqual(try String(contentsOf:app.appendingPathComponent("version")),"old")
        try transaction.replace()
        XCTAssertEqual(try String(contentsOf:app.appendingPathComponent("version")),"new")
        XCTAssertEqual(try String(contentsOf:transaction.backup.appendingPathComponent("version")),"old")
        try transaction.complete()
        XCTAssertFalse(FileManager.default.fileExists(atPath:transaction.backup.path))
        XCTAssertEqual(try String(contentsOf:app.appendingPathComponent("version")),"new")
    }
    func testFailedStartupRestoresOldAppAndFailedPrepareDoesNotTouchIt() throws {
        let root=try folder(),app=try makeApp(root,"ChirpOS.app","old"),source=try makeApp(root,"download.app","new")
        let transaction=try UpdateReplacement(target:app,token:UUID().uuidString)
        XCTAssertThrowsError(try transaction.prepare(from:root.appendingPathComponent("missing")))
        XCTAssertEqual(try String(contentsOf:app.appendingPathComponent("version")),"old")
        try transaction.prepare(from:source);try transaction.replace();try transaction.rollback()
        XCTAssertEqual(try String(contentsOf:app.appendingPathComponent("version")),"old")
        XCTAssertFalse(FileManager.default.fileExists(atPath:transaction.backup.path))
        XCTAssertThrowsError(try UpdateReplacement(target:app,token:"../arbitrary"))
        let link=root.appendingPathComponent("link/ChirpOS.app");try FileManager.default.createDirectory(at:link.deletingLastPathComponent(),withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:app)
        XCTAssertThrowsError(try UpdateReplacement(target:link,token:UUID().uuidString))
    }
    func testProReplacementUsesBrandPathsAndRollsBackFailedStartup() throws {
        let root = try folder(), app = try makeApp(root, "ChirpOS Pro.app", "old"), source = try makeApp(root, "download.app", "new")
        let token = UUID().uuidString
        let transaction = try UpdateReplacement(target: app, token: token, appName: "ChirpOS Pro.app")
        XCTAssertEqual(transaction.candidate.lastPathComponent, ".ChirpOS Pro-\(token).new.app")
        XCTAssertEqual(transaction.backup.lastPathComponent, ".ChirpOS Pro-\(token).old.app")
        XCTAssertEqual(transaction.candidate.deletingLastPathComponent(), app.deletingLastPathComponent())
        XCTAssertThrowsError(try transaction.prepare(from: root.appendingPathComponent("missing")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.candidate.path))
        try transaction.prepare(from: source)
        XCTAssertThrowsError(try transaction.prepare(from: source))
        try transaction.replace()
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("version")), "new")
        XCTAssertEqual(try String(contentsOf: transaction.backup.appendingPathComponent("version")), "old")
        try transaction.rollback()
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("version")), "old")
        try transaction.rollback(); try transaction.complete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.candidate.path))
    }
    func testProReplacementCanRestoreMissingTargetAndCompleteHealthyUpdate() throws {
        let root = try folder(), app = try makeApp(root, "ChirpOS Pro.app", "old"), source = try makeApp(root, "download.app", "new")
        let transaction = try UpdateReplacement(target: app, token: UUID().uuidString, appName: "ChirpOS Pro.app")
        try transaction.prepare(from: source); try transaction.replace()
        try FileManager.default.removeItem(at: app)
        try transaction.rollback()
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("version")), "old")
        try transaction.prepare(from: source); try transaction.replace(); try transaction.complete()
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("version")), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.backup.path))
    }
    func testReplacementRejectsUnknownNamesCrossChannelTargetsAndSymlinks() throws {
        let root = try folder(), pro = try makeApp(root, "ChirpOS Pro.app", "old"), legacy = try makeApp(root, "ChirpOS.app", "old")
        let token = UUID().uuidString
        XCTAssertThrowsError(try UpdateReplacement(target: pro, token: token))
        XCTAssertThrowsError(try UpdateReplacement(target: legacy, token: token, appName: "ChirpOS Pro.app"))
        XCTAssertThrowsError(try UpdateReplacement(target: root.appendingPathComponent("Other.app"), token: token, appName: "Other.app"))
        XCTAssertThrowsError(try UpdateReplacement(target: pro, token: "../bad", appName: "ChirpOS Pro.app"))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try UpdateReplacement(target: link.appendingPathComponent("ChirpOS Pro.app"), token: token, appName: "ChirpOS Pro.app"))
    }
    /// Minimal uncompressed ZIP fixture with independently configurable local names.
    func zip(_ name:String, localName:String?=nil, mode:UInt32=0o100644, size:UInt32=1, extra:Data=Data()) -> Data {
        var d=Data()
        func n(_ value:UInt32,_ count:Int) { for i in 0..<count { d.append(UInt8(truncatingIfNeeded:value >> (8*i))) } }
        let local=Data((localName ?? name).utf8),central=Data(name.utf8)
        n(0x04034b50,4);n(20,2);n(0,2);n(0,2);n(0,2);n(0,2);n(0,4);n(1,4);n(size,4);n(UInt32(local.count),2);n(UInt32(extra.count),2);d.append(local);d.append(extra);d.append(1)
        let start=UInt32(d.count)
        n(0x02014b50,4);n(0x0314,2);n(20,2);n(0,2);n(0,2);n(0,2);n(0,2);n(0,4);n(1,4);n(size,4);n(UInt32(central.count),2);n(UInt32(extra.count),2);n(0,2);n(0,2);n(0,2);n(mode << 16,4);n(0,4);d.append(central);d.append(extra)
        let length=UInt32(d.count)-start
        n(0x06054b50,4);n(0,2);n(0,2);n(1,2);n(1,2);n(length,4);n(start,4);n(0,2)
        return d
    }
    func testArchiveRejectsTraversalSymlinksBombsAndConflictingHeaders() throws {
        XCTAssertNoThrow(try UpdateArchive.validate(zip("ChirpOS.app/Contents/MacOS/Birding")))
        for name in ["../evil","/ChirpOS.app/file","ChirpOS.app/../evil","ChirpOS.app/a/../../evil","ChirpOS.app/a\\evil","other.app/file"] {
            XCTAssertThrowsError(try UpdateArchive.validate(zip(name)),name)
        }
        XCTAssertThrowsError(try UpdateArchive.validate(zip("ChirpOS.app/link",mode:0o120777)))
        XCTAssertThrowsError(try UpdateArchive.validate(zip("ChirpOS.app/file",localName:"ChirpOS.app/evil")))
        XCTAssertThrowsError(try UpdateArchive.validate(zip("ChirpOS.app/bomb",size:UInt32(1024*1024*1024+1))))
        XCTAssertThrowsError(try UpdateArchive.validate(Data([0,1,2])))
        for extra in [Data([0x75,0x70,0,0]),Data([1,0,0,0]),Data([0x55,0x54,20,0])] {
            XCTAssertThrowsError(try UpdateArchive.validate(zip("ChirpOS.app/file",extra:extra)))
        }
        XCTAssertNoThrow(try UpdateArchive.validate(zip("ChirpOS.app/file",extra:Data([0x55,0x54,1,0,0]))))
    }
    func testProArchiveRequiresKnownChannelRootAndRetainsArchiveDefenses() throws {
        let valid = zip("ChirpOS Pro.app/Contents/MacOS/Birding")
        XCTAssertEqual(try UpdateArchive.validate(valid, appName: "ChirpOS Pro.app"), 1)
        XCTAssertThrowsError(try UpdateArchive.validate(valid))
        XCTAssertThrowsError(try UpdateArchive.validate(zip("ChirpOS.app/file"), appName: "ChirpOS Pro.app"))
        XCTAssertThrowsError(try UpdateArchive.validate(zip("Other.app/file"), appName: "Other.app"))
        XCTAssertThrowsError(try UpdateArchive.validate(valid, appName: "../ChirpOS Pro.app"))
        for name in ["ChirpOS Pro.app/../evil", "ChirpOS Pro.app/./evil", "ChirpOS Pro.app/a\\evil", "ChirpOS Pro.app/a:evil", "ChirpOS Pro.app/evil\0", "/ChirpOS Pro.app/file", "ChirpOS Pro.app.evil/file"] {
            XCTAssertThrowsError(try UpdateArchive.validate(zip(name), appName: "ChirpOS Pro.app"), name)
        }
        XCTAssertThrowsError(try UpdateArchive.validate(zip("ChirpOS Pro.app/link", mode: 0o120777), appName: "ChirpOS Pro.app"))
        XCTAssertThrowsError(try UpdateArchive.validate(zip("ChirpOS Pro.app/file", localName: "ChirpOS Pro.app/evil"), appName: "ChirpOS Pro.app"))
        XCTAssertThrowsError(try UpdateArchive.validate(zip("ChirpOS Pro.app/bomb", size: UInt32(1024*1024*1024+1)), appName: "ChirpOS Pro.app"))
        XCTAssertThrowsError(try UpdateArchive.validate(zip("ChirpOS Pro.app/file", extra: Data([0x75,0x70,0,0])), appName: "ChirpOS Pro.app"))
        XCTAssertNoThrow(try UpdateArchive.validate(zip("__MACOSX/._ChirpOS Pro.app"), appName: "ChirpOS Pro.app"))
    }
}
