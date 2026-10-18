import SwiftUI
import AppKit

struct EventTheme: Identifiable {
    let id: String
    private let title: String
    var name: String { L10n.text(title) }
    let color: Color
    var menuSwatch: NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { bounds in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
    static let all: [EventTheme] = [
        .init(id: "sage", title: "松绿", color: Color(red: 0.28, green: 0.48, blue: 0.40)),
        .init(id: "blue", title: "海蓝", color: Color(red: 0.28, green: 0.47, blue: 0.69)),
        .init(id: "rose", title: "蔷薇", color: Color(red: 0.68, green: 0.37, blue: 0.45)),
        .init(id: "amber", title: "暖金", color: Color(red: 0.67, green: 0.47, blue: 0.23)),
        .init(id: "violet", title: "雾紫", color: Color(red: 0.51, green: 0.42, blue: 0.65))
    ]
    static func color(for key: String) -> Color {
        if let preset = all.first(where: { $0.id == key }) { return preset.color }
        if key.utf8.count == 7, key.first == "#",
           key.dropFirst().utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
           let rgb = UInt32(key.dropFirst(), radix: 16) {
            return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
        }
        return all[0].color
    }
    static func key(for color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard components.allSatisfy({ $0.isFinite }) else { return nil }
        let bytes = components.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
    static let symbols: [(String, String)] = [
        ("calendar", "日历"), ("airplane", "旅行"), ("gift", "生日"),
        ("heart", "纪念"), ("graduationcap", "学业"), ("flag", "目标"),
        ("sun.max", "生活"), ("briefcase", "工作")
    ]
}
