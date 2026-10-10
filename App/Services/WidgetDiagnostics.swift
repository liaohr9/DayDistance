import AppKit
import Foundation
import UserNotifications

/// A small allowlist of status fields. Never add an event, URL, or localized error here.
struct DiagnosticReport: Encodable, Equatable {
    enum DataSourceState: String, Codable { case readable, notCreated, unreadable }
    let reportVersion = 1
    let applicationVersion: String
    let buildVersion: String
    let storageMode: String
    let systemVersion: String
    let eventCount: Int?
    let dataSourceState: DataSourceState
    let errorCategory: String?
    let notificationAuthorization: String
    let widgetExtensionEmbedded: Bool
    let reduceMotion: Bool
    let increaseContrast: Bool
    let reduceTransparency: Bool

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct DiagnosticMetadata {
    let applicationVersion: String
    let buildVersion: String
    let storageMode: String
    let systemVersion: String
    let widgetExtensionEmbedded: Bool
    let reduceMotion: Bool
    let increaseContrast: Bool
    let reduceTransparency: Bool

    @MainActor static func current(bundle: Bundle = .main) -> Self {
        let extensions = bundle.builtInPlugInsURL.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
        } ?? []
        let hasWidget = extensions.contains { url in
            guard url.pathExtension == "appex", let extensionBundle = Bundle(url: url),
                  let configuration = extensionBundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any] else { return false }
            return configuration["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
        }
        return Self(applicationVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                    storageMode: SharedContainer.isLocalDevelopment ? "local" : "appGroup",
                    systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                    widgetExtensionEmbedded: hasWidget,
                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                    reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }
}

/// Uses the same reader as the widget; no migration, save, permission request, or network operation.
@MainActor
struct WidgetDiagnostics {
    private let repository: () throws -> EventRepository
    private let notificationAuthorization: () async -> String
    private let metadata: DiagnosticMetadata

    init(repository: @escaping () throws -> EventRepository = { try SharedContainer.repository() },
         notificationAuthorization: @escaping () async -> String = { await Self.currentAuthorization() },
         metadata: DiagnosticMetadata? = nil) {
        self.repository = repository
        self.notificationAuthorization = notificationAuthorization
        self.metadata = metadata ?? .current()
    }

    func check() async -> DiagnosticReport {
        let count: Int?
        let state: DiagnosticReport.DataSourceState
        let category: String?
        do {
            let source = try repository()
            count = try source.load().count
            state = FileManager.default.fileExists(atPath: source.fileURL.path) ? .readable : .notCreated
            category = nil
        } catch {
            count = nil
            state = .unreadable
            category = Self.errorCategory(error)
        }
        return DiagnosticReport(applicationVersion: metadata.applicationVersion, buildVersion: metadata.buildVersion,
                                storageMode: metadata.storageMode, systemVersion: metadata.systemVersion,
                                eventCount: count, dataSourceState: state, errorCategory: category,
                                notificationAuthorization: await notificationAuthorization(),
                                widgetExtensionEmbedded: metadata.widgetExtensionEmbedded,
                                reduceMotion: metadata.reduceMotion, increaseContrast: metadata.increaseContrast,
                                reduceTransparency: metadata.reduceTransparency)
    }

    /// Save only after the user chooses a destination. Protect event files and their lock sidecars.
    func export(_ report: DiagnosticReport, to destination: URL) throws {
        var protected = SharedContainer.protectedDataURLs()
        if let source = try? repository() { protected.append(source.fileURL) }
        let allProtected = protected + protected.flatMap { [$0.appendingPathExtension("lock"), $0.appendingPathExtension("reminders.lock")] }
        let resolved = destination.standardizedFileURL.resolvingSymlinksInPath()
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        for url in allProtected {
            let target = url.standardizedFileURL.resolvingSymlinksInPath()
            let targetAttributes = try? FileManager.default.attributesOfItem(atPath: target.path)
            let sameFile = attributes?[.systemFileNumber] as? NSNumber != nil
                && attributes?[.systemFileNumber] as? NSNumber == targetAttributes?[.systemFileNumber] as? NSNumber
                && attributes?[.systemNumber] as? NSNumber == targetAttributes?[.systemNumber] as? NSNumber
            guard resolved != target, !sameFile else { throw EventError.protectedExportDestination }
        }
        try report.jsonData().write(to: destination, options: .atomic)
    }

    private static func currentAuthorization() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    private static func errorCategory(_ error: Error) -> String {
        if let eventError = error as? EventError {
            switch eventError {
            case .unavailableContainer: return "unavailableContainer"
            case .unsupportedVersion: return "unsupportedVersion"
            case .duplicateID, .blankTitle, .invalidDate: return "invalidData"
            case .busyData: return "busy"
            default: return "storageError"
            }
        }
        if error is DecodingError { return "invalidData" }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(nsError.code) { return "permissionDenied" }
        return "storageError"
    }
}
