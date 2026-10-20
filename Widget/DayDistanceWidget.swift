import WidgetKit
import SwiftUI
import OSLog

struct DayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        let sample = CountdownEvent(title: L10n.text("下一个期待"), targetDate: Date().addingTimeInterval(7*86400), symbol: "sun.max")
        return DayEntry(date: Date(), events: [sample], explicitID: nil, error: nil)
    }
    func snapshot(for configuration: SelectEventIntent, in context: Context) async -> DayEntry {
        read(configuration: configuration, at: Date())
    }
    func timeline(for configuration: SelectEventIntent, in context: Context) async -> Timeline<DayEntry> {
        let now = Date()
        let current = read(configuration: configuration, at: now)
        if current.error != nil { return Timeline(entries: [current], policy: .after(now.addingTimeInterval(900))) }
        // Explicit/manual slots cannot be changed by automatic sorting. A hidden
        // today event must not cause minute archives for an unrelated selection.
        let clockEventIDs: Set<UUID>?
        if context.family == .systemMedium && current.manualSelection.enabled {
            clockEventIDs = Set(current.manualSelection.resolvedSlots(events: current.events, now: now).compactMap { slot in
                if case .event(let event) = slot { return event.id }
                return nil
            })
        } else if let id = current.explicitID {
            clockEventIDs = Set(UUID(uuidString: id).map { [$0] } ?? [])
        } else { clockEventIDs = nil }
        var dates = WidgetPolicy.timelineDates(events: current.events, now: now, timeZone: .autoupdatingCurrent,
                                               includeTodayClock: current.displayOptions.showClock, clockEventIDs: clockEventIDs)
        if let list = current.smartList {
            let horizon = now.addingTimeInterval(48 * 3600)
            var cursor = now
            for _ in 0..<63 {
                let next = list.nextUpdate(events: current.events, after: cursor)
                guard next > cursor, next <= horizon else { break }
                dates.append(next); cursor = next
            }
            dates = Array(Set(dates).sorted().prefix(64))
        }
        let entries = dates.map { current.at($0) }
        return Timeline(entries: entries, policy: .atEnd)
    }
    private func read(configuration: SelectEventIntent, at date: Date) -> DayEntry {
        SharedContainer.prepareWidgetLanguage()
        do {
            let events = try SharedContainer.repository().load()
            let lists = configuration.isSmartList ? try SmartListRepository(fileURL: SharedContainer.smartListFileURL()).load() : []
            var entry = configuration.makeEntry(events: events, smartLists: lists, at: date)
            entry.pageIndex = entry.pagingID.flatMap { id in
                (try? WidgetPageStore(directory: SharedContainer.widgetPageDirectory()))?.load(id: id, signature: entry.pageSignature)
            } ?? 0
            let requestedID = configuration.explicitID ?? "automatic"
            let selection = entry.selection
            let resolvedID: String
            if case .event(let event) = selection { resolvedID = event.id.uuidString }
            else { resolvedID = String(describing: selection) }
            let manualSlots = configuration.manualSelection.resolvedSlots(events: events).map { slot in
                switch slot {
                case .event(let event): return event.id.uuidString
                case .unavailable(let id): return "unavailable:\(id)"
                }
            }.joined(separator: ",")
            Logger(subsystem: "local.daydistance.mac", category: "widget").info("Timeline loaded \(events.count) events; language=\(L10n.currentLanguage.rawValue, privacy: .public); requested=\(requestedID, privacy: .public); resolved=\(resolvedID, privacy: .public); pageID=\(entry.pagingID ?? "nil", privacy: .public); page=\(entry.pageIndex); mediumManual=\(configuration.manualMediumSelection); mediumSlots=\(manualSlots, privacy: .public)")
            return entry
        } catch {
            Logger(subsystem: "local.daydistance.mac", category: "widget").error("Timeline read failed: \(error.localizedDescription, privacy: .public)")
            return DayEntry(date: date, events: [], explicitID: configuration.explicitID, error: configuration.isSmartList ? "暂时无法读取智能列表" : "暂时无法读取事件", displayOptions: configuration.displayOptions, manualSelection: configuration.manualSelection, filter: configuration.filter)
        }
    }
}

@main
struct DayDistanceWidget: Widget {
    let kind = "DayDistanceWidget"
    init() { SharedContainer.prepareWidgetLanguage() }
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectEventIntent.self, provider: DayProvider()) { entry in
            DayWidgetView(entry: entry)
                .environment(\.locale, L10n.locale)
                .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
        }
        .configurationDisplayName("日距")
        .description("显示事件日期和倒计天数。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
