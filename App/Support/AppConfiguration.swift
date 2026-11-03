import Foundation

struct AppConfiguration {
    let cloudEnabled: Bool
    let cloudContainerIdentifier: String?
    let usesInMemoryStore: Bool
    let skipsOnboarding: Bool

    init(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        if let value = info["WordAtlasCloudEnabled"] as? Bool {
            cloudEnabled = value
        } else if let value = info["WordAtlasCloudEnabled"] as? String {
            cloudEnabled = ["yes", "true", "1"].contains(
                value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        } else {
            cloudEnabled = false
        }
        cloudContainerIdentifier = info["CloudKitContainerIdentifier"] as? String
        #if DEBUG
        usesInMemoryStore = arguments.contains("--ui-testing")
        skipsOnboarding = arguments.contains("--skip-onboarding")
        #else
        usesInMemoryStore = false
        skipsOnboarding = false
        #endif
    }
}
