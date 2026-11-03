import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var cacheBytes: Int64 = 0
    @State private var cacheError: String?
    @State private var clearing = false
    @State private var showsCacheConfirmation = false

    var body: some View {
        Form {
            Section("你的学习节奏") {
                Picker("每日新词", selection: preference(\.dailyGoal)) {
                    ForEach(LearningPreferences.dailyGoalOptions, id: \.self) { Text("\($0) 个").tag($0) }
                }
                Picker("起点等级", selection: preference(\.startLevel)) {
                    ForEach(LearningPreferences.supportedLevels, id: \.self) { Text($0).tag($0) }
                }
                Picker("发音偏好", selection: preference(\.accent)) {
                    Text("英式发音").tag(Accent.uk)
                    Text("美式发音").tag(Accent.us)
                }
                Picker("外观", selection: preference(\.appearance)) {
                    Text("跟随系统").tag("system")
                    Text("浅色图鉴").tag("light")
                    Text("深色图鉴").tag("dark")
                }
            }
            Section {
                Label(store.syncStatus, systemImage: "icloud")
                if let date = store.lastSyncedAt {
                    LabeledContent("最近成功同步", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                Button("检查同步状态") { Task { await store.refresh() } }
            } header: {
                Text("iCloud 与学习记录")
            } footer: {
                Text("使用同一 Apple ID 同步学习成果、收藏和设置。未完成的题目保留在当前设备；插画和录音缓存不占用 iCloud 空间。")
            }
            Section {
                LabeledContent("媒体缓存", value: ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))
                LabeledContent("缓存上限", value: "512 MB")
                Button(clearing ? "正在清理…" : "清理图片与录音缓存", role: .destructive) { showsCacheConfirmation = true }
                    .disabled(clearing)
                if let cacheError { Text(cacheError).font(.caption).foregroundStyle(AtlasTheme.clay) }
            } header: {
                Text("离线与存储")
            } footer: {
                Text("词库始终离线可用。浏览过的图片与录音会自动缓存，清理缓存会保留你的学习进度。")
            }
            Section(AppBrand.aboutTitle) {
                HStack(spacing: 14) {
                    AtlasMark(size: 45)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppBrand.displayName).font(.headline)
                        Text("\(AppBrand.tagline)  \(AppBrand.version)").font(.caption).foregroundStyle(
                            AtlasTheme.secondary)
                    }
                }.padding(.vertical, 9)
                Link("原项目与开放词库", destination: URL(string: "https://github.com/designfuchen/word-atlas")!)
                Link(
                    "Word Atlas contributors — CC BY 4.0",
                    destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                NavigationLink("内容说明与开源许可") { AttributionView() }
                Text("原生 SwiftUI 界面、学习数据存储与同步为本版本改编；词库文本、插画和录音保留原项目内容。")
                    .font(.caption).foregroundStyle(AtlasTheme.secondary)
            }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden).background(AtlasTheme.paper)
        .tint(AtlasTheme.green).navigationTitle("学习设置")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .task { cacheBytes = await MediaRepository.shared.cacheSize() }
        .confirmationDialog("清理已缓存的图片与录音？", isPresented: $showsCacheConfirmation, titleVisibility: .visible) {
            Button("清理缓存", role: .destructive) {
                Task { await clearMediaCache() }
            }
        } message: {
            Text("学习记录和收藏会保留。下次浏览时将重新下载媒体。")
        }
    }

    private func preference<Value>(_ key: WritableKeyPath<LearningPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: key] },
            set: { value in
                var preferences = store.preferences
                preferences[keyPath: key] = value
                store.updatePreferences(preferences)
            }
        )
    }

    private func clearMediaCache() async {
        clearing = true
        cacheError = nil
        defer { clearing = false }

        do {
            try await MediaRepository.shared.clearCache()
        } catch {
            cacheError = error.localizedDescription
        }
        cacheBytes = await MediaRepository.shared.cacheSize()
    }
}
