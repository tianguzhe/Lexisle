import SwiftUI

struct WordDetailView: View {
    let word: VocabularyEntry
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var audio = AudioService.shared

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 600
            let inset: CGFloat = geometry.size.width < 400 ? 18 : 26
            let contentWidth = min(geometry.size.width, 760) - inset * 2
            let usesSideArtwork = contentWidth >= 640 && dynamicTypeSize < .xxLarge
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 24 : 30) {
                    if usesSideArtwork {
                        HStack(alignment: .center, spacing: 24) {
                            artwork.frame(width: 190, height: 210)
                            identity.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            artwork.frame(height: min(260, max(120, contentWidth / 1.5)))
                            identity
                        }
                    }
                    meanings
                    examples
                    if !word.collocations.isEmpty { collocations }
                    if !word.family.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: "词族 · WORD FAMILY")
                            Text(word.family.joined(separator: "   ·   "))
                                .font(AtlasTypography.englishDetail).lineSpacing(5).textSelection(.enabled)
                        }
                    }
                    if !word.tip.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb").foregroundStyle(AtlasTheme.clay).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 7) {
                                Text("记忆的线索").font(.subheadline.weight(.semibold))
                                Text(word.tip).font(.subheadline).foregroundStyle(AtlasTheme.secondary)
                                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(AtlasTheme.moss.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                    }
                    if let note = word.note, !note.isEmpty {
                        Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(AtlasTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, inset).padding(.top, 18).padding(.bottom, 30)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
        .background(AtlasTheme.paper).foregroundStyle(AtlasTheme.ink)
        .navigationTitle("")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
    }

    private var artwork: some View {
        WordArtwork(wordID: word.id, topic: word.topic, full: true)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(alignment: .bottomLeading) {
                Label(word.topicName, systemImage: word.topic.topicSymbol)
                    .font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule()).padding(12)
            }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                LevelBadge(level: word.cefr)
                Text(store.cards[word.id]?.isMastered == true ? "已掌握" : store.cards[word.id] == nil ? "等待初见" : "正在生长")
                    .font(.caption).foregroundStyle(AtlasTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    store.toggleFavorite(word.id)
                } label: {
                    Image(systemName: store.favorites.contains(word.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
                        .background(AtlasTheme.moss, in: Circle())
                }.buttonStyle(.plain).foregroundStyle(AtlasTheme.green)
                    .accessibilityLabel(store.favorites.contains(word.id) ? "取消收藏" : "收藏单词")
                    .accessibilityIdentifier("favoriteWord")
            }
            Text(word.word).font(AtlasTypography.wordTitle(size: 34))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    pronunciation(.uk)
                    pronunciation(.us)
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) {
                    pronunciation(.uk, expanded: true)
                    pronunciation(.us, expanded: true)
                }
            }
            if audio.isPlaying || audio.isLoading {
                Text(audio.sourceLabel).font(.caption2).foregroundStyle(AtlasTheme.secondary)
            }
            if let error = audio.errorMessage {
                Text(error).font(.caption).foregroundStyle(AtlasTheme.clay)
            }
        }
    }

    private var meanings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "词义 · MEANING")
            ForEach(Array(word.senses.enumerated()), id: \.offset) { index, sense in
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%02d", index + 1)).font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(AtlasTheme.secondary).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(sense.pos)  \(sense.zh)").font(.body.weight(.medium))
                        Text(sense.en).font(AtlasTypography.englishDetail)
                            .foregroundStyle(AtlasTheme.secondary).lineSpacing(4)
                    }.fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "放进语境 · IN CONTEXT")
            ForEach(Array(word.examples.enumerated()), id: \.offset) { index, example in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(index == 0 ? "日常表达" : "进阶表达")
                            .font(.caption.weight(.medium)).foregroundStyle(AtlasTheme.secondary)
                        Spacer()
                        Button {
                            Task {
                                _ = await audio.play(
                                    word: word, kind: index == 0 ? .example : .example2,
                                    accent: store.preferences.accent)
                            }
                        } label: {
                            Image(systemName: "speaker.wave.2").font(.subheadline)
                                .frame(width: 44, height: 44).background(AtlasTheme.paper, in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel("朗读第 \(index + 1) 条例句")
                    }
                    Text(example.en).font(AtlasTypography.englishBody).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text(example.zh).font(.subheadline).foregroundStyle(AtlasTheme.secondary).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }.atlasSurface(padding: 18)
            }
        }
    }

    private var collocations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "常见搭配 · TOGETHER")
            ForEach(word.collocations, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Circle().fill(AtlasTheme.green.opacity(0.4)).frame(width: 4, height: 4)
                    collocationLabel(item)
                        .font(.subheadline).lineSpacing(4).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 3)
            }
        }
    }

    private func collocationLabel(_ item: String) -> Text {
        guard let separator = item.range(of: "｜") else { return Text(item) }
        let english = Text(String(item[..<separator.lowerBound])).font(AtlasTypography.englishDetail)
        return Text("\(english)  ·  \(String(item[separator.upperBound...]))")
    }

    private func pronunciation(_ accent: Accent, expanded: Bool = false) -> some View {
        Button {
            Task { _ = await audio.play(word: word, kind: accent == .uk ? .uk : .us, accent: accent) }
        } label: {
            HStack(spacing: 7) {
                Text(accent == .uk ? "UK" : "US").font(.system(.caption2, design: .monospaced, weight: .semibold))
                Text(accent == .uk ? word.uk : word.us).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                if expanded { Spacer(minLength: 4) }
                Image(systemName: "speaker.wave.2").font(.caption).fixedSize()
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: expanded ? .infinity : nil, minHeight: 46, alignment: .leading)
                .background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(AtlasTheme.line, lineWidth: 0.8))
        }.buttonStyle(.plain).foregroundStyle(AtlasTheme.green).accessibilityLabel("\(accent.title)发音，\(word.word)")
    }
}
