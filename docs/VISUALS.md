# README 界面素材来源

所有公开界面均使用虚构事件，不读取或修改个人事件文件。

- `events.png`：生产ContentView原生窗口，私有临时数据，2026-10-10截图。
- `editor.png`：生产EventEditor编辑表单，截图后取消草稿。
- `reminders.png`：生产EventEditor重复提醒展开，假通知客户端，不发送真实通知，截图后取消。
- `widgets.png`：生产DayWidgetContent在原生演示窗口展示小号、中号与深色外观，固定2026-10-10示例日期；**不是系统桌面截图或实际WidgetKit集成验收**。
- `icon.png`：应用当前亮色Dock图标。

重现示例窗口：`python3 script/public_ui_probe.py --showcase --language zh-Hans`；小组件展示：`python3 script/widget_showcase.py`。两者退出时删除临时数据与App登记，不覆盖安装版。窗口截图使用原生computer use获取；README没有用效果图冒充真实界面。
