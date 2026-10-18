import Foundation
import Observation

/// Native per-app language. No event data is changed.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    var id: Self { self }
    var label: String { self == .english ? "English" : "简体中文" }

    static func selection(defaults: UserDefaults = .standard,
                          domain: String = Bundle.main.bundleIdentifier ?? "local.daydistance.mac",
                          systemLanguages: [String]? = nil) -> AppLanguage {
        // The merged defaults domain includes global/registered values. Only
        // the persistent app domain describes a previously chosen app language.
        let saved = defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String]
        if let first = saved?.first, let value = supported(first) { return value }
        let languages = systemLanguages ?? (defaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? ["en"])
        let preferred = Bundle.preferredLocalizations(from: allCases.map(\.rawValue), forPreferences: languages).first ?? "en"
        return supported(preferred) ?? .english
    }
    private static func supported(_ language: String) -> AppLanguage? {
        if language == "en" || language.hasPrefix("en-") { return .english }
        if language == "zh" || language == "zh-CN" || language == "zh-SG" || language.hasPrefix("zh-Hans") { return .simplifiedChinese }
        return nil
    }
    func save(defaults: UserDefaults = .standard) {
        defaults.set([rawValue], forKey: "AppleLanguages")
    }
    static func appliedFile(beside events: URL) -> URL {
        events.deletingLastPathComponent().appendingPathComponent("app-language.json")
    }
    static func applied(at file: URL) -> AppLanguage? {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 4096,
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    /// A user selection commits the shared snapshot before changing visible UI.
    /// If storage fails, keep the current UI and preference together.
    func apply(defaults: UserDefaults = .standard, file: URL) throws {
        try publish(to: file)
        save(defaults: defaults)
        L10n.useLanguage(self)
    }
    /// Returns whether the applied widget/background snapshot changed.
    @discardableResult func publish(to file: URL) throws -> Bool {
        guard Self.applied(at: file) != self else { return false }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
        return true
    }
}

/// Uses the app/widget bundle in production and SwiftPM's resource bundle in tests.
/// Keys retain the original Chinese wording; user content is never a localization key.
enum L10n {
    static let languageDidChange = Notification.Name("daydistance.language.changed")
    @Observable final class LanguageState: @unchecked Sendable {
        @ObservationIgnored let lock = NSRecursiveLock()
        @ObservationIgnored var language = AppLanguage.selection()
        @ObservationIgnored var localizedBundle: Bundle?
        var revision = 0
    }
    private static let state = LanguageState()
    static var currentLanguage: AppLanguage {
        state.lock.lock(); defer { state.lock.unlock() }
        let _ = state.revision
        return state.language
    }
    // Preserve regional date/time conventions while changing interface wording.
    static var locale: Locale {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        var language = Locale.Language.Components(identifier: currentLanguage.rawValue)
        language.region = Locale.autoupdatingCurrent.region
        components.languageComponents = language
        return Locale(components: components)
    }
    static func useLanguage(_ language: AppLanguage) {
        let localized = resourceBundle(for: language, in: bundle)
        state.lock.lock()
        let changed = state.language != language || state.localizedBundle == nil
        state.language = language
        state.localizedBundle = localized
        if changed { state.revision += 1 }
        state.lock.unlock()
        if changed { NotificationCenter.default.post(name: languageDidChange, object: nil) }
    }
    /// Bundle resource lookup may filter by preferred language or normalize lproj
    /// casing differently across SDKs. Resolve the actual shipped directory.
    static func resourceBundle(for language: AppLanguage, in source: Bundle) -> Bundle? {
        guard let resources = source.resourceURL,
              let entries = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil),
              let directory = entries.first(where: {
                  $0.lastPathComponent.caseInsensitiveCompare(language.rawValue + ".lproj") == .orderedSame
              }) else { return nil }
        return Bundle(url: directory)
    }
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    static func text(_ key: String, bundle: Bundle? = nil) -> String {
        state.lock.lock()
        let _ = state.revision
        let selected = state.localizedBundle
        state.lock.unlock()
        return NSLocalizedString(key, bundle: bundle ?? selected ?? self.bundle, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.autoupdatingCurrent, arguments: arguments)
    }

    static func format(_ key: String, bundle: Bundle, locale: Locale = .autoupdatingCurrent, _ arguments: CVarArg...) -> String {
        String(format: text(key, bundle: bundle), locale: locale, arguments: arguments)
    }

    static func time(hour: Int, minute: Int = 0, locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour, minute: minute))!
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
