import Foundation

struct CounterSnapshot: Equatable, Sendable {
    let days: Int
    let isFuture: Bool
    let seconds: Int
    let isSameDay: Bool
    var supportsClock = true
    var showsClock: Bool { supportsClock && (seconds < 86400 || isSameDay) }
    func direction(for event: CountdownEvent) -> String { event.repeatYearly && isSameDay ? L10n.text("纪念日") : direction }
    var direction: String { L10n.text(isFuture ? "还有" : "已过") }
    var dayLabel: String { days == 0 ? L10n.text("今天") : days.formatted(.number.grouping(.never)) }
    func summary(for event: CountdownEvent) -> String {
        days == 0 ? L10n.format("%@ · 今天", direction(for: event)) : (days == 1 ? L10n.format("%@ 1 天", direction(for: event)) : L10n.format("%@ %ld 天", direction(for: event), days))
    }
    var dayUnit: String { L10n.text(days == 1 ? "天（单数）" : "天") }
    var clockLabel: String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, remainder = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
    }
}

enum DayCounter {
    static func snapshot(event: CountdownEvent, now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> CounterSnapshot {
        var value = snapshot(target: event.countdownDate(now: now, timeZone: timeZone), now: now,
                             includesStartDay: event.includesStartDay && !event.repeatYearly, timeZone: timeZone)
        value.supportsClock = !event.isAllDay && (!event.repeatYearly || value.isFuture)
        return value
    }
    static func snapshot(target: Date, now: Date, includesStartDay: Bool = false, timeZone: TimeZone = .autoupdatingCurrent) -> CounterSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let difference = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
        let interval = abs(target.timeIntervalSince(now))
        let seconds = interval.isFinite ? Int(min(floor(interval), Double(Int.max / 2))) : 0
        let isFuture = now < target
        let days = abs(difference) + (includesStartDay && !isFuture ? 1 : 0)
        return CounterSnapshot(days: days, isFuture: isFuture, seconds: seconds, isSameDay: difference == 0)
    }
}
