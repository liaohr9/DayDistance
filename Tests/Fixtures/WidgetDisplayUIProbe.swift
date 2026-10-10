import SwiftUI
import WidgetKit

// Uses production widget views and disposable, in-memory events only.
@main
struct WidgetDisplayUIProbe: App {
    var body: some Scene {
        WindowGroup("日距 · 小组件显示验证") { WidgetDisplayProbeView() }
        .defaultSize(width: 960, height: 480)
    }
}

struct WidgetDisplayProbeView: View {
    @State private var options = WidgetDisplayOptions()
    @State private var inactive = false
    @State private var manual = false
    @State private var missing = false
    @State private var format = EventDisplayFormat.days
    private let now: Date
    private let events: [CountdownEvent]
    init() {
        let date = Date()
        now = date
        events = [CountdownEvent(title: "七天后出发", targetDate: date.addingTimeInterval(7 * 86400), symbol: "airplane"),
         CountdownEvent(title: "今天的纪念", targetDate: date.addingTimeInterval(-300), isAllDay: true, calendarDay: CalendarDay(date: date), repeatYearly: true, symbol: "heart"),
         CountdownEvent(title: "已经过了十天", targetDate: date.addingTimeInterval(-10 * 86400), symbol: "flag")]
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
            HStack(spacing: 16) {
                sample(family: .systemSmall, single: true, title: "小号 · 单事件")
                sample(family: .systemMedium, single: false, title: "中号 · 概览")
                sample(family: .systemMedium, single: true, title: "中号 · 单事件")
            }
        }.padding(20)
    }
    private func sample(family: WidgetFamily, single: Bool, title: String) -> some View {
        let data = events.map { event -> CountdownEvent in
            var value = event; value.displayFormat = format
            if inactive { value.lifecycle = .archived }; return value
        }
        let selection = WidgetManualSelection(enabled: manual, slotIDs: [missing ? UUID().uuidString : data[2].id.uuidString, data[0].id.uuidString, data[1].id.uuidString])
        return VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            DayWidgetContent(entry: DayEntry(date: now, events: data, explicitID: single ? data[1].id.uuidString : nil, error: nil, displayOptions: options, manualSelection: selection), family: family)
                .padding(16)
                .frame(width: family == .systemSmall ? 164 : 344, height: 164)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
