import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class ShortcutRepositoryTests: XCTestCase {
    private var directory: URL!
    private var source: URL!
    private var repository: EventRepository { EventRepository(fileURL: source) }
    private var shortcuts: ShortcutEventRepository { ShortcutEventRepository(repository: repository) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayDistanceShortcuts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("events.json")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func event(_ title: String = "Same title", lifecycle: EventLifecycle = .active) -> CountdownEvent {
        CountdownEvent(title: title, targetDate: Date(timeIntervalSince1970: 1800000000), lifecycle: lifecycle,
                       trashedAt: lifecycle == .trashed ? Date() : nil)
    }

    func testChoicesPreserveDuplicateTitlesAndDatesUsingDistinctUUIDs() throws {
        let first = event(), second = event(), archived = event(lifecycle: .archived), trashed = event(lifecycle: .trashed)
        try repository.save([first, archived, second, trashed], replacing: [])
        let bytes = try Data(contentsOf: source)
        let choices = try shortcuts.activeEvents()
        XCTAssertEqual(Set(choices.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(try shortcuts.activeEvent(identifier: first.id.uuidString), first)
        XCTAssertEqual(try shortcuts.activeEvent(identifier: second.id.uuidString), second)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("backups").path))
    }

    func testMissingInactiveAndMalformedIdentifiersDoNotFallBack() throws {
        let archived = event(lifecycle: .archived), trashed = event(lifecycle: .trashed)
        try repository.save([event("Active"), archived, trashed], replacing: [])
        XCTAssertThrowsError(try shortcuts.activeEvent(identifier: UUID().uuidString)) {
            guard case ShortcutEventError.missingEvent = $0 else { return XCTFail("Expected missing event, got \($0)") }
        }
        for value in [archived, trashed] {
            XCTAssertThrowsError(try shortcuts.activeEvent(identifier: value.id.uuidString)) {
                guard case ShortcutEventError.inactiveEvent = $0 else { return XCTFail("Expected inactive event, got \($0)") }
            }
        }
        XCTAssertThrowsError(try shortcuts.activeEvent(identifier: "not-a-uuid")) {
            guard case ShortcutEventError.invalidIdentifier = $0 else { return XCTFail("Expected invalid identifier, got \($0)") }
        }
    }

    func testColdMissingFileIsReadOnlyAndCreatesNoLockOrContainer() throws {
        source = directory.appendingPathComponent("missing/events.json")
        XCTAssertEqual(try shortcuts.activeEvents(), [])
        XCTAssertThrowsError(try shortcuts.activeEvent(identifier: UUID().uuidString))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.deletingLastPathComponent().path))
    }

    func testCorruptOrNewerSchemaReadThrowsWithoutChangingAnyBytes() throws {
        for value in [Data("corrupt".utf8), Data("{\"schemaVersion\":999,\"events\":[]}".utf8)] {
            try value.write(to: source)
            XCTAssertThrowsError(try shortcuts.activeEvents())
            XCTAssertThrowsError(try shortcuts.activeEvent(identifier: UUID().uuidString))
            XCTAssertEqual(try Data(contentsOf: source), value)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path + ".lock"))
        }
    }

    func testRenamedEventStillResolvesByOriginalUUIDAndLatestDiskSnapshot() throws {
        let first = event("Before")
        try repository.save([first], replacing: [])
        var renamed = first; renamed.title = "After"
        try repository.save([renamed], replacing: [first])
        XCTAssertEqual(try shortcuts.activeEvent(identifier: first.id.uuidString).title, "After")
    }

    func testDeepLinkContainsExactlyTheSelectedUUID() {
        let id = UUID()
        let url = ShortcutEventRepository.openURL(for: id)
        XCTAssertEqual(url.scheme, "daydistance")
        XCTAssertEqual(url.host, "event")
        XCTAssertEqual(url.path, "/" + id.uuidString)
        XCTAssertNil(url.query)
    }
}
