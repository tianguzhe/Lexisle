import Foundation

/// Coordinates CDN requests and shared downloads; MediaDiskCache owns all file operations.
actor MediaRepository {
    static let shared = MediaRepository()
    static let defaultBaseURL = URL(string: "https://0xlei.tech/words/atlas/")!
    static let defaultCapacity: Int64 = 512 * 1_024 * 1_024

    private struct PendingDownload {
        let id = UUID()
        let task: Task<URL, Error>
    }

    private let baseURL: URL
    private let cache: MediaDiskCache
    private let session: URLSession
    private let mediaFlags: [String: Int]
    private var pending: [URL: PendingDownload] = [:]

    init(
        baseURL: URL = MediaRepository.defaultBaseURL,
        cacheDirectory: URL? = nil,
        session: URLSession? = nil,
        capacity: Int64 = MediaRepository.defaultCapacity,
        mediaFlags: [String: Int]? = nil
    ) {
        self.baseURL = baseURL
        let directory =
            cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WordAtlas/Media-v1", isDirectory: true)
        cache = MediaDiskCache(directory: directory, capacity: capacity)
        self.session = session ?? Self.makeSession()
        self.mediaFlags = mediaFlags ?? AtlasIndex.loadMediaFlags()
    }

    nonisolated static func remoteURL(wordID: String, kind: MediaKind, baseURL: URL = defaultBaseURL) throws -> URL {
        guard !wordID.isEmpty,
            wordID.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
            })
        else { throw MediaError.invalidIdentifier }
        return baseURL.appendingPathComponent(kind.folder, isDirectory: true)
            .appendingPathComponent(wordID).appendingPathExtension(kind.fileExtension)
    }

    func hasMedia(wordID: String, kind: MediaKind) -> Bool {
        if let flags = mediaFlags[wordID] { return flags & kind.availabilityBit != 0 }
        return kind != .example2
    }

    func localURL(wordID: String, kind: MediaKind) async throws -> URL {
        try Task.checkCancellation()
        let remote = try Self.remoteURL(wordID: wordID, kind: kind, baseURL: baseURL)
        guard hasMedia(wordID: wordID, kind: kind) else { throw MediaError.unavailable }
        let destination = cache.fileURL(wordID: wordID, kind: kind)
        if let cached = cache.cachedFile(at: destination, kind: kind) { return cached }

        let request: PendingDownload
        if let existing = pending[destination] {
            request = existing
        } else {
            request = PendingDownload(task: Task { try await self.download(remote, to: destination, kind: kind) })
            pending[destination] = request
        }
        defer {
            // clearCache may have replaced this request while it was suspended.
            if pending[destination]?.id == request.id { pending[destination] = nil }
        }
        // Cancelling one reader must not cancel another reader's shared download.
        let url = try await request.task.value
        try Task.checkCancellation()
        return url
    }

    func prefetch(wordIDs: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for id in Set(wordIDs.prefix(5)) {
                group.addTask {
                    for kind in [MediaKind.image, .uk, .us] {
                        guard !Task.isCancelled else { return }
                        _ = try? await self.localURL(wordID: id, kind: kind)
                    }
                }
            }
        }
    }

    func cacheSize() -> Int64 { cache.size }

    func clearCache() async throws {
        for request in pending.values {
            request.task.cancel()
        }
        pending.removeAll()
        try cache.clear()
        await ArtworkImageCache.shared.clear()
    }

    nonisolated static func validateFile(_ url: URL, kind: MediaKind) throws {
        try MediaDiskCache.validateFile(url, kind: kind)
    }

    private func download(_ remote: URL, to destination: URL, kind: MediaKind) async throws -> URL {
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: remote)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue(kind.acceptHeader, forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse else { throw MediaError.invalidResponse }
                guard (200..<300).contains(response.statusCode) else { throw MediaError.http(response.statusCode) }
                guard data.count <= 32 * 1_024 * 1_024 else { throw MediaError.invalidMedia }
                return try cache.store(data, at: destination, kind: kind)
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                guard attempt == 0, Self.canRetry(error) else { throw error }
                try await Task.sleep(for: .milliseconds(350))
            }
        }
        throw MediaError.invalidResponse
    }

    private nonisolated static func canRetry(_ error: Error) -> Bool {
        if let networkError = error as? URLError,
            [.notConnectedToInternet, .cancelled, .unsupportedURL].contains(networkError.code)
        {
            return false
        }
        if let mediaError = error as? MediaError {
            switch mediaError {
            case .http(let code): return code >= 500 || code == 429
            case .invalidMedia, .invalidIdentifier, .unavailable: return false
            case .invalidResponse: return true
            }
        }
        return true
    }

    private nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 25
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}
