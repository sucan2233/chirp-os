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
            let flags:Set<String>=["--stress-behavior","--stress-seconds","--stress-birds","--stress-displays","--stress-seed","--stress-mode"]
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
            guard let seconds=Double(values["--stress-seconds"] ?? "600"),
                  let birds=Int(values["--stress-birds"] ?? "24"),
                  let displays=Int(values["--stress-displays"] ?? "2"),
                  let seed=UInt64(values["--stress-seed"] ?? "73") else {
                throw ArgumentError.invalid("stress counts, duration and seed must be numeric")
            }
            let mode=values["--stress-mode"] ?? "scripted"
            guard mode == "scripted" || mode == "autonomous" else {
                throw ArgumentError.invalid("stress mode must be scripted or autonomous")
            }
            let report=try BehaviorStress.run(configuration:.init(seconds:seconds,birds:birds,displays:displays,seed:seed,autonomous:mode == "autonomous"))
            let envelope=Envelope(formatVersion:1,passed:report.passed,operatingSystem:ProcessInfo.processInfo.operatingSystemVersionString,
                                  processorCount:ProcessInfo.processInfo.processorCount,report:report)
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(envelope).write(to:URL(fileURLWithPath:output),options:.atomic)
            print("Behavior stress: \(report.passed ? "PASS":"FAIL") — \(output)")
            exit(report.passed ? 0:1)
        } catch {
            fputs("Behavior stress: FAIL — \(error.localizedDescription)\n",stderr);exit(1)
        }
    }
}
