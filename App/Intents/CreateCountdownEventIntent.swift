import AppIntents
import Foundation

struct CreateCountdownEventIntent: AppIntent {
    static var title = LocalizedStringResource("创建日距事件")
    static var description = IntentDescription(LocalizedStringResource("创建一个新事件并返回事件标识。通知默认关闭；编辑或对话框打开时不会创建。"))
    static var openAppWhenRun: Bool = true

    @Parameter(title: LocalizedStringResource("事件名称")) var name: String
    @Parameter(title: LocalizedStringResource("目标日期")) var date: Date
    @Parameter(title: LocalizedStringResource("全天"), default: false) var allDay: Bool

    static var parameterSummary: some ParameterSummary {
        Summary { \.$name; \.$date; \.$allDay }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let event = try ShortcutEventService.shared.create(title: name, targetDate: date, isAllDay: allDay)
        var message = L10n.format("已创建：%@", event.title)
        // Saving succeeds independently of backup availability; make a backup failure visible.
        if let warning = ShortcutEventService.shared.creationBackupWarning { message += "\n" + warning }
        return .result(value: event.id.uuidString, dialog: IntentDialog(stringLiteral: message))
    }
}
