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
        let tagLabel = event.tags.joined(separator: ", ")
        let subtitle: String = tagLabel.isEmpty ? dateLabel : "\(dateLabel) · \(tagLabel)"
        let titleAndTags: String = tagLabel.isEmpty ? event.title : "\(event.title) · \(tagLabel)"
        let tooltip = titleAndTags + L10n.text(" · 双击编辑")
        let lifecycleLabel: String = switch event.lifecycle {
        case .active: ""
        case .archived: L10n.text("已归档")
        case .trashed: L10n.text("在回收站中")
        }
        let spokenLabel = [event.title, event.isPinned ? L10n.text("已置顶") : "", lifecycleLabel, tagLabel, dateLabel, summary]
            .filter { !$0.isEmpty }.joined(separator: ", ")
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
                Text(verbatim: subtitle)
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
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        // The accessibility label excludes the clock, so second ticks do not alter speech.
        .accessibilityLabel(spokenLabel)

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
