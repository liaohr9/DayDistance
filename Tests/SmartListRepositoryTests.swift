import XCTest
import Darwin
@testable import DayDistanceCore
final class SmartListRepositoryTests: XCTestCase {
    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("SmartListTests-" + UUID().uuidString) }
    func testReadsCreateNothingAndCASRestoreIsolation() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let repository = SmartListRepository(fileURL: root.appendingPathComponent("lists.json"))
        XCTAssertEqual(try repository.load(), []); XCTAssertEqual(try repository.backups(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let lists = [SmartList(name: "First")]
        try repository.save(lists, replacing: [])
        XCTAssertEqual(try repository.load(), lists)
        XCTAssertThrowsError(try repository.save([], replacing: []))
        let backups = try repository.backups()
        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(try repository.loadBackup(backups[0]), lists)
        XCTAssertEqual(try repository.loadBackup(backups[1]), [])
        let other = SmartListRepository(fileURL: root.appendingPathComponent("isolated/lists.json"))
        XCTAssertEqual(try other.load(), []); XCTAssertEqual(try other.backups(), [])
    }
    func testCorruptFutureDuplicateAndBusy() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("lists.json"), repo = SmartListRepository(fileURL: root.appendingPathComponent("lists.json"))
        for bytes in [Data("oops".utf8), Data("{\"schemaVersion\":2,\"lists\":[]}".utf8)] {
            try bytes.write(to: url)
            XCTAssertThrowsError(try repo.load()); XCTAssertThrowsError(try repo.save([], replacing: []))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        try FileManager.default.removeItem(at: url)
        let list = SmartList(name: "x")
        XCTAssertThrowsError(try repo.save([list,list], replacing: []))
        let lock = Darwin.open(url.path + ".lock", O_CREAT | O_RDWR, 0o600)
        defer { Darwin.close(lock) }
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try repo.save([list], replacing: []))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testBoundedOwnedBackupsAndTamper() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let repo = SmartListRepository(fileURL: root.appendingPathComponent("lists.json"))
        var previous: [SmartList] = []
        for index in 0..<15 { let next = [SmartList(name: "\(index)")]; try repo.save(next, replacing: previous); previous = next }
        let backups = try repo.backups(); XCTAssertEqual(backups.count, 20)
        let unknown = repo.backupDirectory.appendingPathComponent("personal.json")
        try Data("keep".utf8).write(to: unknown)
        try repo.save([], replacing: previous)
        XCTAssertEqual(try Data(contentsOf: unknown), Data("keep".utf8))
        let backup = try XCTUnwrap(repo.backups().first)
        try Data("changed".utf8).write(to: repo.backupDirectory.appendingPathComponent(backup.id))
        XCTAssertThrowsError(try repo.loadBackup(backup))
        let traversal = SmartListBackup(id: "../lists.json", createdAt: Date(), listCount: 0, fingerprint: "")
        XCTAssertThrowsError(try repo.loadBackup(traversal))
    }
    func testUnsafeBackupLinksRejectedAndLiveUnchanged() throws {
        for hard in [false,true] {
            let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
            let repo = SmartListRepository(fileURL: root.appendingPathComponent("lists.json"))
            let first = [SmartList(name: "First")]; try repo.save(first, replacing: [])
            let backup = try XCTUnwrap(repo.backups().first)
            let path = repo.backupDirectory.appendingPathComponent(backup.id)
            try FileManager.default.removeItem(at: path)
            if hard { try FileManager.default.linkItem(at: repo.fileURL, to: path) }
            else { try FileManager.default.createSymbolicLink(at: path, withDestinationURL: repo.fileURL) }
            XCTAssertThrowsError(try repo.backups())
            XCTAssertThrowsError(try repo.save([], replacing: first))
            // A hard link to live data also deliberately fails the live reader.
            if !hard { XCTAssertEqual(try repo.load(), first) }
        }
    }
}
extension SmartListRepositoryTests {
    func testLiveAndFolderSymlinksAndDuplicateRules() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = SmartListRepository(fileURL: root.appendingPathComponent("lists.json"))
        let target = root.appendingPathComponent("target.json")
        try Data("preserve".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: repo.fileURL, withDestinationURL: target)
        XCTAssertThrowsError(try repo.load())
        XCTAssertThrowsError(try repo.save([SmartList(name: "x")], replacing: []))
        XCTAssertEqual(try Data(contentsOf: target), Data("preserve".utf8))
        try FileManager.default.removeItem(at: repo.fileURL)
        try FileManager.default.createSymbolicLink(at: repo.backupDirectory, withDestinationURL: root)
        XCTAssertThrowsError(try repo.backups())
        XCTAssertThrowsError(try repo.save([SmartList(name: "x")], replacing: []))
        let rule = SmartRule(text: "x")
        XCTAssertThrowsError(try repo.save([SmartList(name: "x", rules: [rule,rule])], replacing: []))
    }
}
extension SmartListRepositoryTests {
    func testRecoveryPreservesCorruptBytesAndReadDoesNotWrite() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let repo = SmartListRepository(fileURL: root.appendingPathComponent("lists.json"))
        let missing = try repo.recoveryFingerprint()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let lists = [SmartList(name: "Recovery")]; try repo.save(lists, replacing: [])
        let backup = try XCTUnwrap(repo.backups().first)
        let broken = Data("{broken original bytes".utf8); try broken.write(to: repo.fileURL)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path)
        let token = try repo.recoveryFingerprint()
        XCTAssertNotEqual(token, missing)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), before)
        XCTAssertThrowsError(try repo.save([], replacing: []))
        try repo.restore(backup, replacingLiveFingerprint: token)
        XCTAssertEqual(try repo.load(), lists)
        let quarantine = try FileManager.default.contentsOfDirectory(at: repo.backupDirectory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("quarantine-") }
        XCTAssertEqual(quarantine.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(quarantine.first)), broken)
        XCTAssertEqual(try repo.backups().count, 2)
        try repo.save([], replacing: lists)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(quarantine.first)), broken)
    }
    func testRecoveryCASValidMissingAndBusy() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let repo = SmartListRepository(fileURL: root.appendingPathComponent("lists.json"))
        let missing = try repo.recoveryFingerprint()
        let lists = [SmartList(name: "Original")]; try repo.save(lists, replacing: [])
        let backup = try XCTUnwrap(repo.backups().first)
        XCTAssertThrowsError(try repo.restore(backup, replacingLiveFingerprint: missing))
        let token = try repo.recoveryFingerprint()
        let lock = Darwin.open(repo.fileURL.path + ".lock", O_RDWR)
        XCTAssertGreaterThanOrEqual(lock, 0); defer { Darwin.close(lock) }
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try repo.restore(backup, replacingLiveFingerprint: token))
        XCTAssertEqual(flock(lock, LOCK_UN), 0)
        try repo.save([], replacing: lists)
        XCTAssertThrowsError(try repo.restore(backup, replacingLiveFingerprint: token))
        try repo.restore(backup, replacingLiveFingerprint: repo.recoveryFingerprint())
        XCTAssertEqual(try repo.load(), lists)
        try FileManager.default.removeItem(at: repo.fileURL)
        try repo.restore(backup, replacingLiveFingerprint: repo.recoveryFingerprint())
        XCTAssertEqual(try repo.load(), lists)
    }
    func testRecoveryRejectsFutureAndUnsafeFiles() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let repo = SmartListRepository(fileURL: root.appendingPathComponent("lists.json"))
        try repo.save([SmartList(name: "x")], replacing: [])
        let backup = try XCTUnwrap(repo.backups().first)
        let token = try repo.recoveryFingerprint()
        let future = Data("{\"schemaVersion\":999,\"lists\":\"unknown fields\"}".utf8)
        try future.write(to: repo.fileURL)
        XCTAssertThrowsError(try repo.recoveryFingerprint()) { error in guard case EventError.unsupportedVersion = error else { return XCTFail("Expected future schema error") } }
        XCTAssertThrowsError(try repo.restore(backup, replacingLiveFingerprint: token))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), future)
        try FileManager.default.removeItem(at: repo.fileURL)
        try FileManager.default.createSymbolicLink(at: repo.fileURL, withDestinationURL: repo.backupDirectory.appendingPathComponent(backup.id))
        XCTAssertThrowsError(try repo.recoveryFingerprint())
        XCTAssertThrowsError(try repo.restore(backup, replacingLiveFingerprint: token))
    }
}

extension SmartListRepositoryTests {
    func testRecoveryRejectsOversizedHardlinkedLiveAndUnsafeLock() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let repo = SmartListRepository(fileURL: root.appendingPathComponent("lists.json"))
        try repo.save([SmartList(name: "x")], replacing: [])
        let backup = try XCTUnwrap(repo.backups().first)
        let token = try repo.recoveryFingerprint()
        try Data(repeating: 0x41, count: 8 * 1024 * 1024 + 1).write(to: repo.fileURL)
        XCTAssertThrowsError(try repo.recoveryFingerprint())
        XCTAssertThrowsError(try repo.restore(backup, replacingLiveFingerprint: token))
        try Data("broken".utf8).write(to: repo.fileURL)
        let original = try Data(contentsOf: repo.fileURL)
        let hardlink = root.appendingPathComponent("hardlink.json")
        try FileManager.default.linkItem(at: repo.fileURL, to: hardlink)
        XCTAssertThrowsError(try repo.recoveryFingerprint())
        XCTAssertThrowsError(try repo.restore(backup, replacingLiveFingerprint: token))
        try FileManager.default.removeItem(at: hardlink)
        let validToken = try repo.recoveryFingerprint()
        let lock = repo.fileURL.appendingPathExtension("lock")
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: repo.fileURL)
        XCTAssertThrowsError(try repo.restore(backup, replacingLiveFingerprint: validToken))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)
    }
}
