import Foundation
import AppKit
import SwiftUI

// Round-trip the production @Parameter primitive values. The public framework
// exposes no Codable serializer for a whole AppIntent; OS persistence is separate.
private struct StoredParameters: Codable, Equatable {
    let contentSource: WidgetContentSource
    let smartListID: String?
    let appearance: WidgetAppearance?
    let showAdvancedFilters: Bool
    let filter: WidgetFilter
    let largePageSize: Int
    let pagingID: String?
    let eventID: String?
    let manualMediumSelection: Bool
    let mediumEvent1ID: String?
    let mediumEvent2ID: String?
    let mediumEvent3ID: String?
    let showIcon: Bool
    let showTargetDate: Bool
    let showClock: Bool
    init(_ intent: SelectEventIntent) {
        contentSource = intent.contentSource
        smartListID = intent.smartListID
        appearance = intent.appearance
        showAdvancedFilters = intent.showAdvancedFilters
        filter = intent.filter; largePageSize = intent.largePageSize; pagingID = intent.pagingID
        eventID = intent.$eventID.wrappedValue
        manualMediumSelection = intent.$manualMediumSelection.wrappedValue
        mediumEvent1ID = intent.$mediumEvent1ID.wrappedValue
        mediumEvent2ID = intent.$mediumEvent2ID.wrappedValue
        mediumEvent3ID = intent.$mediumEvent3ID.wrappedValue
        showIcon = intent.$showIcon.wrappedValue
        showTargetDate = intent.$showTargetDate.wrappedValue
        showClock = intent.$showClock.wrappedValue
    }
    var restored: SelectEventIntent {
        let intent = SelectEventIntent()
        intent.contentSource = contentSource
        intent.smartListID = smartListID
        intent.appearance = appearance
        intent.showAdvancedFilters = showAdvancedFilters
        intent.dateScope = filter.scope; intent.includedTags = filter.includedTags; intent.excludedTags = filter.excludedTags
        intent.tagMatch = filter.tagMatch; intent.sortOrder = filter.sort; intent.prioritizePinned = filter.prioritizePinned; intent.skipCount = filter.skip
        intent.largePageSize = largePageSize
        intent.eventID = eventID
        intent.manualMediumSelection = manualMediumSelection
        intent.mediumEvent1ID = mediumEvent1ID
        intent.mediumEvent2ID = mediumEvent2ID
        intent.mediumEvent3ID = mediumEvent3ID
        intent.showIcon = showIcon
        intent.showTargetDate = showTargetDate
        intent.showClock = showClock
        return intent
    }
}

@main struct WidgetIntentProbe {
    static func main() async throws {
        precondition(!SelectEventIntent().showAdvancedFilters)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = CountdownEvent(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, title: "未来", targetDate: now.addingTimeInterval(3600))
        let past = CountdownEvent(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, title: "过去", targetDate: now.addingTimeInterval(-3600))
        let events = [past, future]
        let intent = SelectEventIntent()
        precondition(intent.filter == WidgetFilter())
        precondition(intent.largePageSize == 6 && intent.pagingID != nil)
        precondition(intent.pagingID == SelectEventIntent().pagingID)
        let originalPageID = intent.pagingID
        intent.showAdvancedFilters = true
        intent.dateScope = .upcoming
        intent.includedTags = ["工作", "会议"]
        intent.excludedTags = ["私人"]
        intent.tagMatch = .all
        intent.sortOrder = .nearest
        intent.skipCount = 1
        intent.prioritizePinned = false
        intent.largePageSize = 10
        precondition(intent.pagingID != originalPageID)
        let restoredFilter = try JSONDecoder().decode(StoredParameters.self, from: JSONEncoder().encode(StoredParameters(intent))).restored
        precondition(restoredFilter.showAdvancedFilters && restoredFilter.filter == intent.filter && restoredFilter.largePageSize == 10 && restoredFilter.pagingID == intent.pagingID)
        let filteredEntry = DayEntry(date: now, events: events, explicitID: nil, error: nil, filter: intent.filter, pageSize: 10, pagingID: intent.pagingID, pageIndex: 2)
        let futureEntry = filteredEntry.at(now.addingTimeInterval(60))
        precondition(futureEntry.filter == filteredEntry.filter && futureEntry.pagingID == filteredEntry.pagingID && futureEntry.pageIndex == 2)
        intent.dateScope = .all; intent.includedTags = []; intent.excludedTags = []; intent.sortOrder = .automatic; intent.skipCount = 0; intent.prioritizePinned = true
        precondition(intent.showIcon && intent.showTargetDate && intent.showClock)
        precondition(!intent.manualMediumSelection)
        precondition(intent.manualSelection.resolvedSlots(events: events).isEmpty)
        let noSelection = await ManualEventOptionsProvider().defaultResult()
        precondition(noSelection == WidgetManualSelection.noSelectionID)
        intent.manualMediumSelection = true
        intent.mediumEvent1ID = past.id.uuidString
        intent.mediumEvent2ID = future.id.uuidString
        intent.mediumEvent3ID = past.id.uuidString
        intent.appearance = nil // Legacy archive: no appearance preset.
        intent.showIcon = false
        intent.showTargetDate = false
        intent.showClock = false
        let entry = DayEntry(date: now, events: events, explicitID: past.id.uuidString, error: nil, displayOptions: intent.displayOptions, manualSelection: intent.manualSelection)
        let next = entry.at(now.addingTimeInterval(60))
        precondition(!next.displayOptions.showIcon && !next.displayOptions.showTargetDate && !next.displayOptions.showClock)
        precondition(next.explicitID == entry.explicitID && next.events == events)
        precondition(next.manualSelection == intent.manualSelection)
        precondition(next.manualSelection.resolvedSlots(events: events) == [.event(past), .event(future)])
        precondition(next.date != entry.date)
        for mask in 0..<8 {
            let variant = SelectEventIntent()
            variant.appearance = nil
            variant.showIcon = mask & 1 != 0
            variant.showTargetDate = mask & 2 != 0
            variant.showClock = mask & 4 != 0
            variant.manualMediumSelection = true
            variant.mediumEvent1ID = past.id.uuidString
            variant.mediumEvent2ID = "missing-id"
            variant.mediumEvent3ID = WidgetManualSelection.noSelectionID
            variant.eventID = future.id.uuidString
            let stored = StoredParameters(variant)
            let data = try JSONEncoder().encode(stored)
            let decoded = try JSONDecoder().decode(StoredParameters.self, from: data)
            precondition(decoded == stored)
            let restored = decoded.restored
            let item = DayEntry(date: now, events: events, explicitID: restored.explicitID, error: nil, displayOptions: restored.displayOptions, manualSelection: restored.manualSelection)
            let nextItem = item.at(now.addingTimeInterval(86400))
            precondition(nextItem.displayOptions == variant.displayOptions)
            precondition(nextItem.manualSelection == variant.manualSelection)
            precondition(nextItem.explicitID == future.id.uuidString)
            // Small selection remains scalar even when medium manual selection differs.
            precondition(nextItem.selection == .event(future))
            precondition(nextItem.manualSelection.resolvedSlots(events: events) == [.event(past), .unavailable("missing-id")])
        }
        let defaults = SelectEventIntent()
        precondition(defaults.showIcon && defaults.showTargetDate && defaults.showClock)
        precondition(DayEntry(date: now, events: events, explicitID: nil, error: nil).displayOptions == defaults.displayOptions)
        let chosen = Color(red: 0.2, green: 0.4, blue: 0.8)
        let customKey = EventTheme.key(for: chosen)!
        precondition(customKey == "#3366CC")
        let custom = CountdownEvent(title: "Custom color", targetDate: now, colorKey: customKey)
        let customRoundTrip = try EventRepository.decodeSnapshot(EventRepository.encodeSnapshot([custom]))
        precondition(customRoundTrip.first?.colorKey == customKey)
        let restoredColor = NSColor(EventTheme.color(for: customKey)).usingColorSpace(.sRGB)!
        precondition(abs(restoredColor.blueComponent - 0.8) < 0.01)
        precondition(EventTheme.color(for: "invalid") == EventTheme.color(for: "sage"))
        var swatches = Set<String>()
        for theme in EventTheme.all {
            let image = theme.menuSwatch
            precondition(!image.isTemplate && image.size.width == 16)
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
            swatches.insert("\(Int(color.redComponent * 255)),\(Int(color.greenComponent * 255)),\(Int(color.blueComponent * 255))")
        }
        precondition(swatches.count == 5, "Theme menu must contain five actual RGB swatches")
        print("Widget filters/stable configuration paging IDs/parameter values/future entry/RGB swatches PASS")
        print("Display parameters: defaults/explicit false/independent widgets/future timeline preservation PASS")
        print("Real @Parameter primitive encode/decode: all 8 display combinations/manual slots/legacy small selection PASS")
        let unavailableID = UUID().uuidString
        let invalid = DayEntry(date: now, events: events, explicitID: nil, error: "error", displayOptions: intent.displayOptions,
                               manualSelection: WidgetManualSelection(enabled: true, slotIDs: [unavailableID, "invalid-id", nil]))
        let invalidNext = invalid.at(now.addingTimeInterval(60))
        precondition(invalidNext.error == invalid.error && invalidNext.manualSelection == invalid.manualSelection)
        precondition(invalidNext.manualSelection.resolvedSlots(events: events) == [.unavailable(unavailableID), .unavailable("invalid-id")])
        precondition(WidgetPolicy.selection(events: events, explicitID: intent.explicitID, now: now) == .event(future))
        intent.eventID = nil
        precondition(WidgetPolicy.selection(events: events, explicitID: intent.explicitID, now: now) == .event(future))
        intent.eventID = "automatic"
        precondition(WidgetPolicy.selection(events: events, explicitID: intent.explicitID, now: now) == .event(future))
        intent.eventID = past.id.uuidString
        precondition(WidgetPolicy.selection(events: events, explicitID: intent.explicitID, now: now) == .event(past))
        let other = SelectEventIntent()
        precondition(WidgetPolicy.selection(events: events, explicitID: other.explicitID, now: now) == .event(future))
        precondition(WidgetPolicy.selection(events: [future], explicitID: intent.explicitID, now: now) == .missing)
        intent.eventID = ""
        precondition(WidgetPolicy.selection(events: events, explicitID: intent.explicitID, now: now) == .missing)
        intent.eventID = "invalid-id"
        precondition(WidgetPolicy.selection(events: events, explicitID: intent.explicitID, now: now) == .missing)
        print("Real SelectEventIntent: default/nil/automatic/UUID/independent intent/deleted/empty/invalid selection PASS")
    }
}
