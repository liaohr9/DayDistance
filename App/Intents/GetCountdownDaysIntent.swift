import AppIntents
import Foundation

struct GetCountdownDaysIntent: AppIntent {
    static var title = LocalizedStringResource("查询日距天数")
    static var description = IntentDescription(LocalizedStringResource("读取指定事件的天数。结果为非负整数，摘要区分还有与已过；归档或删除的事件不会替换为其他事件。"))
    static var openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("事件"), optionsProvider: CountdownEventOptionsProvider())
    var eventID: String

    static var parameterSummary: some ParameterSummary { Summary { \.$eventID } }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let result = try ShortcutEventService.shared.days(identifier: eventID)
        let message = L10n.format("%@ · %@", result.event.title, result.snapshot.summary(for: result.event))
        return .result(value: result.snapshot.days, dialog: IntentDialog(stringLiteral: message))
    }
}
