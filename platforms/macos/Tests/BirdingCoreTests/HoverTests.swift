import XCTest
@testable import BirdingCore

final class HoverTests:XCTestCase {
    func testCustomDelayAndContinuousHover() {
        var tracker=HoverTracker<Int>()
        XCTAssertNil(tracker.update(1,now:0,delay:0.25))
        XCTAssertNil(tracker.update(1,now:0.24,delay:0.25))
        XCTAssertEqual(tracker.update(1,now:0.25,delay:0.25),1)
        XCTAssertNil(tracker.update(2,now:1,delay:0.25))
        XCTAssertNil(tracker.update(nil,now:1.1,delay:0.25))
        XCTAssertNil(tracker.update(2,now:2,delay:0.25))
        XCTAssertEqual(tracker.update(2,now:2.25,delay:0.25),2)
    }
    func testZeroDelayAndLongDelay() {
        var tracker=HoverTracker<Int>()
        XCTAssertEqual(tracker.update(1,now:0,delay:0),1)
        XCTAssertNil(tracker.update(2,now:1,delay:10))
        XCTAssertNil(tracker.update(2,now:10.99,delay:10))
        XCTAssertEqual(tracker.update(2,now:11,delay:10),2)
    }
    func testOldSettingsDefaultToOneSecond() throws {
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as! [String:Any]
        object.removeValue(forKey:"hoverDelay")
        let saved=try BirdSettings.decode(JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(saved.hoverDelay,1)
    }
    func testHoverDelayPersistsWithoutChangingOtherSettings() throws {
        for delay in [0,0.25,1,10] {
            var original=BirdSettings();original.hoverDelay=delay
            original.probabilities.adjust(at:0,to:1234)
            original.probabilities.setLocked(true,at:0)
            let saved=try BirdSettings.decode(JSONEncoder().encode(original))
            XCTAssertEqual(saved.hoverDelay,delay)
            XCTAssertEqual(saved.probabilities,original.probabilities)
            XCTAssertEqual(saved.catalog.species,original.catalog.species)
        }
    }
    func testInvalidHoverDelayIsRejected() throws {
        for delay in [-1.0,10.01] {
            var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdSettings())) as! [String:Any]
            object["hoverDelay"]=delay
            XCTAssertThrowsError(try BirdSettings.decode(JSONSerialization.data(withJSONObject:object)))
        }
    }
}
