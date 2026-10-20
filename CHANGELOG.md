# Changelog

## 1.17.0 — date recurrence, lists and original-date memories

- Add daily/monthly date recurrence; clamp shorter months and restore the anchor day.
- Separate recurrence and tags into native editor groups; expose repeatDaily/repeatMonthly to CLI/MCP.

- Add regular lists and nested folders, with a single sidebar creation menu and one-list event membership.
- Add a Display-page after-date action: preserve the original date or move one-time events to recoverable Trash. Nonannual memories may use anniversary formatting.
- Show Remaining HH:mm for today’s upcoming timed widget events, retaining existing display options.
- Fix normal GUI opening while an MCP listener is running; reconnect older listeners after updating.
- Stop reminders beyond one-time expiry; preserve drafts and backups, disarm cleanup on recovery, and support afterDate in CLI/JSON/MCP.
- Read legacy data; new event/list schemas protect against unsafe older writers. This remains an unnotarized Apple Silicon preview.

## 1.15.0 — local agent automation

- Add a JSON CLI and ten MCP tools in the native app, with default-off read/write access.
- Coordinate running and headless commands through one event store, retaining backup, reminder and widget refresh paths.
- Protect drafts/revisions and create retries; handle cold opening and initialization recovery.
- See [release details and known limits](docs/RELEASE-1.15.0.md) and [the CLI/MCP guide](docs/AUTOMATION.md).

## 1.14.0 — widget recovery and release history

- Add offline Chinese/English Release Notes under Settings → Software Update, covering current changes and previous public versions.
- Generate localized update-prompt descriptions from the same catalog and sign the entire feed after embedding them.


- Request registration for the bundled widget once after installing, replacing or updating the app.
- Add Settings → Widgets → Refresh & Repair Widgets, with localized results and a bounded background operation.
- Validate the bundled extension before registration; preserve events and widget configurations.
- Keep registration-request status separate from widget rendering in diagnostics. No system database resets or global widget-process restarts.

## 1.13.1 — language resource compatibility

- Resolve the actual en/zh-Hans resource directories regardless of preferred localization or directory casing.
- Cover lowercase zh-hans.lproj resources, fixing two failures exposed by GitHub-hosted macOS CI.
- Precompute event-row text outside the SwiftUI builder to avoid an older compiler type-check timeout; displayed and spoken text stay the same.

## 1.13.0 — in-app updates

- Add Settings → Software Update and a manual Check for Updates command.
- Check the GitHub-hosted signed feed daily, with an optional automatic-check switch.
- Ask before download/install; validate feed and archive signatures, install and relaunch through Sparkle2.10.0.
- Protect event/rule drafts and file operations; keep the app, widget and updater helpers arm64 only.
- Publish signed update artifacts separately; preview builds remain unnotarized.

## 1.12.1 source — Apply language immediately

- Choosing Chinese or English now refreshes open windows, event and Smart List sheets, Help, menu bar content and app commands without restarting.
- Preserve editor identity, unsaved fields, date/time and text undo. Refresh the stable native sort menu labels without rebuilding its items while tracking.
- Publish the chosen language immediately, request widget timelines and refresh localized reminder scheduling. Failed language storage keeps the current preference and interface together.
- Native application/window/clipboard commands retain responder-chain actions and shortcuts, with one Settings entry and localized labels.
- 175 core tests and native regression checks pass; actual UI verification uses disposable drafts and the installed sandboxed app. System-provided services and widget configuration hosts remain controlled by macOS. No new public binary release.

## 1.12.0 source — App language

- Choose Simplified Chinese or English in General settings; native menus, windows and forms switch at the next normal launch. No Follow System option.
- Widgets and background reminders read the last applied language rather than a pending choice. User content and regional date/time conventions are preserved.
- Reorder widget configuration fields and preserve legacy appearance switches with an explicit Custom default. All 20 parameter identifiers/types remain compatible.
- 172 core tests, native regression suite and arm64 builds pass. Real installed-app language switching verified; system-hosted widget configuration and desktop language pixels remain separate checks. No new public binary release.

## 1.11.0 source — Smart Lists

- Photos-style named rule lists with all/any matching, live counts, sort/pinning/skip, sidebar navigation, duplicate and confirmed delete.
- Widgets choose reusable lists and Standard / Compact / Custom appearance. All 17 legacy parameter identifiers and existing selections remain intact.
- Independent CAS storage and 20 rule snapshots. Explicit recovery quarantines damaged bytes, checks confirmation fingerprints, and refuses newer schema versions.
- Time-sensitive selection/cursor reconciliation and absolute-distance midpoint refresh. Event data schema remains unchanged.
- No new public binary release; Developer ID signing, notarization, and real desktop Smart List acceptance remain separate gates.

## 1.10.0 source — settings redesign

- Build 33: event-boundary list refresh, row-only clocks, precomputed sort dates and lightweight next-reminder previews. Reuse identical pending notifications and move reminder planning/reads off the main actor.
- Simpler editor: More Options reveals existing tags/yearly rules; one color menu keeps swatches and the system wheel. Help is grouped by topic, with widget checks centralized in Settings.
- Correct annual custom previews when a 365-day advance passes two expired candidates. Local preview builds now use optimized compilation; Debug remains unoptimized.

- App Settings: four native sidebar categories, remembered selection, shared data and widget-check entry points. A compact single-row title bar keeps native window controls and removes the redundant sidebar button.
- Event editor: Basics / Reminder / Display with one draft and fixed actions.
- Widget configuration: conditional controls by size and mode; advanced and legacy active filters stay editable. Existing identifiers and values are preserved.
- Adds isolated settings routing/modal guards and a check of Xcode-extracted widget summary metadata.
- No new public binary release. Developer ID signing and notarization remain separate release requirements.


## 1.9.0 — 标签、筛选与大号组件（源码更新）

- 新增标签输入、去重和搜索；保留未带标签的旧事件。
- 原生 macOS 色轮自由选色，保留五种彩色预设；RGB 颜色在应用和组件一致显示。
- 每个组件独立配置日期范围、包含全部／任一标签、排除标签、排序、置顶优先和跳过 N 条。
- 分页位置由已持久化的配置稳定确定，避免系统不保存隐藏随机标识导致回到首页。相同筛选、排序与每页条数的组件同步页码；不同条件各自保存页码。
- 大号组件每页 5–10 条及分页按钮；中号自动概览沿用三条，手动槽位不受自动筛选影响。
- 写入 schema 7、读取 schema 1–7；启动不改写旧数据。保存后不支持用 1.8 或更早版本编辑。
- 当前下载 Release 仍为 1.8.1 开发预览；没有新增已公证发行包。

## 1.8.2 — 后台登记恢复（源码更新）

- 已启用后台、真实启动回执已确认且登记恢复未报错时，隐藏主窗口有限覆盖说明；关闭、待批准和真实提醒错误仍显示。
- 每次冷启动重建已启用后台登记一次，处理版本升级及同版本替换导致的旧系统登记失效；恢复中断下次启动重试，保留用户关闭与系统待批准状态。
- 系统登记显示开启但任务未启动时，等待系统处理旧标识后重登记一次；仍失败显示错误，下次启动继续恢复。登记等待不会阻塞事件列表加载。
- 开发安装替换前注销旧包登记，失败恢复旧包登记；先完成 LaunchServices 清理再启动，避免启动后再次登记应用使后台标识失效。
- CI 增加原生后台登记和通知服务回归。

已通过130项核心测试、14项安装测试及原生后台/通知服务回归。实际本机ad hoc构建仍遇到AMFI启动签名约束拒绝，后台持续运行未通过最终验收；没有自动隐藏这一失败。需正式签名后继续验证。

现有 1.8.1 开发预览下载包未包含本次源码修复。

## 1.8.1 — 开发预览 1（2026-10-10）

首次公开源码与下载预览，使用MIT许可证。

- 修复系统允许通知后设置仍缓存Denied：打开设置、返回应用和设置可见期间自动检查，权限变化后补排，无需重新保存事件。
- 同步权限行的无障碍值及主窗口提醒提示；权限不变不反复重新安排队列。
- 提供双架构DMG、App ZIP、SHA256及示例界面说明。

包含已有功能：桌面小号/中号与自选显示、全天/年度事件、起始日计数、不同时间格式、导入导出、备份恢复、归档回收站、多选批量、Vim、每日/满月/周年提醒、可选后台和菜单栏、Dock外观及中英文。

已验证130项核心测试、原生服务权限与并发回归、主App/Widget双架构编译、严格嵌套签名和同窗口真实UI权限刷新。

### 预览限制

- 本地ad hoc签名，没有Developer ID签名及公证，互联网下载可能无法直接打开。
- 最低部署目标macOS14，但本次现场测试在macOS27；其他受支持系统需继续实测。
- 实际通知送达、持续后台、正式共享容器、完整VoiceOver与正式签名快捷指令仍待验证。
- 正式版存储模式不同，升级须经导出/导入迁移；不要用旧版编辑schema6数据。
