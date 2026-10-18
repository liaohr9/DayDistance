import Foundation
import WidgetKit

struct WidgetDisplayOptions: Equatable {
    var showIcon = true
    var showTargetDate = true
    var showClock = true
}

struct DayEntry: TimelineEntry {
    let date: Date
    let events: [CountdownEvent]
    let explicitID: String?
    let error: String?
    var displayOptions = WidgetDisplayOptions()
    var manualSelection = WidgetManualSelection()
    var filter = WidgetFilter()
    var pageSize = 6
    var pagingID: String?
    var pageIndex = 0
    var smartList: SmartList?
    var pageSignature: String { smartList?.signature(pageSize: pageSize) ?? filter.signature(pageSize: pageSize) }
    var automaticEvents: [CountdownEvent] { smartList?.evaluate(events: events, now: date).events ?? filter.apply(events: events, now: date) }
    var page: WidgetPage { WidgetPage(events: automaticEvents, page: pageIndex, pageSize: pageSize) }
    var selection: WidgetSelection {
        if smartList != nil { return automaticEvents.first.map(WidgetSelection.event) ?? .empty }
        return WidgetPolicy.selection(events: events, explicitID: explicitID, now: date)
    }
    // Every future entry must retain this particular widget's presentation.
    func at(_ date: Date) -> DayEntry {
        DayEntry(date: date, events: events, explicitID: explicitID, error: error, displayOptions: displayOptions, manualSelection: manualSelection, filter: filter, pageSize: pageSize, pagingID: pagingID, pageIndex: pageIndex, smartList: smartList)
    }
}
