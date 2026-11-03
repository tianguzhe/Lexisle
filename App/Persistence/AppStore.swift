import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class AppStore {
    private(set) var preferences = LearningPreferences()
    private(set) var favorites: Set<String> = []
    private(set) var cards: [String: MemoryCard] = [:]
    private(set) var reviewEvents: [LearningEvent] = []
    private(set) var session: LearningSession?
    var errorMessage: String?
    private(set) var syncStatus = "进度保存在此设备"
    private(set) var lastSyncedAt: Date?
    let cloudEnabled: Bool

    @ObservationIgnored private let localContainer: ModelContainer
    @ObservationIgnored private let localContext: ModelContext
    @ObservationIgnored private var cloudJournal: CloudJournal?
    @ObservationIgnored private var snapshot: LocalSnapshot
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private var catalog: [VocabularyEntry] = []
    @ObservationIgnored private var words: [String: VocabularyEntry] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var operations: [LearningOperation] = []
    private var statistics = LearningStatistics(events: [])

    init(
        inMemory: Bool = false,
        cloudEnabled: Bool = false,
        storageDirectory: URL? = nil,
        cloudContainerIdentifier: String? = AppConfiguration().cloudContainerIdentifier
    ) throws {
        self.cloudEnabled = cloudEnabled && !inMemory
        let localSchema = Schema(versionedSchema: LocalSchemaV1.self)
        let directory =
            storageDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WordAtlas", isDirectory: true)
        if !inMemory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                "Local", schema: localSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                "Local", schema: localSchema,
                url: directory.appendingPathComponent("learning.store"), cloudKitDatabase: .none)
        }
        localContainer = try ModelContainer(
            for: localSchema, migrationPlan: LocalMigrationPlan.self, configurations: [configuration])
        localContext = ModelContext(localContainer)
        localContext.autosaveEnabled = false
        let snapshots = try localContext.fetch(FetchDescriptor<LocalSnapshot>())
        if let existing = snapshots.first(where: { $0.key == "session" }) {
            snapshot = existing
        } else {
            let initial = LocalSnapshot()
            localContext.insert(initial)
            try localContext.save()
            snapshot = initial
        }
        if !snapshot.payload.isEmpty {
            session = try decoder.decode(LearningSession.self, from: snapshot.payload)
        }
        try reloadLocalOperations()

        if self.cloudEnabled {
            do {
                cloudJournal = try CloudJournal(directory: directory, identifier: cloudContainerIdentifier)
                cloudJournal?.observe { [weak self] event in self?.handleCloudEvent(event) }
                syncStatus = "正在连接 iCloud"
            } catch {
                syncStatus = "iCloud 暂不可用，学习记录已保存在本机"
                errorMessage = error.localizedDescription
            }
        }
    }

    var activeSession: LearningSession? { session?.finished == false ? session : nil }
    var draftAnswer: String { session?.draftAnswer ?? "" }
    var learnedCount: Int { cards.count }
    var masteredCount: Int { cards.values.filter(\.isMastered).count }
    var todayReviewCount: Int { statistics.reviews().count }
    var todayCorrectCount: Int { statistics.reviews().filter(\.correct).count }
    var todayNewCount: Int { statistics.newWordCount() }
    var streak: Int { statistics.streak() }

    func setCatalog(_ entries: [VocabularyEntry]) {
        catalog = entries
        words = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    func dueIDs(now: Date = Date()) -> [String] {
        cards.filter { $0.value.due <= now && (words.isEmpty || words[$0.key] != nil) }
            .sorted { $0.value.due == $1.value.due ? $0.key < $1.key : $0.value.due < $1.value.due }
            .map(\.key)
    }

    func nextNewWords(entries: [VocabularyEntry], limit: Int? = nil) -> [VocabularyEntry] {
        SessionBuilder.newWords(
            entries: entries, cards: cards, level: preferences.startLevel,
            limit: limit ?? max(0, preferences.dailyGoal - todayNewCount))
    }

    func activity(days: Int) -> [ActivityDay] {
        statistics.activity(days: days)
    }

    func updatePreferences(_ value: LearningPreferences) {
        let operation = LearningOperation(id: UUID().uuidString, date: Date(), payload: .preferences(value.validated()))
        commit(operation: operation, nextSession: session)
    }

    func toggleFavorite(_ id: String) {
        let operation = LearningOperation(
            id: UUID().uuidString, date: Date(),
            payload: .favorite(FavoriteChange(wordID: id, isFavorite: !favorites.contains(id))))
        commit(operation: operation, nextSession: session)
    }

    func startSession(entries: [VocabularyEntry], reviewOnly: Bool = false) {
        setCatalog(entries)
        guard activeSession == nil else { return }
        guard
            let next = SessionBuilder.build(
                entries: entries, cards: cards, preferences: preferences,
                newCount: todayNewCount, reviewOnly: reviewOnly)
        else { return }
        commit(operation: nil, nextSession: next)
    }

    func submitAnswer(_ answer: String, elapsed: TimeInterval, hinted: Bool = false) {
        guard var next = session, !next.finished, next.pending == nil,
            let step = next.current, step.kind != .intro
        else { return }
        guard let word = words[step.wordID] else {
            errorMessage = LearningError.missingWord.localizedDescription
            return
        }
        let correct =
            step.kind == .spell
            ? ReviewScheduler.normalizedSpelling(answer) == ReviewScheduler.normalizedSpelling(word.word)
            : answer == word.id
        next.pending = AnswerFeedback(correct: correct, correctAnswer: word.word, answer: answer)
        next.draftAnswer = ""
        var operation: LearningOperation?
        if next.graded[word.id] == nil && !step.retry {
            let now = Date()
            let grade = ReviewScheduler.grade(
                kind: step.kind, correct: correct, elapsed: elapsed,
                hinted: hinted || next.hintUsed)
            let event = LearningEvent(
                id: "\(next.id):\(word.id)", wordID: word.id, sessionID: next.id, date: now,
                rating: grade, correct: correct, isNew: cards[word.id] == nil, duration: min(90, max(0, elapsed)))
            next.graded[word.id] = grade
            operation = LearningOperation(id: event.id, date: now, payload: .review(event))
        }
        if !correct, next.steps.filter({ $0.wordID == word.id && $0.retry }).count < 2 {
            let kind: StudyKind = step.kind == .meaning ? .listen : .meaning
            let retry = StudyStep(
                wordID: word.id, kind: kind,
                options: SessionBuilder.options(for: word, in: catalog, kind: kind), retry: true)
            next.steps.insert(retry, at: min(next.steps.count, next.index + 4))
        }
        commit(operation: operation, nextSession: next)
    }

    func advance() {
        guard var next = session, !next.finished, let step = next.current else { return }
        guard step.kind == .intro || next.pending != nil else { return }
        next.index += 1
        next.pending = nil
        next.draftAnswer = ""
        next.hintUsed = false
        next.finished = next.index >= next.steps.count
        commit(operation: nil, nextSession: next)
    }

    func updateDraft(_ answer: String) {
        guard session?.current?.kind == .spell, session?.pending == nil else { return }
        session?.draftAnswer = answer
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.saveSession()
        }
    }

    func markHintUsed() {
        guard var next = session, next.current != nil, next.pending == nil, !next.hintUsed else { return }
        next.hintUsed = true
        commit(operation: nil, nextSession: next)
    }

    func saveSession() {
        draftTask?.cancel()
        commit(operation: nil, nextSession: session)
    }

    /// A failed recording and unavailable device voice must not trap the learner in a listening task.
    func useTextFallbackForCurrentQuestion() {
        guard var next = session, let current = next.current, current.kind == .listen, next.pending == nil,
            let word = words[current.wordID]
        else { return }
        next.steps[next.index].kind = .meaning
        next.steps[next.index].options = SessionBuilder.options(for: word, in: catalog, kind: .meaning)
        commit(operation: nil, nextSession: next)
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            try reloadLocalOperations()
        } catch {
            errorMessage = "未能读取学习记录：\(error.localizedDescription)"
            return
        }
        guard let cloudJournal else { return }
        do {
            let account = try await cloudJournal.accountStatus()
            guard account == .available else {
                syncStatus =
                    account == .noAccount
                    ? "登录 iCloud 后可同步，进度已保存在本机"
                    : "iCloud 暂不可用，进度已保存在本机"
                return
            }
            try merge(cloudJournal.operations())
            let pending = try publishPendingOperations(to: cloudJournal)
            if pending > 0 {
                syncStatus = "学习记录已加入 iCloud 同步队列"
            } else if lastSyncedAt == nil {
                syncStatus = "iCloud 已连接，等待同步确认"
            }
        } catch {
            syncStatus = "同步暂未完成，进度已保存在本机"
            errorMessage = error.localizedDescription
        }
    }

    /// Validate the entire incoming batch before saving; rollback cannot undo a completed save.
    func merge(_ incoming: [LearningOperation]) throws {
        let current = try readLocalOperations()
        var existing = Set(current.map(\.id))
        let additions = LearningOperation.ordered(incoming).filter { existing.insert($0.id).inserted }
        let projection = try LearningProjection(operations: current + additions)
        do {
            for operation in additions {
                localContext.insert(
                    LocalJournalEntry(
                        operation: operation, payload: try encoder.encode(operation), cloudSubmitted: true
                    ))
            }
            try localContext.save()
            apply(projection)
        } catch {
            localContext.rollback()
            throw error
        }
    }

    func exportedOperations() -> [LearningOperation] { operations }

    private func commit(operation: LearningOperation?, nextSession: LearningSession?) {
        do {
            let payload = try nextSession.map { try encoder.encode($0) } ?? Data()
            var projection: LearningProjection?
            if let operation {
                let current = try readLocalOperations()
                let isNew = !current.contains { $0.id == operation.id }
                projection = try LearningProjection(operations: current + (isNew ? [operation] : []))
                if isNew {
                    localContext.insert(LocalJournalEntry(operation: operation, payload: try encoder.encode(operation)))
                }
            }
            snapshot.payload = payload
            try localContext.save()
            session = nextSession
            if let projection { apply(projection) }
            errorMessage = nil
            scheduleRefresh()
        } catch {
            localContext.rollback()
            errorMessage = "未能保存进度：\(error.localizedDescription)"
        }
    }

    private func readLocalOperations() throws -> [LearningOperation] {
        try localContext.fetch(FetchDescriptor<LocalJournalEntry>()).map {
            try decoder.decode(LearningOperation.self, from: $0.payload)
        }
    }

    private func reloadLocalOperations() throws {
        apply(try LearningProjection(operations: readLocalOperations()))
    }

    private func apply(_ projection: LearningProjection) {
        operations = projection.operations
        preferences = projection.preferences
        favorites = projection.favorites
        reviewEvents = projection.events
        cards = projection.cards
        statistics = LearningStatistics(events: projection.events)
    }

    private func publishPendingOperations(to cloudJournal: CloudJournal) throws -> Int {
        let pending = try localContext.fetch(FetchDescriptor<LocalJournalEntry>()).filter { !$0.cloudSubmitted }
        guard !pending.isEmpty else { return 0 }
        let operations = try pending.map { try decoder.decode(LearningOperation.self, from: $0.payload) }
        try cloudJournal.enqueue(operations)
        do {
            for record in pending { record.cloudSubmitted = true }
            try localContext.save()
            return pending.count
        } catch {
            // Cloud enqueue is idempotent: a failed acknowledgement can safely be retried.
            localContext.rollback()
            throw error
        }
    }

    private func scheduleRefresh() {
        guard cloudJournal != nil else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            await self.refresh()
        }
    }

    private func handleCloudEvent(_ event: CloudJournal.Event) {
        switch event {
        case .remoteChange:
            scheduleRefresh()
        case .transferStarted:
            syncStatus = "正在与 iCloud 同步"
        case .transferCompleted(let date):
            lastSyncedAt = date
            syncStatus = "最近同步：\(date.formatted(date: .omitted, time: .shortened))"
            scheduleRefresh()
        case .transferFailed(let message):
            syncStatus = "同步暂未完成，进度已保存在本机"
            errorMessage = message
        }
    }
}
