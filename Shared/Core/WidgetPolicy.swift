import Foundation

enum WidgetSelection: Equatable { case event(CountdownEvent), empty, missing }
enum EventSortOrder: String, CaseIterable, Identifiable {
    case date, created
    var id: Self { self }
    var label: String { L10n.text(self == .date ? "按日期" : "按创建时间") }
}
enum WidgetPolicy {
    static func sorted(events: [CountdownEvent], now: Date, order: EventSortOrder = .date, includingInactive: Bool = false) -> [CountdownEvent] {
        events.filter { includingInactive || $0.isActive }.sorted { left, right in
            if left.isPinned != right.isPinned { return left.isPinned }
            if order == .created {
                if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
                return left.id.uuidString < right.id.uuidString
            }
            let leftDate = left.countdownDate(now: now), rightDate = right.countdownDate(now: now)
            let leftFuture = left.isUpcoming(at: now), rightFuture = right.isUpcoming(at: now)
            if leftFuture != rightFuture { return leftFuture }
            if leftDate == rightDate { return left.id.uuidString < right.id.uuidString }
            return leftFuture ? leftDate < rightDate : leftDate > rightDate
        }
    }
    static func selection(events: [CountdownEvent], explicitID: String?, now: Date) -> WidgetSelection {
        if let explicitID {
            guard let event = events.first(where: { $0.isActive && $0.id.uuidString == explicitID }) else { return .missing }
            return .event(event)
        }
        return sorted(events: events, now: now).first.map(WidgetSelection.event) ?? .empty
    }
    static func timelineDates(events: [CountdownEvent], now: Date, timeZone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let horizon = now.addingTimeInterval(48*3600)
        var dates: Set<Date> = [now, horizon]
        for event in events where event.isActive {
            let target = event.countdownDate(now: now, timeZone: timeZone)
            let boundaries = event.isAllDay ? [target] : [target, target.addingTimeInterval(-86400 + 1), target.addingTimeInterval(86400)]
            for boundary in boundaries where boundary > now && boundary <= horizon { dates.insert(boundary) }
        }
        var midnight = calendar.startOfDay(for: now)
        while let next = calendar.date(byAdding: .day, value: 1, to: midnight), next <= horizon {
            dates.insert(next); midnight = next
        }
        // Reload at the final entry, even if the budget truncates the 48-hour horizon.
        return Array(dates.sorted().prefix(64))
    }
}
