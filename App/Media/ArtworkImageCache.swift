import Foundation
import ImageIO

private final class ArtworkBitmap: NSObject, @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

actor ArtworkImageCache {
    static let shared = ArtworkImageCache()
    private let cache = NSCache<NSString, ArtworkBitmap>()

    init() {
        cache.totalCostLimit = 48 * 1_024 * 1_024
        cache.countLimit = 100
    }

    func image(at url: URL, maximumPixelSize: Int) -> CGImage? {
        let key = "\(url.path)-\(maximumPixelSize)" as NSString
        if let existing = cache.object(forKey: key) { return existing.image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let bitmap = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
        else { return nil }
        cache.setObject(ArtworkBitmap(bitmap), forKey: key, cost: bitmap.bytesPerRow * bitmap.height)
        return bitmap
    }

    func clear() { cache.removeAllObjects() }
}
