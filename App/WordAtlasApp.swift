import SwiftUI

@main
struct WordAtlasApp: App {
    @State private var bootstrap = AppBootstrap()
    @FocusedValue(\.atlasRouter) private var focusedRouter

    var body: some Scene {
        WindowGroup {
            if let store = bootstrap.store {
                AtlasWindowView().environment(store).environment(bootstrap.vocabulary)
                    .preferredColorScheme(colorScheme)
                    .task {
                        await bootstrap.prepare()
                        if store.cloudEnabled {
                            #if os(iOS)
                            UIApplication.shared.registerForRemoteNotifications()
                            #else
                            NSApplication.shared.registerForRemoteNotifications()
                            #endif
                        }
                    }
                    #if os(macOS)
                .frame(minWidth: 640, minHeight: 600)
                    #endif
            } else {
                ContentUnavailableView {
                    Label("学习记录暂时无法打开", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(bootstrap.startupError ?? "请重新打开 App。已有数据会保留。")
                } actions: {
                    Button("重试", action: bootstrap.openStore)
                }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 880)
        .commands {
            CommandGroup(after: .newItem) {
                Button("开始今日学习") {
                    if let store = bootstrap.store {
                        focusedRouter?.startLearning(store: store, entries: bootstrap.vocabulary.entries)
                    }
                }.keyboardShortcut("l", modifiers: [.command])
                Button("搜索图鉴") {
                    focusedRouter?.destination = .atlas
                    focusedRouter?.searchFocusToken += 1
                }.keyboardShortcut("f", modifiers: [.command])
            }
        }
        #endif
        #if os(macOS)
        Settings {
            if let store = bootstrap.store {
                NavigationStack { SettingsView().environment(store).environment(bootstrap.vocabulary) }
                    .frame(width: 560, height: 640)
            }
        }
        #endif
    }

    private var colorScheme: ColorScheme? {
        switch bootstrap.store?.preferences.appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}

private struct AtlasWindowView: View {
    @State private var router = AppRouter()
    var body: some View {
        RootView().environment(router).focusedSceneValue(\.atlasRouter, router)
            .onDisappear { router.releaseStudy() }
    }
}
