# 日距 1.14.0（43）· 未公证开发预览

### 新增

- 新增“更新日志”，可在设置中离线查看本次变化和历史公开版本。
- 更新提示展示本次更新说明，安装前可了解新增功能和修复内容。

### 改进

- 首次打开、更新或替换安装包后，自动请求登记日距小组件。

### 修复

- 设置 → 小组件新增“刷新并修复小组件”，可重试系统登记和内容刷新，无需终端操作。
- 保留已有事件和组件配置；修复结果清楚区分请求已提交、安装不完整及系统未响应。

仅支持 Apple Silicon（arm64）、macOS 14+。使用 ad hoc 本地签名，尚无 Developer ID 签名或 Apple 公证；EdDSA 更新签名不等于 Apple 公证。若系统阻止打开，请等待公证版或从源码构建，不要关闭系统安全保护。

1.13.0 及以上可在应用中“检查更新…”；更早版本下载 ZIP 手动安装到 Applications。先完成编辑并导出备份。修复后关闭并重开系统组件页，搜索“日距”或“DayDistance”。提交登记请求不等于系统已完成展示；外部 M5 设备的根因尚未证实。

验证：178 项核心测试、更新日志发布工具测试、原生设置及更新保护、1,152 种组件 metadata 组合、Apple Silicon 构建和严格嵌套签名；computer use 核对中英文日志及历史滚动。用户数据、组件配置和更新公钥保持。旧系统、完整 VoiceOver、桌面最终像素和正式共享容器等边界仍需独立验收。


---

## English

### New

- Add Release Notes in Settings to read current changes and previous public releases offline.
- Show release notes in update prompts so you can review new features and fixes before installing.

### Improvements

- Request widget registration automatically after installation, an update, or replacing the app.

### Fixes

- Add Refresh & Repair Widgets in Settings to retry registration and content refresh without Terminal.
- Preserve events and widget configurations, with distinct messages for submitted requests, incomplete installations, and timeouts.

Apple Silicon only, macOS 14+. Ad hoc signed and **not notarized**. The signed update feed and ZIP use the existing EdDSA key; this is not Apple notarization. Versions 1.13.0+ can update in the app; older versions need a manual ZIP installation. Save edits and export a backup first. Widget registration requests do not guarantee immediate gallery or desktop rendering. The external M5 report remains unconfirmed on-device.
