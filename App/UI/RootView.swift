import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(VocabularyRepository.self) private var vocabulary
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        GeometryReader { geometry in
            let usesThreeColumns = geometry.size.width >= 1100 && isBrowsingWords
            navigation(width: geometry.size.width, usesThreeColumns: usesThreeColumns)
                .onChange(of: usesThreeColumns, initial: true) { _, value in router.usesInspector = value }
        }
        .tint(AtlasTheme.green)
        .background(AtlasTheme.paper)
        .sheet(item: $router.presentedWord) { word in
            NavigationStack {
                WordDetailView(word: word)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成", systemImage: "xmark") { router.presentedWord = nil }
                                .labelStyle(.iconOnly).accessibilityLabel("关闭词条")
                        }
                    }
            }
            .presentationDragIndicator(.visible)
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 680)
            #endif
        }
        .sheet(isPresented: $router.showsStudy, onDismiss: { router.releaseStudy() }) {
            StudyView()
                #if os(macOS)
            .frame(minWidth: 620, idealWidth: 780, minHeight: 700, idealHeight: 850)
                #endif
                .interactiveDismissDisabled(store.session?.pending != nil)
        }
        .sheet(isPresented: $router.showsSettings) {
            NavigationStack { SettingsView() }
                #if os(macOS)
            .frame(width: 560, height: 680)
                #endif
        }
        .sheet(isPresented: $router.showsTopics) {
            NavigationStack { TopicLibraryView() }
                .presentationDragIndicator(.visible)
                #if os(macOS)
            .frame(minWidth: 620, idealWidth: 760, minHeight: 650, idealHeight: 800)
                #endif
        }
        .sheet(isPresented: Binding(get: { needsOnboarding }, set: { _ in })) {
            OnboardingView().interactiveDismissDisabled()
                #if os(macOS)
            .frame(width: 640, height: 780)
                #endif
        }
        .alert(
            "暂时无法完成操作",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("知道了") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert("学习进行中", isPresented: Binding(get: { router.notice != nil }, set: { if !$0 { router.notice = nil } })) {
            Button("知道了") { router.notice = nil }
        } message: {
            Text(router.notice ?? "")
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
    }

    private var isBrowsingWords: Bool {
        router.destination == .atlas || router.destination == .favorites
    }

    private var needsOnboarding: Bool {
        !store.preferences.onboarded && !vocabulary.isLoading && !vocabulary.entries.isEmpty
    }

    @ViewBuilder private func navigation(width: CGFloat, usesThreeColumns: Bool) -> some View {
        if width < 700 {
            compactNavigation
        } else if usesThreeColumns {
            NavigationSplitView {
                sidebar
            } content: {
                AtlasView(favoritesOnly: router.destination == .favorites, listStyle: true)
                    .navigationSplitViewColumnWidth(min: 290, ideal: 350, max: 450)
            } detail: {
                if let id = router.selectedWordID, let word = vocabulary.word(id: id) {
                    WordDetailView(word: word)
                } else {
                    detailWelcome
                }
            }.navigationSplitViewStyle(.balanced)
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                page(router.destination)
            }.navigationSplitViewStyle(.balanced)
        }
    }

    private var sidebar: some View {
        AtlasSidebar().navigationSplitViewColumnWidth(min: 185, ideal: 210, max: 240)
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active: Task { await store.refresh() }
        case .background: AudioService.shared.stop()
        default: break
        }
    }

    private var compactNavigation: some View {
        @Bindable var router = router
        return TabView(selection: $router.destination) {
            ForEach(AppDestination.allCases) { destination in
                Tab(destination.title, systemImage: destination.symbol, value: destination) {
                    NavigationStack {
                        page(destination)
                            #if os(iOS)
                        .toolbar(.hidden, for: .navigationBar)
                            #endif
                    }
                }
            }
        }
    }

    @ViewBuilder private func page(_ destination: AppDestination) -> some View {
        if vocabulary.isLoading {
            VStack(spacing: 18) {
                AtlasMark(size: 60)
                ProgressView("正在打开你的单词图鉴…").font(.subheadline)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(AtlasTheme.paper)
        } else if let error = vocabulary.errorMessage {
            ContentUnavailableView {
                Label("图鉴暂时无法打开", systemImage: "book.closed")
            } description: {
                Text(error)
            } actions: {
                Button("重新载入") {
                    Task {
                        await vocabulary.load()
                        store.setCatalog(vocabulary.entries)
                    }
                }
            }
        } else {
            switch destination {
            case .today: TodayView()
            case .atlas: AtlasView()
            case .favorites: AtlasView(favoritesOnly: true)
            case .profile: ProfileView()
            }
        }
    }

    private var detailWelcome: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Image("brand-hero").resizable().scaledToFit()
                        .frame(maxWidth: min(280, geometry.size.height * 0.36))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    VStack(spacing: 12) {
                        Eyebrow(text: "A WORLD IN EVERY WORD")
                        Text("一词一画，\n遇见更大的世界。").font(.system(.title, design: .serif)).multilineTextAlignment(.center)
                        Text("选择一个单词，翻开它的故事。").font(.subheadline).foregroundStyle(AtlasTheme.secondary)
                    }
                }.padding(28).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(AtlasTheme.paper).foregroundStyle(AtlasTheme.ink)
    }
}
