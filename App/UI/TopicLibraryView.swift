import SwiftUI

struct TopicLibraryView: View {
    @Environment(VocabularyRepository.self) private var vocabulary
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            let metrics = AtlasLayoutMetrics(width: geometry.size.width)
            let columns =
                dynamicTypeSize.isAccessibilitySize
                ? 1 : geometry.size.width < 600 ? 2 : geometry.size.width < 900 ? 3 : 4
            let counts = Dictionary(grouping: vocabulary.entries, by: \.topic).mapValues(\.count)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AtlasPageTitle(
                        title: "找到你的好奇心。", subtitle: "19 个主题，每一个都是认识世界的入口。", eyebrow: "EXPLORE BY TOPIC",
                        compact: metrics.isCompact)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14), count: columns),
                        spacing: 16
                    ) {
                        ForEach(vocabulary.topics) { topic in
                            TopicCard(topic: topic, count: counts[topic.id]) {
                                router.explore(topic: topic.id)
                                dismiss()
                            }
                        }
                    }
                }.padding(.horizontal, metrics.horizontalPadding).padding(.top, 14).padding(.bottom, 28)
                    .frame(maxWidth: 1040).frame(maxWidth: .infinity)
            }.background(AtlasTheme.paper)
        }
        .navigationTitle("全部主题")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).accessibilityLabel("关闭主题列表")
            }
        }
    }
}
