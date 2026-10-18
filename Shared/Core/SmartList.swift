import Foundation
import CryptoKit

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
    var errorDescription: String? { L10n.text("智能列表条件无效，请检查名称、条件和范围。") }
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
    func validated() throws -> Self {
        var value = self; value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty, value.name.count <= 100, rules.count <= 100, (0...999999).contains(skip) else { throw SmartListError.invalidList }
        guard Set(rules.map(\.id)).count == rules.count else { throw EventError.duplicateID }
        value.rules = try rules.map { try $0.validated() }; return value
    }
    func evaluate(events: [CountdownEvent], now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> SmartListResult {
        guard rules.count <= 100, let valid = try? rules.map({ try $0.validated() }) else { return SmartListResult(matching: [], events: []) }
        let calendar = CalendarDay.calendar(timeZone)
        let today = calendar.startOfDay(for: now)
        let active = events.filter(\.isActive)
        let dates = Dictionary(active.map { ($0.id, $0.countdownDate(now: now, timeZone: timeZone)) }, uniquingKeysWith: { first, _ in first })
        let matching = active.filter { event in
            guard event.isActive else { return false }
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
        return String(decoding: try! encoder.encode(encoded), as: UTF8.self) + ":\(match.rawValue):\(sort.rawValue):\(prioritizePinned):\(skip):\(pageSize)"
    }
    func pageIdentifier(pageSize: Int) -> String {
        let hex = SHA256.hash(data: Data(signature(pageSize: pageSize).utf8)).prefix(16).map { String(format: "%02X", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.suffix(12))"
    }
}
