import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class VimKeyTests: XCTestCase {
    func testSequencesExpireAndDoNotRepeatDestructiveActions() {
        var keys = VimKeySequence()
        XCTAssertNil(keys.command("d", at: 0))
        XCTAssertNil(keys.command("d", at: 1))
        XCTAssertEqual(keys.command("d", at: 1.1), .trash)
        XCTAssertNil(keys.command("g", at: 2))
        XCTAssertEqual(keys.command("g", at: 2.1), .first)
        XCTAssertEqual(keys.command("G", at: 3), .last)
        XCTAssertEqual(keys.command("j", at: 4), .down)
        XCTAssertEqual(keys.command("r", control: true, at: 5), .redo)
        XCTAssertNil(keys.command("x", at: 6))
    }
    func testVisualSelectionAndBoundaries() {
        let ids = (0..<4).map { _ in UUID() }
        var nav = VimListNavigation()
        var selected = Set<UUID>()
        nav.move(1, ids: ids, selected: &selected)
        XCTAssertEqual(selected, [ids[0]])
        nav.anchor = nav.cursor
        nav.move(1, ids: ids, selected: &selected)
        nav.move(1, ids: ids, selected: &selected)
        XCTAssertEqual(selected, Set(ids.prefix(3)))
        nav.move(-1, ids: ids, selected: &selected)
        XCTAssertEqual(selected, Set(ids.prefix(2)))
        nav.move(-20, ids: ids, selected: &selected)
        XCTAssertEqual(selected, [ids[0]])
        nav.anchor = nil
        nav.move(20, ids: ids, selected: &selected)
        XCTAssertEqual(selected, [ids[3]])
        nav.move(1, ids: [], selected: &selected)
        XCTAssertTrue(selected.isEmpty)
    }
}
