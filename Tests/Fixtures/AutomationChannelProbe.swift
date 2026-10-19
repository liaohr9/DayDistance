import Foundation
@main struct AutomationChannelProbe {
 static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("ipc")
  var lease=try AutomationLease.acquire(in:root)
  precondition(lease != nil)
  let second=try AutomationLease.acquire(in:root);precondition(second==nil)
  var server:AutomationSocketServer?=try AutomationSocketServer(directory:root) { request in .object(["operation":.string(request.operation)]) }
  let response=try await Task.detached {try AutomationChannel.request(.init(operation:"capabilities"),directory:root)}.value
  precondition(response?.object?["operation"] == .string("capabilities"))
  server=nil;lease=nil
  let next=try AutomationLease.acquire(in:root);precondition(next != nil)
  _ = server
  print("AUTOMATION_CHANNEL_PASS: lease/socket/response/release")
 }
}
