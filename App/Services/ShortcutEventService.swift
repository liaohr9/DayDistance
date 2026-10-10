import Foundation

/// All mutations use the running application's store and its existing CAS/backup path.
/// An uninstalled service fails closed rather than writing around a pending draft.
@MainActor
final class ShortcutEventService {
    static private(set) var shared = ShortcutEventService()

    private let store: EventStore?
    private let repositoryProvider: () throws -> EventRepository
    private let canUseUI: () -> Bool
    private let activateMain: () -> Void
    private let didCreate: (CountdownEvent) -> Void
    private let now: () -> Date
    private let timeZone: () -> TimeZone

    init(store: EventStore? = nil,
         repositoryProvider: @escaping () throws -> EventRepository = { try SharedContainer.repository() },
         canUseUI: @escaping () -> Bool = { true },
         activateMain: @escaping () -> Void = {},
         didCreate: @escaping (CountdownEvent) -> Void = { _ in },
         now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .autoupdatingCurrent }) {
        self.store = store
        self.repositoryProvider = repositoryProvider
        self.canUseUI = canUseUI
        self.activateMain = activateMain
        self.didCreate = didCreate
        self.now = now
        self.timeZone = timeZone
    }

    static func install(store: EventStore,
                        repositoryProvider: @escaping () throws -> EventRepository = { try SharedContainer.repository() },
                        canUseUI: @escaping () -> Bool = { true },
                        activateMain: @escaping () -> Void = {},
                        didCreate: @escaping (CountdownEvent) -> Void = { _ in }) {
        shared = ShortcutEventService(store: store, repositoryProvider: repositoryProvider,
                                      canUseUI: canUseUI, activateMain: activateMain, didCreate: didCreate)
    }

    func activeEvents() throws -> [CountdownEvent] {
        try ShortcutEventRepository(repository: repositoryProvider()).activeEvents()
    }

    var creationBackupWarning: String? { store?.backupMessage }

    func activeEvent(identifier: String) throws -> CountdownEvent {
        try ShortcutEventRepository(repository: repositoryProvider()).activeEvent(identifier: identifier)
    }

    func create(title: String, targetDate: Date, isAllDay: Bool) throws -> CountdownEvent {
        let store = try availableIdleStore()
        guard targetDate.timeIntervalSince1970.isFinite else { throw EventError.invalidDate }
        let date = now()
        let event = try CountdownEvent(title: title, targetDate: targetDate,
                                       isAllDay: isAllDay,
                                       calendarDay: isAllDay ? CalendarDay(date: targetDate, timeZone: timeZone()) : nil,
                                       createdAt: date, updatedAt: date).validated(now: date)
        // Keep the store's baseline: a newer on-disk writer must be reported as a conflict.
        guard store.upsert(event, replacing: nil), let saved = store.events.first(where: { $0.id == event.id }) else {
            throw ShortcutEventError.saveFailed(store.errorMessage ?? EventError.changedData.localizedDescription)
        }
        didCreate(saved)
        return saved
    }

    func days(identifier: String) throws -> (event: CountdownEvent, snapshot: CounterSnapshot) {
        let event = try activeEvent(identifier: identifier)
        return (event, DayCounter.snapshot(event: event, now: now(), timeZone: timeZone()))
    }

    func open(identifier: String) throws -> CountdownEvent {
        let store = try availableIdleStore()
        let selected = try activeEvent(identifier: identifier)
        // Refresh only after the idle guard, preserving all draft/modal/transfer boundaries.
        store.reload()
        guard store.isLoaded else {
            throw ShortcutEventError.saveFailed(store.errorMessage ?? EventError.unavailableContainer.localizedDescription)
        }
        guard let event = store.events.first(where: { $0.id == selected.id }) else { throw ShortcutEventError.missingEvent }
        guard event.isActive else { throw ShortcutEventError.inactiveEvent }
        store.open(ShortcutEventRepository.openURL(for: event.id))
        guard store.editingEvent?.event.id == event.id else { throw ShortcutEventError.interfaceBusy }
        activateMain()
        return event
    }

    private func availableIdleStore() throws -> EventStore {
        guard let store else { throw ShortcutEventError.applicationUnavailable }
        guard store.editingEvent == nil, !store.isTransferring, !store.isShowingBackups,
              !store.isHistoryModalPresented, canUseUI() else { throw ShortcutEventError.interfaceBusy }
        if !store.isLoaded { store.reload() }
        guard store.isLoaded else { throw ShortcutEventError.applicationUnavailable }
        return store
    }
}
