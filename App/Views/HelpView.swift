import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

@MainActor
struct HelpView: View {
    let store: EventStore
    @State private var report: DiagnosticReport?
    @State private var isChecking = false
    @State private var isExporting = false
    @State private var refreshMessage: String?
    @State private var exportMessage: String?

    var body: some View {
        TabView {
            page {
                WidgetSetupGuide()
                helpSection("记录一个日子", "按 ⌘N 新建事件，填写名称和日期。打开“全天”后只记录年月日，切换时区仍是同一个日子；关闭后可选择时间。选中事件按 ⌘E 编辑，⌘F 搜索。")
                helpSection("每年重复", "开启后倒计到下一个纪念日，当天整天显示当前纪念日，过日再进入下一年。原始年份保留用于周年说明；2 月 29 日在非闰年按 2 月 28 日计算。“当天算 1 天”只影响不重复事件的正计时。")
                helpSection("计日格式", "在编辑窗口的“更多选项”选择天数、周 / 天或年 / 月 / 天。周年只用于每年重复的事件。年份与月份按实际日历计算，默认仍显示天数。")
                helpSection("固定中号事件", "编辑中号小组件，开启“中号手动选择事件”，按第一、第二、第三槽位选择最多三个事件。重复选择只显示一次；归档或删除后该槽位显示不可用，不会替换为其他事件。小号仍使用原来的事件选择。")
                helpSection("快捷指令", "在系统“快捷指令”中添加日距的创建事件、查询天数或打开事件动作。查询返回非负天数，摘要区分还有与已过。创建默认不提醒；编辑或文件面板打开时，创建和打开动作会暂停并提示。")
                helpSection("复制与分享", "在事件右键菜单复制摘要，或打开“分享图片”预览。可以隐藏目标日期，再用系统面板保存 PNG。图片只保存到你选择的位置，不会自动发送。")
                helpSection("置顶与排序", "在事件右键菜单置顶，置顶事件始终排在前面。使用“显示”菜单按日期或创建时间排序，默认按日期；应用会记住选择。")
                helpSection("撤销修改", "新建、编辑、删除、置顶和导入成功后，可用 ⌘Z 撤销、⇧⌘Z 重做，历史只保留到退出应用。文本框优先撤销文字输入；编辑或文件面板打开时不执行事件撤销。其他进程修改数据后，旧历史失效。")
                helpSection("每日与纪念日提醒", "编辑事件，展开“重复提醒”，分别设置每日、每满一个月和每满一年的时间。每日显示通知当天的天数；满月与周年按原始日期计算，短月用月末，闰年恢复原日。系统队列容量有限，可在设置查看已安排日期；开启并获系统批准的后台刷新会在退出后定时补排。")
                helpSection("Vim 与多选", "事件列表中：j/k 上下，gg/G 首尾，/ 搜索，v 连续选择，Space 切换单项，Esc 结束选择，i 编辑，o 新建，dd 移到回收站，u 撤销，Ctrl-r 重做。文本输入和弹窗内不拦截。设置中可关闭 Vim 键位。")
                helpSection("多选与复制", "使用 ⌘/⇧ 多选，右键批量归档、移到回收站或恢复。⌘⇧A 归档，⌘⇧R 恢复；每次批量操作可一次撤销。⌘D 复制为新事件，先打开草稿且默认关闭提醒，取消不保存。")
                helpSection("自定义提醒", "提醒可选自定义，设置提前 0–365 天及时间。提前天数按日历计算。编辑窗口显示保存后的预计时间；设置显示通知权限及系统中已安排的下一条提醒。权限只在保存启用提醒时申请。")
                helpSection("事件提醒", "提醒默认关闭，可选当天或前一天。全天事件在上午 9 点提醒，定时事件按目标时间提醒。保存启用提醒时才请求系统权限；拒绝权限或安排失败会显示说明，事件仍会保存。年度提醒会预先安排一段时间，再次打开应用会补排。")
                helpSection("桌面小组件", "在桌面右键选择“编辑小组件”，添加日距的小号或中号组件。自动选择优先考虑置顶与最近日子，也可指定一个事件。每个组件可分别开关“显示事件图标”“显示目标日期”“显示当天精确计时”；全天事件不显示精确计时。")
                helpSection("归档与回收站", "归档让事件退出日常列表；删除先移到回收站，可以恢复。回收站不会自动清空，永久删除前需要确认，自动备份中的副本仍可能保留。")
                helpSection("本地恢复快照", "在“文件 → 备份与恢复”选择一份快照，先查看变化，再确认恢复。最多保留 20 份有效快照，仅保存在这台 Mac。")
                helpSection("菜单栏入口", "在设置中开启“显示菜单栏图标”，查看置顶及最近事件，快速打开应用或新建事件。")
                helpSection("备份与导入", "在“文件”菜单导出事件 JSON 作为备份，导入会添加未存在的事件。遇到同一事件的不同版本会保留当前数据并说明冲突。保存含新功能的数据后，旧版应用可能无法读取，请使用当前版本。")
            }
            .tabItem { Text("使用帮助") }

            page {
                if let report {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("应用版本", value: L10n.format("%@（%@）", report.applicationVersion, report.buildVersion))
                        LabeledContent("应用已载入事件", value: store.isLoaded ? L10n.format("%ld 个", store.events.count) : L10n.text("未成功载入"))
                        LabeledContent("共享数据源", value: dataSourceLabel(report))
                        LabeledContent("共享数据源事件", value: report.eventCount.map { L10n.format("%ld 个", $0) } ?? L10n.text("无法读取"))
                        LabeledContent("存储方式", value: L10n.text(report.storageMode == "local" ? "本地开发存储" : "应用共享存储"))
                        LabeledContent("小组件扩展", value: L10n.text(report.widgetExtensionEmbedded ? "应用包内已包含" : "应用包内未发现"))
                        LabeledContent("通知权限", value: authorizationLabel(report.notificationAuthorization))
                    }
                    .textSelection(.enabled)
                } else {
                    Text("正在读取状态…").foregroundStyle(.secondary)
                }
                HStack {
                    Button("重新检查") { Task { await check() } }
                        .disabled(isChecking || isExporting)
                    Button("请求刷新") {
                        WidgetCenter.shared.reloadTimelines(ofKind: "DayDistanceWidget")
                        refreshMessage = L10n.text("已向系统请求刷新；实际更新时间由 macOS 决定。")
                    }
                    .disabled(isExporting)
                    if isChecking { ProgressView().controlSize(.small) }
                }
                if let refreshMessage { Text(refreshMessage).font(.callout).foregroundStyle(.secondary) }
                helpSection("检查结果的含义", "数据源可读表示应用能读取组件使用的事件文件。扩展已包含表示安装包内有小组件。以上结果不能证明桌面组件已经正常显示；请在桌面核对实际内容。")
                helpSection("组件内容没有更新", "先重新检查并请求刷新，再在桌面确认组件选择的事件。指定事件已删除时可重新选择；自动选择会随事件和日期变化。若仍有问题，可导出诊断报告，并自行附上问题描述或截图。")
                helpSection("通知未出现", "在系统设置的“通知”中检查日距权限，以及专注模式等系统设置。允许通知后，重新保存需要提醒的事件。诊断检查不会请求或更改权限。")
            }
            .tabItem { Text("小组件检查") }

            page {
                helpSection("离线使用，本地保存", "日距不需要账号，不收集或上传事件内容，也不自动发送诊断信息。事件保存在这台 Mac 上，应用与小组件读取同一份数据。")
                helpSection("提醒由 macOS 提供", "只有保存启用了提醒的事件时，应用才请求通知权限。事件名称和提醒时间会交给这台 Mac 的通知系统，用于显示提醒；诊断检查只读取权限状态。")
                helpSection("诊断报告包含什么", "报告只包含应用和系统版本、存储方式、事件数量、读取结果的一般错误类别、通知权限、小组件扩展状态，以及减少动态效果、增强对比度、降低透明度设置。")
                helpSection("诊断报告不包含什么", "报告不包含事件名称、事件日期、事件标识、账号、凭据或完整用户路径。导出只是将 JSON 文件保存到你选择的位置，不会自动发送。你可以检查文件后自行分享。")
                helpSection("分享反馈", "导出诊断报告后，可以通过你自行选择的渠道发送给维护者，并补充遇到问题的步骤。截图可能包含事件名称和日期，分享前请自行检查。")
                Button("导出诊断报告…") { Task { await exportDiagnosticReport() } }
                    .disabled(isChecking || isExporting || store.editingEvent != nil || store.isTransferring || store.isShowingBackups || store.isHistoryModalPresented)
                if let exportMessage { Text(exportMessage).font(.callout).foregroundStyle(.secondary) }
                helpSection("事件备份", "“导出事件”会包含完整事件内容，适合备份。诊断报告只用于排查状态。请妥善保存事件备份，并自行决定是否分享。")
            }
            .tabItem { Text("隐私") }
        }
        .padding(16)
        .frame(minWidth: 600, idealWidth: 600, minHeight: 460, idealHeight: 460)
        .task { await check() }
    }

    private func page<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
    }

    private func helpSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title)).font(.headline)
            Text(L10n.text(text)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func check() async {
        guard !isChecking else { return }
        isChecking = true
        report = await WidgetDiagnostics().check()
        isChecking = false
    }

    private func exportDiagnosticReport() async {
        guard !isChecking, !isExporting, store.editingEvent == nil, !store.isTransferring, !store.isShowingBackups, !store.isHistoryModalPresented else { return }
        isExporting = true
        store.isTransferring = true
        let diagnostics = WidgetDiagnostics()
        let snapshot = await diagnostics.check()
        report = snapshot
        let panel = NSSavePanel()
        panel.title = L10n.text("导出诊断报告")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = L10n.text("日距诊断报告.json")
        panel.canCreateDirectories = true
        panel.message = L10n.text("只保存状态信息，不含事件内容。文件不会自动发送。")
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            isExporting = false
            store.isTransferring = false
            guard response == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                try diagnostics.export(snapshot, to: url)
                exportMessage = L10n.text("诊断报告已保存。请检查后自行分享。")
            } catch EventError.protectedExportDestination {
                exportMessage = L10n.text("不能覆盖事件数据或锁文件。请选择其他位置。")
            } catch {
                exportMessage = L10n.text("未能保存诊断报告。请检查所选位置的访问权限后重试。")
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    private func dataSourceLabel(_ report: DiagnosticReport) -> String {
        switch report.dataSourceState {
        case .readable: return L10n.text("可读取")
        case .notCreated: return L10n.text("尚无保存文件")
        case .unreadable:
            switch report.errorCategory {
            case "unavailableContainer": return L10n.text("无法访问共享存储")
            case "unsupportedVersion": return L10n.text("需要较新版本应用")
            case "invalidData": return L10n.text("数据无法识别")
            case "permissionDenied": return L10n.text("缺少读取权限")
            default: return L10n.text("暂时无法读取")
            }
        }
    }

    private func authorizationLabel(_ value: String) -> String {
        switch value {
        case "notDetermined": return L10n.text("尚未请求")
        case "denied": return L10n.text("未允许")
        case "authorized": return L10n.text("已允许")
        case "provisional": return L10n.text("暂时允许")
        case "ephemeral": return L10n.text("临时允许")
        default: return L10n.text("无法确定")
        }
    }
}
