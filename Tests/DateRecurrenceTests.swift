import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class DateRecurrenceTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    // Decode as a client would, so old builds demonstrate missing recurrence behavior.
    private func event(_ kind: String, anchor: String = "2024-01-31T09:15:00Z", allDay: Bool = false) throws -> CountdownEvent {
        let anchorDate = date(anchor)
        let value = CountdownEvent(title: "Repeat", targetDate: anchorDate, isAllDay: allDay,
                                   calendarDay: CalendarDay(date: anchorDate, timeZone: utc),
                                   annualTime: CalendarTime(date: anchorDate, timeZone: utc), reminder: .onDay)
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        fields[kind] = true
        return try JSONDecoder().decode(CountdownEvent.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testMonthlyShortMonthRestoresOriginalDayInFollowingMonth() throws {
        let e = try event("repeatMonthly")
        for (now, expected) in [("2026-02-01T00:00:00Z", "2026-02-28T09:15:00Z"),
                                ("2026-03-01T00:00:00Z", "2026-03-31T09:15:00Z"),
                                ("2028-02-01T00:00:00Z", "2028-02-29T09:15:00Z"),
                                ("2026-04-01T00:00:00Z", "2026-04-30T09:15:00Z")] {
            XCTAssertEqual(e.occurrence(onOrAfter: date(now), timeZone: utc), date(expected))
        }
    }
    func testMonthlyKeepsOccurrenceThroughItsDayAndNeverPredatesAnchor() throws {
        let e = try event("repeatMonthly", anchor: "2026-01-31T09:15:00Z")
        XCTAssertEqual(e.occurrence(onOrAfter: date("2025-02-01T00:00:00Z"), timeZone: utc), e.targetDate)
        XCTAssertEqual(e.occurrence(onOrAfter: date("2026-02-28T23:59:00Z"), timeZone: utc), date("2026-02-28T09:15:00Z"))
        XCTAssertEqual(e.occurrence(onOrAfter: date("2026-03-01T00:00:00Z"), timeZone: utc), date("2026-03-31T09:15:00Z"))
    }
    func testDailyPreservesLocalWallTimeAcrossDST() throws {
        let e = try event("repeatDaily", anchor: "2026-03-07T09:15:00Z")
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(e.occurrence(onOrAfter: date("2026-03-08T00:00:00-08:00"), timeZone: zone), date("2026-03-08T09:15:00-07:00"))
        XCTAssertEqual(e.occurrence(onOrAfter: date("2026-03-09T00:00:00-07:00"), timeZone: zone), date("2026-03-09T09:15:00-07:00"))
    }
    func testDailyAllDayRollsAtMidnightAndNeverPredatesAnchor() throws {
        let e = try event("repeatDaily", anchor: "2026-10-20T09:15:00Z", allDay: true)
        XCTAssertEqual(e.occurrence(onOrAfter: date("2026-10-19T12:00:00Z"), timeZone: utc), date("2026-10-20T00:00:00Z"))
        XCTAssertEqual(e.occurrence(onOrAfter: date("2026-10-21T12:00:00Z"), timeZone: utc), date("2026-10-21T00:00:00Z"))
    }
    func testRepeatingEventsIgnoreAutoTrashAndInclusiveCounting() throws {
        for kind in ["repeatDaily", "repeatMonthly"] {
            var e = try event(kind); e.afterDate = .trash; e.includesStartDay = true
            XCTAssertNil(e.automaticTrashDate(timeZone: utc))
            XCTAssertTrue(e.isUpcoming(at: date("2026-02-01T00:00:00Z")))
            XCTAssertEqual(DayCounter.snapshot(event: e, now: date("2026-02-28T12:00:00Z"), timeZone: utc).days, 0)
        }
    }
    func testMonthlyReminderQueueUsesClampedDatesAndRestoresDay() throws {
        let e = try event("repeatMonthly")
        let plan = ReminderPolicy.plan(events: [e], now: date("2026-02-01T00:00:00Z"), timeZone: utc)
        XCTAssertEqual(plan.requests.count, 12)
        XCTAssertEqual(plan.requests.first?.fireDate, date("2026-02-28T09:15:00Z"))
        XCTAssertEqual(plan.requests.dropFirst().first?.fireDate, date("2026-03-31T09:15:00Z"))
        XCTAssertTrue(plan.requests.allSatisfy(\.followsDeviceTimeZone))
    }
    func testDailyCustomReminderLooksAheadAndKeepsQueueBounded() throws {
        var e = try event("repeatDaily")
        e.reminder = .custom; e.reminderDaysBefore = 365; e.reminderTime = CalendarTime(hour: 8, minute: 0)
        let plan = ReminderPolicy.plan(events: [e], now: date("2026-02-01T12:00:00Z"), timeZone: utc)
        XCTAssertEqual(plan.requests.count, 60)
        XCTAssertEqual(plan.requests.first?.fireDate, date("2026-02-02T08:00:00Z"))
        XCTAssertEqual(Set(plan.requests.map(\.identifier)).count, plan.requests.count)
    }
    func testOldSnapshotAndRoundTrip() throws {
        let e = CountdownEvent(title: "Legacy", targetDate: date("2024-01-31T09:15:00Z"))
        let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e))
        let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": 8, "events": [fields]])
        XCTAssertEqual(try EventRepository.decodeSnapshot(bytes).first?.countdownDate(now: Date(), timeZone: utc), e.targetDate)
        let repeated = try event("repeatMonthly")
        let copy = try XCTUnwrap(EventRepository.decodeSnapshot(EventRepository.encodeSnapshot([repeated])).first)
        XCTAssertEqual(copy.occurrence(onOrAfter: date("2026-02-01T00:00:00Z"), timeZone: utc), date("2026-02-28T09:15:00Z"))
    }
    func testConflictingRepeatFlagsAreRejected() throws {
        var e = try event("repeatMonthly"); e.repeatYearly = true
        XCTAssertThrowsError(try e.validated(now: Date()))
    }
    func testRepeatingDateNotificationsParticipateInRenewalAndReservation() throws {
        var e = try event("repeatDaily")
        XCTAssertTrue(e.hasRecurringReminders)
        let plan = ReminderPolicy.plan(events: [e], now: date("2026-02-01T00:00:00Z"), timeZone: utc)
        XCTAssertTrue(plan.requests.allSatisfy { $0.cadence != .once })
        e.reminder = .none
        XCTAssertFalse(e.hasRecurringReminders)
        XCTAssertFalse(e.hasEnabledReminders)
    }
    func testCLIHandlesDailyAndMonthlyOptions() throws {
        let parsed = try AutomationCLI.parse(["events", "create", "--title", "Daily", "--at", "2026-11-01T09:00:00Z", "--repeat-daily", "true", "--repeat-monthly", "false", "--request-id", "new"])
        XCTAssertEqual(parsed.arguments["repeatDaily"], .bool(true))
        XCTAssertEqual(parsed.arguments["repeatMonthly"], .bool(false))
    }
}
