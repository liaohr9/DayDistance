import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class EventExpirationTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func once(_ value: String) -> CountdownEvent {
        var event = CountdownEvent(title: "Once", targetDate: date(value))
        event.afterDate = .trash
        return event
    }
    func testOldDataAndNewEventsKeepOriginalDateByDefault() throws {
        let event = CountdownEvent(title: "Memory", targetDate: date("2020-01-01T12:00:00Z"))
        XCTAssertEqual(event.afterDate, .keep)
        XCTAssertNil(event.automaticTrashDate(timeZone: utc))
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        fields.removeValue(forKey: "afterDate")
        for schema in 1...7 {
            let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": schema, "events": [fields]])
            XCTAssertEqual(try EventRepository.decodeSnapshot(data).first?.afterDate, .keep)
        }
    }
    func testTimedEventExpiresAtItsOriginalInstant() {
        let event = once("2026-10-20T18:00:00Z")
        let end = event.targetDate
        XCTAssertFalse(event.shouldAutomaticallyTrash(at: end.addingTimeInterval(-0.01), timeZone: utc))
        XCTAssertTrue(event.shouldAutomaticallyTrash(at: end, timeZone: utc))
        let moved = event.automaticallyTrashed(at: end, timeZone: utc)
        XCTAssertEqual(moved.lifecycle, .trashed)
        XCTAssertEqual(moved.trashedAt, end)
        XCTAssertEqual(moved.targetDate, event.targetDate)
        XCTAssertEqual(moved.automaticallyTrashed(at: end.addingTimeInterval(10), timeZone: utc), moved)
    }
    func testAllDayWaitsUntilFollowingLocalDayIncludingDST() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var event = once("2026-03-08T12:00:00-07:00")
        event.isAllDay = true; event.calendarDay = CalendarDay(year: 2026, month: 3, day: 8)
        let end = date("2026-03-09T00:00:00-07:00")
        XCTAssertEqual(event.automaticTrashDate(timeZone: zone), end)
        XCTAssertFalse(event.shouldAutomaticallyTrash(at: end.addingTimeInterval(-1), timeZone: zone))
        XCTAssertTrue(event.shouldAutomaticallyTrash(at: end, timeZone: zone))
    }
    func testArchivedAndYearlyEventsAreNeverAutomaticallyTrashed() {
        var event = once("2020-01-01T12:00:00Z")
        event.lifecycle = .archived
        XCTAssertFalse(event.shouldAutomaticallyTrash(at: Date(), timeZone: utc))
        event.lifecycle = .active; event.repeatYearly = true
        XCTAssertNil(event.automaticTrashDate(timeZone: utc))
        XCTAssertEqual(event.automaticallyTrashed(at: Date(), timeZone: utc), event)
    }
    func testWidgetsAndSmartListsHideExpiredEvenBeforeAppRuns() {
        let event = once("2026-10-20T18:00:00Z"), now = date("2026-10-21T00:00:00Z")
        XCTAssertTrue(WidgetPolicy.sorted(events: [event], now: now).isEmpty)
        XCTAssertTrue(WidgetFilter().apply(events: [event], now: now).isEmpty)
        XCTAssertEqual(WidgetPolicy.selection(events: [event], explicitID: event.id.uuidString, now: now), .missing)
        let manual = WidgetManualSelection(enabled: true, slotIDs: [event.id.uuidString])
        XCTAssertTrue(manual.resolvedSlots(events: [event], now: now).isEmpty)
        let list = SmartList(name: "All")
        XCTAssertTrue(list.evaluate(events: [event], now: now).events.isEmpty)
    }
    func testRemindersNeverContinueAfterOnceEventExpires() {
        var event = once("2026-10-21T18:00:00Z")
        event.dailyReminderTime = CalendarTime(hour: 9, minute: 0)
        event.monthlyReminderTime = CalendarTime(hour: 9, minute: 0)
        let now = date("2026-10-20T08:00:00Z")
        let plan = ReminderPolicy.plan(events: [event], now: now, timeZone: utc)
        XCTAssertEqual(plan.requests.count, 2)
        XCTAssertTrue(plan.requests.allSatisfy { $0.fireDate <= event.targetDate })
        XCTAssertTrue(ReminderPolicy.plan(events: [event], now: event.targetDate, timeZone: utc).requests.isEmpty)
    }
    func testAnniversaryStyleDoesNotTurnOriginalDateIntoYearlyRepeat() {
        var event = CountdownEvent(title: "Memory", targetDate: date("2023-06-10T12:00:00Z"))
        event.displayFormat = .anniversary
        let now = date("2026-10-20T12:00:00Z")
        XCTAssertEqual(event.countdownDate(now: now, timeZone: utc), event.targetDate)
        XCTAssertFalse(event.repeatYearly)
        XCTAssertTrue(EventDisplayFormatter.summary(event: event, now: now, timeZone: utc).contains(L10n.format("%ld 周年 · %@", 3, "")))
    }
}
