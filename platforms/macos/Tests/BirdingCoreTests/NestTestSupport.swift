import XCTest
@testable import BirdingCore

enum NestTestSupport {
    static let species:SpeciesID = .spottedDove
    static let carry:Set<String>=["carryLook","carryLower","carryGrip","carryPlace"]
    static let build:Set<String>=["nestPlace","nestAdjust0","nestAdjust1","nestSettle"]
    static let common=Set(["stand","blink","land0","land1","land2"]+(0..<8).map{"fly\($0)"})
    static let frames=common.union(carry).union(build)
    static func settings()->BirdSettings {
        var s=BirdSettings();s.perchActions=false;s.passiveAttentionEnabled=false
        s.pointerVisits=false;s.flockPasses=false;s.socialInteractions=false;s.ambientLeafPlayEnabled=false
        s.ambientFrequency = .high;return s
    }
    static func engine(scale:CGFloat=1,negative:Bool=false,right:Bool=true,ground:Bool=false,
                       screens:Int=1,residents:Int=1,species:SpeciesID? = .spottedDove,
                       seed:UInt64=3701,record:Bool=false)->BehaviorEngine {
        let s=settings(),e=BehaviorEngine(seed:seed,settings:s,recordInputs:record)
        e.populationEnabled=false;e.ambientEnabled=false;e.autonomousRouting=false
        let origin=CGPoint(x:negative ? -10000*scale:0,y:negative ? -6000*scale:0)
        let display=CGRect(x:origin.x,y:origin.y,width:2400*scale,height:2200*scale)
        var displays=[display]
        if screens==4 {
            displays += [display.offsetBy(dx:2500*scale,dy:0),display.offsetBy(dx:0,dy:2300*scale),
                display.offsetBy(dx:2500*scale,dy:2300*scale)]
        }
        let works=displays.map{$0.insetBy(dx:0,dy:0)}
        let host:Surface
        if ground {
            let work=CGRect(x:display.minX,y:display.minY+24*scale,width:display.width,height:display.height-124*scale)
            host=Geometry.ground(id:3701,display:display,workArea:work)
        } else {
            host=Surface(id:3701,pid:42,rect:CGRect(x:origin.x+200*scale,y:origin.y+1700*scale,width:2000*scale,height:180*scale))
        }
        var surfaces=[host],birds:[Bird]=[]
        if let species {
            let x=origin.x+(right ? 550:1900)*scale
            let fraction=(x-Geometry.perchX(0,rect:host.rect))/(host.rect.width-84)
            let bird=Bird(position:.zero,fraction:fraction,profile:s.catalog.profile(species),random:{0.5})
            bird.perch(on:host,spriteScale:scale*bird.profile.relativeScale);bird.perchDuration=3600
            bird.facingRight=right;birds.append(bird)
        }
        for index in 0..<max(0,residents-birds.count) {
            let row=index/8,column=index%8
            let support=Surface(id:UInt32(3800+row),pid:43,
                rect:CGRect(x:origin.x+100*scale,y:origin.y+CGFloat(120+row*90)*scale,width:2200*scale,height:40*scale))
            if column==0 {surfaces.append(support)}
            let bird=Bird(position:.zero,fraction:CGFloat(column+1)/9,
                profile:s.catalog.profile(.yellowBrowedWarbler),random:{0.5})
            bird.perch(on:support,spriteScale:scale*bird.profile.relativeScale);bird.perchDuration=3600;birds.append(bird)
        }
        var workAreas=works
        if ground {workAreas[0]=CGRect(x:display.minX,y:display.minY+24*scale,width:display.width,height:display.height-124*scale)}
        e.updateWorld(.init(screens:workAreas,displays:displays,surfaces:surfaces,scale:scale,
            pointer:CGPoint(x:origin.x+20*scale,y:origin.y+20*scale),
            availableFrames:Dictionary(uniqueKeysWithValues:SpeciesID.allCases.map{($0,frames)}),
            displayIDs:displays.indices.map{"nest-display-\($0)"}))
        if !birds.isEmpty {e.installFixtureBirds(birds)}
        advance(e,10.1);return e
    }
    static func point(_ e:BehaviorEngine)->CGPoint {
        let host=e.world.surfaces.first{$0.id==3701}!,scale=e.world.scale
        let x=e.world.displays[0].minX+1400*scale
        let fraction=(x-Geometry.perchX(0,rect:host.rect))/(host.rect.width-84)
        // A 48pt nest canvas has 24pt below contact; ground must leave that
        // complete user object in the physical display, beyond the 9pt tail.
        let supportScale=host.isGround ? max(scale*8/3,scale*e.settings.catalog.profile(species).relativeScale):scale
        return Geometry.foot(on:host,fraction:fraction,edge:.top,scale:supportScale)
    }
    static func prepared(scale:CGFloat=1,negative:Bool=false,right:Bool=true,ground:Bool=false,
                         screens:Int=1,residents:Int=1,seed:UInt64=3701)throws->BehaviorEngine {
        let e=engine(scale:scale,negative:negative,right:right,ground:ground,screens:screens,residents:residents,seed:seed)
        var placement=point(e)
        // Put the leftward workload near the real host's left edge. Its tray
        // must use the production right-side fallback, without injecting state.
        if !right {placement.x=e.world.displays[0].minX+(ground ? 100:300)*scale}
        XCTAssertEqual(e.handle(.placeNest(at:placement)),.accepted)
        _=try nest(e);return e
    }
    static func advance(_ e:BehaviorEngine,_ seconds:Double,hz:Int=60) {
        for _ in 0..<Int((seconds*Double(hz)).rounded()) {e.advance(1/Double(hz))}
    }
    static func start(_ e:BehaviorEngine,build:Bool=false,source:BehaviorSource = .preview,
                      file:StaticString=#filePath,line:UInt=#line)throws->BehaviorRunID {
        let result=e.handle(build ? .nestBuild(source):.nestMaterialCarry(source))
        guard case .started(let run)=result else {
            XCTFail("Real nest command must start: \(result)",file:file,line:line)
            throw NSError(domain:"NestTests",code:1)
        }
        return run
    }
    static func nest(_ e:BehaviorEngine)throws->NestSnapshot {try XCTUnwrap(e.nestSnapshot().first)}
    static func material(_ e:BehaviorEngine,_ id:ScenePropID)throws->NestMaterialSnapshot {
        try XCTUnwrap(try nest(e).materials.first{$0.id==id})
    }
    static func tokens(_ e:BehaviorEngine)->[ScenePropRenderState] {e.propSnapshot().filter{$0.kind == .twigToken}}
    static func terminals(_ e:BehaviorEngine,_ run:BehaviorRunID)->[BehaviorEvent] {
        e.events.filter{$0.runID==run && [.completed,.cancelled,.failed].contains($0.type)}
    }
    static func until(_ e:BehaviorEngine,_ run:BehaviorRunID,limit:Double=36,
                      file:StaticString=#filePath,line:UInt=#line,_ condition:()->Bool)throws {
        for _ in 0..<Int(limit*60) {
            if condition() {return}
            guard e.runtime.runs[run] != nil else {break}
            e.advance(BehaviorEngine.step)
        }
        XCTFail("Nest boundary not reached: \(terminals(e,run))",file:file,line:line)
        throw NSError(domain:"NestTests",code:2)
    }
    static func finish(_ e:BehaviorEngine,_ run:BehaviorRunID,hz:Int=60) {
        for _ in 0..<36*hz {if e.runtime.runs[run]==nil {return};e.advance(1/Double(hz))}
        XCTFail("Nest run exceeded its hard deadline")
    }
    static func released(_ e:BehaviorEngine,_ run:BehaviorRunID,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertNil(e.runtime.runs[run],file:file,line:line)
        XCTAssertFalse(e.runtime.owners.values.contains(run),file:file,line:line)
        XCTAssertEqual(terminals(e,run).count,1,file:file,line:line)
        XCTAssertEqual(e.leasedBirdCount,0,file:file,line:line);XCTAssertEqual(e.reservedLandingCount,0,file:file,line:line)
        XCTAssertEqual(e.habitatReservationCount,0,file:file,line:line);XCTAssertFalse(e.ambientBusy,file:file,line:line)
        XCTAssertTrue(e.runtime.propIDs.isEmpty,file:file,line:line)
        XCTAssertTrue(e.runtime.giftReceiverReservations.isEmpty,file:file,line:line)
        XCTAssertNil(e.giftAuthorizationRequest,file:file,line:line);XCTAssertEqual(e.activeGiftAuthorizationCount,0,file:file,line:line)
        for nest in e.nestSnapshot() {
            XCTAssertNil(nest.reservation,file:file,line:line)
            XCTAssertTrue(nest.materials.allSatisfy{$0.owner==nil && $0.reservedByRun==nil},file:file,line:line)
        }
    }
    static func conserved(_ e:BehaviorEngine,ids:Set<ScenePropID>,file:StaticString=#filePath,line:UInt=#line) throws {
        let nest=try nest(e)
        XCTAssertEqual(nest.materials.count,3,file:file,line:line)
        XCTAssertEqual(Set(nest.materials.map(\.id)),ids,file:file,line:line)
        XCTAssertEqual(nest.available+nest.attached+nest.delivered+nest.arranged+nest.spent,3,file:file,line:line)
        XCTAssertEqual(nest.progress,nest.arranged,file:file,line:line)
        XCTAssertLessThanOrEqual(nest.attached,1,file:file,line:line)
        let tokens=tokens(e)
        XCTAssertEqual(Set(tokens.map(\.id)).count,tokens.count,file:file,line:line)
        XCTAssertTrue(Set(tokens.map(\.id)).isSubset(of:ids),file:file,line:line)
        XCTAssertTrue(e.carriedObjectSnapshot().isEmpty,file:file,line:line)
    }
    static func clear(_ e:BehaviorEngine) {
        XCTAssertEqual(e.handle(.removeNest),.accepted);advance(e,2.25)
        XCTAssertTrue(e.nestSnapshot().isEmpty);XCTAssertTrue(e.habitatSnapshot().isEmpty)
        XCTAssertTrue(tokens(e).isEmpty);XCTAssertNil(e.sceneFocus)
        XCTAssertFalse(e.world.surfaces.contains{$0.habitatKind == .nest})
    }
    static func deliver(_ e:BehaviorEngine)throws->BehaviorRunID {
        let run=try start(e);finish(e,run);released(e,run)
        XCTAssertEqual(terminals(e,run).map(\.type),[.completed])
        // A separate visit still requires one real settled second; preview
        // bypasses cooldown, not the ordinary-resident admission rule.
        advance(e,1.1);return run
    }
}
