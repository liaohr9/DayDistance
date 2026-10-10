import Foundation
import Observation
import ServiceManagement

enum BackgroundReminderStatus: Equatable { case off, enabled, requiresApproval, unavailable }
enum BackgroundReminderInvocation {
    enum Mode: Equatable { case normal, refresh, invalid }
    static func mode(arguments: [String]) -> Mode {
        guard arguments.contains("--refresh-reminders") else { return .normal }
        return arguments.count == 2 && arguments[1] == "--refresh-reminders" ? .refresh : .invalid
    }
}

@MainActor protocol BackgroundReminderClient {
    var status: BackgroundReminderStatus { get }
    func register() async throws
    func unregister() async throws
    func confirmExecution(since: Date) async throws -> Bool
    func openSettings()
}

@MainActor private final class SystemBackgroundReminderClient: BackgroundReminderClient {
    private let service = SMAppService.agent(plistName: "local.daydistance.mac.reminders.plist")
    var status: BackgroundReminderStatus {
        switch service.status {
        case .notRegistered: return .off
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func register() async throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
    func confirmExecution(since: Date) async throws -> Bool {
        // BTM can invalidate the previous app record asynchronously after replacement.
        // RunAtLoad must produce a new receipt, not merely report SMAppService.enabled.
        let deadline = Date().addingTimeInterval(35)
        repeat {
            UserDefaults.standard.synchronize()
            if let execution = UserDefaults.standard.object(forKey: BackgroundReminderController.executionKey) as? Date,
               execution >= since { return true }
            try await Task.sleep(for: .milliseconds(500))
        } while Date() < deadline
        return false
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@Observable @MainActor final class BackgroundReminderController {
    private(set) var status: BackgroundReminderStatus = .off
    private(set) var isUpdating = false
    private(set) var errorMessage: String?
    private var hasConfirmedExecution = false
    static let executionKey = "backgroundReminderLastExecution"
    static func recordExecution() {
        UserDefaults.standard.set(Date(), forKey: executionKey)
        UserDefaults.standard.synchronize()
    }
    @ObservationIgnored private let client: any BackgroundReminderClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let buildVersion: String
    @ObservationIgnored private var refreshedThisLaunch = false
    private static let registeredBuildKey = "backgroundReminderRegisteredBuild"
    private static let repairPendingKey = "backgroundReminderRepairPending"
    init(client: (any BackgroundReminderClient)? = nil, defaults: UserDefaults = .standard,
         buildVersion: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "development") {
        self.defaults = defaults
        self.buildVersion = buildVersion
        self.client = client ?? SystemBackgroundReminderClient()
        refreshStatus()
    }
    var isRequested: Bool { status == .enabled || status == .requiresApproval }
    var isEnabled: Bool { status == .enabled }
    var canRenewReminders: Bool { isEnabled && hasConfirmedExecution && !isUpdating && errorMessage == nil }
    var statusDescription: String {
        if isUpdating { return L10n.text("正在验证后台刷新…") }
        switch status {
        case .off: return L10n.text("未启用后台刷新")
        case .enabled: return L10n.text("已允许后台刷新")
        case .requiresApproval: return L10n.text("请在系统设置中允许日距在后台运行。")
        case .unavailable: return L10n.text("后台刷新不可用，请检查应用安装与签名。")
        }
    }
    func refreshStatus() { status = client.status }
    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false; refreshStatus() }
        do {
            if enabled {
                if !isRequested { try await registerAndConfirm() }
                if client.status == .enabled || client.status == .requiresApproval {
                    defaults.set(buildVersion, forKey: Self.registeredBuildKey)
                    defaults.removeObject(forKey: Self.repairPendingKey)
                }
            } else {
                // Explicit opt-out must cancel recovery even after a failed register.
                if isRequested { try await client.unregister() }
                hasConfirmedExecution = false
                defaults.removeObject(forKey: Self.registeredBuildKey)
                defaults.removeObject(forKey: Self.repairPendingKey)
            }
            refreshedThisLaunch = true
            errorMessage = nil
        } catch { errorMessage = L10n.format("无法更改后台刷新：%@", error.localizedDescription) }
    }
    // Replacing an app can invalidate its BTM identifier without changing its build
    // number. Rebuild an enabled registration once per cold launch, not just upgrades.
    // A persisted repair flag allows an interrupted unregister/register to recover.
    // Never opt in an untouched, disabled, or approval-pending service.
    func refreshAfterUpdate() async {
        refreshStatus()
        guard !refreshedThisLaunch, !isUpdating else { return }
        refreshedThisLaunch = true
        let pendingRepair = defaults.bool(forKey: Self.repairPendingKey)
        guard status == .enabled || (pendingRepair && status != .requiresApproval) else { return }
        isUpdating = true
        defer { isUpdating = false; refreshStatus() }
        do {
            defaults.set(true, forKey: Self.repairPendingKey)
            if isRequested { try await client.unregister() }
            try await registerAndConfirm()
            if client.status == .enabled || client.status == .requiresApproval {
                defaults.set(buildVersion, forKey: Self.registeredBuildKey)
                defaults.removeObject(forKey: Self.repairPendingKey)
            }
            errorMessage = nil
        } catch {
            errorMessage = L10n.format("无法更改后台刷新：%@", error.localizedDescription)
        }
    }
    private func registerAndConfirm() async throws {
        hasConfirmedExecution = false
        for attempt in 0..<2 {
            let started = Date()
            try await client.register()
            if client.status == .requiresApproval { return }
            if client.status == .enabled, try await client.confirmExecution(since: started) {
                hasConfirmedExecution = true
                return
            }
            if attempt == 0 { try await client.unregister() }
        }
        throw NSError(domain: "DayDistance.BackgroundReminder", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: L10n.text("后台任务未能启动，请重新打开应用重试。")])
    }
    func openSettings() { client.openSettings() }
}
