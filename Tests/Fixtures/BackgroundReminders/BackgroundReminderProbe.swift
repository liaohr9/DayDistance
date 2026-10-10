import Foundation

@MainActor final class FakeBackgroundClient: BackgroundReminderClient {
    var status = BackgroundReminderStatus.off
    var registers = 0
    var unregisters = 0
    var shouldFail = false
    func register() async throws {
        registers += 1
        if shouldFail { throw NSError(domain: "test", code: 1) }
        status = .requiresApproval
    }
    func unregister() async throws { unregisters += 1; status = .off }
    func openSettings() { }
}

@main struct BackgroundReminderProbe {
    @MainActor static func main() async {
        let client = FakeBackgroundClient()
        let suite = "DayDistanceBackgroundTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "23")
        precondition(!controller.isRequested && !controller.isEnabled)
        await controller.setEnabled(true)
        precondition(client.registers == 1 && controller.isRequested && !controller.isEnabled && controller.status == .requiresApproval)
        await controller.setEnabled(false)
        precondition(client.unregisters == 1 && !controller.isRequested)
        client.shouldFail = true
        await controller.setEnabled(true)
        precondition(controller.errorMessage != nil && !controller.isRequested && !controller.isUpdating)
        client.status = .enabled
        controller.refreshStatus()
        precondition(controller.isEnabled)
        client.shouldFail = false
        await controller.setEnabled(false)
        await controller.setEnabled(true)
        precondition(client.registers == 3)
        await controller.refreshAfterUpdate()
        precondition(client.registers == 3)
        let upgraded = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "24")
        await upgraded.refreshAfterUpdate()
        precondition(client.registers == 4 && client.unregisters == 3 && upgraded.isRequested)
        await upgraded.refreshAfterUpdate()
        precondition(client.registers == 4)
        await upgraded.setEnabled(false)
        let disabledUpgrade = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "25")
        await disabledUpgrade.refreshAfterUpdate()
        precondition(client.registers == 4 && !disabledUpgrade.isRequested)
        precondition(BackgroundReminderInvocation.mode(arguments: ["DayDistance", "--refresh-reminders"]) == .refresh)
        precondition(BackgroundReminderInvocation.mode(arguments: ["DayDistance", "/file"]) == .normal)
        precondition(BackgroundReminderInvocation.mode(arguments: ["DayDistance", "--refresh-reminders", "/file"]) == .invalid)
        print("BACKGROUND_REMINDER_PASS: opt-in, approval truth, off, errors, external status, exact invocation")
    }
}
