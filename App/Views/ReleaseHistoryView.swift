import SwiftUI

struct ReleaseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("更新日志").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("开发预览版，尚未经过 Apple 公证。").font(.callout).foregroundStyle(.secondary)
                    if ReleaseHistory.entries.isEmpty {
                        Text("无法读取更新日志。")
                    }
                    ForEach(ReleaseHistory.entries) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: entry.version).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                                Spacer()
                                Text(verbatim: entry.date).font(.callout).foregroundStyle(.secondary)
                            }
                            ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title).font(.headline)
                                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("•").accessibilityHidden(true)
                                            Text(item.text(language: L10n.currentLanguage)).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                            Divider().padding(.top, 6)
                        }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.textSelection(.enabled)
        }.frame(width: 600, height: 540)
    }
}
