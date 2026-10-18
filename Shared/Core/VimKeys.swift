import Foundation

enum VimListCommand: Equatable {
    case down, up, first, last, search, visual, toggle, edit, create, trash, undo, redo, escape
}

struct VimKeySequence {
    private var prefix = ""
    private var lastTime: TimeInterval = 0
    mutating func reset() { prefix = "" }
    mutating func command(_ text: String, control: Bool = false, at time: TimeInterval) -> VimListCommand? {
        if time - lastTime > 0.8 { prefix = "" }
        lastTime = time
        let old = prefix
        prefix = ""
        if control { return text == "r" ? .redo : nil }
        switch text {
        case "j": return .down
        case "k": return .up
        case "G": return .last
        case "g": if old == "g" { return .first }; prefix = "g"; return nil
        case "d": if old == "d" { return .trash }; prefix = "d"; return nil
        case "/": return .search
        case "v", "V": return .visual
        case " ": return .toggle
        case "i": return .edit
        case "o": return .create
        case "u": return .undo
        default: return nil
        }
    }
}

struct VimListNavigation {
    var cursor: UUID?
    var anchor: UUID?
    mutating func reconcile(ids: [UUID], selected: inout Set<UUID>) {
        let visible = Set(ids)
        selected.formIntersection(visible)
        if let cursor, !visible.contains(cursor) { self.cursor = nil }
        if let anchor, !visible.contains(anchor) { self.anchor = nil }
    }
    mutating func move(_ step: Int, ids: [UUID], selected: inout Set<UUID>) {
        guard !ids.isEmpty else { cursor = nil; anchor = nil; selected = []; return }
        let current = cursor.flatMap { ids.firstIndex(of: $0) }
            ?? ids.firstIndex(where: { selected.contains($0) }) ?? (step > 0 ? -1 : ids.count)
        let next = min(max(current + step, 0), ids.count - 1)
        cursor = ids[next]
        if let anchor, let start = ids.firstIndex(of: anchor) {
            selected = Set(ids[min(start, next)...max(start, next)])
        } else { selected = [ids[next]] }
    }
}
