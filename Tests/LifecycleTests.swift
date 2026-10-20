import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class LifecycleTests: XCTestCase {
    func testLegacyDefaultsAndSchemaRoundTrip() throws {
        let event = CountdownEvent(title: "Legacy", targetDate: Date())
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        for key in ["lifecycle", "trashedAt", "wasArchivedBeforeTrash"] { fields.removeValue(forKey: key) }
        let legacy = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "events": [fields]])
        XCTAssertTrue(try EventRepository.decodeSnapshot(legacy)[0].isActive)
        var trash = event; trash.lifecycle = .trashed; trash.trashedAt = Date(); trash.wasArchivedBeforeTrash = true
        XCTAssertEqual(try EventRepository.decodeSnapshot(EventRepository.encodeSnapshot([trash])), [trash])
        XCTAssertThrowsError(try EventRepository.decodeSnapshot(Data("{\"schemaVersion\":10,\"events\":[]}".utf8)))
    }
    func testInactiveExcludedFromAutomaticAndExplicitWidgets() {
        let now = Date()
        let active = CountdownEvent(title: "Active", targetDate: now.addingTimeInterval(500))
        var archived = active; archived.id = UUID(); archived.lifecycle = .archived; archived.isPinned = true
        var trash = active; trash.id = UUID(); trash.lifecycle = .trashed; trash.trashedAt = now
        XCTAssertEqual(WidgetPolicy.sorted(events: [archived, trash, active], now: now), [active])
        XCTAssertEqual(WidgetPolicy.selection(events: [archived, active], explicitID: archived.id.uuidString, now: now), .missing)
        XCTAssertEqual(WidgetPolicy.sorted(events: [archived, trash, active], now: now, includingInactive: true).count, 3)
    }
    func testInactiveRemindersAreNotScheduled() {
        let now = Date()
        var event = CountdownEvent(title: "Reminder", targetDate: now.addingTimeInterval(3600), reminder: .onDay)
        XCTAssertEqual(ReminderPolicy.plan(events: [event], now: now).requests.count, 1)
        event.lifecycle = .archived
        XCTAssertTrue(ReminderPolicy.plan(events: [event], now: now).requests.isEmpty)
        event.lifecycle = .trashed; event.trashedAt = now
        XCTAssertTrue(ReminderPolicy.plan(events: [event], now: now).requests.isEmpty)
    }
    func testTrashWithoutValidDateRejected() throws {
        let trash = CountdownEvent(title: "Invalid", targetDate: Date(), lifecycle: .trashed)
        XCTAssertThrowsError(try EventRepository.encodeSnapshot([trash]))
    }
}
