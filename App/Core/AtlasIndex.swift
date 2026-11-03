import Foundation

/// The bundled compact manifest is shared by catalog validation and media availability checks.
struct AtlasIndex: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        let id: String
        let flags: Int

        init(from decoder: any Decoder) throws {
            var values = try decoder.unkeyedContainer()
            id = try values.decode(String.self)
            _ = try values.decode(String.self)  // Headword
            _ = try values.decode(String.self)  // Chinese meaning
            _ = try values.decode(String.self)  // IPA
            _ = try values.decode(Int.self)  // CEFR index
            _ = try values.decode(Int.self)  // Topic index
            flags = try values.decode(Int.self)
        }
    }

    let count: Int
    let words: [Row]

    private enum CodingKeys: String, CodingKey { case count, words }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        count = try values.decode(Int.self, forKey: .count)
        words = try values.decode([Row].self, forKey: .words)
        guard count == words.count, Set(words.map(\.id)).count == count else {
            throw CatalogError.inconsistentCatalog
        }
    }

    var mediaFlagsByID: [String: Int] {
        Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0.flags) })
    }

    static func loadMediaFlags(bundle: Bundle = .main) -> [String: Int] {
        guard let url = bundle.url(forResource: "atlas-index", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let index = try? JSONDecoder().decode(Self.self, from: data)
        else { return [:] }
        return index.mediaFlagsByID
    }
}
