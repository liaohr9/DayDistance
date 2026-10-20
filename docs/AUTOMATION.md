# DayDistance for Agents / 日距自动化

Available in 1.15.0. Apple Silicon, macOS 14 or later. The CLI and MCP server ship inside the native app: no Node.js, Python, HTTP service, or separate runtime is required.

## 中文快速开始

1. 将日距放入 `/Applications/日距.app`，至少打开一次。
2. 在 **设置 → 自动化** 打开“允许本机 Agent 读取事件”。需要创建或修改时，再打开“允许创建和修改事件”。默认均关闭；关闭读取会同时关闭写入。
3. 点“安装命令行工具…”，选择保存位置，例如 `~/.local/bin/daydistance`。将该目录加入 PATH，或直接运行完整路径。安装器不会修改 shell 配置，不需要 sudo。

```sh
daydistance capabilities
daydistance events list --limit 20
daydistance events create --title '旅行' --date 2027-03-01 --request-id trip-2027-03
```

也可以直接使用应用内的可执行文件：

```sh
'/Applications/日距.app/Contents/MacOS/DayDistance' --cli events list
```

MCP 可以持续监听，同时通过访达、Spotlight 或 Dock 正常打开主窗口。更新应用后，已有的 MCP 连接需要在 Agent 客户端重连一次，才会使用新可执行文件。

普通命令输出单份 JSON。`--help` 输出帮助；`--json` 可省略。`--stdin` 从标准输入读取一个完整 JSON 文档，读至 EOF，输入上限 64 KiB。

```sh
printf '%s\n' '{"apiVersion":1,"operation":"create","arguments":{"title":"旅行","date":"2027-03-01","requestId":"trip-2027-03"}}' | daydistance --stdin
```

创建须提供 `requestId`，同一标识的完全相同请求重试不会创建重复事件。修改、归档、移入回收站、恢复须先 `get` 获取最新 `revision`。冲突时重新读取；不要自动覆盖用户更改。

```sh
daydistance events get EVENT_UUID
daydistance events update EVENT_UUID --if-revision CURRENT_REVISION --title '新的名称'
daydistance events archive EVENT_UUID --if-revision CURRENT_REVISION
daydistance events trash EVENT_UUID --if-revision CURRENT_REVISION
daydistance events restore EVENT_UUID --if-revision CURRENT_REVISION
daydistance events countdown EVENT_UUID
daydistance events open EVENT_UUID
```

应用运行时，命令交给正在运行的 App 处理，窗口中的事件会同步变化；事件编辑、文件操作或模态窗口尚未完成时，写入返回 `BUSY`。应用退出后，命令使用相同的签名应用执行后台处理，不显示主窗口。只有 `open` 明确请求打开事件。保存沿用原有备份和小组件刷新，并等待提醒同步；提醒失败不撤销已保存事件，结果会附带警告。

## MCP 配置 / MCP configuration

Add a stdio server to your MCP client's configuration. The key `mcpServers` is a common format; adapt the outer configuration to your client's documentation. A running GUI is optional.

```json
{
  "mcpServers": {
    "daydistance": {
      "command": "/Applications/日距.app/Contents/MacOS/DayDistance",
      "args": ["--cli", "mcp"]
    }
  }
}
```

Or use the absolute path of the installed `daydistance` wrapper with `args: ["mcp"]`. Do not put shell quoting characters inside the JSON command value.

Ten tools: `daydistance_capabilities`, `daydistance_list`, `daydistance_get`, `daydistance_countdown`, `daydistance_create`, `daydistance_update`, `daydistance_archive`, `daydistance_trash`, `daydistance_restore`, `daydistance_open`.

The server implements newline-delimited JSON-RPC over stdio, `initialize`, `ping`, `tools/list`, and `tools/call`. It supports protocol versions `2025-11-25`, `2025-06-18`, and `2024-11-05`. Tool results contain both `structuredContent` and a JSON text content block. Domain failures use `isError: true`; malformed requests and unknown tools use JSON-RPC errors. Standard output contains protocol messages only. No port is opened.

Example agent instruction:

> Check DayDistance capabilities, then create an all-day event “Submit paper” on 2027-03-01. Use requestId paper-deadline-2027-03. If the request times out, retry with the same requestId and identical fields. Do not change any existing event.

## English quick start

Open **Settings → Automation**, enable local read access, and optionally enable write access. Install the command-line wrapper at a user-selected location. You can also call the app executable directly with `--cli`. Reads and writes work while the app is open or closed. Active edits and file dialogs block mutations without discarding drafts.

```sh
daydistance events create --title 'Submit paper' --at 2027-03-01T18:00:00+08:00 --request-id paper-2027-03
daydistance events list --state active --tag Research --limit 20 --offset 0
```

Use `--date YYYY-MM-DD` for an all-day calendar date, or `--at ISO8601` for a timestamp with seconds and an explicit timezone. Exactly one is required when creating; timestamps are saved at the app's existing minute precision. Optional fields: repeatable `--tag`, `--includes-start-day true|false`, `--repeat-yearly true|false`, and `--pinned true|false`. Updates preserve fields you omit; JSON `tags: []` clears tags. Supported list states: `active`, `archived`, `trashed`, `all`; all supplied tags must match. List order is ascending target date, then UUID; page size is 1–200, default 100.

## Contract and limits / 接口约定与边界

- API envelope: `{"apiVersion":1,"operation":"list","arguments":{}}`. Fields and types are validated; unknown argument fields are rejected. Dates use the Mac's current calendar timezone for all-day events.
- Success: `{"apiVersion":1,"ok":true,"data":{...}}`. Failure: `{"apiVersion":1,"ok":false,"error":{"code":"BUSY","message":"..."}}`.
- CLI exits: `0` success, `64` invalid input/version, `66` missing/removed event, `70` storage/transport failure, `75` busy/conflict, `77` disabled/read-only. Error codes and field names are stable English identifiers regardless of display language.
- Create receipts are saved atomically with the event and survive process restarts and normal app edits. Reusing a key with changed fields returns `CONFLICT`. A permanently removed event returns `EVENT_REMOVED`, rather than silently recreating it. Receipt capacity is 4,096; capacity exhaustion fails without creating an event. JSON export/import and migration to an older app are **not** cross-install deduplication guarantees.
- No permanent-deletion, notification-permission, app-setting, file-import/export, or arbitrary-code tool is exposed in this version. Existing reminders survive event edits; creating custom reminder schedules through the API is deferred.
- Access is local to the current macOS account. Private same-user IPC and the default-off switches prevent unintended API use; they are not isolation against other software already running with your account's file access. Do not point untrusted agents at the server.
- Never edit `events.json` directly. GUI and CLI serialize ownership and use the existing event store, compare-and-save, backup and reminder paths.
- No client configuration is changed automatically. Moving/renaming the app after installing the wrapper requires reinstalling it. Normal in-place app updates keep the wrapper path valid.
- Local validation is separate from public release. Developer preview packages remain unnotarized until Developer ID signing and Apple notarization are completed.

- Known preview limit: unusually large MCP responses (over 2 MiB including both content representations) close the stdio session. Reconnect with a smaller list limit. A bounded pagination error is deferred. / 已知预览边界：MCP 的双份内容合计超过 2 MiB 时会关闭连接，请用较小的 limit 分页；明确的分页错误提示待补充。

### After-date behavior / 到期后处理

`events create` and `events update` accept `--after-date keep|trash` (JSON/MCP: `afterDate`). The default `keep` preserves the original date and counts elapsed days. `trash` hides an expired nonrepeating event from widgets and moves it to recoverable Trash when the app/CLI next processes the store. All-day events expire at the start of the following local day. Restoring an event changes this field to `keep`. Yearly repeat and `trash` cannot be combined.

例如：`daydistance events create --title "Submit assignment" --at 2027-01-15T18:00:00+08:00 --after-date trash --request-id assignment-2027-01-15`。GUI 中在事件的“显示 → 到期后”设置；保留原日期的纪念事件可选择天数或周年格式。
