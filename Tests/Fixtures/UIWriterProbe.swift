import Foundation
import Darwin

// A separate process writes through the real repository's lock/CAS protocol.
@main
struct UIWriterProbe {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
        precondition(folder.deletingLastPathComponent() == temporary)
        precondition(folder.lastPathComponent.hasPrefix("daydistance-ui-") && folder.pathExtension == "noindex")
        // Validate independently: this binary can also be invoked directly.
        for component in ["data", "data/events.json", "data/events.json.lock"] {
            let url = folder.appendingPathComponent(component)
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0,
                  metadata.st_mode & S_IFMT != S_IFLNK,
                  url.resolvingSymlinksInPath().path.hasPrefix(folder.path + "/") else {
                fputs("Refusing an escaped or missing QA data path.\n", stderr)
                exit(2)
            }
        }
        let repository = EventRepository(fileURL: folder.appendingPathComponent("data/events.json"))
        let baseline = try repository.load()
        guard var event = baseline.first else { preconditionFailure("Missing QA event") }
        event.title = "其他进程保存的名称"
        event.updatedAt = Date()
        try repository.save([event] + baseline.dropFirst(), replacing: baseline)
        print("Separate repository writer renamed the first temporary event.")
    }
}
