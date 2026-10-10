import AppIntents
import Foundation

/// Primitive UUID values also work with local ad hoc builds, without AppEntity registration.
struct CountdownEventOptionsProvider: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> IntentItemCollection<String> {
        let now = Date()
        let events = try ShortcutEventService.shared.activeEvents()
        let items = events.map { event in
            IntentItem<String>(event.id.uuidString, title: "\(event.title)",
                               subtitle: "\(event.dateLabel(now: now)) · \(event.id.uuidString)")
        }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }
}
