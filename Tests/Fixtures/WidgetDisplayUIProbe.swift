import SwiftUI
import WidgetKit

// Uses production widget views and disposable, in-memory events only.
@main
struct WidgetDisplayUIProbe: App {
    var body: some Scene {
        WindowGroup("日距 · 小组件显示验证") { WidgetDisplayProbeView() }
        .defaultSize(width: 1080, height: 640)
    }
}

struct WidgetDisplayProbeView: View {
    @State private var options = WidgetDisplayOptions()
    @State private var inactive = false
    @State private var manual = false
    @State private var missing = false
    @State private var largeRows = 6
    @State private var eventCount = 2
    @State private var pageIndex = 0
    @State private var filtered = false
    @State private var format = EventDisplayFormat.days
    private let now: Date
    private let events: [CountdownEvent]
    init() {
        let date = Date()
        now = date
        events = [CountdownEvent(title: "七天后出发", targetDate: date.addingTimeInterval(7 * 86400), symbol: "airplane"),
         CountdownEvent(title: "今天的纪念", targetDate: date.addingTimeInterval(-300), isAllDay: true, calendarDay: CalendarDay(date: date), repeatYearly: true, symbol: "heart"),
         CountdownEvent(title: "已经过了十天", targetDate: date.addingTimeInterval(-10 * 86400), symbol: "flag")] + (4...15).map { index in
            CountdownEvent(title: "期待 \(index)", targetDate: date.addingTimeInterval(Double(index) * 86400), symbol: "flag", colorKey: index.isMultiple(of: 2) ? "blue" : "rose", tags: index.isMultiple(of: 2) ? ["工作"] : ["生活"])
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications/日距.app"))
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading) {
                    Text("已安装图标与生产小组件视图").font(.headline)
                    Text("临时事件，不读取或保存用户数据").foregroundStyle(.secondary)
                }
            }
            HStack {
                Toggle("显示事件图标", isOn: $options.showIcon)
                Toggle("显示目标日期", isOn: $options.showTargetDate)
                Toggle("显示当天精确计时", isOn: $options.showClock)
                Toggle("仅归档事件（空状态）", isOn: $inactive)
            }.toggleStyle(.checkbox)
            HStack {
                Toggle("中号手动：第三、第一、第二", isOn: $manual)
                Toggle("第一槽位不可用", isOn: $missing)
                Picker("计日格式", selection: $format) {
                    ForEach(EventDisplayFormat.allCases, id: \.self) { Text($0.label).tag($0) }
                }.frame(width: 250)
            }.toggleStyle(.checkbox)
            HStack {
                Stepper("测试事件：\(eventCount) 条", value: $eventCount, in: 1...15).frame(width: 170)
                Picker("大号每页条数", selection: $largeRows) { ForEach(5...10, id: \.self) { Text("\($0)").tag($0) } }.frame(width: 190)
                Picker("预览页面", selection: $pageIndex) { ForEach(0..<3, id: \.self) { Text("\($0 + 1)").tag($0) } }.frame(width: 170)
                Toggle("工作标签、按距离、跳过第一条", isOn: $filtered)
            }
            HStack(alignment: .top, spacing: 16) {
                sample(family: .systemLarge, single: false, title: "大号 · 自动筛选与分页")
                VStack(spacing: 16) {
                    sample(family: .systemMedium, single: false, title: "中号 · 同一筛选")
                    sample(family: .systemMedium, single: true, title: "中号 · 指定事件不受自动筛选影响")
                }
                sample(family: .systemSmall, single: true, title: "小号 · 单事件")
            }
        }.padding(20)
    }
    private func sample(family: WidgetFamily, single: Bool, title: String) -> some View {
        let data = events.prefix(eventCount).map { event -> CountdownEvent in
            var value = event; value.displayFormat = format
            if inactive { value.lifecycle = .archived }; return value
        }
        let selection = WidgetManualSelection(enabled: manual, slotIDs: [missing ? UUID().uuidString : events[2].id.uuidString, events[0].id.uuidString, events[1].id.uuidString])
        return VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            DayWidgetContent(entry: DayEntry(date: now, events: data, explicitID: single ? data[min(1, data.count - 1)].id.uuidString : nil, error: nil, displayOptions: options, manualSelection: selection, filter: filtered ? WidgetFilter(scope: .upcoming, includedTags: ["工作"], sort: .nearest, prioritizePinned: false, skip: 1) : WidgetFilter(), pageSize: largeRows, pagingID: "11111111-1111-1111-1111-111111111111", pageIndex: pageIndex), family: family)
                .padding(16)
                .frame(width: family == .systemSmall ? 164 : 344, height: family == .systemLarge ? 344 : 164)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
