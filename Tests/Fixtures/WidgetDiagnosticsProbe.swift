import Foundation

@main
struct WidgetDiagnosticsProbe {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayDistanceDiagnostics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("events.json")
        let repository = EventRepository(fileURL: source)
        let event = CountdownEvent(title: "DO_NOT_EXPORT_PRIVATE_TITLE", targetDate: Date(timeIntervalSince1970: 1234567890))
        try repository.save([event], replacing: [])
        try FileManager.default.removeItem(atPath: source.path + ".lock")
        let original = try Data(contentsOf: source)
        let metadata = DiagnosticMetadata(applicationVersion: "1.6", buildVersion: "42", storageMode: "local", systemVersion: "test-system", widgetExtensionEmbedded: true, reduceMotion: false, increaseContrast: false, reduceTransparency: false)
        let service = WidgetDiagnostics(repository: { repository }, notificationAuthorization: { "denied" }, metadata: metadata)
        let report = await service.check()
        require(report.eventCount == 1 && report.dataSourceState == .readable, "reads current validated event count")
        require(report.notificationAuthorization == "denied", "reports injected authorization without requesting permission")
        require(try Data(contentsOf: source) == original, "diagnostics preserve source bytes")
        require(!FileManager.default.fileExists(atPath: source.path + ".lock"), "diagnostics create no write lock")
        let exported = try report.jsonData()
        let text = String(decoding: exported, as: UTF8.self)
        for forbidden in [event.title, event.id.uuidString, source.path, "targetDate", "createdAt", "updatedAt"] {
            require(!text.contains(forbidden), "export excludes event content and full user paths")
        }
        let object = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        require(Set(object.keys) == Set(["reportVersion", "applicationVersion", "buildVersion", "storageMode", "systemVersion", "eventCount", "dataSourceState", "notificationAuthorization", "widgetExtensionEmbedded", "reduceMotion", "increaseContrast", "reduceTransparency"]), "export has explicit non-content field allowlist")
        let output = directory.appendingPathComponent("diagnostics.json")
        try service.export(report, to: output)
        require(try Data(contentsOf: output) == exported, "writes only diagnostic report")
        let reminderLock = source.appendingPathExtension("reminders.lock")
        try Data("stable lock".utf8).write(to: reminderLock)
        let reminderAlias = directory.appendingPathComponent("reminder-lock-alias.json")
        try FileManager.default.linkItem(at: reminderLock, to: reminderAlias)
        for protected in [source, URL(fileURLWithPath: source.path + ".lock"), reminderLock, reminderAlias] {
            do { try service.export(report, to: protected); fatalError("protected destination was accepted") }
            catch EventError.protectedExportDestination { }
        }
        let symlink = directory.appendingPathComponent("source-link.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        do { try service.export(report, to: symlink); fatalError("symlink destination was accepted") }
        catch EventError.protectedExportDestination { }
        let hardlink = directory.appendingPathComponent("source-hardlink.json")
        try FileManager.default.linkItem(at: source, to: hardlink)
        do { try service.export(report, to: hardlink); fatalError("hardlink destination was accepted") }
        catch EventError.protectedExportDestination { }
        require(try Data(contentsOf: source) == original, "export protection preserves source bytes")
        try Data("private broken payload at /Users/private/events.json".utf8).write(to: source)
        let broken = await service.check()
        require(broken.eventCount == nil && broken.dataSourceState == .unreadable && broken.errorCategory == "invalidData", "corrupt source produces general error category")
        require(!String(decoding: try broken.jsonData(), as: UTF8.self).contains("/Users/"), "error export contains no private path")
        try Data("{\"schemaVersion\":999,\"events\":[]}".utf8).write(to: source)
        let newer = await service.check()
        require(newer.errorCategory == "unsupportedVersion", "unsupported schema is identified")
        let missingSource = directory.appendingPathComponent("absent/events.json")
        let missing = WidgetDiagnostics(repository: { EventRepository(fileURL: missingSource) }, notificationAuthorization: { "notDetermined" }, metadata: metadata)
        let missingReport = await missing.check()
        require(missingReport.eventCount == 0 && missingReport.dataSourceState == .notCreated, "absent source is honestly identified")
        require(!FileManager.default.fileExists(atPath: missingSource.deletingLastPathComponent().path), "missing-source check creates no directory")
        let unavailable = WidgetDiagnostics(repository: { throw EventError.unavailableContainer }, notificationAuthorization: { "notDetermined" }, metadata: metadata)
        let unavailableReport = await unavailable.check()
        require(unavailableReport.errorCategory == "unavailableContainer", "unavailable container reports safe category")
        print("PASS: diagnostic count, read-only behavior, report field allowlist, source/lock/symlink/hardlink protection, corrupt/newer/missing/unavailable storage")
    }

    static func require(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
}
