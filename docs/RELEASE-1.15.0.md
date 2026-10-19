# 日距 1.15.0（44）· CLI + JSON 与 MCP（未公证开发预览）

### 新增

- 新增 CLI + JSON 与 MCP stdio，可由本机 Agent 创建、查询、修改、归档事件，以及移入回收站或恢复。
- 设置新增“自动化”，可分别授权读取和写入；支持安装用户级命令行工具，默认不开放事件访问。

### 改进

- App 打开时通过本机私有通信处理命令，退出后可无窗口执行；沿用备份、提醒同步和小组件刷新。
- 创建支持 requestId 重试去重，修改支持 revision 冲突检查；编辑中的草稿和文件操作会阻止外部写入。

### 修复

- 确保冷启动打开指定事件后才确认成功；跨时区重试年度事件不会重复创建或错误冲突，初始化故障可明确重试。

使用：打开 **设置 → 自动化**，按需开启读取和写入。MCP 客户端可运行 `/Applications/日距.app/Contents/MacOS/DayDistance`，参数 `--cli mcp`；命令行工具可从同一设置页安装。详见[使用与配置说明](https://github.com/liaohr9/DayDistance/blob/main/docs/AUTOMATION.md)。

Apple Silicon（arm64）、macOS 14+；ad hoc 签名，尚未经过 Apple Developer ID 签名或公证。EdDSA 更新签名不等于 Apple 公证。1.13.0 及以上可在应用内“检查更新…”，更早版本下载 ZIP 手动安装。请先完成编辑并导出备份；不要关闭系统安全保护。

已知边界：仅本机使用；去重记录不随 JSON 导出迁移；极大的 MCP 响应超过 2 MiB 时会关闭连接，请减小 limit 分页后重连，明确的分页错误提示待补。此更新不新增永久删除、远程 HTTP 或终端 TUI。

验证：182 项核心测试及完整原生构建回归；真实沙盒 CLI/MCP、6 进程并发重试、草稿保护、单次命令冷启动编辑、权限撤销、中英设置和故障重试。原有事件和组件配置保持。桌面组件像素、真实通知投递、其他 Mac/macOS 14 和 Developer ID 公证仍需独立验收。

---

## English

### New

- Add a JSON CLI and MCP stdio server for local agents to create, query, edit, archive, trash and restore events.
- Add Automation settings with separate read/write access and a user-level command installer. Event access is off by default.

### Improvements

- Route commands through the running app or process them without a window when it is closed, using the existing backup, reminder and widget-refresh paths.
- Deduplicate create retries using requestId and check revisions before edits. Active drafts and file operations block external mutations.

### Fixes

- Acknowledge cold-start event opening only after the GUI accepts it; preserve yearly-event retries across time zones and allow recovery from local initialization failures.

Start in **Settings → Automation** and enable read and optional write access. Configure a stdio MCP server with command `/Applications/日距.app/Contents/MacOS/DayDistance` and args `["--cli", "mcp"]`, or install the CLI wrapper from the same settings page. See the [bilingual guide](https://github.com/liaohr9/DayDistance/blob/main/docs/AUTOMATION.md).

Apple Silicon only, macOS 14+. Ad hoc signed and **not notarized**. EdDSA update signatures are not Apple notarization. Versions 1.13.0+ can check for updates in the app; older versions need manual installation. Save edits and export a backup first. Do not disable macOS security protections.

Known limits: local Mac only; exported JSON does not carry create-retry receipts; MCP responses over 2 MiB close stdio, so reconnect with a smaller page limit. A bounded pagination error remains deferred. No permanent-deletion, HTTP or TUI interface is added.

Validation includes 182 core tests, complete native regressions, signed sandbox GUI/headless CLI and MCP clients, six-process retry deduplication, draft protection, cold-start opening, permission revocation and initialization recovery. Existing events and widget configurations were preserved. Desktop pixels, real notification delivery, other Macs/macOS 14 and Developer ID notarization retain separate acceptance boundaries.
