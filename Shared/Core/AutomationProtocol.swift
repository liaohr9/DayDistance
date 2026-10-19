import CryptoKit
import Foundation

enum JSONValue: Codable, Equatable, Sendable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let value = try? c.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? c.decode(String.self) {
      self = .string(value)
    } else if let value = try? c.decode(Double.self) {
      self = .number(value)
    } else if let value = try? c.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      self = .array(try c.decode([JSONValue].self))
    }
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
  var string: String? { if case .string(let v) = self { v } else { nil } }
  var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
  var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
  var integer: Int? {
    guard case .number(let v) = self, v.isFinite, v.rounded() == v, v >= Double(Int32.min),
      v <= Double(Int32.max)
    else { return nil }
    return Int(v)
  }
  func encoded() throws -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try e.encode(self)
  }
  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
struct AutomationFailure: Error {
  let code: String
  let message: String
  init(_ code: String, _ message: String) {
    self.code = code
    self.message = message
  }
  var response: JSONValue {
    .object([
      "apiVersion": .number(1), "ok": .bool(false),
      "error": .object(["code": .string(code), "message": .string(message)]),
    ])
  }
  static func invalid(_ message: String) -> Self { .init("INVALID_ARGUMENT", message) }
}
struct AutomationRequest: Codable, Sendable {
  var apiVersion = 1
  let operation: String
  var arguments: [String: JSONValue]
  init(operation: String, arguments: [String: JSONValue] = [:]) {
    self.operation = operation
    self.arguments = arguments
  }
}
struct AutomationReceipt: Codable, Equatable, Sendable {
  let payloadHash: String
  let eventID: UUID
}
struct AutomationDates {
  static func parse(at: String?, day: String?) throws -> (date: Date, day: CalendarDay?) {
    guard (at != nil) != (day != nil) else {
      throw AutomationFailure.invalid("Provide exactly one of at or date.")
    }
    if let day {
      guard day.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
        throw AutomationFailure.invalid("date must be YYYY-MM-DD.")
      }
      let parts = day.split(separator: "-").compactMap { Int($0) }
      let value = CalendarDay(year: parts[0], month: parts[1], day: parts[2])
      guard let date = value.date(timeZone: .autoupdatingCurrent) else {
        throw AutomationFailure.invalid("Invalid calendar date.")
      }
      return (date, value)
    }
    let text = at!
    guard
      text.range(
        of:
          "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,3})?(Z|[+-][0-9]{2}:[0-9]{2})$",
        options: .regularExpression) != nil
    else {
      throw AutomationFailure.invalid(
        "at must be ISO 8601 with seconds and an explicit time-zone offset.")
    }
    let f = ISO8601DateFormatter()
    f.formatOptions =
      text.contains(".")
      ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
    let datePart = String(text.prefix(10))
    _ = try parse(at: nil, day: datePart)
    let clock = String(text.dropFirst(11).prefix(8)).split(separator: ":").compactMap { Int($0) }
    if !text.hasSuffix("Z") {
      let offset = text.suffix(5).split(separator: ":").compactMap { Int($0) }
      guard offset.count == 2, offset[0] < 24, offset[1] < 60 else {
        throw AutomationFailure.invalid("Invalid time-zone offset.")
      }
    }
    guard clock[0] < 24, clock[1] < 60, clock[2] < 60, let date = f.date(from: text) else {
      throw AutomationFailure.invalid("Invalid timestamp.")
    }
    return (date, nil)
  }
  static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
