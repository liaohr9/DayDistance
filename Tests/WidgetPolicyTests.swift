import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class WidgetPolicyTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z")!
    func event(_ seconds: TimeInterval, id: UUID = UUID()) -> CountdownEvent {
        CountdownEvent(id: id, title: "日子", targetDate: now.addingTimeInterval(seconds))
    }
    func testOverviewFutureThenMostRecentPast() {
        let a = event(3600), b = event(7200), c = event(-60), d = event(-120)
        XCTAssertEqual(WidgetPolicy.sorted(events: [d,b,c,a], now: now).map(\.id), [a.id,b.id,c.id,d.id])
    }
    func testExplicitMissingEventStaysMissing() {
        XCTAssertEqual(WidgetPolicy.selection(events: [event(3600)], explicitID: UUID().uuidString, now: now), .missing)
    }
    func testDefaultAndEmptySelection() {
        let next = event(3600), previous = event(-60)
        XCTAssertEqual(WidgetPolicy.selection(events: [previous,next], explicitID: nil, now: now), .event(next))
        XCTAssertEqual(WidgetPolicy.selection(events: [], explicitID: nil, now: now), .empty)
    }
    func testExplicitSelectionAndMalformedID() {
        let value = event(-60)
        XCTAssertEqual(WidgetPolicy.selection(events: [value], explicitID: value.id.uuidString, now: now), .event(value))
        XCTAssertEqual(WidgetPolicy.selection(events: [value], explicitID: "bad", now: now), .missing)
    }
    func testSwitchSelectionWithDuplicateTitlesAndUpdatedDate() {
        var future = event(3600), past = event(-3600)
        future.title = "相同名字"
        past.title = "相同名字"
        let events = [future, past]
        XCTAssertEqual(WidgetPolicy.selection(events: events, explicitID: future.id.uuidString, now: now), .event(future))
        XCTAssertEqual(WidgetPolicy.selection(events: events, explicitID: past.id.uuidString, now: now), .event(past))
        past.title = "新名字"
        past.targetDate = now.addingTimeInterval(-7200)
        XCTAssertEqual(WidgetPolicy.selection(events: [future, past], explicitID: past.id.uuidString, now: now), .event(past))
        XCTAssertEqual(WidgetPolicy.selection(events: [future, past], explicitID: future.id.uuidString, now: now), .event(future))
    }
    func testTimelineContainsTargetAndMidnight() {
        let target = event(600)
        let dates = WidgetPolicy.timelineDates(events: [target], now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(dates.first, now)
        XCTAssertTrue(dates.contains(target.targetDate))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(12*3600)))
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
        XCTAssertLessThanOrEqual(dates.last!, now.addingTimeInterval(48*3600))
    }
    func testTimelineEntersPreciseCountdownBeforeMidnight() {
        let target = event(30*3600)
        let boundary = target.targetDate.addingTimeInterval(-86400+1)
        let dates = WidgetPolicy.timelineDates(events: [target], now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(dates.contains(boundary))
        XCTAssertLessThan(DayCounter.snapshot(target: target.targetDate, now: boundary, timeZone: TimeZone(secondsFromGMT: 0)!).seconds, 86400)
    }
    func testTimelineLeavesPreciseElapsedWindow() {
        let target = event(-23*3600)
        let boundary = target.targetDate.addingTimeInterval(86400)
        let dates = WidgetPolicy.timelineDates(events: [target], now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(dates.contains(boundary))
        XCTAssertEqual(DayCounter.snapshot(target: target.targetDate, now: boundary, timeZone: TimeZone(secondsFromGMT: 0)!).seconds, 86400)
    }
    func testTimelineLimitsManyTargetsAndIgnoresPast() {
        let events = (1...100).map { event(TimeInterval($0*60)) } + [event(-60)]
        let dates = WidgetPolicy.timelineDates(events: events, now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(dates.count, 64)
        XCTAssertFalse(dates.contains(now.addingTimeInterval(-60)))
    }
}
