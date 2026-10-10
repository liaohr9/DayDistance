import Foundation

/// Manual medium widgets preserve the user's order, including unavailable slots.
/// This configuration never participates in the legacy small-widget selection.
struct WidgetManualSelection: Equatable {
    static let noSelectionID = "none"
    var enabled = false
    var slotIDs: [String?] = []

    func resolvedSlots(events: [CountdownEvent]) -> [WidgetManualSlot] {
        var seen = Set<String>()
        return slotIDs.prefix(3).compactMap { rawID in
            guard let rawID, !rawID.isEmpty, rawID != Self.noSelectionID else { return nil }
            let uuid = UUID(uuidString: rawID)
            let identity = uuid?.uuidString ?? rawID
            guard seen.insert(identity).inserted else { return nil }
            guard let uuid, let event = events.first(where: { $0.id == uuid && $0.isActive }) else {
                return .unavailable(identity)
            }
            return .event(event)
        }
    }
}

enum WidgetManualSlot: Equatable, Identifiable {
    case event(CountdownEvent)
    case unavailable(String)

    var id: String {
        switch self {
        case .event(let event): return event.id.uuidString
        case .unavailable(let id): return id
        }
    }
}
