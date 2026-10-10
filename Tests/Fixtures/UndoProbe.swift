import Foundation
import Darwin

@main struct UndoProbe {
    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let repository = EventRepository(fileURL: folder.appendingPathComponent("events.json"))
        let store = EventStore(repository: repository)
        let manager = store.eventUndoManager
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CountdownEvent(title: "原名", targetDate: date)
        precondition(store.upsert(event, replacing: nil))
        let original = store.events[0]
        let sameBackup = try store.listBackups().first!
        let beforeNoop = try Data(contentsOf: repository.fileURL)
        let snapshotCount = try store.listBackups().count
        precondition(store.restoreBackup(sameBackup))
        let afterNoop = try Data(contentsOf: repository.fileURL)
        precondition(beforeNoop == afterNoop)
        let afterSnapshotCount = try store.listBackups().count
        precondition(snapshotCount == afterSnapshotCount)

        var changed = original; changed.title = "改名"; changed.isAllDay = true; changed.repeatYearly = true; changed.isPinned = true; changed.reminder = .onDay
        precondition(store.upsert(changed, replacing: original))
        let saved = store.events[0]
        precondition(store.delete(saved))
        let deleted = store.events
        manager.undo(); precondition(store.events == [saved]); manager.undo(); precondition(store.events == [original])
        manager.undo(); precondition(store.events.isEmpty)
        manager.redo(); precondition(store.events == [original]); manager.redo(); precondition(store.events == [saved])
        manager.redo(); precondition(store.events == deleted)
        manager.undo(); precondition(store.events == [saved])
        let bytes = try Data(contentsOf: repository.fileURL)

        // Rejected saves must not create history or replace source bytes.
        let undoName = manager.undoActionName
        let redoName = manager.redoActionName
        store.edit(saved)
        precondition(!store.upsert(CountdownEvent(id: saved.id, title: "  ", targetDate: date), replacing: saved))
        let afterFailedSave = try Data(contentsOf: repository.fileURL)
        precondition(afterFailedSave == bytes)
        precondition(manager.undoActionName == undoName && manager.redoActionName == redoName)

        // Both branches are available before blocking. A rejected native call must
        // neither pop a group nor write data, so both remain after unblocking.
        precondition(!manager.canUndo && !manager.canRedo)
        manager.undo(); manager.redo()
        store.editingEvent = nil
        precondition(manager.canUndo && manager.canRedo)
        precondition(store.events == [saved])
        for reason in 0..<3 {
            if reason == 0 { store.isTransferring = true }
            if reason == 1 { store.isHistoryModalPresented = true }
            if reason == 2 { store.isShowingBackups = true }
            precondition(!manager.canUndo && !manager.canRedo)
            manager.undo(); manager.redo()
            store.isHistoryModalPresented = false
            store.isTransferring = false
            store.isShowingBackups = false
            precondition(manager.canUndo && manager.canRedo)
            precondition(store.events == [saved])
            let blockedBytes = try Data(contentsOf: repository.fileURL)
            precondition(blockedBytes == bytes)
        }
        manager.undo(); precondition(store.events == [original])
        manager.redo(); precondition(store.events == [saved])

        var external = saved; external.title = "其他写入者"
        try repository.save([external], replacing: [saved])
        manager.undo()
        let diskAfterConflict = try repository.load()
        precondition(diskAfterConflict == [external]); precondition(store.events == [external]); precondition(store.errorMessage != nil)
        precondition(!manager.canUndo && !manager.canRedo)

        // Lifecycle operations remain one atomic, reversible event mutation.
        precondition(store.archive(external))
        let archived = store.events[0]
        precondition(archived.lifecycle == .archived)
        precondition(store.delete(archived))
        let trashed = store.events[0]
        precondition(trashed.lifecycle == .trashed && trashed.wasArchivedBeforeTrash)
        precondition(store.recover(trashed))
        let recovered = store.events[0]
        precondition(recovered.lifecycle == .archived && recovered.trashedAt == nil && !recovered.wasArchivedBeforeTrash)
        manager.undo(); precondition(store.events == [trashed])
        manager.redo(); precondition(store.events == [recovered])
        precondition(store.delete(recovered))
        let trashedAgain = store.events[0]
        precondition(store.permanentlyDelete(trashedAgain))
        precondition(store.events.isEmpty)
        manager.undo(); precondition(store.events == [trashedAgain])
        manager.redo(); precondition(store.events.isEmpty)
        print("UNDO_PASS: application history/create/edit/delete/undo3/redo3/blocked editor/file/modal/backups/failed save/external CAS/archive/trash/recover/permanent delete")
    }
}
