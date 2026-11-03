import Foundation

/// Builds the due-first learning path without changing persisted progress.
enum SessionBuilder {
    static let levels = LearningPreferences.supportedLevels

    private static let introductionGroupSize = 5
    private static let maximumReviews = 120
    private static let distractorRadius = 400
    private static let distractorCount = 3

    static func newWords(entries: [VocabularyEntry], cards: [String: MemoryCard], level: String, limit: Int)
        -> [VocabularyEntry]
    {
        guard limit > 0 else { return [] }
        let startingRank = levelRank(level, fallback: 2)
        var selected: [VocabularyEntry] = []
        selected.reserveCapacity(min(limit, entries.count))

        // Preserve catalog order, then wrap to lower levels only if the preferred path is exhausted.
        for includeLowerLevels in [false, true] {
            for word in entries where cards[word.id] == nil {
                let isLowerLevel = levelRank(word.cefr) < startingRank
                guard isLowerLevel == includeLowerLevels else { continue }
                selected.append(word)
                if selected.count == limit { return selected }
            }
        }
        return selected
    }

    static func build(
        entries: [VocabularyEntry], cards: [String: MemoryCard], preferences: LearningPreferences,
        newCount: Int, reviewOnly: Bool, now: Date = Date()
    ) -> LearningSession? {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let due = cards.filter { $0.value.due <= now && byID[$0.key] != nil }
            .sorted { $0.value.due == $1.value.due ? $0.key < $1.key : $0.value.due < $1.value.due }
            .prefix(maximumReviews).map(\.key)
        let fresh =
            reviewOnly
            ? []
            : newWords(
                entries: entries, cards: cards, level: preferences.startLevel,
                limit: max(0, preferences.dailyGoal - newCount))
        var steps = due.enumerated().compactMap { offset, id -> StudyStep? in
            guard let word = byID[id] else { return nil }
            return quiz(word: word, entries: entries, card: cards[id], offset: offset)
        }

        for start in stride(from: 0, to: fresh.count, by: introductionGroupSize) {
            let end = min(start + introductionGroupSize, fresh.count)
            let group = fresh[start..<end]
            steps += group.map { StudyStep(wordID: $0.id, kind: .intro) }
            steps += group.shuffled().enumerated().map { offset, word in
                quiz(word: word, entries: entries, card: nil, offset: offset)
            }
        }

        guard !steps.isEmpty else { return nil }
        return LearningSession(startedAt: now, steps: steps, newIDs: fresh.map(\.id))
    }

    static func quiz(word: VocabularyEntry, entries: [VocabularyEntry], card: MemoryCard?, offset: Int) -> StudyStep {
        let kind: StudyKind
        if (card?.stability ?? 0) >= 4 && offset % 3 == 0 {
            kind = .spell
        } else if offset % 3 == 1 {
            kind = .listen
        } else {
            kind = .meaning
        }
        let choices = kind == .spell ? [] : options(for: word, in: entries, kind: kind)
        return StudyStep(wordID: word.id, kind: kind, options: choices)
    }

    static func options(for word: VocabularyEntry, in entries: [VocabularyEntry], kind: StudyKind) -> [String] {
        var seen = Set([answerText(for: word, kind: kind)])
        let position = entries.firstIndex { $0.id == word.id } ?? 0
        let lowerBound = max(0, position - distractorRadius)
        let upperBound = min(entries.count, position + distractorRadius + 1)

        // Score only neighbouring words once, rather than sorting the complete catalog for every question.
        var candidates: [(word: VocabularyEntry, rank: Int)] = []
        for candidate in entries[lowerBound..<upperBound] where candidate.id != word.id {
            candidates.append((word: candidate, rank: score(candidate, word: word, kind: kind)))
        }
        candidates.sort { left, right in
            if left.rank == right.rank { return left.word.id < right.word.id }
            return left.rank > right.rank
        }

        var chosen: [String] = []
        for candidate in candidates {
            let answer = answerText(for: candidate.word, kind: kind)
            guard !answer.isEmpty, seen.insert(answer).inserted else { continue }
            chosen.append(candidate.word.id)
            if chosen.count == distractorCount { break }
        }
        return (chosen + [word.id]).shuffled()
    }

    private static func levelRank(_ level: String, fallback: Int = 0) -> Int {
        levels.firstIndex(of: level) ?? fallback
    }

    private static func answerText(for word: VocabularyEntry, kind: StudyKind) -> String {
        kind == .meaning ? word.meaning : ReviewScheduler.normalizedSpelling(word.word)
    }

    private static func score(_ candidate: VocabularyEntry, word: VocabularyEntry, kind: StudyKind) -> Int {
        (candidate.cefr == word.cefr ? 20 : 0) + (candidate.pos == word.pos ? 12 : 0)
            + (kind != .meaning && candidate.word.first == word.word.first ? 30 : 0)
            + max(0, 10 - abs(candidate.word.count - word.word.count))
    }
}
