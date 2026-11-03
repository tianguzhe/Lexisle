import SwiftUI

struct AttributionView: View {
    @State private var notices: [LicenseNotice] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("让知识，被更多人看见。").font(.system(.title, design: .serif))
                Text("词库文本、插画和录音由 Word Atlas contributors 提供，采用 CC BY 4.0 授权。本版本改编为原生 SwiftUI 应用，并新增本地学习记录与 iCloud 同步。")
                Text("原项目内容使用生成式 AI 和合成语音，经过自动校验，尚未逐条人工审校，可能存在错误。它不是官方雅思词表，也不承诺考试成绩。")
                    .foregroundStyle(AtlasTheme.secondary)
                ForEach(notices) { notice in
                    Text(notice.text).font(.caption.monospaced()).textSelection(.enabled)
                }
            }.padding(28).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.background(AtlasTheme.paper).foregroundStyle(AtlasTheme.ink).navigationTitle("内容与许可")
            .task {
                notices = await Task.detached(priority: .userInitiated) { LicenseNotice.loadBundled() }.value
            }
    }
}

private struct LicenseNotice: Identifiable, Sendable {
    let id: String
    let text: String

    static func loadBundled() -> [LicenseNotice] {
        let resources = [("UPSTREAM_LICENSE", "txt"), ("CONTENT_LICENSE", "md"), ("FSRS_LICENSE", "txt")]
        return resources.compactMap { name, fileExtension in
            guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
                let text = try? String(contentsOf: url, encoding: .utf8)
            else { return nil }
            return LicenseNotice(id: name, text: text)
        }
    }
}
