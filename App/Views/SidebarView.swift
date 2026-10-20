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
    let createNode: (ListKind, UUID?) -> Void
    let editSmartList: (SmartList) -> Void
    let copySmartList: (SmartList) -> Void
    let deleteSmartList: (SmartList) -> Void
    let moveNode: (SmartList, UUID?) -> Void
    let showSmartBackups: () -> Void
    var body: some View {
        let counts = counts(at: now)
        List(selection: sidebarSelection) {
            ForEach(EventFilter.allCases) { filter in
                HStack {
                    Label(filter.label, systemImage: filter.symbol)
                    Spacer()
                    Text("\(counts[filter, default: 0])").monospacedDigit().foregroundStyle(.secondary)
                }.tag(SidebarSelection.category(filter))
            }
            Section {
                ForEach(smartLists.filter { $0.parentID == nil }) { list in
                    SidebarTreeNode(list: list, lists: smartLists, events: events, now: now,
                        canManage: canManage, create: createNode, edit: editSmartList,
                        copy: copySmartList, delete: deleteSmartList, move: moveNode)
                }
            } header: {
                HStack {
                    Text(L10n.text("列表"))
                    Spacer()
                    SidebarAddMenu(canManage: canManage, canRecover: canRecover,
                        create: { createNode($0, nil) }, recover: showSmartBackups)
                        .frame(width: 22, height: 22)
                }.accessibilityElement(children: .contain)
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

private struct SidebarTreeNode: View {
    let list: SmartList
    let lists: [SmartList]
    let events: [CountdownEvent]
    let now: Date
    let canManage: Bool
    let create: (ListKind, UUID?) -> Void
    let edit: (SmartList) -> Void
    let copy: (SmartList) -> Void
    let delete: (SmartList) -> Void
    let move: (SmartList, UUID?) -> Void
    @State private var expanded = true
    var body: some View {
        Group {
            if list.kind == .folder {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(lists.filter { $0.parentID == list.id }) { child in
                        SidebarTreeNode(list: child, lists: lists, events: events, now: now, canManage: canManage,
                            create: create, edit: edit, copy: copy, delete: delete, move: move)
                    }
                } label: { row }
            } else { row }
        }
        .tag(SidebarSelection.smart(list.id))
    }
    @ViewBuilder private var nodeMenu: some View {
            if list.kind == .folder {
                Button(L10n.text("新建列表")) { create(.ordinary, list.id) }
                Button(L10n.text("新建智能列表")) { create(.smart, list.id) }
                Button(L10n.text("新建文件夹")) { create(.folder, list.id) }
                Divider()
            }
            Button(L10n.text(list.kind == .smart ? "编辑智能列表" : "重命名与位置…")) { edit(list) }
            Menu(L10n.text("移到文件夹")) {
                Button(L10n.text("最外层")) { move(list, nil) }.disabled(list.parentID == nil)
                let excluded = ListHierarchy.descendants(of: list.id, in: lists)
                ForEach(lists.filter { $0.kind == .folder && !excluded.contains($0.id) }) { folder in
                    Button(ListHierarchy.path(for: folder, in: lists)) { move(list, folder.id) }.disabled(list.parentID == folder.id)
                }
            }
            if list.kind == .smart { Button(L10n.text("复制智能列表")) { copy(list) } }
            Divider()
            Button(L10n.text(list.kind == .folder ? "删除文件夹…" : "删除列表…"), role: .destructive) { delete(list) }
    }
    private var row: some View {
        HStack {
            Label(list.name, systemImage: list.symbol).lineLimit(1)
            Spacer(minLength: 4)
            if list.kind != .folder {
                Text("\(list.evaluate(events: events, now: now).events.count)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }.help(ListHierarchy.path(for: list, in: lists))
            .contextMenu { nodeMenu.disabled(!canManage) }
    }
}


/// A native menu button keeps the section-header hit target and accessibility action
/// independent of the List row. No disclosure arrow or footer control is needed.
private struct SidebarAddMenu: NSViewRepresentable {
    let canManage: Bool
    let canRecover: Bool
    let create: (ListKind) -> Void
    let recover: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.imagePosition = .imageOnly
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        let menu = NSMenu()
        menu.autoenablesItems = false
        let label = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        label.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        menu.addItem(label)
        for index in 0..<4 {
            if index == 3 { menu.addItem(.separator()) }
            let item = NSMenuItem(title: "", action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            item.tag = index; item.target = context.coordinator
            menu.addItem(item)
        }
        button.menu = menu
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.create = create
        context.coordinator.recover = recover
        button.isEnabled = canManage || canRecover
        button.setAccessibilityLabel(L10n.text("添加列表或文件夹"))
        button.toolTip = L10n.text("添加列表或文件夹")
        let titles = ["新建列表", "新建智能列表", "新建文件夹", "列表备份…"]
        for item in button.menu?.items.dropFirst() ?? [] where !item.isSeparatorItem {
            item.title = L10n.text(titles[item.tag])
            item.isEnabled = item.tag == 3 ? canRecover : canManage
        }
    }
    final class Coordinator: NSObject {
        var create: ((ListKind) -> Void)?
        var recover: (() -> Void)?
        @objc func choose(_ item: NSMenuItem) {
            guard item.isEnabled else { return }
            switch item.tag {
            case 0: create?(.ordinary)
            case 1: create?(.smart)
            case 2: create?(.folder)
            case 3: recover?()
            default: break
            }
        }
    }
}
