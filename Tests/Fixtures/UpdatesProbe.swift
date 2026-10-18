import Foundation
@MainActor final class ProbeUpdateClient: AppUpdateClient {
    var automaticallyChecksForUpdates = true
    var canCheckForUpdates = true
    var lastUpdateCheckDate: Date?
    var stateChanged: (() -> Void)?
    var mayInterrupt: () -> Bool = { true }
    var starts = 0, checks = 0
    func start() throws { starts += 1 }
    func checkForUpdates() { checks += 1 }
}
@MainActor @main enum UpdatesProbe {
    static func main() throws {
        let client = ProbeUpdateClient()
        let controller = UpdateController(client: client)
        var editing = true
        controller.start { !editing }
        controller.start { !editing }
        precondition(client.starts == 1)
        precondition(!client.mayInterrupt())
        controller.checkForUpdates(); precondition(client.checks == 0, "Don't interrupt a draft")
        editing = false
        controller.checkForUpdates(); precondition(client.checks == 1)
        controller.automaticChecksEnabled = false
        precondition(!client.automaticallyChecksForUpdates)
        controller.checkForUpdates(); precondition(client.checks == 2, "Manual works while automatic checks are off")
        client.canCheckForUpdates = false; client.stateChanged?()
        controller.checkForUpdates(); precondition(client.checks == 2)
        client.canCheckForUpdates = true; client.stateChanged?()
        var installed = false
        editing = true
        precondition(controller.postponeInstallation { installed = true })
        controller.resumeWhenSafe(); precondition(!installed)
        editing = false; controller.resumeWhenSafe(); precondition(installed)
        installed = false; controller.resumeWhenSafe(); precondition(!installed, "Resume once")
        precondition(!controller.postponeInstallation { installed = true }, "No postponement when safe")
        print("UPDATES_PASS: single start, editing guard, shared setting, manual checks, in-flight guard, deferred installation")
    }
}
