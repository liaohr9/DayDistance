import Foundation
import AppKit
import UserNotifications
@main struct SettingsProbe {
    @MainActor static func main() async throws {
        let suite = "daydistance-settings-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        precondition(SettingsRouting.section(defaults: defaults) == .general)
        SettingsRouting.request(.notifications, defaults: defaults, center: center)
        precondition(SettingsRouting.section(defaults: defaults) == .notifications)
        precondition(SettingsSection.allCases.count == 6)
        defaults.set("removed-page", forKey: SettingsRouting.key)
        precondition(SettingsRouting.section(defaults: defaults) == .general)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let repository = EventRepository(fileURL: root.appendingPathComponent("events.json"))
        try repository.save([], replacing: [])
        let store = EventStore(repository: repository)
        precondition(store.canManageData)
        store.newEvent(); precondition(!store.canManageData)
        store.editingEvent = nil
        store.isTransferring = true; precondition(!store.canManageData)
        store.isTransferring = false; store.isShowingBackups = true; precondition(!store.canManageData)
        store.isShowingBackups = false; store.isHistoryModalPresented = true; precondition(!store.canManageData)
        store.isHistoryModalPresented = false; precondition(store.canManageData)
        precondition(!EventStore(automaticallyLoad: false).canManageData)
        let originalLanguage = L10n.currentLanguage
        defer { L10n.useLanguage(originalLanguage) }
        let menu = NSMenu(title: "Main")
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        file.submenu = NSMenu(title: "File")
        file.submenu!.addItem(NSMenuItem(title: "Close", action: Selector(("performClose:")), keyEquivalent: "w"))
        file.submenu!.addItem(NSMenuItem(title: "Close All", action: Selector(("menuAction:")), keyEquivalent: ""))
        let userWindow = NSMenuItem(title: "File", action: Selector(("makeKeyAndOrderFront:")), keyEquivalent: "")
        file.submenu!.addItem(userWindow)
        menu.addItem(file)
        L10n.useLanguage(.simplifiedChinese); NativeMenuLanguage.refresh(menu)
        precondition(file.title == "文件" && file.submenu!.items[0].title == "关闭")
        precondition(file.submenu!.items[1].title == "全部关闭", "Wrapped native actions must refresh their titles too")
        precondition(userWindow.title == "File", "Never translate user window names")
        L10n.useLanguage(.english); NativeMenuLanguage.refresh(menu)
        precondition(file.title == "File" && file.submenu!.items[0].title == "Close")
        let blocked=root.appendingPathComponent("blocked-owner")
        try Data("not a directory".utf8).write(to:blocked)
        let idle=EventStore(repository:repository,automaticallyLoad:false)
        let controller=AutomationController()
        let reminder=EventReminderService(client:AutomationQuietClient())
        await controller.start(store:idle,reminders:reminder,open:{_ in},directory:blocked)
        precondition(!idle.isLoaded && idle.errorMessage != nil,"ownership failure must be visible")
        try FileManager.default.removeItem(at:blocked)
        try FileManager.default.createDirectory(at:blocked,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let endpoint=blocked.appendingPathComponent("rpc");try Data("not a socket".utf8).write(to:endpoint)
        idle.reload()
        for _ in 0..<50 {if idle.isLoaded {break};try await Task.sleep(for:.milliseconds(20))}
        precondition(idle.isLoaded && idle.errorMessage != nil,"listener failure must remain visible while ownership is retained")
        try FileManager.default.removeItem(at:endpoint)
        idle.reload()
        for _ in 0..<50 {if idle.errorMessage==nil {break};try await Task.sleep(for:.milliseconds(20))}
        let reply=try await Task.detached {try AutomationChannel.request(.init(operation:"capabilities"),directory:blocked)}.value
        precondition(reply != nil && idle.errorMessage==nil,"retry must recover the listener without bypassing ownership")
        print("AUTOMATION_OWNERSHIP_RECOVERY_PASS")
        print("Settings route persistence / invalid route fallback / all data modal guards PASS")
    }
}

@MainActor final class AutomationQuietClient:EventNotificationClient {
 func authorizationStatus() async -> UNAuthorizationStatus {.denied}
 func requestAuthorization() async throws -> Bool {false}
 func pendingRequests() async -> [UNNotificationRequest] {[]}
 func add(_ request:UNNotificationRequest) async throws {}
 func removePending(identifiers:[String]) {}
}
