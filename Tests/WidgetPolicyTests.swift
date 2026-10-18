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

final class WidgetFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func item(_ days: Double, tags: [String] = [], pinned: Bool = false) -> CountdownEvent {
        CountdownEvent(title: "Event \(days)", targetDate: now.addingTimeInterval(days * 86400), isPinned: pinned, tags: tags)
    }
    func testTagsNormalizeAndRoundTrip() throws {
        let event = try item(1, tags: [" 工作 ", "work", "WORK", "", "旅行"]).validated(now: now)
        XCTAssertEqual(event.tags, ["工作", "work", "旅行"])
        let encoded = try EventRepository.encodeSnapshot([event])
        XCTAssertEqual(try EventRepository.decodeSnapshot(encoded), [event])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["schemaVersion"] = 6
        var entries = try XCTUnwrap(json["events"] as? [[String: Any]])
        entries[0].removeValue(forKey: "tags"); json["events"] = entries
        XCTAssertEqual(try EventRepository.decodeSnapshot(JSONSerialization.data(withJSONObject: json)).first?.tags, [])
        XCTAssertEqual(CountdownEvent.parseTags("工作，旅行; Work\nwork"), ["工作", "旅行", "Work"])
    }
    func testTagLimitsRejectInsteadOfDroppingData() throws {
        XCTAssertThrowsError(try item(1, tags: [String(repeating: "x", count: 41)]).validated(now: now))
        XCTAssertThrowsError(try item(1, tags: (0..<31).map(String.init)).validated(now: now))
    }
    func testDefaultFilterKeepsLegacyOrder() {
        let events = [item(-1), item(2), item(10, pinned: true)]
        XCTAssertEqual(WidgetFilter().apply(events: events, now: now), WidgetPolicy.sorted(events: events, now: now))
    }
    func testAllAnyExcludeAndSkipCombineInOrder() {
        let first = item(1, tags: ["工作", "会议"]), second = item(2, tags: ["工作", "会议"])
        let excluded = item(3, tags: ["工作", "会议", "私人"]), other = item(0.5, tags: ["工作"])
        var filter = WidgetFilter(includedTags: ["工作", "会议"], excludedTags: ["私人"], skip: 1)
        XCTAssertEqual(filter.apply(events: [excluded, other, second, first], now: now), [second])
        filter.tagMatch = .any; filter.skip = 0
        XCTAssertEqual(filter.apply(events: [first, other], now: now), [other, first])
        filter.includedTags = ["WORK"]
        XCTAssertEqual(filter.apply(events: [item(1, tags: ["work"])], now: now).count, 1)
    }
    func testDateScopesAndInactiveNeverLeak() {
        let past = item(-2), future = item(3)
        var archived = item(1); archived.lifecycle = .archived
        var trash = item(2); trash.lifecycle = .trashed
        XCTAssertEqual(WidgetFilter(scope: .upcoming).apply(events: [past, future, archived, trash], now: now), [future])
        XCTAssertEqual(WidgetFilter(scope: .past).apply(events: [past, future], now: now), [past])
    }
    func testNearestFarthestAndPinnedAreExplicit() {
        let past = item(-1), future = item(3), pinned = item(10, pinned: true)
        var filter = WidgetFilter(sort: .nearest, prioritizePinned: false)
        XCTAssertEqual(filter.apply(events: [future, pinned, past], now: now), [past, future, pinned])
        filter.prioritizePinned = true
        XCTAssertEqual(filter.apply(events: [future, past, pinned], now: now).first, pinned)
        filter.sort = .farthest; filter.prioritizePinned = false
        XCTAssertEqual(filter.apply(events: [past, future, pinned], now: now), [pinned, future, past])
    }
    func testSkipBoundsAndEmptyTagConditions() {
        let event = item(1)
        XCTAssertEqual(WidgetFilter(skip: -1).apply(events: [event], now: now), [event])
        XCTAssertTrue(WidgetFilter(skip: Int.max).apply(events: [event], now: now).isEmpty)
        XCTAssertEqual(WidgetFilter(includedTags: ["  "]).apply(events: [event], now: now), [event])
    }
    func testPaginationIsBoundedAndIndependent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetPageStore(directory: directory), first = UUID().uuidString, second = UUID().uuidString
        try store.save(page: 2, id: first, signature: "A")
        XCTAssertEqual(store.load(id: first, signature: "A"), 2)
        XCTAssertEqual(store.load(id: second, signature: "A"), 0)
        XCTAssertEqual(store.load(id: first, signature: "B"), 0)
        XCTAssertThrowsError(try store.save(page: 1, id: "../events", signature: "A"))
        let values = (1...13).map { item(Double($0)) }
        XCTAssertEqual(WidgetPage(events: values, page: 2, pageSize: 6).events, [values[12]])
        XCTAssertEqual(WidgetPage(events: values, page: Int.max, pageSize: 6).index, 2)
        XCTAssertEqual(WidgetPage(events: [], page: 99, pageSize: 0).count, 1)
        XCTAssertNotEqual(WidgetFilter().signature(pageSize: 6), WidgetFilter().signature(pageSize: 10))
    }
    func testPageIdentitySurvivesReloadAndConfigurationRoundTrip() throws {
        let filter = WidgetFilter(includedTags: ["Work"], sort: .nearest, prioritizePinned: false, skip: 1)
        let restored = try JSONDecoder().decode(WidgetFilter.self, from: JSONEncoder().encode(filter))
        let id = filter.pageIdentifier(pageSize: 6)
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(id, restored.pageIdentifier(pageSize: 6))
        XCTAssertNotEqual(id, filter.pageIdentifier(pageSize: 10))
        XCTAssertNotEqual(id, WidgetFilter().pageIdentifier(pageSize: 6))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetPageStore(directory: directory)
        try store.save(page: 2, id: id, signature: filter.signature(pageSize: 6))
        XCTAssertEqual(store.load(id: restored.pageIdentifier(pageSize: 6), signature: restored.signature(pageSize: 6)), 2)
    }

}
