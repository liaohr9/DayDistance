import SwiftUI

struct EventRow: View {
    let event: CountdownEvent
    let now: Date
    let isSelected: Bool
    var paused = false
    var body: some View {
        TimelineView(EventTimelineSchedule(events: [event], paused: paused, includeClock: true, referenceDate: now)) { context in
            EventRowContent(event: event, now: context.date, isSelected: isSelected)
        }
    }
}

private struct EventRowContent: View {
    let event: CountdownEvent
    let now: Date
    let isSelected: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let value = DayCounter.snapshot(event: event, now: now)
        let dateLabel = event.dateLabel(now: now)
        let summary = EventDisplayFormatter.summary(event: event, now: now)
        HStack(spacing: 12) {
            Image(systemName: event.symbol)
                .accessibilityHidden(true)
                .font(.title3).foregroundStyle(isSelected || contrast == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(EventTheme.color(for: event.colorKey)))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(event.title).font(.body.weight(.medium)).lineLimit(1)
                    if event.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true) }
                }
                Text(dateLabel + (event.tags.isEmpty ? "" : " · " + event.tags.joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 4) {
                Text(summary)
                    .font(.body.weight(.medium)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.8)
                if value.showsClock {
                    Text(value.clockLabel).accessibilityHidden(true).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }.frame(maxWidth: 300, alignment: .trailing)
        }
        .frame(height: 52)
        .contentShape(Rectangle())
        .help(event.title + (event.tags.isEmpty ? "" : " · " + event.tags.joined(separator: ", ")) + L10n.text(" · 双击编辑"))
        .accessibilityElement(children: .ignore)
        // The accessibility label excludes the clock, so second ticks do not alter speech.
        .accessibilityLabel([event.title, event.isPinned ? L10n.text("已置顶") : "", event.lifecycle == .archived ? L10n.text("已归档") : (event.lifecycle == .trashed ? L10n.text("在回收站中") : ""), event.tags.joined(separator: ", "), dateLabel, summary].filter { !$0.isEmpty }.joined(separator: ", "))

    }
}

/// Finite when paused, otherwise advances directly to the next meaningful change.
struct EventTimelineSchedule: TimelineSchedule {
    var events: [CountdownEvent]
    var paused = false
    var includeClock = false
    var referenceDate = Date.distantPast
    var smartList: SmartList? = nil
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        AnySequence {
            var next: Date? = startDate
            return AnyIterator<Date> {
                guard let date = next else { return nil }
                if paused { next = nil }
                else {
                    let standard = EventRefreshPolicy.nextUpdate(events: events, after: date, includeClock: includeClock)
                    next = min(standard, smartList?.nextUpdate(events: events, after: date) ?? standard)
                }
                return date
            }
        }
    }
}
