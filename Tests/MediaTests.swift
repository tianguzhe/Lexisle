import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import WordAtlas

@Suite("Media cache and CDN", .serialized)
struct MediaTests {
    @Test func buildsCDNPathsAndRejectsTraversal() throws {
        let url = try MediaRepository.remoteURL(wordID: "united-kingdom", kind: .example2)
        #expect(url.absoluteString == "https://0xlei.tech/words/atlas/audio/ex2/united-kingdom.mp3")
        #expect(throws: MediaError.self) { try MediaRepository.remoteURL(wordID: "../secret", kind: .image) }
        #expect(
            try MediaRepository.remoteURL(wordID: "library", kind: .thumbnail).path.hasSuffix("/thumb/library.webp"))
    }

    @Test func concurrentReadersShareDownloadAndThenUseDisk() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        MediaStubProtocol.state.set(data: fixture.image, status: 200, delay: 0.05)
        let repository = fixture.repository()
        async let first = repository.localURL(wordID: "library", kind: .image)
        async let second = repository.localURL(wordID: "library", kind: .image)
        let (firstURL, secondURL) = try await (first, second)
        #expect(firstURL == secondURL)
        #expect(MediaStubProtocol.state.requestCount == 1)
        _ = try await repository.localURL(wordID: "library", kind: .image)
        #expect(MediaStubProtocol.state.requestCount == 1)
        #expect(await repository.cacheSize() == Int64(fixture.image.count))
    }

    @Test func corruptCacheIsReplacedAndMissingSecondExampleDoesNotDownload() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        MediaStubProtocol.state.set(data: fixture.image, status: 200)
        try Data("not an image".utf8).write(to: fixture.directory.appendingPathComponent("image-library.webp"))
        let repository = fixture.repository(flags: ["library": 15])
        let restored = try await repository.localURL(wordID: "library", kind: .image)
        try MediaRepository.validateFile(restored, kind: .image)
        #expect(MediaStubProtocol.state.requestCount == 1)
        await #expect(throws: MediaError.self) {
            try await repository.localURL(wordID: "library", kind: .example2)
        }
        #expect(MediaStubProtocol.state.requestCount == 1)
    }

    @Test func rejectsHTTPFailuresAndCorruptDownloadsWithoutCaching() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        MediaStubProtocol.state.set(data: fixture.image, status: 404)
        let repository = fixture.repository()
        await #expect(throws: MediaError.self) {
            try await repository.localURL(wordID: "missing", kind: .image)
        }
        #expect(MediaStubProtocol.state.requestCount == 1)
        #expect(await repository.cacheSize() == 0)
        MediaStubProtocol.state.set(data: Data("corrupt".utf8), status: 200)
        await #expect(throws: MediaError.self) {
            try await repository.localURL(wordID: "broken", kind: .image)
        }
        #expect(await repository.cacheSize() == 0)
    }

    @Test func evictsLeastRecentlyUsedAndClearsCache() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        MediaStubProtocol.state.set(data: fixture.image, status: 200)
        let repository = fixture.repository(capacity: Int64(fixture.image.count * 2))
        let first = try await repository.localURL(wordID: "first", kind: .image)
        let second = try await repository.localURL(wordID: "second", kind: .image)
        _ = try await repository.localURL(wordID: "first", kind: .image)
        _ = try await repository.localURL(wordID: "third", kind: .image)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(await repository.cacheSize() <= Int64(fixture.image.count * 2))
        try await repository.clearCache()
        #expect(await repository.cacheSize() == 0)
    }

    @Test func cancelledReaderDoesNotCancelOtherReaders() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        MediaStubProtocol.state.set(data: fixture.image, status: 200, delay: 0.05)
        let repository = fixture.repository()
        let cancelled = Task { try await repository.localURL(wordID: "library", kind: .image) }
        let survivor = Task { try await repository.localURL(wordID: "library", kind: .image) }
        try await Task.sleep(for: .milliseconds(10))
        cancelled.cancel()
        let url = try await survivor.value
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(MediaStubProtocol.state.requestCount == 1)
    }

    @Test func clearingCacheCancelsDownloadsWithoutRecreatingFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        MediaStubProtocol.state.set(data: fixture.image, status: 200, delay: 0.15)
        let repository = fixture.repository()
        let download = Task { try await repository.localURL(wordID: "library", kind: .image) }
        try await waitForRequest()

        try await repository.clearCache()
        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(await repository.cacheSize() == 0)
        #expect(
            !FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("image-library.webp").path)
        )

        MediaStubProtocol.state.set(data: fixture.image, status: 200)
        let fresh = try await repository.localURL(wordID: "library", kind: .image)
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(MediaStubProtocol.state.requestCount == 1)
    }

    @Test func retriesTemporaryServerFailuresOnlyOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        MediaStubProtocol.state.set(data: fixture.image, status: 503)
        let repository = fixture.repository()

        await #expect(throws: MediaError.self) {
            try await repository.localURL(wordID: "library", kind: .image)
        }
        #expect(MediaStubProtocol.state.requestCount == 2)
        #expect(await repository.cacheSize() == 0)
    }

    private func waitForRequest() async throws {
        for _ in 0..<100 {
            if MediaStubProtocol.state.requestCount > 0 { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected media request to start")
    }

    private struct Fixture {
        let directory: URL
        let image: Data

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("MediaTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let context = try #require(
                CGContext(
                    data: nil, width: 4, height: 4, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.3, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            let bitmap = try #require(context.makeImage())
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, bitmap, nil)
            #expect(CGImageDestinationFinalize(destination))
            image = data as Data
        }

        func repository(capacity: Int64 = MediaRepository.defaultCapacity, flags: [String: Int] = [:])
            -> MediaRepository
        {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MediaStubProtocol.self]
            return MediaRepository(
                baseURL: URL(string: "https://media.example.test/atlas/")!,
                cacheDirectory: directory, session: URLSession(configuration: configuration), capacity: capacity,
                mediaFlags: flags)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }
}

private final class MediaStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var status = 200
    private var delay = 0.0
    private var count = 0

    var requestCount: Int { lock.withLock { count } }

    func set(data: Data, status: Int, delay: Double = 0) {
        lock.withLock {
            self.data = data
            self.status = status
            self.delay = delay
            count = 0
        }
    }

    func response() -> (Data, Int, Double) {
        lock.withLock {
            count += 1
            return (data, status, delay)
        }
    }
}

private final class MediaStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = MediaStubState()
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (data, status, delay) = Self.state.response()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            guard !lock.withLock({ stopped }), let url = request.url,
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() { lock.withLock { stopped = true } }
}
