import Foundation
import BirdingCore

/// Declarative current-engine scenarios, independent of saved recording files.
/// Never load an old log and change its simulationVersion. Capture new expected
/// output for regression; BirdingCoreTests independently asserts scene semantics.
enum SharedBehaviorExport {
    private typealias Object = [String:Any]
    private static let flight = (0...7).map {"fly\($0)"} + (0...2).map {"land\($0)"}
    private static let common = ["stand","blink","preen0","preen1","idle0","idle1","idle2"] + flight
    private static let carry = ["carryLook","carryLower","carryGrip","carryPlace"]
    private static let catchFrames = ["stand","blink"] + flight + (0...2).map {"glide\($0)"}
        + (0...2).map {"bank\($0)"} + ["bound","catchOpen","catchClose","catchRecover"]
    private static func point(_ x:Double,_ y:Double)->Object {["x":x,"y":y]}
    private static func rect(_ x:Double,_ y:Double,_ w:Double,_ h:Double)->Object {
        ["x":x,"y":y,"width":w,"height":h]
    }
    private static func surface(_ id:Int,_ x:Double,_ y:Double,_ w:Double,_ h:Double)->Object {
        ["id":id,"pid":42,"layer":0,"isGround":false,"rect":rect(x,y,w,h),
         "canHostBirds":true,"occludesFlight":false]
    }
    private static func bird(_ species:SpeciesID = .treeSparrow,_ host:Int = 61,_ fraction:Double = 0.5,
                             right:Bool = true,origin:Object? = nil,duration:Double = 600)->Object {
        var value:Object=["species":species.rawValue,"host":host,"fraction":fraction,
                          "perchDuration":duration,"facingRight":right]
        value["flightOrigin"]=origin
        return value
    }
    private static func command(_ name:String,_ payload:Object = [:])->Object {
        var value=payload;value["name"]=name
        return ["kind":"command","command":value]
    }
    private static func preview(_ name:String)->Object {command(name,["source":"preview"])}
    private static func advance(_ ticks:Int,hz:Int = 30,ambient:Bool = false)->Object {
        ["kind":"advance","elapsed":1.0/Double(hz),"repeatCount":ticks,
         "options":["population":false,"ambient":ambient,"routing":false]]
    }
    private static func pause(_ flag:Bool)->Object {command("pause",["flag":flag])}
    private struct Scene {
        var name:String
        var seed:UInt64 = 81
        var settings:BirdSettings
        var world:Object
        var birds:[Object]
        var inputs:[Object] = []
        var memory:Object?
        init(_ name:String,species:SpeciesID = .treeSparrow,seed:UInt64 = 81,
             size:(Double,Double) = (1600,1200),host:Object? = nil,frames:[String]? = nil,
             fraction:Double = 0.5,quiet:Bool = false) {
            self.name=name;self.seed=seed
            settings=BirdSettings()
            // Scene admission must not depend on the changing national weights.
            let index=settings.probabilities.entries.firstIndex{$0.id == species}!
            settings.probabilities.adjust(at:index,to:10_000)
            settings.ambientLeafPlayEnabled=false
            settings.pointerFollowEnabled = !quiet
            if quiet {
                settings.perchActions=false;settings.passiveAttentionEnabled=false
                settings.pointerVisits=false;settings.flockPasses=false;settings.socialInteractions=false
            }
            let host=host ?? SharedBehaviorExport.surface(61,100,900,1400,250)
            let screen=SharedBehaviorExport.rect(0,0,size.0,size.1)
            world=["screens":[screen],"displays":[screen],"surfaces":[host],"scale":1,
                   "pointer":quiet ? SharedBehaviorExport.point(20,20):SharedBehaviorExport.point(30,30),"buttonsDown":false,
                   "observationClick":false,"availableFrames":[species.rawValue:frames ?? SharedBehaviorExport.common]]
            birds=[SharedBehaviorExport.bird(species,host["id"] as! Int,fraction)]
        }
        func log() throws -> BehaviorInputLog {
            let config=try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings))
            var envelope:Object=["version":BehaviorInputLog.currentVersion,
                "simulationVersion":BehaviorInputLog.engineVersion,"seed":String(seed),
                "settings":config,"initialWorld":world,"fixtureBirds":birds,"inputs":inputs]
            envelope["initialVisitorMemory"]=memory
            return try BehaviorInputLog.decode(JSONSerialization.data(withJSONObject:envelope))
        }
    }

    /// Writes all 22 scenarios from source. Decoding and cross-rate replay must
    /// succeed for every scenario before any output file is replaced.
    static func export(to folder:URL) throws {
        let scenes=makeScenes()
        var logs:[(String,BehaviorInputLog)]=[]
        for scene in scenes {
            var log=try scene.log()
            let reference=try log.replay(callbackHz:60)
            for hz in [30,120] {
                guard try log.replay(callbackHz:hz)==reference else {
                    throw BehaviorRecordingError.invalid("\(scene.name): \(hz)Hz report differs")
                }
            }
            log.expected=reference
            logs.append((scene.name,log))
        }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for (name,log) in logs {try log.save(to:folder.appendingPathComponent(name+".json"))}
        print("Exported \(logs.count) handwritten scenarios for simulation v\(BehaviorInputLog.engineVersion); semantic acceptance remains in XCTest.")
    }

    private static func makeScenes()->[Scene] {
        var result:[Scene]=[]
        var s=Scene("attention")
        s.inputs=[command("attention",["action":"watch","source":"preview"]),advance(90),
                  command("attention",["action":"alert","source":"preview"]),advance(90)];result.append(s)
        s=Scene("leaf")
        s.inputs=[command("leafPlay",["point":point(800,500),"source":"preview"]),advance(1050)];result.append(s)
        s=Scene("social");s.birds=[bird(.treeSparrow,61,0.44),bird(.treeSparrow,61,0.56)]
        s.inputs=[preview("socialGreeting"),advance(180)];result.append(s)
        s=Scene("interruptions")
        s.inputs=[command("attention",["action":"watch","source":"preview"]),advance(15),pause(true),advance(60),
                  command("pointerClick"),command("relocate",["target":"1"]),advance(300),pause(false),advance(60)];result.append(s)
        s=Scene("side-hop");s.inputs=[advance(60),preview("sideHop"),advance(90)];result.append(s)
        s=Scene("takeoff-preparation");s.inputs=[preview("prepareTakeoff"),advance(600)];result.append(s)
        s=Scene("returning-visitor");s.birds=[];s.world["pointer"]=point(20,20)
        let index=s.settings.catalog.species.firstIndex{$0.id == .treeSparrow}!
        s.settings.catalog.species[index].perchMin=300;s.settings.catalog.species[index].perchMax=600
        s.inputs=[["kind":"visitorMemory","visitorMemory":visitorMemory(seed:"9001",species:.treeSparrow,calm:150)],
                  ["kind":"arrive"],advance(600),command("remove",["target":"1"]),["kind":"arrive"],advance(600)];result.append(s)
        s=Scene("activity-rhythm");s.settings.activityRhythm = .quiet;s.world["localMinuteOfDay"]=1380
        s.inputs=[advance(1800,ambient:true),command("flockPass",["source":"automatic"]),preview("flockPass"),advance(900)];result.append(s)
        s=Scene("edge-peek",host:surface(61,100,900,800,250),fraction:0.1)
        s.inputs=[advance(30),preview("edgePeek"),advance(180),preview("edgePeek"),advance(6),pause(true),advance(60),pause(false),advance(180)];result.append(s)
        s=Scene("chase",host:surface(61,100,900,1400,200));s.world["pointer"]=point(40,40)
        s.birds=[bird(.treeSparrow,61,0.35),bird(.treeSparrow,61,0.55)]
        s.inputs=[advance(30),preview("chase"),advance(600),preview("chase"),advance(6),pause(true),advance(60),pause(false),advance(600)];result.append(s)
        s=Scene("travel-together",size:(1920,1100));s.settings.perchActions=false;s.world["pointer"]=point(40,40)
        s.world["surfaces"]=[surface(71,1640,400,240,160),surface(72,1640,640,240,160)]
        s.birds=[bird(.treeSparrow,71,0.5,origin:point(100,400)),bird(.treeSparrow,72,0.5,origin:point(120,640))]
        s.inputs=[advance(24),preview("travelTogether"),advance(30),pause(true),advance(60),pause(false),advance(600),preview("travelTogether")];result.append(s)
        let preenFrames=["stand"] + flight + ["Give","Receive"].flatMap {role in (0...2).map {"allopreen\(role)\($0)"}}
        s=Scene("allopreening",species:.barnSwallow,host:surface(61,300,450,800,180),frames:preenFrames)
        s.settings.perchActions=false;s.world["pointer"]=point(1400,50)
        s.birds=[bird(.barnSwallow,61,0.2206703910614525),bird(.barnSwallow,61,0.388268156424581)]
        s.inputs=[advance(30),preview("allopreening"),advance(60),pause(true),advance(60),pause(false),advance(300)];result.append(s)
        s=Scene("fixed-perch");s.settings.perchActions=false;s.world["displayIDs"]=["fixture-display"]
        s.settings.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"fixture-display",displayFrame:CGRect(x:0,y:0,width:1600,height:1200),x:0.6875,y:0.375)]
        s.inputs=[advance(60),preview("fixedPerchVisit"),advance(600)];result.append(s)
        for bath in [false,true] {
            let frames=["stand"] + flight + (bath ? ["shake","bathInspect","bathTouch","bathLower","bath0","bath1","bath2","bathRise"]:["feedLook","feedDown0","feedDown1","feedLift"])
            s=Scene(bath ? "bath":"food-tray",seed:bath ? 1614:1414,size:(2000,1400),host:surface(141,200,1050,400,150),frames:frames,quiet:true)
            s.inputs=[advance(bath ? 270:18),command(bath ? "placeBath":"placeFoodTray",["point":point(1300,700)]),
                      preview(bath ? "bathVisit":"foodTrayVisit"),advance(90),pause(true),advance(60),pause(false),advance(1200)];result.append(s)
        }
        s=Scene("leaf-carry",seed:971,size:(2400,1500),host:surface(971,200,1100,2000,180),
                frames:["stand","blink","shake"] + flight + (0...2).map {"glide\($0)"} + (0...2).map {"bank\($0)"} + ["bound"] + carry,fraction:0.15,quiet:true)
        s.inputs=[advance(270),command("placeCarryLeaf",["point":point(1200,1100)]),preview("leafCarry"),advance(15),pause(true),advance(60),pause(false),advance(900),
                  command("placeCarryLeaf",["point":point(700,1100)]),preview("leafCarry"),pause(true),advance(90),command("removeCarryLeaf"),pause(false),advance(600),
                  command("placeCarryLeafAfter",["delay":3]),command("cancelCarryLeafPlacement"),advance(120),command("clearCurrentScene")];result.append(s)
        for flycatcher in [false,true] {
            let species:SpeciesID=flycatcher ? .yellowRumpedFlycatcher:.barnSwallow
            let host=flycatcher ? 2101:1901
            s=Scene(flycatcher ? "flycatcher-insect-catch":"insect-catch",species:species,seed:UInt64(host),size:(2400,2000),
                    host:surface(host,flycatcher ? 200:2000,1650,flycatcher ? 2000:280,180),frames:catchFrames,fraction:flycatcher ? 0.15:0.5,quiet:true)
            let action=command("insectCatch",["species":species.rawValue,"source":"preview"])
            // These scenarios count 60 Hz callbacks: three ticks leave the
            // insect at age 0.05, and six more advance it to age 0.15.
            // The flycatcher must begin at 1s, before its base idle hop starts
            // at 1.5s; the same 60 ticks at 30 Hz reject admission at 2s.
            if flycatcher {
                s.inputs=[advance(60,hz:60),action,advance(3,hz:60),pause(true),advance(120,hz:60),pause(false),advance(1500,hz:60),action,advance(3,hz:60),pause(true),advance(60,hz:60),command("pointerClick"),pause(false),advance(780,hz:60),command("clearInsect"),command("clearCurrentScene")]
            } else {
                s.birds=[bird(species,host,0.5,origin:point(220,1650))]
                s.inputs=[advance(45,hz:60),action,advance(3,hz:60),pause(true),advance(120,hz:60),pause(false),command("pointerClick"),advance(6,hz:60),command("clearInsect"),advance(15,hz:60),action,advance(6,hz:60),pause(true),advance(60,hz:60),pause(false),advance(2100,hz:60),command("cancelInsectCatchPreview"),command("clearCurrentScene")]
            }
            result.append(s)
        }
        s=Scene("visitor-gift",species:.azureWingedMagpie,seed:1971,size:(2400,2200),host:surface(1971,200,1700,2000,180),frames:["stand","blink"] + flight + carry,fraction:0.15,quiet:true)
        s.birds=[bird(.azureWingedMagpie,1971,0.15,duration:3600)]
        s.settings.visitorGiftsEnabled=true;s.world["displayIDs"]=["gift-display"]
        s.settings.fixedPerches=[FixedPerchAnchor(slot:1,displayID:"gift-display",displayFrame:CGRect(x:0,y:0,width:2400,height:2200),x:0.75,y:0.5)]
        s.memory=visitorMemory(seed:"73",species:.azureWingedMagpie,calm:180)
        s.inputs=[advance(270),command("placeCarryLeaf",["point":point(1000,1700)]),preview("visitorGift"),authorization(1),advance(15),pause(true),advance(60),pause(false),advance(1050),command("clearVisitorGift"),
                  command("placeCarryLeaf",["point":point(1000,1700)]),preview("visitorGift"),authorization(2),pause(true),advance(60),command("clearVisitorGift"),pause(false),advance(150),
                  command("placeCarryLeafAfter",["delay":3]),command("cancelCarryLeafPlacement"),command("cancelAmbient",["reason":"sleep"])];result.append(s)
        s=Scene("courtship-display",species:.spottedDove,seed:2701,size:(2400,2200),host:surface(2701,200,1700,2000,180),frames:["stand","blink"] + flight + ["courtRaise","courtBow0","courtBow1","courtBowRecover","courtObserve"],quiet:true)
        s.settings.socialInteractions=true;s.settings.ambientFrequency = .high;s.world["displayIDs"]=["court-display"]
        s.birds=[bird(.spottedDove,2701,0.29123173277661796),bird(.spottedDove,2701,0.395615866388309,right:false)]
        s.inputs=[advance(303),preview("courtshipDisplay"),advance(42),pause(true),advance(60),pause(false),advance(90),advance(303),preview("courtshipDisplay"),advance(21),pause(true),advance(60),command("remove",["target":"1"]),pause(false),advance(30)];result.append(s)
        for build in [false,true] {
            s=Scene(build ? "nest-build":"nest-material-carry",species:.spottedDove,seed:3701,size:(2400,2200),host:surface(3701,200,1700,2000,180),frames:["stand","blink"] + flight + carry + ["nestPlace","nestAdjust0","nestAdjust1","nestSettle"],fraction:0.16075156576200417,quiet:true)
            s.settings.ambientFrequency = .high;s.world["displayIDs"]=["nest-display-0"]
            s.inputs=[advance(303),command("placeNest",["point":point(1400,1700)])]
            if build {
                s.inputs += [preview("nestMaterialCarry"),advance(1200),command("nestBuild",["source":"user"]),advance(15),pause(true),advance(60),pause(false),advance(1050)]
                for _ in 0..<2 {s.inputs += [preview("nestMaterialCarry"),advance(1200),preview("nestBuild"),advance(1050)]}
            } else {
                s.inputs += [command("nestMaterialCarry",["source":"user"]),advance(15),pause(true),advance(60),pause(false),advance(1200),preview("nestMaterialCarry"),advance(6),command("pointerClick"),advance(360)]
            }
            s.inputs += [command("removeNest"),advance(68)];result.append(s)
        }
        return result
    }
    private static func visitorMemory(seed:String,species:SpeciesID,calm:Double)->Object {
        ["version":1,"seed":seed,"nextID":"100","visitOrdinal":"100","profiles":[
            ["id":"99","species":species.rawValue,"seed":"9001","calmSeconds":calm,"visits":2,"lastVisitOrdinal":"100"]]]
    }
    private static func authorization(_ request:Int)->Object {
        let binding:Object=["requestID":String(request),"visitorArchiveSeed":"73","visitorID":"99",
            "birdID":["rawValue":1],"species":"azureWingedMagpie","source":"preview",
            "leafID":["rawValue":request],"receiverSlot":1,"receiverRevision":1]
        let token:Object=["id":"00000000-0000-4000-8000-00000000000\(request)","binding":binding]
        return ["kind":"giftAuthorization","giftAuthorization":["binding":binding,"token":token]]
    }
}
