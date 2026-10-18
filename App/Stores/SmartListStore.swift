import Foundation
import Observation
import WidgetKit

@Observable @MainActor
final class SmartListStore {
    private(set) var lists: [SmartList] = []
    private(set) var isLoaded = false
    var errorMessage: String?
    var draft: SmartList?
    var pendingDelete: SmartList?
    var isShowingBackups = false
    private var original: SmartList?
    @ObservationIgnored private let repositoryProvider: () -> SmartListRepository?
    var isPresentingModal: Bool { draft != nil || pendingDelete != nil || isShowingBackups }
    init(repositoryProvider: @escaping () -> SmartListRepository?) { self.repositoryProvider = repositoryProvider }
    func reload() {
        guard let repository = repositoryProvider() else { return }
        do { lists = try repository.load(); isLoaded = true; errorMessage = nil }
        catch { isLoaded = false; errorMessage = error.localizedDescription }
    }
    func begin(_ list: SmartList? = nil, copy: Bool = false) {
        guard isLoaded, !isPresentingModal else { return }
        original = copy ? nil : list
        var value = list ?? SmartList(name: L10n.text("新智能列表"))
        if copy { value.id = UUID(); value.name = L10n.format("%@ 副本", value.name) }
        draft = value
    }
    func cancel() { draft = nil; original = nil }
    @discardableResult func saveDraft() -> Bool {
        guard let draft else { return false }
        if upsert(draft, replacing: original) { cancel(); return true }
        return false
    }
    @discardableResult func upsert(_ list: SmartList, replacing expected: SmartList?) -> Bool {
        guard isLoaded else { return false }
        do {
            let value = try list.validated()
            guard lists.first(where: { $0.id == value.id }) == expected else { throw EventError.changedData }
            var updated = lists
            if let index = updated.firstIndex(where: { $0.id == value.id }) { updated[index] = value }
            else { updated.append(value) }
            return persist(updated)
        } catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult func confirmDelete() -> Bool {
        guard let expected = pendingDelete, lists.contains(expected) else { errorMessage = EventError.changedData.localizedDescription; return false }
        if persist(lists.filter { $0.id != expected.id }) { pendingDelete = nil; return true }
        return false
    }
    func backups() throws -> [SmartListBackup] { try repositoryProvider()?.backups() ?? [] }
    func recoveryFingerprint() -> String? {
        do { return try repositoryProvider()?.recoveryFingerprint() }
        catch { errorMessage = error.localizedDescription; return nil }
    }
    @discardableResult func restore(_ backup: SmartListBackup, replacingLiveFingerprint expected: String? = nil) -> Bool {
        guard draft == nil, pendingDelete == nil, let repository = repositoryProvider() else { return false }
        do {
            let fingerprint = try expected ?? repository.recoveryFingerprint()
            try repository.restore(backup, replacingLiveFingerprint: fingerprint)
            lists = try repository.load()
            isLoaded = true; errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    private func persist(_ updated: [SmartList]) -> Bool {
        guard let repository = repositoryProvider() else { return false }
        do {
            try repository.save(updated, replacing: lists)
            lists = try repository.load()
            isLoaded = true; errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            // Keep drafts, but refresh the CAS baseline after a competing writer.
            if case EventError.changedData = error { lists = (try? repository.load()) ?? lists }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
