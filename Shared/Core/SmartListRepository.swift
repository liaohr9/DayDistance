import Foundation
import Darwin
import CryptoKit

struct SmartListBackup: Identifiable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let listCount: Int
    let fingerprint: String
}

struct SmartListRepository: Sendable {
    let fileURL: URL
    var backupDirectory: URL { fileURL.deletingLastPathComponent().appendingPathComponent("smart-list-backups", isDirectory: true) }
    private let lockName = ".daydistance-smart-backups.lock"
    private static let namePattern = #"^daydistance-smart-([0-9]{13})-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.json$"#
    private struct Envelope: Codable { let schemaVersion: Int; let lists: [SmartList] }
    private struct Schema: Decodable { let schemaVersion: Int }
    private static let maximumBytes = 8 * 1024 * 1024
    private static func encodeSnapshot(_ lists: [SmartList]) throws -> Data {
        guard lists.count <= 100 else { throw SmartListError.invalidList }
        guard Set(lists.map(\.id)).count == lists.count else { throw EventError.duplicateID }
        let validated = try lists.map { try $0.validated() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Envelope(schemaVersion: 1, lists: validated))
        guard data.count <= maximumBytes else { throw SmartListError.invalidList }
        return data
    }
    private static func decodeSnapshot(_ data: Data) throws -> [SmartList] {
        guard data.count <= maximumBytes else { throw SmartListError.invalidList }
        let decoder = JSONDecoder()
        guard try decoder.decode(Schema.self, from: data).schemaVersion == 1 else { throw EventError.unsupportedVersion }
        let lists = try decoder.decode(Envelope.self, from: data).lists
        _ = try encodeSnapshot(lists)
        return lists
    }
    func load() throws -> [SmartList] {
        let parent = Darwin.open(fileURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else {
            if errno == ENOENT { return [] }
            throw LocalBackupError.unsafeLocation
        }
        defer { Darwin.close(parent) }
        let fd = Darwin.openat(parent, fileURL.lastPathComponent, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return [] }
            throw LocalBackupError.unsafeLocation
        }
        defer { Darwin.close(fd) }
        try requireSafeRegular(fd)
        return try Self.decodeSnapshot(FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data())
    }
    func save(_ lists: [SmartList], replacing expected: [SmartList]) throws {
        let data = try Self.encodeSnapshot(lists)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let parent = Darwin.open(fileURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else { throw LocalBackupError.unsafeLocation }
        defer { Darwin.close(parent) }
        let fd = Darwin.openat(parent, fileURL.lastPathComponent + ".lock", O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw LocalBackupError.unsafeLocation }
        defer { Darwin.close(fd) }
        try requireSafeRegular(fd)
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { throw EventError.busyData }
            throw posixError()
        }
        let before = try load()
        guard before == expected else { throw EventError.changedData }
        guard lists != before else { return }
        // Preserve both states before publishing the new live snapshot.
        try recordSnapshots([Self.encodeSnapshot(before), data])
        let temporary = ".daydistance-smart-live-\(UUID().uuidString.lowercased()).tmp"
        try atomicCreate(data, named: temporary, directory: parent)
        defer { Darwin.unlinkat(parent, temporary, 0) }
        guard Darwin.renameat(parent, temporary, parent, fileURL.lastPathComponent) == 0 else { throw posixError() }
    }
    /// Read-only preview token. Missing live data has a distinct identity from empty bytes.
    func recoveryFingerprint() throws -> String {
        let parent = Darwin.open(fileURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else {
            if errno == ENOENT { return liveToken(nil) }
            throw LocalBackupError.unsafeLocation
        }
        defer { Darwin.close(parent) }
        let bytes = try readRawLive(parent: parent)
        try rejectUnsupportedSchema(bytes)
        return liveToken(bytes)
    }

    /// Explicit recovery is separate from ordinary save: corrupt bytes must be preserved first.
    func restore(_ backup: SmartListBackup, replacingLiveFingerprint expected: String) throws {
        // A selected backup necessarily has an existing parent; never create one on recovery.
        let parent = Darwin.open(fileURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else { throw LocalBackupError.unsafeLocation }
        defer { Darwin.close(parent) }
        let lock = Darwin.openat(parent, fileURL.lastPathComponent + ".lock", O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard lock >= 0 else { throw LocalBackupError.unsafeLocation }
        defer { Darwin.close(lock) }
        try requireSafeRegular(lock)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { throw EventError.busyData }
            throw posixError()
        }
        let bytes = try readRawLive(parent: parent)
        try rejectUnsupportedSchema(bytes)
        guard liveToken(bytes) == expected else { throw EventError.changedData }
        let restored = try loadBackup(backup)
        let data = try Self.encodeSnapshot(restored)
        if let bytes, (try? Self.decodeSnapshot(bytes)) == nil {
            guard let directory = try openFolder(create: true) else { throw LocalBackupError.unsafeLocation }
            defer { Darwin.close(directory) }
            // This exact original is deliberately outside the decodable/20-snapshot namespace.
            try atomicCreate(bytes, named: "quarantine-\(UUID().uuidString.lowercased()).json", directory: directory)
            guard fsync(directory) == 0 else { throw posixError() }
        } else {
            let before = try bytes.map(Self.decodeSnapshot) ?? []
            try recordSnapshots([Self.encodeSnapshot(before), data])
        }
        // Recheck even while locked to detect changes from non-cooperating file writers.
        guard liveToken(try readRawLive(parent: parent)) == expected else { throw EventError.changedData }
        let temporary = ".daydistance-smart-live-\(UUID().uuidString.lowercased()).tmp"
        try atomicCreate(data, named: temporary, directory: parent)
        defer { Darwin.unlinkat(parent, temporary, 0) }
        guard Darwin.renameat(parent, temporary, parent, fileURL.lastPathComponent) == 0 else { throw posixError() }
    }

    private func rejectUnsupportedSchema(_ bytes: Data?) throws {
        if let bytes, let schema = try? JSONDecoder().decode(Schema.self, from: bytes), schema.schemaVersion != 1 {
            throw EventError.unsupportedVersion
        }
    }
    private func liveToken(_ bytes: Data?) -> String {
        bytes.map { "sha256:" + fingerprint($0) } ?? "missing:smart-list-v1"
    }
    private func readRawLive(parent: Int32) throws -> Data? {
        let fd = Darwin.openat(parent, fileURL.lastPathComponent, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw LocalBackupError.unsafeLocation
        }
        defer { Darwin.close(fd) }
        try requireSafeRegular(fd)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var bytes = Data()
        while bytes.count <= Self.maximumBytes {
            guard let chunk = try handle.read(upToCount: min(65536, Self.maximumBytes + 1 - bytes.count)), !chunk.isEmpty else { return bytes }
            bytes.append(chunk)
        }
        throw LocalBackupError.unsafeLocation
    }
    private func requireSafeRegular(_ fd: Int32) throws {
        var attributes = stat()
        guard fstat(fd, &attributes) == 0,
              attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), attributes.st_nlink == 1,
              attributes.st_size <= Self.maximumBytes else { throw LocalBackupError.unsafeLocation }
    }
    func backups() throws -> [SmartListBackup] {
        guard let directory = try openFolder(create: false) else { return [] }
        defer { Darwin.close(directory) }
        return try readList(directory)
    }
    func loadBackup(_ backup: SmartListBackup) throws -> [SmartList] {
        guard parseName(backup.id) != nil else { throw LocalBackupError.invalidSnapshot }
        guard let directory = try openFolder(create: false) else { throw LocalBackupError.changedSnapshot }
        defer { Darwin.close(directory) }
        let bytes = try readFile(backup.id, directory: directory)
        guard fingerprint(bytes) == backup.fingerprint else { throw LocalBackupError.changedSnapshot }
        return try Self.decodeSnapshot(bytes)
    }
    private func recordSnapshots(_ snapshots: [Data]) throws {
        guard let directory = try openFolder(create: true) else { throw LocalBackupError.unsafeLocation }
        defer { Darwin.close(directory) }
        let lock = Darwin.openat(directory, lockName, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard lock >= 0 else { throw LocalBackupError.unsafeLocation }
        defer { Darwin.close(lock) }
        try requireRegularSingleLink(lock)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw EventError.busyData }
        let previous = try readList(directory)
        var milliseconds = max(Int64(Date().timeIntervalSince1970 * 1000), previous.first.map { Int64(($0.createdAt.timeIntervalSince1970 * 1000).rounded()) + 1 } ?? 0)
        for data in snapshots {
            let name = "daydistance-smart-\(String(format: "%013lld", milliseconds))-\(UUID().uuidString.lowercased()).json"
            try atomicCreate(data, named: name, directory: directory)
            milliseconds += 1
        }
        for old in try readList(directory).dropFirst(20) {
            guard fingerprint(try readFile(old.id, directory: directory)) == old.fingerprint else { throw LocalBackupError.changedSnapshot }
            guard Darwin.unlinkat(directory, old.id, 0) == 0 else { throw posixError() }
        }
    }
    private func openFolder(create: Bool) throws -> Int32? {
        let parent = Darwin.open(fileURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw LocalBackupError.unsafeLocation
        }
        defer { Darwin.close(parent) }
        var directory = Darwin.openat(parent, "smart-list-backups", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        if directory < 0, errno == ENOENT {
            guard create else { return nil }
            guard Darwin.mkdirat(parent, "smart-list-backups", 0o700) == 0 || errno == EEXIST else { throw posixError() }
            directory = Darwin.openat(parent, "smart-list-backups", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard directory >= 0 else { throw LocalBackupError.unsafeLocation }
        return directory
    }

    private func readList(_ directory: Int32) throws -> [SmartListBackup] {
        let existingLock = Darwin.openat(directory, lockName, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        if existingLock >= 0 {
            defer { Darwin.close(existingLock) }
            try requireRegularSingleLink(existingLock)
        } else if errno != ENOENT { throw LocalBackupError.unsafeLocation }
        // A new descriptor gives each listing a fresh directory cursor.
        let cursor = Darwin.openat(directory, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard cursor >= 0 else { throw posixError() }
        guard let stream = fdopendir(cursor) else { Darwin.close(cursor); throw posixError() }
        defer { closedir(stream) }
        var result: [SmartListBackup] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            guard let date = parseName(name) else { continue }
            let bytes = try readFile(name, directory: directory)
            // Invalid/unsupported files are retained, never offered for restore or pruned.
            guard let events = try? Self.decodeSnapshot(bytes) else { continue }
            result.append(SmartListBackup(id: name, createdAt: date, listCount: events.count, fingerprint: fingerprint(bytes)))
        }
        return result.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id > $1.id
        }
    }

    private func readFile(_ name: String, directory: Int32) throws -> Data {
        let descriptor = Darwin.openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw LocalBackupError.unsafeLocation }
        defer { Darwin.close(descriptor) }
        try requireRegularSingleLink(descriptor)
        try requireSafeRegular(descriptor)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        return try handle.readToEnd() ?? Data()
    }

    private func requireRegularSingleLink(_ descriptor: Int32) throws {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), attributes.st_nlink == 1 else { throw LocalBackupError.unsafeLocation }
        // Also protect live data reached through a source symlink pointing into this folder.
        for protected in [fileURL.path, fileURL.path + ".lock"] {
            var live = stat()
            if fstatat(AT_FDCWD, protected, &live, 0) == 0,
               attributes.st_dev == live.st_dev, attributes.st_ino == live.st_ino { throw LocalBackupError.unsafeLocation }
        }
    }

    private func atomicCreate(_ data: Data, named name: String, directory: Int32) throws {
        let temporary = ".daydistance-smart-\(UUID().uuidString.lowercased()).tmp"
        let descriptor = Darwin.openat(directory, temporary, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer {
            Darwin.close(descriptor)
            Darwin.unlinkat(directory, temporary, 0)
        }
        try requireRegularSingleLink(descriptor)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw posixError() }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw posixError() }
        // Atomic publication with exclusive destination prevents replacing any existing file.
        guard renameatx_np(directory, temporary, directory, name, UInt32(RENAME_EXCL)) == 0 else { throw posixError() }
    }

    private func parseName(_ name: String) -> Date? {
        guard let expression = try? NSRegularExpression(pattern: Self.namePattern),
              let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let stampRange = Range(match.range(at: 1), in: name), let stamp = Double(name[stampRange]) else { return nil }
        return Date(timeIntervalSince1970: stamp / 1000)
    }
    private func fingerprint(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
