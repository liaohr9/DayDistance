import AppKit
import Observation

enum DockIconAppearance: String, CaseIterable, Identifiable {
    case system, light, dark, clear
    static let preferenceKey = "dockIconAppearance"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: L10n.text("跟随系统")
        case .light: L10n.text("亮色")
        case .dark: L10n.text("暗色")
        case .clear: L10n.text("透明玻璃")
        }
    }
    func resourceName(isDark: Bool) -> String? {
        switch self {
        case .system: nil
        case .light: "Light"
        case .dark: "Dark"
        case .clear: isDark ? "ClearDark" : "ClearLight"
        }
    }
}

/// Overrides the running Dock icon without changing the signed bundle or window appearance.
@MainActor @Observable final class DockIconController {
    private(set) var selection: DockIconAppearance = .system
    private(set) var errorMessage: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loadImage: (String) -> NSImage?
    @ObservationIgnored private let setImage: @MainActor (NSImage?) -> Void
    @ObservationIgnored private var images: [String: NSImage] = [:]
    @ObservationIgnored private var lastResource: String?
    @ObservationIgnored private var hasApplied = false
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    init(defaults: UserDefaults = .standard,
         loadImage: @escaping (String) -> NSImage? = { name in
             guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "DockIcons") else { return nil }
             return NSImage(contentsOf: url)
         },
         setImage: @escaping @MainActor (NSImage?) -> Void = { NSApplication.shared.applicationIconImage = $0 }) {
        self.defaults = defaults
        self.loadImage = loadImage
        self.setImage = setImage
    }

    func start() {
        restore()
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func restore(isDark: Bool? = nil) {
        let saved = defaults.string(forKey: DockIconAppearance.preferenceKey)
        let appearance = saved.flatMap(DockIconAppearance.init(rawValue:)) ?? .system
        if apply(appearance, isDark: isDark ?? systemIsDark) { selection = appearance }
    }

    @discardableResult func select(_ appearance: DockIconAppearance, isDark: Bool? = nil) -> Bool {
        guard apply(appearance, isDark: isDark ?? systemIsDark) else { return false }
        selection = appearance
        defaults.set(appearance.rawValue, forKey: DockIconAppearance.preferenceKey)
        return true
    }

    func refresh(isDark: Bool? = nil) {
        _ = apply(selection, isDark: isDark ?? systemIsDark)
    }

    private var systemIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func apply(_ appearance: DockIconAppearance, isDark: Bool) -> Bool {
        let resource = appearance.resourceName(isDark: isDark)
        if hasApplied && resource == lastResource { errorMessage = nil; return true }
        var image: NSImage?
        if let resource {
            guard let loaded = images[resource] ?? loadImage(resource) else {
                errorMessage = L10n.text("无法加载图标，请重新打开应用后重试。")
                return false
            }
            images[resource] = loaded
            image = loaded
        }
        // nil restores the original system-managed Icon Composer icon.
        setImage(image)
        lastResource = resource
        hasApplied = true
        errorMessage = nil
        return true
    }
}

@MainActor final class DayDistanceAppDelegate: NSObject, NSApplicationDelegate {
    let dockIcons = DockIconController()
    private var menuObservers: [NSObjectProtocol] = []
    private var menuRefreshScheduled = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        dockIcons.start()
        for name in [L10n.languageDidChange, NSMenu.didBeginTrackingNotification, NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    // Menu tracking uses a nested run loop. Refresh its actual
                    // menu synchronously; a deferred main-queue pass is too late.
                    if let menu = note.object as? NSMenu, NativeMenuLanguage.belongsToMainMenu(menu) {
                        NativeMenuLanguage.refresh(menu)
                    }
                    guard let self, !self.menuRefreshScheduled else { return }
                    self.menuRefreshScheduled = true
                    // SwiftUI rebuilds its commands first. Coalesce menu changes
                    // into one pass, keeping actions and keyboard shortcuts.
                    DispatchQueue.main.async {
                        NativeMenuLanguage.refresh(NSApp.mainMenu)
                        self.menuRefreshScheduled = false
                    }
                }
            })
        }
    }
}

@MainActor enum NativeMenuLanguage {
    private static var isRefreshing = false
    static func belongsToMainMenu(_ menu: NSMenu) -> Bool {
        func contains(_ root: NSMenu) -> Bool {
            root === menu || root.items.contains { $0.submenu.map(contains) ?? false }
        }
        guard let main = NSApp.mainMenu else { return false }
        return contains(main) || (!menu.title.isEmpty && main.items.contains { $0.submenu?.title == menu.title })
    }
    static func refresh(_ menu: NSMenu?) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        update(menu)
    }
    private static func update(_ menu: NSMenu?) {
        guard let menu else { return }
        let chinese = L10n.currentLanguage == .simplifiedChinese
        let groups = [("文件", "File"), ("编辑", "Edit"), ("显示", "View"), ("窗口", "Window"), ("帮助", "Help"), ("服务", "Services")]
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
        let actions: [String: (String, String)] = [
            "orderFrontStandardAboutPanel:": ("关于 \(app)", "About \(app)"),
            "showSettingsWindow:": ("设置…", "Settings…"),
            "hide:": ("隐藏 \(app)", "Hide \(app)"),
            "hideOtherApplications:": ("隐藏其他", "Hide Others"),
            "unhideAllApplications:": ("全部显示", "Show All"),
            "terminate:": ("退出 \(app)", "Quit \(app)"),
            "performClose:": ("关闭", "Close"), "closeAll:": ("全部关闭", "Close All"),
            "cut:": ("剪切", "Cut"), "copy:": ("拷贝", "Copy"), "paste:": ("粘贴", "Paste"),
            "pasteAndMatchStyle:": ("粘贴并匹配样式", "Paste and Match Style"),
            "delete:": ("删除", "Delete"), "selectAll:": ("全选", "Select All"),
            "performMiniaturize:": ("最小化", "Minimize"), "performZoom:": ("缩放", "Zoom"),
            "arrangeInFront:": ("前置全部窗口", "Bring All to Front"),
            "toggleFullScreen:": ("切换全屏幕", "Toggle Full Screen"),
            "toggleSidebar:": ("切换边栏", "Toggle Sidebar")
        ]
        let labels = Array(actions.values) + [("设置…", "Settings…")]
        for item in menu.items {
            if let submenu = item.submenu {
                if let pair = groups.first(where: { item.title == $0.0 || item.title == $0.1 }) {
                    let title = chinese ? pair.0 : pair.1
                    if item.title != title { item.title = title }
                    if submenu.title != title { submenu.title = title }
                }
                update(submenu)
            }
            if let action = item.action, NSStringFromSelector(action) != "makeKeyAndOrderFront:", !(item.representedObject is NSWindow),
               let pair = actions[NSStringFromSelector(action)] ?? labels.first(where: { item.title == $0.0 || item.title == $0.1 }) {
                let title = chinese ? pair.0 : pair.1
                if item.title != title { item.title = title }
            }
        }
    }
}
