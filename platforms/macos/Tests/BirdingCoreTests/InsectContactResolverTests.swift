import XCTest
@testable import BirdingCore

final class InsectContactResolverTests:XCTestCase {
    private func store(duration:Double=14)throws->InsectStore {
        let path=try XCTUnwrap(InsectTrajectory(waypoints:[
            .init(time:0,position:CGPoint(x:-20,y:50)),
            .init(time:duration,position:CGPoint(x:120,y:50))],
            display:CGRect(x:0,y:0,width:100,height:100),worldScale:1))
        let store=InsectStore();XCTAssertTrue(store.install(id:ScenePropID(9),trajectory:path));return store
    }
    private func resolve(_ step:InsectStep,interval:ClosedRange<Double> = 0...14,
                         open:Range<Double> = 0..<14,boundaries:[Double]=[],
                         beak:@escaping(Double)->CGPoint?)->InsectSweepResult {
        InsectContactResolver.resolve(step,runID:BehaviorRunID(rawValue:2),birdID:BirdID(3),
            simulationStart:100+step.startAge,motionInterval:interval,openInterval:open,
            boundaries:boundaries,beakAt:beak)
    }

    func testSweepFindsEarliestRealContactWhenBothFrameEndpointsMiss() throws {
        for hz in [30,60,120] {
            let store=try self.store();var contact:InsectContact?
            for _ in 0..<14*hz {
                guard let step=store.makeStep(1/Double(hz)) else {break}
                let result=resolve(step,beak:{_ in CGPoint(x:50,y:50)})
                XCTAssertLessThanOrEqual(result.segments,InsectContactResolver.maximumSegments)
                XCTAssertTrue(store.commit(step,capture:result.contact))
                if let hit=result.contact {contact=hit;break}
            }
            let hit=try XCTUnwrap(contact)
            // The independent straight line reaches x=47 at t=6.7, entering
            // the radius-three circle around the fixed beak at x=50.
            XCTAssertEqual(hit.insectAge,6.7,accuracy:1e-7)
            XCTAssertEqual(hit.time,106.7,accuracy:1e-7)
            XCTAssertEqual(hit.insectID,ScenePropID(9));XCTAssertEqual(hit.birdID,BirdID(3))
            XCTAssertEqual(hit.runID,BehaviorRunID(rawValue:2));XCTAssertNil(store.current)
            XCTAssertEqual(hit.insectPosition.x,47,accuracy:1e-6)
            XCTAssertEqual(hit.insectPosition.y,50)
            XCTAssertLessThanOrEqual(Geometry.distance(hit.beakPosition,hit.insectPosition),3)
        }
        let store=try self.store(),step=try XCTUnwrap(store.makeStep(14))
        XCTAssertGreaterThan(Geometry.distance(CGPoint(x:50,y:50),step.trajectory.position(at:0)),3)
        XCTAssertGreaterThan(Geometry.distance(CGPoint(x:50,y:50),step.trajectory.position(at:14)),3)
        let result=resolve(step,beak:{_ in CGPoint(x:50,y:50)})
        XCTAssertEqual(try XCTUnwrap(result.contact).insectAge,6.7,accuracy:1e-7)
        XCTAssertTrue(store.commit(step,capture:result.contact),"A real earlier contact wins over expiry later in the same tick")
        XCTAssertNotNil(store.lastContact)
    }

    func testExpiryExitAndOpenBeakWindowRejectLaterContactWithinTheSameTick() throws {
        let store=try self.store(),step=try XCTUnwrap(store.makeStep(14))
        let early=resolve(step,beak:{_ in CGPoint(x:100,y:50)})
        XCTAssertEqual(try XCTUnwrap(early.contact).insectAge,11.7,accuracy:1e-7)
        XCTAssertNil(resolve(step,beak:{_ in CGPoint(x:104,y:50)}).contact,
            "The first possible contact is age12.1, after the lifetime cap")
        XCTAssertNil(resolve(step,open:0..<6.6,beak:{_ in CGPoint(x:50,y:50)}).contact)
        XCTAssertNil(resolve(step,open:7.4..<14,beak:{_ in CGPoint(x:50,y:50)}).contact)
        let newlyOpen=resolve(step,open:7.1..<7.2,beak:{_ in CGPoint(x:50,y:50)})
        XCTAssertEqual(try XCTUnwrap(newlyOpen.contact).insectAge,7.1,accuracy:1e-9)
        let leaving=try self.store(duration:7),leavingStep=try XCTUnwrap(leaving.makeStep(8))
        XCTAssertNil(resolve(leavingStep,beak:{_ in CGPoint(x:112,y:50)}).contact,
            "A beak outside the final visible edge cannot capture after exit")
        XCTAssertTrue(store.commit(step,capture:nil));XCTAssertNil(store.current);XCTAssertNil(store.lastContact)
    }

    func testActualCurvedSamplesDoNotInventContactAcrossAPoseDiscontinuity() throws {
        let store=try self.store();XCTAssertTrue(store.commit(try XCTUnwrap(store.makeStep(6.9)),capture:nil))
        let step=try XCTUnwrap(store.makeStep(0.2))
        let jump=resolve(step,interval:6.9...7.1,boundaries:[7],beak:{age in
            CGPoint(x:age<7 ? 20:80,y:50)
        })
        XCTAssertNil(jump.contact,"A chord across two different anchors would cross the insect, but neither actual pose does")
        let curved=resolve(step,interval:6.9...7.1,beak:{age in
            CGPoint(x:50,y:50+2000*(age-7)*(age-7))
        })
        let hit=try XCTUnwrap(curved.contact)
        XCTAssertGreaterThan(hit.insectAge,6.9);XCTAssertLessThan(hit.insectAge,7)
        XCTAssertLessThanOrEqual(Geometry.distance(hit.beakPosition,hit.insectPosition),3)
        XCTAssertLessThanOrEqual(curved.segments,128)
    }

    func testFiniteSearchBudgetAndNonfiniteBeakSamplesCannotManufactureSuccess() throws {
        let store=try self.store(),step=try XCTUnwrap(store.makeStep(14))
        let overflow=resolve(step,boundaries:(1..<300).map{Double($0)/25},beak:{_ in CGPoint(x:50,y:50)})
        XCTAssertNil(overflow.contact);XCTAssertLessThanOrEqual(overflow.segments,128)
        for point:CGPoint? in [nil,CGPoint(x:CGFloat.nan,y:50),CGPoint(x:50,y:CGFloat.infinity)] {
            let result=resolve(step,beak:{_ in point})
            XCTAssertNil(result.contact);XCTAssertLessThanOrEqual(result.segments,128)
        }
        XCTAssertEqual(InsectContactResolver.maximumSegments,128)
        XCTAssertNil(store.lastContact);XCTAssertEqual(store.current?.age,0,"Sampling is read only")
    }

    func testStoreRejectsAContactWithoutExactFrozenTimeGeometry() throws {
        let store=try self.store(),step=try XCTUnwrap(store.makeStep(14))
        let valid=try XCTUnwrap(resolve(step,beak:{_ in CGPoint(x:50,y:50)}).contact)
        for mismatch in ["identity","age","position","distance"] {
            let contact=InsectContact(runID:valid.runID,birdID:valid.birdID,
                insectID:mismatch == "identity" ? ScenePropID(10):valid.insectID,time:valid.time,
                insectAge:mismatch == "age" ? 12:valid.insectAge,
                beakPosition:mismatch == "distance" ? CGPoint(x:90,y:90):valid.beakPosition,
                insectPosition:mismatch == "position" ? CGPoint(x:50,y:50):valid.insectPosition)
            XCTAssertFalse(store.commit(step,capture:contact),mismatch)
            XCTAssertNotNil(store.current);XCTAssertEqual(store.current?.age,0)
        }
        XCTAssertTrue(store.commit(step,capture:valid));XCTAssertNil(store.current)
        XCTAssertFalse(store.commit(step,capture:valid));XCTAssertEqual(store.lastContact?.time,valid.time)
    }
}
