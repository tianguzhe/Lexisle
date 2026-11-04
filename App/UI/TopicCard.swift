import SwiftUI

struct TopicCard: View {
    let topic: Topic
    var count: Int? = nil
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                artwork
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.name).font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if let count {
                            Text("\(count.formatted()) 个词").font(.caption2).foregroundStyle(AtlasTheme.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(AtlasTheme.secondary)
                        .accessibilityHidden(true)
                }.foregroundStyle(AtlasTheme.ink).padding(.horizontal, 2).padding(.bottom, 3)
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(AtlasTheme.line.opacity(0.6), lineWidth: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(topic.name)
        .accessibilityValue(count.map { "\($0.formatted()) 个词" } ?? "")
        .accessibilityIdentifier("topic-\(topic.id)")
    }

    @ViewBuilder private var artwork: some View {
        let image = GeometryReader { geometry in
            Image("topic-\(topic.id)").resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        if dynamicTypeSize.isAccessibilitySize {
            image.frame(height: 160)
        } else {
            image.aspectRatio(1.45, contentMode: .fit)
        }
    }

}
