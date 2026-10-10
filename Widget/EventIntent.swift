import AppIntents
import Foundation
import OSLog

// Store a primitive ID: local ad hoc builds cannot resolve AppEntity identities.
// Display labels are separate so duplicate names and renames keep the right event.
struct EventOptionsProvider: DynamicOptionsProvider {
    func defaultResult() async -> String? { "automatic" }
    func results() async throws -> IntentItemCollection<String> {
        let events = try SharedContainer.repository().load()
        let automatic = IntentItem<String>("automatic", title: LocalizedStringResource("自动选择"), subtitle: LocalizedStringResource("小号显示最近日子，中号显示概览"))
        let items = [automatic] + WidgetPolicy.sorted(events: events, now: Date()).map { event in
            IntentItem<String>(event.id.uuidString, title: "\(event.title)", subtitle: "\(event.dateLabel(now: Date()))")
        }
        Logger(subsystem: "local.daydistance.mac", category: "widget").info("Event options loaded \(events.count) events")
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }
}

struct ManualEventOptionsProvider: DynamicOptionsProvider {
    func defaultResult() async -> String? { WidgetManualSelection.noSelectionID }
    func results() async throws -> IntentItemCollection<String> {
        let events = try SharedContainer.repository().load()
        let none = IntentItem<String>(WidgetManualSelection.noSelectionID, title: LocalizedStringResource("不选择"))
        let items = [none] + WidgetPolicy.sorted(events: events, now: Date()).map { event in
            IntentItem<String>(event.id.uuidString, title: "\(event.title)", subtitle: "\(event.dateLabel(now: Date()))")
        }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }
}

struct SelectEventIntent: WidgetConfigurationIntent {
    static var title = LocalizedStringResource("选择一个日子")
    static var description = IntentDescription(LocalizedStringResource("小号默认显示最近的日子；中号默认显示概览。也可以指定一个事件。"))
    @Parameter(title: LocalizedStringResource("事件"), optionsProvider: EventOptionsProvider())
    var eventID: String?
    @Parameter(title: LocalizedStringResource("显示事件图标"), default: true)
    var showIcon: Bool
    @Parameter(title: LocalizedStringResource("显示目标日期"), default: true)
    var showTargetDate: Bool
    @Parameter(title: LocalizedStringResource("显示当天精确计时"), default: true)
    var showClock: Bool
    @Parameter(title: LocalizedStringResource("中号手动选择事件"), default: false)
    var manualMediumSelection: Bool
    @Parameter(title: LocalizedStringResource("中号第一个事件"), optionsProvider: ManualEventOptionsProvider())
    var mediumEvent1ID: String?
    @Parameter(title: LocalizedStringResource("中号第二个事件"), optionsProvider: ManualEventOptionsProvider())
    var mediumEvent2ID: String?
    @Parameter(title: LocalizedStringResource("中号第三个事件"), optionsProvider: ManualEventOptionsProvider())
    var mediumEvent3ID: String?
    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$eventID
            \.$showIcon
            \.$showTargetDate
            \.$showClock
            \.$manualMediumSelection
            \.$mediumEvent1ID
            \.$mediumEvent2ID
            \.$mediumEvent3ID
        }
    }
    init() { eventID = "automatic" }
    var explicitID: String? { eventID == "automatic" ? nil : eventID }
    var manualSelection: WidgetManualSelection {
        WidgetManualSelection(enabled: manualMediumSelection, slotIDs: [mediumEvent1ID, mediumEvent2ID, mediumEvent3ID])
    }
    var displayOptions: WidgetDisplayOptions {
        WidgetDisplayOptions(showIcon: showIcon, showTargetDate: showTargetDate, showClock: showClock)
    }
}
