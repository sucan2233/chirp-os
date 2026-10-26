import Foundation

/// Product labels are separate from persistent storage keys and bundle identity.
enum AppBranding {
    static var isPro: Bool { Bundle.main.object(forInfoDictionaryKey: "ChirpOSProBuild") as? Bool == true }
    static var isDevelopment: Bool { Bundle.main.object(forInfoDictionaryKey: "ChirpOSDevelopmentBuild") as? Bool == true }
    static var chineseName: String { isPro ? "啾啾 Pro" : (isDevelopment ? "啾啾测试版" : "啾啾") }
    static var englishName: String { isPro ? "ChirpOS Pro" : (isDevelopment ? "ChirpOS Dev" : "ChirpOS") }
}
