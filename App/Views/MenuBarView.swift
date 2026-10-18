import SwiftUI
import AppKit
import WidgetKit

/// Changes locale without changing view identity, so editor @State drafts survive.
struct AppLanguageEnvironment: ViewModifier {
    func body(content: Content) -> some View { content.environment(\.locale, L10n.locale) }
}
extension View {
    func appLanguage() -> some View { modifier(AppLanguageEnvironment()) }
}

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

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, notifications, data, widgets, updates
    var id: Self { self }
    var label: String {
        let key = switch self { case .general: "通用"; case .notifications: "通知与后台"; case .data: "数据与备份"; case .widgets: "小组件"; case .updates: "软件更新" }
        return L10n.text(key)
    }
    var symbol: String { switch self { case .general: "gearshape"; case .notifications: "bell"; case .data: "externaldrive"; case .widgets: "rectangle.3.group"; case .updates: "arrow.triangle.2.circlepath" } }
}
enum SettingsDataAction: String { case importEvents, exportEvents, backups }
enum SettingsRouting {
    static let key = "settingsSection"
    static let sectionRequested = Notification.Name("daydistance.settings.section")
    static let dataRequested = Notification.Name("daydistance.settings.data")
    static func section(defaults: UserDefaults = .standard) -> SettingsSection {
        SettingsSection(rawValue: defaults.string(forKey: key) ?? "") ?? .general
    }
    static func request(_ section: SettingsSection, defaults: UserDefaults = .standard, center: NotificationCenter = .default) {
        defaults.set(section.rawValue, forKey: key)
        center.post(name: sectionRequested, object: section.rawValue)
    }
}

struct PreferencesView: View {
    @Bindable var dockIcons: DockIconController
    @Bindable var reminders: EventReminderService
    @Bindable var background: BackgroundReminderController
    @Bindable var store: EventStore
    @Bindable var updates: UpdateController = .production()
    @Bindable var widgetMaintenance: WidgetMaintenanceController = .production()
    var applyLanguage: @MainActor (AppLanguage) throws -> Void = { language in
        try language.apply(file: SharedContainer.languageFileURL())
        WidgetCenter.shared.reloadAllTimelines()
    }
    @AppStorage("settingsSection") private var sectionRaw = SettingsSection.general.rawValue
    @AppStorage("vimKeysEnabled") private var vimKeysEnabled = true
    @AppStorage("showMenuBar") private var showMenuBar = false
    @State private var showReminderDetails = false
    @State private var showReleaseHistory = false
    @State private var backups: [LocalBackup] = []
    @State private var backupError: String?
    @State private var language = AppLanguage.selection()
    @State private var languageError: String?
    private var section: SettingsSection { SettingsSection(rawValue: sectionRaw) ?? .general }
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsSection.allCases, selection: Binding<SettingsSection?>(get: { section }, set: { if let value = $0 { sectionRaw = value.rawValue } })) { page in
                Label(page.label, systemImage: page.symbol).tag(page)
            }.listStyle(.sidebar)
                .accessibilityLabel("设置分类")
                .toolbar(removing: .sidebarToggle)
                .frame(minWidth: 210, idealWidth: 230, maxWidth: 270)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } detail: {
            Group {
                if section == .widgets {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            WidgetSetupGuide()
                            WidgetCheckPane(store: store, maintenance: widgetMaintenance)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Form {
                        switch section {
                        case .general: general
                        case .notifications: notifications
                        case .data: data
                        case .widgets: EmptyView()
                        case .updates: softwareUpdates
                        }
                    }.formStyle(.grouped)
                }
            }.navigationTitle(section.label)
                .toolbar(removing: .sidebarToggle)
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 490, idealHeight: 530)
        .onReceive(NotificationCenter.default.publisher(for: SettingsRouting.sectionRequested)) { note in
            if let raw = note.object as? String, SettingsSection(rawValue: raw) != nil { sectionRaw = raw }
        }
        .sheet(isPresented: $showReleaseHistory) { ReleaseHistoryView().appLanguage() }
        .task(id: section) {
            if section == .data {
                refreshBackups()
            }
            guard section == .notifications else { return }
            background.refreshStatus()
            while !Task.isCancelled {
                await reminders.refreshPermissionAndScheduleIfChanged()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onChange(of: store.events) { if section == .data { refreshBackups() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard section == .notifications else { return }
            background.refreshStatus()
            Task { await reminders.refreshPermissionAndScheduleIfChanged() }
        }
    }
    @ViewBuilder private var general: some View {
        Section("语言") {
            Picker("应用语言", selection: $language) {
                ForEach(AppLanguage.allCases) { Text(verbatim: $0.label).tag($0) }
            }.onChange(of: language) {
                guard language != L10n.currentLanguage else { return }
                do {
                    try applyLanguage(language)
                    languageError = nil
                } catch {
                    language = L10n.currentLanguage
                    languageError = L10n.text("无法应用语言，请重试。")
                }
            }
            Text("选择后立即生效，桌面小组件会随后刷新。")
                .font(.caption).foregroundStyle(.secondary)
            if let languageError { Text(languageError).foregroundStyle(.red) }
        }
        Section("外观") {
            Picker("Dock 图标外观", selection: Binding(get: { dockIcons.selection }, set: { dockIcons.select($0) })) {
                ForEach(DockIconAppearance.allCases) { Text($0.label).tag($0) }
            }
            Text("仅影响应用运行时的 Dock 图标；访达与 Spotlight 的图标跟随系统。").font(.caption).foregroundStyle(.secondary)
            if let message = dockIcons.errorMessage { Text(message).foregroundStyle(.red) }
        }
        Section("菜单栏") {
            Toggle("显示菜单栏图标", isOn: $showMenuBar)
            Text("显示置顶及最近事件，快速打开应用或新建事件。").font(.caption).foregroundStyle(.secondary)
        }
        Section("键盘") {
            Toggle("Vim 键位", isOn: $vimKeysEnabled)
            Text("仅在事件列表中生效。键位说明见帮助。").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var softwareUpdates: some View {
        Section("软件更新") {
            LabeledContent("当前版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            Toggle("自动检查更新", isOn: Binding(get: { updates.automaticChecksEnabled }, set: { updates.automaticChecksEnabled = $0 }))
            Text("应用打开时，每天检查 GitHub 上的新版本。发现更新后先询问，确认后下载、校验并安装。")
                .font(.caption).foregroundStyle(.secondary)
            Button("检查更新…") { updates.checkForUpdates() }.disabled(!store.canManageData || !updates.canCheck)
            Button("更新日志…") { showReleaseHistory = true }
            if let checked = updates.lastChecked {
                LabeledContent("上次检查", value: checked.formatted(date: .abbreviated, time: .shortened))
            }
            if let error = updates.errorMessage { Text(error).foregroundStyle(.red) }
            if updates.isWaitingToInstall { Text("完成当前编辑后将安装更新并重新打开日距。").foregroundStyle(.secondary) }
            if !store.canManageData { Text("请先完成当前编辑或文件操作。").foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private var notifications: some View {
        Section("系统通知") {
            LabeledContent("通知权限", value: reminders.authorizationDescription)
            if let next = reminders.nextScheduledDates.values.filter({ $0 > Date() }).min() {
                LabeledContent("下一条已安排提醒", value: next.formatted(date: .abbreviated, time: .shortened))
            } else { Text("没有已安排的提醒").foregroundStyle(.secondary) }
            Button("打开系统通知设置…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
        }
        Section("退出后的提醒") {
            Toggle("后台刷新提醒", isOn: Binding(get: { background.isRequested }, set: { enabled in Task { await background.setEnabled(enabled) } })).disabled(background.isUpdating)
            Text(background.statusDescription).font(.callout).foregroundStyle(.secondary)
            if let message = background.errorMessage { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            if background.status == .requiresApproval || background.status == .unavailable {
                Button("管理后台权限") { background.openSettings() }
            }
            DisclosureGroup("安排详情", isExpanded: $showReminderDetails) {
                if let through = reminders.dailyCoverageDates.values.min() {
                    LabeledContent("每日提醒已安排至", value: through.formatted(date: .abbreviated, time: .shortened))
                }
                Text("仅在本机补排每日、满月和周年通知；关闭后已安排的通知仍会发送，覆盖日期之后需重新打开应用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var data: some View {
        Section("事件文件") {
            LabeledContent("事件数量", value: store.isLoaded ? L10n.format("%ld 个", store.events.count) : L10n.text("未成功载入"))
            HStack {
                Button("导入事件…") { perform(.importEvents) }
                Button("导出事件…") { perform(.exportEvents) }
            }.disabled(!store.canManageData)
        }
        Section("自动本地备份") {
            Text("成功修改后自动保留最多20份快照。").foregroundStyle(.secondary)
            LabeledContent("可用备份", value: L10n.format("%ld 份", backups.count))
            if let latest = backups.first { LabeledContent("最近备份", value: latest.createdAt.formatted(date: .abbreviated, time: .shortened)) }
            if let backupError { Text(backupError).foregroundStyle(.red) }
            Button("备份与恢复…") { perform(.backups) }.disabled(!store.canManageData)
        }
        if !store.canManageData { Text("请先完成当前编辑或文件操作。").foregroundStyle(.secondary) }
    }
    private func refreshBackups() {
        do { backups = try store.listBackups(); backupError = nil }
        catch { backupError = error.localizedDescription }
    }
    private func perform(_ action: SettingsDataAction) {
        guard store.canManageData else { return }
        NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: SettingsRouting.dataRequested, object: action.rawValue)
    }
}
