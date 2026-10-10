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
    var selection: WidgetSelection { WidgetPolicy.selection(events: events, explicitID: explicitID, now: date) }
    // Every future entry must retain this particular widget's presentation.
    func at(_ date: Date) -> DayEntry {
        DayEntry(date: date, events: events, explicitID: explicitID, error: error, displayOptions: displayOptions, manualSelection: manualSelection)
    }
}
