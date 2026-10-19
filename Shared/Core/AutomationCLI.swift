import Foundation

enum AutomationCLI {
  static let help = """
    DayDistance CLI — JSON API v1
    events list [--query TEXT] [--tag TAG] [--state active|archived|trashed|all] [--limit N] [--offset N]
    events get|countdown|open ID
    events create --title TEXT (--date YYYY-MM-DD | --at ISO8601) --request-id KEY
    events update ID --if-revision REV [--title TEXT] [--date DAY | --at ISO8601]
    events archive|trash|restore ID --if-revision REV
    Fields: --tag TAG (repeatable), --includes-start-day true|false, --repeat-yearly true|false, --pinned true|false
    All results are JSON. --json is accepted. --stdin reads one JSON API request.
    capabilities    Show API capabilities and local automation permission state.
    mcp             Serve MCP over stdio (newline-delimited JSON-RPC).
    Enable automation in Settings → Automation. No permanent deletion API.
    """
  static func parse(_ input: [String]) throws -> AutomationRequest {
    var args = input
    if args.first == "--json" { args.removeFirst() }
    if args == ["capabilities"] { return .init(operation: "capabilities") }
    guard args.count >= 2, args[0] == "events",
      ["list", "get", "countdown", "open", "create", "update", "archive", "trash", "restore"]
        .contains(args[1])
    else { throw AutomationFailure.invalid("Unknown command. Use --help.") }
    let op = args[1]
    var values: [String: JSONValue] = [:]
    var index = 2
    if ["get", "countdown", "open", "update", "archive", "trash", "restore"].contains(op) {
      guard index < args.count, !args[index].hasPrefix("--") else {
        throw AutomationFailure.invalid("An event UUID is required.")
      }
      values["id"] = .string(args[index])
      index += 1
    }
    let map = [
      "--title": "title", "--date": "date", "--at": "at", "--request-id": "requestId",
      "--if-revision": "revision", "--query": "query", "--state": "state", "--limit": "limit",
      "--offset": "offset", "--tag": "tags", "--includes-start-day": "includesStartDay",
      "--repeat-yearly": "repeatYearly", "--pinned": "pinned",
    ]
    while index < args.count {
      if args[index] == "--json" {
        index += 1
        continue
      }
      guard let key = map[args[index]], index + 1 < args.count else {
        throw AutomationFailure.invalid("Unknown option or missing value: \(args[index])")
      }
      let value = args[index + 1]
      index += 2
      if key == "tags" {
        values[key] = .array((values[key]?.array ?? []) + [.string(value)])
        continue
      }
      guard values[key] == nil else { throw AutomationFailure.invalid("Repeated option: \(key)") }
      if ["limit", "offset"].contains(key) {
        guard let number = Int32(value) else {
          throw AutomationFailure.invalid("\(key) must be an integer.")
        }
        values[key] = .number(Double(number))
      } else if ["includesStartDay", "repeatYearly", "pinned"].contains(key) {
        guard ["true", "false"].contains(value) else {
          throw AutomationFailure.invalid("\(key) must be true or false.")
        }
        values[key] = .bool(value == "true")
      } else {
        values[key] = .string(value)
      }
    }
    return .init(operation: op, arguments: values)
  }
}
