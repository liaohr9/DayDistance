import Foundation
import Darwin

struct EventRepository: Sendable {
    let fileURL: URL
    private struct Envelope: Codable {
        let schemaVersion: Int
        let events: [CountdownEvent]
        var automationReceipts: [String: AutomationReceipt]? = nil
    }
    private struct Schema: Decodable { let schemaVersion: Int }

    // Export the latest validated disk snapshot, not a possibly stale window list.
    func exportSnapshot() throws -> Data { try Self.encodeSnapshot(load()) }
    func exportSnapshot(to destination: URL, protecting protectedURLs: [URL] = []) throws {
        let dataFiles = [fileURL] + protectedURLs
        let protected = dataFiles + ExportDestinationPolicy.smartListFiles(beside: dataFiles)
        let directories = ExportDestinationPolicy.smartListBackupDirectories(beside: dataFiles)
        try ExportDestinationPolicy.validate(destination, protectedFiles: protected, protectedDirectories: directories)
        try withWriteLock {
            // Read after the save panel closes, and coordinate with our writers.
            try ExportDestinationPolicy.validate(destination, protectedFiles: protected, protectedDirectories: directories)
            try exportSnapshot().write(to: destination, options: .atomic)
        }
    }
    func importSnapshot(_ data: Data, replacing expected: [CountdownEvent]) throws -> [CountdownEvent] {
        let incoming = try Self.decodeSnapshot(data)
        return try withWriteLock {
            let current = try load()
            guard current == expected else { throw EventError.changedData }
            let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            for event in incoming {
                if let existing = byID[event.id], existing != event { throw EventError.importConflict }
            }
            let merged = current + incoming.filter { byID[$0.id] == nil }
            if merged != current { try write(merged) }
            return merged
        }
    }

    // Main-app-only migration. The extension only loads the destination.
    // Existing destination (including an intentionally empty list) always wins.
    func loadMigrating(from legacy: EventRepository) throws -> [CountdownEvent] {
        try withWriteLock {
            if FileManager.default.fileExists(atPath: fileURL.path) { return try load() }
            let events = try legacy.load()
            try write(events)
            return events
        }
    }
    func load() throws -> [CountdownEvent] {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch CocoaError.fileReadNoSuchFile { return [] }
        return try Self.decodeSnapshot(data)
    }
    static func decodeSnapshot(_ data: Data) throws -> [CountdownEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        // Reject future envelopes before interpreting their event fields.
        let schema = try decoder.decode(Schema.self, from: data)
        guard (1...8).contains(schema.schemaVersion) else { throw EventError.unsupportedVersion }
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard Set(envelope.events.map(\.id)).count == envelope.events.count else { throw EventError.duplicateID }
        for event in envelope.events { _ = try event.validated(now: event.updatedAt) }
        return envelope.events
    }
    func save(_ events: [CountdownEvent], replacing expected: [CountdownEvent], automationReceipt: (String, AutomationReceipt)? = nil) throws {
        try withWriteLock {
            // Validation and replacement share a lock across application processes.
            guard try load() == expected else { throw EventError.changedData }
            try write(events, automationReceipt: automationReceipt)
        }
    }
    func automationReceipt(for key: String) throws -> AutomationReceipt? { try receipts()[key] }
    private func receipts() throws -> [String: AutomationReceipt] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        _ = try Self.decodeSnapshot(data)
        return try JSONDecoder().decode(Envelope.self, from: data).automationReceipts ?? [:]
    }
    private func withWriteLock<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Never remove this sidecar: atomic replacement changes the JSON inode.
        let descriptor = Darwin.open(fileURL.path + ".lock", O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            if code == EWOULDBLOCK { throw EventError.busyData }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return try action()
    }
    private func write(_ events: [CountdownEvent], automationReceipt: (String, AutomationReceipt)? = nil) throws {
        var savedReceipts = try receipts()
        if let (key, receipt) = automationReceipt {
            guard savedReceipts[key] == nil || savedReceipts[key] == receipt else { throw EventError.changedData }
            guard savedReceipts[key] != nil || savedReceipts.count < 4096 else { throw AutomationFailure("LIMIT_REACHED", "Automation receipt storage is full; no event was created.") }
            savedReceipts[key] = receipt
        }
        let snapshot = try Self.encodeSnapshot(events)
        var envelope = try JSONDecoder().decode(Envelope.self, from: snapshot)
        envelope.automationReceipts = savedReceipts.isEmpty ? nil : savedReceipts
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(envelope).write(to: fileURL, options: .atomic)
    }
    static func encodeSnapshot(_ events: [CountdownEvent]) throws -> Data {
        guard Set(events.map(\.id)).count == events.count else { throw EventError.duplicateID }
        for event in events { _ = try event.validated(now: event.updatedAt) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(schemaVersion: 8, events: events))
    }
}
