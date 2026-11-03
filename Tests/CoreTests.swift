import FSRS
import Foundation
import XCTest

@testable import WordAtlas

final class SchedulerTests: XCTestCase {
    /// Oracle generated with ts-fsrs 5.4.2, retention .9, fuzz off, 1m/10m learning and 10m relearning.
    func testFSRS6MatchesOriginalTypeScriptOracle() throws {
        let scheduler = ReviewScheduler()
        var previous: MemoryCard?
        var now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
        let grades = [3, 3, 3, 3, 1, 3, 3]
        let expectedStability = [2.3065, 2.3065, 10.97104786, 46.31685657, 2.93384526, 2.93384526, 7.79910198]
        let expectedDifficulty = [2.11810397, 2.11121424, 2.1043314, 2.09745544, 7.38771571, 7.37555636, 7.36340917]
        let expectedDays: [Double] = [0, 2, 11, 46, 0, 3, 8]
        for index in grades.indices {
            let event = LearningEvent(
                id: "event-\(index)", wordID: "library", sessionID: "oracle", date: now,
                rating: grades[index], correct: grades[index] != 1, isNew: index == 0, duration: 2)
            let next = try scheduler.review(previous, event: event)
            XCTAssertEqual(next.stability, expectedStability[index], accuracy: 0.00001)
            XCTAssertEqual(next.card.difficulty, expectedDifficulty[index], accuracy: 0.00001)
            XCTAssertEqual(next.card.scheduledDays, expectedDays[index])
            if index == 0 { XCTAssertEqual(next.due.timeIntervalSince(now), 600, accuracy: 0.001) }
            if index == 4 {
                XCTAssertEqual(next.card.state, .relearning)
                XCTAssertEqual(next.card.lapses, 1)
                XCTAssertFalse(next.isMastered)
            }
            previous = next
            now = next.due
        }
    }

    func testReplayDeduplicatesAndIgnoresArrivalOrder() throws {
        let now = Date(timeIntervalSince1970: 1_782_000_000)
        let a = LearningEvent(
            id: "a", wordID: "library", sessionID: "first", date: now,
            rating: 3, correct: true, isNew: true, duration: 2)
        let b = LearningEvent(
            id: "b", wordID: "library", sessionID: "second", date: now.addingTimeInterval(600),
            rating: 3, correct: true, isNew: false, duration: 2)
        let scheduler = ReviewScheduler()
        XCTAssertEqual(try scheduler.replay([a, b]), try scheduler.replay([b, a, a, b]))
        XCTAssertEqual(try scheduler.replay([a, b])["library"]?.repetitions, 2)
    }

    func testSpellingNormalizesPunctuationAndWhitespace() {
        XCTAssertEqual(ReviewScheduler.normalizedSpelling("  O’CLOCK\n"), "o'clock")
        XCTAssertEqual(ReviewScheduler.normalizedSpelling("Well‑being"), "well-being")
        XCTAssertEqual(ReviewScheduler.normalizedSpelling("United    Kingdom"), "united kingdom")
        XCTAssertNotEqual(ReviewScheduler.normalizedSpelling("principle"), "principal")
    }

    func testGradingHonorsHintsAndWrongAnswers() {
        XCTAssertEqual(ReviewScheduler.grade(kind: .spell, correct: false, elapsed: 1, hinted: false), 1)
        XCTAssertEqual(ReviewScheduler.grade(kind: .spell, correct: true, elapsed: 1, hinted: true), 2)
        XCTAssertEqual(ReviewScheduler.grade(kind: .spell, correct: true, elapsed: 1, hinted: false), 4)
        XCTAssertEqual(ReviewScheduler.grade(kind: .meaning, correct: true, elapsed: 2, hinted: false), 3)
    }
}

final class LearningModelTests: XCTestCase {
    func testPreferenceValidationPreservesStoredStringValues() throws {
        let original = LearningPreferences(
            dailyGoal: 20, startLevel: "C1", accent: .us, onboarded: true, appearance: "dark")
        XCTAssertEqual(original.validated(), original)

        var invalid = original
        invalid.dailyGoal = 0
        invalid.startLevel = "unknown"
        invalid.appearance = "unknown"
        let validated = invalid.validated()
        XCTAssertEqual(validated.dailyGoal, 1)
        XCTAssertEqual(validated.startLevel, "B1")
        XCTAssertEqual(validated.appearance, "system")
        XCTAssertEqual(validated.accent, .us)
        invalid.dailyGoal = 100
        XCTAssertEqual(invalid.validated().dailyGoal, 50)

        let encoded = try JSONEncoder().encode(original)
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(stored["appearance"] as? String, "dark")
        XCTAssertEqual(stored["startLevel"] as? String, "C1")
        XCTAssertEqual(stored["accent"] as? String, "us")
        XCTAssertEqual(try JSONDecoder().decode(LearningPreferences.self, from: encoded), original)
    }

    func testSessionBeforeDraftAndHintFieldsStillDecodes() throws {
        let legacy = Data(
            """
            {"id":"legacy","startedAt":0,"steps":[{"id":"step","wordID":"library","kind":"spell","options":[],"retry":false}],"index":0,"graded":{},"newIDs":["library"],"finished":false}
            """.utf8)
        let session = try JSONDecoder().decode(LearningSession.self, from: legacy)
        XCTAssertEqual(session.current?.wordID, "library")
        XCTAssertEqual(session.current?.kind, .spell)
        XCTAssertEqual(session.draftAnswer, "")
        XCTAssertFalse(session.hintUsed)
        XCTAssertNil(session.pending)
        let encoded = try JSONEncoder().encode(session)
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(stored["newIDs"] as? [String], ["library"])
        XCTAssertEqual(stored["hintUsed"] as? Bool, false)
        XCTAssertEqual(stored["draftAnswer"] as? String, "")
    }
}

final class SessionBuilderTests: XCTestCase {
    func testReviewOnlySessionOrdersDueWordsAndExcludesMissingOrFutureCards() throws {
        let now = Date(timeIntervalSince1970: 1_782_000_000)
        func memory(due: Date) -> MemoryCard { MemoryCard(card: Card(due: due), firstSeen: now) }
        let cards = [
            "journey": memory(due: now.addingTimeInterval(-10)),
            "library": memory(due: now.addingTimeInterval(-20)),
            "forest": memory(due: now.addingTimeInterval(60)),
            "not-in-catalog": memory(due: now.addingTimeInterval(-30)),
        ]
        let session = try XCTUnwrap(
            SessionBuilder.build(
                entries: WordFixtures.make(), cards: cards,
                preferences: LearningPreferences(), newCount: 0, reviewOnly: true, now: now))
        XCTAssertEqual(session.steps.map(\.wordID), ["library", "journey"])
        XCTAssertFalse(session.steps.contains { $0.kind == .intro })
        XCTAssertTrue(session.newIDs.isEmpty)
    }

    func testMeaningChoicesDoNotIncludeDuplicateDisplayedAnswers() throws {
        var words = WordFixtures.make()
        words[1].senses[0].zh = words[0].meaning
        words[3].senses[0].zh = words[2].meaning
        let options = SessionBuilder.options(for: words[0], in: words, kind: .meaning)
        let byID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        let meanings = options.compactMap { byID[$0]?.meaning }
        XCTAssertEqual(options.count, 4)
        XCTAssertEqual(options.filter { $0 == words[0].id }.count, 1)
        XCTAssertFalse(options.contains(words[1].id))
        XCTAssertEqual(Set(meanings).count, options.count)
    }
}

@MainActor final class CatalogTests: XCTestCase {
    func testManifestRejectsDuplicateIDsAndIncorrectCounts() throws {
        func data(ids: [String], count: Int) throws -> Data {
            let rows: [[Any]] = ids.map { [$0, $0, "释义", "/ipa/", 0, 0, 31] }
            return try JSONSerialization.data(withJSONObject: ["count": count, "words": rows])
        }
        XCTAssertThrowsError(try JSONDecoder().decode(AtlasIndex.self, from: data(ids: ["a", "a"], count: 2)))
        XCTAssertThrowsError(try JSONDecoder().decode(AtlasIndex.self, from: data(ids: ["a"], count: 2)))
        let index = try JSONDecoder().decode(AtlasIndex.self, from: data(ids: ["a", "b"], count: 2))
        XCTAssertEqual(index.mediaFlagsByID, ["a": 31, "b": 31])
    }

    func testConcurrentLoadWaitsUntilCatalogIsPublished() async {
        let repository = VocabularyRepository()
        let first = Task { await repository.load() }
        while !repository.isLoading && repository.entries.isEmpty && repository.errorMessage == nil {
            await Task.yield()
        }
        await repository.load()
        XCTAssertNil(repository.errorMessage)
        XCTAssertEqual(repository.entries.count, 7298, "Every awaiting window must receive a complete catalog")
        XCTAssertEqual(repository.word(id: "library")?.word, "library")
        await first.value
    }
}

@MainActor final class LearningStoreTests: XCTestCase {
    func testDefaultPlanUsesLevelAndDailyLimit() throws {
        let store = try AppStore(inMemory: true)
        var preferences = store.preferences
        preferences.dailyGoal = 2
        store.updatePreferences(preferences)
        let words = WordFixtures.make()
        store.startSession(entries: words)
        let session = try XCTUnwrap(store.session)
        XCTAssertEqual(session.newIDs, ["journey", "river"])
        XCTAssertEqual(session.steps.filter { $0.kind == .intro }.count, 2)
        XCTAssertEqual(session.steps.filter { $0.kind != .intro }.count, 2)
        XCTAssertEqual(session.steps.prefix(2).map(\.kind), [.intro, .intro])
    }

    func testDailyQueueWrapsToLowerUnseenLevels() {
        let words = WordFixtures.make()
        let selection = SessionBuilder.newWords(entries: words, cards: [:], level: "C2", limit: 2)
        XCTAssertEqual(selection.map(\.id), ["library", "journey"])
    }

    func testDoubleSubmitAndRetriesCountOnce() throws {
        let store = try AppStore(inMemory: true)
        var preferences = store.preferences
        preferences.dailyGoal = 1
        store.updatePreferences(preferences)
        store.startSession(entries: WordFixtures.make())
        store.advance()
        let wordID = try XCTUnwrap(store.session?.current?.wordID)
        store.submitAnswer("incorrect", elapsed: 2)
        store.submitAnswer(wordID, elapsed: 2)
        XCTAssertEqual(store.reviewEvents.count, 1)
        XCTAssertFalse(try XCTUnwrap(store.session?.pending).correct)
        store.advance()
        XCTAssertEqual(store.session?.current?.retry, true)
        store.submitAnswer(wordID, elapsed: 2)
        XCTAssertEqual(store.reviewEvents.count, 1)
        XCTAssertEqual(store.todayReviewCount, 1)
        XCTAssertEqual(store.todayCorrectCount, 0)
        XCTAssertEqual(store.todayNewCount, 1)
        store.advance()
        XCTAssertEqual(store.session?.finished, true)
        store.startSession(entries: WordFixtures.make())
        XCTAssertEqual(store.session?.finished, true, "Daily new-word budget must survive completed sessions")
    }

    func testTwoOfflineDevicesMergeWithoutLosingReviewsOrFavorites() throws {
        let left = try AppStore(inMemory: true)
        let right = try AppStore(inMemory: true)
        let now = Date().addingTimeInterval(-3600)
        let first = LearningEvent(
            id: "first", wordID: "library", sessionID: "left", date: now,
            rating: 3, correct: true, isNew: true, duration: 2)
        let second = LearningEvent(
            id: "second", wordID: "library", sessionID: "right", date: now.addingTimeInterval(600),
            rating: 3, correct: true, isNew: true, duration: 2)
        let add = LearningOperation(
            id: "favorite-add", date: now, payload: .favorite(.init(wordID: "river", isFavorite: true)))
        let remove = LearningOperation(
            id: "favorite-remove", date: now.addingTimeInterval(1),
            payload: .favorite(.init(wordID: "river", isFavorite: false)))
        let a = LearningOperation(id: first.id, date: first.date, payload: .review(first))
        let b = LearningOperation(id: second.id, date: second.date, payload: .review(second))
        try left.merge([a, add])
        try right.merge([b, remove])
        let all = left.exportedOperations() + right.exportedOperations()
        try left.merge(Array(all.reversed()))
        try right.merge(all + all)
        XCTAssertEqual(left.cards, right.cards)
        XCTAssertEqual(left.reviewEvents, right.reviewEvents)
        XCTAssertEqual(left.reviewEvents.count, 2)
        XCTAssertEqual(left.favorites, right.favorites)
        XCTAssertFalse(left.favorites.contains("river"))
        XCTAssertEqual(left.learnedCount, 1)
    }

    func testPreferencesUseStableTimestampAndIDOrdering() throws {
        let store = try AppStore(inMemory: true)
        let date = Date()
        var low = LearningPreferences()
        low.dailyGoal = 5
        var high = LearningPreferences()
        high.dailyGoal = 20
        let a = LearningOperation(id: "a", date: date, payload: .preferences(low))
        let b = LearningOperation(id: "b", date: date, payload: .preferences(high))
        try store.merge([b, a])
        XCTAssertEqual(store.preferences.dailyGoal, 20)
        try store.merge([a, b, a])
        XCTAssertEqual(store.preferences.dailyGoal, 20)
    }

    func testSavedPendingAnswerSurvivesRelaunchWithoutRegrading() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WordAtlasTests-\(UUID().uuidString)")
        let words = WordFixtures.make()
        var correctID = ""
        do {
            let store = try AppStore(storageDirectory: directory)
            var preferences = store.preferences
            preferences.dailyGoal = 1
            store.updatePreferences(preferences)
            store.startSession(entries: words)
            store.advance()
            correctID = try XCTUnwrap(store.session?.current?.wordID)
            store.submitAnswer(correctID, elapsed: 2)
            XCTAssertEqual(store.reviewEvents.count, 1)
        }
        let restored = try AppStore(storageDirectory: directory)
        restored.setCatalog(words)
        XCTAssertEqual(restored.session?.pending?.correct, true)
        restored.submitAnswer(correctID, elapsed: 2)
        XCTAssertEqual(restored.reviewEvents.count, 1)
        restored.advance()
        XCTAssertEqual(restored.session?.finished, true)
    }

    func testMissingAudioFallsBackWithoutScoring() throws {
        let store = try AppStore(inMemory: true)
        var preferences = store.preferences
        preferences.dailyGoal = 2
        store.updatePreferences(preferences)
        store.startSession(entries: WordFixtures.make())
        store.advance()
        store.advance()
        let first = try XCTUnwrap(store.session?.current)
        store.submitAnswer(first.wordID, elapsed: 2)
        store.advance()
        XCTAssertEqual(store.session?.current?.kind, .listen)
        store.useTextFallbackForCurrentQuestion()
        XCTAssertEqual(store.session?.current?.kind, .meaning)
        XCTAssertEqual(store.reviewEvents.count, 1)
    }

    func testHintSurvivesRelaunchAndLimitsGrade() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WordAtlasHintTests-\(UUID().uuidString)")
        let words = WordFixtures.make()
        do {
            let store = try AppStore(storageDirectory: directory)
            var preferences = store.preferences
            preferences.dailyGoal = 1
            store.updatePreferences(preferences)
            store.startSession(entries: words)
            store.advance()
            store.markHintUsed()
            XCTAssertEqual(store.session?.hintUsed, true)
        }
        let restored = try AppStore(storageDirectory: directory)
        restored.setCatalog(words)
        let current = try XCTUnwrap(restored.session?.current)
        restored.submitAnswer(current.wordID, elapsed: 1, hinted: false)
        XCTAssertEqual(restored.reviewEvents.first?.rating, 2)
        restored.advance()
        XCTAssertEqual(restored.session?.hintUsed, false)
    }

    func testCompleteEmbeddedCatalogAndMediaFlags() async throws {
        let repository = VocabularyRepository()
        await repository.load()
        XCTAssertNil(repository.errorMessage)
        XCTAssertEqual(repository.entries.count, 7298)
        XCTAssertEqual(repository.entries.reduce(0) { $0 + $1.examples.count }, 14596)
        XCTAssertEqual(repository.topics.count, 19)
        XCTAssertEqual(Set(repository.entries.map(\.id)).count, 7298)
        XCTAssertEqual(repository.entries.filter { $0.hasMedia("ex2") }.count, 1011)
        XCTAssertTrue(
            repository.entries.allSatisfy {
                $0.hasMedia("img") && $0.hasMedia("uk") && $0.hasMedia("us") && $0.hasMedia("ex")
            })
        XCTAssertEqual(repository.word(id: "library")?.word, "library")
    }
}

private enum WordFixtures {
    static func make() -> [VocabularyEntry] {
        ["library", "journey", "river", "promise", "forest", "explore"].enumerated().map { index, word in
            VocabularyEntry(
                id: word, word: word, uk: "/test/", us: "/test/",
                senses: [WordSense(pos: "n.", zh: "释义\(index)", en: "Definition \(index)")],
                examples: [WordExample(en: "A \(word).", zh: "例句")], collocations: [], family: [],
                synonyms: [], antonyms: [], tip: "", cefr: index == 0 ? "A1" : "B1", topic: "nature", note: nil)
        }
    }
}
