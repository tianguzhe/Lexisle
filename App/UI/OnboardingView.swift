import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var level = "B1"
    @State private var goal = 10
    @State private var accent = Accent.uk
    @ScaledMetric(relativeTo: .title) private var titleSize = 28

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 500
            let inset: CGFloat = geometry.size.width < 400 ? 20 : 28
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 22 : 26) {
                    HStack(spacing: 10) {
                        AtlasMark(size: 34)
                        Eyebrow(text: AppBrand.welcomeWordmark)
                    }
                    GeometryReader { artwork in
                        Image("brand-hero").resizable().scaledToFill()
                            .frame(width: artwork.size.width, height: artwork.size.height).clipped()
                    }
                    .frame(height: min(compact ? 120 : 150, max(80, geometry.size.height * 0.18)))
                    .clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("一词一画，\n打开新的世界。")
                            .font(
                                .system(size: compact ? titleSize : titleSize * 1.14, weight: .medium, design: .serif)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        Text("7,298 个单词，各有画面与声音。\n选一个起点，按自己的节奏慢慢来。")
                            .font(.subheadline).foregroundStyle(AtlasTheme.secondary).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    levelSelection
                    let layout =
                        compact || dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 22))
                    layout {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("每天认识几个新词？").font(.subheadline.weight(.semibold))
                            Picker("每日新词量", selection: $goal) {
                                ForEach(LearningPreferences.dailyGoalOptions, id: \.self) { Text("\($0) 个").tag($0) }
                            }.pickerStyle(.segmented).frame(minHeight: 44)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("喜欢的声音").font(.subheadline.weight(.semibold))
                            Picker("喜欢的口音", selection: $accent) {
                                Text("英式发音").tag(Accent.uk)
                                Text("美式发音").tag(Accent.us)
                            }.pickerStyle(.segmented).frame(minHeight: 44)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, inset).padding(.top, 24).padding(.bottom, 18)
                .frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 9) {
                    Button {
                        var preferences = store.preferences
                        preferences.startLevel = level
                        preferences.dailyGoal = goal
                        preferences.accent = accent
                        preferences.onboarded = true
                        store.updatePreferences(preferences)
                    } label: {
                        HStack {
                            Text(AppBrand.onboardingAction)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.right")
                        }
                    }.buttonStyle(AtlasPrimaryButton()).accessibilityIdentifier("completeOnboarding")
                    Text("无需注册 · 文字词库离线可用 · 进度保存在本机")
                        .font(.caption2).foregroundStyle(AtlasTheme.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, inset).padding(.vertical, 12)
                .frame(maxWidth: 650).frame(maxWidth: .infinity)
                .background(AtlasTheme.paper)
                .overlay(alignment: .top) { Rectangle().fill(AtlasTheme.line).frame(height: 0.7) }
            }
        }
        .background(AtlasTheme.paper).foregroundStyle(AtlasTheme.ink).tint(AtlasTheme.green)
    }

    private var levelSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("你想从哪里开始？").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("随时可调整").font(.caption).foregroundStyle(AtlasTheme.secondary)
            }
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 0), spacing: 8),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 3), spacing: 8
            ) {
                ForEach(LearningPreferences.supportedLevels, id: \.self) { item in
                    Button {
                        level = item
                    } label: {
                        VStack(spacing: 5) {
                            Text(item).font(.system(.headline, design: .monospaced))
                            Text(
                                [
                                    "A1": "初识英语", "A2": "日常基础", "B1": "自在表达", "B2": "进阶探索",
                                    "C1": "深入理解", "C2": "精通语言",
                                ][item] ?? ""
                            )
                            .font(.caption2).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 4).padding(.vertical, 11)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(
                            level == item ? AtlasTheme.moss : AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14).stroke(
                                level == item ? AtlasTheme.green : AtlasTheme.line, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityAddTraits(level == item ? .isSelected : [])
                }
            }
        }
    }
}
