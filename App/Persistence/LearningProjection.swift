import Foundation

/// Rebuilds visible learning state before a journal transaction is allowed to commit.
struct LearningProjection {
    let operations: [LearningOperation]
    let preferences: LearningPreferences
    let favorites: Set<String>
    let events: [LearningEvent]
    let cards: [String: MemoryCard]

    init(operations: [LearningOperation]) throws {
        self.operations = LearningOperation.ordered(operations)
        var preferences = LearningPreferences()
        var favorites: Set<String> = []
        var events: [LearningEvent] = []

        for operation in self.operations {
            switch operation.payload {
            case .review(let event):
                events.append(event)
            case .favorite(let change):
                if change.isFavorite {
                    favorites.insert(change.wordID)
                } else {
                    favorites.remove(change.wordID)
                }
            case .preferences(let value):
                preferences = value.validated()
            }
        }

        self.preferences = preferences
        self.favorites = favorites
        self.events = events
        self.cards = try ReviewScheduler().replay(events)
    }
}
