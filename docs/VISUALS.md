# README 界面素材来源

所有公开界面均使用虚构事件，不读取或修改个人事件文件。

- `events.png`：生产 ContentView 原生浅色窗口，六个虚构事件，私有临时数据；用户于 2026-10-10 自行截图，保留原图的桌面背景与构图。
- `events-en.png`：同一演示界面的英文版，事件名称、界面文字和日期格式均为英文；用户于 2026-10-10 自行截图。
- `editor.png`：生产EventEditor编辑表单，截图后取消草稿。
- `reminders.png`：生产EventEditor重复提醒展开，假通知客户端，不发送真实通知，截图后取消。
- `widgets.png`：生产DayWidgetContent在原生演示窗口展示小号、中号与深色外观，固定2026-10-10示例日期；**不是系统桌面截图或实际WidgetKit集成验收**。
- `icon.png`：应用当前亮色Dock图标。

重现主页面示例窗口：`python3 script/public_ui_probe.py --capture-ready --language zh-Hans`（英文版用 `--language en`）；日期与天数按运行时的本地时间显示。其他表单示例：`python3 script/public_ui_probe.py --showcase --language zh-Hans`；小组件展示：`python3 script/widget_showcase.py`。两者退出时删除临时数据与App登记，不覆盖安装版。主页面截图由用户提供，其余窗口截图使用原生 computer use 获取；README 没有用效果图冒充真实界面。
