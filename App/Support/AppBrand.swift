import Foundation

/// Runtime identity comes from the same build configuration as the installed app name.
enum AppBrand {
    static let name = value(for: "CFBundleDisplayName", fallback: "词屿")
    static let englishName = value(for: "AppBrandEnglishName", fallback: "Lexisle")
    static let tagline = value(for: "AppBrandTagline", fallback: "从一个词，抵达新世界。")

    static var displayName: String { "\(name) · \(englishName)" }
    static var wordmark: String { englishName.uppercased() }
    static var welcomeWordmark: String { "\(wordmark) · \(name)" }
    static var onboardingAction: String { "开启我的\(name)旅程" }
    static var aboutTitle: String { "关于\(name)" }

    private static func value(for key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !value.contains("$(")
        else { return fallback }
        return value
    }
}
