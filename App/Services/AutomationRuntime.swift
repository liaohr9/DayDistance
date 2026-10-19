import AppKit
import Darwin
import Foundation
import OSLog

@MainActor enum AutomationAccess {
  static let readKey = "automationReadEnabled", writeKey = "automationWriteEnabled"
  static func permissions() -> (Bool, Bool) {
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    return (
      CFPreferencesCopyAppValue(readKey as CFString, kCFPreferencesCurrentApplication) as? Bool
        ?? false,
      CFPreferencesCopyAppValue(writeKey as CFString, kCFPreferencesCurrentApplication) as? Bool
        ?? false
    )
  }
  static func uiAvailable() -> Bool {
    NSApp.modalWindow == nil && !NSApp.windows.contains { $0.attachedSheet != nil }
  }
}

/// Retained for the process lifetime, including after the main window closes.
@MainActor final class AutomationController {
  static let shared = AutomationController()
  private var lease: AutomationLease?
  private var server: AutomationSocketServer?
  private var starting = false
  func start(
    store: EventStore, reminders: EventReminderService, open: @escaping (UUID) throws -> Void,
    directory customDirectory: URL? = nil
  ) async {
    guard !starting, server == nil else { return }
    store.prepareForReload = { [weak self, weak store, weak reminders] in
      guard let self else { return false }
      if self.lease != nil && (self.starting || self.server != nil) { return true }
      if !self.starting, let store, let reminders {
        Task {
          await self.start(
            store: store, reminders: reminders, open: open, directory: customDirectory)
        }
      }
      return false
    }
    starting = true
    defer { starting = false }
    do {
      let directory = customDirectory ?? AutomationChannel.directory()
      // Wait for a CLI save to finish before loading a GUI snapshot.
      while lease == nil {
        lease = try AutomationLease.acquire(in: directory)
        if lease == nil {
          // A simultaneous explicit launch may create a second GUI process.
          // Only the owner presents data; an unloaded duplicate exits safely.
          if (try await Task.detached(
            priority: .utility,
            operation: {
              try AutomationChannel.request(.init(operation: "capabilities"), directory: directory)
            }
          ).value) != nil {
            NSApp.terminate(nil)
            return
          }
          try await Task.sleep(for: .milliseconds(100))
        }
      }
      store.reload()
      let service = AutomationService(
        store: store, permissions: AutomationAccess.permissions,
        canUseUI: AutomationAccess.uiAvailable,
        sync: {
          await reminders.sync(events: store.events.filter(\.isActive))
          return reminders.statusMessage
        }, open: open)
      server = try AutomationSocketServer(directory: directory) { request in
        await service.execute(request)
      }
    } catch {
      store.errorMessage = L10n.text("无法准备本地数据访问。请重试；现有事件已保留。")
      // Retain the lease if listener creation fails: headless writers must not bypass the GUI.
      Logger(subsystem: "local.daydistance.mac", category: "automation").error(
        "Automation listener unavailable: \(error.localizedDescription,privacy:.private)")
    }
  }
}

@MainActor enum AutomationRuntime {
  static func execute(_ request: AutomationRequest) async -> JSONValue {
    do {
      let directory = AutomationChannel.directory()
      for _ in 0..<40 {
        if let reply = try await Task.detached(
          priority: .utility,
          operation: { try AutomationChannel.request(request, directory: directory) }
        ).value {
          return reply
        }
        var owner = try AutomationLease.acquire(in: directory)
        if owner != nil {
          var requestedOpen: UUID?
          let response: JSONValue
          do {
            let repository = try SharedContainer.repository()
            let store = EventStore(repository: repository)
            let reminders = EventReminderService(repositoryProvider: { repository })
            let service = AutomationService(
              store: store, permissions: AutomationAccess.permissions, canUseUI: { true },
              sync: {
                await reminders.sync(events: store.events.filter(\.isActive))
                return reminders.statusMessage
              }, open: { id in requestedOpen = id })
            response = await service.execute(request)
          } catch {
            response =
              AutomationFailure("UNAVAILABLE", "The event repository is not available.").response
          }
          withExtendedLifetime(owner) {}
          owner = nil  // A launching GUI must be able to load before receiving the event route.
          if let id = requestedOpen, response.object?["ok"] == .bool(true) {
            do { return try await openInOwnApplication(id) } catch {
              return AutomationFailure(
                "UNAVAILABLE", "DayDistance could not open the event. Open the app and retry."
              ).response
            }
          }
          return response
        }
        try await Task.sleep(for: .milliseconds(100))
      }
      return AutomationFailure(
        "BUSY", "DayDistance is starting or another command is finishing. Retry shortly."
      ).response
    } catch let e as AutomationFailure { return e.response } catch {
      return AutomationFailure(
        "UNAVAILABLE", "Local automation could not connect. Open DayDistance and retry."
      ).response
    }
  }
  private static func openInOwnApplication(_ id: UUID) async throws -> JSONValue {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    config.addsToRecentItems = false
    config.allowsRunningApplicationSubstitution = false
    config.promptsUserIfNeeded = false
    // The calling CLI/MCP process shares this bundle identity. Force a GUI
    // launch rather than letting LaunchServices send the request back to it.
    config.createsNewApplicationInstance = true
    _ = try await NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL, configuration: config)
    // Keep the UUID until the actual GUI listener acknowledges it. Launch completion
    // alone does not guarantee that SwiftUI has loaded the event store or its URL handler.
    let directory = AutomationChannel.directory()
    let request = AutomationRequest(operation: "open", arguments: ["id": .string(id.uuidString)])
    for _ in 0..<100 {
      if let reply = try await Task.detached(
        priority: .utility,
        operation: { try AutomationChannel.request(request, directory: directory) }
      ).value {
        return reply
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    return AutomationFailure(
      "BUSY", "DayDistance is still starting. Retry opening the event shortly."
    ).response
  }
  static func launch(arguments: [String]) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    // CLI/MCP stdout belongs exclusively to the protocol; AppKit logs go to stderr.
    L10n.useLanguage(SharedContainer.appliedLanguage())
    Task { @MainActor in
      if arguments == ["mcp"] {
        await serveMCP()
        exit(0)
      }
      do {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
          print(AutomationCLI.help)
          exit(0)
        }
        let request: AutomationRequest
        if arguments == ["--stdin"] {
          let data = try await Task.detached { try AutomationStdioReader().readOneDocument() }.value
          request = try JSONDecoder().decode(AutomationRequest.self, from: data)
        } else {
          request = try AutomationCLI.parse(arguments)
        }
        let response = await execute(request)
        try AutomationChannel.writeLine(response.encoded(), to: STDOUT_FILENO)
        exit(exitCode(response))
      } catch let e as AutomationFailure {
        emitFailure(e)
        exit(64)
      } catch {
        emitFailure(.invalid("Expected a valid JSON API request or command. Use --help."))
        exit(64)
      }
    }
    app.run()
  }
  static func exitCode(_ response: JSONValue) -> Int32 {
    if response.object?["ok"] == .bool(true) { return 0 }
    switch response.object?["error"]?.object?["code"]?.string {
    case "DISABLED", "READ_ONLY": return 77
    case "BUSY", "CONFLICT": return 75
    case "NOT_FOUND", "EVENT_REMOVED": return 66
    case "INVALID_ARGUMENT", "UNSUPPORTED_API_VERSION": return 64
    default: return 70
    }
  }
  private static func emitFailure(_ failure: AutomationFailure) {
    if let data = try? failure.response.encoded() {
      try? AutomationChannel.writeLine(data, to: STDOUT_FILENO)
    }
  }
  private static func serveMCP() async {
    let reader = AutomationStdioReader()
    let server = AutomationMCP { request in await execute(request) }
    while true {
      do {
        guard
          let data = try await Task.detached(priority: .utility, operation: { try reader.next() })
            .value
        else { return }
        let reply: JSONValue?
        do {
          reply = await server.respond(try JSONDecoder().decode(JSONValue.self, from: data))
        } catch { reply = AutomationMCP.parseError() }
        if let reply {
          let bytes = try reply.encoded()
          guard bytes.count <= AutomationChannel.responseLimit else { return }
          try AutomationChannel.writeLine(bytes, to: STDOUT_FILENO)
        }
      } catch { return }
    }
  }
}

/// Buffered line framing retains coalesced stdin messages and enforces the same input bound.
final class AutomationStdioReader: @unchecked Sendable {
  private var buffer = Data()
  func next() throws -> Data? {
    while true {
      if let i = buffer.firstIndex(of: 10) {
        guard i <= AutomationChannel.requestLimit else {
          throw AutomationFailure("TOO_LARGE", "Input limit: 64 KiB.")
        }
        let line = buffer.prefix(upTo: i)
        buffer.removeSubrange(...i)
        return Data(line)
      }
      guard buffer.count <= AutomationChannel.requestLimit else {
        throw AutomationFailure("TOO_LARGE", "Input limit: 64 KiB.")
      }
      guard let more = try readChunk() else {
        guard buffer.isEmpty else {
          throw AutomationFailure.invalid("Expected a newline-terminated JSON message.")
        }
        return nil
      }
      buffer.append(more)
    }
  }
  private func readChunk() throws -> Data? {
    var bytes = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
      if count < 0 && errno == EINTR { continue }
      guard count >= 0 else { throw AutomationFailure("UNAVAILABLE", "Cannot read stdin.") }
      return count == 0 ? nil : Data(bytes.prefix(count))
    }
  }
  func readOneDocument() throws -> Data {
    var result = Data()
    while let more = try readChunk() {
      result.append(more)
      guard result.count <= AutomationChannel.requestLimit else {
        throw AutomationFailure("TOO_LARGE", "Input limit: 64 KiB.")
      }
    }
    return result
  }
}
