import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class ReminderPolicyTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testDisabledReminderDoesNotSchedule() {
        let event = CountdownEvent(title: "没有提醒", targetDate: date("2026-10-10T18:15:00+08:00"))
        XCTAssertTrue(ReminderPolicy.plan(events: [event], now: date("2026-10-08T00:00:00+08:00")).requests.isEmpty)
    }

    func testTimedReminderAndDayBeforeUseLocalWallTime() {
        var event = CountdownEvent(title: "定时", targetDate: date("2026-10-10T18:15:00+08:00"), reminder: .onDay)
        let now = date("2026-10-08T00:00:00+08:00")
        XCTAssertEqual(ReminderPolicy.plan(events: [event], now: now, timeZone: shanghai).requests.first?.fireDate, event.targetDate)
        event.reminder = .dayBefore
        XCTAssertEqual(ReminderPolicy.plan(events: [event], now: now, timeZone: shanghai).requests.first?.fireDate,
                       date("2026-10-09T18:15:00+08:00"))
    }

    func testAllDayReminderUsesNineAMInSelectedTimeZone() {
        let event = CountdownEvent(title: "全天", targetDate: date("2026-10-10T00:00:00+08:00"),
                                   isAllDay: true, calendarDay: CalendarDay(year: 2026, month: 10, day: 10), reminder: .onDay)
        let now = date("2026-10-08T00:00:00Z")
        for zone in [shanghai, TimeZone(identifier: "America/Los_Angeles")!] {
            let result = ReminderPolicy.plan(events: [event], now: now, timeZone: zone)
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.requests[0].fireDate)
            XCTAssertEqual(components.year, 2026); XCTAssertEqual(components.month, 10); XCTAssertEqual(components.day, 10)
            XCTAssertEqual(components.hour, 9); XCTAssertEqual(components.minute, 0)
        }
    }

    func testDayBeforeDSTUsesCalendarDayNot24Hours() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        for (target, previous, interval) in [("2026-03-08T12:00:00-07:00", "2026-03-07T12:00:00-08:00", 82800.0),
                                             ("2026-11-01T12:00:00-08:00", "2026-10-31T12:00:00-07:00", 90000.0)] {
            let event = CountdownEvent(title: "DST", targetDate: date(target), reminder: .dayBefore)
            let plan = ReminderPolicy.plan(events: [event], now: date("2026-01-01T00:00:00Z"), timeZone: zone)
            XCTAssertEqual(plan.requests.first?.fireDate, date(previous))
            XCTAssertEqual(event.targetDate.timeIntervalSince(plan.requests[0].fireDate), interval)
        }
    }

    func testAnnualSchedulesEightFutureYearsAndClampsLeapDay() {
        let event = CountdownEvent(title: "闰日", targetDate: date("2024-02-29T00:00:00+08:00"), isAllDay: true,
                                   calendarDay: CalendarDay(year: 2024, month: 2, day: 29), repeatYearly: true, reminder: .onDay)
        let plan = ReminderPolicy.plan(events: [event], now: date("2026-01-01T00:00:00+08:00"), timeZone: shanghai)
        XCTAssertEqual(plan.requests.count, 8)
        XCTAssertEqual(plan.requests[0].fireDate, date("2026-02-28T09:00:00+08:00"))
        XCTAssertEqual(plan.requests[2].fireDate, date("2028-02-29T09:00:00+08:00"))
        XCTAssertTrue(plan.hasAnnualEvents)
        XCTAssertEqual(Set(plan.requests.map(\.identifier)).count, 8)
    }

    func testAnnualPassedReminderTodayRollsToFutureWithoutChangingEvent() {
        let event = CountdownEvent(title: "今天", targetDate: date("2024-10-08T08:30:00+08:00"), repeatYearly: true, reminder: .onDay)
        let plan = ReminderPolicy.plan(events: [event], now: date("2026-10-08T12:00:00+08:00"), timeZone: shanghai)
        XCTAssertEqual(plan.requests.count, 8)
        XCTAssertEqual(plan.requests[0].fireDate, date("2027-10-08T08:30:00+08:00"))
        XCTAssertEqual(event.targetDate, date("2024-10-08T08:30:00+08:00"))
    }

    func testAnnualDayBeforeAfterReminderTimeSchedulesFollowingYear() {
        let event = CountdownEvent(title: "明天", targetDate: date("2024-10-09T08:30:00+08:00"), repeatYearly: true, reminder: .dayBefore)
        let plan = ReminderPolicy.plan(events: [event], now: date("2026-10-08T12:00:00+08:00"), timeZone: shanghai)
        XCTAssertEqual(plan.requests.count, 8)
        XCTAssertEqual(plan.requests[0].fireDate, date("2027-10-08T08:30:00+08:00"))
    }

    func testPastNonRepeatingReminderIsExplicitlySkipped() {
        let event = CountdownEvent(title: "过去", targetDate: date("2026-10-08T08:30:00+08:00"), reminder: .onDay)
        let plan = ReminderPolicy.plan(events: [event], now: date("2026-10-08T12:00:00+08:00"), timeZone: shanghai)
        XCTAssertTrue(plan.requests.isEmpty)
        XCTAssertEqual(plan.pastEventCount, 1)
    }

    func testQueueCapKeepsEarliestSixtyAndReportsTruncation() {
        let events = (0..<9).map { index in
            CountdownEvent(title: "年度\(index)", targetDate: date("2024-10-\(10 + index)T08:30:00+08:00"), repeatYearly: true, reminder: .onDay)
        }
        let now = date("2026-10-08T00:00:00+08:00")
        let full = ReminderPolicy.plan(events: events, now: now, timeZone: shanghai, maximumRequests: 100)
        let capped = ReminderPolicy.plan(events: events.reversed(), now: now, timeZone: shanghai)
        XCTAssertEqual(full.requests.count, 72)
        XCTAssertEqual(capped.requests.count, 60)
        XCTAssertEqual(capped.truncatedRequestCount, 12)
        XCTAssertEqual(capped.requests, Array(full.requests.prefix(60)))
    }
    func testAnnualHorizonStopsAtLargestSupportedYear() {
        let event = CountdownEvent(title: "最晚年份", targetDate: date("9999-10-10T09:00:00Z"),
                                   calendarDay: CalendarDay(year: 9999, month: 10, day: 10), repeatYearly: true, reminder: .onDay)
        let plan = ReminderPolicy.plan(events: [event], now: date("9998-01-01T00:00:00Z"), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(plan.requests.count, 1)
        XCTAssertEqual(plan.requests[0].fireDate, date("9999-10-10T09:00:00Z"))
    }

    func testZeroAnnualHorizonSchedulesNothing() {
        let event = CountdownEvent(title: "年度", targetDate: date("2026-10-10T09:00:00Z"), repeatYearly: true, reminder: .onDay)
        XCTAssertTrue(ReminderPolicy.plan(events: [event], now: date("2026-01-01T00:00:00Z"), annualOccurrences: 0).requests.isEmpty)
    }

}
