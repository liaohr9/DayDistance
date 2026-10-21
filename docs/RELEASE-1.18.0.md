# 日距 1.18.0（50）· 恢复 Intel 支持

- 恢复 Intel Mac 支持，发布同时包含 **arm64 + x86_64** 的 Universal 通用 ZIP。
- 主应用、桌面小组件、CLI/MCP 与 Sparkle 更新助手均保留两种架构，无需按芯片选择安装包。
- 继续支持 macOS 14+，保留 1.17.1 的性能优化；事件格式、列表、小组件配置和自动化权限不变。
- 现有可运行版本可通过应用内“检查更新…”获取通用版；Intel 用户如果当前安装的是无法启动的 arm64 专用版，请先备份已有数据，再手动下载此版本替换 App。

**未公证开发预览。** 使用 ad hoc 代码签名和 EdDSA 更新验签，尚无 Developer ID 签名或 Apple 公证。双架构编译、签名和 Apple Silicon/Rosetta 验证不等于 Intel 真机验收，Intel Mac 与较早 macOS 的现场运行仍需独立确认。通用包包含额外架构，因此比 1.17.1 的 arm64 专用包更大。

---

# DayDistance 1.18.0 (50) · Intel support restored

- Restore Intel Mac support with one **arm64 + x86_64 Universal ZIP**.
- The native app, desktop widget, CLI/MCP executable and Sparkle updater helpers all contain both architectures.
- Keep macOS 14+ support and the 1.17.1 performance improvements. Event formats, lists, widget configurations and automation permissions are unchanged.
- Running versions can use Check for Updates. On Intel, if the installed arm64-only version cannot launch, back up any existing data and replace the app using this download.

**Unnotarized developer preview.** Ad hoc code signatures and EdDSA update verification are not Developer ID signing or Apple notarization. Compilation, signatures and Apple Silicon/Rosetta checks do not establish real Intel-hardware acceptance; older macOS and physical Intel runtime checks remain separate. The added architecture makes this Universal package larger than the arm64-only 1.17.1 download.
