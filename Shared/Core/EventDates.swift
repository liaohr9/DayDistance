import Foundation

struct CalendarDay: Codable, Equatable, Sendable {
    var year: Int
    var month: Int
    var day: Int
    init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    init(date: Date, timeZone: TimeZone = .autoupdatingCurrent) {
        let c = Self.calendar(timeZone)
        year = c.component(.year, from: date); month = c.component(.month, from: date); day = c.component(.day, from: date)
    }
    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; return calendar
    }
    func date(timeZone: TimeZone) -> Date? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let c = Self.calendar(timeZone)
        guard let date = c.date(from: DateComponents(year: year, month: month, day: day)),
              c.component(.year, from: date) == year, c.component(.month, from: date) == month,
              c.component(.day, from: date) == day else { return nil }
        return date
    }
}
struct CalendarTime: Codable, Equatable, Sendable {
    var hour: Int
    var minute: Int
    init(hour: Int, minute: Int) { self.hour = hour; self.minute = minute }
    init(date: Date, timeZone: TimeZone = .autoupdatingCurrent) {
        let c = CalendarDay.calendar(timeZone)
        hour = c.component(.hour, from: date); minute = c.component(.minute, from: date)
    }
}
extension CountdownEvent {
    func originalDate(timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        guard (isAllDay || repeatYearly), let day = calendarDay,
              let start = day.date(timeZone: timeZone) else { return targetDate }
        let c = CalendarDay.calendar(timeZone)
        let time = annualTime ?? CalendarTime(date: targetDate, timeZone: timeZone)
        return c.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: start) ?? start
    }
    func occurrence(onOrAfter now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        let c = CalendarDay.calendar(timeZone)
        let original = calendarDay ?? CalendarDay(date: targetDate, timeZone: timeZone)
        if !repeatYearly { return isAllDay ? original.date(timeZone: timeZone) ?? targetDate : targetDate }
        let time = annualTime ?? CalendarTime(date: targetDate, timeZone: timeZone)
        // Keep this occurrence throughout its day, and never move before the original year.
        let year = max(original.year, c.component(.year, from: now))
        guard (1...9999).contains(year) else { return targetDate }
        for candidateYear in year...min(year + 1, 9999) {
            guard let month = c.date(from: DateComponents(year: candidateYear, month: original.month, day: 1)),
                  let range = c.range(of: .day, in: .month, for: month),
                  let day = c.date(from: DateComponents(year: candidateYear, month: original.month, day: min(original.day, range.count))) else { continue }
            let occurrence = isAllDay ? day : c.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
            if c.startOfDay(for: occurrence) >= c.startOfDay(for: now) { return occurrence }
        }
        return targetDate
    }
    func countdownDate(now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        occurrence(onOrAfter: now, timeZone: timeZone)
    }
    func isUpcoming(at now: Date) -> Bool { repeatYearly || countdownDate(now: now) > now }
    func dateLabel(now: Date, original: Bool = false, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let date = original ? originalDate(timeZone: timeZone) : countdownDate(now: now, timeZone: timeZone)
        let style = Date.FormatStyle(date: .numeric, time: isAllDay ? .omitted : .shortened, locale: locale, timeZone: timeZone)
        let label = date.formatted(style)
        return repeatYearly && !original ? L10n.format("每年 · %@", label) : label
    }
}
