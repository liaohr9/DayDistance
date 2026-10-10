import SwiftUI

@MainActor
struct BackupsView: View {
    let store: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var backups: [LocalBackup] = []
    @State private var selectedID: String?
    @State private var previewEvents: [CountdownEvent]?
    @State private var previewBaseline: [CountdownEvent] = []
    @State private var message: String?
    @State private var pendingRestore: LocalBackup?
    @State private var pendingBaseline: [CountdownEvent]?
    @State private var pendingSummary: String?
    @State private var isLoading = false

    private var selected: LocalBackup? { backups.first { $0.id == selectedID } }
    private var summary: String? {
        guard let previewEvents else { return nil }
        let current = Dictionary(uniqueKeysWithValues: previewBaseline.map { ($0.id, $0) })
        let incoming = Dictionary(uniqueKeysWithValues: previewEvents.map { ($0.id, $0) })
        let added = incoming.keys.filter { current[$0] == nil }.count
        let removed = current.keys.filter { incoming[$0] == nil }.count
        let changed = incoming.filter { id, event in current[id] != nil && current[id] != event }.count
        return L10n.format("恢复后共 %d 个事件：新增 %d，移除 %d，更改 %d。", previewEvents.count, added, removed, changed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("本地备份")).font(.title2)
            Text(L10n.text("仅保存在这台 Mac，最多保留 20 份。"))
                .foregroundStyle(.secondary)
            if backups.isEmpty {
                ContentUnavailableView {
                    Label(L10n.text("尚无本地备份"), systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(L10n.text("下一次成功修改事件后会创建恢复快照。"))
                }
            } else {
                List(selection: $selectedID) {
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.createdAt.formatted(date: .abbreviated, time: .standard))
                            Text(L10n.format("%@ · %d 个事件", L10n.text(backup.phase == .before ? "修改前" : "修改后"), backup.eventCount))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .tag(backup.id)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 160)
            }
            if let summary {
                Text(summary).textSelection(.enabled)
                Text(L10n.text("恢复将替换当前事件列表，保留备份中的事件标识。"))
                    .font(.callout).foregroundStyle(.secondary)
            } else if !backups.isEmpty {
                Text(L10n.text("选择一份备份查看恢复变化。")).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button(L10n.text("重新读取"), action: reload).disabled(isLoading)
                Spacer()
                Button(L10n.text("关闭")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("恢复所选备份…")) {
                    pendingBaseline = previewBaseline
                    pendingSummary = summary
                    pendingRestore = selected
                }
                    .disabled(selected == nil || previewEvents == nil || isLoading)
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 440, idealHeight: 460)
        .onAppear(perform: reload)
        .onChange(of: selectedID) { preview() }
        .onChange(of: store.events) { preview() }
        .alert(L10n.text("恢复这份备份？"), isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
            Button(L10n.text("取消"), role: .cancel) { pendingRestore = nil }
            Button(L10n.text("恢复"), role: .destructive) { restore() }
        } message: {
            Text([pendingSummary, L10n.text("恢复将替换当前事件列表，保留备份中的事件标识。")].compactMap { $0 }.joined(separator: "\n"))
        }
    }

    private func reload() {
        isLoading = true
        defer { isLoading = false }
        do {
            backups = try store.listBackups()
            selectedID = backups.contains { $0.id == selectedID } ? selectedID : backups.first?.id
            message = nil
            preview()
        } catch {
            backups = []
            selectedID = nil
            previewEvents = nil
            message = L10n.text("无法读取本地备份。")
        }
    }

    private func preview() {
        previewEvents = nil
        guard let selected, let repository = store.backupRepository else { return }
        do {
            previewEvents = try repository.load(selected)
            previewBaseline = store.events
            message = nil
        } catch { message = L10n.text("无法预览这份备份。") }
    }

    private func restore() {
        guard let backup = pendingRestore, let baseline = pendingBaseline else { return }
        pendingRestore = nil
        pendingBaseline = nil
        pendingSummary = nil
        guard baseline == store.events else {
            preview()
            message = L10n.text("当前事件已更改，请重新确认恢复。")
            return
        }
        if store.restoreBackup(backup) {
            reload()
            message = L10n.text("已恢复本地备份。")
        } else { message = store.errorMessage ?? L10n.text("恢复失败，当前数据已保留。") }
    }
}
