import SwiftUI
import WidgetKit

struct DayWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family
    var body: some View { DayWidgetContent(entry: entry, family: family) }
}

struct DayWidgetContent: View {
    let entry: DayEntry
    let family: WidgetFamily
    private let sage = EventTheme.color(for: "sage")
    var body: some View {
        Group {
            if let error = entry.error {
                message(error, symbol: "exclamationmark.triangle", detail: "打开日距，检查数据访问")
            } else if family == .systemMedium && entry.manualSelection.enabled {
                manualOverview
            } else if entry.selection == .missing {
                message("事件不可用", symbol: "calendar.badge.exclamationmark", detail: "编辑小组件，重新选择")
            } else if entry.selection == .empty {
                message(entry.events.isEmpty ? "添加你的第一个日子" : "没有可显示的事件", symbol: "calendar.badge.plus", detail: entry.events.isEmpty ? "打开日距，记录一个期待" : "打开日距，恢复或新建事件")
            } else if family == .systemMedium && entry.explicitID == nil {
                overview
            } else if case .event(let event) = entry.selection {
                single(event)
                    .widgetURL(URL(string: "daydistance://event/\(event.id.uuidString)"))
            }
        }
    }
    private func message(_ title: String, symbol: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(sage)
            Text(L10n.text(title)).font(.headline)
            Text(L10n.text(detail)).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "daydistance://open"))
    }
    private func single(_ event: CountdownEvent) -> some View {
        let value = DayCounter.snapshot(event: event, now: entry.date)
        let color = EventTheme.color(for: event.colorKey)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if entry.displayOptions.showIcon { Image(systemName: event.symbol).foregroundStyle(color).accessibilityHidden(true) }
                Text(event.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if event.displayFormat == .days {
                    Text(value.dayLabel)
                        .font(.system(size: value.days == 0 ? 36 : 52, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1).monospacedDigit()
                    if value.days != 0 { Text(value.dayUnit).font(.callout) }
                } else {
                    Text(EventDisplayFormatter.duration(event: event, now: entry.date))
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.65).lineLimit(2).monospacedDigit()
                }
                Spacer(minLength: 0)
            }.foregroundStyle(color)
            HStack(spacing: 5) {
                Text(value.direction(for: event))
                if value.showsClock && entry.displayOptions.showClock { Text(event.countdownDate(now: entry.date), style: .timer).monospacedDigit() }
            }.font(.caption).foregroundStyle(color)
            if entry.displayOptions.showTargetDate {
                Text(event.dateLabel(now: entry.date))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(WidgetPolicy.sorted(events: entry.events, now: entry.date).prefix(3))) { event in
                overviewRow(event)
            }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder private var manualOverview: some View {
        let slots = entry.manualSelection.resolvedSlots(events: entry.events)
        if slots.isEmpty {
            message("选择要显示的日子", symbol: "calendar.badge.plus", detail: "编辑小组件，选择最多三个事件")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(slots) { slot in
                    switch slot {
                    case .event(let event): overviewRow(event)
                    case .unavailable:
                        Link(destination: URL(string: "daydistance://open")!) {
                            HStack(spacing: 10) {
                                if entry.displayOptions.showIcon {
                                    Image(systemName: "calendar.badge.exclamationmark").accessibilityHidden(true).frame(width: 25).foregroundStyle(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.text("事件不可用")).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(L10n.text("编辑小组件，重新选择")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func overviewRow(_ event: CountdownEvent) -> some View {
        Link(destination: URL(string: "daydistance://event/\(event.id.uuidString)")!) {
            let value = DayCounter.snapshot(event: event, now: entry.date)
            HStack(spacing: 10) {
                if entry.displayOptions.showIcon {
                    Image(systemName: event.symbol).accessibilityHidden(true).frame(width: 25).foregroundStyle(EventTheme.color(for: event.colorKey))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if value.showsClock && entry.displayOptions.showClock {
                        Text(event.countdownDate(now: entry.date), style: .timer).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    } else if entry.displayOptions.showTargetDate {
                        Text(event.dateLabel(now: entry.date)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                Text(EventDisplayFormatter.summary(event: event, now: entry.date))
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(EventTheme.color(for: event.colorKey))
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
        }
    }
}
