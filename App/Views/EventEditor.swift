import SwiftUI

private struct EventRemindersKey: EnvironmentKey { static let defaultValue: EventReminderService? = nil }

private struct ReminderPermissionKey: EnvironmentKey {
    static let defaultValue: @MainActor () async -> String? = { L10n.text("临时验证不会发送系统提醒。") }
}
extension EnvironmentValues {
    var eventReminders: EventReminderService? {
        get { self[EventRemindersKey.self] }
        set { self[EventRemindersKey.self] = newValue }
    }
    var requestReminderPermission: @MainActor () async -> String? {
        get { self[ReminderPermissionKey.self] }
        set { self[ReminderPermissionKey.self] = newValue }
    }
}

struct EventEditor: View {
    @State var event: CountdownEvent
    let session: EventEditSession
    private var isExisting: Bool { session.original != nil }
    @Bindable var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReminderPermission) private var requestReminderPermission
    @Environment(\.eventReminders) private var reminders
    @State private var isSaving = false
    @State private var showAppearance = false
    @State private var showRecurringReminders = false
    @State private var confirmDelete = false
    @State private var saveError: String?
    @FocusState private var nameFocused: Bool

    init(session: EventEditSession, store: EventStore) {
        var draft = session.event
        draft.targetDate = draft.originalDate()
        if !draft.repeatYearly && draft.displayFormat == .anniversary { draft.displayFormat = .days }
        self._event = State(initialValue: draft)
        self._showRecurringReminders = State(initialValue: draft.hasRecurringReminders)
        self.session = session
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text(isExisting ? "编辑事件" : "新建事件")).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
            Form {
                TextField("名称", text: $event.title)
                    .textFieldStyle(.roundedBorder).focused($nameFocused)
                    .accessibilityLabel("事件名称")
                DatePicker("日期", selection: $event.targetDate, displayedComponents: .date)
                    .datePickerStyle(.field).accessibilityLabel("目标日期")
                Toggle("全天", isOn: $event.isAllDay).toggleStyle(.checkbox)
                if !event.isAllDay {
                    DatePicker("时间", selection: $event.targetDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field).accessibilityLabel("目标时间")
                }
                Toggle("每年重复", isOn: $event.repeatYearly).toggleStyle(.checkbox)
                Picker("单次提醒", selection: $event.reminder) {
                    ForEach(EventReminder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if event.reminder == .custom {
                    Stepper(value: $event.reminderDaysBefore, in: 0...365) {
                        Text(L10n.format("提前 %ld 天", event.reminderDaysBefore))
                    }.accessibilityLabel("提醒提前天数")
                    DatePicker("提醒时间", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                }
            }.formStyle(.columns)
            DisclosureGroup("重复提醒", isExpanded: $showRecurringReminders) {
                Form {
                    recurringControl("每日提醒", timeLabel: "每日提醒时间", keyPath: \.dailyReminderTime)
                    recurringControl("每满一个月", timeLabel: "满月提醒时间", keyPath: \.monthlyReminderTime)
                    recurringControl("每满一年", timeLabel: "周年提醒时间", keyPath: \.yearlyReminderTime)
                }.formStyle(.columns)
                Text("满月和周年按原始日期计算；短月按月末，闰年恢复原日期。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if event.hasEnabledReminders {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("通知权限：%@", reminders?.authorizationDescription ?? L10n.text("临时验证")))
                    if let next = ReminderPolicy.plan(events: [preparedDraft], now: Date()).requests.first?.fireDate {
                        Text(L10n.format("保存后预计提醒：%@", next.formatted(date: .abbreviated, time: .shortened)))
                    } else { Text("提醒时间已过，不会安排通知。") }
                }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if event.hasRecurringReminders {
                Text("重复提醒会提前安排。打开应用可自动补排；如需退出后持续更新，请在设置中启用后台刷新。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if event.repeatYearly {
                Text("保留原始日期，倒计至下一次纪念日。2 月 29 日在非闰年按 2 月 28 日计算。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if event.reminder != .none && event.reminder != .custom && event.isAllDay {
                Text(L10n.format("全天事件在 %@ 提醒。", L10n.time(hour: 9))).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Toggle("当天算第 1 天", isOn: $event.includesStartDay)
                    .toggleStyle(.switch).disabled(event.repeatYearly)
                Text("正计时包含当天；关闭时从第 0 天开始。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("更多选项", isExpanded: $showAppearance) {
                Form {
                    Picker("计日格式", selection: $event.displayFormat) {
                        ForEach(EventDisplayFormat.allCases.filter { $0 != .anniversary || event.repeatYearly }, id: \.self) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    Toggle("置顶", isOn: $event.isPinned).toggleStyle(.checkbox)
                    Picker("图标", selection: $event.symbol) {
                        ForEach(EventTheme.symbols, id: \.0) { symbol, name in
                            Label(L10n.text(name), systemImage: symbol).tag(symbol)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Picker("颜色", selection: $event.colorKey) {
                        ForEach(EventTheme.all) { theme in
                            Label { Text(L10n.text(theme.name)) } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(theme.color)
                            }.tag(theme.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.formStyle(.columns).padding(.top, 10)
            }
                }.padding(.trailing, 6)
            }.frame(height: showRecurringReminders || showAppearance ? 480 : (event.reminder == .custom ? 400 : 300))
            if let saveError {
                Text(saveError).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isExisting {
                    Button("删除", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    let value = preparedDraft
                    isSaving = true
                    Task { @MainActor in
                        let warning = !value.hasEnabledReminders ? nil : await requestReminderPermission()
                        if store.upsert(value, replacing: session.original) {
                            if let warning { store.errorMessage = warning }
                            dismiss()
                        } else { saveError = store.errorMessage }
                        isSaving = false
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.top, 2)
        }
        .padding(20).frame(width: 440)
        .disabled(isSaving)
        .onAppear { nameFocused = true }
        .onChange(of: event.reminder) {
            if event.reminder == .custom && event.reminderTime == nil {
                event.reminderTime = event.isAllDay ? CalendarTime(hour: 9, minute: 0) : CalendarTime(date: event.targetDate)
            }
        }
        .onChange(of: event.repeatYearly) { if !event.repeatYearly && event.displayFormat == .anniversary { event.displayFormat = .days } }
        .alert("删除事件？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let original = session.original, store.delete(original) { dismiss() } else { saveError = store.errorMessage }
            }
        } message: { Text(L10n.format("删除「%@」后可从回收站恢复。", event.title)) }
    }
    private var preparedDraft: CountdownEvent {
        var value = event
        value.calendarDay = value.isAllDay || value.repeatYearly ? CalendarDay(date: value.targetDate) : nil
        value.annualTime = value.repeatYearly ? CalendarTime(date: value.targetDate) : nil
        return value
    }
    @ViewBuilder private func recurringControl(_ label: String, timeLabel: String, keyPath: WritableKeyPath<CountdownEvent, CalendarTime?>) -> some View {
        Toggle(L10n.text(label), isOn: Binding(get: { event[keyPath: keyPath] != nil }, set: { event[keyPath: keyPath] = $0 ? CalendarTime(hour: 9, minute: 0) : nil }))
            .toggleStyle(.checkbox)
        if event[keyPath: keyPath] != nil {
            DatePicker(L10n.text(timeLabel), selection: Binding(get: {
                let time = event[keyPath: keyPath] ?? CalendarTime(hour: 9, minute: 0)
                return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
            }, set: { event[keyPath: keyPath] = CalendarTime(date: $0) }), displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(get: {
            let time = event.reminderTime ?? CalendarTime(hour: 9, minute: 0)
            return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
        }, set: { event.reminderTime = CalendarTime(date: $0) })
    }

}
