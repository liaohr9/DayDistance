import SwiftUI

// A disposable QA host renders production views with a temporary repository.
@main
struct ListUIProbe: App {
    @State private var store: EventStore
    @FocusedValue(\.eventActions) private var eventActions

    init() {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(folder.lastPathComponent.hasPrefix("daydistance-ui-") && folder.pathExtension == "noindex")
        let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "list"
        let repository = EventRepository(fileURL: folder.appendingPathComponent("data/events.json"))
        let now = Date()
        let events = (1...(mode == "list" ? 60 : 3)).map { index in
            CountdownEvent(
                title: String(format: "测试事件 %02d", index) + (index == 10 ? "：这是一段用来验证最小窗口下长名称显示与编辑的完整中文事件名称" : ""),
                targetDate: Calendar.current.date(byAdding: .day, value: index, to: now)!
            )
        }
        try! repository.save(events, replacing: [])
        let source = folder.appendingPathComponent("data/events.json")
        let baseline = try! Data(contentsOf: source)
        try! baseline.write(to: folder.appendingPathComponent("baseline.json"), options: .atomic)
        if mode == "read-corrupt" || mode == "read-newer" {
            if mode == "read-corrupt" {
                try! Data("{\"schemaVersion\":".utf8).write(to: source, options: .atomic)
            } else {
                var envelope = try! JSONSerialization.jsonObject(with: baseline) as! [String: Any]
                envelope["schemaVersion"] = 7
                try! JSONSerialization.data(withJSONObject: envelope).write(to: source, options: .atomic)
            }
        }
        _store = State(initialValue: EventStore(repository: repository))
    }

    var body: some Scene {
        WindowGroup("日距 · 临时列表测试") {
            ContentView(store: store).frame(minWidth: 640, minHeight: 360)
        }
        .defaultSize(width: 640, height: 360)
        .commands {
            // Only the QA host exposes reload; edit/delete invoke production
            // focused actions with the same availability as product commands.
            CommandMenu("验证") {
                Button("重新读取临时事件", action: store.reload)
                    .disabled(store.editingEvent != nil || store.isTransferring)
                Button("编辑事件") { eventActions?.edit() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(eventActions?.hasSelection != true)
                Button("删除事件") { eventActions?.delete() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(eventActions?.hasSelection != true)
            }
        }
    }
}
