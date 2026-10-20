import Foundation
@main struct WidgetSmartListProbe {
    static func main() throws {
        let now = Date()
        let original = CountdownEvent(title: "Work", targetDate: now.addingTimeInterval(3*86400))
        let other = CountdownEvent(title: "Holiday", targetDate: now.addingTimeInterval(5*86400))
        let intent = SelectEventIntent()
        intent.appearance = nil; intent.showIcon = false; intent.showTargetDate = true; intent.showClock = false
        precondition(intent.displayOptions == WidgetDisplayOptions(showIcon: false, showTargetDate: true, showClock: false))
        intent.appearance = .standard
        precondition(intent.displayOptions == WidgetDisplayOptions())
        intent.appearance = .compact
        precondition(intent.displayOptions == WidgetDisplayOptions(showIcon: false, showTargetDate: false, showClock: false))
        intent.appearance = .custom
        precondition(!intent.displayOptions.showIcon && intent.displayOptions.showTargetDate && !intent.displayOptions.showClock)
        let list = SmartList(name: "Work only", rules: [SmartRule(field: .title, comparison: .equals, text: "Work")])
        intent.contentSource = .smartList; intent.smartListID = list.id.uuidString
        intent.manualMediumSelection = true; intent.mediumEvent1ID = other.id.uuidString
        precondition(intent.isSmartList && intent.explicitID == nil)
        let entry = intent.makeEntry(events: [original,other], smartLists: [list], at: now)
        precondition(entry.error == nil && !entry.manualSelection.enabled)
        precondition(entry.automaticEvents.map(\.id) == [original.id])
        precondition(entry.at(now.addingTimeInterval(86400)).smartList?.id == list.id)
        precondition(entry.pageSignature == list.signature(pageSize: entry.pageSize))
        precondition(intent.makeEntry(events: [original,other], smartLists: [], at: now).error != nil)
        let ordinary = SmartList(name: "Saved", kind: .ordinary, eventIDs: [other.id])
        intent.smartListID = ordinary.id.uuidString
        precondition(intent.makeEntry(events: [original, other], smartLists: [ordinary], at: now).automaticEvents.map(\.id) == [other.id])
        intent.smartListID = "invalid"
        precondition(intent.makeEntry(events: [original,other], smartLists: [list], at: now).error != nil)
        intent.contentSource = .events; intent.smartListID = nil; intent.eventID = original.id.uuidString
        precondition(!intent.isSmartList && intent.explicitID == original.id.uuidString)
        print("SMART_WIDGET_PASS: legacy flags, appearance presets, smart prefix, manual precedence, future rules, fail-closed missing/invalid selection")
    }
}
