import AppKit
import SwiftUI

// Used only by a generated QA copy of the production App entrypoint.
// No URL scheme is registered; every test link explicitly targets this bundle.
@MainActor enum LifecycleProbeRepository {
    static var root: URL { Bundle.main.bundleURL.deletingLastPathComponent() }

    static func makeStore() -> EventStore {
        let folder = root
        precondition(folder.lastPathComponent.hasPrefix("daydistance-ui-") && folder.pathExtension == "noindex")
        precondition(folder.deletingLastPathComponent().resolvingSymlinksInPath() == URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath())
        precondition(folder.resolvingSymlinksInPath().path == folder.standardizedFileURL.path)
        let dataFolder = folder.appendingPathComponent("data", isDirectory: true)
        precondition(dataFolder.resolvingSymlinksInPath().path == dataFolder.standardizedFileURL.path)
        let file = dataFolder.appendingPathComponent("events.json")
        let baseline = folder.appendingPathComponent("baseline.json")
        let repository = EventRepository(fileURL: file)
        if !FileManager.default.fileExists(atPath: baseline.path) {
            let events = (1...3).map { index in
                CountdownEvent(title: String(format: "测试事件 %02d", index),
                    targetDate: Calendar.current.date(byAdding: .day, value: index, to: Date())!)
            }
            try! repository.save(events, replacing: [])
            try! Data(contentsOf: file).write(to: baseline, options: .atomic)
        }
        return EventStore(repository: repository)
    }

    static func deliver(_ url: URL) {
        precondition(Bundle.main.bundleIdentifier == "local.daydistance.uiprobe")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error { NSLog("QA URL delivery failed: %@", error.localizedDescription) }
        }
    }

    static func openEvent(_ title: String) {
        let repository = EventRepository(fileURL: root.appendingPathComponent("data/events.json"))
        guard let event = try? repository.load().first(where: { $0.title == title }) else { return }
        deliver(URL(string: "daydistance://event/\(event.id.uuidString)")!)
    }
}

struct LifecycleProbeCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("验证") {
            Button("打开临时事件01链接") { LifecycleProbeRepository.openEvent("测试事件 01") }
            Button("打开临时事件02链接") { LifecycleProbeRepository.openEvent("测试事件 02") }
            Button("打开不存在的临时事件链接") {
                LifecycleProbeRepository.deliver(URL(string: "daydistance://event/00000000-0000-0000-0000-000000000000")!)
            }
            Button("打开无效的临时链接") {
                LifecycleProbeRepository.deliver(URL(string: "daydistance://event/not-a-uuid")!)
            }
            Divider()
            Button("打开另一个测试窗口") { openWindow(id: "main") }
        }
    }
}
