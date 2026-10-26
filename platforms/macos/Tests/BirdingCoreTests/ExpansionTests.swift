import XCTest
@testable import BirdingCore

final class ExpansionTests:XCTestCase {
    func testNationalCatalogAndDistinctTitIdentity() {
        let catalog=SpeciesCatalog.standard
        XCTAssertEqual(catalog.species.count,100)
        XCTAssertTrue(catalog.species.allSatisfy { $0.weight > 0 && $0.weightBasis.contains("全国") })
        XCTAssertEqual(catalog.profile(.greatTit).scientificName,"Parus minor")
        XCTAssertEqual(catalog.profile(.eurasianGreatTit).scientificName,"Parus major")
        XCTAssertTrue(catalog.species.dropFirst(46).allSatisfy { !($0.appearanceNotes ?? "").isEmpty && !($0.scientificName ?? "").isEmpty })
        XCTAssertEqual(SpeciesBehavior.frame(.eurasianNuthatch,age:1,side:true),"cling0")
        XCTAssertTrue(SpeciesBehavior.frame(.eurasianNuthatch,age:4,side:true)!.hasPrefix("peck"))
        XCTAssertTrue(FlightBehavior.canGlide(.himalayanVulture))
        XCTAssertFalse(FlightBehavior.canGlide(.easternSpotBilledDuck))
    }

    func testGalleryPlaysOnlySelectedAction() {
        let resting=Set((0..<1200).map{GalleryPose.frame(.nightHeron,age:Double($0)/30,fps:20)})
        XCTAssertEqual(resting,Set(["stand","breathe","blink"]))
        let night=Set((0..<300).map{GalleryPose.frame(.nightHeron,age:Double($0)/30,fps:20,action:.other)})
        XCTAssertEqual(night,Set(LivelyMotion.frameNames(for:.nightHeron)+["stand"]))
        let wood=Set((0..<150).map{GalleryPose.frame(.greatSpottedWoodpecker,age:Double($0)/30,fps:24,action:.other)})
        XCTAssertEqual(wood,Set(["cling0","sideBrace","sideDraw","sideTap","sideRecover"]))
        for i in 0..<300 {
            let t=Double(i)/30
            XCTAssertEqual(GalleryPose.frame(.blackKite,age:t,fps:20,action:.other), LivelyMotion.previewFrame(species:.blackKite,age:t))
            XCTAssertTrue(GalleryPose.frame(.blackKite,age:t,fps:20,action:.flapping).hasPrefix("fly"))
            XCTAssertEqual(GalleryPose.frame(.blackKite,age:t,fps:20,action:.gliding),"glide1")
        }
    }
    func testHoverRequiresContinuousIdentityAndResetsOnExit() {
        var h=HoverTracker<Int>()
        XCTAssertNil(h.update(1,now:10));XCTAssertNil(h.update(1,now:10.99))
        XCTAssertEqual(h.update(1,now:11),1)
        XCTAssertNil(h.update(2,now:13.1));XCTAssertNil(h.update(nil,now:14))
        XCTAssertNil(h.update(2,now:17));XCTAssertEqual(h.update(2,now:20),2)
    }
    func testNightHeronWatchAndBriefActions() {
        XCTAssertEqual(SpeciesBehavior.frame(.nightHeron,age:12),"stand")
        XCTAssertEqual(SpeciesBehavior.frame(.nightHeron,age:21),"stretch")
        XCTAssertTrue(SpeciesBehavior.frame(.nightHeron,age:31.4)!.hasPrefix("poop"))
        XCTAssertEqual(SpeciesBehavior.frame(.nightHeron,age:33),"stand")
        XCTAssertGreaterThanOrEqual(SpeciesCatalog.standard.profile(.nightHeron).perchMin,53)
    }
    func testSidePerchTracksResizeAndFacesHost() {
        let host=Surface(id:1,rect:CGRect(x:300,y:100,width:500,height:600))
        let bird=Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(.greatSpottedWoodpecker))
        bird.edge = .right;bird.perch(on:host)
        XCTAssertEqual(bird.position,CGPoint(x:800,y:400));XCTAssertFalse(bird.facingRight)
        var resized=host;resized.rect.size.width+=30
        bird.updateHost(surfaces:[resized],sampleDT:0.033)
        XCTAssertEqual(bird.position.x,830);XCTAssertEqual(bird.state,.perched)
        bird.tick(4.2);XCTAssertTrue(bird.frameName.hasPrefix("peck"))
        bird.fly(to:CGPoint(x:830,y:200),host:resized);XCTAssertNil(bird.depthID)
    }
    func testSideRangesRejectOcclusionAndReserveSpace() {
        let host=Surface(id:1,rect:CGRect(x:300,y:100,width:500,height:600))
        let cover=Surface(id:2,rect:CGRect(x:250,y:200,width:100,height:180))
        let screen=CGRect(x:0,y:0,width:1200,height:900)
        let ranges=Geometry.sideRanges(on:host,edge:.left,surfaces:[cover,host],screen:screen,scale:1,occupied:[])
        XCTAssertFalse(ranges.isEmpty)
        for r in ranges {for y in stride(from:r.lowerBound+0.1,to:r.upperBound,by:5) {
            XCTAssertFalse(Geometry.landingFootprint(at:CGPoint(x:300,y:y),scale:1).intersects(cover.rect))
        }}
        XCTAssertTrue(Geometry.sideRanges(on:host,edge:.left,surfaces:[host],screen:screen,scale:1,occupied:[host.rect.insetBy(dx:-100,dy:-100)]).isEmpty)
    }
}
