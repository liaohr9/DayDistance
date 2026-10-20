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
        guard (isAllDay || isRepeating), let day = calendarDay,
              let start = day.date(timeZone: timeZone) else { return targetDate }
        let c = CalendarDay.calendar(timeZone)
        let time = annualTime ?? CalendarTime(date: targetDate, timeZone: timeZone)
        return c.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: start) ?? start
    }
    func occurrence(onOrAfter now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        let c = CalendarDay.calendar(timeZone)
        let original = calendarDay ?? CalendarDay(date: targetDate, timeZone: timeZone)
        if !isRepeating { return isAllDay ? original.date(timeZone: timeZone) ?? targetDate : targetDate }
        let time = annualTime ?? CalendarTime(date: targetDate, timeZone: timeZone)
        let today = c.startOfDay(for: now)
        guard let anchor = original.date(timeZone: timeZone) else { return targetDate }
        func timed(_ day: Date) -> Date {
            isAllDay ? day : c.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
        }
        // Keep the occurrence throughout its local day, including after its time.
        if repeatDaily { return timed(max(anchor, today)) }
        let year = max(original.year, c.component(.year, from: now))
        guard (1...9999).contains(year) else { return targetDate }
        let month = c.component(.month, from: now)
        let firstMonth = repeatMonthly ? max(original.year * 12 + original.month - 1, c.component(.year, from: now) * 12 + month - 1) : year * 12 + original.month - 1
        for offset in 0...1 {
            let index = firstMonth + offset * (repeatMonthly ? 1 : 12)
            let y = index / 12, m = index % 12 + 1
            guard (1...9999).contains(y),
                  let start = c.date(from: DateComponents(year: y, month: m, day: 1)),
                  let range = c.range(of: .day, in: .month, for: start),
                  let day = c.date(from: DateComponents(year: y, month: m, day: min(original.day, range.count))) else { continue }
            if day >= today { return timed(day) }
        }
        return targetDate
    }
    func countdownDate(now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        occurrence(onOrAfter: now, timeZone: timeZone)
    }
    func isUpcoming(at now: Date) -> Bool { isRepeating || countdownDate(now: now) > now }
    func dateLabel(now: Date, original: Bool = false, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let date = original ? originalDate(timeZone: timeZone) : countdownDate(now: now, timeZone: timeZone)
        let style = Date.FormatStyle(date: .numeric, time: isAllDay ? .omitted : .shortened, locale: locale, timeZone: timeZone)
        let label = date.formatted(style)
        guard !original else { return label }
        if repeatDaily { return L10n.format("每天 · %@", label) }
        if repeatMonthly { return L10n.format("每月 · %@", label) }
        return repeatYearly ? L10n.format("每年 · %@", label) : label
    }
}
