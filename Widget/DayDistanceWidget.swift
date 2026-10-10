import WidgetKit
import SwiftUI
import OSLog

struct DayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        let sample = CountdownEvent(title: "下一个期待", targetDate: Date().addingTimeInterval(7*86400), symbol: "sun.max")
        return DayEntry(date: Date(), events: [sample], explicitID: nil, error: nil)
    }
    func snapshot(for configuration: SelectEventIntent, in context: Context) async -> DayEntry {
        read(configuration: configuration, at: Date())
    }
    func timeline(for configuration: SelectEventIntent, in context: Context) async -> Timeline<DayEntry> {
        let now = Date()
        let current = read(configuration: configuration, at: now)
        if current.error != nil { return Timeline(entries: [current], policy: .after(now.addingTimeInterval(900))) }
        let dates = WidgetPolicy.timelineDates(events: current.events, now: now, timeZone: .autoupdatingCurrent)
        let entries = dates.map { current.at($0) }
        return Timeline(entries: entries, policy: .atEnd)
    }
    private func read(configuration: SelectEventIntent, at date: Date) -> DayEntry {
        do {
            let events = try SharedContainer.repository().load()
            let requestedID = configuration.explicitID ?? "automatic"
            let selection = WidgetPolicy.selection(events: events, explicitID: configuration.explicitID, now: date)
            let resolvedID: String
            if case .event(let event) = selection { resolvedID = event.id.uuidString }
            else { resolvedID = String(describing: selection) }
            let manualSlots = configuration.manualSelection.resolvedSlots(events: events).map { slot in
                switch slot {
                case .event(let event): return event.id.uuidString
                case .unavailable(let id): return "unavailable:\(id)"
                }
            }.joined(separator: ",")
            Logger(subsystem: "local.daydistance.mac", category: "widget").info("Timeline loaded \(events.count) events; requested=\(requestedID, privacy: .public); resolved=\(resolvedID, privacy: .public); mediumManual=\(configuration.manualMediumSelection); mediumSlots=\(manualSlots, privacy: .public)")
            return DayEntry(date: date, events: events, explicitID: configuration.explicitID, error: nil, displayOptions: configuration.displayOptions, manualSelection: configuration.manualSelection)
        } catch {
            Logger(subsystem: "local.daydistance.mac", category: "widget").error("Timeline read failed: \(error.localizedDescription, privacy: .public)")
            return DayEntry(date: date, events: [], explicitID: configuration.explicitID, error: "暂时无法读取事件", displayOptions: configuration.displayOptions, manualSelection: configuration.manualSelection)
        }
    }
}

@main
struct DayDistanceWidget: Widget {
    let kind = "DayDistanceWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectEventIntent.self, provider: DayProvider()) { entry in
            DayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
        }
        .configurationDisplayName("日距")
        .description("显示事件日期和倒计天数。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
