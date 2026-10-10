import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class PublicFeatureTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testAllDayKeepsCalendarDateAcrossTimeZones() throws {
        var event = CountdownEvent(title: "全天", targetDate: date("2026-10-08T12:00:00+08:00"))
        event.isAllDay = true
        event.calendarDay = CalendarDay(year: 2026, month: 10, day: 8)
        for name in ["Asia/Shanghai", "America/Los_Angeles", "Europe/Berlin"] {
            let tz = TimeZone(identifier: name)!
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = tz
            let target = event.countdownDate(now: Date(), timeZone: tz)
            XCTAssertEqual(calendar.component(.day, from: target), 8)
            XCTAssertEqual(calendar.component(.hour, from: target), 0)
            XCTAssertFalse(DayCounter.snapshot(event: event, now: target.addingTimeInterval(3600), timeZone: tz).showsClock)
        }
    }
    func testYearlyKeepsOriginalAndTodayThroughEndOfDay() {
        var event = CountdownEvent(title: "纪念日", targetDate: date("2023-10-08T10:00:00+08:00"))
        event.repeatYearly = true
        event.calendarDay = CalendarDay(year: 2023, month: 10, day: 8)
        event.annualTime = CalendarTime(hour: 10, minute: 0)
        let later = date("2026-10-08T22:00:00+08:00")
        XCTAssertEqual(event.countdownDate(now: later, timeZone: zone), date("2026-10-08T10:00:00+08:00"))
        XCTAssertEqual(DayCounter.snapshot(event: event, now: later, timeZone: zone).days, 0)
        XCTAssertFalse(DayCounter.snapshot(event: event, now: later, timeZone: zone).showsClock)
        XCTAssertEqual(event.countdownDate(now: date("2026-10-09T00:00:00+08:00"), timeZone: zone), date("2027-10-08T10:00:00+08:00"))
        XCTAssertEqual(event.targetDate, date("2023-10-08T10:00:00+08:00"))
    }
    func testLeapDayClampsAndResumesInLeapYear() {
        var event = CountdownEvent(title: "生日", targetDate: date("2024-02-29T09:00:00+08:00"))
        event.repeatYearly = true; event.isAllDay = true
        event.calendarDay = CalendarDay(year: 2024, month: 2, day: 29)
        XCTAssertEqual(event.countdownDate(now: date("2026-02-27T12:00:00+08:00"), timeZone: zone), date("2026-02-28T00:00:00+08:00"))
        XCTAssertEqual(event.countdownDate(now: date("2028-02-28T12:00:00+08:00"), timeZone: zone), date("2028-02-29T00:00:00+08:00"))
    }
    func testAnnualDoesNotOccurBeforeOriginalYear() {
        var event = CountdownEvent(title: "未来", targetDate: date("2030-02-10T09:00:00+08:00"))
        event.repeatYearly = true
        event.calendarDay = CalendarDay(year: 2030, month: 2, day: 10)
        event.annualTime = CalendarTime(hour: 9, minute: 0)
        XCTAssertEqual(event.countdownDate(now: date("2026-10-08T12:00:00+08:00"), timeZone: zone), event.targetDate)
    }
    func testPinnedPreservesExplicitWidgetSelection() {
        let now = Date()
        let normal = CountdownEvent(title: "最近", targetDate: now.addingTimeInterval(60))
        var pinned = CountdownEvent(title: "重要", targetDate: now.addingTimeInterval(86400))
        pinned.isPinned = true
        XCTAssertEqual(WidgetPolicy.selection(events: [normal, pinned], explicitID: nil, now: now), .event(pinned))
        XCTAssertEqual(WidgetPolicy.selection(events: [normal, pinned], explicitID: normal.id.uuidString, now: now), .event(normal))
    }
    func testInvalidCivilDateAndReminderRoundTrip() throws {
        var event = CountdownEvent(title: "日期", targetDate: Date())
        event.isAllDay = true; event.calendarDay = CalendarDay(year: 2026, month: 2, day: 30)
        XCTAssertThrowsError(try event.validated(now: Date()))
        event.calendarDay = CalendarDay(year: 2026, month: 2, day: 28)
        event.reminder = .dayBefore; event.isPinned = true; event.repeatYearly = true
        XCTAssertEqual(try JSONDecoder().decode(CountdownEvent.self, from: JSONEncoder().encode(event)), event)
    }
}
