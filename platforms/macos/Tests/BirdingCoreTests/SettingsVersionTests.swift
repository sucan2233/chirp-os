import Foundation
import XCTest
import BirdingCore

final class SettingsVersionTests: XCTestCase {
    func testNewSettingsEncodeCurrentVersionAtTopLevel() throws {
        let settings=BirdSettings()
        XCTAssertEqual(BirdSettings.currentSchemaVersion,1)
        XCTAssertEqual(settings.schemaVersion,1)
        let object=try settingsObject(settings)
        XCTAssertEqual(object["schemaVersion"] as? Int,1)
        XCTAssertNotNil(object["catalog"])
        XCTAssertNotNil(object["probabilities"])
    }

    func testCurrentVersionRoundTripsEverySetting() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        for enabled in [false,true] {
            let original=configuredSettings(enabled:enabled)
            let data=try JSONEncoder().encode(original)
            assertSettingsEqual(try JSONDecoder().decode(BirdSettings.self,from:data),original)
            assertSettingsEqual(try BirdSettings.decode(data),original)
            try original.save(to:url)
            assertSettingsEqual(try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("legacy.json")),original)
            let saved=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
            XCTAssertEqual(saved["schemaVersion"] as? Int,1)
        }
    }

    func testMissingAndZeroVersionsMigrateWithoutResettingAnySetting() throws {
        for enabled in [false,true] {
            let original=configuredSettings(enabled:enabled)
            for explicitZero in [false,true] {
                let data=try oldSettingsData(original,explicitZero:explicitZero)
                let direct=try JSONDecoder().decode(BirdSettings.self,from:data)
                let migrated=try BirdSettings.decode(data)
                assertSettingsEqual(direct,original)
                assertSettingsEqual(migrated,original)
                assertSettingsEqual(try BirdSettings.decode(JSONEncoder().encode(migrated)),migrated)
                XCTAssertEqual(try settingsObject(migrated)["schemaVersion"] as? Int,1)
            }
        }
    }

    func testOldFilesMissingNewSwitchesReceiveTheirExistingDefaults() throws {
        var expected=configuredSettings()
        var object=try settingsObject(expected)
        for key in ["schemaVersion","pointerVisits","pointerFollowEnabled","flockPasses",
                    "socialInteractions","perchActions","passiveAttentionEnabled",
                    "leafPlayEnabled","ambientLeafPlayEnabled"] {
            object.removeValue(forKey:key)
        }
        expected.pointerVisits=true;expected.pointerFollowEnabled=false
        expected.flockPasses=true;expected.socialInteractions=true;expected.perchActions=true
        expected.passiveAttentionEnabled=true;expected.leafPlayEnabled=true;expected.ambientLeafPlayEnabled=true
        let data=try JSONSerialization.data(withJSONObject:object)
        assertSettingsEqual(try JSONDecoder().decode(BirdSettings.self,from:data),expected)
        assertSettingsEqual(try BirdSettings.decode(data),expected)
    }

    func testOldSpeciesExpansionKeepsProbabilitiesLocksAndPreferencesOnRepeatedMigration() throws {
        var original=configuredSettings()
        original.catalog.species=Array(original.catalog.species.prefix(7))
        original.probabilities=ProbabilityDistribution(catalog:original.catalog)
        original.probabilities.adjust(at:0,to:1234)
        original.probabilities.setLocked(true,at:0)
        original.pendingSpecies=[]
        let added=SpeciesCatalog.standard.species.filter { profile in
            !original.catalog.species.contains(where:{$0.id==profile.id})
        }
        let migrated=try BirdSettings.decode(oldSettingsData(original))
        var expected=original
        expected.catalog.species += added
        try expected.probabilities.includeNewSpecies()
        expected.pendingSpecies=added.map(\.id)
        assertSettingsEqual(migrated,expected)
        XCTAssertEqual(Array(migrated.probabilities.entries.prefix(original.probabilities.entries.count)),original.probabilities.entries)
        XCTAssertTrue(migrated.probabilities.entries.dropFirst(original.probabilities.entries.count).allSatisfy{$0.points==0 && !$0.locked})
        XCTAssertTrue(migrated.probabilities.isValid)
        assertSettingsEqual(try BirdSettings.decode(JSONEncoder().encode(migrated)),migrated)
    }

    func testOldBehaviorDefaultsMigrateOnceWhileCustomValuesSurvive() throws {
        var original=configuredSettings()
        original.perchDefaultsVersion=nil
        for i in original.catalog.species.indices {
            let id=original.catalog.species[i].id
            original.catalog.species[i].flapFPS=SpeciesCatalog.standard.profile(id).flapFPS / FlightBehavior.motion(id).rate
            original.catalog.species[i].perchMin/=2
            original.catalog.species[i].perchMax/=2
        }
        original.catalog.species[0].perchMin+=1
        original.catalog.species[1].perchMax+=1
        original.catalog.species[0].flapFPS=27.125
        var expected=original
        expected.perchDefaultsVersion=1
        for i in expected.catalog.species.indices {
            let current=SpeciesCatalog.standard.profile(expected.catalog.species[i].id)
            if i>0 {expected.catalog.species[i].flapFPS=current.flapFPS}
            if i>1 {
                expected.catalog.species[i].perchMin=current.perchMin
                expected.catalog.species[i].perchMax=current.perchMax
            }
        }
        let migrated=try BirdSettings.decode(oldSettingsData(original))
        assertSettingsEqual(migrated,expected)
        assertSettingsEqual(try BirdSettings.decode(JSONEncoder().encode(migrated)),migrated)
    }

    func testFutureVersionsAreRejectedByBothDecodingEntrypoints() throws {
        for version in [2,Int.max] {
            var object=try settingsObject(configuredSettings())
            object["schemaVersion"]=version
            let data=try JSONSerialization.data(withJSONObject:object)
            assertRejectedByDecoders(data,expected:.unsupportedVersion(version))
        }
    }

    func testFutureVersionTakesPriorityOverMissingOrIncompatibleCatalogAndSettings() throws {
        let version=BirdSettings.currentSchemaVersion+1
        let objects:[[String:Any]] = [
            ["schemaVersion":version],
            ["schemaVersion":version,"catalog":"future catalog","hoverDelay":"future delay"],
            ["schemaVersion":version,"catalog":["species":[["id":"futureBird"]]],"probabilities":false]
        ]
        for object in objects {
            assertRejectedByDecoders(try JSONSerialization.data(withJSONObject:object),expected:.unsupportedVersion(version))
        }
    }

    func testLoadAndFallbackSaveLeaveFutureFilesByteForByteUnchanged() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        let legacy=folder.appendingPathComponent("species.json")
        let legacyData=try JSONEncoder().encode(SpeciesCatalog.standard)
        try legacyData.write(to:legacy)
        for version in [2,Int.max] {
            var complete=try settingsObject(configuredSettings())
            complete["schemaVersion"]=version
            for object in [complete,["schemaVersion":version,"catalog":"future format"]] {
                let data=try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys])
                try data.write(to:url)
                assertVersionError(.unsupportedVersion(version)) {
                    _ = try BirdSettings.load(from:url,legacyURL:legacy)
                }
                XCTAssertEqual(try Data(contentsOf:url),data)
                assertVersionError(.unsupportedVersion(version)) {try BirdSettings().save(to:url)}
                XCTAssertEqual(try Data(contentsOf:url),data)
                var invalid=BirdSettings();invalid.hoverDelay = .infinity
                assertVersionError(.unsupportedVersion(version)) {try invalid.save(to:url)}
                XCTAssertEqual(try Data(contentsOf:url),data)
                XCTAssertEqual(try Data(contentsOf:legacy),legacyData)
            }
        }
    }

    func testIllegalVersionsAreRejectedAndCannotBeOverwritten() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        let invalidLiterals=["-1","-9223372036854775808","1.5","\"1\"","\"future\"",
                             "true","false","null","[]","{}","9223372036854775808","1e100"]
        for literal in invalidLiterals {
            let data=Data("{\"schemaVersion\":\(literal),\"catalog\":null}".utf8)
            assertRejectedByDecoders(data,expected:.invalidVersion)
            try data.write(to:url)
            assertVersionError(.invalidVersion) {
                _ = try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("legacy.json"))
            }
            XCTAssertEqual(try Data(contentsOf:url),data)
            assertVersionError(.invalidVersion) {try BirdSettings().save(to:url)}
            XCTAssertEqual(try Data(contentsOf:url),data)
        }
    }

    func testLoadingOldTargetDoesNotWriteAndSavingUpgradesItsVersion() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        for explicitZero in [false,true] {
            let original=configuredSettings()
            let data=try oldSettingsData(original,explicitZero:explicitZero)
            try data.write(to:url)
            var loaded=try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("legacy.json"))
            assertSettingsEqual(loaded,original)
            XCTAssertEqual(try Data(contentsOf:url),data)
            loaded.hoverDelay=0.75
            try loaded.save(to:url)
            let saved=try Data(contentsOf:url)
            let object=try XCTUnwrap(JSONSerialization.jsonObject(with:saved) as? [String:Any])
            XCTAssertEqual(object["schemaVersion"] as? Int,1)
            assertSettingsEqual(try BirdSettings.decode(saved),loaded)
        }
    }

    func testSaveChecksOnlyExistingVersionContractAndAllowsRepairingOtherFields() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        let original=configuredSettings()
        for json in ["{\"catalog\":false}","{\"schemaVersion\":0,\"catalog\":false}","{\"schemaVersion\":1}"] {
            try Data(json.utf8).write(to:url)
            try original.save(to:url)
            assertSettingsEqual(try BirdSettings.decode(Data(contentsOf:url)),original)
        }
    }

    func testInvalidOutgoingSettingsLeaveExistingFileUnchangedAndDoNotCreateDirectories() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        let data=try oldSettingsData(configuredSettings())
        try data.write(to:url)
        var invalid=BirdSettings()
        invalid.catalog.species[0].speed = -1
        XCTAssertThrowsError(try invalid.save(to:url))
        XCTAssertEqual(try Data(contentsOf:url),data)
        let missingFolder=folder.appendingPathComponent("not-created")
        XCTAssertThrowsError(try invalid.save(to:missingFolder.appendingPathComponent("settings.json")))
        XCTAssertFalse(FileManager.default.fileExists(atPath:missingFolder.path))
    }

    func testLegacySpeciesFileStillMigratesWithoutWritingEitherSource() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        let legacy=folder.appendingPathComponent("species.json")
        var catalog=SpeciesCatalog.standard
        catalog.species=Array(catalog.species.prefix(7))
        catalog.species[0].speed=1.25
        let data=try JSONEncoder().encode(catalog)
        try data.write(to:legacy)
        let migrated=try BirdSettings.load(from:url,legacyURL:legacy)
        XCTAssertEqual(migrated.schemaVersion,1)
        XCTAssertEqual(Array(migrated.catalog.species.prefix(catalog.species.count)),catalog.species)
        XCTAssertEqual(Array(migrated.probabilities.entries.prefix(catalog.species.count)),ProbabilityDistribution(catalog:catalog).entries)
        XCTAssertTrue(migrated.probabilities.entries.dropFirst(catalog.species.count).allSatisfy{$0.points==0 && !$0.locked})
        XCTAssertTrue(migrated.pointerVisits);XCTAssertFalse(migrated.pointerFollowEnabled)
        XCTAssertTrue(migrated.flockPasses);XCTAssertTrue(migrated.socialInteractions)
        XCTAssertTrue(migrated.perchActions);XCTAssertTrue(migrated.passiveAttentionEnabled)
        XCTAssertTrue(migrated.leafPlayEnabled);XCTAssertTrue(migrated.ambientLeafPlayEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        XCTAssertEqual(try Data(contentsOf:legacy),data)
        assertSettingsEqual(try BirdSettings.decode(JSONEncoder().encode(migrated)),migrated)
    }

    func testVersionErrorsHaveDisplayableDescriptionsIncludingFutureVersion() throws {
        let future=BirdSettingsVersionError.unsupportedVersion(42)
        XCTAssertTrue(try XCTUnwrap(future.errorDescription).contains("42"))
        XCTAssertTrue(future.localizedDescription.contains("42"))
        XCTAssertFalse(try XCTUnwrap(BirdSettingsVersionError.invalidVersion.errorDescription).isEmpty)
    }

    private func temporaryFolder() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }

    private func settingsObject(_ settings:BirdSettings) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
    }

    private func oldSettingsData(_ settings:BirdSettings,explicitZero:Bool = false) throws -> Data {
        var object=try settingsObject(settings)
        if explicitZero {object["schemaVersion"]=0}
        else {object.removeValue(forKey:"schemaVersion")}
        return try JSONSerialization.data(withJSONObject:object)
    }

    private func configuredSettings(enabled:Bool = false) -> BirdSettings {
        var settings=BirdSettings()
        settings.hoverDelay=0.25
        settings.pointerVisits=enabled;settings.pointerFollowEnabled = !enabled
        settings.flockPasses=enabled;settings.socialInteractions=enabled;settings.perchActions=enabled
        settings.passiveAttentionEnabled=enabled;settings.leafPlayEnabled=enabled;settings.ambientLeafPlayEnabled=enabled
        settings.ambientFrequency = .high
        settings.catalog.species[0].speed=1.25
        settings.probabilities.adjust(at:0,to:1234)
        settings.probabilities.setLocked(true,at:0)
        settings.pendingSpecies=[.nightHeron]
        return settings
    }

    private func assertRejectedByDecoders(_ data:Data,expected:BirdSettingsVersionError,file:StaticString = #filePath,line:UInt = #line) {
        assertVersionError(expected,file:file,line:line) {_ = try JSONDecoder().decode(BirdSettings.self,from:data)}
        assertVersionError(expected,file:file,line:line) {_ = try BirdSettings.decode(data)}
    }

    private func assertVersionError(_ expected:BirdSettingsVersionError,file:StaticString = #filePath,line:UInt = #line,
                                    operation:() throws -> Void) {
        XCTAssertThrowsError(try operation(),file:file,line:line) {error in
            XCTAssertEqual(error as? BirdSettingsVersionError,expected,file:file,line:line)
        }
    }

    private func assertSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,file:StaticString = #filePath,line:UInt = #line) {
        XCTAssertEqual(actual.schemaVersion,1,file:file,line:line)
        XCTAssertEqual(actual.schemaVersion,expected.schemaVersion,file:file,line:line)
        XCTAssertEqual(actual.catalog.species,expected.catalog.species,file:file,line:line)
        XCTAssertEqual(actual.probabilities,expected.probabilities,file:file,line:line)
        XCTAssertEqual(actual.hoverDelay,expected.hoverDelay,file:file,line:line)
        XCTAssertEqual(actual.pointerVisits,expected.pointerVisits,file:file,line:line)
        XCTAssertEqual(actual.pointerFollowEnabled,expected.pointerFollowEnabled,file:file,line:line)
        XCTAssertEqual(actual.flockPasses,expected.flockPasses,file:file,line:line)
        XCTAssertEqual(actual.socialInteractions,expected.socialInteractions,file:file,line:line)
        XCTAssertEqual(actual.perchActions,expected.perchActions,file:file,line:line)
        XCTAssertEqual(actual.passiveAttentionEnabled,expected.passiveAttentionEnabled,file:file,line:line)
        XCTAssertEqual(actual.leafPlayEnabled,expected.leafPlayEnabled,file:file,line:line)
        XCTAssertEqual(actual.ambientLeafPlayEnabled,expected.ambientLeafPlayEnabled,file:file,line:line)
        XCTAssertEqual(actual.ambientFrequency,expected.ambientFrequency,file:file,line:line)
        XCTAssertEqual(actual.perchDefaultsVersion,expected.perchDefaultsVersion,file:file,line:line)
        XCTAssertEqual(actual.pendingSpecies,expected.pendingSpecies,file:file,line:line)
    }
}
