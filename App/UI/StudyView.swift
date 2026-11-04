import SwiftUI

struct StudyView: View {
    @Environment(AppStore.self) private var store
    @Environment(VocabularyRepository.self) private var vocabulary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var audio = AudioService.shared
    @State private var started = Date()
    @State private var hinted = false
    @State private var audioUnavailable = false
    @FocusState private var spellingFocused: Bool
    @AccessibilityFocusState private var feedbackFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            sessionLayout(size: geometry.size)
        }
        .background(AtlasTheme.paper)
        .foregroundStyle(AtlasTheme.ink)
        .onDisappear {
            audio.stop()
            store.saveSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                store.saveSession()
                audio.stop()
            }
            if phase == .active { started = Date() }
        }
    }

    private func sessionLayout(size: CGSize) -> some View {
        let compact = size.width < 600
        let inset: CGFloat = size.width < 400 ? 18 : 24
        return VStack(spacing: 0) {
            progressHeader(inset: inset)
            if let session = store.session, session.finished {
                completion(session, compact: compact)
            } else if let step = store.session?.current, let word = vocabulary.word(id: step.wordID) {
                activeStep(step, word: word, size: size, compact: compact, inset: inset)
            } else {
                EmptyAtlasView(symbol: "checkmark.seal", title: "今天的计划已经完成", message: "记忆也需要留白。明天，我们再见。")
                Button("返回今日") { dismiss() }.buttonStyle(AtlasPrimaryButton())
                Spacer()
            }
        }
    }

    private func progressHeader(inset: CGFloat) -> some View {
        HStack(spacing: 14) {
            Button {
                store.saveSession()
                audio.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.subheadline.weight(.medium))
                    .frame(width: 44, height: 44).background(AtlasTheme.surface, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("保存进度并退出学习")
            VStack(alignment: .leading, spacing: 8) {
                Text("今日学习").font(.caption.weight(.medium)).foregroundStyle(AtlasTheme.secondary)
                ProgressView(value: store.session?.progress ?? 0).tint(AtlasTheme.green)
                    .accessibilityLabel("本次学习进度")
            }
            Text(stepCountLabel)
                .font(.caption.monospacedDigit()).foregroundStyle(AtlasTheme.secondary).fixedSize()
        }.padding(.horizontal, inset).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
    }

    private var stepCountLabel: String {
        let total = store.session?.steps.count ?? 0
        let current = min((store.session?.index ?? 0) + 1, total)
        return "\(current) / \(total)"
    }

    private func activeStep(
        _ step: StudyStep, word: VocabularyEntry, size: CGSize,
        compact: Bool, inset: CGFloat
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: compact ? 18 : 24) {
                    HStack(alignment: .top, spacing: 12) {
                        Eyebrow(text: step.retry ? "再遇见一次 · 巩固练习" : step.kind.title)
                        Spacer(minLength: 0)
                        LevelBadge(level: word.cefr)
                    }.id("studyQuestion")
                    question(step, word: word, compact: compact, width: size.width, height: size.height)
                    if step.kind != .intro {
                        if step.kind == .spell { spellingInput(word) } else { options(step, word: word) }
                    }
                    if let feedback = store.session?.pending {
                        answerFeedback(feedback, word: word, retry: step.retry)
                            .id("studyFeedback")
                            .accessibilityFocused($feedbackFocused)
                    }
                }.padding(.horizontal, inset).padding(.top, 12).padding(.bottom, 20)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if step.kind == .intro || store.session?.pending != nil {
                    advanceButton(isIntroduction: step.kind == .intro, inset: inset)
                }
            }
            .onChange(of: step.id) { _, _ in
                proxy.scrollTo("studyQuestion", anchor: .top)
            }
            .onChange(of: store.session?.pending, initial: true) { _, feedback in
                guard feedback != nil else {
                    feedbackFocused = false
                    return
                }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo("studyFeedback", anchor: dynamicTypeSize.isAccessibilitySize ? .top : .bottom)
                }
                feedbackFocused = true
            }
        }
        .task(id: step.id) { await prepareStep(step, word: word) }
    }

    private func answerFeedback(_ feedback: AnswerFeedback, word: VocabularyEntry, retry: Bool) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: feedback.correct ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                .font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text(feedback.correct ? "记住了，又向前一步。" : "没关系，再认识它一次。")
                    .font(.subheadline.weight(.semibold))
                Text("\(Text(word.word).font(AtlasTypography.wordCard))  ·  \(word.meaning)")
                    .font(.subheadline).lineSpacing(3)
                if retry { Text("巩固练习不重复计分").font(.caption) }
            }.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(feedback.correct ? AtlasTheme.green : AtlasTheme.clay)
            .padding(18).background(AtlasTheme.moss.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
    }

    private func advanceButton(isIntroduction: Bool, inset: CGFloat) -> some View {
        Button {
            audio.stop()
            store.advance()
        } label: {
            HStack {
                Text(isIntroduction ? "认识了，继续" : "继续")
                Spacer()
                Image(systemName: "arrow.right")
            }.frame(maxWidth: .infinity)
        }.buttonStyle(AtlasPrimaryButton()).keyboardShortcut(.return, modifiers: [])
            .padding(.horizontal, inset).padding(.vertical, 12)
            .frame(maxWidth: 620).frame(maxWidth: .infinity).background(AtlasTheme.paper)
            .overlay(alignment: .top) { Rectangle().fill(AtlasTheme.line).frame(height: 0.7) }
    }

    private func prepareStep(_ step: StudyStep, word: VocabularyEntry) async {
        started = Date()
        hinted = store.session?.hintUsed ?? false
        audioUnavailable = false
        spellingFocused = step.kind == .spell
        let ids = Array((store.session?.steps.dropFirst(store.session?.index ?? 0).map(\.wordID) ?? []).prefix(5))
        Task { await MediaRepository.shared.prefetch(wordIDs: ids) }
        if step.kind == .listen && store.session?.pending == nil {
            await playListeningWord(word, stepID: step.id)
        }
    }

    private var pronunciationKind: MediaKind {
        store.preferences.accent == .uk ? .uk : .us
    }

    private func playListeningWord(_ word: VocabularyEntry, stepID: String) async {
        let played = await audio.play(word: word, kind: pronunciationKind, accent: store.preferences.accent)
        guard !Task.isCancelled, store.session?.current?.id == stepID, scenePhase == .active else { return }
        started = Date()
        if !played && audio.errorMessage != nil {
            audioUnavailable = true
            store.useTextFallbackForCurrentQuestion()
        }
    }

    @ViewBuilder private func question(
        _ step: StudyStep, word: VocabularyEntry, compact: Bool, width: CGFloat, height: CGFloat
    ) -> some View {
        if step.kind == .listen {
            VStack(spacing: 12) {
                Button {
                    Task { await playListeningWord(word, stepID: step.id) }
                } label: {
                    Image(systemName: audio.isPlaying ? "waveform" : "speaker.wave.2")
                        .font(.system(size: compact ? 34 : 42, weight: .light))
                        .frame(width: compact ? 96 : 120, height: compact ? 96 : 120)
                        .background(AtlasTheme.moss, in: Circle())
                }.buttonStyle(.plain).disabled(audio.isLoading).accessibilityLabel("播放单词发音")
                Text("听见的是哪一个词？").font(.system(.title3, design: .serif)).multilineTextAlignment(.center)
                Text(audio.isLoading ? "正在准备发音…" : audio.sourceLabel.isEmpty ? "轻点再听一次" : audio.sourceLabel)
                    .font(.caption).foregroundStyle(AtlasTheme.secondary)
            }.padding(.vertical, compact ? 8 : 16)
        } else {
            if step.kind != .meaning {
                WordArtwork(wordID: word.id, topic: word.topic, full: true)
                    .frame(
                        width: compact ? min(min(264, max(160, height * 0.37)), max(0, width - 36)) : 320,
                        height: dynamicTypeSize.isAccessibilitySize
                            ? 120 : compact ? min(180, max(120, height * 0.25)) : 215
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            VStack(spacing: 8) {
                if step.kind == .spell {
                    Text(word.meaning).font(.title2.weight(.medium)).multilineTextAlignment(.center)
                    Text("用英文写下这个单词").font(.subheadline).foregroundStyle(AtlasTheme.secondary)
                } else {
                    Text(word.word).font(
                        AtlasTypography.wordTitle(size: compact ? 36 : 42)
                    )
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task {
                            _ = await audio.play(word: word, kind: pronunciationKind, accent: store.preferences.accent)
                        }
                    } label: {
                        Label(store.preferences.accent == .uk ? word.uk : word.us, systemImage: "speaker.wave.2")
                            .font(.subheadline).padding(.horizontal, 13).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(AtlasTheme.secondary)
                    if step.kind == .intro {
                        Text("\(word.pos)  \(word.meaning)").font(.body.weight(.medium)).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if let example = word.examples.first {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(example.en).font(AtlasTypography.englishBody).lineSpacing(3)
                                Text(example.zh).font(.subheadline).foregroundStyle(AtlasTheme.secondary).lineSpacing(3)
                            }.fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(compact ? 16 : 20)
                                .background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 18)).padding(.top, 8)
                        }
                    }
                }
                if audioUnavailable { Text("发音暂不可用，已切换为文字练习").font(.caption).foregroundStyle(AtlasTheme.clay) }
            }.padding(.vertical, 2)
        }
    }

    private func options(_ step: StudyStep, word: VocabularyEntry) -> some View {
        VStack(spacing: 11) {
            ForEach(Array(step.options.enumerated()), id: \.element) { index, id in
                if let option = vocabulary.word(id: id) {
                    let feedback = store.session?.pending
                    let correct = feedback != nil && id == word.id
                    let wrong = feedback?.answer == id && feedback?.correct == false
                    Button {
                        submit(id)
                    } label: {
                        HStack(spacing: 15) {
                            Text("\(index + 1)").font(.system(.caption, design: .monospaced))
                                .frame(width: 28, height: 28).background(
                                    AtlasTheme.paper, in: RoundedRectangle(cornerRadius: 8))
                            Text(step.kind == .meaning ? option.meaning : option.word)
                                .font(step.kind == .meaning ? .body : AtlasTypography.wordOption)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if correct { Image(systemName: "checkmark.circle.fill") }
                            if wrong { Image(systemName: "xmark.circle") }
                        }.padding(14).frame(minHeight: 56)
                            .foregroundStyle(wrong ? AtlasTheme.clay : AtlasTheme.ink)
                            .background(
                                correct ? AtlasTheme.moss : AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 17)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 17).stroke(
                                    correct ? AtlasTheme.green : wrong ? AtlasTheme.clay : AtlasTheme.line, lineWidth: 1
                                ))
                    }.buttonStyle(StudyAnswerButtonStyle()).disabled(feedback != nil)
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
                        .accessibilityIdentifier("answerOption\(index)")
                }
            }
        }
    }

    private func spellingInput(_ word: VocabularyEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("输入英文单词", text: Binding(get: { store.draftAnswer }, set: { store.updateDraft($0) }))
                .textFieldStyle(.plain).font(AtlasTypography.spelling).padding(20)
                .background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AtlasTheme.line, lineWidth: 1))
                .focused($spellingFocused).disabled(store.session?.pending != nil)
                #if os(iOS)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                #endif
                .onSubmit { if !store.draftAnswer.isEmpty { submit(store.draftAnswer) } }
            if store.session?.pending == nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        spellingHint(word).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        spellingConfirm.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        spellingHint(word)
                        spellingConfirm
                    }
                }
            }
        }
    }

    private func spellingHint(_ word: VocabularyEntry) -> some View {
        Button(hinted ? "以 \(word.word.prefix(1)) 开头，共 \(word.word.count) 个字符" : "给我一点提示") {
            hinted = true
            store.markHintUsed()
        }.buttonStyle(.plain).font(.caption).foregroundStyle(AtlasTheme.secondary).frame(minHeight: 44)
    }

    private var spellingConfirm: some View {
        Button("确认") { submit(store.draftAnswer) }.buttonStyle(AtlasPrimaryButton())
            .disabled(store.draftAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func submit(_ answer: String) {
        store.submitAnswer(answer, elapsed: Date().timeIntervalSince(started), hinted: hinted)
        spellingFocused = false
    }

    private func completionMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(value).font(.largeTitle.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(AtlasTheme.secondary)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }

    private func completion(_ session: LearningSession, compact: Bool) -> some View {
        ScrollView {
            VStack(spacing: compact ? 20 : 26) {
                Image("brand-done").resizable().scaledToFit().frame(
                    maxWidth: compact ? 210 : 280, maxHeight: compact ? 165 : 220
                )
                .clipShape(RoundedRectangle(cornerRadius: 25)).accessibilityHidden(true)
                Eyebrow(text: "ONE CHAPTER CLOSER")
                Text("今天的你，\n又多了一点光。").font(.system(compact ? .title : .largeTitle, design: .serif))
                    .multilineTextAlignment(.center)
                let metricLayout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 24)) : AnyLayout(HStackLayout(spacing: 20))
                metricLayout {
                    completionMetric("本次学习", value: "\(session.graded.count)")
                    completionMetric("首次正确率", value: "\(session.accuracy)%")
                }.padding(20).background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                Text("进度已保存。让新认识的单词，在记忆里慢慢扎根。").font(.subheadline)
                    .foregroundStyle(AtlasTheme.secondary).multilineTextAlignment(.center)
                Button("收好今天的进步") { dismiss() }.buttonStyle(AtlasPrimaryButton())
            }.padding(compact ? 24 : 32).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
    }
}

/// Answered choices remain legible while disabled, so the result can still be compared.
private struct StudyAnswerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}
