import XCTest
@testable import BirdingCore

enum CourtshipTestSupport {
    static let species:SpeciesID = .spottedDove
    static let dedicated:Set<String>=["courtRaise","courtBow0","courtBow1","courtBowRecover","courtObserve"]
    static let frames:Set<String>=dedicated.union(["stand","blink","land0","land1","land2"]+(0..<8).map{"fly\($0)"})
    // Sample inside every authored stage, including each of the two bow cycles.
    static let stages:[Double]=[0.2,0.65,1.4,2.4,3.15,3.7]
    static func settings()->BirdSettings {
        var s=BirdSettings();s.perchActions=false;s.passiveAttentionEnabled=false
        s.pointerVisits=false;s.flockPasses=false;s.ambientLeafPlayEnabled=false
        s.ambientFrequency = .high;return s
    }
    static func engine(scale:CGFloat=1,negative:Bool=false,right:Bool=true,ground:Bool=false,
                       gap:CGFloat?=nil,quiet:Double=10.1,residents:Int=2,seed:UInt64=2701,
                       species:[SpeciesID]=[.spottedDove,.spottedDove],hz:Int=60)->BehaviorEngine {
        let s=settings(),e=BehaviorEngine(seed:seed,settings:s)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let dx:CGFloat=negative ? -3000*scale:0,dy:CGFloat=negative ? -2600*scale:0
        let screen=CGRect(x:dx,y:dy,width:2400*scale,height:2200*scale)
        let host=Surface(id:2701,pid:42,rect:CGRect(x:200*scale+dx,y:1700*scale+dy,width:2000*scale,height:180*scale),isGround:ground)
        let size=scale*s.catalog.profile(.spottedDove).relativeScale
        let separation=gap ?? (58*size+60*scale)
        let xs:[CGFloat]=right ? [800*scale+dx,800*scale+dx+separation]:[1400*scale+dx,1400*scale+dx-separation]
        var surfaces=[host],birds:[Bird]=[]
        for (index,kind) in species.enumerated() {
            let x=xs[index%2]
            let bird=Bird(position:.zero,fraction:(x-Geometry.perchX(0,rect:host.rect))/(host.rect.width-84),
                profile:s.catalog.profile(kind),random:{0.5})
            bird.perch(on:host,spriteScale:scale*bird.profile.relativeScale)
            bird.perchDuration=3600;bird.facingRight=right;birds.append(bird)
        }
        for index in 0..<max(0,residents-birds.count) {
            let row=index/8,column=index%8
            let support=Surface(id:UInt32(2800+row),pid:43,
                rect:CGRect(x:100*scale+dx,y:CGFloat(120+row*90)*scale+dy,width:2200*scale,height:40*scale))
            if column==0 {surfaces.append(support)}
            let bird=Bird(position:.zero,fraction:CGFloat(column+1)/9,
                profile:s.catalog.profile(.yellowBrowedWarbler),random:{0.5})
            bird.perch(on:support,spriteScale:scale*bird.profile.relativeScale)
            bird.perchDuration=3600;birds.append(bird)
        }
        e.updateWorld(.init(screens:[screen],displays:[screen],surfaces:surfaces,scale:scale,
            pointer:CGPoint(x:20*scale+dx,y:20*scale+dy),
            availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)}),displayIDs:["court-display"]))
        e.installFixtureBirds(birds);advance(e,quiet,hz:hz);return e
    }
    static func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    static func start(_ e:BehaviorEngine,source:BehaviorSource = .preview,
                      file:StaticString=#filePath,line:UInt=#line)throws->BehaviorRunID {
        let result=e.handle(.courtshipDisplay(source))
        guard case .started(let run)=result else {
            XCTFail("Real courtship command must start: \(result)",file:file,line:line)
            throw NSError(domain:"CourtshipTests",code:1)
        }
        return run
    }
    static func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID)->[BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    static func clean(_ e:BehaviorEngine,_ run:BehaviorRunID,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertNil(e.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(terminals(e,run).count,1,file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line)
        XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertEqual(e.habitatReservationCount,0,file:file,line:line)
        XCTAssertTrue(e.runtime.giftReceiverReservations.isEmpty,file:file,line:line)
        XCTAssertTrue(e.runtime.propIDs.isEmpty,file:file,line:line)
        XCTAssertTrue(e.propSnapshot().isEmpty,file:file,line:line)
        XCTAssertFalse(e.ambientBusy,file:file,line:line)
    }
}
