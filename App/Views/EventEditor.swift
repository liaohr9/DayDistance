import SwiftUI
import AppKit

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

private struct ReminderPreviewRequest: Equatable {
    let draft: CountdownEvent
    let calendarRevision: Int
}

private enum EventEditorPage { case basic, reminders, display }

struct EventEditor: View {
    @State var event: CountdownEvent
    let session: EventEditSession
    private var isExisting: Bool { session.original != nil }
    @Bindable var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReminderPermission) private var requestReminderPermission
    @Environment(\.eventReminders) private var reminders
    @StateObject private var colorPanel = EventColorPanel()
    @State private var tagsText: String
    @State private var nextReminderDate: Date?
    @State private var previewRevision = 0
    private let lists: [SmartList]
    private let saveCategory: ((UUID, UUID?, UUID?) -> String?)?
    @State private var selectedListID: UUID?
    @State private var membershipBaseline: UUID?
    @State private var savedBaseline: CountdownEvent?
    @State private var isSaving = false
    @State private var selectedPage = EventEditorPage.basic
    @Environment(\.openSettings) private var openSettings
    @State private var confirmDelete = false
    @State private var saveError: String?
    @FocusState private var nameFocused: Bool

    init(session: EventEditSession, store: EventStore, lists: [SmartList] = [],
         initialListID: UUID? = nil, currentListID: UUID? = nil,
         saveCategory: ((UUID, UUID?, UUID?) -> String?)? = nil) {
        var draft = session.event
        draft.targetDate = draft.originalDate()
        self._event = State(initialValue: draft)
        self._tagsText = State(initialValue: draft.tags.joined(separator: ", "))
        self.session = session
        self.store = store
        self.lists = lists
        self.saveCategory = saveCategory
        _selectedListID = State(initialValue: initialListID)
        _membershipBaseline = State(initialValue: currentListID)
        _savedBaseline = State(initialValue: session.original)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(isExisting ? "编辑事件" : "添加一个日子")).font(.title2.weight(.semibold))
            Picker("事件设置分类", selection: $selectedPage) {
                Text("基本信息").tag(EventEditorPage.basic)
                Text("提醒").tag(EventEditorPage.reminders)
                Text("显示").tag(EventEditorPage.display)
            }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch selectedPage {
                case .basic: basicPage
                case .reminders: remindersPage
                case .display: displayPage
                }
            }.frame(height: 380)
            if let saveError {
                Text(saveError).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isExisting { Button("删除", role: .destructive) { confirmDelete = true } }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    let value = preparedDraft
                    isSaving = true
                    Task { @MainActor in
                        let warning = !value.hasEnabledReminders ? nil : await requestReminderPermission()
                        if store.upsert(value, replacing: savedBaseline) {
                            savedBaseline = store.events.first { $0.id == value.id }
                            if selectedListID != membershipBaseline, let saveCategory,
                               let error = saveCategory(value.id, membershipBaseline, selectedListID) {
                                saveError = L10n.format("事件已保存，但列表分类未保存：%@", error)
                                isSaving = false
                                return
                            }
                            membershipBaseline = selectedListID
                            if let warning { store.errorMessage = warning }
                            dismiss()
                        } else { saveError = store.errorMessage }
                        isSaving = false
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 540)
            .disabled(isSaving)
            .onAppear { nameFocused = true }
            .onChange(of: event.reminder) {
                if event.reminder == .custom && event.reminderTime == nil {
                    event.reminderTime = event.isAllDay ? CalendarTime(hour: 9, minute: 0) : CalendarTime(date: event.targetDate)
                }
            }
            .onChange(of: event.recurrence) { if event.isRepeating { event.afterDate = .keep } }
            .alert("删除事件？", isPresented: $confirmDelete) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    if let original = savedBaseline, store.delete(original) { dismiss() } else { saveError = store.errorMessage }
                }
            } message: { Text(L10n.format("删除「%@」后可从回收站恢复。", event.title)) }
    }
    private var basicPage: some View {
        Form {
            Section("事件信息") {
                TextField("名称", text: $event.title).focused($nameFocused).accessibilityLabel("事件名称")
                if saveCategory != nil {
                    Picker(L10n.text("列表"), selection: $selectedListID) {
                        Text(L10n.text("无列表")).tag(nil as UUID?)
                        ForEach(lists.filter { $0.kind == .ordinary }) { list in
                            Text(ListHierarchy.path(for: list, in: lists)).tag(Optional(list.id))
                        }
                    }
                }
            }
            Section("日期") {
                DatePicker("日期", selection: $event.targetDate, displayedComponents: .date)
                    .datePickerStyle(.field).accessibilityLabel("目标日期")
                Toggle("全天", isOn: $event.isAllDay)
                if !event.isAllDay {
                    DatePicker("时间", selection: $event.targetDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field).accessibilityLabel("目标时间")
                }
            }
            Section("重复") {
                Picker("重复频率", selection: $event.recurrence) {
                    ForEach(EventRecurrence.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                if event.repeatMonthly {
                    Text("当月没有该日时使用月末，下个月恢复原日号。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if event.repeatDaily {
                    Text("每天按原时间重复；通知在“提醒”页单独设置。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if event.repeatYearly {
                    Text("倒计至下一次纪念日；通知在“提醒”页单独设置。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("标签") {
                TextField("标签", text: $tagsText, prompt: Text("用逗号分隔，如工作，旅行"))
                    .accessibilityLabel("事件标签")
            }
        }.formStyle(.grouped)
    }
    private var remindersPage: some View {
        Form {
            Section("到期提醒") {
                Picker("提醒时间", selection: $event.reminder) {
                    ForEach(EventReminder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if event.reminder == .custom {
                    Stepper(value: $event.reminderDaysBefore, in: 0...365) { Text(L10n.format("提前 %ld 天", event.reminderDaysBefore)) }
                        .accessibilityLabel("提醒提前天数")
                    DatePicker("自定提醒时间", selection: reminderTimeBinding, displayedComponents: .hourAndMinute).datePickerStyle(.field)
                }
            }
            Section("每日进度") { recurringControl("每日提醒", timeLabel: "每日提醒时间", keyPath: \.dailyReminderTime) }
            Section("纪念提醒") {
                recurringControl("每满一个月", timeLabel: "满月提醒时间", keyPath: \.monthlyReminderTime)
                recurringControl("每满一年", timeLabel: "周年提醒时间", keyPath: \.yearlyReminderTime)
                if event.monthlyReminderTime != nil || event.yearlyReminderTime != nil {
                    Text("满月和周年按原始日期计算；短月按月末，闰年恢复原日期。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                if event.hasEnabledReminders {
                    LabeledContent("通知权限", value: reminders?.authorizationDescription ?? L10n.text("临时验证"))
                    if let next = nextReminderDate {
                        Text(L10n.format("保存后预计提醒：%@", next.formatted(date: .abbreviated, time: .shortened))).font(.caption)
                    } else { Text("提醒时间已过，不会安排通知。").font(.caption) }
                }
                if event.hasEnabledReminders {
                    Button("通知与后台设置…") { SettingsRouting.request(.notifications); openSettings() }
                }
            }
        }.formStyle(.grouped)
        .task(id: ReminderPreviewRequest(draft: preparedDraft, calendarRevision: previewRevision)) {
            // No queue generation in body; only the active reminder page evaluates its draft.
            while !Task.isCancelled {
                let now = Date()
                nextReminderDate = ReminderPolicy.nextDate(event: preparedDraft, now: now)
                let delay = min(3600, max(1, nextReminderDate?.timeIntervalSince(now) ?? 3600))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            previewRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            previewRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in previewRevision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in previewRevision += 1 }
    }
    private var displayPage: some View {
        Form {
            Section(L10n.text("到期后")) {
                Picker(L10n.text("处理方式"), selection: $event.afterDate) {
                    ForEach(EventAfterDate.allCases, id: \.self) { action in
                        Text(action.label).tag(action)
                    }
                }.disabled(event.isRepeating)
                Text(L10n.text(event.isRepeating ? "重复事件会保留，不会自动移入回收站。" : event.afterDate == .keep ? "保留原日期，继续显示已经过的天数或周年。" : "到期后移入回收站，可随时恢复；全天事件在当天结束后处理。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("计数方式") {
                Picker("计日格式", selection: $event.displayFormat) {
                    ForEach(EventDisplayFormat.allCases, id: \.self) { format in
                        Text(format.label).tag(format)
                    }
                }
                if !event.isRepeating {
                    Toggle("当天算第 1 天", isOn: $event.includesStartDay).toggleStyle(.switch)
                    Text(L10n.text(event.includesStartDay ? "当天 1 天 → 次日 2 天" : "当天 0 天 → 次日 1 天"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("图标与颜色") {
                Picker("图标", selection: $event.symbol) {
                    ForEach(EventTheme.symbols, id: \.0) { symbol, name in Label(L10n.text(name), systemImage: symbol).tag(symbol) }
                }
                LabeledContent("颜色") {
                    Menu {
                        ForEach(EventTheme.all) { theme in
                            Button { colorPanel.close(); event.colorKey = theme.id } label: {
                                Label { Text(theme.name) } icon: { Image(nsImage: theme.menuSwatch).renderingMode(.original) }.labelStyle(.titleAndIcon)
                            }
                        }
                        Divider()
                        Button("自定颜色…") {
                            colorPanel.show(color: EventTheme.color(for: event.colorKey)) { color in
                                if let key = EventTheme.key(for: color) { event.colorKey = key }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(EventTheme.color(for: event.colorKey)).frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                            Text(EventTheme.all.first(where: { $0.id == event.colorKey })?.name ?? L10n.text("自定颜色"))
                        }
                    }.fixedSize().accessibilityLabel("事件颜色")
                        .help("打开系统颜色选择器").onDisappear { colorPanel.close() }
                }
            }
        }.formStyle(.grouped)
    }
    private var preparedDraft: CountdownEvent {
        var value = event
        value.tags = CountdownEvent.parseTags(tagsText)
        value.calendarDay = value.isAllDay || value.isRepeating ? CalendarDay(date: value.targetDate) : nil
        value.annualTime = value.isRepeating ? CalendarTime(date: value.targetDate) : nil
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

/// Own the shared native panel only while this editor is displaying it.
/// A plain button also gives keyboard and VoiceOver users an explicit action.
@MainActor private final class EventColorPanel: NSObject, ObservableObject {
    private var onChange: ((Color) -> Void)?
    private var isShowing = false
    func show(color: Color, onChange: @escaping (Color) -> Void) {
        let panel = NSColorPanel.shared
        self.onChange = nil
        panel.color = NSColor(color)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.mode = .wheel
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        isShowing = true
        self.onChange = onChange
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func changed(_ sender: NSColorPanel) { onChange?(Color(nsColor: sender.color)) }
    func close() {
        guard isShowing else { return }
        let panel = NSColorPanel.shared
        panel.orderOut(nil)
        panel.setTarget(nil)
        panel.setAction(nil)
        isShowing = false
        onChange = nil
    }
}
