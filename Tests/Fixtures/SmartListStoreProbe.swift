import Foundation

@main struct SmartListStoreProbe {
    @MainActor static func main() throws {
        let reference = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let early = CountdownEvent(title: "Past", targetDate: reference.addingTimeInterval(-1000))
        let later = CountdownEvent(title: "Future", targetDate: reference.addingTimeInterval(3000))
        let nearest = SmartList(name: "Skipped nearest", skip: 1)
        let schedule = EventTimelineSchedule(events: [early,later], relatedSmartLists: [nearest])
        let dates = Array(schedule.entries(from: reference, mode: .normal).prefix(2))
        precondition(dates.count == 2 && abs(dates[1].timeIntervalSince(reference) - 1000.001) < 0.01)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let repo = SmartListRepository(fileURL: root.appendingPathComponent("smart-lists.json"))
        let store = SmartListStore(repositoryProvider: { repo })
        store.reload(); precondition(store.isLoaded && store.lists.isEmpty)
        store.begin(); store.draft?.name = "  Trip  "
        precondition(!FileManager.default.fileExists(atPath: repo.fileURL.path))
        store.cancel(); precondition(store.lists.isEmpty)
        store.begin(); store.draft?.name = "  Trip  "
        precondition(store.saveDraft() && store.lists[0].name == "Trip")
        let first = store.lists[0]
        store.begin(first); store.draft?.name = "Second"
        precondition(store.saveDraft())
        let backups = try store.backups(); precondition(backups.count >= 2)
        let other = SmartListStore(repositoryProvider: { repo }); other.reload()
        store.begin(store.lists[0]); store.draft?.name = "Third"; precondition(store.saveDraft())
        other.begin(other.lists[0]); other.draft?.name = "Conflicting"
        precondition(!other.saveDraft() && other.draft?.name == "Conflicting")
        other.cancel()
        store.pendingDelete = store.lists[0]; precondition(store.confirmDelete() && store.lists.isEmpty)
        precondition(store.restore(backups[0]) && !store.lists.isEmpty)
        let loaded = try repo.load(); precondition(loaded == store.lists)
        let folder = SmartList(name: "School", kind: .folder)
        precondition(store.upsert(folder, replacing: nil))
        let child = SmartList(name: "Homework", kind: .ordinary, parentID: folder.id)
        precondition(store.upsert(child, replacing: nil))
        let eventID = UUID()
        precondition(store.assign([eventID], to: child.id))
        precondition(store.containingList(for: eventID) == child.id)
        precondition(!store.assign(eventID, from: nil, to: nil))
        precondition(!store.move(folder, to: folder.id))
        store.pendingDelete = folder
        precondition(store.confirmDelete())
        precondition(store.lists.first(where: { $0.id == child.id })?.parentID == nil)
        precondition(store.containingList(for: eventID) == child.id)
        precondition(store.assign(eventID, from: child.id, to: nil))
        precondition(store.containingList(for: eventID) == nil)
        let eventRepo = EventRepository(fileURL: root.appendingPathComponent("events.json"))
        let eventStore = EventStore(repository: eventRepo)
        precondition(eventStore.smartListRepository()?.fileURL == repo.fileURL)
        eventStore.isSmartListModalPresented = true
        precondition(!eventStore.canManageData)
        eventStore.newEvent(); precondition(eventStore.editingEvent == nil)
        let bytes = try Data(contentsOf: repo.fileURL)
        eventStore.reload()
        let after = try Data(contentsOf: repo.fileURL); precondition(after == bytes)
        let recoverable = try store.backups().first(where: { $0.listCount > 0 })!
        let damaged = Data("{damaged".utf8)
        try damaged.write(to: repo.fileURL)
        store.reload(); precondition(!store.isLoaded)
        let availableBackups = try store.backups(); precondition(!availableBackups.isEmpty)
        let oldToken = store.recoveryFingerprint()!
        let competing = Data("{different damage".utf8)
        try competing.write(to: repo.fileURL)
        precondition(!store.restore(recoverable, replacingLiveFingerprint: oldToken))
        let conflictBytes = try Data(contentsOf: repo.fileURL); precondition(conflictBytes == competing)
        let confirmed = store.recoveryFingerprint()!
        precondition(store.restore(recoverable, replacingLiveFingerprint: confirmed))
        precondition(store.isLoaded && !store.lists.isEmpty)
        let quarantines = try FileManager.default.contentsOfDirectory(at: repo.backupDirectory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("quarantine-") }
        let preserved = try quarantines.contains { try Data(contentsOf: $0) == competing }; precondition(preserved)
        let future = Data("{\"schemaVersion\":999,\"lists\":[]}".utf8)
        try future.write(to: repo.fileURL)
        store.reload(); precondition(!store.isLoaded && store.recoveryFingerprint() == nil)
        precondition(!store.restore(recoverable))
        let futureBytes = try Data(contentsOf: repo.fileURL); precondition(futureBytes == future)
        print("smart-list store: draft/cancel/canonical CAS/conflict/delete/restore passed")
    }
}
