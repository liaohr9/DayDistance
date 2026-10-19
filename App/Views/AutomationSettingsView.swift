import AppKit
import Darwin
import SwiftUI

struct AutomationSettingsView: View {
  @AppStorage("automationReadEnabled") private var readEnabled = false
  @AppStorage("automationWriteEnabled") private var writeEnabled = false
  @State private var message: String?
  var body: some View {
    Section {
      Toggle(L10n.text("允许本机 Agent 读取事件"), isOn: $readEnabled)
        .onChange(of: readEnabled) { if !readEnabled { writeEnabled = false } }
      Toggle(L10n.text("允许创建和修改事件"), isOn: $writeEnabled).disabled(!readEnabled)
      Text(L10n.text("仅限当前 Mac 用户。关闭读取后，命令行和 MCP 均不能访问事件；不会开放网络端口。")).font(.caption)
        .foregroundStyle(.secondary)
    } header: {
      Text(L10n.text("访问权限"))
    }
    Section {
      Button(L10n.text("安装命令行工具…")) { install() }
      Text(L10n.text("选择保存位置，例如 ~/.local/bin/daydistance。请将该文件夹加入 PATH，或使用完整路径运行。无需管理员权限。")).font(
        .caption
      ).foregroundStyle(.secondary)
      Text("daydistance --help\ndaydistance events list\ndaydistance mcp").font(
        .system(.caption, design: .monospaced)
      ).textSelection(.enabled)
      if let message { Text(message).font(.caption).textSelection(.enabled) }
    } header: {
      Text(L10n.text("命令行与 MCP"))
    }
  }
  private func install() {
    let panel = NSSavePanel()
    panel.title = L10n.text("安装命令行工具…")
    panel.nameFieldStringValue = "daydistance"
    panel.canCreateDirectories = true
    if let home = getpwuid(getuid())?.pointee.pw_dir {
      panel.directoryURL = URL(fileURLWithPath: String(cString: home)).appendingPathComponent(
        ".local/bin")
    }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try AutomationInstaller.install(at: url, app: Bundle.main.bundleURL)
      message = L10n.format("已安装：%@", url.path)
    } catch { message = L10n.text("安装失败。请选择可写的位置，且不要覆盖其他文件。") }
  }
}

enum AutomationInstaller {
  static let marker = "# DayDistance managed CLI v1"
  static func script(app: URL) -> String {
    let executable = app.appendingPathComponent("Contents/MacOS/DayDistance").path
    let quoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
    return "#!/bin/sh\n\(marker)\nexec \(quoted) --cli \"$@\"\n"
  }
  static func install(at url: URL, app: URL) throws {
    let fm = FileManager.default
    let attributes = try? fm.attributesOfItem(atPath: url.path)
    if let attributes {
      guard attributes[.type] as? FileAttributeType == .typeRegular,
        let old = try? String(contentsOf: url, encoding: .utf8),
        old.hasPrefix("#!/bin/sh\n" + marker + "\n")
      else { throw CocoaError(.fileWriteFileExists) }
    }
    try Data(script(app: app).utf8).write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }
}
