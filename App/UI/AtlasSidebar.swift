import SwiftUI

struct AtlasSidebar: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    brand
                    navigationLinks
                    Spacer(minLength: 24)
                    if !dynamicTypeSize.isAccessibilitySize { closingNote }
                    settingsButton
                }.frame(minHeight: geometry.size.height, alignment: .top)
            }.scrollIndicators(.hidden)
        }
        .background(AtlasTheme.paper)
        .foregroundStyle(AtlasTheme.ink)
        .toolbar(.hidden)
    }

    private var brand: some View {
        HStack(spacing: 12) {
            AtlasMark()
            VStack(alignment: .leading, spacing: 3) {
                Text(AppBrand.name).font(.title3.weight(.semibold)).tracking(3)
                Text(AppBrand.wordmark).font(.system(size: 9, design: .monospaced)).tracking(2)
                    .foregroundStyle(AtlasTheme.secondary)
            }
        }.padding(.top, 28).padding(.horizontal, 20)
    }

    private var navigationLinks: some View {
        VStack(spacing: 8) {
            ForEach(AppDestination.allCases) { destination in
                let selected = router.destination == destination
                Button {
                    router.destination = destination
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: destination.symbol).font(.system(size: 18)).frame(width: 24)
                        Text(destination.title).font(.system(.subheadline, weight: .medium))
                        Spacer()
                        if destination == .favorites && !store.favorites.isEmpty {
                            Text("\(store.favorites.count)").font(.caption.monospacedDigit())
                        }
                    }.padding(.horizontal, 16).frame(minHeight: 48)
                        .background(selected ? AtlasTheme.moss : .clear, in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain)
                    .foregroundStyle(selected ? AtlasTheme.green : AtlasTheme.secondary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(.horizontal, 12)
    }

    private var closingNote: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "leaf").font(.title2.weight(.ultraLight))
            Text("Little by little,\na little becomes a lot.")
                .font(.system(.subheadline, design: .serif)).italic().lineSpacing(4)
            Text("每天一点，慢慢看见改变。").font(.caption2).foregroundStyle(AtlasTheme.secondary)
        }.foregroundStyle(AtlasTheme.green).padding(20)
    }

    private var settingsButton: some View {
        Button {
            router.showsSettings = true
        } label: {
            HStack {
                Image(systemName: "slider.horizontal.3")
                Text("学习设置")
                Spacer()
            }.font(.subheadline).frame(minHeight: 44)
        }.buttonStyle(.plain)
            .foregroundStyle(AtlasTheme.secondary)
            .padding(.horizontal, 24).padding(.bottom, 18)
    }
}
