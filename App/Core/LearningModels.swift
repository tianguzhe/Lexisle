import FSRS
import Foundation

struct LearningPreferences: Codable, Equatable, Sendable {
    static let supportedLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]
    static let dailyGoalOptions = [5, 10, 15, 20]
    static let supportedAppearances = ["system", "light", "dark"]

    var dailyGoal: Int = 10
    var startLevel: String = "B1"
    var accent: Accent = .uk
    var onboarded: Bool = false
    var appearance: String = "system"

    func validated() -> Self {
        var result = self
        result.dailyGoal = min(50, max(1, dailyGoal))
        if !Self.supportedLevels.contains(startLevel) { result.startLevel = "B1" }
        if !Self.supportedAppearances.contains(appearance) { result.appearance = "system" }
        return result
    }
}

struct MemoryCard: Codable, Sendable, Equatable {
    private static let masteredStability: Double = 21

    var card: Card
    var firstSeen: Date
    var due: Date { card.due }
    var stability: Double { card.stability }
    var repetitions: Int { card.reps }
    var isMastered: Bool { card.state == .review && card.stability >= Self.masteredStability }
}

struct LearningEvent: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var wordID: String
    var sessionID: String
    var date: Date
    var rating: Int
    var correct: Bool
    var isNew: Bool
    var duration: TimeInterval
    var schedulerVersion: String = "fsrs6-4fbaf20-retention90"
}

enum StudyKind: String, Codable, Sendable {
    case intro, meaning, listen, spell
    var title: String {
        switch self {
        case .intro: "认识新词"
        case .meaning: "选出正确释义"
        case .listen: "听音辨词"
        case .spell: "拼写单词"
        }
    }
}

struct StudyStep: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var wordID: String
    var kind: StudyKind
    var options: [String] = []
    var retry: Bool = false
}

struct AnswerFeedback: Codable, Equatable, Sendable {
    var correct: Bool
    var correctAnswer: String
    var answer: String
}

struct LearningSession: Identifiable, Codable, Sendable {
    var id: String = UUID().uuidString
    var startedAt: Date = Date()
    var steps: [StudyStep]
    var index: Int = 0
    var graded: [String: Int] = [:]
    var newIDs: [String] = []
    var finished: Bool = false
    var pending: AnswerFeedback?
    var draftAnswer: String = ""
    var hintUsed: Bool = false
    var current: StudyStep? { steps.indices.contains(index) && !finished ? steps[index] : nil }
    var progress: Double { steps.isEmpty ? 1 : min(1, Double(index) / Double(steps.count)) }
    var correctCount: Int { graded.values.filter { $0 > 1 }.count }
    var accuracy: Int { graded.isEmpty ? 0 : Int((Double(correctCount) / Double(graded.count) * 100).rounded()) }
}

extension LearningSession {
    enum CodingKeys: String, CodingKey {
        case id, startedAt, steps, index, graded, newIDs, finished, pending, draftAnswer, hintUsed
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        steps = try values.decode([StudyStep].self, forKey: .steps)
        index = try values.decodeIfPresent(Int.self, forKey: .index) ?? 0
        graded = try values.decodeIfPresent([String: Int].self, forKey: .graded) ?? [:]
        newIDs = try values.decodeIfPresent([String].self, forKey: .newIDs) ?? []
        finished = try values.decodeIfPresent(Bool.self, forKey: .finished) ?? false
        pending = try values.decodeIfPresent(AnswerFeedback.self, forKey: .pending)
        draftAnswer = try values.decodeIfPresent(String.self, forKey: .draftAnswer) ?? ""
        hintUsed = try values.decodeIfPresent(Bool.self, forKey: .hintUsed) ?? false
    }
}

struct ActivityDay: Identifiable, Sendable {
    var date: Date
    var reviewed: Int
    var correct: Int
    var newWords: Int
    var id: Date { date }
}

struct FavoriteChange: Codable, Equatable, Sendable {
    var wordID: String
    var isFavorite: Bool
}

enum OperationPayload: Codable, Equatable, Sendable {
    case review(LearningEvent)
    case favorite(FavoriteChange)
    case preferences(LearningPreferences)
}

struct LearningOperation: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var date: Date
    var payload: OperationPayload

    static func ordered(_ operations: [LearningOperation]) -> [LearningOperation] {
        var byID: [String: LearningOperation] = [:]
        for operation in operations { byID[operation.id] = operation }
        return byID.values.sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
    }
}

enum LearningError: LocalizedError {
    case invalidRating, missingWord

    var errorDescription: String? {
        switch self {
        case .invalidRating: "学习记录中的评级无效。"
        case .missingWord: "当前词条不在词库中，请重新载入词库。"
        }
    }
}
