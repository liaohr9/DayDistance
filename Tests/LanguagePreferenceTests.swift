import XCTest
import Observation
#if SWIFT_PACKAGE
@testable import DayDistanceCore
#endif

final class LanguagePreferenceTests: XCTestCase {
    func testExplicitLanguageFindsActualLowercaseResourceDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("zh-hans.lproj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("en.lproj"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "language-resource-probe", "CFBundleDevelopmentRegion": "en"], format: .xml, options: 0).write(to: root.appendingPathComponent("Info.plist"))
        try PropertyListSerialization.data(fromPropertyList: ["今天": "今天"], format: .xml, options: 0).write(to: root.appendingPathComponent("zh-hans.lproj/Localizable.strings"))
        try PropertyListSerialization.data(fromPropertyList: ["今天": "Today"], format: .xml, options: 0).write(to: root.appendingPathComponent("en.lproj/Localizable.strings"))
        let source = try XCTUnwrap(Bundle(url: root))
        let chinese = try XCTUnwrap(L10n.resourceBundle(for: .simplifiedChinese, in: source))
        XCTAssertEqual(chinese.bundleURL.lastPathComponent, "zh-hans.lproj")
        XCTAssertEqual(L10n.text("今天", bundle: chinese), "今天")
    }

    func testApplyPublishesAndChangesLookupWithoutRelaunch() throws {
        let original = L10n.currentLanguage
        defer { L10n.useLanguage(original) }
        let domain = "live-language-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("app-language.json")
        try AppLanguage.english.apply(defaults: defaults, file: file)
        XCTAssertEqual(L10n.text("今天"), "Today")
        try AppLanguage.simplifiedChinese.apply(defaults: defaults, file: file)
        XCTAssertEqual(L10n.text("今天"), "今天")
        XCTAssertEqual(AppLanguage.applied(at: file), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.selection(defaults: defaults, domain: domain), .simplifiedChinese)
    }
    func testApplyFailureKeepsCurrentLanguageAndPreference() throws {
        let original = L10n.currentLanguage
        defer { L10n.useLanguage(original) }
        L10n.useLanguage(.english)
        let domain = "live-language-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        AppLanguage.english.save(defaults: defaults)
        try Data("not a directory".utf8).write(to: root)
        XCTAssertThrowsError(try AppLanguage.simplifiedChinese.apply(defaults: defaults, file: root.appendingPathComponent("app-language.json")))
        XCTAssertEqual(L10n.text("今天"), "Today")
        XCTAssertEqual(AppLanguage.selection(defaults: defaults, domain: domain), .english)
    }
    func testLookupAndLocaleNotifySwiftUIObservationOnChange() {
        let original = L10n.currentLanguage
        defer { L10n.useLanguage(original) }
        L10n.useLanguage(.english)
        let lookupChanged = expectation(description: "Localized lookup invalidates its consumer")
        let localeChanged = expectation(description: "Locale invalidates its consumer")
        withObservationTracking { _ = L10n.text("今天") } onChange: { lookupChanged.fulfill() }
        withObservationTracking { _ = L10n.locale } onChange: { localeChanged.fulfill() }
        L10n.useLanguage(.simplifiedChinese)
        wait(for: [lookupChanged, localeChanged], timeout: 1)
    }
    func testOnlyChineseAndEnglishAreOffered() {
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), Set(["zh-Hans", "en"]))
    }
    func testInterfaceLocalePreservesRegion() {
        let original = L10n.currentLanguage
        defer { L10n.useLanguage(original) }
        L10n.useLanguage(.english)
        XCTAssertEqual(L10n.locale.language.languageCode?.identifier, "en")
        XCTAssertEqual(L10n.locale.region, Locale.autoupdatingCurrent.region)
        L10n.useLanguage(.simplifiedChinese)
        XCTAssertEqual(L10n.locale.language.languageCode?.identifier, "zh")
        XCTAssertEqual(L10n.locale.region, Locale.autoupdatingCurrent.region)
    }

    func testOnlyPersistentAppOverrideDeterminesSelection() throws {
        let domain = "language-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.register(defaults: ["AppleLanguages": ["en"]])
        XCTAssertEqual(AppLanguage.selection(defaults: defaults, domain: domain, systemLanguages: ["zh-Hans"]), .simplifiedChinese)
        defaults.set(["en-GB"], forKey: "AppleLanguages")
        XCTAssertEqual(AppLanguage.selection(defaults: defaults, domain: domain), .english)
        defaults.set(["zh-Hans-CN"], forKey: "AppleLanguages")
        XCTAssertEqual(AppLanguage.selection(defaults: defaults, domain: domain), .simplifiedChinese)
        defaults.set(["fr"], forKey: "AppleLanguages")
        XCTAssertEqual(AppLanguage.selection(defaults: defaults, domain: domain, systemLanguages: ["zh-Hans"]), .simplifiedChinese)
    }

    func testSavePreservesOtherSettings() throws {
        let domain = "language-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("keep", forKey: "unrelated")
        let global = defaults.persistentDomain(forName: UserDefaults.globalDomain)
        AppLanguage.english.save(defaults: defaults)
        XCTAssertEqual(AppLanguage.selection(defaults: defaults, domain: domain), .english)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
        AppLanguage.simplifiedChinese.save(defaults: defaults)
        XCTAssertEqual(AppLanguage.selection(defaults: defaults, domain: domain), .simplifiedChinese)
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
        XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]), NSDictionary(dictionary: global ?? [:]))
    }

    func testAppliedLanguageChangesOnlyWhenPublished() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let events = root.appendingPathComponent("events.json")
        let original = Data("user events remain untouched".utf8)
        try original.write(to: events)
        let file = AppLanguage.appliedFile(beside: events)
        XCTAssertNil(AppLanguage.applied(at: file))
        XCTAssertTrue(try AppLanguage.english.publish(to: file))
        XCTAssertFalse(try AppLanguage.english.publish(to: file))
        XCTAssertEqual(AppLanguage.applied(at: file), .english)
        let domain = "language-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        AppLanguage.simplifiedChinese.save(defaults: defaults)
        XCTAssertEqual(AppLanguage.applied(at: file), .english, "Pending choice must not change widget/background language")
        XCTAssertTrue(try AppLanguage.selection(defaults: defaults, domain: domain).publish(to: file))
        XCTAssertEqual(AppLanguage.applied(at: file), .simplifiedChinese)
        try Data("invalid".utf8).write(to: file)
        XCTAssertNil(AppLanguage.applied(at: file))
        try Data(repeating: 65, count: 4097).write(to: file)
        XCTAssertNil(AppLanguage.applied(at: file))
        XCTAssertEqual(try Data(contentsOf: events), original)
    }

    func testLanguagePreferenceCannotBeReplacedByAnExport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let events = root.appendingPathComponent("events.json")
        XCTAssertThrowsError(try ExportDestinationPolicy.validate(AppLanguage.appliedFile(beside: events), protectedFiles: [events]))
    }

    func testWidgetExplicitLocalizationAndUserText() {
        let original = L10n.currentLanguage
        defer { L10n.useLanguage(original) }
        L10n.useLanguage(.english)
        XCTAssertEqual(L10n.text("今天"), "Today")
        XCTAssertEqual(L10n.text("My event 用户名称"), "My event 用户名称")
        L10n.useLanguage(.simplifiedChinese)
        XCTAssertEqual(L10n.text("今天"), "今天")
    }
}
