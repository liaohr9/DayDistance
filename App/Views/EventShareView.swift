import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EventShareCard: View {
    let event: CountdownEvent
    let now: Date
    let showDate: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: event.symbol).accessibilityHidden(true)
                Text(event.title).lineLimit(2)
            }.font(.system(size: 24, weight: .medium))
            Spacer(minLength: 0)
            Text(EventDisplayFormatter.summary(event: event, now: now))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .lineLimit(2).minimumScaleFactor(0.5).monospacedDigit()
                .foregroundStyle(EventTheme.color(for: event.colorKey))
            if showDate { Text(event.dateLabel(now: now)).font(.system(size: 18)).foregroundStyle(.secondary) }
        }
        .padding(42).frame(width: 600, height: 360, alignment: .leading)
        .background(.white).foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }
}

@MainActor struct EventShareView: View {
    let event: CountdownEvent
    let now: Date
    let store: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDate = true
    @State private var isExporting = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("分享事件").font(.headline)
            EventShareCard(event: event, now: now, showDate: showDate)
                .scaleEffect(0.8, anchor: .topLeading).frame(width: 480, height: 288, alignment: .topLeading)
                .clipped().border(Color(nsColor: .separatorColor))
                .accessibilityLabel(event.title + ", " + EventDisplayFormatter.summary(event: event, now: now))
            Toggle("包含具体日期", isOn: $showDate).toggleStyle(.checkbox)
            Text("图片仅保存到你选择的位置，不会自动发送。")
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("复制摘要") { EventShareService.copySummary(event: event, now: now) }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存图片…", action: save).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 520).disabled(isExporting)
        .interactiveDismissDisabled(isExporting)
    }
    private func save() {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.title = L10n.text("保存分享图片")
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = L10n.text("日距分享.png")
        panel.canCreateDirectories = true
        isExporting = true; store.isTransferring = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            defer { isExporting = false; store.isTransferring = false }
            guard response == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                try EventShareService.save(event: event, now: now, showDate: showDate, to: url, protecting: store.protectedExportDataURLs)
                message = L10n.text("图片已保存。")
            } catch { message = L10n.format("图片保存失败：%@", error.localizedDescription) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}
