import CryptoKit
import Darwin
import Foundation

struct LocalBackup: Identifiable, Equatable, Sendable {
    enum Phase: String, Sendable { case before, after }
    let id: String
    let createdAt: Date
    let eventCount: Int
    let phase: Phase
    // Detect replacement between the preview and confirmation, without exposing content in the list.
    let fingerprint: String
}

enum LocalBackupError: LocalizedError {
    case unsafeLocation, changedSnapshot, invalidSnapshot, busy
    var errorDescription: String? {
        switch self {
        case .unsafeLocation: return L10n.text("备份位置无法安全访问。请检查本地数据目录。")
        case .changedSnapshot: return L10n.text("这份备份已被更改。请重新读取备份列表。")
        case .invalidSnapshot: return L10n.text("备份文件无法识别。")
        case .busy: return L10n.text("另一个窗口正在创建备份，请稍后重试。")
        }
    }
}

/// Called only after a successful actual event mutation. Listing and loading never create files.
struct LocalBackupRepository: Sendable {
    static let maximumSnapshots = 20
    let eventFileURL: URL
    var folderURL: URL { eventFileURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true) }
    private let lockName = ".daydistance-backups.lock"
    private static let namePattern = #"^daydistance-([0-9]{13})-(before|after)-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.json$"#

    func recordMutation(before: [CountdownEvent], after: [CountdownEvent], at date: Date = Date()) throws {
        guard before != after else { return }
        // Validate both snapshots before creating a directory or writing either one.
        let beforeData = try EventRepository.encodeSnapshot(before)
        let afterData = try EventRepository.encodeSnapshot(after)
        let milliseconds = date.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 10_000_000_000_000 else { throw LocalBackupError.invalidSnapshot }
        let requestedMilliseconds = Int64(milliseconds.rounded(.down))
        guard let directory = try openFolder(create: true) else { throw LocalBackupError.unsafeLocation }
        defer { Darwin.close(directory) }
        let lock = Darwin.openat(directory, lockName, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw posixError() }
        defer { Darwin.close(lock) }
        try requireRegularSingleLink(lock)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { throw LocalBackupError.busy }
            throw posixError()
        }
        // Reject unsafe owned entries before adding snapshots; unknown files are left alone.
        let previous = try readList(directory)
        let newestMilliseconds = previous.first.map { Int64(($0.createdAt.timeIntervalSince1970 * 1000).rounded()) } ?? -1
        let nextMilliseconds = max(requestedMilliseconds, newestMilliseconds + 1)
        guard nextMilliseconds < 10_000_000_000_000 else { throw LocalBackupError.invalidSnapshot }
        let timestamp = String(format: "%013lld", nextMilliseconds)
        for (phase, data) in [(LocalBackup.Phase.before, beforeData), (.after, afterData)] {
            let name = "daydistance-\(timestamp)-\(phase.rawValue)-\(UUID().uuidString.lowercased()).json"
            try atomicCreate(data, named: name, directory: directory)
        }
        let valid = try readList(directory)
        for old in valid.dropFirst(Self.maximumSnapshots) {
            // Recheck the exact candidate before removing only this owned file.
            let bytes = try readFile(old.id, directory: directory)
            guard fingerprint(bytes) == old.fingerprint else { throw LocalBackupError.changedSnapshot }
            guard Darwin.unlinkat(directory, old.id, 0) == 0 else { throw posixError() }
        }
    }

    func list() throws -> [LocalBackup] {
        guard let directory = try openFolder(create: false) else { return [] }
        defer { Darwin.close(directory) }
        return try readList(directory)
    }

    func load(_ backup: LocalBackup) throws -> [CountdownEvent] {
        guard parseName(backup.id) != nil else { throw LocalBackupError.invalidSnapshot }
        guard let directory = try openFolder(create: false) else { throw LocalBackupError.changedSnapshot }
        defer { Darwin.close(directory) }
        let bytes = try readFile(backup.id, directory: directory)
        guard fingerprint(bytes) == backup.fingerprint else { throw LocalBackupError.changedSnapshot }
        return try EventRepository.decodeSnapshot(bytes)
    }

    private func openFolder(create: Bool) throws -> Int32? {
        let parent = Darwin.open(eventFileURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw LocalBackupError.unsafeLocation
        }
        defer { Darwin.close(parent) }
        var directory = Darwin.openat(parent, "backups", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        if directory < 0, errno == ENOENT {
            guard create else { return nil }
            guard Darwin.mkdirat(parent, "backups", 0o700) == 0 || errno == EEXIST else { throw posixError() }
            directory = Darwin.openat(parent, "backups", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard directory >= 0 else { throw LocalBackupError.unsafeLocation }
        return directory
    }

    private func readList(_ directory: Int32) throws -> [LocalBackup] {
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
        var result: [LocalBackup] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            guard let (date, phase) = parseName(name) else { continue }
            let bytes = try readFile(name, directory: directory)
            // Invalid/unsupported files are retained, never offered for restore or pruned.
            guard let events = try? EventRepository.decodeSnapshot(bytes) else { continue }
            result.append(LocalBackup(id: name, createdAt: date, eventCount: events.count, phase: phase, fingerprint: fingerprint(bytes)))
        }
        return result.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            if $0.phase != $1.phase { return $0.phase == .after }
            return $0.id > $1.id
        }
    }

    private func readFile(_ name: String, directory: Int32) throws -> Data {
        let descriptor = Darwin.openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw LocalBackupError.unsafeLocation }
        defer { Darwin.close(descriptor) }
        try requireRegularSingleLink(descriptor)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        return try handle.readToEnd() ?? Data()
    }

    private func requireRegularSingleLink(_ descriptor: Int32) throws {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), attributes.st_nlink == 1 else { throw LocalBackupError.unsafeLocation }
        // Also protect live data reached through a source symlink pointing into this folder.
        for protected in [eventFileURL.path, eventFileURL.path + ".lock"] {
            var live = stat()
            if fstatat(AT_FDCWD, protected, &live, 0) == 0,
               attributes.st_dev == live.st_dev, attributes.st_ino == live.st_ino { throw LocalBackupError.unsafeLocation }
        }
    }

    private func atomicCreate(_ data: Data, named name: String, directory: Int32) throws {
        let temporary = ".daydistance-\(UUID().uuidString.lowercased()).tmp"
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

    private func parseName(_ name: String) -> (Date, LocalBackup.Phase)? {
        guard let expression = try? NSRegularExpression(pattern: Self.namePattern),
              let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let stampRange = Range(match.range(at: 1), in: name), let stamp = Double(name[stampRange]),
              let phaseRange = Range(match.range(at: 2), in: name), let phase = LocalBackup.Phase(rawValue: String(name[phaseRange])) else { return nil }
        return (Date(timeIntervalSince1970: stamp / 1000), phase)
    }
    private func fingerprint(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
