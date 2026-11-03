import SwiftUI

struct WordArtwork: View {
    let wordID: String
    let topic: String
    var full: Bool = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bitmap: CGImage?
    @State private var bitmapWordID: String?

    var body: some View {
        GeometryReader { geometry in
            let request = ArtworkRequest(
                wordID: wordID, full: full,
                pixelSize: Self.pixelSize(for: geometry.size, scale: displayScale))
            ZStack {
                placeholder
                if let bitmap, bitmapWordID == wordID {
                    Image(decorative: bitmap, scale: displayScale)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: bitmap != nil)
            .task(id: request) { await loadArtwork(request) }
        }
        .accessibilityHidden(true)
    }

    private struct ArtworkRequest: Hashable {
        let wordID: String
        let full: Bool
        let pixelSize: Int
    }

    private static func pixelSize(for size: CGSize, scale: CGFloat) -> Int {
        let requested = max(size.width, size.height) * scale
        let bucket = Int((requested / 128).rounded(.up)) * 128
        return min(1_024, max(128, bucket))
    }

    private func loadArtwork(_ request: ArtworkRequest) async {
        bitmap = nil
        bitmapWordID = nil
        do {
            let url = try await MediaRepository.shared.localURL(
                wordID: request.wordID, kind: request.full ? .image : .thumbnail
            )
            try Task.checkCancellation()
            let decoded = await ArtworkImageCache.shared.image(at: url, maximumPixelSize: request.pixelSize)
            try Task.checkCancellation()
            bitmapWordID = request.wordID
            bitmap = decoded
        } catch {
            // Keep the topic placeholder visible when cancelled, offline or unavailable.
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(
                red: colorScheme == .dark ? 0.14 : 0.91, green: colorScheme == .dark ? 0.20 : 0.93,
                blue: colorScheme == .dark ? 0.18 : 0.86)
            Circle()
                .fill(.primary.opacity(0.025))
                .padding(25)
            Image(systemName: symbol)
                .font(.system(size: full ? 64 : 38, weight: .ultraLight))
                .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.39).opacity(0.65))
        }
    }

    private var symbol: String {
        switch topic {
        case "education": "books.vertical"
        case "work": "briefcase"
        case "technology": "desktopcomputer"
        case "science": "atom"
        case "environment", "nature": "leaf"
        case "health": "heart"
        case "society": "person.2"
        case "government": "building.columns"
        case "economy": "chart.line.uptrend.xyaxis"
        case "media": "newspaper"
        case "arts": "paintpalette"
        case "travel": "globe.europe.africa"
        case "city": "building.2"
        case "daily": "cup.and.saucer"
        case "emotion": "sun.max"
        case "thinking": "sparkle"
        case "sport": "figure.run"
        case "history": "hourglass"
        default: "book.closed"
        }
    }
}
