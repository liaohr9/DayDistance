import SwiftUI

enum EventFilter: String, CaseIterable, Identifiable {
    case all = "全部事件", upcoming = "即将到来", past = "已经过去", archived = "归档", trash = "回收站"
    var label: String { L10n.text(rawValue) }
    var id: Self { self }
    var symbol: String {
        switch self { case .all: return "calendar"; case .upcoming: return "clock"; case .past: return "clock.arrow.circlepath"; case .archived: return "archivebox"; case .trash: return "trash" }
    }
    func accepts(_ event: CountdownEvent, now: Date) -> Bool {
        switch self { case .all: return event.isActive; case .upcoming: return event.isActive && event.isUpcoming(at: now); case .past: return event.isActive && !event.isUpcoming(at: now); case .archived: return event.lifecycle == .archived; case .trash: return event.lifecycle == .trashed }
    }
}

struct SidebarView: View {
    @Binding var selection: EventFilter?
    let events: [CountdownEvent]
    let now: Date
    var body: some View {
        List(EventFilter.allCases, selection: $selection) { filter in
            HStack {
                Label(filter.label, systemImage: filter.symbol)
                Spacer()
                Text("\(events.filter { filter.accepts($0, now: now) }.count)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }.tag(filter)
        }.listStyle(.sidebar)
    }
}
