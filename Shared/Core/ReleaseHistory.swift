import Foundation

struct ReleaseText: Decodable {
    let en: String
    let zhHans: String
    enum CodingKeys: String, CodingKey { case en; case zhHans = "zh-Hans" }
    func text(language: AppLanguage) -> String { language == .english ? en : zhHans }
}
struct ReleaseEntry: Decodable, Identifiable {
    struct Section: Decodable {
        enum Kind: String, Decodable { case added, improved, fixed }
        let kind: Kind
        let items: [ReleaseText]
        var title: String {
            let key = switch kind { case .added: "新增"; case .improved: "改进"; case .fixed: "修复" }
            return L10n.text(key)
        }
    }
    let version: String
    let build: Int
    let date: String
    let sections: [Section]
    var id: String { version }
}
enum ReleaseHistory {
    private struct Document: Decodable { let releases: [ReleaseEntry] }
    static func load(bundle: Bundle = L10n.bundle) throws -> [ReleaseEntry] {
        guard let url = bundle.url(forResource: "release-history", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)).releases
    }
    static let entries = (try? load()) ?? []
}
