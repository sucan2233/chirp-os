import XCTest
@testable import BirdingCore

final class CourtshipPoseTests:XCTestCase {
    func testOnlySpottedDovesHaveBothRolesAndTheCompleteFiveFrameContract() throws {
        let names=["courtRaise","courtBow0","courtBow1","courtBowRecover","courtObserve"]
        XCTAssertEqual(SpeciesBehaviorProfile.species(for:.courtshipDisplay),[.spottedDove])
        XCTAssertEqual(SpeciesBehaviorProfile.courtshipFrameNames,names)
        XCTAssertEqual(BirdCapability.courtship.requiredFrames,Set(names))
        XCTAssertEqual(CourtshipRole.allCases,[.initiator,.observer])
        for species in SpeciesID.allCases {
            let allowed=species == .spottedDove
            XCTAssertEqual(SpeciesBehaviorProfile.profile(for:species).allows(.courtshipDisplay),allowed)
            for role:CourtshipRole in [.initiator,.observer] {
                let clip=PoseClip.courtship(species:species,role:role)
                XCTAssertEqual(clip != nil,allowed)
                if let clip {
                    XCTAssertEqual(clip.requiredFrames,Set(names+["stand"]))
                    XCTAssertEqual(clip.duration,4,accuracy:1e-12)
                    XCTAssertEqual(clip.maximumLoops,1);XCTAssertEqual(clip.foot,.init(29,39))
                    XCTAssertEqual(clip.recovery,.currentEngineState)
                    XCTAssertNil(clip.sample(at:4));XCTAssertNil(clip.sample(at:-0.1));XCTAssertNil(clip.sample(at:.nan))
                    XCTAssertEqual(try JSONDecoder().decode(PoseClip.self,from:JSONEncoder().encode(clip)),clip)
                }
            }
        }
    }

    func testSingleClockLiteralStageBoundariesIncludeBothBowsAndObserverTurn() throws {
        let initiator=try XCTUnwrap(PoseClip.courtship(species:.spottedDove,role:.initiator))
        let observer=try XCTUnwrap(PoseClip.courtship(species:.spottedDove,role:.observer))
        let samples:[(Double,String,String)]=[(0,"stand","stand"),(0.39999,"stand","stand"),
            (0.4,"courtRaise","stand"),(0.89999,"courtRaise","stand"),
            (0.9,"courtBow0","stand"),(1.25,"courtBow1","stand"),(1.65,"courtBowRecover","stand"),
            (1.9,"courtBow0","stand"),(2.25,"courtBow1","stand"),(2.65,"courtBowRecover","stand"),
            (2.9,"courtBowRecover","courtObserve"),(3.39999,"courtBowRecover","courtObserve"),
            (3.4,"courtBowRecover","stand"),(3.99999,"courtBowRecover","stand")]
        for (age,a,b) in samples {
            XCTAssertEqual(initiator.sample(at:age)?.name,a,"initiator \(age)")
            XCTAssertEqual(observer.sample(at:age)?.name,b,"observer \(age)")
        }
        for clip in [initiator,observer] {for frame in clip.frames {
            XCTAssertTrue(frame.beak.x.isFinite && frame.beak.y.isFinite)
            let foot=CGPoint(x:-900,y:-400)
            for scale:CGFloat in [0.5,1,2] {
                let a=frame.beak.world(foot:foot,scale:scale,facingRight:true)
                let b=frame.beak.world(foot:foot,scale:scale,facingRight:false)
                XCTAssertEqual(a.x-foot.x,foot.x-b.x,accuracy:1e-9)
                XCTAssertEqual(a.y,b.y,accuracy:1e-9)
            }
        }}
    }
}
