import Foundation

enum ShortcutEventError: LocalizedError {
    case applicationUnavailable, interfaceBusy, invalidIdentifier, missingEvent, inactiveEvent, saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationUnavailable: return L10n.text("请先打开日距，确认事件数据可以读取，再运行快捷指令。")
        case .interfaceBusy: return L10n.text("日距正在编辑事件或显示对话框。请先保存或取消，再运行快捷指令。")
        case .invalidIdentifier: return L10n.text("事件标识无法识别。请在快捷指令中重新选择事件。")
        case .missingEvent: return L10n.text("该事件不存在或已被删除。")
        case .inactiveEvent: return L10n.text("该事件已归档或在回收站中。请先恢复事件。")
        case .saveFailed(let message): return message
        }
    }
}

/// Read-only access for parameter resolution and day queries. Never migrate, create, or save here.
struct ShortcutEventRepository: Sendable {
    let repository: EventRepository

    func activeEvents() throws -> [CountdownEvent] {
        try repository.load().filter(\.isActive).sorted {
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if $0.targetDate != $1.targetDate { return $0.targetDate < $1.targetDate }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func activeEvent(identifier: String) throws -> CountdownEvent {
        guard let id = UUID(uuidString: identifier) else { throw ShortcutEventError.invalidIdentifier }
        guard let event = try repository.load().first(where: { $0.id == id }) else { throw ShortcutEventError.missingEvent }
        guard event.isActive else { throw ShortcutEventError.inactiveEvent }
        return event
    }

    static func openURL(for id: UUID) -> URL {
        // UUID's textual form cannot introduce a URL delimiter.
        URL(string: "daydistance://event/\(id.uuidString)")!
    }
}
