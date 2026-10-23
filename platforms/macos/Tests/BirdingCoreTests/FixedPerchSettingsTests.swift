import XCTest
@testable import BirdingCore

final class FixedPerchSettingsTests: XCTestCase {
    private let display=CGRect(x:-1600,y:-300,width:1600,height:1000)

    private func anchor(slot:Int=1,displayID:String="left",frame:CGRect?=nil,x:Double=0.25,y:Double=0.75) -> FixedPerchAnchor {
        FixedPerchAnchor(slot:slot,displayID:displayID,displayFrame:frame ?? display,x:x,y:y)
    }

    func testNewAndOldSettingsEnableEmptyFixedPerches() throws {
        XCTAssertTrue(BirdSettings().fixedPerchesEnabled)
        XCTAssertTrue(BirdSettings().fixedPerches.isEmpty)
        var original=BirdSettings()
        original.hoverDelay=0.25;original.pointerVisits=false
        original.catalog.species[0].speed=1.25
        var object=try settingsObject(original)
        object.removeValue(forKey:"fixedPerchesEnabled")
        object.removeValue(forKey:"fixedPerches")
        object.removeValue(forKey:"schemaVersion")
        let data=try JSONSerialization.data(withJSONObject:object)
        for decoded in [try JSONDecoder().decode(BirdSettings.self,from:data),try BirdSettings.decode(data)] {
            XCTAssertTrue(decoded.fixedPerchesEnabled)
            XCTAssertTrue(decoded.fixedPerches.isEmpty)
            XCTAssertEqual(decoded.hoverDelay,original.hoverDelay)
            XCTAssertEqual(decoded.pointerVisits,original.pointerVisits)
            XCTAssertEqual(decoded.catalog.species,original.catalog.species)
            XCTAssertEqual(decoded.probabilities,original.probabilities)
        }
    }

    func testLegacyCatalogDefaultsDoNotWriteEitherSource() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let legacy=folder.appendingPathComponent("species.json"),url=folder.appendingPathComponent("settings.json")
        let data=try JSONEncoder().encode(SpeciesCatalog.standard)
        try data.write(to:legacy)
        let settings=try BirdSettings.load(from:url,legacyURL:legacy)
        XCTAssertTrue(settings.fixedPerchesEnabled)
        XCTAssertTrue(settings.fixedPerches.isEmpty)
        XCTAssertEqual(try Data(contentsOf:legacy),data)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
    }

    func testSaveLoadAndModelRoundTripPreserveAnchorsWhileDisabled() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        var settings=BirdSettings()
        settings.fixedPerches=[anchor(),anchor(slot:2,displayID:"",x:0,y:1),anchor(slot:3,x:1,y:0)]
        settings.hoverDelay=0.75
        for enabled in [true,false,true] {
            settings.fixedPerchesEnabled=enabled
            try settings.save(to:url)
            let data=try Data(contentsOf:url)
            let loaded=try BirdSettings.load(from:url,legacyURL:folder.appendingPathComponent("legacy.json"))
            let direct=try JSONDecoder().decode(BirdSettings.self,from:data)
            for decoded in [loaded,direct] {
                XCTAssertEqual(decoded.fixedPerchesEnabled,enabled)
                XCTAssertEqual(decoded.fixedPerches,settings.fixedPerches)
                XCTAssertEqual(decoded.hoverDelay,settings.hoverDelay)
            }
        }
        let value=anchor(displayID:String(repeating:"屏",count:128))
        XCTAssertEqual(try JSONDecoder().decode(FixedPerchAnchor.self,from:JSONEncoder().encode(value)),value)
    }

    func testAnchorDecoderRejectsIllegalSlotIDAndGeometry() throws {
        let invalid=[anchor(slot:0),anchor(slot:4),anchor(slot:Int.max),
                     anchor(displayID:String(repeating:"a",count:129)),
                     anchor(frame:CGRect(x:0,y:0,width:0,height:100)),
                     anchor(frame:CGRect(x:0,y:0,width:-100,height:100)),
                     anchor(frame:CGRect(x:0,y:0,width:100,height:-100)),
                     anchor(frame:CGRect(x:1_000_001,y:0,width:100,height:100)),
                     anchor(frame:CGRect(x:-1_000_001,y:0,width:100,height:100)),
                     anchor(frame:CGRect(x:999_999,y:0,width:100,height:100)),
                     anchor(frame:CGRect(x:0,y:0,width:1_000_001,height:100)),
                     anchor(x:-0.01),anchor(x:1.01),anchor(y:-0.01),anchor(y:1.01)]
        for value in invalid {
            let data=try JSONEncoder().encode(value)
            XCTAssertThrowsError(try JSONDecoder().decode(FixedPerchAnchor.self,from:data),"\(value)")
            var settings=BirdSettings();settings.fixedPerches=[value]
            try assertRejectedByBothDecoders(settings)
        }
    }

    func testDirectModelDecoderRejectsNonfiniteCoordinates() throws {
        let decoder=JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity:"Infinity",negativeInfinity:"-Infinity",nan:"NaN")
        for key in ["x","y"] {
            for invalid in ["Infinity","-Infinity","NaN"] {
                var object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(anchor())) as? [String:Any])
                object[key]=invalid
                let data=try JSONSerialization.data(withJSONObject:object)
                XCTAssertThrowsError(try decoder.decode(FixedPerchAnchor.self,from:data))
                var settings=try settingsObject(BirdSettings());settings["fixedPerches"]=[object]
                XCTAssertThrowsError(try decoder.decode(BirdSettings.self,from:JSONSerialization.data(withJSONObject:settings)))
            }
        }
        let encoder=JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity:"Infinity",negativeInfinity:"-Infinity",nan:"NaN")
        for frame in [CGRect.infinite,CGRect(x:CGFloat.nan,y:0,width:100,height:100),
                      CGRect(x:0,y:CGFloat.infinity,width:100,height:100),
                      CGRect(x:0,y:0,width:CGFloat.infinity,height:100)] {
            let bad=anchor(frame:frame)
            XCTAssertThrowsError(try decoder.decode(FixedPerchAnchor.self,from:encoder.encode(bad)))
            var settings=BirdSettings();settings.fixedPerches=[bad]
            XCTAssertThrowsError(try decoder.decode(BirdSettings.self,from:encoder.encode(settings)))
        }
    }

    func testDuplicateSlotsAndMoreThanThreeAreRejectedEvenWhenDisabled() throws {
        for anchors in [[anchor(),anchor()],
                        [anchor(),anchor(slot:2),anchor(slot:3),anchor(slot:3)]] {
            var settings=BirdSettings();settings.fixedPerches=anchors;settings.fixedPerchesEnabled=false
            try assertRejectedByBothDecoders(settings)
        }
    }

    func testMalformedFieldsAreRejectedWithoutDroppingAnchors() throws {
        let valid=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(anchor())) as? [String:Any])
        for invalid:Any in [NSNull(),"perches",1,[valid,NSNull()]] {
            var object=try settingsObject(BirdSettings());object["fixedPerches"]=invalid
            let data=try JSONSerialization.data(withJSONObject:object)
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data))
            XCTAssertThrowsError(try BirdSettings.decode(data))
        }
        for key in ["slot","displayID","displayFrame","x","y"] {
            var bad=valid;bad.removeValue(forKey:key)
            var object=try settingsObject(BirdSettings());object["fixedPerches"]=[valid,bad]
            let data=try JSONSerialization.data(withJSONObject:object)
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data))
            XCTAssertThrowsError(try BirdSettings.decode(data))
        }
        for invalid:Any in ["enabled",1,[],["enabled":true]] {
            var object=try settingsObject(BirdSettings());object["fixedPerchesEnabled"]=invalid
            XCTAssertThrowsError(try BirdSettings.decode(JSONSerialization.data(withJSONObject:object)))
        }
    }

    func testInvalidSavePreservesExistingBytesAndDoesNotCreateDirectory() throws {
        let folder=try temporaryFolder()
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("settings.json")
        var original=BirdSettings();original.fixedPerches=[anchor()]
        try original.save(to:url)
        let data=try Data(contentsOf:url)
        let badAnchors=[[anchor(),anchor()],
                        [anchor(),anchor(slot:2),anchor(slot:3),anchor(slot:3)],
                        [anchor(slot:0)],[anchor(x:.nan)],[anchor(y:.infinity)],
                        [anchor(frame:.infinite)],
                        [anchor(frame:CGRect(x:CGFloat.nan,y:0,width:100,height:100))],
                        [anchor(frame:CGRect(x:0,y:0,width:100,height:CGFloat.infinity))]]
        for anchors in badAnchors {
            var invalid=original;invalid.fixedPerches=anchors;invalid.fixedPerchesEnabled=false
            XCTAssertThrowsError(try invalid.save(to:url))
            XCTAssertEqual(try Data(contentsOf:url),data)
            let missing=folder.appendingPathComponent("not-created")
            XCTAssertThrowsError(try invalid.save(to:missing.appendingPathComponent("settings.json")))
            XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path))
        }
    }

    private func assertRejectedByBothDecoders(_ settings:BirdSettings) throws {
        let data=try JSONEncoder().encode(settings)
        XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data))
        XCTAssertThrowsError(try BirdSettings.decode(data))
    }

    private func settingsObject(_ settings:BirdSettings) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
    }

    private func temporaryFolder() throws -> URL {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        return folder
    }
}
