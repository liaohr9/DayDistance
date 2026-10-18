import SwiftUI

struct SmartListBackupsView: View {
    @Bindable var store: SmartListStore
    @State private var backups: [SmartListBackup] = []
    @State private var pending: SmartListBackup?
    @State private var pendingFingerprint: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("智能列表备份")).font(.title2.bold())
            Text(L10n.text("恢复仅替换智能列表，不修改事件。"))
            Text(L10n.text("事件导出仅包含事件，不包含智能列表。")).font(.callout).foregroundStyle(.secondary)
            List(backups) { backup in
                HStack {
                    VStack(alignment: .leading) {
                        Text(backup.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                        Text(L10n.format("%ld 个智能列表", backup.listCount)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("恢复")) {
                        guard let fingerprint = store.recoveryFingerprint() else { return }
                        pendingFingerprint = fingerprint; pending = backup
                    }
                }
            }.frame(height: 260)
            if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button(L10n.text("完成")) { store.isShowingBackups = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 560)
        .onAppear(perform: reload)
        .alert(L10n.text("恢复智能列表备份？"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(L10n.text("取消"), role: .cancel) { pending = nil }
            Button(L10n.text("恢复"), role: .destructive) {
                if let backup = pending, let fingerprint = pendingFingerprint, store.restore(backup, replacingLiveFingerprint: fingerprint) { reload() }
                pending = nil; pendingFingerprint = nil
            }
        } message: { Text(L10n.text("当前智能列表会先自动备份。事件保持不变。")) }
    }
    private func reload() {
        do { backups = try store.backups() }
        catch { store.errorMessage = error.localizedDescription }
    }
}
