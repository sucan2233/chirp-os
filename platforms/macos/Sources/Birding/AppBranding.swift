import Foundation
import BirdingCore

/// Product labels are separate from persistent storage keys and bundle identity.
enum AppBranding {
    static var isPro: Bool { Bundle.main.object(forInfoDictionaryKey: "ChirpOSProBuild") as? Bool == true }
    static var isDevelopment: Bool { Bundle.main.object(forInfoDictionaryKey: "ChirpOSDevelopmentBuild") as? Bool == true }
    static var updateChannel: UpdateChannel { isPro ? .pro : .legacy }
    static var updatesEnabled: Bool {
        if isPro {
            guard Bundle.main.object(forInfoDictionaryKey: "ChirpOSUpdatesEnabled") as? Bool == true,
                  let key = Bundle.main.object(forInfoDictionaryKey: "ChirpOSUpdatePublicKey") as? String,
                  Data(base64Encoded: key)?.count == 32 else { return false }
            return true
        }
        return !isDevelopment
    }
    static var chineseName: String { isPro ? "啾啾 Pro" : (isDevelopment ? "啾啾测试版" : "啾啾") }
    static var englishName: String { isPro ? "ChirpOS Pro" : (isDevelopment ? "ChirpOS Dev" : "ChirpOS") }
}
