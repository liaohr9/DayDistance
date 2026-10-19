import XCTest

#if SWIFT_PACKAGE
  @testable import DayDistanceCore
#endif
final class AutomationMCPTests: XCTestCase {
  func testHandshakeToolsAndErrors() async throws {
    let mcp = AutomationMCP { request in
      .object(["ok": .bool(request.operation != "trash"), "operation": .string(request.operation)])
    }
    func rpc(_ method: String, _ params: [String: JSONValue] = [:]) -> JSONValue {
      .object([
        "jsonrpc": .string("2.0"), "id": .number(1), "method": .string(method),
        "params": .object(params),
      ])
    }
    let early = await mcp.respond(rpc("tools/list"))
    XCTAssertNotNil(early?.object?["error"])
    let hello = await mcp.respond(
      rpc(
        "initialize",
        [
          "protocolVersion": .string("2025-11-25"), "capabilities": .object([:]),
          "clientInfo": .object(["name": .string("test"), "version": .string("1")]),
        ]))
    XCTAssertEqual(hello?.object?["result"]?.object?["protocolVersion"], .string("2025-11-25"))
    let tools = await mcp.respond(rpc("tools/list"))
    XCTAssertEqual(tools?.object?["result"]?.object?["tools"]?.array?.count, 10)
    let call = await mcp.respond(
      rpc("tools/call", ["name": .string("daydistance_list"), "arguments": .object([:])]))
    XCTAssertEqual(
      call?.object?["result"]?.object?["structuredContent"]?.object?["operation"], .string("list"))
    XCTAssertEqual(call?.object?["result"]?.object?["isError"], .bool(false))
    let fail = await mcp.respond(
      rpc("tools/call", ["name": .string("daydistance_trash"), "arguments": .object([:])]))
    XCTAssertEqual(fail?.object?["result"]?.object?["isError"], .bool(true))
    let invalid = await mcp.respond(rpc("tools/call", ["name": .string("other")]))
    XCTAssertEqual(invalid?.object?["error"]?.object?["code"], .number(-32602))
    let note = await mcp.respond(
      .object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]))
    XCTAssertNil(note)
  }
}
