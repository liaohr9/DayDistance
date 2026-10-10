import Foundation
import Darwin

struct EventRepository: Sendable {
    let fileURL: URL
    private struct Envelope: Codable {
        let schemaVersion: Int
        let events: [CountdownEvent]
    }
    private struct Schema: Decodable { let schemaVersion: Int }

    // Export the latest validated disk snapshot, not a possibly stale window list.
    func exportSnapshot() throws -> Data { try Self.encodeSnapshot(load()) }
    func exportSnapshot(to destination: URL, protecting protectedURLs: [URL] = []) throws {
        let dataFiles = [fileURL] + protectedURLs
        let protected = dataFiles + dataFiles.flatMap { [$0.appendingPathExtension("lock"), $0.appendingPathExtension("reminders.lock")] }
        let resolved = destination.standardizedFileURL.resolvingSymlinksInPath()
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        for url in protected {
            let target = url.standardizedFileURL.resolvingSymlinksInPath()
            let targetAttributes = try? FileManager.default.attributesOfItem(atPath: target.path)
            let sameFile = attributes?[.systemFileNumber] as? NSNumber != nil
                && attributes?[.systemFileNumber] as? NSNumber == targetAttributes?[.systemFileNumber] as? NSNumber
                && attributes?[.systemNumber] as? NSNumber == targetAttributes?[.systemNumber] as? NSNumber
            guard resolved != target, !sameFile else { throw EventError.protectedExportDestination }
        }
        try withWriteLock {
            // Read after the save panel closes, and coordinate with our writers.
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
        guard (1...6).contains(schema.schemaVersion) else { throw EventError.unsupportedVersion }
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard Set(envelope.events.map(\.id)).count == envelope.events.count else { throw EventError.duplicateID }
        for event in envelope.events { _ = try event.validated(now: event.updatedAt) }
        return envelope.events
    }
    func save(_ events: [CountdownEvent], replacing expected: [CountdownEvent]) throws {
        try withWriteLock {
            // Validation and replacement share a lock across application processes.
            guard try load() == expected else { throw EventError.changedData }
            try write(events)
        }
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
    private func write(_ events: [CountdownEvent]) throws {
        try Self.encodeSnapshot(events).write(to: fileURL, options: .atomic)
    }
    static func encodeSnapshot(_ events: [CountdownEvent]) throws -> Data {
        guard Set(events.map(\.id)).count == events.count else { throw EventError.duplicateID }
        for event in events { _ = try event.validated(now: event.updatedAt) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(schemaVersion: 6, events: events))
    }
}
