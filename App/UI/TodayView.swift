import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(VocabularyRepository.self) private var vocabulary
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroFont: CGFloat = 27

    private var dueCount: Int { store.dueIDs().count }
    private var newCount: Int { store.nextNewWords(entries: vocabulary.entries).count }
    private var hasSession: Bool { store.session != nil && store.session?.finished == false }
    private var dayWord: VocabularyEntry? {
        guard !vocabulary.entries.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let featured = ["serendipity", "bloom", "wander", "promising", "tranquil", "curiosity", "embrace"]
        return vocabulary.word(id: featured[day % featured.count]) ?? vocabulary.entries[day % vocabulary.entries.count]
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = AtlasLayoutMetrics(width: geometry.size.width)
            let wide = geometry.size.width > 760
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    header(compact: metrics.isCompact)
                    journeyCard(
                        wide: wide, width: min(metrics.contentWidth, metrics.width) - metrics.horizontalPadding * 2)
                    let layout =
                        wide
                        ? AnyLayout(HStackLayout(alignment: .top, spacing: 22)) : AnyLayout(VStackLayout(spacing: 22))
                    layout {
                        if let word = dayWord { dailyWord(word, wide: wide).frame(maxWidth: .infinity) }
                        weeklyProgress(wide: wide).frame(maxWidth: .infinity)
                    }
                    topics(width: min(metrics.width, metrics.contentWidth))
                    Label("每天一点，慢慢生长。", systemImage: "leaf")
                        .font(.caption).foregroundStyle(AtlasTheme.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8).accessibilityHidden(true)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.isCompact ? 12 : 22).padding(.bottom, 28)
                .frame(maxWidth: metrics.contentWidth).frame(maxWidth: .infinity)
            }.background(AtlasTheme.paper)
        }
        .navigationTitle("")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AtlasPageTitle(
                title: "\(greeting)，探索者。", subtitle: "留一点时间，认识新的世界。",
                eyebrow: Date().formatted(.dateTime.month().day().weekday(.wide)), compact: compact
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                Button {
                    router.destination = .profile
                } label: {
                    Image(systemName: "leaf").font(.system(size: 20, weight: .light))
                        .frame(width: 44, height: 44).background(AtlasTheme.moss, in: Circle())
                }.buttonStyle(.plain).foregroundStyle(AtlasTheme.green).accessibilityLabel("查看我的学习进度")
            }
        }
    }

    private func journeyCard(wide: Bool, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: wide ? 20 : 16) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle").font(.caption)
                    Eyebrow(text: hasSession ? "继续这一章" : "今日学习", color: Color(hex: 0xC2D0B8))
                    Spacer(minLength: 0)
                    if !wide {
                        Image(systemName: "book.pages").font(.title3.weight(.light)).foregroundStyle(
                            Color(hex: 0xC2D0B8))
                    }
                }
                Text(hasSession ? "继续你的学习旅程。" : newCount + dueCount == 0 ? "今天的计划，完成了。" : "每天一点，世界更近。")
                    .font(.system(size: wide ? heroFont * 1.25 : heroFont, weight: .medium, design: .serif))
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { planLabels }
                    VStack(alignment: .leading, spacing: 8) { planLabels }
                }.font(.subheadline).foregroundStyle(Color(hex: 0xCDD7C5))
                Button {
                    if !hasSession && newCount + dueCount == 0 {
                        router.destination = .profile
                    } else {
                        router.startLearning(store: store, entries: vocabulary.entries)
                    }
                } label: {
                    HStack(spacing: 18) {
                        Text(hasSession ? "继续学习" : newCount + dueCount == 0 ? "查看今日成果" : "开始今日学习")
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                    }.frame(maxWidth: wide ? 240 : .infinity)
                }
                .buttonStyle(AtlasPrimaryButton(light: true))
                .disabled(vocabulary.entries.isEmpty)
                if dueCount > 0 && !hasSession {
                    Button("今天先复习") {
                        router.startLearning(store: store, entries: vocabulary.entries, reviewOnly: true)
                    }.buttonStyle(.plain).font(.caption).frame(minHeight: 44).foregroundStyle(Color(hex: 0xCDD7C5))
                }
            }.padding(wide ? 30 : 22).frame(maxWidth: .infinity, alignment: .leading)
            if wide && !dynamicTypeSize.isAccessibilitySize {
                Image("brand-hero").resizable().scaledToFill()
                    .frame(width: width * 0.39, height: 280).clipped()
                    .overlay(alignment: .leading) {
                        LinearGradient(colors: [AtlasTheme.hero, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 50)
                    }.accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color(hex: 0xF5F3E6)).background(AtlasTheme.hero)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder private var planLabels: some View {
        Label("\(newCount) 个新词", systemImage: "leaf")
        if dueCount > 0 {
            Label("\(dueCount) 个待复习", systemImage: "arrow.clockwise")
        } else {
            Text("约 \(max(1, newCount)) 分钟").foregroundStyle(Color(hex: 0xADBEA6))
        }
    }

    private func dailyWord(_ word: VocabularyEntry, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "每日一词", subtitle: "今天，和这个词见一面") {
                Image(systemName: "sparkle").foregroundStyle(AtlasTheme.clay)
            }
            Button {
                router.show(word)
            } label: {
                let layout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
                layout {
                    WordArtwork(wordID: word.id, topic: word.topic)
                        .frame(width: 86, height: 96).clipShape(RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 9) {
                        Text(word.word).font(.system(.title2, design: .serif, weight: .medium))
                            .foregroundStyle(AtlasTheme.ink).lineLimit(2).minimumScaleFactor(0.7)
                        Text(word.uk).font(.caption).foregroundStyle(AtlasTheme.secondary)
                        Text(word.meaning).font(.subheadline).foregroundStyle(AtlasTheme.ink).lineLimit(2)
                        Label("翻开词卡", systemImage: "arrow.up.right").font(.caption).foregroundStyle(AtlasTheme.green)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.frame(minHeight: wide ? 178 : nil, alignment: .top).atlasSurface()
    }

    private func weeklyProgress(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "本周足迹", subtitle: "一点一滴，都算数") {
                Label("\(store.streak) 天", systemImage: "flame").font(.caption.weight(.medium)).foregroundStyle(
                    AtlasTheme.clay)
            }
            HStack(spacing: 0) {
                ForEach(store.activity(days: 7)) { day in
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(day.reviewed > 0 ? AtlasTheme.green : AtlasTheme.paper)
                            if day.reviewed > 0 {
                                Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(
                                    AtlasTheme.surface)
                            } else {
                                Circle().fill(AtlasTheme.line).frame(width: 5, height: 5)
                            }
                        }.frame(width: 30, height: 30)
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2).foregroundStyle(AtlasTheme.secondary)
                    }.frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(day.date.formatted(date: .abbreviated, time: .omitted))，学习 \(day.reviewed) 词")
                }
            }
            HStack {
                Text("今天已认识 \(store.todayNewCount) 个新词")
                Spacer()
                Text("\(store.todayNewCount) / \(store.preferences.dailyGoal)").monospacedDigit()
            }.font(.caption).foregroundStyle(AtlasTheme.secondary)
            ProgressView(value: min(Double(store.todayNewCount) / Double(max(1, store.preferences.dailyGoal)), 1))
                .tint(AtlasTheme.green).accessibilityLabel("今日新词目标")
        }.frame(minHeight: wide ? 178 : nil, alignment: .top).atlasSurface()
    }

    private var featuredTopics: [Topic] {
        ["nature", "travel", "daily", "arts", "thinking", "technology"].compactMap { id in
            vocabulary.topics.first { $0.id == id }
        }
    }

    private func topics(width: CGFloat) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 2 : width >= 1050 ? 6 : width >= 640 ? 3 : 2
        return VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "从好奇的地方出发", subtitle: "精选主题，连接真实生活") {
                Button {
                    router.showsTopics = true
                } label: {
                    HStack(spacing: 5) {
                        Text("全部主题")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(AtlasTheme.green)
                    .accessibilityIdentifier("showAllTopics")
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14), count: columns), spacing: 16
            ) {
                ForEach(featuredTopics) { topic in
                    TopicCard(topic: topic) { router.explore(topic: topic.id) }
                }
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<18: "下午好"
        case 18..<24: "晚上好"
        default: "夜深了"
        }
    }
}
