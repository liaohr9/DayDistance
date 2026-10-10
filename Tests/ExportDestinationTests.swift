import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class ExportDestinationTests: XCTestCase {
    func testProtectsLiveFileLockAndSymlinkAliasesWithoutWriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = root.appendingPathComponent("events.json"), lock = root.appendingPathComponent("events.json.lock")
        try Data("original".utf8).write(to: data); try Data("lock".utf8).write(to: lock)
        let alias = root.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: data)
        let reminderLock = data.appendingPathExtension("reminders.lock")
        try Data("reminder lock".utf8).write(to: reminderLock)
        let reminderAlias = root.appendingPathComponent("reminder-alias.png")
        try FileManager.default.linkItem(at: reminderLock, to: reminderAlias)
        for destination in [data, lock, alias, reminderLock, reminderAlias] {
            XCTAssertThrowsError(try ExportDestinationPolicy.validate(destination, protectedFiles: [data]))
            XCTAssertThrowsError(try EventRepository(fileURL: data).exportSnapshot(to: destination)) { error in
                guard case EventError.protectedExportDestination = error else { return XCTFail("Expected protected export destination, got \(error)") }
            }
        }
        XCTAssertEqual(try Data(contentsOf: data), Data("original".utf8))
        XCTAssertNoThrow(try ExportDestinationPolicy.validate(root.appendingPathComponent("safe.png"), protectedFiles: [data]))
    }
    func testRejectsHardLinkedEventAndBackupEvenOutsideFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let event = root.appendingPathComponent("events.json"), snapshot = backup.appendingPathComponent("old.json")
        try Data("event".utf8).write(to: event); try Data("snapshot".utf8).write(to: snapshot)
        let eventAlias = root.appendingPathComponent("event.png"), snapshotAlias = root.appendingPathComponent("backup.png")
        try FileManager.default.linkItem(at: event, to: eventAlias)
        try FileManager.default.linkItem(at: snapshot, to: snapshotAlias)
        for destination in [eventAlias, snapshotAlias, backup.appendingPathComponent("new.png")] {
            XCTAssertThrowsError(try ExportDestinationPolicy.validate(destination, protectedFiles: [event], protectedDirectories: [backup]))
        }
        XCTAssertEqual(try Data(contentsOf: snapshot), Data("snapshot".utf8))
    }
    func testDirectorySymlinkCannotBypassBackupProtectionAndSiblingIsAllowed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("other")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: backup)
        XCTAssertThrowsError(try ExportDestinationPolicy.validate(alias.appendingPathComponent("image.png"), protectedFiles: [], protectedDirectories: [backup]))
        XCTAssertNoThrow(try ExportDestinationPolicy.validate(root.appendingPathComponent("backups-user.png"), protectedFiles: [], protectedDirectories: [backup]))
    }
}
