import Foundation

enum EventLifecycle: String, Codable, Sendable { case active, archived, trashed }

enum EventDisplayFormat: String, Codable, CaseIterable, Sendable {
    case days, weeks, calendar, anniversary

    var label: String {
        switch self {
        case .days: return L10n.text("天数")
        case .weeks: return L10n.text("周 / 天")
        case .calendar: return L10n.text("年 / 月 / 天")
        case .anniversary: return L10n.text("周年")
        }
    }
}

enum EventReminder: String, Codable, CaseIterable, Sendable {
    case none, onDay, dayBefore, custom
    var label: String {
        switch self { case .none: return L10n.text("不提醒"); case .onDay: return L10n.text("当天"); case .dayBefore: return L10n.text("提前一天"); case .custom: return L10n.text("自定义") }
    }
}

struct CountdownEvent: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var targetDate: Date
    var isAllDay: Bool
    var calendarDay: CalendarDay?
    var annualTime: CalendarTime?
    var repeatYearly: Bool
    var isPinned: Bool
    var reminder: EventReminder
    var reminderDaysBefore: Int = 0
    var reminderTime: CalendarTime?
    var dailyReminderTime: CalendarTime?
    var monthlyReminderTime: CalendarTime?
    var yearlyReminderTime: CalendarTime?
    var hasEnabledReminders: Bool { reminder != .none || hasRecurringReminders }
    var hasRecurringReminders: Bool { dailyReminderTime != nil || monthlyReminderTime != nil || yearlyReminderTime != nil }
    var lifecycle: EventLifecycle
    var trashedAt: Date?
    var wasArchivedBeforeTrash: Bool
    var isActive: Bool { lifecycle == .active }
    var includesStartDay: Bool
    var displayFormat: EventDisplayFormat
    var symbol: String
    var colorKey: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, targetDate: Date, includesStartDay: Bool = false, displayFormat: EventDisplayFormat = .days, isAllDay: Bool = false, calendarDay: CalendarDay? = nil, annualTime: CalendarTime? = nil, repeatYearly: Bool = false, isPinned: Bool = false, reminder: EventReminder = .none, lifecycle: EventLifecycle = .active, trashedAt: Date? = nil, wasArchivedBeforeTrash: Bool = false, symbol: String = "calendar", colorKey: String = "sage", tags: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.targetDate = targetDate
        self.isAllDay = isAllDay; self.calendarDay = calendarDay; self.annualTime = annualTime
        self.repeatYearly = repeatYearly; self.isPinned = isPinned; self.reminder = reminder
        self.lifecycle = lifecycle; self.trashedAt = trashedAt; self.wasArchivedBeforeTrash = wasArchivedBeforeTrash
        self.includesStartDay = includesStartDay
        self.displayFormat = displayFormat
        self.symbol = symbol; self.colorKey = colorKey; self.tags = tags
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case reminderDaysBefore, reminderTime, dailyReminderTime, monthlyReminderTime, yearlyReminderTime
        case tags, id, title, targetDate, includesStartDay, displayFormat, isAllDay, calendarDay, annualTime, repeatYearly, isPinned, reminder, lifecycle, trashedAt, wasArchivedBeforeTrash, symbol, colorKey, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        targetDate = try values.decode(Date.self, forKey: .targetDate)
        isAllDay = try values.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        calendarDay = try values.decodeIfPresent(CalendarDay.self, forKey: .calendarDay)
        annualTime = try values.decodeIfPresent(CalendarTime.self, forKey: .annualTime)
        repeatYearly = try values.decodeIfPresent(Bool.self, forKey: .repeatYearly) ?? false
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        reminder = try values.decodeIfPresent(EventReminder.self, forKey: .reminder) ?? .none
        reminderDaysBefore = try values.decodeIfPresent(Int.self, forKey: .reminderDaysBefore) ?? 0
        reminderTime = try values.decodeIfPresent(CalendarTime.self, forKey: .reminderTime)
        dailyReminderTime = try values.decodeIfPresent(CalendarTime.self, forKey: .dailyReminderTime)
        monthlyReminderTime = try values.decodeIfPresent(CalendarTime.self, forKey: .monthlyReminderTime)
        yearlyReminderTime = try values.decodeIfPresent(CalendarTime.self, forKey: .yearlyReminderTime)
        lifecycle = try values.decodeIfPresent(EventLifecycle.self, forKey: .lifecycle) ?? .active
        trashedAt = try values.decodeIfPresent(Date.self, forKey: .trashedAt)
        wasArchivedBeforeTrash = try values.decodeIfPresent(Bool.self, forKey: .wasArchivedBeforeTrash) ?? false
        includesStartDay = try values.decodeIfPresent(Bool.self, forKey: .includesStartDay) ?? false
        displayFormat = try values.decodeIfPresent(EventDisplayFormat.self, forKey: .displayFormat) ?? .days
        symbol = try values.decode(String.self, forKey: .symbol)
        colorKey = try values.decode(String.self, forKey: .colorKey)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }

    static func tagIdentity(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(tagIdentity($0)).inserted }
    }
    static func parseTags(_ text: String) -> [String] {
        normalizedTags(text.components(separatedBy: CharacterSet(charactersIn: ",，;；\n")))
    }

    func validated(now: Date) throws -> Self {
        var result = self
        // Keep a typed display choice while editing; the formatter handles anniversary on nonannual events.
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.tags = Self.normalizedTags(tags)
        guard result.tags.count <= 30, result.tags.allSatisfy({ $0.count <= 40 }) else { throw EventError.invalidTags }
        guard !result.title.isEmpty else { throw EventError.blankTitle }
        guard targetDate.timeIntervalSince1970.isFinite else { throw EventError.invalidDate }
        result.targetDate = Date(timeIntervalSince1970: floor(targetDate.timeIntervalSince1970 / 60) * 60)
        if isAllDay || repeatYearly {
            if result.calendarDay == nil { result.calendarDay = CalendarDay(date: targetDate) }
            if repeatYearly && result.annualTime == nil { result.annualTime = CalendarTime(date: targetDate) }
        }
        if let day = result.calendarDay, day.date(timeZone: .autoupdatingCurrent) == nil { throw EventError.invalidDate }
        if let time = result.annualTime, !(0..<24).contains(time.hour) || !(0..<60).contains(time.minute) { throw EventError.invalidDate }
        guard (0...365).contains(reminderDaysBefore) else { throw EventError.invalidDate }
        if let time = reminderTime, !(0..<24).contains(time.hour) || !(0..<60).contains(time.minute) { throw EventError.invalidDate }
        if reminder == .custom && reminderTime == nil { throw EventError.invalidDate }
        for time in [dailyReminderTime, monthlyReminderTime, yearlyReminderTime].compactMap({ $0 }) {
            guard (0..<24).contains(time.hour), (0..<60).contains(time.minute) else { throw EventError.invalidDate }
        }
        if lifecycle == .trashed {
            guard let trashedAt, trashedAt.timeIntervalSince1970.isFinite else { throw EventError.invalidDate }
        }
        result.updatedAt = now
        return result
    }
}

// An editing session keeps its baseline even when the event list is refreshed.
struct EventEditSession: Identifiable, Sendable {
    let id = UUID()
    let event: CountdownEvent
    let original: CountdownEvent?
    init(event: CountdownEvent, isNew: Bool = false) {
        self.event = event
        self.original = isNew ? nil : event
    }
}

enum EventError: LocalizedError {
    case invalidTags, blankTitle, invalidDate, unsupportedVersion, duplicateID, unavailableContainer, changedData, busyData, importConflict, protectedExportDestination
    var errorDescription: String? {
        switch self {
        case .invalidTags: return L10n.text("最多添加 30 个标签，每个标签不超过 40 个字。")
        case .blankTitle: return L10n.text("请填写事件名称。")
        case .invalidDate: return L10n.text("日期无法识别，请重新选择。")
        case .unsupportedVersion: return L10n.text("数据来自较新版本，请升级应用后再打开。原文件已保留。")
        case .duplicateID: return L10n.text("事件数据包含重复标识。原文件已保留。")
        case .unavailableContainer: return L10n.text("无法访问事件数据目录。请重新打开日距，检查数据访问。")
        case .changedData: return L10n.text("事件已在其他窗口或进程中更改。请取消并重新打开，再确认修改。")
        case .busyData: return L10n.text("其他窗口或进程正在保存，请稍后重试。")
        case .importConflict: return L10n.text("备份中存在同一事件的不同版本。未导入任何事件，请核对后重试。")
        case .protectedExportDestination: return L10n.text("不能覆盖应用的事件数据或锁文件。请选择其他位置保存备份。")
        }
    }
}
