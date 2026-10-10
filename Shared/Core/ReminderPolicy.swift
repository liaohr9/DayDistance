import Foundation

enum ReminderCadence: String, Hashable, Sendable { case once, daily, monthly, yearly }

struct PlannedEventReminder: Equatable, Sendable {
    let identifier: String
    let eventID: UUID
    let title: String
    let fireDate: Date
    let daysBefore: Int
    let kind: EventReminder
    let followsDeviceTimeZone: Bool
    var cadence: ReminderCadence = .once
    var body: String = ""
}

struct EventReminderPlan: Equatable, Sendable {
    let requests: [PlannedEventReminder]
    let pastEventCount: Int
    let truncatedRequestCount: Int
    let hasAnnualEvents: Bool
}

enum ReminderPolicy {
    static let identifierPrefix = "daydistance."
    static let annualOccurrences = 8
    static let maximumRequests = 60
    static let dailyOccurrences = 60
    static let monthlyOccurrences = 12

    /// Returns actual future notification times, without requesting permission or changing events.
    static func plan(events: [CountdownEvent], now: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent,
                     annualOccurrences: Int = annualOccurrences, maximumRequests: Int = maximumRequests) -> EventReminderPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var candidates: [PlannedEventReminder] = []
        var pastEventCount = 0
        let enabled = events.filter { $0.isActive && $0.hasEnabledReminders }
        for event in enabled { candidates += recurringRequests(event: event, now: now, calendar: calendar) }
        for event in enabled where event.reminder != .none {
            var cursor = now
            var futureCount = 0
            // One extra annual candidate lets a reminder already passed today roll to next year.
            let attempts = event.repeatYearly ? (annualOccurrences > 0 ? annualOccurrences + 1 : 0) : 1
            for _ in 0..<attempts {
                guard (1...9999).contains(calendar.component(.year, from: cursor)) else { break }
                let occurrence = event.occurrence(onOrAfter: cursor, timeZone: timeZone)
                guard (1...9999).contains(calendar.component(.year, from: occurrence)) else { break }
                if event.repeatYearly, calendar.startOfDay(for: occurrence) < calendar.startOfDay(for: cursor) { break }
                var fireDate = occurrence
                if event.reminder == .custom, let time = event.reminderTime {
                    fireDate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: occurrence) ?? occurrence
                } else if event.isAllDay {
                    fireDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: occurrence) ?? occurrence
                }
                let daysBefore = event.reminder == .custom ? event.reminderDaysBefore : (event.reminder == .dayBefore ? 1 : 0)
                if daysBefore > 0 {
                    // Calendar subtraction preserves local wall time across 23/25-hour days.
                    fireDate = calendar.date(byAdding: .day, value: -daysBefore, to: fireDate) ?? fireDate
                }
                if fireDate > now {
                    candidates.append(PlannedEventReminder(
                        identifier: identifierPrefix + event.id.uuidString + "." + String(Int64(fireDate.timeIntervalSince1970)),
                        eventID: event.id, title: event.title, fireDate: fireDate, daysBefore: daysBefore, kind: event.reminder,
                        followsDeviceTimeZone: event.isAllDay || event.repeatYearly,
                        body: daysBefore == 0 ? L10n.text("今天是这个日子。") : (daysBefore == 1 ? L10n.text("明天是这个日子。") : L10n.format("距离这个日子还有 %ld 天。", daysBefore))))
                    futureCount += 1
                }
                guard event.repeatYearly, futureCount < max(0, annualOccurrences),
                      let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: occurrence)),
                      nextDay > cursor else { break }
                cursor = nextDay
            }
            if futureCount == 0 { pastEventCount += 1 }
        }
        candidates.sort {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.identifier < $1.identifier
        }
        let limit = max(0, maximumRequests)
        return EventReminderPlan(requests: limitedRequests(candidates, maximumRequests: limit), pastEventCount: pastEventCount,
                                 truncatedRequestCount: max(0, candidates.count - limit),
                                 hasAnnualEvents: enabled.contains { $0.repeatYearly || $0.yearlyReminderTime != nil })
    }

    /// Reserve the next request for each event/cadence before filling remaining slots.
    /// A daily stream must not silently starve an upcoming yearly anniversary.
    static func limitedRequests(_ requests: [PlannedEventReminder], maximumRequests: Int) -> [PlannedEventReminder] {
        let sorted = requests.sorted { $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate }
        var groups: Set<String> = []
        var reserved: [PlannedEventReminder] = []
        var remaining: [PlannedEventReminder] = []
        for request in sorted {
            if groups.insert(request.eventID.uuidString + "." + request.cadence.rawValue).inserted { reserved.append(request) }
            else { remaining.append(request) }
        }
        return Array((reserved + remaining).prefix(max(0, maximumRequests))).sorted {
            $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate
        }
    }

    private static func recurringRequests(event: CountdownEvent, now: Date, calendar: Calendar) -> [PlannedEventReminder] {
        var result: [PlannedEventReminder] = []
        func append(_ date: Date, cadence: ReminderCadence, body: String) {
            guard date > now else { return }
            result.append(PlannedEventReminder(identifier: identifierPrefix + event.id.uuidString + "." + cadence.rawValue + "." + String(Int64(date.timeIntervalSince1970)),
                eventID: event.id, title: event.title, fireDate: date, daysBefore: 0, kind: .none,
                followsDeviceTimeZone: true, cadence: cadence, body: body))
        }
        if let time = event.dailyReminderTime {
            let today = calendar.startOfDay(for: now)
            for offset in 0...dailyOccurrences {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let fire = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) else { continue }
                if result.count < dailyOccurrences {
                    append(fire, cadence: .daily, body: DayCounter.snapshot(event: event, now: fire, timeZone: calendar.timeZone).summary(for: event))
                }
            }
        }
        let anchor = event.calendarDay ?? CalendarDay(date: event.targetDate, timeZone: calendar.timeZone)
        let current = calendar.dateComponents([.year, .month], from: now)
        if let time = event.monthlyReminderTime {
            let elapsed = ((current.year ?? anchor.year) - anchor.year) * 12 + (current.month ?? anchor.month) - anchor.month
            let first = max(1, elapsed)
            let before = result.count
            for number in first..<(first + monthlyOccurrences + 1) {
                guard result.count - before < monthlyOccurrences else { break }
                let absolute = (anchor.year - 1) * 12 + anchor.month - 1 + number
                let year = absolute / 12 + 1, month = absolute % 12 + 1
                if let fire = milestoneDate(year: year, month: month, day: anchor.day, time: time, calendar: calendar) {
                    append(fire, cadence: .monthly, body: L10n.format("今天是第 %ld 个月纪念日。", number))
                }
            }
        }
        if let time = event.yearlyReminderTime {
            let first = max(1, (current.year ?? anchor.year) - anchor.year)
            let before = result.count
            for number in first..<(first + annualOccurrences + 1) {
                guard result.count - before < annualOccurrences else { break }
                if let fire = milestoneDate(year: anchor.year + number, month: anchor.month, day: anchor.day, time: time, calendar: calendar) {
                    append(fire, cadence: .yearly, body: L10n.format("今天是第 %ld 周年纪念日。", number))
                }
            }
        }
        return result
    }

    private static func milestoneDate(year: Int, month: Int, day: Int, time: CalendarTime, calendar: Calendar) -> Date? {
        guard (1...9999).contains(year), let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: start),
              let date = calendar.date(byAdding: .day, value: min(day, range.count) - 1, to: start) else { return nil }
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date)
    }

}
