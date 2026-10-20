# 日距 1.17.0（48）· 列表分类与到期后处理（未公证开发预览）

### 新增

- 新增普通列表和可嵌套文件夹，可按工作、生活等分类事件；侧栏“列表”右侧的加号统一创建列表、智能列表和文件夹。
- 事件“显示”页新增到期后处理：保留原日期继续计日，或将一次性事件移入可恢复的回收站；保留的纪念事件也可使用周年格式。

### 改进

- 今天尚未到期的定时事件，在开启当天计时的小组件中显示“还有 HH:mm”，去掉重复秒计时，目标日期仍可显示。
- 到期处理会等待编辑结束；全天事件保留到当天结束，恢复后取消自动清理。App 关闭时组件先隐藏到期事件，下次打开 App 或 CLI 时移入回收站。
- CLI、JSON 与 MCP 支持 afterDate=keep|trash（CLI：--after-date）；延续重试去重、冲突保护、备份及提醒同步。

### 修复

- 修复 MCP 持续监听时，Finder、Spotlight 或正常打开日距无法出现主窗口的问题；已有旧版 MCP 连接需在 Agent 中重新连接。
- 提醒不再安排到一次性事件到期之后；旧事件默认保留，既有列表、智能列表、小组件选择和显示设置保持。

使用入口：侧栏“列表”旁的 ＋ 创建普通列表、智能列表或文件夹；事件编辑页选择所属列表；“显示”页设置到期后处理与计日格式。未开启自动清理的旧事件保持原样。

此版本合并自1.15.0以来的本地改动，1.16系列未作为公开Release单独发行。Apple Silicon（arm64）、macOS 14+；ad hoc签名，**尚未经过Developer ID签名或Apple公证**。EdDSA更新验签不等于Apple公证。1.13.0及以上可在应用内“检查更新…”，旧版手动下载ZIP。正常更新保留本地事件和组件配置。

数据兼容：事件写入使用schema 8，列表/分类使用schema 2；旧数据兼容读取。保存新设置后，较旧版本无法安全读取新格式，请勿降级后覆盖数据。分类通过列表备份保护；事件JSON导出只包含事件内容。

验证：198核心测试、原生存储/批量/提醒/自动化/组件回归、arm64构建与严格嵌套签名；中英文界面和临时数据自动到期/恢复、真实桌面时分显示。其他Mac/macOS 14、实际通知送达与长期睡眠后的系统刷新仍需独立验收。MCP超大响应仍需使用较小limit分页；此版本不新增远程HTTP、TUI、永久删除或云同步。

---

## English

### New

- Organize events in regular lists and nested folders. Use the plus beside Lists to create a list, smart list or folder.
- Choose what happens after an event in Display settings: keep the original date and count elapsed days, or move a one-time event to recoverable Trash. Memories can also use anniversary formatting.

### Improvements

- With same-day timers enabled, widgets show today’s upcoming timed events as Remaining HH:mm, without a duplicate seconds timer. The target date remains optional.
- Expiry waits for active edits to finish. All-day events remain until the day ends; restoring an event disables automatic cleanup. Widgets hide expired events while the app is closed; the app or CLI moves them to Trash when next opened.
- Set afterDate=keep|trash through JSON/MCP, or --after-date in the CLI, with existing deduplication, conflict protection, backups and reminder synchronization.

### Fixes

- Fix normal opening from Finder or Spotlight while an MCP server is listening. Reconnect existing MCP clients to use the new executable.
- Stop scheduling reminders beyond a one-time event’s expiry. Existing events default to keeping their original dates; preserve lists, smart lists, widget selections and display settings.

Use the plus beside Lists to create a regular list, smart list or folder. Assign an event in its editor and set its after-date action and count format under Display. Existing events keep their dates unless you enable cleanup.

This release combines local changes since 1.15.0; the 1.16 series was not released separately. Apple Silicon only, macOS 14+. Ad hoc signed and **not notarized**. EdDSA update signatures are not Apple notarization. Version 1.13.0+ can check for updates in the app; older builds need the ZIP. Normal upgrades retain local events and widget configurations.

Data compatibility: new writes use event schema 8 and list schema 2. Existing files are readable, but older apps cannot safely read new formats after saving; do not downgrade and overwrite them. Event JSON exports do not include list membership; use list backups for hierarchy and classification.

Validation covers 198 core tests, native storage/batch/reminder/automation/widget probes, arm64 builds and strict nested signatures, bilingual UI, disposable expiry/recovery and real desktop HH:mm display. Other Macs/macOS 14, actual delivery and long-sleep refresh remain separate checks. Use small page limits for very large MCP responses. No remote HTTP, TUI, permanent-deletion or cloud-sync feature is added.
