import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class ReminderSchedulingLockTests: XCTestCase {
    func testConcurrentSchedulersCannotAcquireSameLeaseAndReleaseReusesInode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("reminders.lock")
        var first: ReminderSchedulingLock? = try ReminderSchedulingLock.acquire(at: url)
        XCTAssertNotNil(first)
        XCTAssertNil(try ReminderSchedulingLock.acquire(at: url))
        let inode = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as! NSNumber
        first = nil
        let second = try ReminderSchedulingLock.acquire(at: url)
        XCTAssertNotNil(second)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber, inode)
    }
    func testRefusesSymlinkWithoutChangingTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("keep")
        try Data("keep".utf8).write(to: target)
        let link = root.appendingPathComponent("reminders.lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try ReminderSchedulingLock.acquire(at: link))
        XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
    }
}
