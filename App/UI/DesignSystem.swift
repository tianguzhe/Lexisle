import SwiftUI

enum AtlasTheme {
    static let paper = adaptive(0xF6F5EF, 0x191E1B)
    static let surface = adaptive(0xFFFEFA, 0x232A25)
    static let ink = adaptive(0x203D32, 0xE5EBDF)
    static let secondary = adaptive(0x687364, 0xAFBBA9)
    static let green = adaptive(0x315C46, 0xA9C6A2)
    static let moss = adaptive(0xE5EAD9, 0x344134)
    static let line = adaptive(0xE4E6DA, 0x394239)
    static let clay = adaptive(0xB86C4C, 0xDDA386)
    static let hero = Color(hex: 0x233F32)

    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        #if os(iOS)
        Color(
            uiColor: UIColor { traits in
                let value = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((value >> 16) & 255) / 255,
                    green: CGFloat((value >> 8) & 255) / 255,
                    blue: CGFloat(value & 255) / 255, alpha: 1)
            })
        #else
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(
                    red: CGFloat((value >> 16) & 255) / 255,
                    green: CGFloat((value >> 8) & 255) / 255,
                    blue: CGFloat(value & 255) / 255, alpha: 1)
            })
        #endif
    }
}

/// English learning content uses book typography; interface labels and IPA retain system fonts.
enum AtlasTypography {
    static let wordCard = Font.custom("Lora-SemiBold", size: size(mobile: 18, desktop: 16), relativeTo: .headline)
    static let wordFeature = Font.custom("Lora-SemiBold", size: size(mobile: 24, desktop: 22), relativeTo: .title2)
    static let wordOption = Font.custom("Lora-SemiBold", size: size(mobile: 20, desktop: 18), relativeTo: .title3)
    static let englishBody = Font.custom("Lora-Regular", size: size(mobile: 17, desktop: 15), relativeTo: .body)
    static let englishDetail = Font.custom(
        "Lora-Regular", size: size(mobile: 15, desktop: 13), relativeTo: .subheadline)
    static let spelling = Font.custom("Lora-Regular", size: size(mobile: 22, desktop: 20), relativeTo: .title2)
    static let englishQuote = Font.custom("Lora-Italic", size: size(mobile: 15, desktop: 13), relativeTo: .subheadline)

    static func wordTitle(size: CGFloat) -> Font {
        .custom("Lora-SemiBold", size: size, relativeTo: .largeTitle)
    }

    private static func size(mobile: CGFloat, desktop: CGFloat) -> CGFloat {
        #if os(macOS)
        desktop
        #else
        mobile
        #endif
    }
}

struct AtlasLayoutMetrics: Equatable {
    let width: CGFloat
    var isCompact: Bool { width < 600 }
    var horizontalPadding: CGFloat { width < 400 ? 18 : width < 700 ? 24 : 32 }
    var sectionSpacing: CGFloat { isCompact ? 24 : 32 }
    var contentWidth: CGFloat { 1120 }
}

struct AtlasPageTitle: View {
    let title: String
    let subtitle: String
    var eyebrow: String? = nil
    var compact = false
    @ScaledMetric(relativeTo: .largeTitle) private var compactSize: CGFloat = 27
    @ScaledMetric(relativeTo: .largeTitle) private var regularSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            if let eyebrow { Eyebrow(text: eyebrow) }
            Text(title).font(.system(size: compact ? compactSize : regularSize, weight: .medium, design: .serif))
                .tracking(-0.4).foregroundStyle(AtlasTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(AtlasTheme.secondary)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct AtlasMark: View {
    var size: CGFloat = 42
    var body: some View {
        Image("BrandMark")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = AtlasTheme.secondary
    var body: some View {
        Text(text).font(.system(.caption2, design: .monospaced, weight: .medium))
            .tracking(1.2).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SectionHeading<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let layout =
            dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(.headline, weight: .semibold)).foregroundStyle(AtlasTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(AtlasTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            trailing.fixedSize(horizontal: dynamicTypeSize < .xxxLarge, vertical: true)
        }
    }
}

struct AtlasPrimaryButton: ButtonStyle {
    var light = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, weight: .semibold))
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(minHeight: 48)
            .foregroundStyle(light ? AtlasTheme.hero : Color.white)
            .background(
                light ? Color(hex: 0xECF0DD) : AtlasTheme.hero,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .opacity(!isEnabled ? 0.42 : configuration.isPressed ? 0.78 : 1)
    }
}

struct AtlasSurface: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(AtlasTheme.line.opacity(0.7), lineWidth: 0.8))
    }
}

extension View {
    func atlasSurface(padding: CGFloat = 20) -> some View { modifier(AtlasSurface(padding: padding)) }
}

struct LevelBadge: View {
    let level: String
    var body: some View {
        Text(level).font(.system(.caption2, design: .monospaced, weight: .semibold))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(AtlasTheme.green).background(AtlasTheme.moss, in: Capsule())
    }
}

struct EmptyAtlasView: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(AtlasTheme.green).frame(width: 90, height: 90)
                .background(AtlasTheme.moss, in: RoundedRectangle(cornerRadius: 28))
            Text(title).font(.title3.weight(.medium)).foregroundStyle(AtlasTheme.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(message).font(.subheadline).foregroundStyle(AtlasTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 300)
        }.frame(maxWidth: .infinity, minHeight: 280).padding(24)
    }
}

extension String {
    var topicSymbol: String {
        switch self {
        case "education": "graduationcap"
        case "work": "briefcase"
        case "technology": "cpu"
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
        case "thinking": "lightbulb"
        case "sport": "figure.run"
        case "history": "clock"
        default: "book"
        }
    }
}
