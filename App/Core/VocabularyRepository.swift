import Foundation
import Observation

@MainActor @Observable
final class VocabularyRepository {
    private(set) var entries: [VocabularyEntry] = []
    private(set) var isLoading = false
    var errorMessage: String?
    let topics = Topic.all

    @ObservationIgnored private var byID: [String: VocabularyEntry] = [:]
    @ObservationIgnored private let resourceDirectory: URL?
    @ObservationIgnored private var pendingLoad: Task<Void, Never>?

    init(resourceDirectory: URL? = nil) { self.resourceDirectory = resourceDirectory }

    /// All callers await publication of the same catalog, including callers from a second window.
    func load() async {
        guard entries.isEmpty else { return }
        if let pendingLoad {
            await pendingLoad.value
            return
        }

        isLoading = true
        errorMessage = nil
        let task = Task { await loadCatalog() }
        pendingLoad = task
        await task.value
    }

    func word(id: String) -> VocabularyEntry? { byID[id] }

    private func loadCatalog() async {
        defer {
            isLoading = false
            pendingLoad = nil
        }
        do {
            let files = try CatalogFiles(directory: resourceDirectory)
            let decoded = try await Task.detached(priority: .userInitiated) {
                try files.decode()
            }.value
            byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            entries = decoded
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CatalogFiles: Sendable {
    let words: URL
    let index: URL

    init(directory: URL?) throws {
        guard
            let words = directory?.appendingPathComponent("word-atlas.json")
                ?? Bundle.main.url(forResource: "word-atlas", withExtension: "json"),
            let index = directory?.appendingPathComponent("atlas-index.json")
                ?? Bundle.main.url(forResource: "atlas-index", withExtension: "json")
        else {
            throw CatalogError.missingResource
        }
        self.words = words
        self.index = index
    }

    func decode() throws -> [VocabularyEntry] {
        let decoder = JSONDecoder()
        var entries = try decoder.decode([VocabularyEntry].self, from: Data(contentsOf: words))
        let manifest = try decoder.decode(AtlasIndex.self, from: Data(contentsOf: index))
        // The manifest validates unique IDs; matching their order also validates entry identity and count.
        guard entries.map(\.id) == manifest.words.map(\.id) else { throw CatalogError.inconsistentCatalog }
        for position in entries.indices { entries[position].mediaFlags = manifest.words[position].flags }
        return entries
    }
}

enum CatalogError: LocalizedError {
    case missingResource, inconsistentCatalog

    var errorDescription: String? {
        switch self {
        case .missingResource: "找不到内置词库，请重新安装应用。学习记录不会被删除。"
        case .inconsistentCatalog: "词库与媒体索引不一致，无法载入。"
        }
    }
}
