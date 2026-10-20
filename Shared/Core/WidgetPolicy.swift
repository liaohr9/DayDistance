import Foundation
import CryptoKit

enum WidgetSelection: Equatable { case event(CountdownEvent), empty, missing }
enum EventSortOrder: String, CaseIterable, Identifiable {
    case date, created
    var id: Self { self }
    var label: String { L10n.text(self == .date ? "按日期" : "按创建时间") }
}
enum WidgetPolicy {
    static func sorted(events: [CountdownEvent], now: Date, order: EventSortOrder = .date, includingInactive: Bool = false, prioritizePinned: Bool = true) -> [CountdownEvent] {
        // Resolve calendar occurrences once per event, rather than four times per comparison.
        let candidates = events.filter { includingInactive || $0.isVisible(at: now) }
        if order == .created {
            return candidates.sorted { left, right in
                if prioritizePinned && left.isPinned != right.isPinned { return left.isPinned }
                if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
                return left.id.uuidString < right.id.uuidString
            }
        }
        return candidates.map { event in
            let date = event.countdownDate(now: now)
            return (event: event, date: date, future: event.repeatYearly || date > now)
        }.sorted { left, right in
            if prioritizePinned && left.event.isPinned != right.event.isPinned { return left.event.isPinned }
            if left.future != right.future { return left.future }
            if left.date == right.date { return left.event.id.uuidString < right.event.id.uuidString }
            return left.future ? left.date < right.date : left.date > right.date
        }.map(\.event)
    }

    static func selection(events: [CountdownEvent], explicitID: String?, now: Date) -> WidgetSelection {
        if let explicitID {
            guard let event = events.first(where: { $0.isVisible(at: now) && $0.id.uuidString == explicitID }) else { return .missing }
            return .event(event)
        }
        return sorted(events: events, now: now).first.map(WidgetSelection.event) ?? .empty
    }
    /// A timed event due today uses a single HH:mm summary in widgets. All-day
    /// dates and elapsed events keep their calendar-day presentation.
    static func todayRemainingClock(event: CountdownEvent, now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        let value = DayCounter.snapshot(event: event, now: now, timeZone: timeZone)
        guard value.isSameDay, value.isFuture, value.supportsClock else { return nil }
        return String(format: "%02d:%02d", value.seconds / 3600, value.seconds % 3600 / 60)
    }

    static func timelineDates(events: [CountdownEvent], now: Date, timeZone: TimeZone, includeTodayClock: Bool = false, clockEventIDs: Set<UUID>? = nil) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let horizon = now.addingTimeInterval(48*3600)
        var dates: Set<Date> = [now, horizon]
        for event in events where event.isActive {
            let target = event.countdownDate(now: now, timeZone: timeZone)
            let boundaries = event.isAllDay ? [target] : [target, target.addingTimeInterval(-86400 + 1), target.addingTimeInterval(86400)]
            let expiration = event.automaticTrashDate(timeZone: timeZone).map { [$0] } ?? []
            for boundary in boundaries + expiration where boundary > now && boundary <= horizon { dates.insert(boundary) }
        }
        if includeTodayClock {
            // WidgetKit archives static HH:mm text, so supply minute entries rather
            // than a process timer or per-second reload. The 64-entry cap below
            // also applies to these dates; the final entry requests another timeline.
            for event in events where event.isActive && !event.isAllDay && (clockEventIDs?.contains(event.id) ?? true) {
                let target = event.countdownDate(now: now, timeZone: timeZone)
                let start = max(now, calendar.startOfDay(for: target))
                guard target > start, start < horizon else { continue }
                // HH:mm truncates seconds. Enter just after each remaining-minute
                // boundary, including dates with nonzero seconds, to avoid a full
                // extra minute showing the previous value at an exact boundary.
                let wholeMinutes = floor(target.timeIntervalSince(start) / 60)
                var tick = target.addingTimeInterval(-wholeMinutes * 60 + 0.01)
                for _ in 0..<63 {
                    guard tick < target, tick <= horizon else { break }
                    dates.insert(tick)
                    tick = tick.addingTimeInterval(60)
                }
            }
        }
        var midnight = calendar.startOfDay(for: now)
        while let next = calendar.date(byAdding: .day, value: 1, to: midnight), next <= horizon {
            dates.insert(next); midnight = next
        }
        // Reload at the final entry, even if the budget truncates the 48-hour horizon.
        return Array(dates.sorted().prefix(64))
    }
}

enum WidgetDateScope: String, Codable, CaseIterable, Sendable { case all, upcoming, past }
enum WidgetTagMatch: String, Codable, CaseIterable, Sendable { case all, any }
enum WidgetSort: String, Codable, CaseIterable, Sendable {
    case automatic, nearest, farthest, dateAscending, dateDescending, createdNewest, title
}

/// Conditions are ANDed, then sorted, then skipped. Pagination never changes event data.
struct WidgetFilter: Codable, Equatable, Sendable {
    var scope = WidgetDateScope.all
    var includedTags: [String] = []
    var tagMatch = WidgetTagMatch.all
    var excludedTags: [String] = []
    var sort = WidgetSort.automatic
    var prioritizePinned = true
    var skip = 0

    func apply(events: [CountdownEvent], now: Date) -> [CountdownEvent] {
        let include = Set(CountdownEvent.normalizedTags(includedTags).map(CountdownEvent.tagIdentity))
        let exclude = Set(CountdownEvent.normalizedTags(excludedTags).map(CountdownEvent.tagIdentity))
        let matching = events.filter { event in
            guard event.isVisible(at: now) else { return false }
            if scope == .upcoming && !event.isUpcoming(at: now) { return false }
            if scope == .past && event.isUpcoming(at: now) { return false }
            let tags = Set(event.tags.map(CountdownEvent.tagIdentity))
            guard exclude.isDisjoint(with: tags) else { return false }
            return include.isEmpty || (tagMatch == .all ? include.isSubset(of: tags) : !include.isDisjoint(with: tags))
        }
        let ordered: [CountdownEvent]
        if sort == .automatic {
            ordered = WidgetPolicy.sorted(events: matching, now: now, prioritizePinned: prioritizePinned)
        } else {
            ordered = matching.sorted { left, right in
                if prioritizePinned && left.isPinned != right.isPinned { return left.isPinned }
                let ld = left.countdownDate(now: now), rd = right.countdownDate(now: now)
                switch sort {
                case .nearest, .farthest:
                    let l = abs(ld.timeIntervalSince(now)), r = abs(rd.timeIntervalSince(now))
                    if l != r { return sort == .nearest ? l < r : l > r }
                case .dateAscending, .dateDescending:
                    if ld != rd { return sort == .dateAscending ? ld < rd : ld > rd }
                case .createdNewest:
                    if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
                case .title:
                    let result = left.title.localizedStandardCompare(right.title)
                    if result != .orderedSame { return result == .orderedAscending }
                case .automatic: break
                }
                return left.id.uuidString < right.id.uuidString
            }
        }
        return Array(ordered.dropFirst(min(max(skip, 0), ordered.count)))
    }
    /// Derive page identity from persisted settings, not a hidden random intent parameter.
    /// Identical rules and page sizes share a position; different rules stay independent.
    func pageIdentifier(pageSize: Int) -> String {
        let digest = SHA256.hash(data: Data(signature(pageSize: pageSize).utf8))
        let hex = digest.prefix(16).map { String(format: "%02X", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.suffix(12))"
    }
    func signature(pageSize: Int) -> String {
        // Include every condition and page size so changing a widget returns to page one.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8)! + ":\(pageSize)"
    }
}

struct WidgetPage {
    let events: [CountdownEvent]
    let index: Int
    let count: Int
    init(events: [CountdownEvent], page: Int, pageSize: Int) {
        let size = min(max(pageSize, 5), 10)
        count = max(1, (events.count + size - 1) / size)
        index = min(max(page, 0), count - 1)
        self.events = Array(events.dropFirst(index * size).prefix(size))
    }
}

/// Only per-widget presentation state is written here, never the event JSON or locks.
struct WidgetPageStore {
    let directory: URL
    private struct State: Codable { let page: Int; let signature: String }
    private func file(id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id) else { throw CocoaError(.fileWriteInvalidFileName) }
        return directory.appendingPathComponent(uuid.uuidString + ".json")
    }
    func load(id: String, signature: String) -> Int {
        guard let url = try? file(id: id), let data = try? Data(contentsOf: url), data.count < 65536,
              let value = try? JSONDecoder().decode(State.self, from: data), value.signature == signature else { return 0 }
        return max(0, min(value.page, 1_000_000))
    }
    func save(page: Int, id: String, signature: String) throws {
        let url = try file(id: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try directory.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
        try JSONEncoder().encode(State(page: max(0, min(page, 1_000_000)), signature: signature)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
