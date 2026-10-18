import Foundation
import Observation

@MainActor protocol AppUpdateClient: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    var stateChanged: (() -> Void)? { get set }
    var mayInterrupt: () -> Bool { get set }
    func start() throws
    func checkForUpdates()
}

/// Sparkle owns scheduling, preferences, signature verification and installation.
/// This adapter only protects the application's editing and file-operation state.
@MainActor @Observable final class UpdateController {
    private(set) var errorMessage: String?
    private(set) var isWaitingToInstall = false
    private(set) var revision = 0
    @ObservationIgnored private let client: AppUpdateClient
    @ObservationIgnored private var started = false
    @ObservationIgnored private var installation: (() -> Void)?
    @ObservationIgnored private var resumeTimer: Timer?
    init(client: AppUpdateClient) {
        self.client = client
        client.stateChanged = { [weak self] in self?.revision += 1 }
    }
    static func production() -> UpdateController {
        #if canImport(Sparkle)
        let client = SparkleUpdateClient()
        let controller = UpdateController(client: client)
        client.postponeInstallation = { [weak controller] action in controller?.postponeInstallation(action) ?? true }
        return controller
        #else
        // Command-line model/UI probes deliberately do not embed the updater.
        return UpdateController(client: UnavailableUpdateClient())
        #endif
    }
    func start(mayInterrupt: @escaping () -> Bool) {
        guard !started else { return }
        started = true; client.mayInterrupt = mayInterrupt
        do { try client.start() }
        catch { errorMessage = L10n.text("更新服务暂不可用，请稍后重试。") }
        revision += 1
    }
    var automaticChecksEnabled: Bool {
        get { _ = revision; return client.automaticallyChecksForUpdates }
        set { client.automaticallyChecksForUpdates = newValue; revision += 1 }
    }
    var canCheck: Bool { _ = revision; return started && errorMessage == nil && client.canCheckForUpdates && client.mayInterrupt() }
    var lastChecked: Date? { _ = revision; return client.lastUpdateCheckDate }
    func checkForUpdates() { guard canCheck else { return }; client.checkForUpdates() }
    func postponeInstallation(_ action: @escaping () -> Void) -> Bool {
        guard !client.mayInterrupt() else { return false }
        installation = action; isWaitingToInstall = true
        resumeTimer?.invalidate()
        resumeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.resumeWhenSafe() }
        }
        return true
    }
    func resumeWhenSafe() {
        guard client.mayInterrupt(), let action = installation else { return }
        installation = nil; resumeTimer?.invalidate(); resumeTimer = nil
        isWaitingToInstall = false; action()
    }
}

#if !canImport(Sparkle)
@MainActor private final class UnavailableUpdateClient: AppUpdateClient {
    var automaticallyChecksForUpdates = false
    var canCheckForUpdates: Bool { false }
    var lastUpdateCheckDate: Date? { nil }
    var stateChanged: (() -> Void)?
    var mayInterrupt: () -> Bool = { false }
    func start() throws { }
    func checkForUpdates() { }
}
#endif
