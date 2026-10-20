import SwiftUI

struct SmartListEditor: View {
    @Bindable var store: SmartListStore
    let events: [CountdownEvent]
    @State private var reference = Date()
    @State private var draft: SmartList
    init(store: SmartListStore, events: [CountdownEvent]) {
        self.store = store
        self.events = events
        _draft = State(initialValue: store.draft ?? SmartList())
    }
    private var isSmart: Bool { draft.kind == .smart }
    private var availableFolders: [SmartList] {
        let excluded = ListHierarchy.descendants(of: draft.id, in: store.lists)
        return store.lists.filter { $0.kind == .folder && !excluded.contains($0.id) }
    }
    private var value: Binding<SmartList> { $draft }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.typeLabel).font(.title2.weight(.semibold))
            LabeledContent(L10n.text("名称")) {
                TextField(L10n.text("名称"), text: value.name).textFieldStyle(.roundedBorder)
            }
            Picker(L10n.text("所在文件夹"), selection: value.parentID) {
                Text(L10n.text("最外层")).tag(nil as UUID?)
                ForEach(availableFolders) { folder in
                    Text(ListHierarchy.path(for: folder, in: store.lists)).tag(Optional(folder.id))
                }
            }
            if !isSmart {
                Text(L10n.text(draft.kind == .folder ? "文件夹用于整理列表，也可以包含子文件夹。" : "手动分类事件；每个事件只属于一个普通列表。"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if isSmart {
            HStack {
                Text(L10n.text("满足以下"))
                Picker(L10n.text("匹配方式"), selection: value.match) {
                    Text(L10n.text("全部条件")).tag(SmartMatchMode.all)
                    Text(L10n.text("任一条件")).tag(SmartMatchMode.any)
                }.labelsHidden().frame(width: 140)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(value.rules) { rule in
                        VStack(alignment: .leading, spacing: 3) {
                            SmartRuleRow(rule: rule, tags: Array(Set(events.flatMap(\.tags))).sorted()) {
                                draft.rules.removeAll { $0.id == rule.wrappedValue.id }
                            }
                            if (try? rule.wrappedValue.validated()) == nil {
                                Text(L10n.text("请填写有效条件或检查日期范围。")).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    Button { draft.rules.append(SmartRule()) } label: { Label(L10n.text("添加条件"), systemImage: "plus") }.disabled(draft.rules.count >= 100)
                    if draft.rules.isEmpty { Text(L10n.text("没有条件时匹配全部有效事件。")).foregroundStyle(.secondary) }
                    DisclosureGroup(L10n.text("排序与跳过")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.text("排序"))
                                Picker(L10n.text("排序"), selection: value.sort) { ForEach(WidgetSort.allCases, id: \.self) { Text(SmartListLabels.sort($0)).tag($0) } }.labelsHidden().frame(width: 180)
                            }
                            Toggle(L10n.text("置顶优先"), isOn: value.prioritizePinned)
                            HStack { Text(L10n.text("跳过前几个事件")); TextField("0", value: value.skip, format: .number).frame(width: 90) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                }.padding(2)
            }.frame(minHeight: 180, maxHeight: 340)
            Group {
                TimelineView(EventTimelineSchedule(events: events, includeClock: false, referenceDate: reference)) { context in
                    let result = draft.evaluate(events: events, now: context.date)
                    Text(L10n.format("匹配 %ld 个，显示 %ld 个事件", result.matching.count, result.events.count)).foregroundStyle(.secondary)
                }
            }
            }
            if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("取消")) { store.cancel() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("保存")) {
                    guard store.draft != nil else { return }
                    store.draft = draft
                    _ = store.saveDraft()
                }.keyboardShortcut(.defaultAction)
                    .disabled((try? draft.validated()) == nil)
            }
        }.padding(24).frame(width: isSmart ? 680 : 440)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange), NotificationCenter.default.publisher(for: .NSSystemClockDidChange))) { _ in reference = Date() }
    }
}

private struct SmartRuleRow: View {
    @Binding var rule: SmartRule
    let tags: [String]
    let remove: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Picker(L10n.text("字段"), selection: $rule.field) {
                ForEach(SmartRuleField.allCases, id: \.self) { Text(SmartListLabels.field($0)).tag($0) }
            }.labelsHidden().frame(width: 110)
            Picker(L10n.text("运算符"), selection: $rule.comparison) {
                ForEach(rule.field.allowedComparisons, id: \.self) { Text(SmartListLabels.comparison($0)).tag($0) }
            }.labelsHidden().frame(width: 112)
            Group {
                switch rule.field {
                case .title, .tag:
                    HStack(spacing: 2) {
                        TextField(L10n.text("文字"), text: $rule.text).textFieldStyle(.roundedBorder)
                        if rule.field == .tag, !tags.isEmpty {
                            Menu { ForEach(tags, id: \.self) { tag in Button(tag) { rule.text = tag } } } label: { Image(systemName: "tag") }.menuStyle(.borderlessButton).frame(width: 25)
                        }
                    }
                case .dayDistance: TextField(L10n.text("天数"), value: $rule.number, format: .number).textFieldStyle(.roundedBorder)
                case .dateState:
                    Picker(L10n.text("日期状态"), selection: $rule.dateState) {
                        Text(L10n.text("未来")).tag(SmartDateState.future)
                        Text(L10n.text("今天")).tag(SmartDateState.today)
                        Text(L10n.text("过去")).tag(SmartDateState.past)
                    }.labelsHidden()
                case .pinned, .yearly:
                    Picker(L10n.text("是否"), selection: $rule.flag) { Text(L10n.text("是")).tag(true); Text(L10n.text("否")).tag(false) }.labelsHidden()
                case .targetDate:
                    DatePicker("", selection: dayBinding(end: false), displayedComponents: .date).labelsHidden()
                    if rule.comparison == .between { DatePicker("", selection: dayBinding(end: true), displayedComponents: .date).labelsHidden() }
                }
            }.frame(maxWidth: .infinity)
            Button(action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel(L10n.text("移除条件"))
        }
        .onChange(of: rule.field) { if !rule.field.allowedComparisons.contains(rule.comparison) { rule.comparison = rule.field.allowedComparisons[0] } }
    }
    private func dayBinding(end: Bool) -> Binding<Date> {
        Binding(get: { (end ? rule.endDate : rule.date).date(timeZone: .autoupdatingCurrent) ?? Date() }, set: {
            if end { rule.endDate = CalendarDay(date: $0) } else { rule.date = CalendarDay(date: $0) }
        })
    }
}

enum SmartListLabels {
    static func field(_ value: SmartRuleField) -> String {
        L10n.text([.title: "标题", .tag: "标签", .dateState: "日期状态", .dayDistance: "相距天数", .targetDate: "目标日期", .pinned: "置顶", .yearly: "每年重复"][value]!)
    }
    static func comparison(_ value: SmartComparison) -> String {
        L10n.text([.contains: "包含", .notContains: "不包含", .equals: "等于", .notEquals: "不等于", .atMost: "不大于", .atLeast: "不小于", .before: "早于", .after: "晚于", .between: "介于"][value]!)
    }
    static func sort(_ value: WidgetSort) -> String {
        L10n.text([.automatic: "自动排序", .nearest: "最近优先", .farthest: "最远优先", .dateAscending: "日期升序", .dateDescending: "日期降序", .createdNewest: "最近创建", .title: "标题排序"][value]!)
    }
}
