import SwiftUI
import AppKit
import OSLog

@main
@MainActor enum DayDistanceLaunch {
    static func main() {
        switch BackgroundReminderInvocation.mode(arguments: CommandLine.arguments) {
        case .normal: DayDistanceApp.main()
        case .invalid: exit(64)
        case .refresh:
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
    @AppStorage("showMenuBar") private var showMenuBar = false
    @AppStorage("eventSortOrder") private var sortOrder = EventSortOrder.date
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.eventActions) private var eventActions
    @MainActor init() {
        let initialStore = EventStore(automaticallyLoad: false)
        _store = State(initialValue: initialStore)
        ShortcutEventService.install(store: initialStore,
            repositoryProvider: { try SharedContainer.repository() },
            canUseUI: { NSApp.modalWindow == nil && NSApp.keyWindow?.attachedSheet == nil },
            activateMain: { NSApp.activate(ignoringOtherApps: true) })
    }
    var body: some Scene {
        Window("日距", id: "main") {
            ContentView(store: store)
                .environment(\.requestReminderPermission, { await reminders.authorizeIfNeeded() })
                .environment(\.eventReminders, reminders)
                .frame(minWidth: 640, minHeight: 360)
                .task { await backgroundReminders.refreshAfterUpdate(); if !store.isLoaded { store.reload() }; installShortcuts(); await syncReminders() }
                .onChange(of: reminders.statusMessage) { store.reminderMessage = reminders.statusMessage }
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
        }
        .defaultSize(width: 800, height: 520)
        .commands {
            CommandGroup(replacing: .help) {
                Button("日距帮助") { openWindow(id: "help") }
            }
            CommandGroup(after: .sidebar) {
                Picker("事件排序", selection: $sortOrder) {
                    ForEach(EventSortOrder.allCases) { Text($0.label).tag($0) }
                }.disabled(eventActions?.canTransfer != true)
            }
            CommandGroup(replacing: .newItem) {
                Button("新建事件") {
                    if let actions = eventActions { actions.create() }
                    else if store.editingEvent == nil { store.newEvent() }
                }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!store.isLoaded || store.editingEvent != nil || store.isTransferring || store.isShowingBackups || store.isHistoryModalPresented || eventActions?.canCreate == false)
            }
            CommandGroup(after: .newItem) {
                Button("编辑事件") { eventActions?.edit() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(eventActions?.canEdit != true)
                Button("复制为新事件") { eventActions?.duplicate() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(eventActions?.canDuplicate != true)
                Button("归档所选事件") { eventActions?.archive() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(eventActions?.canArchive != true)
                Button("恢复所选事件") { eventActions?.restore() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(eventActions?.canRestore != true)
                Button("删除事件") { eventActions?.delete() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(eventActions?.hasSelection != true)
                Divider()
                Button("导入事件…") { eventActions?.importEvents() }
                    .disabled(eventActions?.canTransfer != true)
                Button("导出事件…") { eventActions?.exportEvents() }
                    .disabled(eventActions?.canTransfer != true)
                Button("分享图片…") { eventActions?.share() }
                    .disabled(eventActions?.canShare != true)
                Button("备份与恢复…") { store.isShowingBackups = true }
                    .disabled(eventActions?.canTransfer != true)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { performUndo(redo: false) }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!canUndo(redo: false))
                Button("重做") { performUndo(redo: true) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!canUndo(redo: true))
            }
            CommandGroup(after: .pasteboard) {
                Button("复制事件摘要") { eventActions?.copySummary() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(eventActions?.canShare != true)
            }
            CommandGroup(after: .textEditing) {
                Button("搜索事件") { eventActions?.searchEvents() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(eventActions?.canSearch != true)
            }
        }
        Settings { PreferencesView(dockIcons: applicationDelegate.dockIcons, reminders: reminders, background: backgroundReminders) }
        MenuBarExtra("日距", systemImage: "hourglass", isInserted: $showMenuBar) {
            MenuBarView(store: store, openMain: activateMain, create: {
                activateMain()
                store.newEvent()
            })
        }.menuBarExtraStyle(.window)
        Window("日距帮助", id: "help") {
            HelpView(store: store)
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
        await reminders.sync(events: store.events.filter(\.isActive))
        // Publish after every sync, even if a recurring failure has the same text.
        if store.isLoaded { store.reminderMessage = reminders.statusMessage }
    }
    @MainActor private func activateMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
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
