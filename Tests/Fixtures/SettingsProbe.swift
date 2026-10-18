import Foundation
import AppKit
@main struct SettingsProbe {
    @MainActor static func main() throws {
        let suite = "daydistance-settings-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        precondition(SettingsRouting.section(defaults: defaults) == .general)
        SettingsRouting.request(.notifications, defaults: defaults, center: center)
        precondition(SettingsRouting.section(defaults: defaults) == .notifications)
        precondition(SettingsSection.allCases.count == 5)
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
        print("Settings route persistence / invalid route fallback / all data modal guards PASS")
    }
}
