import SwiftUI
import WidgetKit

// Public illustration: production WidgetKit content with fictional in-memory events.
// This is a native showcase window, not a desktop-widget integration test.
@main struct WidgetShowcase: App {
    var body: some Scene {
        Window("日距 · 小组件", id: "showcase") { ShowcaseView().preferredColorScheme(.light) }
            .defaultSize(width: 880, height: 480)
    }
}
struct ShowcaseView: View {
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
    var events: [CountdownEvent] {
        let day = { (y: Int, m: Int, d: Int) in Calendar.current.date(from: DateComponents(year:y, month:m, day:d, hour:9))! }
        return [CountdownEvent(id:UUID(uuidString:"00000000-0000-0000-0000-000000000001")!, title:"京都之旅", targetDate:day(2026,11,8), isAllDay:true, calendarDay:CalendarDay(date:day(2026,11,8)), symbol:"airplane", colorKey:"amber"),
                CountdownEvent(id:UUID(uuidString:"00000000-0000-0000-0000-000000000002")!, title:"第一场马拉松", targetDate:day(2026,11,15), isAllDay:true, calendarDay:CalendarDay(date:day(2026,11,15)), symbol:"flag", colorKey:"sage"),
                CountdownEvent(id:UUID(uuidString:"00000000-0000-0000-0000-000000000003")!, title:"开始学习钢琴", targetDate:day(2024,5,20), isAllDay:true, calendarDay:CalendarDay(date:day(2024,5,20)), symbol:"sun.max", colorKey:"blue")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing:24) {
            HStack {
                Text("小组件，让时间一眼可见。").font(.system(size:24, weight:.semibold))
                Spacer()
                Text("日距").font(.system(size:15, weight:.medium)).foregroundStyle(.secondary)
            }
            HStack(alignment:.top, spacing:24) {
                card(.systemSmall, single:true, dark:false, label:"小号 · 一个重要日子")
                card(.systemMedium, single:false, dark:false, label:"中号 · 最多三个事件")
                card(.systemSmall, single:true, dark:true, label:"深色外观")
            }
            HStack {
                Image(systemName:"slider.horizontal.3")
                Text("选择事件、调整顺序，自定义图标与日期显示。").font(.system(size:14))
            }.foregroundStyle(.secondary)
        }.padding(32).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(Color(red:0.96,green:0.95,blue:0.93))
    }
    func card(_ family: WidgetFamily, single:Bool, dark:Bool, label:String) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text(label).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)
            DayWidgetContent(entry: DayEntry(date:now,events:events,explicitID:single ? events[0].id.uuidString:nil,error:nil),family:family)
                .padding(18).frame(width:family == .systemSmall ? 170:350,height:178)
                .background(dark ? Color(red:0.14,green:0.14,blue:0.15):.white,in:RoundedRectangle(cornerRadius:24))
                .environment(\.colorScheme,dark ? .dark:.light)
                .shadow(color:.black.opacity(0.06),radius:14,x:0,y:5)
        }
    }
}
