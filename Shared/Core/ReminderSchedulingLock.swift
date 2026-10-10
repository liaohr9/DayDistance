import Foundation
import Darwin

/// Serializes notification queue replacement across the main app and headless refresh.
/// Keep the sidecar inode; deleting a flock file would split the coordination domain.
final class ReminderSchedulingLock {
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
    static func acquire(at url: URL) throws -> ReminderSchedulingLock? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            if code == EWOULDBLOCK { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return ReminderSchedulingLock(descriptor: descriptor)
    }
}
