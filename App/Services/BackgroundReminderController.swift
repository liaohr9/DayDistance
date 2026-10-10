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
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@Observable @MainActor final class BackgroundReminderController {
    private(set) var status: BackgroundReminderStatus = .off
    private(set) var isUpdating = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let client: any BackgroundReminderClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let buildVersion: String
    private static let registeredBuildKey = "backgroundReminderRegisteredBuild"
    init(client: (any BackgroundReminderClient)? = nil, defaults: UserDefaults = .standard,
         buildVersion: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "development") {
        self.defaults = defaults
        self.buildVersion = buildVersion
        self.client = client ?? SystemBackgroundReminderClient()
        refreshStatus()
    }
    var isRequested: Bool { status == .enabled || status == .requiresApproval }
    var isEnabled: Bool { status == .enabled }
    var statusDescription: String {
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
                if !isRequested { try await client.register() }
                if client.status == .enabled || client.status == .requiresApproval {
                    defaults.set(buildVersion, forKey: Self.registeredBuildKey)
                }
            } else if isRequested {
                try await client.unregister()
                defaults.removeObject(forKey: Self.registeredBuildKey)
            }
            errorMessage = nil
        } catch { errorMessage = L10n.format("无法更改后台刷新：%@", error.localizedDescription) }
    }
    // SMAppService requires registration to be renewed when the executable changes.
    // Only renew a service the user already requested; never opt in during launch.
    func refreshAfterUpdate() async {
        refreshStatus()
        guard isRequested, !isUpdating,
              defaults.string(forKey: Self.registeredBuildKey) != buildVersion else { return }
        isUpdating = true
        defer { isUpdating = false; refreshStatus() }
        do {
            try await client.unregister()
            try await client.register()
            if client.status == .enabled || client.status == .requiresApproval {
                defaults.set(buildVersion, forKey: Self.registeredBuildKey)
            }
            errorMessage = nil
        } catch {
            errorMessage = L10n.format("无法更改后台刷新：%@", error.localizedDescription)
        }
    }
    func openSettings() { client.openSettings() }
}
