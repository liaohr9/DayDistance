import SwiftUI

struct EventTheme: Identifiable {
    let id: String
    private let title: String
    var name: String { L10n.text(title) }
    let color: Color
    static let all: [EventTheme] = [
        .init(id: "sage", title: "松绿", color: Color(red: 0.28, green: 0.48, blue: 0.40)),
        .init(id: "blue", title: "海蓝", color: Color(red: 0.28, green: 0.47, blue: 0.69)),
        .init(id: "rose", title: "蔷薇", color: Color(red: 0.68, green: 0.37, blue: 0.45)),
        .init(id: "amber", title: "暖金", color: Color(red: 0.67, green: 0.47, blue: 0.23)),
        .init(id: "violet", title: "雾紫", color: Color(red: 0.51, green: 0.42, blue: 0.65))
    ]
    static func color(for key: String) -> Color { all.first(where: { $0.id == key })?.color ?? all[0].color }
    static let symbols: [(String, String)] = [
        ("calendar", "日历"), ("airplane", "旅行"), ("gift", "生日"),
        ("heart", "纪念"), ("graduationcap", "学业"), ("flag", "目标"),
        ("sun.max", "生活"), ("briefcase", "工作")
    ]
}
