import Foundation

/// MCP stdio adapter. All event rules and permission checks stay in AutomationService.
actor AutomationMCP {
  private var initialized = false
  private let execute: @Sendable (AutomationRequest) async -> JSONValue
  init(execute: @escaping @Sendable (AutomationRequest) async -> JSONValue) {
    self.execute = execute
  }
  func respond(_ message: JSONValue) async -> JSONValue? {
    guard let o = message.object, o["jsonrpc"] == .string("2.0"), let method = o["method"]?.string
    else { return error(.null, -32600, "Invalid JSON-RPC request.") }
    let id = o["id"]
    if let id, id != .null, id.string == nil, case .number = id {
    } else if let id, id != .null, id.string == nil {
      return error(.null, -32600, "Invalid request id.")
    }
    guard let id else { return nil }  // Notifications never produce stdout responses.
    let params = o["params"]?.object ?? [:]
    if o["params"] != nil && o["params"]?.object == nil {
      return error(id, -32602, "params must be an object.")
    }
    if method == "initialize" {
      guard !initialized, let version = params["protocolVersion"]?.string,
        params["clientInfo"]?.object != nil, params["capabilities"]?.object != nil
      else {
        return error(
          id, -32602, "Expected protocolVersion, capabilities and clientInfo; initialize once.")
      }
      initialized = true
      return result(
        id,
        .object([
          "protocolVersion": .string(
            ["2025-11-25", "2025-06-18", "2024-11-05"].contains(version) ? version : "2025-11-25"),
          "capabilities": .object(["tools": .object([:])]),
          "serverInfo": .object(["name": .string("DayDistance"), "version": .string("1.0.0")]),
          "instructions": .string(
            "Local event management. Enable read/write in DayDistance Settings → Automation. Read the current revision before editing. Reuse a create requestId only for an identical retry. No permanent deletion."
          ),
        ]))
    }
    guard initialized else { return error(id, -32002, "Initialize the server first.") }
    switch method {
    case "ping": return result(id, .object([:]))
    case "tools/list": return result(id, .object(["tools": .array(Self.tools)]))
    case "tools/call":
      guard let name = params["name"]?.string, let operation = Self.names[name],
        params["arguments"] == nil || params["arguments"]?.object != nil
      else { return error(id, -32602, "Unknown tool or invalid arguments.") }
      let response = await execute(
        .init(operation: operation, arguments: params["arguments"]?.object ?? [:]))
      let text = String(data: (try? response.encoded()) ?? Data(), encoding: .utf8) ?? "{}"
      return result(
        id,
        .object([
          "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
          "structuredContent": response, "isError": .bool(response.object?["ok"] != .bool(true)),
        ]))
    default: return error(id, -32601, "Method not found.")
    }
  }
  static func parseError() -> JSONValue {
    .object([
      "jsonrpc": .string("2.0"), "id": .null,
      "error": .object(["code": .number(-32700), "message": .string("Invalid JSON.")]),
    ])
  }
  private func result(_ id: JSONValue, _ value: JSONValue) -> JSONValue {
    .object(["jsonrpc": .string("2.0"), "id": id, "result": value])
  }
  private func error(_ id: JSONValue, _ code: Int, _ message: String) -> JSONValue {
    .object([
      "jsonrpc": .string("2.0"), "id": id,
      "error": .object(["code": .number(Double(code)), "message": .string(message)]),
    ])
  }
  static let operations = [
    "capabilities", "list", "get", "countdown", "create", "update", "archive", "trash", "restore",
    "open",
  ]
  static let names = Dictionary(uniqueKeysWithValues: operations.map { ("daydistance_" + $0, $0) })
  static var tools: [JSONValue] {
    let string: JSONValue = .object(["type": .string("string")])
    let bool: JSONValue = .object(["type": .string("boolean")])
    let eventFields: [String: JSONValue] = [
      "title": string,
      "at": .object([
        "type": .string("string"),
        "description": .string("ISO 8601 with seconds and an explicit time-zone offset."),
      ]),
      "date": .object([
        "type": .string("string"),
        "description": .string("All-day YYYY-MM-DD; mutually exclusive with at."),
      ]), "tags": .object(["type": .string("array"), "items": string, "maxItems": .number(30)]),
      "includesStartDay": bool, "repeatYearly": bool, "pinned": bool,
      "afterDate": .object(["type": .string("string"), "enum": .array([.string("keep"), .string("trash")]),
        "description": .string("Keep original date and count elapsed days (default), or move a nonrepeating event to recoverable Trash after expiry.")]),
    ]
    return operations.map { op in
      var fields: [String: JSONValue] = [:]
      var required = [String]()
      switch op {
      case "list":
        fields = [
          "query": string, "tags": .object(["type": .string("array"), "items": string]),
          "state": .object([
            "type": .string("string"),
            "enum": .array(["active", "archived", "trashed", "all"].map(JSONValue.string)),
          ]),
          "limit": .object([
            "type": .string("integer"), "minimum": .number(1), "maximum": .number(200),
          ]), "offset": .object(["type": .string("integer"), "minimum": .number(0)]),
        ]
      case "create":
        fields = eventFields
        fields["requestId"] = string
        required = ["title", "requestId"]
      case "update":
        fields = eventFields
        fields["id"] = string
        fields["revision"] = string
        required = ["id", "revision"]
      case "archive", "trash", "restore":
        fields = ["id": string, "revision": string]
        required = ["id", "revision"]
      case "get", "countdown", "open":
        fields = ["id": string]
        required = ["id"]
      default: break
      }
      let descriptions = [
        "capabilities": "Check local API access. Does not expose events.",
        "list": "List saved events with pagination. All tags must match.",
        "get": "Read an event and its current revision.",
        "countdown": "Calculate the current calendar-day distance.",
        "create": "Create one event. Require at or date. requestId deduplicates identical retries.",
        "update": "Edit supplied fields only; revision must match the current event.",
        "archive": "Archive an event; revision required.",
        "trash": "Move to recoverable Trash; revision required. Never permanently deletes.",
        "restore": "Restore an archived or trashed event; revision required.",
        "open": "Explicitly open an active event in the app; may bring the app forward.",
      ]
      let read = ["capabilities", "list", "get", "countdown"].contains(op)
      return .object([
        "name": .string("daydistance_" + op), "description": .string(descriptions[op]!),
        "inputSchema": .object([
          "type": .string("object"), "properties": .object(fields),
          "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false),
        ]),
        "annotations": .object([
          "readOnlyHint": .bool(read),
          "destructiveHint": .bool(!read && op != "create" && op != "open"),
          "openWorldHint": .bool(false),
        ]),
      ])
    }
  }
}
