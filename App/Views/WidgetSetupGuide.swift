import SwiftUI

struct WidgetSetupGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加桌面小组件").font(.headline)
            HStack(alignment: .top, spacing: 20) {
                step("1", "desktopcomputer", "桌面右键", "选择“编辑小组件”。")
                step("2", "square.grid.2x2", "找到日距", "选择小号或中号，拖到桌面。")
                step("3", "slider.horizontal.3", "选择事件", "右键小组件，选择“编辑日距”。")
            }
            Text("小号显示一个日子；中号可自动概览，或按顺序固定最多三个事件。")
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
