import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class RecurringReminderTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testDailyBodyChangesForEachDeliveryDate() {
        var event = CountdownEvent(title: "Launch", targetDate: date("2026-10-12T15:00:00Z"))
        event.dailyReminderTime = CalendarTime(hour: 9, minute: 0)
        let daily = ReminderPolicy.plan(events: [event], now: date("2026-10-09T10:00:00Z"), timeZone: utc).requests.filter { $0.cadence == .daily }
        XCTAssertEqual(daily[0].fireDate, date("2026-10-10T09:00:00Z"))
        XCTAssertEqual(daily[0].body, DayCounter.snapshot(event: event, now: daily[0].fireDate, timeZone: utc).summary(for: event))
        XCTAssertNotEqual(daily[0].body, daily[1].body)
        XCTAssertTrue(daily.contains { $0.fireDate == date("2026-10-13T09:00:00Z") && $0.body.contains("1") })
        XCTAssertTrue(event.hasEnabledReminders)
    }
    func testMonthEndUsesOriginalAnchorWithoutDrift() {
        var event = CountdownEvent(title: "Start", targetDate: date("2026-01-31T18:00:00Z"))
        event.monthlyReminderTime = CalendarTime(hour: 10, minute: 30)
        let monthly = ReminderPolicy.plan(events: [event], now: date("2026-02-01T00:00:00Z"), timeZone: utc).requests.filter { $0.cadence == .monthly }
        XCTAssertEqual(monthly.count, ReminderPolicy.monthlyOccurrences)
        XCTAssertEqual(monthly[0].fireDate, date("2026-02-28T10:30:00Z"))
        XCTAssertEqual(monthly[1].fireDate, date("2026-03-31T10:30:00Z"))
        XCTAssertEqual(monthly[0].body, L10n.format("今天是第 %ld 个月纪念日。", 1))
        XCTAssertEqual(monthly[1].body, L10n.format("今天是第 %ld 个月纪念日。", 2))
    }
    func testLeapAnniversariesRecoverLeapDayAndDoNotCountYearZero() {
        var event = CountdownEvent(title: "Leap", targetDate: date("2024-02-29T18:00:00Z"))
        event.yearlyReminderTime = CalendarTime(hour: 9, minute: 15)
        let yearly = ReminderPolicy.plan(events: [event], now: date("2024-02-01T00:00:00Z"), timeZone: utc).requests.filter { $0.cadence == .yearly }
        XCTAssertEqual(yearly.count, ReminderPolicy.annualOccurrences)
        XCTAssertEqual(yearly[0].fireDate, date("2025-02-28T09:15:00Z"))
        XCTAssertEqual(yearly[3].fireDate, date("2028-02-29T09:15:00Z"))
        XCTAssertEqual(yearly[0].body, L10n.format("今天是第 %ld 周年纪念日。", 1))
    }
    func testQueueReservesNextRequestForEveryEnabledCadence() {
        var event = CountdownEvent(title: "Both", targetDate: date("2026-01-10T12:00:00Z"))
        event.dailyReminderTime = CalendarTime(hour: 9, minute: 0)
        event.monthlyReminderTime = CalendarTime(hour: 10, minute: 0)
        event.yearlyReminderTime = CalendarTime(hour: 11, minute: 0)
        let plan = ReminderPolicy.plan(events: [event], now: date("2026-10-09T00:00:00Z"), timeZone: utc, maximumRequests: 3)
        XCTAssertEqual(Set(plan.requests.map(\.cadence)), [.daily, .monthly, .yearly])
        XCTAssertEqual(Set(plan.requests.map(\.identifier)).count, 3)
        event.lifecycle = .archived
        XCTAssertTrue(ReminderPolicy.plan(events: [event], now: date("2026-10-09T00:00:00Z"), timeZone: utc).requests.isEmpty)
    }
    func testDailyWallTimeAcrossDSTAndMissedToday() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var event = CountdownEvent(title: "DST", targetDate: date("2026-06-01T00:00:00Z"))
        event.dailyReminderTime = CalendarTime(hour: 9, minute: 0)
        let daily = ReminderPolicy.plan(events: [event], now: date("2026-03-07T10:00:00-08:00"), timeZone: zone).requests.filter { $0.cadence == .daily }
        XCTAssertEqual(daily[0].fireDate, date("2026-03-08T09:00:00-07:00"))
        XCTAssertEqual(daily[1].fireDate, date("2026-03-09T09:00:00-07:00"))
        XCTAssertTrue(daily[0].followsDeviceTimeZone)
    }
    func testRecurringPersistenceValidationAndLegacyDefaults() throws {
        var event = CountdownEvent(title: "Store", targetDate: Date())
        event.dailyReminderTime = CalendarTime(hour: 8, minute: 30)
        event.monthlyReminderTime = CalendarTime(hour: 10, minute: 0)
        XCTAssertEqual(try EventRepository.decodeSnapshot(EventRepository.encodeSnapshot([event])), [event])
        event.yearlyReminderTime = CalendarTime(hour: 24, minute: 0)
        XCTAssertThrowsError(try event.validated(now: Date()))
        let data = Data("{\"schemaVersion\":1,\"events\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"Old\",\"targetDate\":800000000,\"createdAt\":800000000,\"updatedAt\":800000000,\"symbol\":\"calendar\",\"colorKey\":\"sage\"}]}".utf8)
        let old = try EventRepository.decodeSnapshot(data)[0]
        XCTAssertFalse(old.hasEnabledReminders)
        XCTAssertNil(old.dailyReminderTime)
    }
}
