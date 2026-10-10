import Foundation

/// Uses the app/widget bundle in production and SwiftPM's resource bundle in tests.
/// Keys retain the original Chinese wording; user content is never a localization key.
enum L10n {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    static func text(_ key: String, bundle: Bundle? = nil) -> String {
        NSLocalizedString(key, bundle: bundle ?? self.bundle, comment: "")
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
