import Foundation
@main struct AutomationServiceProbe {
 @MainActor static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);let repo=EventRepository(fileURL:root.appendingPathComponent("events.json"));
  if CommandLine.arguments.count>2 {
   let mode=CommandLine.arguments[2]
   let eventStore=EventStore(repository:repo)
   let engine=AutomationService(store:eventStore,permissions:{(true,true)},canUseUI:{true},sync:{nil})
   let timed=AutomationRequest(operation:"create",arguments:["title":.string("Yearly"),"at":.string("2027-03-01T00:30:00Z"),"repeatYearly":.bool(true),"requestId":.string("timezone")])
   let value=await engine.execute(timed)
   require(value.object?["ok"] == .bool(true),"timezone replay must succeed: \(value)")
   if mode=="replay" {require(value.object?["data"]?.object?["replayed"] == .bool(true),"timezone replay must reuse original UUID")}
   print("TIMEZONE_\(mode.uppercased())_PASS \(TimeZone.autoupdatingCurrent.identifier)");return
  }
  try repo.save([],replacing:[])
  let store=EventStore(repository:repo);var effects=0
  let service=AutomationService(store:store,permissions:{(true,true)},canUseUI:{true},sync:{effects+=1;return nil})
  let request=AutomationRequest(operation:"create",arguments:["title":.string("Agent test"),"date":.string("2026-11-16"),"requestId":.string("once")])
  let first=await service.execute(request);require(first.object?["ok"] == .bool(true),"creation")
  let event=first.object!["data"]!.object!["event"]!.object!;let id=event["id"]!;let rev=event["revision"]!
  require(store.events.count==1 && effects==1,"one save and effects")
  _ = await service.execute(request);require(store.events.count==1 && effects==1,"retry no duplicate or repeated effects")
  let restarted=AutomationService(store:EventStore(repository:repo),permissions:{(true,true)},canUseUI:{true},sync:{nil})
  let replay=await restarted.execute(request);require(replay.object?["data"]?.object?["replayed"] == .bool(true),"receipt survives restart")
  var changed=request;changed.arguments["title"] = .string("Different")
  require((await service.execute(changed)).object?["error"]?.object?["code"] == .string("CONFLICT"),"key reuse conflict")
  store.newEvent()
  require((await service.execute(.init(operation:"update",arguments:["id":id,"revision":rev,"title":.string("overwrite")]))).object?["error"]?.object?["code"] == .string("BUSY"),"draft protected")
  require(store.editingEvent != nil && store.events[0].title=="Agent test","draft and event preserved")
  store.editingEvent=nil
  let updated=await service.execute(.init(operation:"update",arguments:["id":id,"revision":rev,"title":.string("Updated")]))
  require(updated.object?["ok"] == .bool(true),"update with revision")
  require((await service.execute(.init(operation:"trash",arguments:["id":id,"revision":rev]))).object?["error"]?.object?["code"] == .string("CONFLICT"),"stale revision rejected")
  let disabled=AutomationService(store:store,permissions:{(false,false)},canUseUI:{true},sync:{nil})
  require((await disabled.execute(.init(operation:"list"))).object?["error"]?.object?["code"] == .string("DISABLED"),"permission gate")
  let oneShot=AutomationRequest(operation:"create",arguments:["title":.string("Once"),"at":.string("2028-01-01T12:00:00Z"),"afterDate":.string("trash"),"requestId":.string("one-shot")])
  let oneReply=await service.execute(oneShot)
  require(oneReply.object?["ok"] == .bool(true),"one-shot creation")
  require(oneReply.object?["data"]?.object?["event"]?.object?["afterDate"] == .string("trash"),"afterDate in DTO")
  require((await service.execute(oneShot)).object?["data"]?.object?["replayed"] == .bool(true),"one-shot replay")
  var keepRequest=oneShot;keepRequest.arguments["afterDate"] = .string("keep")
  require((await service.execute(keepRequest)).object?["error"]?.object?["code"] == .string("CONFLICT"),"policy differs in replay hash")
  var badAnnual=oneShot;badAnnual.arguments["requestId"] = .string("annual-once");badAnnual.arguments["repeatYearly"] = .bool(true)
  require((await service.execute(badAnnual)).object?["error"]?.object?["code"] == .string("INVALID_ARGUMENT"),"annual one-shot conflict rejected")
  print("AUTOMATION_SERVICE_PASS: create/replay/restart/conflict/draft/revision/permission")
 }
 static func require(_ value:Bool,_ message:String) { if !value {fatalError(message)} }
}
