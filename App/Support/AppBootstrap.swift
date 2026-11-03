import Foundation
import Observation

/// One data store and catalog per app; navigation remains local to each window.
@MainActor @Observable
final class AppBootstrap {
    private(set) var store: AppStore?
    private(set) var startupError: String?
    let vocabulary = VocabularyRepository()

    @ObservationIgnored private let configuration: AppConfiguration

    init(configuration: AppConfiguration = AppConfiguration()) {
        self.configuration = configuration
        openStore()
    }

    func openStore() {
        guard store == nil else { return }
        do {
            store = try AppStore(
                inMemory: configuration.usesInMemoryStore,
                cloudEnabled: configuration.cloudEnabled,
                cloudContainerIdentifier: configuration.cloudContainerIdentifier
            )
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }

    func prepare() async {
        guard let store else { return }
        await vocabulary.load()
        store.setCatalog(vocabulary.entries)
        await store.refresh()
        if configuration.skipsOnboarding && !store.preferences.onboarded {
            var preferences = store.preferences
            preferences.onboarded = true
            store.updatePreferences(preferences)
        }
    }
}
