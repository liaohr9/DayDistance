import Foundation

/// Shared by the GUI socket handler and the signed executable's headless CLI path.
@MainActor final class AutomationService {
  private let store: EventStore
  private let permissions: () -> (read: Bool, write: Bool)
  private let canUseUI: () -> Bool
  private let sync: () async -> String?
  private let open: (UUID) throws -> Void
  private var isMutating = false
  init(
    store: EventStore, permissions: @escaping () -> (Bool, Bool), canUseUI: @escaping () -> Bool,
    sync: @escaping () async -> String?,
    open: @escaping (UUID) throws -> Void = { _ in
      throw AutomationFailure("UNAVAILABLE", "The UI route is not installed.")
    }
  ) {
    self.store = store
    self.permissions = permissions
    self.canUseUI = canUseUI
    self.sync = sync
    self.open = open
  }
  func execute(_ request: AutomationRequest) async -> JSONValue {
    do {
      return .object([
        "apiVersion": .number(1), "ok": .bool(true), "data": try await perform(request),
      ])
    } catch let failure as AutomationFailure { return failure.response } catch EventError
      .changedData
    {
      return AutomationFailure("CONFLICT", "The event changed; read it again before retrying.")
        .response
    } catch EventError.busyData {
      return AutomationFailure("BUSY", "Another operation is saving. Retry later.").response
    } catch {
      return AutomationFailure(
        "STORAGE_ERROR", "The event could not be saved or read. Existing data was preserved."
      ).response
    }
  }
  private func perform(_ request: AutomationRequest) async throws -> JSONValue {
    guard request.apiVersion == 1 else {
      throw AutomationFailure("UNSUPPORTED_API_VERSION", "Supported apiVersion: 1")
    }
    let (read, write) = permissions()
    let op = request.operation
    let a = request.arguments
    if op == "capabilities" {
      try keys(a, allowed: [])
      return .object([
        "readEnabled": .bool(read), "writeEnabled": .bool(read && write),
        "operations": .array(
          ["list", "get", "countdown", "create", "update", "archive", "trash", "restore", "open"]
            .map(JSONValue.string)), "timePrecision": .string("minute"),
      ])
    }
    guard read else {
      throw AutomationFailure(
        "DISABLED", "Enable local automation in DayDistance Settings → Automation.")
    }
    guard store.isLoaded else {
      throw AutomationFailure("UNAVAILABLE", "Event data is not available.")
    }
    if op == "list" {
      try keys(a, allowed: ["query", "tags", "state", "limit", "offset"])
      let state = try string(a, "state") ?? "active"
      guard ["active", "archived", "trashed", "all"].contains(state) else {
        throw AutomationFailure.invalid("Unknown state.")
      }
      let limit = try integer(a, "limit", default: 100)
      let offset = try integer(a, "offset", default: 0)
      guard (1...200).contains(limit), offset >= 0 else {
        throw AutomationFailure.invalid("limit must be 1–200 and offset nonnegative.")
      }
      let query = try string(a, "query") ?? ""
      let tags = try strings(a, "tags") ?? []
      let events = store.events.filter { e in
        (state == "all" || e.lifecycle.rawValue == state)
          && (query.isEmpty || e.title.localizedStandardContains(query))
          && tags.allSatisfy { tag in
            e.tags.contains { CountdownEvent.tagIdentity($0) == CountdownEvent.tagIdentity(tag) }
          }
      }.sorted {
        $0.targetDate == $1.targetDate
          ? $0.id.uuidString < $1.id.uuidString : $0.targetDate < $1.targetDate
      }
      return .object([
        "events": .array(events.dropFirst(offset).prefix(limit).map(dto)),
        "total": .number(Double(events.count)), "offset": .number(Double(offset)),
      ])
    }
    if ["get", "countdown"].contains(op) {
      try keys(a, allowed: ["id"])
      let e = try event(a)
      if op == "get" { return .object(["event": dto(e)]) }
      let snap = DayCounter.snapshot(event: e, now: Date())
      return .object([
        "event": dto(e), "days": .number(Double(snap.days)),
        "direction": .string(snap.isFuture ? "remaining" : "elapsed"),
        "sameDay": .bool(snap.isSameDay),
        "timeZone": .string(TimeZone.autoupdatingCurrent.identifier),
      ])
    }
    guard ["create", "update", "archive", "trash", "restore", "open"].contains(op) else {
      throw AutomationFailure.invalid("Unknown operation.")
    }
    guard !isMutating, store.canManageData, canUseUI() else {
      throw AutomationFailure("BUSY", "Finish the active edit or file operation, then retry.")
    }
    if op == "open" {
      try keys(a, allowed: ["id"])
      let e = try event(a)
      guard e.isActive else {
        throw AutomationFailure("INACTIVE_EVENT", "Restore the event before opening it.")
      }
      try open(e.id)
      return .object(["id": .string(e.id.uuidString), "opening": .bool(true)])
    }
    guard write else {
      throw AutomationFailure("READ_ONLY", "Enable write access in Settings → Automation.")
    }
    isMutating = true
    defer { isMutating = false }
    let fields: Set<String> = [
      "title", "at", "date", "tags", "includesStartDay", "repeatYearly", "pinned",
    ]
    var saved: CountdownEvent
    if op == "create" {
      try keys(a, allowed: fields.union(["requestId"]))
      guard let key = try string(a, "requestId"), !key.isEmpty, key.utf8.count <= 256 else {
        throw AutomationFailure.invalid("A requestId of 1–256 bytes is required for safe retries.")
      }
      let title = try string(a, "title", required: true)!
      let e = try patched(
        CountdownEvent(title: title, targetDate: Date()), arguments: a, creating: true)
      let payload: JSONValue = .object([
        "title": .string(e.title),
        "at": .string(e.isAllDay ? "" : AutomationDates.timestamp(e.targetDate)),
        "allDay": .bool(e.isAllDay),
        "day": .string(
          (e.isAllDay ? e.calendarDay : nil).map {
            String(format: "%04d-%02d-%02d", $0.year, $0.month, $0.day)
          } ?? ""),
        "tags": .array(e.tags.map(JSONValue.string)), "includesStartDay": .bool(e.includesStartDay),
        "repeatYearly": .bool(e.repeatYearly), "pinned": .bool(e.isPinned),
      ])
      let keyHash = JSONValue.digest(Data(("daydistance-api-v1:" + key).utf8))
      let payloadHash = JSONValue.digest(try payload.encoded())
      if let receipt = try store.automationReceipt(for: keyHash) {
        guard receipt.payloadHash == payloadHash else {
          throw AutomationFailure(
            "CONFLICT", "This requestId was already used with different fields.")
        }
        guard let existing = store.events.first(where: { $0.id == receipt.eventID }) else {
          throw AutomationFailure(
            "EVENT_REMOVED",
            "This request was already saved, but its event was removed. Use a new requestId for a new event."
          )
        }
        return .object([
          "event": dto(existing), "replayed": .bool(true), "sideEffects": .string("notRepeated"),
        ])
      }
      guard
        store.upsert(
          e, replacing: nil,
          automationReceipt: (keyHash, .init(payloadHash: payloadHash, eventID: e.id)))
      else {
        throw store.lastPersistenceFailure
          ?? AutomationFailure("SAVE_FAILED", "The event could not be saved.")
      }
      saved = store.events.first(where: { $0.id == e.id })!
    } else {
      try keys(a, allowed: op == "update" ? fields.union(["id", "revision"]) : ["id", "revision"])
      let old = try event(a)
      guard try string(a, "revision", required: true) == revision(old) else {
        throw AutomationFailure("CONFLICT", "The revision is out of date; read the event again.")
      }
      var value = old
      switch op {
      case "update":
        guard !Set(a.keys).isDisjoint(with: fields) else {
          throw AutomationFailure.invalid("No fields to update.")
        }
        value = try patched(old, arguments: a, creating: false)
      case "archive":
        guard old.lifecycle != .trashed else {
          throw AutomationFailure("INACTIVE_EVENT", "Restore a trashed event first.")
        }
        value.lifecycle = .archived
      case "trash":
        if old.lifecycle != .trashed {
          value.wasArchivedBeforeTrash = old.lifecycle == .archived
          value.lifecycle = .trashed
          value.trashedAt = Date()
        }
      case "restore":
        value.lifecycle =
          old.lifecycle == .trashed && old.wasArchivedBeforeTrash ? .archived : .active
        value.trashedAt = nil
        value.wasArchivedBeforeTrash = false
      default: break
      }
      guard store.upsert(value, replacing: old) else {
        throw store.lastPersistenceFailure
          ?? AutomationFailure("SAVE_FAILED", "The event could not be saved.")
      }
      saved = store.events.first(where: { $0.id == old.id })!
    }
    let reminderWarning = await sync()
    var data: [String: JSONValue] = [
      "event": dto(saved), "replayed": .bool(false),
      "sideEffects": .object([
        "widgetRefresh": .string("requested"),
        "reminders": .string(reminderWarning == nil ? "synchronized" : "warning"),
        "backup": .string(store.backupMessage == nil ? "recorded" : "warning"),
      ]),
    ]
    let warnings = [store.backupMessage, reminderWarning].compactMap { $0 }
    if !warnings.isEmpty { data["warnings"] = .array(warnings.map(JSONValue.string)) }
    return .object(data)
  }
  private func patched(_ old: CountdownEvent, arguments a: [String: JSONValue], creating: Bool)
    throws -> CountdownEvent
  {
    var e = old
    if let title = try string(a, "title") {
      guard title.utf8.count <= 4096 else { throw AutomationFailure.invalid("Title is too long.") }
      e.title = title
    }
    if creating || a["at"] != nil || a["date"] != nil {
      let value = try AutomationDates.parse(at: string(a, "at"), day: string(a, "date"))
      e.targetDate = value.date
      e.isAllDay = value.day != nil
      e.calendarDay = value.day
      e.annualTime = nil
    }
    if let tags = try strings(a, "tags") { e.tags = tags }
    for (key, target) in [
      ("includesStartDay", \CountdownEvent.includesStartDay),
      ("repeatYearly", \CountdownEvent.repeatYearly), ("pinned", \CountdownEvent.isPinned),
    ] {
      if let value = a[key] {
        guard let flag = value.bool else {
          throw AutomationFailure.invalid("\(key) must be boolean.")
        }
        e[keyPath: target] = flag
      }
    }
    do { return try e.validated(now: Date()) } catch {
      throw AutomationFailure.invalid("Invalid event fields: \(error.localizedDescription)")
    }
  }
  private func event(_ a: [String: JSONValue]) throws -> CountdownEvent {
    guard let raw = try string(a, "id", required: true), let id = UUID(uuidString: raw) else {
      throw AutomationFailure.invalid("id must be an event UUID.")
    }
    guard let e = store.events.first(where: { $0.id == id }) else {
      throw AutomationFailure("NOT_FOUND", "The event does not exist.")
    }
    return e
  }
  private func revision(_ e: CountdownEvent) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return JSONValue.digest(try! encoder.encode(e))
  }
  private func dto(_ e: CountdownEvent) -> JSONValue {
    var v: [String: JSONValue] = [
      "id": .string(e.id.uuidString), "revision": .string(revision(e)), "title": .string(e.title),
      "at": .string(AutomationDates.timestamp(e.targetDate)), "allDay": .bool(e.isAllDay),
      "state": .string(e.lifecycle.rawValue), "tags": .array(e.tags.map(JSONValue.string)),
      "includesStartDay": .bool(e.includesStartDay), "repeatYearly": .bool(e.repeatYearly),
      "pinned": .bool(e.isPinned),
    ]
    if let d = e.calendarDay {
      v["date"] = .string(String(format: "%04d-%02d-%02d", d.year, d.month, d.day))
    }
    return .object(v)
  }
  private func keys(_ a: [String: JSONValue], allowed: Set<String>) throws {
    guard Set(a.keys).isSubset(of: allowed) else {
      throw AutomationFailure.invalid(
        "Unknown fields: \(Set(a.keys).subtracting(allowed).sorted().joined(separator:", "))")
    }
  }
  private func string(_ a: [String: JSONValue], _ key: String, required: Bool = false) throws
    -> String?
  {
    guard let v = a[key] else {
      if required { throw AutomationFailure.invalid("Missing \(key).") }
      return nil
    }
    guard let text = v.string else { throw AutomationFailure.invalid("\(key) must be a string.") }
    return text
  }
  private func strings(_ a: [String: JSONValue], _ key: String) throws -> [String]? {
    guard let v = a[key] else { return nil }
    guard let array = v.array, array.count <= 30, array.allSatisfy({ $0.string != nil }) else {
      throw AutomationFailure.invalid("\(key) must be an array of at most 30 strings.")
    }
    return array.map { $0.string! }
  }
  private func integer(_ a: [String: JSONValue], _ key: String, default fallback: Int) throws -> Int
  {
    guard let v = a[key] else { return fallback }
    guard let n = v.integer else { throw AutomationFailure.invalid("\(key) must be an integer.") }
    return n
  }
}
