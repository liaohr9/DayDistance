import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif
final class ReleaseHistoryTests: XCTestCase {
    func testBundledHistoryIsNewestFirstAndExcludesUnreleasedLocalBuilds() throws {
        let entries = try ReleaseHistory.load()
        XCTAssertEqual(entries.first?.version, "1.18.0")
        XCTAssertEqual(entries.first?.build, 50)
        XCTAssertEqual(entries.map(\.version), ["1.18.0", "1.17.1", "1.17.0", "1.15.0", "1.14.0", "1.13.2", "1.13.1", "1.13.0", "1.8.1"])
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(entries.map(\.build), entries.map(\.build).sorted(by: >))
    }
    func testEveryPublishedEntryContainsUsefulChineseAndEnglishNotes() throws {
        for entry in try ReleaseHistory.load() {
            XCTAssertFalse(entry.sections.isEmpty)
            XCTAssertEqual(entry.date.count, 10)
            for section in entry.sections {
                XCTAssertFalse(section.items.isEmpty)
                for item in section.items {
                    XCTAssertFalse(item.text(language: .english).isEmpty)
                    XCTAssertFalse(item.text(language: .simplifiedChinese).isEmpty)
                    XCTAssertNotEqual(item.text(language: .english), item.text(language: .simplifiedChinese))
                }
            }
        }
    }
}
