import Foundation
import Darwin

enum SharedContainer {
    static var isLocalDevelopment: Bool {
        Bundle.main.object(forInfoDictionaryKey: "DayDistanceStorageMode") as? String == "local"
    }
    static var groupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "DayDistanceAppGroup") as? String ?? "group.local.daydistance.shared"
    }
    // Path protection does not grant access or read these migration sources.
    static func protectedDataURLs() -> [URL] {
        var urls: [URL] = []
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            let base = URL(fileURLWithPath: String(cString: home), isDirectory: true)
            urls.append(base.appendingPathComponent("Library/Application Support/DayDistanceLocal/events.json"))
            urls.append(base.appendingPathComponent("Library/Group Containers/\(groupIdentifier)/events.json"))
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(support.appendingPathComponent("DayDistance/events.json"))
        }
        return urls
    }
    static func repository() throws -> EventRepository {
        if isLocalDevelopment {
            // NSHomeDirectory is redirected into the sandbox. POSIX gives the account home.
            // Access is limited by each target's explicit directory entitlement.
            guard let home = getpwuid(getuid())?.pointee.pw_dir else { throw EventError.unavailableContainer }
            let url = URL(fileURLWithPath: String(cString: home), isDirectory: true)
                .appendingPathComponent("Library/Application Support/DayDistanceLocal/events.json")
            return EventRepository(fileURL: url)
        }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw EventError.unavailableContainer
        }
        return EventRepository(fileURL: container.appendingPathComponent("events.json"))
    }
    static func loadForApplication() throws -> (EventRepository, [CountdownEvent]) {
        let destination = try repository()
        if isLocalDevelopment {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let legacy = EventRepository(fileURL: support.appendingPathComponent("DayDistance/events.json"))
            return (destination, try destination.loadMigrating(from: legacy))
        }
        return (destination, try destination.load())
    }
}
