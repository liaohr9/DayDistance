import XCTest
@testable import DayDistanceCore
final class RefreshAndPreviewTests:XCTestCase {
 let zone=TimeZone(identifier:"America/Los_Angeles")!
 func date(_ s:String)->Date {ISO8601DateFormatter().date(from:s)!}
 func testDistantDayOnlyEventsDoNotTickEverySecond() {
  let now=date("2026-10-18T12:00:00Z")
  let event=CountdownEvent(title:"Distant",targetDate:now.addingTimeInterval(10*86400))
  XCTAssertEqual(EventRefreshPolicy.nextUpdate(events:[event],after:now,includeClock:true,timeZone:zone),date("2026-10-19T07:00:00Z"))
 }
 func testClockStartsAt24HourBoundaryAndTicksOnlyWhenNeeded() {
  let now=date("2026-10-18T12:00:00Z")
  let event=CountdownEvent(title:"Clock",targetDate:now.addingTimeInterval(86410))
  XCTAssertEqual(EventRefreshPolicy.nextUpdate(events:[event],after:now,includeClock:true,timeZone:zone),now.addingTimeInterval(11))
  let ticking=now.addingTimeInterval(11.2)
  XCTAssertEqual(EventRefreshPolicy.nextUpdate(events:[event],after:ticking,includeClock:true,timeZone:zone),now.addingTimeInterval(12))
 }
 func testSummaryRefreshesAtExactTargetEvenWithoutClocks() {
  let now=date("2026-10-18T12:00:00Z")
  let event=CountdownEvent(title:"Target",targetDate:now.addingTimeInterval(10.5))
  XCTAssertEqual(EventRefreshPolicy.nextUpdate(events:[event],after:now,includeClock:false,timeZone:zone),event.targetDate)
 }
 func testAllDayAndAnnualPastDoNotCreateSecondTimers() {
  let now=date("2026-10-18T12:00:00Z")
  var allDay=CountdownEvent(title:"All day",targetDate:now.addingTimeInterval(10),isAllDay:true)
  XCTAssertGreaterThan(EventRefreshPolicy.nextUpdate(events:[allDay],after:now,includeClock:true,timeZone:zone).timeIntervalSince(now),3600)
  allDay.isAllDay=false;allDay.repeatYearly=true;allDay.targetDate=now.addingTimeInterval(-10)
  XCTAssertGreaterThan(EventRefreshPolicy.nextUpdate(events:[allDay],after:now,includeClock:true,timeZone:zone).timeIntervalSince(now),3600)
 }
 func testMidnightScheduleUsesCalendarDuringDST() {
  let now=date("2026-11-01T07:00:00Z")
  XCTAssertEqual(EventRefreshPolicy.nextUpdate(events:[],after:now,includeClock:false,timeZone:zone),date("2026-11-02T08:00:00Z"))
 }
 func testAnnualPreviewSearchesPastTwoExpired365DayCandidates() {
  let now=date("2026-10-18T12:00:00Z")
  var event=CountdownEvent(title:"Annual",targetDate:date("2024-10-18T09:00:00Z"),repeatYearly:true,reminder:.custom)
  event.reminderTime=CalendarTime(hour:9,minute:0);event.reminderDaysBefore=365
  let utc=TimeZone(secondsFromGMT:0)!
  let expected=ReminderPolicy.plan(events:[event],now:now,timeZone:utc).requests.first?.fireDate
  XCTAssertNotNil(expected)
  XCTAssertEqual(ReminderPolicy.nextDate(event:event,now:now,timeZone:utc),expected)
 }
 func testPreviewAgreesWithFullQueueAcrossCadencesAndCalendarBoundaries() {
  for zoneID in ["UTC","Asia/Shanghai","America/Los_Angeles"] {
   let zone=TimeZone(identifier:zoneID)!
   for nowText in ["2026-01-31T20:00:00Z","2026-02-28T20:00:00Z","2028-02-29T20:00:00Z","2026-11-01T08:30:00Z"] {
    let now=date(nowText)
    for target in ["2024-02-29T08:00:00Z","2026-01-31T08:00:00Z","2030-06-10T08:00:00Z"] {
     for mask in 0..<16 {
      var e=CountdownEvent(title:"Preview",targetDate:date(target),repeatYearly:mask%2==0,reminder:mask&1==0 ? .custom:.none)
      e.reminderTime=CalendarTime(hour:9,minute:0);e.reminderDaysBefore=5
      if mask&2 != 0 {e.dailyReminderTime=CalendarTime(hour:9,minute:0)}
      if mask&4 != 0 {e.monthlyReminderTime=CalendarTime(hour:10,minute:0)}
      if mask&8 != 0 {e.yearlyReminderTime=CalendarTime(hour:11,minute:0)}
      XCTAssertEqual(ReminderPolicy.nextDate(event:e,now:now,timeZone:zone),ReminderPolicy.plan(events:[e],now:now,timeZone:zone).requests.first?.fireDate,"\(zoneID) \(nowText) \(target) \(mask)")
     }
    }
   }
  }
 }
}
