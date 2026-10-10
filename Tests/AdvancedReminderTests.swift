import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class AdvancedReminderTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testCustomReminderUsesCalendarDaysAcrossDST() throws {
        var event = CountdownEvent(title: "Custom", targetDate: date("2026-03-09T17:00:00-07:00"), reminder: .custom)
        event.reminderDaysBefore = 2; event.reminderTime = CalendarTime(hour: 8, minute: 45)
        let request = ReminderPolicy.plan(events: [event], now: date("2026-03-01T00:00:00Z"), timeZone: zone).requests.first!
        XCTAssertEqual(request.fireDate, date("2026-03-07T08:45:00-08:00"))
        XCTAssertEqual(request.daysBefore, 2)
        XCTAssertEqual(try event.validated(now: Date()).reminderTime, event.reminderTime)
    }
    func testCustomAnnualPassedTimeRollsForward() {
        var event = CountdownEvent(title: "Year", targetDate: date("2024-10-10T17:00:00Z"), repeatYearly: true, reminder: .custom)
        event.reminderDaysBefore = 7; event.reminderTime = CalendarTime(hour: 9, minute: 0)
        let plan = ReminderPolicy.plan(events: [event], now: date("2026-10-08T00:00:00Z"), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(plan.requests.first?.fireDate, date("2027-10-03T09:00:00Z"))
        XCTAssertEqual(plan.requests.count, 8)
    }
    func testCustomValidationAndRoundTrip() throws {
        var event = CountdownEvent(title: "Custom", targetDate: Date(), reminder: .custom)
        XCTAssertThrowsError(try event.validated(now: Date()))
        event.reminderTime = CalendarTime(hour: 9, minute: 0); event.reminderDaysBefore = 366
        XCTAssertThrowsError(try event.validated(now: Date()))
        event.reminderDaysBefore = 365
        let data = try EventRepository.encodeSnapshot([event])
        XCTAssertEqual(try EventRepository.decodeSnapshot(data).first, event)
        let legacy = CountdownEvent(title: "Legacy", targetDate: Date(), reminder: .dayBefore)
        XCTAssertEqual(try EventRepository.decodeSnapshot(EventRepository.encodeSnapshot([legacy])).first?.reminder, .dayBefore)
    }
}
