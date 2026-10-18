import Foundation

@MainActor final class MaintenanceClient: WidgetMaintenanceClient {
    var fingerprint = "installation-1"
    var calls = 0
    var reloads = 0
    var result = WidgetMaintenanceOutcome.requested
    var pause: CheckedContinuation<Void, Never>?
    var delayed = false
    func requestRepair() async -> WidgetMaintenanceOutcome {
        calls += 1
        if delayed { await withCheckedContinuation { pause = $0 } }
        return result
    }
    func reloadTimelines() { reloads += 1 }
}
@main struct WidgetMaintenanceProbe {
    @MainActor static func main() async {
        let suite = "local.daydistance.maintenance-probe." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = MaintenanceClient()
        let controller = WidgetMaintenanceController(client: client, defaults: defaults)
        await controller.prepareAfterLaunch()
        require(client.calls == 1 && client.reloads == 1, "first launch registers own widget and requests timeline reload")
        await controller.prepareAfterLaunch()
        let second = WidgetMaintenanceController(client: client, defaults: defaults)
        await second.prepareAfterLaunch()
        require(client.calls == 1, "same installation is not registered on every view or relaunch")
        client.fingerprint = "replacement-with-same-version"
        let replacement = WidgetMaintenanceController(client: client, defaults: defaults)
        await replacement.prepareAfterLaunch()
        require(client.calls == 2, "changed installation retries even with identical version")
        await replacement.repair()
        require(client.calls == 3, "manual repair always retries")
        client.result = .failed
        await replacement.repair()
        require(replacement.outcome == .failed && client.reloads == 3, "failed registration is not reported or refreshed as success")
        let failed = WidgetMaintenanceController(client: client, defaults: defaults)
        await failed.prepareAfterLaunch()
        require(client.calls == 4, "failed attempt does not loop every launch")
        client.result = .requested; client.delayed = true
        let work = Task { await replacement.repair() }
        while client.pause == nil { await Task.yield() }
        require(replacement.isWorking, "busy state is visible")
        let before = client.calls
        await replacement.repair()
        require(client.calls == before, "repeated click coalesces while busy")
        client.pause?.resume(); client.pause = nil
        await work.value
        require(!replacement.isWorking && replacement.outcome == .requested, "busy state finishes without declaring desktop success")
        require(WidgetMaintenanceOutcome.persisted(defaults) == .requested, "only safe outcome enum is persisted")
        defaults.set("private event title /Users/private", forKey: WidgetMaintenanceController.outcomeKey)
        require(WidgetMaintenanceOutcome.persisted(defaults) == nil, "unknown preference bytes are excluded from diagnostics")
        print("WIDGET_MAINTENANCE_PASS: install/replacement/manual/busy/failure/reload/privacy")
    }
    static func require(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
}
