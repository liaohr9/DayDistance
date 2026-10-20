import Foundation

/// Event formatting shares the counter's occurrence, direction and inclusive-day rules.
enum EventDisplayFormatter {
    static func summary(event: CountdownEvent, now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let snapshot = DayCounter.snapshot(event: event, now: now, timeZone: timeZone)
        if event.displayFormat == .days {
            return snapshot.summary(for: event)
        }
        if event.displayFormat == .anniversary {
            return anniversary(event: event, now: now, timeZone: timeZone, remainder: snapshot.summary(for: event))
        }
        if snapshot.days == 0 { return snapshot.summary(for: event) }
        return L10n.format("%@ %@", snapshot.direction(for: event), duration(event: event, now: now, timeZone: timeZone))
    }

    static func duration(event: CountdownEvent, now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let snapshot = DayCounter.snapshot(event: event, now: now, timeZone: timeZone)
        switch event.displayFormat {
        case .days:
            return dayDuration(snapshot.days)
        case .weeks:
            guard snapshot.days > 0 else { return L10n.text("今天") }
            var parts: [String] = []
            append(snapshot.days / 7, singular: "1 周", plural: "%ld 周", to: &parts)
            append(snapshot.days % 7, singular: "1 天", plural: "%ld 天", to: &parts)
            return parts.joined(separator: " ")
        case .calendar:
            guard snapshot.days > 0 else { return L10n.text("今天") }
            let calendar = CalendarDay.calendar(timeZone)
            let target = calendar.startOfDay(for: event.countdownDate(now: now, timeZone: timeZone))
            let today = calendar.startOfDay(for: now)
            let start = min(target, today)
            var end = max(target, today)
            if event.includesStartDay && !event.repeatYearly && !snapshot.isFuture {
                end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
            }
            // Ordered local day endpoints make past/future durations symmetric, including month ends and DST.
            let components = calendar.dateComponents([.year, .month, .day], from: start, to: end)
            var parts: [String] = []
            append(components.year ?? 0, singular: "1 年", plural: "%ld 年", to: &parts)
            append(components.month ?? 0, singular: "1 个月", plural: "%ld 个月", to: &parts)
            append(components.day ?? 0, singular: "1 天", plural: "%ld 天", to: &parts)
            return parts.isEmpty ? dayDuration(snapshot.days) : parts.joined(separator: " ")
        case .anniversary:
            let remainder = dayDuration(snapshot.days)
            return anniversary(event: event, now: now, timeZone: timeZone, remainder: remainder)
        }
    }

    private static func dayDuration(_ days: Int) -> String {
        if days == 0 { return L10n.text("今天") }
        return days == 1 ? L10n.text("1 天") : L10n.format("%ld 天", days)
    }

    private static func append(_ count: Int, singular: String, plural: String, to parts: inout [String]) {
        guard count > 0 else { return }
        parts.append(count == 1 ? L10n.text(singular) : L10n.format(plural, count))
    }

    private static func anniversary(event: CountdownEvent, now: Date, timeZone: TimeZone, remainder: String) -> String {
        if !event.repeatYearly {
            let calendar = CalendarDay.calendar(timeZone)
            let original = calendar.startOfDay(for: event.originalDate(timeZone: timeZone))
            let today = calendar.startOfDay(for: now)
            let years = calendar.dateComponents([.year], from: original, to: today).year ?? 0
            guard years > 0 else { return remainder }
            return L10n.format("%ld 周年 · %@", years, remainder)
        }
        let original = event.calendarDay ?? CalendarDay(date: event.targetDate, timeZone: timeZone)
        let year = CalendarDay.calendar(timeZone).component(.year, from: event.countdownDate(now: now, timeZone: timeZone))
        return L10n.format("%ld 周年 · %@", max(0, year - original.year), remainder)
    }
}
