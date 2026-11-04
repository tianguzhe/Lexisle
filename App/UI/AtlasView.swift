import SwiftUI

struct AtlasView: View {
    var favoritesOnly = false
    var listStyle = false
    @Environment(AppStore.self) private var store
    @Environment(VocabularyRepository.self) private var vocabulary
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var searchFocused: Bool

    private var filteredWords: [VocabularyEntry] {
        let query = router.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return vocabulary.entries.filter { word in
            (!favoritesOnly || store.favorites.contains(word.id))
                && (router.topicFilter == "all" || word.topic == router.topicFilter)
                && (router.levelFilter == "all" || word.cefr == router.levelFilter) && matchesLearningStatus(word)
                && (query.isEmpty || word.word.localizedStandardContains(query)
                    || word.senses.contains { $0.zh.localizedStandardContains(query) })
        }
    }

    private func matchesLearningStatus(_ word: VocabularyEntry) -> Bool {
        let card = store.cards[word.id]
        switch router.statusFilter {
        case "all": return true
        case "new": return card == nil
        case "learning": return card != nil && card?.isMastered == false
        case "mastered": return card?.isMastered == true
        default: return false
        }
    }

    var body: some View {
        let words = filteredWords
        GeometryReader { geometry in
            let metrics = AtlasLayoutMetrics(width: geometry.size.width)
            let horizontalPadding = listStyle ? 18 : metrics.horizontalPadding
            let contentWidth = min(geometry.size.width, metrics.contentWidth) - horizontalPadding * 2
            ScrollView {
                VStack(alignment: .leading, spacing: listStyle ? 20 : metrics.sectionSpacing) {
                    header(compact: metrics.isCompact)
                    VStack(alignment: .leading, spacing: 12) {
                        searchField
                        filters
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        resultsHeading(count: words.count)
                        if words.isEmpty {
                            EmptyAtlasView(
                                symbol: favoritesOnly ? "bookmark" : "magnifyingglass",
                                title: favoritesOnly && store.favorites.isEmpty ? "给喜欢的词留个位置" : "还没有找到这个词",
                                message: favoritesOnly && store.favorites.isEmpty
                                    ? "在词卡上轻点书签，把想再见的单词收进这里。" : "试试其他关键词，或放宽筛选条件。")
                        } else if listStyle {
                            LazyVStack(spacing: 9) {
                                ForEach(words) { word in
                                    Button {
                                        openWord(word)
                                    } label: {
                                        wordRow(word)
                                    }.buttonStyle(.plain)
                                        .accessibilityLabel("\(word.word)，\(word.meaning)，\(word.cefr)")
                                        .accessibilityAddTraits(router.selectedWordID == word.id ? .isSelected : [])
                                }
                            }
                        } else {
                            LazyVGrid(columns: gridColumns(contentWidth: contentWidth), spacing: 16) {
                                ForEach(words) { word in
                                    Button {
                                        openWord(word)
                                    } label: {
                                        WordGridCard(word: word)
                                    }
                                    .buttonStyle(.plain).accessibilityLabel("\(word.word)，\(word.meaning)，\(word.cefr)")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, metrics.isCompact ? 16 : 24).padding(.bottom, 30)
                .frame(maxWidth: 1120).frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        }
        .background(AtlasTheme.paper)
        .navigationTitle("")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .onChange(of: router.searchFocusToken) { _, _ in searchFocused = true }
    }

    @ViewBuilder private func header(compact: Bool) -> some View {
        if listStyle {
            VStack(alignment: .leading, spacing: 7) {
                Text(favoritesOnly ? "我的收藏" : "单词图鉴")
                    .font(.system(.title2, design: .serif, weight: .medium)).foregroundStyle(AtlasTheme.ink)
                Text(favoritesOnly ? "把想再见的词，收进这里。" : "循着好奇，翻开一个词。")
                    .font(.caption).foregroundStyle(AtlasTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            AtlasPageTitle(
                title: favoritesOnly ? "把喜欢的词，留下。" : "把世界，读成单词。",
                subtitle: favoritesOnly ? "每一次收藏，都是好奇心的回声。" : "7,298 个单词，19 个生活主题",
                eyebrow: favoritesOnly ? "MY COLLECTION" : AppBrand.wordmark,
                compact: compact
            )
        }
    }

    private var searchField: some View {
        @Bindable var router = router
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.subheadline).foregroundStyle(AtlasTheme.secondary)
            TextField("搜索单词或中文释义", text: $router.searchText)
                .textFieldStyle(.plain).font(.subheadline).focused($searchFocused)
                .accessibilityIdentifier("atlasSearch")
                .onSubmit { searchFocused = false }
                #if os(iOS)
            .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                #endif
            if !router.searchText.isEmpty {
                Button {
                    router.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(AtlasTheme.secondary).frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("清除搜索")
            }
        }.padding(.leading, 15).padding(.trailing, router.searchText.isEmpty ? 15 : 3)
            .frame(minHeight: 50)
            .background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(AtlasTheme.line, lineWidth: 1))
    }

    private func resultsHeading(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(count.formatted()) 个词条").font(.caption).foregroundStyle(AtlasTheme.secondary)
            Spacer(minLength: 8)
            if router.hasActiveFilters {
                Button("重置筛选", action: router.resetFilters)
                    .buttonStyle(.plain).font(.caption).foregroundStyle(AtlasTheme.green).frame(minHeight: 44)
            }
        }
    }

    private func openWord(_ word: VocabularyEntry) {
        searchFocused = false
        router.show(word)
    }

    private func gridColumns(contentWidth: CGFloat) -> [GridItem] {
        if dynamicTypeSize.isAccessibilitySize { return [GridItem(.flexible(minimum: 0))] }
        let largerText = dynamicTypeSize >= .xxLarge
        let spacing: CGFloat = contentWidth < 560 ? 14 : 18
        let minimumWidth: CGFloat = largerText ? 220 : 180
        let count = max(largerText ? 1 : 2, Int((max(0, contentWidth) + spacing) / (minimumWidth + spacing)))
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: count)
    }

    private var filters: some View {
        @Bindable var router = router
        return AtlasFilterFlow(spacing: 8) {
            Menu {
                Picker("主题", selection: $router.topicFilter) {
                    Text("全部主题").tag("all")
                    ForEach(vocabulary.topics) { Text($0.name).tag($0.id) }
                }
            } label: {
                menuLabel(
                    vocabulary.topics.first(where: { $0.id == router.topicFilter })?.name ?? "主题",
                    selected: router.topicFilter != "all")
            }
            Menu {
                Picker("等级", selection: $router.levelFilter) {
                    Text("全部等级").tag("all")
                    ForEach(LearningPreferences.supportedLevels, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                menuLabel(
                    router.levelFilter == "all" ? "等级" : router.levelFilter, selected: router.levelFilter != "all")
            }
            Menu {
                Picker("学习状态", selection: $router.statusFilter) {
                    Text("全部状态").tag("all")
                    Text("未学习").tag("new")
                    Text("学习中").tag("learning")
                    Text("已掌握").tag("mastered")
                }
            } label: {
                menuLabel(
                    ["new": "未学习", "learning": "学习中", "mastered": "已掌握"][router.statusFilter] ?? "学习状态",
                    selected: router.statusFilter != "all")
            }
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
    }

    private func menuLabel(_ title: String, selected: Bool) -> some View {
        HStack(spacing: 7) {
            Text(title)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
        }.font(.caption.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? AtlasTheme.green : AtlasTheme.secondary)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(selected ? AtlasTheme.moss : AtlasTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? .clear : AtlasTheme.line, lineWidth: 0.8))
    }

    private func wordRow(_ word: VocabularyEntry) -> some View {
        HStack(spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                WordArtwork(wordID: word.id, topic: word.topic).frame(width: 60, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(word.word).font(AtlasTypography.wordCard).foregroundStyle(AtlasTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(word.meaning).font(.caption).foregroundStyle(AtlasTheme.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if store.favorites.contains(word.id) {
                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(AtlasTheme.clay)
            }
        }.padding(10).background(
            router.selectedWordID == word.id ? AtlasTheme.moss : AtlasTheme.surface,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .contentShape(Rectangle())
    }
}

struct WordGridCard: View {
    let word: VocabularyEntry
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
                .overlay(alignment: .topLeading) { LevelBadge(level: word.cefr).padding(9) }
                .overlay(alignment: .topTrailing) {
                    if store.favorites.contains(word.id) {
                        Image(systemName: "bookmark.fill").font(.caption)
                            .foregroundStyle(AtlasTheme.clay).padding(8).background(.regularMaterial, in: Circle())
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 7) {
                Text(word.word).font(AtlasTypography.wordCard)
                    .foregroundStyle(AtlasTheme.ink)
                    .modifier(WordCardLineLimit(expanded: dynamicTypeSize.isAccessibilitySize))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(word.meaning).font(.caption).foregroundStyle(AtlasTheme.secondary)
                    .modifier(WordCardLineLimit(expanded: dynamicTypeSize.isAccessibilitySize))
                HStack {
                    Text(word.topicName).font(.caption2).foregroundStyle(AtlasTheme.secondary)
                    Spacer()
                    if store.cards[word.id]?.isMastered == true {
                        Image(systemName: "checkmark.seal").font(.caption).foregroundStyle(AtlasTheme.green)
                    } else {
                        Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(
                            AtlasTheme.secondary)
                    }
                }
            }.padding(13)
        }.background(AtlasTheme.surface).clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(AtlasTheme.line.opacity(0.7), lineWidth: 0.7))
    }

    @ViewBuilder private var artwork: some View {
        let image = WordArtwork(wordID: word.id, topic: word.topic)
        if dynamicTypeSize.isAccessibilitySize {
            image.frame(height: 180)
        } else {
            image.aspectRatio(1.2, contentMode: .fit)
        }
    }
}

private struct WordCardLineLimit: ViewModifier {
    let expanded: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if expanded {
            content.fixedSize(horizontal: false, vertical: true)
        } else {
            content.lineLimit(2, reservesSpace: true)
        }
    }
}

/// Filter controls wrap as a group instead of requiring a second scrolling direction.
private struct AtlasFilterFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = positions(subviews: subviews, width: width)
        return CGSize(width: proposal.width ?? result.width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = positions(subviews: subviews, width: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            let point = frame.origin
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func positions(subviews: Subviews, width: CGFloat) -> (frames: [CGRect], width: CGFloat, height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, usedWidth, y + rowHeight)
    }
}
