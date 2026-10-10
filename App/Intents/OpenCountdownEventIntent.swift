import AppIntents
import Foundation

struct OpenCountdownEventIntent: AppIntent {
    static var title = LocalizedStringResource("打开日距事件")
    static var description = IntentDescription(LocalizedStringResource("在日距中打开指定事件。不会保存事件或覆盖正在编辑的草稿。"))
    static var openAppWhenRun: Bool = true

    @Parameter(title: LocalizedStringResource("事件"), optionsProvider: CountdownEventOptionsProvider())
    var eventID: String

    static var parameterSummary: some ParameterSummary { Summary { \.$eventID } }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let event = try ShortcutEventService.shared.open(identifier: eventID)
        return .result(dialog: IntentDialog(stringLiteral: L10n.format("已打开：%@", event.title)))
    }
}
