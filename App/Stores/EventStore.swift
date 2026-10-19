import Foundation
import Observation
import WidgetKit

enum EventBatchOperation { case archive, unarchive, trash, recover, permanentlyDelete }

@Observable @MainActor
final class EventStore {
    private(set) var events: [CountdownEvent] = []
    private(set) var isLoaded = false
    private(set) var firstEventAdded = false
    @ObservationIgnored private(set) var lastPersistenceFailure: Error?
    func automationReceipt(for key: String) throws -> AutomationReceipt? {
        guard let repository else { throw EventError.unavailableContainer }
        return try repository.automationReceipt(for: key)
    }
    var errorMessage: String?
    var editingEvent: EventEditSession?
    var isTransferring = false
    var isShowingBackups = false
    var backupMessage: String?
    var reminderMessage: String?
    var backupRepository: LocalBackupRepository? { repository.map { LocalBackupRepository(eventFileURL: $0.fileURL) } }
    func listBackups() throws -> [LocalBackup] { try backupRepository?.list() ?? [] }
    @discardableResult func restoreBackup(_ backup: LocalBackup) -> Bool {
        guard isLoaded, editingEvent == nil, !isTransferring, !isSmartListModalPresented, let backupRepository else { return false }
        do { return persist(try backupRepository.load(backup), name: L10n.text("恢复备份")) }
        catch { errorMessage = L10n.format("恢复失败，原数据已保留：%@", error.localizedDescription); return false }
    }
    func smartListRepository() -> SmartListRepository? {
        repository.map { SmartListRepository(fileURL: $0.fileURL.deletingLastPathComponent().appendingPathComponent("smart-lists.json")) }
    }
    var isSmartListModalPresented = false
    private var repository: EventRepository?
    var canManageData: Bool { isLoaded && editingEvent == nil && !isTransferring && !isShowingBackups && !isHistoryModalPresented && !isSmartListModalPresented }
    var isHistoryModalPresented = false
    @ObservationIgnored let eventUndoManager = EventHistoryUndoManager()

    init(repository: EventRepository? = nil, automaticallyLoad: Bool = true) {
        self.repository = repository
        eventUndoManager.shouldPerformHistory = { [weak self] in
            guard let self else { return false }
            return self.isLoaded && self.editingEvent == nil && !self.isTransferring && !self.isHistoryModalPresented && !self.isSmartListModalPresented && !self.isShowingBackups
        }
        if automaticallyLoad { reload() }
    }
    var protectedExportDataURLs: [URL] { SharedContainer.protectedDataURLs() + (repository.map { [$0.fileURL] } ?? []) }
    func exportEvents(to destination: URL) throws {
        guard isLoaded, editingEvent == nil, !isTransferring, !isSmartListModalPresented, let repository else { throw EventError.unavailableContainer }
        try repository.exportSnapshot(to: destination, protecting: SharedContainer.protectedDataURLs())
    }
    func importEvents(_ data: Data) -> Int? {
        guard isLoaded, editingEvent == nil, !isTransferring, !isSmartListModalPresented, let repository else { return nil }
        do {
            let loaded = try repository.importSnapshot(data, replacing: events)
            let count = loaded.count - events.count
            let before = events
            events = loaded
            if before.isEmpty && !loaded.isEmpty { firstEventAdded = true }
            recordBackups(before: before, after: loaded)
            if loaded != before { registerUndo(before: before, after: loaded, name: L10n.text("导入事件"), manager: eventUndoManager) }
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
            return count
        } catch {
            if case EventError.changedData = error { refreshAfterConflict() }
            errorMessage = L10n.format("导入失败，原数据已保留：%@", error.localizedDescription)
            return nil
        }
    }
    @ObservationIgnored var prepareForReload: (() -> Bool)?
    func reload() {
        if let prepareForReload, !prepareForReload() { return }
        do {
            let (repository, loaded): (EventRepository, [CountdownEvent])
            if let current = self.repository { (repository, loaded) = (current, try current.load()) }
            else { (repository, loaded) = try SharedContainer.loadForApplication() }
            self.repository = repository
            events = loaded
            isLoaded = true
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            isLoaded = false
            errorMessage = L10n.format("读取失败：%@", error.localizedDescription)
        }
    }
    func newEvent() {
        guard isLoaded, editingEvent == nil, !isTransferring, !isShowingBackups, !isHistoryModalPresented && !isSmartListModalPresented else { return }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        editingEvent = EventEditSession(event: CountdownEvent(title: "", targetDate: tomorrow), isNew: true)
    }
    func edit(_ event: CountdownEvent) {
        guard isLoaded, editingEvent == nil, !isTransferring, !isShowingBackups, !isHistoryModalPresented && !isSmartListModalPresented else { return }
        editingEvent = EventEditSession(event: event)
    }
    @discardableResult
    func upsert(_ event: CountdownEvent, replacing original: CountdownEvent?, automationReceipt: (String, AutomationReceipt)? = nil) -> Bool {
        lastPersistenceFailure = nil
        guard isLoaded, !isTransferring, !isSmartListModalPresented else { return false }
        do {
            guard events.first(where: { $0.id == event.id }) == original else { throw EventError.changedData }
            let value = try event.validated(now: Date())
            var updated = events
            if let index = updated.firstIndex(where: { $0.id == value.id }) { updated[index] = value }
            else { updated.append(value) }
            let wasEmpty = events.isEmpty
            let saved = persist(updated, name: L10n.text(original == nil ? "新建事件" : "编辑事件"), automationReceipt: automationReceipt)
            if saved && wasEmpty { firstEventAdded = true }
            return saved
        } catch {
            lastPersistenceFailure = error
            if case EventError.changedData = error { refreshAfterConflict() }
            errorMessage = error.localizedDescription
            return false
        }
    }
    @discardableResult
    func delete(_ event: CountdownEvent) -> Bool {
        guard isLoaded, !isTransferring, !isSmartListModalPresented else { return false }
        guard events.first(where: { $0.id == event.id }) == event else {
            refreshAfterConflict()
            errorMessage = EventError.changedData.localizedDescription
            return false
        }
        guard event.lifecycle != .trashed else { return false }
        var value = event
        value.wasArchivedBeforeTrash = event.lifecycle == .archived
        value.lifecycle = .trashed
        value.trashedAt = Date()
        value.updatedAt = Date()
        return persist(events.map { $0.id == event.id ? value : $0 }, name: L10n.text("移到回收站"))
    }
    @discardableResult func archive(_ event: CountdownEvent) -> Bool {
        guard editingEvent == nil, !isShowingBackups, !isHistoryModalPresented && !isSmartListModalPresented, event.lifecycle != .trashed else { return false }
        var value = event
        value.lifecycle = event.lifecycle == .archived ? .active : .archived
        return upsert(value, replacing: event)
    }
    @discardableResult func recover(_ event: CountdownEvent) -> Bool {
        guard editingEvent == nil, !isShowingBackups, !isHistoryModalPresented && !isSmartListModalPresented, event.lifecycle == .trashed else { return false }
        var value = event
        value.lifecycle = event.wasArchivedBeforeTrash ? .archived : .active
        value.trashedAt = nil
        value.wasArchivedBeforeTrash = false
        return upsert(value, replacing: event)
    }
    @discardableResult func permanentlyDelete(_ event: CountdownEvent) -> Bool {
        guard isLoaded, !isTransferring, !isSmartListModalPresented, editingEvent == nil, event.lifecycle == .trashed else { return false }
        guard events.first(where: { $0.id == event.id }) == event else {
            refreshAfterConflict(); errorMessage = EventError.changedData.localizedDescription; return false
        }
        return persist(events.filter { $0.id != event.id }, name: L10n.text("永久删除"))
    }
    /// All selected baselines are checked before one save and one undo group.
    @discardableResult func batch(_ operation: EventBatchOperation, events selected: [CountdownEvent]) -> Bool {
        guard isLoaded, editingEvent == nil, !isTransferring, !isShowingBackups, !isHistoryModalPresented && !isSmartListModalPresented,
              !selected.isEmpty, Set(selected.map(\.id)).count == selected.count else { return false }
        guard selected.allSatisfy({ expected in events.first(where: { $0.id == expected.id }) == expected }) else {
            refreshAfterConflict(); errorMessage = EventError.changedData.localizedDescription; return false
        }
        let valid = selected.allSatisfy { event in
            switch operation {
            case .archive: event.lifecycle == .active
            case .unarchive: event.lifecycle == .archived
            case .trash: event.lifecycle != .trashed
            case .recover, .permanentlyDelete: event.lifecycle == .trashed
            }
        }
        guard valid else { return false }
        let ids = Set(selected.map(\.id))
        let now = Date()
        let updated = events.compactMap { event -> CountdownEvent? in
            guard ids.contains(event.id) else { return event }
            if operation == .permanentlyDelete { return nil }
            var value = event
            switch operation {
            case .archive: value.lifecycle = .archived
            case .unarchive: value.lifecycle = .active
            case .trash:
                value.wasArchivedBeforeTrash = value.lifecycle == .archived
                value.lifecycle = .trashed; value.trashedAt = now
            case .recover:
                value.lifecycle = value.wasArchivedBeforeTrash ? .archived : .active
                value.trashedAt = nil; value.wasArchivedBeforeTrash = false
            case .permanentlyDelete: break
            }
            value.updatedAt = now
            return value
        }
        let title: String
        switch operation {
        case .archive: title = "归档"
        case .unarchive: title = "取消归档"
        case .trash: title = "移到回收站"
        case .recover: title = "恢复"
        case .permanentlyDelete: title = "永久删除"
        }
        return persist(updated, name: L10n.text(title))
    }

    func duplicate(_ event: CountdownEvent) {
        guard isLoaded, editingEvent == nil, !isTransferring, !isShowingBackups, !isHistoryModalPresented && !isSmartListModalPresented,
              event.lifecycle != .trashed, events.contains(event) else { return }
        var draft = event
        draft.id = UUID(); draft.title = L10n.format("%@ 副本", event.title)
        draft.lifecycle = .active; draft.trashedAt = nil; draft.wasArchivedBeforeTrash = false
        draft.isPinned = false; draft.reminder = .none; draft.reminderDaysBefore = 0; draft.reminderTime = nil
        draft.dailyReminderTime = nil; draft.monthlyReminderTime = nil; draft.yearlyReminderTime = nil
        draft.createdAt = Date(); draft.updatedAt = draft.createdAt
        editingEvent = EventEditSession(event: draft, isNew: true)
    }

    private func recordBackups(before: [CountdownEvent], after: [CountdownEvent]) {
        guard let backupRepository, before != after else { return }
        do { try backupRepository.recordMutation(before: before, after: after); backupMessage = nil }
        catch { backupMessage = L10n.format("事件已保存，但自动备份失败：%@", error.localizedDescription) }
    }
    func togglePinned(_ event: CountdownEvent) {
        var value = event; value.isPinned.toggle()
        _ = upsert(value, replacing: event)
    }
    private func registerUndo(before: [CountdownEvent], after: [CountdownEvent], name: String, manager: UndoManager?) {
        guard let manager else { return }
        let opensGroup = !manager.isUndoing && !manager.isRedoing && manager.groupingLevel == 0
        if opensGroup { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { [weak manager] store in
            MainActor.assumeIsolated { store.restore(before, replacing: after, name: name, manager: manager) }
        }
        manager.setActionName(name)
        if opensGroup { manager.endUndoGrouping() }
    }
    private func restore(_ snapshot: [CountdownEvent], replacing expected: [CountdownEvent], name: String, manager: UndoManager?) {
        guard isLoaded, editingEvent == nil, !isTransferring, !isHistoryModalPresented && !isSmartListModalPresented, let repository else { return }
        do {
            guard events == expected else { throw EventError.changedData }
            try repository.save(snapshot, replacing: expected)
            events = snapshot
            recordBackups(before: expected, after: snapshot)
            registerUndo(before: expected, after: snapshot, name: name, manager: manager)
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if let history = manager as? EventHistoryUndoManager { history.invalidateHistory() }
            else { manager?.removeAllActions(withTarget: self) }
            refreshAfterConflict()
            errorMessage = L10n.format("无法撤销，当前数据已保留：%@", error.localizedDescription)
        }
    }
    private func persist(_ updated: [CountdownEvent], name: String, automationReceipt: (String, AutomationReceipt)? = nil) -> Bool {
        lastPersistenceFailure = nil
        guard isLoaded, let repository else { errorMessage = EventError.unavailableContainer.localizedDescription; return false }
        guard updated != events else { errorMessage = nil; return true }
        do {
            let before = events
            try repository.save(updated, replacing: before, automationReceipt: automationReceipt)
            events = updated
            recordBackups(before: before, after: updated)
            registerUndo(before: before, after: updated, name: name, manager: eventUndoManager)
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            if case EventError.changedData = error { refreshAfterConflict() }
            lastPersistenceFailure = error
            errorMessage = L10n.format("保存失败，原数据已保留：%@", error.localizedDescription)
            return false
        }
    }
    private func refreshAfterConflict() {
        guard let repository else { return }
        do {
            // Do not run migration again or discard the sheet's unsaved draft.
            events = try repository.load()
            isLoaded = true
            WidgetCenter.shared.reloadAllTimelines()
        } catch { isLoaded = false }
    }
    func open(_ url: URL) {
        guard isLoaded, editingEvent == nil, !isTransferring, !isShowingBackups, !isHistoryModalPresented && !isSmartListModalPresented else { return }
        guard url.scheme == "daydistance", url.host == "event",
              let id = UUID(uuidString: url.lastPathComponent), let event = events.first(where: { $0.id == id }) else {
            if url.host == "event" { editingEvent = nil; errorMessage = L10n.text("该事件不存在或已被删除。") }
            return
        }
        guard event.isActive else { errorMessage = L10n.text("该事件已归档或在回收站中。请先恢复事件。"); return }
        errorMessage = nil
        edit(event)
    }
}
