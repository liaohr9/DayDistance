import SwiftUI
import AppKit
import OSLog
import Combine
import WidgetKit

@main
@MainActor enum DayDistanceLaunch {
    static func main() {
        switch BackgroundReminderInvocation.mode(arguments: CommandLine.arguments) {
        case .normal:
            let language = AppLanguage.selection()
            language.save()
            L10n.useLanguage(language)
            do {
                if try language.publish(to: SharedContainer.languageFileURL()) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                Logger(subsystem: "local.daydistance.mac", category: "language").error("Widget language could not be saved: \(error.localizedDescription, privacy: .private)")
            }
            DayDistanceApp.main()
        case .invalid: exit(64)
        case .refresh:
            L10n.useLanguage(SharedContainer.appliedLanguage())
            BackgroundReminderController.recordExecution()
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            let timeout = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { _ in
                Logger(subsystem: "local.daydistance.mac", category: "background-reminders").error("Background refresh timed out")
                exit(70)
            }
            Task { @MainActor in
                defer { timeout.invalidate(); app.terminate(nil) }
                do {
                    let repository = try SharedContainer.repository()
                    let events = try repository.load()
                    guard events.contains(where: { $0.isActive && $0.hasRecurringReminders }) else {
                        Logger(subsystem: "local.daydistance.mac", category: "background-reminders").info("No enabled recurring reminders; no queue changed")
                        return
                    }
                    let reminders = EventReminderService(repositoryProvider: { repository })
                    await reminders.sync(events: events)
                    Logger(subsystem: "local.daydistance.mac", category: "background-reminders").info("Background refresh finished; pending events=\(reminders.nextScheduledDates.count)")
                } catch {
                    Logger(subsystem: "local.daydistance.mac", category: "background-reminders").error("Background read failed; existing queue retained: \(error.localizedDescription, privacy: .private)")
                }
            }
            app.run()
        }
    }
}

struct DayDistanceApp: App {
    @NSApplicationDelegateAdaptor(DayDistanceAppDelegate.self) private var applicationDelegate
    @State private var store: EventStore
    @State private var reminders = EventReminderService(repositoryProvider: { try SharedContainer.repository() })
    @State private var backgroundReminders = BackgroundReminderController()
    @State private var updates = UpdateController.production()
    @State private var widgetMaintenance = WidgetMaintenanceController.production()
    @AppStorage("showMenuBar") private var showMenuBar = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @MainActor init() {
        let initialStore = EventStore(automaticallyLoad: false)
        _store = State(initialValue: initialStore)
        ShortcutEventService.install(store: initialStore,
            repositoryProvider: { try SharedContainer.repository() },
            canUseUI: { NSApp.modalWindow == nil && NSApp.keyWindow?.attachedSheet == nil },
            activateMain: { NSApp.activate(ignoringOtherApps: true) })
    }
    var body: some Scene {
        Window(L10n.text("日距"), id: "main") {
            ContentView(store: store)
                .appLanguage()
                .environment(\.requestReminderPermission, { await reminders.authorizeIfNeeded() })
                .environment(\.eventReminders, reminders)
                .frame(minWidth: 640, minHeight: 360)
                .task {
                    if !store.isLoaded { store.reload() }
                    updates.start {
                        store.canManageData && NSApp.modalWindow == nil &&
                        !NSApp.windows.contains(where: { $0.attachedSheet != nil })
                    }
                    installShortcuts()
                    await syncReminders()
                    await backgroundReminders.refreshAfterUpdate()
                    publishReminderMessage()
                }
                .task { await widgetMaintenance.prepareAfterLaunch() }
                .onChange(of: reminders.statusMessage) { publishReminderMessage() }
                .onChange(of: backgroundReminders.canRenewReminders) { publishReminderMessage() }
                 .onChange(of: store.events) { Task { await syncReminders() } }
                .onReceive(Timer.publish(every: 3600, on: .main, in: .common).autoconnect()) { _ in Task { await syncReminders() } }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in Task { await syncReminders() } }
                .onChange(of: scenePhase) { if scenePhase == .active { Task { await syncReminders() } } }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    Task { await syncReminders() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    Task { await syncReminders() }
                }
                .onChange(of: store.isLoaded) { if store.isLoaded { Task { await syncReminders() } } }
                .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChange)) { _ in
                    Task { await syncReminders() }
                }
        }
        .defaultSize(width: 800, height: 520)
        .commands { DayDistanceCommands(store: store, updates: updates) }
        Settings { PreferencesView(dockIcons: applicationDelegate.dockIcons, reminders: reminders, background: backgroundReminders, store: store, updates: updates, widgetMaintenance: widgetMaintenance).appLanguage() }
            .windowToolbarStyle(.unifiedCompact)
            .commandsRemoved()
        MenuBarExtra(L10n.text("日距"), systemImage: "hourglass", isInserted: $showMenuBar) {
            MenuBarView(store: store, openMain: activateMain, create: {
                activateMain()
                store.newEvent()
            }).appLanguage()
        }.menuBarExtraStyle(.window)
        Window(L10n.text("日距帮助"), id: "help") {
            HelpView(store: store)
                .appLanguage()
        }.defaultSize(width: 600, height: 460)
    }
    @MainActor private func installShortcuts() {
        ShortcutEventService.install(store: store,
            repositoryProvider: { try SharedContainer.repository() },
            canUseUI: { NSApp.modalWindow == nil && NSApp.keyWindow?.attachedSheet == nil },
            activateMain: activateMain)
    }
    @MainActor private func syncReminders() async {
        guard store.isLoaded else { return }
        backgroundReminders.refreshStatus()
        await reminders.sync(events: store.events.filter(\.isActive))
        // Publish after every sync, even if a recurring failure has the same text.
        publishReminderMessage()
    }
    @MainActor private func publishReminderMessage() {
        guard store.isLoaded else { return }
        store.reminderMessage = reminders.displayMessage(backgroundRefreshEnabled: backgroundReminders.canRenewReminders)
    }
    @MainActor private func activateMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Focused actions change when selection and sheet focus change. Keep that
// dependency in the menu, so updating commands cannot invalidate the Scene
// that produces those actions and create a focus/layout feedback loop.
private struct DayDistanceCommands: Commands {
    @StateObject private var undoUpdates = CommandUndoUpdates()
    let store: EventStore
    let updates: UpdateController
    @AppStorage("eventSortOrder") private var sortOrder = EventSortOrder.date
    @FocusedValue(\.eventActions) private var eventActions
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some Commands {
        let _ = undoUpdates.revision
            CommandGroup(replacing: .appInfo) {
                Button(L10n.format("关于 %@", L10n.text("日距"))) { NSApp.orderFrontStandardAboutPanel(nil) }
            }
            CommandGroup(after: .appInfo) {
                Button(L10n.text("检查更新…")) { updates.checkForUpdates() }
                    .disabled(!store.canManageData || !updates.canCheck)
            }
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("设置…")) { openSettings() }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appVisibility) {
                Button(L10n.format("隐藏 %@", L10n.text("日距"))) { NSApp.hide(nil) }.keyboardShortcut("h", modifiers: .command)
                Button(L10n.text("隐藏其他")) { NSApp.hideOtherApplications(nil) }.keyboardShortcut("h", modifiers: [.command, .option])
                Button(L10n.text("全部显示")) { NSApp.unhideAllApplications(nil) }
            }
            CommandGroup(replacing: .appTermination) {
                Button(L10n.format("退出 %@", L10n.text("日距"))) { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button(L10n.text("关闭窗口")) { NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil) }
                    .keyboardShortcut("w", modifiers: .command)
                Button(L10n.text("关闭所有窗口")) { NSApp.sendAction(Selector(("closeAll:")), to: nil, from: nil) }
                    .keyboardShortcut("w", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .pasteboard) {
                nativeTextCommand("剪切", action: "cut:", key: "x")
                nativeTextCommand("拷贝", action: "copy:", key: "c")
                nativeTextCommand("粘贴", action: "paste:", key: "v")
                Button(L10n.text("删除文本")) { NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: nil) }
                    .disabled(!canPerformNative(#selector(NSText.delete(_:))))
                nativeTextCommand("全选", action: "selectAll:", key: "a")
            }
            CommandGroup(replacing: .help) {
                Button(L10n.text("日距帮助")) { openWindow(id: "help") }
            }
            CommandGroup(after: .sidebar) {
                Picker(L10n.text("事件排序"), selection: $sortOrder) {
                    ForEach(EventSortOrder.allCases) { Text($0.label).tag($0) }
                }.disabled(eventActions?.canTransfer != true)
            }
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("新建事件")) {
                    if let actions = eventActions { actions.create() }
                    else if store.editingEvent == nil { store.newEvent() }
                }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!store.isLoaded || store.editingEvent != nil || store.isTransferring || store.isShowingBackups || store.isHistoryModalPresented || eventActions?.canCreate == false)
            }
            CommandGroup(after: .newItem) {
                Button(L10n.text("编辑事件")) { eventActions?.edit() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(eventActions?.canEdit != true)
                Button(L10n.text("复制为新事件")) { eventActions?.duplicate() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(eventActions?.canDuplicate != true)
                Button(L10n.text("归档所选事件")) { eventActions?.archive() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(eventActions?.canArchive != true)
                Button(L10n.text("恢复所选事件")) { eventActions?.restore() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(eventActions?.canRestore != true)
                Button(L10n.text("删除事件")) { eventActions?.delete() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(eventActions?.hasSelection != true)
                Divider()
                Button(L10n.text("导入事件…")) { eventActions?.importEvents() }
                    .disabled(eventActions?.canTransfer != true)
                Button(L10n.text("导出事件…")) { eventActions?.exportEvents() }
                    .disabled(eventActions?.canTransfer != true)
                Button(L10n.text("分享图片…")) { eventActions?.share() }
                    .disabled(eventActions?.canShare != true)
                Button(L10n.text("备份与恢复…")) { store.isShowingBackups = true }
                    .disabled(eventActions?.canTransfer != true)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(L10n.text("撤销")) { performUndo(redo: false) }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!canUndo(redo: false))
                Button(L10n.text("重做")) { performUndo(redo: true) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!canUndo(redo: true))
            }
            CommandGroup(after: .pasteboard) {
                Button(L10n.text("复制事件摘要")) { eventActions?.copySummary() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(eventActions?.canShare != true)
            }
            CommandGroup(after: .textEditing) {
                Button(L10n.text("搜索事件")) { eventActions?.searchEvents() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(eventActions?.canSearch != true)
            }
    }
    @MainActor private func nativeTextCommand(_ title: String, action: String, key: KeyEquivalent) -> some View {
        let selector = Selector(action)
        return Button(L10n.text(title)) { NSApp.sendAction(selector, to: nil, from: nil) }
            .keyboardShortcut(key, modifiers: .command)
            .disabled(!canPerformNative(selector))
    }
    @MainActor private func canPerformNative(_ action: Selector) -> Bool {
        guard let target = NSApp.target(forAction: action) else { return false }
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        if let validator = target as? NSMenuItemValidation { return validator.validateMenuItem(item) }
        if let validator = target as? NSUserInterfaceValidations { return validator.validateUserInterfaceItem(item) }
        return true
    }
    @MainActor private func canUndo(redo: Bool) -> Bool {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
            return redo ? text.undoManager?.canRedo == true : text.undoManager?.canUndo == true
        }
        return redo ? store.eventUndoManager.canRedo : store.eventUndoManager.canUndo
    }
    @MainActor private func performUndo(redo: Bool) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, let manager = text.undoManager {
            if redo { manager.redo() } else { manager.undo() }
        } else {
            if redo { store.eventUndoManager.redo() } else { store.eventUndoManager.undo() }
        }
    }
}

@MainActor private final class CommandUndoUpdates: ObservableObject {
    @Published private(set) var revision = 0
    private var subscription: AnyCancellable?
    init() {
        let names: [Notification.Name] = [NSText.didChangeNotification,
            NSTextView.didChangeSelectionNotification,
            NSText.didBeginEditingNotification, NSText.didEndEditingNotification,
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange, NSWindow.didBecomeKeyNotification]
        subscription = Publishers.MergeMany(names.map { NotificationCenter.default.publisher(for: $0) })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.revision += 1 }
    }
}
