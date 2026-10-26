import AppKit
import BirdingCore
import Darwin

/// Explicit, headless acceptance workload. The identical instrumentation can be
/// compiled into a baseline checkout without changing its product behavior.
/// This does not measure WindowServer composition or real desktop input latency.
enum MotionBenchmark {
    private static let species: [SpeciesID] = [
        .treeSparrow,.redWhiskeredBulbul,.spottedDove,.yellowRumpedFlycatcher,
        .blackDrongo,.greyHeron,.whimbrel,.commonMoorhen,
        .commonBuzzard,.collaredScopsOwl,.hoopoe,.commonKingfisher
    ]
    private static func cpuSeconds() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }
    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size):0
    }
    static func run(to url: URL) -> Int32 {
        do {
            let beforeArt = residentBytes(), loadStart = cpuSeconds()
            // Match the application's eager all-species artwork cache in both builds.
            let arts = Dictionary(uniqueKeysWithValues: SpeciesCatalog.standard.species.map {
                ($0.id, BirdArt(species: $0.id))
            })
            let artCPU = cpuSeconds() - loadStart, afterArt = residentBytes()
            var settings = BirdSettings()
            settings.pointerVisits = false; settings.flockPasses = false
            settings.socialInteractions = false; settings.ambientLeafPlayEnabled = false
            settings.edgePeekEnabled = false; settings.sideHopEnabled = false
            settings.passiveAttentionEnabled = false
            let engine = BehaviorEngine(seed: 73, settings: settings)
            engine.populationEnabled = false; engine.ambientEnabled = false; engine.autonomousRouting = false
            let screen = CGRect(x:0,y:0,width:2400,height:1800)
            let hosts = species.indices.map { index in
                Surface(id:UInt32(700+index),pid:31,
                    rect:CGRect(x:CGFloat(50+(index%4)*590),y:CGFloat(450+(index/4)*500),width:540,height:120))
            }
            engine.updateWorld(BehaviorWorld(screens:[screen],displays:[screen],surfaces:hosts,scale:1,
                pointer:CGPoint(x:0,y:0),availableFrames:arts.mapValues{Set($0.frames.keys)}))
            let birds = zip(species,hosts).map { id, host in
                let bird = Bird(position:.zero,fraction:0.5,profile:SpeciesCatalog.standard.profile(id),random:{0.5})
                bird.perch(on:host,spriteScale:engine.spriteScale(for:bird));bird.perchDuration=10_000
                return bird
            }
            engine.installFixtureBirds(birds)
            guard let context = CGContext(data:nil,width:2400,height:1800,bitsPerComponent:8,bytesPerRow:0,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw NSError(domain:"MotionBenchmark",code:1)
            }
            context.interpolationQuality = .none
            var cpuSamples:[Double]=[], memorySamples:[UInt64]=[], checksum=0
            // 10 seconds warmup, then 120 simulated seconds at 60 Hz. No sleeping
            // or input/desktop manipulation; draw the production cached sprites.
            for tick in 0..<7800 {
                let begin = cpuSeconds()
                autoreleasepool {
                    engine.advance(1.0/60)
                    context.clear(CGRect(x:0,y:0,width:2400,height:1800))
                    let rows=engine.renderSnapshot()
                    checksum += rows.count
                    for row in rows {
                        arts[row.species]?.draw(name:row.frameName,at:CGPoint(x:row.position.x,y:row.position.y+row.hopOffset*row.scale),
                            scale:row.scale,
                            right:row.facingRight,context:context)
                    }
                }
                if tick >= 600 {cpuSamples.append((cpuSeconds()-begin)*1000)}
                if tick >= 600 && tick % 600 == 0 {memorySamples.append(residentBytes())}
            }
            let sorted=cpuSamples.sorted()
            let result:[String:Any] = [
                "schemaVersion":1,"seed":73,"species":species.map(\.rawValue),"birdCount":12,
                "warmupSeconds":10,"sampleSeconds":120,"callbackHz":60,"samples":sorted.count,
                "cpuClock":"CLOCK_PROCESS_CPUTIME_ID","percentileMethod":"nearest rank ceil(0.95*n)-1",
                "cpuFrameP95Milliseconds":sorted[Int(ceil(Double(sorted.count)*0.95))-1],
                "cpuFrameMedianMilliseconds":sorted[sorted.count/2],
                "cpuFrameMeanMilliseconds":sorted.reduce(0,+)/Double(sorted.count),
                "artLoadCPUSeconds":artCPU,"residentBeforeArtBytes":beforeArt,"residentAfterArtBytes":afterArt,
                "residentSamplesBytes":memorySamples,"renderedBirdSamples":checksum,
                "cachedSpecies":arts.count,"cachedFrames":arts.values.reduce(0){$0+$1.frames.count},
                "scope":"fixed 12-bird engine + offscreen CGContext draw with full catalog cache; excludes real compositor, sleep/wake and window following"
            ]
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic)
            print("Motion benchmark: \(sorted.count) frames, p95 \(sorted[Int(ceil(Double(sorted.count)*0.95))-1])ms CPU")
            return 0
        } catch {fputs("Motion benchmark: \(error)\n",stderr);return 1}
    }
}
