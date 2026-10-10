import Foundation

/// Prevent an image or diagnostic export from replacing live data or recovery snapshots.
enum ExportDestinationPolicy {
    // Foundation can leave symlink parents unresolved when the final file does not exist.
    private static func resolve(_ url: URL) -> URL {
        var ancestor = url.standardizedFileURL
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var result = ancestor.resolvingSymlinksInPath()
        for component in suffix.reversed() { result.appendPathComponent(component) }
        return result.standardizedFileURL
    }
    static func validate(_ destination: URL, protectedFiles: [URL], protectedDirectories: [URL] = []) throws {
        let resolved = resolve(destination)
        let files = protectedFiles + protectedFiles.flatMap { [$0.appendingPathExtension("lock"), $0.appendingPathExtension("reminders.lock")] }
        let directories = protectedDirectories.map { resolve($0) }
        for folder in directories {
            guard resolved != folder, !resolved.path.hasPrefix(folder.path + "/") else { throw EventError.protectedExportDestination }
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        func aliases(_ url: URL) -> Bool {
            let target = resolve(url)
            if resolved == target { return true }
            guard let attributes, let other = try? FileManager.default.attributesOfItem(atPath: target.path) else { return false }
            return attributes[.systemFileNumber] as? NSNumber == other[.systemFileNumber] as? NSNumber
                && attributes[.systemNumber] as? NSNumber == other[.systemNumber] as? NSNumber
        }
        guard !files.contains(where: aliases) else { throw EventError.protectedExportDestination }
        if attributes != nil {
            for folder in directories {
                if let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsPackageDescendants]) {
                    for case let url as URL in entries where aliases(url) { throw EventError.protectedExportDestination }
                }
            }
        }
    }
}
