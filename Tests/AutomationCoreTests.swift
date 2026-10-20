import XCTest

#if SWIFT_PACKAGE
  @testable import DayDistanceCore
#endif
final class AutomationCoreTests: XCTestCase {
  func testStrictDatesAndExplicitTimeZone() throws {
    XCTAssertThrowsError(try AutomationDates.parse(at: "2026-11-16T20:00:00", day: nil))
    XCTAssertThrowsError(try AutomationDates.parse(at: nil, day: "2026-02-30"))
    XCTAssertThrowsError(
      try AutomationDates.parse(at: "2026-11-16T20:00:00+08:00", day: "2026-11-16"))
    let value = try AutomationDates.parse(at: "2026-11-16T20:00:00+08:00", day: nil)
    XCTAssertEqual(
      value.date.timeIntervalSince1970,
      ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!.timeIntervalSince1970)
    XCTAssertNil(value.day)
    XCTAssertThrowsError(try AutomationDates.parse(at: "2026-11-16T20:00:00+08:99", day: nil))
  }
  func testCLICreatesStrictTypedRequestAndRejectsUnknownOptions() throws {
    let request = try AutomationCLI.parse([
      "events", "create", "--title", "Paper", "--date", "2026-11-16", "--request-id", "stable",
      "--json",
    ])
    XCTAssertEqual(
      try AutomationCLI.parse([
        "events", "create", "--title", "--json", "--date", "2026-11-16", "--request-id", "literal",
      ]).arguments["title"], .string("--json"))
    XCTAssertEqual(request.operation, "create")
    XCTAssertEqual(request.arguments["title"], .string("Paper"))
    XCTAssertThrowsError(try AutomationCLI.parse(["events", "create", "--titlle", "Paper"]))
    XCTAssertThrowsError(try AutomationCLI.parse(["events", "list", "--limit", "bad"]))
  }
  func testCreateReceiptSharesAtomicSnapshotAndSurvivesOtherWrites() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let repo = EventRepository(fileURL: folder.appendingPathComponent("events.json"))
    let event = CountdownEvent(
      title: "Stable", targetDate: Date(timeIntervalSince1970: 1_800_000_000))
    let receipt = AutomationReceipt(payloadHash: "payload", eventID: event.id)
    try repo.save([event], replacing: [], automationReceipt: ("request", receipt))
    XCTAssertEqual(try repo.automationReceipt(for: "request"), receipt)
    try repo.save([], replacing: [event])
    XCTAssertEqual(
      try repo.automationReceipt(for: "request"), receipt,
      "permanent removal must not silently recreate a retried request")
    XCTAssertTrue(try repo.load().isEmpty)
  }
    func testCLIParsesOneShotExpiry() throws {
        let request = try AutomationCLI.parse(["events", "create", "--title", "Once", "--at", "2026-12-01T12:00:00Z", "--request-id", "once", "--after-date", "trash"])
        XCTAssertEqual(request.arguments["afterDate"], .string("trash"))
    }

}
