import Foundation

enum MediaKind: String, CaseIterable, Codable, Sendable {
    case thumbnail, image, uk, us, example, example2

    var folder: String {
        switch self {
        case .thumbnail: "thumb"
        case .image: "img"
        case .uk: "audio/uk"
        case .us: "audio/us"
        case .example: "audio/ex"
        case .example2: "audio/ex2"
        }
    }

    var fileExtension: String { isImage ? "webp" : "mp3" }
    var isImage: Bool { self == .thumbnail || self == .image }
    var acceptHeader: String { isImage ? "image/webp,image/*" : "audio/mpeg,audio/*" }

    var availabilityBit: Int {
        switch self {
        case .thumbnail, .image: 1
        case .uk: 2
        case .us: 4
        case .example: 8
        case .example2: 16
        }
    }
}

enum MediaError: LocalizedError, Sendable {
    case invalidIdentifier, unavailable, invalidResponse
    case http(Int)
    case invalidMedia

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier: "词条资源标识无效。"
        case .unavailable: "这个词条没有对应的原声录音。"
        case .invalidResponse: "资源服务器返回了无法识别的响应。"
        case .http(let code): "资源暂时无法下载（\(code)）。"
        case .invalidMedia: "资源文件损坏或格式不受支持。"
        }
    }
}
