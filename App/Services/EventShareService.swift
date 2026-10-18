import AppKit
import SwiftUI

@MainActor enum EventShareService {
    static func summary(event: CountdownEvent, now: Date) -> String {
        event.title + " · " + EventDisplayFormatter.summary(event: event, now: now)
    }
    static func copySummary(event: CountdownEvent, now: Date) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary(event: event, now: now), forType: .string)
    }
    static func png(event: CountdownEvent, now: Date, showDate: Bool) throws -> Data {
        let renderer = ImageRenderer(content: EventShareCard(event: event, now: now, showDate: showDate))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
    static func save(event: CountdownEvent, now: Date, showDate: Bool, to destination: URL, protecting files: [URL]) throws {
        let directories = files.map { LocalBackupRepository(eventFileURL: $0).folderURL } + ExportDestinationPolicy.smartListBackupDirectories(beside: files)
        let protected = files + ExportDestinationPolicy.smartListFiles(beside: files)
        try ExportDestinationPolicy.validate(destination, protectedFiles: protected, protectedDirectories: directories)
        let data = try png(event: event, now: now, showDate: showDate)
        try ExportDestinationPolicy.validate(destination, protectedFiles: protected, protectedDirectories: directories)
        try data.write(to: destination, options: .atomic)
    }
}
