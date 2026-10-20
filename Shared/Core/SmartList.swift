import Foundation
import CryptoKit

enum ListKind: String, Codable, Sendable { case smart, ordinary, folder }

enum SmartMatchMode: String, Codable, CaseIterable, Sendable { case all, any }
enum SmartComparison: String, Codable, CaseIterable, Sendable { case contains, notContains, equals, notEquals, atMost, atLeast, before, after, between }
enum SmartDateState: String, Codable, CaseIterable, Sendable { case future, today, past }
enum SmartRuleField: String, Codable, CaseIterable, Sendable {
    case title, tag, dateState, dayDistance, targetDate, pinned, yearly
    var allowedComparisons: [SmartComparison] {
        switch self {
        case .title, .tag: return [.contains, .notContains, .equals, .notEquals]
        case .dateState, .pinned, .yearly: return [.equals, .notEquals]
        case .dayDistance: return [.equals, .notEquals, .atMost, .atLeast]
        case .targetDate: return [.equals, .notEquals, .before, .after, .between]
        }
    }
}
enum SmartListError: LocalizedError {
    case invalidRule, invalidList
    var errorDescription: String? { L10n.text("列表设置无效，请检查名称、位置和条件。") }
}
struct SmartRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var field: SmartRuleField = .tag
    var comparison: SmartComparison = .contains
    var text: String = ""
    var number: Int = 0
    var date: CalendarDay = CalendarDay(date: Date())
    var endDate: CalendarDay = CalendarDay(date: Date())
    var flag: Bool = true
    var dateState: SmartDateState = .future
    func validated() throws -> Self {
        var value = self; value.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard field.allowedComparisons.contains(comparison), (0...999999).contains(number), text.count <= 500,
              date.date(timeZone: TimeZone(secondsFromGMT: 0)!) != nil,
              endDate.date(timeZone: TimeZone(secondsFromGMT: 0)!) != nil else { throw SmartListError.invalidRule }
        if field == .title || field == .tag { guard !value.text.isEmpty else { throw SmartListError.invalidRule } }
        if field == .targetDate && comparison == .between && Self.dayKey(date) > Self.dayKey(endDate) { throw SmartListError.invalidRule }
        return value
    }
    fileprivate static func dayKey(_ day: CalendarDay) -> Int { day.year * 10000 + day.month * 100 + day.day }
}
struct SmartListResult: Sendable { let matching: [CountdownEvent]; let events: [CountdownEvent] }
struct SmartList: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String = ""
    var match: SmartMatchMode = .all
    var rules: [SmartRule] = []
    var sort: WidgetSort = .nearest
    var prioritizePinned: Bool = false
    var skip: Int = 0
    var kind: ListKind = .smart
    var parentID: UUID?
    var eventIDs: [UUID] = []
    var symbol: String { kind == .folder ? "folder" : kind == .ordinary ? "list.bullet" : "line.3.horizontal.decrease.circle" }
    var typeLabel: String { L10n.text(kind == .folder ? "文件夹" : kind == .ordinary ? "普通列表" : "智能列表") }
    func validated() throws -> Self {
        guard eventIDs.count <= 10000, Set(eventIDs).count == eventIDs.count,
              kind == .ordinary || eventIDs.isEmpty,
              kind == .smart || rules.isEmpty,
              parentID != id else { throw SmartListError.invalidList }
        var value = self; value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty, value.name.count <= 100, rules.count <= 100, (0...999999).contains(skip) else { throw SmartListError.invalidList }
        guard Set(rules.map(\.id)).count == rules.count else { throw EventError.duplicateID }
        value.rules = try rules.map { try $0.validated() }; return value
    }
    func evaluate(events: [CountdownEvent], now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> SmartListResult {
        guard rules.count <= 100, let valid = try? rules.map({ try $0.validated() }) else { return SmartListResult(matching: [], events: []) }
        let calendar = CalendarDay.calendar(timeZone)
        let today = calendar.startOfDay(for: now)
        let members = Set(eventIDs)
        let active = events.filter { $0.isVisible(at: now, timeZone: timeZone) && (kind == .smart || (kind == .ordinary && members.contains($0.id))) }
        let dates = Dictionary(active.map { ($0.id, $0.countdownDate(now: now, timeZone: timeZone)) }, uniquingKeysWith: { first, _ in first })
        let matching = active.filter { event in
            guard event.isVisible(at: now, timeZone: timeZone) else { return false }
            let target = calendar.startOfDay(for: dates[event.id]!)
            let distance = calendar.dateComponents([.day], from: today, to: target).day ?? 0
            let state: SmartDateState = distance == 0 ? .today : distance > 0 ? .future : .past
            let tags = event.tags.map(CountdownEvent.tagIdentity)
            let title = CountdownEvent.tagIdentity(event.title)
            let key = SmartRule.dayKey(CalendarDay(date: target, timeZone: timeZone))
            func matches(_ rule: SmartRule) -> Bool {
                let text = CountdownEvent.tagIdentity(rule.text)
                switch rule.field {
                case .title, .tag:
                    let values = rule.field == .title ? [title] : tags
                    let found = values.contains { (rule.comparison == .contains || rule.comparison == .notContains) ? $0.contains(text) : $0 == text }
                    return rule.comparison == .notContains || rule.comparison == .notEquals ? !found : found
                case .dateState: return rule.comparison == .equals ? state == rule.dateState : state != rule.dateState
                case .pinned, .yearly:
                    let flag = rule.field == .pinned ? event.isPinned : event.repeatYearly
                    return rule.comparison == .equals ? flag == rule.flag : flag != rule.flag
                case .dayDistance:
                    let days = abs(distance)
                    switch rule.comparison { case .equals: return days == rule.number; case .notEquals: return days != rule.number; case .atMost: return days <= rule.number; case .atLeast: return days >= rule.number; default: return false }
                case .targetDate:
                    let start = SmartRule.dayKey(rule.date), end = SmartRule.dayKey(rule.endDate)
                    switch rule.comparison { case .equals: return key == start; case .notEquals: return key != start; case .before: return key < start; case .after: return key > start; case .between: return key >= start && key <= end; default: return false }
                }
            }
            return valid.isEmpty || (match == .all ? valid.allSatisfy(matches) : valid.contains(where: matches))
        }
        let ordered = matching.sorted { left, right in
            if prioritizePinned && left.isPinned != right.isPinned { return left.isPinned }
            let l = dates[left.id]!, r = dates[right.id]!
            switch sort {
            case .automatic:
                let lf = left.repeatYearly || l > now, rf = right.repeatYearly || r > now
                if lf != rf { return lf }; if l != r { return lf ? l < r : l > r }
            case .nearest, .farthest:
                let ld = abs(l.timeIntervalSince(now)), rd = abs(r.timeIntervalSince(now))
                if ld != rd { return sort == .nearest ? ld < rd : ld > rd }
            case .dateAscending, .dateDescending: if l != r { return sort == .dateAscending ? l < r : l > r }
            case .createdNewest: if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            case .title:
                let comparison = left.title.localizedStandardCompare(right.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return left.id.uuidString < right.id.uuidString
        }
        return SmartListResult(matching: matching, events: Array(ordered.dropFirst(max(0, skip))))
    }
    /// Absolute-distance ordering can change between target times, at pair midpoints.
    func nextUpdate(events: [CountdownEvent], after now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        var next = EventRefreshPolicy.nextUpdate(events: events, after: now, includeClock: false, timeZone: timeZone)
        guard sort == .nearest || sort == .farthest else { return next }
        let dates = evaluate(events: events, now: now, timeZone: timeZone).matching.map {
            $0.countdownDate(now: now, timeZone: timeZone).timeIntervalSinceReferenceDate
        }
        let time = now.timeIntervalSinceReferenceDate
        let future = dates.filter { $0 > time }.sorted()
        // For each past target, binary-search the next future target whose midpoint has not passed.
        // This covers order changes after skipping entries without enumerating every pair.
        for past in dates where past <= time {
            let threshold = 2 * time - past
            var low = 0, high = future.count
            while low < high {
                let middle = (low + high) / 2
                if future[middle] >= threshold { high = middle } else { low = middle + 1 }
            }
            if low < future.count {
                let crossing = Date(timeIntervalSinceReferenceDate: past + (future[low] - past) / 2 + 0.001)
                next = min(next, crossing)
            }
        }
        return next
    }
    func signature(pageSize: Int) -> String {
        // Encode only fields which affect evaluation; editorial identities are excluded.
        let conditions: [[String: String]] = rules.map { rule in
            var value = ["field": rule.field.rawValue, "comparison": rule.comparison.rawValue]
            switch rule.field {
            case .title, .tag: value["text"] = CountdownEvent.tagIdentity(rule.text)
            case .dateState: value["state"] = rule.dateState.rawValue
            case .dayDistance: value["number"] = String(rule.number)
            case .pinned, .yearly: value["flag"] = String(rule.flag)
            case .targetDate:
                value["date"] = String(SmartRule.dayKey(rule.date))
                if rule.comparison == .between { value["end"] = String(SmartRule.dayKey(rule.endDate)) }
            }
            return value
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = conditions.map { String(decoding: try! encoder.encode($0), as: UTF8.self) }.sorted()
        let membership = kind == .smart ? "" : ":\(kind.rawValue):" + eventIDs.map(\.uuidString).sorted().joined(separator: ",")
        return membership + String(decoding: try! encoder.encode(encoded), as: UTF8.self) + ":\(match.rawValue):\(sort.rawValue):\(prioritizePinned):\(skip):\(pageSize)"
    }
    func pageIdentifier(pageSize: Int) -> String {
        let hex = SHA256.hash(data: Data(signature(pageSize: pageSize).utf8)).prefix(16).map { String(format: "%02X", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.suffix(12))"
    }
}


extension SmartList {
    private enum CodingKeys: String, CodingKey { case id, name, match, rules, sort, prioritizePinned, skip, kind, parentID, eventIDs }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        match = try values.decode(SmartMatchMode.self, forKey: .match)
        rules = try values.decode([SmartRule].self, forKey: .rules)
        sort = try values.decode(WidgetSort.self, forKey: .sort)
        prioritizePinned = try values.decode(Bool.self, forKey: .prioritizePinned)
        skip = try values.decode(Int.self, forKey: .skip)
        kind = try values.decodeIfPresent(ListKind.self, forKey: .kind) ?? .smart
        parentID = try values.decodeIfPresent(UUID.self, forKey: .parentID)
        eventIDs = try values.decodeIfPresent([UUID].self, forKey: .eventIDs) ?? []
    }
}

/// All mutations are applied to one classification snapshot under the existing CAS lock.
enum ListHierarchy {
    static func validated(_ lists: [SmartList]) throws -> [SmartList] {
        guard lists.count <= 100, Set(lists.map(\.id)).count == lists.count else { throw SmartListError.invalidList }
        let values = try lists.map { try $0.validated() }
        let byID = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        var members = Set<UUID>()
        for list in values {
            for id in list.eventIDs { guard members.insert(id).inserted else { throw SmartListError.invalidList } }
            var visited: Set<UUID> = [list.id]
            var parent = list.parentID
            while let id = parent {
                guard visited.insert(id).inserted, let folder = byID[id], folder.kind == .folder else { throw SmartListError.invalidList }
                parent = folder.parentID
            }
        }
        return values
    }
    static func path(for list: SmartList, in lists: [SmartList]) -> String {
        var parts = [list.name], parent = list.parentID, seen: Set<UUID> = [list.id]
        while let id = parent, seen.insert(id).inserted, let folder = lists.first(where: { $0.id == id }) {
            parts.insert(folder.name, at: 0); parent = folder.parentID
        }
        return parts.joined(separator: " / ")
    }
    static func descendants(of id: UUID, in lists: [SmartList]) -> Set<UUID> {
        var found: Set<UUID> = [id]
        var previous = 0
        while found.count != previous {
            previous = found.count
            for list in lists where list.parentID.map(found.contains) == true { found.insert(list.id) }
        }
        return found
    }
    static func removing(_ id: UUID, from lists: [SmartList]) -> [SmartList] {
        let parent = lists.first(where: { $0.id == id })?.parentID
        return lists.filter { $0.id != id }.map { list in
            var value = list
            if value.parentID == id { value.parentID = parent }
            return value
        }
    }
    static func assigning(_ ids: Set<UUID>, to target: UUID?, in lists: [SmartList]) throws -> [SmartList] {
        if let target { guard lists.contains(where: { $0.id == target && $0.kind == .ordinary }) else { throw SmartListError.invalidList } }
        let updated = lists.map { list in
            var value = list
            if list.kind == .ordinary {
                value.eventIDs.removeAll { ids.contains($0) }
                if list.id == target { value.eventIDs += ids.sorted { $0.uuidString < $1.uuidString } }
            }
            return value
        }
        return try validated(updated)
    }
    static func events(in id: UUID, lists: [SmartList], events: [CountdownEvent], now: Date) -> [CountdownEvent] {
        guard let list = lists.first(where: { $0.id == id }) else { return [] }
        if list.kind != .folder { return list.evaluate(events: events, now: now).events }
        let descendants = descendants(of: id, in: lists)
        let members = Set(lists.filter { descendants.contains($0.id) && $0.kind != .folder }
            .flatMap { $0.evaluate(events: events, now: now).events.map(\.id) })
        return WidgetPolicy.sorted(events: events.filter { members.contains($0.id) }, now: now)
    }
}
