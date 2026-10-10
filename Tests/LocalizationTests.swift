import XCTest
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class LocalizationTests: XCTestCase {
    private func languageBundle(_ language: String) throws -> Bundle {
        #if SWIFT_PACKAGE
        let resourceBundle = L10n.bundle
        #else
        let resourceBundle = Bundle(for: LocalizationTests.self)
        #endif
        // Catalog tests inspect every shipped language, independent of preferred
        // localization or SwiftPM's casing of language-directory names.
        let resources = try XCTUnwrap(resourceBundle.resourceURL)
        let directories = try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
        let url = try XCTUnwrap(directories.first {
            $0.lastPathComponent.caseInsensitiveCompare(language + ".lproj") == .orderedSame
        })
        return try XCTUnwrap(Bundle(url: url))
    }

    private func catalog(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(try languageBundle(language).url(forResource: "Localizable", withExtension: "strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }

    func testBothCatalogsHaveSameKeysAndEnglishTranslations() throws {
        let english = try catalog("en"), chinese = try catalog("zh-Hans")
        XCTAssertGreaterThan(english.count, 200)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        for (key, translation) in english {
            XCTAssertFalse(translation.isEmpty, key)
            XCTAssertNil(translation.range(of: "[\\p{Han}]", options: .regularExpression), key)
            XCTAssertFalse(chinese[key]?.isEmpty ?? true, key)
        }
    }

    func testEnglishDaySingularAndPlural() throws {
        let english = try languageBundle("en"), chinese = try languageBundle("zh-Hans")
        XCTAssertEqual(L10n.text("天（单数）", bundle: english), "day")
        XCTAssertEqual(L10n.text("天（单数）", bundle: chinese), "天")
        XCTAssertEqual(L10n.format("%@ 1 天", bundle: english, "Remaining"), "Remaining 1 day")
        XCTAssertEqual(L10n.format("%@ %ld 天", bundle: english, "Remaining", 2), "Remaining 2 days")
    }
    func testFormatPlaceholdersMatchAcrossLanguages() throws {
        let english = try catalog("en"), chinese = try catalog("zh-Hans")
        let expression = try NSRegularExpression(pattern: "%([-+0 #]*[0-9]*(?:\\.[0-9]+)?[hlLzjt]*[@diuoxXfFeEgGcs])")
        func placeholders(_ text: String) -> [String] {
            expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                String(text[Range($0.range, in: text)!])
            }.sorted()
        }
        for key in english.keys { XCTAssertEqual(placeholders(english[key]!), placeholders(chinese[key]!), key) }
    }

    func testLocalizedLookupPreservesUserTextAndFormatsCounts() throws {
        let english = try languageBundle("en"), chinese = try languageBundle("zh-Hans")
        XCTAssertEqual(L10n.text("今天", bundle: english), "Today")
        XCTAssertEqual(L10n.text("今天", bundle: chinese), "今天")
        XCTAssertEqual(L10n.format("已导入 %ld 个事件。", bundle: english, locale: Locale(identifier: "en_US"), 3), "Imported 3 events.")
        XCTAssertEqual(L10n.format("删除「%@」后可从回收站恢复。", bundle: english, "用户自己的名字"),
                       "You can restore “用户自己的名字” from Trash after deleting it.")
        XCTAssertEqual(L10n.text("Unknown user-supplied text", bundle: english), "Unknown user-supplied text")
    }

    func testDateOrderUsesRegionalLocaleAndAllDayOmitsClock() {
        let now = ISO8601DateFormatter().date(from: "2026-10-09T00:00:00Z")!
        let target = ISO8601DateFormatter().date(from: "2026-11-10T18:15:00Z")!
        let event = CountdownEvent(title: "Personal Title", targetDate: target)
        let zone = TimeZone(secondsFromGMT: 0)!
        let us = event.dateLabel(now: now, locale: Locale(identifier: "en_US"), timeZone: zone)
        let gb = event.dateLabel(now: now, locale: Locale(identifier: "en_GB"), timeZone: zone)
        XCTAssertNotEqual(us, gb)
        XCTAssertTrue(us.hasPrefix("11/10/2026"), us)
        XCTAssertTrue(gb.hasPrefix("10/11/2026"), gb)
        XCTAssertTrue(us.contains("PM"), us)
        XCTAssertTrue(gb.contains("18:15"), gb)
        let allDay = CountdownEvent(title: "Personal Title", targetDate: target, isAllDay: true,
                                    calendarDay: CalendarDay(year: 2026, month: 10, day: 10))
        XCTAssertFalse(allDay.dateLabel(now: now, locale: Locale(identifier: "en_US"), timeZone: zone).contains("PM"))
        XCTAssertFalse(allDay.dateLabel(now: now, locale: Locale(identifier: "en_GB"), timeZone: zone).contains(":"))
    }

    func testReminderTimeUsesRegional12Or24HourClock() {
        let zone = TimeZone(secondsFromGMT: 0)!
        let us = L10n.time(hour: 18, minute: 15, locale: Locale(identifier: "en_US"), timeZone: zone)
        let gb = L10n.time(hour: 18, minute: 15, locale: Locale(identifier: "en_GB"), timeZone: zone)
        XCTAssertTrue(us.contains("PM"), us)
        XCTAssertEqual(gb, "18:15")
    }

    func testPublicFeatureKeysExistInEnglishCatalog() throws {
        let english = try catalog("en")
        for key in ["新建事件", "全天", "每年重复", "提醒", "置顶", "归档", "回收站", "永久删除", "本地备份",
                    "自动备份", "恢复所选备份…", "显示菜单栏图标", "使用帮助", "隐私", "通知权限", "选择一个日子",
                    "显示事件图标", "显示目标日期", "显示当天精确计时", "提醒队列最多 60 条，已优先保留最近提醒；%ld 条暂未安排，请再次打开日距补排。"] {
            XCTAssertNotNil(english[key], key)
        }
    }
}
