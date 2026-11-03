import FSRS
import Foundation

/// Pure deterministic adapter. Immutable events can be replayed in either arrival order.
struct ReviewScheduler {
    private let engine = FSRS(
        parameters: FSRSParameters(
            requestRetention: 0.9,
            w: FSRSDefaults.defaultWv6,
            enableFuzz: false,
            enableShortTerm: true,
            learningSteps: ["1m", "10m"],
            relearningSteps: ["10m"]
        ))

    func review(_ previous: MemoryCard?, event: LearningEvent) throws -> MemoryCard {
        guard let rating = Rating(rawValue: event.rating), rating != .manual else {
            throw LearningError.invalidRating
        }
        let initial = previous?.card ?? Card(due: event.date)
        let next = try engine.next(card: initial, now: event.date, grade: rating).card
        return MemoryCard(card: next, firstSeen: previous?.firstSeen ?? event.date)
    }

    func replay(_ events: [LearningEvent]) throws -> [String: MemoryCard] {
        var result: [String: MemoryCard] = [:]
        var seen: Set<String> = []
        for event in events.sorted(by: { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }) {
            guard seen.insert(event.id).inserted else { continue }
            result[event.wordID] = try review(result[event.wordID], event: event)
        }
        return result
    }

    static func grade(kind: StudyKind, correct: Bool, elapsed: TimeInterval, hinted: Bool) -> Int {
        guard correct else { return Rating.again.rawValue }
        let slowAnswerThreshold: TimeInterval = kind == .spell ? 20 : 9
        if hinted || elapsed > slowAnswerThreshold { return Rating.hard.rawValue }
        if kind == .spell && elapsed < 6 { return Rating.easy.rawValue }
        return Rating.good.rawValue
    }

    static func normalizedSpelling(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "‐", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
