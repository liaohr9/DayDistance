import Foundation
import Darwin

@main struct Probe {
    static func require(_ condition: @autoclosure () throws -> Bool) rethrows {
        let value = try condition()
        precondition(value)
    }
    @MainActor static func main() throws {
        let mode = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
        let repo = EventRepository(fileURL: url)
        if mode == "transfer" {
            let store = EventStore(repository: repo)
            let incoming = CountdownEvent(title: "迁移的事件", targetDate: Date(timeIntervalSince1970: 1_800_000_000), createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_750_000_000))
            let source = EventRepository(fileURL: url.deletingLastPathComponent().appendingPathComponent("source.json"))
            try source.save([incoming], replacing: [])
            let original = try Data(contentsOf: source.fileURL)
            let snapshot = try source.exportSnapshot()
            guard store.importEvents(snapshot) == 1 else { print("FAIL: Store did not import one event"); exit(1) }
            try require(try repo.load() == [incoming])
            precondition(store.events == [incoming])
            precondition(store.importEvents(snapshot) == 0)
            let targetBytes = try Data(contentsOf: url)
            precondition(store.importEvents(Data("not json".utf8)) == nil)
            try require(try Data(contentsOf: url) == targetBytes)
            store.edit(incoming)
            let session = store.editingEvent!.id
            precondition(store.importEvents(snapshot) == nil)
            let copyURL = url.deletingLastPathComponent().appendingPathComponent("copy.json")
            do { try store.exportEvents(to: copyURL); preconditionFailure("Export allowed while editing") } catch {}
            precondition(store.editingEvent?.id == session)
            store.editingEvent = nil
            store.isTransferring = true
            precondition(!store.delete(incoming))
            precondition(!store.upsert(incoming, replacing: incoming))
            store.newEvent(); store.edit(incoming)
            store.open(URL(string: "daydistance://event/" + incoming.id.uuidString)!)
            precondition(store.editingEvent == nil)
            store.isTransferring = false
            let other = CountdownEvent(title: "其他窗口新增", targetDate: Date())
            try repo.save([incoming, other], replacing: [incoming])
            try store.exportEvents(to: copyURL)
            let copy = EventRepository(fileURL: copyURL)
            try require(try copy.load() == [incoming, other])
            precondition(store.importEvents(snapshot) == nil)
            precondition(store.events == [incoming, other])
            precondition(store.importEvents(snapshot) == 0)
            var conflict = incoming; conflict.title = "旧备份改名"
            try source.save([conflict], replacing: [incoming])
            let conflictingBackup = try source.exportSnapshot()
            precondition(store.importEvents(conflictingBackup) == nil)
            try require(try repo.load() == [incoming, other])
            precondition(original == snapshot)
            print("Store import/export, duplicates, corrupt/conflict/stale baseline, modal guard and latest export: PASS")
            return
        }
        if mode == "reload" {
            let seed = CountdownEvent(title: "加载后保留的事件", targetDate: Date())
            try repo.save([seed], replacing: [])
            let baseline = try Data(contentsOf: url)
            let store = EventStore(repository: repo)
            precondition(store.isLoaded && store.events == [seed])
            let corrupt = Data("{\"schemaVersion\":".utf8)
            for newer in [false, true] {
                let fault: Data
                if newer {
                    var envelope = try JSONSerialization.jsonObject(with: baseline) as! [String: Any]
                    envelope["schemaVersion"] = 8
                    fault = try JSONSerialization.data(withJSONObject: envelope)
                } else { fault = corrupt }
                try fault.write(to: url, options: .atomic)
                store.reload()
                precondition(!store.isLoaded && store.events == [seed])
                let readError = store.errorMessage
                precondition(readError != nil)
                store.newEvent(); store.edit(seed)
                precondition(store.editingEvent == nil)
                store.open(URL(string: "daydistance://event/" + seed.id.uuidString)!)
                precondition(store.errorMessage == readError, "Deep link cleared the read failure")
                store.open(URL(string: "daydistance://event/" + UUID().uuidString)!)
                precondition(store.errorMessage == readError)
                precondition(!store.delete(seed))
                precondition(store.errorMessage == readError)
                var draft = seed; draft.title = "拒绝的草稿"
                precondition(!store.upsert(draft, replacing: seed))
                precondition(store.errorMessage == readError)
                try require(try Data(contentsOf: url) == fault)
                try baseline.write(to: url, options: .atomic)
                store.reload()
                precondition(store.isLoaded && store.errorMessage == nil && store.events == [seed])
                store.edit(seed)
                precondition(store.editingEvent?.original == seed)
                store.editingEvent = nil
            }
            print("Store running reload failure: preserved snapshot/error/bytes, refused actions/deep links, recovery: PASS")
            return
        }
        if mode == "store" {
            let first = EventStore(repository: repo)
            let second = EventStore(repository: repo)
            let seed = CountdownEvent(title: "原事件", targetDate: Date())
            precondition(first.upsert(seed, replacing: nil))
            second.reload()
            let stale = second.events[0]
            second.edit(stale)
            let session = second.editingEvent!
            var newer = first.events[0]
            newer.title = "另一个窗口改名"
            precondition(first.upsert(newer, replacing: first.events[0]))
            var draft = stale
            draft.title = "旧表单的草稿"
            let latest = try Data(contentsOf: url)
            precondition(!second.upsert(draft, replacing: session.original))
            try require(try Data(contentsOf: url) == latest)
            precondition(second.events[0].title == "另一个窗口改名")
            second.open(URL(string: "daydistance://event/" + stale.id.uuidString)!)
            precondition(second.editingEvent?.original == session.original)
            second.open(URL(string: "daydistance://event/" + UUID().uuidString)!)
            precondition(second.editingEvent?.id == session.id)
            second.newEvent()
            second.edit(newer)
            precondition(second.editingEvent?.id == session.id)
            precondition(!second.upsert(draft, replacing: session.original))
            precondition(!second.delete(stale))
            try require(try Data(contentsOf: url) == latest)
            second.editingEvent = nil
            let current = second.events[0]
            precondition(second.delete(current))
            precondition(!first.upsert(newer, replacing: first.events[0]))
            try require(try repo.load().filter(\.isActive).isEmpty)
            first.edit(newer)
            let deletedSession = first.editingEvent!
            precondition(!first.upsert(newer, replacing: deletedSession.original))
            precondition(first.editingEvent?.original != nil)
            precondition(!first.upsert(newer, replacing: first.editingEvent!.original))
            try require(try repo.load().filter(\.isActive).isEmpty)
            first.editingEvent = nil
            let fresh = CountdownEvent(title: "新事件", targetDate: Date())
            precondition(first.upsert(fresh, replacing: nil))
            try require(try repo.load().last?.title == "新事件")
            print("Store stale edit/delete, retry, deletion and new save: PASS")
            return
        }
        let expected = try repo.load()
        if mode == "race" {
            let label = CommandLine.arguments[3]
            let dir = url.deletingLastPathComponent()
            try Data().write(to: dir.appendingPathComponent(label + ".ready"))
            let deadline = Date().addingTimeInterval(5)
            while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("go").path) {
                guard Date() < deadline else { throw NSError(domain: "ProbeTimeout", code: 1) }
                usleep(1000)
            }
        }
        do {
            try repo.save(expected + [CountdownEvent(title: mode, targetDate: Date())], replacing: expected)
        } catch EventError.changedData { exit(42) }
          catch EventError.busyData { exit(43) }
    }
}
