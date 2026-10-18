import Foundation
import Observation
import Security
import WidgetKit

/// A successful request is not proof that macOS displayed the widget.
enum WidgetMaintenanceOutcome: String, Codable {
    case requested, notInstalled, missingExtension, invalidSignature, failed, timedOut
    var message: String {
        let key = switch self {
        case .requested: "已请求重新登记并刷新。请关闭后重新打开“编辑小组件”，搜索“日距”或“DayDistance”。"
        case .notInstalled: "请先将日距移到“应用程序”，再打开应用进行修复。"
        case .missingExtension: "安装包内的小组件不完整，请重新下载安装包。"
        case .invalidSignature: "小组件签名无法验证，请重新下载应用；不要自行修改或重新签名安装包。"
        case .failed: "系统未能完成登记请求。请重试；若仍失败，请导出诊断报告。"
        case .timedOut: "系统暂未响应登记请求，请稍后重试。"
        }
        return L10n.text(key)
    }
    @MainActor static func persisted(_ defaults: UserDefaults = .standard) -> Self? {
        defaults.string(forKey: WidgetMaintenanceController.outcomeKey).flatMap(Self.init(rawValue:))
    }
}

@MainActor protocol WidgetMaintenanceClient: AnyObject {
    var fingerprint: String { get }
    func requestRepair() async -> WidgetMaintenanceOutcome
    func reloadTimelines()
}

@MainActor @Observable final class WidgetMaintenanceController {
    static let outcomeKey = "widgetMaintenance.lastOutcome"
    private static let attemptKey = "widgetMaintenance.lastInstallation"
    private(set) var outcome: WidgetMaintenanceOutcome?
    private(set) var isWorking = false
    @ObservationIgnored private let client: WidgetMaintenanceClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var prepared = false

    init(client: WidgetMaintenanceClient, defaults: UserDefaults = .standard) {
        self.client = client; self.defaults = defaults
    }
    static func production() -> WidgetMaintenanceController { .init(client: NativeWidgetMaintenanceClient()) }
    func prepareAfterLaunch() async {
        guard !prepared else { return }
        prepared = true
        guard defaults.string(forKey: Self.attemptKey) != client.fingerprint else { return }
        await repair()
    }
    func repair() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        defaults.set(client.fingerprint, forKey: Self.attemptKey)
        let result = await client.requestRepair()
        outcome = result
        defaults.set(result.rawValue, forKey: Self.outcomeKey)
        if result == .requested { client.reloadTimelines() }
    }
}

/// Only the extension in this running application's sealed bundle can be requested.
/// No shell, database reset, election changes, system-process signals or extra entitlements.
@MainActor final class NativeWidgetMaintenanceClient: WidgetMaintenanceClient {
    private let bundle: Bundle
    let fingerprint: String
    init(bundle: Bundle = .main) {
        self.bundle = bundle
        let root = bundle.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let binary = bundle.executableURL ?? root
        let attributes = (try? FileManager.default.attributesOfItem(atPath: binary.path)) ?? [:]
        fingerprint = [root.path, bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                       String(describing: attributes[.systemFileNumber] ?? "unknown"),
                       String(describing: attributes[.modificationDate] ?? "unknown")].joined(separator: "|")
    }
    func requestRepair() async -> WidgetMaintenanceOutcome {
        let root = bundle.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let appDirectories = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        guard root.pathExtension == "app", appDirectories.contains(where: {
            root.path.hasPrefix($0.standardizedFileURL.resolvingSymlinksInPath().path + "/")
        }) else { return .notInstalled }
        guard let identifier = bundle.bundleIdentifier,
              let plugins = bundle.builtInPlugInsURL else { return .missingExtension }
        let extensionURL = plugins.appendingPathComponent("DayDistanceWidget.appex").standardizedFileURL.resolvingSymlinksInPath()
        guard extensionURL.path.hasPrefix(root.path + "/Contents/PlugIns/"),
              let widget = Bundle(url: extensionURL), widget.bundleIdentifier == identifier + ".widget",
              let configuration = widget.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
              configuration["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension",
              widget.object(forInfoDictionaryKey: "CFBundleVersion") as? String == bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else { return .missingExtension }
        return await Task.detached(priority: .utility) {
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(extensionURL as CFURL, [], &code) == errSecSuccess,
                  let code, SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
            else { return .invalidSignature }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            process.arguments = ["-a", extensionURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return .failed }
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while process.isRunning && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
            guard !process.isRunning else { process.terminate(); return .timedOut }
            return process.terminationStatus == 0 ? .requested : .failed
        }.value
    }
    func reloadTimelines() { WidgetCenter.shared.reloadTimelines(ofKind: "DayDistanceWidget") }
}
