import Charts
import SwiftUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var period = 7
    @ScaledMetric(relativeTo: .title) private var metricSize: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            let metrics = AtlasLayoutMetrics(width: geometry.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    HStack(alignment: .top, spacing: 16) {
                        AtlasPageTitle(
                            title: "我的学习", subtitle: "每一步，都有回响。", eyebrow: "YOUR JOURNEY", compact: metrics.isCompact
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            router.showsSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3").font(.body)
                                .frame(width: 44, height: 44).background(AtlasTheme.surface, in: Circle())
                                .overlay(Circle().stroke(AtlasTheme.line, lineWidth: 0.8))
                        }.buttonStyle(.plain).accessibilityLabel("学习设置")
                    }
                    LazyVGrid(columns: metricColumns(width: geometry.size.width), spacing: 12) {
                        metric("已认识", value: "\(store.learnedCount)", unit: "个词", symbol: "book.pages")
                        metric("已掌握", value: "\(store.masteredCount)", unit: "个词", symbol: "leaf")
                        metric("连续学习", value: "\(store.streak)", unit: "天", symbol: "flame")
                        metric(
                            "学习足迹",
                            value: "\(Set(store.reviewEvents.map { Calendar.current.startOfDay(for: $0.date) }).count)",
                            unit: "天", symbol: "calendar")
                    }
                    activityChart(compact: metrics.isCompact || dynamicTypeSize.isAccessibilitySize)
                    let lowerLayout =
                        geometry.size.width >= 850 && !dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                        : AnyLayout(VStackLayout(spacing: 18))
                    lowerLayout {
                        todaySummary.frame(maxWidth: .infinity, alignment: .leading)
                        syncSummary.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.isCompact ? 16 : 24).padding(.bottom, 30)
                .frame(maxWidth: 1040).frame(maxWidth: .infinity)
            }
        }.background(AtlasTheme.paper).foregroundStyle(AtlasTheme.ink).navigationTitle("")
            #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
            #endif
    }

    private func metricColumns(width: CGFloat) -> [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : width < 760 ? 2 : 4
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: count)
    }

    private func activityChart(compact: Bool) -> some View {
        let activity = store.activity(days: period)
        return VStack(alignment: .leading, spacing: 22) {
            let layout =
                compact
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
            layout {
                VStack(alignment: .leading, spacing: 5) {
                    Text("成长的节奏").font(.headline)
                    Text("每一格，都是认真学习过的时刻").font(.caption).foregroundStyle(AtlasTheme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Picker("统计周期", selection: $period) {
                    Text("近 7 天").tag(7)
                    Text("近 30 天").tag(30)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: compact ? 260 : 180, minHeight: 44)
            }
            Chart(activity) { day in
                BarMark(x: .value("日期", day.date, unit: .day), y: .value("学习词数", day.reviewed))
                    .foregroundStyle(AtlasTheme.green.gradient).cornerRadius(4)
                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(day.reviewed) 个词")
            }
            .chartYScale(domain: 0...max(10, activity.map(\.reviewed).max() ?? 0))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == 7 ? 1 : 7)) { _ in
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(AtlasTheme.line)
                    AxisValueLabel()
                }
            }
            .frame(height: compact ? 175 : 220)
            if activity.allSatisfy({ $0.reviewed == 0 }) {
                Label(
                    store.reviewEvents.isEmpty ? "完成第一次学习，留下你的第一段足迹。" : "这段时间还没有学习记录，从今天继续。",
                    systemImage: "sparkle"
                )
                .font(.caption).foregroundStyle(AtlasTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.atlasSurface(padding: compact ? 18 : 24)
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("今天的小收获").font(.headline)
                Spacer()
                Image(systemName: "sun.max").foregroundStyle(AtlasTheme.clay)
            }
            let layout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(store.todayNewCount) / \(store.preferences.dailyGoal)").font(
                        .system(.title2, design: .serif))
                    Text("新词目标").font(.caption).foregroundStyle(AtlasTheme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        store.todayReviewCount == 0
                            ? "—" : "\(Int(Double(store.todayCorrectCount) / Double(store.todayReviewCount) * 100))%"
                    )
                    .font(.system(.title2, design: .serif))
                    Text("首次正确率").font(.caption).foregroundStyle(AtlasTheme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ProgressView(value: min(1, Double(store.todayNewCount) / Double(max(1, store.preferences.dailyGoal))))
                .tint(AtlasTheme.green).accessibilityLabel("今日新词目标")
        }.atlasSurface(padding: 20)
    }

    private var syncSummary: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: "icloud").font(.title3)
                Text("安心记录每一步").font(.headline)
            }
            Text(store.syncStatus).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                Text("学习记录优先保存在本机。\n离线时，也能继续学习。")
                    .font(.caption).foregroundStyle(AtlasTheme.secondary).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    router.showsSettings = true
                } label: {
                    Image(systemName: "arrow.up.right").frame(width: 44, height: 44)
                        .background(AtlasTheme.surface.opacity(0.7), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("查看同步设置")
            }
        }.padding(20).background(AtlasTheme.moss.opacity(0.55), in: RoundedRectangle(cornerRadius: 22))
    }

    private func metric(_ title: String, value: String, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(title).font(.caption).foregroundStyle(AtlasTheme.secondary)
                Spacer(minLength: 2)
                Image(systemName: symbol).font(.subheadline.weight(.light)).foregroundStyle(AtlasTheme.green)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    metricValue(value).fixedSize()
                    Text(unit).font(.caption).foregroundStyle(AtlasTheme.secondary).fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    metricValue(value).lineLimit(1).minimumScaleFactor(0.8)
                    Text(unit).font(.caption).foregroundStyle(AtlasTheme.secondary)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).atlasSurface(padding: 17)
            .accessibilityElement(children: .combine)
    }

    private func metricValue(_ value: String) -> some View {
        Text(value).font(.system(size: metricSize, weight: .regular, design: .serif)).monospacedDigit()
    }
}
