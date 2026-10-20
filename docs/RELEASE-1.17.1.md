# 日距 1.17.1（49）· 性能与工程优化

减少重复存储计算，限制长时间使用时的撤销快照积累，修复增量构建中的更新框架恢复。

- 本地备份列表复用已验证内容的事件计数，减少重复解码，仍读取并校验实际文件。
- 保存事件直接编码最终文档，保留原子写入、冲突检测与 Agent 重试去重。
- 事件撤销/重做保留最近 100 次操作；文字编辑的原生撤销保持独立。
- 修复清理构建产物后，增量构建可能遗漏 Sparkle 更新框架的问题；补充恢复、版本和路径保护回归。

在同机优化构建、20 份有效备份、7 个热态样本中，1,000 事件的备份列表 p50 由约 280 ms 降至 34 ms，5,000 事件由约 1,398 ms 降至 169 ms。这是备份列表操作的测量，不是整个应用的加速倍数。4 事件时该操作约 4.4 → 2.8 ms。有限窗口内没有观察到空闲持续写盘或组件/MCP 空转，仍需长期使用验证。

**Apple Silicon（arm64），macOS 14+；ad hoc 签名，尚未经过 Developer ID 签名或 Apple 公证。** 更新源和 ZIP 使用 EdDSA 验签；这不等于 Apple 公证。1.13.0 及以上可在应用内“检查更新…”，安装前会征求确认。原有事件、列表与组件设置沿用，存储 schema 不变。

---

# DayDistance 1.17.1 (49) · Performance and build improvements

- Reuse validated event counts when listing backups, reducing repeated decoding while still verifying file contents.
- Encode the final event document directly on save, retaining atomic writes, conflict checks and Agent retry deduplication.
- Retain the latest 100 event undo/redo operations to bound snapshot accumulation. Native text undo remains separate.
- Recover the embedded Sparkle framework during incremental builds after product cleanup, with version and path-safety regression tests.

With 20 valid backups and seven warm samples in an optimized same-machine benchmark, backup-list p50 changed from approximately 280 to 34 ms at 1,000 events and 1,398 to 169 ms at 5,000 events. This measures backup listing, not whole-app speed. At four events it changed from about 4.4 to 2.8 ms. Short idle measurements found no continuous disk writes or widget/MCP busy loop; long-term behavior remains a separate check.

**Apple Silicon only, macOS 14+. Ad hoc signed and not notarized by Apple.** The feed and ZIP use EdDSA update signatures; these are not Apple notarization. Version 1.13.0+ can check for and install updates in the app with user confirmation. Existing events, lists, widget settings and storage schema are retained.
