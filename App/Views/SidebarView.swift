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

private enum SidebarSelection: Hashable { case category(EventFilter), smart(UUID) }

struct SidebarView: View {
    @Binding var selection: EventFilter?
    let events: [CountdownEvent]
    let now: Date
    @Binding var smartSelection: UUID?
    let smartLists: [SmartList]
    let canManage: Bool
    let canRecover: Bool
    let createSmartList: () -> Void
    let editSmartList: (SmartList) -> Void
    let copySmartList: (SmartList) -> Void
    let deleteSmartList: (SmartList) -> Void
    let showSmartBackups: () -> Void
    var body: some View {
        let counts = counts(at: now)
        List(selection: sidebarSelection) {
          ForEach(EventFilter.allCases) { filter in
            HStack {
                Label(filter.label, systemImage: filter.symbol)
                Spacer()
                Text("\(counts[filter, default: 0])")
                    .monospacedDigit().foregroundStyle(.secondary)
            }.tag(SidebarSelection.category(filter))
          }
          Section {
            ForEach(smartLists) { list in
                HStack { Label(list.name, systemImage: "line.3.horizontal.decrease.circle"); Spacer(); Text("\(list.evaluate(events: events, now: now).events.count)").monospacedDigit().foregroundStyle(.secondary) }
                .tag(SidebarSelection.smart(list.id))
                .contextMenu {
                    Button(L10n.text("编辑智能列表")) { editSmartList(list) }.disabled(!canManage)
                    Button(L10n.text("复制智能列表")) { copySmartList(list) }.disabled(!canManage)
                    Button(L10n.text("删除智能列表"), role: .destructive) { deleteSmartList(list) }.disabled(!canManage)
                }
            }
            Button(action: showSmartBackups) { Label(L10n.text("智能列表备份"), systemImage: "clock.arrow.circlepath") }.buttonStyle(.plain).disabled(!canRecover)
          } header: {
            HStack { Text(L10n.text("智能列表")); Spacer(); Button(action: createSmartList) { Image(systemName: "plus") }.buttonStyle(.borderless).disabled(!canManage).accessibilityLabel(L10n.text("新建智能列表")) }.accessibilityElement(children: .contain)
          }
        }.listStyle(.sidebar)
    }
    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(get: { smartSelection.map(SidebarSelection.smart) ?? selection.map(SidebarSelection.category) }, set: { value in
            guard let value else { return }
            switch value {
            case .category(let filter): smartSelection = nil; selection = filter
            case .smart(let id): smartSelection = id; selection = nil
            }
        })
    }
    private func counts(at now: Date) -> [EventFilter: Int] {
        var result: [EventFilter: Int] = [:]
        for event in events {
            switch event.lifecycle {
            case .active:
                result[.all, default: 0] += 1
                result[event.isUpcoming(at: now) ? .upcoming : .past, default: 0] += 1
            case .archived: result[.archived, default: 0] += 1
            case .trashed: result[.trash, default: 0] += 1
            }
        }
        return result
    }
}
