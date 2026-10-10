import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var store: EventStore
    let openMain: () -> Void
    let create: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                let events = Array(WidgetPolicy.sorted(events: store.events, now: context.date).prefix(5))
                if !store.isLoaded {
                    Label("无法读取事件", systemImage: "exclamationmark.triangle")
                } else if events.isEmpty {
                    Text("没有可显示的事件").foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        Button { openMain() } label: {
                            HStack {
                                Image(systemName: event.symbol).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).lineLimit(1)
                                    Text(event.dateLabel(now: context.date)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(EventDisplayFormatter.summary(event: event, now: context.date)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.8)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Divider()
                HStack {
                    Button("打开日距", action: openMain)
                    Spacer()
                    Button(action: create) { Label("新建事件", systemImage: "plus") }
                        .disabled(!store.isLoaded || store.editingEvent != nil || store.isTransferring || store.isShowingBackups || store.isHistoryModalPresented)
                }
            }.padding(14).frame(width: 340)
        }
    }
}

struct PreferencesView: View {
    @Bindable var dockIcons: DockIconController
    @Bindable var reminders: EventReminderService
    @Bindable var background: BackgroundReminderController
    @AppStorage("vimKeysEnabled") private var vimKeysEnabled = true
    @AppStorage("showMenuBar") private var showMenuBar = false
    var body: some View {
        Form {
            Section {
                Picker("Dock 图标外观", selection: Binding(
                    get: { dockIcons.selection },
                    set: { dockIcons.select($0) })) {
                    ForEach(DockIconAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                Text("仅影响应用运行时的 Dock 图标；访达与 Spotlight 的图标跟随系统。")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = dockIcons.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Toggle("显示菜单栏图标", isOn: $showMenuBar)
                Text("显示置顶及最近事件，快速打开应用或新建事件。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Vim 键位", isOn: $vimKeysEnabled)
                Text("仅在事件列表中生效。键位说明见帮助。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("通知权限", value: reminders.authorizationDescription)
                    .id(reminders.authorizationDescription)
                if let next = reminders.nextScheduledDates.values.filter({ $0 > Date() }).min() {
                    LabeledContent("下一条已安排提醒", value: next.formatted(date: .abbreviated, time: .shortened))
                } else { Text("没有已安排的提醒").foregroundStyle(.secondary) }
                if let through = reminders.dailyCoverageDates.values.min() {
                    LabeledContent("每日提醒已安排至", value: through.formatted(date: .abbreviated, time: .shortened))
                }
                Button("打开系统设置") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
            }
            Section {
                Toggle("后台刷新提醒", isOn: Binding(get: { background.isRequested }, set: { enabled in Task { await background.setEnabled(enabled) } }))
                    .disabled(background.isUpdating)
                Text(background.statusDescription).font(.caption).foregroundStyle(.secondary)
                Text("仅在本机补排每日、满月和周年通知；关闭后已安排的通知仍会发送，覆盖日期之后需重新打开应用。")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = background.errorMessage { Text(message).font(.caption).foregroundStyle(.red) }
                if background.status == .requiresApproval || background.status == .unavailable {
                    Button("管理后台权限") { background.openSettings() }
                }
            }
        }.formStyle(.grouped).padding().frame(width: 440, height: 500)
            .task {
                // Permission can change in System Settings without this window being recreated.
                while !Task.isCancelled {
                    await reminders.refreshPermissionAndScheduleIfChanged()
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                }
            }
            .onAppear { background.refreshStatus() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                background.refreshStatus()
                Task { await reminders.refreshPermissionAndScheduleIfChanged() }
            }
    }
}
