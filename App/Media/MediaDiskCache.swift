import AVFoundation
import Foundation
import ImageIO

/// File operations are synchronous and serialized by the owning MediaRepository actor.
/// Cache filenames remain stable across app versions; media never enters SwiftData.
struct MediaDiskCache: Sendable {
    let directory: URL
    let capacity: Int64

    init(directory: URL, capacity: Int64) {
        self.directory = directory
        self.capacity = max(1, capacity)
    }

    func fileURL(wordID: String, kind: MediaKind) -> URL {
        directory.appendingPathComponent("\(kind.rawValue)-\(wordID)").appendingPathExtension(kind.fileExtension)
    }

    func cachedFile(at url: URL, kind: MediaKind) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            try Self.validateFile(url, kind: kind)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    func store(_ data: Data, at destination: URL, kind: MediaKind) throws -> URL {
        guard !data.isEmpty, Int64(data.count) <= capacity else { throw MediaError.invalidMedia }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".partial-\(UUID().uuidString)")
            .appendingPathExtension(kind.fileExtension)
        defer { try? FileManager.default.removeItem(at: temporary) }

        try data.write(to: temporary, options: .atomic)
        try Self.validateFile(temporary, kind: kind)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        evictOldFiles(keeping: destination)
        return destination
    }

    var size: Int64 { cachedFiles().reduce(0) { $0 + $1.bytes } }

    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    static func validateFile(_ url: URL, kind: MediaKind) throws {
        if kind.isImage { try validateImage(url) } else { try validateAudio(url) }
    }

    private static func validateImage(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            CGImageSourceGetCount(source) > 0,
            CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 8,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary) != nil
        else { throw MediaError.invalidMedia }
    }

    private static func validateAudio(_ url: URL) throws {
        do {
            let audio = try AVAudioFile(forReading: url)
            guard audio.length > 0,
                let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 128)
            else {
                throw MediaError.invalidMedia
            }
            try audio.read(into: buffer, frameCount: 128)
            guard buffer.frameLength > 0 else { throw MediaError.invalidMedia }
        } catch {
            throw MediaError.invalidMedia
        }
    }

    private struct CachedFile {
        let url: URL
        let bytes: Int64
        let accessed: Date
    }

    private func cachedFiles() -> [CachedFile] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            )
        else { return [] }

        return files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return CachedFile(
                url: url, bytes: Int64(values.fileSize ?? 0), accessed: values.contentModificationDate ?? .distantPast)
        }
    }

    private func evictOldFiles(keeping protectedURL: URL) {
        let files = cachedFiles()
        var total = files.reduce(Int64(0)) { $0 + $1.bytes }
        for file in files.sorted(by: { $0.accessed < $1.accessed }) where file.url != protectedURL {
            guard total > capacity else { break }
            if (try? FileManager.default.removeItem(at: file.url)) != nil { total -= file.bytes }
        }
    }
}
