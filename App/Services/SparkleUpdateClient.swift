#if canImport(Sparkle)
import AppKit
import Sparkle

@MainActor final class SparkleUpdateClient: NSObject, AppUpdateClient, SPUUpdaterDelegate {
    var stateChanged: (() -> Void)?
    var mayInterrupt: () -> Bool = { false }
    var postponeInstallation: ((@escaping () -> Void) -> Bool)?
    private var observations: [NSKeyValueObservation] = []
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }
    func start() throws {
        let updater = controller.updater
        observations = [updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.stateChanged?() }
        }, updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.stateChanged?() }
        }]
        try updater.start()
    }
    func checkForUpdates() { controller.checkForUpdates(nil) }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard mayInterrupt() else {
            throw NSError(domain: "local.daydistance.updates", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("请先完成当前编辑或文件操作。")])
        }
    }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard mayInterrupt() else {
            throw NSError(domain: "local.daydistance.updates", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("请先完成当前编辑或文件操作。")])
        }
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeInstallation?(installHandler) ?? true
    }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
}
#endif
