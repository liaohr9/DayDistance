import Foundation

@main struct BatchProbe {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let repository = EventRepository(fileURL: root.appendingPathComponent("events.json"))
        var originals = [CountdownEvent(title: "One", targetDate: Date().addingTimeInterval(86400), reminder: .onDay), CountdownEvent(title: "Two", targetDate: Date().addingTimeInterval(172800))]
        originals[0].dailyReminderTime = CalendarTime(hour: 9, minute: 0)
        originals[0].monthlyReminderTime = CalendarTime(hour: 10, minute: 0)
        try repository.save(originals, replacing: [])
        let store = EventStore(repository: repository)
        precondition(store.batch(.archive, events: originals))
        precondition(store.events.allSatisfy { $0.lifecycle == .archived })
        store.eventUndoManager.undo(); precondition(store.events == originals)
        store.eventUndoManager.redo(); precondition(store.events.allSatisfy { $0.lifecycle == .archived })
        precondition(store.batch(.trash, events: store.events))
        precondition(store.events.allSatisfy { $0.lifecycle == .trashed && $0.wasArchivedBeforeTrash })
        precondition(store.batch(.recover, events: store.events))
        precondition(store.events.allSatisfy { $0.lifecycle == .archived && $0.trashedAt == nil })
        let before = store.events
        let bytes = try Data(contentsOf: repository.fileURL)
        precondition(!store.batch(.trash, events: [originals[0], before[1]]))
        let after = try Data(contentsOf: repository.fileURL); precondition(bytes == after)
        store.edit(before[0]); precondition(!store.batch(.trash, events: before)); store.editingEvent = nil
        store.duplicate(before[0])
        let draft = store.editingEvent!
        precondition(draft.original == nil && draft.event.id != before[0].id && draft.event.lifecycle == .active && !draft.event.hasEnabledReminders)
        precondition(store.events == before)
        store.editingEvent = nil
        var external = before; external[1].title = "External"
        try repository.save(external, replacing: before)
        precondition(!store.batch(.trash, events: before))
        let disk = try repository.load(); precondition(disk == external && store.events == external)
        precondition(!store.batch(.archive, events: []))
        precondition(store.batch(.trash, events: store.events))
        let trash = store.events
        precondition(store.batch(.permanentlyDelete, events: trash))
        precondition(store.events.isEmpty)
        store.eventUndoManager.undo(); precondition(store.events == trash)
        // One-shot expiry uses one CAS save, preserves drafts, and recovery disarms
        // the automatic policy so that an event can be rescheduled safely.
        let expiryRoot = root.appendingPathComponent("expiry")
        let expiryRepo = EventRepository(fileURL: expiryRoot.appendingPathComponent("events.json"))
        let now = Date()
        var once = CountdownEvent(title: "Disposable", targetDate: now.addingTimeInterval(60))
        once.afterDate = .trash
        let memory = CountdownEvent(title: "Memory", targetDate: now.addingTimeInterval(-86400))
        try expiryRepo.save([once, memory], replacing: [])
        let expiryStore = EventStore(repository: expiryRepo)
        let end = now.addingTimeInterval(61)
        expiryStore.edit(once)
        precondition(!expiryStore.reconcileExpiredEvents(now: end))
        precondition(expiryStore.events == [once, memory])
        expiryStore.editingEvent = nil
        precondition(expiryStore.reconcileExpiredEvents(now: end))
        precondition(expiryStore.events[0].lifecycle == .trashed && expiryStore.events[1] == memory)
        let moved = expiryStore.events[0]
        precondition(expiryStore.reconcileExpiredEvents(now: end.addingTimeInterval(1)))
        precondition(expiryStore.events[0] == moved)
        precondition(expiryStore.recover(moved))
        precondition(expiryStore.events[0].isActive && expiryStore.events[0].afterDate == .keep)
        precondition(expiryStore.reconcileExpiredEvents(now: end.addingTimeInterval(100)))
        precondition(expiryStore.events[0].isActive)
        var overdue = once; overdue.targetDate = now.addingTimeInterval(-60)
        try expiryRepo.save([overdue, memory], replacing: try expiryRepo.load())
        let cold = EventStore(repository: expiryRepo)
        precondition(cold.events[0].lifecycle == .trashed && cold.events[1] == memory)
        let expiryBackups = try cold.listBackups()
        precondition(!expiryBackups.isEmpty)
        print("Expiry: draft deferral/CAS/persistence/idempotence/recovery/cold-load/backup PASS")
        print("Atomic batch/undo/redo/recovery/CAS/modal/duplicate checks passed")
    }
}
