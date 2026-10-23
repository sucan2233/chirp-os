import Foundation
import XCTest
@testable import BirdingCore

final class ActivityRhythmTests:XCTestCase {
    private let id=BirdID(1)
    private let still=BirdStimulus(near:false,inAttentionRange:false,fastPass:false,click:false)

    func testModesHaveStableJSONNames() throws {
        XCTAssertEqual(ActivityRhythmMode.allCases.map(\.rawValue),["steady","localDayNight","quiet"])
        for mode in ActivityRhythmMode.allCases {
            let data=try JSONEncoder().encode(mode)
            XCTAssertEqual(String(data:data,encoding:.utf8),"\"\(mode.rawValue)\"")
            XCTAssertEqual(try JSONDecoder().decode(ActivityRhythmMode.self,from:data),mode)
        }
    }

    func testSteadyAndQuietIgnoreClockAndSpecies() {
        let minutes:[Int?]=[nil,Int.min,-1,0,360,480,720,1080,1320,1439,1440,Int.max]
        for minute in minutes {
            XCTAssertEqual(ActivityRhythmPolicy.ambientRate(mode:.steady,minute:minute),1)
            XCTAssertEqual(ActivityRhythmPolicy.ambientRate(mode:.quiet,minute:minute),0)
            for species in SpeciesID.allCases {
                XCTAssertEqual(ActivityRhythmPolicy.restRate(mode:.steady,minute:minute,species:species),1)
                XCTAssertEqual(ActivityRhythmPolicy.restRate(mode:.quiet,minute:minute,species:species),1.6)
            }
        }
    }

    func testMissingAndInvalidLocalMinutesReturnNeutralRates() {
        let minutes:[Int?]=[nil,Int.min,-1440,-1,1440,1441,Int.max]
        for minute in minutes {
            XCTAssertEqual(ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute),1)
            for species in SpeciesID.allCases {
                XCTAssertEqual(ActivityRhythmPolicy.restRate(mode:.localDayNight,minute:minute,species:species),1)
            }
        }
    }

    func testLocalDayNightPlateausAndSmoothstepSamples() {
        for minute in Array(0...360)+Array(1320..<1440) {
            XCTAssertEqual(ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute),0.35)
        }
        for minute in 480...1080 {
            XCTAssertEqual(ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute),1)
        }
        let samples:[(Int,Double)]=[(390,0.15625),(420,0.5),(450,0.84375),
            (1140,0.84375),(1200,0.5),(1260,0.15625)]
        for (minute,day) in samples {
            XCTAssertEqual(ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute),
                0.35+0.65*day,accuracy:1e-12)
            XCTAssertEqual(ActivityRhythmPolicy.restRate(mode:.localDayNight,minute:minute,species:.treeSparrow),
                1+0.6*(1-day),accuracy:1e-12)
            XCTAssertEqual(ActivityRhythmPolicy.restRate(mode:.localDayNight,minute:minute,species:.nightHeron),
                1+0.6*day,accuracy:1e-12)
        }
    }

    func testLocalRatesStayBoundedAndContinuousIncludingMidnight() {
        for minute in 0..<1440 {
            let next=(minute+1)%1440
            let ambient=ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute)
            XCTAssertTrue((0.35...1).contains(ambient))
            XCTAssertLessThan(abs(ambient-ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:next)),0.009)
            for species:SpeciesID in [.treeSparrow,.nightHeron,.collaredScopsOwl] {
                let rest=ActivityRhythmPolicy.restRate(mode:.localDayNight,minute:minute,species:species)
                XCTAssertTrue((1...1.6).contains(rest))
                XCTAssertLessThan(abs(rest-ActivityRhythmPolicy.restRate(mode:.localDayNight,minute:next,species:species)),0.009)
            }
        }
        // A smoothstep joins each plateau with a flat slope, sampled in minutes.
        for boundary in [360,480,1080,1320] {
            let center=ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:boundary)
            for minute in [boundary-1,boundary+1] {
                XCTAssertLessThan(abs(center-ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute)),0.00015)
            }
        }
        for minute in 360..<480 {
            XCTAssertLessThan(ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute),
                ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute+1))
        }
        for minute in 1080..<1320 {
            XCTAssertGreaterThan(ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute),
                ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:minute+1))
        }
        XCTAssertEqual(ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:1439),
            ActivityRhythmPolicy.ambientRate(mode:.localDayNight,minute:0))
    }

    func testOnlySelectedSpeciesReverseProductRestSchedule() {
        for species in SpeciesID.allCases {
            let reversed=species == .nightHeron || species == .collaredScopsOwl
            for minute in [0,359,360,420,480,720,1080,1200,1320,1439] {
                let reference=ActivityRhythmPolicy.restRate(mode:.localDayNight,minute:minute,species:.treeSparrow)
                let rest=ActivityRhythmPolicy.restRate(mode:.localDayNight,minute:minute,species:species)
                XCTAssertEqual(rest,reversed ? 2.6-reference:reference,accuracy:1e-12)
            }
            XCTAssertEqual(ActivityRhythmPolicy.restRate(mode:.localDayNight,minute:720,species:species),reversed ? 1.6:1)
            for minute in [1439,0,360,1320] {
                XCTAssertEqual(ActivityRhythmPolicy.restRate(mode:.localDayNight,minute:minute,species:species),reversed ? 1:1.6)
            }
        }
    }

    func testNewSettingsDefaultToSteadyWithoutSchemaBump() throws {
        let settings=BirdSettings(),object=try settingsObject(settings)
        XCTAssertEqual(settings.activityRhythm,.steady)
        XCTAssertEqual(BirdSettings.currentSchemaVersion,1)
        XCTAssertEqual(settings.schemaVersion,1)
        XCTAssertEqual(object["schemaVersion"] as? Int,1)
        XCTAssertEqual(object["activityRhythm"] as? String,"steady")
    }

    func testMissingOrNullRhythmMigratesToSteadyForEverySupportedSchema() throws {
        let original=configuredSettings()
        for version:Int? in [nil,0,1] {
            for nullValue in [false,true] {
                var object=try settingsObject(original)
                if let version {object["schemaVersion"]=version}
                else {object.removeValue(forKey:"schemaVersion")}
                if nullValue {object["activityRhythm"]=NSNull()}
                else {object.removeValue(forKey:"activityRhythm")}
                let data=try JSONSerialization.data(withJSONObject:object)
                for migrated in [try JSONDecoder().decode(BirdSettings.self,from:data),try BirdSettings.decode(data)] {
                    XCTAssertEqual(migrated.activityRhythm,.steady)
                    XCTAssertEqual(migrated.schemaVersion,1)
                    try assertOtherSettingsEqual(migrated,original)
                }
            }
        }
    }

    func testAllRhythmsRoundTripIndependentlyOfOtherSettings() throws {
        for mode in ActivityRhythmMode.allCases {
            var original=configuredSettings();original.activityRhythm=mode
            let data=try JSONEncoder().encode(original)
            for decoded in [try JSONDecoder().decode(BirdSettings.self,from:data),try BirdSettings.decode(data)] {
                XCTAssertEqual(decoded.activityRhythm,mode)
                XCTAssertEqual(decoded.schemaVersion,1)
                XCTAssertEqual(try settingsObject(decoded)["activityRhythm"] as? String,mode.rawValue)
                try assertOtherSettingsEqual(decoded,original)
            }
        }
    }

    func testInvalidRhythmEnumAndTypesAreRejectedByBothDecoders() throws {
        let invalid:[Any]=["","Steady","dayNight","futureMode",0,1,true,[],["mode":"quiet"]]
        for value in invalid {
            var object=try settingsObject(configuredSettings());object["activityRhythm"]=value
            let data=try JSONSerialization.data(withJSONObject:object)
            XCTAssertThrowsError(try JSONDecoder().decode(BirdSettings.self,from:data))
            XCTAssertThrowsError(try BirdSettings.decode(data))
        }
    }

    func testSteadyRatePreservesDefaultPlannerSequenceAndRandomPlans() throws {
        let bird=perchedBird(),implicit=planner(bird),explicit=planner(bird)
        let first=try XCTUnwrap(implicit.rhythms[id]),second=try XCTUnwrap(explicit.rhythms[id])
        let rate=ActivityRhythmPolicy.restRate(mode:.steady,minute:nil,species:bird.profile.id)
        var rests=0
        for _ in 0..<480 {
            let action=implicit.candidate(id,bird:bird,dt:0.25,enabled:true,occupied:false,quiet:true)
            let other=explicit.candidate(id,bird:bird,dt:0.25,enabled:true,occupied:false,quiet:true,restRate:rate)
            XCTAssertEqual(action,other)
            XCTAssertEqual(first.quiet,second.quiet);XCTAssertEqual(first.nextRest,second.nextRest)
            XCTAssertEqual(first.landingAge,second.landingAge)
            XCTAssertEqual(first.pendingPreen,second.pendingPreen)
            if let action {
                rests+=1
                let plan=try XCTUnwrap(implicit.plan(action,for:id)),otherPlan=try XCTUnwrap(explicit.plan(action,for:id))
                XCTAssertEqual(plan.kind,otherPlan.kind);XCTAssertEqual(plan.duration,otherPlan.duration)
                XCTAssertEqual(plan.rate,otherPlan.rate)
            }
        }
        XCTAssertGreaterThan(rests,1)
    }

    func testQuietRateAccumulatesRestEarlierWithoutChangingThreshold() throws {
        let bird=perchedBird(),steady=planner(bird),quiet=planner(bird)
        let normal=try XCTUnwrap(steady.rhythms[id]),faster=try XCTUnwrap(quiet.rhythms[id])
        let threshold=normal.nextRest
        XCTAssertEqual(faster.nextRest,threshold)
        let rate=ActivityRhythmPolicy.restRate(mode:.quiet,minute:nil,species:bird.profile.id)
        let elapsed=threshold/rate+0.001
        XCTAssertNil(steady.candidate(id,bird:bird,dt:elapsed,enabled:true,occupied:false,quiet:true))
        XCTAssertEqual(quiet.candidate(id,bird:bird,dt:elapsed,enabled:true,occupied:false,quiet:true,restRate:rate),.rest)
        XCTAssertEqual(normal.quiet,elapsed,accuracy:1e-12)
        XCTAssertEqual(normal.nextRest,threshold)
        XCTAssertEqual(faster.quiet,0)
        XCTAssertEqual(steady.candidate(id,bird:bird,dt:threshold-elapsed+0.001,enabled:true,occupied:false,quiet:true),.rest)
        XCTAssertEqual(normal.nextRest,faster.nextRest,"The rate must not consume or change scheduling RNG")
    }

    func testRestRateDoesNotAccelerateLandingPreenOrItsExpiry() throws {
        for rate in [1.0,1.6] {
            let bird=perchedBird(),planner=self.planner(bird),rhythm=try XCTUnwrap(planner.rhythms[id])
            rhythm.pendingPreen=true;rhythm.nextRest=100
            let delay=rhythm.landingDelay
            XCTAssertNil(planner.candidate(id,bird:bird,dt:delay*0.75,enabled:true,occupied:false,quiet:true,restRate:rate))
            XCTAssertEqual(rhythm.landingAge,delay*0.75,accuracy:1e-12)
            XCTAssertTrue(rhythm.pendingPreen)
            XCTAssertEqual(rhythm.quiet,delay*0.75*rate,accuracy:1e-12)
            XCTAssertEqual(planner.candidate(id,bird:bird,dt:delay*0.25+1e-9,enabled:true,occupied:false,quiet:true,restRate:rate),.preen)
            XCTAssertEqual(rhythm.landingAge,delay+1e-9,accuracy:1e-12)

            rhythm.pendingPreen=true;rhythm.landingAge=0
            XCTAssertNil(planner.candidate(id,bird:bird,dt:2.49,enabled:true,occupied:true,quiet:true,restRate:rate))
            XCTAssertTrue(rhythm.pendingPreen);XCTAssertEqual(rhythm.landingAge,2.49,accuracy:1e-12)
            XCTAssertNil(planner.candidate(id,bird:bird,dt:0.02,enabled:true,occupied:true,quiet:true,restRate:rate))
            XCTAssertFalse(rhythm.pendingPreen);XCTAssertEqual(rhythm.landingAge,2.51,accuracy:1e-12)
        }
    }

    func testRestRateDoesNotAccelerateCooldownOrQuietTime() throws {
        for rate in [1.0,1.6] {
            let bird=perchedBird(),planner=self.planner(bird),rhythm=try XCTUnwrap(planner.rhythms[id])
            planner.didStart(id,kind:.rest);planner.didFinish(id,kind:.rest)
            let cooldown=try XCTUnwrap(rhythm.cooldowns[.rest])
            rhythm.nextRest=1
            planner.observe(id,stimulus:still,dt:cooldown-0.5)
            XCTAssertEqual(try XCTUnwrap(rhythm.cooldowns[.rest]),0.5,accuracy:1e-12)
            XCTAssertEqual(rhythm.quietTime,cooldown-0.5,accuracy:1e-12)
            XCTAssertNil(planner.candidate(id,bird:bird,dt:1,enabled:true,occupied:false,quiet:true,restRate:rate))
            XCTAssertEqual(rhythm.quiet,rate,accuracy:1e-12)
            XCTAssertEqual(try XCTUnwrap(rhythm.cooldowns[.rest]),0.5,accuracy:1e-12)
            XCTAssertEqual(rhythm.quietTime,cooldown-0.5,accuracy:1e-12)
            planner.observe(id,stimulus:still,dt:0.5)
            XCTAssertNil(rhythm.cooldowns[.rest])
            XCTAssertEqual(planner.candidate(id,bird:bird,dt:0,enabled:true,occupied:false,quiet:true,restRate:rate),.rest)
        }
    }

    func testQuietRateStillHonorsPerchEligibilityGates() throws {
        for gate in ["disabled","occupied","disturbed"] {
            let bird=perchedBird(),planner=self.planner(bird),rhythm=try XCTUnwrap(planner.rhythms[id])
            rhythm.nextRest=1;rhythm.quiet=0.5
            XCTAssertNil(planner.candidate(id,bird:bird,dt:10,enabled:gate != "disabled",
                occupied:gate == "occupied",quiet:gate != "disturbed",restRate:1.6))
            XCTAssertEqual(rhythm.quiet,0)
        }
    }

    private func perchedBird() -> Bird {
        let bird=Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(.treeSparrow),random:{0.5})
        bird.perch(on:Surface(id:71,rect:CGRect(x:0,y:800,width:1200,height:400)))
        bird.perchDuration=600
        return bird
    }

    private func planner(_ bird:Bird) -> PerchActivityPlanner {
        let planner=PerchActivityPlanner(seed:73);planner.register(id,bird:bird)
        return planner
    }

    private func configuredSettings() -> BirdSettings {
        var settings=BirdSettings();settings.activityRhythm = .quiet
        settings.hoverDelay=0.25;settings.pointerVisits=false;settings.pointerFollowEnabled=true
        settings.flockPasses=false;settings.socialInteractions=false;settings.perchActions=false
        settings.passiveAttentionEnabled=false;settings.sideHopEnabled=false;settings.takeoffPreparationEnabled=false
        settings.leafPlayEnabled=false;settings.ambientLeafPlayEnabled=false;settings.visitorMemoryEnabled=false
        settings.ambientFrequency = .high;settings.catalog.species[0].speed=1.25
        settings.probabilities.adjust(at:0,to:1234);settings.probabilities.setLocked(true,at:0)
        settings.pendingSpecies=[.nightHeron]
        return settings
    }

    private func settingsObject(_ settings:BirdSettings) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
    }

    private func assertOtherSettingsEqual(_ actual:BirdSettings,_ expected:BirdSettings,
                                          file:StaticString=#filePath,line:UInt=#line) throws {
        var actualObject=try settingsObject(actual),expectedObject=try settingsObject(expected)
        actualObject.removeValue(forKey:"activityRhythm");expectedObject.removeValue(forKey:"activityRhythm")
        XCTAssertTrue(NSDictionary(dictionary:actualObject).isEqual(to:expectedObject),file:file,line:line)
    }
}
