import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class LocalBackupTests: XCTestCase {
    private var directory: URL!
    private var source: URL!
    private var backups: LocalBackupRepository { LocalBackupRepository(eventFileURL: source) }
    private var folder: URL { source.deletingLastPathComponent().appendingPathComponent("backups") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LocalBackups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("events.json")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func event(_ name: String) -> CountdownEvent {
        CountdownEvent(title: name, targetDate: Date(timeIntervalSince1970: 1800000000), createdAt: Date(timeIntervalSince1970: 1700000000), updatedAt: Date(timeIntervalSince1970: 1700000000))
    }
    private func file(_ backup: LocalBackup) -> URL { folder.appendingPathComponent(backup.id) }

    func testReadsAndNoopCreateNothing() throws {
        XCTAssertEqual(try backups.list(), [])
        try backups.recordMutation(before: [], after: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }
    func testFirstSuccessfulMutationPreservesBeforeAfterIDsAndLiveFile() throws {
        let events = [event("Private event")]
        try EventRepository(fileURL: source).save(events, replacing: [])
        let liveBytes = try Data(contentsOf: source)
        try backups.recordMutation(before: [], after: events)
        let snapshots = try backups.list()
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.map(\.phase), [.after, .before])
        XCTAssertEqual(snapshots.map(\.eventCount), [1, 0])
        XCTAssertEqual(try backups.load(snapshots[0]), events)
        XCTAssertEqual(try backups.load(snapshots[0]).first?.id, events.first?.id)
        XCTAssertEqual(try backups.load(snapshots[1]), [])
        XCTAssertEqual(try Data(contentsOf: source), liveBytes)
    }
    func testListingAndPreviewDoNotChangeExistingSnapshotBytesOrNames() throws {
        try backups.recordMutation(before: [], after: [event("Live")])
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        let snapshot = try XCTUnwrap(backups.list().first)
        let bytes = try Data(contentsOf: file(snapshot))
        _ = try backups.list()
        _ = try backups.load(snapshot)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), names)
        XCTAssertEqual(try Data(contentsOf: file(snapshot)), bytes)
    }
    func testRingPreservesLatestTwentyValidSnapshotsOnly() throws {
        for index in 0..<13 {
            try backups.recordMutation(before: [], after: [event("\(index)")], at: Date(timeIntervalSince1970: Double(1700000000 + index)))
        }
        let snapshots = try backups.list()
        XCTAssertEqual(snapshots.count, 20)
        XCTAssertEqual(try backups.load(snapshots[0]).first?.title, "12")
        XCTAssertEqual(snapshots.last?.createdAt, Date(timeIntervalSince1970: 1700000003))
        let owned = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertEqual(owned.count, 20)
    }
    func testCorruptNewerAndForeignFilesAreNeverPruned() throws {
        try backups.recordMutation(before: [], after: [event("First")])
        let initial = try backups.list()
        let broken = file(initial[0]), newer = file(initial[1])
        let brokenBytes = Data("not json".utf8)
        let newerBytes = Data("{\"schemaVersion\":999,\"events\":[]}".utf8)
        try brokenBytes.write(to: broken)
        try newerBytes.write(to: newer)
        let foreign = folder.appendingPathComponent("personal.json")
        try Data("keep me".utf8).write(to: foreign)
        XCTAssertTrue(try backups.list().isEmpty)
        for index in 0..<12 {
            try backups.recordMutation(before: [], after: [event("\(index)")], at: Date(timeIntervalSince1970: Double(1800000000 + index)))
        }
        XCTAssertEqual(try backups.list().count, 20)
        XCTAssertEqual(try Data(contentsOf: broken), brokenBytes)
        XCTAssertEqual(try Data(contentsOf: newer), newerBytes)
        XCTAssertEqual(try String(contentsOf: foreign), "keep me")
    }
    func testSameMillisecondMutationsStillRetainTheNewest() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        for index in 0..<13 { try backups.recordMutation(before: [], after: [event("\(index)")], at: date) }
        let snapshots = try backups.list()
        XCTAssertEqual(snapshots.count, 20)
        XCTAssertEqual(try backups.load(snapshots[0]).first?.title, "12")
    }
    func testLiveSourceSymlinkToOwnedSnapshotIsNeverPruned() throws {
        try backups.recordMutation(before: [], after: [event("Live")])
        let snapshot = try XCTUnwrap(backups.list().first)
        let bytes = try Data(contentsOf: file(snapshot))
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: file(snapshot))
        XCTAssertThrowsError(try backups.list())
        XCTAssertThrowsError(try backups.list())
        XCTAssertThrowsError(try backups.recordMutation(before: [], after: [event("New")]))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
    func testCurrentSchemaAndAllFieldsRoundTripViaSharedCodec() throws {
        var value = event("Annual all-day")
        value.isAllDay = true; value.calendarDay = CalendarDay(year: 2028, month: 2, day: 29)
        value.repeatYearly = true; value.isPinned = true; value.reminder = .dayBefore
        try backups.recordMutation(before: [], after: [value])
        let snapshot = try XCTUnwrap(backups.list().first)
        XCTAssertEqual(try backups.load(snapshot), [value])
        XCTAssertEqual(try Data(contentsOf: file(snapshot)), try EventRepository.encodeSnapshot([value]))
    }
    func testWarmListingRevalidatesChangedContentEvenWhenTimestampIsRestored() throws {
        let first = event("Original")
        try backups.recordMutation(before: [], after: [first])
        let original = try XCTUnwrap(backups.list().first)
        let path = file(original)
        let stamp = try FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate] as! Date
        let replacement = [first, event("Second")]
        try EventRepository.encodeSnapshot(replacement).write(to: path)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: path.path)
        let refreshed = try XCTUnwrap(backups.list().first(where: { $0.id == original.id }))
        XCTAssertEqual(refreshed.eventCount, 2)
        XCTAssertNotEqual(refreshed.fingerprint, original.fingerprint)
        XCTAssertEqual(try backups.load(refreshed), replacement)
        XCTAssertThrowsError(try backups.load(original))
        try Data("corrupted after warm listing".utf8).write(to: path)
        XCTAssertFalse(try backups.list().contains(where: { $0.id == original.id }))
        XCTAssertEqual(try String(contentsOf: path), "corrupted after warm listing")
    }
    func testInvalidInputCreatesNothing() throws {
        let invalid = event("")
        XCTAssertThrowsError(try backups.recordMutation(before: [], after: [invalid]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
    func testSymlinkFolderRejectedWithoutWritingOutside() throws {
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
        XCTAssertThrowsError(try backups.list())
        XCTAssertThrowsError(try backups.recordMutation(before: [], after: [event("A")]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }
    func testOwnedSnapshotSymlinkAndHardlinkAreRejectedAndLiveDataPreserved() throws {
        let value = event("Live")
        try EventRepository(fileURL: source).save([value], replacing: [])
        let liveBytes = try Data(contentsOf: source)
        try backups.recordMutation(before: [], after: [value])
        let snapshot = try XCTUnwrap(backups.list().first)
        let destination = file(snapshot)
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
        XCTAssertThrowsError(try backups.list())
        XCTAssertThrowsError(try backups.load(snapshot))
        XCTAssertThrowsError(try backups.recordMutation(before: [], after: [event("New")]))
        XCTAssertEqual(try Data(contentsOf: source), liveBytes)
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.linkItem(at: source, to: destination)
        XCTAssertThrowsError(try backups.list())
        XCTAssertThrowsError(try backups.recordMutation(before: [], after: [event("New")]))
        XCTAssertEqual(try Data(contentsOf: source), liveBytes)
    }
    func testBackupLockAliasesRejected() throws {
        try EventRepository(fileURL: source).save([event("Live")], replacing: [])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lock = folder.appendingPathComponent(".daydistance-backups.lock")
        try FileManager.default.linkItem(at: source, to: lock)
        let bytes = try Data(contentsOf: source)
        XCTAssertThrowsError(try backups.list())
        XCTAssertThrowsError(try backups.recordMutation(before: [], after: [event("New")]))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
    func testPreviewFingerprintRejectsChangedSnapshotAndForgedFilename() throws {
        try backups.recordMutation(before: [], after: [event("Original")])
        let snapshot = try XCTUnwrap(backups.list().first)
        try EventRepository.encodeSnapshot([event("Changed")]).write(to: file(snapshot))
        XCTAssertThrowsError(try backups.load(snapshot))
        let forged = LocalBackup(id: "../events.json", createdAt: snapshot.createdAt, eventCount: 1, phase: .after, fingerprint: snapshot.fingerprint)
        XCTAssertThrowsError(try backups.load(forged))
    }
}
