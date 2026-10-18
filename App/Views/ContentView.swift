import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct EventActions {
    let hasSelection: Bool
    let canEdit: Bool
    let canCreate: Bool
    let canTransfer: Bool
    let canArchive: Bool
    let canRestore: Bool
    let archive: () -> Void
    let restore: () -> Void
    let canDuplicate: Bool
    let duplicate: () -> Void
    let canShare: Bool
    let copySummary: () -> Void
    let share: () -> Void
    let canSearch: Bool
    let create: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let importEvents: () -> Void
    let exportEvents: () -> Void
    let searchEvents: () -> Void
}
private struct EventActionsKey: FocusedValueKey { typealias Value = EventActions }
extension FocusedValues {
    var eventActions: EventActions? {
        get { self[EventActionsKey.self] }
        set { self[EventActionsKey.self] = newValue }
    }
}

struct ContentView: View {
    @Bindable var store: EventStore
    @State private var smartStore: SmartListStore
    @State private var smartSelection: UUID?
    init(store: EventStore) {
        self.store = store
        _smartStore = State(initialValue: SmartListStore(repositoryProvider: { [weak store] in
            guard store?.isLoaded == true else { return nil }
            return store?.smartListRepository()
        }))
    }
    @AppStorage("eventSortOrder") private var sortOrder = EventSortOrder.date
    @AppStorage("hasShownWidgetHint") private var hasShownWidgetHint = false
    @State private var showWidgetHint = false
    @State private var shareEvent: CountdownEvent?
    @Environment(\.openWindow) private var openWindow
    @State private var filter: EventFilter? = .all
    @State private var search = ""
    @State private var calendarReference = Date.distantPast
    @State private var selectedIDs: Set<UUID> = []
    @State private var vimNavigation = VimListNavigation()
    @State private var vimSequence = VimKeySequence()
    @State private var keyboardSelection: Set<UUID>?
    @AppStorage("vimKeysEnabled") private var vimKeysEnabled = true
    @State private var pendingDelete: [CountdownEvent]?
    @State private var isImporting = false
    @State private var transferMessage: String?
    @FocusState private var eventListFocused: Bool
    private var selectedEvents: [CountdownEvent] {
        guard smartSelection == nil || smartStore.isLoaded else { return [] }
        return store.events.filter { selectedIDs.contains($0.id) }
    }
    // Recheck time-sensitive rules at the action boundary as well as on timeline updates.
    private var currentSelectedEvents: [CountdownEvent] { visibleEvents(now: Date()).filter { selectedIDs.contains($0.id) } }
    private var currentSelectedEvent: CountdownEvent? {
        let events = currentSelectedEvents
        return events.count == 1 ? events.first : nil
    }
    private var selectedEvent: CountdownEvent? { selectedEvents.count == 1 ? selectedEvents.first : nil }
    private var deletingPermanently: Bool { pendingDelete?.allSatisfy { $0.lifecycle == .trashed } == true }
    private var isPresentingModal: Bool { store.editingEvent != nil || pendingDelete != nil || store.isTransferring || transferMessage != nil || store.isShowingBackups || shareEvent != nil || smartStore.isPresentingModal }

    var body: some View {
        eventMonitoringContent
        .onOpenURL { url in
            guard !isPresentingModal else { return }
            smartSelection = nil
            filter = EventFilter.all
            search = ""
            store.open(url)
            selectedIDs = store.editingEvent.map { [$0.event.id] } ?? []
        }
        .sheet(item: $store.editingEvent) { session in
            EventEditor(session: session, store: store).appLanguage()
        }
        .alert(deletingPermanently ? L10n.text("永久删除所选事件？") : L10n.text("删除事件？"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button(L10n.text(deletingPermanently ? "永久删除" : "移到回收站"), role: .destructive) {
                guard let events = pendingDelete else { return }
                let operation: EventBatchOperation = deletingPermanently ? .permanentlyDelete : .trash
                pendingDelete = nil; updateHistoryModal()
                if store.batch(operation, events: events) { clearSelection() }
            }
        } message: {
            Text(deletingPermanently ? L10n.text("所选事件将从回收站移除。自动备份中的副本仍会保留。") : L10n.format("%ld 个事件将移到回收站，可随时恢复。", pendingDelete?.count ?? 0))
        }
    }

    private var eventActions: EventActions {
        EventActions(hasSelection: store.isLoaded && !selectedEvents.isEmpty && !isPresentingModal, canEdit: store.isLoaded && selectedEvent?.isActive == true && !isPresentingModal, canCreate: store.isLoaded && !isPresentingModal, canTransfer: store.isLoaded && !isPresentingModal, canArchive: store.isLoaded && !selectedEvents.isEmpty && selectedEvents.allSatisfy { $0.isActive } && !isPresentingModal, canRestore: store.isLoaded && !selectedEvents.isEmpty && selectedEvents.allSatisfy { !$0.isActive } && !isPresentingModal, archive: archiveSelected, restore: restoreSelected, canDuplicate: store.isLoaded && selectedEvent != nil && selectedEvent?.lifecycle != .trashed && !isPresentingModal, duplicate: duplicateSelected, canShare: store.isLoaded && selectedEvent != nil && !isPresentingModal, copySummary: copySelectedSummary, share: shareSelected, canSearch: store.isLoaded && !isPresentingModal, create: createEvent, edit: editSelected, delete: deleteSelected, importEvents: beginImport, exportEvents: beginExport, searchEvents: focusSearch)
    }

    private var smartListContent: some View {
        navigationContent
        .onAppear { smartStore.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !isPresentingModal { smartStore.reload() }
        }
        .onChange(of: store.isLoaded) { if store.isLoaded { smartStore.reload() } }
        .onChange(of: smartStore.isPresentingModal) { store.isSmartListModalPresented = smartStore.isPresentingModal }
        .onChange(of: smartSelection) { clearSelection() }
        .onChange(of: smartStore.lists) { selectedIDs.formIntersection(Set(visibleEvents(now: Date()).map(\.id))) }
        .sheet(isPresented: Binding(get: { smartStore.draft != nil }, set: { if !$0 { smartStore.cancel() } })) { SmartListEditor(store: smartStore, events: store.events).appLanguage() }
        .sheet(isPresented: $smartStore.isShowingBackups) { SmartListBackupsView(store: smartStore).appLanguage() }
        .alert(L10n.text("删除智能列表？"), isPresented: Binding(get: { smartStore.pendingDelete != nil }, set: { if !$0 { smartStore.pendingDelete = nil } })) {
            Button(L10n.text("取消"), role: .cancel) { smartStore.pendingDelete = nil }
            Button(L10n.text("删除"), role: .destructive) { _ = smartStore.confirmDelete() }
        } message: { Text(L10n.text("事件保持不变；使用此列表的小组件会提示列表不存在。")) }
        .onChange(of: shareEvent) { updateHistoryModal() }
        .sheet(item: $shareEvent) { event in EventShareView(event: event, now: Date(), store: store).appLanguage() }
        .onChange(of: pendingDelete) { updateHistoryModal() }
        .onChange(of: transferMessage) { updateHistoryModal() }
        .sheet(isPresented: $store.isShowingBackups) { BackupsView(store: store).appLanguage() }
        .focusedSceneValue(\.eventActions, eventActions)
    }

    private var eventMonitoringContent: some View {
        smartListContent
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            store.isTransferring = false
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if let count = store.importEvents(data) {
                    transferMessage = count == 0 ? L10n.text("没有新增事件。") : L10n.format("已导入 %ld 个事件。", count)
                }
            } catch { store.errorMessage = L10n.format("导入失败，原数据已保留：%@", error.localizedDescription) }
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsRouting.dataRequested)) { note in
            guard store.canManageData, !isPresentingModal, let raw = note.object as? String,
                  let action = SettingsDataAction(rawValue: raw) else { return }
            switch action { case .importEvents: beginImport(); case .exportEvents: beginExport(); case .backups: store.isShowingBackups = true }
        }
        .onChange(of: isImporting) { if !isImporting { store.isTransferring = false } }
        .alert("导入完成", isPresented: Binding(get: { transferMessage != nil }, set: { if !$0 { transferMessage = nil } })) {
            Button("好", role: .cancel) { transferMessage = nil }
        } message: { Text(transferMessage ?? "") }
                .onAppear { offerWidgetHint() }
        .onChange(of: store.firstEventAdded) { offerWidgetHint() }
        .onChange(of: store.events) {
            selectedIDs.formIntersection(Set(visibleEvents(now: Date()).map(\.id)))
            if let cursor = vimNavigation.cursor, !store.events.contains(where: { $0.id == cursor }) { vimNavigation = VimListNavigation() }
        }
        .onChange(of: store.editingEvent?.id) {
            if let session = store.editingEvent, session.original == nil { smartSelection = nil; filter = EventFilter.all; search = "" }
        }
        .onChange(of: filter) { clearSelection() }
        .onChange(of: search) { clearSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged),
                   NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification))
            .receive(on: RunLoop.main)) { _ in calendarReference = Date() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in calendarReference = Date() }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    private var navigationContent: some View {
        // Only time-dependent content ticks. Rebuilding the native toolbar
        // every second dismisses an open menu before a user can select an item.
        NavigationSplitView {
            TimelineView(EventTimelineSchedule(events: store.events, paused: isPresentingModal, referenceDate: calendarReference)) { context in
                SidebarView(selection: $filter, events: store.events, now: context.date, smartSelection: $smartSelection, smartLists: smartStore.isLoaded ? smartStore.lists : [], canManage: store.isLoaded && smartStore.isLoaded && !isPresentingModal, canRecover: store.isLoaded && !isPresentingModal, createSmartList: { smartStore.begin() }, editSmartList: { smartStore.begin($0) }, copySmartList: { smartStore.begin($0, copy: true) }, deleteSmartList: { smartStore.pendingDelete = $0 }, showSmartBackups: { smartStore.isShowingBackups = true })
                    .disabled(isPresentingModal)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            TimelineView(EventTimelineSchedule(events: store.events, paused: isPresentingModal, referenceDate: calendarReference,
                smartList: smartStore.isLoaded ? smartStore.lists.first(where: { $0.id == smartSelection }) : nil)) { context in
                detail(now: context.date)
            }
        }
        .navigationTitle(smartSelection == nil ? (filter?.label ?? EventFilter.all.label) : (smartStore.lists.first { $0.id == smartSelection }?.name ?? L10n.text("智能列表不存在")))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NativeEventSortMenu(selection: $sortOrder, isEnabled: !isPresentingModal && smartSelection == nil)
                    .frame(width: 44, height: 28)
            }
            ToolbarItem(placement: .primaryAction) {
                if !selectedEvents.isEmpty && selectedEvents.allSatisfy({ !$0.isActive }) {
                    Button {
                        let events = currentSelectedEvents
                        let operation: EventBatchOperation = events.allSatisfy { $0.lifecycle == .trashed } ? .recover : .unarchive
                        _ = store.batch(operation, events: events)
                    } label: { Label("恢复", systemImage: "arrow.uturn.backward") }
                    .disabled(!store.isLoaded || isPresentingModal)
                } else {
                    Button(action: editSelected) { Label("编辑事件", systemImage: "pencil") }
                        .help("编辑事件（⌘E）").disabled(!store.isLoaded || selectedEvent?.isActive != true || isPresentingModal)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: createEvent) { Label("新建事件", systemImage: "plus") }
                    .help("新建事件（⌘N）").disabled(!store.isLoaded || isPresentingModal)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "搜索")
    }

    @ViewBuilder private func detail(now: Date) -> some View {
        let visible = visibleEvents(now: now)
        VStack(spacing: 0) {
            if showWidgetHint {
                HStack(spacing: 12) {
                    Label("让日子显示在桌面", systemImage: "square.grid.2x2").font(.callout)
                    Spacer()
                    Button("查看步骤") { openWindow(id: "help") }
                    Button { showWidgetHint = false } label: { Image(systemName: "xmark").accessibilityLabel("关闭提示") }
                        .buttonStyle(.plain)
                }.padding(12)
            }
            if let error = store.errorMessage, store.isLoaded {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                    Spacer()
                    Button("关闭") { store.errorMessage = nil }
                }.font(.callout).padding(12)
            }
            ForEach(Array([store.backupMessage, store.reminderMessage].compactMap { $0 }.enumerated()), id: \.offset) { _, message in
                HStack {
                    Label(message, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                    Spacer()
                    Button("关闭") { if message == store.backupMessage { store.backupMessage = nil } else { store.reminderMessage = nil } }
                }.font(.callout).padding(12)
            }
            if let error = smartStore.errorMessage {
                HStack { Text(error).foregroundStyle(.red); Spacer(); Button(L10n.text("重试")) { smartStore.reload() } }.padding(12)
            }
            if smartSelection != nil && !smartStore.isLoaded {
                ContentUnavailableView(L10n.text("无法读取智能列表"), systemImage: "externaldrive.badge.exclamationmark", description: Text(smartStore.errorMessage ?? ""))
            } else if smartSelection != nil && !smartStore.lists.contains(where: { $0.id == smartSelection }) {
                ContentUnavailableView(L10n.text("智能列表不存在"), systemImage: "line.3.horizontal.decrease.circle", description: Text(L10n.text("请在侧栏选择其他列表，或从智能列表备份恢复。")))
            } else if !store.isLoaded {
                ContentUnavailableView {
                    Label("无法读取事件", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "请稍后重试。")
                } actions: {
                    Button("重试", action: store.reload)
                }
            } else if visible.isEmpty {
                ContentUnavailableView {
                    Label(L10n.text(search.isEmpty ? ((filter == .trash) ? "回收站为空" : (filter == .archived ? "没有归档事件" : "没有事件")) : "没有搜索结果"), systemImage: search.isEmpty ? "calendar" : "magnifyingglass")
                } description: {
                    if !search.isEmpty { Text("试试其他名称。") }
                } actions: {
                    if search.isEmpty && filter != .archived && filter != .trash {
                        Button("新建事件", action: createEvent)
                        if store.events.isEmpty { Button("导入备份…", action: beginImport) }
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selectedIDs) {
                        ForEach(visible) { event in
                            EventRow(event: event, now: now, isSelected: selectedIDs.contains(event.id), paused: isPresentingModal)
                                .id(event.id)
                                .tag(event.id)
                                .accessibilityAction(named: Text("编辑事件")) { if !isPresentingModal && event.isActive { store.edit(event) } }
                                .accessibilityAction(named: Text("复制摘要")) { copySummary(event) }
                                .accessibilityAction(named: Text("移到回收站")) { if !isPresentingModal && event.lifecycle != .trashed { pendingDelete = [event] } }
                                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        }
                    }
                    .listStyle(.inset)
                    .id("\((filter ?? .all).rawValue):\(search)")
                    .focusable()
                    .focusEffectDisabled()
                    .focused($eventListFocused)
                    .simultaneousGesture(TapGesture().onEnded {
                        guard !isPresentingModal else { return }
                        eventListFocused = true
                    })
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        let events = store.events.filter { ids.contains($0.id) }
                        if events.count == 1, let event = events.first {
                            Button("复制摘要") { copySummary(event) }
                            Button("分享图片…") { shareEvent = event }
                            if event.lifecycle != .trashed {
                                Button("复制为新事件", systemImage: "doc.on.doc") { store.duplicate(event) }
                            }
                            if event.isActive {
                                Button(L10n.text(event.isPinned ? "取消置顶" : "置顶"), systemImage: event.isPinned ? "pin.slash" : "pin") { store.togglePinned(event) }
                                Button("编辑事件", systemImage: "pencil") { store.edit(event) }
                            }
                            Divider()
                        }
                        if !events.isEmpty {
                            if events.allSatisfy({ $0.lifecycle == .trashed }) {
                                Button("恢复", systemImage: "arrow.uturn.backward") { _ = store.batch(.recover, events: events) }
                                Button("永久删除", systemImage: "trash", role: .destructive) { pendingDelete = events }
                            } else if events.allSatisfy({ $0.lifecycle != .trashed }) {
                                if events.allSatisfy({ $0.lifecycle == .active }) {
                                    Button("归档", systemImage: "archivebox") { _ = store.batch(.archive, events: events) }
                                } else if events.allSatisfy({ $0.lifecycle == .archived }) {
                                    Button("取消归档", systemImage: "archivebox") { _ = store.batch(.unarchive, events: events) }
                                }
                                Button("移到回收站", systemImage: "trash", role: .destructive) { pendingDelete = events }
                            }
                        }
                    } primaryAction: { ids in
                        if ids.count == 1, let id = ids.first, let event = store.events.first(where: { $0.id == id }), event.isActive { store.edit(event) }
                    }
                    .disabled(isPresentingModal)
                    .accessibilityLabel("事件列表")
                    .onDeleteCommand(perform: deleteSelected)
                    .onMoveCommand { direction in
                        guard !isPresentingModal else { return }
                        if direction == .down { moveSelection(1, visible: visible) }
                        if direction == .up { moveSelection(-1, visible: visible) }
                    }
                    .onKeyPress(phases: [.down, .repeat]) { key in handleListKey(key, visible: visible) }
                    .onChange(of: selectedIDs) { _, ids in
                        if keyboardSelection != ids && ids.count == 1 { vimNavigation.cursor = ids.first }
                        keyboardSelection = nil
                        if let cursor = vimNavigation.cursor, visible.contains(where: { $0.id == cursor }) { proxy.scrollTo(cursor) }
                    }
                    .onChange(of: eventListFocused) { if !eventListFocused { vimSequence.reset(); vimNavigation.anchor = nil } }
                    .onAppear { if !isPresentingModal { eventListFocused = true } }

                }
            }
        }
        .onChange(of: visible.map(\.id), initial: true) { _, ids in
            vimNavigation.reconcile(ids: ids, selected: &selectedIDs)
        }
    }
    private func visibleEvents(now: Date) -> [CountdownEvent] {
        let source: [CountdownEvent]
        if let id = smartSelection {
            guard smartStore.isLoaded else { return [] }
            source = smartStore.lists.first(where: { $0.id == id })?.evaluate(events: store.events, now: now).events ?? []
        } else {
            source = WidgetPolicy.sorted(events: store.events, now: now, order: sortOrder, includingInactive: true).filter { (filter ?? .all).accepts($0, now: now) }
        }
        return source.filter { (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(search) }))
        }
    }
    private func clearSelection() { keyboardSelection = nil; selectedIDs = []; vimNavigation = VimListNavigation(); vimSequence.reset() }
    private func moveSelection(_ step: Int, visible: [CountdownEvent]) {
        var result = selectedIDs
        vimNavigation.move(step, ids: visible.map(\.id), selected: &result)
        applyKeyboardSelection(result)
    }
    private func applyKeyboardSelection(_ ids: Set<UUID>) {
        if selectedIDs != ids { keyboardSelection = ids; selectedIDs = ids }
    }
    private func archiveSelected() {
        guard !isPresentingModal else { return }
        _ = store.batch(.archive, events: currentSelectedEvents)
    }
    private func restoreSelected() {
        guard !isPresentingModal else { return }
        let operation: EventBatchOperation = currentSelectedEvents.allSatisfy { $0.lifecycle == .trashed } ? .recover : .unarchive
        _ = store.batch(operation, events: currentSelectedEvents)
    }
    private func duplicateSelected() {
        guard !isPresentingModal, let event = currentSelectedEvent else { return }
        store.duplicate(event)
    }
    private func handleListKey(_ key: KeyPress, visible: [CountdownEvent]) -> KeyPress.Result {
        // Native List can own focus without updating the wrapper FocusState.
        // This handler is attached only to the event List; text responders are excluded.
        guard store.isLoaded, !isPresentingModal,
              !(NSApp.keyWindow?.firstResponder is NSTextView) else { return .ignored }
        if key.key == .return { editSelected(); return selectedEvent == nil ? .ignored : .handled }
        if key.key == .escape {
            vimSequence.reset(); vimNavigation.anchor = nil
            if let cursor = vimNavigation.cursor, visible.contains(where: { $0.id == cursor }) { applyKeyboardSelection([cursor]) } else { clearSelection() }
            return .handled
        }
        guard !key.modifiers.contains(.command), !key.modifiers.contains(.option) else { return .ignored }
        if key.key == .upArrow || key.key == .downArrow {
            if key.modifiers.contains(.shift), vimNavigation.anchor == nil {
                vimNavigation.anchor = vimNavigation.cursor ?? visible.first(where: { selectedIDs.contains($0.id) })?.id
            } else if !key.modifiers.contains(.shift) { vimNavigation.anchor = nil }
            moveSelection(key.key == .downArrow ? 1 : -1, visible: visible); return .handled
        }
        guard vimKeysEnabled else { return .ignored }
        let text = key.characters
        guard "jkgGd/vV iou".contains(text) && !text.isEmpty || (key.modifiers.contains(.control) && text == "r") else { return .ignored }
        if key.phase == .repeat && ["d", "g"].contains(text) { return .handled }
        guard let command = vimSequence.command(text, control: key.modifiers.contains(.control), at: ProcessInfo.processInfo.systemUptime) else { return .handled }
        switch command {
        case .down: moveSelection(1, visible: visible)
        case .up: moveSelection(-1, visible: visible)
        case .first: moveSelection(-visible.count, visible: visible)
        case .last: moveSelection(visible.count, visible: visible)
        case .search: focusSearch()
        case .visual:
            let cursor = vimNavigation.cursor ?? visible.first(where: { selectedIDs.contains($0.id) })?.id ?? visible.first?.id
            vimNavigation.cursor = cursor
            vimNavigation.anchor = vimNavigation.anchor == nil ? cursor : nil
            if let cursor { applyKeyboardSelection([cursor]) }
        case .toggle:
            if let cursor = vimNavigation.cursor ?? visible.first?.id {
                vimNavigation.cursor = cursor; vimNavigation.anchor = nil
                var ids = selectedIDs
                if ids.contains(cursor) { ids.remove(cursor) } else { ids.insert(cursor) }
                applyKeyboardSelection(ids)
            }
        case .edit: editSelected()
        case .create: createEvent()
        case .trash: if filter != .trash { deleteSelected() }
        case .undo: store.eventUndoManager.undo()
        case .redo: store.eventUndoManager.redo()
        case .escape: break
        }
        return .handled
    }

    private func updateHistoryModal() { store.isHistoryModalPresented = pendingDelete != nil || transferMessage != nil || shareEvent != nil }
    private func offerWidgetHint() {
        guard store.firstEventAdded, !hasShownWidgetHint else { return }
        hasShownWidgetHint = true; showWidgetHint = true
    }
    private func copySummary(_ event: CountdownEvent) {
        guard store.isLoaded, !isPresentingModal else { return }
        EventShareService.copySummary(event: event, now: Date())
    }
    private func copySelectedSummary() { if let event = currentSelectedEvent { copySummary(event) } }
    private func shareSelected() {
        guard store.isLoaded, !isPresentingModal, let event = currentSelectedEvent else { return }
        shareEvent = event
    }
    private func createEvent() {
        guard !isPresentingModal else { return }
        store.newEvent()
    }
    private func focusSearch() {
        guard store.isLoaded, !isPresentingModal else { return }
        // SwiftUI's toolbar search uses the native item. Begin interaction also
        // restores focus when search is already presented, on macOS 14 too.
        let item = NSApp.keyWindow?.toolbar?.items.compactMap { $0 as? NSSearchToolbarItem }.first
        item?.beginSearchInteraction()
    }
    private func beginImport() {
        guard store.isLoaded, !isPresentingModal else { return }
        store.isTransferring = true
        isImporting = true
    }
    private func beginExport() {
        guard store.isLoaded, !isPresentingModal else { return }
        let panel = NSSavePanel()
        panel.title = L10n.text("导出事件")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = L10n.text("日距事件.json")
        panel.canCreateDirectories = true
        store.isTransferring = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            store.isTransferring = false
            guard response == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { try store.exportEvents(to: url) }
            catch { store.errorMessage = L10n.format("导出失败：%@", error.localizedDescription) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func editSelected() {
        guard store.isLoaded, !isPresentingModal else { return }
        if let event = currentSelectedEvent, event.isActive { store.edit(event) }
    }
    private func deleteSelected() {
        guard store.isLoaded, !isPresentingModal else { return }
        let events = currentSelectedEvents
        if !events.isEmpty { pendingDelete = events }
    }
}

// Keep one AppKit menu for this toolbar item. Clock redraws must never replace
// its items while AppKit is tracking the user's mouse or keyboard selection.
private struct NativeEventSortMenu: NSViewRepresentable {
    @Binding var selection: EventSortOrder
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(L10n.text("排序"))
        button.toolTip = L10n.text("事件排序")
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectOrder(_:))
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: L10n.text("排序"), action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
        menu.addItem(title)
        for order in EventSortOrder.allCases {
            let item = NSMenuItem(title: order.label, action: nil, keyEquivalent: "")
            item.representedObject = order.rawValue
            menu.addItem(item)
        }
        menu.delegate = context.coordinator
        button.menu = menu
        context.coordinator.refreshChecks(menu)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(L10n.text("排序"))
        button.toolTip = L10n.text("事件排序")
        if !context.coordinator.isTracking, let menu = button.menu {
            context.coordinator.refreshChecks(menu)
        }
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var selection: Binding<EventSortOrder>
        var isTracking = false
        init(selection: Binding<EventSortOrder>) { self.selection = selection }
        func refreshChecks(_ menu: NSMenu) {
            for item in menu.items {
                let title = (item.representedObject as? String).flatMap(EventSortOrder.init(rawValue:))?.label ?? L10n.text("排序")
                if item.title != title { item.title = title }
                item.state = (item.representedObject as? String) == selection.wrappedValue.rawValue ? .on : .off
            }
        }
        func menuWillOpen(_ menu: NSMenu) { refreshChecks(menu); isTracking = true }
        func menuDidClose(_ menu: NSMenu) { isTracking = false; refreshChecks(menu) }
        @objc func selectOrder(_ sender: NSPopUpButton) {
            guard sender.isEnabled, let raw = sender.selectedItem?.representedObject as? String,
                  let order = EventSortOrder(rawValue: raw) else { return }
            selection.wrappedValue = order
        }
    }
}
