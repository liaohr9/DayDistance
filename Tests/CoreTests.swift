import XCTest
import Darwin
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class CoreTests: XCTestCase {
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testCalendarDaysAcrossMidnight() {
        let now = date("2026-10-05T23:50:00+08:00")
        let target = date("2026-10-06T00:10:00+08:00")
        let value = DayCounter.snapshot(target: target, now: now, timeZone: shanghai)
        XCTAssertEqual(value.days, 1)
        XCTAssertTrue(value.isFuture)
        XCTAssertEqual(value.seconds, 1200)
    }
    func testPastAndSameDay() {
        let now = date("2026-10-05T10:00:00+08:00")
        let value = DayCounter.snapshot(target: date("2026-10-05T09:30:00+08:00"), now: now, timeZone: shanghai)
        XCTAssertEqual(value.days, 0)
        XCTAssertFalse(value.isFuture)
        XCTAssertEqual(value.seconds, 1800)
        XCTAssertEqual(DayCounter.snapshot(target: date("2026-10-03T09:30:00+08:00"), now: now, timeZone: shanghai).days, 2)
    }
    func testExactTargetHasPassed() {
        let now = date("2026-10-05T10:00:00Z")
        let value = DayCounter.snapshot(target: now, now: now, timeZone: shanghai)
        XCTAssertFalse(value.isFuture)
        XCTAssertEqual(value.seconds, 0)
    }
    func testLeapDay() {
        XCTAssertEqual(DayCounter.snapshot(target: date("2028-03-01T12:00:00Z"), now: date("2028-02-28T12:00:00Z"), timeZone: TimeZone(secondsFromGMT: 0)!).days, 2)
    }
    func testDSTSpringAndAutumnAreCalendarDays() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        for (start, end, seconds) in [("2026-03-07T12:00:00-08:00", "2026-03-08T12:00:00-07:00", 82800), ("2026-10-31T12:00:00-07:00", "2026-11-01T12:00:00-08:00", 90000)] {
            let value = DayCounter.snapshot(target: date(end), now: date(start), timeZone: zone)
            XCTAssertEqual(value.days, 1)
            XCTAssertEqual(value.seconds, seconds)
        }
    }
    func testTimezoneChangesDaysButNotInstant() {
        let now = date("2026-10-05T15:00:00Z"), target = date("2026-10-05T17:00:00Z")
        XCTAssertEqual(DayCounter.snapshot(target: target, now: now, timeZone: shanghai).days, 1)
        XCTAssertEqual(DayCounter.snapshot(target: target, now: now, timeZone: TimeZone(secondsFromGMT: 0)!).days, 0)
    }
    func testInclusiveElapsedAtTargetAndFollowingDays() {
        let target = date("2026-10-05T09:30:00+08:00")
        for (now, expected) in [(target, 1), (date("2026-10-05T10:00:00+08:00"), 1), (date("2026-10-06T00:01:00+08:00"), 2)] {
            let normal = DayCounter.snapshot(target: target, now: now, timeZone: shanghai)
            let inclusive = DayCounter.snapshot(target: target, now: now, includesStartDay: true, timeZone: shanghai)
            XCTAssertEqual(inclusive.days, expected)
            XCTAssertEqual(inclusive.days, normal.days + 1)
            XCTAssertEqual(inclusive.isFuture, normal.isFuture)
            XCTAssertEqual(inclusive.seconds, normal.seconds)
        }
    }
    func testInclusiveLeavesFutureUnchanged() {
        let now = date("2026-10-05T09:00:00+08:00")
        for target in [date("2026-10-05T09:30:00+08:00"), date("2026-10-07T00:01:00+08:00")] {
            XCTAssertEqual(DayCounter.snapshot(target: target, now: now, includesStartDay: true, timeZone: shanghai),
                           DayCounter.snapshot(target: target, now: now, timeZone: shanghai))
        }
    }
    func testInclusiveKeepsClockVisibleOn25HourSameDay() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let target = date("2026-11-01T00:00:00-07:00"), now = date("2026-11-01T23:30:00-08:00")
        for enabled in [false, true] {
            let value = DayCounter.snapshot(target: target, now: now, includesStartDay: enabled, timeZone: zone)
            XCTAssertEqual(value.seconds, 88200)
            XCTAssertTrue(value.showsClock)
            XCTAssertEqual(value.clockLabel, "24:30:00")
            let nextDay = DayCounter.snapshot(target: target, now: date("2026-11-02T23:30:00-08:00"), includesStartDay: enabled, timeZone: zone)
            XCTAssertFalse(nextDay.showsClock)
        }
    }
    func testInclusiveUsesCalendarAcrossDSTLeapDayAndTimezone() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        for (target, now, seconds) in [("2026-03-07T12:00:00-08:00", "2026-03-08T12:00:00-07:00", 82800), ("2026-10-31T12:00:00-07:00", "2026-11-01T12:00:00-08:00", 90000)] {
            let value = DayCounter.snapshot(target: date(target), now: date(now), includesStartDay: true, timeZone: zone)
            XCTAssertEqual(value.days, 2)
            XCTAssertEqual(value.seconds, seconds)
        }
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(DayCounter.snapshot(target: date("2028-02-28T12:00:00Z"), now: date("2028-03-01T12:00:00Z"), includesStartDay: true, timeZone: utc).days, 3)
        let now = date("2026-10-05T16:30:00Z"), target = date("2026-10-05T15:30:00Z")
        XCTAssertEqual(DayCounter.snapshot(target: target, now: now, includesStartDay: true, timeZone: shanghai).days, 2)
        XCTAssertEqual(DayCounter.snapshot(target: target, now: now, includesStartDay: true, timeZone: utc).days, 1)
    }
    func testLegacyAndNewEventsDefaultToDayZero() throws {
        let event = CountdownEvent(title: "原事件", targetDate: date("2026-10-05T09:30:00Z"))
        XCTAssertFalse(event.includesStartDay)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        fields.removeValue(forKey: "includesStartDay")
        let legacy = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "events": [fields]])
        let repo = EventRepository(fileURL: temporaryURL())
        try FileManager.default.createDirectory(at: repo.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacy.write(to: repo.fileURL)
        XCTAssertEqual(try repo.load(), [event])
        XCTAssertFalse(try XCTUnwrap(repo.load().first).includesStartDay)
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), legacy)
    }
    func testInclusiveFlagSurvivesReopenExportImportAndTurningOff() throws {
        let repo = EventRepository(fileURL: temporaryURL()), destination = EventRepository(fileURL: temporaryURL())
        var event = CountdownEvent(title: "纪念日", targetDate: date("2026-10-05T09:30:00Z"))
        event.includesStartDay = true
        try repo.save([event], replacing: [])
        XCTAssertEqual(try EventRepository(fileURL: repo.fileURL).load(), [event])
        XCTAssertEqual(try destination.importSnapshot(repo.exportSnapshot(), replacing: []), [event])
        var disabled = event
        disabled.includesStartDay = false
        try repo.save([disabled], replacing: [event])
        XCTAssertEqual(try repo.load(), [disabled])
        XCTAssertEqual(disabled.id, event.id)
    }
    func testInclusiveFlagChangeRejectsStaleSave() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let original = CountdownEvent(title: "同一事件", targetDate: Date())
        try repo.save([original], replacing: [])
        var updated = original
        updated.includesStartDay = true
        try repo.save([updated], replacing: [original])
        let bytes = try Data(contentsOf: repo.fileURL)
        XCTAssertThrowsError(try repo.save([original], replacing: [original]))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), bytes)
    }
    func testInvalidInclusiveFlagCannotBeOverwritten() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let event = CountdownEvent(title: "原事件", targetDate: Date())
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        fields["includesStartDay"] = "yes"
        let bad = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "events": [fields]])
        try FileManager.default.createDirectory(at: repo.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bad.write(to: repo.fileURL)
        XCTAssertThrowsError(try repo.load())
        XCTAssertThrowsError(try repo.save([], replacing: []))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), bad)
    }
    private var temporaryDirectories: [URL] = []
    override func tearDownWithError() throws {
        for directory in temporaryDirectories where FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
    }
    func temporaryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("events.json")
    }
    func testSaveEditDeleteAndReopen() throws {
        let url = temporaryURL(), repo = EventRepository(fileURL: temporaryURL())
        XCTAssertEqual(try repo.load(), [])
        let store = EventRepository(fileURL: url)
        var event = CountdownEvent(title: "  出发  ", targetDate: date("2026-12-01T10:00:36Z"))
        event = try event.validated(now: date("2026-10-05T10:00:00Z"))
        XCTAssertEqual(event.title, "出发")
        XCTAssertEqual(event.targetDate.timeIntervalSince1970.truncatingRemainder(dividingBy: 60), 0)
        try store.save([event], replacing: try store.load())
        XCTAssertEqual(try EventRepository(fileURL: url).load(), [event])
        let originalID = event.id
        event.title = "旅行"
        try store.save([event], replacing: try store.load())
        XCTAssertEqual(try store.load().first?.id, originalID)
        XCTAssertEqual(try store.load().first?.title, "旅行")
        try store.save([], replacing: try store.load())
        XCTAssertTrue(try store.load().isEmpty)
    }
    func testBlankTitleRejected() {
        XCTAssertThrowsError(try CountdownEvent(title: " \n ", targetDate: Date()).validated(now: Date()))
    }
    func testCorruptedFileCannotBeOverwritten() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bad = Data("broken-json".utf8)
        try bad.write(to: url)
        let repo = EventRepository(fileURL: url)
        XCTAssertThrowsError(try repo.load())
        XCTAssertThrowsError(try repo.save([], replacing: []))
        XCTAssertEqual(try Data(contentsOf: url), bad)
    }
    func testUnsupportedVersionCannotBeOverwritten() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bad = Data("{\"schemaVersion\":99,\"events\":[]}".utf8)
        try bad.write(to: url)
        XCTAssertThrowsError(try EventRepository(fileURL: url).save([], replacing: []))
        XCTAssertEqual(try Data(contentsOf: url), bad)
    }
    func testFailedWriteLeavesFileUnchanged() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try EventRepository(fileURL: url).save([], replacing: []))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
    func testMigratesLegacyEventsWithoutChangingSource() throws {
        let legacy = EventRepository(fileURL: temporaryURL())
        let shared = EventRepository(fileURL: temporaryURL())
        let event = CountdownEvent(title: "已有日子", targetDate: date("2026-10-12T05:25:00Z"), symbol: "calendar", colorKey: "blue")
        try legacy.save([event], replacing: [])
        let original = try Data(contentsOf: legacy.fileURL)
        XCTAssertEqual(try shared.loadMigrating(from: legacy), [event])
        XCTAssertEqual(try shared.load(), [event])
        XCTAssertEqual(try Data(contentsOf: legacy.fileURL), original)
    }
    func testMigrationNeverOverwritesExistingSharedData() throws {
        let legacy = EventRepository(fileURL: temporaryURL())
        let shared = EventRepository(fileURL: temporaryURL())
        let old = CountdownEvent(title: "旧数据", targetDate: Date())
        let current = CountdownEvent(title: "新数据", targetDate: Date())
        try legacy.save([old], replacing: [])
        try shared.save([current], replacing: [])
        XCTAssertEqual(try shared.loadMigrating(from: legacy), [current])
        try shared.save([], replacing: [current])
        XCTAssertEqual(try shared.loadMigrating(from: legacy), [])
    }

    private func backupData(_ events: [CountdownEvent], version: Int = 1) throws -> Data {
        struct Backup: Encodable { let schemaVersion: Int; let events: [CountdownEvent] }
        return try JSONEncoder().encode(Backup(schemaVersion: version, events: events))
    }
    func testExportSnapshotPreservesEveryFieldAndSourceBytes() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let event = CountdownEvent(title: "迁移", targetDate: date("2027-01-01T12:34:00Z"), symbol: "heart", colorKey: "rose", createdAt: date("2020-01-01T00:00:00Z"), updatedAt: date("2026-10-06T00:00:00Z"))
        try repo.save([event], replacing: [])
        let original = try Data(contentsOf: repo.fileURL)
        let exported = try repo.exportSnapshot()
        XCTAssertFalse(exported.isEmpty)
        guard !exported.isEmpty else { return }
        struct Backup: Decodable { let schemaVersion: Int; let events: [CountdownEvent] }
        let copy = try JSONDecoder().decode(Backup.self, from: exported)
        XCTAssertEqual(copy.schemaVersion, 6)
        XCTAssertEqual(copy.events, [event])
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)
    }
    func testExportRefusesDataLockLegacyAndSymlinkTargets() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let event = CountdownEvent(title: "原事件", targetDate: Date())
        try repo.save([event], replacing: [])
        let original = try Data(contentsOf: repo.fileURL)
        let lock = URL(fileURLWithPath: repo.fileURL.path + ".lock")
        let lockOriginal = try Data(contentsOf: lock)
        let legacy = temporaryURL()
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacyOriginal = Data("旧版本原数据".utf8)
        try legacyOriginal.write(to: legacy)
        let link = repo.fileURL.deletingLastPathComponent().appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo.fileURL)
        let hardLink = repo.fileURL.deletingLastPathComponent().appendingPathComponent("hard-link.json")
        try FileManager.default.linkItem(at: repo.fileURL, to: hardLink)
        for target in [repo.fileURL, lock, legacy, URL(fileURLWithPath: legacy.path + ".lock"), link, hardLink] {
            XCTAssertThrowsError(try repo.exportSnapshot(to: target, protecting: [legacy]))
            XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)
            XCTAssertEqual(try Data(contentsOf: lock), lockOriginal)
            XCTAssertEqual(try Data(contentsOf: legacy), legacyOriginal)
        }
    }
    func testExportToCopyReadsLatestDiskAndPreservesActiveData() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let first = CountdownEvent(title: "原事件", targetDate: Date())
        let newer = CountdownEvent(title: "另一进程新增", targetDate: Date())
        try repo.save([first], replacing: [])
        _ = try repo.exportSnapshot()
        try repo.save([first, newer], replacing: [first])
        let original = try Data(contentsOf: repo.fileURL)
        let copyURL = repo.fileURL.deletingLastPathComponent().appendingPathComponent("backup.json")
        try repo.exportSnapshot(to: copyURL)
        XCTAssertEqual(try EventRepository(fileURL: copyURL).load(), [first, newer])
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)
    }
    func testImportAddsEventsWithoutChangingIDsDatesOrExistingEvents() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let current = CountdownEvent(title: "当前", targetDate: Date())
        let incoming = CountdownEvent(title: "备份", targetDate: date("2028-02-29T10:30:00Z"))
        try repo.save([current], replacing: [])
        let data = try backupData([incoming])
        XCTAssertEqual(try repo.importSnapshot(data, replacing: [current]), [current, incoming])
        XCTAssertEqual(try repo.load(), [current, incoming])
    }
    func testImportIdenticalBackupTwiceDoesNotRewriteOrDuplicate() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let event = CountdownEvent(title: "原事件", targetDate: Date())
        let data = try backupData([event])
        XCTAssertEqual(try repo.importSnapshot(data, replacing: []), [event])
        guard FileManager.default.fileExists(atPath: repo.fileURL.path) else { return }
        let original = try Data(contentsOf: repo.fileURL)
        XCTAssertEqual(try repo.importSnapshot(data, replacing: [event]), [event])
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)
        let beforeEmpty = try Data(contentsOf: repo.fileURL)
        XCTAssertEqual(try repo.importSnapshot(backupData([]), replacing: [event]), [event])
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), beforeEmpty)
    }
    func testImportConflictRejectsEntireBackupIncludingEarlierNewEvent() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let current = CountdownEvent(title: "当前版本", targetDate: Date())
        var conflict = current; conflict.title = "旧版本"
        let new = CountdownEvent(title: "不应部分导入", targetDate: Date())
        try repo.save([current], replacing: [])
        let original = try Data(contentsOf: repo.fileURL)
        XCTAssertThrowsError(try repo.importSnapshot(backupData([new, conflict]), replacing: [current]))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)
    }
    func testImportInvalidDataPreservesDestination() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let event = CountdownEvent(title: "保留", targetDate: Date())
        try repo.save([event], replacing: [])
        let original = try Data(contentsOf: repo.fileURL)
        let blank = CountdownEvent(title: "  ", targetDate: Date())
        for data in [Data("not json".utf8), try backupData([], version: 99), try backupData([event, event]), try backupData([blank])] {
            XCTAssertThrowsError(try repo.importSnapshot(data, replacing: [event]))
            XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)
        }
    }
    func testImportStaleBaselineAndCorruptDestinationNeverOverwrite() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let event = CountdownEvent(title: "另一进程新增", targetDate: Date())
        try repo.save([event], replacing: [])
        let original = try Data(contentsOf: repo.fileURL)
        XCTAssertThrowsError(try repo.importSnapshot(backupData([]), replacing: []))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: repo.fileURL)
        XCTAssertThrowsError(try repo.importSnapshot(backupData([event]), replacing: []))
        XCTAssertThrowsError(try repo.exportSnapshot())
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), corrupt)
    }
    func testImportBusyLockAndUnwritableDestinationArePreserved() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let event = CountdownEvent(title: "原事件", targetDate: Date())
        try repo.save([event], replacing: [])
        let original = try Data(contentsOf: repo.fileURL)
        let fd = Darwin.open(repo.fileURL.path + ".lock", O_RDWR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { Darwin.close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try repo.importSnapshot(backupData([]), replacing: [event]))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)
        let blocked = EventRepository(fileURL: temporaryURL())
        try FileManager.default.createDirectory(at: blocked.fileURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try blocked.importSnapshot(backupData([event]), replacing: []))
    }
    func testCorruptLegacyIsNotMigratedAsEmpty() throws {
        let legacy = EventRepository(fileURL: temporaryURL())
        let shared = EventRepository(fileURL: temporaryURL())
        try FileManager.default.createDirectory(at: legacy.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("invalid-json".utf8)
        try original.write(to: legacy.fileURL)
        XCTAssertThrowsError(try shared.loadMigrating(from: legacy))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: legacy.fileURL), original)
    }
    func testCorruptSharedDataCannotBeReplacedByLegacy() throws {
        let legacy = EventRepository(fileURL: temporaryURL())
        let shared = EventRepository(fileURL: temporaryURL())
        try legacy.save([CountdownEvent(title: "旧数据", targetDate: Date())], replacing: [])
        try FileManager.default.createDirectory(at: shared.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("invalid-json".utf8)
        try original.write(to: shared.fileURL)
        XCTAssertThrowsError(try shared.loadMigrating(from: legacy))
        XCTAssertEqual(try Data(contentsOf: shared.fileURL), original)
    }

    func testStaleEditCannotOverwriteAnotherWritersEvents() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let first = CountdownEvent(title: "原事件", targetDate: Date())
        let other = CountdownEvent(title: "另一进程新增", targetDate: Date())
        try repo.save([first], replacing: [])
        let stale = try repo.load()
        try repo.save([first, other], replacing: stale)
        let latest = try Data(contentsOf: repo.fileURL)
        var edited = first
        edited.title = "旧窗口的修改"
        XCTAssertThrowsError(try repo.save([edited], replacing: stale))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), latest)
    }
    func testStaleDeleteCannotEraseAnotherWritersEdit() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        var event = CountdownEvent(title: "原事件", targetDate: Date())
        try repo.save([event], replacing: [])
        let stale = try repo.load()
        event.title = "最新名称"
        try repo.save([event], replacing: stale)
        XCTAssertThrowsError(try repo.save([], replacing: stale))
        XCTAssertEqual(try repo.load().first?.title, "最新名称")
    }
    func testStaleFirstSaveCannotEraseNewFile() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let newer = CountdownEvent(title: "新文件", targetDate: Date())
        try repo.save([newer], replacing: [])
        XCTAssertThrowsError(try repo.save([], replacing: []))
        XCTAssertEqual(try repo.load(), [newer])
    }
    func testDeletedFileIsNotRecreatedFromStaleList() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        let event = CountdownEvent(title: "原事件", targetDate: Date())
        try repo.save([event], replacing: [])
        try FileManager.default.removeItem(at: repo.fileURL)
        XCTAssertThrowsError(try repo.save([event], replacing: [event]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.fileURL.path))
    }
    func testBusyWriterDoesNotOverwriteOrBlock() throws {
        let repo = EventRepository(fileURL: temporaryURL())
        try repo.save([], replacing: [])
        let initial = try Data(contentsOf: repo.fileURL)
        let fd = Darwin.open(repo.fileURL.path + ".lock", O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { Darwin.close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        let started = Date()
        XCTAssertThrowsError(try repo.save([CountdownEvent(title: "新增", targetDate: Date())], replacing: []))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), initial)
        XCTAssertEqual(flock(fd, LOCK_UN), 0)
        try repo.save([CountdownEvent(title: "锁释放后保存", targetDate: Date())], replacing: [])
        XCTAssertEqual(try repo.load().first?.title, "锁释放后保存")
    }

}
