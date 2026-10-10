import Foundation

@MainActor final class FakeBackgroundClient: BackgroundReminderClient {
    var status = BackgroundReminderStatus.off
    var registers = 0
    var unregisters = 0
    var shouldFail = false
    var shouldFailUnregister = false
    var confirmations: [Bool] = []
    var confirmationChecks = 0
    func confirmExecution(since: Date) async throws -> Bool {
        confirmationChecks += 1
        return confirmations.isEmpty ? true : confirmations.removeFirst()
    }
    var registrationStatus = BackgroundReminderStatus.requiresApproval
    func register() async throws {
        registers += 1
        if shouldFail { throw NSError(domain: "test", code: 1) }
        status = registrationStatus
    }
    func unregister() async throws {
        unregisters += 1
        if shouldFailUnregister { throw NSError(domain: "test-unregister", code: 2) }
        status = .off
    }
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
        client.status = .enabled
        let upgraded = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "24")
        await upgraded.refreshAfterUpdate()
        precondition(client.registers == 4 && client.unregisters == 3 && upgraded.isRequested)
        await upgraded.refreshAfterUpdate()
        precondition(client.registers == 4)
        await upgraded.setEnabled(false)
        let disabledUpgrade = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "25")
        await disabledUpgrade.refreshAfterUpdate()
        precondition(client.registers == 4 && !disabledUpgrade.isRequested)
        client.status = .enabled
        client.registrationStatus = .enabled
        defaults.set("25", forKey: "backgroundReminderRegisteredBuild")
        let sameBuild = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "25")
        let registrationsBeforeReplacement = client.registers
        await sameBuild.refreshAfterUpdate()
        precondition(sameBuild.canRenewReminders)
        precondition(client.registers == registrationsBeforeReplacement + 1, "Same-version cold launch must rebuild an enabled registration")
        await sameBuild.refreshAfterUpdate()
        precondition(client.registers == registrationsBeforeReplacement + 1, "Rebuild only once per cold launch")

        client.confirmations = [false, true]
        let staleRegistration = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "25")
        let registrationsBeforeStale = client.registers
        await staleRegistration.refreshAfterUpdate()
        precondition(client.registers == registrationsBeforeStale + 2, "Retry a registration that never executed")
        precondition(staleRegistration.canRenewReminders)
        client.confirmations = [false, false]
        let neverStarted = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "25")
        await neverStarted.refreshAfterUpdate()
        precondition(neverStarted.errorMessage != nil && !neverStarted.canRenewReminders, "Enabled without execution is not healthy")
        client.confirmations = []
        let retryExecution = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "25")
        await retryExecution.refreshAfterUpdate()
        precondition(retryExecution.canRenewReminders)

        client.shouldFail = true
        let failedRepair = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "26")
        await failedRepair.refreshAfterUpdate()
        precondition(failedRepair.errorMessage != nil && !failedRepair.canRenewReminders)
        client.shouldFail = false
        let retryRepair = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "26")
        await retryRepair.refreshAfterUpdate()
        precondition(retryRepair.isEnabled && retryRepair.errorMessage == nil, "Failed authorized repair must survive a cold launch")
        client.shouldFailUnregister = true
        let unregisterFailure = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "26")
        await unregisterFailure.refreshAfterUpdate()
        precondition(unregisterFailure.errorMessage != nil && !unregisterFailure.canRenewReminders)
        client.shouldFailUnregister = false
        let retryUnregister = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "26")
        await retryUnregister.refreshAfterUpdate()
        precondition(retryUnregister.canRenewReminders)
        await retryRepair.setEnabled(false)
        let registrationsBeforeOff = client.registers
        let remainsOff = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "27")
        await remainsOff.refreshAfterUpdate()
        precondition(!remainsOff.isRequested && client.registers == registrationsBeforeOff, "Explicit off cancels any repair")

        client.status = .enabled
        client.shouldFail = true
        let interruptedOptOut = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "27")
        await interruptedOptOut.refreshAfterUpdate()
        precondition(client.status == .off && defaults.bool(forKey: "backgroundReminderRepairPending"))
        await interruptedOptOut.setEnabled(false)
        precondition(!defaults.bool(forKey: "backgroundReminderRepairPending"), "Explicit off must clear interrupted recovery")
        client.shouldFail = false
        let optedOutRetry = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "27")
        let registrationsAfterOptOut = client.registers
        await optedOutRetry.refreshAfterUpdate()
        precondition(client.registers == registrationsAfterOptOut && !optedOutRetry.isRequested)

        defaults.set(true, forKey: "backgroundReminderRepairPending")
        client.status = .requiresApproval
        let waiting = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "28")
        await waiting.refreshAfterUpdate()
        precondition(!waiting.isEnabled && client.status == .requiresApproval && client.registers == registrationsAfterOptOut, "Do not re-register while awaiting system approval")
        defaults.removeObject(forKey: "backgroundReminderRepairPending")
        client.status = .unavailable
        let unavailable = BackgroundReminderController(client: client, defaults: defaults, buildVersion: "28")
        await unavailable.refreshAfterUpdate()
        precondition(!unavailable.isRequested && client.registers == registrationsAfterOptOut)

        precondition(BackgroundReminderInvocation.mode(arguments: ["DayDistance", "--refresh-reminders"]) == .refresh)
        precondition(BackgroundReminderInvocation.mode(arguments: ["DayDistance", "/file"]) == .normal)
        precondition(BackgroundReminderInvocation.mode(arguments: ["DayDistance", "--refresh-reminders", "/file"]) == .invalid)
        print("BACKGROUND_REMINDER_PASS: opt-in, approval truth, off, errors, external status, exact invocation")
    }
}
