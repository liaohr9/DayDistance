import SwiftUI

struct WidgetSetupGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加桌面小组件").font(.headline)
            HStack(alignment: .top, spacing: 20) {
                step("1", "desktopcomputer", "桌面右键", "选择“编辑小组件”。")
                step("2", "square.grid.2x2", "找到日距", "选择小号、中号或大号，拖到桌面。")
                step("3", "slider.horizontal.3", "选择事件", "右键小组件，选择“编辑日距”。")
            }
            Text(L10n.text("在日距侧栏创建智能列表，再在小组件的“内容来源”中选择“智能列表”。规则可由多个小组件共用。"))
                .font(.caption).foregroundStyle(.secondary)
            Text("小号显示一个日子；中号概览最多三条；大号每页五至十条，可按按钮翻页。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
    private func step(_ number: String, _ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(number, systemImage: symbol).font(.title3).accessibilityHidden(true)
            Text(L10n.text(title)).font(.subheadline.weight(.medium))
            Text(L10n.text(detail)).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
