import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class WidgetManualTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ seconds: TimeInterval, lifecycle: EventLifecycle = .active) -> CountdownEvent {
        CountdownEvent(title: "相同名字", targetDate: now.addingTimeInterval(seconds), lifecycle: lifecycle)
    }
    func testManualOrderDoesNotUseDatesPinsOrTitles() {
        let first = event(-3600), second = event(3600), third = event(7200)
        let config = WidgetManualSelection(enabled: true, slotIDs: [third.id.uuidString, first.id.uuidString, second.id.uuidString])
        XCTAssertEqual(config.resolvedSlots(events: [first, second, third]), [.event(third), .event(first), .event(second)])
    }
    func testDuplicateUUIDsDeduplicateInOrderIncludingCase() {
        let first = event(3600), second = event(7200)
        let config = WidgetManualSelection(enabled: true, slotIDs: [first.id.uuidString, first.id.uuidString.lowercased(), second.id.uuidString])
        XCTAssertEqual(config.resolvedSlots(events: [second, first]), [.event(first), .event(second)])
    }
    func testMissingInvalidArchivedAndTrashedNeverSubstitute() {
        let fallback = event(3600), archived = event(7200, lifecycle: .archived), trashed = event(9000, lifecycle: .trashed)
        let missing = UUID().uuidString
        let config = WidgetManualSelection(enabled: true, slotIDs: [missing, archived.id.uuidString, "bad-id"])
        XCTAssertEqual(config.resolvedSlots(events: [fallback, archived]), [.unavailable(missing), .unavailable(archived.id.uuidString), .unavailable("bad-id")])
        XCTAssertEqual(WidgetManualSelection(enabled: true, slotIDs: [trashed.id.uuidString]).resolvedSlots(events: [fallback, trashed]), [.unavailable(trashed.id.uuidString)])
    }
    func testEmptySlotsAndSentinelHaveNoFallback() {
        let config = WidgetManualSelection(enabled: true, slotIDs: [nil, WidgetManualSelection.noSelectionID, ""])
        XCTAssertTrue(config.resolvedSlots(events: [event(3600)]).isEmpty)
        XCTAssertFalse(WidgetManualSelection().enabled)
    }
    func testOnlyThreeConfiguredSlotsAreAccepted() {
        let a = event(3600), b = event(7200), c = event(9000), d = event(12000)
        let config = WidgetManualSelection(enabled: true, slotIDs: [a.id.uuidString, b.id.uuidString, c.id.uuidString, d.id.uuidString])
        XCTAssertEqual(config.resolvedSlots(events: [d, c, b, a]), [.event(a), .event(b), .event(c)])
    }
    func testSelectionTracksRenameByUUID() {
        var selected = event(3600)
        let config = WidgetManualSelection(enabled: true, slotIDs: [selected.id.uuidString])
        selected.title = "新名字"
        selected.targetDate = now.addingTimeInterval(-9000)
        XCTAssertEqual(config.resolvedSlots(events: [selected]), [.event(selected)])
    }
}
