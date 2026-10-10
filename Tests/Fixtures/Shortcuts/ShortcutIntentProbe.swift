import AppIntents
import Darwin
import Foundation

@main
struct ShortcutIntentProbe {
    @MainActor
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DayDistanceShortcutProbe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let coldSource = folder.appendingPathComponent("events.json")
        let coldRepository = EventRepository(fileURL: coldSource)
        // Cold read-only startup must not create data or a lock file.
        let coldStore = EventStore(repository: coldRepository, automaticallyLoad: false)
        let coldService = ShortcutEventService(store: coldStore, repositoryProvider: { coldRepository })
        precondition(!coldStore.isLoaded)
        try require(try coldService.activeEvents().isEmpty)
        precondition(!FileManager.default.fileExists(atPath: coldSource.path))
        precondition(!FileManager.default.fileExists(atPath: coldSource.path + ".lock"))
        let coldEvent = try coldService.create(title: "Cold creation", targetDate: Date(), isAllDay: true)
        precondition(coldStore.isLoaded && coldStore.events.first?.id == coldEvent.id)
        let separate = folder.appendingPathComponent("live")
        try FileManager.default.createDirectory(at: separate, withIntermediateDirectories: true)
        let liveRepository = EventRepository(fileURL: separate.appendingPathComponent("events.json"))
        // Rest of fixture uses an independent repository with no cold seed event.
        let repository = liveRepository
        let source = liveRepository.fileURL
        let store = EventStore(repository: repository)
        var modal = false
        var activations = 0
        var creations = 0
        ShortcutEventService.install(store: store, repositoryProvider: { repository }, canUseUI: { !modal },
                                     activateMain: { activations += 1 }, didCreate: { _ in creations += 1 })
        precondition(CreateCountdownEventIntent.openAppWhenRun && OpenCountdownEventIntent.openAppWhenRun)
        precondition(!GetCountdownDaysIntent.openAppWhenRun)
        let create = CreateCountdownEventIntent()
        create.name = "  Shortcut fixture  "
        create.date = Date().addingTimeInterval(10 * 86400)
        precondition(!create.allDay)
        let created = try await create.perform()
        let id = created.value!
        let initial = try repository.load()
        precondition(initial.count == 1 && initial[0].id.uuidString == id)
        precondition(initial[0].title == "Shortcut fixture" && initial[0].reminder == .none && initial[0].isActive)
        precondition(!initial[0].isAllDay && creations == 1)
        let backups = LocalBackupRepository(eventFileURL: source)
        let firstBackups = try backups.list()
        precondition(firstBackups.count == 2)
        try require(try backups.load(firstBackups[1]) == [])
        try require(try backups.load(firstBackups[0]) == initial)
        let liveBytes = try Data(contentsOf: source)
        let query = GetCountdownDaysIntent()
        query.eventID = id
        let queried = try await query.perform()
        precondition(queried.value == DayCounter.snapshot(event: initial[0], now: Date()).days)
        let choices = try await CountdownEventOptionsProvider().results()
        precondition(choices.items == [id])
        let open = OpenCountdownEventIntent()
        open.eventID = id
        _ = try await open.perform()
        precondition(store.editingEvent?.event.id.uuidString == id && activations == 1)
        try require(try Data(contentsOf: source) == liveBytes)
        try require(try backups.list() == firstBackups)
        let draft = store.editingEvent!
        try await rejects { _ = try await create.perform() }
        try await rejects { _ = try await open.perform() }
        precondition(store.editingEvent?.id == draft.id && creations == 1 && activations == 1)
        // Read-only querying remains safe while a draft exists.
        _ = try await query.perform()
        store.editingEvent = nil
        for flag in 0..<4 {
            store.isTransferring = flag == 0
            store.isShowingBackups = flag == 1
            store.isHistoryModalPresented = flag == 2
            modal = flag == 3
            try await rejects { _ = try await create.perform() }
            try await rejects { _ = try await open.perform() }
        }
        store.isTransferring = false; store.isShowingBackups = false; store.isHistoryModalPresented = false; modal = false
        try require(try Data(contentsOf: source) == liveBytes)
        try require(try backups.list() == firstBackups)
        create.name = "\n "
        try await rejects { _ = try await create.perform() }
        create.name = "All day"
        create.allDay = true
        let allDay = try await create.perform()
        let allDayEvent = try ShortcutEventRepository(repository: repository).activeEvent(identifier: allDay.value!)
        precondition(allDayEvent.isAllDay && allDayEvent.calendarDay != nil && allDayEvent.reminder == .none)
        var current = try repository.load()
        var renamed = current[0]; renamed.title = "Renamed"
        var duplicate = renamed; duplicate.id = UUID()
        let replacement = [renamed, duplicate, allDayEvent]
        try repository.save(replacement, replacing: current)
        // Parameter options keep both identical titles/dates; UUIDs do not alias.
        let duplicates = try await CountdownEventOptionsProvider().results()
        precondition(Set(duplicates.items) == Set(replacement.map { $0.id.uuidString }))
        for item in duplicates.sections.flatMap(\.items) {
            precondition(String(localized: item.description.subtitle!).contains(item.value))
            precondition(!String(localized: item.description.title).isEmpty)
        }
        try require(try ShortcutEventService.shared.activeEvent(identifier: id).title == "Renamed")
        // A stale store must fail its CAS, preserve the external snapshot and make no backups.
        let beforeCASBackups = try backups.list()
        try await rejects { _ = try await create.perform() }
        try require(try repository.load() == replacement)
        try require(try backups.list() == beforeCASBackups)
        current = replacement
        renamed.lifecycle = .archived
        let inactive = [renamed, duplicate, allDayEvent]
        try repository.save(inactive, replacing: current)
        try await rejects { _ = try await query.perform() }
        try await rejects { _ = try await open.perform() }
        query.eventID = UUID().uuidString; open.eventID = query.eventID
        try await rejects { _ = try await query.perform() }
        try await rejects { _ = try await open.perform() }
        query.eventID = "invalid UUID"; open.eventID = query.eventID
        try await rejects { _ = try await query.perform() }
        try await rejects { _ = try await open.perform() }
        let corruptBytes = Data("unreadable event fixture".utf8)
        try corruptBytes.write(to: source)
        query.eventID = duplicate.id.uuidString; open.eventID = query.eventID
        try await rejects { _ = try await query.perform() }
        try await rejects { _ = try await open.perform() }
        try await rejects { _ = try await CountdownEventOptionsProvider().results() }
        store.reload()
        precondition(!store.isLoaded)
        try await rejects { _ = try await create.perform() }
        try require(try Data(contentsOf: source) == corruptBytes)
        try require(try backups.list() == beforeCASBackups)
        try EventRepository.encodeSnapshot(inactive).write(to: source)
        store.reload()
        // Lock contention rejects writes; no mutation or backups are recorded.
        let fd = Darwin.open(source.path + ".lock", O_RDWR | O_CLOEXEC)
        precondition(fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0)
        try await rejects { _ = try await create.perform() }
        flock(fd, LOCK_UN); Darwin.close(fd)
        try require(try repository.load() == inactive)
        try require(try backups.list() == beforeCASBackups)
        let uninstalled = ShortcutEventService(repositoryProvider: { repository })
        do {
            _ = try uninstalled.create(title: "Never saved", targetDate: Date(), isAllDay: false)
            fatalError("Uninstalled runtime created data")
        } catch ShortcutEventError.applicationUnavailable {}
        // Backup failure is distinct from successful mutation and visible to the caller.
        let backupFolder = backups.folderURL
        let retainedFolder = folder.appendingPathComponent("retained-backups")
        try FileManager.default.moveItem(at: backupFolder, to: retainedFolder)
        try Data("not a directory".utf8).write(to: backupFolder)
        let warningResult = try await create.perform()
        precondition(warningResult.value != nil && store.backupMessage != nil)
        try require(try repository.load().count == inactive.count + 1)
        print("Native three-intent perform: create/query/open, UUID duplicates, readonly bytes, backups, CAS, lock, draft/modal/transfer, missing/inactive/read failure, unavailable runtime and backup warning PASS")
    }

    static func require(_ condition: @autoclosure () throws -> Bool) throws {
        let value = try condition()
        precondition(value)
    }

    @MainActor
    static func rejects(_ operation: () async throws -> Void) async throws {
        do { try await operation(); fatalError("Expected failure") }
        catch { /* Expected; postconditions below verify unchanged data. */ }
    }
}
