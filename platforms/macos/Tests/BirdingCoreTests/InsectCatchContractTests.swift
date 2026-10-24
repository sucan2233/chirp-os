import XCTest
@testable import BirdingCore

final class InsectCatchContractTests:XCTestCase {
    func testM6fTwoAuthorizesOnlySwallowAndFlycatcherAndRequiresTheWholeCatchPackage() throws {
        let catchFrames:Set<String>=["catchOpen","catchClose","catchRecover"]
        let required=catchFrames.union(["stand","land0","land1","land2"]).union((0..<8).map{"fly\($0)"})
        XCTAssertEqual(SpeciesBehaviorProfile.catchFrameNames,["catchOpen","catchClose","catchRecover"])
        XCTAssertEqual(SpeciesBehaviorProfile.species(for:.insectCatch),[.barnSwallow,.yellowRumpedFlycatcher])
        XCTAssertEqual(BirdCapability.insectCatching.requiredFrames,catchFrames)
        XCTAssertEqual(BehaviorDefinitions.definition(for:.insectCatch).requiredFrames,required)
        XCTAssertTrue(SpeciesBehaviorProfile.profile(for:.yellowRumpedFlycatcher).allows(.insectCatch))
        XCTAssertFalse(SpeciesBehaviorProfile.profile(for:.yellowRumpedFlycatcher).allows(.fixedPerchVisit))
        for species in SpeciesID.allCases {
            let row=try XCTUnwrap(SpeciesSupportAudit(species:species,availableFrames:required).behaviors.first{$0.kind == .insectCatch})
            XCTAssertEqual(row.productAllowed,[SpeciesID.barnSwallow,.yellowRumpedFlycatcher].contains(species))
            XCTAssertEqual(row.contentSupported,[SpeciesID.barnSwallow,.yellowRumpedFlycatcher].contains(species))
            XCTAssertTrue(row.missingFrames.isEmpty)
            for missing in required {
                let partial=SpeciesSupportAudit(species:species,availableFrames:required.subtracting([missing]))
                let entry=try XCTUnwrap(partial.behaviors.first{$0.kind == .insectCatch})
                XCTAssertEqual(entry.missingFrames,[missing]);XCTAssertFalse(entry.contentSupported)
            }
        }
        XCTAssertEqual(BehaviorReason.missedTarget.rawValue,"missedTarget")
    }

    func testCommandsRetainExplicitSpeciesAndSourceAndRejectMalformedPayloads() throws {
        let commands:[EngineCommand]=[.insectCatch(species:.barnSwallow,source:.preview),
            .insectCatch(species:.barnSwallow,source:.automatic),.insectCatch(species:.barnSwallow,source:.user),
            .insectCatch(species:.yellowRumpedFlycatcher,source:.preview),.cancelInsectCatchPreview,.clearInsect]
        for command in commands {
            let bytes=try JSONEncoder().encode(RecordedCommand(command))
            let decoded=try JSONDecoder().decode(RecordedCommand.self,from:bytes)
            XCTAssertEqual(try BehaviorInputLog.encoder().encode(RecordedCommand(decoded.validated())),
                try BehaviorInputLog.encoder().encode(RecordedCommand(command)))
        }
        var command=RecordedCommand(.insectCatch(species:.barnSwallow,source:.preview))
        XCTAssertEqual(command.species,"barnSwallow");XCTAssertEqual(command.source,"preview")
        command.species=nil;XCTAssertThrowsError(try command.validated())
        command.species="futureBird";XCTAssertThrowsError(try command.validated())
        command.species="barnSwallow";command.source=nil;XCTAssertThrowsError(try command.validated())
        command.source="futureSource";XCTAssertThrowsError(try command.validated())
    }

    func testRecordedInsectArtDefaultsTrueWithoutOverridingAnExplicitFalse() throws {
        XCTAssertTrue(BehaviorWorld().insectArtAvailable)
        var world=BehaviorWorld();world.insectArtAvailable=false
        let bytes=try JSONEncoder().encode(RecordedWorld(world))
        let recorded=try JSONDecoder().decode(RecordedWorld.self,from:bytes)
        XCTAssertFalse(try recorded.validated().insectArtAvailable)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        raw.removeValue(forKey:"insectArtAvailable")
        let absent=try JSONDecoder().decode(RecordedWorld.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertTrue(try absent.validated(inheriting:world).insectArtAvailable)
    }

    func testRecoveryClipAndAllFlightFramesExposeMirroredFiniteBeakAnchors() throws {
        XCTAssertEqual(CatchArtGeometry.frameNames,["catchOpen","catchClose","catchRecover"])
        XCTAssertEqual(CatchArtGeometry.footAnchor,CGPoint(x:29,y:39))
        XCTAssertEqual(CatchArtGeometry.insectFrameNames,["insect0","insect1","insect2","insect3"])
        XCTAssertEqual(CatchArtGeometry.insectLogicalSize,CGSize(width:16,height:16))
        XCTAssertEqual(CatchArtGeometry.insectAnchor,CGPoint(x:8,y:8))
        XCTAssertEqual(CatchArtGeometry.insectCollisionRadius,3);XCTAssertEqual(CatchArtGeometry.insectLifetime,12)
        let clip=try XCTUnwrap(PoseClip.insectCatchRecovery(species:.barnSwallow))
        XCTAssertEqual(clip.frames.map(\.name),["catchClose","catchRecover"])
        XCTAssertEqual(clip.duration,0.48,accuracy:1e-12);XCTAssertEqual(clip.maximumLoops,1)
        XCTAssertEqual(clip.sample(at:0)?.name,"catchClose")
        XCTAssertEqual(clip.sample(at:0.18)?.name,"catchRecover");XCTAssertNil(clip.sample(at:0.48))
        let flycatcher=try XCTUnwrap(PoseClip.insectCatchRecovery(species:.yellowRumpedFlycatcher))
        XCTAssertEqual(flycatcher.frames.map(\.name),["catchClose","catchRecover"])
        XCTAssertEqual(flycatcher.frames.map(\.duration),[0.18,0.30])
        XCTAssertEqual(flycatcher.duration,0.48,accuracy:1e-12)
        XCTAssertEqual(flycatcher.sample(at:0)?.name,"catchClose")
        XCTAssertEqual(flycatcher.sample(at:0.18)?.name,"catchRecover")
        XCTAssertNil(flycatcher.sample(at:0.48))
        let frames=Set(["stand","catchOpen","catchClose","catchRecover","land0","land1","land2"])
            .union((0..<8).map{"fly\($0)"})
        for frame in frames {
            let anchor=try XCTUnwrap(PoseClip.catchBeakAnchor(species:.barnSwallow,frame:frame),frame)
            XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite)
            for scale:CGFloat in [0.5,1,2] {
                let foot=CGPoint(x:200,y:300)
                let right=anchor.world(foot:foot,scale:scale,facingRight:true)
                let left=anchor.world(foot:foot,scale:scale,facingRight:false)
                XCTAssertEqual(right.x+left.x,400,accuracy:1e-9)
                XCTAssertEqual(right.y,left.y,accuracy:1e-9)
                XCTAssertEqual(right.y,300+CGFloat(anchor.y-39)*scale,accuracy:1e-9)
            }
        }
        for frame in CatchArtGeometry.insectFrameNames {XCTAssertNotNil(CatchArtGeometry.insectPose(frame:frame))}
        XCTAssertNil(CatchArtGeometry.insectPose(frame:"insect4"))
        for frame in frames {
            let anchor=try XCTUnwrap(PoseClip.catchBeakAnchor(species:.yellowRumpedFlycatcher,frame:frame),frame)
            XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite)
            for scale:CGFloat in [0.5,1,2] {
                let foot=CGPoint(x:-200,y:-300)
                let right=anchor.world(foot:foot,scale:scale,facingRight:true)
                let left=anchor.world(foot:foot,scale:scale,facingRight:false)
                XCTAssertEqual(right.x+left.x,-400,accuracy:1e-9)
                XCTAssertEqual(right.y,left.y,accuracy:1e-9)
            }
        }
        XCTAssertNil(PoseClip.catchBeakAnchor(species:.treeSparrow,frame:"catchOpen"))
    }
}
