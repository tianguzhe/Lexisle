import Foundation

enum Accent: String, CaseIterable, Codable, Sendable, Identifiable {
    case uk, us
    var id: String { rawValue }
    var title: String { self == .uk ? "英音" : "美音" }
    var language: String { self == .uk ? "en-GB" : "en-US" }
}

struct WordSense: Codable, Hashable, Sendable {
    var pos: String
    var zh: String
    var en: String
}

struct WordExample: Codable, Hashable, Sendable {
    var en: String
    var zh: String
}

struct Topic: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String

    static let all: [Topic] = [
        .init(id: "education", name: "教育"), .init(id: "work", name: "职场"),
        .init(id: "technology", name: "科技"), .init(id: "science", name: "科学"),
        .init(id: "environment", name: "环境"), .init(id: "health", name: "健康"),
        .init(id: "society", name: "社会"), .init(id: "government", name: "政法"),
        .init(id: "economy", name: "经济"), .init(id: "media", name: "媒体"),
        .init(id: "arts", name: "艺术"), .init(id: "travel", name: "旅行"),
        .init(id: "city", name: "城市"), .init(id: "nature", name: "自然"),
        .init(id: "daily", name: "生活"), .init(id: "emotion", name: "情感"),
        .init(id: "thinking", name: "思维"), .init(id: "sport", name: "运动"),
        .init(id: "history", name: "历史"),
    ]
}

struct VocabularyEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var word: String
    var uk: String
    var us: String
    var senses: [WordSense]
    var examples: [WordExample]
    var collocations: [String]
    var family: [String]
    var synonyms: [String]
    var antonyms: [String]
    var tip: String
    var cefr: String
    var topic: String
    var note: String?
    var mediaFlags: Int = 0

    var meaning: String { senses.first?.zh ?? "" }
    var pos: String { senses.first?.pos ?? "" }
    var topicName: String { Topic.all.first { $0.id == topic }?.name ?? topic }
    func hasMedia(_ kind: String) -> Bool {
        let flag = ["img": 1, "thumb": 1, "uk": 2, "us": 4, "ex": 8, "ex2": 16][kind] ?? 0
        return mediaFlags & flag != 0
    }

    enum CodingKeys: String, CodingKey {
        case id, uk, us, senses, tip, cefr, topic, note
        case word = "w"
        case examples = "ex"
        case collocations = "col"
        case family = "fam"
        case synonyms = "syn"
        case antonyms = "ant"
    }
}
