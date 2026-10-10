import AppKit
import Observation
import UserNotifications

@MainActor
protocol EventNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(identifiers: [String])
}

@MainActor
final class SystemEventNotificationClient: EventNotificationClient {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }
    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pendingRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
}

@Observable @MainActor
final class EventReminderService {
    private var problemMessage: String?
    private var renewalNotice: String?
    var statusMessage: String? { displayMessage(backgroundRefreshEnabled: false) }

    /// Hide only the informational coverage notice; retain permission and scheduling errors.
    func displayMessage(backgroundRefreshEnabled: Bool) -> String? {
        let messages = [problemMessage, backgroundRefreshEnabled ? nil : renewalNotice].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
    private(set) var nextScheduledDates: [UUID: Date] = [:]
    private(set) var dailyCoverageDates: [UUID: Date] = [:]
    @ObservationIgnored private let repositoryProvider: (() throws -> EventRepository)?
    private(set) var authorizationDescription = L10n.text("尚未检查")
    @ObservationIgnored private let client: any EventNotificationClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private var lastAuthorizationStatus: UNAuthorizationStatus?
    @ObservationIgnored private var latestEvents: [CountdownEvent] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private let notificationDelegate: EventNotificationDelegate?

    init(client: (any EventNotificationClient)? = nil, now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .autoupdatingCurrent }, repositoryProvider: (() throws -> EventRepository)? = nil) {
        self.repositoryProvider = repositoryProvider
        self.client = client ?? SystemEventNotificationClient()
        self.now = now
        self.timeZone = timeZone
        if client == nil {
            let delegate = EventNotificationDelegate()
            notificationDelegate = delegate
            UNUserNotificationCenter.current().delegate = delegate
        } else {
            notificationDelegate = nil
        }
    }

    /// Called only when a user saves an enabled reminder; startup and sync never prompt.
    func authorizeIfNeeded() async -> String? {
        let status = await client.authorizationStatus()
        updateAuthorizationDescription(status)
        switch status {
        case .authorized, .provisional: return nil
        case .denied: return L10n.text("通知权限已关闭。请在系统设置 → 通知 → 日距中开启；事件已保存。")
        case .notDetermined:
            do {
                let granted = try await client.requestAuthorization()
                authorizationDescription = granted ? L10n.text("已允许") : L10n.text("已拒绝")
                return granted ? nil : L10n.text("未获通知权限。请在系统设置 → 通知 → 日距中开启；事件已保存。")
            } catch {
                return L10n.format("无法申请通知权限：%@。事件已保存。", error.localizedDescription)
            }
        @unknown default: return L10n.text("无法确认通知权限。请检查系统设置 → 通知 → 日距。")
        }
    }

    /// Read only; never requests permission. Reschedule only when the system permission changes.
    func refreshPermissionAndScheduleIfChanged() async {
        let actual = await client.authorizationStatus()
        guard !Task.isCancelled else { return }
        let changed = actual != lastAuthorizationStatus
        updateAuthorizationDescription(actual)
        if changed { await sync(events: latestEvents) }
    }

    /// Coalesces concurrent edits and finishes the latest plan before any awaiting caller returns.
    func sync(events: [CountdownEvent]) async {
        latestEvents = events
        generation += 1
        if syncTask == nil {
            syncTask = Task { [weak self] in
                guard let self else { return }
                await self.drainQueue()
            }
        }
        await syncTask?.value
    }

    private func drainQueue() async {
        while true {
            let currentGeneration = generation
            let events = latestEvents
            await synchronize(events: events, generation: currentGeneration)
            if currentGeneration == generation { break }
        }
        syncTask = nil
    }

    private func synchronize(events: [CountdownEvent], generation expectedGeneration: Int) async {
        guard let repositoryProvider else { await applyPlan(events: events, generation: expectedGeneration); return }
        do {
            let repository = try repositoryProvider()
            let lockURL = repository.fileURL.appendingPathExtension("reminders.lock")
            var lease: ReminderSchedulingLock?
            for _ in 0..<100 {
                guard generation == expectedGeneration else { return }
                lease = try ReminderSchedulingLock.acquire(at: lockURL)
                if lease != nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard let lease else {
                renewalNotice = nil
                problemMessage = L10n.text("另一个进程正在更新提醒，请稍后重试。")
                return
            }
            // Keep the lease across asynchronous system calls; do not retain stale window data.
            defer { withExtendedLifetime(lease) {} }
            for _ in 0..<5 {
                let snapshot = try repository.load().filter(\.isActive)
                await applyPlan(events: snapshot, generation: expectedGeneration)
                guard generation == expectedGeneration else { return }
                if try repository.load().filter(\.isActive) == snapshot { return }
            }
            renewalNotice = nil
            problemMessage = L10n.text("事件正在持续更改，提醒将在下次刷新时更新。")
        } catch {
            renewalNotice = nil
            problemMessage = L10n.format("无法读取或更新提醒：%@。已有提醒已保留。", error.localizedDescription)
        }
    }

    private func applyPlan(events: [CountdownEvent], generation expectedGeneration: Int) async {
        let status = await client.authorizationStatus()
        guard generation == expectedGeneration else { return }
        updateAuthorizationDescription(status)
        let allowed = status == .authorized || status == .provisional
        let zone = timeZone()
        let plan = ReminderPolicy.plan(events: events, now: now(), timeZone: zone)
        let pending = await client.pendingRequests()
        guard generation == expectedGeneration else { return }
        // Also respect slots occupied by other notification features in this app.
        let unrelatedCount = pending.filter { !$0.identifier.hasPrefix(ReminderPolicy.identifierPrefix) }.count
        let available = max(0, ReminderPolicy.maximumRequests - unrelatedCount)
        let requests = allowed ? ReminderPolicy.limitedRequests(plan.requests, maximumRequests: available) : []
        let desiredIDs = Set(requests.map(\.identifier))
        let obsolete = pending.map(\.identifier).filter {
            $0.hasPrefix(ReminderPolicy.identifierPrefix) && !desiredIDs.contains($0)
        }
        client.removePending(identifiers: obsolete)
        var failures = 0
        for reminder in requests {
            guard generation == expectedGeneration else { return }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["eventID": reminder.eventID.uuidString]
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            // Floating day/annual reminders follow the device wall clock, including while quit.
            // An embedded calendar also embeds its timezone, so omit both for these events.
            if !reminder.followsDeviceTimeZone {
                components.calendar = calendar
                components.timeZone = zone
            }
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do { try await client.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)) }
            catch { failures += 1 }
        }
        guard generation == expectedGeneration else { return }
        let actualIDs = Set(await client.pendingRequests().map(\.identifier))
        guard generation == expectedGeneration else { return }
        var scheduled: [UUID: Date] = [:]
        for reminder in requests where actualIDs.contains(reminder.identifier) {
            scheduled[reminder.eventID] = min(scheduled[reminder.eventID] ?? reminder.fireDate, reminder.fireDate)
        }
        nextScheduledDates = scheduled
        var coverage: [UUID: Date] = [:]
        for event in events where event.dailyReminderTime != nil {
            let daily = plan.requests.filter { $0.eventID == event.id && $0.cadence == .daily }.sorted { $0.fireDate < $1.fireDate }
            for request in daily {
                guard actualIDs.contains(request.identifier) else { break }
                coverage[event.id] = request.fireDate
            }
        }
        dailyCoverageDates = coverage
        var messages: [String] = []
        var notice: String?
        if events.contains(where: { $0.hasEnabledReminders }), !allowed {
            messages.append(status == .notDetermined ? L10n.text("尚未允许通知。请编辑事件并保存已启用的提醒以申请权限。") : L10n.text("通知未获权限，请在系统设置 → 通知 → 日距中开启。"))
        }
        if plan.pastEventCount > 0 { messages.append(L10n.format("%ld 个事件的提醒时间已过，未安排通知。", plan.pastEventCount)) }
        if failures > 0 { messages.append(L10n.format("%ld 条提醒安排失败。请重新打开日距重试；事件已保存。", failures)) }
        let truncated = plan.truncatedRequestCount + max(0, plan.requests.count - available)
        if truncated > 0, allowed {
            if events.contains(where: { $0.hasRecurringReminders }) {
                let hasScheduledRecurring = requests.contains { $0.cadence != .once && actualIDs.contains($0.identifier) }
                if hasScheduledRecurring {
                    notice = L10n.text("重复提醒已预排有限日期。请查看设置中的覆盖日期；打开应用或启用后台刷新可继续补排。")
                } else {
                    messages.append(L10n.text("通知队列容量不足，提醒尚未安排。请重新打开日距补排。"))
                }
            } else {
                messages.append(L10n.format("提醒队列最多 60 条，已优先保留最近提醒；%ld 条暂未安排，请再次打开日距补排。", truncated))
            }
        }
        problemMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
        renewalNotice = notice
    }

    private func updateAuthorizationDescription(_ status: UNAuthorizationStatus) {
        lastAuthorizationStatus = status
        switch status {
        case .authorized: authorizationDescription = L10n.text("已允许")
        case .provisional: authorizationDescription = L10n.text("临时允许")
        case .denied: authorizationDescription = L10n.text("已拒绝")
        case .notDetermined: authorizationDescription = L10n.text("尚未申请")
        @unknown default: authorizationDescription = L10n.text("未知")
        }
    }
}

private final class EventNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let raw = response.notification.request.content.userInfo["eventID"] as? String,
              let id = UUID(uuidString: raw), let url = URL(string: "daydistance://event/\(id.uuidString)") else {
            completionHandler()
            return
        }
        Task { @MainActor in
            NSWorkspace.shared.open(url)
            completionHandler()
        }
    }
}
