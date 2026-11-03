import Observation
import SwiftUI

enum AppDestination: String, CaseIterable, Identifiable {
    case today, atlas, favorites, profile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "今日"
        case .atlas: "图鉴"
        case .favorites: "收藏"
        case .profile: "我的"
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.horizon"
        case .atlas: "square.grid.2x2"
        case .favorites: "bookmark"
        case .profile: "chart.bar.xaxis"
        }
    }
}

@MainActor @Observable final class AppRouter {
    let windowID = UUID()
    var destination: AppDestination = .today
    var selectedWordID: String?
    var presentedWord: VocabularyEntry?
    var usesInspector = false
    var showsStudy = false
    var showsSettings = false
    var showsTopics = false
    var searchText = ""
    var topicFilter = "all"
    var levelFilter = "all"
    var statusFilter = "all"
    var searchFocusToken = 0
    var notice: String?

    var hasActiveFilters: Bool {
        topicFilter != "all" || levelFilter != "all" || statusFilter != "all"
    }

    func startLearning(store: AppStore, entries: [VocabularyEntry], reviewOnly: Bool = false) {
        guard StudyPresentation.shared.owner == nil || StudyPresentation.shared.owner == windowID else {
            notice = "学习正在另一个窗口中进行，请回到那个窗口继续。"
            return
        }
        store.startSession(entries: entries, reviewOnly: reviewOnly)
        guard store.session != nil else {
            destination = .profile
            return
        }
        StudyPresentation.shared.owner = windowID
        showsStudy = true
    }

    func releaseStudy() {
        if StudyPresentation.shared.owner == windowID { StudyPresentation.shared.owner = nil }
    }

    func show(_ word: VocabularyEntry) {
        selectedWordID = word.id
        if !usesInspector { presentedWord = word }
    }

    func explore(topic: String = "all") {
        searchText = ""
        resetFilters()
        topicFilter = topic
        destination = .atlas
    }

    func resetFilters() {
        topicFilter = "all"
        levelFilter = "all"
        statusFilter = "all"
    }
}

@MainActor private final class StudyPresentation {
    static let shared = StudyPresentation()
    var owner: UUID?
}

private struct AtlasRouterKey: FocusedValueKey { typealias Value = AppRouter }
extension FocusedValues {
    var atlasRouter: AppRouter? {
        get { self[AtlasRouterKey.self] }
        set { self[AtlasRouterKey.self] = newValue }
    }
}
