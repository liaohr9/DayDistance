import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class DisplayFormatTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func event(_ target: String, format: EventDisplayFormat = .days, includesStart: Bool = false) -> CountdownEvent {
        CountdownEvent(title: "Format", targetDate: date(target), includesStartDay: includesStart, displayFormat: format)
    }
    private func duration(_ event: CountdownEvent, _ now: String, zone: TimeZone? = nil) -> String {
        EventDisplayFormatter.duration(event: event, now: date(now), timeZone: zone ?? utc)
    }
    private func plural(_ count: Int, _ unit: String) -> String {
        count == 1 ? L10n.text("1 \(unit)") : L10n.format("%ld \(unit)", count)
    }
    private func legacySnapshot(schema: Int) throws -> Data {
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event("2024-02-29T10:00:00Z"))) as! [String: Any]
        fields.removeValue(forKey: "displayFormat")
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": schema, "events": [fields]])
    }

    func testLegacySchemasDefaultToDaysAndNewEventsDefaultToDays() throws {
        XCTAssertEqual(event("2024-02-29T10:00:00Z").displayFormat, .days)
        for schema in 1...3 {
            let legacy = try EventRepository.decodeSnapshot(legacySnapshot(schema: schema))
            XCTAssertEqual(legacy.first?.displayFormat, .days)
        }
    }

    func testEveryFormatSurvivesValidationAndCurrentSchemaRoundTrip() throws {
        for format in EventDisplayFormat.allCases {
            let original = event("2024-02-29T10:00:00Z", format: format)
            XCTAssertEqual(try original.validated(now: original.updatedAt).displayFormat, format)
            let data = try EventRepository.encodeSnapshot([original])
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(json["schemaVersion"] as? Int, 8)
            XCTAssertEqual(try EventRepository.decodeSnapshot(data), [original])
        }
    }

    func testPreviousReaderRefusesNewSchema() throws {
        // Mirrors the v1.7 schema gate: an unknown field alone would be ignored.
        struct OldSchema: Decodable { let schemaVersion: Int }
        let data = try EventRepository.encodeSnapshot([event("2024-02-29T10:00:00Z", format: .calendar)])
        let schema = try JSONDecoder().decode(OldSchema.self, from: data)
        XCTAssertFalse((1...5).contains(schema.schemaVersion))
    }

    func testFutureSchemaIsRejectedBeforeUnknownFields() throws {
        let data = Data(#"{"schemaVersion":9,"events":[{"displayFormat":"future"}]}"#.utf8)
        XCTAssertThrowsError(try EventRepository.decodeSnapshot(data)) {
            guard case EventError.unsupportedVersion = $0 else { return XCTFail("Expected future-schema error, got \($0)") }
        }
    }

    func testInvalidDisplayEnumAndFutureImportPreserveData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = EventRepository(fileURL: folder.appendingPathComponent("events.json"))
        let original = event("2024-02-29T10:00:00Z")
        try repo.save([original], replacing: [])
        let bytes = try Data(contentsOf: repo.fileURL)
        var json = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        var fields = (json["events"] as! [[String: Any]])[0]
        fields["displayFormat"] = "unrecognized"
        json["events"] = [fields]
        let invalid = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try EventRepository.decodeSnapshot(invalid))
        for incoming in [invalid, Data(#"{"schemaVersion":9,"events":[]}"#.utf8)] {
            XCTAssertThrowsError(try repo.importSnapshot(incoming, replacing: [original]))
            XCTAssertEqual(try Data(contentsOf: repo.fileURL), bytes)
        }
    }

    func testDefaultSummaryExactlyPreservesDayCounter() {
        for now in ["2026-10-01T12:00:00Z", "2026-10-09T08:00:00Z", "2026-10-09T18:00:00Z", "2026-10-17T12:00:00Z"] {
            for includes in [false, true] {
                let value = event("2026-10-09T12:00:00Z", includesStart: includes)
                XCTAssertEqual(EventDisplayFormatter.summary(event: value, now: date(now), timeZone: utc),
                               DayCounter.snapshot(event: value, now: date(now), timeZone: utc).summary(for: value))
            }
        }
    }

    func testWeeksUsesActualDayQuotientAndRemainder() {
        let value = event("2026-10-16T12:00:00Z", format: .weeks)
        XCTAssertEqual(duration(value, "2026-10-01T12:00:00Z"), "\(plural(2, "周")) \(plural(1, "天"))")
        XCTAssertEqual(duration(value, "2026-10-02T12:00:00Z"), plural(2, "周"))
        XCTAssertEqual(duration(value, "2026-10-15T12:00:00Z"), plural(1, "天"))
        XCTAssertEqual(duration(value, "2026-10-16T08:00:00Z"), L10n.text("今天"))
        XCTAssertEqual(EventDisplayFormatter.summary(event: value, now: date("2026-10-01T12:00:00Z"), timeZone: utc),
                       L10n.format("%@ %@", L10n.text("还有"), "\(plural(2, "周")) \(plural(1, "天"))"))
    }

    func testCalendarMonthEndsAndFuturePastSymmetry() {
        for (start, end, expected) in [
            ("2025-01-31T12:00:00Z", "2025-02-28T12:00:00Z", plural(1, "个月")),
            ("2024-01-31T12:00:00Z", "2024-02-29T12:00:00Z", plural(1, "个月")),
            ("2025-01-31T12:00:00Z", "2025-03-01T12:00:00Z", "\(plural(1, "个月")) \(plural(1, "天"))"),
            ("2025-01-15T12:00:00Z", "2026-04-17T12:00:00Z", "\(plural(1, "年")) \(plural(3, "个月")) \(plural(2, "天"))")
        ] {
            XCTAssertEqual(duration(event(end, format: .calendar), start), expected)
            XCTAssertEqual(duration(event(start, format: .calendar), end), expected)
        }
    }

    func testCalendarLeapYearAndLongSpanUseActualCalendar() {
        XCTAssertEqual(duration(event("2025-02-28T12:00:00Z", format: .calendar), "2024-02-29T12:00:00Z"), plural(1, "年"))
        XCTAssertEqual(duration(event("2028-03-01T12:00:00Z", format: .calendar), "2024-02-29T12:00:00Z"),
                       "\(plural(4, "年")) \(plural(1, "天"))")
    }

    func testDSTCountsCivilDaysForCalendarAndWeeks() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        for (start, end) in [("2026-03-07T12:00:00-08:00", "2026-03-09T12:00:00-07:00"),
                             ("2026-10-31T12:00:00-07:00", "2026-11-02T12:00:00-08:00")] {
            for format in [EventDisplayFormat.days, .weeks, .calendar] {
                XCTAssertEqual(duration(event(end, format: format), start, zone: zone), plural(2, "天"))
            }
        }
    }

    func testIncludeStartAppliesOnlyToElapsedNonannual() {
        let elapsed = event("2025-01-31T12:00:00Z", format: .calendar, includesStart: true)
        XCTAssertEqual(duration(elapsed, "2025-02-28T12:00:00Z"), "\(plural(1, "个月")) \(plural(1, "天"))")
        let future = event("2025-02-28T12:00:00Z", format: .calendar, includesStart: true)
        XCTAssertEqual(duration(future, "2025-01-31T12:00:00Z"), plural(1, "个月"))
        let today = event("2025-02-28T12:00:00Z", format: .calendar, includesStart: true)
        XCTAssertEqual(duration(today, "2025-02-28T18:00:00Z"), plural(1, "天"))
        XCTAssertEqual(duration(today, "2025-02-28T08:00:00Z"), L10n.text("今天"))
        let week = event("2026-10-01T12:00:00Z", format: .weeks, includesStart: true)
        XCTAssertEqual(duration(week, "2026-10-07T12:00:00Z"), plural(1, "周"))
        var yearly = event("2024-02-29T12:00:00Z", format: .calendar, includesStart: true)
        yearly.repeatYearly = true; yearly.isAllDay = true
        yearly.calendarDay = CalendarDay(year: 2024, month: 2, day: 29)
        XCTAssertEqual(duration(yearly, "2026-02-28T18:00:00Z"), L10n.text("今天"))
    }

    func testAllDayCalendarDateIsStableAcrossTimeZones() {
        var value = event("2026-03-02T00:00:00Z", format: .calendar)
        value.isAllDay = true; value.calendarDay = CalendarDay(year: 2026, month: 3, day: 1)
        for name in ["Asia/Shanghai", "America/Los_Angeles"] {
            let zone = TimeZone(identifier: name)!
            let now = CalendarDay(year: 2026, month: 2, day: 1).date(timeZone: zone)!
            XCTAssertEqual(EventDisplayFormatter.duration(event: value, now: now, timeZone: zone), plural(1, "个月"))
        }
    }

    func testAnniversaryKeepsOriginalYearAndAdvancesOnlyAfterOccurrenceDay() {
        var value = event("2023-10-09T10:00:00Z", format: .anniversary, includesStart: true)
        value.repeatYearly = true; value.calendarDay = CalendarDay(year: 2023, month: 10, day: 9)
        value.annualTime = CalendarTime(hour: 10, minute: 0)
        XCTAssertEqual(duration(value, "2026-10-07T18:00:00Z"), L10n.format("%ld 周年 · %@", 3, plural(2, "天")))
        for now in ["2026-10-09T08:00:00Z", "2026-10-09T22:00:00Z"] {
            XCTAssertEqual(duration(value, now), L10n.format("%ld 周年 · %@", 3, L10n.text("今天")))
            XCTAssertEqual(EventDisplayFormatter.summary(event: value, now: date(now), timeZone: utc),
                           L10n.format("%ld 周年 · %@", 3, L10n.format("%@ · 今天", L10n.text("纪念日"))))
        }
        XCTAssertEqual(duration(value, "2026-10-10T00:00:00Z"), L10n.format("%ld 周年 · %@", 4, plural(364, "天")))
        XCTAssertEqual(value.calendarDay?.year, 2023)
    }

    func testLeapAnniversaryAndFutureOriginalYear() {
        var value = event("2024-02-29T00:00:00Z", format: .anniversary)
        value.repeatYearly = true; value.isAllDay = true
        value.calendarDay = CalendarDay(year: 2024, month: 2, day: 29)
        XCTAssertEqual(duration(value, "2026-02-27T12:00:00Z"), L10n.format("%ld 周年 · %@", 2, plural(1, "天")))
        XCTAssertEqual(duration(value, "2028-02-28T12:00:00Z"), L10n.format("%ld 周年 · %@", 4, plural(1, "天")))
        value.calendarDay = CalendarDay(year: 2030, month: 2, day: 10)
        let now = date("2026-10-09T12:00:00Z")
        let days = DayCounter.snapshot(event: value, now: now, timeZone: utc).days
        XCTAssertEqual(EventDisplayFormatter.duration(event: value, now: now, timeZone: utc),
                       L10n.format("%ld 周年 · %@", 0, plural(days, "天")))
    }

    func testNonannualAnniversarySafelyFallsBackToDaySummary() {
        let value = event("2026-10-09T12:00:00Z", format: .anniversary)
        let now = date("2026-10-07T12:00:00Z")
        XCTAssertEqual(EventDisplayFormatter.summary(event: value, now: now, timeZone: utc),
                       DayCounter.snapshot(event: value, now: now, timeZone: utc).summary(for: value))
        XCTAssertEqual(EventDisplayFormatter.duration(event: value, now: now, timeZone: utc), plural(2, "天"))
    }
}
