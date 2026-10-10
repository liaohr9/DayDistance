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
    func applicationDidFinishLaunching(_ notification: Notification) { dockIcons.start() }
}
