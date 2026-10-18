import XCTest
@testable import DayDistanceCore
final class SmartListTests: XCTestCase {
    func testEmptyAndNormalizedRules() throws {
        let event = CountdownEvent(title: "Café", targetDate: Date(), tags: ["École"])
        XCTAssertEqual(SmartList().evaluate(events: [event], now: Date()).events.count, 1)
        let rule = SmartRule(field: .title, text: " cafe ")
        XCTAssertEqual(SmartList(rules: [rule]).evaluate(events: [event], now: Date()).events.count, 1)
        XCTAssertThrowsError(try SmartRule(field: .pinned, comparison: .contains).validated())
    }
    func testSignatureIgnoresEditorialIdentity() {
        let a = SmartList(name: "One", rules: [SmartRule(text: "École")])
        let b = SmartList(name: "Two", rules: [SmartRule(text: "ecole")])
        XCTAssertEqual(a.signature(pageSize: 5), b.signature(pageSize: 5))
    }
}
extension SmartListTests {
    private var zone: TimeZone { TimeZone(secondsFromGMT: 0)! }
    private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testCalendarStatesDistanceAndInactive() {
        let now = instant("2026-10-18T23:00:00Z")
        let events = [-1,0,1].map { offset in CountdownEvent(title: "\(offset)", targetDate: now.addingTimeInterval(Double(offset) * 86400), includesStartDay: true) }
        for state in [SmartDateState.past, .today, .future] {
            let list = SmartList(rules: [SmartRule(field: .dateState, comparison: .equals, dateState: state)])
            XCTAssertEqual(list.evaluate(events: events, now: now, timeZone: zone).events.count, 1)
        }
        let distance = SmartList(rules: [SmartRule(field: .dayDistance, comparison: .equals, number: 1)])
        XCTAssertEqual(distance.evaluate(events: events, now: now, timeZone: zone).events.count, 2)
        var inactive = events[0]; inactive.lifecycle = .archived
        XCTAssertTrue(SmartList(match: .any).evaluate(events: [inactive], now: now).events.isEmpty)
        XCTAssertEqual(SmartList(match: .any).evaluate(events: events, now: now).events.count, 3)
    }
    func testAllAnyTagAndRange() {
        let now = instant("2026-10-18T12:00:00Z")
        let event = CountdownEvent(title: "Café", targetDate: now, tags: ["ÉCOLE"])
        let rules = [SmartRule(text: "ecole"), SmartRule(field: .title, text: "absent")]
        XCTAssertTrue(SmartList(rules: rules).evaluate(events: [event], now: now).events.isEmpty)
        XCTAssertEqual(SmartList(match: .any, rules: rules).evaluate(events: [event], now: now).events.count, 1)
        let day = CalendarDay(year: 2026, month: 10, day: 18)
        let range = SmartList(rules: [SmartRule(field: .targetDate, comparison: .between, date: day, endDate: day)])
        XCTAssertEqual(range.evaluate(events: [event], now: now, timeZone: zone).events.count, 1)
    }
    func testYearlyLeapDayAndSortSkip() {
        let now = instant("2025-02-28T12:00:00Z")
        let leap = CountdownEvent(title: "Leap", targetDate: instant("2024-02-29T00:00:00Z"), isAllDay: true, calendarDay: CalendarDay(year: 2024, month: 2, day: 29), repeatYearly: true)
        XCTAssertEqual(SmartList(rules: [SmartRule(field: .dateState, comparison: .equals, dateState: .today)]).evaluate(events: [leap], now: now, timeZone: zone).events.count, 1)
        let pinned = CountdownEvent(title: "Pinned", targetDate: now.addingTimeInterval(86400 * 5), isPinned: true)
        let near = CountdownEvent(title: "Near", targetDate: now.addingTimeInterval(86400))
        let result = SmartList(prioritizePinned: true, skip: 1).evaluate(events: [near,pinned,leap], now: now, timeZone: zone)
        XCTAssertEqual(result.matching.count, 3)
        XCTAssertEqual(result.events.first?.id, leap.id)
    }
    func testValidationBoundsAndPageIdentity() throws {
        XCTAssertThrowsError(try SmartList(name: " ").validated())
        XCTAssertThrowsError(try SmartRule(field: .dayDistance, comparison: .equals, number: -1).validated())
        XCTAssertThrowsError(try SmartRule(date: CalendarDay(year: 2025, month: 2, day: 29)).validated())
        XCTAssertThrowsError(try SmartRule(field: .targetDate, comparison: .between, date: CalendarDay(year: 2026, month: 1, day: 2), endDate: CalendarDay(year: 2026, month: 1, day: 1)).validated())
        XCTAssertThrowsError(try SmartList(name: "x", skip: 1000000).validated())
        let list = SmartList(name: "x")
        XCTAssertNotNil(UUID(uuidString: list.pageIdentifier(pageSize: 5)))
        XCTAssertNotEqual(list.pageIdentifier(pageSize: 5), list.pageIdentifier(pageSize: 10))
    }
}

extension SmartListTests {
    func testTitleSortUsesNativeNaturalOrder() {
        let now = Date()
        let events = ["Event 10", "Event 2"].map { CountdownEvent(title: $0, targetDate: now) }
        XCTAssertEqual(SmartList(sort: .title).evaluate(events: events, now: now).events.map(\.title), ["Event 2", "Event 10"])
    }
}

extension SmartListTests {
    func testDistanceSortSchedulesTheNextCrossingIncludingSkippedResults() {
        let now = instant("2026-10-18T11:00:00Z")
        let earlier = CountdownEvent(title: "Earlier", targetDate: instant("2026-10-18T10:00:00Z"))
        let later = CountdownEvent(title: "Later", targetDate: instant("2026-10-18T14:00:00Z"))
        for sort in [WidgetSort.nearest, .farthest] {
            let list = SmartList(sort: sort, skip: 1)
            let next = list.nextUpdate(events: [earlier,later], after: now, timeZone: zone)
            XCTAssertEqual(next.timeIntervalSince1970, instant("2026-10-18T12:00:00Z").timeIntervalSince1970 + 0.001, accuracy: 0.0001)
            XCTAssertNotEqual(list.evaluate(events: [earlier,later], now: now, timeZone: zone).events.first?.id,
                              list.evaluate(events: [earlier,later], now: next, timeZone: zone).events.first?.id)
            XCTAssertGreaterThan(list.nextUpdate(events: [earlier,later], after: next, timeZone: zone), next)
        }
        let midpoint = instant("2026-10-18T12:00:00Z")
        XCTAssertEqual(SmartList(sort: .nearest).nextUpdate(events: [earlier,later], after: midpoint, timeZone: zone), midpoint.addingTimeInterval(0.001))
        XCTAssertEqual(SmartList(sort: .title).nextUpdate(events: [earlier,later], after: now, timeZone: zone), later.targetDate)
    }
}
