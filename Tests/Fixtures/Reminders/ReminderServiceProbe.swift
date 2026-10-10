import Foundation
import UserNotifications

@MainActor private final class FakeNotifications: EventNotificationClient {
    var status: UNAuthorizationStatus = .authorized
    var pending: [String: UNNotificationRequest] = [:]
    var permissionCalls = 0
    var failAdds = false
    var blockNextAdd = false
    var blocked: CheckedContinuation<Void, Never>?
    var addCount = 0
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { permissionCalls += 1; return status == .authorized }
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
    func add(_ request: UNNotificationRequest) async throws {
        addCount += 1
        if blockNextAdd {
            blockNextAdd = false
            await withCheckedContinuation { blocked = $0 }
        }
        if failAdds { throw NSError(domain: "fixture", code: 1) }
        pending[request.identifier] = request
    }
    func removePending(identifiers: [String]) { for identifier in identifiers { pending.removeValue(forKey: identifier) } }
    func unblock() { let continuation = blocked; blocked = nil; continuation?.resume() }
}

@main struct ReminderServiceProbe {
    @MainActor static func main() async {
        let now = ISO8601DateFormatter().date(from: "2026-10-08T00:00:00Z")!
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let client = FakeNotifications()
        let unrelated = UNNotificationRequest(identifier: "another.feature", content: UNMutableNotificationContent(), trigger: nil)
        client.pending[unrelated.identifier] = unrelated
        let service = EventReminderService(client: client, now: { now }, timeZone: { zone })
        var event = CountdownEvent(title: "Original", targetDate: now.addingTimeInterval(172800), reminder: .onDay)
        await service.sync(events: [event])
        precondition(client.permissionCalls == 0 && client.pending.count == 2)
        precondition(service.nextScheduledDates[event.id] == event.targetDate)
        let initialID = client.pending.keys.first { $0.hasPrefix("daydistance.") }!
        let request = client.pending[initialID]!
        precondition(request.content.userInfo["eventID"] as? String == event.id.uuidString)
        precondition((request.trigger as? UNCalendarNotificationTrigger)?.dateComponents.timeZone == zone)
        event.title = "Title Only"
        await service.sync(events: [event])
        precondition(client.pending[initialID]?.content.title == "Title Only")
        event.targetDate = event.targetDate.addingTimeInterval(86400)
        event.title = "Edited"
        await service.sync(events: [event])
        precondition(client.pending[initialID] == nil && client.pending.count == 2)
        precondition(client.pending.values.contains { $0.content.title == "Edited" })
        await service.sync(events: [])
        precondition(client.pending.keys.sorted() == ["another.feature"])

        client.status = .denied
        await service.sync(events: [event])
        precondition(client.permissionCalls == 0 && client.pending.count == 1)
        precondition(service.nextScheduledDates.isEmpty)
        precondition(service.statusMessage?.contains("权限") == true)
        let denialMessage = await service.authorizeIfNeeded()
        precondition(denialMessage != nil)
        precondition(client.permissionCalls == 0)
        client.status = .notDetermined
        await service.sync(events: [event])
        precondition(client.permissionCalls == 0)
        let undeterminedMessage = await service.authorizeIfNeeded()
        precondition(undeterminedMessage != nil)
        precondition(client.permissionCalls == 1)

        client.status = .authorized

        // Custom choices reach the native request, and only real pending requests
        // appear as the next scheduled reminder.
        var custom = CountdownEvent(title: "Custom", targetDate: now.addingTimeInterval(5 * 86400), reminder: .custom)
        custom.reminderDaysBefore = 2
        custom.reminderTime = CalendarTime(hour: 10, minute: 30)
        await service.sync(events: [custom])
        let customRequest = client.pending.values.first { $0.identifier.hasPrefix("daydistance.") }!
        let customTrigger = customRequest.trigger as! UNCalendarNotificationTrigger
        precondition(customTrigger.dateComponents.day == 11 && customTrigger.dateComponents.hour == 10 && customTrigger.dateComponents.minute == 30)
        precondition(customRequest.content.body == L10n.format("距离这个日子还有 %ld 天。", 2))
        precondition(service.nextScheduledDates[custom.id] == ReminderPolicy.plan(events: [custom], now: now, timeZone: zone).requests.first?.fireDate)
        await service.sync(events: [])
        client.failAdds = true
        await service.sync(events: [custom])
        precondition(service.nextScheduledDates.isEmpty)
        client.failAdds = false
        client.failAdds = true
        await service.sync(events: [event])
        precondition(service.statusMessage?.contains("安排失败") == true)
        client.failAdds = false

        // Older suspended system work must be removed when a newer edit replaces its plan.
        client.blockNextAdd = true
        let oldTask = Task { await service.sync(events: [event]) }
        while client.blocked == nil { await Task.yield() }
        var latest = event
        latest.title = "Latest"
        latest.targetDate = latest.targetDate.addingTimeInterval(86400)
        var newSyncStarted = false
        let newTask = Task { newSyncStarted = true; await service.sync(events: [latest]) }
        while !newSyncStarted { await Task.yield() }
        client.unblock()
        await oldTask.value
        await newTask.value
        let owned = client.pending.values.filter { $0.identifier.hasPrefix("daydistance.") }
        precondition(owned.count == 1 && owned[0].content.title == "Latest")
        precondition(client.pending["another.feature"] != nil)

        // Floating all-day/annual dates omit both timezone containers; absolute dates retain theirs.
        let floatingEvent = CountdownEvent(title: "Floating", targetDate: now.addingTimeInterval(172800),
                                           isAllDay: true, calendarDay: CalendarDay(year: 2030, month: 10, day: 10), reminder: .onDay)
        await service.sync(events: [floatingEvent])
        let floatingRequest = client.pending.values.first { $0.identifier.hasPrefix("daydistance.") }!
        let floatingTrigger = floatingRequest.trigger as! UNCalendarNotificationTrigger
        precondition(floatingTrigger.dateComponents.calendar == nil && floatingTrigger.dateComponents.timeZone == nil)
        // NSTimeZone.default is process-local; this fixture does not change macOS settings.
        let originalZone = NSTimeZone.default
        NSTimeZone.default = zone
        let shanghaiNext = floatingTrigger.nextTriggerDate()!
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        let losAngelesNext = floatingTrigger.nextTriggerDate()!
        NSTimeZone.default = originalZone
        precondition(losAngelesNext.timeIntervalSince(shanghaiNext) == 15 * 3600)
        var yearlyEvent = floatingEvent
        yearlyEvent.isAllDay = false
        yearlyEvent.repeatYearly = true
        await service.sync(events: [yearlyEvent])
        let yearlyTrigger = client.pending.values.first { $0.identifier.hasPrefix("daydistance.") }!.trigger as! UNCalendarNotificationTrigger
        precondition(yearlyTrigger.dateComponents.calendar == nil && yearlyTrigger.dateComponents.timeZone == nil)
        precondition(service.statusMessage == nil)
        client.status = .denied
        event.reminder = .none
        await service.sync(events: [event])
        precondition(service.statusMessage == nil)
        precondition(client.pending.keys.sorted() == ["another.feature"])
        client.status = .authorized

        // A daily request must use its delivery day's count, not a fixed “today” body.
        var dailyEvent = CountdownEvent(title: "Daily", targetDate: now.addingTimeInterval(10 * 86400))
        dailyEvent.dailyReminderTime = CalendarTime(hour: 9, minute: 0)
        dailyEvent.monthlyReminderTime = CalendarTime(hour: 11, minute: 0)
        await service.sync(events: [dailyEvent])
        let dailyPlan = ReminderPolicy.plan(events: [dailyEvent], now: now, timeZone: zone, maximumRequests: 59)
        let firstDaily = dailyPlan.requests.first { $0.cadence == .daily }!
        precondition(client.pending[firstDaily.identifier]?.content.body == firstDaily.body)
        precondition(service.dailyCoverageDates[dailyEvent.id] != nil)
        precondition(client.pending.count == 60)
        client.status = .denied
        await service.sync(events: [dailyEvent])
        precondition(service.dailyCoverageDates.isEmpty)
        precondition(service.statusMessage?.contains("预排") != true)
        client.status = .authorized
        await service.sync(events: [])
        precondition(service.dailyCoverageDates.isEmpty)

        // Changing macOS permission must refresh the open settings without another save.
        client.status = .denied
        await service.sync(events: [dailyEvent])
        let beforePermissionRefresh = client.permissionCalls
        client.status = .authorized
        await service.refreshPermissionAndScheduleIfChanged()
        precondition(service.authorizationDescription == L10n.text("已允许") && service.nextScheduledDates[dailyEvent.id] != nil)
        let scheduledAfterPermission = Set(client.pending.keys)
        client.blockNextAdd = true
        await service.refreshPermissionAndScheduleIfChanged()
        precondition(client.blocked == nil && Set(client.pending.keys) == scheduledAfterPermission)
        client.blockNextAdd = false
        client.status = .denied
        await service.refreshPermissionAndScheduleIfChanged()
        precondition(service.authorizationDescription == L10n.text("已拒绝") && service.nextScheduledDates.isEmpty && service.dailyCoverageDates.isEmpty)
        precondition(client.permissionCalls == beforePermissionRefresh)
        client.status = .authorized

        // Disk, not stale window memory, is authoritative for background and foreground refresh.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = EventRepository(fileURL: root.appendingPathComponent("events.json"))
        try! repository.save([dailyEvent], replacing: [])
        let diskClient = FakeNotifications()
        let diskService = EventReminderService(client: diskClient, now: { now }, timeZone: { zone }, repositoryProvider: { repository })
        await diskService.sync(events: [])
        precondition(diskService.nextScheduledDates[dailyEvent.id] != nil && !diskClient.pending.isEmpty)
        let baseline = try! Data(contentsOf: repository.fileURL)
        let beforeReadError = Set(diskClient.pending.keys)
        try! Data("broken".utf8).write(to: repository.fileURL)
        await diskService.sync(events: [])
        precondition(Set(diskClient.pending.keys) == beforeReadError && diskService.statusMessage != nil)
        try! baseline.write(to: repository.fileURL)
        diskClient.blockNextAdd = true
        let pendingRefresh = Task { await diskService.sync(events: [dailyEvent]) }
        while diskClient.blocked == nil { await Task.yield() }
        try! repository.save([], replacing: [dailyEvent])
        let secondService = EventReminderService(client: diskClient, now: { now }, timeZone: { zone }, repositoryProvider: { repository })
        let secondRefresh = Task { await secondService.sync(events: [dailyEvent]) }
        diskClient.unblock()
        await pendingRefresh.value; await secondRefresh.value
        precondition(diskClient.pending.isEmpty && diskService.nextScheduledDates.isEmpty && secondService.nextScheduledDates.isEmpty)

        // The shared process limit includes requests belonging to other features.
        for index in 0..<10 {
            let request = UNNotificationRequest(identifier: "other.\(index)", content: UNMutableNotificationContent(), trigger: nil)
            client.pending[request.identifier] = request
        }
        let repeated = (0..<9).map { index in
            CountdownEvent(title: "Annual \(index)", targetDate: now.addingTimeInterval(Double(index + 3) * 86400),
                           repeatYearly: true, reminder: .onDay)
        }
        await service.sync(events: repeated)
        precondition(client.pending.count == 60)
        precondition(service.statusMessage?.contains("暂未安排") == true)
        for index in 10..<60 {
            let request = UNNotificationRequest(identifier: "other.\(index)", content: UNMutableNotificationContent(), trigger: nil)
            client.pending[request.identifier] = request
        }
        await service.sync(events: [dailyEvent])
        precondition(service.dailyCoverageDates.isEmpty && service.nextScheduledDates.isEmpty)
        precondition(service.statusMessage != nil && service.statusMessage?.contains("预排") != true)
        precondition(client.permissionCalls == 1)
        print("REMINDER_SERVICE_PASS: permission isolation, replacement, deletion, failed scheduling, stale edits, unrelated preservation, floating timezone, disabled permissions, custom and daily body/coverage, disk snapshot/read failures/concurrent refresh, capacity")
    }
}
