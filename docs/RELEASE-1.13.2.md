# 日距 1.13.2（41）· 开发预览（未公证）

修复大号小组件在事件不足一页时分散到上下两端的问题。现在按配置的每页容量保留行距，从顶部依次排列，下方留白；分页的最后一页同样生效，翻页按钮保留在底部。原有事件、筛选、排序与显示选项不变。

**仅支持 Apple Silicon（arm64）、macOS 14+。本包使用本地 ad hoc 签名，尚无 Developer ID 签名或 Apple 公证。** 更新源和 ZIP 使用现有 EdDSA 密钥签名，EdDSA 不等于 Apple 公证。系统若阻止首次打开，请等待公证版本或从源码构建，不要关闭系统安全保护。

1.13.0 / 1.13.1 用户可通过应用菜单“检查更新…”或“设置 → 软件更新”获取本次更新。自动检查开启时，应用运行期间每天检查一次，发现新版先询问；确认后下载、校验并安装重启。更早版本需要手动安装 ZIP 一次。请先保存或取消正在编辑的内容。

验证：176 项核心测试、1,152 种小组件 metadata 组合、安装保护测试、Apple Silicon 构建与严格嵌套签名；computer use 核对生产组件视图中的 1 / 2 / 4 / 5 / 10 条事件、末页以及日期和图标开关，并在系统大号组件的 344×344 尺寸下复核。已安装版本保留原事件与组件配置，新扩展读取原选择并生成系统大号 timeline。

验收边界：生产视图与系统 timeline 已核对，实际桌面最终位置尚未直接核对。较早受支持系统、完整 VoiceOver、正式 App Group 迁移及 Developer ID / 公证仍需独立验收。当前仍为开发预览。

手动安装：下载 ZIP，解压，将“日距.app”放入 Applications。升级前导出备份，保存或取消编辑并正常退出旧版，保留一份应用。SHA256SUMS.txt 用于校验下载完整性。

---

## English

Fixes large widgets spreading a short list across their full height. Events now occupy consecutive slots from the top, with empty space below; the last page follows the same layout and paging controls stay at the bottom. Existing events, filtering, sorting, and appearance settings are unchanged.

Apple Silicon only, macOS 14+. This is an **ad hoc signed, unnotarized developer preview**. The feed and ZIP use the existing EdDSA update key; this is not Apple notarization. Versions 1.13.0 and 1.13.1 can update in the app; earlier versions need one manual ZIP installation.

Production widget views, layout variants, the native system timeline, 176 core tests, metadata compatibility, installation guards, and arm64 signing checks were validated. Final desktop placement, older supported systems, full VoiceOver, formal App Group migration, Developer ID signing, and notarization remain separate acceptance items.
