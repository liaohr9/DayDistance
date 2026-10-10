import AppKit

@main struct DockIconProbe {
    @MainActor static func main() {
        let suite = "local.daydistance.icon-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        var applied: [NSImage?] = []
        var missing = false
        let controller = DockIconController(defaults: defaults, loadImage: { name in
            missing ? nil : NSImage(contentsOf: resources.appendingPathComponent(name + ".png"))
        }, setImage: { applied.append($0) })
        controller.restore(isDark: false)
        precondition(controller.selection == .system && applied.count == 1 && applied[0] == nil)
        precondition(controller.select(.light, isDark: false))
        let light = applied.last!!.tiffRepresentation!
        precondition(defaults.string(forKey: DockIconAppearance.preferenceKey) == "light")
        precondition(controller.select(.light, isDark: true) && applied.count == 2)
        precondition(controller.select(.dark, isDark: false))
        precondition(applied.last!!.tiffRepresentation! != light)
        precondition(controller.select(.clear, isDark: false))
        let clearLight = applied.last!!.tiffRepresentation!
        controller.refresh(isDark: true)
        precondition(applied.last!!.tiffRepresentation! != clearLight && applied.count == 5)
        controller.refresh(isDark: true)
        precondition(applied.count == 5)
        missing = true
        // A fresh controller has no cached Light; failed selection preserves mode and preference.
        let failed = DockIconController(defaults: defaults, loadImage: { _ in nil }, setImage: { _ in preconditionFailure("Missing image must not reset current icon") })
        precondition(!failed.select(.dark, isDark: false))
        precondition(failed.selection == .system && failed.errorMessage != nil)
        precondition(defaults.string(forKey: DockIconAppearance.preferenceKey) == "clear")
        missing = false
        var restoredName: String?
        let restored = DockIconController(defaults: defaults, loadImage: { name in
            restoredName = name
            return NSImage(contentsOf: resources.appendingPathComponent(name + ".png"))
        }, setImage: { precondition($0 != nil) })
        restored.restore(isDark: true)
        precondition(restored.selection == .clear && restoredName == "ClearDark")
        precondition(controller.select(.system, isDark: true))
        precondition(applied.last! == nil && controller.errorMessage == nil)
        defaults.set("unknown", forKey: DockIconAppearance.preferenceKey)
        controller.restore(isDark: false)
        precondition(controller.selection == .system)
        print("Dock icon checks passed (default, all modes, persistence, appearance refresh, reset, missing asset)")
    }
}
