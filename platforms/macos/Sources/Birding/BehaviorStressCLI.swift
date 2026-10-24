import Foundation
import BirdingCore

/// Explicit, headless diagnostics: no desktop controller or user settings load.
enum BehaviorStressCLI {
    private struct Envelope:Encodable {
        let formatVersion:Int
        let passed:Bool
        let operatingSystem:String
        let processorCount:Int
        let report:BehaviorStress.Report
        let expectedSideHopReproduced:Bool?
    }
    private enum ArgumentError:Error,LocalizedError {
        case invalid(String)
        var errorDescription:String? {
            if case .invalid(let message)=self {return message};return nil
        }
    }

    static func runIfRequested() {
        let args=Array(CommandLine.arguments.dropFirst())
        guard args.contains(where:{$0.hasPrefix("--stress-")}) else {return}
        do {
            let flags:Set<String>=["--stress-behavior","--stress-seconds","--stress-birds","--stress-displays","--stress-seed","--stress-mode","--stress-sidehop-case","--stress-content"]
            var values:[String:String]=[:]
            var index=0
            while index<args.count {
                let flag=args[index]
                guard flags.contains(flag),values[flag]==nil,index+1<args.count,
                      !args[index+1].hasPrefix("--"),!args[index+1].isEmpty else {
                    throw ArgumentError.invalid("invalid, duplicate or incomplete stress option: \(flag)")
                }
                values[flag]=args[index+1];index+=2
            }
            guard let output=values["--stress-behavior"] else {
                throw ArgumentError.invalid("--stress-behavior requires a local report path")
            }
            let sideHopCase=values["--stress-sidehop-case"]
            guard sideHopCase==nil || sideHopCase=="m5n-183" else {
                throw ArgumentError.invalid("stress sidehop case must be m5n-183")
            }
            let defaults=sideHopCase==nil ? BehaviorStress.Configuration():BehaviorStress.m5nSideHopConfiguration
            guard let seconds=Double(values["--stress-seconds"] ?? String(defaults.seconds)),
                  let birds=Int(values["--stress-birds"] ?? String(defaults.birds)),
                  let displays=Int(values["--stress-displays"] ?? String(defaults.displays)),
                  let seed=UInt64(values["--stress-seed"] ?? String(defaults.seed)) else {
                throw ArgumentError.invalid("stress counts, duration and seed must be numeric")
            }
            let mode=values["--stress-mode"] ?? (defaults.autonomous ? "autonomous":"scripted")
            guard mode == "scripted" || mode == "autonomous" else {
                throw ArgumentError.invalid("stress mode must be scripted or autonomous")
            }
            if sideHopCase != nil {
                guard seconds>=575,birds==12,displays==2,seed==73,mode=="autonomous" else {
                    throw ArgumentError.invalid("m5n-183 requires >=575 seconds, 12 birds, 2 displays, seed 73, autonomous mode")
                }
            }
            let content=values["--stress-content"] ?? "enabled"
            guard ["enabled","disabled"].contains(content) else {throw ArgumentError.invalid("stress content must be enabled or disabled")}
            let report=try BehaviorStress.run(configuration:.init(seconds:seconds,birds:birds,displays:displays,seed:seed,autonomous:mode == "autonomous",newContentDisabled:content == "disabled"))
            let expected=report.failures.samples.first(where:{$0.matchesM5nSideHopFailure})
            let reproduced=sideHopCase.map{_ in expected?.sideHop != nil}
            let passed=report.passed && reproduced != false
            let envelope=Envelope(formatVersion:1,passed:passed,operatingSystem:ProcessInfo.processInfo.operatingSystemVersionString,
                                  processorCount:ProcessInfo.processInfo.processorCount,report:report,expectedSideHopReproduced:reproduced)
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(envelope).write(to:URL(fileURLWithPath:output),options:.atomic)
            if sideHopCase != nil {
                print("M5n sideHop run 183: \(reproduced == true ? "REPRODUCED":"NOT REPRODUCED")")
                if let diagnostic=expected?.sideHop {
                    print("sideHop: \(diagnostic.classification.rawValue) / \(diagnostic.cause.rawValue) / \(diagnostic.stage)")
                }
            }
            print("Behavior stress: \(passed ? "PASS":"FAIL") — \(output)")
            exit(passed ? 0:1)
        } catch {
            fputs("Behavior stress: FAIL — \(error.localizedDescription)\n",stderr);exit(1)
        }
    }
}
